/*
 * Popup (full representation): presets (first = default, marked), Custom one-off
 * pair, Start Break Now / Delay Break when relevant, and the Disable/Enable toggle.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: full

    required property var ctrl
    property string presetsJson

    readonly property var presets: parsePresets(presetsJson)
    readonly property string phase: ctrl.phase
    readonly property bool working: phase === "work"

    function parsePresets(json) {
        try {
            let arr = JSON.parse(json || "");
            if (Array.isArray(arr) && arr.length > 0 && arr.every(function (p) {
                return p && typeof p.label === "string" && p.workMin > 0 && p.breakMin > 0;
            }))
                return arr;
        } catch (e) {}
        return [
            { label: "50/10", workMin: 50, breakMin: 10 },
            { label: "25/5", workMin: 25, breakMin: 5 },
            { label: "45/15", workMin: 45, breakMin: 15 }
        ];
    }

    implicitWidth: Kirigami.Units.gridUnit * 17
    implicitHeight: column.implicitHeight + Kirigami.Units.gridUnit * 1.5

    // i18n() is a global injected at plasmoid runtime by KLocalizedContext; it
    // has no importable type, so unqualified warnings on it are silenced here.
    function statusText() {
        // qmllint disable unqualified
        switch (phase) {
        case "idle":
            return i18n("Idle");
        case "work":
            return i18n("Work — %1 remaining", ctrl.remainingText);
        case "break":
            return i18n("Break — %1 remaining", ctrl.remainingText);
        case "wait":
            return i18n("Break finished — take your time");
        case "disabled":
            return i18n("Disabled for now");
        default:
            return "";
        }
        // qmllint enable unqualified
    }

    ColumnLayout {
        id: column
        anchors {
            fill: parent
            margins: Kirigami.Units.gridUnit * 0.75
        }
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 4
            text: full.statusText()
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // -------------------------------------------------------- preset list

        Repeater {
            // Presets start a fresh block from any non-timing state (idle,
            // finished-break wait, meeting mode); hidden while timing so the
            // machine's guard and the UI stay coherent.
            model: full.working ? 0 : full.presets.length

            PlasmaComponents.Button {
                id: presetButton

                required property int index

                Layout.fillWidth: true
                text: (presetButton.index === 0 ? "★ " : "") + full.presets[presetButton.index].label
                onClicked: {
                    full.ctrl.closePopup();
                    full.ctrl.startPreset(full.presets[presetButton.index]);
                }
                QQC2.ToolTip {
                    visible: presetButton.hovered && presetButton.index === 0
                    text: i18n("Default preset") // qmllint disable unqualified
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: !full.working
        }

        // ------------------------------------------------------ custom one-off

        RowLayout {
            visible: !full.working
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Custom:") // qmllint disable unqualified
            }
            QQC2.SpinBox {
                id: customWork
                from: 1
                to: 600
                editable: true
            }
            QQC2.Label {
                text: i18n("min work") // qmllint disable unqualified
            }
            QQC2.SpinBox {
                id: customBreak
                from: 1
                to: 600
                editable: true
            }
            QQC2.Label {
                text: i18n("min break") // qmllint disable unqualified
            }
            PlasmaComponents.Button {
                icon.name: "media-playback-start"
                text: i18n("Start") // qmllint disable unqualified
                onClicked: {
                    full.ctrl.closePopup();
                    full.ctrl.startCustom(customWork.value, customBreak.value);
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: full.working
        }

        // ---------------------------------------------------- running actions

        PlasmaComponents.Button {
            visible: full.working
            Layout.fillWidth: true
            icon.name: "go-next-skip"
            text: i18n("Start break now") // qmllint disable unqualified
            onClicked: {
                full.ctrl.closePopup();
                full.ctrl.startBreakNow();
            }
        }

        PlasmaComponents.Button {
            visible: full.working && full.ctrl.pendingBreak
            Layout.fillWidth: true
            icon.name: "clock"
            text: i18n("Delay break 5 minutes") // qmllint disable unqualified
            onClicked: full.ctrl.delayBreak()
        }

        // -------------------------------------------------------------- toggle

        PlasmaComponents.Button {
            Layout.fillWidth: true
            icon.name: full.phase === "disabled" ? "checkmark" : "dialog-cancel"
            text: full.phase === "disabled" ? i18n("Enable") : i18n("Disable for now") // qmllint disable unqualified
            onClicked: full.phase === "disabled" ? full.ctrl.enable() : full.ctrl.disable()
        }

        // Hint toward the config dialog where presets are edited (cap of 5 lives there).
        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Edit presets in Configure — Presets") // qmllint disable unqualified
        }
    }
}
