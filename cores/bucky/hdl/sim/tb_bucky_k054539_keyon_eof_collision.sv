`timescale 1ns/1ps

module tb_bucky_k054539_keyon_eof_collision;
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

	task eof_case;
		input [3:0] eof_state;
		input [7:0] eof_data;
		input [1:0] sample_type;
		begin
			@(negedge clk);
			dut.active=8'h01;
			dut.restart=8'h01; // earlier key-on queued after this voice's S_LOAD
			dut.ch=0;
			dut.state=eof_state;
			dut.w_type=sample_type;
			dut.w_lo=8'h00;
			dut.w_loopen=0;
			dut.regs[9'h12f]=8'h01;
			dut.regs[9'h00c]=8'hbc;
			dut.regs[9'h00d]=8'h9a;
			dut.regs[9'h00e]=8'h78;
			dut.regs[9'h100]=(sample_type==2'd0) ? 8'h00 :
			                   (sample_type==2'd1) ? 8'h04 : 8'h08;
			rom_data=eof_data;
			rom_ok=1;
			cen=1;
			@(posedge clk); #1;
			rom_ok=0; cen=0;
			if (!dut.active[0] || !dut.restart[0])
				$fatal(1,"queued key-on lost at EOF state=%0d active=%b restart=%b",
				       eof_state,dut.active[0],dut.restart[0]);

			// Advance the retired old voice to its next S_LOAD and prove the
			// queued replacement start is consumed from the committed position.
			@(negedge clk); dut.state=4'd1; cen=1;
			@(posedge clk); #1; cen=0;
			if (dut.restart[0])
				$fatal(1,"queued key-on was not consumed at next S_LOAD state=%0d",eof_state);
			if ((sample_type==2'd2 && dut.w_pos !== {24'h789abc,1'b0}) ||
			    (sample_type!=2'd2 && dut.w_pos !== {1'b0,24'h789abc}))
				$fatal(1,"queued key-on loaded wrong position state=%0d pos=%07x",
				       eof_state,dut.w_pos);
		end
	endtask

	initial begin
		repeat(3) @(posedge clk);
		rst=0;
		eof_case(4'd3,8'h80,2'd0); // 8-bit EOF
		eof_case(4'd5,8'h80,2'd1); // 16-bit 0x8000 EOF (w_lo=0)
		eof_case(4'd6,8'h88,2'd2); // DPCM EOF
		$display("PASS tb_bucky_k054539_keyon_eof_collision");
		$finish;
	end

	wire _unused = &{1'b0,dout,timeout,st_dout,rom_cs,rom_addr,rb_wait,
	                 left,right,1'b0};
endmodule
