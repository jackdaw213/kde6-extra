/// Ideas:
/// - refactor all complex height/width calculations to use simple 12x12 virtual grid
/// - "skip layout" button, which would allow to skip to next assist position from the quatersToShowNext
/// - support for Krunner text field to launch new apps
/// - restore previous size on un-snapping of programatically snapped window
/// - create task switcher widget which will visually show windows tiled using this assist, allowing to minimize/restore them at once
///
/// Plasma 6 port changes:
/// - unversioned Qt 6 / Plasma 6 imports; `org.kde.kwin` provides the KWinComponents types
///   and the `Workspace` singleton (the lowercase `workspace` / `options` context
///   properties of Plasma 5 are gone)
/// - `workspace.clients` -> `Workspace.stackingOrder`
/// - workspace signals renamed: onClientActivated -> onWindowActivated, onClientAdded -> onWindowAdded
/// - onClientFullScreenSet is gone; fullscreen handling moved to per-window
///   fullScreenChanged listeners (see windows.js)
/// - config reload Connections on `options` is gone (there is no options object in
///   declarative scripts); configs are re-read each time the assist is shown instead
/// - KWinComponents.ThumbnailItem -> KWinComponents.WindowThumbnail (wId takes the
///   window's internalId QUuid now)
/// - PlasmaCore.IconItem -> Kirigami.Icon
/// - QtGraphicalEffects -> QtQuick.Effects (MultiEffect) in DesktopBackground.qml

import QtQuick
/// aliased: KWin's org.kde.kwin module exports an uncreatable `Window` type
/// which would shadow QtQuick.Window's Window when imported unqualified
import QtQuick.Window as QuickWindow
import QtQuick.Controls
/// double import: the unaliased import provides the `Workspace` singleton
/// (also resolvable from the imported .js files), the aliased one provides
/// the KWinComponents QML types (WindowThumbnail, DesktopBackground)
import org.kde.kwin
import org.kde.kwin as KWinComponents
import QtQml.Models
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "components"
import "../code/assist.js" as AssistManager
import "../code/keyboard.js" as KeyboardManager
import "../code/windows.js" as WindowManager

QuickWindow.Window {
    id: mainWindow
    /// Qt.Popup is required for the assist window to receive keyboard input on
    /// Wayland (without it keys go to the focused app). kwin's popup filter
    /// force-dismisses popups on outside clicks; the onVisibleChanged handler
    /// below recovers the script state when that happens.
    flags: Qt.FramelessWindowHint | Qt.X11BypassWindowManagerHint | Qt.WindowStaysOnTopHint | Qt.Popup
    /// unique caption: lets the JS side identify the assist's KWin::Window object
    /// (the QML id is a different wrapper object and cannot be compared)
    title: "kde-snap-assist-overlay"
    visible: true
    color: "transparent"
    x: mainWindow.width * 2
    y: mainWindow.height * 2
    height: 1
    width: 1

    /// recover when the window is closed by the compositor (or otherwise hidden)
    /// while the assist is logically open — otherwise `activated` stays true and
    /// the assist stops showing until the next successful close
    onVisibleChanged: {
        if (!visible && activated) AssistManager.hideAssist(true);
    }

    /// service variables
    property bool activated: false
    property var clients: null
    property var lastActiveClient: null /// last active client to focus if cancelled
    property int focusedIndex: 0 /// selection by keyboard
    property bool trackActiveWindows: true
    property var activationTime: ({}) /// store timestamps of last window's activation
    property var windowSizesBeforeSnap: ({}) /// store widnow sizes before they were snapped via script (when rememberWindowSizes is on)
    property int cardHeight: 220 /// calculated dynamically before assist reveal
    property int cardWidth: 370
    property int columnsCount: 2 /// calculated depending on available width
    property int gridSpacing: 25 /// maybe should be configurable?
    property bool cycleKeyboard: false /// not in use
    property bool preventFromShowing: false /// flag used to temporarly prevent assist from showing when not desired

    /// for tracking snapped windows
    property bool trackSnappedWindows: true
    property var snappedWindowGroups: ([]) /// store snapped windows in groups
    property var snappedWindows: ([]) /// temporarly store windows which will be added in group on finish
    property bool ignoreFocusChange: false /// prevent endless loop for raiseSnappedTogether

    /// for quater tiling
    property var quatersToShowNext: ({}) /// store next quaters to show assist after selection
    property var filteredClients: ([]) /// clients to filter (which are already snapped in current flow)
    property var filteredQuaters: ([]) /// quaters to ignore during iteration (occupied by big window)
    property real currentScreenWidth: 1
    property real currentScreenHeight: 1
    property real minDx: 0 /// store the real "0" dx coordinate
    property real minDy: 0
    property int assistPadding: 0  /// padding to add around assist (not applied to windows)
    property int layoutMode: 0 /// 0 - horizontal halve, 1 - quater, 2 - vertical halve
    property var storedQuaterPosition: ({}) /// store initial quater position for Tab button switching
    property var storedFirstQuaterToShow: ({}) /// store planned first quater for Tab button switching
    property var assistSourceWindow: null /// window the currently open assist was shown for

    /// aliases exposing child ids as real root properties: QML ids are NOT root
    /// properties, so the scope-isolated JS modules must reach them this way
    property alias keyboardHandlerRef: keyboardHandler
    property alias fadeInAnimationRef: fadeInAnimation
    property alias scrollViewRef: scrollView
    property alias clientsRepeaterRef: clientsRepeater
    /// true while the script itself changes the assist window's geometry
    /// (show/hide), so self-inflicted geometry changes are not misread as
    /// user-initiated quick-tiling of the assist window
    property bool programmaticAssistGeometry: false
    property int assistEpoch: 0 /// incremented on close; invalidates pending show timers

    /// configurable
    property int transitionDuration
    property color cardColor
    property color hoveredCardColor
    property color backdropColor
    property color textColor
    property int borderRadius
    property bool sortByLastActive
    property bool showMinimizedWindows
    property bool showOtherScreensWindows
    property bool showOtherDesktopsWindows
    property bool descendingOrder
    property int snapDetectPrecision
    property int delayBeforeShowingAssist
    property bool showSnappedWindows
    property bool minimizeSnappedTogether
    property bool raiseSnappedTogether
    property bool fillOnSnappedClose
    property bool fillOnSnappedMove
    property int fitWindowInGroupBehind
    property bool rememberWindowSizes
    property bool showDesktopBackground
    property int desktopBackgroundBlur

    Connections {
        target: Workspace
        function onWindowActivated(window) {
            if (!window) return;
            WindowManager.handleWindowFocus(window);
        }
        function onWindowAdded(window) {
            WindowManager.addListenersToClient(window);
        }
        function onVirtualScreenSizeChanged(){
            /// Fix for assist getting shown when screen size changed
            AssistManager.preventAssistFromShowing(1000, () => AssistManager.hideAssist(false));
        }
    }

    Component.onCompleted: {
        AssistManager.init(mainWindow, WindowManager);
        KeyboardManager.init(mainWindow);
        WindowManager.init(mainWindow, AssistManager);
        loadConfigs();
        const windows = Workspace.stackingOrder;
        for (let i = 0; i < windows.length; ++i) {
            WindowManager.addListenersToClient(windows[i]);
        }

        mainWindow.hide();
    }

    /// Desktop preview on background with blur
    Loader {
        source: showDesktopBackground ? 'components/DesktopBackground.qml' : ''
    }

    /// Main view
    Rectangle {
        id: assistBackground
        width: mainWindow.width
        height: mainWindow.height
        color: backdropColor

        /// fade-in animation on appear
        NumberAnimation on opacity {
            id: fadeInAnimation
            from: 0
            to: 1
            duration: transitionDuration
        }

        /// click on empty space to close
        MouseArea {
            anchors.fill: parent
            onClicked: {  if (activated) AssistManager.hideAssist(true); }
        }

        ScrollView {
            id: scrollView
            anchors.centerIn: parent
            height: gridView.height > mainWindow.height * 0.95 ? mainWindow.height * 0.95 : gridView.height
            width: columnsCount * (cardWidth + gridSpacing)

            Grid {
                id: gridView
                columns: columnsCount
                spacing: gridSpacing
                anchors.centerIn: parent

                Repeater {
                    id: clientsRepeater
                    model: clients

                        Rectangle {
                            id: clientItem
                            color: cardColor
                            radius: borderRadius
                            width:  cardWidth
                            height: cardHeight
                            border.color: activePalette.highlight
                            border.width: focusedIndex == index ? 3 : 0
                            visible: true

                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter

                                Rectangle {
                                    height: 8
                                    width: 12
                                    color: "transparent"
                                }

                                /// window title and icon
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    bottomPadding: 8
                                    width: cardWidth - 10

                                    Rectangle {
                                        height: 8
                                        width: 15
                                        color: "transparent"
                                    }

                                    Kirigami.Icon {
                                        id: icon
                                        height: 12
                                        width: 12
                                        source: modelData.icon
                                    }

                                    Text {
                                        text: modelData.caption
                                        leftPadding: 7
                                        color: textColor
                                        elide: Text.ElideRight
                                        width: parent.width - 26
                                    }
                                }

                                /// window thumbnail
                                KWinComponents.WindowThumbnail {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    id: clientThumbnail
                                    wId: modelData.internalId
                                    clip: true
                                    visible: mainWindow.activated
                                    width: cardWidth - 6
                                    height: cardHeight - 40
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    clientItem.color = hoveredCardColor;
                                }
                                onExited: {
                                    clientItem.color = cardColor;
                                }
                                onClicked: {
                                    WindowManager.selectClient(modelData);
                                }
                            }
                        }
                    }
            }
        }
    }

    /// Close assist button
    CornerButton {
        id: closeButton
        y: 20
        icon.name: "window-close"
        ToolTip.text: qsTr("Close snap assist")
        onClicked: AssistManager.hideAssist(true);
    }

    /// Change layout button
    CornerButton {
        id: changeSizeButton
        y: 60

        Image {
            anchors.centerIn: parent
            source: mainWindow.height == currentScreenHeight && mainWindow.width == currentScreenWidth / 2 ?
                        "icons/vertical-half.svg"
                        : mainWindow.width == currentScreenWidth ?
                            "icons/horizontal-half.svg"
                            : mainWindow.width == currentScreenWidth / 3 ?
                                "icons/three-in-row.svg"
                                : mainWindow.width == currentScreenWidth / 3 * 2 ?
                                    "icons/65-35.svg"
                                    : "icons/quarter.svg"
            sourceSize.width: parent.width - 8
            sourceSize.height: parent.height - 8
            cache: true
            opacity: 0.85
        }

        ToolTip.text: qsTr("Change layout")
        onClicked: AssistManager.switchAssistLayout();
    }

    /// Timer factory for delayed calls.
    /// Each call gets its OWN Timer object: sharing a single Timer (as the Plasma 5
    /// version did) made concurrent delays (e.g. preventAssistFromShowing 300ms vs
    /// assist reveal 3ms) overwrite each other's intervals and fire callbacks early.
    function setTimeout(cb, delayTime) {
        const t = Qt.createQmlObject("import QtQuick; Timer { }", mainWindow);
        t.interval = delayTime;
        t.repeat = false;
        t.triggered.connect(function release() {
            t.triggered.disconnect(release);
            Qt.callLater(function() { t.destroy(); });
            cb();
        });
        t.start();
        return t;
    }

    /// Reference for current theme's highlight color
    SystemPalette {
        id: activePalette
        colorGroup: SystemPalette.Active
    }

    /// Keyboard handler
    Item {
        anchors.fill: parent
        id: keyboardHandler
        Keys.onPressed: function(event) {
            if (activated == false) return;

            /// super+arrow while the assist is open: quick-tile the window the
            /// assist was shown for (kwin's own shortcut targets the focused
            /// assist window and does nothing)
            if (event.modifiers & Qt.MetaModifier) {
                switch (event.key) {
                case Qt.Key_Left:
                    if (WindowManager.tileSourceWindow("left")) return;
                    break;
                case Qt.Key_Right:
                    if (WindowManager.tileSourceWindow("right")) return;
                    break;
                case Qt.Key_Up:
                    if (WindowManager.tileSourceWindow("up")) return;
                    break;
                case Qt.Key_Down:
                    if (WindowManager.tileSourceWindow("down")) return;
                    break;
                }
            }

               switch (event.key) {
                case Qt.Key_Escape:
                    AssistManager.hideAssist(true);
                    break;
                case Qt.Key_Left:
                    KeyboardManager.moveFocusLeft();
                    break;
                case Qt.Key_Right:
                    KeyboardManager.moveFocusRight();
                    break;
                case Qt.Key_Up:
                    KeyboardManager.moveFocusUp();
                    break;
                case Qt.Key_Down:
                    KeyboardManager.moveFocusDown();
                    break;
                case Qt.Key_Return:
                    WindowManager.selectClient(clients[focusedIndex]);
                    break;
                case Qt.Key_Tab:
                    AssistManager.switchAssistLayout();
                    break;
                }
        }
    }

    function loadConfigs() {
        sortByLastActive = KWin.readConfig("sortByLastActive", true);
        descendingOrder = KWin.readConfig("descendingOrder", true);
        showMinimizedWindows = KWin.readConfig("showMinimizedWindows", true);
        showOtherScreensWindows = KWin.readConfig("showOtherScreensWindows", false);
        showOtherDesktopsWindows = KWin.readConfig("showOtherDesktopsWindows", false);
        textColor = KWin.readConfig("textColor", "#ffffff");
        cardColor = KWin.readConfig("cardColor", "#75475057");
        hoveredCardColor = KWin.readConfig("hoveredCardColor", "#75d9dde1");
        backdropColor = KWin.readConfig("backdropColor", "#902a2e32");
        borderRadius = KWin.readConfig("borderRadius", 5);
        transitionDuration = KWin.readConfig("transitionDuration", 150);
        snapDetectPrecision = KWin.readConfig("snapDetectPrecision", 0);
        delayBeforeShowingAssist = KWin.readConfig("delayBeforeShowingAssist", 100);
        rememberWindowSizes = KWin.readConfig("rememberWindowSizes", true);
        showSnappedWindows = KWin.readConfig("showSnappedWindows", true);
        minimizeSnappedTogether = KWin.readConfig("minimizeSnappedTogether", false);
        raiseSnappedTogether = KWin.readConfig("raiseSnappedTogether", false);
        fillOnSnappedClose = KWin.readConfig("fillOnSnappedClose", false);
        fillOnSnappedMove = KWin.readConfig("fillOnSnappedMove", false);
        fitWindowInGroupBehind = KWin.readConfig("fitWindowInGroupBehind", false);
        showDesktopBackground = KWin.readConfig("showDesktopBackground", true);
        desktopBackgroundBlur = KWin.readConfig("desktopBackgroundBlur", 32);
        trackSnappedWindows = minimizeSnappedTogether || raiseSnappedTogether || fillOnSnappedClose || !showSnappedWindows;
        trackActiveWindows = sortByLastActive || fitWindowInGroupBehind;

        /// workaround for configs bug, when boolean gets stored for string values
        if (textColor == false) textColor = "#ffffff";
        if (cardColor == false) cardColor = "#75475057";
        if (hoveredCardColor == false) hoveredCardColor = "#75d9dde1";
        if (backdropColor == false) backdropColor = "#902a2e32";
    }
}
