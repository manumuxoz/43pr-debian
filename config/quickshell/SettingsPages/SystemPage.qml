import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page

    property string homeDir: ""
    property string uptime: "..."
    property string os: "..."
    property string wm: "Hyprland"
    property string cpu: "Loading..."
    property string gpu: "Loading..."
    property string memory: "Loading..."
    property string ramSpeed: "—"

    property real cpuUsage: 0
    property real gpuUsage: 0
    property real memoryUsage: 0

    property string cpuTemp: "—"
    property string gpuTemp: "—"
    property string cpuFreq: "—"
    property string cpuGovernor: "—"
    property string gpuFreq: "—"
    property int nproc: 0

    property var cpuHistory: []
    property var gpuHistory: []
    property var memoryHistory: []
    property var loadHistory: []
    property var netHistory: []

    property var cpuPrev: null
    property var netPrev: null

    property string loadText: "— · — · —"
    property real loadUsage: 0
    property real netDown: 0
    property real netUp: 0
    property real netScaleMax: 100
    property string wifiSignal: "—"
    property string wifiLevel: "—"

    property string batteryText: "…"
    property string batteryHealthText: "…"

    property string tempNvme: "—"
    property string tempWifi: "—"
    property string tempAcpi: "—"

    property int hardwareLabelSize: 12
    property int hardwareTextSize: 12
    property string mono: "JetBrainsMono Nerd Font"
    property int rightMargin: 46

    property string currentTime: ""

    // --- helpers -----------------------------------------------------

    // Appends one sample to the named history, keeping the last 60 points.
    function pushHistory(value, type) {
        var history = page[type + "History"].slice()
        history.push(value)
        if (history.length > 60) history.shift()
        page[type + "History"] = history
    }

    // Pushes `value` (0-100) onto the named history ("cpu"/"gpu"/"memory")
    // and updates the matching *Usage property. HardwareGraph repaints
    // itself via onHistoryChanged, so no manual requestPaint() is needed.
    function updateGraph(value, type) {
        value = parseFloat(value)
        if (isNaN(value)) return
        value = Math.max(0, Math.min(100, value))

        page[type + "Usage"] = value
        pushHistory(value, type)
    }

    function updateCpuFromStat(value) {
        var p = value.trim().split(/\s+/)
        if (p.length < 5) return

        var user = Number(p[1])
        var nice = Number(p[2])
        var system = Number(p[3])
        var idle = Number(p[4])
        var iowait = Number(p[5] || 0)
        var irq = Number(p[6] || 0)
        var softirq = Number(p[7] || 0)
        var steal = Number(p[8] || 0)

        var idleTime = idle + iowait
        var total = user + nice + system + idle + iowait + irq + softirq + steal

        if (cpuPrev !== null) {
            var totalDelta = total - cpuPrev.total
            var idleDelta = idleTime - cpuPrev.idle

            if (totalDelta > 0)
                updateGraph(100 * (1 - idleDelta / totalDelta), "cpu")
        }

        cpuPrev = { total: total, idle: idleTime }
    }

    function formatMemory(kb) {
        var gb = kb / 1024 / 1024
        return gb >= 1 ? gb.toFixed(1) + " GiB" : Math.round(kb / 1024) + " MiB"
    }

    function updateMemoryFromStat(value) {
        var total = 0
        var available = 0
        var lines = value.trim().split("\n")

        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].trim().split(/\s+/)

            if (parts[0] === "MemTotal:")
                total = Number(parts[1])
            else if (parts[0] === "MemAvailable:")
                available = Number(parts[1])
        }

        if (total <= 0) return

        var used = total - available
        updateGraph((used / total) * 100, "memory")
        page.memory = formatMemory(used) + " / " + formatMemory(total)
    }

    function formatTemp(value) {
        var temp = parseFloat(value.trim())
        return isNaN(temp) ? "—" : Math.round(temp) + "°C"
    }

    // Builds a `sensors | awk` one-liner that prints the first temperature
    // found on any line matching one of `patterns`.
    function sensorTempCmd(patterns) {
        return "sensors 2>/dev/null | awk '/" + patterns.join("|") +
            "/ {for(i=1;i<=NF;i++) if($i ~ /\\+?[0-9]+(\\.[0-9]+)?°C/) " +
            "{gsub(/[+°C]/, \"\", $i); print $i; exit}}'"
    }

    function formatMilliTemp(value) {
        var temp = parseFloat(value.trim())
        return isNaN(temp) ? "—" : Math.round(temp / 1000) + "°C"
    }

    function formatSpeed(kbps) {
        if (!(kbps > 0.5)) return "0 KB/s"
        if (kbps < 1000) return Math.round(kbps) + " KB/s"
        return (kbps / 1024).toFixed(1) + " MB/s"
    }

    function formatMinutes(mins) {
        if (mins >= 90) return Math.floor(mins / 60) + " h " + Math.round(mins % 60) + " min"
        return Math.round(mins) + " min"
    }

    // Rounds `max` up to a friendly graph ceiling (1/2/5 * 10^n).
    function niceScale(max) {
        if (!(max > 0)) return 100

        var pow = Math.pow(10, Math.floor(Math.log(max) / Math.LN10))
        var norm = max / pow
        var nice = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10
        return nice * pow
    }

    function updateLoadFromFile(text) {
        var p = text.trim().split(/\s+/)
        if (p.length < 4) return

        var l1 = Number(p[0])
        page.loadText = l1.toFixed(2) + " · " + Number(p[1]).toFixed(2) + " · " + Number(p[2]).toFixed(2)

        if (page.nproc > 0 && !isNaN(l1))
            updateGraph(l1 / page.nproc * 100, "load")
    }

    function updateFreqs(text) {
        var lines = text.trim().split("\n")
        if (lines.length < 3) return

        var ghz = parseFloat(lines[0])
        page.cpuFreq = isNaN(ghz) ? "—" : ghz.toFixed(2) + " GHz"
        page.cpuGovernor = lines[1].trim() || "—"

        var mhz = parseFloat(lines[2])
        page.gpuFreq = isNaN(mhz) ? "—" : mhz > 0 ? (mhz / 1000).toFixed(2) + " GHz" : "idle"
    }

    // wlo1 byte counters; rates are derived between two consecutive samples.
    function updateNetFromCounters(text) {
        var lines = text.trim().split("\n")
        if (lines.length < 2) return

        var rx = Number(lines[0])
        var tx = Number(lines[1])
        if (isNaN(rx) || isNaN(tx)) return

        var now = Date.now()
        if (netPrev !== null) {
            var dt = (now - netPrev.t) / 1000
            if (dt > 0 && rx >= netPrev.rx && tx >= netPrev.tx) {
                page.netDown = (rx - netPrev.rx) / dt / 1024
                page.netUp = (tx - netPrev.tx) / dt / 1024
                pushHistory(page.netDown + page.netUp, "net")

                var max = 0
                for (var i = 0; i < page.netHistory.length; i++)
                    if (page.netHistory[i] > max) max = page.netHistory[i]
                page.netScaleMax = niceScale(max * 1.1)
            }
        }
        netPrev = { rx: rx, tx: tx, t: now }
    }

    function updateWifi(text) {
        var p = text.trim().split(/\s+/)
        if (p.length < 2) return

        page.wifiSignal = p[0]
        page.wifiLevel = p[1] + " dBm"
    }

    function batteryTime(charge, full, amps, status) {
        if (amps < 0.01) return "—"

        var hours = -1
        if (status === "Discharging") hours = (charge / 1e6) / amps
        else if (status === "Charging") hours = Math.max(0, ((full - charge) / 1e6) / amps)
        if (hours < 0) return "—"

        return formatMinutes(hours * 60)
    }

    function updateBattery(text) {
        var l = text.trim().split("\n")
        if (l.length < 8) return

        var level = parseInt(l[0], 10)
        var status = l[1].trim()
        var volts = Number(l[2]) / 1e6
        var amps = Math.abs(Number(l[3])) / 1e6
        var charge = Number(l[4])
        var full = Number(l[5])
        var design = Number(l[6])
        var cycles = l[7].trim()

        page.batteryText = level + "% · " + status.toLowerCase() +
            (amps > 0.01 ? " · " + (volts * amps).toFixed(1) + " W" : "") +
            " · " + batteryTime(charge, full, amps, status)
        page.batteryHealthText = (design > 0 ? Math.round(full / design * 100) + "%" : "—") +
            " · " + cycles + " cycles · " + (full / 1e6).toFixed(2) + "/" + (design / 1e6).toFixed(2) + " Ah"
    }

    function updateClock() {
        page.currentTime = Qt.formatTime(new Date(), "HH:mm:ss")
    }

    function drawGraph(ctx, history, scaleMax) {
        ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height)

        var w = ctx.canvas.width
        var h = ctx.canvas.height

        if (history.length < 2) return

        var max = (scaleMax && scaleMax > 0) ? scaleMax : 100
        var step = w / (history.length - 1)

        ctx.beginPath()
        ctx.moveTo(0, h)
        for (var i = 0; i < history.length; i++)
            ctx.lineTo(i * step, h - Math.max(0, Math.min(max, history[i])) / max * h)
        ctx.lineTo(w, h)
        ctx.closePath()

        ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
        ctx.fill()

        ctx.beginPath()
        for (var j = 0; j < history.length; j++) {
            var x = j * step
            var y = h - Math.max(0, Math.min(max, history[j])) / max * h
            if (j) ctx.lineTo(x, y)
            else ctx.moveTo(x, y)
        }

        ctx.strokeStyle = Theme.accent
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.stroke()
    }

    // --- reusable components ------------------------------------------

    component InfoRow: Column {
        property string icon: ""
        property string label: ""
        property string value: ""
        property int valueWidth: 500

        spacing: 3

        Text {
            text: icon + "  " + label
            color: Theme.textDim
            font.family: page.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Text {
            text: value
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
            width: valueWidth
        }
    }

    component HardwareGraph: Column {
        id: block

        property string icon: ""
        property string label: ""
        property string valueText: ""
        property var badges: []
        property var history: []
        property bool clickable: false
        property real scaleMax: 100
        property string scaleTopLabel: "100%"

        signal clicked()

        width: parent.width
        spacing: 10

        onHistoryChanged: graphCanvas.requestPaint()

        Item {
            width: parent.width
            height: 24

            Row {
                id: headerRow
                anchors.fill: parent
                spacing: 20

                Text {
                    text: block.icon + "  " + block.label
                    color: Theme.textDim
                    font.family: page.mono
                    font.pixelSize: page.hardwareLabelSize
                    font.letterSpacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: block.valueText
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: page.hardwareTextSize
                    elide: Text.ElideLeft
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: block.badges

                    Text {
                        text: modelData
                        color: Theme.text
                        font.family: page.mono
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: block.clickable
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: block.clicked()
            }
        }

        Item {
            width: parent.width
            height: 60

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.border
            }

            Repeater {
                model: [0.25, 0.5, 0.75]

                Rectangle {
                    y: parent.height * modelData
                    width: parent.width
                    height: 1
                    color: Theme.border
                    opacity: 0.35
                }
            }

            Canvas {
                id: graphCanvas
                anchors.fill: parent
                anchors.margins: 6
                onPaint: page.drawGraph(getContext("2d"), block.history, block.scaleMax)
            }

            Text {
                text: block.scaleTopLabel
                anchors { top: parent.top; right: parent.right; margins: 5 }
                color: Theme.text
                opacity: 0.35
                font.family: page.mono
                font.pixelSize: 8
            }

            Text {
                text: "0%"
                anchors { bottom: parent.bottom; right: parent.right; margins: 5 }
                color: Theme.text
                opacity: 0.35
                font.family: page.mono
                font.pixelSize: 8
            }
        }
    }

    // --- processes -------------------------------------------------

    Process {
        id: pHome
        command: ["sh", "-c", "printf '%s' \"$HOME\""]
        running: true
        stdout: StdioCollector { onStreamFinished: page.homeDir = text.trim() }
    }

    Process {
        id: pUptime
        command: ["uptime", "-p"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.uptime = text.trim() }
    }

    Process {
        id: pOs
        command: ["sh", "-c", "grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.os = text.trim() }
    }

    Process {
        id: pCpu
        command: ["sh", "-c", "awk -F: '/model name/ {gsub(/^ +/, \"\", $2); print $2; exit}' /proc/cpuinfo"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.cpu = text.trim() }
    }

    Process {
        id: pCpuUsage
        command: ["sh", "-c", "head -1 /proc/stat"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateCpuFromStat(text) }
    }

    Process {
        id: pCpuTemp
        // coretemp's temp1 is the CPU package sensor. Read it straight from
        // sysfs so the panel works without lm-sensors installed. The kernel
        // reports millidegrees; the shell trims it to whole degrees.
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do if [ \"$(cat $h/name 2>/dev/null)\" = coretemp ]; then echo $(( $(cat $h/temp1_input) / 1000 )); break; fi; done"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.cpuTemp = page.formatTemp(text) }
    }

    Process {
        id: pGpu
        command: [
            "sh", "-c",
            "lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | sed -E 's/.*: //; s/ \\(rev.*\\)//' | head -1"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: page.gpu = text.trim() || "Unknown"
        }
    }

    Process {
        id: pGpuUsage
        // i915 exposes no gpu_busy_percent and perf events are blocked for
        // unprivileged users (perf_event_paranoid=3), so nvtop returns a null
        // gpu_util. Use per-engine busy time from /proc/<pid>/fdinfo instead.
        // See scripts/gpu-usage.py (mirrors the waybar GPU module).
        command: ["sh", "-c", "exec \"$HOME\"/.config/quickshell/scripts/gpu-usage.py"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateGraph(text, "gpu") }
    }

    Process {
        id: pGpuTemp
        // The i915 driver exposes no temperature sensor for this iGPU, so the
        // badge stays "—" on this machine. Patterns target discrete GPUs
        // (NVIDIA/AMD); bare "temp1:" is omitted because it would false-match
        // CPU/ACPI/Wi-Fi chips if lm-sensors gets installed.
        command: ["sh", "-c", page.sensorTempCmd(["GPU Temp:", "edge:", "junction:"])]
        running: true
        stdout: StdioCollector { onStreamFinished: page.gpuTemp = page.formatTemp(text) }
    }

    Process {
        id: pMemory
        command: ["sh", "-c", "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateMemoryFromStat(text) }
    }

    Process {
        id: pRamCache
        command: ["sh", "-c", "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/ram-speed\" 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var value = text.trim()
                if (value) page.ramSpeed = value
            }
        }
    }

    Process {
        id: pRamSpeed
        command: ["sh", "-c", "exec \"$HOME\"/.config/quickshell/scripts/ram-speed.sh"]
        stdout: StdioCollector {
            onStreamFinished: page.ramSpeed = text.trim() || "—"
        }
    }

    Process {
        id: pNproc
        command: ["nproc"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.nproc = parseInt(text.trim(), 10) || 0 }
    }

    Process {
        id: pLoad
        command: ["cat", "/proc/loadavg"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateLoadFromFile(text) }
    }

    Process {
        id: pFreq
        // Average CPU core frequency (kHz -> GHz), governor, and the iGPU
        // actual clock. LC_ALL=C keeps awk's decimal point locale-independent.
        command: [
            "sh", "-c",
            "LC_ALL=C awk '{s+=$1;n++} END {if (n) printf \"%.2f\", s/n/1000000}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; echo; cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor; cat /sys/class/drm/card0/gt_act_freq_mhz"
        ]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateFreqs(text) }
    }

    Process {
        id: pNet
        command: ["sh", "-c", "cat /sys/class/net/wlo1/statistics/rx_bytes /sys/class/net/wlo1/statistics/tx_bytes"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateNetFromCounters(text) }
    }

    Process {
        id: pWifi
        command: ["sh", "-c", "awk 'NR==3 {gsub(/\\./,\"\"); print $3, $4}' /proc/net/wireless"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateWifi(text) }
    }

    Process {
        id: pBattery
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/capacity /sys/class/power_supply/BAT0/status /sys/class/power_supply/BAT0/voltage_now /sys/class/power_supply/BAT0/current_now /sys/class/power_supply/BAT0/charge_now /sys/class/power_supply/BAT0/charge_full /sys/class/power_supply/BAT0/charge_full_design /sys/class/power_supply/BAT0/cycle_count"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.updateBattery(text) }
    }

    Process {
        id: pTempNvme
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name 2>/dev/null)\" = nvme ] && cat $h/temp1_input; done"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.tempNvme = page.formatMilliTemp(text) }
    }

    Process {
        id: pTempWifi
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case \"$(cat $h/name 2>/dev/null)\" in iwlwifi*) cat $h/temp1_input;; esac; done"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.tempWifi = page.formatMilliTemp(text) }
    }

    Process {
        id: pTempAcpi
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name 2>/dev/null)\" = acpitz ] && cat $h/temp1_input; done"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.tempAcpi = page.formatMilliTemp(text) }
    }

    // --- timers ------------------------------------------------------

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            page.updateClock()
            pCpuUsage.running = true
            pCpuTemp.running = true
            pGpuUsage.running = true
            pGpuTemp.running = true
            pNet.running = true
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            pMemory.running = true
            pLoad.running = true
            pFreq.running = true
            pWifi.running = true
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            pUptime.running = true
            pBattery.running = true
            pTempNvme.running = true
            pTempWifi.running = true
            pTempAcpi.running = true
        }
    }

    Component.onCompleted: {
        page.updateClock()
        pCpuTemp.running = true
        pGpuTemp.running = true
    }

    // --- UI ------------------------------------------------------------

    Flickable {
        id: scrollArea

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

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

            spacing: 20

            Text {
                text: "SYSTEM"
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

            Row {
                width: parent.width
                height: 150
                spacing: 24

                Item {
                    width: 150
                    height: 150

                    Image {
                        anchors.centerIn: parent
                        source: page.homeDir ? "file://" + page.homeDir + "/.config/quickshell/comitern.svg" : ""
                        width: 140
                        height: 140
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        opacity: 1.0
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    InfoRow { icon: "󰣇"; label: "OS"; value: page.os }
                    InfoRow { icon: "󱂬"; label: "WM"; value: page.wm }
                    InfoRow { icon: "󰔛"; label: "UPTIME"; value: page.uptime }
                }
            }

            HardwareGraph {
                icon: "󰍛"
                label: "CPU"
                valueText: page.cpu
                badges: [Math.round(page.cpuUsage) + "%", page.cpuTemp, page.cpuFreq, page.cpuGovernor]
                history: page.cpuHistory
            }

            HardwareGraph {
                icon: "󰢮"
                label: "GPU"
                valueText: page.gpu
                badges: [Math.round(page.gpuUsage) + "%", page.gpuTemp, page.gpuFreq]
                history: page.gpuHistory
            }

            HardwareGraph {
                icon: "󰘚"
                label: "RAM"
                valueText: page.memory
                badges: [page.ramSpeed === "—" ? "— click" : page.ramSpeed, Math.round(page.memoryUsage) + "%"]
                history: page.memoryHistory
                clickable: page.ramSpeed === "—"
                onClicked: {
                    page.ramSpeed = "…"
                    pRamSpeed.running = true
                }
            }

            HardwareGraph {
                icon: "󰓅"
                label: "LOAD"
                valueText: page.loadText
                badges: [Math.round(page.loadUsage) + "%"]
                history: page.loadHistory
            }

            HardwareGraph {
                icon: "󰖩"
                label: "NET"
                valueText: "↓ " + page.formatSpeed(page.netDown) + "   ↑ " + page.formatSpeed(page.netUp)
                badges: ["Wi-Fi " + page.wifiSignal + "/70 · " + page.wifiLevel]
                history: page.netHistory
                scaleMax: page.netScaleMax
                scaleTopLabel: page.formatSpeed(page.netScaleMax)
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            Column {
                width: parent.width
                spacing: 14

                InfoRow { icon: "󰁹"; label: "BATTERY"; value: page.batteryText; valueWidth: 680 }
                InfoRow { icon: "󰁹"; label: "BATTERY HEALTH"; value: page.batteryHealthText; valueWidth: 680 }
                InfoRow {
                    icon: "󰔏"
                    label: "SENSORS"
                    value: "NVMe " + page.tempNvme + " · Wi-Fi " + page.tempWifi + " · ACPI " + page.tempAcpi
                    valueWidth: 680
                }
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
