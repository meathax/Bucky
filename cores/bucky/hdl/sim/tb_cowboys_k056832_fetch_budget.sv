`timescale 1ns/1ps

// K056832 line-fetch budget gate.
//
// The tile fetch must place all four layers of the next line into the fill
// bank before the LHBL falling edge swaps the banks. The header of
// cowboys_k056832.v states the gate directly: 196 ROM reads per line at
// CLKDIV=6 (pxl_cen 8MHz, clk 48MHz -> 512*6 = 3072 clk per line).
//
// That budget was originally validated against a combinational tile ROM
// (zero latency) -- see the "NOTA sim" in the RTL header. Real hardware
// serves tiles from SDRAM, so each fetch stalls in P_ROM3 waiting for
// rom_ok. This bench serves the ROM with a settable latency and reports the
// reads actually completed per line, which is what the budget claim rests on.
//
// Why it matters: nothing clears the line buffers. A line whose fetch is cut
// short does not render partially -- the pixels it never wrote still hold the
// content of two lines earlier (the banks alternate), and a layer the fetch
// never reached keeps a whole stale line. On screens built from many unique
// FIX tiles (the stage title) that reads as long horizontal streaks.

module tb_cowboys_k056832_fetch_budget #(
    parameter int CLKDIV = 6
);

    localparam int TILES_LINE  = 196;   // 4 layers * 49 tiles
    localparam int LINE_CLK    = 512*CLKDIV;

    reg         clk=0, rst=1, pxl_cen=0;
    reg  [31:0] rom_data=32'h0;
    reg         rom_ok=0;
    wire        lhbl, lvbl, hs, vs, rom_cs;
    wire [ 8:0] hdump, vdump, vrender, vrender1;
    wire [18:0] rom_addr;
    wire [ 1:0] rom_lyr;
    wire [15:0] cpu_din;
    wire [ 7:0] lyrf_pxl, lyra_pxl, lyrb_pxl, lyrc_pxl, rom_bank;
    wire [ 1:0] lyra_mix, lyrb_mix, lyrc_mix;

    integer latency  = 0;   // clk cycles a tile ROM read stalls before rom_ok
    integer failures = 0;
    integer active_latency = 0;
    integer request_index = 0;
    integer mixed_stall = 0;

    initial mixed_stall = $test$plusargs("MIXED_STALL");

    always #10.4166 clk=~clk;   // 48 MHz

    integer cendiv=0;
    always @(posedge clk) begin
        if(cendiv==CLKDIV-1) begin cendiv<=0; pxl_cen<=1; end
        else begin cendiv<=cendiv+1; pxl_cen<=0; end
    end

    cowboys_k056832 dut(
        .rst(rst), .clk(clk), .pxl_cen(pxl_cen),
        .lhbl(lhbl), .lvbl(lvbl), .hs(hs), .vs(vs),
        .hdump(hdump), .vdump(vdump), .vrender(vrender), .vrender1(vrender1),
        .vram_cs(1'b0), .reg_cs(1'b0), .regb_cs(1'b0), .cpu_we(1'b0),
        .cpu_addr(12'd0), .cpu_dout(16'd0), .cpu_din(cpu_din),
        .rom_addr(rom_addr), .rom_lyr(rom_lyr), .rom_cs(rom_cs),
        .rom_data(rom_data), .rom_ok(rom_ok),
        .lyrf_pxl(lyrf_pxl), .lyra_pxl(lyra_pxl), .lyrb_pxl(lyrb_pxl), .lyrc_pxl(lyrc_pxl),
        .lyra_mix(lyra_mix), .lyrb_mix(lyrb_mix), .lyrc_mix(lyrc_mix),
        .rom_bank(rom_bank),
        .gfx_en(4'hf), .debug_bus(8'd0)
    );

    // Tile ROM model: hold rom_ok low for `latency` cycles after rom_cs rises,
    // mimicking an SDRAM read that misses the line cache. Data content is
    // irrelevant here -- the gate counts completed reads, not pixels.
    integer waitcnt=0;
    reg     prev_cs=0;
    always @(posedge clk) begin
        prev_cs <= rom_cs;
        if(!rom_cs) begin
            rom_ok  <= 0;
            waitcnt <= 0;
        end else if(!prev_cs) begin
            request_index = request_index + 1;
            active_latency = latency;
            // A sparse, deterministic stress profile models an otherwise
            // healthy line-cache stream interrupted by isolated SDRAM
            // service stalls.  The 96 MHz video clock has the budget to
            // absorb these without exposing a stale line.
            if(mixed_stall && (request_index % 37)==0)
                active_latency = active_latency + 32;
            waitcnt <= 0;
            rom_ok  <= (active_latency==0);
        end else if(!rom_ok) begin
            if(waitcnt >= active_latency-1) rom_ok <= 1;
            else waitcnt <= waitcnt+1;
        end
        // Every nibble identical, so a tile's pen does not depend on the pixel
        // within it; the value is derived from rom_addr[2:0], which with a blank
        // VRAM equals tyf and therefore changes from line to line. One displayed
        // line must then contain a single pen value -- a second value can only
        // have come from a different line's fetch left behind in the buffer.
        rom_data <= {8{4'd1 + {1'b0,rom_addr[2:0]}}};   // 8 nibbles, value 1..8
    end

    // Count completed ROM reads between LHBL falling edges. One tile fetch =
    // one rising edge of rom_cs (asserted through P_ROM2+P_ROM3).
    integer reads_line=0;
    integer worst=0, best=0, sampled=0, lines_seen=0, total_reads=0;
    reg     prev_lhbl=1;
    reg     counting=0;
    always @(posedge clk) begin
        prev_lhbl <= lhbl;
        if(prev_lhbl && !lhbl) begin
            lines_seen = lines_seen+1;
            if(counting) begin
                if(sampled==0 || reads_line<worst) worst = reads_line;
                if(sampled==0 || reads_line>best ) best  = reads_line;
                sampled = sampled+1;
            end
            reads_line = (rom_cs && !prev_cs) ? 1 : 0;
        end else if(rom_cs && !prev_cs) begin
            reads_line  = reads_line+1;
            total_reads = total_reads+1;
        end
    end

    // Cross-line contamination check on the last-fetched layer (C is fetched
    // fourth, so it is the first to be starved when the line runs out of time).
    // Two ways a stale line shows up, and both must be caught:
    //   * fetch stopped part way through layer C -> new tiles and two-line-old
    //     tiles share the line, so more than one pen value appears in it;
    //   * fetch never reached layer C at all -> the whole line is old, which is
    //     uniform, but its pen is the one from two lines back and so breaks the
    //     +1-per-line sequence that tyf produces.
    integer stale_px=0, seq_err=0, coverage_masked=0, line_pen=-1, prev_line_pen=-1;
    reg     prev_lhbl_c=1;
    always @(posedge clk) begin
        prev_lhbl_c <= lhbl;
        if(prev_lhbl_c && !lhbl) begin               // visible part of a line ended
            if(counting && line_pen>0 && prev_line_pen>0)
                if( ((line_pen-1) - (prev_line_pen-1) + 8) % 8 != 1 ) seq_err = seq_err+1;
            if(line_pen>0) prev_line_pen = line_pen;
            line_pen = -1;
        end else if(pxl_cen && lhbl && lyrc_pxl!=8'd0) begin
            if(line_pen < 0) line_pen = lyrc_pxl[3:0];
            else if(counting && lyrc_pxl[3:0] != line_pen) stale_px = stale_px+1;
        end
        // The coverage guard is diagnostic only.  A passing 96 MHz run must
        // never rely on it to hide an unfilled portion of a displayed line.
        if(counting && pxl_cen && lhbl && dut.dpx < 9'd384 && dut.cov_ok !== 4'hf)
            coverage_masked = coverage_masked + 1;
    end

    task run_latency(input integer lat);
        begin
            latency = lat;
            mixed_stall = 0;
            request_index = 0;
            counting = 0; sampled = 0; worst = 0; best = 0; stale_px = 0; seq_err = 0; coverage_masked = 0;
            // settle: let a few whole lines pass before sampling
            repeat(4*LINE_CLK) @(posedge clk);
            counting = 1;
            repeat(12*LINE_CLK) @(posedge clk);
            counting = 0;
            $display("  latency=%0d clk : reads/line worst=%0d best=%0d (need %0d) %-5s  mixed px=%0d wrong-line=%0d masked=%0d %s",
                     lat, worst, best, TILES_LINE,
                     worst>=TILES_LINE ? "OK" : "SHORT", stale_px, seq_err,
                     coverage_masked,
                     (stale_px==0 && seq_err==0) ? "" : "<-- STALE LINE VISIBLE");
            // A line the fetch could not finish may lose tiles, but it must never
            // display pixels belonging to another line.
            if(stale_px != 0 || seq_err != 0) failures = failures+1;
            if(CLKDIV >= 12 && worst < TILES_LINE) begin
                $display("FAIL 96MHz fetch budget: %0d reads/line at latency=%0d, need %0d",
                         worst, lat, TILES_LINE);
                failures = failures+1;
            end
            if(CLKDIV >= 12 && coverage_masked != 0) begin
                $display("FAIL 96MHz fetch budget used coverage mask %0d times", coverage_masked);
                failures = failures+1;
            end
        end
    endtask

    task run_mixed_profile;
        begin
            latency = 4;
            mixed_stall = 1;
            request_index = 0;
            counting = 0; sampled = 0; worst = 0; best = 0; stale_px = 0; seq_err = 0; coverage_masked = 0;
            repeat(4*LINE_CLK) @(posedge clk);
            counting = 1;
            repeat(12*LINE_CLK) @(posedge clk);
            counting = 0;
            $display("  mixed profile (base=4 + isolated 32-cycle stalls): reads/line worst=%0d best=%0d (need %0d) mixed px=%0d wrong-line=%0d masked=%0d",
                     worst, best, TILES_LINE, stale_px, seq_err, coverage_masked);
            if(worst < TILES_LINE || stale_px != 0 || seq_err != 0 || coverage_masked != 0)
                failures = failures+1;
            mixed_stall = 0;
        end
    endtask

    initial begin
        repeat(8) @(posedge clk);
        rst=0;
        $display("K056832 line-fetch budget @CLKDIV=%0d (%0d clk/line)", CLKDIV, LINE_CLK);
        run_latency(0);
        run_latency(2);
        run_latency(4);
        run_latency(6);
        run_latency(8);
        run_latency(12);
        run_latency(20);
		if(CLKDIV >= 12 && $test$plusargs("MIXED_STALL"))
			run_mixed_profile();

        // The gate: at the hardware clock ratio the fetch must still complete
        // with a realistic SDRAM stall. avg 2.5 clk was the figure the RTL
        // header assumed; require the design to hold at 4.
        latency = 4;
        counting = 0; sampled = 0; worst = 0; best = 0;
        repeat(4*LINE_CLK) @(posedge clk);
        counting = 1;
        repeat(12*LINE_CLK) @(posedge clk);
        counting = 0;
        if(worst < TILES_LINE) begin
            $display("FAIL fetch budget: %0d reads/line at latency=4, need %0d",
                     worst, TILES_LINE);
            failures = failures+1;
        end

        if(failures != 0) $fatal(1,"K056832 fetch-budget failures=%0d", failures);
        $display("PASS K056832 fetch budget");
        $finish;
    end

endmodule
