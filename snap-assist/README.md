# KDE Snap Assist — Plasma 6 port

KWin script that suggests thumbnails of other windows when you snap a window to a
screen edge (Windows 11 Snap Assist style). This is a port of
[emvaized/kde-snap-assist](https://github.com/emvaized/kde-snap-assist) to
**KDE Plasma 6 / KWin 6** (developed and verified against KWin 6.8.2, Qt 6.12,
Wayland on this machine).

Upstream sources are kept untracked in `upstream/` (branch `main`, plus the
upstream `plasma6-wip` branch which this port started from and fixed).

## What was ported

The script is a *declarative* KWin script (QML UI + JS logic). Plasma 6 removed or
renamed most of the scripting surface it used. Verified API mapping:

| Plasma 5 | Plasma 6 (KWin 6.8) |
|---|---|
| `workspace.clients` | `Workspace.stackingOrder` |
| `workspace.activeClient` (get/set) | `Workspace.activeWindow` (get/set) |
| `workspace.clientArea(KWin.MaximizeArea, w)` | `Workspace.clientArea(2, w)` — the `KWin` enum object is not reachable from declarative scripts; `MaximizeArea == 2`. Only overloads: `(option, Window*)` and `(option, LogicalOutput*, VirtualDesktop*)` — passing `window.output` throws |
| `workspace.activeScreen` (int index) | `Workspace.activeScreen` (LogicalOutput object); window side: `client.screen` → `client.output` |
| `client.desktop` (int) | `client.desktops` (list of VirtualDesktop objects) |
| `client.clientStartUserMovedResized` / `clientFinishUserMovedResized` | `client.interactiveMoveResizeStarted` / `interactiveMoveResizeFinished` |
| `client.clientMinimized` / `clientUnminimized` | single `client.minimizedChanged` (branch on `client.minimized`) |
| `client.windowClosed`, `client.desktopChanged` | `client.closed`, `client.desktopsChanged` |
| `workspace.onClientActivated/onClientAdded` | `Workspace.onWindowActivated/onWindowAdded` |
| `workspace.onClientFullScreenSet` (workspace-wide) | per-window `client.fullScreenChanged` |
| `options` object for config reload | gone; configs re-read via `KWin.readConfig` each time the assist is shown |
| `client.internalId` (number) | QUuid — normalized with `String()` (`windowId()` helper) before storing/comparing |
| `client.frameGeometry = Qt.rect(...)` | plain `{x, y, width, height}` object (KWin `RectF`, float precision; subfield writes don't write back) |
| `KWinComponents.ThumbnailItem { wId }` | `KWinComponents.WindowThumbnail { wId }` (QUuid) |
| desktop background via lookup + thumbnail | `KWinComponents.DesktopBackground { output; desktop }` |
| `QtGraphicalEffects` FastBlur | `QtQuick.Effects` MultiEffect (Qt5Compat not installed here) |
| versioned imports | unversioned Qt 6 imports; `org.kde.kwin` imported twice (unaliased for the `Workspace` singleton, aliased as `KWinComponents` for types) |
| `metadata.desktop` | `metadata.json` (`KPackageStructure: KWin/Script`, `X-Plasma-API: declarativescript`) |

## Scope architecture (important)

On Qt 6 QV4, `import "x.js" as Alias` gives the JS module an **isolated scope**:
unqualified references to the QML document's root properties, ids, or sibling
import aliases throw `ReferenceError` at runtime — and one raised inside a Wayland
protocol callback **segfaulted the compositor** (first kwin crash on this machine;
see the crash report of 2026-11-02). Therefore:

- each JS module gets an explicit context handoff: `init(root, …)` is called from
  `Component.onCompleted` (AssistManager and WindowManager receive each other;
  KeyboardManager receives the root);
- all shared state lives on the root object and is accessed as `_root.<name>`;
- cross-module calls go through `_assist.<fn>` / `_wm.<fn>`;
- QML ids are **not** root properties — child items used from JS
  (keyboardHandler, scrollView, fadeInAnimation, clientsRepeater) are exposed via
  `property alias …Ref: <id>`;
- `Workspace`/`KWin` singletons resolve fine unqualified inside .js files.

## Features added during the port

- **KDE-glass backdrop**: blurred desktop background behind the assist by default
  (`showDesktopBackground`, `desktopBackgroundBlur` in the settings), using the
  standard `MultiEffect` blur.
- **Follow re-snap**: while the assist is open, `super+arrow` tiles the window the
  assist was shown for and the assist flips to the other side. Two paths:
  the assist retargets `Workspace.activeWindow` to the source (kwin's own
  shortcut then tiles it), and if the assist itself receives `Meta+Arrow` keys it
  tiles the source directly via a geometry write.
- Stale-timer invalidation (epoch counter), stuck-state recovery
  (`onVisibleChanged`), per-call timers (the upstream single-Timer design had
  cross-talk between the 300 ms prevention and 3 ms show delays).

## Layout

```
metadata.json               KPackage metadata (KWin/Script, declarativescript)
contents/code/*.js          JS logic (assist.js, keyboard.js, windows.js; main.js is a stub)
contents/ui/main.qml        assist UI + config + Connections
contents/ui/components/     CornerButton, DesktopBackground
contents/ui/config.ui       config dialog (unchanged from upstream)
contents/ui/icons/*.svg     layout icons (unchanged)
contents/config/main.xml    KConfigXT schema (defaults: blurred background on)
```

## Install

```sh
kpackagetool6 --type KWin/Script --install /home/jackdaw/GitHub/kde6-snap-assist
# update if already installed:
kpackagetool6 --type KWin/Script --upgrade /home/jackdaw/GitHub/kde6-snap-assist
```

Then reconfigure KWin or log out/in. The script is enabled by default
(`EnabledByDefault` in metadata.json); toggle in System Settings → Window
Management → KWin Scripts if needed.

## Quick manual test without installing

```sh
# ALWAYS unload first — loadDeclarativeScript stacks instances otherwise
# (five stacked zombie instances once amplified a JS error into a compositor crash)
qdbus org.kde.KWin /Scripting unloadScript snapAssistDev
qdbus org.kde.KWin /Scripting loadDeclarativeScript \
    <path>/contents/ui/main.qml snapAssistDev
qdbus org.kde.KWin /Scripting start
# unload again:
qdbus org.kde.KWin /Scripting unloadScript snapAssistDev
```

KWin script errors go to the journal: `journalctl --user _COMM=kwin_wayland -f`.
When reloading repeatedly, change the file path as well — the QML engine caches
compiled components by URL and can serve a stale unit for a reused path.

## Known limitations / notes

- `super+arrow` with the assist open retiles the assist's source window, not the
  assist itself (kwin's shortcut targets the focused window; the assist redirects).
- Windows on all virtual desktops are treated as "other desktops" windows
  (matches upstream Plasma 5 behavior).
- The QV4 segfault on ReferenceError inside protocol callbacks is also a
  KWin/Qt hardening bug — worth reporting to bugs.kde.org with the crash report.
