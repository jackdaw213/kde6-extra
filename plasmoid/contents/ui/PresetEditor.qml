/*
 * Preset editor — config dialog page.
 * Edits {label, workMin, breakMin, largeBreakMin?}; hard cap of 5 presets total:
 * the 6th is refused with an explanatory message. First preset is the default.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
    id: editor

    property var presets: parsePresets(Plasmoid.configuration.presets)
    readonly property int maxPresets: 5

    function parsePresets(json) {
        try {
            const arr = JSON.parse(json || "");
            if (Array.isArray(arr) && arr.length > 0)
                return arr;
        } catch (e) {}
        return [
            { label: "50/10", workMin: 50, breakMin: 10 },
            { label: "25/5", workMin: 25, breakMin: 5 },
            { label: "45/15", workMin: 45, breakMin: 15 }
        ];
    }

    function writeBack() {
        Plasmoid.configuration.presets = JSON.stringify(editor.presets);
    }

    function removeRow(i) {
        if (editor.presets.length <= 1)
            return;
        const arr = editor.presets.slice();
        arr.splice(i, 1);
        editor.presets = arr;
        writeBack();
    }

    function addRow() {
        if (editor.presets.length >= editor.maxPresets)
            return false;
        const arr = editor.presets.slice();
        arr.push({ label: "custom", workMin: 25, breakMin: 5 });
        editor.presets = arr;
        writeBack();
        return true;
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Kirigami.Units.gridUnit
        }
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 3
            text: i18n("Presets") // qmllint disable unqualified
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("A preset is a Work Block and Break pair in minutes. The first preset is the default. \"Large break\" of 0 means it is derived automatically. Maximum %1 presets.", editor.maxPresets) // qmllint disable unqualified
        }

        // ----------------------------------------------------------- column heads

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.preferredWidth: editor.width * 0.34
                text: i18n("Name") // qmllint disable unqualified
            }
            QQC2.Label {
                Layout.preferredWidth: editor.width * 0.17
                text: i18n("Work") // qmllint disable unqualified
            }
            QQC2.Label {
                Layout.preferredWidth: editor.width * 0.17
                text: i18n("Break") // qmllint disable unqualified
            }
            QQC2.Label {
                Layout.preferredWidth: editor.width * 0.17
                text: i18n("Large break") // qmllint disable unqualified
            }
            Item {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
            }
        }

        // ------------------------------------------------------------ preset rows

        Repeater {
            id: rowRepeater
            model: editor.presets.length

            RowLayout {
                id: row
                required property int index
                spacing: Kirigami.Units.smallSpacing

                // commit() stores this row's widgets' current values back into
                // editor.presets[index]; the sibling ids below are in the same
                // component scope, so every read is statically resolved.
                function commit() {
                    editor.presets[index] = {
                        label: labelField.text.length > 0 ? labelField.text : editor.presets[index].label,
                        workMin: workSpin.value,
                        breakMin: breakSpin.value
                    };
                    if (largeSpin.value > 0)
                        editor.presets[index].largeBreakMin = largeSpin.value;
                    editor.writeBack();
                }

                QQC2.TextField {
                    id: labelField
                    Layout.preferredWidth: editor.width * 0.34
                    text: editor.presets[row.index].label
                    onEditingFinished: row.commit()
                }
                QQC2.SpinBox {
                    id: workSpin
                    Layout.preferredWidth: editor.width * 0.17
                    from: 1
                    to: 600
                    editable: true
                    value: editor.presets[row.index].workMin
                    onValueModified: row.commit()
                }
                QQC2.SpinBox {
                    id: breakSpin
                    Layout.preferredWidth: editor.width * 0.17
                    from: 1
                    to: 600
                    editable: true
                    value: editor.presets[row.index].breakMin
                    onValueModified: row.commit()
                }
                QQC2.SpinBox {
                    id: largeSpin
                    Layout.preferredWidth: editor.width * 0.17
                    from: 0
                    to: 600
                    editable: true
                    value: editor.presets[row.index].largeBreakMin || 0
                    onValueModified: row.commit()
                }
                QQC2.ToolButton {
                    id: removeButton
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    icon.name: "edit-delete-remove"
                    enabled: editor.presets.length > 1
                    onClicked: editor.removeRow(row.index)
                    QQC2.ToolTip {
                        visible: removeButton.hovered
                        text: i18n("Remove preset") // qmllint disable unqualified
                    }
                }
            }
        }

        // ---------------------------------------------------------------- add row

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                icon.name: "list-add"
                text: i18n("Add preset") // qmllint disable unqualified
                enabled: editor.presets.length < editor.maxPresets
                onClicked: editor.addRow()
            }

            QQC2.Label {
                visible: editor.presets.length >= editor.maxPresets
                color: Kirigami.Theme.neutralTextColor
                text: i18n("Limit reached: %1 presets maximum. Remove one to add another.", editor.maxPresets) // qmllint disable unqualified
            }
        }

        Item {
            Layout.fillHeight: true
        }

        // ------------------------------------------------------- cycle length

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.SpinBox {
                id: cycleSpin
                from: 2
                to: 12
                editable: true
                value: {
                    var v = Plasmoid.configuration.cycleLength;
                    return (Number.isInteger(v) && v >= 2) ? v : 4;
                }
                onValueModified: Plasmoid.configuration.cycleLength = cycleSpin.value
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Large break every %1 work blocks (its length uses the preset's large-break value, or the automatic rule)", cycleSpin.value) // qmllint disable unqualified
            }
        }
    }
}
