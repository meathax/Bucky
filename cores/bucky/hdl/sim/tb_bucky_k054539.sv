`timescale 1ns/1ps

module tb_bucky_k054539;
    reg rst=1, clk=0, cen=0;
    reg [8:0] addr=0;
    reg we=0, rd=0, cs=0;
    reg [7:0] din=0;
    wire [7:0] dout;
    wire timeout;
    wire [7:0] st_dout;
    wire rom_cs;
    wire [23:0] rom_addr;
    wire rb_wait;
    reg [7:0] rom_data=0;
    reg rom_ok=0;
    wire signed [15:0] left, right;
    integer failures=0;

    always #5 clk=~clk;

    k054539 dut(
        .rst(rst), .clk(clk), .cen(cen), .timeout(timeout),
        .addr(addr), .we(we), .rd(rd), .cs(cs), .din(din), .dout(dout),
        .rom_cs(rom_cs), .rom_addr(rom_addr), .rom_data(rom_data), .rom_ok(rom_ok),
        .rb_wait(rb_wait),
        .left(left), .right(right), .debug_bus(8'h00), .st_dout(st_dout)
    );

    task wr;
        input [8:0] a; input [7:0] d;
        begin
            @(negedge clk); addr=a; din=d; cs=1; we=1; rd=0;
            @(posedge clk); #1; cs=0; we=0;
            @(posedge clk); #1; // physical write commits after strobe release
        end
    endtask

    task expect_reg;
        input [8:0] a; input [7:0] expected;
        begin
            @(negedge clk); addr=a; cs=1; we=0; rd=1;
            #1;
            while (rb_wait) begin
                @(posedge clk); #1;
            end
            if (dout !== expected) begin
                $display("FAIL K054539 read addr=%03x expected=%02x actual=%02x",a,expected,dout);
                failures=failures+1;
            end
            @(posedge clk); #1; cs=0; rd=0;
        end
    endtask

    initial begin
        repeat(2) @(posedge clk);
        rst=0;

        // Register RAM and active-channel readback (MAME 0x22c/0x22f).
        wr(9'h003,8'h44);
        expect_reg(9'h003,8'h44);
        expect_reg(9'h12c,8'h00);
        wr(9'h12f,8'h11);       // PCM + ROM/RAM readback enable
        wr(9'h114,8'h01);       // key on channel 0
        expect_reg(9'h12c,8'h01);
        wr(9'h115,8'h01);       // key off channel 0
        expect_reg(9'h12c,8'h00);

        // UPDATE_AT_KEYON: position bytes are hidden until key-on, then
        // committed atomically into the visible channel registers.
        wr(9'h12f,8'h11);       // PCM + readback + UPDATE_AT_KEYON
        wr(9'h00c,8'h12);
        expect_reg(9'h00c,8'h00);
        wr(9'h114,8'h01);
        expect_reg(9'h00c,8'h12);

        // A key-on command retriggers a voice even when it is already
        // active.  Bucky reuses the PCM voices for short event effects; if
        // the active bit suppresses restart, later coin/impact/voice samples
        // continue from the previous position and are effectively silent.
        // MAME commits the new position latch on every key-on.
        cen=1;
        wait (!dut.restart[0]);  // first key-on has been consumed by S_LOAD
        @(posedge clk); #1;
        cen=0;
        wr(9'h00c,8'h34);
        wr(9'h00d,8'h12);
        wr(9'h00e,8'h00);
        expect_reg(9'h00c,8'h12); // still hidden while channel is active
        wr(9'h114,8'h01);         // re-key the already-active channel
        expect_reg(9'h00c,8'h34);
        expect_reg(9'h00d,8'h12);
        if (!dut.restart[0]) begin
            $display("FAIL K054539 active voice did not re-arm restart on key-on");
            failures=failures+1;
        end
        wr(9'h115,8'h01);

        // A key-on release arriving on the same clock as an EOF response must win
        // over the sequencer's attempt to retire the old sample. SiliconRE
        // shows key-on is queued for the next sequence; losing active here
        // leaves restart armed on a channel that S_LOAD will skip forever.
        @(negedge clk);
        dut.active=8'h01;
        dut.restart=8'h00;
        dut.ch=3'd0;
        dut.state=4'd3;          // S_R8
        cen=0;
        rom_data=8'h80;         // 8-bit EOF marker
        rom_ok=1;
        addr=9'h114;
        din=8'h01;
        cs=1;
        we=1;
        rd=0;
        repeat(2) @(posedge clk);
        @(negedge clk); cs=0; we=0; cen=1;
        @(posedge clk); #1;
        if (!dut.active[0] || !dut.restart[0]) begin
            $display("FAIL K054539 same-cycle EOF/key-on lost request active=%b restart=%b",
                     dut.active[0], dut.restart[0]);
            failures=failures+1;
        end
        cen=0; rom_ok=0;
        dut.state=4'd0;          // isolate the following data-port checks
        dut.active=8'h00;
        dut.restart=8'h00;

        // Move the fixed-rate counter into its post-boundary idle window
        // with every voice off. The data-port arbiter intentionally refuses
        // to start a CPU ROM read exactly on a sample boundary.
        cen=1;
        repeat(40) @(posedge clk);
        wait(dut.state == 4'd0);
        cen=0;

        // ROM-bank data-port readback is serialized through the shared ROM
        // request and advertises a Z80 wait until rom_ok arrives.
        wr(9'h12e,8'h01);       // bank 1, pointer resets to zero
        @(negedge clk); addr=9'h12d; cs=1; we=0; rd=1; #1;
        if (!rb_wait) begin
            $display("FAIL K054539 ROM read did not assert wait");
            failures=failures+1;
        end
        @(posedge clk); #1;     // latch the request
        @(posedge clk); #1;     // launch the shared ROM request
        if (!rom_cs || rom_addr!==24'h020000) begin
            $display("FAIL K054539 ROM request addr/cs cs=%b addr=%06x",rom_cs,rom_addr);
            failures=failures+1;
        end
        rom_data=8'h5a; rom_ok=1;
        @(posedge clk); #1;
        rom_ok=0;
        if (rb_wait || dout!==8'h5a) begin
            $display("FAIL K054539 ROM readback wait=%b data=%02x",rb_wait,dout);
            failures=failures+1;
        end
        @(negedge clk); cs=0; rd=0;

        // Reverb data-port write/read, bank 0x80, pointer increments after
        // each access and the port obeys global readback bit 4.
        wr(9'h12e,8'h80);
        wr(9'h12d,8'ha5);
        expect_reg(9'h12d,8'h00); // pointer now points at the next byte
        wr(9'h12e,8'h80);
        expect_reg(9'h12d,8'ha5);

        if(failures != 0) $fatal(1,"K054539 failures=%0d", failures);
        $display("PASS tb_bucky_k054539");
        $finish;
    end
endmodule
