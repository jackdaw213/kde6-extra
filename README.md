# PomodoroKDE

An enforced Pomodoro timer as a Plasma 6 panel widget. Work Blocks expire into a fullscreen rest overlay that beats even true-fullscreen applications, pauses your media, and waits as long as you actually rest. Designed for a 50/10 rhythm and driven entirely by wall-clock deadlines — reboots, logouts and plasmashell restarts never lose or stretch a running timer.

## Features

- **Panel icon** that shows a timer icon when idle and the remaining `mm:ss` while running.
- **One-click presets** in the left-click popup: 50/10 (default, marked ★), 25/5, 45/15 — each starts a Work Block immediately. A **Custom…** pair of spinboxes starts any one-off (work, break) pair.
- **Fullscreen Break overlay** (Wayland layer-shell, overlay layer — above fullscreen apps):
  - announces **Rest time** with the remaining break `mm:ss`,
  - **Continue** is disabled *and* visibly grayed for the whole break and enables itself exactly when the wall-clock break deadline passes (even after a restart) — then waits indefinitely for however long you rest,
  - **Skip** requires two clicks (first click arms *"Really skip work?"*, the second confirms),
  - **Delay break 5 minutes** — repeatable; each click adds five more minutes and resumes work.
- **Large Break cadence**: every 4th Work Block earns a Large Break (configurable cycle length). Its length is the preset's explicit large-break value if set, otherwise derived automatically: normal break ≤6 min → 20, 7–12 → 30, ≥13 → 40.
- **Media Pause** at break start: all *playing* MPRIS players are paused. Paused media is never auto-resumed — anywhere.
- **Chime** at break start only.
- **Start Break Now** in the popup cuts a delayed work period short.
- **Disable for now** (meeting mode) suspends everything; re-enabling starts a fresh default 50/10 Work Block.
- **Persistence**: every state change snapshots `phase, deadline, preset, completedBlocks, cycleLength, pendingBreak` into the plasmoid config; on load the snapshot is restored and settled with one wall-clock tick — a deadline crossed while away transitions immediately, anchored at the original expiry instant.

## Install

```sh
kpackagetool6 -t Plasma/Applet -i plasmoid
```

(Home install, no root needed. Re-install cleanly with `kpackagetool6 -t Plasma/Applet -r org.kde.plasma.pomodoro` first if you have an older copy.)

## Add to a panel

1. Right-click the Plasma panel → *Enter Edit Mode* → *Add Widgets…*
2. Find **Pomodoro** and drag it onto the panel (or click it to place it in the system tray area of your choice).
3. Leave Edit Mode.

## Usage

- **Start**: left-click the icon → click a preset (or unfold *Custom…* values → *Start*).
- **Panel while running**: the icon shows the remaining `mm:ss`.
- **When a Work Block expires**: the screen is covered by the Rest overlay and the break begins instantly — media pauses, chime sounds.
- **Continue**: enabled when the break's countdown reaches zero; starts a fresh full Work Block of the current preset.
- **Skip**: mid-flow escape hatch; two clicks on purpose (arm → *Yes*). The cycle advances as if the break had run.
- **Delay break 5 minutes**: on the overlay (or *Delay* in the popup while working through a delayed break); each click adds five minutes.
- **Cut a delay short**: popup → *Start break now*.
- **Meeting**: popup → *Disable for now*; *Enable* starts a fresh 50/10 block.
- **Edit presets / cycle length**: panel icon's context menu (right-click) → *Configure Pomodoro…* → *Presets* page. Up to 5 presets; the first one is the default; a large-break of `0` means *derive automatically*.

## Architecture

- All domain behavior (phases, deadlines, cycle math, preset handling) lives in one pure module, `plasmoid/contents/ui/pomodoro-machine.js` (no Qt/Plasma imports) — the single test seam, exercised by `tests/tst_machine.qml` via `qmltestrunner` (Qt 6):

  ```sh
  QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_machine.qml
  ```

- The break overlay is a widget-owned Wayland layer-shell surface (`org.kde.layershell`, `LayerOverlay`) per `docs/adr/0002`. (The originally planned KWin-script overlay from `docs/adr/0001` was probed and found unable to return button intents on stock KWin 6.7.5 — see ADR-0002 for the evidence and the amendment.)
- Media pause uses plasma-workspace's own `org.kde.plasma.private.mpris` QML module (`Mpris2Model` → `Pause()`); the chime uses QtMultimedia (`SoundEffect`) with a freedesktop sound-theme sample. Both are loaded via loaders and degrade to a logged no-op if the module is unavailable.

## Limitations

- **Single display**: the overlay covers the screen the compositor hands it (`ScreenFromCompositor`); no multi-monitor spreading.
- **Layer-shell attachment from the plasmashell process** is the one integration point that cannot be fully verified from a sandboxed development environment. The overlay logs whether the layer surface attached (`layerSurfaceDefined`); if attachment ever fails in practice, the window still shows but as a plain top-level window, which true-fullscreen applications may cover — that degraded mode is a known, documented fallback (ADR-0002), never a silent one.
- **Enforcement is compositor-grade, not kiosk-grade**: a determined user can still kill the plasmoid from a TTY. That is out of scope.
- Media pause is best-effort per player: it needs the player to honor MPRIS `CanControl`/`Pause`; players ignoring MPRIS are not stopped.
- The chime sample comes from the freedesktop sound theme; if `/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga` is missing (unusual on Plasma desktops), the chime logs and skips.
- No statistics/history, no Wayland screen-lock integration, no auto-resume of media (deliberately never).
- Development of this widget happened inside a sandbox with read-only `~/.local/share`; end-to-end install verification on the real home directory is left to the user's own `kpackagetool6` run (packaging itself is verified: install/list/uninstall all pass with a redirected data home).
