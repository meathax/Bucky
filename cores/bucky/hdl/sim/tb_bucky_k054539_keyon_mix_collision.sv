`timescale 1ns/1ps

module tb_bucky_k054539_keyon_mix_collision;
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

	always #5 clk=~clk;

	k054539 dut(
		.rst(rst), .clk(clk), .cen(cen), .timeout(timeout),
		.addr(addr), .we(we), .rd(rd), .cs(cs), .din(din), .dout(dout),
		.rom_cs(rom_cs), .rom_addr(rom_addr), .rom_data(rom_data), .rom_ok(rom_ok),
		.rb_wait(rb_wait),
		.left(left), .right(right), .debug_bus(8'h00), .st_dout(st_dout)
	);

	task expect_position;
		input [23:0] expected;
		input [8*32-1:0] label;
		begin
			if ({dut.regs[9'h00e],dut.regs[9'h00d],dut.regs[9'h00c]} !== expected)
				$fatal(1,"%0s position actual=%06x expected=%06x",label,
				       {dut.regs[9'h00e],dut.regs[9'h00d],dut.regs[9'h00c]},expected);
		end
	endtask

	initial begin
		repeat(3) @(posedge clk);
		rst=0;
		@(negedge clk);

		// UPDATE_AT_KEYON is active. Model an old voice reaching S_MIX on
		// the exact master-clock edge where the Z80 releases /WR and the
		// physical chip commits a new start.
		dut.regs[9'h12f]=8'h01;
		dut.regs[9'h00c]=8'h45;
		dut.regs[9'h00d]=8'h23;
		dut.regs[9'h00e]=8'h01;
		dut.active=8'h01;
		dut.ch=0;
		dut.state=4'd0;
		dut.w_type=0;
		dut.w_pos=25'h0012345;
		dut.w_pfrac=0;
		dut.w_val=0;
		dut.w_pval=0;
		dut.pos_latch[0]=8'hbc;
		dut.pos_latch[1]=8'h9a;
		dut.pos_latch[2]=8'h78;
		addr=9'h114;
		din=8'h01;
		cs=1;
		we=1;
		cen=0;

		repeat(3) @(posedge clk);
		#1;
		if (dut.restart[0])
			$fatal(1,"held key-on armed before /WR release");
		expect_position(24'h012345,"held key-on before release");
		@(negedge clk);
		cs=0; we=0; cen=1;
		dut.state=4'd7;       // release commit collides with old S_MIX
		@(posedge clk); #1;
		cen=0;
		expect_position(24'h789abc,"same-clock key-on/S_MIX");
		if (!dut.restart[0] || !dut.active[0])
			$fatal(1,"same-clock key-on did not arm active/restart");

		// The same priority is required when key-on occurs earlier in the
		// channel's in-flight window. restart remains armed until the next
		// S_LOAD, so a later S_MIX must preserve the committed new start.
		@(negedge clk);
		dut.regs[9'h00c]=8'h56;
		dut.regs[9'h00d]=8'h34;
		dut.regs[9'h00e]=8'h12;
		dut.restart=8'h01;
		dut.state=4'd7;
		dut.w_pos=25'h000cdef;
		cen=1;
		@(posedge clk); #1; cen=0;
		expect_position(24'h123456,"pending-restart S_MIX");

		// With no pending retrigger, the live-position mirror remains normal.
		@(negedge clk);
		dut.restart=8'h00;
		dut.state=4'd7;
		dut.w_pos=25'h0013579;
		cen=1;
		@(posedge clk); #1; cen=0;
		expect_position(24'h013579,"ordinary S_MIX");

		$display("PASS tb_bucky_k054539_keyon_mix_collision position=%06x",
		         {dut.regs[9'h00e],dut.regs[9'h00d],dut.regs[9'h00c]});
		$finish;
	end

	wire _unused = &{1'b0,dout,timeout,st_dout,rom_cs,rom_addr,rb_wait,
	                 left,right,rom_data,rom_ok,1'b0};
endmodule
