`timescale 1ns/1ps

module tb_bucky_k053251_shadow;
	reg clk=0, rst=1, pxl_cen=0, cs=0, sel=0;
	reg [3:0] addr=0, ioctl_addr=0;
	reg [5:0] din=0, pri0=0, pri1=0, pri2=0;
	reg [8:0] ci0=0, ci1=0, ci2=0;
	reg [7:0] ci3=0, ci4=0;
	reg [1:0] shd_in=0;
	wire [1:0] shd_out;
	wire [7:0] ioctl_din, reg_dout;
	wire [10:0] cout;
	wire brit, col_n;
	integer failures=0;

	always #5 clk=~clk;

	k053251 dut(
		.rst(rst),.clk(clk),.pxl_cen(pxl_cen),.cs(cs),.addr(addr),.din(din),
		.sel(sel),.pri0(pri0),.pri1(pri1),.pri2(pri2),
		.ci0(ci0),.ci1(ci1),.ci2(ci2),.ci3(ci3),.ci4(ci4),
		.shd_in(shd_in),.shd_out(shd_out),.ioctl_addr(ioctl_addr),
		.ioctl_din(ioctl_din),.reg_dout(reg_dout),.cout(cout),.brit(brit),.col_n(col_n)
	);

	task wr;
		input [3:0] a;
		input [5:0] d;
		begin
			@(negedge clk); addr=a; din=d; cs=1;
			@(negedge clk); cs=0;
		end
	endtask

	task sample_expect;
		input [1:0] expected;
		begin
			// The priority cascade resolves during the seven clocks between
			// pixel enables.  The following enable commits its shadow result.
			@(negedge clk); pxl_cen=1;
			@(negedge clk); pxl_cen=0;
			repeat(7) @(posedge clk);
			@(negedge clk); pxl_cen=1;
			@(posedge clk); #1;
			if(shd_out!==expected) begin
				$display("FAIL shadow expected=%0d actual=%0d winning_pri=%0d shadow_pri=%0d",
					expected,shd_out,dut.mix4p,dut.shd_p);
				failures=failures+1;
			end
			@(negedge clk); pxl_cen=0;
		end
	endtask

	initial begin
		repeat(2) @(posedge clk); rst=0;
		// Bucky's boot values: shadow code 1 has priority 5.  Numerically
		// larger layer priorities are lower priority, so this shadow must
		// pass over a background at priority 16.
		wr(6,6'd5);
		wr(3,6'd16);
		ci3=8'h01;
		shd_in=2'd1;
		sample_expect(2'd1);

		// A layer above the shadow (priority 4) must remain unshadowed.
		wr(3,6'd4);
		sample_expect(2'd0);

		if(failures!=0) $fatal(1,"K053251 shadow failures=%0d",failures);
		$display("PASS tb_bucky_k053251_shadow");
		$finish;
	end
endmodule
