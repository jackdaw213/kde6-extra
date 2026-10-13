/*
 * Chime adapter — audible cue when a Break starts and when the Desk Overlay
 * appears (SPEC-002).
 *
 * Uses QtMultimedia MediaPlayer (ffmpeg-backed, decodes Ogg/Vorbis) with the
 * bundled soft piano arpeggio in ../sounds/, resolved relative to this file so
 * it works from the installed package path. SoundEffect was rejected: it
 * decodes via QWaveDecoder, which is WAV-only.
 * Loaded via a Loader from main.qml for graceful degradation.
 */
import QtQuick
import QtMultimedia

QtObject {
    id: chimer

    readonly property string sampleUrl: Qt.resolvedUrl("../sounds/pomodoro-chime.ogg")

    property MediaPlayer sound: MediaPlayer {
        source: chimer.sampleUrl
        audioOutput: AudioOutput {
            volume: 0.9
        }
        onErrorOccurred: function (error, errorString) {
            console.warn("pomodoro: chime playback error:", errorString);
        }
    }

    function chime() {
        try {
            sound.stop();
            sound.play();
        } catch (e) {
            console.warn("pomodoro: chime failed:", e);
        }
    }
}
