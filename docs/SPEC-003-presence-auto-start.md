# SPEC 003: Presence-driven auto-start and lock-paused Work Blocks

Status: ready-for-agent
Work item: 61ee938b-638c-4aa3-900d-b3e0656472f7 (idea-to-ship)
Glossary: `CONTEXT.md` · ADR: `docs/adr/0003-pause-work-block-on-lock.md` · Parent spec: `docs/SPEC.md`

## Problem Statement

The timer starts only when I click a preset. When I sit down to work I often forget, so the day runs without breaks. The widget also charges me for time at a locked screen: a 50-minute Work Block keeps counting while I am away in a meeting, and it is over when I return.

## Solution

The widget treats an unlocked session as Presence. After a configurable Presence window (default 5 minutes) with no timing phase, it starts a Work Block with the Default Preset and sends one notification. A manual Disable stays in force until the screen locks once; after the next unlock, Presence can start the timer again. A screen lock also pauses a running Work Block and its Desk Reminder; both resume from the frozen remaining time on unlock. Breaks keep their wall-clock deadline, so real rest time away counts as rest. If lock detection is unavailable, the new behavior is off and the manual widget works exactly as before.

## User Stories

1. As a user, I want the Work Block to start by itself after I have been at an unlocked computer for a few minutes, so that I do not forget to start the timer.
2. As a user, I want the auto-start delay to be five minutes by default, so that a brief login or a quick check does not start a block.
3. As a user, I want to change the auto-start delay between 1 and 60 minutes, so that the trigger fits my routine.
4. As a user, I want an on/off switch for auto-start, so that I can stop all automatic starts.
5. As a user, I want auto-start to use my starred Default Preset, so that the automatic block matches my chosen rhythm.
6. As a user, I want a missing or invalid star to fall back to the built-in 50/10, so that auto-start always has a valid preset.
7. As a user, I want auto-start to fire only after the session stays unlocked for the whole delay, so that a screen lock resets the count.
8. As a user, I want one desktop notification on auto-start, so that I know a block started and which preset it uses.
9. As a user, I want no chime on auto-start, so that the chime keeps its meaning for rest and posture prompts.
10. As a user, I want auto-start to never interrupt a running Work Block or Break, so that the machine state is never overridden.
11. As a user, I want auto-start to never resume the finished-break overlay, so that Continue stays my explicit choice.
12. As a user, I want my manual Disable to protect a meeting even while I stay at the computer, so that the timer does not come back mid-meeting.
13. As a user, I want a manual Disable to re-arm after I lock the screen and come back, so that the timer returns when my meeting ends.
14. As a user, I want a running Work Block to pause while the screen is locked, so that away time does not count as work.
15. As a user, I want the Work Block to resume with its exact remaining time on unlock, so that I still get the full block.
16. As a user, I want the Desk Reminder countdown to freeze with the Work Block, so that a posture prompt is not due right after I return.
17. As a user, I want a pending Delay Break to survive a lock, so that the delayed break is not lost.
18. As a user, I want a Break to keep counting while the screen is locked, so that real rest time away counts as rest.
19. As a user, I want a Paused Work Block to survive plasmashell restart, logout, and reboot, so that a crash does not eat my remaining work time.
20. As a user, I want the Presence window to restart after a plasmashell restart, so that a stale timestamp cannot start a block after I was away.
21. As a user, I want the machine to keep working normally when the lock-state source is missing, so that a platform change degrades only the new features.
22. As a user, I want the auto-start and pause rules documented in the glossary and an ADR, so that future changes do not silently break the time contract.

## Scenarios

These scenarios extend `features/pomodoro.feature`.

```gherkin
Feature extension: Presence-driven auto-start and lock-paused Work Blocks

  Scenario: Auto-start after the Presence window
    Given the widget is idle and auto-start is on for 5 minutes
    When the session stays unlocked for 5 minutes
    Then a Work Block of the Default Preset starts
    And one notification names the started preset
    And no chime plays

  Scenario: Presence below the threshold
    Given the widget is idle and auto-start is on for 5 minutes
    When the session locks after 3 unlocked minutes
    Then no Work Block starts
    And the Presence window is reset

  Scenario: Auto-start from Disabled after a lock
    Given the user disabled the timer for a meeting
    And the session stays unlocked for 30 minutes
    Then no Work Block starts
    When the session locks once and unlocks again
    And the session stays unlocked for 5 minutes
    Then a Work Block of the Default Preset starts

  Scenario: Auto-start never interrupts timing
    Given a Work Block or a Break or the finished-break wait is active
    When the session stays unlocked for 5 minutes
    Then no auto-start occurs

  Scenario: A locked screen pauses the Work Block
    Given a Work Block with 20 minutes remaining
    When the session locks
    Then the Work Block remaining time freezes at 20 minutes
    And the Desk Reminder countdown freezes
    When the session unlocks 30 minutes later
    Then the Work Block has 20 minutes remaining
    And the Desk Reminder resumes from its frozen time

  Scenario: A Break keeps its wall-clock deadline
    Given a Break with 8 minutes remaining
    When the session locks for 10 minutes
    Then the Break deadline is unchanged
    And after unlock the overlay waits with Continue enabled

  Scenario: A Paused Work Block survives a restart
    Given a Paused Work Block with 12 minutes remaining
    When plasmashell restarts
    Then the Work Block is still paused with 12 minutes remaining
    When the session unlocks
    Then the Work Block resumes with 12 minutes remaining

  Scenario: Auto-start is off
    Given auto-start is off
    When the session stays unlocked for 60 minutes
    Then no Work Block starts

  Scenario: Missing Default Preset falls back
    Given auto-start is on and the star is missing or invalid
    When the Presence window elapses
    Then a 50/10 Work Block starts

  Scenario: The lock source is unavailable
    Given the lock state cannot be read
    Then auto-start and Work Block pause are off
    And manual start, continue, skip, delay, disable, and enable still work

  Scenario: Auto-start minutes stay in range
    Given the user edits the auto-start delay
    When the value is outside 1 to 60
    Then the stored value stays within 1 to 60
```

## Implementation Decisions

### Domain state

The pure state machine gains these host-supplied fields: `autoStartEnabled` (boolean), `autoStartMinutes` (integer 1–60), and `presenceSince` (epoch ms, 0 = no window). It gains these machine-owned fields: `locked`, `autoStartArmed`, `paused`, `pausedRemainingMs`, and `deskPausedRemainingMs`.

- `autoStartEnabled` and `autoStartMinutes` are config, supplied by the host on load and on change, like the Desk Reminder fields.
- `presenceSince` is set by the host only through the lock and unlock intents. It is never persisted.
- `autoStartArmed` is true when Auto-start may leave Disabled. A manual Disable sets it false. A screen lock while Disabled sets it true. It is persisted.
- A Paused Work Block has no active work deadline. Its remaining time lives in `pausedRemainingMs`; the Desk Reminder remaining time lives in `deskPausedRemainingMs`. Both are persisted.

### Lock and unlock intents

- `screenLocked` sets `locked` true and clears `presenceSince`. While Disabled it sets `autoStartArmed` true. While a Work Block runs unpaused, it sets `paused` true, copies the remaining work and desk times into the frozen fields, and clears both deadlines. It emits no effect.
- `screenUnlocked` sets `locked` false and starts a fresh `presenceSince` at the current instant. While a Paused Work Block exists, it clears `paused` and restores both deadlines as the current instant plus the frozen remaining times. It emits no effect.
- Repeated lock or unlock observations with no change are identity no-ops.
- Lock and unlock never change a Break, the finished-break wait, the idle phase, or a Disabled phase beyond the arm flag.

### Presence tick and auto-start

- A dedicated `presenceTick` intent checks Auto-start. It is the only path to an automatic start, and it is testable with a fake clock.
- The check requires: `autoStartEnabled` true, `locked` false, the phase is idle or Disabled, a valid `presenceSince`, and elapsed time at least `autoStartMinutes × 60 000`. From Disabled it also requires `autoStartArmed` true.
- A valid result starts a Work Block through the normal work transition with `defaultPreset || DEFAULT_PRESET`, clears the Presence window, and emits one `notifyAutoStart` effect carrying the preset's derived label. No chime, no overlay effect, except a defensive `hideOverlay` when a restored state still carries a due desk prompt.
- `presenceTick` never starts work from `work`, `break`, or `wait`. It never resumes a delayed break or the finished-break wait.
- Hostile values are guarded: a non-finite, zero, or future `presenceSince` cannot start a block; minutes round to an integer and clamp into 1–60, with 5 as the fallback for non-numeric junk.
- The machine's normal `tick` skips the work-expiry and desk steps while `paused` is true, so a paused block cannot expire behind the lock screen.

### Pause and resume

- Only a Work Block pauses. A Break, the finished-break wait, and the idle or Disabled phases keep their existing behavior.
- Pause freezes the remaining work time and the remaining Desk Reminder time. Resume shifts both deadlines by the paused duration. The user receives the full remaining block.
- A lock at or after the work deadline does not pause a finished block: the next tick starts the Break anchored at the original expiry, so locked time counts as Break time.
- An outage marks the session away without pausing a running block. When the source recovers while the session is still locked, the first real lock observation pauses the block, so recovered locked time is not counted as work.
- A Desk Reminder whose deadline is reached at the lock instant but not yet observed by a tick freezes as due; the prompt fires on the first resume tick instead of becoming a fresh full interval.
- A pending Delay Break (`pendingBreak` true) is preserved across the pause. A Delay intent that reaches a paused block (a defensive path; the card disables the control) adds five minutes to the frozen work time and keeps the block paused, so the extension cannot be lost on unlock. Start break now is disabled while paused; the block must resume before it can end early.
- Starting a fresh Work Block, entering a Break, entering the wait, and Disable all clear the pause fields.
- The panel's remaining-time display reads `pausedRemainingMs` while paused, so a frozen timer looks frozen, not broken.

### Host integration

- A Presence monitor observes the session lock state over the session bus. On Plasma 6.7.5 the installed QML D-Bus bridge provides the session bus and signal watching. The lock signal is the screen saver active state (`org.freedesktop.ScreenSaver.GetActive` and its `ActiveChanged` signal); `org.freedesktop.login1` `LockedHint` is the documented fallback when the screen saver service is absent.
- The monitor dispatches `screenLocked` and `screenUnlocked` only on transitions, never on every poll. Polling the current state once per second is the safety net for a missed signal.
- The logind fallback is polled once per second; the screen-saver signal is the primary path. The monitor runs behind a Loader with a logging fallback, following the existing optional-integration pattern. When the source is unavailable it reports that state once and the new behavior stays off: a `presenceUnavailable` intent closes the Presence window and treats the session as away until a fresh observation. The monitor forgets its applied observation on an outage, so the first successful poll after recovery re-applies the current state instead of deduping against stale data. Manual behavior is unaffected, except that a Work Block already paused by a lock stays frozen until the source returns (Disable then Enable is the manual recovery).
- A dedicated one-second Presence timer dispatches `presenceTick` while the machine is loaded and in the idle or Disabled phase. The existing phase heartbeat keeps its current condition and cadence, so Disabled stays heartbeat-free.
- The auto-start notification is a new host effect. It sends one desktop notification titled "Pomodoro started", with the started preset's derived label in the body (for example, "Work block 50/10 started automatically"). The notification is informational: no action buttons, no sound. Failure to send is logged and never blocks or delays the start.
- Auto-start starts silently in the machine. It does not chime and does not open the popup.

### Configuration and card

- Two new config entries: `autoStartEnabled` (boolean, default true) and `autoStartMinutes` (integer, default 5).
- The card settings page gains an Auto-start section below the Desk Reminder controls: an "Auto-start" label, an on/off switch, a 1–60 minute spinbox, and a wrapped hint line. The hint explains the Presence rule and the re-arm rule. When the lock source is unavailable, the hint says so and the switch is inert.
- The card writes config through the existing outbound-signal pattern; the host echoes the stored values back. The machine receives the values on load and on every config change.
- Enabling Auto-start takes effect on the next Presence tick. It does not reset an existing Presence window. A window already past the configured duration starts a block at the next tick.
- The card keeps its pinned width and constant frame. Any wrapped hint reserves its height with the existing reserved-height helper. The end-work controls (Delay, Start break now) are disabled while a Work Block is paused.

### Persistence and restore

- The state snapshot gains `paused`, `pausedRemainingMs`, `deskPausedRemainingMs`, and `autoStartArmed`. It does not gain the Presence window or the raw lock state.
- A restored Paused Work Block keeps its frozen remaining times and does not tick toward a Break. It resumes on the next unlock observation.
- The snapshot validator accepts a work phase with no deadline only while `paused` is true. Pause fields are dropped when the restored phase is not work.
- On restore, `autoStartArmed` defaults to false when absent or invalid, so an old or hand-edited snapshot can never auto-start out of a manual Disable. The Presence window starts empty; the first unlocked observation opens it.
- The paused flag, frozen times, and arm flag participate in the host's tick change detection, so a change made by a tick is persisted.

## Testing Decisions

- The pure state machine remains the one primary seam. Every new behavior is asserted through intents and state, never through private fields:
  - lock pauses a Work Block and freezes the Desk Reminder;
  - unlock resumes both from the frozen times;
  - a Break ignores lock and unlock;
  - `presenceTick` at exactly N minutes starts the Default Preset from idle;
  - below N it does nothing;
  - a lock resets the window;
  - Disabled requires a prior lock before auto-start fires;
  - auto-start never fires from work, break, or wait;
  - the notification effect carries the preset label and no chime;
  - the missing-star fallback starts 50/10;
  - hostile minutes and timestamps cannot start a block;
  - a Paused Work Block survives a restore and does not expire;
  - a pending Delay Break survives the pause;
  - enabling or disabling Auto-start cannot bypass the above.
- The headless card test covers the new settings row, the 1–60 spinbox bounds, the config writes, the inert switch when the source is unavailable, the paused action-button guards, and the constant-frame contract, following the existing Desk Reminder tests.
- A small headless test of the Presence monitor's observation contract verifies that an observation the controller could not apply is retried, not recorded and swallowed, that repeated observations dedup, that a null controller records nothing, and that a source outage resets the applied observation so recovery re-applies it.
- Machine tests pin the boundary cases: a lock at the work deadline keeps the original Break anchor, a lock at the desk deadline keeps the due prompt, a Delay intent on a paused block extends the frozen time, an outage-then-lock sequence still arms Auto-start from Disabled, and a lock observed after an outage pauses a still-running block.
- The D-Bus monitor's live path and the notification are thin adapters, verified manually on the live session. The manual checklist covers a lock during work, a lock during a break, a lock during a meeting, a Disable re-arm, and a notification. The host snapshot validator is exercised through the machine's restored-raw-state test and the live restart check.
- A paused work block's persistence is asserted at the machine seam from the exact restored shape; the host's snapshot validator is a manual restart check, as with the existing phase restore.
- The existing validation gate runs every stage: lint every QML file, run every machine and card test, and validate the chime asset. New QML files and test files are picked up by the existing globs.

## Out of Scope

- Keyboard or mouse idle-time measurement. Presence is the unlocked session.
- Focused-window detection.
- Pausing a Break, including while locked.
- Auto-continuing from the finished-break wait.
- Auto-start while a Work Block, a Break, or the wait is active.
- Notification actions, sounds, or history.
- Multiple monitors or per-screen presence.
- Lock sources beyond the screen saver and logind signals.
- A screen that only blanks through DPMS without locking or activating the screen saver.

## Further Notes

- The Presence heuristic is an explicit operator decision: an unlocked desktop means the user is at the computer. It is intentionally not an input-idle measurement.
- The pause rule amends the wall-clock deadline contract for Work Blocks only. ADR-0003 records why, and the glossary records the exception.
- The settings default is on, because the operator asked for the timer to start itself.
- The notification is the only new effect. The existing chime remains reserved for Break start and the Desk Overlay.
