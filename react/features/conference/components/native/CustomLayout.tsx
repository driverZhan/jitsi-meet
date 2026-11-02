import React, { PureComponent } from 'react';
import {
    FlatList,
    GestureResponderEvent,
    View,
    ViewStyle
} from 'react-native';
import { connect } from 'react-redux';

import { IReduxState, IStore } from '../../../app/types';
import ParticipantView from '../../../base/participants/components/ParticipantView.native';
import { getLocalParticipant } from '../../../base/participants/functions';
import { ILocalParticipant } from '../../../base/participants/types';
import { getHideSelfView } from '../../../base/settings/functions.any';
import { IParticipantViewLayout } from '../../../mobile/external-api/reducer';

/**
 * The type of the React {@code Component} props of {@link CustomLayout}.
 */
interface IProps {

    /**
     * Whether or not to hide the self view.
     */
    _disableSelfView: boolean;

    /**
     * Application's viewport height.
     */
    _height: number;

    /**
     * The local participant.
     */
    _localParticipant?: ILocalParticipant;

    /**
     * An array with the IDs of the remote participants in the conference.
     */
    _remoteParticipants: Array<string>;

    /**
     * Per-participant view layouts (position and size in dp) requested by the
     * native host app via setParticipantViewLayout.
     */
    _viewLayouts: { [participantId: string]: IParticipantViewLayout; };

    /**
     * Application's viewport width.
     */
    _width: number;

    /**
     * Invoked to trigger state changes in Redux.
     */
    dispatch: IStore['dispatch'];

    /**
     * Callback to invoke when the layout is tapped.
     */
    onClick: (e?: GestureResponderEvent) => void;
}

/**
 * An empty array. The purpose of the constant is to use the same reference
 * every time we need an empty array. This will prevent unnecessary re-renders.
 */
const EMPTY_ARRAY: any[] = [];

/**
 * Implements a React {@code PureComponent} which renders participant video
 * views in a minimal grid without the default UI chrome (no Toolbox, Filmstrip,
 * TitleBar, etc.).
 *
 * Each participant view is rendered via {@link ParticipantView}, which sets
 * both {@code nativeID} and {@code testID} to
 * {@code `participant-${participantId}`}. On Android, the host app locates the
 * view via {@code nativeID}; on iOS, {@code testID} maps to
 * {@code accessibilityIdentifier} for recursive view-hierarchy search.
 *
 * The {@code PARTICIPANT_VIEW_READY} event is fired from
 * {@link ParticipantView}'s {@code componentDidMount}, so the host app
 * receives the callback regardless of which layout is active.
 *
 * @augments PureComponent
 */
class CustomLayout extends PureComponent<IProps> {

    /**
     * Creates new CustomLayout component.
     *
     * @param {IProps} props - The props of the component.
     */
    constructor(props: IProps) {
        super(props);

        this._keyExtractor = this._keyExtractor.bind(this);
        this._renderParticipant = this._renderParticipant.bind(this);
    }

    /**
     * Returns a key for a passed item of the list.
     *
     * @param {string} item - The user ID.
     * @returns {string} - The user ID.
     */
    _keyExtractor(item: string) {
        return item;
    }

    /**
     * Returns all participants with the local participant at the beginning.
     *
     * @private
     * @returns {Array<string>}
     */
    _getParticipants() {
        const { _localParticipant, _remoteParticipants, _disableSelfView } = this.props;

        if (!_localParticipant) {
            return EMPTY_ARRAY;
        }

        if (_disableSelfView) {
            return _remoteParticipants;
        }

        return [ _localParticipant.id, ..._remoteParticipants ];
    }

    /**
     * Calculates the number of columns for the grid based on the participant
     * count.
     *
     * @private
     * @returns {number}
     */
    _getColumns() {
        const count = this._getParticipants().length;

        if (count <= 1) {
            return 1;
        }

        if (count <= 4) {
            return 2;
        }

        if (count <= 9) {
            return 3;
        }

        return 4;
    }

    /**
     * Creates React Element to display each participant in the default grid.
     *
     * @private
     * @returns {ReactElement}
     */
    _renderParticipant({ item }: { item: string; }) {
        const { _height, _width } = this.props;
        const columns = this._getColumns();
        const thumbnailWidth = _width / columns;
        const thumbnailHeight = _height / Math.ceil(this._getParticipants().length / columns);
        const avatarSize = 2 * Math.round(Math.min(thumbnailWidth, thumbnailHeight) / 4 / 2);

        console.log(`[CustomLayout] _renderParticipant: ${item}`);

        return (
            <View
                style = {{
                    flex: 1,
                    backgroundColor: '#000000'
                } as ViewStyle}>
                <ParticipantView
                    avatarSize = { avatarSize }
                    onPress = { this.props.onClick }
                    participantId = { item }
                    style = {{ flex: 1 }}
                    useConnectivityInfoLabel = { false }
                    zOrder = { 0 }
                    zoomEnabled = { false } />
            </View>
        );
    }

    /**
     * Creates a React Element for a participant whose view layout (position
     * and size) was explicitly requested by the native host app. The view is
     * absolutely positioned so the host app has full control over it.
     *
     * The structure is a two-level one on purpose:
     * - The outer holder (keyed by viewKey) always stays in the React Native
     *   hierarchy, so the indices of its siblings never change even while the
     *   inner wrapper is reparented into a native container (Fabric mounting
     *   instructions are index based; removing a child from a multi-child
     *   parent shifts the indices of all its siblings and crashes with
     *   "Attempt to unmount a view which has a different index").
     * - The inner wrapper carries the distinct nativeID/testID
     *   ({@code positioned-participant-<viewKey>}) and is the only child of
     *   the holder, so the host app can safely reparent it: the only React
     *   Native operation ever touching the holder's children is the unmount
     *   of this single child, which the native side guards against by
     *   restoring the wrapper first.
     *
     * Both levels set {@code collapsable={false}}: layout-only views are
     * otherwise flattened away by Fabric (they get no native view at all),
     * which would silently make the wrapper a direct native child of some
     * ancestor with many unrelated siblings and reintroduce the index crash.
     *
     * The viewKey (the participant id used in the first
     * setParticipantViewLayout call) is used instead of the current
     * participant id so the wrapper is never remounted when the participant
     * id changes (e.g. on conference join).
     *
     * @param {string} participantId - The participant ID.
     * @param {IParticipantViewLayout} layout - The requested layout in dp.
     * @private
     * @returns {ReactElement}
     */
    _renderPositionedParticipant(participantId: string, layout: IParticipantViewLayout) {
        const avatarSize = 2 * Math.round(Math.min(layout.width, layout.height) / 4 / 2);
        const viewKey = participantId;
        console.log(`[CustomLayout] _renderPositionedParticipant:: ${participantId} viewKey:${layout.viewKey}`);

        return (
            <View
                collapsable = { false }
                key = { viewKey }
                pointerEvents = 'box-none'
                style = {{
                    height: layout.height,
                    left: layout.x,
                    position: 'absolute',
                    top: layout.y,
                    width: layout.width
                } as ViewStyle}>
                <View
                    collapsable = { false }
                    nativeID = { `positioned-participant-${viewKey}` }
                    style = {{
                        backgroundColor: '#000000',
                        flex: 1
                    } as ViewStyle}
                    testID = { `positioned-participant-${viewKey}` }>
                    <ParticipantView
                        avatarSize = { avatarSize }
                        onPress = { this.props.onClick }
                        participantId = { participantId }
                        style = {{ flex: 1 }}
                        useConnectivityInfoLabel = { false }
                        zOrder = { 0 }
                        zoomEnabled = { false } />
                </View>
            </View>
        );
    }

    /**
     * Implements React's {@link Component#render()}.
     *
     * @inheritdoc
     * @returns {ReactElement}
     */
    override render() {
        const { _height, _viewLayouts, _width } = this.props;
        const participants = this._getParticipants();
        const positioned = participants.filter((id: string) => Boolean(_viewLayouts[id]));
        const unpositioned = participants.filter((id: string) => !_viewLayouts[id]);
        const columns = this._getColumns();

        return (
            <View
                style = {{
                    flex: 1,
                    backgroundColor: '#000000',
                    height: _height,
                    width: _width
                } as ViewStyle}>
                { unpositioned.length > 0 && (
                    <FlatList
                        bounces = { false }
                        data = { unpositioned }
                        key = { columns }
                        keyExtractor = { this._keyExtractor }
                        numColumns = { columns }
                        renderItem = { this._renderParticipant }
                        showsHorizontalScrollIndicator = { false }
                        showsVerticalScrollIndicator = { false }
                        style = {{ flex: 1 } as ViewStyle} />
                ) }
                { positioned.map((id: string) => this._renderPositionedParticipant(id, _viewLayouts[id])) }
            </View>
        );
    }
}

/**
 * Maps (parts of) the redux state to the associated {@link CustomLayout}'s
 * props.
 *
 * @param {Object} state - The redux state.
 * @private
 * @returns {IProps}
 */
function _mapStateToProps(state: IReduxState) {
    const responsiveUi = state['features/base/responsive-ui'];
    const { remoteParticipants } = state['features/filmstrip'];
    const { participantViewLayouts } = state['features/mobile/external-api'];

    return {
        _disableSelfView: getHideSelfView(state),
        _height: responsiveUi.clientHeight,
        _localParticipant: getLocalParticipant(state),
        _remoteParticipants: remoteParticipants ?? EMPTY_ARRAY,
        _viewLayouts: participantViewLayouts ?? {},
        _width: responsiveUi.clientWidth
    };
}

export default connect(_mapStateToProps)(CustomLayout);
