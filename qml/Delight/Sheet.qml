import QtQuick

// Rounded translucent container for Delight panels. Children go in a column.
Rectangle {
  id: root

  property string title: ""
  default property alias content: body.data

  implicitWidth: 360
  implicitHeight: column.implicitHeight + Tokens.padding * 2
  radius: Tokens.radius + 4
  color: Qt.rgba(Tokens.background.r, Tokens.background.g, Tokens.background.b, 0.94)
  border.color: Tokens.border
  border.width: 1

  Column {
    id: column
    anchors.fill: parent
    anchors.margins: Tokens.padding
    spacing: Tokens.spacing

    Text {
      text: root.title
      visible: text !== ""
      color: Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSize + 2
      font.bold: true
    }

    Column {
      id: body
      width: parent.width
      spacing: Tokens.spacing
    }
  }
}
