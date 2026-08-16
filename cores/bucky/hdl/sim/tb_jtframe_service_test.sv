// Focused JTFRAME input-path regression.  The merge block is the final
// active-low boundary consumed by jtbucky_game: keyboard and gamepad sources
// must assert Service/Test independently and a simultaneous assertion must
// not let either signal be lost.
module tb_jtframe_service_test;
    reg clk;
    reg rst = 1'b1;
    always #1 clk = ~clk;

    reg [3:0] board_coin = 4'h0, board_start = 4'h0;
    reg [3:0] key_coin = 4'h0, key_start = 4'h0;
    reg [3:0] joy_coin = 4'h0, joy_start = 4'h0;
    reg [15:0] joy1 = 16'h0000, joy2 = 16'h0000;
    reg [15:0] joy3 = 16'h0000, joy4 = 16'h0000;
    reg [9:0] key_joy1 = 10'h000, key_joy2 = 10'h000;
    reg [9:0] key_joy3 = 10'h000, key_joy4 = 10'h000;
    reg joy_test = 1'b0, key_test = 1'b0;
    reg key_tilt = 1'b0, key_service = 1'b0, joy_service = 1'b0;
    reg [2:0] mouse_but_1p = 3'b000, mouse_but_2p = 3'b000;

    wire [9:0] game_joy1, game_joy2, game_joy3, game_joy4;
    wire [3:0] game_coin, game_start;
    wire game_test, game_tilt, game_service;

    jtframe_merge_keyjoy dut (
        .rst          (rst),
        .clk          (clk),
        .board_coin   (board_coin),
        .board_start  (board_start),
        .key_coin     (key_coin),
        .key_start    (key_start),
        .joy_coin     (joy_coin),
        .joy_start    (joy_start),
        .joy1         (joy1),
        .joy2         (joy2),
        .joy3         (joy3),
        .joy4         (joy4),
        .key_joy1     (key_joy1),
        .key_joy2     (key_joy2),
        .key_joy3     (key_joy3),
        .key_joy4     (key_joy4),
        .joy_test     (joy_test),
        .key_test     (key_test),
        .key_tilt     (key_tilt),
        .key_service  (key_service),
        .joy_service  (joy_service),
        .mouse_but_1p (mouse_but_1p),
        .mouse_but_2p (mouse_but_2p),
        .game_joy1    (game_joy1),
        .game_joy2    (game_joy2),
        .game_joy3    (game_joy3),
        .game_joy4    (game_joy4),
        .game_coin    (game_coin),
        .game_start   (game_start),
        .game_test    (game_test),
        .game_tilt    (game_tilt),
        .game_service (game_service)
    );

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic expect_inputs(input reg want_service, input reg want_test,
                                  input string label);
        begin
            if (game_service !== want_service || game_test !== want_test) begin
                $display("FAIL: %0s service=%b test=%b (expected %b/%b)",
                         label, game_service, game_test,
                         want_service, want_test);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        repeat (2) tick();
        expect_inputs(1'b1, 1'b1, "reset");
        rst = 1'b0;
        tick();
        expect_inputs(1'b1, 1'b1, "idle");

        key_service = 1'b1;
        tick();
        expect_inputs(1'b0, 1'b1, "key service");
        key_service = 1'b0;
        tick();

        joy_service = 1'b1;
        tick();
        expect_inputs(1'b0, 1'b1, "gamepad service");
        joy_service = 1'b0;
        tick();

        key_test = 1'b1;
        tick();
        expect_inputs(1'b1, 1'b0, "key test");
        key_test = 1'b0;
        tick();

        joy_test = 1'b1;
        tick();
        expect_inputs(1'b1, 1'b0, "gamepad test");

        // Both controls may be held together; each remains asserted.
        joy_service = 1'b1;
        key_service = 1'b1;
        key_test = 1'b1;
        tick();
        expect_inputs(1'b0, 1'b0, "both controls");

        $display("PASS: JTFRAME Service/Test merge path");
        $finish;
    end
endmodule
