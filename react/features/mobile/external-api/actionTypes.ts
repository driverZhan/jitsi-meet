/**
 * The type of the action which indicates the SDK is ready to be closed.
 *
 * @returns {{
 *     type: READY_TO_CLOSE
 * }}
 */
export const READY_TO_CLOSE = 'READY_TO_CLOSE';

/**
 * The type of the action which sets the list of known participant IDs which
 * have an active screen share.
 *
 * @returns {{
    *     type: SCREEN_SHARE_PARTICIPANTS_UPDATED,
    *     participantIds: Array<string>
    * }}
    */
export const SCREEN_SHARE_PARTICIPANTS_UPDATED
    = 'SCREEN_SHARE_PARTICIPANTS_UPDATED';

/**
 * The type of the action which sets the layout (position and size) requested
 * by the native host app for a participant's video view in the custom layout.
 *
 * @returns {{
 *     type: PARTICIPANT_VIEW_LAYOUT_UPDATED,
 *     participantId: string,
 *     layout: ?Object
 * }}
 */
export const PARTICIPANT_VIEW_LAYOUT_UPDATED
    = 'PARTICIPANT_VIEW_LAYOUT_UPDATED';

/**
 * The type of the action which clears every participant view layout
 * requested by the native host app, releasing the custom layout's
 * resources so they don't accumulate across conferences (e.g. on hang up,
 * when participant ids have already changed and PARTICIPANT_LEFT can no
 * longer match the entries keyed by endpoint id).
 *
 * @returns {{
 *     type: PARTICIPANT_VIEW_LAYOUTS_CLEARED
 * }}
 */
export const PARTICIPANT_VIEW_LAYOUTS_CLEARED
    = 'PARTICIPANT_VIEW_LAYOUTS_CLEARED';

/**
 * The type of the action which sets whether participant avatars (shown when
 * the video is off) should be hidden, as requested by the native host app.
 *
 * @returns {{
 *     type: AVATAR_HIDDEN_UPDATED,
 *     hidden: boolean
 * }}
 */
export const AVATAR_HIDDEN_UPDATED = 'AVATAR_HIDDEN_UPDATED';
