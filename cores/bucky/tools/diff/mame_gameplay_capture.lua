-- Deterministic Bucky parent capture through the first live-combat scene.
-- The only machine mutations are the declared cabinet input journal entries.
local cpu = assert(manager.machine.devices[":maincpu"])
local program = assert(cpu.spaces["program"])
local screen = assert(manager.machine.screens[":screen"])
local output_dir = assert(os.getenv("BUCKY_MAME_RUN_DIR"),
                          "BUCKY_MAME_RUN_DIR is required")
local stop_frame = tonumber(os.getenv("BUCKY_MAME_STOP_FRAME") or "1401")
local object_dump_frame = tonumber(os.getenv("BUCKY_MAME_OBJ_DUMP_FRAME") or "-1")
local full_object_dump_frame = tonumber(os.getenv("BUCKY_MAME_OBJ_FULL_DUMP_FRAME") or "-1")
local watch_object = os.getenv("BUCKY_MAME_OBJ_WATCH") == "1"
local watch_player = os.getenv("BUCKY_MAME_PLAYER_WATCH") == "1"
local trace_producer = os.getenv("BUCKY_MAME_PRODUCER_TRACE") == "1"
local log = assert(io.open(output_dir .. "/mame-gameplay.log", "w"))
local applied = assert(io.open(output_dir .. "/applied-inputs.jsonl", "w"))
local object_watch = watch_object and assert(io.open(output_dir .. "/object-watch.log", "w")) or nil
local player_watch = watch_player and assert(io.open(output_dir .. "/player-watch.log", "w")) or nil
local frame = 0
local input_seq = 0
local coin, start, button1, right
local watch_addresses = {0x091420, 0x091424, 0x091426, 0x09142c,
                         0x093b7c, 0x093b7e}
local watch_previous = {}
local object_write_tap
local object_read_tap
local player_write_tap
local player_read_tap
local player_input_tap
local producer_trace = trace_producer and assert(io.open(output_dir .. "/eeprom-workram.raw.jsonl", "w")) or nil
local producer_taps = {}
local producer_seq = 0
local watch_address_set = {}
for _, address in ipairs(watch_addresses) do watch_address_set[address] = true end

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

local function pc()
  local ok, value = pcall(function() return cpu.state["PC"].value end)
  return ok and value or 0
end

local function trace_access(rw, offset, data, mask)
  local byte_enable = ((mask & 0x00ff) ~= 0 and 1 or 0) |
                      ((mask & 0xff00) ~= 0 and 2 or 0)
  local normalized_data = data & mask & 0xffff
  producer_trace:write(string.format(
    '{"domain":"eeprom_workram","seq":%d,"event":"bus","phase":"completed","rw":"%s","address":%d,"data":%d,"byte_enable":%d,"width_bits":16,"pc":%d,"frame":%d,"reset_epoch":1}\n',
    producer_seq, rw, offset, normalized_data, byte_enable, pc(), frame))
  producer_trace:flush()
  producer_seq = producer_seq + 1
end

if trace_producer then
  local windows = {
    {0x080050, 0x080069, "workram_source"},
    {0x080940, 0x08094f, "workram_consumer"},
    {0x08f000, 0x08f006, "eeprom_shadow"}
  }
  for _, window in ipairs(windows) do
    producer_taps[#producer_taps + 1] = program:install_read_tap(
      window[1], window[2], window[3] .. "_read",
      function(offset, data, mask) trace_access("R", offset, data, mask) end)
    producer_taps[#producer_taps + 1] = program:install_write_tap(
      window[1], window[2], window[3] .. "_write",
      function(offset, data, mask) trace_access("W", offset, data, mask) end)
  end
end

if watch_player then
  player_write_tap = program:install_write_tap(
    0x080940, 0x08094f, "bucky_player_state",
    function(offset, data, mask)
      player_watch:write(string.format(
        "PLAYER_WRITE frame=%d pc=%06X addr=%06X data=%04X mask=%04X\n",
        frame, pc(), offset, data & 0xffff, mask & 0xffff))
      player_watch:flush()
    end)
  player_read_tap = program:install_read_tap(
    0x080940, 0x08094f, "bucky_player_state_reads",
    function(offset, data, mask)
      player_watch:write(string.format(
        "PLAYER_READ frame=%d pc=%06X addr=%06X data=%04X mask=%04X\n",
        frame, pc(), offset, data & 0xffff, mask & 0xffff))
      player_watch:flush()
    end)
  player_input_tap = program:install_read_tap(
    0x0da000, 0x0da001, "bucky_player_input_reads",
    function(offset, data, mask)
      if frame >= 500 then
        player_watch:write(string.format(
          "PLAYER_INPUT frame=%d pc=%06X addr=%06X data=%04X mask=%04X\n",
          frame, pc(), offset, data & 0xffff, mask & 0xffff))
        player_watch:flush()
      end
    end)
end

if object_watch then
  object_write_tap = program:install_write_tap(
    0x091400, 0x0914ff, "bucky_object_slot_14",
    function(offset, data, mask)
      object_watch:write(string.format(
        "OBJECT_WRITE frame=%d pc=%06X addr=%06X data=%04X mask=%04X\n",
        frame, pc(), offset, data & 0xffff, mask & 0xffff))
      object_watch:flush()
    end)
  object_read_tap = program:install_read_tap(
    0x091400, 0x0914ff, "bucky_object_slot_14_reads",
    function(offset, data, mask)
      if watch_address_set[offset] then
        object_watch:write(string.format(
          "OBJECT_READ frame=%d pc=%06X addr=%06X data=%04X mask=%04X\n",
          frame, pc(), offset, data & 0xffff, mask & 0xffff))
        object_watch:flush()
      end
    end)
end

local function apply(field, field_name, value)
  assert(field, "missing MAME input field " .. field_name)
  field:set_value(value)
  input_seq = input_seq + 1
  applied:write(string.format(
    '{"seq":%d,"field":"%s","value":%d,"at":{"kind":"vblank_rise","domain":"screen","ordinal":%d,"reset_epoch":1}}\n',
    input_seq, field_name, value, frame))
  applied:flush()
  log:write(string.format("INPUT frame=%d field=%s value=%d pc=%06X\n",
                          frame, field_name, value, pc()))
  log:flush()
end

local function snapshot(tag)
  local path = string.format("%s/frame-%d.png", output_dir, frame)
  local error_text = screen:snapshot(path)
  log:write(string.format("SNAPSHOT tag=%s frame=%d pc=%06X path=%s error=%s\n",
                          tag, frame, pc(), path, tostring(error_text)))
  log:flush()
end

local function dump_object_source()
  local path = string.format("%s/object-source-%d.log", output_dir, frame)
  local object_log = assert(io.open(path, "w"))
  object_log:write(string.format("OBJECT_SOURCE frame=%d pc=%06X\n", frame, pc()))
  for slot = 0, 255 do
    local base = 0x090000 + slot * 0x100
    local words = {}
    local nonzero = false
    for word = 0, 7 do
      local value = program:read_u16(base + word * 2) & 0xffff
      words[#words + 1] = string.format("%04X", value)
      nonzero = nonzero or value ~= 0
    end
    if nonzero then
      object_log:write(string.format("SLOT %03d %s\n", slot,
                                     table.concat(words, ":")))
    end
  end
  object_log:close()
  log:write(string.format("OBJECT_SOURCE frame=%d path=%s\n", frame, path))
  log:flush()
end

local function dump_full_object_source()
  local path = string.format("%s/object-full-%d.log", output_dir, frame)
  local object_log = assert(io.open(path, "w"))
  object_log:write(string.format("OBJECT_FULL frame=%d pc=%06X\n", frame, pc()))
  for word = 0, 32767 do
    local value = program:read_u16(0x090000 + word * 2) & 0xffff
    if value ~= 0 then
      object_log:write(string.format("%06X %04X\n", 0x090000 + word * 2, value))
    end
  end
  object_log:close()
  log:write(string.format("OBJECT_FULL frame=%d path=%s\n", frame, path))
  log:flush()
end

emu.register_frame_done(function()
  frame = frame + 1
  if trace_producer then
    for _, tap in ipairs(producer_taps) do tap:reinstall() end
  end
  if object_watch then
    -- Pass-through handlers may be displaced when MAME rebuilds an address
    -- map.  Reinstalling is idempotent and keeps the exact access evidence
    -- alive through reset and protection/DMA setup.
    object_write_tap:reinstall()
    object_read_tap:reinstall()
  end
  if watch_player then
    player_write_tap:reinstall()
    player_read_tap:reinstall()
    player_input_tap:reinstall()
  end
  if frame == 1 then
    coin = assert((find_field({"Coin 1"})))
    start = assert((find_field({"1 Player Start", "P1 Start"})))
    button1 = assert((find_field({"P1 Button 1"})))
    right = assert((find_field({"P1 Joystick Right", "P1 Right", "P1 Joy Right"})))
    coin:set_value(0)
    start:set_value(0)
    button1:set_value(0)
    right:set_value(0)
    log:write("READY frame=1\n")
    log:flush()
  end

  if frame == 470 then apply(coin, "Coin 1", 1) end
  if frame == 490 then apply(coin, "Coin 1", 0) end
  if frame == 510 then apply(start, "1 Player Start", 1) end
  if frame == 530 then apply(start, "1 Player Start", 0) end

  if frame == 1200 then apply(right, "P1 Right", 1) end

  if frame >= 550 and frame <= stop_frame and ((frame - 550) % 50) == 0 then
    apply(button1, "P1 Button 1", 1)
  elseif frame >= 551 and frame <= stop_frame and ((frame - 551) % 50) == 0 then
    apply(button1, "P1 Button 1", 0)
  end

  if frame == 580 or (frame >= 600 and frame <= 1400 and (frame % 100) == 0) then
    snapshot(frame == 1400 and "live-combat" or "progress")
  end
  if frame == object_dump_frame then dump_object_source() end
  if frame == full_object_dump_frame then dump_full_object_source() end
  if object_watch then
    for _, address in ipairs(watch_addresses) do
      local value = program:read_u16(address) & 0xffff
      if watch_previous[address] == nil or watch_previous[address] ~= value then
        object_watch:write(string.format("OBJECT_WATCH frame=%d pc=%06X addr=%06X data=%04X\n",
                                         frame, pc(), address, value))
        object_watch:flush()
        watch_previous[address] = value
      end
    end
  end
  if watch_player and frame >= 460 then
    player_watch:write(string.format(
      "PLAYER_WATCH frame=%d pc=%06X b45=%02X b47=%02X\n",
      frame, pc(), program:read_u8(0x080945), program:read_u8(0x080947)))
    player_watch:flush()
  end
  if frame == 1401 then apply(right, "P1 Right", 0) end

  if frame >= stop_frame then
    log:write(string.format("DONE frame=%d pc=%06X inputs=%d\n",
                            frame, pc(), input_seq))
    log:flush()
    applied:flush()
    log:close()
    applied:close()
    if object_watch then object_watch:close() end
    if watch_player then player_watch:close() end
    if trace_producer then producer_trace:close() end
    manager.machine:exit()
  end
end, "bucky_gameplay_capture")
