import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    property var monitors: []
    property int rightMargin: 50
    property real brightnessValue: 0.6
    property real nightlightValue: 0 // 0 = apagada; (0,1] = "cantidad" (6500..2500 K)
    readonly property int nightlightDefaultTemperature: 4000 // al encender con la luna
    property bool nightlightEnabled: false
    readonly property string nightlightScript: Quickshell.env("HOME") + "/.config/hypr/scripts/nightlight-toggle.sh"
    property real sliderMarginRight: 10
    property real labelWidth: 96
    property var scalePresets: ["1.0", "1.25", "1.5", "1.75", "2.0", "2.5"]
    property string primaryOutput: ""
    property int resolutionLimit: 6
    property real cardLabelWidth: 84

    Process {
        id: brightnessGet
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",")
                if (parts.length >= 4) {
                    const pct = parseInt(parts[3])
                    if (!isNaN(pct)) page.brightnessValue = pct / 100
                }
            }
        }
    }

    Process { id: brightnessSet }

    function commitBrightness(value) {
        const pct = Math.round(value * 100) + "%"
        brightnessSet.command = ["brightnessctl", "set", pct]
        brightnessSet.running = true
    }

    Process {
        id: nightlightProcess

        property var pendingArgs: null

        // Si llega una orden mientras otra corre, nos quedamos con la ultima:
        // los gestos rapidos de la barra se agrupan y no se pierde ninguno.
        function enqueue(args) {
            if (running) {
                pendingArgs = args
                return
            }
            command = [page.nightlightScript].concat(args)
            running = true
        }

        onExited: exitCode => {
            const next = pendingArgs
            pendingArgs = null
            // Al terminar la ultima orden se relee el estado real.
            if (next !== null) enqueue(next)
            else nightlightStatus.requestRefresh()
        }
    }

    // La barra representa "cantidad" de luz nocturna: 0 = apagada,
    // 1 = maximo calor (2500 K); encendida, el minimo es 6500 K (casi neutro).
    function nightlightTemperature(value) { return Math.round(6500 - value * 4000) }

    function nightlightValueFromTemperature(kelvin) {
        return Math.max(0, Math.min(1, (6500 - kelvin) / 4000))
    }

    function nightlightOn() {
        // Encender con la luna parte siempre del valor por defecto (4000 K).
        // Actualizacion optimista: la luna responde al instante y el sondeo
        // posterior confirma (o corrige) el estado real.
        page.nightlightValue = page.nightlightValueFromTemperature(page.nightlightDefaultTemperature)
        page.nightlightEnabled = true
        nightlightProcess.enqueue(["on", String(page.nightlightDefaultTemperature)])
    }

    function nightlightOff() {
        // Apagar devuelve la barra a 0: la luz apagada es el unico estado con barra 0.
        page.nightlightValue = 0
        page.nightlightEnabled = false
        nightlightProcess.enqueue(["off"])
    }

    function commitNightlight(value) {
        // Barra a 0 = apagar; cualquier otro valor = encender a esa temperatura.
        if (value <= 0) {
            page.nightlightOff()
            return
        }
        page.nightlightValue = value
        page.nightlightEnabled = true
        // "on" es idempotente: si ya estaba encendida solo cambia el tono,
        // asi que usar la barra siempre deja la luz encendida a esa temperatura.
        nightlightProcess.enqueue(["on", String(page.nightlightTemperature(value))])
    }

    Process {
        id: nightlightStatus

        property bool refreshQueued: false

        function requestRefresh() {
            if (running) {
                refreshQueued = true
                return
            }
            running = true
        }

        onExited: {
            if (refreshQueued) {
                refreshQueued = false
                requestRefresh()
            }
        }

        command: [page.nightlightScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                // Descarta salidas vacias o lecturas que quedaron obsoletas
                // porque una orden estaba en marcha en ese momento.
                if (out === "" || nightlightProcess.running) return
                const parts = out.split(/\s+/)
                const isOn = parts[0] === "on"
                page.nightlightEnabled = isOn
                if (!isOn) {
                    // Luz apagada: la barra siempre vuelve a 0.
                    page.nightlightValue = 0
                } else if (parts.length >= 2) {
                    const kelvin = parseInt(parts[1])
                    if (!isNaN(kelvin)) {
                        // Encendida, la barra nunca queda en 0 (el 0 es "apagada").
                        page.nightlightValue = Math.max(page.nightlightValueFromTemperature(kelvin), 0.01)
                    }
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }

    // Reconciliacion periodica con el estado real (por ejemplo, si la luz se
    // cambia con SUPER+SHIFT+P mientras la pagina esta abierta).
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (!nightlightProcess.running) nightlightStatus.requestRefresh()
        }
    }

    function monitorMode(mon) { return mon.width + "x" + mon.height + "@" + mon.refreshRate.toFixed(2) }

    function luaString(value) { return String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") }

    function monitorLua(mon, options = {}) {
        const values = ["output = \"" + luaString(mon.name) + "\""]
        if (options.mode !== undefined) values.push("mode = \"" + luaString(options.mode) + "\"")
        if (options.position !== undefined) values.push("position = \"" + luaString(options.position) + "\"")
        if (options.scale !== undefined) values.push("scale = " + options.scale)
        if (options.disabled !== undefined) values.push("disabled = " + options.disabled)
        if (options.mirrorOf !== undefined) values.push("mirrorOf = \"" + luaString(options.mirrorOf) + "\"")
        return "hl.monitor({" + values.join(",") + "})"
    }

    Process {
        id: pList
        command: ["hyprctl", "monitors", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.monitors = JSON.parse(text)
                } catch (error) {
                    page.monitors = []
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }

    function refresh() {
        pList.running = true
    }

    // Refresco completo: lista de monitores + salida principal actual.
    function refreshAll() {
        page.refresh()
        if (!pPrimaryGet.running) {
            pPrimaryGet.command = page.monitorCtl(["primary"])
            pPrimaryGet.running = true
        }
    }

    Process {
        id: pApply
        property var pendingMon: null

        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (out.length === 0) return

                const match = out.match(/using suggested scale:\s*([\d.]+)/i)
                if (match && pApply.pendingMon) {
                    const suggested = parseFloat(match[1])
                    page.setScale(pApply.pendingMon, suggested, true)
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        onExited: exitCode => {
            refreshTimer.restart()
        }
    }

    function gcd(a, b) { while (b) { [a, b] = [b, a % b] }; return a }

    function validScale(mon, requested) {
        const width = mon.width
        const height = mon.height
        let best = requested
        let bestDistance = Infinity

        for (let i = 84; i <= 360; i++) {
            const scale = i / 120
            if (scale < 0.7 || scale > 3.0) continue

            const logicalWidth = width / scale
            const logicalHeight = height / scale

            if (Math.abs(logicalWidth - Math.round(logicalWidth)) < 0.0001 &&
                Math.abs(logicalHeight - Math.round(logicalHeight)) < 0.0001) {
                const distance = Math.abs(scale - requested)
                if (distance < bestDistance) {
                    best = scale
                    bestDistance = distance
                }
            }
        }

        return best
    }

    function setScale(mon, scale, isRetry = false) {
        const requested = scale
        const applied = isRetry ? scale : validScale(mon, requested)

        const idx = page.monitors.findIndex(m => m.name === mon.name)
        if (idx !== -1) {
            const updated = page.monitors.slice()
            updated[idx] = Object.assign({}, updated[idx], { scale: applied })
            page.monitors = updated
        }

        pApply.pendingMon = mon
        pApply.command = [
            "hyprctl", "eval",
            monitorLua(mon, { mode: monitorMode(mon), position: mon.x + "x" + mon.y, scale: applied })
        ]
        pApply.running = true
    }

    Process {
        id: pSetScale
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim()
                if (msg.length > 0) console.warn("monitor-ctl.sh scale: " + msg)
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("monitor-ctl.sh scale salió con código " + exitCode)
            applyTimer.restart()
        }
    }

    // Presets de escala: aplica el valor EXACTO (sin el filtro de tamaño
    // lógico entero de validScale) y lo persiste para el relogin mediante
    // scripts/monitor-ctl.sh (que además asegura debug:disable_scale_checks).
    function setScaleExact(mon, scale) {
        if (!mon || !mon.name || pSetScale.running) {
            return
        }
        const requested = Math.round(scale * 100) / 100
        const idx = page.monitors.findIndex(m => m.name === mon.name)
        if (idx !== -1) {
            const updated = page.monitors.slice()
            updated[idx] = Object.assign({}, updated[idx], { scale: requested })
            page.monitors = updated
        }
        pSetScale.command = page.monitorCtl(["scale", mon.name, requested.toFixed(2)])
        pSetScale.running = true
        applyTimer.restart()
    }

    // --- availableModes por salida (nada hardcodeado) ---------------------
    // Los modos llegan como "1440x900@59.89Hz"; todo se parsea de ahi.
    function monitorCtl(args) {
        const command = [Quickshell.env("HOME") + "/.config/hypr/scripts/monitor-ctl.sh"]
        for (let i = 0; i < args.length; i++) command.push(String(args[i]))
        return command
    }

    function parseAvailableModes(mon) {
        const parsed = []
        const modes = (mon && mon.availableModes) ? mon.availableModes : []
        for (let i = 0; i < modes.length; i++) {
            const match = String(modes[i]).match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz$/)
            if (!match) continue
            parsed.push({
                width: parseInt(match[1]),
                height: parseInt(match[2]),
                rate: parseFloat(match[3])
            })
        }
        return parsed
    }

    function rateLabel(rate) {
        const rounded = Math.round(rate)
        if (Math.abs(rate - rounded) < 0.01) return String(rounded)
        return String(parseFloat(rate.toFixed(2)))
    }

    // Resoluciones unicas (WxH), ordenadas por area descendente, limitadas a
    // page.resolutionLimit y siempre con la resolucion actual incluida.
    function resolutionChoices(mon) {
        const modes = page.parseAvailableModes(mon)
        const seen = ({})
        const result = []
        for (let i = 0; i < modes.length; i++) {
            const key = modes[i].width + "x" + modes[i].height
            if (seen[key]) continue
            seen[key] = true
            result.push({ label: key, width: modes[i].width, height: modes[i].height })
        }
        result.sort(function (a, b) {
            const areaA = a.width * a.height
            const areaB = b.width * b.height
            if (areaA !== areaB) return areaB - areaA
            return b.width - a.width
        })
        const currentKey = mon ? mon.width + "x" + mon.height : ""
        const limited = result.slice(0, page.resolutionLimit)
        if (currentKey.length === 0 || result.length <= page.resolutionLimit) {
            return limited
        }
        for (let i = 0; i < limited.length; i++) {
            if (limited[i].label === currentKey) return limited
        }
        for (let i = 0; i < result.length; i++) {
            if (result[i].label === currentKey) {
                limited[limited.length - 1] = result[i]
                break
            }
        }
        return limited
    }

    // Tasas de refresco disponibles para la resolucion actual, de mayor a menor.
    function refreshChoices(mon) {
        const modes = page.parseAvailableModes(mon)
        const width = mon ? mon.width : 0
        const height = mon ? mon.height : 0
        const seen = ({})
        const result = []
        for (let i = 0; i < modes.length; i++) {
            if (modes[i].width !== width || modes[i].height !== height) continue
            const key = modes[i].rate.toFixed(2)
            if (seen[key]) continue
            seen[key] = true
            result.push({ label: page.rateLabel(modes[i].rate), rate: modes[i].rate })
        }
        result.sort(function (a, b) { return b.rate - a.rate })
        return result
    }

    function isCurrentResolution(mon, choice) {
        return !!mon && mon.width === choice.width && mon.height === choice.height
    }

    function isCurrentRate(mon, choice) {
        return !!mon && Math.abs(mon.refreshRate - choice.rate) < 0.02
    }

    // RR a usar al cambiar de resolucion: la actual si sigue existiendo,
    // si no la mayor disponible para ese WxH.
    function preferredRate(mon, width, height) {
        const modes = page.parseAvailableModes(mon)
        let highest = null
        let current = null
        for (let i = 0; i < modes.length; i++) {
            const mode = modes[i]
            if (mode.width !== width || mode.height !== height) continue
            if (highest === null || mode.rate > highest) highest = mode.rate
            if (mon && Math.abs(mon.refreshRate - mode.rate) < 0.02) current = mode.rate
        }
        if (current !== null) return current
        return highest
    }

    function applyResolution(mon, width, height) {
        const rate = page.preferredRate(mon, width, height)
        if (rate === null) return
        page.applyMode(mon, width, height, rate)
    }

    function applyRate(mon, rate) {
        if (!mon) return
        page.applyMode(mon, mon.width, mon.height, rate)
    }

    // Aplica WxH@RR via monitor-ctl.sh (valida contra availableModes y persiste).
    function applyMode(mon, width, height, rate) {
        if (!mon || !mon.name || pMode.running) {
            return
        }
        const idx = page.monitors.findIndex(m => m.name === mon.name)
        if (idx !== -1) {
            const updated = page.monitors.slice()
            updated[idx] = Object.assign({}, updated[idx], {
                width: width,
                height: height,
                refreshRate: rate
            })
            page.monitors = updated
        }
        pMode.command = page.monitorCtl(["mode", mon.name, width + "x" + height + "@" + rate.toFixed(2)])
        pMode.running = true
        applyTimer.restart()
    }

    Process {
        id: pMode
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim()
                if (msg.length > 0) console.warn("monitor-ctl.sh mode: " + msg)
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("monitor-ctl.sh mode salió con código " + exitCode)
            applyTimer.restart()
        }
    }

    // Salida principal actual (la imprime monitor-ctl.sh primary sin args).
    Process {
        id: pPrimaryGet
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (out.length > 0) page.primaryOutput = out
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }

    Process {
        id: pPrimarySet
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim()
                if (msg.length > 0) console.warn("monitor-ctl.sh primary: " + msg)
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("monitor-ctl.sh primary salió con código " + exitCode)
            applyTimer.restart()
        }
    }

    // Cambia la pantalla principal (escritorios 1-5) y deja la otra en auto (6-10).
    function setPrimary(mon) {
        if (!mon || !mon.name || pPrimarySet.running) {
            return
        }
        pPrimarySet.command = page.monitorCtl(["primary", mon.name])
        pPrimarySet.running = true
        applyTimer.restart()
    }

    // Ancho de boton de preset: reparte el ancho disponible con un tope,
    // para que las filas con pocos botones no queden desmesuradas.
    function presetButtonWidth(available, spacing, count) {
        if (count <= 0) return 0
        return Math.min(112, (available - spacing * (count - 1)) / count)
    }

    Timer { id: refreshTimer; interval: 250; onTriggered: page.refresh() }
    Timer { id: applyTimer; interval: 1500; onTriggered: page.refreshAll() }

    Process {
        id: pEditConfig
        command: ["sh", "-c", "xed ~/.config/hypr/monitors.lua"]
        onExited: exitCode => {}
    }

    function editConfig() {
        if (pEditConfig.running) {
            return
        }
        pEditConfig.running = true
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: page.rightMargin
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            id: scrollBar

            background: Rectangle {
                color: "transparent"
                radius: width / 2
            }

            contentItem: Rectangle {
                color: "transparent"
                radius: width / 2
            }
        }

        Column {
            id: content
            width: flick.width
            spacing: 9

            Row {
                width: parent.width; height: 36

                Text {
                    text: "DISPLAY"; color: Theme.text
                    font.family: Theme.fontFamily; font.pixelSize: 19; font.letterSpacing: 3
                    anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -6
                }

                Item { width: parent.width - 150; height: 1 }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Row {
                width: parent.width; height: 38; spacing: 8

                Rectangle {
                    width: 28; height: 28; radius: Theme.radius; anchors.verticalCenter: parent.verticalCenter
                    color: Theme.alpha(Theme.accent2, 0.10); border.width: 1; border.color: Theme.border
                    Text {
                        anchors.centerIn: parent; text: "\uf185"; color: Theme.accent2
                        font.family: Theme.iconFont; font.pixelSize: 12
                    }
                }

                Text {
                    width: page.labelWidth; anchors.verticalCenter: parent.verticalCenter
                    text: "BRIGHTNESS"; color: Theme.text
                    font.family: Theme.fontFamily; font.pixelSize: 15
                }

                Slider {
                    width: parent.width - 28 - page.labelWidth - 16 - page.sliderMarginRight
                    height: 72; anchors.verticalCenter: parent.verticalCenter
                    label: ""; icon: ""; value: page.brightnessValue; accentColor: Theme.accent2
                    onCommitted: value => page.commitBrightness(value)
                }
            }

            Row {
                width: parent.width; height: 38; spacing: 10

                Rectangle {
                    width: 28; height: 28; radius: Theme.radius; anchors.verticalCenter: parent.verticalCenter
                    color: page.nightlightEnabled ? Theme.alpha(Theme.accent, 0.10) : Theme.alpha("#A0A0A0", 0.15)
                    border.width: 1; border.color: page.nightlightEnabled ? Theme.accent : Theme.border
                    Text {
                        anchors.centerIn: parent; text: "\uf186"
                        color: page.nightlightEnabled ? Theme.accent : "#A0A0A0"
                        font.family: Theme.iconFont; font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: page.nightlightEnabled ? page.nightlightOff() : page.nightlightOn()
                    }
                }

                Text {
                    width: page.labelWidth; anchors.verticalCenter: parent.verticalCenter
                    text: "NIGHTLIGHT"; color: page.nightlightEnabled ? Theme.text : Theme.textDim
                    font.family: Theme.fontFamily; font.pixelSize: 15
                }

                Slider {
                    id: nightlightSlider
                    width: parent.width - 28 - page.labelWidth - 16 - page.sliderMarginRight
                    height: 72; anchors.verticalCenter: parent.verticalCenter
                    label: ""; icon: ""; value: page.nightlightValue; accentColor: Theme.accent2
                    displayText: nightlightSlider.value > 0 ? page.nightlightTemperature(nightlightSlider.value) + " K" : "Off"
                    onCommitted: value => {
                        page.commitNightlight(value)
                        // El arrastre rompe el binding de `value`; lo restauramos
                        // para que la barra siga reflejando el estado real.
                        nightlightSlider.value = Qt.binding(() => page.nightlightValue)
                    }
                }
            }

            Column {
                width: parent.width; spacing: 16

                Repeater {
                    model: page.monitors

                    delegate: Rectangle {
                        id: monCard
                        required property var modelData

                        readonly property string outputName: monCard.modelData.name
                        readonly property bool isPrimary: page.primaryOutput === monCard.outputName
                        readonly property var resolutions: page.resolutionChoices(monCard.modelData)
                        readonly property var refreshRates: page.refreshChoices(monCard.modelData)

                        width: parent.width
                        implicitHeight: cardColumn.implicitHeight + 28
                        height: implicitHeight
                        radius: Theme.radius
                        color: "#00000000"; border.width: 1
                        border.color: modelData.focused ? "#454545" : Theme.border

                        Column {
                            id: cardColumn
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 14
                            spacing: 7

                            Item {
                                width: parent.width
                                height: 24

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    Text {
                                        text: monCard.outputName; color: Theme.text
                                        font.family: Theme.fontFamily; font.pixelSize: 14; font.bold: true
                                    }

                                    Text {
                                        text: modelData.width + "x" + modelData.height + " @ " + Math.round(modelData.refreshRate) + "Hz"
                                        color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12
                                    }

                                    Text {
                                        visible: modelData.focused; text: "ACTIVE"; color: Theme.accent2
                                        font.family: Theme.fontFamily; font.pixelSize: 10
                                    }
                                }

                                Rectangle {
                                    id: primaryBtn
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    readonly property bool hovered: primaryHover.containsMouse
                                    width: primaryLabel.implicitWidth + 24
                                    height: 22
                                    radius: Theme.radius
                                    color: monCard.isPrimary
                                        ? Theme.alpha(Theme.accent, 0.18)
                                        : (primaryBtn.hovered ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
                                    border.width: 1
                                    border.color: monCard.isPrimary ? Theme.accent : Theme.border

                                    Text {
                                        id: primaryLabel
                                        anchors.centerIn: parent
                                        text: "PRIMARY"
                                        color: monCard.isPrimary ? Theme.text : Theme.textDim
                                        font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1
                                    }

                                    MouseArea {
                                        id: primaryHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.setPrimary(monCard.modelData)
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                height: 30
                                spacing: 10

                                Text {
                                    width: page.cardLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "RESOLUTION"; color: Theme.textDim
                                    font.family: Theme.fontFamily; font.pixelSize: 11
                                }

                                Row {
                                    id: resolutionRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: parent.height
                                    width: parent.width - page.cardLabelWidth - parent.spacing
                                    spacing: 6

                                    Repeater {
                                        id: resolutionRepeater
                                        model: monCard.resolutions

                                        delegate: Rectangle {
                                            id: resolutionBtn
                                            required property var modelData
                                            readonly property bool selected: page.isCurrentResolution(monCard.modelData, resolutionBtn.modelData)
                                            property bool hovered: false
                                            width: page.presetButtonWidth(resolutionRow.width, resolutionRow.spacing, resolutionRepeater.count)
                                            height: resolutionRow.height
                                            radius: Theme.radius
                                            color: selected ? Theme.alpha(Theme.accent, 0.18) : (hovered ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
                                            border.width: 1
                                            border.color: selected ? Theme.accent : Theme.border

                                            Text {
                                                anchors.centerIn: parent
                                                text: resolutionBtn.modelData.label
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: true
                                                font.letterSpacing: 1
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: resolutionBtn.hovered = true
                                                onExited: resolutionBtn.hovered = false
                                                onClicked: page.applyResolution(monCard.modelData, resolutionBtn.modelData.width, resolutionBtn.modelData.height)
                                            }
                                        }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                height: 30
                                spacing: 10

                                Text {
                                    width: page.cardLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "REFRESH"; color: Theme.textDim
                                    font.family: Theme.fontFamily; font.pixelSize: 11
                                }

                                Row {
                                    id: refreshRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: parent.height
                                    width: parent.width - page.cardLabelWidth - parent.spacing
                                    spacing: 6

                                    Repeater {
                                        id: refreshRepeater
                                        model: monCard.refreshRates

                                        delegate: Rectangle {
                                            id: refreshBtn
                                            required property var modelData
                                            readonly property bool selected: page.isCurrentRate(monCard.modelData, refreshBtn.modelData)
                                            property bool hovered: false
                                            width: page.presetButtonWidth(refreshRow.width, refreshRow.spacing, refreshRepeater.count)
                                            height: refreshRow.height
                                            radius: Theme.radius
                                            color: selected ? Theme.alpha(Theme.accent, 0.18) : (hovered ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
                                            border.width: 1
                                            border.color: selected ? Theme.accent : Theme.border

                                            Text {
                                                anchors.centerIn: parent
                                                text: refreshBtn.modelData.label + " Hz"
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.bold: true
                                                font.letterSpacing: 1
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: refreshBtn.hovered = true
                                                onExited: refreshBtn.hovered = false
                                                onClicked: page.applyRate(monCard.modelData, refreshBtn.modelData.rate)
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                width: parent.width
                                height: scaleLabel.implicitHeight
                                Text {
                                    id: scaleLabel
                                    anchors.left: parent.left
                                    text: "SCALE"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily; font.pixelSize: 11
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: String(parseFloat(modelData.scale.toFixed(2))) + "x"
                                    color: Theme.text
                                    font.family: Theme.fontFamily; font.pixelSize: 11
                                }
                            }

                            Row {
                                id: scalePresetsRow
                                width: parent.width
                                height: 32
                                spacing: 8

                                Repeater {
                                    model: page.scalePresets

                                    delegate: Rectangle {
                                        id: scaleBtn
                                        required property string modelData
                                        readonly property real presetValue: parseFloat(scaleBtn.modelData)
                                        readonly property bool selected: Math.abs(presetValue - monCard.modelData.scale) < 0.01
                                        property bool hovered: false
                                        width: (scalePresetsRow.width - scalePresetsRow.spacing * (page.scalePresets.length - 1)) / page.scalePresets.length
                                        height: scalePresetsRow.height
                                        radius: Theme.radius
                                        color: selected ? Theme.alpha(Theme.accent, 0.18) : (hovered ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
                                        border.width: 1
                                        border.color: selected ? Theme.accent : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: scaleBtn.modelData
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.letterSpacing: 1
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: scaleBtn.hovered = true
                                            onExited: scaleBtn.hovered = false
                                            onClicked: page.setScaleExact(monCard.modelData, scaleBtn.presetValue)
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

    Component.onCompleted: {
        brightnessGet.running = true
        nightlightStatus.requestRefresh()
        page.refreshAll()
    }
}
