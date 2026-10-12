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
  property string view: "main"
  property var pairInfo: ({})
  property var devices: []
  property var messages: []
  property string selectedThread: ""
  property string draft: ""

  function open(payloadJson) {
    let payload = {}
    try {
      payload = JSON.parse(payloadJson || "{}")
    } catch (e) {
      console.warn("delight.phone: invalid panel payload", e)
    }
    view = payload.view || "main"
    selectedThread = ""
    opened = true
    refresh()
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.phone")
    else close()
  }

  function refresh() {
    if (!devicesProcess.running) devicesProcess.running = true
    if (view === "pair" && !pairProcess.running) pairProcess.running = true
    if (view === "sms" && !smsProcess.running) smsProcess.running = true
    if (view === "sms" && selectedThread !== "" && !threadProcess.running) {
      threadProcess.command = ["delight", "phone", "sms", "thread", selectedThread, "--json"]
      threadProcess.running = true
    }
  }

  function parseJson(text, fallback) {
    try {
      return JSON.parse(text || JSON.stringify(fallback))
    } catch (e) {
      return fallback
    }
  }

  function run(command) {
    Quickshell.execDetached(command)
    refreshSoon.restart()
  }

  function threads() {
    const grouped = {}
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i]
      const id = String(message.threadId)
      if (!grouped[id] || Number(message.date) > Number(grouped[id].date)) grouped[id] = message
    }
    return Object.keys(grouped).map(function(id) { return grouped[id] })
      .sort(function(a, b) { return Number(b.date) - Number(a.date) })
  }

  function sendReply() {
    if (selectedThread === "" || draft.trim() === "") return
    run(["delight", "phone", "sms", "reply", selectedThread, draft])
    draft = ""
  }

  Process {
    id: devicesProcess
    command: ["delight", "phone", "devices", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.devices = root.parseJson(this.text, [])
    }
  }

  Process {
    id: pairProcess
    command: ["delight", "phone", "pair", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.pairInfo = root.parseJson(this.text, ({}))
    }
  }

  Process {
    id: smsProcess
    command: ["delight", "phone", "sms", "list", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.messages = root.parseJson(this.text, [])
    }
  }

  Process {
    id: threadProcess
    command: []
    stdout: StdioCollector {
      onStreamFinished: root.messages = root.parseJson(this.text, [])
    }
  }

  Timer {
    interval: 1500
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 300
    onTriggered: root.refresh()
  }

  component ActionButton: Rectangle {
    id: button
    property string label: ""
    signal clicked()
    implicitWidth: labelText.implicitWidth + Tokens.padding
    implicitHeight: 32
    radius: Tokens.radiusSmall
    color: area.containsMouse ? Tokens.surfaceRaised : Tokens.surface
    border.color: Tokens.border

    Text {
      id: labelText
      anchors.centerIn: parent
      text: button.label
      color: Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }

    MouseArea {
      id: area
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
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "delight-phone"

    anchors {
      top: true
      right: true
    }
    // The sheet sits edgeGap from the bar and screen edge; the surface adds
    // shadowMargin for the baked shadow, except past the screen edge.
    margins {
      top: Tokens.edgeGap - Tokens.shadowMargin
      right: 0
    }

    implicitWidth: Tokens.space(420) + Tokens.shadowMargin + Tokens.edgeGap
    implicitHeight: Math.min(sheet.implicitHeight, Tokens.space(680)) + Tokens.shadowMargin * 2

    Sheet {
      id: sheet
      anchors.fill: parent
      anchors.leftMargin: Tokens.shadowMargin
      anchors.rightMargin: Tokens.edgeGap
      anchors.topMargin: Tokens.shadowMargin
      anchors.bottomMargin: Tokens.shadowMargin
      title: root.selectedThread !== "" ? "Messages" : (root.view === "pair" ? "Pair a phone" : (root.view === "sms" ? "Messages" : "Phone"))
      focus: true
      Keys.onEscapePressed: {
        if (root.selectedThread !== "") root.selectedThread = ""
        else root.requestClose()
      }

      Column {
        id: content
        width: parent.width
        spacing: Tokens.spacing

        Row {
          spacing: Tokens.spacing
          ActionButton {
            label: "Devices"
            onClicked: {
              root.view = "main"
              root.selectedThread = ""
              root.refresh()
            }
          }
          ActionButton {
            label: "Pair"
            onClicked: {
              root.view = "pair"
              root.selectedThread = ""
              root.refresh()
            }
          }
          ActionButton {
            label: "Messages"
            onClicked: {
              root.view = "sms"
              root.selectedThread = ""
              root.refresh()
            }
          }
          ActionButton {
            label: "Close"
            onClicked: root.requestClose()
          }
        }

        Column {
          width: parent.width
          spacing: Tokens.spacing
          visible: root.view === "main"

          Text {
            visible: root.devices.length === 0
            text: "No paired phone."
            color: Tokens.muted
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
          }

          Repeater {
            model: root.devices

            Column {
              id: deviceRow
              required property var modelData
              width: parent.width
              spacing: Tokens.spacing / 2

              Tile {
                width: parent.width
                icon: "󰄜"
                title: deviceRow.modelData.name
                subtitle: (deviceRow.modelData.connected ? "" : "not connected")
                  + (deviceRow.modelData.battery ? " · " + deviceRow.modelData.battery.charge + "%"
                    + (deviceRow.modelData.battery.charging ? " charging" : "") : "")
                  + (deviceRow.modelData.limited ? " · files & clipboard only" : "")
                status: deviceRow.modelData.connected ? "on" : "off"
                toggleable: false
              }

              Row {
                spacing: Tokens.spacing
                ActionButton {
                  label: "Ring"
                  onClicked: root.run(["delight", "phone", "ring", deviceRow.modelData.id])
                }
                ActionButton {
                  label: "Send clipboard"
                  onClicked: root.run(["delight", "phone", "clipboard", "send"])
                }
                ActionButton {
                  label: "Messages"
                  visible: !deviceRow.modelData.limited
                  onClicked: {
                    root.view = "sms"
                    root.selectedThread = ""
                    root.refresh()
                  }
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Tokens.spacing
          visible: root.view === "pair"

          Text {
            text: "Computer: " + (root.pairInfo.name || "This computer")
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
          }
          Text {
            text: "Install KDE Connect, join the same Wi-Fi, tap "
              + (root.pairInfo.name || "this computer") + " in the app, then confirm the key here."
            color: Tokens.muted
            wrapMode: Text.Wrap
            width: parent.width
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
          }
          Text {
            text: "Android: Add devices by IP using one of these private addresses:"
              + (root.pairInfo.addresses || []).join(", ")
            color: Tokens.muted
            wrapMode: Text.Wrap
            width: parent.width
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
          }
          Image {
            visible: root.pairInfo.qr !== undefined
            source: root.pairInfo.qr ? "file://" + root.pairInfo.qr : ""
            sourceSize.width: 144
            sourceSize.height: 144
            width: Tokens.space(144)
            height: Tokens.space(144)
            fillMode: Image.PreserveAspectFit
          }

          Text {
            text: "Nearby devices"
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
            font.bold: true
          }
          Repeater {
            model: root.pairInfo.discoverable || []
            Row {
              id: discoverableRow
              required property var modelData
              width: parent.width
              spacing: Tokens.spacing
              Text {
                text: discoverableRow.modelData.name
                color: Tokens.foreground
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSize
              }
              ActionButton {
                label: "Pair"
                onClicked: root.run(["delight", "phone", "pair", "request", discoverableRow.modelData.id])
              }
            }
          }

          Text {
            text: "Pairing requests"
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
            font.bold: true
          }
          Repeater {
            model: root.pairInfo.requests || []
            Column {
              id: pairingRequest
              required property var modelData
              width: parent.width
              spacing: Tokens.spacing / 2
              Text {
                text: pairingRequest.modelData.name + " · " + pairingRequest.modelData.verificationKey
                color: Tokens.foreground
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSizeSmall
              }
              Row {
                spacing: Tokens.spacing
                ActionButton {
                  label: "Accept"
                  onClicked: root.run(["delight", "phone", "pair", "accept", pairingRequest.modelData.id])
                }
                ActionButton {
                  label: "Reject"
                  onClicked: root.run(["delight", "phone", "pair", "reject", pairingRequest.modelData.id])
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Tokens.spacing
          visible: root.view === "sms"

          ActionButton {
            visible: root.selectedThread !== ""
            label: "Back to conversations"
            onClicked: root.selectedThread = ""
          }
          Repeater {
            model: root.selectedThread === "" ? root.threads() : []
            Rectangle {
              id: threadRow
              required property var modelData
              width: parent.width
              implicitHeight: threadPreview.implicitHeight + Tokens.padding
              radius: Tokens.radiusSmall
              color: Tokens.surface
              border.color: Tokens.border
              Column {
                id: threadPreview
                anchors.fill: parent
                anchors.margins: Tokens.padding / 2
                spacing: Tokens.spacing / 2
                Text {
                  text: (threadRow.modelData.addresses || []).join(", ") || "Conversation"
                  color: Tokens.foreground
                  font.family: Tokens.fontFamily
                  font.pixelSize: Tokens.fontSize
                  font.bold: true
                }
                Text {
                  text: threadRow.modelData.body
                  color: Tokens.muted
                  elide: Text.ElideRight
                  width: parent.width
                  font.family: Tokens.fontFamily
                  font.pixelSize: Tokens.fontSizeSmall
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedThread = String(threadRow.modelData.threadId)
                  root.refresh()
                }
              }
            }
          }
          Repeater {
            model: root.selectedThread !== "" ? root.messages : []
            Text {
              required property var modelData
              text: (modelData.outgoing ? "You: " : "") + modelData.body
              color: Tokens.foreground
              wrapMode: Text.Wrap
              width: parent.width
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSize
            }
          }
          TextInput {
            visible: root.selectedThread !== ""
            width: parent.width
            text: root.draft
            onTextChanged: root.draft = text
            onAccepted: root.sendReply()
            color: Tokens.foreground
            selectionColor: Tokens.accent
            selectedTextColor: Tokens.background
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
            focus: root.selectedThread !== ""
          }
          ActionButton {
            visible: root.selectedThread !== ""
            label: "Send"
            onClicked: root.sendReply()
          }
        }
      }
    }
  }
}
