"""Shared pieces for the moarchy phone apps.

Vendored into each package at build time rather than shipped as its own pacman
package: the store reports what an app costs in packages and megabytes onto a
stock image, and a second package for two hundred lines of palette arithmetic is
a cost with nothing behind it. One source copy, many self-contained packages --
see packaging/release.sh.
"""

__version__ = "0.1.0"
