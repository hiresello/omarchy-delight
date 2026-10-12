//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=15000
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "../.."
import "../../Delight"

// Offscreen render test for the Control Center (run by ../render-test.sh).
// Renders the real panel content + bar widget from fixture status files, then
// drives it with key events and checks what reached the stubbed `delight`.
ShellRoot {
  id: shellRoot

  readonly property string outDir: Quickshell.env("DELIGHT_TEST_OUT")
  readonly property string omarchyDir: Quickshell.env("DELIGHT_TEST_OMARCHY")
  readonly property string logPath: Quickshell.env("DELIGHT_STUB_LOG")
  readonly property string fixtureIds: Quickshell.env("DELIGHT_TEST_IDS")
  readonly property var themes: String(Quickshell.env("DELIGHT_TEST_THEMES") || "tokyo-night catppuccin-latte").split(" ")
  property var lines: []
  property int failures: 0
  property int count: 0
  property string themeName: ""
  property string wallpaper: ""

  function tap(ok, name, detail) {
    count++
    if (!ok) failures++
    lines.push((ok ? "ok " : "not ok ") + count + " - " + name + (!ok && detail ? "\n  # " + detail : ""))
  }

  function findTile(title) {
    let items = view.focusables()
    for (let i = 0; i < items.length; i++) if (items[i].title === title) return items[i]
    return null
  }

  function logText() {
    stubLog.reload()
    return stubLog.text()
  }

  function shot(name, item) {
    let target = item || stage
    target.grabToImage(function(result) { result.saveToFile(shellRoot.outDir + "/" + name + ".png") })
  }

  function loadTheme(name) {
    themeName = name
    colors.path = omarchyDir + "/themes/" + name + "/colors.toml"
    colors.waitForJob()
    Commons.Color.loadColors(colors.text())
    Commons.Style.scheduleRefresh()
    let bg = String(Quickshell.env("DELIGHT_TEST_WALLPAPER_" + name.replace(/-/g, "_")) || "")
    wallpaper = bg !== "" ? "file://" + bg : ""
  }

  FileView { id: colors; blockLoading: true; printErrors: false }
  FileView { id: stubLog; path: shellRoot.logPath; blockLoading: true; printErrors: false }
  FileView { id: tapOut; path: shellRoot.outDir + "/results.tap"; atomicWrites: true }

  StatusStore { id: store; fallbackInterval: 500 }
  StatusStore {
    id: emptyStore
    statusDir: shellRoot.outDir + "/empty-status"
    fallbackEnabled: false
  }
  Catalog { id: catalog; active: true }
  Actions { id: commands; terminalCommand: ["env"] }

  // The harness steps run one after another; each returns true when done.
  property var steps: []
  property int step: 0
  property int waited: 0
  property var mark: 0

  Timer {
    id: runner
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      if (shellRoot.step >= shellRoot.steps.length) {
        running = false
        tapOut.setText("1.." + shellRoot.count + "\n" + shellRoot.lines.join("\n") + "\n")
        Qt.callLater(Qt.quit)
        return
      }
      let s = shellRoot.steps[shellRoot.step]
      let done = false
      try { done = s.run() } catch (e) { shellRoot.tap(false, s.name, String(e)); done = true }
      shellRoot.waited += interval
      if (!done && shellRoot.waited > (s.timeout || 5000)) {
        shellRoot.tap(false, s.name, "timed out")
        done = true
      }
      if (done) {
        shellRoot.step++
        shellRoot.waited = 0
      }
    }
  }

  TestCase {
    id: keys
    name: "keys"
    when: false
  }

  Component.onCompleted: {
    let ids = fixtureIds.split(" ").filter(function(x) { return x !== "" })
    let fixtures = {}
    let stateSeen = {}
    loadTheme(themes[0])
    steps = [
      { name: "loads all fixture status files", run: function() {
        if (store.modules.length < ids.length) return false
        shellRoot.tap(store.modules.length === ids.length, "loads all " + ids.length + " fixture status files", "got " + store.modules.length)
        for (let i = 0; i < store.modules.length; i++) fixtures[store.modules[i].id] = store.modules[i]
        return true
      } },
      { name: "devices and features load", run: function() {
        if (catalog.devices.length === 0 || catalog.features.length === 0) return false
        shellRoot.tap(true, "device strip and feature list load from delight devices --json / delight list")
        return true
      } },
      { name: "every state renders", run: function() {
        let states = ["on", "off", "busy", "needs-setup", "unsupported", "error"]
        for (let id in fixtures) {
          let m = fixtures[id]
          let tile = shellRoot.findTile(m.title)
          stateSeen[m.state] = true
          shellRoot.tap(!!tile && tile.status === m.state && tile.visible && tile.width > 0 && tile.height > 0,
            "renders " + m.state + " " + (m.toggle ? "tile" : "row") + " for " + id)
          if (tile) shellRoot.tap(tile.compact === !m.toggle, id + " is a " + (m.toggle ? "large tile" : "compact row"))
          if (tile && (m.state === "unsupported" || m.state === "error" || m.state === "needs-setup"))
            shellRoot.tap(tile.caption === m.reason, id + " shows its reason", "caption=" + tile.caption)
        }
        for (let i = 0; i < states.length; i++) shellRoot.tap(stateSeen[states[i]] === true, "fixtures cover state " + states[i])
        return true
      } },
      { name: "bar dot", run: function() {
        let dot = bar.store.attention
        shellRoot.tap(dot === "error", "bar widget shows the attention dot for busy/error", "attention=" + dot)
        return true
      } },
      { name: "screenshot theme 1", timeout: 2000, run: function() {
        if (shellRoot.waited < 600) return false
        view.focusFirst()
        shellRoot.shot("control-center-" + shellRoot.themeName)
        return true
      } },
      { name: "keyboard: first tile focused", run: function() {
        let items = view.focusables()
        shellRoot.tap(items.length > 0 && items[0].activeFocus, "first tile has focus on open")
        keys.keyClick(Qt.Key_Right)
        shellRoot.tap(items[1].activeFocus, "Right moves to the next tile")
        keys.keyClick(Qt.Key_J)
        shellRoot.tap(items[3].activeFocus, "j / Down moves down a tile row")
        keys.keyClick(Qt.Key_Up)
        keys.keyClick(Qt.Key_Left)
        shellRoot.tap(items[0].activeFocus, "Up + Left return to the first tile")
        return true
      } },
      { name: "keyboard: Space toggles", run: function() {
        let tile = view.focusables()[0]
        keys.keyClick(Qt.Key_Space)
        let want = tile.title
        let id = ""
        for (let k in fixtures) if (fixtures[k].title === want) id = k
        shellRoot.mark = id
        return true
      } },
      { name: "toggle reaches delight", run: function() {
        let ok = shellRoot.logText().split("\n").indexOf(shellRoot.mark + " toggle") !== -1
        if (!ok) return false
        shellRoot.tap(true, "Space on a tile runs `delight " + shellRoot.mark + " toggle`")
        return true
      } },
      { name: "detail: first action", run: function() {
        let tile = shellRoot.findTile(fixtures.airplay ? fixtures.airplay.title : "")
        if (!tile) { shellRoot.tap(false, "action fixture present"); return true }
        tile.forceActiveFocus()
        keys.keyClick(".")
        return true
      } },
      { name: "detail action reaches delight", run: function() {
        if (shellRoot.logText().indexOf("airplay settings") === -1) return false
        shellRoot.tap(true, "\"…\" runs the module's first action")
        return true
      } },
      { name: "detail: open fallback", run: function() {
        let tile = shellRoot.findTile(fixtures.control.title)
        tile.detailRequested()
        return true
      } },
      { name: "open fallback reaches delight", run: function() {
        if (shellRoot.logText().indexOf("control open") === -1) return false
        shellRoot.tap(true, "\"…\" without actions runs `delight <id> open`")
        return true
      } },
      { name: "unsupported click explains", run: function() {
        let tile = shellRoot.findTile(fixtures.sidecar.title)
        tile.forceActiveFocus()
        keys.keyClick(Qt.Key_Space)
        return true
      } },
      { name: "unsupported does not toggle", timeout: 1500, run: function() {
        if (shellRoot.waited < 400) return false
        let log = shellRoot.logText()
        shellRoot.tap(log.indexOf("sidecar toggle") === -1 && log.indexOf("sidecar open") === -1, "unsupported tiles never run toggle")
        shellRoot.tap(view.toast.shown && view.toast.text === fixtures.sidecar.reason, "activating an unsupported tile explains why in a quiet toast")
        return true
      } },
      { name: "live status update", run: function() {
        writer.command = ["sh", "-c", "f=$1/control.json; jq '.state=\"on\" | .subtitle=\"Sharing with iPad\"' \"$f\" >\"$f.tmp\" && mv \"$f.tmp\" \"$f\"", "sh", store.statusDir]
        writer.running = true
        shellRoot.mark = Date.now()
        return true
      } },
      { name: "live status lands", run: function() {
        let tile = shellRoot.findTile(fixtures.control.title)
        if (!tile || tile.status !== "on") return false
        shellRoot.tap(true, "status file rewrite restyles the tile live (" + (Date.now() - shellRoot.mark) + " ms)")
        return true
      } },
      { name: "theme switch", run: function() {
        let tile = shellRoot.findTile(fixtures.airplay.title)
        shellRoot.mark = { accent: String(Tokens.accent), badge: String(tile.activeColor), tile: tile }
        shellRoot.loadTheme(shellRoot.themes[1])
        return true
      } },
      { name: "screenshot theme 2", timeout: 2000, run: function() {
        if (shellRoot.waited < 600) return false
        let m = shellRoot.mark
        shellRoot.tap(m.accent !== String(Tokens.accent) && m.badge !== String(m.tile.activeColor),
          "theme switch restyles live without reload (accent " + m.accent + " -> " + Tokens.accent + ")")
        view.focusFirst()
        shellRoot.shot("control-center-" + shellRoot.themeName)
        return true
      } },
      { name: "empty state", timeout: 2000, run: function() {
        emptyStage.visible = true
        if (shellRoot.waited < 600) return false
        shellRoot.tap(emptyView.empty && emptyView.installVisible, "no status files shows the install list")
        shellRoot.tap(emptyView.available.length === 2, "install list comes from `delight list` (uninstalled only)")
        shellRoot.shot("control-center-empty-" + shellRoot.themeName, emptyStage)
        return true
      } },
      { name: "install action", run: function() {
        emptyView.installRequested(emptyView.available[0].id)
        shellRoot.mark = emptyView.available[0].id
        return true
      } },
      { name: "install reaches delight", run: function() {
        if (shellRoot.logText().indexOf(shellRoot.mark + " install") === -1) return false
        shellRoot.tap(true, "Install runs `delight <id> install` in a terminal")
        return true
      } },
      { name: "catalogue", timeout: 2000, run: function() {
        catalogueStage.visible = true
        if (shellRoot.waited < 700) return false
        shellRoot.shot("catalogue-" + shellRoot.themeName, catalogueStage)
        return true
      } },
      { name: "back to theme 1", timeout: 1500, run: function() {
        if (shellRoot.waited < 400) return false
        shellRoot.loadTheme(shellRoot.themes[0])
        return true
      } },
      { name: "catalogue theme 1", timeout: 2000, run: function() {
        if (shellRoot.waited < 700) return false
        shellRoot.shot("catalogue-" + shellRoot.themeName, catalogueStage)
        shellRoot.tap(true, "component catalogue rendered in " + shellRoot.themes.join(" and "))
        return true
      } },
      { name: "flush", timeout: 1500, run: function() { return shellRoot.waited >= 500 } }
    ]
  }

  Process { id: writer }

  FloatingWindow {
    id: win
    implicitWidth: 1280
    implicitHeight: 800
    color: "black"

    Item {
      id: stage
      anchors.fill: parent

      Rectangle { anchors.fill: parent; color: Tokens.background }
      Image {
        anchors.fill: parent
        source: shellRoot.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
      }

      // Stand-in for the Omarchy bar so the widget renders in context.
      Rectangle {
        id: barStrip
        width: parent.width
        height: Commons.Style.bar.sizeHorizontal
        color: Commons.Color.background

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Mon Oct 12  09:41"
          color: Commons.Color.foreground
          font.family: Tokens.fontFamily
          font.pixelSize: Commons.Style.bar.iconFont
        }

        BarWidget {
          id: bar
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      ControlCenterView {
        id: view
        x: parent.width - width - 16
        y: barStrip.height + 8
        width: Tokens.sheetWidth
        height: implicitHeight
        focus: true
        toggles: store.toggles
        rows: store.rows
        devices: catalog.devices
        available: catalog.available
        onToggleRequested: status => commands.toggle(status)
        onDetailRequested: status => commands.detail(status)
        onInstallRequested: id => commands.install(id)
      }
    }

    Item {
      id: emptyStage
      visible: false
      anchors.fill: parent
      Rectangle { anchors.fill: parent; color: Tokens.background }
      Image { anchors.fill: parent; source: shellRoot.wallpaper; fillMode: Image.PreserveAspectCrop }
      ControlCenterView {
        id: emptyView
        x: parent.width - width - 16
        y: 40
        width: Tokens.sheetWidth
        height: implicitHeight
        toggles: emptyStore.toggles
        rows: emptyStore.rows
        available: catalog.available
        onInstallRequested: id => commands.install(id)
      }
    }

    Catalogue {
      id: catalogueStage
      visible: false
      anchors.fill: parent
      wallpaper: shellRoot.wallpaper
    }
  }
}
