/*
 * Media Pause adapter — pauses all PLAYING MPRIS players at break start.
 * Never auto-resumes: no resume path exists anywhere (per spec).
 *
 * Kept in its own file and loaded via a Loader from main.qml so that a missing
 * or changed org.kde.plasma.private.mpris module degrades gracefully (logged)
 * instead of breaking the plasmoid.
 */
import QtQuick
import org.kde.plasma.private.mpris as Mpris

QtObject {
    id: pauser

    readonly property Mpris.Mpris2Model model: Mpris.Mpris2Model {}

    function pauseAll() {
        try {
            const originalIndex = model.currentIndex;
            const count = model.rowCount();
            for (let i = 0; i < count; i++) {
                model.currentIndex = i;
                const player = model.currentPlayer;
                if (player && player.canControl && player.playbackStatus === Mpris.PlaybackStatus.Playing) {
                    player.Pause();
                }
            }
            model.currentIndex = originalIndex;
        } catch (e) {
            console.warn("pomodoro: media pause failed:", e);
        }
    }
}
