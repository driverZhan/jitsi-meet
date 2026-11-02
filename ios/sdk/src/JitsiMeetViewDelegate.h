/*
 * Copyright @ 2017-present 8x8, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

@protocol JitsiMeetViewDelegate <NSObject>

@optional

/**
 * Called when a conference was joined.
 *
 * The `data` dictionary contains a `url` key with the conference URL.
 */
- (void)conferenceJoined:(NSDictionary *)data;

/**
 * Called when the active conference ends, be it because of user choice or
 * because of a failure.
 *
 * The `data` dictionary contains an `error` key with the error and a `url` key
 * with the conference URL. If the conference finished gracefully no `error`
 * key will be present. The possible values for "error" are described here:
 * https://github.com/jitsi/lib-jitsi-meet/blob/master/JitsiConnectionErrors.js
 * https://github.com/jitsi/lib-jitsi-meet/blob/master/JitsiConferenceErrors.js
 */
- (void)conferenceTerminated:(NSDictionary *)data;

/**
 * Called before a conference is joined.
 *
 * The `data` dictionary contains a `url` key with the conference URL.
 */
- (void)conferenceWillJoin:(NSDictionary *)data;

/**
 * Called when entering Picture-in-Picture is requested by the user. The app
 * should now activate its Picture-in-Picture implementation (and resize the
 * associated `JitsiMeetView`. The latter will automatically detect its new size
 * and adjust its user interface to a variant appropriate for the small size
 * ordinarily associated with Picture-in-Picture.)
 *
 * The `data` dictionary is empty.
 */
- (void)enterPictureInPicture:(NSDictionary *)data;

/**
 * Called when a participant has joined the conference.
 *
 * The `data` dictionary contains a `participantId` key with the id of the participant that has joined.
 */
- (void)participantJoined:(NSDictionary *)data;

/**
 * Called when a participant has left the conference.
 *
 * The `data` dictionary contains a `participantId` key with the id of the participant that has left.
 */
- (void)participantLeft:(NSDictionary *)data;

/**
 * Called when a participant's video view is ready.
 *
 * The `data` dictionary contains:
 *   - `participantId` (NSString): the endpoint id of the participant whose
 *     view is now ready. This is always the conference-wide endpoint id, also
 *     for the local participant, so it can be used directly with
 *     findParticipantViewByEndpointId:completion:, detachParticipantView:...
 *     and setParticipantViewLayout:frame:.
 *   - `isLocal` (BOOL): YES if the view belongs to the local participant.
 *   - `reactTag` (NSNumber, optional): the React Native tag of the view.
 *
 * Since the endpoint id of the local participant is only known once the
 * conference has been joined, the event for the local participant is delivered
 * after conferenceJoined:.
 *
 * Each view is tagged with a nativeID of the form
 * "participant-<participantId>". When the custom-layout.enabled feature flag
 * is set to YES, the default meeting layout is disabled and participant video
 * views are rendered in a minimal container.
 */
- (void)participantViewReady:(NSDictionary *)data;

/**
 * Called when a participant's audio mute state changes.
 *
 * The `data` dictionary contains:
 *   - `muted` (BOOL): the new audio mute state.
 *   - `participantId` (NSString): the id of the participant whose audio mute
 *     state changed. For the local participant, this is the local
 *     participant's id.
 */
- (void)audioMutedChanged:(NSDictionary *)data;

/**
 * Called when an endpoint text message is received.
 *
 * The `data` dictionary contains a `senderId` key with the participantId of the sender and a 'message' key with the content.
 */
- (void)endpointTextMessageReceived:(NSDictionary *)data;

/**
 * Called when a participant toggled shared screen.
 *
 * The `data` dictionary contains a `participantId` key with the id of the participant  and a 'sharing' key with boolean value.
 */
- (void)screenShareToggled:(NSDictionary *)data;

/**
 * Called when a chat message is received.
 *
 * The `data` dictionary contains `message`, `senderId` and  `isPrivate` keys.
 */
- (void)chatMessageReceived:(NSDictionary *)data;

/**
 * Called when the chat dialog is displayed/hidden.
 *
 * The `data` dictionary contains a `isOpen` key.
 */
- (void)chatToggled:(NSDictionary *)data;

/**
 * Called when a participant's video mute state changes.
 *
 * The `data` dictionary contains:
 *   - `muted` (BOOL): the new video mute state.
 *   - `participantId` (NSString): the id of the participant whose video mute
 *     state changed. For the local participant, this is the local
 *     participant's id.
 */
- (void)videoMutedChanged:(NSDictionary *)data;

/**
 * Called when the SDK is ready to be closed. No meeting is happening at this point.
 */
- (void)readyToClose:(NSDictionary *)data;

/**
 * Called when the transcription chunk was received.
 *
 * The `data` dictionary contains a `messageID`, `language`, `participant` key.
 */
- (void)transcriptionChunkReceived:(NSDictionary *)data;

/**
 * Called when the custom overflow menu button is pressed.
 *
 * The `data` dictionary contains a `id`, `text` key.
 */
- (void)customButtonPressed:(NSDictionary *)data;

/**
 * Called when the unique identifier for conference has been set.
 *
 * The `data` dictionary contains a `sessionId` key.
 */
- (void)conferenceUniqueIdSet:(NSDictionary *)data;

/**
 * Called when the recording status has changed.
 *
 * The `data` dictionary contains a `sessionData` key.
 */
- (void)recordingStatusChanged:(NSDictionary *)data;

/**
 * Called when a participant's network/connection quality crosses into a
 * degraded state or recovers from it. Emitted for every participant (local and
 * remote) on each client, so the host app can decide how to surface a hint such
 * as "<displayName> 当前网络较差".
 *
 * The `data` dictionary contains:
 *   - `participantId` (NSString): the participant the transition is about.
 *   - `displayName` (NSString): display name of that participant.
 *   - `isLocal` (NSNumber/BOOL): whether it is the local participant.
 *   - `status` (NSString): 'degraded' or 'recovered'.
 *   - `level` (NSString): 'good' | 'nonoptimal' | 'poor' | 'critical'.
 *   - `reason` (NSString, present when degraded): 'lowUplink' | 'packetLoss' |
 *     'videoDegraded' | 'videoCut'.
 *   - `connectionQuality` (NSNumber 0-100): scalar uplink quality.
 *   - `metricsJson` (NSString): a JSON string with the nested metrics
 *     { bitrate, jvbRTT, maxEnabledResolution, packetLoss }. Parse it with
 *     NSJSONSerialization. (Same field is provided on Android so both platforms
 *     share one schema.)
 */
- (void)participantNetworkQualityChanged:(NSDictionary *)data;

@end
