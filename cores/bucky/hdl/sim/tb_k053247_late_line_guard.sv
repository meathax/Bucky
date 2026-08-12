`timescale 1ns/1ps

module tb_k053247_late_line_guard;
	reg clk=0, rst=1, pxl_cen=1, hs=0, flip=0, draw=0;
	reg [9:0] hdump=0, xpos=10'd32;
	reg [3:0] code=0, ysub=0;
	reg [5:0] hzoom=6'd32;
	reg hz_keep=0, hflip=0, vflip=0;
	reg [3:0] pal=0;
	wire busy, rom_cs;
	wire [8:0] rom_addr;
	wire [7:0] buf_pred;
	wire [7:0] pxl;
	integer failures=0, saw_recovery_write=0;

	always #5 clk=~clk;
	always @(posedge clk) hdump <= hdump+1'd1;

	k053247_gate #(
		.AW(10),.CW(4),.PW(8),.ZW(6),.ZI(5),.ZENLARGE(1),
		.SWAPH(0),.HFIX(0),.LATCH(0),.ALPHA(0),.SHADOW(1),
		.SHADOW_PEN(15),.SW(2)
	) dut(
		.rst(rst),.clk(clk),.pxl_cen(pxl_cen),.hs(hs),.flip(flip),.hdump(hdump),
		.draw(draw),.busy(busy),.code(code),.xpos(xpos),.ysub(ysub),.trunc(2'd0),
		.hzoom(hzoom),.hz_keep(hz_keep),.hflip(hflip),.vflip(vflip),.pal(pal),
		.rom_addr(rom_addr),.rom_cs(rom_cs),.rom_ok(rom_cs),.rom_data(32'hffff_ffff),
		.buf_pred(buf_pred),.buf_din(buf_pred),.pxl(pxl)
	);

	task start_tile;
		begin
			@(negedge clk); draw=1;
			@(negedge clk); draw=0;
		end
	endtask

	initial begin
		repeat(2) @(posedge clk); rst=0;
		start_tile();
		wait(dut.dr_active===1'b1);

		// Flip banks while the old tile still owns the draw stage.
		@(negedge clk); hs=1;
		@(posedge clk); #1;
		if(!dut.discard_late_draw) begin
			$display("FAIL late draw was not quarantined at HS");
			failures=failures+1;
		end
		while(dut.dr_active) begin
			@(posedge clk); #1;
			if((dut.u_draw.buf_we || dut.u_draw.buf_we2 ||
			    dut.u_draw.buf_we3 || dut.u_draw.buf_we4) &&
			   (dut.u_linebuf.we || dut.u_linebuf.we2 ||
			    dut.u_linebuf.we3 || dut.u_linebuf.we4)) begin
				$display("FAIL prior-line pixels reached the new producer bank");
				failures=failures+1;
			end
		end
		@(negedge clk); hs=0;
		repeat(2) @(posedge clk);

		// The quarantine must clear for the first tile owned by the new line.
		start_tile();
		repeat(20) begin
			@(posedge clk); #1;
			if(dut.u_linebuf.we || dut.u_linebuf.we2 ||
			   dut.u_linebuf.we3 || dut.u_linebuf.we4)
				saw_recovery_write=1;
		end
		if(!saw_recovery_write) begin
			$display("FAIL next-line tile remained blocked");
			failures=failures+1;
		end

		if(failures!=0) $fatal(1,"K053247 late-line guard failures=%0d",failures);
		$display("PASS tb_k053247_late_line_guard");
		$finish;
	end
endmodule
