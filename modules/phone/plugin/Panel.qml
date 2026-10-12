pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Delight"

// iPhone: what's playing, paired phones and pairing. Reads delightd's status
// file, which delightd rewrites only when something changes.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var daemon: ({})
  readonly property var phones: (daemon.phones || []).filter(function(p) { return p.paired })
  readonly property var playing: daemon.nowPlaying || null

  function open(payloadJson) {
    opened = true
    Tokens.refresh()
    statusFile.reload()
  }

  function close() {
    opened = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("delight.phone")
    else close()
  }

  function media(command) {
    Quickshell.execDetached(["delight", "phone", "media", command])
  }

  FileView {
    id: statusFile
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-delight/delightd.json"
    watchChanges: root.opened
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.daemon = JSON.parse(text() || "{}")
      } catch (e) {
        root.daemon = {}
      }
    }
    onLoadFailed: root.daemon = {}
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
    margins {
      top: Tokens.edgeGap - Tokens.shadowMargin
      right: 0
    }

    implicitWidth: sheet.implicitWidth + Tokens.shadowMargin + Tokens.edgeGap
    implicitHeight: sheet.implicitHeight + Tokens.shadowMargin * 2

    Sheet {
      id: sheet
      anchors.fill: parent
      anchors.leftMargin: Tokens.shadowMargin
      anchors.rightMargin: Tokens.edgeGap
      anchors.topMargin: Tokens.shadowMargin
      anchors.bottomMargin: Tokens.shadowMargin
      title: "iPhone"
      subtitle: root.daemon.pairing ? "Pairing…" : root.phones.length === 0 ? "No iPhone paired" : ""
      focus: true
      Keys.onEscapePressed: root.requestClose()

      // Now playing.
      Rectangle {
        visible: root.playing !== null && !!root.playing.title
        width: parent.width
        implicitHeight: nowPlaying.implicitHeight + Tokens.padding * 2
        radius: Tokens.radius
        color: Tokens.surface
        border.color: Tokens.border
        border.width: Tokens.borderWidth

        Column {
          id: nowPlaying
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Tokens.padding
          spacing: Tokens.spacingSmall

          Text {
            width: parent.width
            text: root.playing ? root.playing.title || "" : ""
            elide: Text.ElideRight
            color: Tokens.foreground
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeTitle
            font.weight: Font.DemiBold
          }

          Text {
            width: parent.width
            text: root.playing ? [root.playing.artist, root.playing.player].filter(Boolean).join(" · ") : ""
            elide: Text.ElideRight
            color: Tokens.muted
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSizeSmall
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.spacingLarge

            Button {
              icon: "󰒮"
              onClicked: root.media("previous")
            }

            Button {
              icon: root.playing && root.playing.playing ? "󰏤" : "󰐊"
              variant: "primary"
              onClicked: root.media("toggle")
            }

            Button {
              icon: "󰒭"
              onClicked: root.media("next")
            }
          }
        }
      }

      Repeater {
        model: root.phones

        ListRow {
          required property var modelData
          width: parent ? parent.width : 0
          icon: "󰀷"
          title: modelData.name || modelData.address
          subtitle: !modelData.connected ? "Not connected" :
            [modelData.notifications ? "Notifications" : "", modelData.media ? "Media" : ""].filter(Boolean).join(" · ") || "Connected"
          interactive: false
        }
      }

      Text {
        visible: root.phones.length === 0 || root.daemon.pairing === true
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.daemon.pairing
          ? "On your iPhone, open Settings › Bluetooth and tap this computer. Confirm the code, then allow notifications."
          : "Pair once and your iPhone's notifications and music show up here. No app needed on the iPhone."
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }

      Text {
        visible: !!root.daemon.error
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.daemon.error || ""
        color: Tokens.urgent
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }

      Button {
        text: root.daemon.pairing ? "Waiting for iPhone…" : "Pair an iPhone"
        variant: "primary"
        busy: root.daemon.pairing === true
        onClicked: Quickshell.execDetached(["delight", "phone", "pair"])
      }
    }
  }
}
