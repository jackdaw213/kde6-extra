# SPEC 002: Preset grid, in-card preset management, Desk Reminder, pleasant chime

Status: ready-for-agent
Work item: 62753271-8a6b-4a21-9fa0-e83472b88ae2 (idea-to-ship)
Glossary: `CONTEXT.md` · Parent spec: `docs/SPEC.md`

## Problem Statement

The widget's preset list wastes space (one full-width button per preset), holds at most 5 presets with the first fixed as default, and can only be edited in the Configure dialog — far from where presets are used. Additionally, long sitting at one desk height is never prompted, and the break-start chime is a harsh alarm that rings too long.

## Solution

Six preset slots laid out as a 2×3 grid with slightly larger font: three locked Built-ins (50/10, 25/5, 45/15) and three user-defined slots. Creating, replacing, deleting user presets and choosing the Default Preset (star, any slot) all happen inside the popup card; the Configure dialog's Presets page is removed. A separate Desk Reminder (default 30 min, user-configurable, on/off toggle in the card) counts only during Work Blocks; on expiry a fullscreen overlay says to change desk height by doing the reverse of what you're doing now, acknowledged with one button that resets the countdown. The Work/Break machine is untouched in precedence: a due Break always wins over a pending Desk Overlay. The chime becomes a bundled, soft ~2–3 s piano arpeggio, played at Break start and at Desk Overlay appearance.

## User Stories

1. As a user, I want presets shown as a 2-row × 3-column grid, so that six rhythms fit compactly in the popup.
2. As a user, I want the preset buttons to use a slightly larger font, so that they are comfortable to read at a glance.
3. As a user, I want the three Built-in presets (50/10, 25/5, 45/15) always present and undeletable, so that I can never lose the classic rhythms.
4. As a user, I want three user-defined preset slots, so that I can add my own rhythms alongside the Built-ins.
5. As a user, I want to edit (replace) a user preset's name, work, and break minutes inside the popup card, so that adjusting rhythms needs no trip to the Configure dialog. *(Superseded round 5: there is no name field — the label derives from the minutes; see the Round 5 amendment.)*
6. As a user, I want to delete a user preset in the card, so that pruning my list is immediate.
7. As a user, I want to add a user preset in the card (capped at three user slots), so that growth is bounded and the grid stays 2×3.
8. As a user, I want to mark any of the six presets as the Default Preset from the card, so that the starred rhythm starts with Enable / re-enable without depending on list position.
9. As a user, I want the Configure dialog to no longer contain a Presets page, so that there is exactly one place to manage presets.
10. As a user, I want a Desk Reminder that counts down only while a Work Block is timing, so that rest periods and meetings don't advance it.
11. As a user, I want the Desk Reminder to reset to its full interval at every Work Block start, so that each block begins a fresh posture interval.
12. As a user, I want a fullscreen overlay when the Desk Reminder expires, telling me to change my standing-desk height by doing the reverse of what I'm doing now, so that I alternate sitting/standing without the widget modeling which one I'm in.
13. As a user, I want a single button on the Desk Overlay ("Done — I switched") that dismisses it and resets the countdown, so that acknowledging is one action.
14. As a user, I want a due Break to take precedence over the Desk Overlay, so that enforced rest is never blocked by a posture prompt.
15. As a user, I want the Desk Reminder's interval (default 30 min) and on/off toggle in the card, so that tuning it needs no Configure dialog.
16. As a user, I want the Desk Reminder OFF to leave no overlay and no countdown, so that disabling is complete.
17. As a user, I want a soft piano-style chime of roughly 2–3 seconds instead of the harsh alarm, so that break start is pleasant, not jarring.
18. As a user, I want the same chime when the Desk Overlay appears, so that the posture prompt gets my ears, not only my eyes.
19. As a user, I want the Desk Reminder to survive restarts like the main timer (wall-clock), so that rebooting mid-block doesn't drop or stretch the posture countdown.
20. As a user, I want clicking a preset in the grid to behave exactly as before (starts that Work Block immediately), so that the layout change doesn't alter muscle memory.

## Scenarios (added to features/pomodoro.feature)

See "Scenario:" additions in `features/pomodoro.feature` — executable specification for grid layout, card editing, default star, desk reminder lifecycle, overlay precedence, and chime scope.

## Implementation Decisions

- **Presets storage stays one JSON config string**, always holding exactly six entries: indexes 0–2 are the seeded Built-ins (restored if a user hand-edits them away), indexes 3–5 are User Presets (empty slot = null). Locking is a storage policy: the card editor never writes Built-in entries.
- **New config entries**: `defaultPreset` (Int index, default 0) replaces "first preset is default"; `deskReminderEnabled` (Bool, default false); `deskReminderMinutes` (Int, default 30). The old "cap of 5" comment/UI is gone.
- **Desk Reminder lives in the state machine** (`pomodoro-machine.js`): new state fields `deskDeadline` (epoch ms, 0 = not running) and `deskDue`; machine inputs gain `deskEnabled`/`deskMinutes` (from config, host-supplied like `cycleLength`). While phase is "work" the desk deadline ticks like the work deadline; `startPreset` (fresh Work Block), `disable`, and the new `deskAck` intent reset/clear it. Expiry emits `showDeskOverlay` + `chime` effects and flips to a desk-due state that persists until acknowledged or superseded.
- **One overlay window, two modes**: `Overlay.qml` gains a desk mode bound to the controller's desk state. The Break overlay unconditionally wins: if the machine enters break/wait while the desk overlay is up, the window shows break content; after the next Work Block starts the desk countdown begins fresh. Desk mode needs no Continue/Skip machinery, just the title line and "Done — I switched" (dispatches `deskAck`).
- **Card layout**: the preset Repeater becomes a GridLayout (3 columns, 2 rows); preset buttons render from the six-slot model with the ★ on `defaultPreset`; management UI (edit user slots, delete, set default, desk interval + toggle) lives in a collapsed section of the card. Behavior while a Work Block times is unchanged (preset grid hidden; settings section may remain accessible but never disturbs the running machine).
  - *Live-operator amendment (round 3):* the hiding is superseded — the grid stays visible with all six cells disabled while the machine is timing, empty grid slots render as inert "—" dashes (creation moved into the settings page, one uniform row per user slot with an Add preset button when empty), and the card holds one constant frame sized by the settings page. Pinned by `tests/tst_full.qml`.
- **PresetEditor.qml and its ConfigCategory are deleted**; `config.qml` ends up empty of categories.
  - *Round 3b amendment:* per-preset explicit large-break editing (the old PresetEditor's `largeBreakMin` spinbox) is consciously deferred. The card editor commits only label/work/break; an explicit `largeBreakMin` reaches the machine solely via a hand-edited config, old values in the stored JSON are preserved and still override the derived rule (`largeBreakMinutes`), and no UI sets a new one.
  - *Round 5 amendment (SUPERSEDES the round-3b deferral; operator decisions):*
    - **Per-preset Large break is back in the card.** Each user row gains a "Large" spinbox (0–600, editable). 0 = the automatic rule (`largeBreakMinutes`: break ≤6→20, 7–12→30, ≥13→40). `updateUserPreset` mirrors the machine's storage convention: an explicit `largeBreakMin` is stored only when >0, and committing 0 (or junk) REMOVES any previously stored value — the spinbox is authoritative on every commit, nothing is carried forward. Hand-edited configs keep working (old explicit values still win).
    - **Derived naming.** A preset's label IS its minutes ("W/B"): `derivedLabel(workMin, breakMin)` is exported by the machine and `normalizePresetSlots` forces every user-slot label through it on read — the grid, star picker and rows all show derived labels with zero extra UI work. No name field exists anywhere; legacy hand-named entries ("custom", …) migrate on read. Consequently the Built-in-collision refusal (matchesBuiltin) is effectively minutes-only, the warning reads "Can't be identical to a Built-in — change the minutes." (static text, no name), and the Add-preset default is **30/5**: under minutes-only identity a 25/5 default would exactly equal a Built-in and locked storage would silently erase it on the next config echo.
    - The machine's startPreset/explicit-large preference is unchanged; regression tests pin that a UI-normalized entry (derived label, no `largeBreakMin` key) follows the auto rule and one with `largeBreakMin: N` uses N.
    - **Legacy migration edge (pinned, policy-consistent):** a hand-named user entry whose minutes equal a Built-in ("custom" 25/5) survives every read — dedup matches its raw stored label first — and displays as a visual duplicate of that Built-in tile, but it is not durable storage: the card's mutators persist the relabeled view, so the next read after any card write drops it. Storage converges silently one write after the migration; pinned by `test_slots_legacyBuiltinMinuteEntry_convergesOnNextWrite`.
  - *Round 6 amendment (operator decisions after the real-shell check; SUPERSEDES the two-line editor and the uncapped grid flex):*
    - **Fixed tile height.** Grid cells are ONE fixed height (2.5 grid units; the 14pt tile label measures 38px tall — probed) and the grid no longer has `Layout.fillHeight`: the main page is pure content, with no spare-height absorber (the round-5 uncapped flex was turning leftover frame pixels into giant tiles that covered the action buttons).
    - **One-line editor.** Each user row is [Work][spin][Break][spin][Large][spin][delete] on a single line (labels in the small font; spinboxes 3.5 grid units wide — the "600" value text still fits, probed). The reserved row height collapses to one control line, shrinking the three Add-preset rows and the frame-defining settings page.
    - **Wider card.** `implicitWidth` 17 → 21 grid units — the minimal probed width that fits the one-line editor row plus the desk controls row without eliding (editor row ~348px = labels 99 + spins 189 + delete 32 + seven 4px gaps 28, vs 351px of content width at the 18px reference unit; 20gu = 333px overflows; desk row ~223px never binds). The row-fit contract is pinned behaviorally (`presetEditRowN` implicitWidth ≤ width), not by arithmetic.
    - **Width-independent frame measure.** The two WordWrap hint labels (`largeBreakHint`, `deskHint`) reserve a FIXED height for their measured 2-line wrap (2.25 grid units, font-proportional) instead of an implicit height: a wrapped QQC2 Label's implicit height is width-dependent and late-settling (desktop style still reports the one-line height after two polish passes — probed), which sized the real popup once from a too-short first-pass measure and painted the desk row + hint past the dialog's bottom edge. Creation-pass implicitHeight == settled implicitHeight is pinned headless; the render sweep asserts zero out-of-frame descendants plus visible-in-window hints at ×1.0/×1.25/×1.5.
- **Chime**: generate a ~2.5 s gentle piano-like arpeggio (soft attack, exponential decay, 3 ascending notes) offline once, ship it as a small Ogg in the plasmoid contents, and point `Chimer.qml` at the bundled file. MediaPlayer + Loader + graceful-fallback structure unchanged.
- **Snapshot**: `stateSnapshot` gains desk fields so a restart mid-Work-Block restores the desk deadline by wall clock.

## Testing Decisions

- **The machine remains the primary seam** (existing `tests/tst_machine.qml`, "the one test seam"): desk-reminder lifecycle (count-only-in-work, reset on block start and ack, expiry effects, restart survival, break precedence), built-in-slot restoration, and (round 5) derived-label migration + the UI-normalized explicit-large contract. Pure intents + epoch-ms in, state + effects out — no mocking needed.
- **A headless QML test** for `FullRepresentation` grid/management behavior follows the existing `tests/tst_compact.qml` pattern (component created with a mock controller, no plasmashell), covering: 2×3 rendering with an empty user slot, star on the configured default, adding/deleting a user preset writes six-slot JSON, Built-in entries immutable — plus (round 5) no-name-field structure, the Large-spinbox contract and its always-laid-out hint line, and the compact reserved action strip (no full-width button; small-font secondary; phase-constant strip height).
- **Chime asset is validated structurally** (file exists, decodes, duration 2–3 s) in check.sh — not behaviorally, since audibility isn't headless-testable.
- Good tests assert observable state/effects only, never internal field bookkeeping beyond the machine's public state shape.

## Out of Scope

- Modeling which posture (sitting/standing) the user is in; the message is reversal-only.
- Per-phase desk intervals (e.g. different for standing vs sitting), desk-reminder scheduling during Breaks, or a second desk chime melody.
- Reordering presets, renaming Built-ins, more than three user slots.
- Any Configure dialog at all (cycleLength currently only reachable there stays as-is until a later change).

## Further Notes

Glossary updated in `CONTEXT.md` (Preset slots, Default Preset, Desk Reminder, Desk Overlay, Chime). The old "5 preset cap" everywhere (config comment, editor, glossary) is superseded by this spec.
