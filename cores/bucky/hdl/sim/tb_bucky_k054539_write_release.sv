`timescale 1ns/1ps

module tb_bucky_k054539_write_release;
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

	task fail;
		input [8*96-1:0] message;
		begin
			$display("FAIL K054539 write-release: %0s",message);
			failures=failures+1;
		end
	endtask

	initial begin
		repeat(3) @(posedge clk);
		rst=0;
		@(negedge clk);

		// Ordinary REG8 storage in the decapped chip is transparent while its
		// decoded active-low write enable is asserted.  It must not inherit the
		// release phase needed by edge-triggered side effects below.
		addr=9'h003; din=8'h5a; cs=1; we=1;
		@(posedge clk); #1;
		if (dut.regs[9'h003] !== 8'h5a)
			fail("ordinary register write was delayed until /WR release");
		@(negedge clk); cs=0; we=0;
		@(posedge clk); #1;

		// Global control bits 0/1/4/5 use posedge nWR22F in SiliconRE. They
		// remain at the old value throughout a held write and change atomically
		// on release, so S_LOAD cannot observe a partially committed control.
		@(negedge clk);
		dut.regs[9'h12f]=8'h00;
		addr=9'h12f; din=8'h11; cs=1; we=1;
		repeat(4) @(posedge clk);
		#1;
		if (dut.regs[9'h12f] !== 8'h00)
			fail("0x22f release-edge control bits changed before /WR release");
		@(negedge clk); cs=0; we=0;
		@(posedge clk); #1;
		if (dut.regs[9'h12f] !== 8'h11)
			fail("0x22f control did not commit on /WR release");
		@(negedge clk);
		addr=9'h12f; din=8'h80; cs=1; we=1;
		@(posedge clk); #1;
		if (dut.regs[9'h12f] !== 8'h91)
			fail("0x22f D7 was not transparent while /WR active");
		@(negedge clk); cs=0; we=0;
		@(posedge clk); #1;

		// Odd per-channel control has a hybrid physical latch: D2/D4/D5 are
		// transparent during nODDWR, while loop-enable D0 captures on release.
		@(negedge clk);
		dut.regs[9'h101]=8'h00;
		addr=9'h101; din=8'h15; cs=1; we=1;
		repeat(3) @(posedge clk);
		#1;
		if (dut.regs[9'h101] !== 8'h14)
			fail("odd control transparent fields/release D0 phase is wrong");
		@(negedge clk); cs=0; we=0;
		@(posedge clk); #1;
		if (dut.regs[9'h101] !== 8'h15)
			fail("odd control D0 did not commit on /WR release");

		// Key-off is level-visible throughout its active decoded strobe in the
		// decapped start/stop block, and is not duplicated at release.
		@(negedge clk);
		dut.regs[9'h12f]=8'h01;
		dut.active=8'h01;
		addr=9'h115; din=8'h01; cs=1; we=1;
		@(posedge clk); #1;
		if (dut.active[0])
			fail("key-off was not accepted at /WR assertion");
		repeat(3) @(posedge clk);
		#1;
		if (dut.active[0])
			fail("held key-off did not keep the channel inactive");
		// 0x115 is outside the 0x101..0x10f odd-control bank. Its register D0
		// must remain ordinary/transparent rather than gaining a release write.
		if (dut.regs[9'h115][0] !== 1'b1)
			fail("0x115 was misdecoded as odd channel-control storage");
		@(negedge clk); cs=0; we=0;
		dut.active=8'h01;
		@(posedge clk); #1;
		if (!dut.active[0])
			fail("key-off was duplicated at /WR release");

		// SiliconRE's ADDRCNT advances on posedge nACCESS22D: one CPU
		// transaction is committed when /WR is released, irrespective of how
		// many 48 MHz clocks the Z80 holds it low.  Seed four words so repeated
		// byte writes and pointer advances are both directly visible.
		@(negedge clk);
		dut.regs[9'h12e]=8'h80;
		dut.read_ptr=0;
		dut.u_rram_lo.u_lo.u_ram.mem[0]=8'h11;
		dut.u_rram_lo.u_hi.u_ram.mem[0]=8'h22;
		dut.u_rram_lo.u_lo.u_ram.mem[1]=8'h33;
		dut.u_rram_lo.u_hi.u_ram.mem[1]=8'h44;
		dut.u_rram_lo.u_lo.u_ram.mem[2]=8'h55;
		dut.u_rram_lo.u_hi.u_ram.mem[2]=8'h66;
		dut.u_rram_lo.u_lo.u_ram.mem[3]=8'h77;
		dut.u_rram_lo.u_hi.u_ram.mem[3]=8'h88;
		addr=9'h12d; din=8'ha5; cs=1; we=1;
		repeat(8) @(posedge clk);
		#1;
		if (dut.read_ptr !== 17'd0)
			fail("0x22d pointer advanced before /WR release");
		if (dut.regs[9'h12d][0] !== 1'b1)
			fail("0x22d was misdecoded as odd channel-control storage");
		if ({dut.u_rram_lo.u_hi.u_ram.mem[3],dut.u_rram_lo.u_lo.u_ram.mem[3],
		     dut.u_rram_lo.u_hi.u_ram.mem[2],dut.u_rram_lo.u_lo.u_ram.mem[2],
		     dut.u_rram_lo.u_hi.u_ram.mem[1],dut.u_rram_lo.u_lo.u_ram.mem[1],
		     dut.u_rram_lo.u_hi.u_ram.mem[0],dut.u_rram_lo.u_lo.u_ram.mem[0]}
		    !== 64'h8877665544332211)
			fail("held 0x22d write changed RAM before /WR release");
		@(negedge clk); cs=0; we=0;
		@(posedge clk); #1;
		if (dut.read_ptr !== 17'd1)
			fail("one held 0x22d transaction did not advance pointer exactly once");
		if ({dut.u_rram_lo.u_hi.u_ram.mem[3],dut.u_rram_lo.u_lo.u_ram.mem[3],
		     dut.u_rram_lo.u_hi.u_ram.mem[2],dut.u_rram_lo.u_lo.u_ram.mem[2],
		     dut.u_rram_lo.u_hi.u_ram.mem[1],dut.u_rram_lo.u_lo.u_ram.mem[1],
		     dut.u_rram_lo.u_hi.u_ram.mem[0],dut.u_rram_lo.u_lo.u_ram.mem[0]}
		    !== 64'h88776655443322a5)
			fail("one held 0x22d transaction did not change exactly one byte");

		// The decapped chip similarly captures key-on at posedge nKONWR. Hold
		// the bus across an in-flight S_LOAD: no request or position commit may
		// occur while /WR is asserted; release creates one request, and the next
		// S_LOAD consumes it permanently rather than the held level re-arming it.
		@(negedge clk);
		dut.regs[9'h12f]=8'h01; // PCM enabled + UPDATE_AT_KEYON
		dut.regs[9'h00c]=8'h33;
		dut.regs[9'h00d]=8'h22;
		dut.regs[9'h00e]=8'h11;
		dut.pos_latch[0]=8'hbc;
		dut.pos_latch[1]=8'h9a;
		dut.pos_latch[2]=8'h78;
		dut.active=8'h01;
		dut.restart=8'h00;
		dut.ch=0;
		dut.cpos[0]=24'h012345;
		addr=9'h114; din=8'h01; cs=1; we=1;
		repeat(3) @(posedge clk);
		@(negedge clk); dut.state=4'd1; cen=1;
		@(posedge clk); #1; cen=0;
		repeat(3) @(posedge clk);
		#1;
		if (dut.restart[0])
			fail("held key-on armed or re-armed restart before /WR release");
		if ({dut.regs[9'h00e],dut.regs[9'h00d],dut.regs[9'h00c]} !== 24'h112233)
			fail("held key-on committed position before /WR release");

		@(negedge clk); cs=0; we=0;
		@(posedge clk); #1;
		if (!dut.restart[0])
			fail("key-on release did not arm exactly one restart");
		if ({dut.regs[9'h00e],dut.regs[9'h00d],dut.regs[9'h00c]} !== 24'h789abc)
			fail("key-on release did not commit the latched start position");

		@(negedge clk); dut.state=4'd1; cen=1;
		@(posedge clk); #1; cen=0;
		if (dut.restart[0])
			fail("next S_LOAD did not consume the released key-on");
		repeat(4) @(posedge clk);
		if (dut.restart[0])
			fail("released key-on re-armed after its one S_LOAD consumption");

		if (failures != 0)
			$fatal(1,"K054539 write-release failures=%0d",failures);
		$display("PASS tb_bucky_k054539_write_release pointer=%0d position=%06x",
		         dut.read_ptr,{dut.regs[9'h00e],dut.regs[9'h00d],dut.regs[9'h00c]});
		$finish;
	end

	wire _unused = &{1'b0,dout,timeout,st_dout,rom_cs,rom_addr,rb_wait,
	                 left,right,rom_data,rom_ok,rd,1'b0};
endmodule
