pragma ComponentBehavior: Bound

import QtQuick
import "Delight"

Item {
  id: root

  property var options: []
  property string value: ""
  signal chosen(string value)

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: Tokens.spacing

    Repeater {
      model: root.options

      delegate: CameraButton {
        required property var modelData
        label: modelData.label
        selected: root.value === modelData.value
        onClicked: root.chosen(modelData.value)
      }
    }
  }
}
