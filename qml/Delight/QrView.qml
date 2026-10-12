import QtQuick
import Quickshell.Io

// QR code card. Give `source` (a PNG, e.g. from `delight_qr <text> out.png`)
// or `text` (encoded live with qrencode). Always dark-on-white so phones scan
// it in any theme. Falls back to showing the text when qrencode is missing.
Item {
  id: root

  property string text: ""
  property url source: ""
  property string caption: ""
  property int size: 184
  property var matrix: []
  readonly property bool hasCode: source.toString() !== "" || matrix.length > 0
  readonly property bool failed: !hasCode && text !== "" && !encoder.running

  implicitWidth: size + Tokens.padding * 2
  implicitHeight: card.height + (captionText.visible ? captionText.implicitHeight + Tokens.spacing : 0)
  Accessible.role: Accessible.Graphic
  Accessible.name: caption !== "" ? caption : "QR code"

  onTextChanged: encode()
  Component.onCompleted: encode()

  function encode() {
    matrix = []
    if (source.toString() !== "" || text === "") return
    encoder.command = ["qrencode", "-t", "ASCII", "-m", "0", "--", text]
    encoder.running = true
  }

  Process {
    id: encoder
    stdout: StdioCollector {
      onStreamFinished: {
        let rows = []
        let lines = String(this.text).split("\n")
        for (let i = 0; i < lines.length; i++) {
          if (lines[i] === "") continue
          let row = []
          for (let j = 0; j < lines[i].length; j += 2) row.push(lines[i][j] === "#")
          rows.push(row)
        }
        root.matrix = rows
      }
    }
  }

  Rectangle {
    id: card
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.size + Tokens.padding * 2
    height: width
    radius: Tokens.radius
    color: "white"

    Image {
      anchors.fill: parent
      anchors.margins: Tokens.padding
      visible: root.source.toString() !== ""
      source: root.source
      smooth: false
      fillMode: Image.PreserveAspectFit
    }

    Canvas {
      id: canvas
      anchors.fill: parent
      anchors.margins: Tokens.padding
      visible: root.source.toString() === "" && root.matrix.length > 0
      onVisibleChanged: requestPaint()
      Connections {
        target: root
        function onMatrixChanged() { canvas.requestPaint() }
      }
      onPaint: {
        let ctx = getContext("2d")
        ctx.reset()
        let n = root.matrix.length
        if (n === 0) return
        let cell = Math.floor(width / n)
        let offset = Math.floor((width - cell * n) / 2)
        ctx.fillStyle = "#000000"
        for (let y = 0; y < n; y++)
          for (let x = 0; x < root.matrix[y].length; x++)
            if (root.matrix[y][x]) ctx.fillRect(offset + x * cell, offset + y * cell, cell, cell)
      }
    }

    Text {
      anchors.fill: parent
      anchors.margins: Tokens.padding
      visible: root.failed
      text: root.text
      wrapMode: Text.WrapAnywhere
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      color: "#202020"
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }
  }

  Text {
    id: captionText
    anchors.top: card.bottom
    anchors.topMargin: Tokens.spacing
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width
    visible: root.caption !== ""
    text: root.caption
    wrapMode: Text.Wrap
    horizontalAlignment: Text.AlignHCenter
    color: Tokens.muted
    font.family: Tokens.fontFamily
    font.pixelSize: Tokens.fontSizeSmall
  }
}
