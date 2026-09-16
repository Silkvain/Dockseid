import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

// Single shared hover preview, reused for every dock slot (mirrors how the
// bar owns one tooltip window instead of one per widget). Shows the app name
// for a single instance, or a Windows-taskbar-style window list with a count
// when an app has more than one open window.
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
  property string appName: ""
  property var toplevels: []

  signal activateInstance(var toplevel)

  // Whether the pointer is currently over this popup's own surface — DockSurface
  // watches this so leaving the trigger icon for the popup (to pick a window
  // from the list) doesn't immediately start the close countdown.
  property bool hovered: false

  readonly property int instanceCount: toplevels.length
  readonly property bool multiInstance: instanceCount > 1

  color: "transparent"
  visible: false
  implicitWidth: Math.ceil(card.implicitWidth)
  implicitHeight: Math.ceil(card.implicitHeight)

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

  BorderSurface {
    id: card
    color: Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, Math.max(1, Style.space(1)))
    radius: Style.cornerRadius
    implicitWidth: Math.max(nameLabel.implicitWidth, popup.multiInstance ? instanceColumn.implicitWidth : 0) + Style.space(20)
    implicitHeight: (popup.multiInstance ? instanceColumn.implicitHeight + nameLabel.implicitHeight + Style.space(6) : nameLabel.implicitHeight) + Style.space(16)

    HoverHandler {
      onHoveredChanged: popup.hovered = hovered
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(10)
      spacing: Style.space(6)

      Text {
        id: nameLabel
        textFormat: Text.PlainText
        text: popup.multiInstance ? (popup.appName + " — " + popup.instanceCount + " windows") : popup.appName
        color: Color.tooltip.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: popup.multiInstance
      }

      ColumnLayout {
        id: instanceColumn
        visible: popup.multiInstance
        spacing: Style.space(2)
        Layout.fillWidth: true

        Repeater {
          model: popup.multiInstance ? popup.toplevels : []

          Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitWidth: rowLabel.implicitWidth + Style.space(12)
            implicitHeight: Style.space(22)
            radius: Style.space(5)
            color: rowArea.containsMouse ? Util.alpha(Color.tooltip.text, 0.1) : "transparent"

            Text {
              id: rowLabel
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: (row.modelData.title || row.modelData.appId || "")
              color: Color.tooltip.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: popup.activateInstance(row.modelData)
            }
          }
        }
      }
    }
  }
}
