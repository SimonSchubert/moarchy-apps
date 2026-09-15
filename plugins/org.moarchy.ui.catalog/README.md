# Chrome catalog

A Quickshell window that shows every control in `shared/qs_ui` on one
screen: app bar, back chevron, icon buttons, pill fields (plain / left /
right / both), type roles, checkboxes, FAB.

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
