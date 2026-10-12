-- Omarchy Delight: sidecar. Loaded by ~/.config/omarchy-delight/hypr.lua.

local state = os.getenv("HOME") .. "/.local/state/omarchy-delight/sidecar"
local runtime = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-delight/sidecar"

-- Re-apply the tablet display's monitor rule after `hyprctl reload` while the
-- sidecar is running (the file only exists between start and stop).
pcall(dofile, runtime .. "/monitor.lua")

-- Optional toggle hotkey: delight sidecar set hotkey "SUPER + CTRL + ALT + T"
local f = io.open(state .. "/hotkey", "r")
if f then
  local keys = f:read("*l")
  f:close()
  if keys and keys ~= "" then
    o.bind(keys, "Toggle tablet display", "delight sidecar toggle")
  end
end
