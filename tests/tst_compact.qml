// Headless test of CompactRepresentation sizing: width must flex with the
// timer text (panel overlap regression). No plasmashell needed.
import QtTest
import QtQuick.Layouts
import QtQuick
import org.kde.kirigami as Kirigami
import "."

TestCase {
    id: suite

    property var mockCtrl: QtObject {
        property bool running: false
        property string remainingText: ""
        function togglePopup() {}
    }

    function makeCompact() {
        let comp = Qt.createComponent("../plasmoid/contents/ui/CompactRepresentation.qml");
        // Simulate a 44px-thick panel: the panel sets the applet's height via
        // Layout.fillHeight; we pin it explicitly here.
        let obj = comp.createObject(null, { ctrl: mockCtrl, height: 44 });
        verify(obj !== null, "create failed: " + (obj === null && comp ? comp.errorString() : "?"));
        return obj;
    }

    function test_idle_showsIconSize() {
        mockCtrl.running = false;
        let c = makeCompact();
        verify(c, "compact creation failed");
        // Idle: square cell at the panel thickness — the icon renders at the
        // same size as before the flex patch (height-bound, not iconSizes.small).
        compare(c.Layout.minimumWidth, c.height);
        compare(c.Layout.preferredWidth, c.height);
        c.destroy();
    }

    function test_running_widthTracksTimerText() {
        mockCtrl.running = true;
        mockCtrl.remainingText = "49:47";
        let c = makeCompact();
        verify(c, "compact creation failed");
        let w1 = c.implicitWidth;
        verify(w1 > Kirigami.Units.iconSizes.small,
               "running compact must be wider than an icon, got " + w1);
        compare(c.Layout.minimumWidth, c.implicitWidth);
        compare(c.Layout.preferredWidth, c.implicitWidth);
        // Text grows to a wider string -> width must grow with it.
        mockCtrl.remainingText = "1:04:59"; // unlikely mm:ss, but stresses tracking
        let w2 = c.implicitWidth;
        verify(w2 >= w1, "implicitWidth must not shrink when text widens: " + w2 + " < " + w1);
        // Back to idle -> back to the square icon cell.
        mockCtrl.running = false;
        compare(c.Layout.minimumWidth, c.height);
        compare(c.Layout.preferredWidth, c.height);
        c.destroy();
    }
}
