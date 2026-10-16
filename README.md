# Hotkey Wheel

A theme-aware action wheel for Omarchy: hold middle-click (or a mouse side
button), point, release. Its 4 to 12 slots run whatever you choose: apps,
Omarchy actions, any of your keybindings, or your own commands. You edit them
from a drawer in the bar, and the wheel uses your theme's menu colours,
border and fonts.

![Hotkey Wheel open over the desktop, pointing at Color picker](preview.png)

## Use

Hold the button, point toward a slot and release to run it. Release where you
started, press **Esc** or right-click to cancel. While you hold, other mouse
buttons do nothing, so they never click the window under the wheel.

## Change the slots

Click the wheel icon (󰄦) in the bar. In the drawer, click a slot (or press
its number) to open the picker, or drag a slot onto another to swap them. The
picker has four searchable tabs:

- **Apps**: your installed apps.
- **Omarchy**: screenshot, color picker, lock, media keys, the Omarchy menus
  and more.
- **Keybindings**: every Omarchy keybinding, your own included, read the same
  way SUPER + K reads them.
- **Custom**: your saved custom actions, and **Create new action** for your
  own name, icon, description and shell command. **Try it** runs it once;
  **Save it** puts it on the slot and keeps it. Both first show you the
  command and its script to read, and go on only when you click **Yes**. Click a saved action to see
  what it does, its command and its script, and to use, rename or remove it.

  Not sure what to write? Describe what you want under **Ask an agent** and
  **Copy prompt** into Claude Code, Codex or any other agent. Its answer ends
  with a code block of four lines, Name to Command: copy it, open the slot
  again and **Paste answer** fills in the form. Read the command and any
  script it wrote when Try it or Save it shows them: once saved, it runs
  like a keybinding you wrote yourself.

**Slots** sets how many the wheel has, and **Show names** shows or hides the
names under the icons. Picks from the lists and these two settings are kept
when you press **Save** (or Ctrl+S); **Cancel** throws them away.

## Install

```bash
omarchy plugin add https://github.com/erikrjohansson/omarchy-hotkey-wheel.git --enable
```

This puts the wheel's icon on the bar. To open the wheel with your mouse,
Hyprland needs one more line. Hyprland decides what mouse buttons do, and the
plugin only changes your Hyprland config when you ask it to, so you add it
once, either way:

- **In the drawer**: click **Set up**. It adds the line (marked, at the end
  of `~/.config/hypr/bindings.lua`) and reloads Hyprland. Nothing else in the
  file changes.
- **By hand**: add this to `~/.config/hypr/bindings.lua`, then run
  `hyprctl reload`:

  ```lua
  dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.erikrjohansson.hotkey-wheel/bindings.lua")
  ```

Without it, the drawer works but holding the button does nothing.

Middle-click opens the wheel by default, so plain middle-click no longer
pastes (Ctrl+middle-click still reaches your apps). To use another button, pick it under
**Open with** in the drawer: **Super + middle** keeps normal middle-click, and
**Back** / **Forward** use the mouse's side buttons. The **On** switch in the
drawer's top right corner turns the wheel off without removing anything.

## Update

```bash
omarchy plugin update io.github.erikrjohansson.hotkey-wheel && hyprctl reload && omarchy restart shell
```

## Remove

```bash
~/.config/omarchy/plugins/io.github.erikrjohansson.hotkey-wheel/hotkey-wheel unsetup && omarchy plugin remove io.github.erikrjohansson.hotkey-wheel
```

`unsetup` removes the line Set up added and reloads Hyprland; if you added it
by hand, delete it yourself first. Your slots and custom actions stay in
`~/.config/omarchy/extensions/` (the `hotkey-wheel*` files); delete them if
you don't plan to come back.

## Requirements

Omarchy 4 with the Lua Hyprland config (tested on Omarchy 4.0.0 alpha,
Hyprland 0.56.2 and Quickshell 0.3.1). Uses `hyprctl`, `bash`, GNU coreutils, `grep`, `sed` and `awk`,
`iconv`, `gtk-launch`, `uwsm-app`, `wl-copy` and `wl-paste`, all part of
Omarchy. The Custom tab's **Copy prompt** works with any agent you use.

## License

MIT
