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

package org.jitsi.meet.sdk;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.AttributeSet;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;

import com.facebook.react.ReactHost;
import com.facebook.react.runtime.ReactSurfaceImpl;
import com.facebook.react.uimanager.util.ReactFindViewUtil;

import org.jitsi.meet.sdk.log.JitsiMeetLogger;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;


public class JitsiMeetView extends FrameLayout {

    /**
     * Background color. Should match the background color set in JS.
     */
    public static final int BACKGROUND_COLOR = 0xFF040404;

    /**
     * React Native surface.
     */
    private ReactSurfaceImpl reactSurface;

    /**
     * Callback used to deliver the result of an asynchronous participant
     * view lookup.
     */
    public interface ParticipantViewCallback {

        /**
         * Invoked on the main thread with the resolved view, or null if the
         * view could not be found in time.
         */
        void onComplete(@Nullable View view);
    }

    /**
     * Number of lookup attempts before giving up. Native views are mounted
     * asynchronously after the JS commit, so the view may not exist yet when
     * the lookup starts.
     */
    private static final int PARTICIPANT_VIEW_LOOKUP_MAX_ATTEMPTS = 30;

    /**
     * Delay in milliseconds between lookup attempts.
     */
    private static final long PARTICIPANT_VIEW_LOOKUP_RETRY_DELAY_MS = 100;

    /**
     * Participant views detached into native containers, keyed by participant
     * id. Held weakly: React Native still owns the views and may destroy them
     * at any time (e.g. participant left).
     */
    private final Map<String, WeakReference<View>> detachedParticipantViews = new HashMap<>();

    /**
     * The original React Native parents of detached participant views, keyed
     * by participant id, so views can be given back to React Native before
     * they are unmounted.
     */
    private final Map<String, WeakReference<ViewGroup>> detachedParticipantParents = new HashMap<>();

    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    /**
     * Helper method to recursively merge 2 {@link Bundle} objects representing React Native props.
     *
     * @param a - The first {@link Bundle}.
     * @param b - The second {@link Bundle}.
     * @return The merged {@link Bundle} object.
     */
    private static Bundle mergeProps(@Nullable Bundle a, @Nullable Bundle b) {
        Bundle result = new Bundle();

        if (a == null) {
            if (b != null) {
                result.putAll(b);
            }

            return result;
        }

        if (b == null) {
            result.putAll(a);

            return result;
        }

        // Start by putting all of a in the result.
        result.putAll(a);

        // Iterate over each key in b and override if appropriate.
        for (String key : b.keySet()) {
            Object bValue = b.get(key);
            Object aValue = a.get(key);
            String valueType = bValue.getClass().getSimpleName();

            if (valueType.contentEquals("Boolean")) {
                result.putBoolean(key, (Boolean)bValue);
            } else if (valueType.contentEquals("String")) {
                result.putString(key, (String)bValue);
            } else if (valueType.contentEquals("Integer")) {
                result.putInt(key, (int)bValue);
            } else if (valueType.contentEquals("Bundle")) {
                result.putBundle(key, mergeProps((Bundle)aValue, (Bundle)bValue));
            } else if (valueType.contentEquals("String[]")) {
                // Convert String[] to ArrayList<String> for React Native bridge compatibility
                String[] stringArray = (String[]) bValue;
                result.putStringArrayList(key, new ArrayList<>(Arrays.asList(stringArray)));
            } else if (valueType.contentEquals("ArrayList")) {
                result.putParcelableArrayList(key, (ArrayList<Bundle>) bValue);
            } else {
                throw new RuntimeException("Unsupported type: " + valueType);
            }
        }

        return result;
    }

    public JitsiMeetView(@NonNull Context context) {
        super(context);
        initialize(context);
    }

    public JitsiMeetView(Context context, AttributeSet attrs) {
        super(context, attrs);
        initialize(context);
    }

    public JitsiMeetView(Context context, AttributeSet attrs, int defStyle) {
        super(context, attrs, defStyle);
        initialize(context);
    }

    /**
     * Releases the React resources (specifically the {@link ReactSurface})
     * associated with this view.
     *
     * MUST be called when the {@link Activity} holding this view is destroyed,
     * typically in the {@code onDestroy} method.
     */
    public void dispose() {
        if (reactSurface != null) {
            ViewGroup surfaceView = reactSurface.getView();
            if (surfaceView != null) {
                removeView(surfaceView);
            }
            reactSurface.stop();
            reactSurface.detach();
            reactSurface = null;
        }
    }

    /**
     * Enters Picture-In-Picture mode, if possible. This method is designed to
     * be called from the {@code Activity.onUserLeaveHint} method.
     *
     * This is currently not mandatory, but if used will provide automatic
     * handling of the picture in picture mode when user minimizes the app. It
     * will be probably the most useful in case the app is using the welcome
     * page.
     */
    public void enterPictureInPicture() {
        PictureInPictureModule pipModule
            = ReactHostHolder.getNativeModule(
                PictureInPictureModule.class);
        if (pipModule != null
                && pipModule.isPictureInPictureSupported()
                && !JitsiMeetActivityDelegate.arePermissionsBeingRequested()) {
            try {
                pipModule.enterPictureInPicture();
            } catch (RuntimeException re) {
                JitsiMeetLogger.e(re, "Failed to enter PiP mode");
            }
        }
    }

    /**
     * Finds the native view rendering the given participant's video, waiting
     * for it to be mounted if necessary (native views are mounted
     * asynchronously after the JS commit).
     *
     * Do NOT manually reparent or resize the returned view: React Native owns
     * it and will undo such changes. Use
     * {@link #detachParticipantView(String, ViewGroup, ParticipantViewCallback)}
     * to host the view in a native container.
     *
     * @param participantId the participant id, e.g. from the
     * PARTICIPANT_VIEW_READY event.
     * @param callback invoked on the main thread with the view, or null.
     */
    public void findParticipantView(String participantId, ParticipantViewCallback callback) {
        findViewWithNativeId(
            "participant-" + participantId,
            PARTICIPANT_VIEW_LOOKUP_MAX_ATTEMPTS,
            callback);
    }

    /**
     * Detaches a participant's video view from the in-meeting layout and moves
     * it into the given native container.
     *
     * Internally this asks the JavaScript side to render the participant in a
     * standalone wrapper sized like the container (so React Native keeps
     * applying a layout which is correct inside the container), waits for the
     * wrapper to be mounted and then reparents it into the container.
     *
     * Requires the custom-layout.enabled feature flag and a laid out
     * container. If the container is resized, call this method again to update
     * the view's size. Call {@link #reattachParticipantView(String)} before
     * removing the container, and do not keep strong references to the
     * returned view: React Native still owns it and destroys it when the
     * participant leaves.
     *
     * @param participantId the participant id.
     * @param container the native view group which should host the
     * participant view.
     * @param callback invoked on the main thread with the detached view
     * (already added to the container, filling it), or null if the view could
     * not be found in time.
     */
    public void detachParticipantView(
            String participantId, ViewGroup container, ParticipantViewCallback callback) {
        if (!container.isLaidOut()) {
            // The container has no size yet; wait for its first layout pass.
            container.post(() -> detachParticipantView(participantId, container, callback));
            return;
        }

        // 1. Ask the JS side to move this participant into a standalone,
        // absolutely positioned wrapper sized like the container. Using origin
        // (0, 0) means any subsequent React Native layout pass produces a
        // layout which is also correct inside the native container.
        float density = getResources().getDisplayMetrics().density;
        LocalBroadcastManager.getInstance(getContext()).sendBroadcast(
            BroadcastIntentHelper.buildSetParticipantViewLayoutIntent(
                participantId,
                0,
                0,
                container.getWidth() / density,
                container.getHeight() / density));

        // 2. Wait for the wrapper (positioned-participant-<id>) to be mounted,
        // then move it into the native container. The wrapper id is distinct
        // from the grid views so the old grid view can never be picked up.
        findViewWithNativeId(
            "positioned-participant-" + participantId,
            PARTICIPANT_VIEW_LOOKUP_MAX_ATTEMPTS,
            view -> {
                if (view == null) {
                    callback.onComplete(null);
                    return;
                }

                ViewGroup parent = (ViewGroup) view.getParent();

                // Guard: the wrapper must be the only child of its dedicated
                // holder view. If it is not (e.g. the holder got flattened
                // away), reparenting it would shift the mounting indices of
                // unrelated sibling views. Refuse to detach in that case.
                if (parent != null && parent != container && parent.getChildCount() != 1) {
                    JitsiMeetLogger.w(
                        "detachParticipantView: unexpected parent with "
                            + parent.getChildCount() + " children, refusing to detach "
                            + participantId);
                    callback.onComplete(null);
                    return;
                }

                if (parent != container) {
                    // Remember the React Native parent so the view can be
                    // given back before React Native unmounts it.
                    if (parent != null) {
                        detachedParticipantParents.put(participantId, new WeakReference<>(parent));
                        parent.removeView(view);
                    }

                    container.addView(
                        view,
                        new ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT));
                }

                detachedParticipantViews.put(participantId, new WeakReference<>(view));

                callback.onComplete(view);
            });
    }

    /**
     * Returns a participant view previously detached with
     * {@link #detachParticipantView(String, ViewGroup, ParticipantViewCallback)}
     * back to the in-meeting layout (default grid).
     *
     * @param participantId the participant id.
     */
    public void reattachParticipantView(String participantId) {
        WeakReference<View> viewRef = detachedParticipantViews.remove(participantId);
        WeakReference<ViewGroup> parentRef = detachedParticipantParents.remove(participantId);
        View view = viewRef != null ? viewRef.get() : null;
        ViewGroup parent = parentRef != null ? parentRef.get() : null;

        // Give the view back to its React Native parent so the unmount caused
        // by clearing the layout finds the view where React Native expects it.
        if (view != null && parent != null && view.getParent() != parent) {
            ViewGroup current = (ViewGroup) view.getParent();
            if (current != null) {
                current.removeView(view);
            }
            parent.addView(view);
        }

        LocalBroadcastManager.getInstance(getContext()).sendBroadcast(
            BroadcastIntentHelper.buildClearParticipantViewLayoutIntent(participantId));
    }

    /**
     * Recursively searches this view's hierarchy for a view with the given
     * nativeID, retrying on the main thread until found or the attempts are
     * exhausted.
     */
    private void findViewWithNativeId(
            String nativeId, int attempts, ParticipantViewCallback callback) {
        View view = ReactFindViewUtil.findView(this, nativeId);

        if (view != null || attempts <= 1) {
            callback.onComplete(view);
            return;
        }

        mainHandler.postDelayed(
            () -> findViewWithNativeId(nativeId, attempts - 1, callback),
            PARTICIPANT_VIEW_LOOKUP_RETRY_DELAY_MS);
    }

    /**
     * Joins the conference specified by the given {@link JitsiMeetConferenceOptions}. If there is
     * already an active conference, it will be left and the new one will be joined.
     * @param options - Description of what conference must be joined and what options will be used
     *                when doing so.
     */
    public void join(@Nullable JitsiMeetConferenceOptions options) {
        setProps(options != null ? options.asProps() : new Bundle());
    }

    /**
     * Internal method which aborts running RN by passing empty props.
     * This is only meant to be used from the enclosing Activity's onDestroy.
     */
    public void abort() {
        setProps(new Bundle());
    }

    /**
     * Creates the {@link ReactSurface} for the given app name with the given
     * props. Once created its view is set as the child of this {@code FrameLayout}.
     *
     * @param appName - The name of the "app" (in React Native terms) to load.
     * @param props - The React Component props to pass to the app.
     */
    private void createReactRootView(String appName, @Nullable Bundle props) {
        if (props == null) {
            props = new Bundle();
        }

        ReactHost reactHost = ReactHostHolder.getReactHost();
        if (reactHost == null) {
            JitsiMeetLogger.w("Cannot create surface, ReactHost is not initialized");
            return;
        }

        if (reactSurface == null) {
            reactSurface = (ReactSurfaceImpl) reactHost.createSurface(getContext(), appName, props);

            ViewGroup surfaceView = reactSurface.getView();
            if (surfaceView != null) {
                surfaceView.setBackgroundColor(BACKGROUND_COLOR);
                addView(surfaceView);
            }

            reactSurface.start();
        } else {
            reactSurface.updateInitProps(props);
        }
    }

    private void initialize(@NonNull Context context) {
        // Check if the parent Activity implements JitsiMeetActivityInterface,
        // otherwise things may go wrong.
        if (!(context instanceof JitsiMeetActivityInterface)) {
            throw new RuntimeException("Enclosing Activity must implement JitsiMeetActivityInterface");
        }

        setBackgroundColor(BACKGROUND_COLOR);
    }

    /**
     * Helper method to set the React Native props.
     * @param newProps - New props to be set on the React Native view.
     */
    private void setProps(@NonNull Bundle newProps) {
        // Merge the default options with the newly provided ones.
        Bundle props = mergeProps(JitsiMeet.getDefaultProps(), newProps);

        // XXX The setProps() method is supposed to be imperative i.e.
        // a second invocation with one and the same URL is expected to join
        // the respective conference again if the first invocation was followed
        // by leaving the conference. However, React and, respectively,
        // appProperties/initialProperties are declarative expressions i.e. one
        // and the same URL will not trigger an automatic re-render in the
        // JavaScript source code. The workaround implemented below introduces
        // "imperativeness" in React Component props by defining a unique value
        // per setProps() invocation.
        props.putLong("timestamp", System.currentTimeMillis());

        createReactRootView("App", props);
    }

    @Override
    protected void onDetachedFromWindow() {
        dispose();
        super.onDetachedFromWindow();
    }
}
