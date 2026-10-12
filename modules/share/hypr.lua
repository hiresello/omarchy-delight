-- Delight share sheet. SUPER+S, SUPER+SHIFT+S and SUPER+CTRL+S are taken by
-- Omarchy (Share menu, scratchpad uses SUPER+ALT+S), so the sheet sits on
-- SUPER + SHIFT + CTRL + S. Bare strings in o.bind are run via hl.dsp.exec_cmd.
o.bind("SUPER + SHIFT + CTRL + S", "Delight share sheet", os.getenv("HOME") .. "/.local/bin/delight share sheet")
