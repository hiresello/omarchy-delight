pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var payload: ({})
  property var status: ({})
  property var config: ({ backend: "droidcam", connection: "auto", ip: "", port: 4747, size: "1280x720" })
  property var apps: ({})
  property var qr: ({})
  property string ipValue: ""
  property bool ipDirty: false

  function open(payloadJson) {
    opened = true
    ipDirty = false
    parse(payloadJson)
    refresh()
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.camera")
    else close()
  }

  function parse(text) {
    try {
      payload = JSON.parse(text || "{}")
      status = payload.status || ({})
      config = payload.config || config
      apps = payload.apps || ({})
      qr = payload.qr || ({})
      if (!ipDirty) ipValue = config.ip || ""
    } catch (e) {
      console.warn("delight.camera: bad panel JSON", e)
    }
  }

  function refresh() {
    if (!reader.running) reader.running = true
  }

  function run(command) {
    Quickshell.execDetached(command)
    refreshSoon.restart()
  }

  Process {
    id: reader
    command: ["delight", "camera", "panel", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.parse(this.text)
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 300
    onTriggered: root.refresh()
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
    WlrLayershell.namespace: "delight-camera-panel"

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
      title: "Continuity Camera"
      focus: true
      Keys.onEscapePressed: root.requestClose()

      Text {
        text: root.status.reason || root.status.subtitle || "Checking camera status…"
        color: root.status.state === "on" ? Tokens.accent : Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
        wrapMode: Text.Wrap
        width: parent.width
      }

      Text {
        text: "Backend"
        color: Tokens.foreground
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
      }

      CameraSegmented {
        options: [{ label: "DroidCam", value: "droidcam" }, { label: "Iriun", value: "iriun" }]
        value: root.config.backend
        onChosen: function(value) { root.run(["delight", "camera", "backend", value]) }
      }

      Text {
        text: "Connection"
        color: Tokens.foreground
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
      }

      CameraSegmented {
        options: [{ label: "Auto", value: "auto" }, { label: "USB", value: "usb" }, { label: "Wi-Fi", value: "wifi" }]
        value: root.config.connection
        onChosen: function(value) { root.run(["delight", "camera", "set", "connection", value]) }
      }

      Row {
        width: parent.width
        spacing: Tokens.spacing

        Rectangle {
          width: parent.width - saveButton.implicitWidth - parent.spacing
          height: 36
          radius: Tokens.radiusSmall
          color: Tokens.surface
          border.color: Tokens.border

          TextInput {
            id: ipInput
            anchors.fill: parent
            anchors.margins: Tokens.spacing
            text: root.ipValue
            color: Tokens.foreground
            selectionColor: Tokens.accent
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
            verticalAlignment: TextInput.AlignVCenter
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            onTextChanged: {
              root.ipValue = text
              root.ipDirty = true
            }
          }
        }

        CameraButton {
          id: saveButton
          label: "Save IP"
          onClicked: {
            root.run(["delight", "camera", "set", "ip", root.ipValue])
            root.ipDirty = false
          }
        }
      }

      Row {
        spacing: Tokens.spacing

        CameraButton {
          label: root.status.state === "on" ? "Disconnect" : "Connect"
          selected: root.status.state === "on"
          onClicked: root.run(["delight", "camera", root.status.state === "on" ? "disconnect" : "connect"])
        }

        CameraButton {
          label: "Enable"
          onClicked: root.run(["delight", "camera", "enable"])
        }
      }

      Text {
        width: parent.width
        text: root.config.backend === "iriun"
          ? "Iriun discovers the phone itself and uses its own Iriun Webcam device."
          : "Android: install DroidCam; use the same Wi-Fi or enable USB debugging. iPhone: install DroidCam; use the same Wi-Fi or trust this computer over USB."
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
        wrapMode: Text.Wrap
      }

      Row {
        spacing: Tokens.spacing
        visible: root.config.backend !== "iriun"

        Image {
          source: root.qr.android || ""
          visible: !!root.qr.android
          width: visible ? 72 : 0
          height: visible ? 72 : 0
          fillMode: Image.PreserveAspectFit
        }

        Text {
          text: root.qr.android ? "" : (root.apps.android || "")
          visible: text !== ""
          color: Tokens.accent
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeSmall
          wrapMode: Text.WrapAnywhere
          width: visible ? parent.width : 0
        }
      }

      Row {
        spacing: Tokens.spacing
        visible: root.config.backend !== "iriun"

        Image {
          source: root.qr.ios || ""
          visible: !!root.qr.ios
          width: visible ? 72 : 0
          height: visible ? 72 : 0
          fillMode: Image.PreserveAspectFit
        }

        Text {
          text: root.qr.ios ? "" : (root.apps.ios || "")
          visible: text !== ""
          color: Tokens.accent
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeSmall
          wrapMode: Text.WrapAnywhere
          width: visible ? parent.width : 0
        }
      }

      Text {
        visible: root.config.backend === "iriun"
        text: root.apps.iriun || "https://iriun.com/"
        color: Tokens.accent
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
        wrapMode: Text.Wrap
        width: parent.width
      }
    }
  }
}
