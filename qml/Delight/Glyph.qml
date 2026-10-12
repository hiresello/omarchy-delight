import QtQuick

// A Nerd Font icon, centred on its ink rather than its advance box, so glyphs
// with uneven side bearings still sit in the middle of a badge or button.
Text {
  id: root

  property string glyph: ""
  property int size: Tokens.iconSize

  text: glyph
  color: Tokens.foreground
  font.family: Tokens.iconFontFamily
  font.pixelSize: size
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
  renderType: Text.NativeRendering

  TextMetrics {
    id: ink
    font: root.font
    text: root.glyph
  }

  readonly property bool measured: glyph !== "" && ink.tightBoundingRect.width > 0
  transform: Translate {
    x: root.measured ? Math.round(ink.advanceWidth / 2 - (ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2)) : 0
    y: root.measured ? Math.round(root.height / 2 - (root.baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2)) : 0
  }
}
