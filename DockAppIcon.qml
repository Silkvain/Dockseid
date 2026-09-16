import QtQuick
import qs.Commons

// One dock slot: icon image, hover highlight, running dot, and an instance
// count badge. All popups (hover preview, context menu) are owned by Dock.qml
// and positioned against this item, so only one popup surface exists at a
// time no matter how many apps are pinned/running.
Item {
  id: root

  required property var modelData
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real sizeScale: 1.0
  property real iconSize: Style.space(42) * sizeScale
  property real slotSize: Style.space(54) * sizeScale
  property bool menuOpen: false

  signal hoverEntered()
  signal hoverExited()
  signal primaryClicked()
  signal middleClicked()
  signal rightClicked()
  // Raw pointer signals for drag-to-reorder — DockSurface owns the actual
  // reordering logic and this icon's position while dragging; this just
  // reports the gesture. dragMoved's (dx, dy) is the total offset from the
  // press point, not a per-event delta.
  signal dragStarted()
  signal dragMoved(real dx, real dy)
  signal dragFinished()

  implicitWidth: slotSize
  implicitHeight: slotSize
  z: mouseArea.dragging ? 10 : 0

  readonly property bool running: modelData.running === true
  readonly property int count: modelData.count || 0
  readonly property bool dragging: mouseArea.dragging
  readonly property bool hot: mouseArea.containsMouse || root.menuOpen

  Rectangle {
    id: hoverBg
    anchors.centerIn: parent
    width: root.iconSize + Style.space(14) * root.sizeScale
    height: root.iconSize + Style.space(14) * root.sizeScale
    radius: width / 2
    color: Util.alpha(root.foreground, root.hot ? 0.12 : 0)
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Image {
    id: iconImage
    anchors.centerIn: parent
    width: root.iconSize
    height: root.iconSize
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: root.modelData.iconSource || ""
    scale: mouseArea.dragging ? 1.1 : (mouseArea.pressed ? 0.92 : 1.0)
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
  }

  // macOS-style running indicator.
  Rectangle {
    visible: root.running
    width: Style.space(5) * root.sizeScale
    height: Style.space(5) * root.sizeScale
    radius: width / 2
    color: root.accent
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(2)
  }

  // Instance-count badge, Windows-taskbar-grouping style.
  Rectangle {
    id: badge
    visible: root.count > 1
    width: Math.max(Style.space(16) * root.sizeScale, badgeLabel.implicitWidth + Style.space(6))
    height: Style.space(16) * root.sizeScale
    radius: height / 2
    color: root.accent
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Style.space(2)
    anchors.rightMargin: Style.space(2)

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.count > 9 ? "9+" : String(root.count)
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    property real pressX: 0
    property real pressY: 0
    property bool dragging: false
    readonly property real dragThreshold: 6

    onEntered: root.hoverEntered()
    onExited: root.hoverExited()

    // mouse.x/mouse.y are local to this MouseArea, which moves every time a
    // drag repositions the icon — using them directly would measure each
    // delta against a reference frame that just shifted under it, feeding
    // back into visible jitter. Mapping through to scene coordinates (a
    // frame that doesn't move with the icon) keeps the delta stable.
    function scenePos(mouse) {
      return mouseArea.mapToItem(null, mouse.x, mouse.y)
    }

    onPressed: function(mouse) {
      var p = scenePos(mouse)
      pressX = p.x
      pressY = p.y
      dragging = false
    }

    // Only a left-button press can turn into a drag; middle/right stay
    // immediate actions. Threshold avoids treating a plain click as a
    // micro-drag.
    onPositionChanged: function(mouse) {
      if (!pressed || (mouse.buttons & Qt.LeftButton) === 0) return
      var p = scenePos(mouse)
      var dx = p.x - pressX
      var dy = p.y - pressY
      if (!dragging && (Math.abs(dx) > dragThreshold || Math.abs(dy) > dragThreshold)) {
        dragging = true
        root.dragStarted()
      }
      if (dragging) root.dragMoved(dx, dy)
    }

    onReleased: function(mouse) {
      if (dragging) {
        dragging = false
        root.dragFinished()
        return
      }
      if (mouse.button === Qt.LeftButton) root.primaryClicked()
      else if (mouse.button === Qt.MiddleButton) root.middleClicked()
      else if (mouse.button === Qt.RightButton) root.rightClicked()
    }
  }
}
