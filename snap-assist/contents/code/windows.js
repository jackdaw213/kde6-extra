/// module state: set by init() from main.qml (see comments there)
var _root = null;
var _assist = null;

/// called from main.qml Component.onCompleted.
/// _root: the main.qml root object (all shared state lives on it).
/// _assist: the AssistManager module (assist.js).
function init(root, assistManager) {
    _root = root;
    _assist = assistManager;
}

/// Window management logic.
/// Ported to the KWin 6 / Plasma 6 scripting API:
/// - `workspace.clients`  -> `Workspace.stackingOrder`
/// - `workspace.activeClient` -> `Workspace.activeWindow`
/// - `workspace.clientArea(KWin.MaximizeArea, w)` -> `Workspace.clientArea(MAXIMIZE_AREA, w)`
///   (the KWin enum object is not reachable from declarative scripts, so the
///   numeric value from KWin's ClientAreaOption is used: MaximizeArea == 2)
/// - client signals renamed: clientStartUserMovedResized -> interactiveMoveResizeStarted,
///   clientFinishUserMovedResized -> interactiveMoveResizeFinished,
///   clientMinimized/clientUnminimized -> minimizedChanged,
///   windowClosed -> closed, desktopChanged -> desktopsChanged
/// - `client.desktop` (int) -> `client.desktops` (list of VirtualDesktop objects)
/// - `client.screen` (int) -> `client.output` (LogicalOutput object)
/// - `client.internalId` is a QUuid now: it is always normalized to a string
///   (via windowId()) before it is stored or compared, because QUuid wrappers
///   are distinct JS objects and would never compare equal by reference.

var MAXIMIZE_AREA = 2; /// KWin::ClientAreaOption::MaximizeArea

/// Normalizes a window's internalId (QUuid) to a plain string
function windowId(w){
    return w ? String(w.internalId) : null;
}

function selectClient(client){
    client.setMaximize(false, false);
    client.shade = false;

    if (_root.rememberWindowSizes)
        _root.windowSizesBeforeSnap[windowId(client)] = { height: client.height, width: client.width };

    client.frameGeometry = {
        x: _root.x - (_root.assistPadding / 2),
        y: _root.y - (_root.assistPadding / 2),
        width: _root.width + _root.assistPadding,
        height: _root.height + _root.assistPadding
    };

    Workspace.activeWindow = client;

    if (_root.trackSnappedWindows) {
        removeWindowFromTrack(windowId(client)); /// remove from track if was previously snapped
        _root.snappedWindows.push(windowId(client));
    }

    _assist.checkToShowNextQuaterAssist(client);
}

/// listeners
function addListenersToClient(client) {
    if (!client || client.specialWindow) return;

    /// the assist window itself: kwin's own quick-tile shortcut (super+arrow)
    /// targets the FOCUSED window — which is the assist while it is open — and
    /// tiles it (invisibly). Intercept that and redirect the tile to the window
    /// the assist was shown for, so the assist "follows" the user's re-snap.
    /// Identified by its unique caption; the QML root object reference is a
    /// different wrapper object and cannot be compared by identity.
    if (client.caption === "kde-snap-assist-overlay") {
        client.frameGeometryChanged.connect(function() {
            if (_root.programmaticAssistGeometry) return;
            const source = _root.assistSourceWindow;
            if (!_root.activated || !source || source.deleted) return;
            const geom = client.frameGeometry;
            if (!geom || geom.width < 100 || geom.height < 100) return;

            console.warn("[SnapAssist] assist quick-tiled -> redirecting to source:", source.caption);
            _root.programmaticAssistGeometry = true;
            client.frameGeometry = { x: _root.width * 2 + 5000, y: _root.height * 2 + 5000, width: 0, height: 0 };
            source.setMaximize(false, false);
            source.frameGeometry = { x: geom.x, y: geom.y, width: geom.width, height: geom.height };
            Workspace.activeWindow = source; /// re-detection runs via the follow branch on the source's geometry change
            _root.setTimeout(function(){ _root.programmaticAssistGeometry = false; }, 80);
        });
        return;
    }

    /// popups (tooltips, menus and the assist itself) never participate in snapping
    if (client.popupWindow) return;

    client.frameGeometryChanged.connect(function() {
        if (client.caption === "kde-snap-assist-overlay") return; /// never react to the assist's own geometry
        if (!client.move && !client.resize) {
            if (_root.activated && !_root.preventFromShowing && client === _root.assistSourceWindow) {
                /// the window this assist was shown for was re-snapped to another
                /// screen region while the assist is open: close the assist and
                /// re-evaluate, so it follows the window to the new position
                _assist.hideAssist(false);
                onWindowResize(client);
            } else if (_root.activated == false && _root.preventFromShowing == false) {
                if (_root.delayBeforeShowingAssist == 0) {
                    onWindowResize(client);
                } else {
                    _root.setTimeout(function(){
                        onWindowResize(client);
                    }, _root.delayBeforeShowingAssist);
                }
            }
        }
    });

    client.interactiveMoveResizeStarted.connect(function(){
        if (_root.trackSnappedWindows && !client.resize)
            removeWindowFromTrack(windowId(client), function(group){
                if (_root.fillOnSnappedMove) fillClosedWindow(client, group);
            });

        if (_root.rememberWindowSizes){
            const storedSize = _root.windowSizesBeforeSnap[windowId(client)];
            if (storedSize) {
                const geom = client.frameGeometry;
                client.frameGeometry = {
                    x: geom.x,
                    y: geom.y,
                    width: storedSize.width ?? client.width,
                    height: storedSize.height ?? client.height
                };
                delete _root.windowSizesBeforeSnap[windowId(client)];
            }
        }
    });

    client.closed.connect(function(){
        handleWindowClose(client);
    });

    client.desktopsChanged.connect(function(){
        if (_root.trackSnappedWindows && !client.resize) removeWindowFromTrack(windowId(client));
    });

    /// replaces both clientMinimized and clientUnminimized of Plasma 5
    client.minimizedChanged.connect(function(){
        if (!_root.trackSnappedWindows || !_root.minimizeSnappedTogether) return;
        if (client.minimized) {
            applyActionToAssosiatedSnapGroup(client, function(cl){ if (cl) cl.minimized = true; });
        } else {
            applyActionToAssosiatedSnapGroup(client, function(cl) {
                if (cl) {
                    cl.minimized = false;
                    if (_root.trackActiveWindows) {
                        const d = new Date();
                        _root.activationTime[windowId(cl)] = d.getTime();
                    }
                }
            });
        }
    });

    /// replaces onClientFullScreenSet of Plasma 5 (Workspace-wide signal is gone;
    /// in KWin 6 every window reports fullscreen state changes itself)
    client.fullScreenChanged.connect(function(){
        if (!client.fullScreen) _assist.preventAssistFromShowing();
    });
}

function onWindowResize(window) {
    if (_root.activated || !window || window.deleted || window.specialWindow) return;
    _assist.finishSnap(false); /// make sure we cleared all variables

    /// don't show assist if window could be fit in the group behind
    if (_root.fitWindowInGroupBehind && windowFitsInSnapGroup(window)) return;

    /// KWin 6.8 scripting exposes exactly two 2-arg/3-arg overloads (verified via
    /// a QML probe against KWin 6.8.2):
    ///   clientArea(ClientAreaOption, Window*)
    ///   clientArea(ClientAreaOption, LogicalOutput*, VirtualDesktop*)
    /// There is NO (option, LogicalOutput*) overload: passing window.output
    /// throws "TypeError: Passing incompatible arguments to C++ functions" and
    /// aborts snap detection. Pass the window itself — KWin resolves its
    /// output and desktop. (Workspace.activeOutput also does not exist; the
    /// property is Workspace.activeScreen.)
    const maxArea = Workspace.clientArea(MAXIMIZE_AREA, window);
    _root.currentScreenWidth = maxArea.width; _root.currentScreenHeight = maxArea.height;
    _root.minDx = maxArea.x; _root.minDy = maxArea.y;
    const dx = window.x, dy = window.y;
    const width = window.width, height = window.height;
    const halfScreenWidth = _root.currentScreenWidth / 2, halfScreenHeight = _root.currentScreenHeight / 2;

    /// Detect if window was snapped
    /// left/right halves
    if (isEqual(width, halfScreenWidth) && isEqual(height, _root.currentScreenHeight) && isEqual(dy, _root.minDy)) {
        if (isEqual(dx, _root.minDx)) {
            /// show on right half
            _assist.delayedShowAssist(_root.minDx + window.width, window.y, undefined, undefined, window);
        } else if (isEqual(dx, _root.minDx + halfScreenWidth)) {
            /// show on left half
            _assist.delayedShowAssist(_root.minDx, _root.minDy, undefined, undefined, window);
        }
        _root.columnsCount = 2;
        _root.layoutMode = 0;
        _root.filteredClients.push(window);

    /// top/bottom halves
    } else if (isEqual(width, _root.currentScreenWidth) && isEqual(height, halfScreenHeight) && isEqual(dx, _root.minDx)) {
        if (isEqual(dy, _root.minDy)) {
            /// show in bottom half
            _assist.delayedShowAssist(_root.minDx, _root.minDy + halfScreenHeight, halfScreenHeight, _root.currentScreenWidth, window);
        } else if (isEqual(dy, _root.minDy + halfScreenHeight)) {
            /// show in top half
            _assist.delayedShowAssist(_root.minDx, _root.minDy, halfScreenHeight, _root.currentScreenWidth, window);
        }
        _root.columnsCount = 3;
        _root.layoutMode = 2;
        _root.filteredClients.push(window);
    }

    /// quater tiling
    else if (isEqual(width, halfScreenWidth) && isEqual(height, halfScreenHeight)) {
        /// define current screen quaters
            _root.quatersToShowNext = {
            0: { dx: _root.minDx, dy:  _root.minDy, height: halfScreenHeight, width: halfScreenWidth, },
            1: { dx: _root.minDx + halfScreenWidth, dy:  _root.minDy, height: halfScreenHeight, width: halfScreenWidth, },
            2: { dx: _root.minDx, dy: _root.minDy + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
            3: { dx: _root.minDx + halfScreenWidth, dy:  _root.minDy + halfScreenHeight, height: halfScreenHeight, width: halfScreenWidth, },
        };

        /// detect which quater snapped window takes
        let currentQuater = -1;
        let l = Object.keys(_root.quatersToShowNext).length;

        for (let i = 0; i < l; i++) {
            const quater = _root.quatersToShowNext[i];
            if (isEqual(dx, quater.dx) && isEqual(dy, quater.dy)) {
                currentQuater = i;
                delete _root.quatersToShowNext[i];
                break;
            }
        }

        /// show snap assist in next quater
        if (currentQuater == -1) return;
        _assist.checkToShowNextQuaterAssist(window);
        _root.layoutMode = 1;
        _root.columnsCount = 2;
    }

    /// 3-in-row tiling
    else if (isEqual(height, _root.currentScreenHeight)) {
        const thirdOfScreenWidth = _root.currentScreenWidth / 3;
        if (isEqual(width, thirdOfScreenWidth)) {
            /// define current screen thirds
            _root.quatersToShowNext = {
                0: { dx: _root.minDx, dy:  _root.minDy, height: _root.currentScreenHeight, width: thirdOfScreenWidth, },
                1: { dx: _root.minDx + thirdOfScreenWidth, dy:  _root.minDy, height: _root.currentScreenHeight, width: thirdOfScreenWidth, },
                2: { dx: _root.minDx + (thirdOfScreenWidth * 2), dy: _root.minDy, height: _root.currentScreenHeight, width: thirdOfScreenWidth, },
            };

            /// detect which quater snapped window takes
            let currentQuater = -1;
            let l = Object.keys(_root.quatersToShowNext).length;

            for (let i = 0; i < l; i++) {
                const quater = _root.quatersToShowNext[i];
                if (isEqual(dx, quater.dx) && isEqual(dy, quater.dy)) {
                    currentQuater = i;
                    delete _root.quatersToShowNext[i];
                    break;
                }
            }

            /// show snap assist in next quater
            if (currentQuater == -1) return;
            _assist.checkToShowNextQuaterAssist(window);
            _root.layoutMode = 3;
            _root.columnsCount = 1;
        }
    }

    /// if only one window available, show it in center and bigger
    if (_root.clients && _root.clients.length == 1) {
        _root.columnsCount = 1;
        _root.cardWidth *= 1.2;
        _root.cardHeight *= 1.2;
    }
}

function handleWindowFocus(window) {
    if (_root.ignoreFocusChange) return;
    if (_root.activated && window !== _root.assistSourceWindow) _assist.hideAssist(false);
    if (!window || window.specialWindow) return;

    /// Store timestamp of last window activation
    if (_root.trackActiveWindows) {
        const d = new Date();
        _root.activationTime[windowId(window)] = d.getTime();
    }

    /// Raise all snapped windows together
    if (_root.trackSnappedWindows && _root.raiseSnappedTogether && !_root.activated) {
        const i = _root.snappedWindowGroups.findIndex((group) => group.windows.includes(windowId(window)));
        if (i > -1) {
            const windows = _root.snappedWindowGroups[i].windows;
            const l = windows.length;
            if (l < 2) return;

            _root.ignoreFocusChange = true;

            for(let i = 0; i < l; i++) {
                if (windows[i] !== windowId(window)) {
                    const w = getClientFromId(windows[i]);
                    if (w && !w.minimized) Workspace.activeWindow = w;
                }
            }

            Workspace.activeWindow = window;
            _root.setTimeout(function(){
                _root.ignoreFocusChange = false;
            }, 100);
        }
    }
}

function handleWindowClose(window){
    if (!window || window.specialWindow) return;
    if (_root.trackActiveWindows) delete _root.activationTime[windowId(window)];
    if (_root.rememberWindowSizes) delete _root.windowSizesBeforeSnap[windowId(window)];

    if (_root.trackSnappedWindows) {
        /// remove window if it was snapped
        removeWindowFromTrack(windowId(window), function(group){
            /// callback when snapped window was closed.
            if (_root.fillOnSnappedClose) fillClosedWindow(window, group);
        });
    }
}


/// for snap groups
function applyActionToAssosiatedSnapGroup(client, callback){
    if (!client || !windowId(client)) return;

    const i = _root.snappedWindowGroups.findIndex((group) => group.windows.includes(windowId(client)));
    if (i > -1) {
        const windows = _root.snappedWindowGroups[i].windows;
        windows.forEach(wid => callback(getClientFromId(wid)));
    }
}

function removeWindowFromTrack(windowIdArg, callback){
    /// Removes provided windowId from tracking of snapped windows
    const windowIdStr = windowIdArg ? String(windowIdArg) : null;
    if (!windowIdStr) return;

    let i2 = -1;
    const i = _root.snappedWindowGroups.findIndex(function(group) {
        i2 = group.windows.indexOf(windowIdStr);
        return i2 > -1;
    });

    if (i > -1) {
        _root.snappedWindowGroups[i].windows.splice(i2, 1);
        if (callback) callback(_root.snappedWindowGroups[i]);
        if (_root.snappedWindowGroups[i].windows.length < 1) _root.snappedWindowGroups.splice(i, 1);
    }
}

function fillClosedWindow(closedWindow, group){
    /// fill the free area when snapped window closed or moved
    const closedWindowGeom = closedWindow.frameGeometry;
    const remainingWindows = group.windows;
    for(let i = 0, l = remainingWindows.length; i < l; i++){
        const window = getClientFromId(remainingWindows[i]);
        if (!window) continue;
        if (String(window.internalId) === String(closedWindow.internalId)) continue;
        const windowGeom = window.frameGeometry;
        if (!windowGeom) continue;

        if (windowGeom.x == closedWindowGeom.x && windowGeom.width == closedWindowGeom.width){
            /// expand vertically
            _assist.preventAssistFromShowing();
            let newHeight = windowGeom.height + closedWindowGeom.height;
            if (newHeight > _root.currentScreenHeight) newHeight = _root.currentScreenHeight;
            window.frameGeometry = {
                x: windowGeom.x,
                y: windowGeom.y - (windowGeom.y > closedWindowGeom.y ? closedWindowGeom.height : 0),
                width: windowGeom.width,
                height: newHeight
            };
            break;
        } else if(windowGeom.y == closedWindowGeom.y && windowGeom.height == closedWindowGeom.height) {
            /// expand horizontally
            _assist.preventAssistFromShowing();
            let newWidth = windowGeom.width + closedWindowGeom.width;
            if (newWidth > _root.currentScreenWidth) newWidth = _root.currentScreenWidth;
            window.frameGeometry = {
                x: windowGeom.x - (windowGeom.x > closedWindowGeom.x ? closedWindowGeom.width : 0),
                y: windowGeom.y,
                width: newWidth,
                height: windowGeom.height
            };
            break;
        }
    }
}

function windowFitsInSnapGroup(client){
    /// determines if newly snapped window could be fit in group behind it
    /// requires track activation time and raise snapped windows together

    /// find last active client
    let lastActiveWindowId = -1, lastActiveTime = -1;
    const activeClientId = Workspace.activeWindow ? windowId(Workspace.activeWindow) : null;
    Object.keys(_root.activationTime).forEach(function(key) {
        if(_root.activationTime[key] > lastActiveTime && key != windowId(client) && key != activeClientId) {
            const c = getClientFromId(key);
            if (c && !c.minimized && sameOutput(c.output, Workspace.activeScreen) && c.desktops.includes(Workspace.currentDesktop)) {
                lastActiveWindowId = windowId(c);
                lastActiveTime = _root.activationTime[key];
            }
        }
    });
    if (lastActiveWindowId < 0) return false;

    /// find if it belongs to snap group
    const indexOfGroup = _root.snappedWindowGroups.findIndex((group) => group.windows.includes(lastActiveWindowId));
    if (indexOfGroup < 0) return false;

    /// check rest of windows in that group
    const snappedWindows = _root.snappedWindowGroups[indexOfGroup].windows;

    for (let i = 0, l = snappedWindows.length; i < l; i++) {
        const w = getClientFromId(snappedWindows[i]);
        if (!w) continue;

        if (w.y == client.y && w.height == client.height && w.width > client.width) {
            /// reduce window width to fit new window in layout
            _root.snappedWindowGroups[indexOfGroup].windows.push(windowId(client));
            _assist.preventAssistFromShowing();
            const newWidth = w.frameGeometry.width - client.width;
            w.frameGeometry = {
                x: w.frameGeometry.x + (w.x == client.x ? client.width : 0),
                y: w.frameGeometry.y,
                width: newWidth,
                height: w.frameGeometry.height
            };
            return true;

        } else if (w.x == client.x && w.width == client.width && w.height > client.height) {
            /// reduce window height to fit new window in layout
            _root.snappedWindowGroups[indexOfGroup].windows.push(windowId(client));
            _assist.preventAssistFromShowing();
            const newHeight = w.frameGeometry.height - client.height;
            w.frameGeometry = {
                x: w.frameGeometry.x,
                y: w.frameGeometry.y + (w.y == client.y ? client.height : 0),
                width: w.frameGeometry.width,
                height: newHeight
            };
            return true;

        } else if (w.x == client.x && w.y == client.y && w.height == client.height && w.width == client.width) {
            /// replace window in group with newly snapped window
            _root.snappedWindowGroups[indexOfGroup].windows.splice(i, 1);
            _root.snappedWindowGroups[indexOfGroup].windows.push(windowId(client));
            return true;
        }
    }

    return false;
}


/// utility functions
function isEqual(a, b) {
    /// for compatibility with scripts like Window Gap
    return a - b <= _root.snapDetectPrecision && a - b >= -_root.snapDetectPrecision;
}

function sameOutput(a, b) {
    /// compares two LogicalOutput objects by identity or name
    return a === b || (a && b && a.name === b.name);
}

function getClientFromId(windowIdArg){
    const windowIdStr = windowIdArg ? String(windowIdArg) : null;
    if (!windowIdStr) return null;
    return Workspace.stackingOrder.find((el) => String(el.internalId) === windowIdStr);
}

function shouldShowWindow(client) {
    if (_root.filteredClients.includes(client)) return false;
    if (client.active || client.specialWindow) return false;
    if (!_root.showMinimizedWindows && client.minimized) return false;
    if (!_root.showOtherScreensWindows && !sameOutput(client.output, Workspace.activeScreen)) return false;
    /// note: windows on all desktops have an empty desktops list, so they are
    /// treated as "other desktops" windows — same as in the Plasma 5 version
    if (!_root.showOtherDesktopsWindows && !client.desktops.includes(Workspace.currentDesktop)) return false;
    if (!_root.showSnappedWindows && _root.snappedWindowGroups.findIndex(group => group.windows.includes(windowId(client)) && group.windows.length > 1) > -1) return false;
    if (client.activities.length > 0 && !client.activities.includes(Workspace.currentActivity)) return false;
    return true;
}

/// (sorting is done inline in assist.js delayedShowAssist with a new-array
/// assignment, so the Repeater gets notified about the new card order)

function tileSourceWindow(direction) {
    /// quick-tiles the window the assist was shown for, triggered by
    /// super+arrow while the assist has keyboard focus (kwin's own shortcut
    /// targets the focused assist window and no-ops, so the assist implements
    /// the tiling itself). The geometry change then triggers the follow logic,
    /// which closes and re-shows the assist on the other side.
    const source = _root.assistSourceWindow;
    if (!_root.activated || !source || source.deleted) return false;

    const area = Workspace.clientArea(MAXIMIZE_AREA, source);
    const halfW = area.width / 2, halfH = area.height / 2;
    let geom = null;
    if (direction === "left")       geom = { x: area.x, y: area.y, width: halfW, height: area.height };
    else if (direction === "right") geom = { x: area.x + halfW, y: area.y, width: halfW, height: area.height };
    else if (direction === "up")    geom = { x: area.x, y: area.y, width: area.width, height: halfH };
    else if (direction === "down")  geom = { x: area.x, y: area.y + halfH, width: area.width, height: halfH };
    if (!geom) return false;

    console.warn("[SnapAssist] tiling source from assist:", direction, "->", source.caption);
    source.setMaximize(false, false);
    source.frameGeometry = geom;
    return true;
}
