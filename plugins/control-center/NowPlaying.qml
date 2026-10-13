pragma ComponentBehavior: Bound

import QtQuick
import "Delight"

// macOS-style Now Playing card for the module reporting `media`: title and
// artist with previous / play-pause / next. The text opens the module; the
// buttons run the module's media commands and leave the panel open.
Rectangle {
  id: root

  property var status: null
  readonly property var media: status && status.media ? status.media : null
  readonly property var buttons: [previousButton, toggleButton, nextButton].filter(function(b) { return b.visible })

  signal commandRequested(var command)
  signal openRequested(var status)

  visible: media !== null
  implicitHeight: Tokens.tileHeight
  radius: Tokens.radius
  color: Tokens.surface
  border.color: Tokens.divider
  border.width: Tokens.borderWidth

  Rectangle {
    id: art
    anchors.left: parent.left
    anchors.leftMargin: Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    width: root.height - Tokens.spacing * 2
    height: width
    radius: Tokens.radiusSmall
    color: Tokens.surfaceRaised

    Glyph {
      anchors.centerIn: parent
      glyph: "󰝚"
      size: Tokens.iconSize
    }
  }

  MouseArea {
    anchors.left: art.right
    anchors.leftMargin: Tokens.spacing
    anchors.right: controls.left
    anchors.rightMargin: Tokens.spacingSmall
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    cursorShape: Qt.PointingHandCursor
    onClicked: root.openRequested(root.status)

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        text: root.media ? root.media.title : ""
        elide: Text.ElideRight
        color: Tokens.foreground
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
        font.weight: Font.DemiBold
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: root.media ? root.media.subtitle : ""
        elide: Text.ElideRight
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }
    }
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.rightMargin: Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    spacing: Tokens.spacingXs

    Button {
      id: previousButton
      visible: !!root.media && root.media.previous.length > 0
      icon: "󰒮"
      label: "Previous"
      variant: "plain"
      onClicked: root.commandRequested(root.media.previous)
    }

    Button {
      id: toggleButton
      visible: !!root.media
      icon: root.media && root.media.playing ? "󰏤" : "󰐊"
      label: root.media && root.media.playing ? "Pause" : "Play"
      variant: "plain"
      onClicked: root.commandRequested(root.media.toggle)
    }

    Button {
      id: nextButton
      visible: !!root.media && root.media.next.length > 0
      icon: "󰒭"
      label: "Next"
      variant: "plain"
      onClicked: root.commandRequested(root.media.next)
    }
  }
}
