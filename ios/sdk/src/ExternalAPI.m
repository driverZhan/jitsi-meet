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

#import "ExternalAPI.h"
#import <React/RCTLog.h>

// Events
static NSString * const hangUpAction = @"org.jitsi.meet.HANG_UP";
static NSString * const setAudioMutedAction = @"org.jitsi.meet.SET_AUDIO_MUTED";
static NSString * const sendEndpointTextMessageAction = @"org.jitsi.meet.SEND_ENDPOINT_TEXT_MESSAGE";
static NSString * const toggleScreenShareAction = @"org.jitsi.meet.TOGGLE_SCREEN_SHARE";
static NSString * const retrieveParticipantsInfoAction = @"org.jitsi.meet.RETRIEVE_PARTICIPANTS_INFO";
static NSString * const openChatAction = @"org.jitsi.meet.OPEN_CHAT";
static NSString * const closeChatAction = @"org.jitsi.meet.CLOSE_CHAT";
static NSString * const sendChatMessageAction = @"org.jitsi.meet.SEND_CHAT_MESSAGE";
static NSString * const setVideoMutedAction = @"org.jitsi.meet.SET_VIDEO_MUTED";
static NSString * const setClosedCaptionsEnabledAction = @"org.jitsi.meet.SET_CLOSED_CAPTIONS_ENABLED";
static NSString * const toggleCameraAction = @"org.jitsi.meet.TOGGLE_CAMERA";
static NSString * const showNotificationAction = @"org.jitsi.meet.SHOW_NOTIFICATION";
static NSString * const hideNotificationAction = @"org.jitsi.meet.HIDE_NOTIFICATION";
static NSString * const startRecordingAction = @"org.jitsi.meet.START_RECORDING";
static NSString * const stopRecordingAction = @"org.jitsi.meet.STOP_RECORDING";
static NSString * const overwriteConfigAction = @"org.jitsi.meet.OVERWRITE_CONFIG";
static NSString * const sendCameraFacingModeMessageAction = @"org.jitsi.meet.SEND_CAMERA_FACING_MODE_MESSAGE";
static NSString * const setParticipantViewLayoutAction = @"org.jitsi.meet.SET_PARTICIPANT_VIEW_LAYOUT";
static NSString * const setAvatarHiddenAction = @"org.jitsi.meet.SET_AVATAR_HIDDEN";
static NSString * const setAudioDeviceAction = @"org.jitsi.meet.SET_AUDIO_DEVICE";

@implementation ExternalAPI

static NSMapTable<NSString*, void (^)(NSArray* participantsInfo)> *participantInfoCompletionHandlers;

/**
 * Last avatar-hidden value requested by the host app. Kept at file scope so
 * the value survives when it is set before the React Native module exists or
 * before the JS side registered its listeners, and can be replayed once JS
 * starts observing.
 */
static NSNumber *pendingAvatarHidden = nil;
static NSNumber *pendingAudioMuted = nil;
static NSNumber *pendingVideoMuted = nil;

__attribute__((constructor))
static void initializeViewsMap(void) {
    participantInfoCompletionHandlers = [NSMapTable strongToStrongObjectsMapTable];
}

RCT_EXPORT_MODULE();

static __weak ExternalAPI *_sharedExternalAPI = nil;

- (instancetype)init {
    self = [super init];
    if (self) {
        _sharedExternalAPI = self;
    }

    return self;
}

+ (ExternalAPI *)sharedInstance {
    return _sharedExternalAPI;
}

- (NSDictionary *)constantsToExport {
    return @{
        @"HANG_UP": hangUpAction,
        @"SET_AUDIO_MUTED" : setAudioMutedAction,
        @"SEND_ENDPOINT_TEXT_MESSAGE": sendEndpointTextMessageAction,
        @"TOGGLE_SCREEN_SHARE": toggleScreenShareAction,
        @"RETRIEVE_PARTICIPANTS_INFO": retrieveParticipantsInfoAction,
        @"OPEN_CHAT": openChatAction,
        @"CLOSE_CHAT": closeChatAction,
        @"SEND_CHAT_MESSAGE": sendChatMessageAction,
        @"SET_VIDEO_MUTED" : setVideoMutedAction,
        @"SET_CLOSED_CAPTIONS_ENABLED": setClosedCaptionsEnabledAction,
        @"TOGGLE_CAMERA": toggleCameraAction,
        @"SHOW_NOTIFICATION": showNotificationAction,
        @"HIDE_NOTIFICATION": hideNotificationAction,
        @"START_RECORDING": startRecordingAction,
        @"STOP_RECORDING": stopRecordingAction,
        @"OVERWRITE_CONFIG": overwriteConfigAction,
        @"SEND_CAMERA_FACING_MODE_MESSAGE": sendCameraFacingModeMessageAction,
        @"SET_PARTICIPANT_VIEW_LAYOUT": setParticipantViewLayoutAction,
        @"SET_AVATAR_HIDDEN": setAvatarHiddenAction,
        @"SET_AUDIO_DEVICE": setAudioDeviceAction
    };
};

/**
 * Make sure all methods in this module are invoked on the main/UI thread.
 */
- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

+ (void)setPendingAvatarHidden:(BOOL)hidden {
    pendingAvatarHidden = @(hidden);
}

+ (void)setPendingAudioMuted:(BOOL)muted {
    pendingAudioMuted = @(muted);
}

+ (void)setPendingVideoMuted:(BOOL)muted {
    pendingVideoMuted = @(muted);
}

- (void)startObserving {
    NSLog(@"[ExternalAPI] startObserving: JS side is now listening for events");
    [super startObserving];

    // Replay state set by the host app before the JS side was listening
    // (events sent while no listeners are registered are dropped by
    // RCTEventEmitter). Dispatch asynchronously so the whole batch of
    // addListener calls is processed first.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (pendingAvatarHidden != nil) {
            [self sendEventWithName:setAvatarHiddenAction
                               body:@{ @"hidden": pendingAvatarHidden }];
        }
        if (pendingAudioMuted != nil) {
            NSLog(@"[ExternalAPI] startObserving: replaying pending audio muted = %@", pendingAudioMuted);
            [self sendEventWithName:setAudioMutedAction
                               body:@{ @"muted": pendingAudioMuted }];
        }
        if (pendingVideoMuted != nil) {
            NSLog(@"[ExternalAPI] startObserving: replaying pending video muted = %@", pendingVideoMuted);
            [self sendEventWithName:setVideoMutedAction
                               body:@{ @"muted": pendingVideoMuted }];
        }
    });
}

// /**
//  * Override sendEventWithName:body: to bypass the _listenerCount check in
//  * RCTEventEmitter. In React Native 0.85+ bridgeless mode, when a second
//  * conference is started (new RCTRootView or module invalidation),
//  * _listenerCount may be 0 even though the JS side has active
//  * NativeEventEmitter listeners. The parent class silently drops events when
//  * _listenerCount == 0. We bypass this by calling _callableJSModules directly.
//  */
// - (void)sendEventWithName:(NSString *)eventName body:(id)body {
//     if (RCT_DEBUG && ![[self supportedEvents] containsObject:eventName]) {
//         RCTLogError(
//             @"`%@` is not a supported event type for %@. Supported events are: `%@`",
//             eventName,
//             [self class],
//             [[self supportedEvents] componentsJoinedByString:@"`, `"]);
//         return;
//     }

//     if (self.callableJSModules) {
//         [self.callableJSModules invokeModule:@"RCTDeviceEventEmitter"
//                                       method:@"emit"
//                                     withArgs:body ? @[ eventName, body ] : @[ eventName ]];
//     } else {
//         NSLog(@"[ExternalAPI] sendEventWithName: callableJSModules is nil, event %@ dropped", eventName);
//     }
// }

- (NSArray<NSString *> *)supportedEvents {
    return @[ hangUpAction,
              setAudioMutedAction,
              sendEndpointTextMessageAction,
              toggleScreenShareAction,
              retrieveParticipantsInfoAction,
              openChatAction,
              closeChatAction,
              sendChatMessageAction,
              setVideoMutedAction,
              setClosedCaptionsEnabledAction,
              toggleCameraAction,
              showNotificationAction,
              hideNotificationAction,
              startRecordingAction,
              stopRecordingAction,
              overwriteConfigAction,
              sendCameraFacingModeMessageAction,
              setParticipantViewLayoutAction,
              setAvatarHiddenAction,
              setAudioDeviceAction
    ]
;
}

// Track listener count for debugging (parent's _listenerCount is private)
static volatile NSInteger _externalListenerCount = 0;

- (void)addListener:(NSString *)eventName {
    [super addListener:eventName];
    _externalListenerCount++;
    NSLog(@"[ExternalAPI] addListener: %@, listenerCount=%ld", eventName, (long)_externalListenerCount);
}

- (void)removeListeners:(double)count {
    [super removeListeners:count];
    _externalListenerCount = MAX(_externalListenerCount - (NSInteger)count, 0);
    NSLog(@"[ExternalAPI] removeListeners: count=%.0f, listenerCount=%ld", count, (long)_externalListenerCount);
}

/**
 * Allows the JS side to query and replay any pending mute state that may
 * have been set before event listeners were registered or while the bridge
 * was temporarily unavailable.
 */
RCT_EXPORT_METHOD(syncMuteState:(RCTResponseSenderBlock)callback) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    if (pendingAudioMuted != nil) {
        result[@"audioMuted"] = pendingAudioMuted;
    }
    if (pendingVideoMuted != nil) {
        result[@"videoMuted"] = pendingVideoMuted;
    }

    NSLog(@"[ExternalAPI] syncMuteState: returning %@", result);

    callback(@[ result ]);
}

/**
 * Called by the JS side to acknowledge that a mute state event was received,
 * allowing the native side to clear the pending value and stop retrying.
 */
RCT_EXPORT_METHOD(clearPendingMuteState:(NSString *)type) {
    NSLog(@"[ExternalAPI] clearPendingMuteState: type=%@", type);
    if ([type isEqualToString:@"audio"]) {
        pendingAudioMuted = nil;
    } else if ([type isEqualToString:@"video"]) {
        pendingVideoMuted = nil;
    }
}

/**
 * Dispatches an event that occurred on JavaScript to the view's delegate.
 *
 * @param name The name of the event.
 * @param data The details/specifics of the event to send determined
 * by/associated with the specified `name`.
 * @param scope
 */
RCT_EXPORT_METHOD(sendEvent:(NSString *)name
                       data:(NSDictionary *)data) {
    if ([name isEqual: @"PARTICIPANTS_INFO_RETRIEVED"]) {
        [self onParticipantsInfoRetrieved: data];
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:sendEventNotificationName
                                                        object:nil
                                                      userInfo:@{@"name": name, @"data": data}];
}

- (void) onParticipantsInfoRetrieved:(NSDictionary *)data {
    NSArray *participantsInfoArray = [data objectForKey:@"participantsInfo"];
    NSString *completionHandlerId = [data objectForKey:@"requestId"];
    
    void (^completionHandler)(NSArray*) = [participantInfoCompletionHandlers objectForKey:completionHandlerId];
    completionHandler(participantsInfoArray);
    [participantInfoCompletionHandlers removeObjectForKey:completionHandlerId];
}

- (void)sendHangUp {
    [self sendEventWithName:hangUpAction body:nil];
}

- (void)sendSetAudioMuted:(BOOL)muted {
    NSLog(@"[ExternalAPI] sendSetAudioMuted called, muted=%d", muted);
    NSDictionary *data = @{ @"muted": [NSNumber numberWithBool:muted]};

    // Store as pending so it can be replayed if the JS side misses the event
//    pendingAudioMuted = [NSNumber numberWithBool:muted];

    // In React Native 0.85+ bridgeless mode, self.bridge is always nil.
    // sendEventWithName:body: uses _callableJSModules (set by TurboModule
    // system), NOT self.bridge. Just call it directly.
    [self sendEventWithName:setAudioMutedAction body:data];
//    NSLog(@"[ExternalAPI] sendSetAudioMuted event sent: %@", setAudioMutedAction);

    // Schedule retries — if JS doesn't clear pending, the event was lost
    // (e.g. no listeners registered yet, or _callableJSModules not ready)
//    NSNumber *expectedValue = pendingAudioMuted;
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingAudioMuted != nil && [pendingAudioMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetAudioMuted: retry 1 (0.3s), pending not cleared");
//            [self sendEventWithName:setAudioMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingAudioMuted != nil && [pendingAudioMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetAudioMuted: retry 2 (0.6s), pending not cleared");
//            [self sendEventWithName:setAudioMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingAudioMuted != nil && [pendingAudioMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetAudioMuted: retry 3 (0.9s), pending not cleared");
//            [self sendEventWithName:setAudioMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingAudioMuted != nil && [pendingAudioMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetAudioMuted: retry 4 (1.2s), pending not cleared");
//            [self sendEventWithName:setAudioMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingAudioMuted != nil && [pendingAudioMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetAudioMuted: retry 5 (2s), pending not cleared");
//            [self sendEventWithName:setAudioMutedAction body:data];
//        }
//    });
}

- (void)sendEndpointTextMessage:(NSString*)message :(NSString*)to {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"to"] = to;
    data[@"message"] = message;
    
    [self sendEventWithName:sendEndpointTextMessageAction body:data];
}

- (void)toggleScreenShare:(BOOL)enabled {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"enabled"] = [NSNumber numberWithBool:enabled];
    
    [self sendEventWithName:toggleScreenShareAction body:data];
}

- (void)retrieveParticipantsInfo:(void (^)(NSArray*))completionHandler {
    NSString *completionHandlerId = [[NSUUID UUID] UUIDString];
    NSDictionary *data = @{ @"requestId": completionHandlerId};
    
    [participantInfoCompletionHandlers setObject:[completionHandler copy] forKey:completionHandlerId];
    
    [self sendEventWithName:retrieveParticipantsInfoAction body:data];
}

- (void)openChat:(NSString*)to {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"to"] = to;
    
    [self sendEventWithName:openChatAction body:data];
}

- (void)closeChat {
    [self sendEventWithName:closeChatAction body:nil];
}

- (void)sendChatMessage:(NSString*)message :(NSString*)to {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"to"] = to;
    data[@"message"] = message;
    
    [self sendEventWithName:sendChatMessageAction body:data];
}

- (void)sendSetVideoMuted:(BOOL)muted {
    NSLog(@"[ExternalAPI] sendSetVideoMuted called, muted=%d, externalAPI=%@", muted, self);
    NSDictionary *data = @{ @"muted": [NSNumber numberWithBool:muted]};

    // Store as pending so it can be replayed if the JS side misses the event
//    pendingVideoMuted = [NSNumber numberWithBool:muted];

    // In React Native 0.85+ bridgeless mode, self.bridge is always nil.
    // sendEventWithName:body: uses _callableJSModules (set by TurboModule
    // system), NOT self.bridge. Just call it directly.
    [self sendEventWithName:setVideoMutedAction body:data];
//    NSLog(@"[ExternalAPI] sendSetVideoMuted event sent: %@", setVideoMutedAction);
//
//    // Schedule retries — if JS doesn't clear pending, the event was lost
//    // (e.g. no listeners registered yet, or _callableJSModules not ready)
//    NSNumber *expectedValue = pendingVideoMuted;
//    
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingVideoMuted != nil && [pendingVideoMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetVideoMuted: retry 1 (1s), pending not cleared");
//            [self sendEventWithName:setVideoMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingVideoMuted != nil && [pendingVideoMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetVideoMuted: retry 2 (2s), pending not cleared");
//            [self sendEventWithName:setVideoMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingVideoMuted != nil && [pendingVideoMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetVideoMuted: retry 3 (3s), pending not cleared");
//            [self sendEventWithName:setVideoMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingVideoMuted != nil && [pendingVideoMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetVideoMuted: retry 4 (4s), pending not cleared");
//            [self sendEventWithName:setVideoMutedAction body:data];
//        }
//    });
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        if (pendingVideoMuted != nil && [pendingVideoMuted isEqualToNumber:expectedValue]) {
//            NSLog(@"[ExternalAPI] sendSetVideoMuted: retry 5 (5s), pending not cleared");
//            [self sendEventWithName:setVideoMutedAction body:data];
//        }
//    });
}

- (void)sendSetClosedCaptionsEnabled:(BOOL)enabled {
    NSDictionary *data = @{ @"enabled": [NSNumber numberWithBool:enabled]};

    [self sendEventWithName:setClosedCaptionsEnabledAction body:data];
}

- (void)toggleCamera {
    [self sendEventWithName:toggleCameraAction body:nil];
}

- (void)showNotification:(NSString*)appearance :(NSString*)description :(NSString*)timeout :(NSString*)title :(NSString*)uid {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"appearance"] = appearance;
    data[@"description"] = description;
    data[@"timeout"] = timeout;
    data[@"title"] = title;
    data[@"uid"] = uid;
    
    [self sendEventWithName:showNotificationAction body:data];
}

- (void)hideNotification:(NSString*)uid {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"uid"] = uid;
    
    [self sendEventWithName:hideNotificationAction body:data];
}

- (void)startRecording:(NSString*)mode :(NSString*)dropboxToken :(BOOL)shouldShare :(NSString*)rtmpStreamKey :(NSString*)rtmpBroadcastID :(NSString*)youtubeStreamKey :(NSString*)youtubeBroadcastID :(NSDictionary*)extraMetadata :(BOOL)transcription {
    NSDictionary *data = @{
        @"mode": mode,
        @"dropboxToken": dropboxToken,
        @"shouldShare": @(shouldShare),
        @"rtmpStreamKey": rtmpStreamKey,
        @"rtmpBroadcastID": rtmpBroadcastID,
        @"youtubeStreamKey": youtubeStreamKey,
        @"youtubeBroadcastID": youtubeBroadcastID,
        @"extraMetadata": extraMetadata,
        @"transcription": @(transcription)
    };
    
    [self sendEventWithName:startRecordingAction body:data];
}

- (void)stopRecording:(NSString*)mode :(BOOL)transcription {
    NSDictionary *data = @{
        @"mode": mode,
        @"transcription": @(transcription)
    };
    
    [self sendEventWithName:stopRecordingAction body:data];
}

- (void)overwriteConfig:(NSDictionary*)config {
    NSDictionary *data = @{
        @"config": config
    };

    [self sendEventWithName:overwriteConfigAction body:data];
}

- (void)sendCameraFacingModeMessage:(NSString*)to :(NSString*)facingMode {
    NSDictionary *data = @{
        @"to": to,
        @"facingMode": facingMode
    };
    
    [self sendEventWithName:sendCameraFacingModeMessageAction body:data];
}

- (void)sendSetParticipantViewLayout:(NSString*)participantId frame:(CGRect)frame {
    NSDictionary *data = @{
        @"participantId": participantId,
        @"x": @(frame.origin.x),
        @"y": @(frame.origin.y),
        @"width": @(frame.size.width),
        @"height": @(frame.size.height)
    };

    [self sendEventWithName:setParticipantViewLayoutAction body:data];
}

- (void)sendClearParticipantViewLayout:(NSString*)participantId {
    NSDictionary *data = @{
        @"participantId": participantId
    };

    [self sendEventWithName:setParticipantViewLayoutAction body:data];
}

- (void)sendSetAvatarHidden:(BOOL)hidden {
    pendingAvatarHidden = @(hidden);

    NSDictionary *data = @{ @"hidden": [NSNumber numberWithBool:hidden] };

    [self sendEventWithName:setAvatarHiddenAction body:data];
}

- (void)sendSetAudioDevice:(NSString*)device {
    NSDictionary *data = @{ @"device": device };

    [self sendEventWithName:setAudioDeviceAction body:data];
}
@end
