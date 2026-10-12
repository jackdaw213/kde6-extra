/*
 * Pomodoro plasmoid — Plasma 6 root component.
 *
 * The controller below owns the machine state (plasmoid/contents/ui/pomodoro-machine.js),
 * executes the machine's emitted effects (overlay show/hide, media pause, chime) and
 * persists a state snapshot on every change. All UI (compact + popup + overlay) binds
 * to this controller.
 */
// Bound: the compact/full representation components below reference ids from this
// file (the controller); Qt 6 requires this pragma for that to be statically legal.
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid

import "pomodoro-machine.js" as Machine

PlasmoidItem {
    id: root

    compactRepresentation: CompactRepresentation { ctrl: controller }
    fullRepresentation: FullRepresentation { ctrl: controller; presetsJson: root.cfgPresets }

    // ------------------------------------------------------------------ controller

    QtObject {
        id: controller

        property var state: Machine.initialState()
        property bool loaded: false

        property bool running: controller.state.phase === "work" || controller.state.phase === "break"
        property string phase: controller.state.phase
        property bool continueEnabled: controller.state.phase === "wait" && controller.state.continueEnabled === true
        property bool largeBreak: controller.state.largeBreak === true
        property bool pendingBreak: controller.state.pendingBreak === true
        property var preset: controller.state.preset

        // Remaining time of the active phase ("" when there is nothing to count down).
        readonly property string remainingText: {
            if (!controller.loaded || (controller.state.phase !== "work" && controller.state.phase !== "break"))
                return "";
            return controller.formatMs(controller.state.remainingMs(Date.now()));
        }

        function formatMs(ms) {
            var totalSec = Math.max(0, Math.floor(ms / 1000));
            var m = Math.floor(totalSec / 60);
            var s = totalSec % 60;
            return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
        }

        // Central intent dispatch: handle → replace state → execute effects → persist.
        function dispatch(type, extra) {
            if (!controller.loaded)
                return;
            var intent = extra || {};
            intent.type = type;
            var now = Date.now();
            var next = Machine.handle(controller.state, intent, now);
            if (next === controller.state)
                return;
            controller.state = Machine.decorate(next);
            executeEffects();
            persist();
        }

        function tick() {
            if (!controller.loaded)
                return;
            var now = Date.now();
            var next = Machine.tick(controller.state, now);
            if (next === controller.state)
                return;
            // Machine.tick always returns a fresh clone; only boundaries are meaningful.
            var changed = next.phase !== controller.state.phase
                || next.deadline !== controller.state.deadline
                || next.completedBlocks !== controller.state.completedBlocks
                || next.pendingBreak !== controller.state.pendingBreak
                || next.continueEnabled !== controller.state.continueEnabled;
            controller.state = Machine.decorate(next);
            if (changed) {
                executeEffects();
                persist();
            }
        }

        // Popup control lives on the PlasmoidItem, not on the attached object;
        // representations call these instead of touching Plasmoid directly.
        function togglePopup() {
            root.expanded = !root.expanded;
        }

        function closePopup() {
            root.expanded = false;
        }

        function executeEffects() {
            var effects = controller.state.effects || [];
            for (let i = 0; i < effects.length; i++) {
                switch (effects[i].type) {
                case "showOverlay":
                    overlayWindow.open();
                    break;
                case "hideOverlay":
                    overlayWindow.close();
                    break;
                case "pauseMedia":
                    root.mprisBridge.pauseAll();
                    break;
                case "chime":
                    root.chimeBridge.chime();
                    break;
                }
            }
        }

        function persist() {
            root.cfgStateSnapshot = JSON.stringify({
                phase: controller.state.phase,
                deadline: controller.state.deadline,
                preset: controller.state.preset,
                completedBlocks: controller.state.completedBlocks,
                cycleLength: controller.state.cycleLength,
                pendingBreak: controller.state.pendingBreak,
                largeBreak: controller.state.largeBreak === true
            });
        }

        // UI-facing intents (called by popup and overlay).

        function startPreset(preset) {
            dispatch("startPreset", { preset: preset });
        }

        function startCustom(workMin, breakMin) {
            dispatch("startPreset", { preset: { label: "custom", workMin: workMin, breakMin: breakMin } });
        }

        function continueBreak() {
            dispatch("continue");
        }

        function skipBreakConfirmed() {
            dispatch("skipBreakConfirmed");
        }

        function delayBreak() {
            dispatch("delayBreak");
        }

        function startBreakNow() {
            dispatch("startBreakNow");
        }

        function disable() {
            dispatch("disable");
        }

        function enable() {
            dispatch("enable");
        }

        // Restore the persisted snapshot and settle it with one wall-clock tick:
        // a deadline crossed while away transitions immediately (overlay returns
        // mid-break, or lands in enabled-continue wait) without stretching time.
        function restore() {
            var snap = null;
            try {
                snap = JSON.parse(Plasmoid.configuration.stateSnapshot || "null");
            } catch (e) {
                snap = null;
            }
            var validPreset = snap && snap.preset
                && typeof snap.preset.workMin === "number" && isFinite(snap.preset.workMin)
                && typeof snap.preset.breakMin === "number" && isFinite(snap.preset.breakMin);
            var validCycle = snap && Number.isInteger(snap.cycleLength) && snap.cycleLength > 0;
            if (snap
                && typeof snap.phase === "string"
                && typeof snap.deadline === "number" && isFinite(snap.deadline)
                && ((snap.phase === "idle" || snap.phase === "disabled") || validPreset)) {
                controller.state = Machine.decorate({
                    phase: snap.phase,
                    deadline: snap.deadline || 0,
                    preset: validPreset ? snap.preset : null,
                    completedBlocks: snap.completedBlocks || 0,
                    cycleLength: validCycle ? snap.cycleLength : (root.cfgCycleLength || Machine.CYCLE_LENGTH_DEFAULT),
                    pendingBreak: snap.pendingBreak === true,
                    continueEnabled: snap.phase === "wait",
                    largeBreak: snap.largeBreak === true,
                    effects: []
                });
            } else {
                controller.state = Machine.initialState();
                controller.state.cycleLength = root.cfgCycleLength || Machine.CYCLE_LENGTH_DEFAULT;
            }
            controller.loaded = true;
            tick();
            // A plasmashell restart mid-break or mid-wait must not leave the break
            // unenforced: no boundary is crossed for a future deadline, so show the
            // overlay directly from the restored phase.
            if (controller.state.phase === "break" || controller.state.phase === "wait")
                overlayWindow.open();
        }
    }

    // --------------------------------------------------------------- config access

    // kcfg-backed config; writes go through these so snapshots are durable immediately.
    property string cfgStateSnapshot
    onCfgStateSnapshotChanged: Plasmoid.configuration.stateSnapshot = cfgStateSnapshot

    property int cfgCycleLength: {
        var v = Plasmoid.configuration.cycleLength;
        return (Number.isInteger(v) && v > 0) ? v : Machine.CYCLE_LENGTH_DEFAULT;
    }
    onCfgCycleLengthChanged: {
        // Take effect for the next breaks; keep the machine carrying the current value.
        controller.state.cycleLength = cfgCycleLength;
    }
    readonly property string cfgPresets: Plasmoid.configuration.presets

    Component.onCompleted: controller.restore()

    // ------------------------------------------------------------------- heartbeat

    Timer {
        interval: 1000
        repeat: true
        running: controller.loaded && controller.phase !== "disabled"
        onTriggered: controller.tick()
    }

    // ---------------------------------------------------------- effect adapters

    // Media pause behind a Loader: the kmpris QML module ships with plasma-workspace;
    // if the import fails on some setup, the plasmoid degrades gracefully (logged).
    Loader {
        id: mprisLoader
        source: "MprisPauser.qml"
    }
    QtObject {
        id: mprisBridgeFallback
        function pauseAll() {
            console.warn("pomodoro: MPRIS module unavailable, media pause skipped");
        }
    }
    readonly property var mprisBridge: mprisLoader.status === Loader.Ready && mprisLoader.item ? mprisLoader.item : mprisBridgeFallback

    // Chime behind a Loader for the same graceful-degradation reason (QtMultimedia).
    Loader {
        id: chimeLoader
        source: "Chimer.qml"
    }
    QtObject {
        id: chimeBridgeFallback
        function chime() {
            console.warn("pomodoro: audio module unavailable, chime skipped");
        }
    }
    readonly property var chimeBridge: chimeLoader.status === Loader.Ready && chimeLoader.item ? chimeLoader.item : chimeBridgeFallback

    // The break overlay lives in this process (LayerShellQt overlay surface);
    // its buttons call the controller directly — no IPC anywhere.
    Overlay {
        id: overlayWindow
        ctrl: controller

        function open() {
            if (!visible)
                visible = true;
        }
        function close() {
            if (visible) {
                visible = false;
                disarm();
            }
        }
    }
}
