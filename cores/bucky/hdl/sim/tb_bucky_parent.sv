`timescale 1ns/1ps

// Parent-only integration bench for the generated JTFRAME SDRAM wrapper.
// ROM images are supplied with +MAIN_HEX=, +SND_HEX=, +TILE_HEX=,
// +SPRITE_HEX=, +PCM_HEX= and +NVRAM_HEX= at run time; no copyrighted ROM
// data belongs in the repository.
module tb_bucky_parent(
`ifdef BUCKY_EXTERNAL_CLOCK
    input  wire        clk,
    input  wire        clk24,
    input  wire        clk48,
    input  wire        clk96,
    output wire [31:0] sim_frames
`endif
);
    import "DPI-C" function void bucky_capture_init(input int width, input int height);
    import "DPI-C" function void bucky_capture_frame(input byte unsigned red[], input byte unsigned green[], input byte unsigned blue[], input int width, input int height);
    import "DPI-C" function void bucky_capture_poll();
    import "DPI-C" function void bucky_capture_done();
    localparam integer MAIN_WORDS = 1179648; // 0x240000 bytes / 2
    localparam integer SND_BYTES  = 262144;  // 0x40000 bytes
    localparam integer TILE_BYTES = 2097152; // K056832 region
    localparam integer SPR_BYTES  = 8388608; // K053246 region
    localparam integer PCM_BYTES  = 4194304; // GX173 K054539 sample region
    localparam [21:0]  PCM_OFFSET_WORD = 22'h020000;
    localparam [21:0]  RAM_OFFSET_WORD = 22'h140000;

`ifdef BUCKY_EXTERNAL_CLOCK
    reg rst=1, rst24=1, rst48=1, rst96=1;
`else
    reg rst=1, clk=0, rst24=1, clk24=0, rst48=1, clk48=0,
        rst96=1, clk96=0;
`endif
    reg pxl2_cen=0, pxl_cen=0;
    // JTFRAME presents cabinet inputs to the game as active-low signals.  A
    // released control is therefore all ones; zero is a pressed input.  The
    // old all-zero defaults held every coin/start/service input down and
    // could make a POST-only run look like a valid attract run.
    reg [3:0] cab_1p=4'hf, coin=4'hf;
    reg [6:0] joystick1=7'h7f, joystick2=7'h7f, joystick3=7'h7f, joystick4=7'h7f;
    reg [1:0] dial_x=0, dial_y=0;
    reg [15:0] joyana_l1=0, joyana_l2=0, joyana_l3=0, joyana_l4=0;
    reg [15:0] joyana_r1=0, joyana_r2=0, joyana_r3=0, joyana_r4=0;
    reg [5:0] snd_en=6'h3f;
    reg [7:0] snd_vol=8'hff;
    // Match MAME's parent defaults: stereo output, common coins, four
    // players.  The IN1 nibble is {SW1:4..1} = 1010 at dipsw[23:20].
    reg [31:0] status=0, dipsw=32'h00a0_0000;
    // JTFRAME's pause signal is active-high at the game boundary; keeping it
    // asserted is the normal running state (the framework does this in
    // simulation too).  A zero here silently held the 68000 in HALT.
    // JTFRAME's game_test signal is active-low in the cabinet interface but
    // defaults high (test switch open).  Keep the parent in normal attract
    // mode; driving zero here enters the service/test path and intentionally
    // waits in the EEPROM/IO diagnostics.
    reg dip_pause=1, dip_test=1, service=1, tilt=0;
    reg [1:0] dip_fxlevel=0;
    // JTFRAME's graphics enables are active-high.  Keep all four layers and
    // the sprite path enabled in the parent integration bench; zero disables
    // every renderer and can falsely look like a black-screen core.
    reg [3:0] gfx_en=4'hf;
    reg [7:0] debug_bus=0;

    reg [25:0] ioctl_addr=0;
    reg [7:0] ioctl_dout=0;
    reg ioctl_wr=0, ioctl_rom=0, ioctl_ram=0, ioctl_cart=0;
    reg [15:0] data_read=0;
    reg [3:0] ba_dst=0, ba_dok=0, ba_rdy=0, ba_ack=0;
    reg prog_rdy=0, prog_ack=0, prog_dst=0, prog_dok=0;

    wire [7:0] red, green, blue;
    wire LHBL, LVBL, HS, VS;
    wire dip_flip;
    wire [7:0] ioctl_din, debug_view;
    wire dwnld_busy;
    wire [21:0] ba0_addr, ba1_addr, ba2_addr, ba3_addr;
    wire [3:0] ba_rd, ba_wr;
    wire [15:0] ba0_din, ba1_din, ba2_din, ba3_din;
    wire [1:0] ba0_dsn, ba1_dsn, ba2_dsn, ba3_dsn;
    wire [15:0] prog_data;
    wire [21:0] prog_addr;
    wire [1:0] prog_ba, prog_mask;
    wire prog_we, prog_rd;
    wire signed [15:0] snd_left, snd_right;
    wire [5:0] snd_vu;
    wire snd_peak, sample;

    // Generated wrapper's internal memory requests are exposed through
    // hierarchical wires for this behavioral SDRAM model.
    wire [6:0] nvram_addr;
    wire [7:0] nvram_din, nvram_dout;
    wire nvram_we;
    // CPU-independent program-fetch visibility.  bucky_main maintains this
    // tracker under SIMULATION for both fx68k (production) and optional J68.
    wire [31:0] main_pc_debug = {8'd0,dut.u_game.u_main.pc_last,1'b0};
    wire [2:0] main_irq_debug =
        dut.u_game.u_main.IPLn == 3'b010 ? 3'd5 :
        dut.u_game.u_main.IPLn == 3'b011 ? 3'd4 : 3'd0;

    reg [15:0] main_mem [0:MAIN_WORDS-1];
    reg [7:0] snd_mem [0:SND_BYTES-1];
    // Packed MAME ROM regions.  Each word is {byte3,byte2,byte1,byte0};
    // this is the order expected by JTFRAME's 32-bit cache return bus.
    reg [31:0] tile_mem [0:(TILE_BYTES/4)-1];
    reg [31:0] sprite_mem [0:(SPR_BYTES/4)-1];
    reg [7:0] pcm_mem [0:PCM_BYTES-1];
    reg [15:0] ram_mem [0:17'h1ffff];
    reg [7:0] nvram_mem [0:127];
    reg [8*256-1:0] main_hex, snd_hex, tile_hex, sprite_hex, pcm_hex, nvram_hex;
    reg [8*256-1:0] result_file;
    integer result_fd;
    reg [8*256-1:0] milestone_file;
    integer milestone_fd;
    reg vram_dump_diag;
    integer vram_dump_frame;
    reg [8*256-1:0] vram_dump_file;
    integer vram_dump_fd;
    reg audio_only;
    reg audio_fm_only;
    // Optional final-mix capture for game-level MAME waveform comparison.
    // This is simulation-only observability: it does not touch the RTL audio
    // path or change the synthesizable parent design.
    reg [8*256-1:0] audio_path;
    integer audio_fd;
    integer audio_samples;
    integer audio_start_frame;
    integer audio_end_frame;
    reg audio_enabled;
    integer i;

    initial begin
        result_file = 0;
        result_fd = 0;
        milestone_file = 0;
        milestone_fd = 0;
        audio_path = 0;
        audio_fd = 0;
        audio_samples = 0;
        audio_start_frame = -1;
        audio_end_frame = -1;
        audio_enabled = 1'b0;
        audio_only = $test$plusargs("AUDIO_ONLY");
        audio_fm_only = $test$plusargs("AUDIO_FM_ONLY");
        if ($value$plusargs("AUDIO_FILE=%s", audio_path)) begin
            audio_fd = $fopen(audio_path, "w");
            if (audio_fd == 0) $fatal(1, "cannot open AUDIO_FILE=%0s", audio_path);
            audio_enabled = 1'b1;
            $fwrite(audio_fd, "# sample_rate=192000 channels=2 format=s16le\n");
        end
        void'($value$plusargs("AUDIO_START_FRAME=%d", audio_start_frame));
        void'($value$plusargs("AUDIO_END_FRAME=%d", audio_end_frame));
        vram_dump_diag = $value$plusargs("VRAM_DUMP_FRAME=%d", vram_dump_frame);
        void'($value$plusargs("VRAM_DUMP_FILE=%s", vram_dump_file));
        void'($value$plusargs("RESULT_FILE=%s", result_file));
        if ($value$plusargs("MILESTONE_FILE=%s", milestone_file)) begin
            milestone_fd = $fopen(milestone_file, "w");
            if (milestone_fd == 0) $fatal(1, "cannot open MILESTONE_FILE=%0s", milestone_file);
            $fwrite(milestone_fd, "LOCK set=bucky rom=parent mame=0.289\n");
            $fclose(milestone_fd);
            milestone_fd = 0;
        end
    end

    assign nvram_dout = nvram_mem[nvram_addr];

    // JTFRAME_SDRAM96 makes clk/clk96 the 96 MHz SDRAM/video domain.  The
    // separate clk48 remains the CPU/sound domain; pixel enables still derive
    // from the SDRAM clock and therefore preserve the 8 MHz raster cadence.
`ifndef BUCKY_EXTERNAL_CLOCK
    always #5  clk   = ~clk;
    always #20 clk24 = ~clk24;
    always #10 clk48 = ~clk48;
    always #5  clk96 = ~clk96;
`endif

    integer pxl_div;
    integer boot_probe;
    // Verbose internal bus/SDRAM probes are opt-in.  A normal parent run
    // should emit only ROM-load, frame, trace and PASS records; use +DIAG
    // when investigating a new divergence.
    reg diag;
    initial diag = $test$plusargs("DIAG");
    reg pixel_diag;
    initial pixel_diag = $test$plusargs("PIXDIAG");
    // Compact frame-boundary CPU/control snapshots are opt-in so long runs
    // remain quiet by default.  This is the acceptance probe for proving that
    // the parent leaves POST and reaches the attract/gameplay state.
    reg frame_state_diag;
    initial frame_state_diag = $test$plusargs("FRAMESTATE");
    reg pc_every_diag;
    initial pc_every_diag = $test$plusargs("PC_EVERY");
    reg cpu_detail_diag;
    initial cpu_detail_diag = $test$plusargs("CPUDETAIL");
    // Optional proof that the JTFRAME HPS/MRA DIP byte reaches the game port.
    // This is read-only instrumentation; it never alters the CPU bus or input
    // values.  +DIP_EXPECT=<nibble> makes the first observed IN1 read fail if
    // the selected switch nibble is not what the harness supplied.
    reg dip_diag;
    reg dip_read_d;
    reg [3:0] dip_expected;
    reg dip_expected_valid;
    integer dip_diag_count;
    initial begin
        dip_diag = $test$plusargs("DIP_DIAG");
        dip_read_d = 1'b0;
        dip_expected = 4'h0;
        dip_expected_valid = $value$plusargs("DIP_EXPECT=%h", dip_expected);
        dip_diag_count = 0;
    end

    // Reset-domain phase regression for JTFRAME_CLK48.  The generated
    // jtframe_rsthold registers the global hold independently in clk and
    // clk48; a domain must never observe release while its raw reset or its
    // locally sampled hold is still asserted.  The #1 sample is intentionally
    // after the nonblocking reset-domain update and is simulation-only.
    reg reset_phase_diag;
    integer reset_release_96;
    integer reset_release_48;
    initial begin
        reset_phase_diag = $test$plusargs("RESET_PHASE");
        reset_release_96 = -1;
        reset_release_48 = -1;
    end
    always @(posedge clk) begin
        if (reset_phase_diag) begin
            #1;
            if (!dut.rst_h && (dut.rst || dut.u_hold.hold))
                $fatal(1, "96MHz reset released before raw reset/hold");
            if (reset_release_96 < 0 && !dut.rst_h) begin
                reset_release_96 = $time;
                $display("[RESET_PHASE] rst_h release t=%0t", $time);
            end
        end
    end
    always @(posedge clk48) begin
        if (reset_phase_diag) begin
            #1;
            if (!dut.rst48_h && (dut.rst48 || dut.u_hold.hold48))
                $fatal(1, "48MHz reset released before raw reset/hold");
            if (reset_release_48 < 0 && !dut.rst48_h) begin
                reset_release_48 = $time;
                $display("[RESET_PHASE] rst48_h release t=%0t", $time);
            end
        end
    end
    always @(posedge clk48) begin
        if (dip_diag && dut.u_game.u_main.in1_cs && dut.u_game.u_main.RnW &&
            !dut.u_game.u_main.ASn && !dut.u_game.u_main.BUSn && !dip_read_d &&
            dip_diag_count < 8) begin
            $display("[DIP_DIAG] read=%0d dipsw=%08x in1=%04x nibble=%x",
                     dip_diag_count, dipsw, dut.u_game.u_main.port_in,
                     dut.u_game.u_main.port_in[7:4]);
            if (dip_expected_valid && dip_diag_count == 0 &&
                dut.u_game.u_main.port_in[7:4] !== dip_expected)
                $fatal(1, "JTFRAME DIP mismatch expected=%x actual=%x",
                       dip_expected, dut.u_game.u_main.port_in[7:4]);
            dip_diag_count = dip_diag_count + 1;
        end
        dip_read_d <= dut.u_game.u_main.in1_cs && dut.u_game.u_main.RnW &&
                      !dut.u_game.u_main.ASn && !dut.u_game.u_main.BUSn;
    end
    reg stop_on_error;
    initial stop_on_error = $test$plusargs("STOP_ON_ERROR");
    reg stop_on_exception;
    initial stop_on_exception = $test$plusargs("STOP_ON_EXCEPTION");
    reg ppm_diag;
    reg [8*256-1:0] ppm_path;
    integer ppm_frame_target;
    integer ppm_frame_id;
    integer ppm_index;
    integer ppm_fd;
    integer ppm_i;
    reg ppm_written;
    reg ppm_series_diag;
    string ppm_series_prefix;
    string ppm_series_file;
    integer ppm_series_start;
    integer ppm_series_end;
    integer ppm_series_period;
    reg capture_hs_l;
`ifdef BUCKY_FAST_SIM
    // Reduce host-side framebuffer copies during long exploratory replays.
    // An explicitly requested PPM target is still captured on its exact frame.
    localparam integer RGB_CAPTURE_DIV = 60;
`else
    localparam integer RGB_CAPTURE_DIV = 4;
`endif
    reg [7:0] ppm_r [0:384*224-1];
    reg [7:0] ppm_g [0:384*224-1];
    reg [7:0] ppm_b [0:384*224-1];
    initial begin
        ppm_diag = $value$plusargs("PPM_FILE=%s", ppm_path);
        ppm_frame_target = 0;
        void'($value$plusargs("PPM_FRAME=%d", ppm_frame_target));
        ppm_frame_id = 0;
        ppm_index = 0;
        ppm_written = 1'b0;
        ppm_series_diag = $value$plusargs("PPM_PREFIX=%s", ppm_series_prefix);
        ppm_series_start = 600;
        ppm_series_end = 1400;
        ppm_series_period = 100;
        capture_hs_l = 1'b0;
        void'($value$plusargs("PPM_START=%d", ppm_series_start));
        void'($value$plusargs("PPM_END=%d", ppm_series_end));
        void'($value$plusargs("PPM_PERIOD=%d", ppm_series_period));
        if (ppm_series_period < 1) ppm_series_period = 1;
        bucky_capture_init(384, 224);
    end

    // Non-GUI host-control polling point. The accepted headless backend never
    // mutates DUT state; it exists only for a future checkpoint control path.
    always @(posedge clk) begin
        capture_hs_l <= HS;
        if (HS && !capture_hs_l)
            bucky_capture_poll();
    end
    final begin
        if (audio_fd != 0) $fclose(audio_fd);
        bucky_capture_done();
    end

    // jtframe_rcmix runs at 192 kHz (48 MHz / FRACM=250).  Capture after the
    // clocked mixer update so each row contains the sample just presented on
    // the final stereo output.  CSV keeps the artifact portable across
    // the simulator, MAME and the local analysis scripts.
    always @(posedge sample) begin
        if (audio_enabled && sample &&
            (audio_start_frame < 0 || frames >= audio_start_frame) &&
            (audio_end_frame < 0 || frames <= audio_end_frame)) begin
            $fwrite(audio_fd, "%0d,%0d,%0d\n", audio_samples,
                    $signed(snd_left), $signed(snd_right));
            audio_samples = audio_samples + 1;
        end
    end
    integer active_pixels;
    integer nonzero_pixels;
    integer lyrf_nonzero;
    integer lyra_nonzero;
    integer lyrb_nonzero;
    integer lyrc_nonzero;
    integer sprite_nonzero;
    reg [31:0] frame_hash;
    reg lvbl_pix_d;
    initial begin
        active_pixels = 0;
        nonzero_pixels = 0;
        lyrf_nonzero = 0;
        lyra_nonzero = 0;
        lyrb_nonzero = 0;
        lyrc_nonzero = 0;
        sprite_nonzero = 0;
        frame_hash = 32'd0;
        lvbl_pix_d = 1'b1;
    end
    reg hold_prev;
    initial hold_prev = 1'b1;
    reg exception_asn_d;
    reg exception_handler_seen;
    reg unexpected_vector_seen;
    integer exception_fd;
    initial begin
        exception_asn_d = 1'b1;
        exception_handler_seen = 1'b0;
        unexpected_vector_seen = 1'b0;
        exception_fd = 0;
    end
    integer coin_frame, coin2_frame, start_frame, button1_frame, button3_frame;
    integer button1_period, button1_end, button3_period, button3_end;
    integer right_start, right_end, input_pulse;
    integer coin_pulse, start_pulse, button1_pulse, button3_pulse;
    // Exact verilator-record replay for the combined P1/P3 MAME port.  Each
    // 48-bit entry is {machine_frame_complete frame, P1_P3 value}; applying it
    // after this bench increments `frames` drives the delta before the next
    // equivalent frame boundary.  The table and cursor are model-resident so
    // VerilatedSave captures the complete replay state.
    reg [47:0] p1p3_replay [0:255];
    reg [8*256-1:0] p1p3_replay_hex;
    integer p1p3_replay_count, p1p3_replay_cursor;
    reg p1p3_replay_enabled;
    reg attract_seen;
    reg require_attract;
    reg start_accepted;
    reg gameplay_seen;
    reg inlevel_seen;
    reg require_gameplay;
    reg require_inlevel;
    reg require_no_exception;
    integer inlevel_frame_target;
    initial begin
        coin_frame = -1;
        coin2_frame = -1;
        start_frame = -1;
        button1_frame = -1;
        button3_frame = -1;
        button1_period = -1;
        button1_end = -1;
        button3_period = -1;
        button3_end = -1;
        right_start = -1;
        right_end = -1;
        input_pulse = 2;
        coin_pulse = -1;
        start_pulse = -1;
        button1_pulse = -1;
        button3_pulse = -1;
        p1p3_replay_hex = 0;
        p1p3_replay_count = 0;
        p1p3_replay_cursor = 0;
        p1p3_replay_enabled = $value$plusargs("P1P3_REPLAY_HEX=%s", p1p3_replay_hex);
        if (p1p3_replay_enabled) begin
            if (!$value$plusargs("P1P3_REPLAY_COUNT=%d", p1p3_replay_count) ||
                p1p3_replay_count < 1 || p1p3_replay_count > 256)
                $fatal(1, "P1P3 replay requires P1P3_REPLAY_COUNT=1..256");
            $readmemh(p1p3_replay_hex, p1p3_replay, 0, p1p3_replay_count-1);
        end
        attract_seen = 0;
        require_attract = $test$plusargs("REQUIRE_ATTRACT");
        start_accepted = 0;
        gameplay_seen = 0;
        inlevel_seen = 0;
        require_gameplay = $test$plusargs("REQUIRE_GAMEPLAY");
        require_inlevel = $test$plusargs("REQUIRE_INLEVEL");
        require_no_exception = $test$plusargs("REQUIRE_NO_EXCEPTION");
        inlevel_frame_target = 1400;
        void'($value$plusargs("COIN_FRAME=%d", coin_frame));
        void'($value$plusargs("COIN2_FRAME=%d", coin2_frame));
        void'($value$plusargs("START_FRAME=%d", start_frame));
        void'($value$plusargs("BUTTON1_FRAME=%d", button1_frame));
        void'($value$plusargs("BUTTON1_PERIOD=%d", button1_period));
        void'($value$plusargs("BUTTON1_END=%d", button1_end));
        void'($value$plusargs("BUTTON3_FRAME=%d", button3_frame));
        void'($value$plusargs("BUTTON3_PERIOD=%d", button3_period));
        void'($value$plusargs("BUTTON3_END=%d", button3_end));
        void'($value$plusargs("RIGHT_START=%d", right_start));
        void'($value$plusargs("RIGHT_END=%d", right_end));
        void'($value$plusargs("INPUT_PULSE=%d", input_pulse));
        if (input_pulse < 1) input_pulse = 1;
        void'($value$plusargs("COIN_PULSE=%d", coin_pulse));
        void'($value$plusargs("START_PULSE=%d", start_pulse));
        void'($value$plusargs("BUTTON1_PULSE=%d", button1_pulse));
        void'($value$plusargs("BUTTON3_PULSE=%d", button3_pulse));
        void'($value$plusargs("INLEVEL_FRAME=%d", inlevel_frame_target));
        if (coin_pulse < 1) coin_pulse = input_pulse;
        if (start_pulse < 1) start_pulse = input_pulse;
        if (button1_pulse < 1) button1_pulse = input_pulse;
        if (button3_pulse < 1) button3_pulse = input_pulse;
    end
    integer post_probe;
    initial post_probe = 0;
    integer sdram_sig_probe;
    initial sdram_sig_probe = 0;
    // Bucky maps every unexpected exception vector to $001d22 (BRA self),
    // whose post-fetch PC appears as $001d24.  J68 already latches the
    // offending address/opcode for an address error, so report those values
    // only when the vector fetch occurs.  Avoid a transaction-history array:
    // that observability alone made the full SoC model prohibitively slow.
    reg        exc_accept_d;
    reg        exc_dumped;
    reg        exception_diag;
    initial begin
        exc_accept_d = 1'b0;
        exc_dumped = 1'b0;
        exception_diag = $test$plusargs("EXCEPTION_DIAG");
    end
    wire exc_accepted = !dut.u_game.u_main.ASn &&
                        !dut.u_game.u_main.BUSn &&
                        !dut.u_game.u_main.dtac_mux;

`ifdef JTFRAME_J68
    always @(posedge clk) begin
        if (rst) begin
            exc_accept_d <= 1'b0;
            exc_dumped <= 1'b0;
        end else begin
            exc_accept_d <= exc_accepted;
            if (exception_diag && frames >= 250 &&
                exc_accepted && !exc_accept_d) begin
                // IRQ4/IRQ5 autovectors live at $70/$74 and are expected.
                // Any other post-reset vector read is the blocker path.
                if (!exc_dumped && dut.u_game.u_main.RnW &&
                    ({dut.u_game.u_main.A,1'b0} >= 24'h000008) &&
                    ({dut.u_game.u_main.A,1'b0} <= 24'h0000fc) &&
                    ({dut.u_game.u_main.A,1'b0} != 24'h000070) &&
                    ({dut.u_game.u_main.A,1'b0} != 24'h000074)) begin
                    exc_dumped <= 1'b1;
                    $display("[EXCEPTION] vector_addr=%06x vector_data=%04x pc=%08x last_fetch=%06x ssp=%08x usp=%08x sr=%04x ins=%04x err_addr=%08x err_ins=%04x err_cpu=%02x bus_addr=%08x",
                             {dut.u_game.u_main.A,1'b0}, dut.u_game.u_main.cpu_din,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.dbg_pc_reg,
                             {dut.u_game.u_main.pc_last,1'b0},
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.dbg_ssp_reg,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.dbg_usp_reg,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.U_mem_io.r_cpu_sr,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.U_mem_io.r_ins_word,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.U_mem_io.r_err_addr,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.U_mem_io.r_err_inst,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.U_mem_io.r_err_cpu,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.U_mem_io.r_address);
                    $finish;
                end
            end
        end
    end

`endif
`ifndef JTFRAME_J68
    // fx68k Line-F diagnostic.  Keep a compact ring of completed 68000 bus
    // cycles only in the late attract window, then dump it when vector $2c
    // is fetched.  The parent ROM contains $51c9 (DBRA) at $0056f4, so the
    // CPU's Ir/Irc/Ird values distinguish a bad ROM return/prefetch from a
    // wrong control-flow target without changing the synthesizable core.
    reg        fx_accept_d;
    integer    fx_ring_wr;
    integer    fx_ring_count;
    integer    fx_ring_i;
    reg [23:0] fx_ring_addr [0:31];
    reg [23:0] fx_ring_pc   [0:31];
    reg [15:0] fx_ring_data [0:31];
    reg [15:0] fx_ring_rom  [0:31];
    reg [ 2:0] fx_ring_fc   [0:31];
    reg [ 1:0] fx_ring_dsn  [0:31];
    reg        fx_ring_rnw  [0:31];
    reg        fx_ring_rok  [0:31];
    reg        fx_ring_dtack[0:31];
    initial begin
        fx_accept_d = 1'b0;
        fx_ring_wr = 0;
        fx_ring_count = 0;
    end
    always @(posedge clk) begin
        if (rst) begin
            fx_accept_d <= 1'b0;
            fx_ring_wr = 0;
            fx_ring_count = 0;
        end else begin
            fx_accept_d <= exc_accepted;
            if (exception_diag && frames >= 480 &&
                exc_accepted && !fx_accept_d) begin
                if (dut.u_game.u_main.RnW &&
                    ({dut.u_game.u_main.A,1'b0} == 24'h00002c)) begin
                    $display("[FX68K_LINEF] frame=%0d pc_last=%06x cpu_pc=%08x Ir=%04x Irc=%04x Ird=%04x A=%06x din=%04x",
                             frames, main_pc_debug,
                             dut.u_game.u_main.u_cpu.u_cpu.PC,
                             dut.u_game.u_main.u_cpu.u_cpu.Ir,
                             dut.u_game.u_main.u_cpu.u_cpu.Irc,
                             dut.u_game.u_main.u_cpu.u_cpu.Ird,
                             {dut.u_game.u_main.A,1'b0},
                             dut.u_game.u_main.cpu_din);
                    for (fx_ring_i = 0; fx_ring_i < fx_ring_count; fx_ring_i = fx_ring_i + 1) begin
                        $display("[FX68K_PREV] n=%0d pc=%06x A=%06x fc=%03b rnw=%0d dsn=%02b data=%04x rom=%04x rok=%0d dtack=%0d",
                                 fx_ring_i,
                                 fx_ring_pc[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_addr[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_fc[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_rnw[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_dsn[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_data[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_rom[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_rok[(fx_ring_wr-fx_ring_count+fx_ring_i)&31],
                                 fx_ring_dtack[(fx_ring_wr-fx_ring_count+fx_ring_i)&31]);
                    end
                end
                fx_ring_addr[fx_ring_wr] = {dut.u_game.u_main.A,1'b0};
                fx_ring_pc[fx_ring_wr] = main_pc_debug[23:0];
                fx_ring_fc[fx_ring_wr] = dut.u_game.u_main.FC;
                fx_ring_rnw[fx_ring_wr] = dut.u_game.u_main.RnW;
                fx_ring_dsn[fx_ring_wr] = {dut.u_game.u_main.UDSn,dut.u_game.u_main.LDSn};
                fx_ring_data[fx_ring_wr] = dut.u_game.u_main.RnW ?
                                           dut.u_game.u_main.cpu_din :
                                           dut.u_game.u_main.cpu_dout_68k;
                fx_ring_rom[fx_ring_wr] = dut.u_game.u_main.rom_data;
                fx_ring_rok[fx_ring_wr] = dut.u_game.u_main.rom_ok;
                fx_ring_dtack[fx_ring_wr] = dut.u_game.u_main.DTACKn;
                fx_ring_wr = (fx_ring_wr + 1) & 31;
                if (fx_ring_count < 32) fx_ring_count = fx_ring_count + 1;
            end
        end
    end
`endif
    // The parent maps most unexpected 68000 vectors to the same $001d22
    // loop.  Record the actual low-vector-table read that precedes it so a
    // bus/address/illegal/other exception cannot be confused with a normal
    // IRQ4/IRQ5 handler.  Keep this outside the optional J68 guard: fx68k is
    // the production and acceptance CPU.
    always @(posedge clk) begin
        if (rst) unexpected_vector_seen = 1'b0;
        if (!rst && frames >= 470 && exception_asn_d &&
            !dut.u_game.u_main.ASn && dut.u_game.u_main.RnW &&
            ({dut.u_game.u_main.A,1'b0} < 24'h000100)) begin
            if (({dut.u_game.u_main.A,1'b0} != 24'h000070) &&
                ({dut.u_game.u_main.A,1'b0} != 24'h000072) &&
                ({dut.u_game.u_main.A,1'b0} != 24'h000074) &&
                ({dut.u_game.u_main.A,1'b0} != 24'h000076) &&
                ({dut.u_game.u_main.A,1'b0} != 24'h000080) &&
                ({dut.u_game.u_main.A,1'b0} != 24'h000082))
                unexpected_vector_seen = 1'b1;
            if (milestone_file != 0) begin
                exception_fd = $fopen(milestone_file, "a");
                $fwrite(exception_fd,
                        "VECTOR_READ frame=%0d pc=%06x addr=%06x fc=%03b dsn=%02b\n",
                        frames, main_pc_debug, {dut.u_game.u_main.A,1'b0},
                        dut.u_game.u_main.FC,
                        {dut.u_game.u_main.UDSn,dut.u_game.u_main.LDSn});
                $fclose(exception_fd);
            end
        end
        if (!rst && frames >= 470 && !exception_handler_seen &&
            (main_pc_debug == 32'h00001d22 || main_pc_debug == 32'h00001d24)) begin
            exception_handler_seen = 1'b1;
            if (milestone_file != 0) begin
                exception_fd = $fopen(milestone_file, "a");
                $fwrite(exception_fd,
                        "EXCEPTION_HANDLER frame=%0d pc=%06x A=%06x fc=%03b rnw=%0d dsn=%02b\n",
                        frames, main_pc_debug, {dut.u_game.u_main.A,1'b0},
                        dut.u_game.u_main.FC, dut.u_game.u_main.RnW,
                        {dut.u_game.u_main.UDSn,dut.u_game.u_main.LDSn});
                $fclose(exception_fd);
            end
            if (stop_on_exception) $finish;
        end
        exception_asn_d <= dut.u_game.u_main.ASn;
    end
    // Return-valid, first-beat and data signals are synchronous-controller
    // inputs.  They must be visible for the whole cycle before the receiving
    // cache's clock edge; pulsing them with nonblocking assignments here
    // would shift every burst by one beat.
    always @* begin
        ba_rdy = 4'b0000;
        ba_dst = 4'b0000;
        ba_dok = 4'b0000;
        if (sdram_pending) begin
            // dok is the per-beat data-valid window; rdy terminates the
            // request only on the final beat (the real SDRAM controller does
            // not drop slot_sel after the first word of a burst).
            ba_rdy[pending_bank] = (pending_beat == pending_beats-1);
            ba_dst[pending_bank] = (pending_beat == 0);
            ba_dok[pending_bank] = 1'b1;
        end
    end

    always @(posedge clk) begin
        // $1d24 is the post-fetch PC of Bucky's generic $1d22 exception loop.
        // Stop only for a non-zero mailbox in this legacy probe; the dedicated
        // J68 exception probe above reports the actual vector and fault data.
        if (!rst && stop_on_error &&
            main_pc_debug == 32'h00001d24 &&
            ((ram_mem[17'h0817f] != 16'h0000) ||
             (ram_mem[17'h08180] != 16'h0000))) begin
            $display("[STOP_ON_ERROR] pc=1d24 mailbox=%04x/%04x",
                     ram_mem[17'h0817f], ram_mem[17'h08180]);
            $finish;
        end
        if (rst) begin
            pxl_div <= 0;
            pxl_cen <= 0;
            pxl2_cen <= 0;
        end else begin
            pxl_cen  <= (pxl_div == 5);
            pxl2_cen <= (pxl_div[1:0] == 2'd2);
            pxl_div  <= (pxl_div == 5) ? 0 : pxl_div + 1;
        end
    end

    initial begin
        for (i=0; i<131072; i=i+1) ram_mem[i] = 16'h0000;
        // The locked parent images cover every element of these large ROM
        // arrays.  Avoid millions of redundant zero assignments before
        // $readmemh; this is simulation-only setup and does not change the
        // loaded ROM contents or the synthesizable core.
        for (i=0; i<128; i=i+1) nvram_mem[i] = 8'hff;
        if ($value$plusargs("MAIN_HEX=%s", main_hex)) begin
            $display("[TB] loading %0s", main_hex);
            $readmemh(main_hex, main_mem);
        end
        if ($value$plusargs("SND_HEX=%s", snd_hex)) begin
            $display("[TB] loading %0s", snd_hex);
            $readmemh(snd_hex, snd_mem);
        end
        if ($value$plusargs("TILE_HEX=%s", tile_hex)) begin
            if (audio_only)
                $display("[TB] AUDIO_ONLY skipping tile ROM %0s", tile_hex);
            else begin
                $display("[TB] loading %0s", tile_hex);
                $readmemh(tile_hex, tile_mem);
            end
        end
        if ($value$plusargs("SPRITE_HEX=%s", sprite_hex)) begin
            if (audio_only)
                $display("[TB] AUDIO_ONLY skipping sprite ROM %0s", sprite_hex);
            else begin
                $display("[TB] loading %0s", sprite_hex);
                $readmemh(sprite_hex, sprite_mem);
            end
        end
        if ($value$plusargs("PCM_HEX=%s", pcm_hex)) begin
            if (audio_fm_only)
                $display("[TB] AUDIO_FM_ONLY skipping PCM ROM %0s", pcm_hex);
            else begin
                $display("[TB] loading %0s", pcm_hex);
                $readmemh(pcm_hex, pcm_mem);
            end
        end
        if ($value$plusargs("NVRAM_HEX=%s", nvram_hex)) begin
            $display("[TB] loading %0s", nvram_hex);
            $readmemh(nvram_hex, nvram_mem);
        end
        void'($value$plusargs("DIPSW=%h", dipsw));
`ifndef BUCKY_EXTERNAL_CLOCK
        repeat (10) @(posedge clk);
        rst=0; rst24=0; rst48=0; rst96=0;
`endif
    end

`ifdef BUCKY_EXTERNAL_CLOCK
    integer reset_edge_count = 0;
    always @(posedge clk) begin
        if (reset_edge_count < 10) begin
            reset_edge_count <= reset_edge_count + 1;
            if (reset_edge_count == 9) begin
                rst   <= 1'b0;
                rst24 <= 1'b0;
                rst48 <= 1'b0;
                rst96 <= 1'b0;
            end
        end
    end
`endif

    // Behavioral SDRAM model for the generated JTFRAME wrapper.  The wrapper
    // exposes only the shared bank requests (ba_rd/ba_wr plus the two-beat
    // data-return handshake); its internal main/sound request wires are not
    // top-level ports.  Bank 0 contains main ROM and writable RAM, bank 1
    // contains the Z80 ROM followed by PCM, and banks 2/3 are graphics.
    reg       sdram_pending=1'b0;
    reg [1:0] pending_bank=2'd0;
    reg       pending_write=1'b0;
    reg [21:0] pending_addr=22'd0;
    reg [15:0] pending_din=16'd0;
    reg [1:0]  pending_mask=2'b11;
    reg [2:0]  pending_beats=3'd0;
    reg [2:0]  pending_beat=3'd0;
    // A bank controller may launch the next slot request while the previous
    // four-beat burst is still returning.  The real SDRAM arbiter holds that
    // request; retain one pending request here instead of dropping the pulse.
    reg        queued_valid=1'b0;
    reg [1:0]  queued_bank=2'd0;
    reg        queued_write=1'b0;
    reg [21:0] queued_addr=22'd0;
    reg [15:0] queued_din=16'd0;
    reg [1:0]  queued_mask=2'b11;
    integer sdram_probe;
    initial sdram_probe = 0;
    integer sdram_read_probe;
    initial sdram_read_probe = 0;
    integer main_probe;
    initial main_probe = 0;

    task automatic read_sdram_word(input [1:0] bank, input [21:0] addr,
                                   output [15:0] value);
        integer byte_index;
        integer word_index;
        reg [16:0] ram_index;
        reg [20:0] main_index;
        begin
            value = 16'h0000;
            case (bank)
                2'd0: begin
                    if (addr >= RAM_OFFSET_WORD && (addr-RAM_OFFSET_WORD) < 22'h020000) begin
                        // The writable window is 0x140000..0x15ffff.  Its
                        // low 17 address bits are therefore the RAM index;
                        // keeping the narrowing explicit avoids a simulator
                        // width truncation in the behavioral model.
                        ram_index = addr[16:0] - RAM_OFFSET_WORD[16:0];
                        value = ram_mem[ram_index];
                    end else if (addr < 22'd1179648) begin
                        main_index = addr[20:0];
                        value = main_mem[main_index];
                    end
                end
                2'd1: begin
                    if (addr >= PCM_OFFSET_WORD) begin
                        byte_index = {10'd0,addr};
                        byte_index = (byte_index - 131072) * 2;
                        if (byte_index < PCM_BYTES-1)
                            value = {pcm_mem[byte_index+1],pcm_mem[byte_index]};
                    end else begin
                        byte_index = {10'd0,addr};
                        byte_index = byte_index * 2;
                        if (byte_index < SND_BYTES-1)
                            value = {snd_mem[byte_index+1],snd_mem[byte_index]};
                    end
                end
                2'd2: begin
                    byte_index = {10'd0,addr} * 2;
                    word_index = byte_index >> 2;
                    if (byte_index < TILE_BYTES)
                        value = byte_index[1] ? tile_mem[word_index][31:16] : tile_mem[word_index][15:0];
                end
                2'd3: begin
                    byte_index = {10'd0,addr} * 2;
                    word_index = byte_index >> 2;
                    if (byte_index < SPR_BYTES)
                        value = byte_index[1] ? sprite_mem[word_index][31:16] : sprite_mem[word_index][15:0];
                end
                default: value = 16'h0000;
            endcase
        end
    endtask

    task automatic write_sdram_word(input [21:0] addr, input [15:0] value,
                                    input [1:0] mask);
        reg [16:0] ram_index;
        begin
            if (addr >= RAM_OFFSET_WORD && (addr-RAM_OFFSET_WORD) < 22'h020000) begin
                ram_index = addr[16:0] - RAM_OFFSET_WORD[16:0];
                // The POST mailbox is a useful cross-check of the CPU-side
                // probe: it is the local SDRAM word corresponding to
                // 68000 address $080bfc.  Log both words without consuming
                // the bounded bus-probe budget used for the RAM pattern test.
                if ($test$plusargs("POST_DIAG") &&
                    (addr == 22'h14817f || addr == 22'h148180))
                    $display("[POSTSDRAM] addr=%06x index=%05x mask=%b data=%04x",
                             addr, ram_index, mask, value);
                if (!mask[0]) ram_mem[ram_index][7:0]  <= value[7:0];
                if (!mask[1]) ram_mem[ram_index][15:8] <= value[15:8];
            end
        end
    endtask

    reg [15:0] sdram_word;
    // The SDRAM contract presents data before the cycle in which rdy/dst is
    // sampled.  Keep the return bus combinational from the pending request;
    // assigning it with a nonblocking edge update would make every cache see
    // the preceding beat (and corrupt the reset vector).
    always @* begin
        sdram_word = 16'h0000;
        if (sdram_pending && !pending_write)
            read_sdram_word(pending_bank, pending_addr + {{19{1'b0}},pending_beat}, sdram_word);
        data_read = sdram_word;
    end

    // The generated JTFRAME bank controller raises ba_rd/ba_wr in a
    // nonblocking assignment at the positive edge.  Sample requests on the
    // opposite edge so the behavioral SDRAM model sees the complete pulse;
    // otherwise the erase transaction can be missed and hold_rst never
    // releases the game CPU.
    always @(negedge clk) begin
        if (diag && sdram_sig_probe < 48) begin
            $display("SDRAM_SIG n=%0d main_cs=%b req1=%b sel1=%b rd0=%b wr0=%b ack0=%b pend=%b q=%b addr0=%06x",
                sdram_sig_probe, dut.main_cs, dut.u_bank0.u_slot1.req,
                dut.u_bank0.u_ctrl.slot_sel[1], dut.ba_rd[0], dut.ba_wr[0],
                dut.ba_ack[0], sdram_pending, queued_valid, dut.ba0_addr);
            sdram_sig_probe = sdram_sig_probe + 1;
        end
        if (rst) boot_probe <= 0;
        else if (diag && boot_probe < 32) begin
            $display("BOOT_PROBE n=%0d rst=%b rst_h=%b hold=%b game_rst=%b halt=%b A=%06x AS=%b UDS=%b LDS=%b RnW=%b dtac=%b rom_cs=%b rom_ok=%b main_cs=%b main_ok=%b bus_busy=%b cpu_cen=%b cpu_cenb=%b req0=%b sel0=%b wr0=%b ack0=%b erase0=%b",
                boot_probe, dut.rst, dut.rst_h, dut.hold_rst, dut.u_game.rst,
                dut.u_game.u_main.HALTn,
                {dut.u_game.u_main.A,1'b0}, dut.u_game.u_main.ASn,
                dut.u_game.u_main.UDSn, dut.u_game.u_main.LDSn,
                dut.u_game.u_main.RnW, dut.u_game.u_main.dtac_mux,
                dut.u_game.u_main.rom_cs, dut.u_game.u_main.rom_ok,
                dut.main_cs,
                dut.main_ok, dut.u_game.u_main.bus_busy,
                dut.u_game.u_main.cpu_cen, dut.u_game.u_main.cpu_cenb,
                dut.u_bank0.u_slot0.req, dut.u_bank0.u_ctrl.slot_sel[0],
                dut.ba_wr[0], dut.ba_ack[0], dut.u_bank0.u_slot0.erase_bsy);
            boot_probe <= boot_probe + 1;
        end
        if (diag && !rst && dut.main_cs && main_probe < 80 && dut.main_addr < 21'h20) begin
            $display("MAIN_PROBE n=%0d addr=%06x data=%04x ok=%b cpu_din=%04x A=%06x cen=%b cenb=%b dtac=%b",
                main_probe, dut.main_addr, dut.main_data, dut.main_ok,
                dut.u_game.u_main.cpu_din, {dut.u_game.u_main.A,1'b0},
                dut.u_game.u_main.cpu_cen, dut.u_game.u_main.cpu_cenb,
                dut.u_game.u_main.dtac_mux);
            main_probe = main_probe + 1;
        end
        if (nvram_we) nvram_mem[nvram_addr] <= nvram_din;

        ba_ack <= 4'b0000;
        if (sdram_pending) begin
            if (diag && !pending_write && sdram_read_probe < 32)
                $display("SDRAM_RSP bank=%0d beat=%0d addr=%06x rnw=%b data=%04x dst=%b",
                         pending_bank, pending_beat, pending_addr,
                         !pending_write, sdram_word, pending_beat==0);
            if (pending_write) begin
                if (pending_beat == 0)
                    write_sdram_word(pending_addr, pending_din, pending_mask);
            end else begin
                // data_read is driven by the combinational return model above.
            end
            if (pending_beat == pending_beats-1) begin
                sdram_pending <= 1'b0;
                pending_beat <= 0;
            end else pending_beat <= pending_beat + 1'b1;
            // Keep a request asserted by a bank controller while this burst
            // drains.  Without this one-entry queue the first 68000 ROM
            // fetch can be lost immediately after bank-0 erase completes.
            if (!queued_valid) begin
                if (ba_rd[0] || ba_wr[0]) begin
                    queued_valid <= 1'b1; queued_bank <= 0;
                    queued_write <= ba_wr[0]; queued_addr <= ba0_addr;
                    queued_din <= ba0_din; queued_mask <= ba0_dsn;
                end else if (ba_rd[1] || ba_wr[1]) begin
                    queued_valid <= 1'b1; queued_bank <= 1;
                    queued_write <= ba_wr[1]; queued_addr <= ba1_addr;
                    queued_din <= ba1_din; queued_mask <= ba1_dsn;
                end else if (ba_rd[2] || ba_wr[2]) begin
                    queued_valid <= 1'b1; queued_bank <= 2;
                    queued_write <= ba_wr[2]; queued_addr <= ba2_addr;
                    queued_din <= ba2_din; queued_mask <= ba2_dsn;
                end else if (ba_rd[3] || ba_wr[3]) begin
                    queued_valid <= 1'b1; queued_bank <= 3;
                    queued_write <= ba_wr[3]; queued_addr <= ba3_addr;
                    queued_din <= ba3_din; queued_mask <= ba3_dsn;
                end
            end
        end else if (queued_valid) begin
            ba_ack[queued_bank] <= 1'b1;
            sdram_pending <= 1'b1;
            pending_bank <= queued_bank;
            pending_write <= queued_write;
            pending_addr <= queued_addr;
            pending_din <= queued_din;
            pending_mask <= queued_mask;
            pending_beats <= 4;
            pending_beat <= 0;
            queued_valid <= 1'b0;
        end else begin
            if (ba_rd[0] || ba_wr[0]) begin
                if (diag && ba_rd[0] && sdram_read_probe < 32) begin
                    $display("SDRAM_REQ bank=0 addr=%06x rd=%b wr=%b", ba0_addr, ba_rd[0], ba_wr[0]);
                    sdram_read_probe = sdram_read_probe + 1;
                end
                sdram_probe = sdram_probe + 1;
                ba_ack[0] <= 1'b1; sdram_pending <= 1'b1; pending_bank <= 0;
                pending_write <= ba_wr[0]; pending_addr <= ba0_addr;
                pending_din <= ba0_din; pending_mask <= ba0_dsn;
                pending_beats <= 4; pending_beat <= 0;
            end else if (ba_rd[1] || ba_wr[1]) begin
                if (diag && sdram_probe < 40) $display("SDRAM_REQ bank=1 addr=%06x rd=%b wr=%b", ba1_addr, ba_rd[1], ba_wr[1]);
                sdram_probe = sdram_probe + 1;
                ba_ack[1] <= 1'b1; sdram_pending <= 1'b1; pending_bank <= 1;
                pending_write <= ba_wr[1]; pending_addr <= ba1_addr;
                pending_din <= ba1_din; pending_mask <= ba1_dsn;
                pending_beats <= 4; pending_beat <= 0;
            end else if (ba_rd[2] || ba_wr[2]) begin
                if (diag && sdram_probe < 40) $display("SDRAM_REQ bank=2 addr=%06x rd=%b wr=%b", ba2_addr, ba_rd[2], ba_wr[2]);
                sdram_probe = sdram_probe + 1;
                ba_ack[2] <= 1'b1; sdram_pending <= 1'b1; pending_bank <= 2;
                pending_write <= ba_wr[2]; pending_addr <= ba2_addr;
                pending_din <= ba2_din; pending_mask <= ba2_dsn;
                pending_beats <= 4; pending_beat <= 0;
            end else if (ba_rd[3] || ba_wr[3]) begin
                if (diag && sdram_probe < 40) $display("SDRAM_REQ bank=3 addr=%06x rd=%b wr=%b", ba3_addr, ba_rd[3], ba_wr[3]);
                sdram_probe = sdram_probe + 1;
                ba_ack[3] <= 1'b1; sdram_pending <= 1'b1; pending_bank <= 3;
                pending_write <= ba_wr[3]; pending_addr <= ba3_addr;
                pending_din <= ba3_din; pending_mask <= ba3_dsn;
                pending_beats <= 4; pending_beat <= 0;
            end
        end
    end

    // A single RGB sample at VBlank is not evidence that the renderer is
    // producing a frame.  Count active/native pixels and a small rolling hash
    // in simulation so palette/tile/sprite bring-up has a measurable signal
    // without writing copyrighted image data to the repository.
    always @(posedge clk) begin
        if (rst) begin
            active_pixels <= 0;
            nonzero_pixels <= 0;
            lyrf_nonzero <= 0;
            lyra_nonzero <= 0;
            lyrb_nonzero <= 0;
            lyrc_nonzero <= 0;
            sprite_nonzero <= 0;
            frame_hash <= 32'd0;
            lvbl_pix_d <= 1'b1;
        end else begin
            // JTFRAME's L-prefixed blanking signals are low during blanking;
            // visible pixels therefore require both blanking signals high.
            if (pxl_cen && LHBL && LVBL) begin
                active_pixels <= active_pixels + 1;
                if (|(red | green | blue))
                    nonzero_pixels <= nonzero_pixels + 1;
                if (dut.u_game.u_video.lyrf_pxl[3:0] != 0)
                    lyrf_nonzero <= lyrf_nonzero + 1;
                if (dut.u_game.u_video.lyra_pxl[3:0] != 0)
                    lyra_nonzero <= lyra_nonzero + 1;
                if (dut.u_game.u_video.lyrb_pxl[3:0] != 0)
                    lyrb_nonzero <= lyrb_nonzero + 1;
                if (dut.u_game.u_video.lyrc_pxl[3:0] != 0)
                    lyrc_nonzero <= lyrc_nonzero + 1;
                if (dut.u_game.u_video.lyro_pxl[3:0] != 0)
                    sprite_nonzero <= sprite_nonzero + 1;
                frame_hash <= {frame_hash[28:0], frame_hash[31:29]} ^
                              {8'd0, red, green, blue};
                // Keep the RGB capture buffer only for periodic diagnostic frames
                // (every fourth native frame) and for an explicitly selected
                // PPM target.  Filling 86,016 array elements on every frame
                // made long gameplay replays dominated by diagnostics while
                // leaving the displayed/captured pixels unchanged.
                if ((ppm_frame_id % RGB_CAPTURE_DIV) == 0 ||
                    (ppm_diag && ppm_frame_id == ppm_frame_target) ||
                    (ppm_series_diag && ppm_frame_id >= ppm_series_start &&
                     ppm_frame_id <= ppm_series_end &&
                     ((ppm_frame_id - ppm_series_start) % ppm_series_period) == 0)) begin
                    if (ppm_index < 384*224) begin
                        ppm_r[ppm_index] <= red;
                        ppm_g[ppm_index] <= green;
                        ppm_b[ppm_index] <= blue;
                    end
                end
                ppm_index <= ppm_index + 1;
            end
            // The rising LVBL edge starts a new active frame.  Dump the
            // completed selected frame on the following blank edge, after the
            // final nonblocking pixel writes have committed.
            if (!LVBL && lvbl_pix_d) begin
                if (ppm_index >= 384*224 && ((ppm_frame_id % RGB_CAPTURE_DIV) == 0))
                    bucky_capture_frame(ppm_r, ppm_g, ppm_b, 384, 224);
                if (ppm_diag && ppm_frame_id == ppm_frame_target &&
                    ppm_index >= 384*224) begin
                    ppm_fd = $fopen(ppm_path, "wb");
                    if (ppm_fd == 0) $fatal(1, "cannot open PPM_FILE=%0s", ppm_path);
                    $fwrite(ppm_fd, "P6\n384 224\n255\n");
                    for (ppm_i = 0; ppm_i < 384*224; ppm_i = ppm_i + 1)
                        $fwrite(ppm_fd, "%c%c%c", ppm_r[ppm_i], ppm_g[ppm_i], ppm_b[ppm_i]);
                    $fclose(ppm_fd);
                    ppm_written <= 1'b1;
                    $display("[PPM] frame=%0d file=%0s", ppm_frame_id, ppm_path);
                end
                if (ppm_series_diag && ppm_frame_id >= ppm_series_start &&
                    ppm_frame_id <= ppm_series_end &&
                    ((ppm_frame_id - ppm_series_start) % ppm_series_period) == 0 &&
                    ppm_index >= 384*224) begin
                    ppm_series_file = $sformatf("%0s-frame%0d.ppm",
                                                ppm_series_prefix, ppm_frame_id);
                    ppm_fd = $fopen(ppm_series_file, "wb");
                    if (ppm_fd == 0)
                        $fatal(1, "cannot open series PPM %0s", ppm_series_file);
                    $fwrite(ppm_fd, "P6\n384 224\n255\n");
                    for (ppm_i = 0; ppm_i < 384*224; ppm_i = ppm_i + 1)
                        $fwrite(ppm_fd, "%c%c%c", ppm_r[ppm_i], ppm_g[ppm_i], ppm_b[ppm_i]);
                    $fclose(ppm_fd);
                    $display("[PPM_SERIES] frame=%0d file=%0s", ppm_frame_id, ppm_series_file);
                end
                ppm_frame_id <= ppm_frame_id + 1;
                ppm_index <= 0;
            end
            if (LVBL && !lvbl_pix_d) begin
                // Optional post-frame snapshot of the CPU-visible K056832
                // VRAM.  This is diagnostic only: the MAME script dumps the
                // corresponding 0x180000-0x183fff window, so comparing the
                // two arrays localizes missing fixed-layer tiles without
                // conflating renderer timing with CPU writes.
                if (vram_dump_diag && ppm_frame_id == vram_dump_frame) begin
                    vram_dump_fd = $fopen(vram_dump_file, "w");
                    if (vram_dump_fd == 0) $fatal(1, "cannot open VRAM_DUMP_FILE=%0s", vram_dump_file);
                    for (ppm_i = 0; ppm_i < 8192; ppm_i = ppm_i + 1)
                        $fdisplay(vram_dump_fd, "%04x", dut.u_game.u_video.u_scroll.u_vram.u_ram.mem[ppm_i]);
                    $fclose(vram_dump_fd);
                    $display("[VRAM_DUMP] frame=%0d file=%0s", ppm_frame_id, vram_dump_file);
                end
                if (frame_state_diag)
                    $display("[FRAMESTATE] pc=%08x A=%06x as=%b rnw=%b dtack=%b irq=%0d ctl2=%04x dma=%b objcha=%b rmrd=%b k38=%04x k251=%0d/%0d/%0d pal=%03x",
                             main_pc_debug,
                             {dut.u_game.u_main.A,1'b0},
                             dut.u_game.u_main.ASn, dut.u_game.u_main.RnW,
                             dut.u_game.u_main.dtac_mux,
                             main_irq_debug,
                             dut.u_game.u_main.cur_control2,
                             dut.u_game.u_video.dma_bsy,
                             dut.u_game.u_main.objcha_n, dut.u_game.u_main.rmrd,
                             dut.u_game.u_video.u_colmix.k38[15],
                             dut.u_game.u_video.u_colmix.pri_a,
                             dut.u_game.u_video.u_colmix.pri_b,
                             dut.u_game.u_video.u_colmix.pri_c,
                             dut.u_game.u_video.u_colmix.pal_addr);
`ifdef JTFRAME_J68
                if (cpu_detail_diag)
                    $display("[CPUDETAIL] pc=%08x sp=%0d ds=%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x sr=%04x",
                             main_pc_debug,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds_ptr,
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[0],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[1],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[2],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[3],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[4],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[5],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[6],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[7],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[8],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[9],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[10],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[11],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[12],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[13],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[14],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.r_ds[15],
                             dut.u_game.u_main.u_cpu.u_cpu.u_j68.U_mem_io.r_cpu_sr);
`else
                if (cpu_detail_diag)
                    $display("[CPUDETAIL] pc=%08x ir=%04x irc=%04x d=%08x/%08x/%08x/%08x/%08x/%08x/%08x/%08x a=%08x/%08x/%08x/%08x/%08x/%08x/%08x/%08x sr=%04x",
                             main_pc_debug,
                             dut.u_game.u_main.u_cpu.u_cpu.Ir,
                             dut.u_game.u_main.u_cpu.u_cpu.Irc,
                             dut.u_game.u_main.u_cpu.u_cpu.D0,
                             dut.u_game.u_main.u_cpu.u_cpu.D1,
                             dut.u_game.u_main.u_cpu.u_cpu.D2,
                             dut.u_game.u_main.u_cpu.u_cpu.D3,
                             dut.u_game.u_main.u_cpu.u_cpu.D4,
                             dut.u_game.u_main.u_cpu.u_cpu.D5,
                             dut.u_game.u_main.u_cpu.u_cpu.D6,
                             dut.u_game.u_main.u_cpu.u_cpu.D7,
                             dut.u_game.u_main.u_cpu.u_cpu.A0,
                             dut.u_game.u_main.u_cpu.u_cpu.A1,
                             dut.u_game.u_main.u_cpu.u_cpu.A2,
                             dut.u_game.u_main.u_cpu.u_cpu.A3,
                             dut.u_game.u_main.u_cpu.u_cpu.A4,
                             dut.u_game.u_main.u_cpu.u_cpu.A5,
                             dut.u_game.u_main.u_cpu.u_cpu.A6,
                             dut.u_game.u_main.u_cpu.u_cpu.A7,
                             dut.u_game.u_main.u_cpu.u_cpu.psw);
`endif
                if (pixel_diag)
                    // Keep the state snapshot at the frame boundary: this is
                    // simulation-only observability and does not alter RTL.
                    // It distinguishes renderer starvation from a color/
                    // priority control suppressing valid layer data.
                    $display("[PIX] active=%0d nonzero=%0d hash=%08x layers=%0d/%0d/%0d/%0d spr=%0d k38ctl=%04x disp/f=%b/%b pf/cs=%0d/%0d hs=%b fline=%03x pri=%0d/%0d/%0d coln=%b pal=%03x rgb=%06x k338=%06x/%02x dac=%06x blend=%b",
                             active_pixels, nonzero_pixels, frame_hash,
                             lyrf_nonzero, lyra_nonzero, lyrb_nonzero,
                             lyrc_nonzero, sprite_nonzero,
                             dut.u_game.u_video.u_colmix.k38[15],
                             dut.u_game.u_video.u_scroll.dispbank,
                             dut.u_game.u_video.u_scroll.fbank,
                             dut.u_game.u_video.u_scroll.pf_st,
                             dut.u_game.u_video.u_scroll.cs_st,
                             dut.u_game.u_video.u_scroll.hs_valid,
                             dut.u_game.u_video.u_scroll.fline,
                             dut.u_game.u_video.u_colmix.pri_a,
                             dut.u_game.u_video.u_colmix.pri_b,
                             dut.u_game.u_video.u_colmix.pri_c,
                             dut.u_game.u_video.u_colmix.k251_coln,
                             dut.u_game.u_video.u_colmix.pal_addr,
                             dut.u_game.u_video.u_colmix.bgr,
                             dut.u_game.u_video.u_colmix.k338_color,
                             dut.u_game.u_video.u_colmix.k338_brightness,
                             dut.u_game.u_video.u_colmix.k338_dac_bgr,
                             dut.u_game.u_video.u_colmix.do_blend);
                active_pixels <= 0;
                nonzero_pixels <= 0;
                lyrf_nonzero <= 0;
                lyra_nonzero <= 0;
                lyrb_nonzero <= 0;
                lyrc_nonzero <= 0;
                sprite_nonzero <= 0;
                frame_hash <= 32'd0;
            end
            lvbl_pix_d <= LVBL;
        end
    end

    // One-shot boundary diagnostic: if the 68000 remains idle after the
    // generated SDRAM erase releases reset, the parent bench is not yet a
    // valid CPU/ROM test even though video timing can still produce frames.
    always @(posedge clk) begin
        if (diag && hold_prev && !dut.hold_rst)
            $display("[TB] HOLD_RELEASE rst_h=%b game_rst=%b HALTn=%b A=%06x AS=%b main_cs=%b main_ok=%b bus_busy=%b",
                dut.rst_h, dut.u_game.rst, dut.u_game.u_main.HALTn,
                {dut.u_game.u_main.A,1'b0}, dut.u_game.u_main.ASn,
                dut.main_cs, dut.main_ok, dut.u_game.u_main.bus_busy);
        hold_prev <= dut.hold_rst;
        if (diag && !dut.rst_h && post_probe < 32) begin
            $display("POST_PROBE n=%0d rst_h=%b game_rst=%b HALTn=%b A=%06x AS=%b UDS=%b LDS=%b RnW=%b main_cs=%b main_ok=%b bus_busy=%b cpu_cen=%b cpu_cenb=%b req1=%b sel1=%b rd0=%b wr0=%b ack0=%b rdy0=%b dst0=%b dok0=%b addr0=%06x",
                post_probe, dut.rst_h, dut.u_game.rst,
                dut.u_game.u_main.HALTn, {dut.u_game.u_main.A,1'b0},
                dut.u_game.u_main.ASn, dut.u_game.u_main.UDSn,
                dut.u_game.u_main.LDSn, dut.u_game.u_main.RnW,
                dut.main_cs, dut.main_ok, dut.u_game.u_main.bus_busy,
                dut.u_game.u_main.cpu_cen, dut.u_game.u_main.cpu_cenb,
                dut.u_bank0.u_slot1.req, dut.u_bank0.u_ctrl.slot_sel[1],
                dut.ba_rd[0], dut.ba_wr[0], dut.ba_ack[0], dut.ba_rdy[0],
                dut.ba_dst[0], dut.ba_dok[0], dut.ba0_addr);
            post_probe = post_probe + 1;
        end
        // GAME_TICK is the stable MAME 0.289 gameplay milestone used by the
        // parent differential helper.  It is only an observation point; the
        // input pulses below remain the sole source of cabinet stimulus.
        // The same ROM address is also used by an early POST helper.  Require
        // the post-diagnostic frame window, and when a directed start was
        // supplied require that pulse to have completed, before accepting the
        // address as a gameplay tick.
        // The untainted MAME 0.289 parent run leaves POST at frame 425 and
        // executes $003644.  Observe that architectural event anywhere in
        // the frame rather than assuming equal frame-boundary PCs.
        if (!rst && !attract_seen && frames >= 400 &&
            main_pc_debug == 32'h00003644) begin
            attract_seen = 1;
            $display("[ATTRACT] pc=003644 frame=%0d mailbox=%04x/%04x",
                     frames, ram_mem[17'h0817f], ram_mem[17'h08180]);
            if (milestone_file != 0) begin
                milestone_fd = $fopen(milestone_file, "a");
                $fwrite(milestone_fd, "ATTRACT frame=%0d pc=003644 mailbox=%04x/%04x\n",
                        frames, ram_mem[17'h0817f], ram_mem[17'h08180]);
                $fclose(milestone_fd);
            end
        end
        // With a credit inserted after attract, MAME 0.289 accepts Start at
        // $0037e0 and then enters the game setup path at $009c06.  Require a
        // subsequent $005194 worker dispatch before calling the directed run
        // gameplay; keep $003a92 as an alternate path used by other internal
        // state transitions, but never accept it before the directed pulse.
        if (!rst && !start_accepted && start_frame >= 0 &&
            frames >= start_frame &&
            (main_pc_debug == 32'h000037e0 ||
             main_pc_debug == 32'h00009c06)) begin
            start_accepted = 1;
            if ($test$plusargs("GAMEPLAY_DIAG"))
                $display("[START_ACCEPTED] pc=%06x frame=%0d coin=%h start=%h",
                         main_pc_debug, frames, coin, cab_1p);
            if (milestone_file != 0) begin
                milestone_fd = $fopen(milestone_file, "a");
                $fwrite(milestone_fd, "START_ACCEPTED frame=%0d pc=%06x coin=%h start=%h\n",
                        frames, main_pc_debug, coin, cab_1p);
                $fclose(milestone_fd);
            end
        end
        if (!rst && !gameplay_seen && start_accepted &&
            (main_pc_debug == 32'h00005194 ||
             main_pc_debug == 32'h00003a92)) begin
            gameplay_seen = 1;
            if ($test$plusargs("GAMEPLAY_DIAG"))
                $display("[GAMEPLAY] pc=%06x frame=%0d coin=%h start=%h mailbox=%04x/%04x",
                         main_pc_debug, frames, coin, cab_1p,
                         ram_mem[17'h0817f], ram_mem[17'h08180]);
            if (milestone_file != 0) begin
                milestone_fd = $fopen(milestone_file, "a");
                $fwrite(milestone_fd, "GAMEPLAY frame=%0d pc=%06x coin=%h start=%h mailbox=%04x/%04x\n",
                        frames, main_pc_debug, coin, cab_1p,
                        ram_mem[17'h0817f], ram_mem[17'h08180]);
                $fclose(milestone_fd);
            end
        end
        // The worker dispatch above occurs hundreds of frames before control
        // is handed to the player.  Require a separately declared, visually
        // verified frame barrier for full gameplay acceptance.  Frame 1400 is
        // the pinned MAME 0.289 live-combat scene for this input journal; the
        // raw PPM comparison remains the pixel-accuracy verdict.
        if (!rst && !inlevel_seen && start_accepted && gameplay_seen &&
            frames >= inlevel_frame_target && inlevel_frame_target >= 1200) begin
            inlevel_seen = 1;
            $display("[INLEVEL] frame=%0d pc=%06x target=%0d",
                     frames, main_pc_debug, inlevel_frame_target);
            if (milestone_file != 0) begin
                milestone_fd = $fopen(milestone_file, "a");
                $fwrite(milestone_fd, "INLEVEL frame=%0d pc=%06x target=%0d\n",
                        frames, main_pc_debug, inlevel_frame_target);
                $fclose(milestone_fd);
            end
        end
    end

    jtbucky_game_sdram dut(.*);

    reg lvbl_d;
    integer frames, max_frames, max_cycles;
    integer pcm_deadline_misses;
    integer sprite_line_overruns;
`ifdef BUCKY_EXTERNAL_CLOCK
    assign sim_frames = frames;
`endif
    longint unsigned cycles, frame_cycle_limit;
    initial begin
        lvbl_d=1; frames=0; cycles=0; max_frames=3; max_cycles=0;
        pcm_deadline_misses=0; sprite_line_overruns=0;
        void'($value$plusargs("MAX_FRAMES=%d", max_frames));
        void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
        // Keep the frame-derived watchdog in 64-bit arithmetic.  A long
        // gameplay replay (3600 frames) otherwise overflows a 32-bit
        // integer at 3.6 billion clocks and aborts at the first 10,000-cycle
        // guard point before the board can reach the requested frame.
        frame_cycle_limit = max_frames;
        frame_cycle_limit = frame_cycle_limit * 1000000;
    end
`ifdef BUCKY_EXTERNAL_CLOCK
    always @(posedge clk) begin
`else
    always begin
            @(posedge clk);
`endif
            cycles = cycles + 1;
            if (dut.u_game.u_sound.k39_timeout) begin
                pcm_deadline_misses = pcm_deadline_misses + 1;
                if ($test$plusargs("SOUND_DIAG"))
                    $display("[PCM_DEADLINE] miss=%0d frame=%0d cycle=%0d",
                             pcm_deadline_misses, frames, cycles);
            end
            if (frames > 1 &&
                dut.u_game.u_video.u_obj.u_scan.u_scan.cen2 &&
                dut.u_game.u_video.u_obj.u_scan.u_scan.hs &&
                !dut.u_game.u_video.u_obj.u_scan.u_scan.hs_l &&
                dut.u_game.u_video.u_obj.u_scan.u_scan.vdump > 9'h10d &&
                dut.u_game.u_video.u_obj.u_scan.u_scan.vdump <= 9'h1f7 &&
                dut.u_game.u_video.u_obj.u_scan.u_scan.scan_obj != 0)
                sprite_line_overruns = sprite_line_overruns + 1;
            if (!LVBL && lvbl_d) begin
                frames = frames + 1;
                // Optional deterministic cabinet sequence.  Keep it disabled
                // by default so an attract-only run remains reproducible.
                // The value is the bench's callback-phase frame.  In this
                // parent integration the 68000 samples the port after the
                // falling-LVBL update, so the locked MAME schedule is passed
                // directly (coin=470, start=510, Button 1=550).  A +1 shift
                // was tested and missed the one-player start poll entirely.
                if (coin_frame >= 0 || coin2_frame >= 0) begin
                    if ((coin_frame >= 0 && frames >= coin_frame && frames < coin_frame + coin_pulse) ||
                        (coin2_frame >= 0 && frames >= coin2_frame && frames < coin2_frame + coin_pulse))
                        coin[0] = 1'b0;
                    else
                        coin[0] = 1'b1;
                end
                if (start_frame >= 0) begin
                    if (frames >= start_frame && frames < start_frame + start_pulse)
                        cab_1p[0] = 1'b0;
                    else
                        cab_1p[0] = 1'b1;
                end
                if (button1_frame >= 0) begin
                    if ((button1_period > 0 && button1_end >= button1_frame &&
                         frames >= button1_frame && frames <= button1_end &&
                        ((frames - button1_frame) % button1_period) < button1_pulse) ||
                        (button1_period <= 0 && frames >= button1_frame &&
                         frames < button1_frame + button1_pulse))
                        joystick1[4] = 1'b0;
                    else
                        joystick1[4] = 1'b1;
                end
                if (button3_frame >= 0) begin
                    if ((button3_period > 0 && button3_end >= button3_frame &&
                         frames >= button3_frame && frames <= button3_end &&
                        ((frames - button3_frame) % button3_period) < button3_pulse) ||
                        (button3_period <= 0 && frames >= button3_frame &&
                         frames < button3_frame + button3_pulse))
                        joystick1[6] = 1'b0;
                    else
                        joystick1[6] = 1'b1;
                end
                // JTFRAME_JOY_DURL maps joystick1[1] to the active-low
                // RIGHT input ({B3,B2,B1,DOWN,UP,RIGHT,LEFT}).
                if (right_start >= 0 && right_end >= right_start &&
                    frames >= right_start && frames <= right_end)
                    joystick1[1] = 1'b0;
                else
                    joystick1[1] = 1'b1;
                if (p1p3_replay_enabled) begin
                    if (p1p3_replay_cursor < p1p3_replay_count &&
                        p1p3_replay[p1p3_replay_cursor][47:16] < frames)
                        $fatal(1, "missed P1_P3 replay event cursor=%0d event_frame=%0d frame=%0d",
                               p1p3_replay_cursor,
                               p1p3_replay[p1p3_replay_cursor][47:16], frames);
                    while (p1p3_replay_cursor < p1p3_replay_count &&
                           p1p3_replay[p1p3_replay_cursor][47:16] == frames) begin
                        {cab_1p[2], joystick3} = p1p3_replay[p1p3_replay_cursor][15:8];
                        {cab_1p[0], joystick1} = p1p3_replay[p1p3_replay_cursor][7:0];
                        if ($test$plusargs("INPUT_DIAG"))
                            $display("[INPUT_REPLAY] frame=%0d P1_P3=%04x cursor=%0d",
                                     frames, p1p3_replay[p1p3_replay_cursor][15:0],
                                     p1p3_replay_cursor);
                        p1p3_replay_cursor = p1p3_replay_cursor + 1;
                    end
                end
                if ($test$plusargs("INPUT_DIAG") &&
                    ((coin_frame >= 0 && frames == coin_frame) ||
                     (coin2_frame >= 0 && frames == coin2_frame) ||
                     (start_frame >= 0 && frames == start_frame) ||
                     (button1_frame >= 0 && frames == button1_frame) ||
                     (button3_frame >= 0 && frames == button3_frame)))
                    $display("[INPUT] frame=%0d coin=%h start=%h joystick1=%h", frames, coin, cab_1p, joystick1);
`ifdef BUCKY_FAST_SIM
                if ($test$plusargs("TB_PROGRESS"))
                    $display("[TB] frame=%0d red=%02x green=%02x blue=%02x", frames, red, green, blue);
`else
                $display("[TB] frame=%0d red=%02x green=%02x blue=%02x", frames, red, green, blue);
`endif
                if (pc_every_diag || ($test$plusargs("PC_DIAG") && ((frames & 15) == 0)))
                    $display("[PC_DIAG] frame=%0d pc=%06x mailbox=%04x/%04x ctl2=%04x dma=%b",
                             frames, main_pc_debug,
                             ram_mem[17'h0817f], ram_mem[17'h08180],
                             dut.u_game.u_main.cur_control2, dut.u_game.u_video.dma_bsy);
                if (frames >= max_frames) begin
                    if (milestone_file != 0) begin
                        milestone_fd = $fopen(milestone_file, "a");
                        $fwrite(milestone_fd,
                                "FINAL frame=%0d pc=%06x attract=%0d start=%0d gameplay=%0d inlevel=%0d ppm=%0d mailbox=%04x/%04x\n",
                                frames, main_pc_debug, attract_seen, start_accepted,
                                gameplay_seen, inlevel_seen, ppm_written,
                                ram_mem[17'h0817f], ram_mem[17'h08180]);
                        $fclose(milestone_fd);
                    end
                    if (require_attract && !attract_seen)
                        $fatal(1, "parent MAME-aligned attract milestone 003644 was not reached");
                    if (require_gameplay && !gameplay_seen)
                        $fatal(1, "parent MAME-aligned directed gameplay milestone was not reached");
                    if (require_inlevel && (!inlevel_seen || !ppm_diag || !ppm_written ||
                                            ppm_frame_target != inlevel_frame_target))
                        $fatal(1, "parent did not capture the declared post-cutscene in-level frame");
                    if (require_no_exception && unexpected_vector_seen)
                        $fatal(1, "parent fetched an unexpected exception vector");
                    if (pcm_deadline_misses != 0)
                        $fatal(1, "K054539 missed %0d fixed-rate sample deadlines",
                               pcm_deadline_misses);
                    $display("[PERF] pcm_deadline_misses=%0d sprite_line_overruns=%0d",
                             pcm_deadline_misses, sprite_line_overruns);
                    $display("[TB] final hold=%b erase_bsy=%b erase_cnt=%0d req0=%b sel0=%b wr0=%b ack0=%b sdram_pending=%b",
                        dut.hold_rst, dut.u_bank0.u_slot0.erase_bsy,
                        dut.u_bank0.u_slot0.erase_cnt, dut.u_bank0.u_slot0.req,
                        dut.u_bank0.u_ctrl.slot_sel[0], dut.ba_wr[0], dut.ba_ack[0],
                        sdram_pending);
                    $display("PASS tb_bucky_parent frames=%0d cycles=%0d", frames, cycles);
                    if (result_file != 0) begin
                        result_fd = $fopen(result_file, "w");
                        if (result_fd == 0) $fatal(1, "cannot open RESULT_FILE=%0s", result_file);
                        $fwrite(result_fd, "PASS\n");
                        $fclose(result_fd);
                    end
                    $finish;
                end
            end
            lvbl_d = LVBL;
            // The first frame includes reset/SDRAM priming and can be much
            // longer than the steady-state ~0.7M-clock cadence.  Keep the
            // explicit MAX_CYCLES override for targeted tests, but leave a
            // generous harness margin so a valid parent run is not rejected
            // just before its requested final VBlank.
            if ((max_cycles > 0 && cycles > max_cycles) ||
                (max_cycles == 0 && cycles > frame_cycle_limit))
                $fatal(1, "parent integration watchdog expired");
    end
endmodule
