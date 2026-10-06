// NotepadWindow.qml
// Bloc de notas flotante. Toggle: `qs ipc call notepad toggle`
// Autoguardado en la ruta activa (por defecto ~/.local/share/quickshell-notepad/notas.md).
// "Guardar como…" permite elegir cualquier ruta del sistema (zenity) y la recuerda.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls

PanelWindow {
    id: root

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: root.showing ? backdrop : null
    }

    property bool showing: false
    property bool dirty: false
    property bool saving: false
    property bool saveError: false
    property bool loading: false
    property string lastSaved: ""
    property string savingText: ""
    property date lastSavedAt: new Date(0)

    readonly property string defaultNotePath: Quickshell.env("HOME") + "/.local/share/quickshell-notepad/notas.md"
    property string notePath: defaultNotePath
    property string pendingPath: ""
    property string pendingText: ""
    property bool reopenAfterDialog: false

    function show() {
        showing = true
        Qt.callLater(function () {
            editor.forceActiveFocus()
            editor.cursorPosition = editor.length
        })
    }

    function hide() {
        saveNow()
        showing = false
    }

    function toggle() {
        showing ? hide() : show()
    }

    function saveNow() {
        saveTimer.stop()
        if (!dirty)
            return

        savingText = editor.text
        saving = true
        noteFile.setText(savingText)
    }

    // Guardar en una ruta elegida por el usuario (diálogo nativo GTK).
    function promptSaveAs() {
        if (saveAsProcess.running)
            return

        root.reopenAfterDialog = root.showing
        root.hide()
        saveAsProcess.exec([
            "zenity", "--file-selection", "--save", "--confirm-overwrite",
            "--title=Guardar nota como",
            "--file-filter=Notas (*.md *.txt) | *.md *.txt",
            "--file-filter=Todos los archivos | *",
            "--filename=" + root.notePath
        ])
    }

    // Escribe el contenido actual en la ruta elegida y pasa a usarla.
    function beginSaveAs(path) {
        root.pendingPath = path
        root.pendingText = editor.text
        Qt.callLater(function () {
            exportFile.setText(root.pendingText)
        })
    }

    function fileLabel() {
        var parts = root.notePath.split("/")
        return parts[parts.length - 1] || "notas.md"
    }

    function statusLabel() {
        if (saveError)
            return "Error al guardar"
        if (saving)
            return "Guardando…"
        if (dirty)
            return "Sin guardar…"
        if (lastSavedAt.getTime() > 0)
            return "Guardado " + Qt.formatTime(lastSavedAt, "HH:mm")
        return "Listo"
    }

    IpcHandler {
        target: "notepad"
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function hide(): void { root.hide() }
        function save(): void { root.saveNow() }
        function saveAs(): void { root.promptSaveAs() }
    }

    FileView {
        id: noteFile
        path: root.notePath
        blockWrites: false
        atomicWrites: true
        watchChanges: true
        printErrors: true

        onLoaded: {
            var content = text()
            root.lastSaved = content
            if (!root.dirty && content !== editor.text) {
                root.loading = true
                editor.text = content
                root.loading = false
                editor.cursorPosition = editor.length
            }
        }
        onSaved: {
            root.saving = false
            root.saveError = false
            root.lastSaved = root.savingText
            root.lastSavedAt = new Date()
            root.dirty = editor.text !== root.lastSaved
            if (root.dirty)
                saveTimer.restart()
        }
        onSaveFailed: {
            root.saving = false
            root.saveError = true
        }
        onLoadFailed: {
            // La ruta recordada ya no existe: volver a la nota por defecto.
            if (root.notePath !== root.defaultNotePath) {
                root.notePath = root.defaultNotePath
                pathFile.setText(root.defaultNotePath)
            } else {
                root.saveError = true
            }
        }
        onFileChanged: reload()
    }

    // Recuerda la última ruta elegida con "guardar como…".
    FileView {
        id: pathFile
        path: Quickshell.env("HOME") + "/.local/share/quickshell-notepad/.last-path"
        blockWrites: false
        atomicWrites: true
        printErrors: false

        onLoaded: {
            var saved = text().trim()
            if (saved !== "" && saved !== root.notePath)
                root.notePath = saved
        }
    }

    // Escribe el contenido en la nueva ruta (sin precargar el archivo destino).
    FileView {
        id: exportFile
        path: root.pendingPath
        preload: false
        blockWrites: false
        atomicWrites: true
        printErrors: true

        onSaved: {
            root.notePath = root.pendingPath
            root.lastSaved = root.pendingText
            root.lastSavedAt = new Date()
            root.dirty = editor.text !== root.lastSaved
            root.saveError = false
            pathFile.setText(root.pendingPath)
        }
        onSaveFailed: {
            root.saveError = true
        }
    }

    // Diálogo "guardar como…".
    Process {
        id: saveAsProcess
        command: []
        stdout: StdioCollector {
            id: saveAsStdout
            waitForEnd: true
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode === 0) {
                var picked = saveAsStdout.text.trim()
                if (picked !== "")
                    root.beginSaveAs(picked)
            }
            if (root.reopenAfterDialog) {
                root.reopenAfterDialog = false
                root.show()
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 700
        onTriggered: root.saveNow()
    }

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

    PerspectivePanel {
        id: card
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: Math.min(900, root.width - 80)
        height: Math.min(680, root.height - 80)
        open: root.showing

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

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                Item {
                    id: header
                    width: parent.width
                    height: 32

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: " NOTAS"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                        font.bold: true
                        font.letterSpacing: 4
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 20
                        spacing: 14

                        Text {
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            text: "●"
                            color: root.saveError ? Theme.danger
                                : (root.dirty || root.saving ? Theme.accent2 : Theme.ok)
                            font.pixelSize: 9
                        }

                        Text {
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            text: root.statusLabel()
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }

                Rectangle {
                    id: separator
                    width: parent.width
                    height: 1
                    color: Theme.border
                }

                Rectangle {
                    id: editorContainer
                    width: parent.width
                    height: parent.height - header.height - separator.height - footer.height - 36
                    color: "transparent"
                    radius: Theme.radius
                    border.color: Theme.borderAccent
                    border.width: 1
                    clip: true

                    Flickable {
                        id: editorFlick
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextArea.flickable: TextArea {
                            id: editor
                            placeholderText: "Escribe algo…"
                            placeholderTextColor: Theme.textFaint
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            persistentSelection: true
                            color: Theme.text
                            selectionColor: Theme.alpha(Theme.accent, 0.35)
                            selectedTextColor: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            background: null
                            focus: root.showing

                            Keys.onEscapePressed: root.hide()
                            Keys.onPressed: function (event) {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                                    if (event.modifiers & Qt.ShiftModifier)
                                        root.promptSaveAs()
                                    else
                                        root.saveNow()
                                    event.accepted = true
                                }
                            }

                            onTextChanged: {
                                if (root.loading)
                                    return

                                root.dirty = editor.text !== root.lastSaved
                                if (root.dirty)
                                    saveTimer.restart()
                                else
                                    saveTimer.stop()
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 6
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: Theme.alpha(Theme.accent, 0.35)
                            }
                            background: null
                        }
                    }
                }

                Item {
                    id: footer
                    width: parent.width
                    height: 22

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fileLabel() + " · "
                            + editor.lineCount + (editor.lineCount === 1 ? " línea · " : " líneas · ")
                            + editor.length + " caracteres"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Ctrl+S guardar · Ctrl+Shift+S guardar como · Esc cerrar"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
