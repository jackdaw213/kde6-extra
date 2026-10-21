# SPEC: Pomodoro Panel Widget for Plasma 6

Status: ready-for-agent
Work item: a6ddf887-9c47-4d4d-ab62-5767186c83ed (idea-to-ship)
Glossary: `CONTEXT.md` · ADRs: `docs/adr/0001-kwin-script-overlay.md`

## Problem Statement

When working long sessions I lose track of breaks entirely — I either never rest, or I rest so long I lose momentum. Existing pomodoro widgets are polite notifications I can ignore; they don't *enforce* rest, they don't fit my preferred 50/10 rhythm, and none of them pause my music or help me gracefully finish "just two more minutes" of a task.

## Solution

A Plasma 6 panel widget that runs Work Blocks and Breaks on selectable presets (50/10 default). When a Work Block expires, a fullscreen, always-on-top overlay blows the entire screen announcing rest time, pausing all media. The break runs its course with Continue disabled; afterward the overlay waits patiently for however long I actually rest. I can skip a break (with confirmation), delay one by five minutes, extend or shorten via custom values, disable everything for a meeting, and trust that reboots never distort a running timer. Every 4th work block earns a large break.

## User Stories

1. As a user, I want a small Pomodoro icon in my Plasma panel, so that my focus timer is always one glance away.
2. As a user, I want the panel icon to show the remaining time while a timer runs, so that I know how long is left without opening anything.
3. As a user, I want left-click on the idle icon to open a popup of presets, so that starting a block is one click.
4. As a user, I want 50/10 as the default preset, with 25/5 and 45/15 also offered, so that my preferred rhythm is the path of least resistance.
5. As a user, I want to edit presets and add my own (work, break) pairs, capped at 5 total, so that the list stays short and personal.
   *(Superseded by SPEC-002: six fixed slots — three locked Built-ins + three user presets — all managed in the popup card; the Default Preset is chosen, not positional.)*
6. As a user, I want to set a fully custom one-off (work, break) pair, so that I'm not limited to the preset list.
   *(Superseded round 2: the Custom one-off row was removed — user presets cover it; the machine still starts any preset payload.)*
7. As a user, I want a work block to expire into a break automatically, so that rest is guaranteed, not remembered.
8. As a user, I want the break to blow the entire screen with a fullscreen overlay, so that I physically cannot miss that it's rest time.
9. As a user, I want the overlay to beat even fullscreen applications, so that a game or video can't hide my break from me.
10. As a user, I want the break timer to start the instant the screen is blown, so that no time is lost between work ending and rest beginning.
11. As a user, I want a chime at break start, so that I'm alerted even when not looking at the screen.
    *(Superseded by SPEC-002: the chime is a bundled soft piano arpeggio, played at break start AND when the Desk Overlay appears.)*
12. As a user, I want my playing music/videos to pause when a break starts, so that rest actually means resting (paused media never auto-resumes).
13. As a user, I want the "Continue back to work" button disabled and grayed out for the whole break duration, so that I'm not tempted to cut rest short by accident.
14. As a user, I want Continue to enable exactly when the break timer finishes and then wait indefinitely, so that taking 12 or 15 minutes instead of 10 costs me nothing and involves no second timer.
15. As a user, I want Continue to start a fresh full work block, so that returning to work always means a complete block.
16. As a user, I want a separate Skip control available during the break, guarded by a confirmation click, so that when I'm mid-flow I can deliberately return to work immediately.
17. As a user, I want the overlay to show the remaining break time, so that I know how long I have.
18. As a user, I want a "Delay break 5 minutes" button when a work block expires, so that I can finish a small urgent task before resting; each click adds 5 more minutes.
19. As a user, I want a "Start break now" action in the panel popup while work is running, so that I can cut a delayed work period short when my task finishes early.
20. As a user, I want every 4th work block's break to be a Large Break (three normal, then one large), so that I get a deeper rest on a sustainable cadence.
21. As a user, I want the Large Break length derived automatically (break ≤6 min → 20; 7–12 → 30; ≥13 → 40) unless my preset specifies one, so that large rests scale sensibly without my input.
22. As a user, I want the cycle to advance on every completed work block — even ones whose break I skipped — so that a large break always arrives on schedule.
23. As a user, I want "Disable for now" in the popup, so that a 30-minute meeting doesn't fight my timer.
24. As a user, I want re-enabling after disable to start a fresh default work block, so that coming back is predictable.
25. As a user, I want running phases tracked by wall-clock deadlines, so that logout, reboot, or a plasmashell crash never loses or stretches a timer.
26. As a user, I want to set custom work and break lengths, so that the tool bends to my day rather than the reverse.

## Scenarios (Gherkin)

Executable scenarios also live in `features/pomodoro.feature`.

```gherkin
Feature: Pomodoro panel widget

  Scenario: Starting the default preset
    Given the widget is idle
    When I click a preset in the popup
    Then a Work Block of that preset's work length starts
    And the panel icon shows the remaining time

  Scenario: Work block expiry blows the screen
    Given a Work Block is running
    When the wall-clock deadline passes
    Then the Break overlay covers the entire screen
    And the break deadline is the expiry instant plus the preset's break length
    And all MPRIS media is paused
    And a chime plays

  Scenario: Continue is locked until the break ends
    Given the Break overlay is up
    Then the Continue button is disabled and grayed out
    When the break deadline passes
    Then the Continue button becomes enabled and stays enabled indefinitely

  Scenario: Taking a longer break naturally
    Given the break timer has finished and the overlay still waits
    When I press Continue at any later moment
    Then a fresh Work Block of the current preset starts immediately

  Scenario: Skipping a break in flow
    Given the Break overlay is up and the break timer is still running
    When I press Skip and confirm
    Then the overlay closes and a fresh Work Block of the current preset starts immediately
    And the cycle advances as if the break had run fully

  Scenario: Delaying a break
    Given the Break overlay is up
    When I press "Delay break 5 minutes"
    Then the overlay closes, the break is not counted, and work resumes with the deadline extended 5 minutes
    And pressing it again extends by 5 more minutes

  Scenario: Cutting a delayed period short
    Given a Delay Break is active with time remaining
    When I choose "Start break now" in the panel popup
    Then the pending break starts immediately

  Scenario: Large break on cadence
    Given the cycle counts every completed Work Block
    When the 4th Work Block expires
    Then the Break is a Large Break
    And its length is the preset's explicit large-break value if set
    And otherwise derived: break ≤6 min gives 20, 7–12 gives 30, ≥13 gives 40

  Scenario: Skipped break keeps cadence honest
    Given a work block whose break was skipped
    When the next work block completes
    Then the cycle has advanced by two

  Scenario: Disable for a meeting
    Given any state
    When I choose "Disable for now"
    Then all timing, overlay, and media-pause behavior is suspended
    And re-enabling starts a fresh default (50/10) Work Block
    *(Re-enabling target superseded by SPEC-002: the Default Preset, chosen in the card.)*

  Scenario: Reboot mid-phase
    Given a Work Block or Break with a wall-clock deadline was running
    When the session restarts before that deadline
    Then the phase resumes with its original deadline intact

  Scenario: Custom values
    Given the popup's custom editor
    When I set any work and break minute pair and start
    Then that one-off pair governs the block exactly like a preset

  Scenario: Preset cap
    Given the user edits presets
    When they try to add a 6th preset
    Then the addition is refused with an explanatory message
```

## Implementation Decisions

- **Shape**: a single Plasma 6 Plasmoid (QML 6). The break overlay is owned by the widget itself and rendered on a Wayland layer-shell surface at the Overlay layer via LayerShellQt (ADR-0001 as amended by ADR-0002), so its buttons call the machine in-process — no IPC anywhere. The KWin-script approach was abandoned after live probes proved no intent channel can exist from KWin declarative scripts (see ADR-0002).
- **State machine**: all domain behavior (phases, deadlines, cycle, presets) lives in one pure QML/JS module — `pomodoro-machine.js` — with no Qt/Plasma imports. Intents in (`startPreset`, `tick`, `skipBreakConfirmed`, `delayBreak`, `startBreakNow`, `disable`, `enable`), state snapshot out. Pure means it is the single test seam (below).
- **Time**: every phase stores an absolute wall-clock deadline (epoch ms), never a countdown. Remaining time is `deadline − now`. Persistence = writing the deadline into the Plasmoid config; restoration = recompute on load. A deadline already passed at restore time transitions immediately (work expiry → break; break expiry → enabled-continue wait). *(Amended by SPEC-003 and ADR-0003: a Work Block paused by a screen lock has no active deadline and shifts its deadline by the paused duration on resume. Breaks keep this wall-clock rule.)*
- **Overlay contract**: the overlay is a widget-owned window bound to the controller's state: rest message, remaining mm:ss (from the wall-clock deadline, restart-surviving), Continue (disabled until break deadline, grayed), Skip (two-click confirm-guarded), Delay 5. Button handlers dispatch machine intents directly.
- **Media pause**: at break start, enumerate MPRIS2 players on the session bus and call Pause on each. No resume path exists anywhere.
- **Chime**: freedesktop sound-theme event (libcanberra or `KNotification`), played only at break start. *(Superseded by SPEC-002: bundled soft piano-style Ogg in the plasmoid, at break start and Desk Overlay.)*
- **Cycle**: integer counter in persisted config; incremented on every Work Block completion (expiry or "start break now"); break skip does not touch it. Large break due when `counter % cycleLength === 0` with `cycleLength` defaulting to 4. Cycle length is user-configurable; the large-break derivation thresholds are fixed constants (see SPEC-002 round 5); per-preset explicit large-break minutes override derivation. *(Round 3b note: `cycleLength` is config-file-only since the Configure Presets page was removed; per-preset large-break editing is consciously deferred — see SPEC-002.)*
- **Presets**: stored in the Plasmoid config as a list of {label, workMin, breakMin, largeBreakMin?}; default seed 50/10, 25/5, 45/15; editor enforces the 5-total cap. *(Superseded by SPEC-002: six fixed slots — three locked Built-ins + three user presets — managed in the popup card.)*
- **Panel UI**: Kirigami-based plasmoid representation; icon swaps to remaining-time text while running; popup lists presets, Custom…, Start break now (when applicable), Disable for now. *(Superseded rounds 2–3: popup is a two-page card — 2×3 preset grid with dashed empty slots, gear-opened settings page with add/edit/delete/star and Desk Reminder; no Custom row.)*
- **Packaging**: standard Plasmoid package (`metadata.json`, `ui/`, `contents/`), installable via `kpackagetool6 -t Plasma/Applet`.

## Testing Decisions

- **The one seam**: `pomodoro-machine.js` — a pure function/intent module exercised by `qmltestrunner` (Qt 6 QML tests) via a thin test harness that injects a fake clock. Everything externally observable (overlay content, button enablement, cycle math, deadline persistence semantics) is asserted through the machine's emitted state.
- Good tests assert *behavior at the seam*: given intent sequences and times, what state is exposed — never internal counters or shape of private helpers.
- Overlay rendering, DBus plumbing, and sound playback are integration surfaces verified manually (documented checklist), not unit-tested — they are thin adapters by design.
- No prior art exists (greenfield); tests live under `tests/`.

## Out of Scope

- Multi-monitor overlay spreading (single display).
- Lock sources beyond the screen saver and logind, or kiosk-grade tamper-proofing.
- Statistics/history of past blocks.
- Auto-resuming media (explicitly never).
- Non-KDE environments.

## Further Notes

- All decisions trace to the grilling session; glossary terms (Work Block, Break, Preset, Large Break, Cycle, Skip, Delay Break, Start Break Now, Disabled for now, Media Pause, Wall-clock deadline) are defined in `CONTEXT.md` and used here deliberately.
- SPEC-003 adds Presence-driven auto-start and lock-paused Work Blocks. It supersedes the wall-clock guarantee for a paused Work Block only.
- Overlay language: the overlay announces "Rest time" with remaining break time.
