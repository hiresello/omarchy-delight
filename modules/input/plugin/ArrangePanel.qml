pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

// Universal Control: arrange neighbouring computers around this one and pick
// the role (share / receive) and backend (auto / Deskflow / Lan Mouse).
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string role: "share"
  property string backend: "auto"
  property var peers: []
  property var devices: []
  property string fingerprint: ""
  property string fingerprintPath: ""
  property string statusSubtitle: ""

  function open(payloadJson) {
    opened = true
    refresh()
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.input")
    else close()
  }

  function refresh() {
    if (!statusReader.running) statusReader.running = true
    if (!peersReader.running) peersReader.running = true
    if (!fpReader.running) fpReader.running = true
  }

  function parseStatus(text) {
    try {
      const s = JSON.parse(text || "{}")
      statusSubtitle = s.subtitle || ""
      devices = Array.isArray(s.devices) ? s.devices : []
    } catch (e) {
      console.warn("delight.input: bad status JSON", e)
    }
  }

  function parsePeers(text) {
    try {
      const parsed = JSON.parse(text || "[]")
      peers = Array.isArray(parsed) ? parsed : []
    } catch (e) {
      console.warn("delight.input: bad peers JSON", e)
    }
  }

  function parseFingerprint(text) {
    try {
      const f = JSON.parse(text || "{}")
      fingerprint = f.local || ""
      fingerprintPath = f.path || ""
    } catch (e) {
      console.warn("delight.input: bad fingerprint JSON", e)
    }
  }

  function deviceConnected(name) {
    for (let i = 0; i < devices.length; i++) {
      if (devices[i] && devices[i].id === name) return devices[i].connected === true
    }
    return false
  }

  // Map a drop position inside arrangeArea to the nearest edge.
  function nearestEdge(x, y, w, h) {
    const distances = {
      "left": x,
      "right": w - x,
      "top": y,
      "bottom": h - y
    }
    let best = "right"
    let bestDistance = w + h
    for (const edge in distances) {
      if (distances[edge] < bestDistance) {
        bestDistance = distances[edge]
        best = edge
      }
    }
    return best
  }

  function peerAtEdge(edge) {
    for (let i = 0; i < peers.length; i++) {
      if (peers[i] && peers[i].edge === edge) return peers[i]
    }
    return null
  }

  function setPeerEdge(name, edge) {
    const next = peers.map(function(p) {
      if (p.name === name) return { "name": p.name, "host": p.host, "edge": edge, "fingerprint": p.fingerprint || "" }
      if (p.edge === edge) return { "name": p.name, "host": p.host, "edge": "", "fingerprint": p.fingerprint || "" }
      return p
    }).filter(function(p) { return p.edge !== "" })
    peers = next
  }

  function addPeer(name, host) {
    if (name === "" || host === "") return
    for (let i = 0; i < peers.length; i++) {
      if (peers[i].name === name) return
    }
    const taken = peers.map(function(p) { return p.edge })
    const edges = ["right", "left", "bottom", "top"]
    let edge = ""
    for (let i = 0; i < edges.length; i++) {
      if (taken.indexOf(edges[i]) === -1) { edge = edges[i]; break }
    }
    if (edge === "") return
    peers = peers.concat([{ "name": name, "host": host, "edge": edge, "fingerprint": "" }])
  }

  function removePeer(name) {
    peers = peers.filter(function(p) { return p.name !== name })
  }

  function setPeerFingerprint(name, fp) {
    peers = peers.map(function(p) {
      return p.name === name ? { "name": p.name, "host": p.host, "edge": p.edge, "fingerprint": fp } : p
    })
  }

  function apply() {
    Quickshell.execDetached(["delight", "input", "set-peers", JSON.stringify(peers)])
    Quickshell.execDetached(["delight", "input", "enable", "--role", role, "--backend", backend])
    refreshSoon.restart()
  }

  Process {
    id: statusReader
    command: ["delight", "input", "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.parseStatus(this.text)
    }
  }

  Process {
    id: peersReader
    command: ["delight", "config", "get", "input.peers"]
    stdout: StdioCollector {
      onStreamFinished: root.parsePeers(this.text)
    }
  }

  Process {
    id: fpReader
    command: ["delight", "input", "fingerprint", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.parseFingerprint(this.text)
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
    interval: 400
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
    WlrLayershell.namespace: "delight-input"

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    implicitWidth: sheet.implicitWidth
    implicitHeight: sheet.implicitHeight

    Sheet {
      id: sheet
      anchors.centerIn: parent
      title: "Universal Control"
      implicitWidth: 480
      focus: true
      Keys.onEscapePressed: root.requestClose()

      // Role picker.
      Row {
        spacing: Tokens.spacing

        Text {
          text: "Role"
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSize
          anchors.verticalCenter: parent.verticalCenter
        }

        Repeater {
          model: [
            { "id": "share", "label": "Share" },
            { "id": "receive", "label": "Receive" }
          ]

          delegate: Rectangle {
            id: roleChip
            required property var modelData
            width: roleLabel.implicitWidth + Tokens.padding * 2
            height: 28
            radius: Tokens.radiusSmall
            color: root.role === roleChip.modelData.id ? Tokens.accent : Tokens.surface
            border.color: Tokens.border

            Text {
              id: roleLabel
              anchors.centerIn: parent
              text: roleChip.modelData.label
              color: root.role === roleChip.modelData.id ? Tokens.background : Tokens.foreground
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSize
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.role = roleChip.modelData.id
            }
          }
        }
      }

      // Backend picker.
      Row {
        spacing: Tokens.spacing

        Text {
          text: "Backend"
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSize
          anchors.verticalCenter: parent.verticalCenter
        }

        Repeater {
          model: [
            { "id": "auto", "label": "Auto" },
            { "id": "deskflow", "label": "Deskflow" },
            { "id": "lan-mouse", "label": "Lan Mouse" }
          ]

          delegate: Rectangle {
            id: backendChip
            required property var modelData
            width: backendLabel.implicitWidth + Tokens.padding * 2
            height: 28
            radius: Tokens.radiusSmall
            color: root.backend === backendChip.modelData.id ? Tokens.accent : Tokens.surface
            border.color: Tokens.border

            Text {
              id: backendLabel
              anchors.centerIn: parent
              text: backendChip.modelData.label
              color: root.backend === backendChip.modelData.id ? Tokens.background : Tokens.foreground
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSize
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.backend = backendChip.modelData.id
            }
          }
        }
      }

      // Screen arrangement: this computer in the middle, four edge zones.
      Item {
        id: arrangeArea
        width: 320
        height: 200
        anchors.horizontalCenter: parent.horizontalCenter

        Repeater {
          model: ["top", "right", "bottom", "left"]

          delegate: Rectangle {
            required property string modelData
            readonly property string edge: modelData
            readonly property var peer: root.peerAtEdge(edge)
            x: edge === "left" ? 0 : edge === "right" ? arrangeArea.width - width : (arrangeArea.width - width) / 2
            y: edge === "top" ? 0 : edge === "bottom" ? arrangeArea.height - height : (arrangeArea.height - height) / 2
            width: edge === "left" || edge === "right" ? 70 : 160
            height: edge === "top" || edge === "bottom" ? 46 : 90
            radius: Tokens.radiusSmall
            color: peer ? Tokens.surfaceRaised : "transparent"
            border.color: Tokens.border
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: parent.peer ? parent.peer.name : parent.edge
              color: parent.peer ? Tokens.foreground : Tokens.muted
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSizeSmall
            }
          }
        }

        Rectangle {
          anchors.centerIn: parent
          width: 120
          height: 72
          radius: Tokens.radiusSmall
          color: Tokens.surface
          border.color: Tokens.accent
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "This computer"
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSize
          }
        }
      }

      // Peer chips: drag to an edge, click remove to delete.
      Column {
        width: parent.width
        spacing: 4

        Repeater {
          model: root.peers

          delegate: Item {
            id: chipRow
            required property var modelData
            width: parent ? parent.width : 0
            height: 32

            Rectangle {
              id: chip
              width: chipLabel.implicitWidth + Tokens.padding * 2 + 24
              height: 26
              radius: Tokens.radiusSmall
              color: Tokens.surfaceRaised
              border.color: Tokens.border
              Drag.active: chipArea.drag.active

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: root.deviceConnected(chipRow.modelData.name) ? Tokens.accent : Tokens.muted
              }

              Text {
                id: chipLabel
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: chipRow.modelData.name + " · " + chipRow.modelData.edge
                color: Tokens.foreground
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSizeSmall
              }

              MouseArea {
                id: chipArea
                anchors.fill: parent
                drag.target: chip
                cursorShape: Qt.PointingHandCursor
                onReleased: {
                  const p = chip.mapToItem(arrangeArea, chip.width / 2, chip.height / 2)
                  root.setPeerEdge(chipRow.modelData.name,
                    root.nearestEdge(p.x, p.y, arrangeArea.width, arrangeArea.height))
                  chip.x = 0
                  chip.y = 0
                }
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "remove"
              color: Tokens.urgent
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSizeSmall

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removePeer(chipRow.modelData.name)
              }
            }
          }
        }
      }

      // Add a neighbour.
      Row {
        spacing: Tokens.spacing

        Rectangle {
          width: 120
          height: 28
          radius: Tokens.radiusSmall
          color: Tokens.surface
          border.color: Tokens.border

          TextInput {
            id: nameInput
            anchors.fill: parent
            anchors.margins: 6
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
            clip: true

            Text {
              anchors.centerIn: parent
              text: "name"
              visible: nameInput.text === ""
              color: Tokens.muted
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSizeSmall
            }
          }
        }

        Rectangle {
          width: 160
          height: 28
          radius: Tokens.radiusSmall
          color: Tokens.surface
          border.color: Tokens.border

          TextInput {
            id: hostInput
            anchors.fill: parent
            anchors.margins: 6
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
            clip: true

            Text {
              anchors.centerIn: parent
              text: "hostname"
              visible: hostInput.text === ""
              color: Tokens.muted
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSizeSmall
            }
          }
        }

        Rectangle {
          width: addLabel.implicitWidth + Tokens.padding * 2
          height: 28
          radius: Tokens.radiusSmall
          color: Tokens.surface
          border.color: Tokens.border

          Text {
            id: addLabel
            anchors.centerIn: parent
            text: "Add neighbour"
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.addPeer(nameInput.text, hostInput.text)
              nameInput.text = ""
              hostInput.text = ""
            }
          }
        }
      }

      // TLS fingerprints.
      Column {
        width: parent.width
        spacing: 4

        Text {
          text: "Local fingerprint: " + (root.fingerprint !== "" ? root.fingerprint : "none yet")
          color: Tokens.foreground
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeSmall
          wrapMode: Text.Wrap
          width: parent.width
        }

        Text {
          text: "Confirm this matches the prompt on the other computer."
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeSmall
        }

        Repeater {
          model: root.peers

          delegate: Row {
            id: fpRow
            required property var modelData
            spacing: Tokens.spacing

            Text {
              text: fpRow.modelData.name
              color: Tokens.muted
              font.family: Tokens.fontFamily
              font.pixelSize: Tokens.fontSizeSmall
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              width: 220
              height: 24
              radius: Tokens.radiusSmall
              color: Tokens.surface
              border.color: Tokens.border

              TextInput {
                anchors.fill: parent
                anchors.margins: 4
                text: fpRow.modelData.fingerprint || ""
                color: Tokens.foreground
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSizeSmall
                clip: true
                onEditingFinished: root.setPeerFingerprint(fpRow.modelData.name, text)
              }
            }
          }
        }
      }

      Text {
        visible: root.statusSubtitle !== ""
        text: root.statusSubtitle
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }

      // Apply.
      Rectangle {
        width: applyLabel.implicitWidth + Tokens.padding * 2
        height: 30
        radius: Tokens.radiusSmall
        color: Tokens.accent
        anchors.right: parent.right

        Text {
          id: applyLabel
          anchors.centerIn: parent
          text: "Apply"
          color: Tokens.background
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSize
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.apply()
        }
      }
    }
  }
}
