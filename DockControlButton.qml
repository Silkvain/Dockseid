import QtQuick
import qs.Commons

// Round glyph button for the dock's leading controls (add app, settings).
Item {
  id: root

  property string glyph: "+"
  property real sizeScale: 1.0
  property real diameter: Style.space(34) * sizeScale

  signal clicked()

  implicitWidth: diameter
  implicitHeight: diameter

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Util.alpha(Color.foreground, area.containsMouse ? 0.12 : 0)
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.glyph
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.heading * root.sizeScale
    opacity: 0.75
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
