import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// OSD de brillo: muestra la misma barra superior que VolumeOsd, pero para el
// brillo de pantalla.
//
// No depende de que el cambio venga de un comando concreto: observa el
// fichero /sys/class/backlight/<device>/brightness con inotify, asi que se
// dispara con las teclas XF86MonBrightnessUp/Down (binds de Hyprland via
// brightnessctl), con el slider de la pagina de monitores del panel, o con
// cualquier otro programa que escriba en sysfs.

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 150
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Only the flyout captures input while it is visible
    mask: Region {
        item: root.showing ? flyout : null
    }

    // -------------------------
    // Backlight state
    // -------------------------

    property string deviceName: ""
    property int brightness: 0
    property int maxBrightness: 1
    property bool gotInitialValue: false

    readonly property real level: maxBrightness > 0 ? brightness / maxBrightness : 0

    // First backlight device (e.g. intel_backlight)
    Process {
        id: deviceDetect

        running: true
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -n 1"]

        stdout: StdioCollector {
            onStreamFinished: {
                const name = this.text.trim()
                if (name !== "")
                    root.deviceName = name
            }
        }
    }

    FileView {
        id: maxFile

        path: root.deviceName !== ""
            ? "/sys/class/backlight/" + root.deviceName + "/max_brightness"
            : ""

        watchChanges: false
        printErrors: false

        onLoaded: {
            const v = parseInt(text())
            if (!isNaN(v) && v > 0)
                root.maxBrightness = v
        }
    }

    FileView {
        id: brightnessFile

        path: root.deviceName !== ""
            ? "/sys/class/backlight/" + root.deviceName + "/brightness"
            : ""

        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        onLoaded: {
            const v = parseInt(text())
            if (isNaN(v))
                return

            root.brightness = v

            // The first load is just the initial value; only changes after
            // that open the OSD.
            if (root.gotInitialValue)
                root.showOsd()
            else
                root.gotInitialValue = true
        }
    }

    // -------------------------
    // OSD state
    // -------------------------

    property bool showing: false
    property bool hovered: flyoutArea.containsMouse

    function showOsd() {
        showing = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer

        interval: 1200
        repeat: false

        onTriggered: {
            // Stay open while the pointer is over the OSD
            if (root.hovered) {
                hideTimer.restart()
                return
            }
            root.showing = false
        }
    }

    // -------------------------
    // BRIGHTNESS OSD
    // -------------------------

    Rectangle {
        id: flyout

        property bool open: root.showing

        width: 320
        height: 28

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 30

        radius: 36
        color: Theme.alpha(Theme.bg, 0.5)

        opacity: open ? 1 : 0
        scale: open ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        // Hover keeps the OSD open
        MouseArea {
            id: flyoutArea

            anchors.fill: parent
            hoverEnabled: true
            enabled: flyout.open
        }

        Text {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter

            // Material Design Icons (Symbols Nerd Font):
            // U+F00DD brightness-4, U+F00DE brightness-5, U+F00E0 brightness-7
            text: {
                if (root.level < 0.34)
                    return "󰃝"
                if (root.level < 0.67)
                    return "󰃞"
                return "󰃠"
            }

            font.family: "Symbols Nerd Font"
            font.pixelSize: 20

            color: Theme.text
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter

            text: Math.round(root.level * 100) + "%"

            font.pixelSize: 12
            font.bold: true

            color: Theme.text
        }

        Rectangle {
            anchors.left: icon.right
            anchors.leftMargin: 15

            anchors.right: parent.right
            anchors.rightMargin: 68

            anchors.verticalCenter: parent.verticalCenter

            height: 5
            radius: 4

            color: "#555555"

            Rectangle {
                width: parent.width * Math.min(root.level, 1)

                height: parent.height
                radius: 4

                color: Theme.text

                Behavior on width {
                    NumberAnimation { duration: 100 }
                }
            }
        }
    }
}
