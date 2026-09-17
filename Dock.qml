import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel

// Dockseid: a persistent, macOS-style pill dock. Declared as a keepLoaded
// "panel" plugin so the shell mounts it once at startup and it stays visible
// permanently, rather than being summoned/hidden like a popup.
Item {
  id: root

  property string stateDir: Quickshell.env("HOME") + "/.local/state/dockseid"
  property string statePath: root.stateDir + "/state.json"

  property var pinnedIds: []
  // The user's manual drag order — a flat list of dock-item keys covering
  // pinned and running-unpinned items alike. Empty until they reorder
  // anything, at which point it fully describes the visible arrangement.
  property var iconOrder: []
  property var settings: DockModel.defaultSettings()
  property bool stateLoaded: false

  // -------------------------------------------------------------- state io
  function persist() {
    if (!root.stateLoaded) return
    stateFile.setText(DockModel.serializeState({ pinned: root.pinnedIds, order: root.iconOrder, settings: root.settings }))
  }

  function loadState(text) {
    var state = DockModel.parseState(text)
    root.pinnedIds = state.pinned
    root.iconOrder = state.order
    root.settings = state.settings
    root.stateLoaded = true
    root.rebuildItems()
  }

  Process {
    id: ensureStateDir
    command: ["mkdir", "-p", root.stateDir]
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
    onFileChanged: reload()
  }

  // ----------------------------------------------------- app/window model
  function resolveEntry(appId) {
    if (!appId) return null
    var byId = DesktopEntries.byId(appId)
    if (byId) return byId
    return DesktopEntries.heuristicLookup(appId)
  }

  function iconForKey(key, entry) {
    var icon = (entry && entry.icon) ? entry.icon : ""
    var path = icon.length > 0 ? Quickshell.iconPath(icon, true) : ""
    if (path.length > 0) return path
    path = Quickshell.iconPath(key, true)
    if (path.length > 0) return path
    return Quickshell.iconPath("application-x-executable", true)
  }

  function nameForKey(key, entry) {
    if (entry && entry.name && String(entry.name).length > 0) return entry.name
    return key
  }

  // Only apps that explicitly declare an XDG "new window" action get one in
  // the dock's context menu — never a blind re-launch of the app's normal
  // Exec line. That's deliberate: a generic re-launch is exactly what causes
  // trouble for single-instance apps (Steam) or apps with their own internal
  // window management (DaVinci Resolve) that never publish such an action
  // and so are correctly left without the option.
  function findNewWindowAction(entry) {
    if (!entry || !entry.actions) return null
    var actions = entry.actions
    for (var i = 0; i < actions.length; i++) {
      var a = actions[i]
      var id = String(a.id || "").toLowerCase()
      var name = String(a.name || "").toLowerCase()
      var idMatch = id.indexOf("new") !== -1 && id.indexOf("window") !== -1
      var nameMatch = name.indexOf("new") !== -1 && name.indexOf("window") !== -1
      if (idMatch || nameMatch) return a
    }
    return null
  }

  function newWindowForItem(item) {
    if (item && item.newWindowAction) item.newWindowAction.execute()
  }

  property var dockItems: []

  // Pinned apps first (in pin order), then any running-but-unpinned apps in
  // first-seen order — this is just the fallback for anything the user
  // hasn't manually dragged yet; sortByOrder() below applies their actual
  // saved arrangement on top of it. Every open window is grouped under its
  // app's single dock slot instead of getting its own icon.
  function rebuildItems() {
    var groups = ({})
    var discoveryOrder = []
    var toplevels = ToplevelManager.toplevels.values

    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      var entry = root.resolveEntry(t.appId)
      var key = entry ? entry.id : t.appId
      if (!groups[key]) { groups[key] = { key: key, entry: entry, toplevels: [] }; discoveryOrder.push(key) }
      groups[key].toplevels.push(t)
    }

    var items = []
    var consumed = ({})

    for (var p = 0; p < root.pinnedIds.length; p++) {
      var pid = root.pinnedIds[p]
      var g = groups[pid]
      var entry2 = g ? g.entry : DesktopEntries.byId(pid)
      items.push({
        key: pid,
        name: root.nameForKey(pid, entry2),
        iconSource: root.iconForKey(pid, entry2),
        pinned: true,
        toplevels: g ? g.toplevels : [],
        running: !!g && g.toplevels.length > 0,
        count: g ? g.toplevels.length : 0,
        newWindowAction: root.findNewWindowAction(entry2)
      })
      consumed[pid] = true
    }

    for (var o = 0; o < discoveryOrder.length; o++) {
      var k = discoveryOrder[o]
      if (consumed[k]) continue
      var grp = groups[k]
      items.push({
        key: k,
        name: root.nameForKey(k, grp.entry),
        iconSource: root.iconForKey(k, grp.entry),
        pinned: false,
        toplevels: grp.toplevels,
        running: true,
        count: grp.toplevels.length,
        newWindowAction: root.findNewWindowAction(grp.entry)
      })
    }

    root.dockItems = DockModel.sortByOrder(items, root.iconOrder)
  }

  // Called once a drag-reorder gesture on the dock completes, with the full
  // new key sequence of whatever was visible during the drag.
  function reorderItems(orderKeys) {
    root.iconOrder = orderKeys.slice()
    root.persist()
    root.rebuildItems()
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.rebuildItems() }
  }
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildItems() }
  }

  // --------------------------------------------------------- pin actions
  function isPinned(key) { return root.pinnedIds.indexOf(key) !== -1 }

  function togglePin(key) {
    var next = root.pinnedIds.slice()
    var idx = next.indexOf(key)
    if (idx === -1) next.push(key)
    else next.splice(idx, 1)
    root.pinnedIds = next
    root.persist()
    root.rebuildItems()
  }

  function pinApp(id) {
    if (root.isPinned(id)) return
    var next = root.pinnedIds.slice()
    next.push(id)
    root.pinnedIds = next
    root.persist()
    root.rebuildItems()
  }

  // ------------------------------------------------------ window actions
  function launchItem(item) {
    var entry = DesktopEntries.byId(item.key) || DesktopEntries.heuristicLookup(item.key)
    if (entry) entry.execute()
  }

  // Click behavior: launch when nothing is open, minimize/restore a single
  // window, or cycle through a group's windows one at a time (the same
  // "click again to get to the next one" grouping Windows uses).
  function cycleOrActivate(item) {
    var list = item.toplevels
    if (list.length === 0) { root.launchItem(item); return }

    if (list.length === 1) {
      var only = list[0]
      if (only.minimized) { only.minimized = false; only.activate() }
      else if (only.activated) { only.minimized = true }
      else { only.activate() }
      return
    }

    var activeIdx = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].activated) { activeIdx = i; break }
    }
    var nextIdx = (activeIdx + 1) % list.length
    list[nextIdx].minimized = false
    list[nextIdx].activate()
  }

  function activateToplevel(t) {
    t.minimized = false
    t.activate()
  }

  function quitItem(item) {
    for (var i = 0; i < item.toplevels.length; i++) item.toplevels[i].close()
  }

  // ------------------------------------------------------------ settings
  function setShape(value) {
    root.settings = Object.assign({}, root.settings, { shape: DockModel.normalizeShape(value) })
    root.persist()
  }
  function setOpacity(value) {
    root.settings = Object.assign({}, root.settings, { opacity: DockModel.clampOpacity(value) })
    root.persist()
  }
  function setThemeMode(value) {
    root.settings = Object.assign({}, root.settings, { themeMode: value === "custom" ? "custom" : "system" })
    root.persist()
  }
  function setCustomColor(kind, hex) {
    var next = Object.assign({}, root.settings)
    if (kind === "background") next.customBackground = DockModel.normalizeHex(hex, next.customBackground)
    else next.customAccent = DockModel.normalizeHex(hex, next.customAccent)
    root.settings = next
    root.persist()
  }
  function setPosition(value) {
    root.settings = Object.assign({}, root.settings, { position: DockModel.normalizePosition(value) })
    root.persist()
  }
  function setMonitor(value) {
    root.settings = Object.assign({}, root.settings, { monitor: DockModel.normalizeMonitor(value) })
    root.persist()
  }
  function setVisibility(value) {
    root.settings = Object.assign({}, root.settings, { visibility: DockModel.normalizeVisibility(value) })
    root.persist()
  }
  function setSize(value) {
    root.settings = Object.assign({}, root.settings, { size: DockModel.clampSize(value) })
    root.persist()
  }
  // Writes to whichever of edgeGapAutohide/edgeGapAlways matches the current
  // visibility mode, so the other mode's offset is left untouched.
  function setEdgeGap(value) {
    var key = root.settings.visibility === "always" ? "edgeGapAlways" : "edgeGapAutohide"
    var patch = {}
    patch[key] = DockModel.clampEdgeGap(value, root.settings[key])
    root.settings = Object.assign({}, root.settings, patch)
    root.persist()
  }
  function setBorderEnabled(value) {
    root.settings = Object.assign({}, root.settings, { borderEnabled: !!value })
    root.persist()
  }
  function setBorderWidth(value) {
    root.settings = Object.assign({}, root.settings, { borderWidth: DockModel.clampBorderWidth(value) })
    root.persist()
  }
  function setShowInFullscreen(value) {
    root.settings = Object.assign({}, root.settings, { showInFullscreen: !!value })
    root.persist()
  }
  function setShowWhenEmpty(value) {
    root.settings = Object.assign({}, root.settings, { showWhenEmpty: !!value })
    root.persist()
  }

  // Follows qs.Commons.Color (and thus the active Omarchy theme) unless the
  // user explicitly opted into a dock-local palette.
  readonly property bool customTheme: root.settings.themeMode === "custom"
  readonly property color dockBackground: root.customTheme
    ? Util.alpha(root.settings.customBackground, root.settings.opacity)
    : Util.alpha(Color.background, root.settings.opacity)
  readonly property color dockAccent: root.customTheme ? root.settings.customAccent : Color.accent
  readonly property color dockForeground: Color.foreground
  readonly property color dockBorder: root.customTheme ? Util.alpha(root.settings.customAccent, 0.6) : Color.popups.border

  // The pill's fixed cross-axis size, in both the horizontal (top/bottom) and
  // vertical (left/right) orientations — DockSurface swaps which axis this
  // maps to, but the corner radius always derives from it so the pill reads
  // as a stadium shape either way.
  readonly property real thickness: Style.space(60) * root.settings.size
  readonly property real dockRadius: root.settings.shape === "square" ? Style.space(10)
    : (root.settings.shape === "rounded" ? root.thickness / 4 : root.thickness / 2)

  readonly property var addAppEntries: {
    var out = []
    var apps = DesktopEntries.applications.values || []
    for (var i = 0; i < apps.length; i++) {
      var e = apps[i]
      if (e.noDisplay) continue
      if (root.isPinned(e.id)) continue
      out.push({ id: e.id, name: e.name, iconSource: root.iconForKey(e.id, e) })
    }
    out.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return out
  }

  // Which screen(s) to mount a dock surface on: every screen, just the first
  // one, or a specific screen by name (falling back to the first screen if
  // that one was unplugged).
  readonly property var activeScreens: {
    var all = Quickshell.screens || []
    if (root.settings.monitor === "all") return all
    if (root.settings.monitor === "primary") return all.length > 0 ? [all[0]] : []
    for (var i = 0; i < all.length; i++) {
      if (all[i].name === root.settings.monitor) return [all[i]]
    }
    return all.length > 0 ? [all[0]] : []
  }

  // No "Primary"/"Default" entry here on purpose — with every real display
  // listed, the user can just pick the one they mean.
  readonly property var monitorOptions: {
    var out = [{ value: "all", label: "All monitors" }]
    var all = Quickshell.screens || []
    for (var i = 0; i < all.length; i++) out.push({ value: all[i].name, label: all[i].name })
    return out
  }

  Component.onCompleted: {
    ensureStateDir.running = true
    root.rebuildItems()
  }

  Variants {
    model: root.activeScreens

    DockSurface {
      required property var modelData
      screen: modelData
      controller: root
    }
  }
}
