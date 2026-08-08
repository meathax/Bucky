`timescale 1ns/1ps

module tb_bucky_k054338;
    reg clk=0, rst=1, cen=1, reg_cs=0, reg_we=0;
    reg [3:0] reg_addr=0;
    reg [15:0] reg_din=0;
    reg [1:0] reg_dsn=0;
    reg [23:0] front_bgr=0, back_bgr=0;
    reg [1:0] mix_code=0, shadow_code=0, brightness_code=0;
    wire [15:0] reg_dout;
    wire [23:0] color_bgr;
    wire [7:0] brightness;
    integer failures=0;

    always #5 clk=~clk;

    bucky_k054338 dut(
        .rst(rst),.clk(clk),.cen(cen),
        .reg_cs(reg_cs),.reg_we(reg_we),.reg_addr(reg_addr),.reg_din(reg_din),.reg_dsn(reg_dsn),.reg_dout(reg_dout),
        .front_bgr(front_bgr),.back_bgr(back_bgr),.mix_code(mix_code),
        .shadow_code(shadow_code),.brightness_code(brightness_code),
        .color_bgr(color_bgr),.brightness(brightness)
    );

    task wr;
        input [3:0] a; input [15:0] d;
        begin
            @(negedge clk); reg_addr=a; reg_din=d; reg_dsn=0; reg_cs=1; reg_we=1;
            @(negedge clk); reg_cs=0; reg_we=0;
        end
    endtask

    task tick_expect;
        input [23:0] expected;
        begin
            @(posedge clk); #1;
            if(color_bgr!==expected) begin
                $display("FAIL color expected=%06x actual=%06x",expected,color_bgr);
                failures=failures+1;
            end
        end
    endtask

    initial begin
        repeat(2) @(posedge clk); rst=0;
        wr(0,16'h0033); wr(1,16'h2211);
        front_bgr=24'hf0c080; back_bgr=24'h102040;
        tick_expect(24'h112233); // control bit 0 clear forces backdrop

        wr(15,16'h0001);        // layers enabled, clamping enabled
        mix_code=0;
        tick_expect(24'hf0c080);

        wr(13,16'h0010);        // mix code 1, alpha level 16
        mix_code=1;
        tick_expect(24'h807060); // exact half interpolation

        wr(13,16'h0000);        // level 0 selects the back layer
        tick_expect(24'h102040);

        wr(13,16'h0030);        // additive, level 16
        tick_expect(24'hf8d0a0); // front + half back, clamped

        wr(2,16'h01c0); wr(3,16'h01c0); wr(4,16'h01c0); // signed -64
        mix_code=0; shadow_code=1;
        tick_expect(24'hb08040);

        wr(11,16'h005a); brightness_code=1;
        @(posedge clk); #1;
        if(brightness!==8'h5a) begin
            $display("FAIL brightness expected=5a actual=%02x",brightness);
            failures=failures+1;
        end

        if(failures!=0) $fatal(1,"K054338 failures=%0d",failures);
        $display("PASS tb_bucky_k054338");
        $finish;
    end
endmodule
