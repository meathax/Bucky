`timescale 1ns/1ps

module tb_bucky_k053252;
    reg clk=0, rst=1, cs=0, we=0, rd=0;
    reg [3:0] addr=0;
    reg [7:0] din=0;
    reg [8:0] vcount=0;
    wire [7:0] dout;
    integer failures=0;

    always #5 clk=~clk;

    bucky_k053252 dut(
        .rst(rst), .clk(clk), .cs(cs), .we(we), .rd(rd), .addr(addr),
        .din(din), .dout(dout), .vcount(vcount)
    );

    task wr;
        input [3:0] a;
        input [7:0] d;
        begin
            @(negedge clk); addr=a; din=d; cs=1; we=1; rd=0;
            @(posedge clk); #1; cs=0; we=0;
        end
    endtask

    task expect_rd;
        input [3:0] a;
        input [7:0] expected;
        begin
            @(negedge clk); addr=a; cs=1; we=0; rd=1;
            @(posedge clk); #1;
            if (dout !== expected) begin
                $display("FAIL K053252 read addr=%x expected=%02x actual=%02x",a,expected,dout);
                failures=failures+1;
            end
            @(negedge clk); cs=0; rd=0;
        end
    endtask

    initial begin
        repeat(2) @(posedge clk);
        rst=0;
        // MAME reset_internal_state(): register 8 reads back as one.
        expect_rd(4'h8,8'h01);
        vcount=9'h000; expect_rd(4'he,8'h00); expect_rd(4'hf,8'h00);
        wr(4'h0,8'h12); wr(4'h1,8'h34); wr(4'h6,8'h80);
        expect_rd(4'h0,8'h12); expect_rd(4'h1,8'h34); expect_rd(4'h6,8'h80);

        // VCT = vcount - (VC + 1), with the high byte exposing only bit 8.
        wr(4'h8,8'h00); wr(4'h9,8'h10);
        vcount=9'h012; expect_rd(4'he,8'h00); expect_rd(4'hf,8'h01);
        vcount=9'h1ff; expect_rd(4'he,8'h01); expect_rd(4'hf,8'hee);

        if (failures != 0) $fatal(1,"K053252 failures=%0d", failures);
        $display("PASS tb_bucky_k053252");
        $finish;
    end
endmodule
