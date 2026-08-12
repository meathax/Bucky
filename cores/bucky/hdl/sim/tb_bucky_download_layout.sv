`timescale 1ns/1ps

// Proves the release MRA header contract at the real JTFRAME downloader
// boundary.  Bucky uses four non-XL SDRAM banks; with BALUT_LEN=5 the fifth
// boundary is PROM start, not a fifth SDRAM bank.  PCM therefore belongs
// behind the 256 KiB sound ROM in bank 1.
module tb_bucky_download_layout;
	localparam [26:0] HEADER_LEN = 27'd16;

	reg clk = 0;
	reg ioctl_rom = 1;
	reg [26:0] ioctl_addr = 0;
	reg [7:0] ioctl_dout = 0;
	reg ioctl_wr = 0;
	wire [22:1] prog_addr;
	wire [15:0] prog_data;
	wire [1:0] prog_mask;
	wire prog_we, prog_rd;
	wire [1:0] prog_ba;
	wire prom_we, header;

	always #5 clk = ~clk;

	jtframe_dwnld #(
		.SDRAMW(23),
		.HEADER(HEADER_LEN),
		.BALUT(1),
		.BALUT_LEN(5),
		.BALUT_REVERSE(1),
		.LUTSH(12),
		.SWAB(1),
		.XL(0)
	) dut (
		.clk(clk), .ioctl_rom(ioctl_rom), .ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout), .ioctl_wr(ioctl_wr),
		.prog_addr(prog_addr), .prog_data(prog_data),
		.prog_mask(prog_mask), .prog_we(prog_we), .prog_rd(prog_rd),
		.prog_ba(prog_ba), .gfx4_en(1'b0), .gfx8_en(1'b0),
		.gfx16_en(1'b0), .gfx16b_en(1'b0), .gfx16c_en(1'b0),
		.prom_we(prom_we), .header(header), .sdram_ack(1'b1)
	);

	task write_header;
		input [4:0] index;
		input [7:0] value;
		begin
			@(negedge clk);
			ioctl_addr = {22'd0, index};
			ioctl_dout = value;
			ioctl_wr = 1;
			@(posedge clk); #1;
			if (!header)
				$fatal(1, "header byte %0d was not decoded as header", index);
			@(negedge clk);
			ioctl_wr = 0;
		end
	endtask

	task check_sdram_byte;
		input [26:0] stream_addr;
		input [1:0] expected_bank;
		input [21:0] expected_word;
		input [1:0] expected_mask;
		begin
			@(negedge clk);
			ioctl_addr = HEADER_LEN + stream_addr;
			ioctl_dout = 8'ha5;
			ioctl_wr = 1;
			@(posedge clk); #1;
			if (!prog_we || prom_we || prog_ba !== expected_bank ||
			    prog_addr !== expected_word || prog_mask !== expected_mask)
				$fatal(1,
				       "stream=%07x prog_we=%b prom_we=%b bank=%0d word=%06x mask=%b expected bank=%0d word=%06x mask=%b",
				       stream_addr, prog_we, prom_we, prog_ba, prog_addr,
				       prog_mask, expected_bank, expected_word, expected_mask);
			@(negedge clk);
			ioctl_wr = 0;
			@(posedge clk); #1;
			if (prog_we || prom_we)
				$fatal(1, "download write did not clear");
		end
	endtask

	task check_prom_byte;
		input [26:0] stream_addr;
		begin
			@(negedge clk);
			ioctl_addr = HEADER_LEN + stream_addr;
			ioctl_dout = 8'h5a;
			ioctl_wr = 1;
			@(posedge clk); #1;
			if (prog_we || !prom_we)
				$fatal(1, "stream=%07x expected PROM routing prog_we=%b prom_we=%b",
				       stream_addr, prog_we, prom_we);
			@(negedge clk);
			ioctl_wr = 0;
			@(posedge clk); #1;
		end
	endtask

	initial begin
		repeat (2) @(negedge clk);

		// Little-endian 12-bit-unit boundaries from the corrected MRA:
		// 0x000000, 0x240000, 0x680000, 0x880000, 0x1080000.
		write_header(0, 8'h00); write_header(1, 8'h00);
		write_header(2, 8'h40); write_header(3, 8'h02);
		write_header(4, 8'h80); write_header(5, 8'h06);
		write_header(6, 8'h80); write_header(7, 8'h08);
		write_header(8, 8'h80); write_header(9, 8'h10);

		// PCM offsets 0, 0x1fffff, 0x200000 and 0x3fffff all remain
		// in bank 1 after its 0x40000-byte sound-ROM prefix.
		check_sdram_byte(27'h0280000, 2'd1, 22'h020000, 2'b10);
		check_sdram_byte(27'h047ffff, 2'd1, 22'h11ffff, 2'b01);
		check_sdram_byte(27'h0480000, 2'd1, 22'h120000, 2'b10);
		check_sdram_byte(27'h067ffff, 2'd1, 22'h21ffff, 2'b01);

		check_sdram_byte(27'h0680000, 2'd2, 22'h000000, 2'b10);
		check_sdram_byte(27'h0880000, 2'd3, 22'h000000, 2'b10);
		check_prom_byte (27'h1080000);

		$display("PASS tb_bucky_download_layout PCM routes to SDRAM bank 1");
		$finish;
	end

	wire _unused = &{1'b0, prog_data, prog_rd, 1'b0};
endmodule
