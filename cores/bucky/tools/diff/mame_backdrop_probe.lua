-- Read-only K054338 backdrop probe for the pinned Bucky gameplay journal.
-- The only machine mutations are the declared cabinet inputs below.
local cpu = assert(manager.machine.devices[":maincpu"])
local program = assert(cpu.spaces["program"])
local screen = assert(manager.machine.screens[":screen"])
local output_dir = assert(os.getenv("BUCKY_MAME_RUN_DIR"),
                          "BUCKY_MAME_RUN_DIR is required")
local stop_frame = tonumber(os.getenv("BUCKY_MAME_STOP_FRAME") or "2200")
local log = assert(io.open(output_dir .. "/backdrop.log", "w"))
local applied = assert(io.open(output_dir .. "/applied-inputs.jsonl", "w"))
local frame = 0
local input_seq = 0
local coin, start, button1, right
local bg_r, bg_g, bg_b = 0, 0, 0
local snapshot_budget = 0
local backdrop_tap

local function pc()
  local ok, value = pcall(function() return cpu.state["PC"].value end)
  return ok and value or 0
end

local function find_field(names)
  for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do
      for _, wanted in ipairs(names) do
        if name == wanted then return field, name end
      end
    end
  end
  return nil, nil
end

local function apply(field, field_name, value)
  assert(field, "missing MAME input field " .. field_name)
  field:set_value(value)
  input_seq = input_seq + 1
  applied:write(string.format(
    '{"seq":%d,"field":"%s","value":%d,"at":{"kind":"vblank_rise","domain":"screen","ordinal":%d,"reset_epoch":1}}\n',
    input_seq, field_name, value, frame))
  applied:flush()
end

backdrop_tap = program:install_write_tap(
  0x0ca000, 0x0ca003, "bucky_k054338_backdrop",
  function(offset, data, mask)
    local old_r, old_g, old_b = bg_r, bg_g, bg_b
    if offset == 0x0ca000 and (mask & 0x00ff) ~= 0 then
      bg_r = data & 0xff
    elseif offset == 0x0ca002 then
      if (mask & 0xff00) ~= 0 then bg_g = (data >> 8) & 0xff end
      if (mask & 0x00ff) ~= 0 then bg_b = data & 0xff end
    end
    if bg_r ~= old_r or bg_g ~= old_g or bg_b ~= old_b then
      log:write(string.format(
        "BACKDROP_WRITE frame=%d pc=%06X addr=%06X data=%04X mask=%04X rgb=%02X%02X%02X\n",
        frame, pc(), offset, data & 0xffff, mask & 0xffff,
        bg_r, bg_g, bg_b))
      log:flush()
      if frame >= 900 then snapshot_budget = 8 end
    end
  end)

emu.register_frame_done(function()
  frame = frame + 1
  backdrop_tap:reinstall()

  if frame == 1 then
    coin = assert((find_field({"Coin 1"})))
    start = assert((find_field({"1 Player Start", "P1 Start"})))
    button1 = assert((find_field({"P1 Button 1"})))
    right = assert((find_field({"P1 Joystick Right", "P1 Right", "P1 Joy Right"})))
    coin:set_value(0)
    start:set_value(0)
    button1:set_value(0)
    right:set_value(0)
  end

  if frame == 470 then apply(coin, "Coin 1", 1) end
  if frame == 490 then apply(coin, "Coin 1", 0) end
  if frame == 510 then apply(start, "1 Player Start", 1) end
  if frame == 530 then apply(start, "1 Player Start", 0) end
  if frame == 1200 then apply(right, "P1 Right", 1) end
  if frame >= 550 and frame <= 1400 and ((frame - 550) % 50) == 0 then
    apply(button1, "P1 Button 1", 1)
  elseif frame >= 551 and frame <= 1401 and ((frame - 551) % 50) == 0 then
    apply(button1, "P1 Button 1", 0)
  end
  if frame == 1401 then apply(right, "P1 Right", 0) end

  if snapshot_budget > 0 then
    local path = string.format("%s/frame-%04d-rgb-%02x%02x%02x.png",
                               output_dir, frame, bg_r, bg_g, bg_b)
    local error_text = screen:snapshot(path)
    log:write(string.format("SNAPSHOT frame=%d rgb=%02X%02X%02X path=%s error=%s\n",
                            frame, bg_r, bg_g, bg_b, path,
                            tostring(error_text)))
    log:flush()
    snapshot_budget = snapshot_budget - 1
  end

  if frame >= stop_frame then
    log:write(string.format("DONE frame=%d pc=%06X inputs=%d rgb=%02X%02X%02X\n",
                            frame, pc(), input_seq, bg_r, bg_g, bg_b))
    log:close()
    applied:close()
    manager.machine:exit()
  end
end, "bucky_backdrop_probe")
