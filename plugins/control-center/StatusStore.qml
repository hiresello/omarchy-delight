pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// Live module statuses. Watches $XDG_RUNTIME_DIR/omarchy-delight/status/*.json
// (one FileView per file, reloaded on every rename/write) and falls back to
// `delight status --json` every `fallbackInterval` ms for modules that have
// not written a file yet. File entries win over fallback entries.
Item {
  id: root

  property string statusDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-delight/status"
  property bool fallbackEnabled: true
  property int fallbackInterval: 30000
  // Poll repeatedly only while someone is looking (the panel is open); the
  // file watcher pushes every change, so a closed panel costs nothing.
  property bool live: true
  property var delightCommand: ["delight"]

  readonly property var stateNames: ["on", "off", "busy", "needs-setup", "unsupported", "error"]
  property var modules: []
  property var fallbackModules: []
  // fileId -> raw text of each status file currently on disk.
  property var fileTexts: ({})

  function setFile(fileId, text) {
    let next = Object.assign({}, fileTexts)
    if (text === null) delete next[fileId]
    else next[fileId] = text
    fileTexts = next
    coalesce.restart()
  }
  // "error" if any module errors, else "busy" if any is busy, else "".
  readonly property string attention: {
    let busy = false
    for (let i = 0; i < modules.length; i++) {
      if (modules[i].state === "error") return "error"
      if (modules[i].state === "busy") busy = true
    }
    return busy ? "busy" : ""
  }
  // Toggles that can't act yet (unsupported, needs setup) join the rows, so
  // the big tiles are only things one click can switch.
  function isTile(m) { return m.toggle && m.state !== "unsupported" && m.state !== "needs-setup" }
  readonly property var toggles: modules.filter(function(m) { return root.isTile(m) })
  readonly property var rows: modules.filter(function(m) { return !root.isTile(m) })

  signal changed()

  signal reloadRequested()

  Component.onCompleted: pollFallback()

  function refresh() {
    reloadRequested()
    pollFallback()
  }

  function pollFallback() {
    if (fallbackEnabled && !fallback.running) fallback.running = true
  }

  // Coerce one parsed status into the contract shape so a malformed file
  // degrades to an error tile instead of breaking the panel.
  function normalize(raw, fileId) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      if (!fileId) return null
      return { id: fileId, state: "error", title: fileId, subtitle: "", icon: "", toggle: false,
        actions: [], devices: [], reason: "Status file is not valid JSON" }
    }
    let id = typeof raw.id === "string" && raw.id !== "" ? raw.id : fileId
    if (!id) return null
    let state = stateNames.indexOf(raw.state) !== -1 ? raw.state : "error"
    let reason = typeof raw.reason === "string" ? raw.reason : ""
    if (state !== raw.state && reason === "") reason = "Unknown state \"" + raw.state + "\""
    if ((state === "error" || state === "unsupported") && reason === "")
      reason = state === "error" ? "Something went wrong" : "Not supported on this machine"
    return {
      id: id,
      state: state,
      title: typeof raw.title === "string" && raw.title !== "" ? raw.title : id,
      subtitle: typeof raw.subtitle === "string" ? raw.subtitle : "",
      icon: typeof raw.icon === "string" ? raw.icon : "",
      toggle: raw.toggle === true,
      actions: Array.isArray(raw.actions) ? raw.actions.filter(function(a) {
        return a && Array.isArray(a.command) && a.command.length > 0
      }) : [],
      devices: Array.isArray(raw.devices) ? raw.devices : [],
      reason: reason,
      updated: typeof raw.updated === "string" ? raw.updated : ""
    }
  }

  function rebuild() {
    let byId = {}
    let i
    for (i = 0; i < fallbackModules.length; i++) {
      let f = normalize(fallbackModules[i], "")
      if (f) byId[f.id] = f
    }
    for (let fileId in fileTexts) {
      let parsed = null
      try { parsed = JSON.parse(fileTexts[fileId]) } catch (e) { parsed = undefined }
      let s = normalize(parsed, fileId)
      if (s) byId[s.id] = s
    }
    let list = Object.keys(byId).map(function(k) { return byId[k] })
    list.sort(function(a, b) {
      let ta = a.title.toLowerCase()
      let tb = b.title.toLowerCase()
      return ta < tb ? -1 : ta > tb ? 1 : (a.id < b.id ? -1 : 1)
    })
    if (JSON.stringify(list) !== JSON.stringify(modules)) {
      modules = list
      changed()
    }
  }

  Timer {
    id: coalesce
    interval: 16
    onTriggered: root.rebuild()
  }

  FolderListModel {
    id: folder
    folder: "file://" + root.statusDir
    nameFilters: ["*.json"]
    showDirs: false
    showHidden: false
    sortField: FolderListModel.Name
    onCountChanged: coalesce.restart()
  }

  Instantiator {
    id: files
    model: folder
    delegate: FileView {
      id: view
      required property string fileName
      required property string filePath
      required property date fileModified
      readonly property string fileId: fileName.replace(/\.json$/, "")
      path: filePath
      watchChanges: true
      printErrors: false
      blockLoading: true
      onFileChanged: reload()
      onFileModifiedChanged: reload()
      onLoaded: root.setFile(fileId, text())
      onLoadFailed: root.setFile(fileId, null)
      Component.onDestruction: root.setFile(fileId, null)

      readonly property Connections reloads: Connections {
        target: root
        function onReloadRequested() { view.reload() }
      }
    }
  }

  Process {
    id: fallback
    command: root.delightCommand.concat(["status", "--json"])
    stdout: StdioCollector {
      onStreamFinished: {
        let list = []
        try {
          let parsed = JSON.parse(this.text || "[]")
          if (Array.isArray(parsed)) list = parsed
        } catch (e) {
          list = []
        }
        root.fallbackModules = list
        coalesce.restart()
      }
    }
  }

  Timer {
    interval: root.fallbackInterval
    repeat: true
    running: root.fallbackEnabled && root.live
    triggeredOnStart: true
    onTriggered: root.pollFallback()
  }
}
