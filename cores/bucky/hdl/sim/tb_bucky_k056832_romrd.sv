`timescale 1ns/1ps

module tb_bucky_k056832_romrd;
    reg clk=0, rst=1;
    reg rd_cs=0;
    reg [12:1] rd_addr=0;
    reg [18:0] tile_addr=0;
    reg tile_cs=0, scr_ok=0;
    reg [31:0] scr_data=0;
    wire rd_ok, tile_ok, scr_cs;
    wire [15:0] rd_data;
    wire [18:0] scr_addr;
    integer failures=0;

    always #5 clk=~clk;

    bucky_k056832_romrd dut(
        .rst(rst), .clk(clk),
        .rd_cs(rd_cs), .rd_addr(rd_addr), .rd_ok(rd_ok), .rd_data(rd_data),
        .tile_addr(tile_addr), .tile_cs(tile_cs), .tile_ok(tile_ok),
        .scr_addr(scr_addr), .scr_cs(scr_cs), .scr_data(scr_data), .scr_ok(scr_ok)
    );

    task fail;
        input [255:0] msg;
        begin $display("FAIL K056832 ROMRD: %0s",msg); failures=failures+1; end
    endtask

    initial begin
        repeat(2) @(posedge clk); rst=0;

        // Normal tile traffic passes through while no CPU read is active.
        tile_addr=19'h12345; tile_cs=1; scr_ok=1;
        #1;
        if (!scr_cs || scr_addr!==19'h12345 || !tile_ok) fail("tile passthrough");
        @(negedge clk); tile_cs=0; scr_ok=0;

        // An odd CPU word selects the upper half of the 32-bit slot.
        rd_addr=12'h003; rd_cs=1; scr_data=32'haabb_ccdd;
        #1 if (scr_cs) fail("CPU request did not break tile slot");
        @(posedge clk); #1;
        if (scr_cs) fail("break state still asserted request");
        @(posedge clk); #1;
        if (!scr_cs || scr_addr!==19'h00001) fail("CPU request address/edge");
        scr_ok=1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        if (!rd_ok || rd_data!==16'haabb) fail("odd CPU readback byte order");
        scr_ok=0;

        // Keep the result valid until the 68000 releases the bus.
        @(posedge clk); #1;
        if (!rd_ok || rd_data!==16'haabb || scr_cs) fail("done hold");
        rd_cs=0;
        @(posedge clk); #1;
        tile_addr=19'h00022; tile_cs=1; scr_ok=1;
        #1 if (!scr_cs || !tile_ok || scr_addr!==19'h00022) fail("tile resume");

        if (failures!=0) $fatal(1,"K056832 ROMRD failures=%0d",failures);
        $display("PASS tb_bucky_k056832_romrd");
        $finish;
    end
endmodule
