import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

// Small custom popup menu for a dock slot's right-click actions. Built from
// scratch (Rectangle + Column) rather than a native platform menu — Quickshell
// only renders platform menus in QApplication mode, which omarchy-shell does
// not use (see Tray.qml).
PopupWindow {
  id: popup

  property QtObject hostWindow: null
  // dockWindow (the surface anchorItem actually lives in) and its computed
  // on-screen origin — see DockSurface.qml's dockOriginX/Y comment. Wayland
  // gives no way to map a point from dockWindow straight into hostWindow
  // (a separate top-level surface), so the two are combined manually below
  // instead of mapping directly into hostWindow.
  property QtObject dockWindow: null
  property real originX: 0
  property real originY: 0
  property Item anchorItem: null
  property string dockPosition: "bottom"
  property bool pinned: false
  property bool running: false
  property bool canOpen: false
  // Only offered when the app both is running and publishes its own XDG
  // "new window" action — see Dock.qml's findNewWindowAction for why this
  // is never a blind re-launch.
  property bool canNewWindow: false

  signal pinToggled()
  signal openRequested()
  signal newWindowRequested()
  signal quitRequested()
  signal dismissed()

  color: "transparent"
  visible: false
  grabFocus: true
  implicitWidth: Math.ceil(card.implicitWidth)
  implicitHeight: Math.ceil(card.implicitHeight)

  onVisibleChanged: if (!visible) popup.dismissed()

  anchor {
    window: popup.hostWindow
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    adjustment: PopupAdjustment.Slide
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!popup.anchorItem || !popup.dockWindow) return
      var off = DockModel.anchorOffset(popup.dockPosition, popup.anchorItem.width, popup.anchorItem.height,
        popup.implicitWidth, popup.implicitHeight, Style.space(8))
      var local = popup.dockWindow.contentItem.mapFromItem(popup.anchorItem, off.x, off.y)
      anchor.rect.x = Math.round(popup.originX + local.x)
      anchor.rect.y = Math.round(popup.originY + local.y)
    }
  }

  component MenuRow: Rectangle {
    id: row
    property string label: ""
    signal activated()
    Layout.fillWidth: true
    implicitHeight: Style.space(28)
    radius: Style.space(5)
    color: rowArea.containsMouse ? Util.alpha(Color.popups.text, 0.1) : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      textFormat: Text.PlainText
      text: row.label
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activated()
    }
  }

  BorderSurface {
    id: card
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(1)))
    radius: Style.cornerRadius
    implicitWidth: Style.space(180)
    implicitHeight: menuColumn.implicitHeight + Style.space(12)

    ColumnLayout {
      id: menuColumn
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(2)

      MenuRow {
        visible: popup.canOpen
        label: "Open"
        onActivated: { popup.openRequested(); popup.visible = false }
      }
      MenuRow {
        visible: popup.canNewWindow
        label: "New Window"
        onActivated: { popup.newWindowRequested(); popup.visible = false }
      }
      MenuRow {
        label: popup.pinned ? "Remove from Dock" : "Keep in Dock"
        onActivated: { popup.pinToggled(); popup.visible = false }
      }
      MenuRow {
        visible: popup.running
        label: "Quit"
        onActivated: { popup.quitRequested(); popup.visible = false }
      }
    }
  }
}
