/*
 * Auto-start notification adapter (SPEC-003).
 *
 * Sends exactly one informational desktop notification via the freedesktop
 * notification service: no action buttons, no sound. Failure is logged and
 * never blocks the started Work Block. Loaded via a Loader from main.qml for
 * graceful degradation.
 */
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: notifier

    function notifyAutoStart(presetLabel) {
        try {
            let reply = DBus.SessionBus.asyncCall({
                service: "org.freedesktop.Notifications",
                path: "/org/freedesktop/Notifications",
                iface: "org.freedesktop.Notifications",
                member: "Notify",
                arguments: [
                    "Pomodoro",
                    0,
                    "",
                    "Pomodoro started",
                    "Work block " + presetLabel + " started automatically.",
                    [],
                    {},
                    5000
                ]
            });
            reply.finished.connect(function () {
                if (reply.isError)
                    console.warn("pomodoro: auto-start notification failed:", reply.error.message);
            });
        } catch (e) {
            console.warn("pomodoro: auto-start notification failed:", e);
        }
    }
}
