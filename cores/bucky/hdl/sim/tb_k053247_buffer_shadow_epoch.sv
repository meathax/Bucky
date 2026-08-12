`timescale 1ns/1ps

module tb_k053247_buffer_shadow_epoch;
	reg clk=0, rst=1, LHBL=1, flip=0, rd=0;
	reg [7:0] wr_data=0, wr_data2=0, wr_data3=0, wr_data4=0;
	reg [3:0] wr_addr=0, wr_addr2=1, wr_addr3=2, wr_addr4=3, rd_addr=0;
	reg we=0, we2=0, we3=0, we4=0;
	wire [7:0] rd_data;
	integer failures=0;

	always #5 clk=~clk;

	k053247_buffer #(
		.DW(8),.AW(4),.ALPHAW(4),.ALPHA(0),.BLANK(0),
		.BLANK_DLY(2),.SW(2),.SHADOW_PEN(15),.SHADOW(1)
	) dut(
		.rst(rst),.clk(clk),.LHBL(LHBL),.flip(flip),
		.wr_data(wr_data),.wr_addr(wr_addr),.we(we),
		.wr_data2(wr_data2),.wr_addr2(wr_addr2),.we2(we2),
		.wr_data3(wr_data3),.wr_addr3(wr_addr3),.we3(we3),
		.wr_data4(wr_data4),.wr_addr4(wr_addr4),.we4(we4),
		.rd_addr(rd_addr),.rd(rd),.rd_data(rd_data)
	);

	task line_flip;
		begin
			@(negedge clk); LHBL=0;
			@(posedge clk); #1;
			@(negedge clk); LHBL=1;
		end
	endtask

	task read_expect;
		input [3:0] a;
		input [1:0] expected_shadow;
		begin
			@(negedge clk); rd_addr=a; rd=1;
			@(negedge clk); rd=0;
			repeat(2) @(posedge clk); #1;
			if(rd_data[7:6]!==expected_shadow) begin
				$display("FAIL addr=%0d expected shadow=%0d actual=%0d data=%02x line=%0d",
					a,expected_shadow,rd_data[7:6],rd_data,dut.line);
				failures=failures+1;
			end
		end
	endtask

	initial begin
		repeat(2) @(posedge clk); rst=0;

		// A settled shadow write belongs to the current producer bank and
		// must appear when that bank becomes the displayed line.
		@(negedge clk); wr_addr=4'd4; wr_data=8'h4f; we=1;
		@(negedge clk); we=0;
		repeat(2) @(posedge clk);
		line_flip();
		read_expect(4'd4,2'd1);

		// Present a shadow write on the exact bank-flip edge.  Its one-cycle
		// RMW control must not follow the new line selector and leak into the
		// following line.  The old RTL wrote this into the wrong ping-pong RAM.
		@(negedge clk); wr_addr=4'd8; wr_data=8'h4f; we=1; LHBL=0;
		@(posedge clk); #1;
		@(negedge clk); we=0; LHBL=1;
		repeat(2) @(posedge clk);
		line_flip();
		read_expect(4'd8,2'd0);

		if(failures!=0) $fatal(1,"K053247 shadow epoch failures=%0d",failures);
		$display("PASS tb_k053247_buffer_shadow_epoch");
		$finish;
	end
endmodule
