// Simulation-only normalized completed-access trace for the GX173 68000 bus.
// Compile with tools/diff/mister_bus_trace.sv and +TRACE_FILE=<path>.
module bucky_main_trace_bind(
	input  logic        clk,
	input  logic        rst,
	input  logic        asn,
	input  logic        busn,
	input  logic        dtackn,
	input  logic        rnw,
	input  logic        udsn,
	input  logic        ldsn,
	input  logic [23:1] address_word,
	input  logic [23:1] pc_word,
	input  logic [15:0] read_data,
	input  logic [15:0] write_data
);
	logic accepted_d;
	wire accepted = !asn && !busn && !dtackn;
	wire completed = accepted && !accepted_d;
	wire [23:0] address = {address_word,1'b0};
	wire [1:0] lanes = {!udsn,!ldsn};
	wire [15:0] data = rnw ? read_data : write_data;
	// Use the completed program-fetch tracker in bucky_main rather than a
	// CPU-implementation-specific hierarchy.  The differential model now
	// defaults to the same fx68k implementation used by synthesis, while J68
	// remains available as an explicit diagnostic option.
	wire [31:0] pc_debug = {8'd0,pc_word,1'b0};

	always_ff @(posedge clk or posedge rst) begin
		if (rst) accepted_d <= 1'b0;
		else accepted_d <= accepted;
	end

	function automatic [15:0] device_for(input logic [23:0] a);
		begin
			casez (a)
				24'h000000: device_for=0;
				default: begin
					if      (a<=24'h07ffff) device_for=0;
					else if (a>=24'h080000 && a<=24'h08ffff) device_for=1;
					else if (a>=24'h090000 && a<=24'h09ffff) device_for=2;
					else if (a>=24'h0a0000 && a<=24'h0affff) device_for=3;
					else if (a>=24'h0c0000 && a<=24'h0c003f) device_for=4;
					else if (a>=24'h0c2000 && a<=24'h0c2007) device_for=5;
					else if (a>=24'h0c4000 && a<=24'h0c4001) device_for=5;
					else if (a>=24'h0ca000 && a<=24'h0ca01f) device_for=6;
					else if (a>=24'h0cc000 && a<=24'h0cc01f) device_for=7;
					else if (a>=24'h0ce000 && a<=24'h0ce01f) device_for=8;
					else if (a>=24'h0d0000 && a<=24'h0d001f) device_for=9;
					else if (a>=24'h0d2000 && a<=24'h0d203f) device_for=10;
					else if (a>=24'h0d4000 && a<=24'h0d4001) device_for=11;
					else if (a>=24'h0d6000 && a<=24'h0d601f) device_for=12;
					else if (a>=24'h0d8000 && a<=24'h0d8007) device_for=4;
					else if (a>=24'h0da000 && a<=24'h0dc003) device_for=13;
					else if (a>=24'h0de000 && a<=24'h0de001) device_for=14;
					else if (a>=24'h180000 && a<=24'h183fff) device_for=15;
					else if (a>=24'h184000 && a<=24'h187fff) device_for=16;
					else if (a>=24'h190000 && a<=24'h191fff) device_for=17;
					else if (a>=24'h1b0000 && a<=24'h1b3fff) device_for=18;
					else if (a>=24'h200000 && a<=24'h23ffff) device_for=19;
					else device_for=16'hffff;
				end
			endcase
		end
	endfunction

	mister_bus_trace #(.DATA_BYTES(2)) u_trace(
		.clk(clk), .reset(rst), .completed(completed), .cpu(8'd0),
		.pc(pc_debug), .rnw(rnw), .address({8'd0,address}), .data(data),
		.lanes(lanes), .device(device_for(address))
	);

	bucky_producer_trace u_producer_trace(
		.clk(clk), .reset(rst), .completed(completed), .pc(pc_debug),
		.rnw(rnw), .address(address), .data(data), .lanes(lanes)
	);
endmodule

// Simulation-only strict selected-domain trace.  Every completed main-CPU
// access in each selected window is emitted; sequence numbers count selected
// events only and therefore expose any missing or reordered event directly.
module bucky_producer_trace(
	input logic        clk,
	input logic        reset,
	input logic        completed,
	input logic [31:0] pc,
	input logic        rnw,
	input logic [23:0] address,
	input logic [15:0] data,
	input logic [1:0]  lanes
);
	integer fd;
	integer seq;
	string trace_file;
	logic enabled;
	wire selected = (address >= 24'h080050 && address <= 24'h080068) ||
	                (address >= 24'h080940 && address <= 24'h08094e) ||
	                (address >= 24'h08f000 && address <= 24'h08f006);
	wire [15:0] normalized_data = {
		lanes[1] ? data[15:8] : 8'h00,
		lanes[0] ? data[7:0]  : 8'h00
	};

	initial begin
		enabled = $value$plusargs("EEP_TRACE_FILE=%s", trace_file);
		fd = 0;
		seq = 0;
		if (enabled) begin
			fd = $fopen(trace_file, "w");
			if (fd == 0) $fatal(1, "cannot open producer trace %s", trace_file);
		end
	end

	always @(posedge clk) begin
		if (enabled && !reset && completed && selected) begin
			$fwrite(fd, "{\"domain\":\"eeprom_workram\",\"seq\":%0d,\"event\":\"bus\",\"phase\":\"completed\",\"rw\":\"%s\",\"address\":%0d,\"data\":%0d,\"byte_enable\":%0d,\"width_bits\":16,\"pc\":%0d,\"reset_epoch\":1}\n",
				seq, rnw ? "R" : "W", address, normalized_data, lanes, pc);
			$fflush(fd);
			seq <= seq + 1;
		end
	end

	final begin
		if (fd != 0) begin
			$display("[EEP_TRACE] events=%0d file=%s", seq, trace_file);
			$fflush(fd);
			$fclose(fd);
		end
	end
endmodule

bind bucky_main bucky_main_trace_bind u_bucky_main_trace_bind(
	.clk(clk), .rst(rst), .asn(ASn), .busn(BUSn), .dtackn(dtac_mux),
	.rnw(RnW), .udsn(UDSn), .ldsn(LDSn), .address_word(A),
	.pc_word(pc_last),
	.read_data(cpu_din), .write_data(cpu_dout_68k)
);
