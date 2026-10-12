pragma ComponentBehavior: Bound

import QtQuick

// Share-sheet grid of targets from `share-targets --json`: [{id,label,icon,kind}].
// Arrow keys / hjkl move, Space/Enter emits targetActivated(target).
// Set `activeTargetId` + `activeProgress` (0..1, <0 = indeterminate) while sending.
FocusScope {
  id: root

  property var targets: []
  property int columns: 4
  property string activeTargetId: ""
  property real activeProgress: -1
  property string emptyText: "No nearby devices"
  property int currentIndex: 0
  readonly property int cellWidth: Math.floor(width / Math.max(1, columns))
  readonly property int cellHeight: Tokens.badgeSize * 2 + Tokens.fontSizeSmall * 2 + Tokens.spacing

  signal targetActivated(var target)

  implicitWidth: Tokens.sheetWidth
  implicitHeight: targets.length === 0 ? Tokens.rowHeight * 2 : Math.ceil(targets.length / Math.max(1, columns)) * cellHeight
  activeFocusOnTab: targets.length > 0

  function move(delta) {
    if (targets.length === 0) return
    currentIndex = Math.max(0, Math.min(targets.length - 1, currentIndex + delta))
  }

  onTargetsChanged: if (currentIndex >= targets.length) currentIndex = Math.max(0, targets.length - 1)

  Keys.onPressed: event => {
    let k = event.key
    if (k === Qt.Key_Left || k === Qt.Key_H) root.move(-1)
    else if (k === Qt.Key_Right || k === Qt.Key_L) root.move(1)
    else if (k === Qt.Key_Up || k === Qt.Key_K) root.move(-root.columns)
    else if (k === Qt.Key_Down || k === Qt.Key_J) root.move(root.columns)
    else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && root.targets.length > 0) root.targetActivated(root.targets[root.currentIndex])
    else return
    event.accepted = true
  }

  Column {
    anchors.centerIn: parent
    visible: root.targets.length === 0
    spacing: Tokens.spacingSmall

    Spinner { anchors.horizontalCenter: parent.horizontalCenter; width: Tokens.iconSize; height: width }
    Text {
      text: root.emptyText
      color: Tokens.muted
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }
  }

  Grid {
    columns: root.columns
    Repeater {
      model: root.targets
      delegate: Item {
        id: cell
        required property var modelData
        required property int index
        readonly property bool current: root.activeFocus && root.currentIndex === index
        readonly property bool sending: root.activeTargetId !== "" && root.activeTargetId === modelData.id
        width: root.cellWidth
        height: root.cellHeight
        Accessible.role: Accessible.Button
        Accessible.name: modelData.label || modelData.id

        Rectangle {
          id: avatar
          anchors.horizontalCenter: parent.horizontalCenter
          y: Tokens.spacingSmall
          width: Tokens.badgeSize * 1.7
          height: width
          radius: width / 2
          color: cell.sending ? Tokens.accent : cellArea.containsMouse ? Tokens.surfacePressed : Tokens.surfaceRaised
          border.width: Tokens.borderWidth
          border.color: Tokens.border
          scale: cellArea.pressed ? 0.94 : 1
          Behavior on color { ColorAnimation { duration: Tokens.animationFast } }
          Behavior on scale { NumberAnimation { duration: Tokens.animationFast } }

          Glyph {
            anchors.centerIn: parent
            glyph: cell.modelData.icon || Tokens.kindIcon(cell.modelData.kind || "")
            size: Tokens.iconSizeLarge
            color: cell.sending ? Tokens.onAccent : Tokens.foreground
          }

          ProgressRing {
            anchors.fill: parent
            anchors.margins: -4
            visible: cell.sending
            indeterminate: root.activeProgress < 0
            value: Math.max(0, root.activeProgress)
            thickness: 3
          }

          FocusRing { radius_: avatar.radius; shown: cell.current }
        }

        Text {
          anchors.top: avatar.bottom
          anchors.topMargin: Tokens.spacingSmall
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - Tokens.spacingSmall
          horizontalAlignment: Text.AlignHCenter
          text: cell.modelData.label || cell.modelData.id
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: Tokens.foreground
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeSmall
        }

        MouseArea {
          id: cellArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.currentIndex = cell.index
            root.targetActivated(cell.modelData)
          }
        }
      }
    }
  }
}
