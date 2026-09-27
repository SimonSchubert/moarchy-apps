# The kit

What every Quickshell app in `apps/` has in common, and nothing it does not: the
window, the host API, the theme, the phone and desktop layouts, the way back
out, and the dozen widgets every app was drawing again. It was taken out of
Vitals, Couch and Airwaves, where the same files had been copied three times.

Every app in `apps/` that is ours is built on it; the older phone-only kit,
`shared/qs_ui`, went with the last of the plugins that used it.

## How an app gets it

Linked, as `apps/<name>/kit -> ../../shared/kit`, and imported unqualified:

```qml
import "kit"
import "kit/Theme.js" as Theme   // only for the arithmetic
```

`packaging/release.sh` swaps the link for a copy of the kit at the same tag,
so a tarball is the app and the exact kit it was checked against. The
PKGBUILD installs it as `/usr/share/<package>/kit/`. There is no runtime
package and no import from the shell.

## An app is an App

`Panel.qml` is an `App`, which is an `Item` the Omarchy shell can hold as a
panel plugin (`kinds: ["panel"]`, `keepLoaded: true`) and which `shell.qml`
runs as its own process with `standalone: true`:

```qml
App {
  id: root
  appId: "org.moarchy.habits"
  title: "Habits"
  store: Store { name: "moarchy-habits"; defaults: ({ lastTab: "today" }) }
  tabs: [{ key: "today", label: "Today", glyph: G.today }, ...]
  settings: Component { SettingsPage { app: root; AppearanceSection { app: root } } }

  TodayView { anchors.fill: parent; app: root; visible: root.tab === "today" }
}
```

- **Host API.** `open(payload)`, `close()`, `toggle()`, `dismiss()` and
  `back()`, as the shell calls them. `back()` steps out one level (a dialog,
  a pushed page, the app's own `stepBack`, the first tab) and answers false at
  the root, so the phone's gesture bar hides the panel itself.
- **Layout by width, never by device.** `compact` is below `breakpoint`
  (720 px). Compact: tabs at the bottom, pages that stack with `push()`,
  Settings behind a gear, 44 px targets, no hover. Wide: a rail of tabs,
  Settings as its last item, 38 px targets, hover, `1`–`9` and `,` on the
  keyboard. `contentArea.width` is what the views have.
- **Slots.** `actions` (header buttons), `mark` (the app's logo), `caption`,
  `railFooter`, `page` (draws `topPage`), `keyHandler`, `stepBack`,
  `header: false` for an app that draws its own top.
- **Standalone.** Opens itself, quits when closed after `store.flush()`,
  and quits after `MOARCHY_QUIT_AFTER` seconds for a headless run.

## Theme

`HostTheme` reads, best first: the shell's own `qs.Commons` (compiled from a
string, so a plain Quickshell does not fail to load the file); Omarchy's
`colors.toml` and the `[menu]` of `shell.toml`; a plain light or dark palette.
`Tokens` turns that into what views draw with — `app.ui.bg`, `.text`,
`.muted`, `.accent`, `.surface`, `.well`, `.good`/`.warn`/`.bad`, `.font`,
`.radius`, `.target`, `.fs.sm` and the rest. An app with colours of its own
(a graph's series, a game's pieces) declares its own `Tokens` with them
added, and keeps every hex value there, as the theme's fallback.
`scripts/app-lint.py` fails a view that writes a colour.

## Checking

```sh
docker build --platform linux/arm64 -f docker/Dockerfile.qml -t moarchy-qml .
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/app-check.sh <app>
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/app-shot.sh <app> .shots/<app>
```

`app-check.sh` is the lints, `qmllint`, the tests and an offscreen run that
fails on any QML warning. `app-shot.sh` photographs the app at 360×720 and
1280×820, light and dark, or the list in the app's `dev/shots`. Look at them.
