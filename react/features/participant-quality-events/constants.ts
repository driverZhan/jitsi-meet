/**
 * The name of the event emitted to the native (SDK) side whenever a
 * participant's connection quality crosses into a degraded state or recovers
 * from it. Host apps listen for this via the platform-specific ExternalAPI
 * bridge (iOS: {@code participantNetworkQualityChanged:}, Android: a
 * {@code LocalBroadcastManager} receiver for
 * {@code org.jitsi.meet.PARTICIPANT_NETWORK_QUALITY_CHANGED}).
 */
export const PARTICIPANT_NETWORK_QUALITY_CHANGED = 'PARTICIPANT_NETWORK_QUALITY_CHANGED';

/**
 * Connection quality (0-100) below which a participant is considered to have a
 * poor connection. Kept consistent with the existing indicator tiers where
 * "poor" starts under 10 and "good" is at/above 30
 * (see connection-indicator/AbstractConnectionIndicator and the native
 * ConnectionStatusComponent).
 */
export const ENTER_POOR_THRESHOLD = 10;

/**
 * Connection quality (0-100) at/above which a previously degraded participant
 * is considered recovered. The gap between this and ENTER_POOR_THRESHOLD forms
 * a hysteresis band that prevents flapping around a single threshold.
 */
export const RECOVER_THRESHOLD = 30;

/**
 * A connection quality value at or below this is treated as effectively no
 * usable uplink (video is dropped / audio-only), reported as "critical".
 */
export const CRITICAL_THRESHOLD = 2;

/**
 * Upload packet-loss percentage at/above which the degrade reason is reported
 * as packet loss rather than generic low uplink bandwidth.
 */
export const PACKET_LOSS_THRESHOLD = 10;

/**
 * How long (in milliseconds) a degrade / recover condition must persist across
 * consecutive stat updates before the transition is committed. This absorbs
 * momentary dips that are common on mobile networks.
 */
export const DEBOUNCE_MS = 2500;

/**
 * Semantic quality buckets surfaced to the host app.
 */
export const QUALITY_LEVEL = {
    GOOD: 'good',
    NONOPTIMAL: 'nonoptimal',
    POOR: 'poor',
    CRITICAL: 'critical'
} as const;

/**
 * Why a participant was flagged as degraded.
 */
export const DEGRADE_REASON = {
    LOW_UPLINK: 'lowUplink',
    PACKET_LOSS: 'packetLoss',
    VIDEO_DEGRADED: 'videoDegraded',
    VIDEO_CUT: 'videoCut'
} as const;
