/// module state: set by init() from main.qml (see comments there)
var _root = null;
var _wm = null;

/// called from main.qml Component.onCompleted.
/// _root: the main.qml root object (all shared state lives on it).
/// _wm: the WindowManager module (windows.js).
function init(root, windowManager) {
    _root = root;
    _wm = windowManager;
}

/// assist
/// Ported to KWin 6 / Plasma 6 scripting API:
/// - `workspace.clients` -> `Workspace.stackingOrder`
/// - `workspace.activeClient` -> `Workspace.activeWindow`
/// - `workspace.activeScreen` -> `Workspace.activeScreen` (now a LogicalOutput object)
/// - internalId is normalized to string via windows.js windowId()
/// The desktop background preview is rendered directly by the
/// KWinComponents.DesktopBackground QML component now, so the manual
/// desktop-window lookup of the Plasma 5 version is gone.

function delayedShowAssist(dx, dy, height, width, window){
    /// config reload: there is no `options` object in declarative scripts on
    /// Plasma 6, so configs are read lazily each time the assist is shown
    _root.loadConfigs();

    const allWindows = Workspace.stackingOrder;
    _root.clients = allWindows.filter(c => _wm.shouldShowWindow(c));
    if (_root.clients.length == 0) return;

    _root.cardWidth = _root.currentScreenWidth / 5;
    _root.cardHeight = _root.cardWidth / 1.68;
    _root.lastActiveClient = Workspace.activeWindow;

    const epoch = _root.assistEpoch;
    _root.setTimeout(function(){
        if (epoch !== _root.assistEpoch) return; /// assist was closed meanwhile
        const w = window ?? Workspace.activeWindow;
        if (w) _root.snappedWindows.push(_wm.windowId(w));
        _root.requestActivate();
        _root.keyboardHandlerRef.forceActiveFocus();
        showAssist(dx, dy, height ?? _root.currentScreenHeight, width ?? _root.currentScreenWidth - window.width);
    }, 3);

    /// Reorderings MUST assign a NEW array: `.sort()`/`.reverse()` mutate in place
    /// and return the same reference, and writing the same reference to a
    /// `property var` fires no change notification — the cards would then stay in
    /// the old order while keyboard selection indexes the new one, so Enter snaps
    /// a different window than the highlighted card
    if (_root.sortByLastActive) {
        _root.clients = _root.clients.slice().sort(function(a, b) {
            const windowIdA = _wm.windowId(a), windowIdB = _wm.windowId(b);
            if (_root.activationTime[windowIdA] && !_root.activationTime[windowIdB]) return 1;
            if (!_root.activationTime[windowIdA] && _root.activationTime[windowIdB]) return -1;
            return _root.activationTime[windowIdA] - _root.activationTime[windowIdB];
        });
    }
    if (_root.descendingOrder) _root.clients = _root.clients.slice().reverse();

    /// remember which window this assist was shown for, so it can follow the
    /// window when it gets re-snapped to another region while the assist is open
    _root.assistSourceWindow = window ?? null;
}

function showAssist(dx, dy, height, width) {
    _root.activated = true;
    _root.focusedIndex = 0;
    _root.programmaticAssistGeometry = true;
    _root.showNormal();
    _root.width = width;
    _root.height = height;
    _root.x = dx;
    _root.y = dy;
    /// keep kwin's own quick-tile shortcut (super+arrow) targeting the source
    /// window while the assist holds the keyboard grab: with the source left as
    /// the active window, super+arrow tiles it and the assist follows via the
    /// geometry-change logic. The assist window keeps keyboard input (popup grab).
    if (_root.assistSourceWindow && !_root.assistSourceWindow.deleted) {
        Workspace.activeWindow = _root.assistSourceWindow;
    }
    _root.setTimeout(function(){ _root.programmaticAssistGeometry = false; }, 80);
    _root.fadeInAnimationRef.restart();
    _root.scrollViewRef.ScrollBar.vertical.position = 0;
}

function preventAssistFromShowing(delay, callback){
    _root.preventFromShowing = true;
    _root.setTimeout(function(){
        _root.preventFromShowing = false;
        if (callback) callback();
    }, delay ?? 300);
}

function hideAssist(shouldFocusLastClient) {
    console.warn("[SnapAssist] hide assist (focusLast:", shouldFocusLastClient + ")");
    _root.activated = false;
    _root.assistEpoch++; /// invalidate pending show timers
    _root.programmaticAssistGeometry = true;
    _root.x = _root.width * 2;
    _root.y = _root.height * 2;
    _root.width = 0;
    _root.height = 0;
    _root.setTimeout(function(){ _root.programmaticAssistGeometry = false; }, 80);

    /// gets called when assist closed without selecting item
    if (shouldFocusLastClient == true) {
        if (_root.lastActiveClient) Workspace.activeWindow = _root.lastActiveClient;
        finishSnap(true);
    }
}

function finishSnap(success){
    /// gets called when close assist, and no other assists awaiting to show
    if (success == true && _root.trackSnappedWindows && _root.snappedWindows.length > 1) {
        /// store snapped windows
        const d = new Date();
        _root.snappedWindowGroups.push({
            timestamp: d.getTime(),
            windows: _root.snappedWindows
        });
    }

    _root.filteredClients = [];
    _root.filteredQuaters = [];
    _root.snappedWindows = [];
    _root.quatersToShowNext = {};
    _root.lastActiveClient = null;
}


/// for quater tiling
function checkToShowNextQuaterAssist(lastSelectedClient){
    const keys = Object.keys(_root.quatersToShowNext).filter(quaterIndex => !_root.filteredQuaters.includes(parseInt(quaterIndex)));
    const l = keys.length;

    if (l > 0) {
        /// need to show assist in other quaters
        if (lastSelectedClient) _root.filteredClients.push(lastSelectedClient);
        const nextQuater = _root.quatersToShowNext[keys[0]];
        delete _root.quatersToShowNext[keys[0]];
        if (_root.layoutMode !== 3) _root.columnsCount = 2;
        delayedShowAssist(nextQuater.dx + (_root.assistPadding / 2), nextQuater.dy + (_root.assistPadding / 2), nextQuater.height - _root.assistPadding, nextQuater.width - _root.assistPadding);
        if (lastSelectedClient) _root.lastActiveClient = lastSelectedClient;
        return true;
    } else {
        /// no other quaters to show assist — we can reset the variables
        preventAssistFromShowing();
        hideAssist(false);
        finishSnap(true);
        return false;
    }
}

function switchAssistLayout() {
    if (!_root.activated) return;
    const halfScreenWidth = _root.currentScreenWidth / 2, halfScreenHeight = _root.currentScreenHeight / 2;

    if (_root.layoutMode == 0) {
        /// horizontal halve
        if (_wm.isEqual(_root.height, _root.currentScreenHeight)) {
            /// reduce to quater
            _root.height /= 2;
            if (_root.y !== _root.minDy) _root.y = _root.minDy;
            _root.quatersToShowNext[0] = {dx: _root.x, dy: _root.minDy + halfScreenHeight, height: _root.height, width: _root.width};
        } else if (_wm.isEqual(_root.height, halfScreenHeight)) {
            if (_wm.isEqual(_root.y, _root.minDy)) {
                /// already shown in top quater, move to the bottom quater
                _root.y = _root.minDy + halfScreenHeight;
                _root.quatersToShowNext[0] = {dx: _root.x, dy: _root.minDy, height: _root.height, width: _root.width};
            } else {
                /// return to initial position
                _root.height *= 2;
                if (_root.y !== _root.minDy) _root.y = _root.minDy;
                delete _root.quatersToShowNext[0];
            }
        }
    } else if (_root.layoutMode == 2) {
        /// vertical halve
        if (_wm.isEqual(_root.width, _root.currentScreenWidth)) {
            /// reduce to quater
            _root.width /= 2;
            _root.columnsCount = 2;
            if (_root.x !== _root.minDx) _root.x = _root.minDx;
            _root.quatersToShowNext[0] = {dx: _root.minDx + halfScreenWidth, dy: _root.y, height: _root.height, width: _root.width};
        } else if (_wm.isEqual(_root.width, halfScreenWidth)) {
            if (_wm.isEqual(_root.x, _root.minDx)) {
                /// already shown in left quater, move to the right quater
                _root.x = _root.minDx + halfScreenWidth;
                _root.quatersToShowNext[0] = {dx: _root.minDx, dy: _root.y, height: _root.height, width: _root.width};
            } else {
                /// return to initial position
                _root.width *= 2;
                _root.columnsCount = 3;
                if (_root.x !== _root.minDx) _root.x = _root.minDx;
                delete _root.quatersToShowNext[0];
            }
        }
    } else if (_root.layoutMode == 1) {
        /// quater
        if (_wm.isEqual(_root.height, halfScreenHeight) && _wm.isEqual(_root.width, halfScreenWidth)) {
            /// store quater's position - to return to in the end of cycle
            _root.storedQuaterPosition.dx = _root.x; _root.storedQuaterPosition.dy = _root.y;
            _root.storedFirstQuaterToShow = _root.quatersToShowNext[0];

            /// make horizontal halve
            _root.height = _root.currentScreenHeight;
            if (_root.y !== _root.minDy) _root.y = _root.minDy;
            _root.columnsCount = 2;
            if (!_root.lastActiveClient) return; /// null guard: source can be gone mid-flow
            if (_wm.isEqual(_root.lastActiveClient.x, _root.minDx)) {
                /// show on the right
                _root.x = _root.minDx + halfScreenWidth;
                _root.filteredQuaters = [1, 3];

                /// special handling to show assist again for newly appeared free quater
                if (_wm.isEqual(_root.lastActiveClient.y, _root.minDy + halfScreenHeight))
                    _root.quatersToShowNext[0] = {dx: _root.minDx, dy: _root.minDy, height: halfScreenHeight, width: halfScreenWidth};
            } else {
                /// show on the left
                _root.x = _root.minDx;
                _root.filteredQuaters = [0, 2];
            }
        } else if (_wm.isEqual(_root.height, _root.currentScreenHeight)) {
            /// make vertical halve
            _root.height = halfScreenHeight;
            _root.width = _root.currentScreenWidth;
            if (_root.x !== _root.minDx) _root.x = _root.minDx;
            _root.columnsCount = 3;
            if (!_root.lastActiveClient) return;
            if (_wm.isEqual(_root.lastActiveClient.y, _root.minDy)) {
                /// show in bottom
                _root.y = _root.minDy + halfScreenHeight;
                _root.filteredQuaters = [2, 3];

                /// special handling to show assist again for newly appeared free quater
                if (_wm.isEqual(_root.lastActiveClient.x, _root.minDx + halfScreenWidth))
                    _root.quatersToShowNext[0] = {dx: _root.minDx, dy: _root.minDy, height: halfScreenHeight, width: halfScreenWidth};
                else if (_wm.isEqual(_root.lastActiveClient.x, _root.minDx))
                    _root.quatersToShowNext[0] = {dx: _root.minDx + halfScreenWidth, dy: _root.minDy, height: halfScreenHeight, width: halfScreenWidth};
            } else {
                /// show on top
                _root.y = _root.minDy;
                _root.filteredQuaters = [0, 1];
            }
        } else {
            /// return to initial position
            _root.width /= 2;
            _root.x = _root.storedQuaterPosition.dx; _root.y = _root.storedQuaterPosition.dy;
            _root.columnsCount = 2;
            _root.filteredQuaters = [];
            _root.quatersToShowNext[0] = _root.storedFirstQuaterToShow;
        }
    } else if (_root.layoutMode == 3) {
        /// three-in-a-row layout
        const thirdOfScreenWidth = _root.currentScreenWidth / 3;

        if (_root.lastActiveClient.x == _root.minDx + thirdOfScreenWidth) {
            /// snapped window in the center
            if (_wm.isEqual(_root.x, _root.minDx)) {
                /// move third to right
                _root.x = _root.minDx + (thirdOfScreenWidth * 2);
                _root.filteredQuaters = [2];
                _root.quatersToShowNext[0] = {dx: _root.minDx, dy: _root.minDy, height: _root.currentScreenHeight, width: thirdOfScreenWidth};
            } else {
                /// move third to left
                _root.x = _root.minDx;
                _root.filteredQuaters = [];
                delete _root.quatersToShowNext[0];
            }
        } else {
            /// snapped window on the side
            if (_wm.isEqual(_root.width, thirdOfScreenWidth)) {
                /// expand to take two thirds
                _root.storedQuaterPosition.dx = _root.x;
                _root.width = thirdOfScreenWidth * 2;
                _root.columnsCount = 2;
                _root.filteredQuaters = _wm.isEqual(_root.x, _root.minDx) ? [1] : [2];

            } else if (_wm.isEqual(_root.height, _root.currentScreenHeight / 2)) {
                /// return to initial position
                _root.width = thirdOfScreenWidth;
                _root.height = _root.currentScreenHeight;
                _root.x = _root.storedQuaterPosition.dx;
                _root.columnsCount = 1;
                _root.filteredQuaters = [];
                delete _root.quatersToShowNext[0];

            } else if (_wm.isEqual(_root.width, thirdOfScreenWidth * 2)) {
                /// show vertically
                _root.height = _root.currentScreenHeight / 2;
                _root.filteredQuaters = [1, 2];
                _root.quatersToShowNext[0] = {dx: _root.x, dy: _root.minDy + (_root.currentScreenHeight / 2), height: _root.currentScreenHeight / 2, width: _root.width};
            }
        }
    }
}
