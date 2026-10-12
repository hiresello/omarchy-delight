import QtQuick
import "Delight"

Item {
  id: root

  property string label: ""
  property bool selected: false
  signal clicked()

  implicitWidth: textItem.implicitWidth + Tokens.padding * 2
  implicitHeight: 34

  Rectangle {
    anchors.fill: parent
    radius: Tokens.radiusSmall
    color: root.selected ? Tokens.accent : (area.containsMouse ? Tokens.surfaceRaised : Tokens.surface)
    border.color: Tokens.border
    border.width: 1
  }

  Text {
    id: textItem
    anchors.centerIn: parent
    text: root.label
    color: root.selected ? Tokens.background : Tokens.foreground
    font.family: Tokens.fontFamily
    font.pixelSize: Tokens.fontSize
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
