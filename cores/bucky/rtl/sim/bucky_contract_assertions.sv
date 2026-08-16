// Simulation-only GX173 invariants.  This file is intentionally absent from
// cfg/files.yaml and is added only by the parent verification build.
module bucky_main_contract_assertions(
	input logic clk, rst, asn, busn, rnw, udsn, ldsn,
	input logic [23:1] address_word,
	input logic rom_cs, ram_cs, obj_cs, vram_cs, pal_cs, romrd_cs,
	input logic tilereg_cs, tilereg_b_cs, alpha_cs, pcu_cs, objreg_cs,
	input logic prot_cs, ccu_cs, collision_cs, sndirq_cs, pair_cs,
	input logic in0_cs, in1_cs, p1p3_cs, p2p4_cs, control2_cs,
	input logic pair_we,
	input logic irq5_ack, irq4_ack,
	input logic [2:0] ipln,
	input logic irq5_q, irq4_q,
	input logic [2:0] fcn
);
	logic irq5_ack_d, irq4_ack_d;
	wire accepted = !asn && !busn;
	wire [23:0] address = {address_word,1'b0};
	wire [21:0] selects = {rom_cs,ram_cs,obj_cs,vram_cs,pal_cs,romrd_cs,
		tilereg_cs,tilereg_b_cs,alpha_cs,pcu_cs,objreg_cs,prot_cs,ccu_cs,
		collision_cs,sndirq_cs,pair_cs,in0_cs,in1_cs,p1p3_cs,p2p4_cs,
		control2_cs,1'b0};

	always_ff @(posedge clk) if (!rst && accepted) begin
		assert ($onehot0(selects))
			else $fatal(1,"GX173 overlapping decode address=%06x selects=%h",address,selects);
		// Upper-only writes to low-byte devices are legal 68000 cycles but
		// must be ignored.  Check the explicit K054321 write enable rather
		// than rejecting the bus transaction itself.
		assert (pair_we == (pair_cs && !rnw && !ldsn))
			else $fatal(1,"K054321 byte-lane write-enable mismatch");
		if (address>=24'h0ce000 && address<=24'h0ce01f && !rnw)
			assert (!udsn || !ldsn) else $fatal(1,"protection write has no active byte lane");
	end

	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			irq5_ack_d <= 1'b0;
			irq4_ack_d <= 1'b0;
		end else begin
			assert (!(irq5_ack && irq4_ack)) else $fatal(1,"simultaneous IRQ4/IRQ5 acknowledge");
			// A 68000 interrupt acknowledge keeps AS low for multiple clocks.
			// Validate the request level only on the acknowledge edge; later
			// held cycles legitimately see the request latch already cleared.
			if (irq5_ack && !irq5_ack_d) assert (ipln==3'b010)
			else $fatal(1,"IRQ5 ack while IPL is not level 5 ipln=%b q5=%b q4=%b fc=%b A=%06x",
				ipln, irq5_q, irq4_q, fcn, address);
			if (irq4_ack && !irq4_ack_d) assert (ipln==3'b011)
			else $fatal(1,"IRQ4 ack while IPL is not level 4 ipln=%b q5=%b q4=%b fc=%b A=%06x",
				ipln, irq5_q, irq4_q, fcn, address);
			irq5_ack_d <= irq5_ack;
			irq4_ack_d <= irq4_ack;
		end
	end
endmodule

bind bucky_main bucky_main_contract_assertions u_bucky_main_contract_assertions(
	.clk(clk),.rst(rst),.asn(ASn),.busn(BUSn),.rnw(RnW),.udsn(UDSn),.ldsn(LDSn),
	.address_word(A),.rom_cs(rom_cs),.ram_cs(ram_cs),.obj_cs(obj_cs),
	.vram_cs(vram_cs),.pal_cs(pal_cs),.romrd_cs(romrd_cs),
	.tilereg_cs(tilereg_cs),.tilereg_b_cs(tilereg_b_cs),.alpha_cs(alpha_cs),
	.pcu_cs(pcu_cs),.objreg_cs(objreg_cs),.prot_cs(prot_cs),.ccu_cs(ccu_cs),
	.collision_cs(collision_cs),.sndirq_cs(sndirq_cs),.pair_cs(pair_cs),
	.in0_cs(in0_cs),.in1_cs(in1_cs),.p1p3_cs(p1p3_cs),.p2p4_cs(p2p4_cs),
	.control2_cs(control2_cs),.pair_we(pair_we),
	.irq5_ack(irq5_ack),.irq4_ack(irq4_ack),.ipln(IPLn),
	.irq5_q(irq5_q),.irq4_q(irq4_q),.fcn(FC)
);

module bucky_dma_contract_assertions(
	input logic clk, rst, pxl2_cen, hs, lvbl, dma_bsy, dma_clr, dma_ok,
	input logic [13:1] dma_addr,
	input logic [11:1] dma_wr_addr,
	input logic dma_weh, dma_wel
);
	logic dma_bsy_d, lvbl_d;
	logic [31:0] frame_epoch, launch_epoch;
	logic launch_valid;

	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			dma_bsy_d<=0; lvbl_d<=1; frame_epoch<=0; launch_epoch<=0; launch_valid<=0;
		end else if (pxl2_cen) begin
			dma_bsy_d <= dma_bsy;
			lvbl_d <= lvbl;
			if (lvbl_d && !lvbl) frame_epoch <= frame_epoch + 1;
			if (!dma_bsy_d && dma_bsy) begin
				assert (!launch_valid) else $fatal(1,"sprite DMA relaunched while prior epoch is in flight");
				launch_epoch <= frame_epoch;
				launch_valid <= 1;
			end
			if (dma_bsy_d && !dma_bsy) begin
				assert (launch_valid) else $fatal(1,"sprite DMA completion without an owner epoch");
				assert (launch_epoch==frame_epoch)
					else $fatal(1,"late sprite DMA completion launch_epoch=%0d frame_epoch=%0d",launch_epoch,frame_epoch);
				launch_valid <= 0;
			end
			if (dma_weh || dma_wel) begin
				assert (dma_bsy) else $fatal(1,"sprite buffer write outside in-flight DMA");
				assert (!(dma_weh && dma_wel)) else $fatal(1,"sprite even/odd buffers written together");
				if (!dma_clr && dma_ok)
					assert (dma_wr_addr[3:1] <= 3'd6) else $fatal(1,"sprite DMA wrote skipped word 7");
			end
		end
	end
endmodule

bind k053246_dma bucky_dma_contract_assertions u_bucky_dma_contract_assertions(
	.clk(clk),.rst(rst),.pxl2_cen(pxl2_cen),.hs(hs),.lvbl(lvbl),
	.dma_bsy(dma_bsy),.dma_clr(dma_clr),.dma_ok(dma_ok),.dma_addr(dma_addr),
	.dma_wr_addr(dma_wr_addr),.dma_weh(dma_weh),.dma_wel(dma_wel)
);

// JTFRAME SDRAM clients must hold a request and its address until the
// controller acknowledges the returned word.  These assertions are bound only
// in simulation and catch the exact failure mode that turns a late tile read
// into a stale line-buffer pixel when the SDRAM clock/latency changes.
module bucky_video_sdram_contract_assertions(
	input logic clk, rst,
	input logic [18:0] tile_addr,
	input logic tile_cs, tile_ok,
	input logic [20:0] sprite_addr,
	input logic sprite_cs, sprite_ok
);
	logic tile_pending, sprite_pending;
	logic [18:0] tile_addr_q;
	logic [20:0] sprite_addr_q;

	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			tile_pending   <= 1'b0;
			sprite_pending <= 1'b0;
			tile_addr_q   <= '0;
			sprite_addr_q <= '0;
		end else begin
			if (tile_pending) begin
				if (tile_ok) tile_pending <= 1'b0;
				else begin
					assert (tile_cs)
						else $fatal(1, "K056832 SDRAM request dropped before ok");
					assert (tile_addr == tile_addr_q)
						else $fatal(1, "K056832 SDRAM address changed before ok");
				end
			end
			if (sprite_pending) begin
				if (sprite_ok) sprite_pending <= 1'b0;
				else begin
					assert (sprite_cs)
						else $fatal(1, "K053246 SDRAM request dropped before ok");
					assert (sprite_addr == sprite_addr_q)
						else $fatal(1, "K053246 SDRAM address changed before ok");
				end
			end
			// JTFRAME's ROM slots default to OKLATCH=1.  The acknowledge may
			// therefore be presented one cycle after the requester drops cs.
			// Only the requester's stability while waiting is asserted here;
			// an isolated ok pulse can be a cache-hit response.

			if (tile_cs && !tile_pending) tile_addr_q <= tile_addr;
			if (sprite_cs && !sprite_pending) sprite_addr_q <= sprite_addr;
			if (tile_cs && !tile_ok && !tile_pending) tile_pending <= 1'b1;
			if (tile_cs && tile_ok && !tile_pending) tile_pending <= 1'b0;
			if (sprite_cs && !sprite_ok && !sprite_pending) sprite_pending <= 1'b1;
			if (sprite_cs && sprite_ok && !sprite_pending) sprite_pending <= 1'b0;
		end
	end
endmodule

bind bucky_video bucky_video_sdram_contract_assertions u_bucky_video_sdram_contract_assertions(
	.clk(clk), .rst(rst),
	.tile_addr(scr_addr), .tile_cs(scr_cs), .tile_ok(scr_ok),
	.sprite_addr(lyro_addr), .sprite_cs(lyro_cs), .sprite_ok(lyro_ok)
);

// The CPU is clocked at clk48 while the generated JTFRAME SDRAM bank runs at
// clk.  At the synchronous boundary the 68000 request must remain owned until
// the bank returns its (possibly OKLATCH-delayed) acknowledgement.
module bucky_main_sdram_boundary_assertions(
	input logic clk, rst,
	input logic [20:1] main_addr,
	input logic main_cs, main_ok
);
	logic pending;
	logic [20:1] addr_q;

	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			pending <= 1'b0;
			addr_q  <= '0;
		end else begin
			if (pending) begin
				if (main_ok) pending <= 1'b0;
				else begin
					assert (main_cs)
						else $fatal(1, "main SDRAM request dropped before ok");
					assert (main_addr == addr_q)
						else $fatal(1, "main SDRAM address changed before ok");
				end
			end
			if (main_cs && !pending)
				addr_q <= main_addr;
			if (main_cs && !main_ok && !pending)
				pending <= 1'b1;
			if (main_cs && main_ok && !pending)
				pending <= 1'b0;
		end
	end
endmodule

bind jtbucky_game_sdram bucky_main_sdram_boundary_assertions u_bucky_main_sdram_boundary_assertions(
	.clk(clk), .rst(rst), .main_addr(main_addr), .main_cs(main_cs), .main_ok(main_ok)
);
