import QtQuick
import Quickshell.Io

// Slow-changing data the panel shows: `delight devices --json` and
// `delight list`. Refreshed on open and every `interval` ms while visible.
Item {
  id: root

  property bool active: false
  property int interval: 30000
  property var delightCommand: ["delight"]
  property var devices: []
  // [{id, name, installed}] from `delight list`.
  property var features: []
  readonly property var available: features.filter(function(f) { return !f.installed })

  function refresh() {
    if (!devicesProc.running) devicesProc.running = true
    if (!listProc.running) listProc.running = true
  }

  onActiveChanged: if (active) refresh()

  Process {
    id: devicesProc
    command: root.delightCommand.concat(["devices", "--json"])
    stdout: StdioCollector {
      onStreamFinished: {
        let list = []
        try {
          let parsed = JSON.parse(this.text || "[]")
          if (Array.isArray(parsed)) list = parsed.filter(function(d) { return d && (d.name || d.id) })
        } catch (e) {
          list = []
        }
        list.sort(function(a, b) { return (b.connected === true) - (a.connected === true) })
        root.devices = list
      }
    }
  }

  Process {
    id: listProc
    command: root.delightCommand.concat(["list"])
    stdout: StdioCollector {
      onStreamFinished: {
        let out = []
        let lines = String(this.text || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
          let cols = lines[i].split("\t")
          if (cols.length < 3 || cols[0] === "") continue
          out.push({ id: cols[0], installed: cols[1] === "installed", name: cols.slice(2).join("\t") })
        }
        root.features = out
      }
    }
  }

  Timer {
    interval: root.interval
    repeat: true
    running: root.active
    onTriggered: root.refresh()
  }
}
