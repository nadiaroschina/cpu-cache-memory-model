module cpu #(parameter
    ADDR1_BUS_SIZE = 15,  // bits
    DATA1_BUS_SIZE = 16,  // bits
    CTR1_BUS_SIZE = 3,  // bits

    CACHE_ADDR_SIZE = 19,  // bits
    CACHE_TAG_SIZE = 10,  // bits
    CACHE_SET_SIZE = 5,  // bits
    CACHE_OFFSET_SIZE = 4  // bits

) (
    input CLK,

    input [ADDR1_BUS_SIZE - 1 : 0] A1,
    inout [DATA1_BUS_SIZE - 1 : 0] D1,
    inout [CTR1_BUS_SIZE - 1 : 0] C1
);

typedef enum reg[CTR1_BUS_SIZE - 1: 0] {C1_NOP = 3'b000, C1_READ8  = 3'b001, C1_READ16 = 3'b010, C1_READ32 = 3'b011, C1_INVALIDATE_LINE = 3'b100, C1_WRITE8 = 3'b101, C1_WRITE16 = 3'b110, C1_WRITE32_RESPONCE = 3'b111 } command1_names;

// bit controlling a1/d1/c1 buses
reg control1;

// command that we write to c1 bus
reg[CTR1_BUS_SIZE - 1: 0] cmd1;
assign C1 = control1 ? cmd1 : 2'bzz;

// address that we write to a1
reg [CACHE_ADDR_SIZE - 1: 0] address1;

// data that we read/write from/to d1 bus
reg[7:0] data1_0, data1_1;
assign D1[7:0] = control1 ? data1_0 : 8'bzzzzzzzz;
assign D1[15:8] = control1 ? data1_1 : 8'bzzzzzzzz;

// logging & initial values
initial begin
    $monitor("[cpu] [%0t] C1 = %b, cmd1 = %b, control1 = %b", $time, C1, cmd1, control1);
    control1 = 1;
    cmd1 = C1_NOP;
end

integer M, N, K;
reg[18:0] pa, pb, pc;
integer s;
reg[7:0] res1;
reg[15:0] res2;

// run  matrix multicipation
// adding clock tics to model the system we're implementing
initial begin
    @(posedge CLK);
    M = 64;
    @(posedge CLK);
    N = 60;
    @(posedge CLK);
    K = 32;
    @(posedge CLK);
    pa = 0;
    @(posedge CLK);
    pc = M * K + K * N;
    @(posedge CLK);
    for (integer y = 0; y < M; y++) begin
        @(posedge CLK); @(posedge CLK);
        for (integer x = 0; x < N; x++) begin
            @(posedge CLK); @(posedge CLK);
                pb = M * K;
                @(posedge CLK);
                s = 0;
                @(posedge CLK);
                for (integer k = 0; k < K; k++) begin

                    @(posedge CLK); @(posedge CLK);
                    
                    // accessing pa + k, read8 to res1
                    cmd1 = C1_READ8;

                    @(posedge CLK);
                    // giving control to cache
                    control1 = 0;
                    address1[15:5] = (pa + k) >> 9;
                    address1[4:0] = ((pa + k) >> 4) % 32;

                    @(posedge CLK);
                    address1[3:0] = (pa + k) % 16;

                    @(posedge CLK);
                    // reading data from cache
                    res1 = data1_0;

                    // regaining control    
                    control1 = 1;

                    // accessing pb + 2x, read16 to res2
                    cmd1 = C1_READ16;

                    @(posedge CLK);
                    // giving control to cache
                    control1 = 0;
                    address1[15:5] = (pb + 2 * x) >> 9;
                    address1[4:0] = ((pb + 2 * x) >> 4) % 32;

                    @(posedge CLK);
                    address1[3:0] = (pb + 2 * x) % 16;

                    @(posedge CLK);
                    // reading data from cache
                    res1 = data1_0;

                    // regaining control    
                    control1 = 1;
                    cmd1 = C1_NOP;

                    s += res1 * res2;
                    @(posedge CLK); @(posedge CLK); @(posedge CLK); @(posedge CLK); @(posedge CLK);
                    pb += N;
                    @(posedge CLK);
                end

            // accessing pc + 4x, write32 from s
            cmd1 = C1_WRITE32_RESPONCE;

            @(posedge CLK);
            // giving control to cache
            control1 = 0;
            address1[15:5] = (pc + 4 * x) >> 9;
            address1[4:0] = ((pc + 4 * x) >> 4) % 32;

            @(posedge CLK);
            address1[3:0] = (pc + 4 * x) % 16;

            // writing data to cache
            @(posedge CLK);
            data1_0 = s % (2 ** 8);
            data1_1 = (s >> 8) % (2 ** 8);
            @(posedge CLK);
            data1_0 = (s >> 16) % (2 ** 8);
            data1_1 = s >> 24;

            // regaining control    
            control1 = 1;
            cmd1 = C1_NOP;

        end
        pa += K;
        @(posedge CLK);
        pc += N;
        @(posedge CLK);
    end

end
    
endmodule