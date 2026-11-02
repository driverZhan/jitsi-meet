import { PARTICIPANT_ID_CHANGED, PARTICIPANT_LEFT } from '../../base/participants/actionTypes';
import ReducerRegistry from '../../base/redux/ReducerRegistry';

import { AVATAR_HIDDEN_UPDATED, PARTICIPANT_VIEW_LAYOUTS_CLEARED, PARTICIPANT_VIEW_LAYOUT_UPDATED, SCREEN_SHARE_PARTICIPANTS_UPDATED } from './actionTypes';

/**
 * The layout (position and size) requested by the native host app for a
 * participant's video view. All values are in density-independent pixels (dp
 * on Android, points on iOS).
 */
export interface IParticipantViewLayout {
    height: number;

    /**
     * Stable handle for the native host app. Initialized with the participant
     * id used in the first setParticipantViewLayout call and preserved when
     * the participant id changes (e.g. the local participant id changes when
     * joining a conference), so the native wrapper view is never remounted
     * and the host app's handle stays valid.
     */
    viewKey: string;
    width: number;
    x: number;
    y: number;
}

export interface IMobileExternalApiState {
    avatarHidden: boolean;
    participantViewLayouts: { [participantId: string]: IParticipantViewLayout; };
    screenShares: string[];
}

const DEFAULT_STATE = {
    avatarHidden: false,
    participantViewLayouts: {},
    screenShares: []
};

ReducerRegistry.register<IMobileExternalApiState>('features/mobile/external-api',
(state = DEFAULT_STATE, action): IMobileExternalApiState => {
    switch (action.type) {
    case SCREEN_SHARE_PARTICIPANTS_UPDATED: {
        return {
            ...state,
            screenShares: action.participantIds
        };
    }
    case PARTICIPANT_VIEW_LAYOUT_UPDATED: {
        const participantViewLayouts = { ...state.participantViewLayouts };

        // The host app may still use the participant id it originally
        // detached with (the viewKey) even after the participant id changed,
        // so match entries by current id or by viewKey.
        const existingId = participantViewLayouts[action.participantId]
            ? action.participantId
            : Object.keys(participantViewLayouts)
                .find(id => participantViewLayouts[id].viewKey === action.participantId);

        if (action.layout) {
            const id = existingId ?? action.participantId;

            participantViewLayouts[id] = {
                ...action.layout,
                viewKey: existingId ? participantViewLayouts[existingId].viewKey : action.participantId
            };
        } else if (existingId) {
            delete participantViewLayouts[existingId];
        }

        return {
            ...state,
            participantViewLayouts
        };
    }
    case PARTICIPANT_VIEW_LAYOUTS_CLEARED: {
        // Drop every requested layout at once (e.g. on hang up) so the
        // custom layout's positioned views don't survive into the next
        // conference. PARTICIPANT_LEFT can't reliably clear entries keyed by
        // endpoint id once the local participant id has changed.
        if (Object.keys(state.participantViewLayouts).length === 0) {
            return state;
        }

        return {
            ...state,
            participantViewLayouts: {}
        };
    }
    case PARTICIPANT_ID_CHANGED: {
        const { oldValue, newValue } = action;

        // The local participant id changes when joining a conference. Migrate
        // the layout entry so the positioned view (keyed by viewKey) survives
        // without being remounted.
        if (oldValue && newValue && state.participantViewLayouts[oldValue]) {
            const participantViewLayouts = { ...state.participantViewLayouts };

            participantViewLayouts[newValue] = participantViewLayouts[oldValue];
            delete participantViewLayouts[oldValue];

            return {
                ...state,
                participantViewLayouts
            };
        }

        return state;
    }
    case AVATAR_HIDDEN_UPDATED: {
        return {
            ...state,
            avatarHidden: Boolean(action.hidden)
        };
    }
    case PARTICIPANT_LEFT: {
        const id = action.participant?.id;

        if (id && state.participantViewLayouts[id]) {
            const participantViewLayouts = { ...state.participantViewLayouts };

            delete participantViewLayouts[id];

            return {
                ...state,
                participantViewLayouts
            };
        }

        return state;
    }
    }

    return state;
});
