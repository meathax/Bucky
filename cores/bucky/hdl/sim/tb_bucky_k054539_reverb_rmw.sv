`timescale 1ns/1ps

module tb_bucky_k054539_reverb_rmw;
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
	// voltab[0]=0x4000, rbvol=voltab>>1=0x2000; 0x4000*0x2000>>16=0x0800.
	localparam signed [15:0] EXPECTED_CONTRIB = 16'h0800;

	always #5 clk=~clk;

	k054539 dut(
		.rst(rst), .clk(clk), .cen(cen), .timeout(timeout),
		.addr(addr), .we(we), .rd(rd), .cs(cs), .din(din), .dout(dout),
		.rom_cs(rom_cs), .rom_addr(rom_addr), .rom_data(rom_data), .rom_ok(rom_ok),
		.rb_wait(rb_wait),
		.left(left), .right(right), .debug_bus(8'h00), .st_dout(st_dout)
	);

	// K054539 runs at 18.432 MHz inside the 48 MHz master domain. Its clock
	// enable is sparse; exercise the synchronous RAM across intervening raw
	// clocks instead of relying on unrealistic back-to-back enables.
	task pcm_step;
		begin
			@(negedge clk); cen=1;
			@(posedge clk); #1; cen=0;
			repeat(2) @(posedge clk);
		end
	endtask

	initial begin
		repeat(3) @(posedge clk);
		rst=0;
		@(negedge clk);

		// First prove the feedback slot is read and cleared through the same
		// synchronous port used by the channel RMW below.
		dut.u_rram_lo.u_lo.u_ram.mem[0] = 8'h11;
		dut.u_rram_lo.u_hi.u_ram.mem[0] = 8'h11;
		dut.reverb_pos=0;
		dut.rr_addr=0;
		dut.rr_we=0;
		dut.state=4'd10;        // S_REVRD consumes feedback at reverb_pos
		repeat(2) @(posedge clk);
		pcm_step();
		if ({dut.u_rram_lo.u_hi.u_ram.mem[0],
		     dut.u_rram_lo.u_lo.u_ram.mem[0]} !== 16'h0000)
			$fatal(1,"reverb feedback slot was not cleared");

		// Put a distinct word at the requested channel reverb address. A
		// correct RMW must add this channel's non-zero contribution only at
		// widx=5 and leave the just-cleared feedback slot untouched.
		dut.u_rram_lo.u_lo.u_ram.mem[5] = 8'h22;
		dut.u_rram_lo.u_hi.u_ram.mem[5] = 8'h22;
		dut.ch=0;
		dut.regs[9'h006]=8'h28; // (0x0028 >> 3) = widx 5 at reverb_pos 0
		dut.regs[9'h007]=8'h00;
		dut.w_val=16'h4000;
		dut.w_vol=0;
		dut.regs[9'h004]=8'h00;
		dut.rr_addr=0;          // previous clear address deliberately differs
		dut.rr_we=0;
		dut.state=4'd7;         // S_MIX emits rd_addr=widx for the next RMW
		#1;
		if (dut.rd_addr !== 13'd5)
			$fatal(1,"reverb test setup failed rd_addr=%0d",dut.rd_addr);

		pcm_step();
		if (dut.state !== 4'd11)
			$fatal(1,"reverb test setup failed state=%0d",dut.state);

		pcm_step(); // S_RVWR consumes the synchronous RAM result
		if (dut.rr_din !== (16'h2222 + EXPECTED_CONTRIB))
			$fatal(1,"reverb RMW data=%04x expected=%04x",
			       dut.rr_din,16'h2222 + EXPECTED_CONTRIB);

		pcm_step(); // S_NEXT: scheduled write commits at the first raw edge
		if ({dut.u_rram_lo.u_hi.u_ram.mem[5],
		     dut.u_rram_lo.u_lo.u_ram.mem[5]} !==
		    (16'h2222 + EXPECTED_CONTRIB))
			$fatal(1,"reverb RMW target=%04x expected=%04x",
			       {dut.u_rram_lo.u_hi.u_ram.mem[5],dut.u_rram_lo.u_lo.u_ram.mem[5]},
			       16'h2222 + EXPECTED_CONTRIB);
		if ({dut.u_rram_lo.u_hi.u_ram.mem[0],
		     dut.u_rram_lo.u_lo.u_ram.mem[0]} !== 16'h0000)
			$fatal(1,"reverb RMW overwrote stale/source word=%04x",
			       {dut.u_rram_lo.u_hi.u_ram.mem[0],dut.u_rram_lo.u_lo.u_ram.mem[0]});

		$display("PASS tb_bucky_k054539_reverb_rmw target=%0d data=%04x",
		         dut.rr_addr,dut.rr_din);
		$finish;
	end

	wire _unused = &{1'b0,dout,timeout,st_dout,rom_cs,rom_addr,rb_wait,
	                 left,right,rom_data,rom_ok,1'b0};
endmodule
