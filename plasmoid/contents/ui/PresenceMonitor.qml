/*
 * Presence monitor adapter — the session's lock state (SPEC-003).
 *
 * Primary source: the screen saver service on the session bus
 * (org.freedesktop.ScreenSaver.GetActive + ActiveChanged). When that service is
 * absent, the adapter falls back to logind's LockedHint on the system bus
 * (org.freedesktop.login1), polled once per second. Idle-time and window probes
 * are deliberately not used (unsupported / interactive).
 *
 * The machine only ever sees raw lock/unlock intents, and only on transitions.
 * An observation is recorded only after the controller applies it, so a reply
 * that lands before the controller is ready is retried by the next poll rather
 * than swallowed. Loaded via a Loader from main.qml so a missing module (or an
 * absent lock service) degrades to a logged, inert monitor instead of breaking
 * the plasmoid.
 */
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: monitor

    // Host controller; main.qml attaches it when the Loader finishes.
    property var ctrl: null
    // False until a successful lock-state reply; the card reads this to disable
    // the auto-start switch and explain why.
    property bool lockSourceAvailable: false

    // Last state the controller actually applied, so polling never re-dispatches
    // an unchanged value and never records an observation the controller missed.
    property bool haveState: false
    property bool lastLocked: false
    property bool unavailableLogged: false
    // The screen saver failed once; use logind's LockedHint from then on.
    property bool useLogind: false
    property bool logindFallbackLogged: false
    property var pendingReply: null

    // A D-Bus variant may arrive as a plain JS value (GetActive's bool) or as
    // one or more nested wrapper objects (Properties.Get's variant). Normalize
    // both shapes without trusting a fixed depth.
    function boolValue(v) {
        let cur = v;
        for (let depth = 0; depth < 4; depth++) {
            if (cur === true || cur === false)
                return cur;
            if (!cur || typeof cur !== "object")
                break;
            cur = cur.value;
        }
        return null;
    }

    function observe(active) {
        monitor.lockSourceAvailable = true;
        monitor.unavailableLogged = false;
        if (!monitor.ctrl)
            return;
        if (monitor.haveState && monitor.lastLocked === active)
            return;
        var applied = active ? monitor.ctrl.screenLocked() : monitor.ctrl.screenUnlocked();
        if (applied !== true)
            return; // controller not loaded yet: the next poll retries
        monitor.haveState = true;
        monitor.lastLocked = active;
    }

    function reportUnavailable(reason) {
        monitor.lockSourceAvailable = false;
        // Forget the applied observation: the next successful poll is a fresh
        // observation and must be re-applied, not deduped against the state from
        // before the outage (the host has since been told the session is away).
        monitor.haveState = false;
        monitor.lastLocked = false;
        if (monitor.unavailableLogged)
            return;
        monitor.unavailableLogged = true;
        console.warn("pomodoro: lock source unavailable, presence features off:", reason);
    }

    function pollScreensaver() {
        try {
            let reply = DBus.SessionBus.asyncCall({
                service: "org.freedesktop.ScreenSaver",
                path: "/ScreenSaver",
                iface: "org.freedesktop.ScreenSaver",
                member: "GetActive"
            });
            monitor.pendingReply = reply;
            reply.finished.connect(function () {
                if (monitor.pendingReply === reply)
                    monitor.pendingReply = null;
                if (reply.isError) {
                    monitor.fallbackToLogind(reply.error.message);
                    return;
                }
                var active = monitor.boolValue(reply.values ? reply.values[0] : null);
                if (active === null) {
                    monitor.fallbackToLogind("GetActive returned no boolean");
                    return;
                }
                monitor.observe(active);
            });
        } catch (e) {
            monitor.fallbackToLogind(String(e));
        }
    }

    function fallbackToLogind(reason) {
        if (!monitor.logindFallbackLogged) {
            monitor.logindFallbackLogged = true;
            console.warn("pomodoro: screen saver unavailable, using logind LockedHint:", reason);
        }
        monitor.useLogind = true;
        monitor.pollLogind();
    }

    function pollLogind() {
        try {
            let reply = DBus.SystemBus.asyncCall({
                service: "org.freedesktop.login1",
                path: "/org/freedesktop/login1/session/auto",
                iface: "org.freedesktop.DBus.Properties",
                member: "Get",
                arguments: ["org.freedesktop.login1.Session", "LockedHint"]
            });
            monitor.pendingReply = reply;
            reply.finished.connect(function () {
                if (monitor.pendingReply === reply)
                    monitor.pendingReply = null;
                if (reply.isError) {
                    monitor.reportUnavailable("screen saver and logind unavailable: "
                                              + reply.error.message);
                    return;
                }
                var locked = monitor.boolValue(reply.values ? reply.values[0] : null);
                if (locked === null) {
                    monitor.reportUnavailable("LockedHint returned no boolean");
                    return;
                }
                monitor.observe(locked);
            });
        } catch (e) {
            monitor.reportUnavailable("logind fallback failed: " + String(e));
        }
    }

    function poll() {
        // Never stack polls behind an unanswered reply; its finished handler is
        // the only place that clears the slot, so a finished-but-unhandled reply
        // cannot be replaced by a newer call and apply a stale observation.
        if (monitor.pendingReply)
            return;
        if (monitor.useLogind)
            monitor.pollLogind();
        else
            monitor.pollScreensaver();
    }

    // The handler prefix is "dbus": SignalWatcher maps ActiveChanged to
    // dbusActiveChanged by contract.
    property var watcher: DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.freedesktop.ScreenSaver"
        path: "/ScreenSaver"
        iface: "org.freedesktop.ScreenSaver"

        function dbusActiveChanged(active) {
            monitor.observe(active === true);
        }
    }

    property var pollTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: monitor.poll()
    }

    Component.onCompleted: monitor.poll()
}
