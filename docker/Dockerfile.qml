# The Qt stack the phone has and a Mac does not.
#
#   docker build --platform linux/arm64 -f docker/Dockerfile.qml -t moarchy-qml .
#   docker run --rm --platform linux/arm64 -v "$PWD:/src" -w /src moarchy-qml scripts/qml-check.sh
#
# Arch, and not the Debian image this started as, for one reason that decides
# everything else: quickshell is `extra/quickshell` for aarch64, so one pacman
# line gets the same Qt and the same Quickshell the phone runs. On Debian the
# module is absent, and then `qmllint` reports every `import Quickshell` as an
# unresolved type and the real warnings drown in it.
#
# Separate from Dockerfile.dev rather than added to it: that image is gtk4,
# libadwaita, python-gobject, Xvfb, xdotool and ImageMagick, none of which a
# plugin needs. As the apps port over it should shrink to nothing and be
# deleted, not unpicked.
FROM --platform=linux/arm64 menci/archlinuxarm:base

# Docker Desktop's VM kernel does not expose Landlock, which pacman 7 uses to
# sandbox downloads. Same line, same reason, as docker/Dockerfile.dev.
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

RUN pacman -Syu --noconfirm --needed \
      quickshell qt6-declarative qt6-5compat \
      adwaita-icon-theme adwaita-fonts cantarell-fonts ttf-dejavu \
      sway wtype grim mesa \
      python jq && \
    pacman -Scc --noconfirm

# qmltestrunner is inside qt6-declarative, which quickshell already depends on,
# so the test gate costs the packages nothing: `check()` in a plugin PKGBUILD
# runs the same binary an AUR user already has.
#
# qt6-5compat is NOT pulled in by quickshell, and it is not optional: every
# icon in the kit is tinted through Qt5Compat.GraphicalEffects, so without it
# the first Chrome.Icon fails the whole document. Found by running Launches in
# a container that had only quickshell.
# What the apps in apps/ draw with and play through. Every icon in shared/kit
# is a JetBrains Mono Nerd Font glyph: without the font a screenshot is a row
# of empty boxes and still exits 0. Noto is what an Omarchy desktop's
# `sans-serif` resolves to, so the text in a shot has the right width. mpv is
# Airwaves'. pywayland and the wlr protocols drive a headless sway's pointer
# (swaymsg's own clicks do nothing); the scanner writes its bindings once.
RUN pacman -Sy --noconfirm --needed \
      ttf-jetbrains-mono-nerd noto-fonts qt6-imageformats mpv \
      python-fonttools python-pywayland wlr-protocols wayland-protocols pkgconf && \
    pacman -Scc --noconfirm && \
    mkdir -p /opt/wlp/proto && \
    python3 -m pywayland.scanner -i /usr/share/wayland/wayland.xml \
      /usr/share/wlr-protocols/unstable/wlr-virtual-pointer-unstable-v1.xml -o /opt/wlp/proto

ENV PATH=/usr/lib/qt6/bin:$PATH \
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    NO_COLOR=1 \
    QS_NO_RELOAD_POPUP=1 \
    QS_DISABLE_FILE_WATCHER=1

WORKDIR /src
