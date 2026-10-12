import QtQuick

// Generic list row: icon, title, subtitle and a trailing slot for controls.
// Emits activated() on click / Space / Enter.
Item {
  id: root

  property string icon: ""
  property string title: ""
  property string subtitle: ""
  property bool interactive: true
  property bool highlighted: false
  default property alias trailing: trailingRow.data

  signal activated()

  implicitWidth: Tokens.sheetWidth
  implicitHeight: Tokens.rowHeight
  activeFocusOnTab: interactive

  Accessible.role: Accessible.ListItem
  Accessible.name: title
  Accessible.description: subtitle
  Accessible.onPressAction: root.activated()

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activated()
      event.accepted = true
    }
  }

  Rectangle {
    id: bg
    anchors.fill: parent
    radius: Tokens.radiusSmall
    color: root.highlighted ? Tokens.alpha(Tokens.accent, 0.16)
      : area.containsMouse && root.interactive ? Tokens.surfaceRaised : "transparent"
    Behavior on color { ColorAnimation { duration: Tokens.animationFast } }
    FocusRing { radius_: bg.radius; shown: root.activeFocus }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.interactive
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Rectangle {
    id: badge
    visible: root.icon !== ""
    anchors.left: parent.left
    anchors.leftMargin: Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(Tokens.badgeSize * 0.85)
    height: width
    radius: width / 2
    color: Tokens.surfacePressed

    Glyph {
      anchors.centerIn: parent
      glyph: root.icon
      size: Tokens.iconSizeSmall
    }
  }

  Column {
    anchors.left: badge.visible ? badge.right : parent.left
    anchors.leftMargin: Tokens.spacingLarge - 2
    anchors.right: trailingRow.left
    anchors.rightMargin: Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Text {
      width: parent.width
      text: root.title
      elide: Text.ElideRight
      color: Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSize
    }
    Text {
      width: parent.width
      text: root.subtitle
      visible: text !== ""
      elide: Text.ElideRight
      color: Tokens.muted
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }
  }

  Row {
    id: trailingRow
    anchors.right: parent.right
    anchors.rightMargin: Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    spacing: Tokens.spacingSmall
  }
}
