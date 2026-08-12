`timescale 1ns/1ps

module tb_cowboys_lyro64;
    reg rst=1, clk=0;
    reg [21:0] slot0_addr=0;
    wire [31:0] slot0_dout;
    reg slot0_cs=0;
    wire slot0_ok;
    reg sdram_ack=0;
    wire sdram_rd;
    wire [21:0] sdram_addr;
    reg data_dst=0, data_rdy=0;
    reg [15:0] data_read=0;

    always #5 clk=~clk;

    cowboys_lyro64 #(.SDRAMW(22)) dut(
        .rst(rst), .clk(clk),
        .slot0_addr(slot0_addr), .slot0_dout(slot0_dout),
        .slot0_cs(slot0_cs), .slot0_ok(slot0_ok),
        .sdram_ack(sdram_ack), .sdram_rd(sdram_rd),
        .sdram_addr(sdram_addr), .data_dst(data_dst),
        .data_rdy(data_rdy), .data_read(data_read)
    );

    task fill_line;
        input [21:0] requested;
        input [15:0] w0, w1, w2, w3;
        begin
            @(negedge clk); slot0_addr=requested; slot0_cs=1;
            wait(sdram_rd);
            if (sdram_addr !== {requested[21:2],2'b00})
                $fatal(1,"sprite burst address=%x expected=%x",sdram_addr,{requested[21:2],2'b00});
            @(negedge clk); sdram_ack=1;
            @(negedge clk); sdram_ack=0; data_dst=1; data_rdy=1; data_read=w0;
            @(negedge clk); data_dst=0; data_read=w1;
            @(negedge clk); data_read=w2;
            @(negedge clk); data_read=w3;
            @(negedge clk); data_rdy=0; data_read=0;
            if (!slot0_ok)
                $fatal(1,"sprite cache line did not become valid");
        end
    endtask

    initial begin
        repeat(3) @(posedge clk);
        rst=0;

        fill_line(22'h000100,16'h1111,16'h2222,16'h3333,16'h4444);
        if (slot0_dout !== 32'h2222_1111)
            $fatal(1,"sprite low half=%x",slot0_dout);
        @(negedge clk); slot0_addr=22'h000102;
        #1;
        if (!slot0_ok || slot0_dout !== 32'h4444_3333 || sdram_rd)
            $fatal(1,"sprite high-half cache hit failed ok=%b data=%x rd=%b",slot0_ok,slot0_dout,sdram_rd);

        @(negedge clk); slot0_cs=0;
        fill_line(22'h000104,16'haaaa,16'hbbbb,16'hcccc,16'hdddd);
        if (slot0_dout !== 32'hbbbb_aaaa)
            $fatal(1,"sprite replacement line=%x",slot0_dout);

        $display("PASS tb_cowboys_lyro64 one burst supplies both 32-bit halves");
        $finish;
    end
endmodule
