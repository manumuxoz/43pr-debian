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
    // Esquina superior derecha: PowerMenu de Quickshell (ya no wlogout).
    property bool powerMenuEnabled: true

    property int triggerHeight: 10
    property color triggerColor: '#0037ff00'
    property real hyprlockFrom: 0.0
    property real hyprlockTo: 0.01

    property real settingsFrom: 0.25
    property real settingsTo: 0.40

    property real wallpaperFrom: 0.60
    property real wallpaperTo: 0.75

    property real powerMenuFrom: 0.99
    property real powerMenuTo: 1.0

    // Una copia de cada zona por monitor. Variants recrea los delegates cuando
    // cambia Quickshell.screens (monitor conectado/desconectado o reconfigurado),
    // así los triggers no se quedan pegados al monitor con el que arrancó el shell.
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.hyprlockEnabled
            anchors { top: true; left: true }
            implicitHeight: root.triggerHeight
            implicitWidth: Math.round(modelData.width * (root.hyprlockTo - root.hyprlockFrom))
            margins {
                left: Math.round(modelData.width * root.hyprlockFrom)
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
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.settingsEnabled
            anchors { top: true; left: true }
            implicitHeight: root.triggerHeight
            implicitWidth: Math.round(modelData.width * (root.settingsTo - root.settingsFrom))
            margins {
                left: Math.round(modelData.width * root.settingsFrom)
                top: 0
            }
            color: root.triggerColor
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: Quickshell.execDetached([
                    "qs", "ipc", "call", "settings", "toggleOn", modelData.name
                ])
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.wallpaperEnabled
            anchors { top: true; left: true }
            implicitHeight: root.triggerHeight
            implicitWidth: Math.round(modelData.width * (root.wallpaperTo - root.wallpaperFrom))
            margins {
                left: Math.round(modelData.width * root.wallpaperFrom)
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
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.powerMenuEnabled
            anchors { top: true; left: true }
            implicitHeight: root.triggerHeight
            implicitWidth: Math.round(modelData.width * (root.powerMenuTo - root.powerMenuFrom))
            margins {
                left: Math.round(modelData.width * root.powerMenuFrom)
                top: 0
            }
            color: root.triggerColor
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: Quickshell.execDetached([
                    "qs", "ipc", "call", "powermenu", "open"
                ])
            }
        }
    }
}
