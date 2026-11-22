import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    // SettingsWindow pauses the samplers while the panel is closed.
    property bool live: true

    property var status: ({})
    property var history: []
    property var powerHistory: []
    property real powerScaleMax: 10
    property string batteryError: ""

    property string governor: "—"
    property string epp: "—"
    property string platformProfile: "—"
    property string ppdState: "—"
    property bool turboKnown: false
    property bool turboOn: false
    property bool turboPending: false
    property string fanRpm: "—"
    property string throttleCount: "—"
    property string swapUse: "—"
    property string cpuTemp: "—"

    property bool limitKnown: false
    property int limitValue: -1
    property bool limitSavePending: false
    property int limitPendingValue: -1
    property string actionError: ""

    property int labelSize: 10
    property int textSize: 12
    property string mono: "JetBrainsMono Nerd Font"
    property int rightMargin: 46

    property string currentTime: ""

    // --- helpers -----------------------------------------------------

    function numberOr(value, fallback) {
        var n = Number(value)
        return isFinite(n) ? n : fallback
    }

    function formatNumber(value, decimals) {
        var n = Number(value)
        if (!isFinite(n)) return "—"
        return n.toFixed(decimals !== undefined ? decimals : 1)
    }

    function percent(value) {
        var n = Number(value)
        return isFinite(n) ? Math.round(n) + "%" : "—"
    }

    function formatMinutes(mins) {
        var n = Number(mins)
        if (!isFinite(n) || n <= 0) return "—"
        if (n >= 90) return Math.floor(n / 60) + " h " + Math.round(n % 60) + " min"
        return Math.round(n) + " min"
    }

    function healthGrade(value) {
        var n = Number(value)
        if (!isFinite(n)) return "—"
        if (n >= 90) return "EXCELLENT"
        if (n >= 80) return "GOOD"
        if (n >= 70) return "FAIR"
        return "POOR"
    }

    function gradeColor(value) {
        var n = Number(value)
        if (!isFinite(n)) return Theme.textDim
        if (n >= 90) return Theme.ok
        if (n >= 80) return Theme.accent
        if (n >= 70) return Theme.accent2
        return Theme.danger
    }

    function stateColor(state) {
        if (state === "Charging") return Theme.ok
        if (state === "Discharging") return Theme.accent
        if (state === "Full") return Theme.accent2
        return Theme.textDim
    }

    function niceScale(max) {
        if (!(max > 0)) return 10
        var pow = Math.pow(10, Math.floor(Math.log(max) / Math.LN10))
        var norm = max / pow
        var nice = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10
        return nice * pow
    }

    function pushPower(value) {
        var w = Number(value)
        if (!isFinite(w)) return
        var values = page.powerHistory.slice()
        values.push(w)
        if (values.length > 60) values.shift()
        page.powerHistory = values

        var peak = 0
        for (var i = 0; i < values.length; i++)
            if (values[i] > peak) peak = values[i]
        page.powerScaleMax = Math.max(5, page.niceScale(peak * 1.2))
    }

    function applyStatus(text) {
        try {
            var data = JSON.parse(text.trim())
            if (!data || data.ok === false) {
                page.batteryError = data && data.error ? data.error : "Battery not detected"
                return
            }
            page.batteryError = ""
            page.status = data
            page.pushPower(data.power_w)

            var supported = data.charge_limit_supported === true
            page.limitKnown = supported
            if (supported && !pSetLimit.running) page.limitValue = Number(data.charge_limit)
            else if (!supported) page.limitValue = -1
        } catch (e) {
            console.warn("Invalid battery status JSON:", e)
        }
    }

    function applyHistory(text) {
        var samples = []
        try {
            var data = JSON.parse(text.trim())
            if (Array.isArray(data)) {
                for (var i = 0; i < data.length; i++) {
                    var item = data[i]
                    if (item && isFinite(Number(item.h)))
                        samples.push(item)
                }
            }
        } catch (e) {
            console.warn("Invalid battery history JSON:", e)
        }
        page.history = samples
    }

    function historyMin() {
        if (page.history.length < 2) return 0
        var min = 100
        for (var i = 0; i < page.history.length; i++)
            if (Number(page.history[i].h) < min) min = Number(page.history[i].h)
        return Math.max(0, Math.floor(min - 2))
    }

    function historyMax() {
        if (page.history.length < 2) return 100
        var max = 0
        for (var i = 0; i < page.history.length; i++)
            if (Number(page.history[i].h) > max) max = Number(page.history[i].h)
        return Math.min(100, Math.max(page.historyMin() + 2, Math.ceil(max + 1)))
    }

    function historyRange() {
        if (page.history.length === 0) return ""
        var first = new Date(Number(page.history[0].t) * 1000)
        var last = new Date(Number(page.history[page.history.length - 1].t) * 1000)
        return Qt.formatDate(first, "dd MMM") + " → " + Qt.formatDate(last, "dd MMM")
    }

    function applyPerformance(text) {
        var lines = text.trim().split("\n")
        if (lines.length >= 9) {
            page.governor = lines[0].trim() || "—"
            page.epp = lines[1].trim() || "—"
            page.platformProfile = lines[2].trim() || "—"
            page.ppdState = lines[3].trim() || "—"

            var noTurbo = lines[4].trim()
            page.turboKnown = noTurbo !== ""
            if (page.turboKnown && !page.turboPending)
                page.turboOn = noTurbo === "0"

            var fan = lines[5].trim()
            page.fanRpm = fan !== "" && fan !== "0" ? fan + " rpm" : "—"
            var throttle = lines[6].trim()
            page.throttleCount = throttle !== "" ? throttle : "—"
            page.swapUse = lines[7].trim() || "none"
            var temp = lines[8].trim()
            page.cpuTemp = temp !== "" ? temp + "°C" : "—"
        }
    }

    function drawSparkline(ctx, samples, key, minValue, maxValue, color, fill) {
        var w = ctx.canvas.width
        var h = ctx.canvas.height
        ctx.clearRect(0, 0, w, h)

        if (!samples || samples.length < 2) return

        var min = isFinite(minValue) ? minValue : 0
        var max = isFinite(maxValue) && maxValue > min ? maxValue : min + 1
        var step = w / (samples.length - 1)

        ctx.beginPath()
        ctx.moveTo(0, h)
        for (var i = 0; i < samples.length; i++) {
            var value = Number(samples[i][key])
            if (!isFinite(value)) value = min
            var y = h - Math.max(0, Math.min(1, (value - min) / (max - min))) * h
            ctx.lineTo(i * step, y)
        }
        ctx.lineTo(w, h)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.10)
        ctx.fill()

        ctx.beginPath()
        for (var j = 0; j < samples.length; j++) {
            var v = Number(samples[j][key])
            if (!isFinite(v)) v = min
            var yy = h - Math.max(0, Math.min(1, (v - min) / (max - min))) * h
            if (j) ctx.lineTo(j * step, yy)
            else ctx.moveTo(j * step, yy)
        }
        ctx.strokeStyle = color
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.stroke()
    }

    function setChargeLimit(value) {
        if (!page.limitKnown || pSetLimit.running) return
        if (value !== 60 && value !== 80 && value !== 100) return

        page.actionError = ""
        pSetLimit.pendingValue = value
        pSetLimit.stdinEnabled = true
        pSetLimit.running = true
    }

    function toggleTurbo() {
        if (!page.turboKnown || pSetTurbo.running) return

        var wanted = !page.turboOn
        page.actionError = ""
        page.turboPending = true
        pSetTurbo.pendingValue = wanted ? 0 : 1
        pSetTurbo.stdinEnabled = true
        pSetTurbo.running = true
    }

    // Persists the user's choices so PowerAgent can re-apply them at the next
    // shell start. Existing keys are preserved: the page may save one control
    // before the other one has been sampled.
    function saveState() {
        var data = {}
        try {
            var current = JSON.parse(powerStore.text())
            if (current && typeof current === "object") data = current
        } catch (e) {}
        if (page.turboKnown) data.turbo = page.turboOn
        if (page.limitKnown) data.chargeLimit = page.limitValue
        powerStore.setText(JSON.stringify(data))
    }

    // --- components ---------------------------------------------------

    component SmallButton: Rectangle {
        id: button

        property string label: ""
        property bool selected: false
        property bool buttonEnabled: true

        signal clicked()

        height: 28
        radius: Theme.radius
        opacity: buttonEnabled ? 1.0 : 0.35
        color: selected
            ? Theme.alpha(Theme.accent, 0.10)
            : (mouse.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "transparent")
        border.width: 1
        border.color: selected || mouse.containsMouse ? Theme.accent : Theme.border

        Text {
            anchors.centerIn: parent
            text: button.label
            color: button.selected ? Theme.accent : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: button.buttonEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component Sparkline: Item {
        id: graph

        property var samples: []
        property string valueKey: "h"
        property real minValue: 0
        property real maxValue: 100
        property color lineColor: Theme.accent
        property string topLabel: ""
        property string bottomLabel: ""

        onSamplesChanged: canvas.requestPaint()

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Theme.border
        }

        Repeater {
            model: [0.25, 0.5, 0.75]

            Rectangle {
                y: graph.height * modelData
                width: graph.width
                height: 1
                color: Theme.border
                opacity: 0.35
            }
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            anchors.margins: 6
            onPaint: page.drawSparkline(getContext("2d"), graph.samples,
                graph.valueKey, graph.minValue, graph.maxValue, graph.lineColor, true)
        }

        Text {
            text: graph.topLabel
            anchors { top: parent.top; right: parent.right; margins: 5 }
            color: Theme.text
            opacity: 0.35
            font.family: page.mono
            font.pixelSize: 8
        }

        Text {
            text: graph.bottomLabel
            anchors { bottom: parent.bottom; right: parent.right; margins: 5 }
            color: Theme.text
            opacity: 0.35
            font.family: page.mono
            font.pixelSize: 8
        }
    }

    component Toggle: Item {
        id: control

        property bool checked: false
        property bool interactive: true

        signal toggled()

        width: 48
        height: 24
        opacity: interactive ? 1.0 : 0.4

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: control.checked ? Theme.alpha(Theme.accent, 0.25) : Theme.trackBg
            border.width: 1
            border.color: control.checked ? Theme.accent : Theme.border

            Rectangle {
                width: 16
                height: 16
                radius: width / 2
                y: 3
                x: control.checked ? parent.width - width - 3 : 3
                color: control.checked ? Theme.accent : Theme.textDim

                Behavior on x {
                    NumberAnimation { duration: Theme.animFast }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: control.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: control.toggled()
        }
    }

    // --- processes ----------------------------------------------------

    Process {
        id: pStatus
        command: ["sh", "-c", "exec \"$HOME\"/.config/quickshell/scripts/battery-health.py status"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.applyStatus(text) }
        stderr: StdioCollector {}
    }

    Process {
        id: pHistory
        command: ["sh", "-c", "exec \"$HOME\"/.config/quickshell/scripts/battery-health.py history --days 180 --limit 720"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.applyHistory(text) }
        stderr: StdioCollector {}
    }

    Process {
        id: pRecord
        command: ["sh", "-c", "exec \"$HOME\"/.config/quickshell/scripts/battery-health.py record"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: pHistory.running = true
    }

    Process {
        id: pPerformance
        command: ["sh", "-c", "exec \"$HOME\"/.config/quickshell/scripts/power-info.sh"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.applyPerformance(text) }
        stderr: StdioCollector {}
    }

    Process {
        id: pSetLimit
        property int pendingValue: -1

        command: ["sudo", "-n", "/usr/bin/tee", "/sys/class/power_supply/BAT0/charge_control_end_threshold"]
        stdinEnabled: false
        running: false

        onStarted: {
            write(pendingValue + "\n")
            stdinEnabled = false
        }

        onExited: function(exitCode) {
            var value = pendingValue
            pendingValue = -1
            if (exitCode === 0) {
                // Read the threshold back before trusting the write: the EC can
                // accept the sysfs write and still clamp or ignore the value.
                page.limitPendingValue = value
                page.limitSavePending = true
                pReadLimit.running = true
            } else {
                page.actionError = "Charge limit write failed — run scripts/install-power-sudoers.sh."
            }
        }
    }

    Process {
        id: pReadLimit
        command: ["cat", "/sys/class/power_supply/BAT0/charge_control_end_threshold"]
        stdout: StdioCollector {
            onStreamFinished: {
                var value = parseInt(text.trim(), 10)
                if (isFinite(value)) {
                    page.limitValue = value
                    if (page.limitPendingValue >= 0 && value !== page.limitPendingValue)
                        page.actionError = "The EC kept " + value + "% instead of "
                            + page.limitPendingValue + "%."
                }
                page.limitPendingValue = -1
                page.limitSavePending = false
                page.saveState()
                pStatus.running = true
            }
        }
        stderr: StdioCollector {}
    }

    Process {
        id: pSetTurbo
        property int pendingValue: -1

        command: ["sudo", "-n", "/usr/bin/tee", "/sys/devices/system/cpu/intel_pstate/no_turbo"]
        stdinEnabled: false
        running: false

        onStarted: {
            write(pendingValue + "\n")
            stdinEnabled = false
        }

        onExited: function(exitCode) {
            var value = pendingValue
            pendingValue = -1
            page.turboPending = false
            if (exitCode === 0 && value >= 0) {
                page.turboOn = value === 0
                page.saveState()
                pPerformance.running = true
            } else {
                page.actionError = "Turbo write failed — run scripts/install-power-sudoers.sh."
            }
        }
    }

    FileView {
        id: powerStore
        path: Quickshell.env("HOME") + "/.config/quickshell/state/power.json"
        printErrors: false
    }

    // --- timers -------------------------------------------------------

    Timer {
        interval: 3000
        running: page.live
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            page.currentTime = Qt.formatTime(new Date(), "HH:mm:ss")
            pStatus.running = true
        }
    }

    Timer {
        interval: 5000
        running: page.live
        triggeredOnStart: true
        repeat: true
        onTriggered: pPerformance.running = true
    }

    Timer {
        interval: 60000
        running: page.live
        repeat: true
        onTriggered: pHistory.running = true
    }

    Component.onCompleted: {
        page.currentTime = Qt.formatTime(new Date(), "HH:mm:ss")
        pRecord.running = true
        pPerformance.running = true
    }

    // --- UI -----------------------------------------------------------

    Flickable {
        id: scrollArea

        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        WheelHandler {
            onWheel: function(event) {
                var delta = event.angleDelta.y
                if (delta !== 0) {
                    scrollArea.contentY = Math.max(
                        0,
                        Math.min(scrollArea.contentHeight - scrollArea.height, scrollArea.contentY - delta)
                    )
                }
                event.accepted = true
            }
        }

        Column {
            id: contentColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: page.rightMargin

            spacing: 18

            Text {
                text: "POWER"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 19
                font.letterSpacing: 3
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            Text {
                visible: page.batteryError !== ""
                text: "Battery: " + page.batteryError
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: page.textSize
            }

            // ---- battery hero -----------------------------------------
            Rectangle {
                width: parent.width
                height: 148
                radius: Theme.radius
                color: "transparent"
                border.color: Theme.border
                visible: page.batteryError === ""

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 24

                    Column {
                        width: (parent.width - 24) * 0.52
                        spacing: 8

                        Row {
                            spacing: 12

                            Text {
                                text: page.percent(page.status.capacity_pct)
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 40
                                font.bold: true
                            }

                            Column {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                spacing: 2

                                Text {
                                    text: (page.status.status || "Unknown").toUpperCase()
                                    color: page.stateColor(page.status.status)
                                    font.family: page.mono
                                    font.pixelSize: 10
                                    font.letterSpacing: 2
                                }

                                Text {
                                    text: (page.status.ac_online ? "AC connected" : "On battery")
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 8
                            radius: 4
                            color: Theme.trackBg

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1,
                                    page.numberOr(page.status.capacity_pct, 0) / 100))
                                height: parent.height
                                radius: parent.radius
                                color: page.numberOr(page.status.capacity_pct, 100) <= 15
                                    ? Theme.danger : Theme.accent
                            }
                        }

                        Text {
                            text: page.formatNumber(page.status.power_w, 2) + " W · "
                                + page.formatNumber(page.status.voltage_v, 2) + " V · "
                                + page.formatNumber(page.status.current_a, 2) + " A"
                            color: Theme.textDim
                            font.family: page.mono
                            font.pixelSize: 10
                        }

                        Text {
                            text: page.status.status === "Charging"
                                ? "Full in " + page.formatMinutes(page.status.time_to_full_min)
                                : page.status.status === "Discharging"
                                    ? "Empty in " + page.formatMinutes(page.status.time_to_empty_min)
                                    : "Plugged in"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: page.textSize
                        }
                    }

                    Column {
                        width: parent.width - (parent.width - 24) * 0.52 - 24
                        spacing: 6

                        Text {
                            text: "BATTERY HEALTH"
                            color: Theme.textDim
                            font.family: page.mono
                            font.pixelSize: page.labelSize
                            font.letterSpacing: 2
                        }

                        Row {
                            spacing: 10

                            Text {
                                text: page.percent(page.status.health_pct)
                                color: page.gradeColor(page.status.health_pct)
                                font.family: Theme.fontFamily
                                font.pixelSize: 32
                                font.bold: true
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                text: page.healthGrade(page.status.health_pct)
                                color: page.gradeColor(page.status.health_pct)
                                font.family: page.mono
                                font.pixelSize: 10
                                font.letterSpacing: 2
                            }
                        }

                        Text {
                            text: "Wear " + page.formatNumber(page.status.wear_pct, 1) + "% · "
                                + (page.status.cycles !== null && page.status.cycles !== undefined
                                    ? page.status.cycles + " cycles" : "cycles —")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: page.textSize
                        }

                        Text {
                            text: page.formatNumber(page.status.charge_full_ah, 2) + " / "
                                + page.formatNumber(page.status.charge_full_design_ah, 2) + " Ah · "
                                + page.formatNumber(page.status.energy_full_wh, 1) + " Wh"
                            color: Theme.textDim
                            font.family: page.mono
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // ---- charge limit -----------------------------------------
            Column {
                width: parent.width
                spacing: 8
                visible: page.limitKnown

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        text: "CHARGE LIMIT"
                        color: Theme.textDim
                        font.family: page.mono
                        font.pixelSize: page.labelSize
                        font.letterSpacing: 2
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: page.limitValue >= 0 ? page.limitValue + "%" : "—"
                        color: Theme.accent2
                        font.family: Theme.fontFamily
                        font.pixelSize: page.textSize
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: 8

                    Repeater {
                        model: [60, 80, 100]

                        delegate: SmallButton {
                            required property var modelData
                            width: 76
                            label: modelData + "%"
                            selected: page.limitValue === modelData
                            buttonEnabled: !pSetLimit.running
                            onClicked: page.setChargeLimit(modelData)
                        }
                    }
                }

                Text {
                    text: "ASUS Battery Health Charging. 60–80% slows wear; 100% keeps full runtime."
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            Text {
                visible: page.actionError !== ""
                text: page.actionError
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            // ---- live power draw ---------------------------------------
            Column {
                width: parent.width
                spacing: 6
                visible: page.batteryError === ""

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        text: "BATTERY POWER · LAST 3 MIN"
                        color: Theme.textDim
                        font.family: page.mono
                        font.pixelSize: page.labelSize
                        font.letterSpacing: 2
                    }

                    Text {
                        text: page.formatNumber(page.status.power_w, 2) + " W"
                        color: Theme.text
                        font.family: page.mono
                        font.pixelSize: page.textSize
                    }
                }

                Sparkline {
                    width: parent.width
                    height: 54
                    samples: page.powerHistory
                    valueKey: "w"
                    minValue: 0
                    maxValue: page.powerScaleMax
                    lineColor: Theme.accent
                    topLabel: page.formatNumber(page.powerScaleMax, 0) + " W"
                    bottomLabel: "0 W"
                }
            }

            // ---- health history ----------------------------------------
            Column {
                width: parent.width
                spacing: 6

                Row {
                    width: parent.width
                    spacing: 10

                    Text {
                        text: "HEALTH HISTORY"
                        color: Theme.textDim
                        font.family: page.mono
                        font.pixelSize: page.labelSize
                        font.letterSpacing: 2
                    }

                    Text {
                        text: page.historyRange()
                        color: Theme.text
                        font.family: page.mono
                        font.pixelSize: 10
                    }
                }

                Sparkline {
                    width: parent.width
                    height: 54
                    samples: page.history
                    valueKey: "h"
                    minValue: page.historyMin()
                    maxValue: page.historyMax()
                    lineColor: page.gradeColor(page.status.health_pct)
                    topLabel: page.history.length >= 2 ? page.historyMax() + "%" : ""
                    bottomLabel: page.history.length >= 2 ? page.historyMin() + "%" : ""
                }

                Text {
                    text: page.history.length < 2
                        ? "Collecting samples — one is saved every 6 h while the session is running."
                        : page.history.length + " samples · one every 6 h while the session is running"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // ---- performance -------------------------------------------
            Text {
                text: "PERFORMANCE"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.letterSpacing: 2
            }

            Row {
                width: parent.width
                spacing: 12

                Text {
                    text: "TURBO BOOST"
                    color: Theme.textDim
                    font.family: page.mono
                    font.pixelSize: page.labelSize
                    font.letterSpacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                }

                Toggle {
                    checked: page.turboOn
                    interactive: page.turboKnown && !page.turboPending
                    onToggled: page.toggleTurbo()
                }

                Text {
                    text: !page.turboKnown ? "not available"
                        : page.turboOn ? "enabled · max clocks, more heat and drain"
                        : "disabled · lower peak power, less heat"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                width: parent.width
                text: "PROFILE " + page.platformProfile.toUpperCase()
                    + " · GOVERNOR " + page.governor
                    + " · EPP " + page.epp
                    + " · PPD " + page.ppdState
                color: Theme.text
                font.family: page.mono
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "THERMALS " + page.cpuTemp
                    + " · FAN " + page.fanRpm
                    + " · PACKAGE THROTTLE " + page.throttleCount + " events"
                color: Theme.textDim
                font.family: page.mono
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "SWAP " + page.swapUse + (page.swapUse === "none" ? " (no zram detected)" : "")
                color: page.swapUse === "none" ? Theme.accent2 : Theme.textDim
                font.family: page.mono
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Item {
                width: 1
                height: 6
            }
        }
    }

    Text {
        id: clock

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: page.rightMargin

        text: page.currentTime
        color: Theme.text
        font.family: page.mono
        font.pixelSize: 18
        font.letterSpacing: 1
    }
}
