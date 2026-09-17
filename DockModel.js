// Pure helpers for Dockseid's persisted state (~/.local/state/dockseid/state.json).
// No Quickshell/QML singleton access here — Dock.qml owns anything that
// needs DesktopEntries, Quickshell.iconPath, or ToplevelManager.

.pragma library

// Ship with the dock's best-feeling setup already on — someone installing
// Dockseid for the first time should get a fully-featured, tasteful dock
// immediately, with the tweak knobs there for whoever wants to deviate
// rather than being required to opt into what most people would want anyway.
function defaultSettings() {
  return {
    shape: "pill",           // "square" | "rounded" | "pill"
    opacity: 0.7,             // dock surface alpha — 70%
    themeMode: "system",      // "system" | "custom"
    customBackground: "#1e1e2e",
    customAccent: "#8aadf4",
    position: "bottom",       // "bottom" | "top" | "left" | "right"
    monitor: "primary",       // "all" | "primary" | a specific screen name
    visibility: "autohide",   // "autohide" | "always"
    size: 0.8,                 // scale factor applied to icon/pill sizing — 80%
    // Tracked separately per visibility mode: a wide gap reads nicely for a
    // floating auto-hide dock, but the same gap in always-visible mode just
    // eats screen space for no reason since the dock isn't trying to look
    // "detached" there. Switching modes keeps each one's own last value
    // instead of carrying one over onto the other.
    edgeGapAutohide: 12,       // px gap kept clear of the physical screen edge
    edgeGapAlways: 0,
    borderEnabled: true,       // whether the pill draws an outline at all
    borderWidth: 2,            // px, uniform on every side when enabled
    // On by default: a fullscreened app still reveals the dock on hover
    // instead of blocking it outright, so it stays reachable (raised above
    // the fullscreen window) without permanently occupying the screen.
    showInFullscreen: true,
    // On by default. Only relevant in auto-hide mode: when on, a screen
    // with no open windows at all keeps the dock permanently shown there
    // instead of hiding it — nothing else is using that space anyway.
    // Irrelevant (and ignored) in always-visible mode, which is already
    // permanently shown regardless of what's open.
    showWhenEmpty: true
  }
}

function defaultState() {
  return { version: 1, pinned: [], order: [], settings: defaultSettings() }
}

function clampOpacity(value) {
  var n = Number(value)
  if (!isFinite(n)) return defaultSettings().opacity
  return Math.max(0.35, Math.min(1, n))
}

function clampSize(value) {
  var n = Number(value)
  if (!isFinite(n)) return defaultSettings().size
  return Math.max(0.7, Math.min(1.6, n))
}

// Plain screen pixels, not run through Style.space() — this compensates for
// a physical bezel, which has nothing to do with the UI's font/spacing scale.
function clampEdgeGap(value, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback === undefined ? 0 : fallback
  return Math.max(0, Math.min(48, n))
}

function clampBorderWidth(value) {
  var n = Number(value)
  if (!isFinite(n)) return defaultSettings().borderWidth
  return Math.max(1, Math.min(6, n))
}

function normalizeShape(value) {
  return (value === "square" || value === "rounded" || value === "pill") ? value : "pill"
}

function normalizePosition(value) {
  return (value === "top" || value === "left" || value === "right") ? value : "bottom"
}

function normalizeMonitor(value) {
  var v = typeof value === "string" ? value.trim() : ""
  return v.length > 0 ? v : "primary"
}

function normalizeVisibility(value) {
  return value === "always" ? "always" : "autohide"
}

function isValidHex(value) {
  return typeof value === "string" && /^#[0-9A-Fa-f]{6}$/.test(value)
}

function normalizeHex(value, fallback) {
  return isValidHex(value) ? value : fallback
}

function normalizeSettings(raw) {
  var d = defaultSettings()
  var s = (raw && typeof raw === "object") ? raw : {}
  return {
    shape: normalizeShape(s.shape),
    opacity: clampOpacity(s.opacity === undefined ? d.opacity : s.opacity),
    themeMode: s.themeMode === "custom" ? "custom" : "system",
    customBackground: normalizeHex(s.customBackground, d.customBackground),
    customAccent: normalizeHex(s.customAccent, d.customAccent),
    position: normalizePosition(s.position),
    monitor: normalizeMonitor(s.monitor),
    visibility: normalizeVisibility(s.visibility),
    size: clampSize(s.size === undefined ? d.size : s.size),
    // s.edgeGap is the pre-split field (single shared gap) — if present and
    // the new per-mode fields aren't, seed both from it so upgrading from an
    // older state.json doesn't reset anyone's offset to the default.
    edgeGapAutohide: clampEdgeGap(
      s.edgeGapAutohide !== undefined ? s.edgeGapAutohide : (s.edgeGap !== undefined ? s.edgeGap : d.edgeGapAutohide),
      d.edgeGapAutohide),
    edgeGapAlways: clampEdgeGap(
      s.edgeGapAlways !== undefined ? s.edgeGapAlways : (s.edgeGap !== undefined ? s.edgeGap : d.edgeGapAlways),
      d.edgeGapAlways),
    borderEnabled: s.borderEnabled === undefined ? d.borderEnabled : !!s.borderEnabled,
    borderWidth: clampBorderWidth(s.borderWidth === undefined ? d.borderWidth : s.borderWidth),
    showInFullscreen: s.showInFullscreen === undefined ? d.showInFullscreen : !!s.showInFullscreen,
    showWhenEmpty: s.showWhenEmpty === undefined ? d.showWhenEmpty : !!s.showWhenEmpty
  }
}

// Where a popup should grow from, given which screen edge the dock itself is
// anchored to — always positioned clear of the dock, pointing back at it.
// Mirrors the bar's own tooltip placement math (Bar.qml's tooltipAnchor).
function anchorOffset(position, anchorWidth, anchorHeight, popupWidth, popupHeight, gap) {
  if (position === "top") return { x: anchorWidth / 2 - popupWidth / 2, y: anchorHeight + gap }
  if (position === "left") return { x: anchorWidth + gap, y: anchorHeight / 2 - popupHeight / 2 }
  if (position === "right") return { x: -popupWidth - gap, y: anchorHeight / 2 - popupHeight / 2 }
  return { x: anchorWidth / 2 - popupWidth / 2, y: -popupHeight - gap } // bottom (default)
}

function normalizePinned(raw) {
  if (!Array.isArray(raw)) return []
  var seen = ({})
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var id = String(raw[i] || "").trim()
    if (id.length === 0 || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

// Same shape as pinned (a deduped list of dock-item keys) — kept as a
// separate name because it means something different: the user's manual
// drag order, covering pinned and running-unpinned items alike.
function normalizeOrder(raw) {
  return normalizePinned(raw)
}

// Arranges dockItems per the user's saved drag order. Anything not yet in
// `orderKeys` (an app the user has never dragged, e.g. freshly launched)
// keeps its place in `items`' existing order and is appended after the
// known ones — matching today's "pinned first, then first-seen" default
// for whatever hasn't been manually arranged.
function sortByOrder(items, orderKeys) {
  var rank = ({})
  for (var i = 0; i < orderKeys.length; i++) rank[orderKeys[i]] = i
  var known = []
  var unknown = []
  for (var j = 0; j < items.length; j++) {
    if (Object.prototype.hasOwnProperty.call(rank, items[j].key)) known.push(items[j])
    else unknown.push(items[j])
  }
  known.sort(function(a, b) { return rank[a.key] - rank[b.key] })
  return known.concat(unknown)
}

// Tolerant parse: malformed/missing fields fall back to defaults instead of
// throwing, so a corrupt state file never blocks the dock from rendering.
function parseState(rawText) {
  var parsed = null
  try { parsed = JSON.parse(rawText) } catch (e) { parsed = null }
  if (!parsed || typeof parsed !== "object") return defaultState()
  return {
    version: 1,
    pinned: normalizePinned(parsed.pinned),
    order: normalizeOrder(parsed.order),
    settings: normalizeSettings(parsed.settings)
  }
}

function serializeState(state) {
  var safe = {
    version: 1,
    pinned: normalizePinned(state ? state.pinned : []),
    order: normalizeOrder(state ? state.order : []),
    settings: normalizeSettings(state ? state.settings : null)
  }
  return JSON.stringify(safe, null, 2) + "\n"
}
