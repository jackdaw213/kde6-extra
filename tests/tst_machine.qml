// Tests for the Pomodoro state machine (the one test seam).
// Pure behavior: intents + wall-clock time in, state + effects out.
import QtTest 1.0
import "../plasmoid/contents/ui/pomodoro-machine.js" as Machine

TestCase {
    name: "PomodoroMachine"

    // Fixed wall-clock anchor: Thu Jan 1 2026 00:00:00 UTC, in epoch ms.
    readonly property real t0: 1767225600000
    readonly property int min: 60000

    function defaultPreset() {
        return { label: "50/10", workMin: 50, breakMin: 10 };
    }

    function freshState() {
        return Machine.initialState();
    }

    // --- Slice 1: start a preset from idle ---

    function test_startPreset_entersWorkPhaseWithDeadline() {
        var st = Machine.handle(freshState(),
                                { type: "startPreset", preset: defaultPreset() }, t0);
        compare(st.phase, "work");
        compare(st.deadline, t0 + 50 * 60000);
        compare(st.remainingMs(t0 + 60000), 49 * 60000);
        compare(st.preset.label, "50/10");
    }

    // --- Slice 2: work expiry starts the break ---

    function start50x10() {
        return Machine.handle(freshState(), { type: "startPreset", preset: defaultPreset() }, t0);
    }

    function test_workExpiry_startsBreakWithEffects() {
        var st = Machine.handle(start50x10(), { type: "tick" }, t0 + 50 * min + 1);
        compare(st.phase, "break");
        compare(st.deadline, t0 + 60 * min);      // anchored at the expiry instant
        compare(st.completedBlocks, 1);
        compare(st.effects.map(function (e) { return e.type; }),
                ["showOverlay", "pauseMedia", "chime"]);
    }

    function test_breakNotCounted_beforeExpiry() {
        var st = Machine.handle(start50x10(), { type: "tick" }, t0 + 49 * min);
        compare(st.phase, "work");
        compare(st.completedBlocks, 0);
        compare(st.effects.length, 0);
    }

    // --- Slice 3: break expiry enables Continue ---

    function startBreak() {
        return Machine.handle(start50x10(), { type: "tick" }, t0 + 50 * min + 1);
    }

    function test_continueDisabled_duringBreak() {
        compare(startBreak().continueEnabled, false);
    }

    function test_breakExpiry_enablesContinueAndWaitIndefinitely() {
        var st = Machine.handle(startBreak(), { type: "tick" }, t0 + 60 * min + 12345);
        compare(st.phase, "wait");
        compare(st.continueEnabled, true);
        compare(st.deadline, 0);           // no deadline: overlay waits indefinitely
        compare(st.effects.length, 0);     // overlay stays up, nothing new fires
    }

    function test_continueEnabledSurvivesTicks() {
        var st = Machine.handle(startBreak(), { type: "tick" }, t0 + 60 * min + 1);
        st = Machine.handle(st, { type: "tick" }, t0 + 75 * min);
        compare(st.continueEnabled, true);
    }

    // --- Slice 4: returning to work (Continue / Skip) ---

    function test_continueInWait_startsFreshWorkOfSamePreset() {
        var wait = Machine.handle(startBreak(), { type: "tick" }, t0 + 60 * min + 1);
        var st = Machine.handle(wait, { type: "continue" }, t0 + 75 * min);
        compare(st.phase, "work");
        compare(st.deadline, t0 + 125 * min);   // fresh 50 minutes from NOW
        compare(st.preset.label, "50/10");
        compare(st.effects.map(function (e) { return e.type; }), ["hideOverlay"]);
    }

    function test_skipConfirmedDuringBreak_startsFreshWorkImmediately() {
        var st = Machine.handle(startBreak(), { type: "skipBreakConfirmed" }, t0 + 52 * min);
        compare(st.phase, "work");
        compare(st.deadline, t0 + 102 * min);
        compare(st.completedBlocks, 1);         // counted at break start; skip changes nothing
        compare(st.effects.map(function (e) { return e.type; }), ["hideOverlay"]);
    }

    function test_continueIgnored_whileButtonDisabled() {
        var st = Machine.handle(startBreak(), { type: "continue" }, t0 + 52 * min);
        compare(st.phase, "break");             // the button is grayed out; nothing happens
    }

    // --- Slice 5: delaying the break / cutting a delay short ---

    function test_delayBreak_resumesWorkAndDoesNotCountBreak() {
        var st = Machine.handle(startBreak(), { type: "delayBreak" }, t0 + 51 * min);
        compare(st.phase, "work");
        compare(st.deadline, t0 + 56 * min);    // now + 5 minutes
        compare(st.pendingBreak, true);
        compare(st.completedBlocks, 0);         // the aborted break is not counted
        compare(st.effects.map(function (e) { return e.type; }), ["hideOverlay"]);
    }

    function test_delayBreak_repeatedClicksAddFiveMinutes() {
        var st = Machine.handle(startBreak(), { type: "delayBreak" }, t0 + 51 * min);
        st = Machine.handle(st, { type: "tick" }, t0 + 52 * min);
        st = Machine.handle(st, { type: "delayBreak" }, t0 + 53 * min);
        compare(st.deadline, t0 + 58 * min);
        compare(st.pendingBreak, true);
        compare(st.completedBlocks, 0);
    }

    function test_startBreakNow_duringWork_startsDueBreakImmediately() {
        var st = Machine.handle(start50x10(), { type: "startBreakNow" }, t0 + 20 * min);
        compare(st.phase, "break");
        compare(st.deadline, t0 + 30 * min);
        compare(st.completedBlocks, 1);
        compare(st.effects.map(function (e) { return e.type; }),
                ["showOverlay", "pauseMedia", "chime"]);
    }

    // --- Slice 6: large break cadence ---

    // Drive one full work→break→skip cycle; returns the state with the next work block running.
    function workBreakSkip(st, workDeadlineMs) {
        st = Machine.handle(st, { type: "tick" }, workDeadlineMs + 1);
        if (st.phase !== "break")
            return st;
        return Machine.handle(st, { type: "skipBreakConfirmed" }, workDeadlineMs + 2 * min);
    }

    function test_fourthBreak_isLarge_derivedFromRule() {
        var st = start50x10();
        // Three normal (50-min work) blocks, each break skipped.
        st = workBreakSkip(st, t0 + 50 * min);
        st = workBreakSkip(st, t0 + 102 * min);
        st = workBreakSkip(st, t0 + 154 * min);
        // 4th block expires at t0+206m → LARGE break: breakMin 10 → 30 by rule.
        st = Machine.handle(st, { type: "tick" }, t0 + 206 * min);
        compare(st.phase, "break");
        compare(st.largeBreak, true);
        compare(st.deadline, t0 + 236 * min);   // expiry + 30 min
        compare(st.completedBlocks, 4);
    }

    function test_fourthBreak_largeOverriddenByPresetValue() {
        var preset = { label: "25/5+12", workMin: 25, breakMin: 5, largeBreakMin: 12 };
        var st = Machine.handle(freshState(), { type: "startPreset", preset: preset }, t0);
        st = workBreakSkip(st, t0 + 25 * min);
        st = workBreakSkip(st, t0 + 52 * min);
        st = workBreakSkip(st, t0 + 79 * min);
        st = Machine.handle(st, { type: "tick" }, t0 + 106 * min);
        compare(st.phase, "break");
        compare(st.largeBreak, true);
        compare(st.deadline, t0 + 118 * min);   // expiry + explicit 12 min
    }

    function test_skippedBreaksKeepCadenceHonest() {
        var st = start50x10();
        st = workBreakSkip(st, t0 + 50 * min);          // block 1, break skipped
        st = workBreakSkip(st, t0 + 102 * min);         // block 2
        st = workBreakSkip(st, t0 + 154 * min);         // block 3
        compare(st.completedBlocks, 3);
        st = Machine.handle(st, { type: "tick" }, t0 + 206 * min);  // block 4 → large
        compare(st.largeBreak, true);
    }

    // --- Slice 7: disable for a meeting, arbitrary preset payloads ---

    function test_disable_stopsEverything() {
        var st = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        compare(st.phase, "disabled");
        compare(st.deadline, 0);
        compare(st.effects.length, 0);          // no overlay was up
    }

    function test_disable_duringBreak_hidesOverlay() {
        var st = Machine.handle(startBreak(), { type: "disable" }, t0 + 55 * min);
        compare(st.phase, "disabled");
        compare(st.effects.map(function (e) { return e.type; }), ["hideOverlay"]);
    }

    function test_enable_startsFreshDefaultWorkBlock() {
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        var st = Machine.handle(dis, { type: "enable" }, t0 + 40 * min);
        compare(st.phase, "work");
        compare(st.preset.workMin, 50);         // fresh default 50/10, not the old block
        compare(st.preset.breakMin, 10);
        compare(st.deadline, t0 + 90 * min);
        compare(st.completedBlocks, 0);
    }

    // --- Slice 14: Enable starts the Default Preset chosen in the card ---

    function test_enable_usesHostSuppliedDefaultPreset() {
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        dis.defaultPreset = { label: "25/5", workMin: 25, breakMin: 5 };
        var st = Machine.handle(dis, { type: "enable" }, t0 + 40 * min);
        compare(st.preset.label, "25/5");        // the starred slot, not list position
        compare(st.deadline, t0 + 65 * min);
    }

    function test_enable_withoutHostDefault_stillUsesBuiltIn50x10() {
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        dis.defaultPreset = null;
        var st = Machine.handle(dis, { type: "enable" }, t0 + 40 * min);
        compare(st.preset.label, "50/10");
    }

    function test_enable_withGarbageHostDefault_degradesToBuiltIn() {
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        dis.defaultPreset = { label: "x", workMin: NaN, breakMin: -3 };
        var st = Machine.handle(dis, { type: "enable" }, t0 + 40 * min);
        compare(st.preset.workMin, 50);
        compare(st.preset.breakMin, 10);
    }

    function test_tickIgnored_whileDisabled() {
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        var st = Machine.handle(dis, { type: "tick" }, t0 + 500 * min);
        compare(st.phase, "disabled");
    }

    // --- Slice 9: startPreset is a from-idle action ---

    function test_startPreset_refusedWhileTiming() {
        var brk = startBreak();
        var st = Machine.handle(brk, { type: "startPreset", preset: defaultPreset() }, t0 + 52 * min);
        compare(st.phase, "break");          // use Continue/Skip during a break, not presets

        var work = start50x10();
        st = Machine.handle(work, { type: "startPreset", preset: defaultPreset() }, t0 + 10 * min);
        compare(st.phase, "work");           // presets must not restart a running block
        compare(st.deadline, t0 + 50 * min); // state unchanged
    }

    function test_startPreset_fromWait_startsChosenPreset_andHidesOverlay() {
        // Break finished; overlay waits indefinitely. Picking a different preset
        // must start that block (not silently do nothing / force default 50/10).
        var wait = Machine.handle(startBreak(), { type: "tick" }, t0 + 61 * min);
        var st = Machine.handle(wait, { type: "startPreset",
            preset: { label: "25/5", workMin: 25, breakMin: 5 } }, t0 + 75 * min);
        compare(st.phase, "work");
        compare(st.preset.label, "25/5");
        compare(st.deadline, t0 + 75 * min + 25 * min);
        var hid = st.effects.some(function (e) { return e.type === "hideOverlay"; });
        compare(hid, true); // the waiting overlay must go away
    }

    function test_startPreset_fromDisabled_startsChosenPreset() {
        // Meeting mode: every preset button must work, not only Enable's default.
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        var st = Machine.handle(dis, { type: "startPreset",
            preset: { label: "45/15", workMin: 45, breakMin: 15 } }, t0 + 12 * min);
        compare(st.phase, "work");
        compare(st.preset.label, "45/15");
        compare(st.deadline, t0 + 12 * min + 45 * min);
    }

    function test_customValues_governBlockLikePreset() {
        // The machine starts ANY {workMin,breakMin} preset payload — this
        // powers user presets and restored snapshots. There is no separate
        // Custom one-off UI row anymore (removed with the card overhaul).
        var st = Machine.handle(freshState(),
                                { type: "startPreset", preset: { label: "custom", workMin: 37, breakMin: 9 } }, t0);
        compare(st.deadline, t0 + 37 * min);
        st = Machine.handle(st, { type: "tick" }, t0 + 37 * min + 1);
        compare(st.phase, "break");
        compare(st.largeBreak, false);
        compare(st.deadline, t0 + 46 * min);    // 9-minute break
    }

    function test_largeBreakDerivation_tiers() {
        compare(Machine.largeBreakMinutes(5), 20);
        compare(Machine.largeBreakMinutes(6), 20);
        compare(Machine.largeBreakMinutes(7), 30);
        compare(Machine.largeBreakMinutes(12), 30);
        compare(Machine.largeBreakMinutes(13), 40);
        compare(Machine.largeBreakMinutes(20), 40);
    }

    // --- Slice 10: Desk Reminder arms at every Work Block start ---

    function test_deskEnabled_armsCountdownAtWorkStart() {
        var st = Machine.initialState();
        st.deskEnabled = true;
        st.deskMinutes = 30;
        st = Machine.handle(st, { type: "startPreset", preset: defaultPreset() }, t0);
        compare(st.phase, "work");
        compare(st.deskDeadline, t0 + 30 * min);  // full interval from block start
        compare(st.deskDue, false);
    }

    function test_deskDisabled_leavesNoCountdown() {
        var st = Machine.handle(freshState(), { type: "startPreset", preset: defaultPreset() }, t0);
        compare(st.deskDeadline, 0);
        compare(st.deskDue, false);
    }

    // --- Slice 11: desk expiry, desk-due persistence, acknowledgement ---

    function startDeskWork() {
        var st = Machine.initialState();
        st.deskEnabled = true;
        st.deskMinutes = 30;
        return Machine.handle(st, { type: "startPreset", preset: defaultPreset() }, t0);
    }

    function test_deskExpiry_showsOverlay_chimes_keepsWorkRunning() {
        var st = Machine.handle(startDeskWork(), { type: "tick" }, t0 + 30 * min + 1);
        compare(st.deskDue, true);
        compare(st.deskDeadline, 0);              // countdown stops while due
        compare(st.phase, "work");                // the Work Block keeps running underneath
        compare(st.deadline, t0 + 50 * min);      // untouched
        compare(st.effects.map(function (e) { return e.type; }),
                ["showDeskOverlay", "chime"]);
    }

    function test_deskDue_persistsWithoutRefiring() {
        var st = Machine.handle(startDeskWork(), { type: "tick" }, t0 + 31 * min);
        st = Machine.handle(st, { type: "tick" }, t0 + 40 * min);
        compare(st.deskDue, true);                // stays up until acknowledged/superseded
        compare(st.effects.length, 0);            // no repeated chime
    }

    function test_deskAck_dismissesAndRestartsCountdown() {
        var due = Machine.handle(startDeskWork(), { type: "tick" }, t0 + 31 * min);
        var st = Machine.handle(due, { type: "deskAck" }, t0 + 35 * min);
        compare(st.deskDue, false);
        compare(st.deskDeadline, t0 + 35 * min + 30 * min); // full interval from NOW
        compare(st.phase, "work");
        compare(st.effects.map(function (e) { return e.type; }), ["hideOverlay"]);
    }

    function test_deskAck_withoutDuePromptIsANoop() {
        var st = startDeskWork();
        var after = Machine.handle(st, { type: "deskAck" }, t0 + 5 * min);
        compare(after.effects.length, 0);
        compare(after.deskDue, false);
        compare(after.deskDeadline, t0 + 30 * min); // countdown untouched
    }

    // Defensive symmetry: if Disable somehow fires while the Desk Overlay is up
    // (unreachable via the fullscreen UI today), the overlay must still be
    // told to hide — matching disable-during-break behavior.
    function test_disable_whileDeskDue_hidesOverlay() {
        var due = Machine.handle(startDeskWork(), { type: "tick" }, t0 + 31 * min);
        var st = Machine.handle(due, { type: "disable" }, t0 + 32 * min);
        compare(st.phase, "disabled");
        compare(st.deskDue, false);
        compare(st.effects.map(function (e) { return e.type; }), ["hideOverlay"]);
    }

    // --- Slice 12: a due Break outranks the Desk Overlay; disable clears desk ---

    function test_dueBreak_beatsDeskPrompt_atSameInstant() {
        // Work and desk deadlines land on the same instant: the Break must win.
        var st = Machine.initialState();
        st.deskEnabled = true;
        st = Machine.handle(st, { type: "startPreset", preset: defaultPreset() }, t0);
        st = Machine.decorate(Object.assign({}, st, { deskDeadline: st.deadline }));
        st = Machine.handle(st, { type: "tick" }, t0 + 50 * min);
        compare(st.phase, "break");
        compare(st.deskDue, false);                   // superseded, not co-existing
        compare(st.deskDeadline, 0);                  // restarts with the next block
        var types = st.effects.map(function (e) { return e.type; });
        compare(types.indexOf("showDeskOverlay"), -1);
        compare(types[0], "showOverlay");             // break content takes the window
    }

    function test_workExpiry_whileDeskDue_supersedesThePrompt() {
        var due = Machine.handle(startDeskWork(), { type: "tick" }, t0 + 31 * min);
        compare(due.deskDue, true);
        var st = Machine.handle(due, { type: "tick" }, t0 + 50 * min + 1);
        compare(st.phase, "break");
        compare(st.deskDue, false);                   // prompt gone; break content shows
        var types = st.effects.map(function (e) { return e.type; });
        compare(types.indexOf("showDeskOverlay"), -1);
    }

    function test_disable_clearsDeskCountdownAndPrompt() {
        var due = Machine.handle(startDeskWork(), { type: "tick" }, t0 + 31 * min);
        var st = Machine.handle(due, { type: "disable" }, t0 + 33 * min);
        compare(st.phase, "disabled");
        compare(st.deskDue, false);
        compare(st.deskDeadline, 0);
        var armed = startDeskWork();
        var off = Machine.handle(armed, { type: "disable" }, t0 + 3 * min);
        compare(off.deskDeadline, 0);
        compare(off.deskDue, false);
    }

    // --- Slice 13: desk countdown survives restarts (wall clock, raw states) ---

    // Builds a state exactly the way main.qml's restore() does: raw fields, no
    // handle() involved. Pre-SPEC-002 snapshots lack the desk fields entirely.
    function restoredDeskState(deskDeadline, deskDue, deskEnabled) {
        return Machine.decorate({
            phase: "work", deadline: t0 + 50 * min,
            preset: { label: "50/10", workMin: 50, breakMin: 10 },
            completedBlocks: 0, cycleLength: 4,
            pendingBreak: false, continueEnabled: false, largeBreak: false,
            deskDeadline: deskDeadline, deskDue: deskDue, deskEnabled: deskEnabled,
            deskMinutes: 30, defaultPreset: null, effects: []
        });
    }

    function test_restartedDeskCountdown_resumesWithOriginalDeadline() {
        var st = Machine.tick(restoredDeskState(t0 + 20 * min, false, true), t0 + 10 * min);
        compare(st.phase, "work");
        compare(st.deskDeadline, t0 + 20 * min);  // untouched by the restart
        compare(st.effects.length, 0);
        st = Machine.tick(st, t0 + 20 * min + 1); // then fires exactly once
        compare(st.deskDue, true);
        compare(st.effects.map(function (e) { return e.type; }),
                ["showDeskOverlay", "chime"]);
    }

    function test_restartedDeskDue_promptSurvivesWithoutRechime() {
        var st = Machine.tick(restoredDeskState(0, true, true), t0 + 45 * min);
        compare(st.deskDue, true);   // overlay must come back after the restart
        compare(st.effects.length, 0);
        var acked = Machine.handle(st, { type: "deskAck" }, t0 + 46 * min);
        compare(acked.deskDeadline, t0 + 46 * min + 30 * min);
    }

    function test_legacySnapshotWithoutDeskFields_armsFreshOnFirstTick() {
        var st = Machine.tick(restoredDeskState(0, false, true), t0 + 10 * min);
        compare(st.deskDeadline, t0 + 40 * min);  // lazily armed: full interval from now
        compare(st.effects.length, 0);
    }

    function test_deskOff_neverArmsLazily() {
        var st = Machine.tick(restoredDeskState(0, false, false), t0 + 10 * min);
        compare(st.deskDeadline, 0);
        compare(st.deskDue, false);
        compare(st.effects.length, 0);
    }

    function test_hostileDeskMinutes_fallBackToDefaultInterval() {
        var raw = restoredDeskState(0, false, true);
        raw.deskMinutes = NaN;
        var st = Machine.handle(raw, { type: "tick" }, t0 + 10 * min);
        compare(st.deskDeadline, t0 + 10 * min + 30 * min);
    }

    // --- Slice 8: wall-clock restore across restarts ---

    function test_restartBeforeDeadline_resumesIntact() {
        var st = Machine.handle(start50x10(), { type: "tick" }, t0 + 30 * min);
        compare(st.phase, "work");
        compare(st.deadline, t0 + 50 * min);    // original deadline untouched
        compare(st.effects.length, 0);
    }

    function test_deadlineLongPastAtRestore_breakAnchoredAtOriginalExpiry() {
        // Session was away past the work deadline; back mid-break.
        var st = Machine.handle(start50x10(), { type: "tick" }, t0 + 55 * min);
        compare(st.phase, "break");
        compare(st.deadline, t0 + 60 * min);    // anchored at expiry instant, not restart
        compare(st.completedBlocks, 1);
    }

    function test_everythingExpiredAtRestore_landsInWaitInOneTick() {
        var st = Machine.handle(start50x10(), { type: "tick" }, t0 + 80 * min);
        compare(st.phase, "wait");
        compare(st.continueEnabled, true);
        compare(st.completedBlocks, 1);
    }

    // --- Slice 9: hostile minute values must degrade safely, never hang ---
    // NOTE: keep the loops inline in every test below. This qmllint 6.12 build
    // crashes (silent exit 255) when certain test functions call locally-defined
    // helpers, so the Slice 9 tests deliberately contain no helper calls.

    function test_nanWorkMin_doesNotHangTheTimer() {
        // workMin: NaN used to yield deadline NaN — the timer hung in "work" forever.
        var st = Machine.handle(freshState(), { type: "startPreset",
            preset: { label: "g", workMin: NaN, breakMin: 10 } }, t0);
        st = Machine.handle(st, { type: "tick" }, t0 + 365 * 24 * 60 * min);
        verify(st.phase !== "work", "timer must not hang; got " + st.phase);
        verify(isFinite(st.deadline));
    }

    function test_nonpositiveWorkMin_fallsBackToDefault() {
        var st = Machine.handle(freshState(), { type: "startPreset",
            preset: { label: "g", workMin: 0, breakMin: 10 } }, t0);
        compare(st.deadline, t0 + 50 * min);
        st = Machine.handle(freshState(), { type: "startPreset",
            preset: { label: "g", workMin: -20, breakMin: 10 } }, t0);
        compare(st.deadline, t0 + 50 * min);
    }

    function test_negativeBreakMin_isStillEnforced() {
        // breakMin: -5 used to skip the rest entirely (instant wait).
        var st = Machine.handle(freshState(), { type: "startPreset",
            preset: { label: "g", workMin: 50, breakMin: -5 } }, t0);
        st = Machine.handle(st, { type: "tick" }, t0 + 50 * min);
        compare(st.phase, "break");
        compare(st.deadline, t0 + 60 * min); // default 10-minute break enforced
        compare(Machine.handle(st, { type: "tick" }, t0 + 55 * min).phase, "break");
    }

    function test_zeroOrNegativeLargeBreakMin_meansDerived() {
        // Editor contract: large break of 0 means derived automatically.
        // 0/-3/NaN used to win outright, producing an instant-over large break.
        // NOTE: no for/while loops with array subscripts here — this qmllint
        // 6.12 build crashes (silent exit 255) on subscript access inside any
        // for/while loop. forEach is the safe iteration idiom in this file.
        // Drives 3 full work→break→continue cycles inline, then lets the 4th
        // Work Block expire.
        [0, -3, NaN].forEach(function (jv) {
            var st = Machine.handle(freshState(), { type: "startPreset",
                preset: { label: "g", workMin: 50, breakMin: 10, largeBreakMin: jv } }, t0);
            var when = t0;
            for (let i = 0; i < 3; i++) {
                st = Machine.handle(st, { type: "tick" }, when + 50 * min); // work expires → break
                st = Machine.handle(st, { type: "tick" }, when + 61 * min); // break over → wait
                st = Machine.handle(st, { type: "continue" }, when + 61 * min); // fresh work
                when = when + 61 * min;
            }
            st = Machine.handle(st, { type: "tick" }, when + 50 * min); // 4th expires
            compare(st.phase, "break", "junk=" + jv);
            compare(st.largeBreak, true, "junk=" + jv);
            compare(st.deadline, when + 50 * min + 30 * min, // derived: break 10 → 30
                    "junk=" + jv);
        });
    }

    function test_validLargeBreakMin_stillWins() {
        var st = Machine.handle(freshState(), { type: "startPreset",
            preset: { label: "g", workMin: 50, breakMin: 10, largeBreakMin: 25 } }, t0);
        var when = t0;
        for (let i = 0; i < 3; i++) {
            st = Machine.handle(st, { type: "tick" }, when + 50 * min);
            st = Machine.handle(st, { type: "tick" }, when + 61 * min);
            st = Machine.handle(st, { type: "continue" }, when + 61 * min);
            when = when + 61 * min;
        }
        st = Machine.handle(st, { type: "tick" }, when + 50 * min);
        compare(st.deadline, when + 50 * min + 25 * min);
    }

    function test_rawSnapshotPreset_garbageBreaksDegradeSafely() {
        // Restore path: hand-edited config reaches enterBreak unfiltered, so the
        // machine itself must sanitize (build the state raw, as restore() does).
        var raw = Machine.decorate({
            phase: "work", deadline: t0 + 50 * min,
            preset: { label: "g", workMin: NaN, breakMin: -5, largeBreakMin: 0 },
            completedBlocks: 3, cycleLength: 4,
            pendingBreak: false, continueEnabled: false, largeBreak: false, effects: []
        });
        var st = Machine.tick(raw, t0 + 50 * min);
        compare(st.phase, "break");
        compare(st.deadline, t0 + 50 * min + 30 * min); // fallback break 10, derived large 30
    }

    function test_zeroOrJunkCycleLength_fallsBackToDefault() {
        var mk = function (cycleLength) {
            return Machine.decorate({
                phase: "work", deadline: t0 + 50 * min,
                preset: { label: "g", workMin: 50, breakMin: 10 },
                completedBlocks: 3, cycleLength: cycleLength,
                pendingBreak: false, continueEnabled: false, largeBreak: false, effects: []
            });
        };
        var st0 = Machine.tick(mk(0), t0 + 50 * min);
        compare(st0.largeBreak, true, "cycleLength 0 must fall back to 4 (4th block large)");
        var st1 = Machine.tick(mk(NaN), t0 + 50 * min);
        compare(st1.largeBreak, true, "cycleLength NaN must fall back to 4");
    }

    // --- Slice 15: six-slot preset storage (SPEC-002) ---
    // NOTE: no for/while loops with array subscripts in these tests — this lint
    // build crashes on that pattern (see the Slice 9 note above).

    function test_slots_garbageYieldsSeededBuiltinsAndEmptyUserSlots() {
        [null, "not json", "{}", 42].forEach(function (junk) {
            var r = Machine.normalizePresetSlots(junk);
            compare(r.length, 6, "junk=" + junk);
            compare(r[0].label, "50/10", "junk=" + junk);
            compare(r[1].label, "25/5", "junk=" + junk);
            compare(r[2].label, "45/15", "junk=" + junk);
            compare(r[3], null, "junk=" + junk);
            compare(r[4], null, "junk=" + junk);
            compare(r[5], null, "junk=" + junk);
        });
    }

    function test_slots_handEditedAwayBuiltins_areReSeeded() {
        var r = Machine.normalizePresetSlots(
            '[null,{"label":"25/5","workMin":25,"breakMin":5},null,{"label":"My 60","workMin":60,"breakMin":9}]');
        compare(r[0].label, "50/10");      // restored, never lost
        compare(r[1].label, "25/5");
        compare(r[2].label, "45/15");      // restored
        compare(r[3].label, "60/9");       // user label derives from the minutes
        compare(r[4], null);
        compare(r[5], null);
    }

    function test_slots_legacyThreeEntryArray_migratesToSixSlots() {
        var r = Machine.normalizePresetSlots(
            '[{"label":"50/10","workMin":50,"breakMin":10},' +
            '{"label":"25/5","workMin":25,"breakMin":5},' +
            '{"label":"45/15","workMin":45,"breakMin":15}]');
        compare(r.length, 6);
        compare(r[0].label, "50/10");
        compare(r[3], null);
        compare(r[5], null);
    }

    function test_slots_legacyDisplacedUserPresets_moveIntoUserSlots() {
        // Pre-SPEC-002 editor let users delete built-ins, shifting customs into
        // slots 0-2. Nothing user-made may vanish: built-ins return to 0-2 and
        // the customs land in the user slots, capped at three.
        var legacy = '[{"label":"Mine A","workMin":11,"breakMin":2},' +
            '{"label":"50/10","workMin":50,"breakMin":10},' +
            '{"label":"Mine B","workMin":22,"breakMin":4},' +
            '{"label":"Mine C","workMin":33,"breakMin":6},' +
            '{"label":"Mine D","workMin":44,"breakMin":8},' +
            '{"label":"Mine E","workMin":55,"breakMin":1}]';
        var r = Machine.normalizePresetSlots(legacy);
        compare(r[0].label, "50/10");
        compare(r[1].label, "25/5");
        compare(r[2].label, "45/15");
        compare(r[3].label, "11/2");       // derived: "Mine A" was 11/2
        compare(r[4].label, "22/4");       // derived: "Mine B" was 22/4
        compare(r[5].label, "33/6");       // derived: "Mine C" was 33/6
    }

    function test_slots_junkUserEntries_becomeNulls() {
        var r = Machine.normalizePresetSlots(
            '[{"label":"50/10","workMin":50,"breakMin":10},' +
            '{"label":"25/5","workMin":25,"breakMin":5},' +
            '{"label":"45/15","workMin":45,"breakMin":15},' +
            '"junk",{"label":"ok","workMin":30,"breakMin":6},{"workMin":-5,"breakMin":3}]');
        compare(r[3].label, "30/6"); // sane user entries compact into slots 3-5
        compare(r[4], null);
        compare(r[5], null);
    }

    function test_slots_mutatedMinutes_noLongerMatchBuiltin_movesToUserSlot() {
        // A pre-SPEC-002 edited "50/11" is not the built-in anymore: the built-in
        // is restored AND the user's variant survives as a user preset.
        var r = Machine.normalizePresetSlots(
            '[{"label":"50/10","workMin":51,"breakMin":10},' +
            '{"label":"25/5","workMin":25,"breakMin":5},' +
            '{"label":"45/15","workMin":45,"breakMin":15}]');
        compare(r[0].workMin, 50);
        compare(r[3].label, "51/10");   // derived from the mutated minutes
        compare(r[3].workMin, 51);
    }

    // --- Slice 16: derived preset labels (operator: no custom name field) ---

    function test_slots_userLabels_areDerivedFromMinutes() {
        // The label IS the minutes ("W/B"); stored names are ignored on read.
        // Built-ins keep their canonical labels; legacy hand-named user entries
        // ("Deep Work", "custom") migrate to the derived form.
        var r = Machine.normalizePresetSlots(
            '[{"label":"50/10","workMin":50,"breakMin":10},' +
            '{"label":"25/5","workMin":25,"breakMin":5},' +
            '{"label":"45/15","workMin":45,"breakMin":15},' +
            '{"label":"Deep Work","workMin":90,"breakMin":12},' +
            '{"label":"custom","workMin":25,"breakMin":5}]');
        compare(r[0].label, "50/10");
        compare(r[1].label, "25/5");
        compare(r[2].label, "45/15");
        compare(r[3].label, "90/12");
        compare(r[4].label, "25/5");   // migrated
        compare(r[3].workMin, 90);     // minutes themselves untouched
        compare(r[4].workMin, 25);
    }

    function test_slots_legacyBuiltinMinuteEntry_convergesOnNextWrite() {
        // Pinned round-5 migration edge: a legacy hand-named entry whose
        // MINUTES equal a Built-in ("custom" 25/5) survives every READ (dedup
        // matches its raw stored label first) and displays as a visual
        // duplicate of that Built-in tile — but it is NOT durable storage.
        // The card's mutators write the RELABELED normalized view, whose
        // entry is an exact Built-in match, so the next read after any card
        // write drops it: storage converges, silently, one write after the
        // migration. This pins the convergence so a future refactor cannot
        // accidentally turn it into duplicate storage or eager read-loss.
        var r = Machine.normalizePresetSlots(
            '[{"label":"50/10","workMin":50,"breakMin":10},' +
            '{"label":"25/5","workMin":25,"breakMin":5},' +
            '{"label":"45/15","workMin":45,"breakMin":15},' +
            '{"label":"Deep Work","workMin":90,"breakMin":12},' +
            '{"label":"custom","workMin":25,"breakMin":5}]');
        compare(r[3].label, "90/12");      // filler occupies the first user slot
        compare(r[4].label, "25/5");       // survives the read, relabeled
        // Simulate any card mutation: it persists the relabeled view...
        var echoed = JSON.stringify(r);
        // ...and the next read converges: the Built-in identity is dropped.
        var r2 = Machine.normalizePresetSlots(echoed);
        compare(r2[4], null);
        compare(r2[0].label, "50/10");     // the real Built-in stays canonical
    }

    function test_derivedLabel_returnsWorkOverBreak() {
        compare(Machine.derivedLabel(25, 5), "25/5");
        compare(Machine.derivedLabel(50, 10), "50/10");
        compare(Machine.derivedLabel(45, 15), "45/15");
        compare(Machine.derivedLabel(90, 12), "90/12");
    }

    function test_derivedLabelCollision_minutesAloneEqualBuiltin() {
        // The card's Built-in-collision refusal composes derivedLabel with
        // builtinIndex: a user preset whose MINUTES equal a Built-in derives
        // the Built-in's label and is indistinguishable from it. Different
        // minutes derive a different label: never a false positive.
        compare(Machine.builtinIndex({
            label: Machine.derivedLabel(25, 5), workMin: 25, breakMin: 5 }), 1);
        compare(Machine.builtinIndex({
            label: Machine.derivedLabel(50, 10), workMin: 50, breakMin: 10 }), 0);
        compare(Machine.builtinIndex({
            label: Machine.derivedLabel(50, 11), workMin: 50, breakMin: 11 }), -1);
    }

    // --- Slice 17: UI-normalized presets keep the explicit-large contract ---
    // The card editor writes {label, workMin, breakMin} plus largeBreakMin only
    // when >0. Regression: that exact shape must honor the auto rule vs the
    // explicit override at the 4th (Large) break.

    function test_uiNormalizedPreset_omittedLargeBreak_usesAutoRule() {
        var slots = Machine.normalizePresetSlots(
            '[{"label":"50/10","workMin":50,"breakMin":10},' +
            '{"label":"25/5","workMin":25,"breakMin":5},' +
            '{"label":"45/15","workMin":45,"breakMin":15},' +
            '{"label":"40/4","workMin":40,"breakMin":4}]');
        var st = Machine.handle(freshState(), { type: "startPreset", preset: slots[3] }, t0);
        compare(st.preset.label, "40/4");
        var when = t0;
        for (let i = 0; i < 3; i++) {
            st = Machine.handle(st, { type: "tick" }, when + 40 * min); // work expires
            st = Machine.handle(st, { type: "tick" }, when + 45 * min); // break over
            st = Machine.handle(st, { type: "continue" }, when + 45 * min);
            when = when + 45 * min;
        }
        st = Machine.handle(st, { type: "tick" }, when + 40 * min);     // 4th expires
        compare(st.phase, "break");
        compare(st.largeBreak, true);
        compare(st.deadline, when + 40 * min + 20 * min);  // rule: break 4 → 20
    }

    function test_uiNormalizedPreset_explicitLargeBreak_wins() {
        var slots = Machine.normalizePresetSlots(
            '[{"label":"50/10","workMin":50,"breakMin":10},' +
            '{"label":"25/5","workMin":25,"breakMin":5},' +
            '{"label":"45/15","workMin":45,"breakMin":15},' +
            '{"label":"40/4","workMin":40,"breakMin":4,"largeBreakMin":45}]');
        var st = Machine.handle(freshState(), { type: "startPreset", preset: slots[3] }, t0);
        var when = t0;
        for (let i = 0; i < 3; i++) {
            st = Machine.handle(st, { type: "tick" }, when + 40 * min);
            st = Machine.handle(st, { type: "tick" }, when + 45 * min);
            st = Machine.handle(st, { type: "continue" }, when + 45 * min);
            when = when + 45 * min;
        }
        st = Machine.handle(st, { type: "tick" }, when + 40 * min);
        compare(st.phase, "break");
        compare(st.largeBreak, true);
        compare(st.deadline, when + 40 * min + 45 * min);  // explicit 45 wins
    }

    // --- Slice 18: Presence, lock pause and auto-start (SPEC-003) ---

    function autoState(enabled, minutes) {
        var st = Machine.initialState();
        st.autoStartEnabled = enabled === true;
        st.autoStartMinutes = minutes === undefined ? 5 : minutes;
        return st;
    }

    function test_initialState_presenceFields() {
        var st = Machine.initialState();
        compare(st.locked, false);
        compare(st.presenceSince, 0);
        compare(st.autoStartEnabled, false);
        compare(st.autoStartMinutes, 5);
        compare(st.autoStartArmed, false);
        compare(st.paused, false);
        compare(st.pausedRemainingMs, 0);
        compare(st.deskPausedRemainingMs, 0);
    }

    function test_screenLocked_pausesRunningWork_andFreezesDesk() {
        var st = Machine.handle(startDeskWork(), { type: "screenLocked" }, t0 + 10 * min);
        compare(st.phase, "work");
        compare(st.locked, true);
        compare(st.presenceSince, 0);
        compare(st.paused, true);
        compare(st.pausedRemainingMs, 40 * min);
        compare(st.deskPausedRemainingMs, 20 * min);
        compare(st.deadline, 0);
        compare(st.deskDeadline, 0);
        compare(st.effects.length, 0);
    }

    function test_screenLocked_whenAlreadyLocked_isIdentityNoop() {
        var locked = Machine.handle(start50x10(), { type: "screenLocked" }, t0 + 10 * min);
        var again = Machine.handle(locked, { type: "screenLocked" }, t0 + 11 * min);
        verify(again === locked, "a repeated lock observation must not clone state");
    }

    function test_screenUnlocked_resumesWorkAndDeskFromFrozenTimes() {
        var locked = Machine.handle(startDeskWork(), { type: "screenLocked" }, t0 + 10 * min);
        var st = Machine.handle(locked, { type: "screenUnlocked" }, t0 + 40 * min);
        compare(st.locked, false);
        compare(st.presenceSince, t0 + 40 * min);
        compare(st.paused, false);
        compare(st.pausedRemainingMs, 0);
        compare(st.deskPausedRemainingMs, 0);
        compare(st.deadline, t0 + 40 * min + 40 * min);
        compare(st.deskDeadline, t0 + 40 * min + 20 * min);
        compare(st.effects.length, 0);
    }

    function test_screenUnlocked_whenAlreadyUnlocked_isIdentityNoop() {
        var opened = Machine.handle(autoState(true, 5), { type: "screenUnlocked" }, t0);
        compare(opened.presenceSince, t0);
        var again = Machine.handle(opened, { type: "screenUnlocked" }, t0 + 2 * min);
        verify(again === opened, "a repeated unlock observation must not reset the window");
    }

    function test_screenLocked_duringBreak_keepsWallClockDeadline() {
        var brk = startBreak();
        var st = Machine.handle(brk, { type: "screenLocked" }, t0 + 52 * min);
        compare(st.phase, "break");
        compare(st.locked, true);
        compare(st.paused, false);
        compare(st.deadline, t0 + 60 * min);
        compare(st.effects.length, 0);
    }

    function test_screenLocked_duringWait_keepsWait() {
        var wait = Machine.handle(startBreak(), { type: "tick" }, t0 + 61 * min);
        var st = Machine.handle(wait, { type: "screenLocked" }, t0 + 62 * min);
        compare(st.phase, "wait");
        compare(st.continueEnabled, true);
        compare(st.paused, false);
        compare(st.deadline, 0);
    }

    function test_screenLocked_preservesPendingBreak() {
        var delayed = Machine.handle(startBreak(), { type: "delayBreak" }, t0 + 51 * min);
        compare(delayed.pendingBreak, true);
        var locked = Machine.handle(delayed, { type: "screenLocked" }, t0 + 51 * min);
        compare(locked.pendingBreak, true);
        var st = Machine.handle(locked, { type: "screenUnlocked" }, t0 + 55 * min);
        compare(st.phase, "work");
        compare(st.pendingBreak, true);
        compare(st.deadline, t0 + 55 * min + 5 * min);
    }

    function test_screenLocked_whileDisabled_armsAutoStart() {
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        compare(dis.autoStartArmed, false);
        var st = Machine.handle(dis, { type: "screenLocked" }, t0 + 12 * min);
        compare(st.phase, "disabled");
        compare(st.locked, true);
        compare(st.autoStartArmed, true);
    }

    function test_screenLocked_whileIdle_doesNotPause() {
        var st = Machine.handle(autoState(true, 5), { type: "screenLocked" }, t0 + 3 * min);
        compare(st.phase, "idle");
        compare(st.paused, false);
        compare(st.locked, true);
    }

    function test_screenLocked_whileDeskDue_keepsPromptAndFreezesWork() {
        var due = Machine.handle(startDeskWork(), { type: "tick" }, t0 + 31 * min);
        compare(due.deskDue, true);
        var locked = Machine.handle(due, { type: "screenLocked" }, t0 + 32 * min);
        compare(locked.paused, true);
        compare(locked.pausedRemainingMs, 18 * min);
        compare(locked.deskDue, true);
        compare(locked.deskPausedRemainingMs, 0);
        var st = Machine.handle(locked, { type: "screenUnlocked" }, t0 + 42 * min);
        compare(st.deskDue, true);
        compare(st.deskDeadline, 0);
        compare(st.deadline, t0 + 42 * min + 18 * min);
    }

    function presenceOpened(enabled, minutes) {
        return Machine.handle(autoState(enabled, minutes), { type: "screenUnlocked" }, t0);
    }

    function test_presenceTick_atWindow_startsDefault_andNotifiesOnce() {
        var st = Machine.handle(presenceOpened(true, 5), { type: "presenceTick" }, t0 + 5 * min);
        compare(st.phase, "work");
        compare(st.preset.label, "50/10");
        compare(st.deadline, t0 + 5 * min + 50 * min);
        compare(st.presenceSince, 0);
        compare(st.paused, false);
        compare(st.effects.length, 1);
        compare(st.effects[0].type, "notifyAutoStart");
        compare(st.effects[0].preset, "50/10");
        var chime = st.effects.some(function (e) { return e.type === "chime"; });
        compare(chime, false, "auto-start must never chime");
    }

    function test_presenceTick_belowWindow_doesNothing() {
        var st = Machine.handle(presenceOpened(true, 5), { type: "presenceTick" }, t0 + 5 * min - 1);
        compare(st.phase, "idle");
        compare(st.effects.length, 0);
    }

    function test_presenceTick_aboveWindow_starts() {
        var st = Machine.handle(presenceOpened(true, 5), { type: "presenceTick" }, t0 + 6 * min);
        compare(st.phase, "work");
        compare(st.preset.label, "50/10");
    }

    function test_presenceTick_usesDefaultPreset_andNotifiesItsLabel() {
        var st = presenceOpened(true, 5);
        st.defaultPreset = { label: "25/5", workMin: 25, breakMin: 5 };
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 5 * min);
        compare(st.phase, "work");
        compare(st.preset.label, "25/5");
        compare(st.deadline, t0 + 5 * min + 25 * min);
        compare(st.effects[0].preset, "25/5");
    }

    function test_presenceTick_missingStar_fallsBackToBuiltIn50x10() {
        var st = presenceOpened(true, 5);
        st.defaultPreset = null;
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 5 * min);
        compare(st.phase, "work");
        compare(st.preset.label, "50/10");
        compare(st.effects[0].preset, "50/10");
    }

    function test_presenceTick_hostileStar_fallsBackToBuiltIn() {
        var st = presenceOpened(true, 5);
        st.defaultPreset = { label: "x", workMin: NaN, breakMin: -3 };
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 5 * min);
        compare(st.preset.workMin, 50);
        compare(st.preset.breakMin, 10);
        compare(st.effects[0].preset, "50/10");
    }

    function test_presenceTick_effectCarriesDerivedLabel() {
        // The notification names the preset's derived label, not a stale or
        // hand-edited stored label (SPEC-002 derived naming).
        var st = presenceOpened(true, 5);
        st.defaultPreset = { label: "Deep Work", workMin: 90, breakMin: 12 };
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 5 * min);
        compare(st.effects.length, 1);
        compare(st.effects[0].preset, "90/12");
    }

    function test_presenceTick_autoStartOff_neverStarts() {
        var st = Machine.handle(presenceOpened(false, 5), { type: "presenceTick" }, t0 + 60 * min);
        compare(st.phase, "idle");
        compare(st.effects.length, 0);
    }

    function test_presenceTick_withoutPresenceWindow_neverStarts() {
        var st = Machine.handle(autoState(true, 5), { type: "presenceTick" }, t0 + 60 * min);
        compare(st.phase, "idle");
        compare(st.effects.length, 0);
    }

    function test_screenLock_resetsPresenceWindow() {
        // 3 unlocked minutes, then a lock: the window restarts on the next
        // unlock, so the old elapsed time cannot trigger a start.
        var st = Machine.handle(presenceOpened(true, 5), { type: "screenLocked" }, t0 + 3 * min);
        compare(st.presenceSince, 0);
        st = Machine.handle(st, { type: "screenUnlocked" }, t0 + 4 * min);
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 7 * min);
        compare(st.phase, "idle");
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 9 * min);
        compare(st.phase, "work");
    }

    function test_presenceTick_disabled_requiresLockReArm() {
        var st = presenceOpened(true, 5);
        st = Machine.handle(st, { type: "disable" }, t0 + 1 * min);
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 30 * min);
        compare(st.phase, "disabled");
        compare(st.effects.length, 0);
        // One lock re-arms; the next unlock's window triggers a start.
        st = Machine.handle(st, { type: "screenLocked" }, t0 + 31 * min);
        compare(st.autoStartArmed, true);
        st = Machine.handle(st, { type: "screenUnlocked" }, t0 + 32 * min);
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 37 * min);
        compare(st.phase, "work");
        compare(st.preset.label, "50/10");
    }

    function test_presenceTick_neverFiresFromWorkBreakOrWait() {
        var work = presenceOpened(true, 5);
        work = Machine.handle(work, { type: "startPreset", preset: defaultPreset() }, t0);
        work.presenceSince = t0;
        work = Machine.handle(work, { type: "presenceTick" }, t0 + 10 * min);
        compare(work.phase, "work");
        compare(work.effects.length, 0);

        var brk = presenceOpened(true, 5);
        brk = Machine.handle(brk, { type: "startPreset", preset: defaultPreset() }, t0);
        brk = Machine.handle(brk, { type: "tick" }, t0 + 50 * min + 1);
        brk = Machine.handle(brk, { type: "tick" }, t0 + 50 * min + 2); // settle break effects
        brk.presenceSince = t0;
        brk = Machine.handle(brk, { type: "presenceTick" }, t0 + 55 * min);
        compare(brk.phase, "break");
        compare(brk.effects.length, 0);

        var wait = presenceOpened(true, 5);
        wait = Machine.handle(wait, { type: "startPreset", preset: defaultPreset() }, t0);
        wait = Machine.handle(wait, { type: "tick" }, t0 + 61 * min);
        wait = Machine.handle(wait, { type: "tick" }, t0 + 61 * min + 1); // settle wait effects
        wait.presenceSince = t0;
        wait = Machine.handle(wait, { type: "presenceTick" }, t0 + 70 * min);
        compare(wait.phase, "wait");
        compare(wait.effects.length, 0);
    }

    function test_presenceTick_enablingMidWindow_doesNotResetExistingWindow() {
        // Enabling takes effect on the next tick; a window already past the
        // configured duration starts immediately (it is not restarted).
        var st = presenceOpened(false, 5);
        st.autoStartEnabled = true;
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 6 * min);
        compare(st.phase, "work");
    }

    function test_presenceTick_hostilePresenceValues_neverStart() {
        [0, -5, NaN, Infinity, t0 + 20 * min].forEach(function (since) {
            var st = autoState(true, 5);
            st.presenceSince = since;
            st = Machine.handle(st, { type: "presenceTick" }, t0 + 10 * min);
            compare(st.phase, "idle", "presenceSince=" + since);
            compare(st.effects.length, 0, "presenceSince=" + since);
        });
    }

    function test_presenceTick_hostileMinutes_roundAndClamp() {
        // Junk falls back to 5; valid values round to an integer and clamp 1-60.
        [[NaN, 5], [0, 1], [-3, 1], [2.4, 2], [0.6, 1], [100, 60], [Infinity, 5]].forEach(function (pair) {
            var minutes = pair[0];
            var expected = pair[1];
            var below = autoState(true, minutes);
            below.presenceSince = t0;
            below = Machine.handle(below, { type: "presenceTick" }, t0 + expected * min - 1);
            compare(below.phase, "idle", "minutes=" + minutes);
            var at = autoState(true, minutes);
            at.presenceSince = t0;
            at = Machine.handle(at, { type: "presenceTick" }, t0 + expected * min);
            compare(at.phase, "work", "minutes=" + minutes);
        });
    }

    function test_presenceTick_withDeskDue_hidesStaleOverlay() {
        // Defensive path: a restored idle state can still carry a due prompt.
        var st = autoState(true, 5);
        st.presenceSince = t0;
        st.deskDue = true;
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 5 * min);
        compare(st.phase, "work");
        compare(st.deskDue, false);
        var types = st.effects.map(function (e) { return e.type; });
        compare(types.indexOf("hideOverlay") >= 0, true);
        compare(types.indexOf("notifyAutoStart") >= 0, true);
        compare(types.indexOf("showOverlay"), -1);
        compare(types.indexOf("chime"), -1);
    }

    function test_presenceTick_startsWorkWithDeskCountdownArmed() {
        var st = autoState(true, 5);
        st.deskEnabled = true;
        st.deskMinutes = 30;
        st.presenceSince = t0;
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 5 * min);
        compare(st.phase, "work");
        compare(st.deskDeadline, t0 + 5 * min + 30 * min);
    }

    // --- Slice 19: a Paused Work Block ignores ticks and clears on transitions ---

    function test_pausedTick_neitherExpiresWorkNorStepsDesk() {
        var locked = Machine.handle(startDeskWork(), { type: "screenLocked" }, t0 + 10 * min);
        // Far past the original work deadline and the desk deadline.
        var st = Machine.tick(locked, t0 + 300 * min);
        compare(st.phase, "work");
        compare(st.paused, true);
        compare(st.deadline, 0);
        compare(st.deskDeadline, 0);
        compare(st.pausedRemainingMs, 40 * min);
        compare(st.deskPausedRemainingMs, 20 * min);
        compare(st.effects.length, 0);
        var types = st.effects.map(function (e) { return e.type; });
        compare(types.indexOf("showOverlay"), -1, "a paused block must not expire into a Break");
    }

    function test_pausedWork_restoredRaw_doesNotExpire_andResumesOnUnlock() {
        // Builds the exact raw state main.qml restores from a paused snapshot.
        var raw = Machine.decorate({
            phase: "work", deadline: 0,
            preset: { label: "50/10", workMin: 50, breakMin: 10 },
            completedBlocks: 0, cycleLength: 4,
            pendingBreak: false, continueEnabled: false, largeBreak: false,
            deskDeadline: 0, deskDue: false, deskEnabled: true, deskMinutes: 30,
            defaultPreset: null,
            autoStartEnabled: true, autoStartMinutes: 5, autoStartArmed: false,
            presenceSince: 0, locked: true,
            paused: true, pausedRemainingMs: 12 * min, deskPausedRemainingMs: 3 * min,
            effects: []
        });
        var st = Machine.tick(raw, t0 + 120 * min);
        compare(st.phase, "work");
        compare(st.paused, true);
        compare(st.pausedRemainingMs, 12 * min);
        compare(st.effects.length, 0);
        st = Machine.handle(st, { type: "screenUnlocked" }, t0 + 120 * min);
        compare(st.paused, false);
        compare(st.deadline, t0 + 120 * min + 12 * min);
        compare(st.deskDeadline, t0 + 120 * min + 3 * min);
    }

    function test_disable_clearsPauseFieldsAndDisarms() {
        var locked = Machine.handle(start50x10(), { type: "screenLocked" }, t0 + 10 * min);
        var st = Machine.handle(locked, { type: "disable" }, t0 + 20 * min);
        compare(st.phase, "disabled");
        compare(st.paused, false);
        compare(st.pausedRemainingMs, 0);
        compare(st.deskPausedRemainingMs, 0);
        compare(st.autoStartArmed, false);
    }

    function test_enterWork_clearsPauseFieldsAndPresenceWindow() {
        var st = autoState(true, 5);
        st.presenceSince = t0 - 10 * min;
        st.paused = true;
        st.pausedRemainingMs = 5 * min;
        st.deskPausedRemainingMs = 2 * min;
        st = Machine.handle(st, { type: "startPreset", preset: defaultPreset() }, t0);
        compare(st.phase, "work");
        compare(st.paused, false);
        compare(st.pausedRemainingMs, 0);
        compare(st.deskPausedRemainingMs, 0);
        compare(st.presenceSince, 0);
    }

    function test_screenLocked_withDeskOff_freezesWorkOnly() {
        var st = Machine.handle(start50x10(), { type: "screenLocked" }, t0 + 10 * min);
        compare(st.pausedRemainingMs, 40 * min);
        compare(st.deskPausedRemainingMs, 0);
        st = Machine.handle(st, { type: "screenUnlocked" }, t0 + 30 * min);
        compare(st.deadline, t0 + 30 * min + 40 * min);
        compare(st.deskDeadline, 0);
    }

    // --- Slice 20: paused edge cases found in review ---

    function test_delayBreak_whilePaused_extendsFrozenTime() {
        // A delayed break is a work phase with pendingBreak true. Locking it
        // pauses it; pressing Delay again must add five minutes to the frozen
        // remaining time, not write a live deadline that unlock overwrites.
        var delayed = Machine.handle(startBreak(), { type: "delayBreak" }, t0 + 51 * min);
        compare(delayed.phase, "work");
        compare(delayed.pendingBreak, true);
        var locked = Machine.handle(delayed, { type: "screenLocked" }, t0 + 52 * min);
        compare(locked.paused, true);
        compare(locked.pausedRemainingMs, 4 * min);
        var st = Machine.handle(locked, { type: "delayBreak" }, t0 + 53 * min);
        compare(st.phase, "work");
        compare(st.paused, true);
        compare(st.pendingBreak, true);
        compare(st.deadline, 0);
        compare(st.pausedRemainingMs, 9 * min);   // 4 left + the 5-minute extension
        st = Machine.handle(st, { type: "screenUnlocked" }, t0 + 60 * min);
        compare(st.paused, false);
        compare(st.deadline, t0 + 60 * min + 9 * min);
    }

    function test_startBreakNow_whilePaused_isRefused() {
        var locked = Machine.handle(startDeskWork(), { type: "screenLocked" }, t0 + 10 * min);
        var st = Machine.handle(locked, { type: "startBreakNow" }, t0 + 12 * min);
        verify(st === locked, "a paused block must refuse Start break now");
    }

    function test_screenLocked_atDeskDeadline_preservesDuePrompt() {
        // Locking exactly at the desk deadline, before the next tick, must not
        // turn the already-due prompt into a fresh full interval on unlock.
        var locked = Machine.handle(startDeskWork(), { type: "screenLocked" }, t0 + 30 * min);
        compare(locked.paused, true);
        var resumed = Machine.handle(locked, { type: "screenUnlocked" }, t0 + 40 * min);
        var due = Machine.tick(resumed, t0 + 40 * min + 1);
        compare(due.deskDue, true);
        var types = due.effects.map(function (e) { return e.type; });
        verify(types.indexOf("showDeskOverlay") >= 0,
               "an already-due desk prompt must fire after resume, got " + types);
    }

    function test_screenLocked_afterAvailabilityLoss_stillArmsDisabled() {
        // A previous outage already marked the session locked. A real lock while
        // Disabled must still re-arm Auto-start despite the locked identity guard.
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        var away = Machine.handle(dis, { type: "presenceUnavailable" }, t0 + 11 * min);
        compare(away.locked, true);
        compare(away.autoStartArmed, false);
        var locked = Machine.handle(away, { type: "screenLocked" }, t0 + 12 * min);
        compare(locked.autoStartArmed, true);
    }

    function test_screenLocked_afterRecovery_stillPausesRunningWork() {
        // While the lock source was unreadable the outage marked the session
        // locked but left the Work Block running. The first real observation
        // after recovery must still pause it, despite the locked identity guard.
        var away = Machine.handle(start50x10(), { type: "presenceUnavailable" }, t0 + 10 * min);
        compare(away.locked, true);
        compare(away.paused, false);
        var recovered = Machine.handle(away, { type: "screenLocked" }, t0 + 12 * min);
        compare(recovered.locked, true);
        compare(recovered.paused, true);
        compare(recovered.pausedRemainingMs, 38 * min);
    }

    function test_screenLocked_atWorkDeadline_keepsBreakAnchor() {
        // Locking at (or after) the work deadline must not pause a finished
        // block: the Break starts at the original expiry, so locked time is rest.
        var locked = Machine.handle(start50x10(), { type: "screenLocked" }, t0 + 50 * min);
        compare(locked.paused, false);
        compare(locked.deadline, t0 + 50 * min);
        var brk = Machine.tick(locked, t0 + 50 * min + 1);
        compare(brk.phase, "break");
        compare(brk.deadline, t0 + 60 * min);   // anchored at the original expiry
    }

    function test_presenceUnavailable_clearsWindowAndBlocksAutoStart() {
        var st = presenceOpened(true, 5);
        compare(st.presenceSince, t0);
        st = Machine.handle(st, { type: "presenceUnavailable" }, t0 + 2 * min);
        compare(st.locked, true);
        compare(st.presenceSince, 0);
        st = Machine.handle(st, { type: "presenceTick" }, t0 + 10 * min);
        compare(st.phase, "idle");
        compare(st.effects.length, 0);
    }

    function test_screenUnlocked_duringBreak_leavesDeadlineUntouched() {
        var brk = startBreak();
        brk = Machine.handle(brk, { type: "screenLocked" }, t0 + 52 * min);
        var st = Machine.handle(brk, { type: "screenUnlocked" }, t0 + 62 * min);
        compare(st.phase, "break");
        compare(st.deadline, t0 + 60 * min);
        compare(st.paused, false);
        compare(st.continueEnabled, false);
        st = Machine.handle(st, { type: "tick" }, t0 + 62 * min);
        compare(st.phase, "wait");
        compare(st.continueEnabled, true);
    }
}
