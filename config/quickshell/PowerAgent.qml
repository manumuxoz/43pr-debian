import QtQuick
import Quickshell
import Quickshell.Io

// Background companion for Settings → Power.
//
// - Records a battery-health sample every six hours (even if the page was
//   never opened, so the health graph has data).
// - Re-applies the charge limit and Turbo Boost choice saved by the page.
//   Both writes use the narrow NOPASSWD rule from
//   scripts/install-power-sudoers.sh; without it they fail silently.
Scope {
    id: agent

    property bool stateReady: false
    property bool hardwareReady: false
    property bool restoreDone: false
    property bool applyLimitAfterTurbo: false

    // -1 means "not configured / not available"; turbo: 1 = on, 0 = off.
    property int turboWanted: -1
    property int limitWanted: -1
    property int currentNoTurbo: -1
    property int currentLimit: -1

    function loadState(text) {
        try {
            var data = JSON.parse(text.trim())
            if (data && typeof data.turbo === "boolean")
                agent.turboWanted = data.turbo ? 1 : 0
            var limit = Number(data && data.chargeLimit)
            if (isFinite(limit) && limit > 0)
                agent.limitWanted = Math.round(limit)
        } catch (e) {
            console.warn("Ignoring invalid power state:", e)
        }
        agent.stateReady = true
        agent.maybeRestore()
    }

    function loadHardware(text) {
        var lines = text.trim().split("\n")
        if (lines.length >= 2) {
            var noTurbo = lines[0].trim()
            if (noTurbo !== "") agent.currentNoTurbo = Number(noTurbo)
            var limit = lines[1].trim()
            if (limit !== "") agent.currentLimit = Number(limit)
        }
        agent.hardwareReady = true
        agent.maybeRestore()
    }

    function maybeRestore() {
        if (!agent.stateReady || !agent.hardwareReady || agent.restoreDone)
            return
        agent.restoreDone = true

        var turboNeeded = agent.turboWanted >= 0 && agent.currentNoTurbo >= 0
            && (agent.turboWanted === 1 ? 0 : 1) !== agent.currentNoTurbo
        var limitNeeded = agent.limitWanted > 0 && agent.currentLimit > 0
            && agent.limitWanted !== agent.currentLimit

        if (turboNeeded) {
            agent.applyLimitAfterTurbo = limitNeeded
            pSetTurbo.value = agent.turboWanted === 1 ? 0 : 1
            pSetTurbo.stdinEnabled = true
            pSetTurbo.running = true
        } else if (limitNeeded) {
            agent.applyLimit()
        }
    }

    function applyLimit() {
        pSetLimit.value = agent.limitWanted
        pSetLimit.stdinEnabled = true
        pSetLimit.running = true
    }

    FileView {
        id: powerStore
        path: Quickshell.env("HOME") + "/.config/quickshell/state/power.json"
        printErrors: false
        onLoaded: agent.loadState(powerStore.text())
    }

    Process {
        id: pReadHardware
        command: [
            "sh", "-c",
            "printf '%s\\n' \"$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)\" " +
            "\"$(cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null)\""
        ]
        running: true
        stdout: StdioCollector { onStreamFinished: agent.loadHardware(text) }
        stderr: StdioCollector {}
    }

    Process {
        id: pSetTurbo
        property int value: -1

        command: ["sudo", "-n", "/usr/bin/tee", "/sys/devices/system/cpu/intel_pstate/no_turbo"]
        stdinEnabled: false
        running: false

        onStarted: {
            write(value + "\n")
            stdinEnabled = false
        }

        onExited: function(exitCode) {
            if (exitCode !== 0)
                console.warn("PowerAgent: could not restore Turbo Boost (install scripts/install-power-sudoers.sh)")
            if (agent.applyLimitAfterTurbo) {
                agent.applyLimitAfterTurbo = false
                agent.applyLimit()
            }
        }
    }

    Process {
        id: pSetLimit
        property int value: -1

        command: ["sudo", "-n", "/usr/bin/tee", "/sys/class/power_supply/BAT0/charge_control_end_threshold"]
        stdinEnabled: false
        running: false

        onStarted: {
            write(value + "\n")
            stdinEnabled = false
        }

        onExited: function(exitCode) {
            if (exitCode !== 0)
                console.warn("PowerAgent: could not restore charge limit (install scripts/install-power-sudoers.sh)")
        }
    }

    Timer {
        interval: 6 * 60 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pRecord.running = true
    }

    Process {
        id: pRecord
        command: ["sh", "-c", "exec \"$HOME\"/.config/quickshell/scripts/battery-health.py record"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }
}
