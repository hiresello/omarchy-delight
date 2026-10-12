-- Universal Control (omarchy-delight input): force-release a captured keyboard/mouse.
-- Lan Mouse uses its own release chord instead: Ctrl+Shift+Super+Alt.
if hl.dsp.release_input_capture then
  o.bind("SUPER + CTRL + ALT + ESCAPE", "Release shared keyboard and mouse", hl.dsp.release_input_capture(), { allow_input_capture = true })
end
