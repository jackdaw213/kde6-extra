# PomodoroKDE

An enforced Pomodoro timer as a Plasma 6 panel widget. Work Blocks expire into a fullscreen rest overlay that beats even true-fullscreen applications, pauses your media, and waits as long as you actually rest. Designed for a 50/10 rhythm and driven by wall-clock deadlines — reboots, logouts and plasmashell restarts never lose or stretch a running timer (a Work Block paused by a screen lock resumes from its frozen remaining time by design).

## Features

- **Panel icon** that shows a timer icon when idle and the remaining `mm:ss` while running.
- **Preset card** in the left-click popup: a 2×3 grid with slightly larger font — three locked **Built-ins** (50/10, 25/5, 45/15, undeletable) plus three user slots. Presets are identified by their minutes: a preset's **label is its own rhythm** ("25/5"-style, derived automatically — there is no name field to fill). Clicking any occupied slot starts that Work Block immediately; the ★ marks the **Default Preset**, selectable on any of the six slots (Enable starts it). An **empty user slot is an inert “—” dash** — nothing to add from the grid: presets are created on the **settings page** (gear button, top right), where every empty user row offers an **Add preset** button (creating a 30/5 rhythm — deliberately not a Built-in duplicate) and every occupied row edits in place (work, break, large break, delete), next to the star picker and the Desk Reminder controls. While a Work Block times (or a Break runs) the grid stays visible but all six cells disable — the machine refuses a restart, and the UI says so instead of hiding the row and leaving a hole. The card holds **one constant size**: its frame is sized by the settings page and both pages live inside it, so toggling the gear, starting/stopping a block or editing presets never resizes the card or moves the gear. *(Round 6: the grid tiles are one fixed height and never flex into the leftover frame space — no giant squares over the buttons; the user-preset editor is a single line (work, break, large, delete); the card is 21 grid units wide — the minimal width that fits that line — and the three hint captions reserve a fixed 2-line height so the popup's first-pass measure equals the settled one and nothing paints past the dialog's bottom edge.)* The former Custom one-off row is gone — user presets cover arbitrary (work, break) rhythms — and there is still no Configure-dialog page.
- **Fullscreen Break overlay** (Wayland layer-shell, overlay layer — above fullscreen apps):
  - announces **Rest time** with the remaining break `mm:ss`,
  - **Continue** is disabled *and* visibly grayed for the whole break and enables itself exactly when the wall-clock break deadline passes (even after a restart) — then waits indefinitely for however long you rest,
  - **Skip** requires two clicks (first click arms *"Really skip work?"*, the second confirms),
  - **Delay break 5 minutes** — repeatable; each click adds five more minutes and resumes work.
- **Large Break cadence**: every 4th Work Block earns a Large Break (cycle length is config-file only — the `cycleLength` entry, default 4; the Configure dialog no longer offers it). Its length is the preset's explicit large-break value if set, otherwise derived automatically: normal break ≤6 min → 20, 7–12 → 30, ≥13 → 40. Each user preset sets its own Large-Break length on the card (**Large** spinbox, 0 = the automatic rule); hand-edited configs keep working (an explicit `largeBreakMin` on a **user** preset is preserved and still wins; Built-in slots always re-seed canonically, discarding any hand-added fields).
- **Media Pause** at break start: all *playing* MPRIS players are paused. Paused media is never auto-resumed — anywhere.
- **Chime** when a Break starts and when the Desk Overlay appears — a bundled, soft ~2.6 s piano-style arpeggio (gentle attack, exponential decay), no external sound-theme dependency.
- **Desk Reminder** (SPEC-002): an optional auxiliary countdown (off by default, 30-minute interval, tunable in the card) that runs **only during a Work Block**, resets at every block start, and on expiry shows a fullscreen prompt to change your standing-desk height by doing the reverse of what you're doing now — acknowledged with one button ("Done — I switched"). A due Break always outranks the Desk Overlay; the Work/Break machine is untouched.
- **Presence auto-start and lock-paused work** (SPEC-003): an unlocked session is *Presence*. After the configurable Presence window (default 5 minutes, 1–60 in the card) with no timing phase, a Work Block of the Default Preset starts by itself and sends **one informational desktop notification** ("Pomodoro started", naming the preset) — no chime, no popup. A manual *Disable for now* stays in force until the screen locks once; the next unlock re-arms auto-start. A screen lock **pauses a running Work Block** and freezes its Desk Reminder countdown; unlocking resumes both from the exact frozen remaining time. A Break keeps its wall-clock deadline, so time away during a Break still counts as rest. If the lock-state source is unavailable, the switch is inert and the hint says so; manual timing works as before, except that a Work Block already paused by a lock stays frozen until the source returns (or you Disable and Enable again).
- **Start Break Now** in the popup cuts a delayed work period short.
- **Disable for now** (meeting mode) suspends everything; re-enabling starts a fresh Work Block of the Default Preset (★, chosen in the card).
- **Persistence**: every state change snapshots `phase, deadline, preset, completedBlocks, cycleLength, pendingBreak, deskDeadline, deskDue, paused, pausedRemainingMs, deskPausedRemainingMs, autoStartArmed` into the plasmoid config; on load the snapshot is restored and settled with one wall-clock tick — a deadline crossed while away transitions immediately, anchored at the original expiry instant. The desk countdown restores by wall clock too (a due prompt even reappears after a restart). A **Paused Work Block survives plasmashell restart, logout and reboot** with its frozen remaining times and resumes on the next unlock; the Presence window itself is never persisted (the first unlocked observation after a restart opens a fresh one).

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

- **Start**: left-click the icon → click a preset (occupied slots only; an empty slot is an inert dash — add presets in the settings page first).
- **Panel while running**: the icon shows the remaining `mm:ss`.
- **When a Work Block expires**: the screen is covered by the Rest overlay and the break begins instantly — media pauses, chime sounds.
- **Continue**: enabled when the break's countdown reaches zero; starts a fresh full Work Block of the current preset.
- **Skip**: mid-flow escape hatch; two clicks on purpose (arm → *Yes*). The cycle advances as if the break had run.
- **Delay break 5 minutes**: on the overlay (or *Delay* in the popup while working through a delayed break); each click adds five minutes.
- **Cut a delay short**: popup → *Start break now*.
- **Meeting**: popup → *Disable for now*; *Enable* starts a fresh block of the Default Preset. A Disable also suppresses Auto-start until the screen locks once; after the next unlock, a full Presence window starts the Default Preset again.
- **Auto-start**: settings page → *Auto-start* switch and 1–60 minute window (default on, 5 minutes). It starts the Default Preset only from Idle or Disabled, never during a Work Block, Break, or the finished-break wait, and never chimes. If screen-lock detection is unavailable the switch is disabled and the hint explains why.
- **Locking the screen**: a running Work Block and its Desk Reminder freeze; unlock resumes both with the full remaining time. A Break is never paused — real rest time away counts. The panel keeps showing the frozen `mm:ss` while paused.
- **Presets & desk reminder**: all in the popup card — grid to start; the gear (top right) flips to the full-card settings page where each of the three user slots is one uniform row: an **Add preset** button when empty, the editor (work, break, large, delete) once filled. Also there: the starred Default Preset picker and the Desk Reminder toggle + interval. The Configure dialog no longer manages presets. A Large break of `0` means *the automatic rule* — every preset's Large spinbox defaults to it, and committing 0 removes any previously stored explicit value.
- **Cycle length**: config-file only (the `cycleLength` entry in the widget's config group, default 4); no UI edits it — the Configure dialog is empty now (SPEC-002 moved all management into the card).

## Architecture

- All domain behavior (phases, deadlines, cycle math, preset handling) lives in one pure module, `plasmoid/contents/ui/pomodoro-machine.js` (no Qt/Plasma imports) — the single test seam, exercised by `tests/tst_machine.qml` via `qmltestrunner` (Qt 6):

  ```sh
  QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_machine.qml
  ```

- The break overlay is a widget-owned Wayland layer-shell surface (`org.kde.layershell`, `LayerOverlay`) per `docs/adr/0002`. (The originally planned KWin-script overlay from `docs/adr/0001` was probed and found unable to return button intents on stock KWin 6.7.5 — see ADR-0002 for the evidence and the amendment.)
- Media pause uses plasma-workspace's own `org.kde.plasma.private.mpris` QML module (`Mpris2Model` → `Pause()`); the chime uses QtMultimedia (`MediaPlayer`) with the bundled `contents/sounds/pomodoro-chime.ogg` arpeggio. Both are loaded via loaders and degrade to a logged no-op if the module is unavailable.
- Presence uses `org.kde.plasma.workspace.dbus` (`SignalWatcher` + `SessionBus.asyncCall`) to observe `org.freedesktop.ScreenSaver.GetActive`/`ActiveChanged`, with a one-second poll as the safety net; if the screen saver service is absent it falls back to logind's `LockedHint` over `SystemBus` (`org.freedesktop.login1`), polled once per second. The auto-start notification is `Notifier.qml` calling `org.freedesktop.Notifications.Notify`. Both sit behind loaders and degrade to logged no-ops.

## Limitations

- **Single display**: the overlay covers the screen the compositor hands it (`ScreenFromCompositor`); no multi-monitor spreading.
- **Layer-shell attachment from the plasmashell process** is the one integration point that cannot be fully verified from a sandboxed development environment. The overlay logs whether the layer surface attached (`layerSurfaceDefined`); if attachment ever fails in practice, the window still shows but as a plain top-level window, which true-fullscreen applications may cover — that degraded mode is a known, documented fallback (ADR-0002), never a silent one.
- **Enforcement is compositor-grade, not kiosk-grade**: a determined user can still kill the plasmoid from a TTY. That is out of scope.
- Media pause is best-effort per player: it needs the player to honor MPRIS `CanControl`/`Pause`; players ignoring MPRIS are not stopped.
- The chime is bundled with the widget, so playback depends only on QtMultimedia being present; if it is not, the chime logs and skips.
- No statistics/history and no auto-resume of media (deliberately never).
- Presence is the **unlocked session**, not keyboard/mouse idle time: a screen that only blanks through DPMS without locking or activating the screen saver is not detected as away. Presence therefore continues while the screen is merely blanked but unlocked, so Auto-start can fire and a running Work Block keeps counting.
- Screen-lock observation and desktop-notification delivery are thin D-Bus adapters. The API shapes, the `GetActive` poll, and a real `Notify` call were verified on the live session; the `SignalWatcher` transition path, the logind fallback, and the notification's visual appearance remain live manual checks. The headless suite covers the machine, the card, and the monitor's retry contract, not the compositor/notification-daemon round-trip.
- Development of this widget happened inside a sandbox with read-only `~/.local/share`; end-to-end install verification on the real home directory is left to the user's own `kpackagetool6` run (packaging itself is verified: install/list/uninstall all pass with a redirected data home).
