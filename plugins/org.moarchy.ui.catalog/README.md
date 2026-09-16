# Chrome catalog

A Quickshell window that shows every control in `shared/qs_ui`, on three tabs.

**Chrome** is every control on one scrolling page: type roles, pill fields
(plain / left / right / both), buttons at their three weights, chips, icon
buttons, the back chevron, checkboxes, tiles, a group of rows, the app bar,
the FAB, the bottom nav and the overflow menu.

**Boxes** is the system those controls are built from, drawn rather than
described: the five steps of `Theme.surface()` as five bands, a group holding
rows holding chips so the nesting rule can be *seen* to be concentric, and the
theme's eight hues as `Theme.tint()` washes. It is the fastest way to tell
whether a change to the ramp or the radius scale did what it meant to, and the
only way to tell whether it did it in both directions -- run it again under
catppuccin-latte and every step has to go the other way.

**Empty** is the state that used to be a grey sentence in the middle of a black
rectangle in eight apps, and is one component in all of them now.

```sh
plugins/org.moarchy.ui.catalog/install-on-device.sh
```

Then tap **Chrome** in the drawer, or:

```sh
omarchy-shell shell toggle org.moarchy.ui.catalog
```

The kit is copied into this plugin as `ui/` at install time. Edit
`shared/qs_ui`, reinstall, and the window is the review.

On a machine with Quickshell and no omarchy, the same window runs on its own:

```sh
plugins/org.moarchy.ui.catalog/run-local.sh
```

That is also the check that the kit stayed portable. If a control starts
needing `qs.Commons` or `qs.Ui` again, this is where it fails to load, before
an app built on it inherits the problem.
