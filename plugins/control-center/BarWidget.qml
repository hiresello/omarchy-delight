import QtQuick
import Quickshell
import qs.Ui
import "Delight"

// Bar icon that toggles the Control Center. A dot marks modules needing
// attention: urgent for any error, accent (pulsing) for any busy module.
BarWidget {
  id: root
  moduleName: "delight.control-center"

  property var shell: null
  property alias store: statusStore
  readonly property string attention: statusStore.attention

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function togglePanel() {
    if (shell && typeof shell.toggle === "function") shell.toggle("delight.control-center", "{}")
    else Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "delight.control-center", "{}"])
  }

  StatusStore {
    id: statusStore
    live: false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘮"
    tooltipText: root.attention === "error" ? "Control Center — needs attention"
      : root.attention === "busy" ? "Control Center — working…" : "Control Center"
    onPressed: root.togglePanel()
  }

  Rectangle {
    id: dot
    objectName: "attentionDot"
    visible: root.attention !== ""
    width: Math.max(5, Math.round(button.height / 6))
    height: width
    radius: width / 2
    x: Math.round(root.width / 2 + button.visualIconSize / 2 - width / 2)
    y: Math.round(root.height / 2 - button.visualIconSize / 2 - height / 3)
    color: root.attention === "error" ? Tokens.urgent : Tokens.accent
    border.width: 1
    border.color: Tokens.background

    SequentialAnimation on opacity {
      running: dot.visible && root.attention === "busy" && !Tokens.reduceMotion
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
  }
}
