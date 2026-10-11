import QtQuick

// One Control Center tile. The body toggles; the chevron opens details.
Rectangle {
  id: root

  property string icon: ""
  property string title: ""
  property string subtitle: ""
  property string status: "off"
  property bool toggleable: true
  property bool hasDetail: false

  signal toggled()
  signal detailRequested()

  readonly property bool active: status === "on"

  implicitWidth: 168
  implicitHeight: 64
  radius: Tokens.radius
  color: bodyArea.containsMouse ? Tokens.surfaceRaised : Tokens.surface
  border.color: Tokens.border
  border.width: 1

  Behavior on color { ColorAnimation { duration: Tokens.animationFast } }

  Rectangle {
    id: badge
    anchors.left: parent.left
    anchors.leftMargin: Tokens.padding
    anchors.verticalCenter: parent.verticalCenter
    width: 34
    height: 34
    radius: width / 2
    color: Tokens.stateColor(root.status)

    Text {
      anchors.centerIn: parent
      text: root.icon
      color: root.active ? Tokens.background : Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.iconSize
    }
  }

  Column {
    anchors.left: badge.right
    anchors.leftMargin: Tokens.spacing
    anchors.right: chevron.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Text {
      width: parent.width
      text: root.title
      color: Tokens.foreground
      elide: Text.ElideRight
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSize
      font.bold: true
    }

    Text {
      width: parent.width
      text: root.subtitle
      visible: text !== ""
      color: Tokens.muted
      elide: Text.ElideRight
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }
  }

  MouseArea {
    id: bodyArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.toggleable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }

  Text {
    id: chevron
    anchors.right: parent.right
    anchors.rightMargin: Tokens.padding
    anchors.verticalCenter: parent.verticalCenter
    visible: root.hasDetail
    width: visible ? implicitWidth : 0
    text: "›"
    color: chevronArea.containsMouse ? Tokens.foreground : Tokens.muted
    font.family: Tokens.fontFamily
    font.pixelSize: Tokens.iconSize

    MouseArea {
      id: chevronArea
      anchors.fill: parent
      anchors.margins: -8
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.detailRequested()
    }
  }
}
