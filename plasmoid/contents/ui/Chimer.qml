/*
 * Chime adapter — audible cue at break start only.
 *
 * Uses QtMultimedia MediaPlayer (ffmpeg-backed, decodes the freedesktop theme's
 * Ogg samples). SoundEffect was rejected: it decodes via QWaveDecoder, which is
 * WAV-only, and the freedesktop sound theme ships only .oga files.
 * Loaded via a Loader from main.qml for graceful degradation.
 */
import QtQuick
import QtMultimedia

QtObject {
    id: chimer

    readonly property string sampleUrl: "file:///usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

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
