/*
 * Break overlay — fullscreen LayerShellQt overlay surface (see docs/adr/0002).
 *
 * Owned by the plasmoid process: buttons call the machine controller directly.
 * Layer properties are set at construction (before the surface attaches); the
 * window is reused across breaks via the visible flag only.
 *
 * Enforced content (per glossary):
 *  - "Rest time" + remaining break mm:ss (wall-clock deadline, restart-surviving)
 *  - Continue disabled AND grayed for the whole break; enables exactly when the
 *    machine flips to "wait" (wall-clock, so it self-enables after a restart too)
 *  - Skip with a two-click confirmation ("Really skip this break?")
 *  - "Delay break 5 minutes" while the break is due (phase "break")
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window as QW
import org.kde.kirigami as Kirigami
import org.kde.layershell as LS

QW.Window {
    id: overlay

    required property var ctrl

    visible: false
    flags: Qt.FramelessWindowHint
    color: "#101218"
    // i18n is injected at plasmoid runtime by plasmashell (KLocalizedContext) and
    // is declared in no qmltypes, so every use needs an explicit lint directive.
    title: i18n("Pomodoro — rest time") // qmllint disable unqualified

    // --- layer surface definition (ATTACHED properties on this Window, applied at
    // construction before the surface attaches). LayerShellQt::Window is an attached
    // type (isCreatable: false — see LayerShellQtQml.qmltypes), NOT a child object.
    LS.Window.scope: "org.kde.plasma.pomodoro"
    LS.Window.layer: LS.Window.LayerOverlay
    LS.Window.keyboardInteractivity: LS.Window.KeyboardInteractivityNone
    LS.Window.screenConfiguration: LS.Window.ScreenConfiguration.ScreenFromCompositor
    LS.Window.anchors: LS.Window.AnchorTop | LS.Window.AnchorBottom | LS.Window.AnchorLeft | LS.Window.AnchorRight
    // Cover the whole screen including panel strips without disturbing anyone's
    // layout: -1 means "announce no exclusive zone", i.e. reserve nothing.
    LS.Window.exclusionZone: -1

    property bool layerSurfaceDefined: false
    // Runtime honesty (ADR-0002: degradation must not be silent). If the attached
    // object above evaluates, the LayerShellQt module loaded and the definition was
    // applied; actual attach-from-plasmashell is live-verified post-install (the
    // module exposes no attach-failure signal to check).
    Component.onCompleted: overlay.layerSurfaceDefined = true

    readonly property string phase: ctrl.phase
    readonly property bool breakDue: phase === "break"
    readonly property bool resting: phase === "break" || phase === "wait"

    // Skip guard: first click arms, second click (Yes) confirms.
    property bool skipArmed: false
    function disarm() {
        skipArmed = false;
    }

    onVisibleChanged: {
        if (visible && !overlay.layerSurfaceDefined)
            console.warn("pomodoro: overlay visible without a loaded layer-shell module — " +
                         "falling back to a plain window; it may be covered by fullscreen apps");
        if (!visible)
            overlay.disarm();
    }

    Timer {
        // disarm the skip confirmation if left unanswered
        interval: 8000
        running: overlay.visible && overlay.skipArmed
        onTriggered: overlay.disarm()
    }

    Rectangle {
        anchors.fill: parent
        color: "#101218"

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.gridUnit

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                color: "white"
                font.pointSize: 34
                font.weight: Font.Bold
                text: i18n("Rest time") // qmllint disable unqualified
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                visible: overlay.ctrl.largeBreak
                color: "#c9d1d9"
                font.pointSize: 16
                text: i18n("Large break") // qmllint disable unqualified
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                color: "white"
                font.pointSize: 88
                text: overlay.phase === "break" ? overlay.ctrl.remainingText : i18n("Take your time") // qmllint disable unqualified
                textFormat: Text.PlainText
            }

            QQC2.Button {
                id: continueButton
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.6
                enabled: overlay.ctrl.continueEnabled
                opacity: enabled ? 1.0 : 0.45          // visibly grayed for the whole break
                text: enabled ? i18n("Continue back to work") : i18n("Resting…") // qmllint disable unqualified
                onClicked: overlay.ctrl.continueBreak()
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing
                visible: overlay.breakDue

                QQC2.Button {
                    visible: !overlay.skipArmed
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    text: i18n("Skip break") // qmllint disable unqualified
                    onClicked: overlay.skipArmed = true
                }

                QQC2.Label {
                    visible: overlay.skipArmed
                    color: "white"
                    text: i18n("Really skip work?") // qmllint disable unqualified
                }
                QQC2.Button {
                    visible: overlay.skipArmed
                    text: i18n("Yes, skip") // qmllint disable unqualified
                    onClicked: overlay.ctrl.skipBreakConfirmed()
                }
                QQC2.Button {
                    visible: overlay.skipArmed
                    text: i18n("No") // qmllint disable unqualified
                    onClicked: overlay.disarm()
                }
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                visible: overlay.breakDue
                text: i18n("Delay break 5 minutes") // qmllint disable unqualified
                onClicked: overlay.ctrl.delayBreak()
            }
        }
    }
}
