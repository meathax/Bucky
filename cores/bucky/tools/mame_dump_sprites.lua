local out = assert(io.open("D:/Arcade/AI/aCORES/Bucky/.workbench/mame/sprite-dump.log", "w"))
local function w(s) out:write(s .. "\n"); out:flush() end
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local coin, start
local frame = 0
local function find_field(namesub)
  for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do
      if name:find(namesub, 1, true) then return field end
    end
  end
end
local function setfield(field, value) if field then field:set_value(value) end end
local function pc()
  local ok, v = pcall(function() return cpu.state["PC"].value end)
  return ok and v or 0
end
local function dump_source(tag)
  w(string.format("DUMP %s frame=%d pc=%06X", tag, frame, pc()))
  for slot = 0, 255 do
    local base = 0x090000 + slot * 0x100
    local w0 = prog:read_u16(base)
    if (w0 & 0x8000) ~= 0 and (w0 & 0x00ff) ~= 0 then
      local words = {}
      for j = 0, 7 do words[#words+1] = string.format("%04X", prog:read_u16(base + j*2)) end
      w(string.format("SLOT %03d %s", slot, table.concat(words, ":")))
    end
  end
end
local function on_frame()
  frame = frame + 1
  if frame == 1 then
    coin = find_field("Coin 1")
    start = find_field("1 Player Start") or find_field("P1 Start")
  elseif frame == 470 then setfield(coin, 1)
  elseif frame == 490 then setfield(coin, 0)
  elseif frame == 510 then setfield(start, 1)
  elseif frame == 530 then setfield(start, 0)
  elseif frame == 511 then dump_source("POST_START")
  elseif frame == 520 then dump_source("GAMEPLAY520")
  elseif frame == 515 then dump_source("GAMEPLAY")
  elseif frame == 580 then dump_source("CARDS") end
  if frame >= 585 then
    setfield(coin, 0); setfield(start, 0); out:close(); manager.machine:exit()
  end
end
if emu.register_frame_done then emu.register_frame_done(on_frame)
elseif emu.register_frame then emu.register_frame(on_frame)
else error("MAME Lua frame callback API unavailable") end
