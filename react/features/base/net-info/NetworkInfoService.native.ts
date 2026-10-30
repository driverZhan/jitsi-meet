import {
    default as NetInfo,
    type NetInfoState,
    type NetInfoSubscription
} from '@react-native-community/netinfo';
// eslint-disable-next-line lines-around-comment
// @ts-ignore
import EventEmitter from 'events';

import { ONLINE_STATE_CHANGED_EVENT } from './events';
import type { NetworkInfo } from './types';

/**
 * The network info service implementation for iOS and Android. 'react-native-netinfo' seems to support windows as well,
 * but that has not been tested and is nto used by jitsi-meet.
 */
export default class NetworkInfoService extends EventEmitter {
    /**
     * Stores the native subscription for future cleanup.
     */
    _subscription?: NetInfoSubscription;

    /**
     * Timer used to debounce network state changes. When switching between
     * network types (e.g. WiFi to cellular), the OS may report transient
     * offline states. The debounce prevents tearing down the connection
     * during brief network transitions.
     */
    _debounceTimer?: ReturnType<typeof setTimeout>;

    /**
     * The debounce delay in milliseconds. This should be long enough to
     * cover typical network switch times (WiFi → cellular can take 2-5s).
     */
    static _DEBOUNCE_DELAY = 5000;

    /**
     * Converts library's structure to {@link NetworkInfo} used by jitsi-meet.
     *
     * @param {NetInfoState} netInfoState - The new state given by the native library.
     * @private
     * @returns {NetworkInfo}
     */
    static _convertNetInfoState(netInfoState: NetInfoState): NetworkInfo {
        return {
            // Treat null (still checking) as online to avoid premature disconnect.
            // Only treat explicit false as offline.
            isOnline: netInfoState.isInternetReachable !== false,

            details: netInfoState.details,
            networkType: netInfoState.type
        };
    }

    /**
     * Checks for support.
     *
     * @returns {boolean}
     */
    static isSupported() {
        return Boolean(NetInfo);
    }

    /**
     * Starts the service.
     *
     * @returns {void}
     */
    start() {
        this._subscription = NetInfo.addEventListener(netInfoState => {
            const networkInfo = NetworkInfoService._convertNetInfoState(netInfoState);

            // Debounce the event emission to avoid rapid state flips during
            // network transitions (e.g. WiFi to 5G cellular switch).
            if (this._debounceTimer) {
                clearTimeout(this._debounceTimer);
            }

            this._debounceTimer = setTimeout(() => {
                this._debounceTimer = undefined;
                super.emit(ONLINE_STATE_CHANGED_EVENT, networkInfo);
            }, NetworkInfoService._DEBOUNCE_DELAY);
        });
    }

    /**
     * Stops the service.
     *
     * @returns {void}
     */
    stop() {
        if (this._subscription) {
            this._subscription();
            this._subscription = undefined;
        }
        if (this._debounceTimer) {
            clearTimeout(this._debounceTimer);
            this._debounceTimer = undefined;
        }
    }
}
