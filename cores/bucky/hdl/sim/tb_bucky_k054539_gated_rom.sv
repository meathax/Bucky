`timescale 1ns/1ps

module tb_bucky_k054539_gated_rom;
	reg rst=1, clk=0, cen_source=0;
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

	// This is the integration contract used by generated
	// jtbucky_game_sdram: a pending PCM request gates the K054539 enable.
	// Consequently the sequencer cannot execute its default CS clear until
	// the shared-ROM response arrives.
	wire cen = cen_source && !(rom_cs && !rom_ok);

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

	integer delay_clocks;
	reg [23:0] request_addr;
	initial begin
		repeat(3) @(posedge clk);
		rst=0;

		// One 8-bit voice advances exactly one byte at the first sample.
		wr(9'h000,8'h00);
		wr(9'h001,8'h00);
		wr(9'h002,8'h01);
		wr(9'h003,8'h00);
		wr(9'h005,8'h18);
		wr(9'h100,8'h00);
		wr(9'h12f,8'h11);
		wr(9'h114,8'h01);

		cen_source=1;
		wait(rom_cs);
		#1 request_addr=rom_addr;

		// Model prolonged bank contention in master-clock time. The request
		// and its byte address must remain continuously presented throughout.
		for (delay_clocks=0; delay_clocks<20; delay_clocks=delay_clocks+1) begin
			@(posedge clk); #1;
			if (cen !== 1'b0)
				$fatal(1,"gated PCM enable advanced during pending request");
			if (!rom_cs || rom_addr !== request_addr)
				$fatal(1,"PCM request changed before rom_ok cs=%b addr=%06x expected=%06x",
				       rom_cs,rom_addr,request_addr);
		end

		@(negedge clk); rom_ok=1; rom_data=8'h01;
		@(posedge clk); #1;
		rom_ok=0;
		if (rom_cs)
			$fatal(1,"PCM request did not retire after rom_ok");
		if (dut.state !== 4'd2)
			$fatal(1,"PCM sequencer did not consume response state=%0d",dut.state);

		$display("PASS tb_bucky_k054539_gated_rom delay_clocks=%0d addr=%06x",
		         delay_clocks,request_addr);
		$finish;
	end

	wire _unused = &{1'b0,dout,timeout,st_dout,rb_wait,left,right,1'b0};
endmodule
