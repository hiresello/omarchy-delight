pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

// Instant Hotspot setup: choose the phone's hotspot network and its paired
// Bluetooth device, then run `delight hotspot setup --ssid ... --bt ...`.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var ssids: []
  property var devices: []
  property string ssid: ""
  property string mac: ""
  property string message: ""
  property bool loading: false

  function open(payloadJson) {
    opened = true
    message = ""
    refresh()
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.hotspot")
    else close()
  }

  function refresh() {
    loading = true
    if (!candidates.running) candidates.running = true
  }

  function parse(text) {
    loading = false
    try {
      const data = JSON.parse(text || "{}")
      ssids = Array.isArray(data.ssids) ? data.ssids : []
      devices = Array.isArray(data.devices) ? data.devices : []
      const selected = data.selected || {}
      if (ssid === "") ssid = selected.ssid || ""
      if (mac === "") mac = selected.mac || ""
    } catch (e) {
      console.warn("delight.hotspot: bad candidates JSON", e)
      message = "Could not read networks and devices."
    }
  }

  function save() {
    if (ssid === "" || mac === "") {
      message = "Choose a hotspot and a phone first."
      return
    }
    message = "Saving…"
    setup.command = ["delight", "hotspot", "setup", "--ssid", ssid, "--bt", mac]
    setup.running = true
  }

  function connectNow() {
    Quickshell.execDetached(["delight", "hotspot", "connect"])
    message = "Connecting… keep the phone's hotspot screen open on iPhone."
  }

  Process {
    id: candidates
    command: ["delight", "hotspot", "candidates", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.parse(this.text)
    }
  }

  Process {
    id: setup
    stdout: StdioCollector {}
    stderr: StdioCollector {
      id: setupErr
    }
    onExited: function(exitCode) {
      root.message = exitCode === 0 ? "Instant Hotspot is set up." : (setupErr.text.trim() || "Setup failed (exit " + exitCode + ").")
    }
  }

  component Row2: Rectangle {
    id: row
    property string label: ""
    property string detail: ""
    property bool selected: false
    signal clicked()

    width: parent ? parent.width : 0
    height: 40
    radius: Tokens.radiusSmall
    color: selected ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.22) : area.containsMouse ? Tokens.surfaceRaised : Tokens.surface
    border.color: selected ? Tokens.accent : Tokens.border
    border.width: 1

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Tokens.padding
      anchors.right: hint.left
      anchors.rightMargin: Tokens.spacing
      anchors.verticalCenter: parent.verticalCenter
      text: row.label
      elide: Text.ElideRight
      color: Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSize
    }

    Text {
      id: hint
      anchors.right: parent.right
      anchors.rightMargin: Tokens.padding
      anchors.verticalCenter: parent.verticalCenter
      text: row.detail
      color: Tokens.muted
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.clicked()
    }
  }

  component Button: Rectangle {
    id: button
    property string label: ""
    property bool primary: false
    signal clicked()

    implicitWidth: buttonText.implicitWidth + Tokens.padding * 2
    implicitHeight: 34
    radius: Tokens.radiusSmall
    color: primary ? Tokens.accent : buttonArea.containsMouse ? Tokens.surfaceRaised : Tokens.surface
    border.color: Tokens.border
    border.width: 1

    Text {
      id: buttonText
      anchors.centerIn: parent
      text: button.label
      color: button.primary ? Tokens.background : Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSize
      font.bold: button.primary
    }

    MouseArea {
      id: buttonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }

  // qmllint's Quickshell type info marks PanelWindow uncreatable; the shell creates it fine.
  // qmllint disable uncreatable-type missing-property
  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "delight-hotspot"

    anchors {
      top: true
      right: true
    }
    margins {
      top: 8
      right: 8
    }

    implicitWidth: sheet.implicitWidth
    implicitHeight: sheet.implicitHeight

    Sheet {
      id: sheet
      anchors.fill: parent
      title: "Instant Hotspot"
      focus: true
      Keys.onEscapePressed: root.requestClose()

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Hotspot network. On iPhone, keep Settings › Personal Hotspot open so it shows up."
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }

      Text {
        visible: !root.loading && root.ssids.length === 0
        text: "No Wi-Fi networks found."
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          model: root.ssids.slice(0, 6)

          Row2 {
            required property var modelData
            label: modelData.ssid || ""
            detail: modelData.active ? "connected" : modelData.saved ? "saved" : modelData.signal ? modelData.signal + "%" : ""
            selected: modelData.ssid === root.ssid
            onClicked: root.ssid = modelData.ssid
          }
        }
      }

      Text {
        text: "Phone (paired Bluetooth device)"
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }

      Text {
        visible: !root.loading && root.devices.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: "No paired devices. Pair your phone in Bluetooth settings first."
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          model: root.devices.slice(0, 6)

          Row2 {
            required property var modelData
            label: modelData.name || modelData.mac
            detail: modelData.connected ? "connected" : modelData.phone ? "phone" : ""
            selected: modelData.mac === root.mac
            onClicked: root.mac = modelData.mac
          }
        }
      }

      Text {
        visible: root.message !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.message
        color: Tokens.foreground
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }

      Row {
        spacing: Tokens.spacing

        Button {
          label: "Save"
          primary: true
          onClicked: root.save()
        }

        Button {
          label: "Connect now"
          onClicked: root.connectNow()
        }

        Button {
          label: "Refresh"
          onClicked: root.refresh()
        }
      }
    }
  }
}
