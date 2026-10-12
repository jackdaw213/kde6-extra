// Pomodoro state machine — the single test seam.
// Pure: intents + wall-clock epoch-ms time in; state (with emitted effects) out.
// No Qt/Plasma imports. The UI layer executes the emitted effects.
.pragma library

var MIN = 60000;

// Automatic Large Break rule; a preset's explicit largeBreakMin overrides it.
function largeBreakMinutes(breakMin) {
    if (breakMin <= 6) return 20;
    if (breakMin <= 12) return 30;
    return 40;
}

var CYCLE_LENGTH_DEFAULT = 4; // three normal breaks, then a large one

// Hostile-value guards: config JSON is user-editable and presets arrive from
// both the editor and (raw) from restored snapshots. A garbage minute value
// must degrade to a safe fallback, never to a hung timer or a skipped rest.
function saneMinutes(v, fallback) {
    var n = Math.round(Number(v));
    return (isFinite(n) && n > 0) ? n : fallback;
}

// Returns a preset whose minute fields are guaranteed sane. largeBreakMin is
// kept only when strictly positive (0/negative/NaN = "derive automatically",
// matching the editor contract).
function normalizePreset(p) {
    var out = {
        label: p && p.label ? String(p.label) : DEFAULT_PRESET.label,
        workMin: saneMinutes(p && p.workMin, DEFAULT_PRESET.workMin),
        breakMin: saneMinutes(p && p.breakMin, DEFAULT_PRESET.breakMin)
    };
    var large = saneMinutes(p && p.largeBreakMin, 0);
    if (large > 0)
        out.largeBreakMin = large;
    return out;
}

function saneCycleLength(v) {
    var n = Math.round(Number(v));
    return (isFinite(n) && n >= 1) ? n : CYCLE_LENGTH_DEFAULT;
}

function initialState() {
    return decorate({
        phase: "idle",
        deadline: 0,
        preset: null,
        completedBlocks: 0,   // counts Work Blocks whose break actually started
        cycleLength: CYCLE_LENGTH_DEFAULT,
        pendingBreak: false,  // true while working through a delayed break
        continueEnabled: false,
        largeBreak: false,
        effects: []
    });
}

function decorate(st) {
    st.remainingMs = function (now) { return Math.max(0, this.deadline - now); };
    return st;
}

function handle(state, intent, now) {
    switch (intent.type) {
    case "startPreset":
        // Presets start a fresh Work Block: allowed from any non-timing state
        // (idle, finished-break wait, meeting mode). Refused only while timing.
        if (state.phase === "work" || state.phase === "break")
            return state;
        return enterWork(state, intent.preset, now,
                         state.phase === "wait" ? [{ type: "hideOverlay" }] : []);
    case "tick":
        return tick(state, now);
    case "continue":
        if (state.phase !== "wait")
            return state; // button disabled; defensive
        return withEffects(enterWork(state, state.preset, now, []), [{ type: "hideOverlay" }]);
    case "skipBreakConfirmed":
        if (state.phase !== "break")
            return state;
        return withEffects(enterWork(state, state.preset, now, []), [{ type: "hideOverlay" }]);
    case "delayBreak":
        if (state.phase === "break")
            return withEffects(delayWork(state, now, 5 * MIN), [{ type: "hideOverlay" }]);
        if (state.phase === "work" && state.pendingBreak)
            return withEffects(delayWork(state, now, 5 * MIN), []); // extend again; no rollback
        return state;
    case "startBreakNow":
        if (state.phase !== "work")
            return state;
        return enterBreak(state, now);
    case "disable":
        if (state.phase === "disabled")
            return state;
        var hid = (state.phase === "break" || state.phase === "wait")
            ? [{ type: "hideOverlay" }] : [];
        return withEffects(disable(state), hid);
    case "enable":
        if (state.phase !== "disabled")
            return state;
        return enterWork(state, DEFAULT_PRESET, now, []);
    default:
        return state;
    }
}

function tick(state, now) {
    // Cascade: one tick may cross several phase boundaries (e.g. everything
    // expired while the session was away). Anchors stay at the original
    // expiry instants; effects accumulate across the crossed boundaries.
    var st = state;
    var acc = [];
    for (var guard = 0; guard < 10; guard++) {
        if (st.phase === "disabled" || st.phase === "idle") break;
        if (st.phase === "work" && now >= st.deadline) {
            st = enterBreak(st, st.deadline); // anchored at the expiry instant
            acc = acc.concat(st.effects);
            continue;
        }
        if (st.phase === "break" && now >= st.deadline) {
            st = enterWait(st);
            acc = acc.concat(st.effects);
            continue;
        }
        break;
    }
    return withEffects(st, acc);
}

function enterWait(state) {
    var st = Object.assign({}, state);
    st.phase = "wait";
    st.deadline = 0;
    st.continueEnabled = true;
    st.effects = [];
    return decorate(st);
}

function withEffects(state, effects) {
    var st = Object.assign({}, state);
    st.effects = effects;
    return decorate(st);
}

// Resume working through a break: extend the deadline, un-count the aborted break
// (when coming from break; already-un-counted when extending an active delay).
function disable(state) {
    var st = Object.assign({}, state);
    st.phase = "disabled";
    st.deadline = 0;
    st.pendingBreak = false;
    st.continueEnabled = false;
    st.largeBreak = false;
    return decorate(st);
}

var DEFAULT_PRESET = { label: "50/10", workMin: 50, breakMin: 10 };
function delayWork(state, now, extensionMs) {
    var st = Object.assign({}, state);
    st.phase = "work";
    st.deadline = now + extensionMs;
    st.pendingBreak = true;
    st.completedBlocks = state.phase === "break"
        ? state.completedBlocks - 1   // the break never happened
        : state.completedBlocks;
    st.continueEnabled = false;
    st.effects = [];
    return decorate(st);
}

function enterBreak(state, atInstant) {
    // Normalize defensively: presets can arrive raw from restored snapshots.
    var src = normalizePreset(state.preset);
    var breakNo = state.completedBlocks + 1;
    var isLarge = breakNo % saneCycleLength(state.cycleLength) === 0;
    var breakMin = isLarge
        ? (src.largeBreakMin !== undefined && src.largeBreakMin !== null
            ? src.largeBreakMin
            : largeBreakMinutes(src.breakMin))
        : src.breakMin;
    var effects = [
        { type: "showOverlay" },
        { type: "pauseMedia" },
        { type: "chime" }
    ];
    var st = Object.assign({}, state);
    st.phase = "break";
    st.deadline = atInstant + breakMin * MIN;
    st.completedBlocks = breakNo;
    st.largeBreak = isLarge;
    st.continueEnabled = false;
    st.effects = effects;
    return decorate(st);
}

function enterWork(state, preset, now, effects) {
    var st = Object.assign({}, state);
    st.phase = "work";
    st.preset = normalizePreset(preset); // store sane values for later breaks/continues
    st.deadline = now + st.preset.workMin * MIN;
    st.pendingBreak = false;
    st.largeBreak = false;
    st.continueEnabled = false;
    st.effects = effects;
    return decorate(st);
}
