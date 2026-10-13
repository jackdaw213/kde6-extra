/*
 * Popup (full representation) — SPEC-002 preset card, two pages in one
 * constant-size frame.
 *
 * Header row: status heading plus a gear ToolButton at the top right that
 * toggles between the two pages. MAIN page: 2×3 preset grid (three locked
 * Built-ins + three user slots) with the ★ marking the Default Preset.
 * Clicking an occupied slot starts it immediately (unchanged muscle memory);
 * an EMPTY user slot renders as a disabled "—" dash — there is nothing to do
 * here, presets are created in the settings page, never from the grid. While
 * the machine is timing (Work Block or Break — both refuse startPreset) the
 * grid stays visible but every cell disables, instead of hiding it and
 * leaving a hole in the card. SETTINGS page: sits on top of the main page,
 * faded out and input-disabled while closed — never visible:false, so neither
 * page ever drops out of the layout — and holds the star picker for any of
 * the six slots, one compact uniform row per user slot (the editor when
 * occupied, an "Add preset" button when empty — creation and in-place editing
 * live here), one always-reserved Built-in-collision warning line, the
 * automatic-Large-Break-rule hint, and the Desk Reminder toggle + interval.
 * Round 5 (derived naming + per-preset Large): a preset's label IS its minutes
 * ("W/B" — pomodoro-machine.js forces user-slot labels through derivedLabel
 * on every read); there is NO name field anywhere. Each user row edits Work,
 * Break and Large minutes (Large 0 = the automatic rule ≤6→20, 7–12→30,
 * ≥13→40) plus delete; the Built-in-collision refusal is therefore effectively
 * minutes-only and the Add default (30/5) deliberately avoids every Built-in
 * (a 25/5 default would exactly equal one and self-erase via locked storage).
 * The card keeps ONE size: the frame height
 * is the taller page's real implicitHeight, so toggling the gear,
 * starting/stopping a block or editing a preset never resizes the card or
 * moves the gear. The Configure dialog no longer manages presets; the old
 * Custom one-off row is gone (user presets cover arbitrary rhythms).
 *
 * Round-4 operator-feedback hardening: grid cells are pinned to ONE equal
 * explicit size (content no longer inflates cells); preset labels scale up
 * with the bigger tiles; the main page's action buttons live in a reserved,
 * always-laid-out strip so the machine phase can never push them below the
 * frame (round 5 compacted that strip: one natural-width running-actions row
 * plus the small-font Enable/Disable secondary beneath — none of the three
 * buttons is full-width anymore); occupied grid cells carry no tooltip (per-cell
 * popup windows were the churn source behind the flashing hover/press
 * highlight; the dash keeps its guidance tooltip).
 *
 * Round 6 (operator: vertical-space failures in the real shell): the grid
 * NO LONGER flexes — every cell is ONE fixed sane height (2.5 grid units:
 * the 14pt tile label measures 38px tall, so 45px leaves comfortable
 * padding) and the main page is pure content, with no spare-height absorber
 * to balloon the tiles over the action buttons. The preset editor is ONE
 * line ([Work][spin][Break][spin][Large][spin][delete]), collapsing every
 * settings row to a single control line, and the card widens 17 → 21 grid
 * units — the minimal probed width that fits the one-line editor row plus
 * the desk row without eliding (editor row measures 349px vs 351px of
 * content width; 20gu = 333px ALREADY overflows). The two wrap-hint labels
 * (largeBreakHint, deskHint) reserve a FIXED height for their measured
 * 2-line wrap at the constant content width: a wrapped QQC2 Label's implicit
 * height is width-dependent AND late-settling (the desktop style still
 * reports the one-line height after two polish passes — probed), which is
 * what made the real popup size once from a too-short first-pass measure and
 * paint the desk row + hint past the dialog's bottom edge. Reserved heights
 * keep the frame's implicit height width-independent from the very first
 * measure pass.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "pomodoro-machine.js" as Machine

Item {
    id: full

    required property var ctrl
    property string presetsJson
    property int defaultPreset
    property bool deskReminderEnabled
    property int deskReminderMinutes

    // Page state: the gear switches between the MAIN page (grid + running
    // actions + enable/disable) and the SETTINGS page (star picker, user
    // preset rows, desk controls). Pages swap by opacity + enabled, never by
    // visible — a hidden page would fall out of the layout and re-height the
    // card frame.
    property bool settingsOpen: false

    // Config writes travel out through signals; main.qml persists them into the
    // kcfg database. (Keeps this component free of Plasmoid imports and thus
    // creatable headless in the tests.)
    signal presetsWritten(string json)
    signal defaultPresetWritten(int presetIndex)
    signal deskReminderEnabledWritten(bool enabled)
    signal deskReminderMinutesWritten(int minutes)

    // i18n() is a global injected at plasmoid runtime by KLocalizedContext; it
    // has no importable type, so unqualified warnings on it are silenced here.
    function statusText() {
        // qmllint disable unqualified
        switch (ctrl.phase) {
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

    readonly property string phase: ctrl.phase
    readonly property bool working: phase === "work"

    // The machine refuses startPreset for BOTH running phases; `timing` covers
    // them so the grid UI matches the guard (no dead-looking clickable cells).
    readonly property bool timing: phase === "work" || phase === "break"

    // The fixed six-slot storage (SPEC-002): 0-2 Built-ins, 3-5 user presets or
    // null. Normalization re-seeds lost Built-ins and drops junk on every read.
    readonly property var slots: Machine.normalizePresetSlots(presetsJson)
    readonly property int userSlotBase: 3

    // Grid label size: the tiles are 2.5 grid units tall (round 6), so the
    // label must scale with them or the tile reads empty. 14pt keeps "★ 50/10"
    // on one unelided line: its PC3 Button implicitWidth is 85px against the
    // ~114px cell at the 18px grid unit — measured, not guessed (at the old
    // 17gu card's 90px cell, 15pt+ elided the starred Built-in). PC3's Button
    // label elides right and never wraps, so the text stays one line even for
    // long custom names.
    readonly property int presetFontSize: 14

    // Grid geometry — ONE source for every cell's size. Cell width is an equal
    // third of the grid's content width, derived from the card width only (an
    // upstream property, so no layout cycle). Round 3 let each wrapper derive
    // its size from its button's content, and GridLayout then distributed
    // space proportionally to content: long-label columns claimed extra width
    // (cells rendered 99/92/74 px wide at popup size).
    //
    // Cell height is ONE FIXED value (round 6): the 14pt tile button measures
    // 38px tall (org.kde.desktop AND Basic, 18px grid unit), so 2.5 grid units
    // = 45px leaves comfortable padding around the centered label. The grid
    // does NOT flex: the round-5 fillHeight absorber turned every spare frame
    // pixel into taller tiles until they covered the action buttons in the
    // real shell. Grid height is pure content now; the main page simply ends
    // above whatever space the settings-page-sized frame leaves free.
    readonly property real cellGap: Kirigami.Units.smallSpacing
    readonly property real cellWidth: Math.max(0, (pageHost.width - 2 * full.cellGap) / 3)
    readonly property real cellHeight: Kirigami.Units.gridUnit * 2.5

    // --- Round-6 clip fix: reserved wrap-hint heights ------------------------
    // Both settings-page hint labels wrap (WordWrap) over the full card width.
    // A wrapped QQC2 Label's implicitHeight is width-dependent and
    // late-settling — probed under org.kde.desktop it still reports the
    // ONE-line height (28px) after two polish passes while its two lines
    // really need 38px — so plasmashell sizes the popup once from a too-short
    // first-pass measure and the settled text paints past the dialog's bottom
    // edge (the round-5 bottom clip; the round-5 harness missed it because it
    // measured only AFTER settling). The hints therefore RESERVE a fixed
    // height instead of exposing an implicit one:
    //   hintHeight = a 2-line wrap with headroom = 2.25 grid units (45px at
    //   the 18px reference unit, where one wrapped small-font line measures
    //   ≈14px — 28px for 2 lines — leaving 12px+ of headroom over the box).
    //   Measured wraps at the 21gu content width: largeBreakHint 2 lines,
    //   deskHint 1 line (it wrapped 2 at the narrower round-5 card — both
    //   reserve the same 2-line height, so neither can ever clip and the
    //   settings geometry is uniform).
    // Expressed in grid units because gridUnit is font-derived: reserve and
    // wrapped text scale TOGETHER (probed: the hint strings still wrap to ≤ 2
    // lines when font AND width co-scale ×1.25 and ×1.5), so the proportion
    // is environment-stable. Pure arithmetic — no text-layout polish
    // involved — so the value is correct from the very first synchronous
    // implicit-size read, which is what makes the frame's implicit height
    // width- AND polish-independent. The render sweep additionally asserts
    // paintedHeight ≤ height for every hint in every state/style.
    readonly property real hintHeight: Kirigami.Units.gridUnit * 2.25
    function reservedHintHeight(label) {
        return full.hintHeight + label.topPadding + label.bottomPadding;
    }

    // Grid text: occupied slots show their label with the star on the Default
    // Preset; empty user slots are inert dashes (creation lives in settings).
    function slotText(i) {
        let s = full.slots[i];
        if (!s)
            // qmllint disable unqualified
            return i18n("—");
            // qmllint enable unqualified
        return (i === full.defaultPreset ? "★ " : "") + s.label;
    }

    // Tooltip guidance for an EMPTY user slot — the only grid cell that still
    // carries a tooltip. Occupied cells dropped theirs (round-4 flash fix):
    // their label and star already sit on the face, and one popup window per
    // grid cell was exactly the show/hide churn that stole the hover
    // highlight under real plasmashell (windowed popups).
    function cellToolTip(i) {
        // qmllint disable unqualified
        return i18n("Manage presets in settings");
        // qmllint enable unqualified
    }

    // Grid cells: occupied slots start immediately (unchanged muscle memory).
    // Empty slots have nothing to do here — the disabled dash cell can't reach
    // this. While the machine is timing this mirrors the disabled cells (the
    // machine itself refuses startPreset while timing; UI guard kept in step).
    function slotClicked(i) {
        if (!full.slots[i] || full.timing)
            return;
        full.ctrl.closePopup();
        full.ctrl.startPreset(full.slots[i]);
    }

    // Slot mutations operate on a copy of the six slots and emit the new JSON;
    // the persisted config echoes back through presetsJson. Guards keep the
    // locked-storage policy: Built-in slots and empty user slots are never
    // written by edit/delete; add only lands on a free user slot (now invoked
    // from that slot's settings-page row, not from the grid).
    function addUserPresetAt(i) {
        if (i < full.userSlotBase || i > 5 || full.slots[i])
            return;
        let arr = full.slots.slice();
        // The default is 30/5, NOT the classic 25/5: under minutes-only identity
        // (the label derives from the minutes) a 25/5 entry would exactly equal
        // the Built-in and locked storage would erase it on the next read.
        arr[i] = { label: Machine.derivedLabel(30, 5), workMin: 30, breakMin: 5 };
        full.presetsWritten(JSON.stringify(arr));
    }

    function updateUserPreset(i, workMin, breakMin, largeBreakMin) {
        if (i < full.userSlotBase || i > 5 || !full.slots[i])
            return;
        let old = full.slots[i];
        let entry = {
            workMin: Machine.saneMinutes(workMin, old.workMin),
            breakMin: Machine.saneMinutes(breakMin, old.breakMin)
        };
        // The label IS the minutes: every commit re-derives it, so a preset's
        // identity is its minutes alone (no name field exists anywhere).
        entry.label = Machine.derivedLabel(entry.workMin, entry.breakMin);
        // The Large spinbox is authoritative on EVERY commit: >0 stores the
        // explicit override, 0/junk REMOVES any previously stored value — the
        // machine's own storage convention; nothing is carried forward.
        let large = Machine.saneMinutes(largeBreakMin, 0);
        if (large > 0)
            entry.largeBreakMin = large;
        let arr = full.slots.slice();
        arr[i] = entry;
        // Exact-Built-in duplicates are refused: with derived labels the
        // refusal is effectively on minutes alone (an entry with 25/5 minutes
        // derives the label "25/5" and IS the Built-in). normalizePresetSlots
        // treats an exact match as locked storage and would filter the entry
        // out on the next read, silently erasing the user's edit. (Old user
        // slots never match a Built-in — normalize keeps them out — so this
        // refusal can only trigger when the NEW minutes collide.)
        if (full.matchesBuiltin(entry))
            return;
        full.presetsWritten(JSON.stringify(arr));
    }

    // True when the entry exactly equals a Built-in (label + minutes), i.e. the
    // machine would treat it as locked storage. Exposed so the editor can warn
    // before committing an edit that would be thrown away.
    function matchesBuiltin(p) {
        return Machine.builtinIndex(p) >= 0;
    }

    function deleteUserPreset(i) {
        if (i < full.userSlotBase || i > 5 || !full.slots[i])
            return;
        let wasDefault = (i === full.defaultPreset);
        let arr = full.slots.slice();
        arr[i] = null;
        full.presetsWritten(JSON.stringify(arr));
        // A deleted slot that carried the star must not leave it dangling on
        // the empty "—" dash: reset the Default Preset to the Built-in slot 0
        // (50/10). The machine already falls back to that preset when the
        // star points at an empty slot, so this only aligns the star UI with
        // the behavior Enable always had.
        if (wasDefault)
            full.defaultPresetWritten(0);
    }

    function setDefaultPreset(i) {
        if (i < 0 || i > 5 || !full.slots[i])
            return;
        full.defaultPresetWritten(i);
    }

    function setDeskReminderEnabled(enabled) {
        full.deskReminderEnabledWritten(enabled === true);
    }

    function setDeskReminderMinutes(mins) {
        full.deskReminderMinutesWritten(Machine.saneMinutes(mins, full.deskReminderMinutes));
    }

    // 21 grid units — the MINIMAL probed width that fits the one-line preset
    // editor row plus the desk controls row without eliding or squeezing
    // (measured, org.kde.desktop at the 18px grid unit: Work/Break/Large
    // small-font labels 30+35+34px = 99, three 3.5gu spinboxes 3×63px = 189,
    // delete ToolButton 32px, SEVEN 4px gaps between the row's eight children
    // = 28px → ~348px row vs 351px of content width; at 20gu the content is
    // 333px and the row ALREADY overflows. The desk row measures ~223px —
    // never the constraint. Basic style: ~345px.) The row-fit contract is
    // pinned behaviorally by tests/tst_full.qml (presetEditRowN implicitWidth
    // ≤ width), not by this arithmetic.
    implicitWidth: Kirigami.Units.gridUnit * 21
    // ONE frame for both pages: the column's height is dominated by whichever
    // page is naturally taller (the settings page — the main page is pure
    // content since round 6: fixed-height cells, no flex absorber), and both
    // pages always stay in the layout, so gear toggles, timing changes and
    // preset edits never re-height the card or move the header. Both operands
    // are REAL implicitHeights of laid-out pages — nothing here assumes fixed
    // pixel metrics, so real plasmashell fonts/units can only shift the
    // result, not desynchronize it from what is actually on the card. The
    // reserved hint heights (reservedHintHeight) keep the measured value
    // width-independent from the first pass on.
    implicitHeight: column.implicitHeight + Kirigami.Units.gridUnit * 1.5

    // Exposed for the headless tests (structure + labels are asserted there).
    readonly property alias presetGrid: grid
    readonly property alias presetCells: cellRepeater
    readonly property alias userEditorsRepeater: userEditors

    ColumnLayout {
        id: column
        anchors {
            fill: parent
            margins: Kirigami.Units.gridUnit * 0.75
        }
        spacing: Kirigami.Units.smallSpacing

        // --------------------------------------------- header: status + gear
        // One shared header row for both pages: status on the left, settings
        // gear pinned top right (subtly checked while the settings page shows).
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 4
                Layout.fillWidth: true
                text: full.statusText()
            }

            QQC2.ToolButton {
                id: settingsGear

                objectName: "settingsGear"
                icon.name: "settings"
                // Bound, not checkable: a checkable button assigns `checked`
                // internally on click, which would stomp this binding and let
                // the visual state drift from the open page.
                checked: full.settingsOpen
                onClicked: full.settingsOpen = !full.settingsOpen

                // Attached form, positioned by Qt's tooltip positioner OUTSIDE
                // the hovered control, with a delay so crossing the header does
                // not spawn/hide a popup at every pass.
                // qmllint disable unqualified
                QQC2.ToolTip.visible: settingsGear.hovered
                QQC2.ToolTip.text: i18n("Settings")
                QQC2.ToolTip.delay: Kirigami.Units.longDuration
                // qmllint enable unqualified
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ------------------------------------------------------------- pages
        // Both pages live here for their whole life. The inactive one is faded
        // out (opacity 0) and input-disabled — never visible:false, which would
        // exclude it from the layout and let the frame re-height. The frame is
        // exactly the taller page's implicitHeight. Round 6: the MAIN page is
        // pure content — fixed-height grid cells and the pinned action strip,
        // nothing flexes — so whatever the settings-page-sized frame leaves
        // free below the strip stays empty; there is no absorber to balloon
        // the tiles and no control can land outside the frame.
        Item {
            id: pageHost

            objectName: "pageHost"
            Layout.fillWidth: true
            implicitHeight: Math.max(mainPage.implicitHeight, settingsPage.implicitHeight)

            // ------------------------------------------------------------ MAIN page

            ColumnLayout {
                id: mainPage

                objectName: "mainPage"
                anchors.fill: parent
                opacity: full.settingsOpen ? 0 : 1
                enabled: !full.settingsOpen
                spacing: Kirigami.Units.smallSpacing

                // ------------------------------------------------ preset grid

                GridLayout {
                    id: grid
                    objectName: "presetGrid"
                    Layout.fillWidth: true
                    // Round 6: NO flex. The old fillHeight absorber turned
                    // every spare frame pixel into equally taller tiles until
                    // the giant squares covered the action buttons in the real
                    // shell. Cells keep ONE fixed height (full.cellHeight);
                    // the main page is pure content and spare frame height
                    // simply stays empty below the strip.
                    Layout.fillHeight: false
                    columns: 3
                    columnSpacing: full.cellGap
                    rowSpacing: full.cellGap

                    Repeater {
                        id: cellRepeater

                        // Always six cells, in every machine phase: while timing
                        // the cells disable, they never vanish.
                        model: 6

                        // Wrapper item: disabled controls receive no hover, so
                        // the dash's guidance tooltip lives on the (still
                        // enabled) wrapper. The button fills the wrapper, so
                        // the whole cell is one flat click/hover target —
                        // nothing between the mouse and the Button state.
                        Item {
                            id: cellWrap

                            required property int index

                            objectName: "presetCellWrap" + index
                            Layout.fillWidth: true
                            // Equal explicit size from ONE source: width thirds
                            // of the grid (full.cellWidth), height the FIXED
                            // full.cellHeight — identical for all six cells,
                            // independent of label content, never flexed (the
                            // round-5 fillHeight ballooned the tiles over the
                            // action buttons in the real shell).
                            Layout.preferredWidth: full.cellWidth
                            Layout.preferredHeight: full.cellHeight
                            implicitWidth: full.cellWidth
                            implicitHeight: full.cellHeight

                            PlasmaComponents.Button {
                                id: cellBtn

                                objectName: "presetCell" + cellWrap.index
                                anchors.fill: parent
                                font.pointSize: full.presetFontSize
                                enabled: full.slots[cellWrap.index] !== null && !full.timing
                                text: full.slotText(cellWrap.index)
                                onClicked: full.slotClicked(cellWrap.index)
                            }

                            HoverHandler {
                                id: cellHover
                            }

                            // Only the EMPTY-slot dash keeps a tooltip (guidance:
                            // creation lives in settings), hosted by the wrapper
                            // because the disabled button never hovers. Placed
                            // explicitly ABOVE the cell so its geometry can
                            // never intersect the pointer and flap the hover
                            // state, with a delay against crossing churn.
                            QQC2.ToolTip {
                                visible: cellHover.hovered && full.slots[cellWrap.index] === null
                                x: (cellWrap.width - width) / 2
                                y: -height - Kirigami.Units.smallSpacing
                                delay: Kirigami.Units.longDuration
                                text: full.cellToolTip(cellWrap.index)
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // ------------------------------------------------ running actions
                // RESERVED strip: all three action buttons are ALWAYS laid out;
                // phase-dependent visibility is expressed as opacity + enabled
                // (the same swap pattern as the pages). The main page's
                // implicitHeight therefore cannot change when a block starts or
                // ends, the card frame (derived from these implicitHeights)
                // stays constant under any real-shell metrics, and the buttons
                // are pinned INSIDE the visible frame — they can never be
                // clipped away below it.
                //
                // Round 5 (operator: "shrink all of them: one compact row,
                // Disable for now as small secondary"): "Start break now" and
                // "Delay 5 min" sit at natural width in one row; Enable/Disable
                // is the SMALL secondary beneath it (smallFont, no fillWidth).
                // Three natural-width buttons in one row would overflow even
                // the round-6 21-grid-unit card (measured 122+99+126 px of
                // implicit width + 2×4px spacing = 355px vs 351px of content
                // width), hence the second line. The strip keeps ONE constant
                // height in every phase.
                ColumnLayout {
                    id: actionStrip
                    objectName: "actionStrip"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    // Round 7 (operator): Start break now and the Enable/
                    // Disable secondary are the SAME SIZE — one shared width
                    // (the max of both buttons' naturals, so neither label
                    // elides); Delay 5 min stays natural in its own row.
                    readonly property real sharedButtonWidth: Math.max(
                        startBreakNowButton.implicitWidth,
                        enableButton.implicitWidth)

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true

                        PlasmaComponents.Button {
                            id: startBreakNowButton

                            objectName: "startBreakNowButton"
                            Layout.preferredWidth: actionStrip.sharedButtonWidth
                            visible: true
                            opacity: full.working ? 1 : 0
                            enabled: full.working
                            icon.name: "go-next-skip"
                            // qmllint disable unqualified
                            text: i18n("Start break now")
                            // qmllint enable unqualified
                            onClicked: {
                                full.ctrl.closePopup();
                                full.ctrl.startBreakNow();
                            }
                        }

                        PlasmaComponents.Button {
                            id: delayBreakButton

                            objectName: "delayBreakButton"
                            visible: true
                            opacity: full.working && full.ctrl.pendingBreak ? 1 : 0
                            enabled: full.working && full.ctrl.pendingBreak
                            icon.name: "clock"
                            // Shortened per operator: the full "Delay break 5
                            // minutes" text would overflow the natural-width row.
                            // qmllint disable unqualified
                            text: i18n("Delay 5 min")
                            // qmllint enable unqualified
                            onClicked: full.ctrl.delayBreak()
                        }
                    }

                    // Small secondary: matches Start break now's size AND font
                    // (shared width above, default font) — subordination comes
                    // only from position (row below). Round 7b operator order.
                    PlasmaComponents.Button {
                        id: enableButton

                        objectName: "enableButton"
                        Layout.preferredWidth: actionStrip.sharedButtonWidth
                        icon.name: full.phase === "disabled" ? "checkmark" : "dialog-cancel"
                        // qmllint disable unqualified
                        text: full.phase === "disabled" ? i18n("Enable") : i18n("Disable for now")
                        // qmllint enable unqualified
                        onClicked: full.phase === "disabled" ? full.ctrl.enable() : full.ctrl.disable()
                    }
                }
            }

            // -------------------------------------------------------- SETTINGS page

            // Sits on top of the main page (declared later → higher z) and is
            // faded out while closed. Its natural height defines the frame, so
            // everything on it holds a constant geometry: one-line uniform
            // user-slot rows and ONE always-reserved warning line never
            // re-height it.
            ColumnLayout {
                id: settingsPage

                objectName: "settingsPage"
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                opacity: full.settingsOpen ? 1 : 0
                enabled: full.settingsOpen
                spacing: Kirigami.Units.smallSpacing

                // Collision registry: row -> its live edited fields currently
                // exactly match a Built-in. Rows report through their
                // onWouldCollideChanged handlers (see delegate).
                property var _collisions: ({})

                function reportCollision(row, on) {
                    if ((_collisions[row] === true) === on)
                        return;
                    let next = Object.assign({}, _collisions);
                    if (on)
                        next[row] = true;
                    else
                        delete next[row];
                    _collisions = next;
                }

                // True while any user row's live minutes exactly match a
                // Built-in; drives the single reserved warning line below.
                readonly property bool hasCollision: {
                    for (let i = 0; i < 3; i++)
                        if (_collisions[i] === true)
                            return true;
                    return false;
                }

                // Default Preset: any of the six slots may carry the star.
                GridLayout {
                    objectName: "starPicker"
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Kirigami.Units.smallSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: 6

                        PlasmaComponents.Button {
                            id: defaultCell

                            required property int index

                            Layout.fillWidth: true
                            // Bound, not checkable — a checkable button would assign
                            // `checked` internally and break this binding, leaving a
                            // phantom star when the Default Preset moves again.
                            checked: defaultCell.index === full.defaultPreset
                            enabled: full.slots[defaultCell.index] !== null
                            text: full.slots[defaultCell.index]
                                  ? full.slots[defaultCell.index].label
                                  // qmllint disable unqualified
                                  : i18n("—")
                            // qmllint enable unqualified
                            onClicked: full.setDefaultPreset(defaultCell.index)

                            // Attached form: outside-the-control placement +
                            // delay, no popup churn while crossing the picker.
                            // qmllint disable unqualified
                            QQC2.ToolTip.visible: defaultCell.hovered
                            QQC2.ToolTip.text: i18n("Set as default")
                            QQC2.ToolTip.delay: Kirigami.Units.longDuration
                            // qmllint enable unqualified
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // User preset rows: ONE compact uniform LINE per user slot 3-5,
                // always present. OCCUPIED → the one-line editor [Work][spin]
                // [Break][spin][Large][spin][delete] (there is NO name field —
                // the label derives from the minutes); EMPTY → a single
                // full-width "Add preset" button that creates the preset in
                // THIS slot (creation lives in settings; editing then happens
                // in place). The row swaps editor/button by OPACITY + ENABLED
                // on the always-laid-out editor column — with ONE exception:
                // the Add button below flips `visible`, which is layout-safe
                // because it is ANCHORED to the row Item, not a layout child,
                // so its visibility cannot re-height anything — so every row
                // keeps ONE constant height and adding or deleting a preset
                // can never re-height the page or the card. Round 6 (operator):
                // the editor is ONE line — the
                // old two-line editor reserved the Large row's height in EVERY
                // row even when empty, tripling the Add-preset rows' bulk and
                // inflating the very page that sizes the card frame. The
                // dedicated tight container groups the three rows together;
                // the per-row warning labels remain consolidated into the ONE
                // always-reserved line below the group.
                //
                // The editor commits immediately on every change (Built-ins
                // intentionally have no editor here). The model is the STABLE
                // slot indices 3-5, not the occupied-slot list: every live edit
                // echoes back through the config and recomputes `slots`; a
                // derived array model there would rebuild all rows on each
                // echo, dropping focus mid-interaction.
                ColumnLayout {
                    objectName: "userRowsGroup"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        id: userEditors

                        objectName: "userEditors"
                        model: 3

                        Item {
                            id: userRow

                            required property int modelData
                            readonly property int slotIdx: userRow.userSlotBase + userRow.modelData
                            readonly property int userSlotBase: 3
                            readonly property var slot: full.slots[userRow.slotIdx]
                            readonly property bool occupied: userRow.slot !== null

                            // Live warning condition: the edited MINUTES
                            // currently exactly match a Built-in (that edit
                            // would be refused on commit). With derived naming
                            // the label is implied by the minutes, so the
                            // composed check is minutes-only.
                            property bool wouldCollide: occupied && !full.matchesBuiltin(slot)
                                && full.matchesBuiltin({
                                    label: Machine.derivedLabel(workSpin.value, breakSpin.value),
                                    workMin: workSpin.value,
                                    breakMin: breakSpin.value
                                });

                            // Report into the settings page's collision registry
                            // (explicit handler, not a cross-delegate binding read:
                            // the aggregation must be reliably reactive).
                            onWouldCollideChanged: settingsPage.reportCollision(userRow.modelData, userRow.wouldCollide)
                            Component.onCompleted: settingsPage.reportCollision(userRow.modelData, userRow.wouldCollide)

                            function commit() {
                                if (userRow.occupied)
                                    full.updateUserPreset(userRow.slotIdx, workSpin.value, breakSpin.value, largeSpin.value);
                            }

                            Layout.fillWidth: true
                            // CONSTANT row height: the editor column always stays in
                            // the layout (opacity-toggled below), so this never
                            // depends on the slot's occupancy or warning state.
                            implicitHeight: editorColumn.implicitHeight

                            ColumnLayout {
                                id: editorColumn

                                objectName: "userEditorColumn" + userRow.modelData
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                opacity: userRow.occupied ? 1 : 0
                                enabled: userRow.occupied
                                spacing: Kirigami.Units.smallSpacing

                                // ONE line, round 6: labels are smallFont;
                                // the spins shrink 4.5 → 3.5 grid units (63px:
                                // the widest legal value "600" needs ~21px of
                                // text against 63 − 2×16px indicators, probed
                                // TEXTCLIP=false). Row height is the one
                                // control line, occupied or not.
                                RowLayout {
                                    objectName: "presetEditRow" + userRow.modelData
                                    spacing: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true

                                    QQC2.Label {
                                        font: Kirigami.Theme.smallFont
                                        // qmllint disable unqualified
                                        text: i18n("Work")
                                        // qmllint enable unqualified
                                    }
                                    QQC2.SpinBox {
                                        id: workSpin

                                        objectName: "workSpin" + userRow.modelData
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                                        from: 1
                                        to: 600
                                        editable: true
                                        value: userRow.slot ? userRow.slot.workMin : 25
                                        onValueModified: userRow.commit()
                                    }
                                    QQC2.Label {
                                        font: Kirigami.Theme.smallFont
                                        // qmllint disable unqualified
                                        text: i18n("Break")
                                        // qmllint enable unqualified
                                    }
                                    QQC2.SpinBox {
                                        id: breakSpin

                                        objectName: "breakSpin" + userRow.modelData
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                                        from: 1
                                        to: 600
                                        editable: true
                                        value: userRow.slot ? userRow.slot.breakMin : 5
                                        onValueModified: userRow.commit()
                                    }
                                    QQC2.Label {
                                        font: Kirigami.Theme.smallFont
                                        // qmllint disable unqualified
                                        text: i18n("Large")
                                        // qmllint enable unqualified
                                    }
                                    QQC2.SpinBox {
                                        id: largeSpin

                                        objectName: "largeSpin" + userRow.modelData
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                                        from: 0
                                        to: 600
                                        editable: true
                                        // 0 = the automatic rule; a stored entry
                                        // without largeBreakMin shows 0.
                                        value: userRow.slot && userRow.slot.largeBreakMin > 0
                                               ? userRow.slot.largeBreakMin : 0
                                        onValueModified: userRow.commit()
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    }
                                    QQC2.ToolButton {
                                        id: deleteButton

                                        objectName: "deleteButton" + userRow.modelData
                                        icon.name: "edit-delete-remove"
                                        onClicked: full.deleteUserPreset(userRow.slotIdx)
                                        // qmllint disable unqualified
                                        QQC2.ToolTip.visible: deleteButton.hovered
                                        QQC2.ToolTip.text: i18n("Delete preset")
                                        QQC2.ToolTip.delay: Kirigami.Units.longDuration
                                        // qmllint enable unqualified
                                    }
                                }
                            }

                            PlasmaComponents.Button {
                                id: addButton

                                objectName: "addPresetButton" + userRow.modelData
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: !userRow.occupied
                                icon.name: "list-add"
                                // qmllint disable unqualified
                                text: i18n("Add preset")
                                // qmllint enable unqualified
                                onClicked: full.addUserPresetAt(userRow.slotIdx)
                            }
                        }
                    }
                }

                // Automatic-rule hint for the Large spinboxes above: one small,
                // low-opacity, ALWAYS-laid-out line (never visible:false).
                // Round 6 clip fix: it WRAPS, and a wrapped label's implicit
                // height is width-dependent and late-settling — the mechanism
                // behind the real shell's bottom clip — so the height is
                // RESERVED for the measured 2-line wrap instead (see the
                // reservedHintHeight comment at the card root).
                QQC2.Label {
                    id: largeBreakHint

                    objectName: "largeBreakHint"
                    Layout.fillWidth: true
                    Layout.minimumHeight: full.reservedHintHeight(largeBreakHint)
                    Layout.maximumHeight: full.reservedHintHeight(largeBreakHint)
                    Layout.preferredHeight: full.reservedHintHeight(largeBreakHint)
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    // qmllint disable unqualified
                    text: i18n("Large break 0 = automatic rule: 20 / 30 / 40 min by break length.")
                    // qmllint enable unqualified
                }

                // ONE collision warning for the whole settings page. The line is
                // ALWAYS laid out at exactly one line height (no wrap — it
                // elides), so its height is constant whether or not a collision
                // is active: editing a preset toward a Built-in duplicate
                // cannot re-height the page or the card. This is the
                // consolidated keeper of the round-3 per-row reserved warning
                // lines.
                QQC2.Label {
                    id: builtinCollisionWarning

                    objectName: "builtinCollisionWarning"
                    Layout.fillWidth: true
                    opacity: settingsPage.hasCollision ? 1 : 0
                    elide: Text.ElideRight
                    color: Kirigami.Theme.neutralTextColor
                    font: Kirigami.Theme.smallFont
                    // Static text: with derived naming a preset's identity is
                    // its minutes, so the message no longer names an entry.
                    // qmllint disable unqualified
                    text: i18n("Can't be identical to a Built-in — change the minutes.")
                    // qmllint enable unqualified
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // Desk Reminder: on/off + interval, effective from the next Work Block.
                RowLayout {
                    objectName: "deskControls"
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        id: deskReminderLabel

                        objectName: "deskReminderLabel"
                        Layout.fillWidth: true
                        // The fillWidth element between fixed-width controls:
                        // elide, never clip or stretch the row.
                        elide: Text.ElideRight
                        // qmllint disable unqualified
                        text: i18n("Desk reminder")
                        // qmllint enable unqualified
                    }
                    QQC2.Switch {
                        checked: full.deskReminderEnabled
                        onToggled: full.setDeskReminderEnabled(checked)
                    }
                    QQC2.SpinBox {
                        id: deskMinutesSpin

                        objectName: "deskMinutesSpin"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                        from: 1
                        to: 240
                        editable: true
                        value: full.deskReminderMinutes
                        onValueModified: full.setDeskReminderMinutes(deskMinutesSpin.value)
                    }
                    QQC2.Label {
                        // qmllint disable unqualified
                        text: i18n("min")
                        // qmllint enable unqualified
                    }
                }
                QQC2.Label {
                    id: deskHint

                    objectName: "deskHint"
                    Layout.fillWidth: true
                    // Round 6 clip fix: reserved height for the measured
                    // 2-line wrap (see reservedHintHeight at the card root) —
                    // the desk hint is the settings page's bottom-most
                    // element, so its late-settling implicit height was
                    // exactly what painted past the real popup's edge.
                    Layout.minimumHeight: full.reservedHintHeight(deskHint)
                    Layout.maximumHeight: full.reservedHintHeight(deskHint)
                    Layout.preferredHeight: full.reservedHintHeight(deskHint)
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    // qmllint disable unqualified
                    text: i18n("Reminds you to alternate your desk height while working.")
                    // qmllint enable unqualified
                }
            }
        }
    }
}
