# Handoff: Pomodoro Panel Widget for Plasma 6 (org.kde.plasma.pomodoro)

Date: 2026-10-13 · Workflow: Matt Pocock idea-to-ship (completed through handoff) · Repo: `~/GitHub/PomodoroKDE`

## Where the work stands

Feature-complete candidate. All review blockers resolved. Machine test suite green. Package validates and installs (validated via `XDG_DATA_HOME` redirect; real home install reserved for the operator — agent sandboxes have read-only `~/.local/share`).

Truth hierarchy (read in this order): `CONTEXT.md` (glossary) → `docs/SPEC.md` (requirements) + `docs/SPEC-002-presets-card-desk-chime.md` (preset grid / in-card management / Desk Reminder / chime, superseding the preset cap and "re-enable = 50/10" decisions below) → `docs/adr/0001-kwin-script-overlay.md` (amended) + `docs/adr/0002-overlay-communication-channel.md` (overlay tech + probe evidence) → `features/pomodoro.feature` (executable scenarios) → code in `plasmoid/`.

Do not re-derive decisions: all 15 are locked. Key ones: presets 50/10 (default), 25/5, 45/15, editable, max 5; Continue grayed for the whole break then self-enables at the wall-clock deadline and waits indefinitely; Skip = two-click confirm, always available during break; Delay Break = repeatable +5 min; cycle = 4th work block's break is Large (auto rule ≤6→20, 7–12→30, ≥13→40, per-preset override); MPRIS pause at break start, never auto-resume; chime at break start; "Disable for now" → re-enable = fresh 50/10; wall-clock deadline persistence across reboots.

Architecture: single plasmoid; state machine in `plasmoid/contents/ui/pomodoro-machine.js` (pure, the one test seam, 25 test functions in `tests/tst_machine.qml`, run with `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_machine.qml` — PATH `qmltestrunner` is Qt5, never use it). Overlay is widget-owned LayerShellQt (Overlay layer) after live probes killed the KWin-script route (see ADR-0002 before proposing any overlay change). Chime = QtMultimedia MediaPlayer (SoundEffect is WAV-only; theme ships .oga only).

## Outstanding: operator live-verification checklist (agents cannot perform these)

1. Install: `kpackagetool6 -t Plasma/Applet -i ~/GitHub/PomodoroKDE/plasmoid`, add widget to panel.
2. Overlay attach (the one risk ADR-0002 flags as unverifiable off-session): start a 1-min custom block, confirm the fullscreen overlay covers panel + stays above a true-fullscreen app. If it degrades to a plain window, a `console.warn` fires ("without a loaded layer-shell module" pattern) — check `journalctl --user` / plasmashell output, then consult ADR-0002's fallback.
3. MPRIS: have Spotify/Firefox playing at break start → must pause, never resume.
4. Chime audibility (`.oga` via MediaPlayer — code path new, only lint-verified).
5. Reboot mid-break → overlay must reappear (restore() reopens it for restored break/wait phases).
6. ~~Preset editor: 6th preset refused; cycle-length spinbox (2–12) in Configure → Presets.~~ **Superseded** (round 3b): there is no Configure page — all preset management lives on the card's settings page (six slots, add/edit/delete/star there). Live-verify instead: the card settings page round-trips (add, edit, delete, move the star, desk controls); `cycleLength` is config-file-only (default 4).

## Review trail

Independent fresh-context review returned FAIL with 3 blockers (dead UI: `Plasmoid.expanded` misuse + missing module import; overlay not reopening after plasmashell restart; chime fed Ogg to a WAV-only decoder) + 7 non-blocking. All 10 resolved and re-verified (suite 27/27, qmllint clean, no stray `Plasmoid.*` without import, `kpackagetool6` install rc=0). `startPreset` gained a from-idle guard, TDD'd (red→green) with `test_startPreset_refusedOutsideIdle`.

Round 3b (suite unblock + review P2s): the `tst_full.qml` qmltestrunner freeze was **not** a QML/i18n issue. Root cause: QtTest writes `~/.config/qmltestrunnerrc`; where `~/.config` is read-only, KConfig escalates to a blocking `kdialog --msgbox` on the GUI thread, which headless never closes and deadlocks the QML loader-thread handshake (the `QObject::installEventFilter(): Cannot filter events for objects in a different thread` QWARN is a benign marker printed just before the freeze). `scripts/check.sh` therefore exports `XDG_CONFIG_HOME` to a throwaway writable dir and caps each test stage at 60 s. The unqualified `i18n()` in `FullRepresentation` resolves under the test runner (the `kf.i18n: Domain is not set` warnings are untranslated-but-working noise) — no shim was added. Reviewer P2s: README Configure-dialog/cycle-length claims corrected; per-preset explicit large-break editing recorded as consciously deferred (README + SPEC-002 amendment); `deleteUserPreset` resets the star to Built-in slot 0 when the starred slot is deleted (red→green: `test_deleteUserPreset_starredSlot_resetsStarToBuiltin`, guard `test_deleteUserPreset_nonStarredSlot_keepsStar`). Full `./scripts/check.sh` green (~4 s): 4 + 26 + 60 tests.

## Suggested skills for the next session

- `pi-subagents` — if further delegation is needed (operator policy: delegate large/context-heavy tasks only; small fixes in-session).
- `visual-explainer` — if the operator wants a state-machine diagram of Work Block/Break/Large Break/Delay flow before accepting the widget.
- Do NOT start swarms or deep-research skills; this project has no market-data or web-research surface.

## Sensitive data

None. No secrets in the repo or this handoff.
