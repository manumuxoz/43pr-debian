import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Hyprland
import QtQuick
import "SettingsPages"

Scope {
    id: shell

    property bool showing: false
    // Keep the window mapped (hidden) so the opening animation can run on an
    // already-created surface. Creating it on demand made the first visible
    // frame appear halfway through the transition.
    property bool mounted: true
    property var targetScreen: Quickshell.screens[0]
    property int selectedIndex: 0
    property bool probePending: false
    property bool pendingShow: false

    // Resolve a monitor name to a Quickshell screen.
    function screenByName(name) {
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i]
        }
        return null
    }

    function show(name) {
        if (name) {
            shell.probePending = false
            shell.showOnScreen(shell.screenByName(name))
            return
        }

        var mon = Hyprland.focusedMonitor
        if (mon && mon.name) {
            shell.showOnScreen(shell.screenByName(mon.name))
            return
        }

        // Quickshell may not know the focused monitor yet (first open after
        // boot). Ask Hyprland directly instead of falling back to screens[0].
        if (!shell.probePending) {
            shell.probePending = true
            focusProbe.running = true
        }
    }

    function focusedScreen() {
        var mon = Hyprland.focusedMonitor
        if (!mon || !mon.name)
            return null
        return shell.screenByName(mon.name)
    }

    // Keep the hidden window on the monitor the user is actually using, so
    // opening it needs no surface move (which made the transition skip ahead).
    function parkOnFocused() {
        if (shell.showing || shell.pendingShow)
            return
        var scr = shell.focusedScreen()
        if (scr && scr !== shell.targetScreen)
            shell.targetScreen = scr
    }

    function showOnScreen(scr) {
        if (!scr)
            scr = Quickshell.screens[0]
        if (!scr)
            return

        shell.probePending = false
        var moving = shell.targetScreen !== scr
        shell.targetScreen = scr
        parkTimer.stop()

        // A mapped-but-hidden window still has to move between outputs. Give
        // the compositor a moment to relocate the surface before revealing it.
        if (moving && !shell.showing) {
            shell.pendingShow = true
            moveTimer.restart()
        } else {
            shell.pendingShow = false
            shell.showing = true
        }
    }

    function finishProbe(monName) {
        if (!shell.probePending)
            return
        shell.probePending = false
        shell.showOnScreen(shell.screenByName(monName))
    }

    function hide() {
        shell.probePending = false
        shell.pendingShow = false
        moveTimer.stop()
        shell.showing = false
        parkTimer.restart()
    }

    function toggle(name) {
        if (shell.showing)
            shell.hide()
        else
            shell.show(name)
    }

    // Recreate the hidden surface after an output layout change. This is the
    // recovery path for compositor-side resource loss on monitor hotplug.
    function remountWindow() {
        if (shell.showing)
            shell.hide()
        shell.pendingShow = false
        moveTimer.stop()
        parkTimer.stop()
        shell.mounted = false
        remountTimer.restart()
    }

    Process {
        id: focusProbe
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            id: focusProbeOut
        }
        onExited: {
            var monName = ""
            try {
                monName = JSON.parse(focusProbeOut.text.trim()).monitor || ""
            } catch (e) {}
            shell.finishProbe(monName)
        }
    }

    Timer {
        id: moveTimer
        interval: 180
        onTriggered: {
            if (shell.pendingShow) {
                shell.pendingShow = false
                shell.showing = true
            }
        }
    }

    Timer {
        id: parkTimer
        interval: 450
        onTriggered: shell.parkOnFocused()
    }

    Timer {
        id: remountTimer
        interval: 250
        onTriggered: {
            if (Quickshell.screens.length === 0) {
                remountTimer.restart()
                return
            }
            shell.targetScreen = Quickshell.screens[0]
            shell.mounted = true
            parkTimer.restart()
        }
    }

    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { shell.parkOnFocused() }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() { shell.remountWindow() }
    }

    Process {
        id: screenProbe
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            id: screenProbeOut
        }
        onExited: {
            var monName = ""
            try {
                monName = JSON.parse(screenProbeOut.text.trim()).monitor || ""
            } catch (e) {}
            var scr = shell.screenByName(monName)
            if (scr && !shell.showing)
                shell.targetScreen = scr
        }
    }

    Timer {
        interval: 800
        running: true
        onTriggered: screenProbe.running = true
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            shell.toggle()
        }
        function show(): void {
            shell.show()
        }
        function hide(): void {
            shell.hide()
        }
        function toggleOn(name: string): void {
            shell.toggle(name)
        }
        function showOn(name: string): void {
            shell.show(name)
        }
        function sound(): void {
            shell.selectedIndex = 1
            shell.show()
        }
        function network(): void {
            shell.selectedIndex = 3
            shell.show()
        }
        function display(): void {
            shell.selectedIndex = 2
            shell.show()
        }
        function snapTop(): void {
            if (windowLoader.item) windowLoader.item.snapTop()
        }
        function snapCenter(): void {
            if (windowLoader.item) windowLoader.item.snapCenter()
        }
        function snapBottom(): void {
            if (windowLoader.item) windowLoader.item.snapBottom()
        }
        function snapLeft(): void {
            if (windowLoader.item) windowLoader.item.snapLeft()
        }
        function snapRight(): void {
            if (windowLoader.item) windowLoader.item.snapRight()
        }
    }

    LazyLoader {
        id: windowLoader
        active: shell.mounted

        PanelWindow {
            id: root
            screen: shell.targetScreen
            anchors { top: true; left: true; right: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            mask: Region {
                item: root.showing ? backdrop : null
            }

            property bool showing: shell.showing
            property int selectedIndex: shell.selectedIndex

            // Keep the default page loaded while closed so all its items are
            // already rasterized when the card animates in. Other pages are
            // unloaded after the close transition to keep their polling from
            // running in the background; SystemPage pauses its own timers via
            // its `live` property.
            property bool pageActive: shell.showing || shell.selectedIndex === 0
                || pageKeepAlive.running

            Timer {
                id: pageKeepAlive
                interval: Theme.animSlow + 100
            }

            Connections {
                target: shell
                function onShowingChanged() {
                    if (shell.showing) {
                        pageKeepAlive.stop()
                        Qt.callLater(function () { backdrop.forceActiveFocus() })
                    } else {
                        pageKeepAlive.restart()
                        root.searchQuery = ""
                        searchInput.text = ""
                    }
                }
            }

            function show()   { shell.show() }
            function hide()   { shell.hide() }
            function toggle() { shell.toggle() }
            property real cardMargin: 40

            // Use the target screen size instead of the newly created window's
            // size. A fresh layer surface starts at 0x0 and its first resize
            // would otherwise animate the card growing from the top-left
            // corner at the same time as the open transition.
            readonly property real screenW: shell.targetScreen ? shell.targetScreen.width : root.width
            readonly property real screenH: shell.targetScreen ? shell.targetScreen.height : root.height

            property real cardHeightCenter: Math.min(640, screenH - cardMargin * 2)
            property real cardHeightSnapped: cardHeightCenter * 0.6   // 40% smaller when pinned top/bottom
            property real cardHeight: cardHeightCenter
            property real cardCenterY: (screenH - cardHeight) / 2
            property real cardY: cardCenterY

            property real cardWidthCenter: Math.min(980, screenW - cardMargin * 2)
            property real cardWidthSnapped: cardWidthCenter * 0.85    // width when pinned left/right
            property real cardHeightSideSnapped: cardHeightCenter * 1.4   // height when pinned left/right (taller than top/bottom snap)
            property real cardWidth: cardWidthCenter
            property real cardCenterX: (screenW - cardWidth) / 2
            property real cardX: cardCenterX

            function snapTop() {
                cardHeight = cardHeightSnapped
                cardY = cardMargin
            }
            function snapBottom() {
                cardHeight = cardHeightSnapped
                cardY = screenH - cardHeight - cardMargin
            }
            function snapLeft() {
                cardWidth = cardWidthSnapped
                cardHeight = cardHeightSideSnapped
                cardX = cardMargin
                cardY = (screenH - cardHeight) / 2
            }
            function snapRight() {
                cardWidth = cardWidthSnapped
                cardHeight = cardHeightSideSnapped
                cardX = screenW - cardWidth - cardMargin
                cardY = (screenH - cardHeight) / 2
            }
            function snapCenter() {
                cardHeight = cardHeightCenter
                cardWidth = cardWidthCenter
                cardY = (screenH - cardHeight) / 2
                cardX = (screenW - cardWidth) / 2
            }

            PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
            property var sink: Pipewire.defaultAudioSink
            property real pwVolume: (sink && sink.audio) ? sink.audio.volume : 0
            property bool pwMuted: (sink && sink.audio) ? sink.audio.muted : false

            Rectangle {
                id: backdrop
                anchors.fill: parent
                color: "transparent"

                focus: root.showing
                Keys.onEscapePressed: root.hide()

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.hide()
                }
            }

            property var navItems: [
                { name: "System", icon: "󰒓", page: "SystemPage" },
                { name: "Audio", icon: "\uf028", page: "SoundPage" },
                { name: "Display", icon: "\uf108", page: "MonitorsPage" },
                { name: "Network", icon: "\uf1eb", page: "NetworkPage" },
                { name: "Bluetooth", icon: "󰂯", page: "BluetoothPage" },
                { name: "Storage", icon: "󰋊", page: "StoragePage" },
                { name: "Configs", icon: "󰧮",  page: "ConfigsPage" },
                { name: "Themes", icon: "󰉼",  page: "ThemesPage" }
            ]


            // ---- search -----------------------------------------------------------
            property string searchQuery: ""

            // navItems filtered by name; origIndex keeps the real page index
            property var filteredNavItems: {
                var q = searchQuery.trim().toLowerCase()
                var out = []
                for (var i = 0; i < navItems.length; i++) {
                    if (q === "" || navItems[i].name.toLowerCase().indexOf(q) >= 0)
                        out.push({ name: navItems[i].name, icon: navItems[i].icon,
                                   page: navItems[i].page, origIndex: i })
                }
                return out
            }

            Shortcut {
                sequence: "Ctrl+F"
                enabled: root.showing
                onActivated: {
                    searchInput.forceActiveFocus()
                    searchInput.selectAll()
                }
            }

            PerspectivePanel {
                id: card
                x: root.cardX
                y: root.cardY
                width: root.cardWidth
                height: root.cardHeight
                open: root.showing

                Behavior on x {
                    enabled: root.showing
                    NumberAnimation {
                        duration: Theme.animMed
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on y {
                    enabled: root.showing
                    NumberAnimation {
                        duration: Theme.animMed
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on width {
                    enabled: root.showing
                    NumberAnimation {
                        duration: Theme.animMed
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on height {
                    enabled: root.showing
                    NumberAnimation {
                        duration: Theme.animMed
                        easing.type: Easing.OutCubic
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {}
                }
                Rectangle {
                    anchors.fill: parent
                    color: Theme.bg
                    radius: Theme.radius
                    border.color: Theme.accent
                    border.width: 1
                    Rectangle {
                        width: 40
                        height: 2
                        color: Theme.accent2
                        anchors {
                            top: parent.top
                            left: parent.left
                            margins: 14
                        }
                    }

                    Rectangle {
                        width: 2
                        height: 40
                        color: Theme.accent2
                        anchors {
                            top: parent.top
                            left: parent.left
                            margins: 14
                        }
                    }

                    Rectangle {
                        width: 40
                        height: 2
                        color: Theme.accent2
                        anchors {
                            bottom: parent.bottom
                            right: parent.right
                            margins: 14
                        }
                    }

                    Rectangle {
                        width: 2
                        height: 40
                        color: Theme.accent2
                        anchors {
                            bottom: parent.bottom
                            right: parent.right
                            margins: 14
                        }
                    }
                    Rectangle {
                        id: positionHandle

                        width: 150
                        height: 16
                        radius: Theme.radius

                        color: Theme.bg
                        border.color: Theme.accent
                        border.width: 1

                        anchors {
                            top: parent.top
                            horizontalCenter: parent.horizontalCenter
                            topMargin: -8
                        }

                        MouseArea {
                            // Clicking the pill body (not the glyphs) snaps to top.
                            anchors.fill: parent
                            onClicked: root.snapTop()
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 20

                            Text {
                                text: "◀"
                                font.family: Theme.fontFamily
                                font.pixelSize: 7
                                color: Theme.textDim

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: root.snapLeft()
                                }
                            }

                            Text {
                                text: "▲"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.textDim

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: root.snapTop()
                                }
                            }

                            Text {
                                text: "●"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.textDim

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: root.snapCenter()
                                }
                            }

                            Text {
                                text: "▼"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.textDim

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: root.snapBottom()
                                }
                            }

                            Text {
                                text: "▶"
                                font.family: Theme.fontFamily
                                font.pixelSize: 7
                                color: Theme.textDim

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    onClicked: root.snapRight()
                                }
                            }
                        }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: 28
                        spacing: 28

                        Column {
                            id: sidebar
                            width: 130
                            height: parent.height
                            spacing: 12

                            Text {
                                text: " SETTINGS"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 19
                                font.bold: true
                                font.letterSpacing: 4
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Theme.border
                            }

                            Rectangle {
                                id: searchBox
                                width: parent.width
                                height: 28
                                radius: Theme.radius
                                color: Theme.alpha(Theme.text, 0.06)
                                border.width: searchInput.activeFocus ? 1 : 0
                                border.color: Theme.accent

                                Text {
                                    visible: searchInput.text === ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    text: "Search"
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }

                                TextInput {
                                    id: searchInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    clip: true
                                    selectByMouse: true
                                    activeFocusOnTab: true
                                    onTextChanged: root.searchQuery = text
                                    Keys.onEscapePressed: {
                                        if (text !== "") {
                                            text = ""
                                            event.accepted = true
                                        } else {
                                            root.hide()
                                        }
                                    }
                                    Keys.onReturnPressed: {
                                        if (root.filteredNavItems.length > 0)
                                            shell.selectedIndex = root.filteredNavItems[0].origIndex
                                    }
                                }
                            }

                            Flickable {
                                id: sidebarFlickable
                                width: parent.width
                                height: Math.max(0, parent.height - 48 - searchBox.height - 12)
                                contentWidth: width
                                contentHeight: navColumn.height
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: contentHeight > height

                                WheelHandler {
                                    target: sidebarFlickable
                                    property: "contentY"
                                    onActiveChanged: {
                                        if (!active)
                                            sidebarFlickable.returnToBounds()
                                    }
                                }

                                Column {
                                    id: navColumn
                                    width: sidebarFlickable.width
                                    spacing: 4

                                    Repeater {
                                        model: root.filteredNavItems
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: sidebar.width
                                            height: 38
                                            radius: Theme.radius
                                            color: root.selectedIndex === modelData.origIndex
                                                ? Theme.alpha(Theme.accent, 0.12)
                                                : "transparent"
                                            border.width: root.selectedIndex === modelData.origIndex ? 1 : 0
                                            border.color: Theme.accent

                                            Rectangle {
                                                visible: root.selectedIndex === modelData.origIndex
                                                width: 3
                                                height: parent.height - 10
                                                anchors {
                                                    verticalCenter: parent.verticalCenter
                                                    left: parent.left
                                                }
                                                color: Theme.accent2
                                            }

                                            Row {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 16
                                                spacing: 12
                                                height: 20

                                                Text {
                                                    width: 18
                                                    height: parent.height
                                                    verticalAlignment: Text.AlignVCenter
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: modelData.icon
                                                    font.family: Theme.iconFont
                                                    font.pixelSize: 14
                                                    color: root.selectedIndex === modelData.origIndex
                                                        ? Theme.text
                                                        : Theme.textDim
                                                }

                                                Text {
                                                    height: parent.height
                                                    verticalAlignment: Text.AlignVCenter
                                                    text: modelData.name
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 13
                                                    color: root.selectedIndex === modelData.origIndex
                                                        ? Theme.text
                                                        : Theme.textDim
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: shell.selectedIndex = modelData.origIndex
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 1
                            height: parent.height
                            color: Theme.border
                        }

                        Item {
                            width: parent.width - sidebar.width - 29
                            height: parent.height
                            clip: true

                            Loader {
                                id: pageLoader
                                anchors.fill: parent
                                active: root.pageActive
                                source: "SettingsPages/"
                                    + root.navItems[root.selectedIndex].page
                                    + ".qml"
                                opacity: 0
                                Component.onCompleted: opacity = 1
                                onSourceChanged: fadeIn.restart()
                                onLoaded: if (item && item.live !== undefined)
                                    item.live = Qt.binding(function () {
                                        return root.showing
                                    })

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.animMed
                                    }
                                }

                                SequentialAnimation {
                                    id: fadeIn

                                    PropertyAction {
                                        target: pageLoader
                                        property: "opacity"
                                        value: 0
                                    }

                                    NumberAnimation {
                                        target: pageLoader
                                        property: "opacity"
                                        to: 1
                                        duration: Theme.animMed
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
