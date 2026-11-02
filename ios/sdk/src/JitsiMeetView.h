/*
 * Copyright @ 2018-present 8x8, Inc.
 * Copyright @ 2017-2018 Atlassian Pty Ltd
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "JitsiMeetConferenceOptions.h"
#import "JitsiMeetViewDelegate.h"

typedef NS_ENUM(NSInteger, RecordingMode) {
    RecordingModeFile,
    RecordingModeStream
};

@interface JitsiMeetView : UIView

@property (nonatomic, nullable, weak) id<JitsiMeetViewDelegate> delegate;

/**
 * Joins the conference specified by the given options. The given options will
 * be merged with the defaultConferenceOptions (if set) in JitsiMeet. If there
 * is an already active conference it will be automatically left prior to
 * joining the new one.
 */
- (void)join:(JitsiMeetConferenceOptions *_Nullable)options;

- (nullable UIView *)findParticipantByEndpointId:(NSString *_Nonnull)endpointId;

/**
 * Locates a participant's video view by its React Native tag.
 *
 * The reactTag is provided in the PARTICIPANT_VIEW_READY event data.
 * This method uses RCTUIManager to find the view directly, which is more
 * reliable than recursive accessibilityIdentifier search.
 *
 * @param reactTag The React Native view tag from the event data.
 * @return The participant's UIView, or nil if not found.
 */
- (nullable UIView *)findParticipantViewByReactTag:(NSNumber *_Nonnull)reactTag;

/**
 * Asynchronously locates a participant's video view by endpoint id, retrying
 * until the view is mounted or a timeout is reached.
 *
 * With the new architecture (Fabric) native views are mounted asynchronously
 * on the main thread after the JS commit, so the view usually does not exist
 * yet when the PARTICIPANT_VIEW_READY event is delivered. This method retries
 * the lookup on the main queue and is the recommended way to obtain the view.
 *
 * The completion block is always invoked on the main queue, with the view or
 * nil if it could not be found within the retry window.
 *
 * @param endpointId The participant id from the PARTICIPANT_VIEW_READY event.
 * @param completion Block invoked with the resolved view, or nil.
 */
- (void)findParticipantViewByEndpointId:(NSString *_Nonnull)endpointId
                             completion:(void (^_Nonnull)(UIView *_Nullable))completion;

/**
 * Detaches a participant's video view from the in-meeting layout and moves it
 * into the given native container view.
 *
 * Internally this asks the JavaScript side to render the participant in a
 * standalone wrapper sized like the container (so React Native keeps applying
 * a frame which is correct inside the container), waits for the wrapper to be
 * mounted and then reparents it into the container. This is the only safe way
 * to host a participant view inside a native view hierarchy: manually calling
 * addSubview: with a view found in the React Native hierarchy will be undone
 * on the next React Native render pass.
 *
 * The completion block is invoked on the main queue with the detached view
 * (already added to the container, filling its bounds), or nil if the view
 * could not be found in time.
 *
 * Requires the custom-layout.enabled feature flag. If the container is
 * resized, call this method again to update the view's size. Call
 * reattachParticipantView: before removing the container, and do not keep
 * strong references to the returned view: React Native still owns it and
 * destroys it when the participant leaves.
 *
 * @param participantId The participant id from the PARTICIPANT_VIEW_READY
 * event.
 * @param container The native view which should host the participant view.
 * @param completion Block invoked with the detached view, or nil.
 */
- (void)detachParticipantView:(NSString *_Nonnull)participantId
                    container:(UIView *_Nonnull)container
                   completion:(void (^_Nonnull)(UIView *_Nullable))completion;

/**
 * Returns a participant view previously detached with
 * detachParticipantView:container:completion: back to the in-meeting layout
 * (default grid).
 *
 * @param participantId The participant id.
 */
- (void)reattachParticipantView:(NSString *_Nonnull)participantId;

/**
 * Sets the position and size of a participant's video view inside the custom
 * layout. The layout is applied by the JavaScript side (React Native owns the
 * layout), so it persists across video updates and re-renders.
 *
 * Only effective when the custom layout is active
 * (custom-layout.enabled feature flag).
 *
 * @param participantId The participant id from the PARTICIPANT_VIEW_READY
 * event.
 * @param frame The desired frame in points, relative to this view.
 */
- (void)setParticipantViewLayout:(NSString *_Nonnull)participantId frame:(CGRect)frame;

/**
 * Removes a layout previously set with setParticipantViewLayout:frame:,
 * returning the participant's view to the default grid.
 *
 * @param participantId The participant id.
 */
- (void)clearParticipantViewLayout:(NSString *_Nonnull)participantId;

/**
 * Sets whether participant avatars (shown when a participant's video is off)
 * should be hidden. When hidden, the participant's view shows a plain black
 * background instead of the avatar. Applies to all participants.
 *
 * @param hidden YES to hide avatars, NO to show them.
 */
- (void)setAvatarHidden:(BOOL)hidden;

/**
 * Selects the audio output/input device used during the conference.
 *
 * Supported values: @"SPEAKER" (loudspeaker), @"EARPIECE" (phone receiver),
 * @"BLUETOOTH", @"HEADPHONES", @"CAR". The requested device must be
 * available, otherwise the request is ignored (an error is logged on the
 * JavaScript side).
 *
 * Must be called while in a conference: the selection is applied to the
 * active audio session and is reset when the audio route changes (e.g.
 * headphones plugged in) or when the conference ends.
 *
 * @param device The device type to select.
 */
- (void)setAudioDevice:(NSString *_Nonnull)device;

/**
 * Convenience wrapper around setAudioDevice: which switches between the
 * loudspeaker and the phone receiver.
 *
 * @param speakerOn YES for the loudspeaker (@"SPEAKER"), NO for the receiver
 * (@"EARPIECE").
 */
- (void)setSpeakerphoneOn:(BOOL)speakerOn;

/**
 * Leaves the currently active conference.
 */
- (void)leave;
- (void)hangUp;
- (void)setAudioMuted:(BOOL)muted;
- (void)sendEndpointTextMessage:(NSString * _Nonnull)message :(NSString * _Nullable)to;
- (void)toggleScreenShare:(BOOL)enabled;
- (void)retrieveParticipantsInfo:(void (^ _Nonnull)(NSArray * _Nullable))completionHandler;
- (void)openChat:(NSString * _Nullable)to;
- (void)closeChat;
- (void)sendChatMessage:(NSString * _Nonnull)message :(NSString * _Nullable)to;
- (void)setVideoMuted:(BOOL)muted;
- (void)setClosedCaptionsEnabled:(BOOL)enabled;
- (void)toggleCamera;
- (void)showNotification:(NSString * _Nonnull)appearance :(NSString * _Nullable)description :(NSString * _Nullable)timeout :(NSString * _Nullable)title :(NSString * _Nullable)uid;
- (void)hideNotification:(NSString * _Nullable)uid;
- (void)startRecording:(RecordingMode)mode :(NSString * _Nullable)dropboxToken :(BOOL)shouldShare :(NSString * _Nullable)rtmpStreamKey :(NSString * _Nullable)rtmpBroadcastID :(NSString * _Nullable)youtubeStreamKey :(NSString * _Nullable)youtubeBroadcastID :(NSDictionary * _Nullable)extraMetadata :(BOOL)transcription;
- (void)stopRecording:(RecordingMode)mode :(BOOL)transcription;
- (void)overwriteConfig:(NSDictionary * _Nonnull)config;
- (void)sendCameraFacingModeMessage:(NSString * _Nonnull)to :(NSString * _Nullable)facingMode;
@end
