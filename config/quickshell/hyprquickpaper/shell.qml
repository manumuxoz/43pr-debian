import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell.Wayland

PanelWindow {
    id: main

    property int speed: 5000
    property int animDuration: 260
    property real zoomScale: 0.8
    property real edgeScale: 0.3
    property real skewFactor: 0
    property real baseSpacing: 0
    property real edgeSpacing: 80
    property int startPosition: 4
    property bool shadowEnabled: true
    property color shadowColor: "#000000"
    property real shadowOpacity: 0.4
    property real shadowBlur: 0.45
    property real shadowX: 6
    property real shadowY: 6
    property string wallpaperPath: configs.wallpaper_path.replace("$HOME", Quickshell.env("HOME"))
    property string cachePath: configs.cache_path.replace("$HOME", Quickshell.env("HOME"))

    property bool showEmpty: false
    readonly property bool looksEmpty: wallpaperPath !== ""
                                       && folderModel.status === FolderListModel.Ready
                                       && folderModel.count === 0

    onLooksEmptyChanged: {
        if (looksEmpty) {
            emptyDelay.restart()
        } else {
            emptyDelay.stop()
            showEmpty = false
        }
    }

    // Open on the monitor indicated by launch.sh (the focused one when the
    // keybind was pressed); fall back to the first screen.
    screen: main.monitorFor(Quickshell.env("HYPRPAPER_MON"))

    function monitorFor(name) {
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i]
        }
        return screens.length > 0 ? screens[0] : null
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    focusable: true
    aboveWindows: true
    exclusionMode: "Ignore"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Component.onCompleted: Quickshell.execDetached(["bash", Quickshell.shellPath("cache.sh"), Quickshell.shellDir])

    // Pressing the keybind again while the picker is open closes it:
    // launch.sh calls this and exits when an instance is already running.
    IpcHandler {
        target: "hyprquickpaper"
        function close() { Qt.quit() }
    }

    FileView {
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: configs
            property string wallpaper_path
            property string cache_path
            property int number_of_pictures
            property string border_color
        }
    }

    FolderListModel {
        id: folderModel
        // While config.json is still loading, wallpaperPath is empty: an empty
        // folder would make the model list the process working directory.
        folder: main.wallpaperPath !== "" ? "file://" + main.wallpaperPath : "file://" + Quickshell.shellDir
        showDirs: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        sortField: FolderListModel.Name
    }

    // Control is keyboard-only now: any click just closes the picker.
    MouseArea {
        id: outsideClickArea
        anchors.fill: parent
        z: 0
        onClicked: Qt.quit()
    }

    Timer {
        id: emptyDelay
        interval: 300
        onTriggered: main.showEmpty = main.looksEmpty
    }

    Column {
        id: emptyState
        anchors.centerIn: parent
        spacing: 10
        z: 2
        visible: main.showEmpty

        Text {
            text: "No wallpapers found"
            color: "#ffffff"
            font.pixelSize: 22
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "Add images to:"
            color: "#aaaaaa"
            font.pixelSize: 13
            anchors.horizontalCenter: parent.horizontalCenter
        }

        TextEdit {
            id: pathText
            text: main.wallpaperPath
            color: "#dddddd"
            font.pixelSize: 14
            readOnly: true
            selectByMouse: true
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }

    ListView {
        id: list
        width: parent.width
        height: 500
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        z: 1
        focus: true
        // Three copies of the list; the middle one is the one on screen. When
        // the selection leaves the middle copy we shift the content by exactly
        // one period (realCount * step). Since every tile repeats with that
        // period, the shift is pixel-identical and can even happen mid
        // animation: that is what makes the strip circular.
        readonly property int copies: 3
        model: folderModel.count * copies
        interactive: false
        orientation: ListView.Horizontal
        spacing: 0
        clip: true
        // Large enough to keep every delegate (all three copies) alive, so
        // wrapping never has to create delegates in the middle of an animation.
        cacheBuffer: list.width * 4
        boundsBehavior: Flickable.StopAtBounds
        // We implement arrow-key navigation ourselves. By default
        // keyNavigationEnabled is bound to `interactive` (true), so the built-in
        // navigation would move the view at the same time as our handler.
        keyNavigationEnabled: false

        readonly property int realCount: folderModel.count
        property int selectedIndex: realCount + main.startPosition
        readonly property real tileWidth: width / configs.number_of_pictures - 10
        readonly property real viewportCenterX: width / 2
        readonly property real step: tileWidth + main.baseSpacing
        readonly property real sideMargin: Math.max(0, viewportCenterX - tileWidth / 2)
        property bool ready: false
        property bool userMoved: false
        property bool animating: false
        property bool teleporting: false

        leftMargin: sideMargin
        rightMargin: sideMargin

        // Center the given index: use the delegate's real content position
        // instead of i*step - sideMargin math, because after heavy model
        // churn the view sometimes lays all delegates out with a constant
        // offset. Falls back to the view's own positioning if the delegate
        // is not instantiated yet.
        function ensureVisibleAnimated(i) {
            const it = itemAtIndex(i)
            if (it) contentX = it.x - sideMargin
            else positionViewAtIndex(i, ListView.Center)
        }

        function centerOnStart() {
            const n = realCount
            if (userMoved || n <= 0 || configs.number_of_pictures <= 0) return
            const sp = ((main.startPosition % n) + n) % n
            // Apply the starting position instantly instead of animating from
            // a stale position while the window is still being laid out. If the
            // view clamps the value because the content is not fully built yet,
            // onContentWidthChanged below re-applies it.
            ready = false
            selectedIndex = n + sp
            // Instant placement (ready=false disables the Behavior); it is
            // re-applied while the view keeps building until the user takes
            // over with the keys.
            ensureVisibleAnimated(selectedIndex)
            ready = true
        }

        function activateCurrent() {
            if (!ready || realCount <= 0) return
            const realIndex = selectedIndex % realCount
            Quickshell.execDetached(["bash", Quickshell.shellPath("commands.sh"), folderModel.get(realIndex, "filePath")])
            Qt.quit()
        }

        // Move the selection to any virtual index, wrapping circularly. The
        // wrap jumps contentX a whole period (selectedIndex by realCount) while
        // the Behavior is disabled: because every tile repeats with that
        // period, the frame is identical, even in the middle of an animation.
        function moveTo(i) {
            if (realCount <= 0) return
            userMoved = true
            const n = realCount
            const period = n * step
            let shift = 0
            while (i >= 2 * n) { i -= n; shift += period }
            while (i < n) { i += n; shift -= period }
            if (shift !== 0) {
                teleporting = true
                contentX -= shift
                teleporting = false
            }
            selectedIndex = i
            ensureVisibleAnimated(selectedIndex)
        }

        function moveSelection(delta) {
            moveTo(selectedIndex + delta)
        }

        onCountChanged: centerOnStart()
        // While the content is still being built, contentWidth keeps growing
        // and a centering attempt can be clamped by the view (leaving the
        // strip off-centre with no further trigger). Re-apply the starting
        // position on every growth until the user takes over with the keys.
        onContentWidthChanged: if (!userMoved) Qt.callLater(centerOnStart)
        // Deferred: when width changes, step/sideMargin bindings may not be
        // re-evaluated yet inside this handler (stale values => wrong center).
        onWidthChanged: Qt.callLater(centerOnStart)
        Component.onCompleted: forceActiveFocus()

        Connections {
            target: configs
            function onNumber_of_picturesChanged() { Qt.callLater(list.centerOnStart) }
        }

        Behavior on contentX {
            // Disabled during the invisible period jump that implements the
            // circular wrap (and while a drag is in progress).
            enabled: list.ready && !list.moving && !list.teleporting
            NumberAnimation {
                id: anim
                duration: main.animDuration
                easing.type: Easing.OutCubic
                onRunningChanged: list.animating = running
            }
        }

        delegate: Item {
            id: delegateItem
            width: list.tileWidth
            height: 500

            // The model is the list repeated `copies` times: map the virtual
            // index back to a real wallpaper.
            readonly property int realIndex: index % Math.max(1, list.realCount)
            readonly property string fileName: folderModel.get(realIndex, "fileName") ?? ""

            property bool active: index === list.selectedIndex
            readonly property real baseWidth: list.tileWidth
            readonly property real baseCenterX: x - list.contentX + baseWidth / 2
            readonly property real distance: Math.abs(baseCenterX - list.viewportCenterX)
            readonly property real fraction: Math.min(1, distance / list.viewportCenterX)
            readonly property real compression: { const t = fraction; return t * t * t * t }
            readonly property real edgeOffset: {
                const amount = main.edgeSpacing * compression
                return baseCenterX < list.viewportCenterX ? amount : -amount
            }
            readonly property real scaleFactor: {
                const t = 1 - fraction * fraction * (3 - 2 * fraction)
                return main.edgeScale + (main.zoomScale - main.edgeScale) * t
            }

            Item {
                id: content
                anchors.verticalCenter: parent.verticalCenter
                width: delegateItem.baseWidth * delegateItem.scaleFactor
                height: delegateItem.height * Math.min(1, delegateItem.scaleFactor)
                x: (delegateItem.baseWidth - width) / 2 + delegateItem.edgeOffset

                Image {
                    id: shadowImage
                    x: main.shadowX
                    y: main.shadowY
                    width: parent.width
                    height: parent.height
                    source: img.source
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    visible: main.shadowEnabled
                    opacity: main.shadowOpacity
                    layer.enabled: true
                    layer.effect: MultiEffect { brightness: -1; blurEnabled: true; blur: main.shadowBlur }
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, main.skewFactor, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                }

                Text {
                    id: alt
                    text: ""
                    color: configs.border_color
                    anchors.centerIn: parent
                    font.pixelSize: 16
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, main.skewFactor, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                }

                Image {
                    id: img
                    anchors.fill: parent
                    opacity: 0.95
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    source: "file://" + main.cachePath + fileName
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, main.skewFactor, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }

                    Timer {
                        id: retryTimer
                        interval: 1000
                        repeat: false
                        onTriggered: { const s = img.source; img.source = ""; img.source = s }
                    }

                    onStatusChanged: {
                        if (status === Image.Error) { alt.text = "Caching"; retryTimer.start() }
                    }
                }

                Rectangle {
                    z: 10
                    anchors.fill: parent
                    visible: delegateItem.active
                    color: "transparent"
                    border.width: 2
                    border.color: configs.border_color
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, main.skewFactor, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                }
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                moveSelection(-1)
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                moveSelection(1)
            } else if (event.key === Qt.Key_PageUp) {
                moveSelection(-5)
            } else if (event.key === Qt.Key_PageDown) {
                moveSelection(5)
            } else if (event.key === Qt.Key_Home) {
                moveTo(list.realCount)
            } else if (event.key === Qt.Key_End) {
                moveTo(2 * list.realCount - 1)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                activateCurrent()
            } else if (event.key === Qt.Key_W || event.key === Qt.Key_Escape) {
                Qt.quit()
            } else {
                return
            }
            event.accepted = true
        }
    }
}