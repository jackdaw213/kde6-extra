/// Desktop preview on background with configurable blur.
/// Plasma 6 port:
/// - the dedicated KWinComponents.DesktopBackground component replaces the manual
///   desktop-window lookup + ThumbnailItem of the Plasma 5 version
/// - QtGraphicalEffects (FastBlur) is not available in Qt 6 without the Qt5Compat
///   module, so the blur is done with MultiEffect from QtQuick.Effects
import QtQuick
/// double import: unaliased for the `Workspace` singleton, aliased for the
/// KWinComponents QML types (DesktopBackground)
import org.kde.kwin
import org.kde.kwin as KWinComponents
import QtQuick.Effects

Item {
    y: - (mainWindow.y - minDy)
    x: - (mainWindow.x - minDx)
    height: Screen.height
    width: currentScreenWidth
    visible: showDesktopBackground && mainWindow.activated

    KWinComponents.DesktopBackground {
        id: desktopBackground
        output: Workspace.activeScreen
        desktop: Workspace.currentDesktop
        anchors.fill: parent
    }

    /// configurable blur
    MultiEffect {
        anchors.fill: parent
        source: desktopBackground
        autoPaddingEnabled: false
        blurEnabled: desktopBackgroundBlur > 0
        blur: Math.min(1.0, desktopBackgroundBlur / 45.0)
        blurMax: 64
        visible: desktopBackgroundBlur > 0
    }
}
