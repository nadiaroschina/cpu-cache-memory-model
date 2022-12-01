module mem #(parameter

    MEM_SIZE = 512 * 1024,  // bytes

    CACHE_OFFSET_SIZE = 4,
    
    ADDR2_BUS_SIZE = 15,  // bits
    DATA2_BUS_SIZE = 16,  // bits
    CTR2_BUS_SIZE = 2,  // bits

    _SEED = 225526
)(
    input CLK,
    input M_DUMP,
    input RESET,
    input [ADDR2_BUS_SIZE - 1 : 0] A2,
    inout [DATA2_BUS_SIZE - 1 : 0] D2,
    inout [CTR2_BUS_SIZE - 1 : 0] C2
);

typedef enum reg[CTR2_BUS_SIZE - 1: 0] { C2_NOP = 2'b00, C2_RESPONSE = 2'b01, C2_READ_LINE = 2'b10, C2_WRITE_LINE = 2'b11 } command2_names;

// bit controlling a2/d2/c2 buses
reg control2;

// command that we write to c2 bus
reg[CTR2_BUS_SIZE - 1 : 0] cmd2;
assign C2 = control2 ? cmd2 : 2'bzz;

// data that we read/write from/to d2 bus
reg[7:0] data2_0, data2_1;
assign D2[7:0] = control2 ? data2_0 : 8'bzzzzzzzz;
assign D2[15:8] = control2 ? data2_1 : 8'bzzzzzzzz;

// actual memory data
reg [7:0] data [MEM_SIZE];

integer SEED = _SEED;

// logging & initial values
initial begin
    $monitor("[mem] [%0t] C2 = %b, cmd2 = %b, control2 = %b", $time, C2, cmd2, control2);
    control2 = 0;
    for (integer i = 0; i < MEM_SIZE; i++) begin
        data[i] = $random(SEED)>>16;
    end
end

// reset system
always @(posedge CLK) begin
    if (RESET) begin
        control2 = 0;
        for (integer i = 0; i < MEM_SIZE; i++) begin
            data[i] = $random(SEED)>>16;
        end
    end
end

// memory dump
always @(posedge CLK) begin
    if (M_DUMP) begin
        for (integer i = 0; i < MEM_SIZE; i++) begin
            data[i] = $random(SEED)>>16;
        end
    end
end


// process queries from cache
always @(posedge CLK) begin
    if (control2 == 0) begin
        case (C2)
            // write data of 1 cache line (16 bytes)
            // d2 bus size is 16 bit (2 bytes)
            // A2 stores adress tag
            C2_WRITE_LINE: begin
                control2 = 1;
                cmd2 = C2_RESPONSE;

                for (reg [CACHE_OFFSET_SIZE - 1:0] offset = 4'b0000; offset < 4'b1111; offset++) begin
                    if (offset[0] == 0) begin 
                        @(posedge(CLK));
                        data[{A2[ADDR2_BUS_SIZE - 1: 0], offset}] = D2[15:8];
                    end
                    if (offset[0] == 1) begin
                        data[{A2[ADDR2_BUS_SIZE - 1: 0], offset}] = D2[7:0];
                    end
                end

                // mem operation should be 100 clk ticks
                for (int i = 0; i < 100 - 8; ++i) @(posedge CLK);
                cmd2 = C2_NOP;
                control2 = 0;
                end
            C2_READ_LINE: begin
                control2 = 1;
                cmd2 = C2_RESPONSE;
                // d2 = [data2_1 data2_0]

                for (reg [CACHE_OFFSET_SIZE - 1:0] offset = 4'b0000; offset < 4'b1111; offset++) begin
                    if (offset[0] == 0) begin 
                        @(posedge(CLK));
                        data2_1 = data[{A2[ADDR2_BUS_SIZE - 1: 0], offset}];
                    end
                    if (offset[0] == 1) begin
                        data2_0 = data[{A2[ADDR2_BUS_SIZE - 1: 0], offset}];
                    end
                end                
                
                // mem operation should be 100 clk ticks
                for (int i = 0; i < 100 - 8; ++i) @(posedge CLK);
                cmd2 = C2_NOP;
                control2 = 0;
                end
        endcase
    end
end

endmodule
