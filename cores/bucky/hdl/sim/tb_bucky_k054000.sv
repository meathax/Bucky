`timescale 1ns/1ps

module tb_bucky_k054000;
    reg clk = 0;
    reg cs = 0;
    reg we = 0;
    reg [4:0] addr = 0;
    reg [7:0] din = 0;
    wire [7:0] dout;
    integer failures = 0;

    always #5 clk = ~clk;

    bucky_k054000 dut(
        .clk(clk), .cs(cs), .we(we), .addr(addr), .din(din), .dout(dout)
    );

    task wr;
        input [4:0] a;
        input [7:0] d;
        begin
            @(negedge clk); addr=a; din=d; cs=1; we=1;
            @(negedge clk); cs=0; we=0;
        end
    endtask

    task expect_status;
        input expected;
        begin
            @(negedge clk); addr=5'h18; cs=1; we=0;
            #1;
            if (dout[0] !== expected) begin
                $display("FAIL status expected=%0d actual=%0d", expected, dout[0]);
                failures = failures + 1;
            end
            @(negedge clk); cs=0;
        end
    endtask

    task clear_regs;
        begin
            wr(5'h01,0); wr(5'h02,0); wr(5'h03,0); wr(5'h04,0);
            wr(5'h06,0); wr(5'h07,0);
            wr(5'h09,0); wr(5'h0a,0); wr(5'h0b,0); wr(5'h0c,0);
            wr(5'h0e,0); wr(5'h0f,0);
            wr(5'h11,0); wr(5'h12,0); wr(5'h13,0);
            wr(5'h15,0); wr(5'h16,0); wr(5'h17,0);
        end
    endtask

    initial begin
        clear_regs();
        expect_status(0);

        // Published power-on-test sequence used to exercise all datapaths.
        wr(5'h01,8'hff); expect_status(1);
        wr(5'h15,8'hff); expect_status(0);
        wr(5'h02,8'hff); expect_status(1);
        wr(5'h16,8'hff); expect_status(0);
        wr(5'h03,8'hff); expect_status(1);
        wr(5'h17,8'hff); expect_status(0);

        wr(5'h09,8'hff); expect_status(1);
        wr(5'h11,8'hff); expect_status(0);
        wr(5'h0a,8'hff); expect_status(1);
        wr(5'h12,8'hff); expect_status(0);
        wr(5'h0b,8'hff); expect_status(1);
        wr(5'h13,8'hff); expect_status(0);

        wr(5'h04,8'hff); expect_status(1);
        wr(5'h06,8'hff); expect_status(0);
        wr(5'h0c,8'hff); expect_status(1);
        wr(5'h07,8'hff); expect_status(0);
        wr(5'h06,8'h00); expect_status(1);
        wr(5'h0e,8'hff); expect_status(0);
        wr(5'h07,8'h00); expect_status(1);
        wr(5'h0f,8'hff); expect_status(0);

        // Boundary from MAME's K054000 axis_check: with 0xff + 0xff
        // semiaxes, +510 is in range and +511 is a miss.
        clear_regs();
        wr(5'h01,8'h00); wr(5'h02,8'h01); wr(5'h03,8'hfe);
        wr(5'h15,8'h00); wr(5'h16,8'h00); wr(5'h17,8'h00);
        wr(5'h06,8'hff); wr(5'h0e,8'hff);
        expect_status(0);
        wr(5'h03,8'hff);
        expect_status(1);

        if (failures != 0) $fatal(1,"K054000 failures=%0d",failures);
        $display("PASS tb_bucky_k054000");
        $finish;
    end
endmodule
