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

    // --- Slice 7: disable for a meeting, custom one-off values ---

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

    function test_tickIgnored_whileDisabled() {
        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        var st = Machine.handle(dis, { type: "tick" }, t0 + 500 * min);
        compare(st.phase, "disabled");
    }

    // --- Slice 9: startPreset is a from-idle action ---

    function test_startPreset_refusedOutsideIdle() {
        var brk = startBreak();
        var st = Machine.handle(brk, { type: "startPreset", preset: defaultPreset() }, t0 + 52 * min);
        compare(st.phase, "break");          // use Continue/Skip during a break, not presets

        var wait = Machine.handle(startBreak(), { type: "tick" }, t0 + 61 * min);
        st = Machine.handle(wait, { type: "startPreset", preset: defaultPreset() }, t0 + 75 * min);
        compare(st.phase, "wait");

        var dis = Machine.handle(start50x10(), { type: "disable" }, t0 + 10 * min);
        st = Machine.handle(dis, { type: "startPreset", preset: defaultPreset() }, t0 + 12 * min);
        compare(st.phase, "disabled");       // re-enabling is the fresh-50/10 path (story 24)
    }

    function test_customValues_governBlockLikePreset() {
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
}
