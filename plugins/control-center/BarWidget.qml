import QtQuick
import Quickshell
import qs.Ui
import "Delight"

// Bar icon that toggles the Control Center panel.
BarWidget {
  id: root
  moduleName: "delight.control-center"

  property var shell: null

  implicitWidth: vertical ? barSize : label.implicitWidth + 12
  implicitHeight: vertical ? label.implicitHeight + 12 : barSize

  function togglePanel() {
    if (shell && typeof shell.toggle === "function") shell.toggle("delight.control-center", "{}")
    else Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "delight.control-center", "{}"])
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: "󰒓"
    color: Tokens.foreground
    font.family: Tokens.fontFamily
    font.pixelSize: Tokens.iconSize
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.togglePanel()
  }
}
