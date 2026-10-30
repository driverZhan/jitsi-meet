import { NativeModules } from 'react-native';

import { IStore } from '../app/types';
import { CONFERENCE_FAILED, CONFERENCE_JOINED, CONFERENCE_LEFT } from '../base/conference/actionTypes';
import { JitsiConnectionQualityEvents } from '../base/lib-jitsi-meet';
import { getLocalParticipant, getParticipantDisplayName } from '../base/participants/functions';
import MiddlewareRegistry from '../base/redux/MiddlewareRegistry';

import {
    CRITICAL_THRESHOLD,
    DEBOUNCE_MS,
    DEGRADE_REASON,
    ENTER_POOR_THRESHOLD,
    PACKET_LOSS_THRESHOLD,
    PARTICIPANT_NETWORK_QUALITY_CHANGED,
    QUALITY_LEVEL,
    RECOVER_THRESHOLD
} from './constants';

/**
 * The subset of the connection stats this evaluator relies on. These are
 * produced by lib-jitsi-meet's ConnectionQuality module and broadcast to every
 * participant over the colibri bridge channel, so each client can judge the
 * uplink quality of all others locally.
 */
interface IQualityStats {
    bitrate?: any;
    connectionQuality?: number;
    jvbRTT?: number;
    maxEnabledResolution?: number | { height?: number; };
    packetLoss?: {
        download?: number;
        total?: number;
        upload?: number;
    };
}

/**
 * Tracks the per-participant evaluation state needed to emit only state
 * transitions (with hysteresis / debouncing).
 */
interface IParticipantState {
    degraded: boolean;
    peakResHeight?: number;
    pendingSince?: number;
}

// The conference currently being monitored and the bound stat handlers, kept so
// they can be detached when the conference is left.
let monitoredConference: any;
let localStatsHandler: ((stats: IQualityStats) => void) | undefined;
let remoteStatsHandler: ((id: string, stats: IQualityStats) => void) | undefined;

/**
 * The redux store, captured so the stat callbacks (which run outside the
 * middleware action flow) can read participant metadata.
 */
let storeRef: IStore | undefined;

// Per participant evaluation bookkeeping, reset on every join / leave.
const participants = new Map<string, IParticipantState>();

/**
 * Extracts the frame height from the (version-variable) maxEnabledResolution
 * stat, or {@code undefined} when it is not available.
 *
 * @param {IQualityStats} stats - The stats to read.
 * @private
 * @returns {number | undefined}
 */
function _getResHeight(stats: IQualityStats): number | undefined {
    const res = stats.maxEnabledResolution;

    if (typeof res === 'number') {
        return res;
    }
    if (res && typeof res === 'object' && typeof res.height === 'number') {
        return res.height;
    }

    return undefined;
}

/**
 * Sends a quality transition event to the native (SDK) side. Failures (for
 * example when no native host is attached) are ignored so stats processing is
 * never interrupted.
 *
 * @param {string} participantId - The participant the transition is about.
 * @param {string} status - Either 'degraded' or 'recovered'.
 * @param {string} level - The semantic quality bucket.
 * @param {string | undefined} reason - Why the participant degraded.
 * @param {IQualityStats} stats - The latest raw metrics.
 * @private
 * @returns {void}
 */
function _emit(
        participantId: string,
        status: string,
        level: string,
        reason: string | undefined,
        stats: IQualityStats) {
    const sendEvent = NativeModules.ExternalAPI?.sendEvent;

    if (!sendEvent || !storeRef) {
        return;
    }

    const state = storeRef.getState();
    const localParticipant = getLocalParticipant(state);

    // Nested metric objects are serialized to a single JSON string so the host
    // app receives the same structured data on Android as on iOS. The native
    // broadcast bridge (BroadcastEvent.buildIntent) otherwise flattens each
    // extra via toString(), which turns nested objects into an unparseable
    // Java "HashMap.toString()" form on Android. Hosts read `metricsJson` and
    // JSON-parse it; the scalar `connectionQuality` is also kept top-level.
    const metricsJson = JSON.stringify({
        bitrate: stats.bitrate,
        jvbRTT: stats.jvbRTT,
        maxEnabledResolution: stats.maxEnabledResolution,
        packetLoss: stats.packetLoss
    });
    const payload = {
        connectionQuality: stats.connectionQuality,
        displayName: getParticipantDisplayName(state, participantId),
        isLocal: localParticipant?.id === participantId,
        level,
        metricsJson,
        participantId,
        reason,
        status
    };

    sendEvent(PARTICIPANT_NETWORK_QUALITY_CHANGED, payload);
}

/**
 * Maps a degraded snapshot to a semantic level and reason, preferring the most
 * specific signal available.
 *
 * @param {IQualityStats} stats - The stats at the moment of degradation.
 * @param {number | undefined} peakResHeight - The peak frame height seen so far.
 * @private
 * @returns {Object}
 */
function _describeDegrade(
        stats: IQualityStats,
        peakResHeight?: number): { level: string; reason: string; } {
    const cq = stats.connectionQuality ?? 0;
    const height = _getResHeight(stats);

    if (cq <= CRITICAL_THRESHOLD) {
        // Effectively no usable video uplink: treated as video dropped to audio.
        return { level: QUALITY_LEVEL.CRITICAL, reason: DEGRADE_REASON.VIDEO_CUT };
    }

    const uploadLoss = stats.packetLoss?.upload ?? stats.packetLoss?.total;

    if (typeof uploadLoss === 'number' && uploadLoss >= PACKET_LOSS_THRESHOLD) {
        return { level: QUALITY_LEVEL.POOR, reason: DEGRADE_REASON.PACKET_LOSS };
    }

    if (typeof height === 'number' && typeof peakResHeight === 'number' && peakResHeight > 0
            && height < peakResHeight * 0.5) {
        return { level: QUALITY_LEVEL.POOR, reason: DEGRADE_REASON.VIDEO_DEGRADED };
    }

    return { level: QUALITY_LEVEL.POOR, reason: DEGRADE_REASON.LOW_UPLINK };
}

/**
 * Processes a single stats update for a participant, committing (and emitting)
 * a transition only after the degrade / recover condition has persisted for
 * {@link DEBOUNCE_MS}.
 *
 * @param {string} id - The participant id.
 * @param {IQualityStats} stats - The latest stats.
 * @private
 * @returns {void}
 */
function _handleStats(id: string, stats: IQualityStats) {
    const cq = stats.connectionQuality;

    // Nothing to judge until the first quality value arrives.
    if (typeof cq !== 'number') {
        return;
    }

    let p = participants.get(id);

    if (!p) {
        p = { degraded: false, peakResHeight: _getResHeight(stats) };
        participants.set(id, p);
    } else {
        const height = _getResHeight(stats);

        if (typeof height === 'number' && (p.peakResHeight === undefined || height > p.peakResHeight)) {
            p.peakResHeight = height;
        }
    }

    const now = Date.now();
    const isBad = cq < ENTER_POOR_THRESHOLD;
    const isGood = cq >= RECOVER_THRESHOLD;
    let transition: { level: string; reason?: string; status: string; } | undefined;

    if (p.degraded) {
        if (isGood) {
            if (p.pendingSince === undefined) {
                p.pendingSince = now;
            } else if (now - p.pendingSince >= DEBOUNCE_MS) {
                p.degraded = false;
                p.pendingSince = undefined;
                transition = { status: 'recovered', level: QUALITY_LEVEL.GOOD };
            }
        } else {
            p.pendingSince = undefined;
        }
    } else if (isBad) {
        if (p.pendingSince === undefined) {
            p.pendingSince = now;
        } else if (now - p.pendingSince >= DEBOUNCE_MS) {
            p.degraded = true;
            p.pendingSince = undefined;

            const { level, reason } = _describeDegrade(stats, p.peakResHeight);

            transition = { status: 'degraded', level, reason };
        }
    } else {
        p.pendingSince = undefined;
    }

    if (transition) {
        _emit(id, transition.status, transition.level, transition.reason, stats);
    }
}

/**
 * Detaches the stat listeners and clears evaluation state.
 *
 * @private
 * @returns {void}
 */
function _teardown() {
    if (monitoredConference) {
        if (localStatsHandler) {
            monitoredConference.off(JitsiConnectionQualityEvents.LOCAL_STATS_UPDATED, localStatsHandler);
        }
        if (remoteStatsHandler) {
            monitoredConference.off(JitsiConnectionQualityEvents.REMOTE_STATS_UPDATED, remoteStatsHandler);
        }
    }

    monitoredConference = undefined;
    localStatsHandler = undefined;
    remoteStatsHandler = undefined;
    participants.clear();
}

/**
 * Middleware of the participant-quality-events feature. Native-only: it observes
 * the conference-wide connection-quality stats that lib-jitsi-meet already
 * broadcasts, derives per-participant degrade / recover transitions, and forwards
 * them to the host app through the ExternalAPI bridge. The web client renders
 * quality through the existing ConnectionIndicator and does not need this.
 *
 * @param {Store} store - The redux store.
 * @returns {Function}
 */
MiddlewareRegistry.register((store: IStore) => next => action => {
    switch (action.type) {
    case CONFERENCE_JOINED: {
        storeRef = store;

        // Defensive: drop any previous monitoring before subscribing anew.
        _teardown();

        const conference = action.conference;

        monitoredConference = conference;

        localStatsHandler = (stats: IQualityStats) => _handleStats(conference.myUserId(), stats);
        remoteStatsHandler = (id: string, stats: IQualityStats) => _handleStats(id, stats);

        conference.on(JitsiConnectionQualityEvents.LOCAL_STATS_UPDATED, localStatsHandler);
        conference.on(JitsiConnectionQualityEvents.REMOTE_STATS_UPDATED, remoteStatsHandler);
        break;
    }

    case CONFERENCE_LEFT:
    case CONFERENCE_FAILED:
        _teardown();
        break;
    }

    return next(action);
});
