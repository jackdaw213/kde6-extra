// Headless test of the PresenceMonitor observation contract: a lock-state
// observation must not be recorded before the controller can apply it, or the
// first unlock after startup would be swallowed and auto-start would stay dead
// until the next lock/unlock transition (SPEC-003).
import QtTest
import QtQuick

TestCase {
    id: suite

    // The fake controller returns false while it is "not loaded", exactly like
    // main.qml's dispatch() guard. A successful apply increments a counter.
    property var fakeCtrl: QtObject {
        property bool ready: false
        property int unlockedCount: 0
        property int lockedCount: 0

        function screenUnlocked() {
            if (!suite.fakeCtrl.ready)
                return false;
            suite.fakeCtrl.unlockedCount++;
            return true;
        }

        function screenLocked() {
            if (!suite.fakeCtrl.ready)
                return false;
            suite.fakeCtrl.lockedCount++;
            return true;
        }
    }

    function init() {
        suite.fakeCtrl.ready = false;
        suite.fakeCtrl.unlockedCount = 0;
        suite.fakeCtrl.lockedCount = 0;
    }

    function makeMonitor() {
        let comp = Qt.createComponent("../plasmoid/contents/ui/PresenceMonitor.qml");
        verify(comp.status === Component.Ready, "component failed: " + comp.errorString());
        let obj = comp.createObject(suite);
        verify(obj !== null, "create failed: " + comp.errorString());
        // The real poll is not the subject; stop the repeating timer. The
        // one-shot initial poll may still land, but the transition dedup keeps
        // it harmless.
        // qmllint disable missing-property
        obj.pollTimer.running = false;
        obj.ctrl = suite.fakeCtrl;
        // qmllint enable missing-property
        return obj;
    }

    function test_observe_withoutController_doesNotRecord() {
        let m = makeMonitor();
        m.ctrl = null;
        m.observe(false);
        suite.fakeCtrl.ready = true;
        m.ctrl = suite.fakeCtrl;
        m.observe(false);
        compare(suite.fakeCtrl.unlockedCount, 1);
        m.destroy();
    }

    function test_observe_afterUnavailable_reapplies() {
        let m = makeMonitor();
        suite.fakeCtrl.ready = true;
        m.observe(false);
        compare(suite.fakeCtrl.unlockedCount, 1);
        // Both sources failed: the host was told away. The next successful poll
        // is a fresh observation and must be applied again, not deduped.
        m.reportUnavailable("test outage");
        m.observe(false);
        compare(suite.fakeCtrl.unlockedCount, 2);
        m.destroy();
    }

    function test_observe_beforeControllerReady_isRetried() {
        let m = makeMonitor();
        m.observe(false);                       // not applied: must not record
        compare(suite.fakeCtrl.unlockedCount, 0);
        suite.fakeCtrl.ready = true;
        m.observe(false);                       // the retry applies exactly once
        compare(suite.fakeCtrl.unlockedCount, 1);
        m.observe(false);                       // repeated observation dedups
        compare(suite.fakeCtrl.unlockedCount, 1);
        m.observe(true);                        // a lock transition applies
        compare(suite.fakeCtrl.lockedCount, 1);
        m.destroy();
    }
}
