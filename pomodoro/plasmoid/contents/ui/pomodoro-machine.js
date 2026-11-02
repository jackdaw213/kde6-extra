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

var DESK_MINUTES_DEFAULT = 30; // Desk Reminder interval when the host supplies garbage
var AUTO_START_MINUTES_DEFAULT = 5; // Presence window when the host supplies garbage

// Working hours (SPEC-004): the fixed daily span during which Auto-start may
// fire — 9:00 to 17:00 local time, every day, as minutes-of-day bounds.
var WORKING_HOURS_START_MIN = 9 * 60;  // 540 — 9:00 local, inclusive
var WORKING_HOURS_END_MIN = 17 * 60;   // 1020 — 17:00 local, exclusive

// Canonical Built-in presets — always occupy slots 0-2 of the six-slot preset
// storage (SPEC-002); a lost or garbled slot is re-seeded from here.
var BUILTIN_SLOTS = [
    { label: "50/10", workMin: 50, breakMin: 10 },
    { label: "25/5", workMin: 25, breakMin: 5 },
    { label: "45/15", workMin: 45, breakMin: 15 }
];

// Hostile-value guards: config JSON is user-editable and presets arrive from
// both the editor and (raw) from restored snapshots. A garbage minute value
// must degrade to a safe fallback, never to a hung timer or a skipped rest.
function saneMinutes(v, fallback) {
    var n = Math.round(Number(v));
    return (isFinite(n) && n > 0) ? n : fallback;
}

// UI naming contract: a preset's label IS its minutes ("W/B") — there is no
// custom name field anywhere. Built-ins keep their canonical labels; user
// presets are always relabeled through this, so the grid/star picker/rows all
// show the same minutes-derived identity with zero extra UI work.
function derivedLabel(workMin, breakMin) {
    return saneMinutes(workMin, 0) + "/" + saneMinutes(breakMin, 0);
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

// True when p is a preset object worth keeping: a real label and sane minutes.
function isSanePreset(p) {
    return !!(p && typeof p === "object"
        && typeof p.label === "string" && p.label.length > 0
        && saneMinutes(p.workMin, 0) > 0
        && saneMinutes(p.breakMin, 0) > 0);
}

// Slot index of the canonical Built-in equal to p, or -1. Equality is exact on
// label and minutes: a renamed or re-tuned entry is a user preset, not the built-in.
// Public: the card's editor reuses this to refuse writes that locked storage
// would silently drop.
function builtinIndex(p) {
    for (var i = 0; i < BUILTIN_SLOTS.length; i++) {
        var b = BUILTIN_SLOTS[i];
        if (p.label === b.label
            && saneMinutes(p.workMin, 0) === b.workMin
            && saneMinutes(p.breakMin, 0) === b.breakMin)
            return i;
    }
    return -1;
}

// Normalizes the stored presets into the fixed six-slot shape (SPEC-002):
// slots 0-2 are always the seeded Built-ins (re-seeded when a hand-edited or
// legacy config lost them), slots 3-5 are user presets or null when empty.
// Accepts a JSON string (config form) or an array. User presets are compacted
// into slots 3-5 in document order (card-written JSON is already contiguous,
// so that form is a fixed point); pre-SPEC-002 arrays could hold user presets
// in slots 0-2 (deleting a built-in shifted customs up) — those survive by the
// same compaction, capped at three, extras dropped, since the grid never grows.
// User-slot labels are FORCED to derivedLabel(workMin, breakMin) on every read:
// legacy hand-named entries ("custom", "Deep Work", …) migrate to the derived
// form, which is the preset's only identity under the no-name-field contract.
// (The exact-Built-in drop runs BEFORE the relabel, so a stored entry that
// matches a Built-in lock-seed canonically and is never duplicated.)
function normalizePresetSlots(raw) {
    var arr = null;
    try {
        var v = typeof raw === "string" ? JSON.parse(raw || "null") : raw;
        if (Array.isArray(v))
            arr = v;
    } catch (e) {
        arr = null;
    }
    var users = [];
    if (arr) {
        arr.forEach(function (p) {
            if (!isSanePreset(p))
                return;
            // Exact built-in matches are locked storage: they re-seed canonically
            // and are never duplicated into the user slots.
            if (builtinIndex(p) >= 0)
                return;
            if (users.length < 3)
                users.push(Object.assign({}, p, { label: derivedLabel(p.workMin, p.breakMin) }));
        });
    }
    var out = [];
    for (var b = 0; b < 3; b++)
        out.push(Object.assign({}, BUILTIN_SLOTS[b]));
    for (var u = 0; u < 3; u++)
        out.push(users[u] || null);
    return out;
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
        // Desk Reminder (SPEC-002): independent auxiliary countdown. Host-supplied
        // config rides the state like cycleLength; deskDeadline is epoch ms with
        // 0 = not armed, deskDue = the prompt is up awaiting acknowledgement.
        deskDeadline: 0,
        deskDue: false,
        deskEnabled: false,
        deskMinutes: DESK_MINUTES_DEFAULT,
        defaultPreset: null,  // host-resolved star preset; null = built-in default
        // Presence (SPEC-003): host-supplied config, machine-owned window/pause.
        // presenceSince 0 = no window; only the lock/unlock intents touch it.
        autoStartEnabled: false,
        autoStartMinutes: 5,
        autoStartArmed: false,
        presenceSince: 0,
        locked: false,
        paused: false,
        pausedRemainingMs: 0,
        deskPausedRemainingMs: 0,
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
        // A Paused Work Block is not running: ending it would discard the frozen
        // work the user still owes. Resume it first (unlock), then end it.
        if (state.phase !== "work" || state.paused === true)
            return state;
        return enterBreak(state, now);
    case "deskAck":
        // "Done — I switched": dismiss the Desk Overlay and start a fresh posture
        // interval — but only while work keeps running; otherwise nothing to arm.
        if (state.deskDue !== true)
            return state;
        var acked = Object.assign({}, state);
        acked.deskDue = false;
        acked.deskDeadline = (acked.phase === "work" && acked.deskEnabled === true)
            ? now + saneMinutes(acked.deskMinutes, DESK_MINUTES_DEFAULT) * MIN
            : 0;
        return withEffects(acked, [{ type: "hideOverlay" }]);
    case "disable":
        if (state.phase === "disabled")
            return state;
        // hideOverlay for any overlay that could be up: break/wait content, or
        // defensively the desk prompt (unreachable via the fullscreen UI, but the
        // machine must not assume the UI).
        var hid = (state.phase === "break" || state.phase === "wait" || state.deskDue)
            ? [{ type: "hideOverlay" }] : [];
        return withEffects(disable(state), hid);
    case "enable":
        if (state.phase !== "disabled")
            return state;
        // SPEC-002: the Default Preset is chosen in the card (any of the six
        // slots); the host resolves the config index and supplies the preset —
        // null/garbage falls back to the built-in default via normalization.
        return enterWork(state, state.defaultPreset || DEFAULT_PRESET, now, []);
    case "screenLocked":
        return screenLocked(state, now);
    case "screenUnlocked":
        return screenUnlocked(state, now);
    case "presenceTick":
        return presenceTick(state, now);
    case "presenceUnavailable":
        return presenceUnavailable(state);
    default:
        return state;
    }
}

// Screen lock pauses only a running, unpaused Work Block: its remaining work
// and desk times are frozen and both deadlines stop (SPEC-003 / ADR-0003).
// A Break keeps its wall-clock deadline; the wait has none to keep.
function screenLocked(state, now) {
    // A Disabled phase arms from a real lock even when an earlier source outage
    // already marked the machine locked. Do this before the identity guard, or
    // the first real lock after the outage would never re-arm Auto-start.
    if (state.phase === "disabled" && state.autoStartArmed !== true) {
        var armed = Object.assign({}, state);
        armed.locked = true;
        armed.presenceSince = 0;
        armed.autoStartArmed = true;
        armed.effects = [];
        return decorate(armed);
    }
    if (state.locked === true) {
        // A source outage marks the session locked but leaves a running Work
        // Block running (pause is off while the source is unreadable). The
        // first real observation after recovery must still freeze it.
        if (state.phase !== "work" || state.paused === true || state.deadline <= now)
            return state;
    }
    var st = Object.assign({}, state);
    st.locked = true;
    st.presenceSince = 0;
    st.effects = [];
    // A block whose deadline already passed is finished, not paused: leave the
    // deadline alone so the next tick starts the Break at the original expiry,
    // and the locked time counts as Break time (SPEC-003).
    if (st.phase === "work" && st.paused !== true && st.deadline > now) {
        st.paused = true;
        st.pausedRemainingMs = Math.max(0, st.deadline - now);
        // A due desk prompt has already stopped its countdown; keep the prompt
        // and freeze nothing for it. A deadline reached at the lock instant but
        // not yet observed by a tick freezes as 1 ms, so the prompt still fires
        // on the first resume tick instead of becoming a fresh full interval.
        st.deskPausedRemainingMs = (st.deskDue === true || st.deskEnabled !== true || !st.deskDeadline)
            ? 0
            : Math.max(1, st.deskDeadline - now);
        st.deadline = 0;
        st.deskDeadline = 0;
    }
    return decorate(st);
}

// The Presence window is config: a hostile value rounds, clamps 1-60, and
// falls back to 5. It never yields a non-positive or unbounded window.
function autoStartWindowMinutes(v) {
    var n = Math.round(Number(v));
    if (!isFinite(n))
        return AUTO_START_MINUTES_DEFAULT;
    return Math.min(60, Math.max(1, n));
}

// True when the epoch-ms instant lies inside Working hours (SPEC-004), judged
// on the local wall clock of that instant: [9:00, 17:00). No host dependency
// beyond the standard date API; no config field — the hours are constants.
function inWorkingHours(now) {
    var d = new Date(now);
    var minutesOfDay = d.getHours() * 60 + d.getMinutes();
    return minutesOfDay >= WORKING_HOURS_START_MIN && minutesOfDay < WORKING_HOURS_END_MIN;
}

// The only automatic-start path (SPEC-003): sustained Presence from idle or
// Disabled, gated to Working hours (SPEC-004). Timing phases and the
// finished-break wait are never interrupted; Disabled additionally requires a
// screen lock to have re-armed auto-start. A tick rejected by any guard —
// including the Working-hours gate — returns the state unchanged, so the open
// Presence window survives and the first in-hours tick fires.
function presenceTick(state, now) {
    if (state.autoStartEnabled !== true || state.locked === true)
        return state;
    if (state.phase !== "idle" && state.phase !== "disabled")
        return state;
    if (state.phase === "disabled" && state.autoStartArmed !== true)
        return state;
    var since = Number(state.presenceSince);
    if (!isFinite(since) || since <= 0 || since > now)
        return state;
    if (now - since < autoStartWindowMinutes(state.autoStartMinutes) * MIN)
        return state;
    // Working hours (SPEC-004): Auto-start fires only inside 9:00-17:00 local.
    // A rejected tick leaves the Presence window open — presence accrued
    // outside hours keeps counting, and a block started in-hours is never
    // clipped by the hours' end.
    if (!inWorkingHours(now))
        return state;
    var preset = normalizePreset(state.defaultPreset || DEFAULT_PRESET);
    var effects = [];
    // Defensive: a restored idle state can still carry a due desk prompt.
    if (state.deskDue === true)
        effects.push({ type: "hideOverlay" });
    effects.push({ type: "notifyAutoStart",
                   preset: derivedLabel(preset.workMin, preset.breakMin) });
    return enterWork(state, preset, now, effects);
}

// The lock source failed while the machine was loaded: close the Presence
// window and treat the session as away until a fresh observation arrives, so a
// stale window cannot auto-start after an outage. Host-driven.
function presenceUnavailable(state) {
    if (state.locked === true && state.presenceSince === 0)
        return state;
    var st = Object.assign({}, state);
    st.locked = true;
    st.presenceSince = 0;
    st.effects = [];
    return decorate(st);
}

// Unlock opens a fresh Presence window and resumes a Paused Work Block from the
// frozen remaining times. Repeated observations are identity no-ops (a monitor
// poll must never restart the window); the first observation after a restore is
// the one that opens it.
function screenUnlocked(state, now) {
    if (state.locked !== true && state.presenceSince > 0)
        return state;
    var st = Object.assign({}, state);
    st.locked = false;
    st.presenceSince = now;
    st.effects = [];
    if (st.phase === "work" && st.paused === true) {
        var deskRemaining = (st.deskPausedRemainingMs > 0)
            ? st.deskPausedRemainingMs
            : saneMinutes(st.deskMinutes, DESK_MINUTES_DEFAULT) * MIN;
        st.paused = false;
        st.deadline = now + Math.max(0, st.pausedRemainingMs);
        // A restored due prompt stays due; otherwise the desk countdown resumes
        // from its frozen time (or a full interval when none was frozen).
        st.deskDeadline = (st.deskDue === true || st.deskEnabled !== true)
            ? 0
            : now + deskRemaining;
        st.pausedRemainingMs = 0;
        st.deskPausedRemainingMs = 0;
    }
    return decorate(st);
}

function tick(state, now) {
    // Cascade: one tick may cross several phase boundaries (e.g. everything
    // expired while the session was away). Anchors stay at the original
    // expiry instants; effects accumulate across the crossed boundaries.
    var st = state;
    var acc = [];
    for (var guard = 0; guard < 10; guard++) {
        if (st.phase === "disabled" || st.phase === "idle") break;
        // A Paused Work Block has no active deadline; it must never expire or
        // step the desk countdown behind the lock screen (SPEC-003).
        if (st.phase === "work" && st.paused === true) break;
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
        if (st.phase === "work") {
            var desky = deskStep(st, now);
            if (desky !== st) {
                st = desky;
                acc = acc.concat(st.effects);
                continue;
            }
        }
        break;
    }
    return withEffects(st, acc);
}

// One Desk Reminder step while a Work Block is timing (spec: counts only during
// work, ticks like the work deadline). Arms lazily when the host enables it
// mid-block or a legacy snapshot carries no desk deadline; fires exactly once
// into the desk-due state; clears itself when the toggle is off.
function deskStep(state, now) {
    if (state.deskEnabled !== true) {
        if (!state.deskDeadline && !state.deskDue)
            return state;
        var off = Object.assign({}, state);
        off.deskDeadline = 0;
        off.deskDue = false;
        return decorate(off);
    }
    if (state.deskDue === true)
        return state;
    var dm = saneMinutes(state.deskMinutes, DESK_MINUTES_DEFAULT);
    if (!state.deskDeadline) {
        var armed = Object.assign({}, state);
        armed.deskDeadline = now + dm * MIN;  // full interval from now
        return decorate(armed);
    }
    if (now >= state.deskDeadline) {
        var due = Object.assign({}, state);
        due.deskDue = true;
        due.deskDeadline = 0;  // countdown stops; the prompt persists until ack/supersede
        return withEffects(due, [{ type: "showDeskOverlay" }, { type: "chime" }]);
    }
    return state;
}

function enterWait(state) {
    var st = Object.assign({}, state);
    st.phase = "wait";
    st.deadline = 0;
    st.continueEnabled = true;
    st.paused = false;
    st.pausedRemainingMs = 0;
    st.deskPausedRemainingMs = 0;
    st.effects = [];
    return decorate(st);
}

function withEffects(state, effects) {
    var st = Object.assign({}, state);
    st.effects = effects;
    return decorate(st);
}

// "Disable for now" (meeting mode): suspend everything — no deadline, no desk
// countdown, no desk prompt.
function disable(state) {
    var st = Object.assign({}, state);
    st.phase = "disabled";
    st.deadline = 0;
    st.pendingBreak = false;
    st.continueEnabled = false;
    st.largeBreak = false;
    st.deskDeadline = 0;
    st.deskDue = false;
    st.paused = false;
    st.pausedRemainingMs = 0;
    st.deskPausedRemainingMs = 0;
    st.autoStartArmed = false;
    return decorate(st);
}

var DEFAULT_PRESET = BUILTIN_SLOTS[0];

// Resume working through a break: extend the deadline, un-count the aborted break
// (when coming from break; already-un-counted when extending an active delay).
function delayWork(state, now, extensionMs) {
    var st = Object.assign({}, state);
    st.phase = "work";
    // A paused block has no live deadline: the extension joins the frozen
    // remaining time and waits with it for the unlock (SPEC-003).
    st.deadline = st.paused === true ? 0 : now + extensionMs;
    if (st.paused === true)
        st.pausedRemainingMs = Math.max(0, st.pausedRemainingMs) + extensionMs;
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
    // A due Break unconditionally outranks a pending Desk Overlay (spec): the
    // prompt is superseded and the countdown restarts with the next work phase.
    st.deskDue = false;
    st.deskDeadline = 0;
    st.paused = false;
    st.pausedRemainingMs = 0;
    st.deskPausedRemainingMs = 0;
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
    // Every fresh Work Block starts a new posture interval (only when the Desk
    // Reminder is on; otherwise no countdown may exist at all).
    st.deskDue = false;
    st.deskDeadline = st.deskEnabled === true
        ? now + saneMinutes(st.deskMinutes, DESK_MINUTES_DEFAULT) * MIN
        : 0;
    // A new Work Block ends any pause and consumes the Presence window.
    st.paused = false;
    st.pausedRemainingMs = 0;
    st.deskPausedRemainingMs = 0;
    st.presenceSince = 0;
    st.effects = effects;
    return decorate(st);
}
