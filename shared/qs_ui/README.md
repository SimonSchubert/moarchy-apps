# Shared Quickshell chrome

Phone chrome for moarchy plugins: app bar, pill field, icon button, back
chevron, checkbox, type roles, FAB, context menu, bottom nav. Palette comes
from the same `colors.toml` the rest of the device reads.

A third-party plugin cannot import `moarchy.common`, so this directory is
**copied into the plugin** as `ui/` at install time. There is no runtime
package and no import from the shell.

```qml
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
```

`plugins/org.moarchy.ui.catalog` is the review surface: every control on
one window. Install it with that plugin's `install-on-device.sh`, which
copies this tree into `ui/` on the phone, or run it on a laptop with that
plugin's `run-local.sh`.

## What it needs

Quickshell, QtQuick, QtQuick.Layouts, `Qt5Compat.GraphicalEffects` for the
icon tint, and a Wayland compositor with layer shell for `AppWindow`. Nothing
from `omarchy-shell`: **no file here imports `qs.Commons` or `qs.Ui`**, which
is what lets an app built on the kit ship to a system that has Quickshell and
nothing of ours.

Three things used to come from the shell, and each has a portable answer that
keeps the phone's behaviour intact rather than approximating it:

- **`Style.font.body`** — `Metrics.shellBody(item)` compiles `import
  qs.Commons` as a string once at startup and returns the shell's own body
  size when that import resolves, 16 when it does not. Text size set in
  Settings still reaches every app on the phone.
- **`Ui.TextField`** — replaced by a `TextInput` in `TextField.qml`. The
  on-screen keyboard was never the shell's to hand out: `moarchy-keyboard`
  binds `zwp_input_method_v2`, Qt speaks text-input-v3 for whatever holds
  focus, so a field raises it through the compositor either way.
- **`Util.alpha`** — `Theme.alpha`, the same `Qt.rgba` call.

Icons resolve Adwaita's absolute paths first and fall back to
`Quickshell.iconPath()` only when a file is missing, so the phone never pays
for a theme walk and another distribution still gets glyphs.
