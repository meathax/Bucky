-- Bucky O'Hare GX173 bounded MAME completed-access trace.
-- Device IDs are shared with the Verilator bind-side classifier.
-- Numeric fields follow mister-bus-jsonl-v1.

local OUTPUT = "mame-trace.jsonl"
local MAX_EVENTS = 100000

local CPU_SPACES = {
    { tag = ":maincpu", cpu = 0, bytes = 2,
      first = 0x000000, last = 0xffffff },
    -- { tag = ":subcpu", cpu = 1, bytes = 2,
    --   first = 0x000000, last = 0xffffff },
}

-- Use stable numeric device IDs shared with the HDL trace.
local RANGES = {
    { first = 0x000000, last = 0x07ffff, device = 0  }, -- 68000 program ROM
    { first = 0x080000, last = 0x08ffff, device = 1  }, -- work RAM
    { first = 0x090000, last = 0x09ffff, device = 2  }, -- sprite RAM
    { first = 0x0a0000, last = 0x0affff, device = 3  }, -- extra RAM
    { first = 0x0c0000, last = 0x0c003f, device = 4  }, -- K056832
    { first = 0x0c2000, last = 0x0c2007, device = 5  }, -- K053246 write
    { first = 0x0c4000, last = 0x0c4001, device = 5  }, -- K053246 read
    { first = 0x0ca000, last = 0x0ca01f, device = 6  }, -- K054338
    { first = 0x0cc000, last = 0x0cc01f, device = 7  }, -- K053251
    { first = 0x0ce000, last = 0x0ce01f, device = 8  }, -- K053990
    { first = 0x0d0000, last = 0x0d001f, device = 9  }, -- K053252
    { first = 0x0d2000, last = 0x0d203f, device = 10 }, -- K054000
    { first = 0x0d4000, last = 0x0d4001, device = 11 }, -- sound IRQ
    { first = 0x0d6000, last = 0x0d601f, device = 12 }, -- K054321
    { first = 0x0d8000, last = 0x0d8007, device = 4  }, -- K056832 VSCCS
    { first = 0x0da000, last = 0x0dc003, device = 13 }, -- controls/DIPs
    { first = 0x0de000, last = 0x0de001, device = 14 }, -- control2/EEPROM
    { first = 0x180000, last = 0x183fff, device = 15 }, -- tile VRAM + mirror
    { first = 0x184000, last = 0x187fff, device = 16 }, -- extra tile RAM
    { first = 0x190000, last = 0x191fff, device = 17 }, -- tile ROM readback
    { first = 0x1b0000, last = 0x1b3fff, device = 18 }, -- palette RAM
    { first = 0x200000, last = 0x23ffff, device = 19 }, -- data ROM
}

local machine = manager.machine
local output = assert(io.open(OUTPUT, "w"))
local taps = {}
local sequence = 0

local function device_for(address)
    for _, range in ipairs(RANGES) do
        if address >= range.first and address <= range.last then
            return range.device
        end
    end
    return -1
end

local function current_pc(device)
    local entry = device.state["CURPC"] or device.state["PC"] or
                  device.state["GENPC"]
    return entry and entry.value or 0
end

local function normalized_lanes(mask, byte_count)
    local lanes = 0
    for lane = 0, byte_count - 1 do
        if (mask & (0xff << (lane * 8))) ~= 0 then
            lanes = lanes | (1 << lane)
        end
    end
    return lanes
end

local function normalized_data(data, lanes, byte_count)
    local result = 0
    for lane = 0, byte_count - 1 do
        if (lanes & (1 << lane)) ~= 0 then
            result = result | (data & (0xff << (lane * 8)))
        end
    end
    return result
end

local function emit(cpu_info, device, rw, address, data, mask)
    if sequence >= MAX_EVENTS then return end
    local lanes = normalized_lanes(mask, cpu_info.bytes)
    local value = normalized_data(data, lanes, cpu_info.bytes)
    output:write(string.format(
        '{"seq":%d,"cpu":%d,"event":"bus","pc":%d,"rw":"%s",' ..
        '"address":%d,"data":%d,"lanes":%d,"device":%d}\n',
        sequence, cpu_info.cpu, current_pc(device), rw, address, value,
        lanes, device_for(address)))
    sequence = sequence + 1
end

for _, cpu_info in ipairs(CPU_SPACES) do
    local device = machine.devices[cpu_info.tag]
    assert(device, "missing CPU device " .. cpu_info.tag)
    local space = assert(device.spaces["program"],
                         "missing program space " .. cpu_info.tag)
    taps[#taps + 1] = space:install_read_tap(
        cpu_info.first, cpu_info.last, "mister_trace_read_" .. cpu_info.cpu,
        function(address, data, mask)
            emit(cpu_info, device, "r", address, data, mask)
            return data
        end)
    taps[#taps + 1] = space:install_write_tap(
        cpu_info.first, cpu_info.last, "mister_trace_write_" .. cpu_info.cpu,
        function(address, data, mask)
            emit(cpu_info, device, "w", address, data, mask)
            -- A tap must be observational.  Returning the original value is
            -- required by MAME's tap API; omitting it changes the emulated
            -- write and can send the traced machine down a false path.
            return data
        end)
end

emu.register_frame_done(function()
    output:flush()
end, "frame")
