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
    integer selected_max_events;

    initial begin
        selected_file = TRACE_FILE;
        void'($value$plusargs("TRACE_FILE=%s", selected_file));
        // Keep normal traces bounded, but allow a deliberately longer
        // parent-only trace when a slow ROM initialization loop is being
        // bisected.  This is simulation-only and cannot affect RTL.
        selected_max_events = MAX_EVENTS;
        void'($value$plusargs("TRACE_MAX=%d", selected_max_events));
        if (selected_max_events < 1)
            selected_max_events = MAX_EVENTS;
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
        if (!reset && completed && event_count < selected_max_events) begin
            // Keep the format as one string literal.  A concatenation of
            // packed string literals is treated as an integer expression by
            // some Verilator versions, producing an unreadable decimal blob
            // instead of JSONL and making the differential gate unusable.
            $fwrite(fd,
                "{\"seq\":%0d,\"cpu\":%0d,\"event\":\"bus\",\"pc\":%0d,\"rw\":\"%s\",\"address\":%0d,\"data\":%0d,\"lanes\":%0d,\"device\":%0d}\n",
                event_count, cpu, pc, rnw ? "r" : "w", address,
                normalized_data, lanes, device);
            // Flush periodically as well as at shutdown.  Verilator can
            // terminate a timing model directly from $finish, before a
            // simulator final block has a chance to drain the host stream.
            if ((event_count & 32'h3ff) == 0)
                $fflush(fd);
            event_count <= event_count + 1;
        end
    end

    final begin
        if (fd != 0) begin
            $display("[TRACE] events=%0d file=%s", event_count, selected_file);
            $fflush(fd);
            $fclose(fd);
        end
    end
endmodule
