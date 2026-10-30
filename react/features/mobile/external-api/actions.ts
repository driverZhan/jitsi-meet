import {
    AVATAR_HIDDEN_UPDATED,
    PARTICIPANT_VIEW_LAYOUTS_CLEARED,
    PARTICIPANT_VIEW_LAYOUT_UPDATED,
    READY_TO_CLOSE,
    SCREEN_SHARE_PARTICIPANTS_UPDATED
} from './actionTypes';
import { IParticipantViewLayout } from './reducer';


/**
 * Creates a (redux) action which signals that the SDK is ready to be closed.
 *
 * @returns {{
 *     type: READY_TO_CLOSE
 * }}
 */
export function readyToClose() {
    return {
        type: READY_TO_CLOSE
    };
}

/**
 * Creates a (redux) action which signals that the list of known participants
 * with screen shares has changed.
 *
 * @param {string} participantIds - The participants which currently have active
 * screen share streams.
 * @returns {{
 *     type: SCREEN_SHARE_PARTICIPANTS_UPDATED,
 *     participantId: string
 * }}
 */
export function setParticipantsWithScreenShare(participantIds: Array<string>) {
    return {
        type: SCREEN_SHARE_PARTICIPANTS_UPDATED,
        participantIds
    };
}

/**
 * Creates a (redux) action which signals that the native host app requested a
 * new layout (position and size) for a participant's video view.
 *
 * @param {string} participantId - The ID of the participant whose view layout
 * changed.
 * @param {?IParticipantViewLayout} layout - The requested layout in dp, or
 * undefined to remove a previously set layout.
 * @returns {{
 *     type: PARTICIPANT_VIEW_LAYOUT_UPDATED,
 *     participantId: string,
 *     layout: ?IParticipantViewLayout
 * }}
 */
export function setParticipantViewLayout(participantId: string, layout?: Omit<IParticipantViewLayout, 'viewKey'>) {
    return {
        type: PARTICIPANT_VIEW_LAYOUT_UPDATED,
        participantId,
        layout
    };
}

/**
 * Creates a (redux) action which clears every participant view layout
 * requested by the native host app, releasing the custom layout's
 * resources. Dispatched on hang up so positioned views don't accumulate
 * across conferences (the local participant id changes on join/leave, so
 * PARTICIPANT_LEFT can't reliably clear entries keyed by endpoint id).
 *
 * @returns {{
 *     type: PARTICIPANT_VIEW_LAYOUTS_CLEARED
 * }}
 */
export function clearParticipantViewLayouts() {
    return {
        type: PARTICIPANT_VIEW_LAYOUTS_CLEARED
    };
}

/**
 * Creates a (redux) action which signals that the native host app requested
 * participant avatars (shown when the video is off) to be hidden or shown.
 *
 * @param {boolean} hidden - True to hide avatars, false to show them.
 * @returns {{
 *     type: AVATAR_HIDDEN_UPDATED,
 *     hidden: boolean
 * }}
 */
export function setAvatarHidden(hidden: boolean) {
    return {
        type: AVATAR_HIDDEN_UPDATED,
        hidden
    };
}
