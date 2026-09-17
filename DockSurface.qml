import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Everything needed to render the dock on one screen: the always-present
// hover trigger strip (autohide mode only), the pill itself, and the three
// popups anchored to it (hover preview, context menu, settings — the
// settings popup also hosts the "Add App" tab). Dock.qml instantiates one
// of these per active screen and owns all the shared state/actions via
// `controller`.
Item {
  id: surface

  required property var screen
  required property var controller

  readonly property var settings: controller.settings
  readonly property string position: settings.position
  readonly property bool vertical: position === "left" || position === "right"
  readonly property bool alwaysVisible: settings.visibility === "always"

  // -------------------------------------------------------- fullscreen
  // Whether any window fullscreened on THIS screen currently overrides the
  // dock. Tracks the generic Wayland toplevel fullscreen flag (not a
  // Hyprland-IPC-specific one) since that's the same ToplevelManager data
  // the dock already builds its icon list from.
  property int toplevelRevision: 0
  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { surface.toplevelRevision++ }
  }
  readonly property bool fullscreenActive: {
    var _rev = surface.toplevelRevision // establishes a dependency so add/remove windows re-evaluate this
    var list = ToplevelManager.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t.fullscreen) continue
      var onThisScreen = t.screens || []
      for (var j = 0; j < onThisScreen.length; j++) {
        if (onThisScreen[j] === surface.screen) return true
      }
    }
    return false
  }
  readonly property bool fullscreenOverride: settings.showInFullscreen && surface.fullscreenActive

  // Whether THIS screen currently has no open windows at all. Reuses the
  // same toplevelRevision dependency as fullscreenActive above.
  readonly property bool screenEmpty: {
    var _rev = surface.toplevelRevision
    var list = ToplevelManager.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var onThisScreen = list[i].screens || []
      for (var j = 0; j < onThisScreen.length; j++) {
        if (onThisScreen[j] === surface.screen) return false
      }
    }
    return true
  }
  // Only meaningful in auto-hide mode — "always visible" is already always
  // shown regardless of what's open, so this never applies there.
  readonly property bool emptyScreenOverride: settings.showWhenEmpty && !surface.alwaysVisible && surface.screenEmpty

  // What the dock actually behaves as right now — the user's own
  // visibility setting, except forced to auto-hide-style behavior while a
  // fullscreen window is overriding it (autohide mode is already exactly
  // this, so that override only ever changes anything for "always
  // visible"), or forced the other way — permanently shown — while its
  // screen has nothing open and showWhenEmpty is on.
  readonly property bool effectiveAlwaysVisible: (surface.alwaysVisible && !surface.fullscreenOverride) || surface.emptyScreenOverride

  readonly property real thickness: controller.thickness
  // User-adjustable clearance from the physical screen edge (raw px, not
  // Style.space-scaled — see DockModel.clampEdgeGap). Applies whether the
  // dock is floating or claiming its space, since a thick bezel is just as
  // much in the way either way.
  //
  // Keyed off the *configured* visibility setting (surface.alwaysVisible),
  // not surface.effectiveAlwaysVisible — this used to follow the effective
  // value, which meant the fullscreen/empty-screen overrides would silently
  // swap in the *other* mode's gap the moment they kicked in (e.g. an
  // auto-hide dock snapping to its always-visible gap while sitting on an
  // empty screen), even though the user never changed their Visibility
  // setting. The configured mode's gap should hold no matter what's
  // temporarily forcing the dock to reveal or hide.
  readonly property real edgeGap: surface.alwaysVisible ? settings.edgeGapAlways : settings.edgeGapAutohide
  // Spans exactly the gap between the physical screen edge and where the
  // revealed pill begins — not a fixed thin strip at the edge, otherwise a
  // larger edge offset means hovering the very edge to reveal the dock,
  // then backtracking across a dead zone to reach it once it slides into
  // view. Stopping precisely at the pill's own near edge (rather than
  // covering the pill's footprint too) matters: the trigger and pill are
  // two separate surfaces, and letting them overlap meant the trigger's
  // transparent-but-input-accepting surface could sit in front of the pill
  // and swallow clicks meant for its icons. The pill has its own hover
  // handling once the cursor reaches it, so the trigger only needs to
  // cover the approach.
  readonly property real triggerThickness: Math.max(1, surface.edgeGap)

  // dockWindow's own top-left corner on this screen, derived the same way
  // its anchors+margins position it (single-edge anchor centers on the free
  // axis — standard wlr-layer-shell behavior). Wayland gives a client no way
  // to query a layer surface's actual compositor-assigned position from
  // another surface, so popups (anchored to the separate, stable
  // popupAnchor window below — see its comment) need this computed
  // client-side rather than read off dockWindow directly.
  readonly property real dockOriginX: surface.vertical
    ? (surface.position === "left" ? surface.edgeGap : surface.screen.width - surface.edgeGap - pill.width)
    : (surface.screen.width - pill.width) / 2
  readonly property real dockOriginY: surface.vertical
    ? (surface.screen.height - pill.height) / 2
    : (surface.position === "top" ? surface.edgeGap : surface.screen.height - surface.edgeGap - pill.height)

  // The outline is drawn inset (Qt Quick draws Rectangle.border within the
  // rect's own bounds), so without this the pill would need to shrink its
  // content to make room for a thicker border. Padding the pill's own size
  // by the border width instead keeps the icons/controls at their natural
  // size and grows the dock outward around them.
  readonly property real borderPad: settings.borderEnabled ? settings.borderWidth : 0
  readonly property real outerThickness: surface.thickness + surface.borderPad * 2

  // -------------------------------------------------------- reveal/hover
  property bool pillHovered: false
  property bool triggerHovered: false
  property bool revealed: surface.effectiveAlwaysVisible

  readonly property bool wantRevealed: surface.effectiveAlwaysVisible || surface.pillHovered
    || surface.triggerHovered || surface.openPopupKind !== "" || surface.dragActive

  onWantRevealedChanged: {
    if (wantRevealed) { hideTimer.stop(); surface.revealed = true }
    else hideTimer.restart()
  }

  Timer {
    id: hideTimer
    interval: 300
    onTriggered: surface.revealed = surface.effectiveAlwaysVisible
  }

  // How far the pill slides toward its own edge (and out of view) when
  // hidden. 0 while revealed or always-visible. Uses the full bordered size
  // so a thick outline doesn't leave a sliver peeking out while "hidden".
  property real slideAmount: surface.revealed ? 0 : surface.outerThickness
  Behavior on slideAmount { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // -------------------------------------------------------- popup state
  // Only one transient popup (hover preview / context menu / settings, the
  // latter also covering its own Add App tab) is ever open at a time.
  property string openPopupKind: ""  // "", "hover", "menu", "settings"
  property var openPopupItem: null

  Timer {
    id: hoverHideTimer
    interval: 220
    onTriggered: if (surface.openPopupKind === "hover") surface.closePopups()
  }

  function closePopups() {
    surface.openPopupKind = ""
    surface.openPopupItem = null
    hoverPopup.visible = false
    contextMenu.visible = false
    settingsPopup.visible = false
  }

  function showHover(iconItem, item) {
    if (surface.openPopupKind === "menu" || surface.openPopupKind === "settings") return
    hoverHideTimer.stop()
    surface.openPopupKind = "hover"
    surface.openPopupItem = item
    hoverPopup.anchorItem = iconItem
    hoverPopup.appName = item.name
    hoverPopup.toplevels = item.toplevels
    hoverPopup.visible = true
  }

  function scheduleHideHover() {
    if (surface.openPopupKind !== "hover") return
    // Pointer is moving from the icon into the popup itself (e.g. to pick a
    // window from a multi-instance list) — let the popup's own hover leave
    // event schedule the close instead, so there's no dead zone to cross.
    if (hoverPopup.hovered) return
    hoverHideTimer.restart()
  }

  // Bridges hover from the icon that opened the popup to the popup itself,
  // which lives in a separate surface and wouldn't otherwise keep it (or the
  // dock's own reveal) alive while the pointer travels across the gap or
  // lingers over a window row.
  Connections {
    target: hoverPopup
    function onHoveredChanged() {
      if (hoverPopup.hovered) hoverHideTimer.stop()
      else surface.scheduleHideHover()
    }
  }

  function showContextMenu(iconItem, item) {
    surface.closePopups()
    surface.openPopupKind = "menu"
    surface.openPopupItem = item
    contextMenu.anchorItem = iconItem
    contextMenu.pinned = item.pinned
    contextMenu.running = item.running
    contextMenu.canOpen = item.pinned && !item.running
    contextMenu.canNewWindow = item.running && !!item.newWindowAction
    contextMenu.visible = true
  }

  function showSettings() {
    surface.closePopups()
    surface.openPopupKind = "settings"
    // Centers on the whole pill rather than just the gear button (which
    // usually sits off to one side), so the popover reads as belonging to
    // the dock as a whole.
    settingsPopup.anchorItem = pill
    settingsPopup.shape = surface.settings.shape
    settingsPopup.opacityValue = surface.settings.opacity
    settingsPopup.themeMode = surface.settings.themeMode
    settingsPopup.customBackground = surface.settings.customBackground
    settingsPopup.customAccent = surface.settings.customAccent
    settingsPopup.monitor = surface.settings.monitor
    settingsPopup.visibilityMode = surface.settings.visibility
    settingsPopup.size = surface.settings.size
    settingsPopup.edgeGap = surface.edgeGap
    settingsPopup.borderEnabled = surface.settings.borderEnabled
    settingsPopup.borderWidth = surface.settings.borderWidth
    settingsPopup.showInFullscreen = surface.settings.showInFullscreen
    settingsPopup.showWhenEmpty = surface.settings.showWhenEmpty
    settingsPopup.monitorOptions = controller.monitorOptions
    settingsPopup.dockPosition = surface.position
    settingsPopup.activeTab = 0
    settingsPopup.visible = true
  }

  // --------------------------------------------------------- drag reorder
  // Per-icon footprint along the dock's primary axis. Must track
  // DockAppIcon's own slotSize formula (Style.space(54) * sizeScale).
  readonly property real iconSpacing: Style.space(4)
  readonly property real iconSlot: Style.space(54) * surface.settings.size + surface.iconSpacing

  property bool dragActive: false
  property string dragKey: ""
  property var dragWorkingOrder: []   // key sequence, valid only while dragActive
  property real dragStartOffset: 0
  property real dragLiveOffset: 0

  function beginDrag(key, index) {
    surface.closePopups()
    surface.dragWorkingOrder = controller.dockItems.map(function(it) { return it.key })
    surface.dragKey = key
    surface.dragStartOffset = index * surface.iconSlot
    surface.dragLiveOffset = surface.dragStartOffset
    surface.dragActive = true
  }

  function updateDrag(dx, dy) {
    if (!surface.dragActive) return
    var delta = surface.vertical ? dy : dx
    var maxOffset = Math.max(0, (surface.dragWorkingOrder.length - 1) * surface.iconSlot)
    surface.dragLiveOffset = Math.max(0, Math.min(maxOffset, surface.dragStartOffset + delta))

    var targetIndex = Math.round(surface.dragLiveOffset / surface.iconSlot)
    var currentIndex = surface.dragWorkingOrder.indexOf(surface.dragKey)
    if (targetIndex !== currentIndex && targetIndex >= 0 && targetIndex < surface.dragWorkingOrder.length) {
      var next = surface.dragWorkingOrder.slice()
      next.splice(currentIndex, 1)
      next.splice(targetIndex, 0, surface.dragKey)
      surface.dragWorkingOrder = next
    }
  }

  function endDrag() {
    if (!surface.dragActive) return
    controller.reorderItems(surface.dragWorkingOrder)
    surface.dragActive = false
    surface.dragKey = ""
    surface.dragWorkingOrder = []
  }

  // --------------------------------------------------------- hover trigger
  // Always-present sliver flush with the chosen edge, spanning the whole
  // edge (matching real screen-edge-triggered auto-hide docks) so the pill
  // doesn't have to be visible for the user to find it.
  PanelWindow {
    id: triggerWindow
    screen: surface.screen
    // Always mapped, even when the trigger has nothing to do (pure
    // always-visible mode with no fullscreen override) — toggling this
    // surface's visible on/off right as its WlrLayershell.layer also needs
    // to change (entering/leaving a fullscreen override) raced the two
    // changes in practice: the pill's own layer switch was observed to take
    // effect live, but the trigger's did not, leaving it stuck on the old
    // layer and unreachable exactly when it was needed. Keeping it mapped
    // unconditionally sidesteps that map/layer-change ordering entirely, at
    // the cost of a harmless (exclusionMode: Ignore, hover-only) edge strip
    // existing even in modes that don't currently use it.
    visible: true
    color: "transparent"

    WlrLayershell.namespace: "dockseid-trigger"
    // Top layer sits below a fullscreened window, so the hover strip would
    // be covered and unreachable there — Overlay stays above it, but only
    // while that's actually needed, so a non-fullscreen desktop is
    // unaffected either way.
    WlrLayershell.layer: surface.fullscreenOverride ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: surface.vertical || surface.position === "top"
      bottom: surface.vertical || surface.position === "bottom"
      left: !surface.vertical || surface.position === "left"
      right: !surface.vertical || surface.position === "right"
    }
    implicitWidth: surface.vertical ? surface.triggerThickness : 0
    implicitHeight: surface.vertical ? 0 : surface.triggerThickness

    HoverHandler {
      onHoveredChanged: surface.triggerHovered = hovered
    }
  }

  // ------------------------------------------------------------- the dock
  PanelWindow {
    id: dockWindow
    screen: surface.screen
    color: "transparent"

    WlrLayershell.namespace: "dockseid"
    WlrLayershell.layer: surface.fullscreenOverride ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: surface.effectiveAlwaysVisible ? ExclusionMode.Auto : ExclusionMode.Ignore

    anchors {
      top: surface.position === "top"
      bottom: surface.position === "bottom"
      left: surface.position === "left"
      right: surface.position === "right"
    }
    margins {
      top: surface.position === "top" ? surface.edgeGap : 0
      bottom: surface.position === "bottom" ? surface.edgeGap : 0
      left: surface.position === "left" ? surface.edgeGap : 0
      right: surface.position === "right" ? surface.edgeGap : 0
    }
    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    BorderSurface {
      id: pill
      color: controller.dockBackground
      // withWidth forces a single uniform width on every side regardless of
      // what the active theme's own popup border happens to specify, so the
      // outline stays even on every corner and the slider below actually
      // has visible effect against any theme.
      borderSpec: Border.withWidth(
        Border.surfaceSpec("popups", "border", controller.dockBorder, 1),
        surface.settings.borderEnabled ? surface.settings.borderWidth : 0)
      radius: controller.dockRadius
      implicitWidth: surface.vertical ? surface.outerThickness : (contentLayout.implicitWidth + Style.space(16) + surface.borderPad * 2)
      implicitHeight: surface.vertical ? (contentLayout.implicitHeight + Style.space(16) + surface.borderPad * 2) : surface.outerThickness

      // Slides the whole pill toward — and past — its own anchored edge to
      // hide it. Whatever crosses the window's own bounds is simply not
      // rendered/hit-testable, so no separate clipping is needed; the
      // always-present triggerWindow is what catches the hover to bring it
      // back.
      x: !surface.vertical ? 0 : (surface.position === "left" ? -surface.slideAmount : surface.slideAmount)
      y: surface.vertical ? 0 : (surface.position === "top" ? -surface.slideAmount : surface.slideAmount)

      HoverHandler {
        onHoveredChanged: surface.pillHovered = hovered
      }

      GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        columns: surface.vertical ? 1 : -1
        rows: surface.vertical ? -1 : 1
        rowSpacing: Style.space(4)
        columnSpacing: Style.space(4)

        // Settings leads the dock (left in horizontal orientation, top in
        // vertical), with the running/pinned apps following after the
        // divider. Adding a new app now lives inside the settings popover
        // (its own tab) instead of a permanent second icon here.
        DockControlButton {
          id: settingsButton
          glyph: "⚙"
          sizeScale: surface.settings.size
          Layout.alignment: Qt.AlignCenter
          onClicked: surface.showSettings()
        }

        Rectangle {
          id: divider
          visible: controller.dockItems.length > 0
          Layout.preferredWidth: surface.vertical ? (surface.thickness - Style.space(20)) : Math.max(1, Style.space(1))
          Layout.preferredHeight: surface.vertical ? Math.max(1, Style.space(1)) : (surface.thickness - Style.space(20))
          Layout.alignment: Qt.AlignCenter
          color: Util.alpha(controller.dockForeground, 0.18)
        }

        // Manually positioned (not a Row/GridLayout flow) so a dragged icon
        // can follow the cursor directly while its neighbors animate around
        // it — see beginDrag/updateDrag/endDrag above.
        Item {
          id: iconStrip
          readonly property int itemCount: controller.dockItems.length
          implicitWidth: surface.vertical ? surface.thickness
            : Math.max(0, iconStrip.itemCount * surface.iconSlot - surface.iconSpacing)
          implicitHeight: surface.vertical
            ? Math.max(0, iconStrip.itemCount * surface.iconSlot - surface.iconSpacing) : surface.thickness

          Repeater {
            model: controller.dockItems

            DockAppIcon {
              id: iconDelegate
              required property int index
              foreground: controller.dockForeground
              accent: controller.dockAccent
              sizeScale: surface.settings.size
              menuOpen: surface.openPopupItem !== null && surface.openPopupItem.key === modelData.key
                && (surface.openPopupKind === "menu" || surface.openPopupKind === "hover")

              readonly property bool isDragging: surface.dragActive && surface.dragKey === modelData.key
              readonly property int visualIndex: surface.dragActive
                ? surface.dragWorkingOrder.indexOf(modelData.key) : index
              readonly property real primaryPos: isDragging ? surface.dragLiveOffset : visualIndex * surface.iconSlot
              readonly property real crossPos: (surface.thickness - slotSize) / 2

              x: surface.vertical ? crossPos : primaryPos
              y: surface.vertical ? primaryPos : crossPos

              Behavior on x { enabled: !iconDelegate.isDragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
              Behavior on y { enabled: !iconDelegate.isDragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

              onHoverEntered: surface.showHover(iconDelegate, modelData)
              onHoverExited: surface.scheduleHideHover()
              onPrimaryClicked: { surface.closePopups(); controller.cycleOrActivate(modelData) }
              onMiddleClicked: if (modelData.running) controller.quitItem(modelData)
              onRightClicked: surface.showContextMenu(iconDelegate, modelData)

              onDragStarted: surface.beginDrag(modelData.key, index)
              onDragMoved: function(dx, dy) { surface.updateDrag(dx, dy) }
              onDragFinished: surface.endDrag()
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------ popup anchor host
  // dockWindow's own size tracks the pill (implicitWidth/Height above), so a
  // popup anchored directly to it needs the compositor to reposition an
  // already-mapped xdg_popup every time dockWindow itself resizes or moves —
  // that live reposition of the actual host surface is what left the
  // rendering artifact, independent of where within it the popup targets.
  // This window spans the whole screen, is fully click-through (empty
  // mask, matching the bar's drag-ghost windows), and never changes size
  // with dock settings, so popups anchor here instead and can freely track
  // the pill without ever perturbing the surface they're attached to.
  PanelWindow {
    id: popupAnchor
    screen: surface.screen
    visible: true
    color: "transparent"

    WlrLayershell.namespace: "dockseid-popup-anchor"
    WlrLayershell.layer: surface.fullscreenOverride ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
  }

  HoverPopup {
    id: hoverPopup
    hostWindow: popupAnchor
    dockWindow: dockWindow
    originX: surface.dockOriginX
    originY: surface.dockOriginY
    dockPosition: surface.position
    onActivateInstance: function(t) { controller.activateToplevel(t); surface.closePopups() }
  }

  IconContextMenu {
    id: contextMenu
    hostWindow: popupAnchor
    dockWindow: dockWindow
    originX: surface.dockOriginX
    originY: surface.dockOriginY
    dockPosition: surface.position
    onPinToggled: if (surface.openPopupItem) controller.togglePin(surface.openPopupItem.key)
    onOpenRequested: if (surface.openPopupItem) controller.launchItem(surface.openPopupItem)
    onNewWindowRequested: if (surface.openPopupItem) controller.newWindowForItem(surface.openPopupItem)
    onQuitRequested: if (surface.openPopupItem) controller.quitItem(surface.openPopupItem)
    onDismissed: if (surface.openPopupKind === "menu") surface.closePopups()
  }

  SettingsPopup {
    id: settingsPopup
    hostWindow: popupAnchor
    dockWindow: dockWindow
    originX: surface.dockOriginX
    originY: surface.dockOriginY
    dockPosition: surface.position
    // Stays live automatically (never touched imperatively elsewhere), so
    // the Add App tab's list always reflects the current pinned set.
    allEntries: controller.addAppEntries
    onAppPicked: function(id) { controller.pinApp(id) }
    onShapePicked: function(v) { controller.setShape(v); settingsPopup.shape = v }
    onOpacityPicked: function(v) { controller.setOpacity(v); settingsPopup.opacityValue = v }
    onThemeModePicked: function(v) { controller.setThemeMode(v); settingsPopup.themeMode = v }
    onCustomColorPicked: function(kind, hex) {
      controller.setCustomColor(kind, hex)
      if (kind === "background") settingsPopup.customBackground = controller.settings.customBackground
      else settingsPopup.customAccent = controller.settings.customAccent
    }
    // Position flips dock orientation (horizontal/vertical) and Monitor
    // relocates to a different screen entirely — both a much bigger
    // structural change than a resize, so still close first for a clean
    // transition. Visibility/Size/Edge Gap only resize/move the pill within
    // the same screen, which popupAnchor above no longer needs to react to,
    // so those can now stay open like the cosmetic settings below.
    onPositionPicked: function(v) { surface.closePopups(); controller.setPosition(v) }
    onMonitorPicked: function(v) { surface.closePopups(); controller.setMonitor(v) }
    onVisibilityPicked: function(v) { controller.setVisibility(v); settingsPopup.visibilityMode = v }
    onSizePicked: function(v) { controller.setSize(v); settingsPopup.size = v }
    onEdgeGapPicked: function(v) { controller.setEdgeGap(v); settingsPopup.edgeGap = v }
    // Purely cosmetic (no window resize/move), so no need to close first.
    onBorderEnabledPicked: function(v) { controller.setBorderEnabled(v); settingsPopup.borderEnabled = v }
    onBorderWidthPicked: function(v) { controller.setBorderWidth(v); settingsPopup.borderWidth = v }
    onShowInFullscreenPicked: function(v) { controller.setShowInFullscreen(v); settingsPopup.showInFullscreen = v }
    onShowWhenEmptyPicked: function(v) { controller.setShowWhenEmpty(v); settingsPopup.showWhenEmpty = v }
    onDismissed: if (surface.openPopupKind === "settings") surface.closePopups()
  }
}
