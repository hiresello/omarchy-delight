import QtQuick

// A Nerd Font icon, optically centred.
Text {
  property string glyph: ""
  property int size: Tokens.iconSize

  text: glyph
  color: Tokens.foreground
  font.family: Tokens.fontFamily
  font.pixelSize: size
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
  renderType: Text.NativeRendering
}
