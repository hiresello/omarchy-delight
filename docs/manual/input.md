# Universal Control

Use this computer's keyboard and mouse on a neighbouring Mac, Windows or Linux
machine, or control this computer from theirs.

```bash
delight input install
delight input enable --role share     # this keyboard drives the other machine (Deskflow)
delight input enable --role receive   # the other machine drives this one (Lan Mouse)
```

Arrange screens in the module's panel from the Control Center. Move the
pointer off the configured edge to cross over; typing and the text clipboard
follow.

- **Release a stuck capture:** `SUPER + CTRL + ALT + ESCAPE` (Deskflow), or
  `Ctrl + Shift + Super + Alt` on the other machine (Lan Mouse).
- SUPER combinations sent from the other machine may not trigger Omarchy's
  shortcuts.

Setting up the Mac or Windows side:
[modules/input/README.md](../../modules/input/README.md).
