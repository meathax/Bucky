`timescale 1ns/1ps

module tb_bucky_k054539_deadline;
    localparam integer ROM_LATENCY = 20;

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
    reg [7:0] rom_data=8'h01;
    reg rom_ok=0;
    wire signed [15:0] left, right;

    integer rom_delay=-1;
    integer commits=0;
    integer timeout_count=0;
    integer tick=0;
    integer last_commit=-1;
    integer ch;

    always #5 clk=~clk;

    k054539 dut(
        .rst(rst), .clk(clk), .cen(cen), .timeout(timeout),
        .addr(addr), .we(we), .rd(rd), .cs(cs), .din(din), .dout(dout),
        .rom_cs(rom_cs), .rom_addr(rom_addr), .rom_data(rom_data), .rom_ok(rom_ok),
        .rb_wait(rb_wait),
        .left(left), .right(right), .debug_bus(8'h00), .st_dout(st_dout)
    );

    task wr;
        input [8:0] a;
        input [7:0] d;
        begin
            @(negedge clk); addr=a; din=d; cs=1; we=1; rd=0;
            @(posedge clk); #1; cs=0; we=0;
            @(posedge clk); #1; // physical write commits after strobe release
        end
    endtask

    // Deterministic shared-ROM model. Each request is held off long enough to
    // exercise realistic contention while remaining inside the 384-enable
    // hardware deadline with all eight channels active.
    always @(posedge clk) begin
        rom_ok <= 1'b0;
        if (rst) begin
            rom_delay <= -1;
        end else if (rom_delay >= 0) begin
            if (rom_delay == 0) begin
                rom_data <= 8'h01;
                rom_ok <= 1'b1;
                rom_delay <= -1;
            end else begin
                rom_delay <= rom_delay - 1;
            end
        end else if (rom_cs) begin
            rom_delay <= ROM_LATENCY;
        end
    end

    always @(posedge clk) begin
        if (!rst && cen) begin
            tick <= tick + 1;
            if (timeout)
                timeout_count <= timeout_count + 1;
            if (dut.state == 4'd9) begin
                if (last_commit >= 0 && (tick-last_commit) != 384)
                    $fatal(1, "K054539 commit interval=%0d expected=384", tick-last_commit);
                last_commit <= tick;
                commits <= commits + 1;
            end
        end
    end

    initial begin
        repeat(3) @(posedge clk);
        rst=0;

        // Eight 8-bit voices advancing one source byte per output sample.
        // Positions are already zero; UPDATE_AT_KEYON commits them together.
        for (ch=0; ch<8; ch=ch+1) begin
            wr((ch*32)+0, 8'h00);
            wr((ch*32)+1, 8'h00);
            wr((ch*32)+2, 8'h01);
            wr((ch*32)+3, 8'h00);
            wr((ch*32)+5, 8'h18);
            wr(9'h100+(ch*2), 8'h00);
        end
        wr(9'h12f,8'h11);
        wr(9'h114,8'hff);
        cen=1;

        wait (commits == 8);
        @(posedge clk);
        if (timeout_count != 0)
            $fatal(1, "K054539 missed %0d fixed-rate sample boundaries", timeout_count);
        $display("PASS tb_bucky_k054539_deadline commits=%0d interval=384 latency=%0d",
                 commits, ROM_LATENCY);
        $finish;
    end

    wire _unused = &{1'b0, dout, st_dout, rom_addr, rb_wait, left, right, 1'b0};
endmodule
