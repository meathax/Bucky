// Testbench-only bounded completed-bus trace template.
// Instantiate or bind it to the core's accepted/completed transaction boundary.

module mister_bus_trace #(
    parameter string TRACE_FILE = "hdl-trace.jsonl",
    parameter integer DATA_BYTES = 2,
    parameter integer MAX_EVENTS = 100000
) (
    input  logic                         clk,
    input  logic                         reset,
    input  logic                         completed,
    input  logic [7:0]                   cpu,
    input  logic [31:0]                  pc,
    input  logic                         rnw,
    input  logic [31:0]                  address,
    input  logic [(DATA_BYTES*8)-1:0]    data,
    input  logic [DATA_BYTES-1:0]        lanes,
    input  logic [15:0]                  device
);
    integer fd;
    integer event_count;
    integer lane;
    logic [(DATA_BYTES*8)-1:0] normalized_data;
    string selected_file;

    initial begin
        selected_file = TRACE_FILE;
        void'($value$plusargs("TRACE_FILE=%s", selected_file));
        fd = $fopen(selected_file, "w");
        if (fd == 0)
            $fatal(1, "cannot open trace file %s", selected_file);
        event_count = 0;
    end

    always_comb begin
        normalized_data = '0;
        for (lane = 0; lane < DATA_BYTES; lane = lane + 1)
            if (lanes[lane])
                normalized_data[lane*8 +: 8] = data[lane*8 +: 8];
    end

    always @(posedge clk) begin
        if (!reset && completed && event_count < MAX_EVENTS) begin
            $fwrite(fd,
                {"{\"seq\":%0d,\"cpu\":%0d,\"event\":\"bus\",",
                 "\"pc\":%0d,\"rw\":\"%s\",\"address\":%0d,",
                 "\"data\":%0d,\"lanes\":%0d,\"device\":%0d}\n"},
                event_count, cpu, pc, rnw ? "r" : "w", address,
                normalized_data, lanes, device);
            event_count <= event_count + 1;
        end
    end

    final begin
        if (fd != 0)
            $fclose(fd);
    end
endmodule
