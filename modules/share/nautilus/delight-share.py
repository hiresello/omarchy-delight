#!/usr/bin/env python3
"""Nautilus "Share…" context-menu item that opens the Delight share sheet.

Installed to ~/.local/share/nautilus-python/extensions/delight-share.py.
Lives next to Omarchy's localsend.py without colliding (distinct item name).
"""

import os

import gi

gi.require_version("Nautilus", "4.1")
from gi.repository import GObject, Gio, Nautilus

DELIGHT_BIN = os.path.expanduser("~/.local/bin/delight")


class DelightShareProvider(GObject.GObject, Nautilus.MenuProvider):
    def _share(self, menu, files):
        paths = [f.get_location().get_path() for f in files]
        paths = [p for p in paths if p]
        if not paths:
            return
        Gio.Subprocess.new([DELIGHT_BIN, "share", "sheet", *paths],
                           Gio.SubprocessFlags.NONE)

    def get_file_items(self, files):
        if not files or not os.path.exists(DELIGHT_BIN):
            return []
        item = Nautilus.MenuItem(
            name="DelightShare::share",
            label="Share…",
            tip="Share the selected files to a nearby device",
        )
        item.connect("activate", self._share, files)
        return [item]
