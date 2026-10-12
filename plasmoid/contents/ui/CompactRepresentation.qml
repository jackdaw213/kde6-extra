/*
 * Compact (panel) representation: timer icon while idle, remaining mm:ss while running.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: compact

    required property var ctrl

    implicitWidth: compact.running ? Math.ceil(timeLabel.implicitWidth) : Kirigami.Units.iconSizes.small
    implicitHeight: Kirigami.Units.iconSizes.small

    readonly property bool running: ctrl.running
    readonly property string remainingText: ctrl.remainingText || "0:00"

    // Plasma 6's org.kde.plasma.core no longer exports IconItem; stock applets
    // use Kirigami.Icon (see /usr/share/plasma/plasmoids/*/CompactRepresentation.qml).
    Kirigami.Icon {
        anchors.fill: parent
        visible: !compact.running
        source: "chronometer"
    }

    Kirigami.Heading {
        id: timeLabel
        anchors.centerIn: parent
        visible: compact.running
        level: 5
        text: compact.remainingText
        textFormat: Text.PlainText
    }

    // Stock click handling (cf. kdeconnect CompactRepresentation): a grabbing
    // MouseArea toggling the PlasmoidItem's expanded state. TapHandler is a
    // passive handler and gets starved by plasmashell's panel click management.
    MouseArea {
        anchors.fill: parent
        onClicked: compact.ctrl.togglePopup()
    }
}
