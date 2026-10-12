pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import ".."
import "../Delight"

// Live acceptance run (see live.sh): the real bar widget + layer-shell panel
// on a Wayland compositor, with real keystrokes from wtype and grim captures.
ShellRoot {
  id: shellRoot

  readonly property string outDir: Quickshell.env("DELIGHT_TEST_OUT")
  readonly property string omarchyDir: Quickshell.env("DELIGHT_TEST_OMARCHY")
  readonly property var themes: String(Quickshell.env("DELIGHT_TEST_THEMES") || "tokyo-night catppuccin-latte").split(" ")
  readonly property int runs: 20
  property var lines: []
  property var timings: []
  property int failures: 0
  property int count: 0
  property string themeName: ""
  property var frameWindow: null
  property real clickedAt: 0
  property var mark: null

  function tap(ok, name) {
    count++
    if (!ok) failures++
    lines.push((ok ? "ok " : "not ok ") + count + " - " + name)
  }

  function logText() {
    stubLog.reload()
    stubLog.waitForJob()
    return stubLog.text()
  }

  function loadTheme(name) {
    themeName = name
    colors.path = omarchyDir + "/themes/" + name + "/colors.toml"
    colors.waitForJob()
    Commons.Color.loadColors(colors.text())
    Commons.Style.scheduleRefresh()
  }

  function sh(argv) {
    helper.command = argv
    helper.running = true
  }

  FileView { id: colors; blockLoading: true; printErrors: false }
  FileView { id: stubLog; path: Quickshell.env("DELIGHT_STUB_LOG"); blockLoading: true; printErrors: false }
  FileView { id: tapOut; path: shellRoot.outDir + "/live.tap"; atomicWrites: true }
  Process {
    id: helper
    stderr: StdioCollector { onStreamFinished: if (text !== "") console.warn("helper:", text) }
    onExited: (code, status) => console.warn("helper exit", code, JSON.stringify(helper.command))
  }

  QtObject {
    id: facade
    function toggle(id, payload) {
      if (panel.opened) panel.close()
      else panel.open(payload)
    }
    function hide(id) { panel.close() }
  }

  // qmllint disable uncreatable-type missing-property
  PanelWindow {
    id: barWindow
    anchors { top: true; left: true; right: true }
    implicitHeight: Commons.Style.bar.sizeHorizontal
    color: Commons.Color.background

    BarWidget {
      id: bar
      shell: facade
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  // qmllint enable uncreatable-type missing-property

  ControlCenterPanel {
    id: panel
    shell: facade
    manifest: ({ keepLoaded: true })
  }

  // Lives inside the panel's window so it can see that window's frames.
  Component {
    id: probe
    Item {
      id: probeItem
      property var win: Window.window
      signal frame()
      onWinChanged: if (win) win.frameSwapped.connect(probeItem.frame)
    }
  }

  function onFrame() {
    if (clickedAt > 0 && panel.opened) {
      timings.push(Date.now() - clickedAt)
      clickedAt = 0
    }
  }

  TestCase { id: input; name: "input"; when: false }

  property var steps: []
  property int step: 0
  property int waited: 0
  property int run: 0

  Timer {
    interval: 20
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
      try { done = s.run() } catch (e) { shellRoot.tap(false, s.name + ": " + e); done = true }
      shellRoot.waited += interval
      if (!done && shellRoot.waited > (s.timeout || 8000)) { shellRoot.tap(false, s.name + ": timed out"); done = true }
      if (done) { shellRoot.step++; shellRoot.waited = 0 }
    }
  }

  Component.onCompleted: {
    loadTheme(themes[0])
    steps = [
      { name: "8 fixture statuses", run: function() {
        if (panel.store.modules.length < 8 || shellRoot.waited < 1000) return false
        shellRoot.tap(panel.store.modules.length === 8, "panel sees 8 fixture status files")
        return true
      } },
      { name: "click opens", timeout: 30000, run: function() {
        if (shellRoot.clickedAt > 0) return false
        if (shellRoot.waited < 250) return false
        if (panel.opened) { input.mouseClick(bar); shellRoot.waited = 0; return false }
        if (shellRoot.timings.length >= shellRoot.runs) return true
        if (!shellRoot.frameWindow) {
          shellRoot.frameWindow = probe.createObject(panel.view)
          shellRoot.frameWindow.frame.connect(shellRoot.onFrame)
        }
        shellRoot.clickedAt = Date.now()
        input.mouseClick(bar)
        shellRoot.waited = 0
        return false
      } },
      { name: "latency", run: function() {
        let cold = shellRoot.timings[0]
        let t = shellRoot.timings.slice(1).sort(function(a, b) { return a - b })
        let p50 = t[Math.floor(t.length / 2)], max = t[t.length - 1]
        let p95 = t[Math.min(t.length - 1, Math.floor(t.length * 0.95))]
        shellRoot.tap(cold < 150, "first bar click -> first panel frame: " + cold + " ms (budget 150)")
        shellRoot.tap(max < 150, "bar click -> first panel frame over " + t.length + " more runs: p50 " + p50 + " ms, p95 " + p95 + " ms, max " + max + " ms (budget 150)")
        return true
      } },
      { name: "open for keys", run: function() {
        if (!panel.opened) input.mouseClick(bar)
        return shellRoot.waited > 600
      } },
      { name: "screenshot 1", run: function() {
        if (shellRoot.waited === 20) shellRoot.sh(["grim", shellRoot.outDir + "/live-" + shellRoot.themeName + ".png"])
        return shellRoot.waited > 800
      } },
      { name: "wtype", run: function() {
        if (shellRoot.waited === 20) {
          let items = panel.view.focusables()
          shellRoot.mark = items[5].title
          shellRoot.sh(["wtype", "-s", "400", "-k", "Down", "-k", "Down", "-k", "Right", "-s", "200", "-k", "space"])
        }
        return shellRoot.waited > 1600
      } },
      { name: "toggle via keyboard", run: function() {
        let id = ""
        for (let i = 0; i < panel.store.modules.length; i++)
          if (panel.store.modules[i].title === shellRoot.mark) id = panel.store.modules[i].id
        if (shellRoot.logText().split("\n").indexOf(id + " toggle") === -1) return false
        shellRoot.tap(true, "real keystrokes (wtype Down Down Right Space) run `delight " + id + " toggle`")
        return true
      } },
      { name: "theme switch", run: function() {
        shellRoot.mark = String(Commons.Color.accent)
        shellRoot.loadTheme(shellRoot.themes[1])
        return true
      } },
      { name: "screenshot 2", run: function() {
        if (shellRoot.waited === 400) shellRoot.sh(["grim", shellRoot.outDir + "/live-" + shellRoot.themeName + ".png"])
        if (shellRoot.waited < 1200) return false
        shellRoot.tap(panel.opened && shellRoot.mark !== String(Tokens.accent), "open panel restyles live on theme switch (" + shellRoot.mark + " -> " + Tokens.accent + ")")
        return true
      } },
      { name: "escape closes", run: function() {
        if (shellRoot.waited === 20) shellRoot.sh(["wtype", "-s", "400", "-k", "Escape"])
        if (shellRoot.waited < 1200) return false
        shellRoot.tap(!panel.opened, "Escape closes the panel")
        return true
      } }
    ]
  }
}
