# Dockseid

A persistent, macOS-style pill dock for [Omarchy](https://omarchy.org). Shows
your running and pinned apps, groups every window of an app under one icon,
and themes itself from your active Omarchy theme by default.

## Features

- **Running apps** — every open application gets a dock icon automatically,
  sourced from Hyprland's toplevel list.
- **Pin apps** — right-click any icon to keep it in the dock even after you
  quit it, or open the gear button's **Add App** tab to search and pin an
  app you haven't opened yet.
- **Reorder icons** — drag any icon (pinned or currently running) to
  rearrange the dock; the order is remembered.
- **Window grouping** — every window of an app stacks on that app's single
  icon. A small badge shows the count when there's more than one; hovering
  lists each window's title so you can jump straight to one (click a row to
  activate it), the same grouping behavior Windows' taskbar uses. Clicking
  the icon itself cycles through the group one window at a time.
- **Theme-aware** — the dock's colors follow `qs.Commons.Color`, so it
  re-themes itself automatically whenever you switch your Omarchy theme (for
  example, to Osaka Jade). Open the gear button to switch to a **Custom**
  palette instead if you want the dock to look different from the rest of
  the desktop.
- **Customization** — the gear button's Settings tab covers which screen(s)
  to show the dock on, which edge it lives on (bottom / top / left / right),
  shape (Square / Rounded / Pill), an optional outline with adjustable
  width, overall size, how far it sits from the screen edge (tracked
  separately for auto-hide vs. always-visible, since a gap that looks right
  floating just wastes space when the dock is pinned in place), and opacity.
- **Auto-hide or always visible** — by default the dock stays out of the way
  and only slides into view when you move the pointer to the screen edge it
  lives on (macOS-style reveal). Switch to **Always visible** in the gear
  popover to pin it in place permanently — like the top bar, it then
  reserves that strip of the screen so windows tile around it instead of
  overlapping it.
- **Over fullscreen apps** — off by default (the dock disappears during
  fullscreen, same as the top bar). Turn it on to have the dock reveal on
  hover over a fullscreen window too, regardless of your visibility setting.

## Usage

- **Left click** — launch a pinned-but-closed app, activate/minimize a
  single window, or cycle to the next window in a group.
- **Middle click** — quit all of an app's windows.
- **Right click** — pin/unpin, open a pinned-but-closed app, or quit.
- **Hover** — see the app name, or the window list for a multi-window group.

## Installation

```sh
omarchy plugin add <git-url-of-this-repo> --enable
```

Or for local development, clone/symlink this folder into
`~/.config/omarchy/plugins/<id>/` and run:

```sh
omarchy plugin enable io.github.silkvain.dockseid
```

## Configuration

All settings (pinned apps, shape, opacity, theme mode, custom colors) are
stored in `~/.local/state/dockseid/state.json` and edited through the dock's
own gear-icon popover — there's nothing to hand-edit.

## License

MIT — see [LICENSE](LICENSE).
