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
    fullRepresentation: FullRepresentation {
        ctrl: controller
        presetsJson: root.cfgPresets
        defaultPreset: root.cfgDefaultPreset
        deskReminderEnabled: root.cfgDeskReminderEnabled
        deskReminderMinutes: root.cfgDeskReminderMinutes
        // Card writes persist straight into the kcfg database; the cfg* bindings
        // echo them back so the grid re-renders from the stored truth.
        onPresetsWritten: (json) => Plasmoid.configuration.presets = json
        onDefaultPresetWritten: (presetIndex) => Plasmoid.configuration.defaultPreset = presetIndex
        onDeskReminderEnabledWritten: (enabled) => Plasmoid.configuration.deskReminderEnabled = enabled
        onDeskReminderMinutesWritten: (minutes) => Plasmoid.configuration.deskReminderMinutes = minutes
    }

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
        // Desk Overlay mode: the same overlay window shows the desk prompt while
        // it is due; a break/wait phase always takes the window instead (the
        // machine clears deskDue on every break, so this cannot deadlock).
        property bool deskDue: controller.state.deskDue === true

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
                || next.continueEnabled !== controller.state.continueEnabled
                || next.deskDeadline !== controller.state.deskDeadline
                || next.deskDue !== controller.state.deskDue;
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
                case "showDeskOverlay":  // same window; Overlay picks the content by mode
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
                largeBreak: controller.state.largeBreak === true,
                // Desk fields restore by wall clock like the main deadline; a
                // due prompt must survive too or a restart would hide the overlay.
                deskDeadline: controller.state.deskDeadline,
                deskDue: controller.state.deskDue === true
            });
        }

        // UI-facing intents (called by popup and overlay).

        function startPreset(preset) {
            dispatch("startPreset", { preset: preset });
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

        function deskAck() {
            dispatch("deskAck");
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
            var validDesk = snap && typeof snap.deskDeadline === "number" && isFinite(snap.deskDeadline);
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
                    deskDeadline: validDesk ? snap.deskDeadline : 0,
                    deskDue: snap.deskDue === true,
                    deskEnabled: root.cfgDeskReminderEnabled,
                    deskMinutes: root.cfgDeskReminderMinutes,
                    defaultPreset: root.defaultPresetObj,
                    effects: []
                });
            } else {
                controller.state = Machine.initialState();
                controller.state.cycleLength = root.cfgCycleLength || Machine.CYCLE_LENGTH_DEFAULT;
                controller.state.deskEnabled = root.cfgDeskReminderEnabled;
                controller.state.deskMinutes = root.cfgDeskReminderMinutes;
                controller.state.defaultPreset = root.defaultPresetObj;
            }
            controller.loaded = true;
            tick();
            // A plasmashell restart mid-break or mid-wait must not leave the break
            // unenforced, and a due desk prompt must come back: no boundary is
            // crossed for future deadlines, so show the overlay from the restored
            // phase directly.
            if (controller.state.phase === "break" || controller.state.phase === "wait" || controller.state.deskDue)
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

    // ------------------------------------------------- preset card & desk config

    readonly property int cfgDefaultPreset: Plasmoid.configuration.defaultPreset
    readonly property bool cfgDeskReminderEnabled: Plasmoid.configuration.deskReminderEnabled
    readonly property int cfgDeskReminderMinutes: Plasmoid.configuration.deskReminderMinutes

    // Six-slot view of the stored presets (machine normalization re-seeds lost
    // Built-ins on every read).
    readonly property var presetSlots: Machine.normalizePresetSlots(cfgPresets)

    // The starred preset resolved to an object for the machine's enable intent;
    // empty or out-of-range stars fall back to the first Built-in.
    readonly property var defaultPresetObj: {
        var s = root.presetSlots;
        var i = root.cfgDefaultPreset;
        return (i >= 0 && i <= 5 && s[i]) ? s[i] : s[0];
    }

    // Push the resolved star into the machine so Enable starts the chosen preset.
    function syncDefaultPreset() {
        if (!controller.loaded)
            return;
        controller.state.defaultPreset = root.defaultPresetObj;
    }
    onCfgPresetsChanged: root.syncDefaultPreset()
    onCfgDefaultPresetChanged: root.syncDefaultPreset()

    onCfgDeskReminderEnabledChanged: {
        if (!controller.loaded)
            return;
        controller.state.deskEnabled = cfgDeskReminderEnabled;
        if (!cfgDeskReminderEnabled && controller.state.deskDue) {
            // Toggling off must not leave the prompt hanging: acknowledge through
            // the machine so the overlay closes by the very same path as the button.
            controller.deskAck();
        }
    }
    onCfgDeskReminderMinutesChanged: {
        if (controller.loaded)
            controller.state.deskMinutes = cfgDeskReminderMinutes;
    }

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
