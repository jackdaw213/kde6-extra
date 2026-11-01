# SPEC 004: Working-hours gate for Auto-start

Status: ready-for-agent
Work item: 1996e4fc-2ef5-4d00-88cb-71772692183c (idea-to-ship)
Glossary: `CONTEXT.md` ("Working hours", "Auto-start") · Parent spec: `docs/SPEC-003-presence-auto-start.md`

## Problem Statement

Auto-start starts a Work Block whenever the Presence window elapses, at any hour. I unlock my computer in the evening or overnight and the timer starts itself at times when I am not working. The automatic start should honor my working day: it belongs between nine and five.

## Solution

Auto-start fires only inside Working hours — 9:00 to 17:00 local time, every day. The gate applies at the instant of the automatic start: Presence accrued outside Working hours still counts toward the Presence window, and a Work Block started inside Working hours is never cut short by their end. Manual starts are never gated. There is no new configuration: the hours are fixed constants.

## User Stories

1. As a user, I want Auto-start to fire only between 9:00 and 17:00, so that the timer never starts itself outside my working day.
2. As a user, I want Presence accrued before 9:00 to count toward the Presence window, so that sitting down at 8:50 starts my block at 9:00 rather than 9:05.
3. As a user, I want the 9:00 edge to be inclusive, so that a window elapsing exactly at 9:00 starts the block.
4. As a user, I want the 17:00 edge to be exclusive, so that a window elapsing at 17:00 does not start a block that evening.
5. As a user, I want a window that elapses outside Working hours to start the block at the first in-hours instant, so that an overnight-unlocked session defers to the next 9:00 instead of firing at night.
6. As a user, I want a block started at 16:59 to run its full length past 17:00, so that the gate governs starts, not runs.
7. As a user, I want the meeting-mode (Disabled) re-arm path to respect Working hours too, so that a re-armed Disable cannot start a block in the evening.
8. As a user, I want the gate on every day of the week, so that Saturday mornings behave like Monday mornings.
9. As a user, I want manual starts (presets, Enable, Continue, Skip, Delay) to work at any hour, so that the gate never blocks a choice I make myself.
10. As a user, I want no new settings for the hours, so that the card stays as it is.

## Scenarios

These scenarios extend `features/pomodoro.feature`.

```gherkin
Feature extension: Working-hours gate for Auto-start (SPEC-004)

  Scenario: Auto-start fires inside Working hours
    Given the widget is idle and auto-start is on with a 5 minute window
    When the Presence window elapses at 10:00 local time
    Then a Work Block of the Default Preset starts

  Scenario: Auto-start does not fire outside Working hours
    Given the widget is idle and auto-start is on with a 5 minute window
    When the Presence window elapses at 08:00 local time
    Then no Work Block starts
    And the Presence window stays open

  Scenario: Presence accrued before 9:00 counts
    Given the widget is idle and auto-start is on with a 5 minute window
    When the session unlocks at 08:56 local time
    And the Presence window has elapsed by 09:00 local time
    Then a Work Block of the Default Preset starts at 09:00

  Scenario: The 17:00 edge is exclusive and defers to the next morning
    Given the widget is idle and auto-start is on with a 5 minute window
    When the Presence window elapses at 17:00 local time
    Then no Work Block starts
    When the window is still elapsed the next morning at 09:00 local time
    Then a Work Block of the Default Preset starts

  Scenario: A block started before 17:00 is not clipped
    Given the Presence window elapses at 16:59 local time
    Then the Work Block starts with its full work length
    And it is not cut short when 17:00 passes

  Scenario: The re-armed Disabled path respects Working hours
    Given I chose "Disable for now" and the session has since locked once
    When the Presence window elapses at 20:00 local time
    Then no Work Block starts
    When the window is still elapsed at 09:00 the next morning
    Then a Work Block of the Default Preset starts

  Scenario: The gate applies every day
    Given the widget is idle and auto-start is on
    When the Presence window elapses on a Saturday at 10:00 local time
    Then a Work Block of the Default Preset starts

  Scenario: Manual starts ignore the gate
    Given the widget is idle at any hour outside Working hours
    When I click a preset, Enable, Continue, Skip, or Delay
    Then the action works exactly as it does inside Working hours
```

## Implementation Decisions

- The Working-hours rule is Auto-start policy and lives in the pure state machine, the one test seam. Two module constants define the span: start 9, end 17, as minutes-of-day bounds (540 inclusive, 1020 exclusive).
- The gate is a pure predicate of the tick instant: it converts the epoch-ms `now` to local wall-clock minutes-of-day and admits the automatic start only when the instant lies in `[9:00, 17:00)`. Local conversion uses the standard date API on the supplied `now`; the machine gains no host dependency and no new config field.
- `presenceTick` applies the gate after its existing guards (enabled, unlocked, phase, arm, window) and before the start transition. A rejected tick returns the state unchanged — the Presence window stays open, so time accrued outside hours keeps counting and the first in-hours tick fires.
- Because the gate sits inside `presenceTick`, both auto-start paths (Idle, and Disabled after a Screen lock re-arms it) respect Working hours with no extra code.
- No other intent is touched. Manual starts, the pause/resume machinery, Breaks, and the wall-clock deadline contract are unchanged; nothing persists.
- The machine's documentation comment on Auto-start names the gate so the policy is discoverable at the seam.

## Testing Decisions

- Good tests assert external behavior through intents and state at the machine seam — never private fields, never the UI.
- Module: the existing machine test suite (prior art: the `presenceTick` block of `tst_machine.qml`).
- Local-time determinism: tests build in-hours and out-of-hours instants with the standard date API from a fixed day anchor (`atLocalHour(hour, minute)`), so the suite is timezone-independent and pins the contract "9:00 local" rather than an implementation echo.
- New boundary tests: no fire below the window outside hours (08:00); fire at exactly 9:00 with presence opened before 9:00; no fire at exactly 17:00 with fire deferred to the next morning's 9:00; full-length block from a 16:59 start; gated Disabled re-arm path; a Saturday fire pinning the every-day rule.
- The gate's arrival invalidates the existing `presenceTick` tests' clock: their fixed UTC anchor falls outside Working hours. They are rebased onto an in-hours day anchor — same window assertions, now on a compliant clock. That rebasing is part of the change, not a test weakening.
- A manual-start regression pin (`startPreset` outside Working hours still enters work) guards against over-gating.
- No card, monitor, or notification tests: no UI, host, or effect changes exist.

## Out of Scope

- Configurable Working hours.
- Weekday gating (Monday-to-Friday).
- Clipping, pausing, or otherwise limiting a block that runs past 17:00.
- Gating manual starts of any kind.
- Resetting the Presence window at the hours' edges or at midnight.
- Any change to notifications, the chime, the overlay, or persistence.

## Further Notes

- The operator chose fixed hours (9–5, every day) over configurable hours and gate-at-fire-time over an in-hours-only Presence window. Both decisions are recorded in the glossary's "Working hours" entry.
- The overnight-unlocked case changes observable behavior deliberately: previously a block started ~5 minutes after an evening unlock; now it defers to 9:00 the next morning. The documented Presence heuristic (unlocked = present) is unchanged.
- No ADR: the decision is easily reversible and carries no surprising trade-off; the glossary entry and this spec carry the context.
