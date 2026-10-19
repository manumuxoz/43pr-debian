import Quickshell
import Quickshell.Wayland
import QtQuick

Item {
    id: root
    // Desactivado: el usuario pidió no bloquear nunca. Este trigger lanzaba
    // hyprlock con solo pasar el mouse por la esquina superior izquierda.
    property bool hyprlockEnabled: false
    property bool settingsEnabled: true
    // Desactivado a peticion del usuario: al arrastrar el raton hasta la zona
    // superior solo debe abrirse el gestor de configuracion, no el selector de
    // fondos de pantalla.
    property bool wallpaperEnabled: false
    property bool wlogoutEnabled: true

    property int triggerHeight: 10
    property color triggerColor: '#0037ff00'
    property real hyprlockFrom: 0.0
    property real hyprlockTo: 0.01

    property real settingsFrom: 0.25
    property real settingsTo: 0.40

    property real wallpaperFrom: 0.60
    property real wallpaperTo: 0.75

    property real wlogoutFrom: 0.99
    property real wlogoutTo: 1.0

    PanelWindow {
        id: hyprlockTrigger
        visible: root.hyprlockEnabled
        anchors { top: true; left: true }
        implicitHeight: root.triggerHeight
        implicitWidth: screen ? Math.round(screen.width * (root.hyprlockTo - root.hyprlockFrom)) : 0
        margins {
            left: screen ? Math.round(screen.width * root.hyprlockFrom) : 0
            top: 0
        }
        color: root.triggerColor
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: Quickshell.execDetached([
                "hyprlock"
            ])
        }
    }

    PanelWindow {
        id: settingsTrigger
        visible: root.settingsEnabled
        anchors { top: true; left: true }
        implicitHeight: root.triggerHeight
        implicitWidth: screen ? Math.round(screen.width * (root.settingsTo - root.settingsFrom)) : 0
        margins {
            left: screen ? Math.round(screen.width * root.settingsFrom) : 0
            top: 0
        }
        color: root.triggerColor
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: Quickshell.execDetached([
                "qs", "ipc", "call", "settings", "toggle"
            ])
        }
    }

    PanelWindow {
        id: wallpaperTrigger
        visible: root.wallpaperEnabled
        anchors { top: true; left: true }
        implicitHeight: root.triggerHeight
        implicitWidth: screen ? Math.round(screen.width * (root.wallpaperTo - root.wallpaperFrom)) : 0
        margins {
            left: screen ? Math.round(screen.width * root.wallpaperFrom) : 0
            top: 0
        }
        color: root.triggerColor
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: Quickshell.execDetached([
                "sh", "-c", "qs -n -p ~/.config/quickshell/hyprquickpaper"
            ])
        }
    }

    PanelWindow {
        id: wlogoutTrigger
        visible: root.wlogoutEnabled
        anchors { top: true; left: true }
        implicitHeight: root.triggerHeight
        implicitWidth: screen ? Math.round(screen.width * (root.wlogoutTo - root.wlogoutFrom)) : 0
        margins {
            left: screen ? Math.round(screen.width * root.wlogoutFrom) : 0
            top: 0
        }
        color: root.triggerColor
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: Quickshell.execDetached([
                ".config/hypr/scripts/wlogout.sh"
            ])
        }
    }
}
