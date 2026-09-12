# queens

Packaging for [Queens](https://github.com/sidhant947/Queens), a crown-placement
logic puzzle by sidhant947. Not an app written here: this directory holds the
Linux runner upstream does not ship, a `.desktop` file, and a PKGBUILD that
builds their code against ours.

## Why it is here at all

Queens is a Flutter app that targets Android. It runs on aarch64 Linux
perfectly well — the SDK's git checkout bootstraps a native arm64 toolchain and
`flutter build linux --release` produces a 23 MB bundle in about twenty seconds
— but it has no `linux/` directory, because `flutter create --platforms=linux .`
generates one on demand and an Android app has never needed it.

That generated runner is the whole problem. It is a template that changes with
the SDK, it is not in upstream's repository, and it is where the one change a
phone needs has to live. Generating it during the build would make the window's
behaviour a function of whichever Flutter the build machine happened to have,
and would drop our change silently the first time the template moved. So it is
committed here, once, and the PKGBUILD copies it over the upstream checkout.

## The one change

Flutter's Linux template hardcodes a GTK header bar on Wayland — its own comment
says "assume the header bar will work". On a 360x720 phone that bar is 40
logical pixels of chrome and a close button nobody taps, and the compositor owns
the frame anyway.

`linux/runner/my_application.cc` reads `QUEENS_NO_TITLEBAR=1` and, when it is
set, asks for neither a header bar nor decorations and opens at phone size.
Unset — which is every desktop — the original GNOME and X11 branches decide
exactly as they did before. `queens.desktop` sets it; a shell on a laptop does
not, and gets an ordinary window with a titlebar.

It is deliberately an environment variable rather than an `#ifdef __aarch64__`:
an Asahi laptop, a Pi 5 and an Ampere workstation are all arm64 *desktops*, and
keying phone behaviour to the architecture would take their titlebars away.

That change is upstreamable as it stands, and should go upstream. If it lands,
this directory keeps only the PKGBUILD.

## Building

    packaging/release.sh queens 1.0.8      # -> dist/moarchy-queens-1.0.8.tar.gz
    # upload as the queens-v1.0.8 asset, then pin its sha256 in PKGBUILD

The build needs Flutter, which is in no pacman repository for aarch64, so it is
not a `makedepends`: the PKGBUILD uses one already on `PATH` and otherwise
clones the pinned tag itself. Build it on an aarch64 machine — the phone image
builder or the VM, both of which have the SDK — not in the Python container the
other apps here use.
