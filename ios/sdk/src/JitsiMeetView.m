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

#include <mach/mach_time.h>

#import <UIKit/UIKit.h>

#import "ExternalAPI.h"
#import "JitsiMeet+Private.h"
#import "JitsiMeetConferenceOptions+Private.h"
#import "JitsiMeetView+Private.h"
#import "ReactUtils.h"
#import <React/RCTRootView.h>
#import <React/RCTUIManager.h>
#import <React/UIView+React.h>


#pragma mark UIColor helpers

@interface UIColor (Hex)

+ (UIColor *)colorWithHex:(uint32_t)hex;
+ (UIColor *)colorWithHex:(uint32_t)hex alpha:(CGFloat)alpha;

@end

@implementation UIColor (Hex)

+ (UIColor *)colorWithHex:(uint32_t)hex {
    return [self colorWithHex:hex alpha:1.0];
}

+ (UIColor *)colorWithHex:(uint32_t)hex alpha:(CGFloat)alpha {
    CGFloat red   = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat green = ((hex >> 8) & 0xFF) / 255.0;
    CGFloat blue  = (hex & 0xFF) / 255.0;

    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

@end

#pragma mark UIColor helpers end

/**
 * Backwards compatibility: turn the boolean prop into a feature flag.
 */
static NSString *const PiPEnabledFeatureFlag = @"pip.enabled";

/**
 * Forward declarations.
 */
static NSString *recordingModeToString(RecordingMode mode);


@implementation JitsiMeetView {
    /**
     * React Native view where the entire content will be rendered.
     */
    RCTRootView *rootView;

    /**
     * Participant views detached into native containers, keyed by
     * participant id. Values are held weakly: React Native still owns the
     * views and may destroy them at any time (e.g. participant left).
     */
    NSMapTable<NSString *, UIView *> *detachedParticipantViews;

    /**
     * The original React Native superviews of detached participant views,
     * keyed by participant id, so views can be given back to React Native
     * before they are unmounted.
     */
    NSMapTable<NSString *, UIView *> *detachedParticipantParents;
}

#pragma mark Initializers

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self doInitialize];
    }

    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self doInitialize];
    }

    return self;
}

/**
 * Internal initialization:
 *
 * - sets the background color
 * - registers necessary observers
 */
- (void)doInitialize {
    // Set a background color which matches the one used in JS.
    self.backgroundColor = [UIColor colorWithHex:0x040404 alpha:1];
    
    [self registerObservers];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIView *)findParticipantByEndpointId:(NSString *)endpointId {
    NSString *identifier = [NSString stringWithFormat:@"participant-%@", endpointId];

    return [self findSubviewWithAccessibilityIdentifier:identifier inView:self];
}

- (UIView *)findSubviewWithAccessibilityIdentifier:(NSString *)identifier inView:(UIView *)view {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) {
        return view;
    }

    for (UIView *subview in view.subviews) {
        UIView *result = [self findSubviewWithAccessibilityIdentifier:identifier inView:subview];
        if (result) {
            return result;
        }
    }

    return nil;
}

- (UIView *)findParticipantViewByReactTag:(NSNumber *)reactTag {
    if (!reactTag) {
        return nil;
    }

    // With the new architecture (Fabric, RCT_NEW_ARCH_ENABLED=1) component
    // views store the react tag in the plain UIView.tag property, while
    // legacy/interop views use the reactTag associated object from
    // UIView+React.h. Check both during the recursive search.
    return [self findSubviewWithReactTag:reactTag inView:self];
}

- (UIView *)findSubviewWithReactTag:(NSNumber *)reactTag inView:(UIView *)view {
    // Fabric: RCTViewComponentView sets UIView.tag to the react tag.
    if (view.tag == reactTag.integerValue) {
        return view;
    }

    // Paper/interop: reactTag associated object.
    if (view.reactTag != nil && [view.reactTag isEqualToNumber:reactTag]) {
        return view;
    }

    for (UIView *subview in view.subviews) {
        UIView *result = [self findSubviewWithReactTag:reactTag inView:subview];
        if (result) {
            return result;
        }
    }

    return nil;
}

/**
 * Number of lookup attempts before giving up. With Fabric the native views
 * are mounted asynchronously on the main thread after the JS commit, so the
 * view may not exist yet when PARTICIPANT_VIEW_READY is delivered.
 */
static const NSInteger kParticipantViewLookupMaxAttempts = 30;

/**
 * Delay between lookup attempts.
 */
static const NSTimeInterval kParticipantViewLookupRetryDelay = 0.1;

/**
 * Number of attempts to wait for the container to be laid out before giving
 * up. When PARTICIPANT_VIEW_READY fires, the host app's container may still
 * have zero bounds because Auto Layout hasn't run yet (mirrors Android's
 * container.isLaidOut() guard).
 */
static const NSInteger kContainerLayoutMaxAttempts = 20;

/**
 * Delay between container layout attempts.
 */
static const NSTimeInterval kContainerLayoutRetryDelay = 0.05;

/**
 * Number of times to retry the layout/renderer fix after reparenting.
 * With Fabric, RTCVideoView may be created AFTER detachParticipantView
 * (e.g. when the local video is unmuted later), so the fix must retry
 * to catch views that do not exist yet on the first pass.
 */
static const NSInteger kForceLayoutMaxAttempts = 6;

/**
 * Delay between layout/renderer fix retries.
 */
static const NSTimeInterval kForceLayoutRetryDelay = 0.5;

- (void)findParticipantViewByEndpointId:(NSString *)endpointId
                             completion:(void (^)(UIView *))completion {
    NSString *identifier = [NSString stringWithFormat:@"participant-%@", endpointId];

    [self findViewWithIdentifier:identifier
                        attempts:kParticipantViewLookupMaxAttempts
                      completion:completion];
}

- (void)findViewWithIdentifier:(NSString *)identifier
                      attempts:(NSInteger)attempts
                    completion:(void (^)(UIView *))completion {
    UIView *view = [self findSubviewWithAccessibilityIdentifier:identifier inView:self];

    if (view || attempts <= 1) {
        completion(view);

        return;
    }

    __weak __typeof(self) weakSelf = self;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kParticipantViewLookupRetryDelay * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            __typeof(self) strongSelf = weakSelf;

            if (!strongSelf) {
                completion(nil);

                return;
            }

            [strongSelf findViewWithIdentifier:identifier
                                      attempts:attempts - 1
                                    completion:completion];
        });
}

- (void)_detachParticipantView:(NSString *)participantId
                      container:(UIView *)container
                        attempt:(NSInteger)attempt
                      completion:(void (^)(UIView *))completion {
    // Guard: the container must have non-zero bounds before we can compute
    // the layout size to send to JS and the frame to apply after reparenting.
    if (container.bounds.size.width == 0 || container.bounds.size.height == 0) {
        if (attempt <= 1) {
            NSLog(@"[JitsiMeetView] detachParticipantView: container has "
                   "zero size after %d attempts, giving up for %@",
                  (int)kContainerLayoutMaxAttempts, participantId);
            completion(nil);

            return;
        }

        __weak __typeof(self) weakSelf = self;

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(kContainerLayoutRetryDelay * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                [weakSelf _detachParticipantView:participantId
                                      container:container
                                        attempt:attempt - 1
                                      completion:completion];
            });

        return;
    }

    if (!detachedParticipantViews) {
        detachedParticipantViews = [NSMapTable strongToWeakObjectsMapTable];
        detachedParticipantParents = [NSMapTable strongToWeakObjectsMapTable];
    }

    // 1. Ask the JS side to move this participant into a standalone,
    // absolutely positioned wrapper sized like the container. Using origin
    // (0, 0) means any subsequent React Native layout pass writes a frame
    // which is also correct inside the native container.
    CGRect frame = CGRectMake(0, 0, container.bounds.size.width, container.bounds.size.height);
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendSetParticipantViewLayout:participantId frame:frame];

    // 2. Wait for the wrapper (positioned-participant-<id>) to be mounted,
    // then move it into the native container. The wrapper id is distinct
    // from the grid views so the old grid view can never be picked up.
    NSString *identifier = [NSString stringWithFormat:@"positioned-participant-%@", participantId];
    __weak __typeof(self) weakSelf = self;

    [self findViewWithIdentifier:identifier
                        attempts:kParticipantViewLookupMaxAttempts
                      completion:^(UIView *view) {
        __typeof(self) strongSelf = weakSelf;

        if (!strongSelf || !view) {
            completion(nil);

            return;
        }

        // Guard: the wrapper must be the only child of its dedicated holder
        // view. If it is not (e.g. the holder got flattened away by Fabric),
        // reparenting it would shift the mounting indices of unrelated
        // sibling views and crash React Native later. Refuse to detach in
        // that case instead of corrupting the hierarchy.
        if (view.superview && view.superview != container
                && view.superview.subviews.count != 1) {
            NSLog(@"[JitsiMeetView] detachParticipantView: unexpected parent "
                   "with %lu children, refusing to detach %@",
                  (unsigned long)view.superview.subviews.count, participantId);
            completion(nil);

            return;
        }

        // Remember the React Native parent so the view can be given back
        // before React Native unmounts it.
        if (view.superview && view.superview != container) {
            [strongSelf->detachedParticipantParents setObject:view.superview forKey:participantId];
        }

        [strongSelf->detachedParticipantViews setObject:view forKey:participantId];

        [container addSubview:view];
        view.frame = container.bounds;

        // Auto-resize the reparented view when the container's bounds change
        // (e.g. safe area inset update, device rotation). The view is no longer
        // in the React Native hierarchy, so it won't get layout updates from
        // React Native; autoresizingMask keeps it in sync with the container.
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        // Force a layout pass on the reparented view and all its subviews.
        // RTCVideoView (from react-native-webrtc) sets its internal videoView's
        // frame in layoutSubviews. After reparenting within the same window,
        // didMoveToWindow is NOT called and layoutSubviews may not fire
        // automatically, leaving the RTCMTLVideoView with a zero/stale frame
        // and the video invisible. When JitsiMeetView is used as a headless
        // manager (not added to a window), RTCVideoView's renderer is only
        // connected once the view is reparented into a window here. If the
        // RTCVideoView does not exist yet (e.g. local video still muted), the
        // fix is retried multiple times to catch it when it is created later
        // after setVideoMuted(false) triggers a new Fabric mount.
        [strongSelf _forceLayoutForViewAndSubviews:view
                                           attempt:kForceLayoutMaxAttempts];

        completion(view);
    }];
}

- (void)detachParticipantView:(NSString *)participantId
                    container:(UIView *)container
                   completion:(void (^)(UIView *))completion {
    [self _detachParticipantView:participantId
                        container:container
                          attempt:kContainerLayoutMaxAttempts
                        completion:completion];
}

/**
 * Recursively calls setNeedsLayout on the view and all its descendants, then
 * triggers layoutIfNeeded. This forces RTCVideoView's layoutSubviews to run,
 * updating its internal RTCMTLVideoView frame after the wrapper was reparented
 * into a native container.
 *
 * Retries multiple times so that RTCVideoView instances created AFTER the
 * reparent (e.g. when the local video is unmuted after detachParticipantView)
 * are also fixed. With Fabric (RCT_NEW_ARCH_ENABLED) views are mounted
 * asynchronously; when JitsiMeetView is used as a "headless" manager (not
 * added to a window) RTCVideoView's renderer is only connected once the view
 * is reparented into a window via detachParticipantView. If the RTCVideoView
 * does not exist yet at that point, the renderer fix must be retried later.
 */
- (void)_forceLayoutForViewAndSubviews:(UIView *)view
    attempt:(NSInteger)attempt
{
    __weak __typeof(self) weakSelf = self;

    // First attempt uses a shorter delay to let Fabric finish mounting.
    NSTimeInterval delay
        = (attempt == kForceLayoutMaxAttempts) ? 0.3 : kForceLayoutRetryDelay;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            __typeof(self) strongSelf = weakSelf;

            // Stop retrying if the view was reattached or removed.
            if (!strongSelf || !view.window) {
                return;
            }

            [strongSelf _recursiveSetNeedsLayout:view];
            [view layoutIfNeeded];

            // RTCVideoView (react-native-webrtc) only adds itself as a video
            // track renderer in didMoveToWindow (when self.window becomes
            // non-nil) or in setVideoTrack: (if self.window is already
            // non-nil). After reparenting within the same window,
            // didMoveToWindow is NOT called, so if setVideoTrack: ran while
            // the view was still being mounted by Fabric (self.window was nil),
            // the renderer was never added. Trigger it by re-setting the
            // videoTrack via KVC (see _triggerVideoRenderersInViewHierarchy),
            // which re-adds the renderer without touching the view hierarchy.
            [strongSelf _triggerVideoRenderersInViewHierarchy:view];

            if (attempt > 0) {
                [strongSelf _forceLayoutForViewAndSubviews:view
                                                     attempt:attempt - 1];
            }
        });
}

- (void)_recursiveSetNeedsLayout:(UIView *)view {
    [view setNeedsLayout];

    for (UIView *subview in view.subviews) {
        [self _recursiveSetNeedsLayout:subview];
    }
}

/**
 * Finds RTCVideoView instances (from react-native-webrtc) by checking for the
 * videoTrack property, and re-connects the video renderer by re-setting the
 * track through KVC. This ensures the renderer is connected even if
 * setVideoTrack: was called before the view was added to a window (e.g.
 * during Fabric's off-screen batch mounting).
 *
 * The track is re-set (nil then the previous value) instead of removing and
 * re-adding the view to its superview: the old remove/add approach interrupted
 * any in-flight touch on the view ("Unexpected nil window in latent system
 * gesture client update") and could leave the touch system stuck, making the
 * whole app stop responding to touches. setVideoTrack: removes the old
 * renderer and adds the new one (when the view is in a window) without
 * touching the view hierarchy, so touches are never interrupted.
 */
- (void)_triggerVideoRenderersInViewHierarchy:(UIView *)view {
    // RTCVideoView has a @property(nonatomic, strong) RTCVideoTrack *videoTrack.
    // Only re-connect when the view is already in a window: setVideoTrack:
    // adds the renderer only when self.window is non-nil.
    if ([view respondsToSelector:@selector(videoTrack)] && view.window) {
        id track = [view valueForKey:@"videoTrack"];

        if (track) {
            // nil removes the existing renderer (and renders a blank frame),
            // re-setting the previous track adds it back. The cycle is
            // idempotent across the layout-fix retries: each pass removes and
            // re-adds exactly one renderer, so no duplicates accumulate.
//            [view setValue:nil forKey:@"videoTrack"];
            [view setValue:track forKey:@"videoTrack"];
        }
    }

    // No view hierarchy mutation happens above, so direct iteration is safe.
    for (UIView *subview in view.subviews) {
        [self _triggerVideoRenderersInViewHierarchy:subview];
    }
}

- (void)reattachParticipantView:(NSString *)participantId {
    UIView *view = [detachedParticipantViews objectForKey:participantId];
    UIView *parent = [detachedParticipantParents objectForKey:participantId];

    // Give the view back to its React Native parent so the unmount caused
    // by clearing the layout finds the view where React Native expects it.
    if (view && parent) {
        // Clear the autoresizingMask set during detach: React Native manages
        // the view's frame via its own layout system, and an autoresizing
        // mask would interfere with it.
        view.autoresizingMask = UIViewAutoresizingNone;
        [parent addSubview:view];
    }

    [detachedParticipantViews removeObjectForKey:participantId];
    [detachedParticipantParents removeObjectForKey:participantId];

    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendClearParticipantViewLayout:participantId];
}

#pragma mark API

- (void)join:(JitsiMeetConferenceOptions *)options {
    [self setProps:options == nil ? @{} : [options asProps]];
}

- (void)leave {
    [self setProps:@{}];
}

- (void)hangUp {
    // Give every detached participant view back to its React Native parent
    // and drop our tracking before tearing the conference down. Positioned
    // wrappers can be left inside native containers (e.g. when the local
    // participant id changed mid-conference and React remounted the wrapper
    // while it was still parented here). Restoring synchronously on hang up,
    // before the JavaScript side clears the layouts and unmounts the
    // wrappers, avoids orphans that would swallow touches in later
    // conferences.
    [self _restoreAllDetachedParticipantViews];

    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendHangUp];
}

- (void)setAudioMuted:(BOOL)muted {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendSetAudioMuted:muted];
}

- (void)setParticipantViewLayout:(NSString * _Nonnull)participantId frame:(CGRect)frame {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendSetParticipantViewLayout:participantId frame:frame];
}

- (void)clearParticipantViewLayout:(NSString * _Nonnull)participantId {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendClearParticipantViewLayout:participantId];
}

- (void)setAvatarHidden:(BOOL)hidden {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];

    if (externalAPI) {
        [externalAPI sendSetAvatarHidden:hidden];
    } else {
        // The React Native module does not exist yet (called before join).
        // Remember the value; it is replayed once the JS side starts
        // observing external API events.
        [ExternalAPI setPendingAvatarHidden:hidden];
    }
}

- (void)setAudioDevice:(NSString * _Nonnull)device {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendSetAudioDevice:device];
}

- (void)setSpeakerphoneOn:(BOOL)speakerOn {
    [self setAudioDevice:speakerOn ? @"SPEAKER" : @"EARPIECE"];
}

- (void)sendEndpointTextMessage:(NSString * _Nonnull)message :(NSString * _Nullable)to {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendEndpointTextMessage:message :to];
}

- (void)toggleScreenShare:(BOOL)enabled {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI toggleScreenShare:enabled];
}

- (void)retrieveParticipantsInfo:(void (^ _Nonnull)(NSArray * _Nullable))completionHandler {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI retrieveParticipantsInfo:completionHandler];
}

- (void)openChat:(NSString*)to  {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI openChat:to];
}

- (void)closeChat  {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI closeChat];
}

- (void)sendChatMessage:(NSString * _Nonnull)message :(NSString * _Nullable)to {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendChatMessage:message :to];
}

- (void)setVideoMuted:(BOOL)muted {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendSetVideoMuted:muted];
}

- (void)setClosedCaptionsEnabled:(BOOL)enabled {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendSetClosedCaptionsEnabled:enabled];
}

- (void)toggleCamera {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI toggleCamera];
}

- (void)showNotification:(NSString *)appearance :(NSString *)description :(NSString *)timeout :(NSString *)title :(NSString *)uid {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI showNotification:appearance :description :timeout :title :uid];
}

-(void)hideNotification:(NSString *)uid {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI hideNotification:uid];
}

- (void)startRecording:(RecordingMode)mode :(NSString * _Nullable)dropboxToken :(BOOL)shouldShare :(NSString * _Nullable)rtmpStreamKey :(NSString * _Nullable)rtmpBroadcastID :(NSString * _Nullable)youtubeStreamKey :(NSString * _Nullable)youtubeBroadcastID :(NSDictionary * _Nullable)extraMetadata :(BOOL)transcription {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI startRecording:recordingModeToString(mode) :dropboxToken :shouldShare :rtmpStreamKey :rtmpBroadcastID :youtubeStreamKey :youtubeBroadcastID :extraMetadata :transcription];
}

- (void)stopRecording:(RecordingMode)mode :(BOOL)transcription {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI stopRecording:recordingModeToString(mode) :transcription];
}

- (void)overwriteConfig:(NSDictionary * _Nonnull)config {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI overwriteConfig:config];
}

- (void)sendCameraFacingModeMessage:(NSString * _Nonnull)to :(NSString * _Nullable)facingMode {
    ExternalAPI *externalAPI = [[JitsiMeet sharedInstance] getExternalAPI];
    [externalAPI sendCameraFacingModeMessage:to :facingMode];
}

#pragma mark Private methods

- (void)registerObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleUpdateViewPropsNotification:) name:updateViewPropsNotificationName object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSendEventNotification:) name:sendEventNotificationName object:nil];
 }

- (void)handleUpdateViewPropsNotification:(NSNotification *)notification {
    NSDictionary *props = [notification.userInfo objectForKey:@"props"];
    [self setProps:props];
}

- (void)handleSendEventNotification:(NSNotification *)notification {
    NSString *eventName = notification.userInfo[@"name"];
    NSString *eventData = notification.userInfo[@"data"];

    // Safety net for detached participant views: when React Native is about
    // to unmount a positioned wrapper (participant left, conference ended),
    // give the view back to its React Native parent first, otherwise the
    // Fabric unmount asserts ("Attempt to unmount a view which is mounted
    // inside different view").
    [self restoreDetachedViewsForEvent:eventName data:notification.userInfo[@"data"]];

    SEL sel = NSSelectorFromString([self methodNameFromEventName:eventName]);
    if (sel && [self.delegate respondsToSelector:sel]) {
        [self.delegate performSelector:sel withObject:eventData];
    }
}

- (void)restoreDetachedViewsForEvent:(NSString *)eventName data:(id)data {
    if (detachedParticipantViews.count == 0) {
        return;
    }

    if ([eventName isEqualToString:@"PARTICIPANT_LEFT"]) {
        NSString *participantId
            = [data isKindOfClass:NSDictionary.class] ? data[@"participantId"] : nil;

        if (participantId) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self restoreDetachedParticipantView:participantId];
            });
        }
    } else if ([eventName isEqualToString:@"CONFERENCE_WILL_TERMINATE"]
            || [eventName isEqualToString:@"CONFERENCE_TERMINATED"]
            || [eventName isEqualToString:@"READY_TO_CLOSE"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSString *participantId in [[self->detachedParticipantViews keyEnumerator] allObjects]) {
                [self restoreDetachedParticipantView:participantId];
            }
        });
    } else if ([eventName isEqualToString:@"VIDEO_MUTED_CHANGED"]) {
        // When the video mute state changes, RTCVideoView instances may be
        // created (unmute) or destroyed (mute) inside the detached views.
        // This is critical for the local participant: PARTICIPANT_VIEW_READY
        // fires while video may still be muted, so detachParticipantView
        // reparents a wrapper with only an Avatar. When setVideoMuted(false)
        // is called later, Fabric creates a new RTCVideoView inside the
        // already-reparented wrapper. The renderer fix must be re-triggered
        // to catch this newly mounted RTCVideoView.
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSString *participantId in
                    [[self->detachedParticipantViews keyEnumerator] allObjects]) {
                UIView *view
                    = [self->detachedParticipantViews objectForKey:participantId];
                if (view) {
                    [self _forceLayoutForViewAndSubviews:view
                                                 attempt:kForceLayoutMaxAttempts];
                }
            }
        });
    }
}

/**
 * Gives a detached participant view back to its original React Native parent
 * (if both still exist) and stops tracking it. Must be called on the main
 * thread.
 */
- (void)restoreDetachedParticipantView:(NSString *)participantId {
    UIView *view = [detachedParticipantViews objectForKey:participantId];
    UIView *parent = [detachedParticipantParents objectForKey:participantId];

    if (view && parent && view.superview != parent) {
        // Clear the autoresizingMask set during detach: React Native manages
        // the view's frame via its own layout system.
        view.autoresizingMask = UIViewAutoresizingNone;
        [parent addSubview:view];
    }

    [detachedParticipantViews removeObjectForKey:participantId];
    [detachedParticipantParents removeObjectForKey:participantId];
}

/**
 * Gives every detached participant view back to its React Native parent (if
 * both still exist) and clears the tracking tables. Must be called on the
 * main thread. Safe to call when nothing is currently detached.
 *
 * This is the synchronous counterpart of the CONFERENCE_TERMINATED branch
 * of {@link restoreDetachedViewsForEvent:data:}, used on hang up so the
 * JavaScript side can cleanly unmount the positioned wrappers (which are
 * back in the React Native hierarchy by then) instead of leaving orphans
 * inside native containers.
 */
- (void)_restoreAllDetachedParticipantViews {
    if (!detachedParticipantViews || detachedParticipantViews.count == 0) {
        return;
    }

    // Snapshot the keys: restoreDetachedParticipantView: mutates the table.
    NSArray<NSString *> *participantIds
        = [[detachedParticipantViews keyEnumerator] allObjects];

    for (NSString *participantId in participantIds) {
        [self restoreDetachedParticipantView:participantId];
    }
}

/**
  * Converts a specific event name i.e. redux action type description to a
  * method name.
  *
  * @param eventName The event name to convert to a method name.
  * @return A method name constructed from the specified `eventName`.
  */
 - (NSString *)methodNameFromEventName:(NSString *)eventName {
    NSMutableString *methodName
        = [NSMutableString stringWithCapacity:eventName.length];

    for (NSString *c in [eventName componentsSeparatedByString:@"_"]) {
        if (c.length) {
            [methodName appendString:
                methodName.length ? c.capitalizedString : c.lowercaseString];
        }
    }
    [methodName appendString:@":"];

    return methodName;
 }

/**
 * Passes the given props to the React Native application. The props which we pass
 * are a combination of 3 different sources:
 *
 * - JitsiMeet.defaultConferenceOptions
 * - This function's parameters
 * - Some extras which are added by this function
 */
- (void)setProps:(NSDictionary *_Nonnull)newProps {
    NSMutableDictionary *props = mergeProps([[JitsiMeet sharedInstance] getDefaultProps], newProps);

    // Set the PiP flag if it wasn't manually set.
    NSMutableDictionary *featureFlags = props[@"flags"];
    if (featureFlags[PiPEnabledFeatureFlag] == nil) {
        featureFlags[PiPEnabledFeatureFlag]
            = [NSNumber numberWithBool:
               self.delegate && [self.delegate respondsToSelector:@selector(enterPictureInPicture:)]];
    }

    // This method is supposed to be imperative i.e. a second
    // invocation with one and the same URL is expected to join the respective
    // conference again if the first invocation was followed by leaving the
    // conference. However, React and, respectively,
    // appProperties/initialProperties are declarative expressions i.e. one and
    // the same URL will not trigger an automatic re-render in the JavaScript
    // source code. The workaround implemented below introduces imperativeness
    // in React Component props by defining a unique value per invocation.
    props[@"timestamp"] = @(mach_absolute_time());

    if (rootView) {
        // Update props with the new URL.
        rootView.appProperties = props;
    } else {
        // Get the factory and use its rootViewFactory to create the view.
        RCTReactNativeFactory *factory = [[JitsiMeet sharedInstance] getReactNativeFactory];        
        rootView = (RCTRootView *)[factory.rootViewFactory viewWithModuleName:@"App"
                                                            initialProperties:props];
        
        factory.bridge = rootView.bridge;
        
        rootView.backgroundColor = self.backgroundColor;

        // Add rootView as a subview which completely covers this one.
        [rootView setFrame:[self bounds]];
        rootView.autoresizingMask
            = UIViewAutoresizingFlexibleWidth
                | UIViewAutoresizingFlexibleHeight;
        [self addSubview:rootView];
    }
}

@end

static NSString *recordingModeToString(RecordingMode mode) {
    switch (mode) {
        case RecordingModeFile:
            return @"file";
        case RecordingModeStream:
            return @"stream";
        default:
            return nil;
    }
}
