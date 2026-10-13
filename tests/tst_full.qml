// Headless test of the FullRepresentation preset card (SPEC-002 + popup-card
// UX round): 2×3 grid with large labels, star on the configured Default
// Preset, in-card user preset management writing six-slot JSON, Built-ins
// immutable. Operator-feedback contract: an EMPTY grid slot is a disabled
// "—" dash (nothing to do here — creation lives in the settings page, where
// every empty user row offers an "Add preset" button); while the machine is
// timing the grid stays visible with all cells disabled (never hidden); and
// the card holds ONE constant frame across gear toggles, timing changes and
// preset edits, with uniform component widths on the settings page.
// Round-4 additions (operator ran the real widget): all six grid cells must
// be strictly identical in size (no content-driven column stretch); labels
// scale up with the bigger tiles without eliding the starred Built-in; the
// main page's action buttons (Start break now / Delay / Enable) are pinned
// INSIDE the visible frame in every machine phase — they can never be
// clipped below it; the settings page (Desk Reminder included) fits the
// frame; the add-preset rows sit compactly with ONE always-reserved
// collision warning line; a held press keeps the cell pressed and hover is
// steady (no per-cell tooltip popups to churn it). Follows tst_compact.qml's
// pattern: component created with a mock controller, no plasmashell needed.
// The card is hosted in a plain shown Window (offscreen platform) and its
// HEIGHT is bound to its implicitHeight exactly as Plasma's popup dialog
// does — an unset height left every vertical-geometry assertion in earlier
// rounds vacuous (height 0), which is how the suite passed a render that
// clipped the action buttons. Config writes are captured via the component's
// *Written signals (main.qml persists them in the real widget).
import QtTest
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

TestCase {
    id: suite

    // captured config writes
    property string writtenJson: ""
    property int writtenDefault: -1
    property var writtenDeskEnabled: null
    property var writtenDeskMinutes: null

    // Plain Window host: without a window, QQuickLayout polish never runs in
    // the test process and page-switch geometry would stay frozen.
    property var hostWindow: null

    property var mockCtrl: QtObject {
        property string phase: "idle"
        property string remainingText: ""
        property bool pendingBreak: false
        property bool popupClosed: false
        property var startedPreset: null
        function closePopup() { suite.mockCtrl.popupClosed = true; }
        function startPreset(p) { suite.mockCtrl.startedPreset = p; }
        function startBreakNow() {}
        function delayBreak() {}
        function disable() {}
        function enable() {}
    }

    // Three Built-ins + one user preset; slots 4-5 empty.
    readonly property string seedJson: JSON.stringify([
        { label: "50/10", workMin: 50, breakMin: 10 },
        { label: "25/5", workMin: 25, breakMin: 5 },
        { label: "45/15", workMin: 45, breakMin: 15 },
        { label: "Mine 60", workMin: 60, breakMin: 9 },
        null,
        null
    ])

    // All three user slots empty: the fresh-install shape the operator saw.
    readonly property string freshJson: JSON.stringify([
        { label: "50/10", workMin: 50, breakMin: 10 },
        { label: "25/5", workMin: 25, breakMin: 5 },
        { label: "45/15", workMin: 45, breakMin: 15 },
        null,
        null,
        null
    ])

    function makeFull(json, defaultIdx) {
        suite.writtenJson = "";
        suite.writtenDefault = -1;
        suite.writtenDeskEnabled = null;
        suite.writtenDeskMinutes = null;
        mockCtrl.popupClosed = false;
        mockCtrl.startedPreset = null;
        mockCtrl.phase = "idle";
        mockCtrl.pendingBreak = false;
        // One shared host Window for the whole suite (theme/svg loading per
        // window is the expensive part; cards themselves are destroyed per test).
        if (!suite.hostWindow)
            suite.hostWindow = Qt.createQmlObject(
                'import QtQuick; import QtQuick.Window; Window { width: 380; height: 900; visible: true }',
                suite, "tstFullHost");
        let comp = Qt.createComponent("../plasmoid/contents/ui/FullRepresentation.qml");
        let obj = comp.createObject(suite.hostWindow, {
            ctrl: mockCtrl,
            presetsJson: json,
            defaultPreset: defaultIdx,
            deskReminderEnabled: true,
            deskReminderMinutes: 30
        });
        verify(obj !== null, "create failed: " + (comp ? comp.errorString() : "?"));
        // Plasma's popup dialog sizes the card from its implicit size in BOTH
        // axes; bind width and height exactly the same way. (Without this the
        // card sat at height 0 and geometry assertions below compared zeros —
        // the round-3 blind spot. Round 6: width too — the popup hands the
        // card its 21-grid-unit implicit width; the old fixed 300 was the
        // round-5 17gu card and would now SQUEEZE the one-line editor row.)
        obj.width = Qt.binding(function () { return obj.implicitWidth; });
        obj.height = Qt.binding(function () { return obj.implicitHeight; });
        // Lint caveat: this lint resolves createObject() to plain QObject (it does
        // not follow the component's nested relative JS import), so the card's
        // custom signals are invisible to it; they exist at runtime.
        // qmllint disable missing-property
        obj.presetsWritten.connect(function (j) { suite.writtenJson = j; });
        obj.defaultPresetWritten.connect(function (i) { suite.writtenDefault = i; });
        obj.deskReminderEnabledWritten.connect(function (e) { suite.writtenDeskEnabled = e; });
        obj.deskReminderMinutesWritten.connect(function (m) { suite.writtenDeskMinutes = m; });
        // qmllint enable missing-property
        // Two polish rounds (header row + deep grid) — 200ms settles both.
        wait(200);                    // settle layout polish before any geometry read
        return obj;
    }

    // Grid cell buttons live inside wrapper items (which host the dash tooltip,
    // so disabled dash cells still explain themselves).
    function cellBtn(card, i) {
        return findChild(card.presetCells.itemAt(i), "presetCell" + i);
    }
    function cellWrap(card, i) {
        return card.presetCells.itemAt(i);
    }

    // Popups hosted by an item (inline QQC2.ToolTip objects are QQuickPopups).
    function popupsOf(item) {
        let found = [];
        for (let i = 0; i < item.data.length; i++) {
            let d = item.data[i];
            if (d.hasOwnProperty && d.hasOwnProperty("popupType"))
                found.push(d);
        }
        return found;
    }

    function parseWritten() {
        return JSON.parse(suite.writtenJson || "null");
    }

    function cleanupTestCase() {
        if (suite.hostWindow)
            suite.hostWindow.destroy();
    }

    // --- grid ---

    function test_grid_rendersSixSlotsInThreeColumns() {
        let f = makeFull(seedJson, 0);
        compare(f.presetGrid.columns, 3);
        compare(f.presetCells.count, 6);          // 2 rows × 3 columns, always six cells
        compare(f.slotText(0), "★ 50/10");        // slot 0 is the configured default
        compare(f.slotText(1), "25/5");
        compare(f.slotText(2), "45/15");
        compare(f.slotText(3), "60/9");           // label derives from the minutes
        compare(f.slotText(4), "—");              // empty user slot = inert dash
        compare(f.slotText(5), "—");
        compare(cellBtn(f, 4).text, "—");
        f.destroy();
    }

    function test_grid_presetFontScalesWithBiggerTiles() {
        let f = makeFull(seedJson, 0);
        compare(cellBtn(f, 0).font.pointSize, f.presetFontSize);
        // Round-3 had 11pt on ~6gu tiles — the label read empty. 14pt is the
        // largest size whose button still fits the pinned cell unelided.
        verify(f.presetFontSize >= 14, "labels must scale up with the tiles, got " + f.presetFontSize);
        f.destroy();
    }

    function test_grid_starredBuiltinLabelFitsOneUnelidedLine() {
        // "buttons are larger, but the text are not" is fixed only if the big
        // label actually fits the pinned cell: the button's content-required
        // implicitWidth must not exceed the allocated cell width (beyond
        // fraction rounding), otherwise PC3 elides the starred Built-in.
        let f = makeFull(seedJson, 0);
        let b = cellBtn(f, 0);
        verify(b.implicitWidth <= cellWrap(f, 0).width + 1.0,
               "'★ 50/10' must fit its tile without eliding (implicit "
               + b.implicitWidth + " > cell " + cellWrap(f, 0).width + ")");
        f.destroy();
    }

    // --- grid cell enablement (operator: empty slots are dashes, not buttons) ---

    function test_grid_emptySlotIsDisabledDash_notClickable() {
        let f = makeFull(seedJson, 0);
        let dash = cellBtn(f, 4);
        verify(dash !== null);
        verify(dash.enabled === false, "empty slot cell must be disabled");
        compare(f.cellToolTip(4), "Manage presets in settings");
        // Clicking the dash must do nothing at all: no start, no config write.
        f.slotClicked(4);
        f.slotClicked(5);
        compare(mockCtrl.startedPreset, null);
        compare(mockCtrl.popupClosed, false);
        compare(suite.writtenJson, "", "the grid must never add presets (creation lives in settings)");
        // Occupied neighbours stay enabled. (Their face already shows the
        // label and star; occupied cells dropped their tooltips in round 4 —
        // one popup window per grid cell was the churn source behind the
        // flashing hover highlight.)
        verify(cellBtn(f, 0).enabled === true);
        f.destroy();
    }

    function test_grid_occupiedCellsCarryNoTooltipPopups_dashDoes() {
        // The flash fix, pinned: an occupied (enabled) cell hosts NO popup that
        // can become visible — a hidden popup object spawns no window over the
        // pointer's cell, so nothing can flap the hover/pressed highlight.
        // (Synthetic QCursor hover delivery is flaky in this sandbox — it
        // worked in early probe runs and stopped at the process level while
        // press events kept delivering — so visibility-baseline is the
        // pinning assertion here, not hover-triggered opening.)
        let f = makeFull(seedJson, 0);            // slots 4-5 are dashes
        // Occupied cells: any hosted popup object must be PERMANENTLY closed —
        // a hidden popup spawns no window over the pointer's cell, so nothing
        // can flap the hover/pressed highlight. (Synthetic QCursor hover
        // delivery is flaky in this sandbox — it worked in early probe runs
        // and stopped at the process level while press events kept delivering
        // — so the visibility-baseline is the pinning assertion here, not
        // hover-triggered opening.)
        for (let occ of [0, 3])
            for (let p of popupsOf(cellWrap(f, occ)))
                verify(p.visible === false, "occupied cell " + occ + " popup must never open");
        compare(popupsOf(cellWrap(f, 4)).length, 1, "dash cell keeps its guidance tooltip");
        compare(popupsOf(cellWrap(f, 5)).length, 1, "dash cell keeps its guidance tooltip");
        // While timing every cell disables; occupied cells still host no open popup.
        mockCtrl.phase = "work";
        for (let occ2 of [0, 3])
            for (let q of popupsOf(cellWrap(f, occ2)))
                verify(q.visible === false, "timing cell " + occ2 + " popup must never open");
        f.destroy();
    }

    // --- grid cell geometry (operator: "these buttons don't have the same size") ---

    function test_grid_allSixCellsStrictlyIdenticalSize() {
        // One source of truth (full.cellWidth / full.cellHeight) pins every
        // cell; content must never inflate a cell. Fractional grid-unit
        // distribution may differ by one device pixel at most.
        let f = makeFull(seedJson, 0);            // labels: ★50/10, 25/5, 45/15, 60/9, —, —
        let ref = cellWrap(f, 0);
        for (let i = 1; i < 6; i++) {
            let w = cellWrap(f, i);
            verify(Math.abs(w.width - ref.width) <= 1.0,
                   "cell " + i + " width " + w.width + " != " + ref.width);
            verify(Math.abs(w.height - ref.height) <= 1.0,
                   "cell " + i + " height " + w.height + " != " + ref.height);
        }
        // Round 6: cells are ONE FIXED sane height (2.5 grid units — the 14pt
        // tile measures 38px tall), NOT flexed frame absorbers. The tile stays
        // comfortably padded and can never balloon over the action strip.
        verify(Math.abs(ref.height - f.cellHeight) <= 1.0,
               "cells must use the fixed cellHeight, got " + ref.height + " vs " + f.cellHeight);
        verify(ref.height < Kirigami.Units.gridUnit * 3,
               "cell height must stay sane (" + ref.height + "); the flex absorber is gone");
        verify(ref.width > 60, "tiles keep a usable width, got " + ref.width);
        // The fixed height must still FIT the 14pt tile label (comfortable
        // padding, never a clipped tile button).
        let btn = cellBtn(f, 0);
        verify(btn.implicitHeight <= ref.height + 0.5,
               "14pt tile button (" + btn.implicitHeight + "px) must fit the fixed cell "
               + ref.height + "px");
        f.destroy();
    }

    function test_grid_noFlex_pureContentMainPage() {
        // Round-6 contract pin: the grid does NOT absorb spare frame height.
        // fillHeight:false and grid height == its own implicit height; the
        // main page's implicit height is pure content (fixed cells + strip),
        // independent of how tall the settings-defined frame is.
        let f = makeFull(seedJson, 0);
        compare(f.presetGrid.Layout.fillHeight, false,
                "the grid must not flex (fillHeight false)");
        verify(Math.abs(f.presetGrid.height - f.presetGrid.implicitHeight) <= 1.0,
               "grid height " + f.presetGrid.height + " must equal its implicit "
               + f.presetGrid.implicitHeight + " (no absorber)");
        // And a timing phase — the tallest strip arrangement — must not
        // change the grid either.
        let g0 = f.presetGrid.implicitHeight;
        mockCtrl.phase = "work";
        mockCtrl.pendingBreak = true;
        wait(50);
        compare(f.presetGrid.implicitHeight, g0, "grid content is phase-independent");
        mockCtrl.pendingBreak = false;
        mockCtrl.phase = "idle";
        f.destroy();
    }

    function test_cardFrame_widthIsTwentyOneGridUnits() {
        // Round 6: the card widens 17 → 21 grid units — the MINIMAL probed
        // width fitting the one-line editor row (349px measured vs 351px of
        // content width; 20gu = 333px overflows) plus the desk row.
        let f = makeFull(seedJson, 0);
        compare(f.implicitWidth, Kirigami.Units.gridUnit * 21,
                "card implicit width must be 21 grid units");
        f.destroy();
    }

    function test_cardFrame_implicitHeightWidthIndependent_firstPassEqualsSettled() {
        // The round-5 clip mechanism, pinned shut: plasmashell sizes the popup
        // ONCE from a first-pass measure; if the frame's implicitHeight only
        // settles LATER (wrapped hints), the settled content paints past the
        // dialog edge. Creation-pass implicitHeight must therefore equal the
        // settled one, and the wrapped hints must fit their reserved boxes.
        let comp = Qt.createComponent("../plasmoid/contents/ui/FullRepresentation.qml");
        let f = comp.createObject(suite.hostWindow, {
            ctrl: mockCtrl,
            presetsJson: seedJson,
            defaultPreset: 0,
            deskReminderEnabled: true,
            deskReminderMinutes: 30
        });
        verify(f !== null, "create failed: " + (comp ? comp.errorString() : "?"));
        f.width = Qt.binding(function () { return f.implicitWidth; });
        f.height = Qt.binding(function () { return f.implicitHeight; });
        // FIRST measure pass: read synchronously right after creation — before
        // any settle wait. This is the value a popup dialog would size from.
        let firstPass = f.implicitHeight;
        verify(firstPass > 0, "first-pass implicitHeight must be laid out, got " + firstPass);
        // Settle exactly the way a popup does: two polish rounds at the final
        // width (wait turns the event loop, letting polish + layouts run).
        wait(150);
        wait(150);
        compare(f.implicitHeight, firstPass,
                "frame implicitHeight must be width-independent: first pass == settled");
        // The wrapped hints fit their reserved boxes (no clipped glyphs, no
        // late growth), and settings being open changes nothing.
        let dh = findChild(f, "deskHint");
        let lh = findChild(f, "largeBreakHint");
        verify(dh !== null && lh !== null);
        verify(dh.paintedHeight <= dh.height + 0.5,
               "deskHint text must fit its reserved height (painted " + dh.paintedHeight
               + " > box " + dh.height + ")");
        verify(lh.paintedHeight <= lh.height + 0.5,
               "largeBreakHint text must fit its reserved height (painted " + lh.paintedHeight
               + " > box " + lh.height + ")");
        f.settingsOpen = true;
        wait(150);
        wait(150);
        compare(f.implicitHeight, firstPass, "settled implicitHeight must not move after polish");
        verify(dh.paintedHeight <= dh.height + 0.5,
               "deskHint must still fit its reserved height once settled");
        verify(lh.paintedHeight <= lh.height + 0.5,
               "largeBreakHint must still fit its reserved height once settled");
        f.destroy();
    }

    // --- star ---

    function test_star_marksConfiguredDefault_notPosition() {
        let f = makeFull(seedJson, 3);            // a user slot is starred, not slot 0
        compare(f.slotText(3), "★ 60/9");
        compare(f.slotText(0), "50/10");
        compare(cellBtn(f, 3).text, "★ 60/9");
        f.destroy();
    }

    function test_setDefault_writesIndex_anyOfSixSlots() {
        let f = makeFull(seedJson, 0);
        f.setDefaultPreset(1);
        compare(suite.writtenDefault, 1);
        // simulate the config round-trip (main.qml echoes the stored index back)
        f.defaultPreset = 1;
        compare(f.slotText(1), "★ 25/5");
        compare(f.slotText(3), "60/9");           // old star moved away
        f.destroy();
    }

    // --- click routing ---

    function test_slotClick_occupiedSlotStartsPresetImmediately() {
        let f = makeFull(seedJson, 0);
        f.slotClicked(0);
        compare(mockCtrl.startedPreset.label, "50/10");
        compare(mockCtrl.popupClosed, true);
        compare(suite.writtenJson, "");           // a start is not a config write
        f.destroy();
    }

    // --- pressed/hover feedback (operator: "it will flash instead of stay highlighted") ---

    function test_grid_heldPressKeepsCellPressed_clickDelivered() {
        // A real press-and-hold on cell 0 through the wrapper: the Button's
        // pressed property must hold for the whole hold (steady pressed
        // highlight), and the release must deliver the click.
        let f = makeFull(seedJson, 0);
        let w = cellWrap(f, 0);
        let b = cellBtn(f, 0);
        let cx = w.width / 2, cy = w.height / 2;
        mouseMove(w, cx, cy);
        wait(60);
        mousePress(w, cx, cy);
        wait(40);
        verify(b.pressed === true, "held mouse press must press the cell");
        let flaps = 0, last = b.pressed;
        for (let k = 0; k < 20; k++) {
            wait(20);
            if (b.pressed !== last) { flaps++; last = b.pressed; }
        }
        compare(flaps, 0, "pressed state must be stable while the button is held");
        mouseRelease(w, cx, cy);
        wait(40);
        compare(mockCtrl.startedPreset.label, "50/10",
                "release must deliver the click: slotClicked started the preset");
        verify(mockCtrl.popupClosed === true, "release must fire onClicked (closePopup ran)");
        mouseMove(f, 1, 1);                       // park pointer away
        wait(30);
        f.destroy();
    }

    function test_grid_buttonIsTopItemUnderEveryCellCenter() {
        // "The hover container doesn't steal it", pinned geometrically: at
        // every cell's center, the deepest visible item under the cursor sits
        // INSIDE the cell's Button — nothing in the wrapper/carrier stack can
        // intercept mouse or hover between the pointer and the Button.
        // (Combined with the no-popup-over-occupied-cells baseline above, no
        // window can spawn over a parked cursor either.)
        let f = makeFull(seedJson, 0);
        // Item.childAt() only examines direct children; the deepest item under a
        // point is found by recursing (map the point into each child as we go).
        function deepestAt(item, x, y) {
            for (;;) {
                let c = item.childAt(x, y);
                if (c === null)
                    return item;
                let p = c.mapFromItem(item, x, y);
                item = c;
                x = p.x;
                y = p.y;
            }
        }
        for (let i = 0; i < 6; i++) {
            let w = cellWrap(f, i);
            let b = cellBtn(f, i);
            // Descend from the WRAPPER, not the card root: the always-laid-out
            // settings overlay (opacity 0, disabled) covers every cell center
            // from the root, making a root-descent vacuous. Wrapper-descent is
            // overlay-immune and directly pins that nothing in the wrapper stack
            // sits between the pointer and the Button.
            let hit = deepestAt(w, w.width / 2, w.height / 2);
            // The deepest item must be (inside) the cell's Button.
            let inside = false;
            for (let it = hit; it !== null; it = it.parent)
                if (it === b) { inside = true; break; }
            verify(inside,
                   "cell " + i + " center does not reach the Button — something intercepts the mouse");
        }
        f.destroy();
    }

    // --- grid while timing (operator: presets disappeared leaving a huge gap) ---

    function test_grid_whileTiming_staysVisibleWithAllCellsDisabled() {
        let f = makeFull(seedJson, 0);
        verify(f.presetGrid.visible === true);
        verify(cellBtn(f, 0).enabled === true, "occupied cells enabled when idle");
        mockCtrl.phase = "work";
        verify(f.working === true);
        verify(f.presetGrid.visible === true, "grid must stay visible while timing");
        compare(f.presetCells.count, 6, "cells must never vanish while timing");
        for (let i = 0; i < 6; i++)
            verify(cellBtn(f, i).enabled === false, "cell " + i + " must disable while a Work Block times");
        // The machine guard is unchanged: a start attempt during timing is a no-op.
        f.slotClicked(0);
        compare(mockCtrl.startedPreset, null);
        // Break refuses startPreset too — the UI must not offer dead clicks there.
        mockCtrl.phase = "break";
        for (let j = 0; j < 6; j++)
            verify(cellBtn(f, j).enabled === false, "cell " + j + " must disable during a Break");
        // Back to idle: occupied cells come back.
        mockCtrl.phase = "idle";
        verify(cellBtn(f, 0).enabled === true);
        verify(cellBtn(f, 3).enabled === true);
        f.destroy();
    }

    // --- action buttons never clipped (operator: "where are the enable and start/stop buttons?") ---

    function test_mainPage_actionsInsideFrame_everyPhase() {
        // Plasma sizes the card from its implicitHeight; whatever clips on the
        // real shell, the LAYOUT itself must keep every action button inside
        // that frame in every machine phase — asserted here against the same
        // implicitHeight the popup will hand out.
        let f = makeFull(seedJson, 0);
        let strip = findChild(f, "actionStrip");
        verify(strip !== null, "main page must have a reserved action strip");

        function assertInsideFrame(tag) {
            let names = ["startBreakNowButton", "delayBreakButton", "enableButton"];
            for (let n = 0; n < 3; n++) {
                let b = findChild(f, names[n]);
                verify(b !== null, names[n] + " must exist");
                let pTop = b.mapToItem(f, 0, 0).y;
                let pBot = b.mapToItem(f, 0, b.height).y;
                verify(pTop >= 0 && pBot <= f.implicitHeight + 0.5,
                       tag + ": " + names[n] + " outside frame (top " + pTop + ", bottom " + pBot
                       + ", frame " + f.implicitHeight + ")");
                verify(b.visible === true, tag + ": " + names[n] + " must stay in the layout");
            }
        }

        // Idle: Enable visible, running actions faded but still laid out.
        assertInsideFrame("idle");
        let enable = findChild(f, "enableButton");
        let start = findChild(f, "startBreakNowButton");
        let delay = findChild(f, "delayBreakButton");
        verify(enable.enabled === true && enable.opacity === 1, "idle shows Enable live");
        verify(start.opacity === 0, "idle fades Start break now");

        // Round 5 (operator: "shrink all of them"): compact strip — NONE of the
        // three buttons may be full-width anymore. Three natural-width buttons
        // in one row would overflow the 17-grid-unit card (measured 122+99+121
        // px vs 279px of content width), so the running actions share one
        // natural-width row and the Enable/Disable small secondary sits below.
        for (let b of [start, delay, enable])
            verify(b.width < strip.width - 1,
                   b.objectName + " must be natural-width, got " + b.width + " of " + strip.width);
        verify(Math.abs(delay.width - delay.implicitWidth) <= 1.0,
               "Delay keeps its natural width");
        // Round 7 (operator): "Disable for now should match the size of
        // Start break now" — the secondary and the primary Start button share
        // ONE width (the max of their naturals), so the two stacked buttons
        // are the same size regardless of label length. Delay is exempt
        // (different row, natural width).
        verify(Math.abs(enable.width - start.width) <= 0.5,
               "Enable/Disable must match Start break now's width ("
               + enable.width + " vs " + start.width + ")");
        verify(Math.abs(start.width - Math.max(start.implicitWidth, enable.implicitWidth)) <= 1.0,
               "shared width is the max of both naturals, no eliding");
        verify(Math.abs(start.mapToItem(f, 0, 0).y - delay.mapToItem(f, 0, 0).y) <= 0.5,
               "start and delay share one row");
        verify(enable.mapToItem(f, 0, 0).y >= delay.mapToItem(f, 0, 0).y + delay.height - 0.5,
               "the small secondary sits below the running-actions row");
        // Round 7b (operator): the secondary matches Start break now's SIZE
        // INCLUDING the font — same typeface metrics, subordinate by nothing.
        compare(enable.font.pointSize, findChild(f, "deskHint").font.pointSize,
                "deskHint still uses the small font (reference consumer unchanged)");
        compare(enable.font.pointSize, start.font.pointSize,
                "Enable/Disable font must match Start break now's font");
        compare(enable.font.pixelSize, start.font.pixelSize,
                "Enable/Disable font must match Start break now's font (pixel)");
        let stripH0 = strip.height;

        // Work: Start break now goes live, frame unchanged.
        let h0 = f.implicitHeight;
        let mainImp0 = findChild(f, "mainPage").implicitHeight;
        mockCtrl.phase = "work";
        wait(30);
        assertInsideFrame("work");
        verify(start.opacity === 1, "working shows Start break now");
        compare(strip.height, stripH0, "strip height must be phase-independent (reserved contract)");
        compare(findChild(f, "mainPage").implicitHeight, mainImp0,
                "the reserved strip must keep the main page implicitHeight phase-independent");
        compare(f.implicitHeight, h0, "phase changes must not re-height the card");

        // Pending break: all three live, frame unchanged.
        mockCtrl.pendingBreak = true;
        wait(30);
        assertInsideFrame("delay");
        verify(delay.opacity === 1);
        compare(strip.height, stripH0, "strip height must be phase-independent (reserved contract)");
        compare(f.implicitHeight, h0, "pending-break must not re-height the card");
        mockCtrl.pendingBreak = false;
        mockCtrl.phase = "idle";
        f.destroy();
    }

    // --- settings page fits the frame (operator: "the desk reminder is not there") ---

    function test_settings_deskSectionInsideFrame() {
        let f = makeFull(seedJson, 0);
        findChild(f, "settingsGear").clicked();
        wait(30);
        let desk = findChild(f, "deskControls");
        let hint = findChild(f, "deskHint");
        verify(desk !== null && hint !== null);
        let deskBot = desk.mapToItem(f, 0, desk.height).y;
        let hintBot = hint.mapToItem(f, 0, hint.height).y;
        verify(deskBot <= f.implicitHeight + 0.5,
               "desk controls must be inside the frame (bottom " + deskBot + " > " + f.implicitHeight + ")");
        verify(hintBot <= f.implicitHeight + 0.5,
               "desk caption must be inside the frame (bottom " + hintBot + " > " + f.implicitHeight + ")");
        // The desk spinbox is a real, enabled control on that page.
        let ds = findChild(f, "deskMinutesSpin");
        verify(ds !== null && ds.enabled === true, "desk spinbox must be live on the settings page");
        // The whole settings page content fits: its natural height must not
        // exceed the frame it defines.
        let sp = findChild(f, "settingsPage");
        verify(sp.implicitHeight <= findChild(f, "pageHost").implicitHeight + 0.5,
               "settings page must fit the frame it defines");
        f.destroy();
    }

    // --- compact add-preset rows (operator: "too far away from each other") ---

    function test_settings_rowsCompactUniform_oneReservedWarningLine() {
        let f = makeFull(seedJson, 0);            // slot 3 occupied ("Mine 60"), 4-5 empty
        findChild(f, "settingsGear").clicked();
        wait(30);
        let eds = f.userEditorsRepeater;
        compare(eds.count, 3);
        let r0 = eds.itemAt(0), r1 = eds.itemAt(1), r2 = eds.itemAt(2);
        // Uniform row heights, and a tight group pitch: rows squeezed closer
        // than a label row + spin row + spin row of air would allow.
        verify(Math.abs(r0.height - r1.height) <= 0.5 && Math.abs(r1.height - r2.height) <= 0.5,
               "user rows must share one height");
        let pitch = r1.mapToItem(f, 0, 0).y - r0.mapToItem(f, 0, 0).y;
        verify(pitch <= r0.height + Kirigami.Units.smallSpacing + 0.5,
               "rows must sit compactly, pitch " + pitch + " > " + (r0.height + Kirigami.Units.smallSpacing));
        // Round 6: the editor is ONE line — [Work][spin][Break][spin][Large]
        // [spin][delete]. Pin the structure and the height: the editor column
        // holds exactly one row; Work and Large spins share that row's y; and
        // the reserved row height is the one control line (the delete
        // ToolButton's height), occupied or not — that is what collapsed the
        // Add-preset rows and shrank the frame-defining settings page.
        let col0 = findChild(r0, "userEditorColumn0");
        verify(col0 !== null);
        let layoutRows = col0.children.filter(function (c) { return c.toString().indexOf("RowLayout") >= 0; });
        compare(layoutRows.length, 1, "the editor column must be a single row now (no Large line)");
        let work0 = findChild(r0, "workSpin0");
        let large0 = findChild(r0, "largeSpin0");
        let del0 = findChild(r0, "deleteButton0");
        verify(work0 !== null && large0 !== null);
        verify(Math.abs(work0.mapToItem(r0, 0, 0).y - large0.mapToItem(r0, 0, 0).y) <= 0.5,
               "Work and Large spins must share ONE line");
        if (del0) {
            // Same row = same vertical CENTER (the taller ToolButton centers
            // the spins, so tops differ by the centering inset).
            let wC = work0.mapToItem(r0, 0, 0).y + work0.height / 2;
            let dC = del0.mapToItem(r0, 0, 0).y + del0.height / 2;
            verify(Math.abs(wC - dC) <= 0.5,
                   "the delete button must share the one-line row (centers " + wC + " vs " + dC + ")");
            verify(r0.height <= del0.height + 1.0,
                   "reserved row height is one control line, got " + r0.height
                   + " vs delete " + del0.height);
        }
        // ONE always-reserved warning line (consolidated from round-3's three
        // per-row lines) — present and constant-height even when idle.
        let warn = findChild(f, "builtinCollisionWarning");
        verify(warn !== null && warn.visible === true, "warning line must stay in the layout");
        verify(warn.opacity === 0, "no collision yet");
        let warnH = warn.height;
        verify(warnH > 0);
        // Driving a row's live MINUTES into an exact Built-in duplicate must
        // light the line up WITHOUT changing any row height or the card frame.
        // No name field exists anymore: the collision is minutes-only.
        let h0 = f.implicitHeight;
        let brk0 = findChild(r0, "breakSpin0");
        verify(brk0 !== null);
        work0.value = 50;
        brk0.value = 10;
        wait(30);
        compare(warn.opacity, 1, "collision must light the reserved line");
        compare(warn.text, "Can't be identical to a Built-in — change the minutes.");
        compare(warn.height, warnH, "warning line height must stay constant (frame stability)");
        compare(r0.height, eds.itemAt(1).height, "warning must not re-height rows");
        compare(f.implicitHeight, h0, "collision warning must not re-height the card");
        // Moving the minutes off the Built-in clears the line; heights unchanged.
        work0.value = 60;
        wait(30);
        compare(warn.opacity, 0);
        compare(f.implicitHeight, h0);
        f.destroy();
    }

    // --- edit / delete user presets ---

    function test_updateUserPreset_writesImmediateEdits() {
        let f = makeFull(seedJson, 0);
        f.updateUserPreset(3, 90, 12, 0);
        let arr = parseWritten();
        compare(arr.length, 6);
        compare(arr[3].label, "90/12");           // label derives from the new minutes
        compare(arr[3].workMin, 90);
        compare(arr[3].breakMin, 12);
        verify(!("largeBreakMin" in arr[3]), "large 0 commits the automatic rule");
        compare(arr[0].label, "50/10");
        f.destroy();
    }

    function test_updateUserPreset_junkMinutes_fallBackToSlotValues() {
        // No name field exists to be blank: junk minutes keep the slot's stored
        // values and the label re-derives from the KEPT minutes.
        let f = makeFull(seedJson, 0);
        f.updateUserPreset(3, -4, NaN, NaN);
        let arr = parseWritten();
        compare(arr[3].label, "60/9");
        compare(arr[3].workMin, 60);              // junk minutes keep the old ones
        compare(arr[3].breakMin, 9);
        verify(!("largeBreakMin" in arr[3]), "junk large means the automatic rule");
        f.destroy();
    }

    function test_updateUserPreset_largeBreakMin_storedOnlyWhenPositive() {
        // Spinbox-authoritative per commit: >0 stores the explicit value, 0 (or
        // junk) REMOVES any previously stored explicit value — never carried
        // forward.
        let f = makeFull(seedJson, 0);
        f.updateUserPreset(3, 60, 9, 45);
        compare(parseWritten()[3].largeBreakMin, 45);
        // config echo, as main.qml does — then 0 must remove, not keep, 45
        f.presetsJson = suite.writtenJson;
        f.updateUserPreset(3, 60, 9, 0);
        verify(!("largeBreakMin" in parseWritten()[3]),
               "large 0 must remove the stored explicit value");
        f.updateUserPreset(3, 60, 9, NaN);
        verify(!("largeBreakMin" in parseWritten()[3]),
               "junk large must remove the stored explicit value too");
        f.destroy();
    }

    function test_updateUserPreset_exactBuiltinDuplicate_isRefused() {
        // A user preset whose minutes equal a Built-in derives the Built-in's
        // label and would be filtered out by the machine's normalize on next
        // read (locked storage), silently erasing the slot — the card must
        // refuse the write instead.
        let f = makeFull(seedJson, 0);
        f.updateUserPreset(3, 50, 10, 0);
        compare(suite.writtenJson, "", "exact-Built-in duplicate must not be written");
        f.updateUserPreset(3, 25, 5, 0);
        compare(suite.writtenJson, "", "the classic 25/5 is a Built-in under derived naming");
        f.destroy();
    }

    function test_updateUserPreset_minutesAloneDefineIdentity() {
        // Renaming is gone: the label derives from the minutes. A user preset
        // whose NEW minutes equal a Built-in is refused even though its STORED
        // name differed; minutes off every Built-in always write.
        let f = makeFull(seedJson, 0);            // slot 3 stored as "Mine 60" 60/9
        f.updateUserPreset(3, 50, 10, 0);         // derives "50/10" == Built-in slot 0
        compare(suite.writtenJson, "");
        f.updateUserPreset(3, 50, 11, 0);         // derives "50/11": legitimate
        verify(suite.writtenJson !== "");
        f.destroy();
    }

    function test_editEcho_doesNotRebuildEditorRows() {
        // The settings Repeater model must be stable (slot indices, not the
        // occupied-slot list): every live edit echoes back through the config
        // and recomputes `slots`; a fresh model array there rebuilt all rows,
        // dropping focus mid-interaction.
        let f = makeFull(seedJson, 0);
        let editors = f.userEditorsRepeater;
        compare(editors.count, 3);                 // slots 3-5, stable, always present
        let row0 = editors.itemAt(0);
        verify(row0 !== null);
        f.updateUserPreset(3, 70, 8, 0);           // write...
        f.presetsJson = suite.writtenJson;         // ...and simulate the config echo
        compare(editors.itemAt(0), row0);          // same delegate object — not rebuilt
        let arr = parseWritten();
        compare(arr[3].label, "70/8");
        f.destroy();
    }

    function test_deleteUserPreset_nullsItsSlot() {
        let f = makeFull(seedJson, 0);
        f.deleteUserPreset(3);
        let arr = parseWritten();
        compare(arr.length, 6);                   // storage always holds six entries
        compare(arr[3], null);
        compare(arr[0].label, "50/10");
        compare(arr[2].label, "45/15");
        f.destroy();
    }

    function test_deleteUserPreset_starredSlot_resetsStarToBuiltin() {
        // Deleting the starred user preset must move the star to a Built-in
        // (slot 0 = 50/10) via defaultPresetWritten: the machine already falls
        // back to the first Built-in when the star points at an empty slot, so
        // keeping the stale index would render a phantom star on the "—" dash.
        let f = makeFull(seedJson, 3);            // star on user slot 3
        f.deleteUserPreset(3);
        compare(parseWritten()[3], null);
        compare(suite.writtenDefault, 0,
                "deleting the starred slot must reset the star to Built-in slot 0");
        f.defaultPreset = suite.writtenDefault;   // config echo, as main.qml does
        compare(f.slotText(0), "★ 50/10");        // star moved to the Built-in
        f.presetsJson = suite.writtenJson;        // config echo for the slots too
        compare(f.slotText(3), "—");              // no phantom star on the dash
        f.destroy();
    }

    function test_deleteUserPreset_nonStarredSlot_keepsStar() {
        // Only the DELETED slot's own star moves: a star on any other slot
        // (Built-in or user) must survive a deletion untouched.
        let f = makeFull(seedJson, 0);            // star on Built-in slot 0
        f.deleteUserPreset(3);
        compare(parseWritten()[3], null);
        compare(suite.writtenDefault, -1,
                "deleting a non-starred slot must not emit a star move");
        f.destroy();
    }

    // --- built-ins are immutable ---

    function test_builtIns_exposeNoEditDeleteControls() {
        let f = makeFull(seedJson, 0);
        f.deleteUserPreset(0);                    // built-in delete attempts are no-ops
        f.updateUserPreset(1, 1, 1, 1);
        f.updateUserPreset(5, 5, 5, 5);           // empty user slot cannot be edited
        f.addUserPresetAt(0);                     // nor can an add land on a built-in
        compare(suite.writtenJson, "");           // none of these wrote anything
        f.destroy();

        let g = makeFull(seedJson, 3);            // star sits on the user slot here
        g.deleteUserPreset(0);                    // built-in delete attempts are no-ops
        g.updateUserPreset(1, 1, 1, 1);
        g.updateUserPreset(5, 5, 5, 5);           // empty user slot cannot be edited
        g.addUserPresetAt(0);                     // nor can an add land on a built-in
        compare(suite.writtenJson, "");           // none of these wrote anything
        compare(g.slotText(0), "50/10");
        compare(g.slotText(1), "25/5");
        compare(g.slotText(5), "—");
        g.destroy();
    }

    // --- settings page (gear in the header row) ---

    function test_settings_gearTogglesPages_pagesSwapByOpacityAndInput() {
        let f = makeFull(seedJson, 0);
        let gear = findChild(f, "settingsGear");
        let main = findChild(f, "mainPage");
        let settings = findChild(f, "settingsPage");
        verify(gear !== null && main !== null && settings !== null,
               "card must expose the gear and the two pages");
        // Pages swap by opacity + enabled; they never leave the layout
        // (visible stays true) so the card frame cannot re-height.
        verify(main.visible === true && settings.visible === true,
               "both pages always stay in the layout");
        verify(settings.opacity === 0 && settings.enabled === false,
               "settings page hidden (faded, input-disabled) by default");
        verify(main.opacity === 1 && main.enabled === true, "main page live by default");
        verify(gear.checked === false, "gear shows the inactive state initially");
        gear.clicked();                          // simulated gear press
        verify(settings.opacity === 1 && settings.enabled === true,
               "gear press shows the settings page");
        verify(main.opacity === 0 && main.enabled === false,
               "main page is faded out and input-disabled under settings");
        verify(gear.checked === true, "gear shows the active page");
        gear.clicked();
        verify(settings.opacity === 0 && settings.enabled === false
               && main.opacity === 1 && main.enabled === true, "pressing again returns");
        f.destroy();
    }

    function test_settings_pageSwitch_keepsConstantCardFrame() {
        let f = makeFull(seedJson, 0);
        wait(50);
        let h0 = f.implicitHeight;
        let w0 = f.implicitWidth;
        verify(h0 > 0, "card has a laid-out frame height");
        let gear = findChild(f, "settingsGear");
        verify(gear !== null);
        let gm = [gear.mapToItem(f, 0, 0).x, gear.mapToItem(f, 0, 0).y];
        verify(gm[1] > 0, "header is positively laid out (vacuous-at-zero checks ended round 3)");
        let main = findChild(f, "mainPage");
        let pageWidth = main.width;              // both pages span the card
        verify(pageWidth > 0, "main page is laid out at card width");
        gear.clicked();
        wait(50);
        let settings = findChild(f, "settingsPage");
        verify(settings.opacity === 1);
        compare(f.implicitHeight, h0, "opening settings must NOT re-height the card");
        compare(f.implicitWidth, w0, "card width is constant");
        compare(gear.mapToItem(f, 0, 0).x, gm[0], "gear must not move when settings open");
        compare(gear.mapToItem(f, 0, 0).y, gm[1], "gear must not move when settings open");
        compare(settings.width, pageWidth, "settings page spans the same card width");
        gear.clicked();
        wait(50);
        compare(f.implicitHeight, h0, "closing settings changes nothing — the frame is one size");
        compare(gear.mapToItem(f, 0, 0).y, gm[1]);
        f.destroy();
    }

    function test_cardFrame_constantAcrossTiming() {
        let f = makeFull(seedJson, 0);
        wait(50);
        let h0 = f.implicitHeight;
        let gear = findChild(f, "settingsGear");
        let gx = gear.x, gy = gear.y;
        mockCtrl.phase = "work";
        mockCtrl.pendingBreak = true;            // tallest working arrangement
        wait(50);
        compare(f.implicitHeight, h0, "starting a timed block must NOT re-height the card");
        compare(gear.x, gx);
        compare(gear.y, gy);
        mockCtrl.phase = "break";
        wait(50);
        compare(f.implicitHeight, h0, "break must not re-height the card either");
        compare(gear.x, gx);
        compare(gear.y, gy);
        f.destroy();
    }

    // --- settings page rows: add-in-settings flow ---

    function test_settings_emptySlotRowShowsAddButton_addWritesThatSlot() {
        let f = makeFull(seedJson, 0);           // slot 3 occupied, slots 4-5 empty
        let hCard0 = f.implicitHeight;
        findChild(f, "settingsGear").clicked();
        wait(50);
        compare(f.implicitHeight, hCard0, "opening settings keeps the frame");
        let editors = f.userEditorsRepeater;
        compare(editors.count, 3);

        // Occupied row: the editor is live; no add button. There is no name
        // field: presets are identified by their minutes.
        let work0 = findChild(editors.itemAt(0), "workSpin0");
        let large0 = findChild(editors.itemAt(0), "largeSpin0");
        let add0 = findChild(editors.itemAt(0), "addPresetButton0");
        verify(work0 !== null && large0 !== null, "occupied slot row shows the spin editor");
        verify(findChild(editors.itemAt(0), "presetLabelField0") === null,
               "no name field may exist in a user row");
        compare(work0.value, 60);                 // stored "Mine 60" = 60/9
        compare(large0.value, 0);                 // no explicit large → automatic rule
        verify(add0.visible === false, "occupied row offers no add button");

        // Empty row: a single live add button, no editor. The editor column is
        // faded out and input-disabled as a subtree (children keep their own
        // property values; the container carries the disabled state).
        let row1 = editors.itemAt(1);
        let h1 = row1.height;
        let add1 = findChild(row1, "addPresetButton1");
        let col1 = findChild(row1, "userEditorColumn1");
        let work1 = findChild(row1, "workSpin1");
        verify(add1 !== null && add1.visible === true && add1.enabled === true,
               "empty slot row shows a clickable add button");
        verify(col1 !== null, "editor container exists even for empty rows");
        verify(col1.opacity === 0 && col1.enabled === false,
               "empty slot row renders no greyed-out editor fields");
        verify(row1.height > 0);

        add1.clicked();                          // create the preset in slot 4
        let arr = parseWritten();
        verify(Array.isArray(arr), "add writes six-slot JSON");
        compare(arr.length, 6);
        compare(arr[4].label, "30/5");            // derived; the default must NOT
        compare(arr[4].workMin, 30);              // equal a Built-in: locked storage
        compare(arr[4].breakMin, 5);              // would erase a 25/5 default on echo
        verify(!("largeBreakMin" in arr[4]), "add defaults to the automatic rule");
        compare(arr[0].label, "50/10");           // built-ins intact
        compare(arr[3].label, "60/9");            // other user preset intact
        compare(arr[5], null);                    // third slot untouched

        // The row itself held a constant height through creation (uniform rows).
        compare(row1.height, h1, "adding a preset must not re-height its row");

        // Simulate the config echo (main.qml writes presets back): the row now
        // edits in place — editor live, add button gone, entry SURVIVED the read.
        f.presetsJson = suite.writtenJson;
        wait(50);
        compare(f.implicitHeight, hCard0, "creating a preset must not re-height the card");
        compare(f.slotText(4), "30/5");           // not self-erased by the echo
        compare(work1.value, 30);
        verify(col1.enabled === true && col1.opacity === 1, "added preset edits in place");
        verify(add1.visible === false, "add button yields to the editor");
        // Row-fit contract (review finding, round 6): the one-line editor row
        // must FIT the card width — its natural implicit width may never
        // exceed the laid-out width, or the controls squeeze/overflow.
        let editRow1 = findChild(f, "presetEditRow1");
        verify(editRow1 !== null, "one-line editor row exists and is discoverable");
        verify(editRow1.width > 0, "occupied row's editor line is laid out");
        verify(editRow1.implicitWidth <= editRow1.width + 0.5,
               "editor row must fit the card width without overflow (21gu contract)");
        f.destroy();
    }

    // --- settings page uniform sizing (operator: "those buttons are like different sizes") ---

    function test_settings_uniformComponentWidths() {
        let f = makeFull(freshJson, 0);          // all three user slots empty
        findChild(f, "settingsGear").clicked();
        wait(50);
        // Spinboxes share one fixed width, including the Large and desk spins.
        let ws = findChild(f, "workSpin0");
        let bs = findChild(f, "breakSpin0");
        let ls = findChild(f, "largeSpin0");
        let ds = findChild(f, "deskMinutesSpin");
        verify(ws !== null && bs !== null && ls !== null && ds !== null);
        verify(ws.Layout.preferredWidth > 0);
        compare(bs.Layout.preferredWidth, ws.Layout.preferredWidth, "work/break spins uniform");
        compare(ls.Layout.preferredWidth, ws.Layout.preferredWidth, "large spin matches editor spins");
        compare(ds.Layout.preferredWidth, ws.Layout.preferredWidth, "desk spin matches editor spins");
        // The three add buttons render identical, content-independent widths.
        let a0 = findChild(f, "addPresetButton0");
        let a1 = findChild(f, "addPresetButton1");
        let a2 = findChild(f, "addPresetButton2");
        verify(a0 !== null && a1 !== null && a2 !== null);
        verify(a0.visible === true && a1.visible === true && a2.visible === true);
        verify(a0.width > 0, "add buttons are laid out");
        compare(a1.width, a0.width, "add buttons must share one width");
        compare(a2.width, a0.width, "add buttons must share one width");
        // Uniform row footprints across the settings page.
        let eds = f.userEditorsRepeater;
        compare(eds.itemAt(0).width, eds.itemAt(1).width, "user rows share the page width");
        compare(eds.itemAt(1).width, eds.itemAt(2).width, "user rows share the page width");
        f.destroy();
    }

    function test_settings_containsStarEditorsDeskControls() {
        let f = makeFull(seedJson, 0);
        findChild(f, "settingsGear").clicked();
        verify(findChild(f, "starPicker") !== null, "star picker lives on the settings page");
        let editors = findChild(f, "userEditors");
        verify(editors !== null, "user preset rows live on the settings page");
        compare(editors.count, 3);               // stable rows for user slots 3-5
        verify(findChild(f, "deskControls") !== null,
               "desk reminder controls live on the settings page");
        f.destroy();
    }

    // --- derived naming & Large spin (round 5: no name field, 0 = auto rule) ---

    function test_settings_labelFieldRemoved_largeSpinContract() {
        let f = makeFull(seedJson, 0);
        findChild(f, "settingsGear").clicked();
        wait(30);
        for (let i = 0; i < 3; i++) {
            verify(findChild(f, "presetLabelField" + i) === null,
                   "label field must be gone entirely (row " + i + ")");
            let ls = findChild(f, "largeSpin" + i);
            verify(ls !== null, "Large spinbox must exist (row " + i + ")");
            compare(ls.from, 0, "Large range starts at 0 = automatic rule");
            compare(ls.to, 600);
            verify(ls.editable === true, "Large must be editable like its siblings");
            compare(ls.value, 0, "stored entries without explicit large show the rule");
        }
        f.destroy();
    }

    function test_settings_largeBreakHint_presentAndSubordinate() {
        // One small-font, low-opacity, ALWAYS-laid-out hint line under the user
        // rows (wraps like the desk hint; never visible:false — constant frame).
        let f = makeFull(seedJson, 0);
        let hint = findChild(f, "largeBreakHint");
        verify(hint !== null, "automatic-rule hint must exist under the user rows");
        verify(hint.visible === true, "hint stays in the layout (constant frame)");
        verify(hint.opacity < 1, "hint is visually subordinate");
        // Compare against the card's existing smallFont consumer: the TestCase
        // context resolves Kirigami.Theme without the card's theme (12pt vs 9).
        compare(hint.font.pointSize, findChild(f, "deskHint").font.pointSize,
                "hint must render in the small font (match the desk hint)");
        verify(hint.text.indexOf("automatic") >= 0, "hint explains the automatic rule");
        f.destroy();
    }

    // --- custom one-off row removed ---

    function test_customRow_isGone() {
        let f = makeFull(seedJson, 0);
        verify(findChild(f, "customRow") === null,
               "the Custom one-off row was removed (user presets cover it)");
        findChild(f, "settingsGear").clicked();  // not hiding in the settings page either
        verify(findChild(f, "customRow") === null);
        f.destroy();
    }

    // --- desk reminder controls ---

    function test_deskReminderLabel_elidesInsteadOfClipping() {
        // Round-5 hardening: the "Desk reminder" label is the fillWidth element
        // squeezed between the fixed-width Switch/SpinBox/"min". Headless render
        // refuted a default-metrics clip, but the real shell's theme/fonts may
        // squeeze the allocation — the label must elide right (never clip or
        // push the row wide).
        let f = makeFull(seedJson, 0);
        let lbl = findChild(f, "deskReminderLabel");
        verify(lbl !== null, "desk reminder label must be discoverable");
        compare(lbl.elide, Text.ElideRight);
        f.destroy();
    }

    function test_deskControls_writeConfig() {
        let f = makeFull(seedJson, 0);
        f.setDeskReminderEnabled(false);
        compare(suite.writtenDeskEnabled, false);
        f.setDeskReminderMinutes(45);
        compare(suite.writtenDeskMinutes, 45);
        f.setDeskReminderMinutes(NaN);            // junk falls back to the current value
        compare(suite.writtenDeskMinutes, 30);
        f.destroy();
    }
}
