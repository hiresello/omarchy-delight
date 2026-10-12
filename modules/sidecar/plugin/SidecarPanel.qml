pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

// Sidecar panel: start/stop the tablet display, choose preset and
// arrangement, and pair Moonlight with the PIN it shows. All actions go
// through `delight sidecar ...`; credentials never reach QML.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var info: ({})
  property string message: ""
  property bool busy: false

  readonly property var status: info.status || ({})
  readonly property var config: info.config || ({})
  readonly property bool active: status.state === "on"
  readonly property bool viewOnly: config.backend === "deskreen"

  function open(payloadJson) {
    try {
      const parsed = JSON.parse(payloadJson || "{}")
      if (parsed && parsed.status) info = parsed
    } catch (e) {
      console.warn("delight.sidecar: bad payload", e)
    }
    message = ""
    opened = true
    refresh()
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.sidecar")
    else close()
  }

  function refresh() {
    if (!reader.running) reader.running = true
  }

  function run(args, label) {
    if (runner.running) return
    busy = true
    message = label || ""
    runner.command = ["delight", "sidecar"].concat(args)
    runner.running = true
  }

  function submitPin() {
    const pin = pinInput.text.trim()
    if (!/^[0-9]{4}$/.test(pin)) {
      message = "Enter the 4-digit PIN Moonlight shows"
      return
    }
    run(["pair", pin], "Pairing…")
    pinInput.text = ""
  }

  component Chip: Rectangle {
    id: chip

    property string label: ""
    property bool selected: false
    property bool usable: true
    signal clicked()

    implicitWidth: chipText.implicitWidth + Tokens.padding * 2
    implicitHeight: chipText.implicitHeight + Tokens.spacing * 2
    radius: Tokens.radiusSmall
    opacity: usable ? 1 : 0.5
    color: selected ? Tokens.accent : (chipArea.containsMouse ? Tokens.surfaceRaised : Tokens.surface)
    border.color: Tokens.border
    border.width: 1

    Behavior on color { ColorAnimation { duration: Tokens.animationFast } }

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: chip.selected ? Tokens.background : Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }

    MouseArea {
      id: chipArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: chip.usable
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  component Label: Text {
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.WordWrap
    color: Tokens.foreground
    font.family: Tokens.fontFamily
    font.pixelSize: Tokens.fontSize
  }

  component Heading: Text {
    color: Tokens.muted
    font.family: Tokens.fontFamily
    font.pixelSize: Tokens.fontSizeSmall
    font.bold: true
  }

  Process {
    id: reader
    command: ["delight", "sidecar", "info", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(this.text || "{}")
          if (parsed && parsed.status) root.info = parsed
        } catch (e) {
          console.warn("delight.sidecar: bad info JSON", e)
        }
      }
    }
  }

  Process {
    id: runner
    stdout: StdioCollector { id: runnerOut }
    stderr: StdioCollector { id: runnerErr }
    onExited: function(exitCode) {
      root.busy = false
      const out = (runnerOut.text || "").trim()
      const err = (runnerErr.text || "").trim().replace(/^delight: /, "")
      root.message = exitCode === 0 ? out : (err || "Failed (exit " + exitCode + ")")
      root.refresh()
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  // qmllint disable uncreatable-type missing-property
  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "delight-sidecar"

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
      implicitWidth: 400
      title: "Sidecar"
      focus: true
      Keys.onEscapePressed: root.requestClose()

      Row {
        spacing: Tokens.spacing

        Chip {
          label: root.active ? "Stop tablet display" : "Start tablet display"
          selected: root.active
          usable: !root.busy
          onClicked: root.run([root.active ? "stop" : "start"], root.active ? "Stopping…" : "Starting…")
        }

        Label {
          width: sheet.width - Tokens.padding * 2 - 180
          anchors.verticalCenter: parent.verticalCenter
          text: root.status.state === "unsupported" || root.status.state === "error"
            ? (root.status.reason || "")
            : (root.status.subtitle || "")
          color: Tokens.muted
          font.pixelSize: Tokens.fontSizeSmall
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
        }
      }

      Heading { text: "ARRANGEMENT" }

      Row {
        spacing: Tokens.spacing

        Repeater {
          model: ["left", "above", "right", "below"]

          Chip {
            required property string modelData
            label: modelData
            selected: root.config.arrangement === modelData
            usable: !root.busy
            onClicked: root.run(["set", "arrangement", modelData], "")
          }
        }
      }

      Heading { text: "TABLET" }

      Flow {
        width: parent.width
        spacing: Tokens.spacing

        Repeater {
          model: root.info.presets || []

          Chip {
            required property var modelData
            label: modelData.label
            selected: root.config.preset === modelData.id
            usable: !root.busy
            onClicked: root.run(["set", "preset", modelData.id], "")
          }
        }

        Chip {
          label: root.config.orientation === "portrait" ? "Portrait" : "Landscape"
          usable: !root.busy
          onClicked: root.run(["set", "orientation", root.config.orientation === "portrait" ? "landscape" : "portrait"], "")
        }
      }

      Heading { text: root.viewOnly ? "DESKREEN (VIEW-ONLY, NO INPUT)" : "PAIR MOONLIGHT" }

      Label {
        visible: !root.viewOnly
        text: "1. Install Moonlight on the tablet (App Store / Google Play).\n"
          + "2. Start the tablet display, open Moonlight and add this PC: "
          + ((root.info.hosts || []).join(", ") || "this computer's LAN or Tailscale IP") + "\n"
          + "3. Type the 4-digit PIN Moonlight shows:"
      }

      Row {
        visible: !root.viewOnly
        spacing: Tokens.spacing * 2

        Repeater {
          model: [
            { name: "iPad / iPhone", png: (root.info.qr || {}).ios || "", url: (root.info.moonlight || {}).ios || "" },
            { name: "Android", png: (root.info.qr || {}).android || "", url: (root.info.moonlight || {}).android || "" }
          ]

          Column {
            id: qrColumn
            required property var modelData
            spacing: Tokens.spacingXs
            visible: modelData.png !== ""

            Image {
              width: Tokens.space(112)
              height: Tokens.space(112)
              smooth: false
              source: qrColumn.modelData.png ? "file://" + qrColumn.modelData.png : ""
            }

            Heading { text: qrColumn.modelData.name }
          }
        }
      }

      Row {
        visible: !root.viewOnly
        spacing: Tokens.spacing

        Rectangle {
          width: Tokens.space(96)
          height: Tokens.badgeSize
          radius: Tokens.radiusSmall
          color: Tokens.surface
          border.color: pinInput.activeFocus ? Tokens.accent : Tokens.border
          border.width: 1

          TextInput {
            id: pinInput
            anchors.fill: parent
            anchors.margins: Tokens.spacing
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize + 2
            font.letterSpacing: 4
            maximumLength: 4
            inputMethodHints: Qt.ImhDigitsOnly
            validator: RegularExpressionValidator { regularExpression: /[0-9]{0,4}/ }
            onAccepted: root.submitPin()
          }
        }

        Chip {
          anchors.verticalCenter: parent.verticalCenter
          label: "Pair"
          usable: !root.busy && root.info.credentials === true
          onClicked: root.submitPin()
        }
      }

      Label {
        visible: !root.viewOnly && root.info.credentials !== true
        color: Tokens.muted
        font.pixelSize: Tokens.fontSizeSmall
        text: "PIN pairing needs your Sunshine web UI login: delight sidecar credentials <user> (password on stdin)."
      }

      Label {
        visible: root.viewOnly
        text: "Open " + (root.info.deskreenUrl || "") + " on the tablet and allow the connection in Deskreen. Deskreen only mirrors; use Sunshine + Moonlight for touch and keyboard input."
      }

      Image {
        visible: root.viewOnly && source !== ""
        width: Tokens.space(112)
        height: Tokens.space(112)
        smooth: false
        source: (root.info.qr || {}).deskreen ? "file://" + root.info.qr.deskreen : ""
      }

      Label {
        visible: root.message !== ""
        text: root.message
        color: Tokens.muted
        font.pixelSize: Tokens.fontSizeSmall
      }
    }
  }
}
