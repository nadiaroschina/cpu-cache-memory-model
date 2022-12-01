module cache #(parameter

    CACHE_LINE_COUNT = 64,
    CACHE_ADDR_SIZE = 19,  // bits
    CACHE_LINE_SIZE = 16, // bytes
    CACHE_TAG_SIZE = 10,  // bits
    CACHE_SET_SIZE = 5,  // bits
    CACHE_OFFSET_SIZE = 4,  // bits
    CACHE_WAY = 2,
    cache_line_len = 1 + 1 + CACHE_TAG_SIZE + 8 * CACHE_LINE_SIZE,

    ADDR1_BUS_SIZE = 15,  // bits
    DATA1_BUS_SIZE = 16,  // bits
    CTR1_BUS_SIZE = 3,  // bits

    ADDR2_BUS_SIZE = 15,  // bits
    DATA2_BUS_SIZE = 16,  // bits
    CTR2_BUS_SIZE = 2  // bits
) (
    input CLK,

    input C_DUMP,
    input RESET,

    input [ADDR1_BUS_SIZE - 1 : 0] A1,
    inout [DATA1_BUS_SIZE - 1 : 0] D1,
    inout [CTR1_BUS_SIZE - 1 : 0] C1,

    output [ADDR2_BUS_SIZE - 1 : 0] A2,
    inout [DATA2_BUS_SIZE - 1 : 0] D2,
    inout [CTR2_BUS_SIZE - 1 : 0] C2
);

typedef enum reg[CTR2_BUS_SIZE - 1: 0] { C2_NOP = 2'b00, C2_RESPONSE = 2'b01, C2_READ_LINE = 2'b10, C2_WRITE_LINE = 2'b11 } command2_names;
typedef enum reg[CTR1_BUS_SIZE - 1: 0] {C1_NOP = 3'b000, C1_READ8  = 3'b001, C1_READ16 = 3'b010, C1_READ32 = 3'b011, C1_INVALIDATE_LINE = 3'b100, C1_WRITE8 = 3'b101, C1_WRITE16 = 3'b110, C1_WRITE32_RESPONCE = 3'b111 } command1_names;

// bit controlling a1/d1/c1 buses
reg control1;

// command that we write to c1 bus
reg[CTR1_BUS_SIZE - 1 : 0] cmd1;
assign C1 = control1 ? cmd1 : 3'bzzz;

// bit controlling a1/d1/c1 buses
reg control2;

// command that we write to c2 bus
reg [CTR2_BUS_SIZE - 1 : 0] cmd2;
assign C2 = control2 ? cmd2 : 2'bzz;

// address that we write to a2
reg [ADDR2_BUS_SIZE - 1: 0] address2;
assign A2[ADDR2_BUS_SIZE - 1 : 0] = address2;

// address that we read from a1
reg [CACHE_ADDR_SIZE - 1: 0] address1;

// parse address1 and assign parts to tag, set and offset
reg [CACHE_TAG_SIZE - 1 : 0] tag;
assign tag = address1[CACHE_ADDR_SIZE - 1 : CACHE_ADDR_SIZE - CACHE_TAG_SIZE];
reg [CACHE_SET_SIZE - 1 : 0] set;
assign set = address1[CACHE_ADDR_SIZE - CACHE_TAG_SIZE - 1: CACHE_OFFSET_SIZE];
reg [CACHE_OFFSET_SIZE - 1 : 0] offset;
assign offset = address1[CACHE_OFFSET_SIZE - 1: 0];

// actual cache data, format: valid(1 bit)-dirty(1 bit)-tag(10 bits)-data(16 bytes)
reg[cache_line_len - 1 : 0] data [CACHE_LINE_COUNT];

// data that we read/write from/to d1 bus
reg[7:0] data1_0, data1_1;
assign D1[7:0] = control1 ? data1_0 : 8'bzzzzzzzz;
assign D1[15:8] = control1 ? data1_1 : 8'bzzzzzzzz;

// data that we read/write from/to d2 bus
reg[7:0] data2_0, data2_1;
assign D2[7:0] = control2 ? data2_0 : 8'bzzzzzzzz;
assign D2[15:8] = control2 ? data2_1 : 8'bzzzzzzzz;

reg cache_hit;
reg[19:0] hit_counter;
reg[19:0] miss_counter;

// logging & initial values
initial begin
    $monitor("[cache] [%0t] C1 = %b, C2 = %b, cmd1 = %b, cmd2 = %b, control1 = %b, control2 = %b", $time, C1, C2, cmd1, cmd2, control1, control2);
    hit_counter = 0;
    miss_counter = 0;
    control1 = 0;
    control2 = 1;
    cmd2 = C2_NOP;
end

// reset system
always @(posedge CLK) begin
    if (RESET) begin
        control1 = 0;
        control2 = 1;
        cmd2 = C2_NOP;
    end
    for (integer i = 0; i < CACHE_LINE_COUNT; i++) begin
        data[i] = 19'b0000000000000000000;
    end
end

// cache dump
always @(posedge CLK) begin
    if (C_DUMP) begin
        for (integer i = 0; i < CACHE_LINE_COUNT; i++) begin
            data[i] = 19'b0000000000000000000;
        end
    end
end

// process queries from cpu
always @(posedge CLK) begin
    if (control1 == 0) begin
        case (C1)

            C1_READ8 || C1_READ16 || C1_READ32: begin
                control1 = 1;
                cmd1 = C1_WRITE32_RESPONCE;

                @ (posedge CLK);
                // reading tag + set from a1
                address1[CACHE_ADDR_SIZE - 1: CACHE_OFFSET_SIZE] = A1[ADDR1_BUS_SIZE - 1: 0];

                @ (posedge CLK);
                // reading offset from a1
                address1[CACHE_OFFSET_SIZE - 1: 0] = A1[CACHE_ADDR_SIZE - 1: 0];

                cache_hit = 0;
                // data[CACHE_WAY * set + r], 0 <= r < CACHE_WAY, may be the line for address
                for (reg r = 0; r < CACHE_WAY; r++) begin
                    // check if line is valid ans has the tag that we need
                    if (data[CACHE_WAY * set + r][cache_line_len - 1] == 1 && data[CACHE_WAY * set + r][cache_line_len - 3 : cache_line_len - CACHE_TAG_SIZE - 2] == tag) begin
                        // writing data to d1 bus
                        if (C1 == C1_READ8) begin
                            @(posedge CLK)
                            data1_0 = data[CACHE_WAY * set][offset +: 8];
                        end
                        if (C1 == C1_READ16) begin
                            @(posedge CLK)
                            data1_0 = data[CACHE_WAY * set][offset +: 8];
                            data1_1 = data[CACHE_WAY * set][offset + 8 +: 8];
                        end
                        if (C1 == C1_READ32) begin
                            @(posedge CLK)
                            data1_0 = data[CACHE_WAY * set][offset +: 8];
                            data1_1 = data[CACHE_WAY * set][offset + 8 +: 8];
                            @(posedge CLK)
                            data1_0 = data[CACHE_WAY * set][offset + 16 +: 8];
                            data1_1 = data[CACHE_WAY * set][offset + 24 +: 8];
                        end
                        cache_hit = 1;
                    end
                end

                if (!cache_hit) begin

                    // we will fetch needed line from memory to 1st line in this cache block

                    // 1st line in this block is invalid - don't have to do anything 
                    if (data[CACHE_WAY * set][cache_line_len - 1] == 0);
                    // 2nd line in this block is invalid or valid but not dirty - copy 1st to 2nd
                    if (data[CACHE_WAY * set + 1][cache_line_len - 1] == 0 || data[CACHE_WAY * set + 1][cache_line_len - 1: cache_line_len - 2] == 2'b00) begin
                        data[CACHE_WAY * set + 1] = data[CACHE_WAY * set];
                    end
                    // 1st and 2nd are valid; 2nd is dirty -- write 2nd to mem, then copy 1st to 2nd
                    if (data[CACHE_WAY * set + 1][cache_line_len - 1] == 0 && data[CACHE_WAY * set + 1][cache_line_len - 1: cache_line_len - 2] == 2'b01) begin
                        
                        cmd2 = C2_WRITE_LINE;
                        address2[ADDR2_BUS_SIZE - 1 : 0] = {data[CACHE_WAY * set + 1][cache_line_len - 3: cache_line_len - 3 - CACHE_TAG_SIZE], set};
                        @(posedge CLK)
                        // giving control to mem
                        control2 = 0;

                        // sending data to mem 
                        for (reg [CACHE_OFFSET_SIZE - 1:0] offset = 4'b0000; offset < 4'b1111; offset++) begin
                            if (offset[0] == 0) begin 
                                @(posedge(CLK));
                                data2_1 = data[CACHE_WAY * set + 1][CACHE_LINE_SIZE * 8 + offset -: 8];
                            end
                            if (offset[0] == 1) begin
                                data2_0 = data[CACHE_WAY * set + 1][CACHE_LINE_SIZE * 8 + offset -: 8];
                            end
                        end

                        // regaining control 
                        control2 = 1;

                        // now we can safely write 1st line data to 2nd
                        data[CACHE_WAY * set + 1] = data[CACHE_WAY * set];

                    end

                    // now we are fetching needed data to 1st line of our cache block

                    cmd2 = C2_READ_LINE;
                    address2[ADDR2_BUS_SIZE - 1 : 0] = {tag, set};
                    @ (posedge CLK);
                    // giving control to mem
                    control2 = 0;

                    // this line becomes valid and not dirty
                    data[CACHE_WAY * set][cache_line_len - 1 : cache_line_len - 2] = 2'b10;

                    // recieving data from mem
                    for (reg [CACHE_OFFSET_SIZE - 1:0] offset = 4'b0000; offset < 4'b1111; offset++) begin
                        if (offset[0] == 0) begin 
                            @(posedge(CLK));
                            data[CACHE_WAY * set][CACHE_LINE_SIZE * 8 + offset -: 8] = data2_1;
                        end
                        if (offset[0] == 1) begin
                            data[CACHE_WAY * set][CACHE_LINE_SIZE * 8 + offset -: 8] = data2_0;
                        end
                    end

                    // regaining control    
                    control2 = 1;

                    // now needed data is in 1st line of cache
                    // writing data to d1 bus
                    if (C1 == C1_READ8) begin
                        @(posedge CLK)
                        data1_0 = data[CACHE_WAY * set][offset +: 8];
                    end
                    if (C1 == C1_READ16) begin
                        @(posedge CLK)
                        data1_0 = data[CACHE_WAY * set][offset +: 8];
                        data1_1 = data[CACHE_WAY * set][offset + 8 +: 8];
                    end
                    if (C1 == C1_READ32) begin
                        @(posedge CLK)
                        data1_0 = data[CACHE_WAY * set][offset +: 8];
                        data1_1 = data[CACHE_WAY * set][offset + 8 +: 8];
                        @(posedge CLK)
                        data1_0 = data[CACHE_WAY * set][offset + 16 +: 8];
                        data1_1 = data[CACHE_WAY * set][offset + 24 +: 8];
                    end

                end

                if (cache_hit) begin
                    hit_counter++;
                end
                if (!cache_hit) begin
                    miss_counter++;
                end

                // giving control back to cpu    
                control1 = 0;

            end

            C1_INVALIDATE_LINE: begin
                control1 = 1;
                cmd1 = C1_WRITE32_RESPONCE;

                @ (posedge CLK);
                // reading tag + set from a1
                address1[CACHE_ADDR_SIZE - 1: CACHE_OFFSET_SIZE] = A1[ADDR1_BUS_SIZE - 1: 0];

                @ (posedge CLK);
                // reading offset from a1
                address1[CACHE_OFFSET_SIZE - 1: 0] = A1[CACHE_ADDR_SIZE - 1: 0];

                // data[CACHE_WAY * set + r], 0 <= r < CACHE_WAY, may be the line for address
                for (reg r = 0; r < CACHE_WAY; r++) begin
                    // check if line has the tag that we need
                    if (data[CACHE_WAY * set + r][cache_line_len - 3 : cache_line_len - CACHE_TAG_SIZE - 2] == tag) begin
                        // set validness bit to 0
                        data[CACHE_WAY * set + r][cache_line_len - 1] = 0;
                        // ...
                    end
                end

                control1 = 0;
            end

            C1_WRITE8 || C1_WRITE16 || C1_WRITE32_RESPONCE: begin
                control1 = 1;
                cmd1 = C1_WRITE32_RESPONCE;

                @ (posedge CLK);
                // reading tag + set from a1
                address1[CACHE_ADDR_SIZE - 1: CACHE_OFFSET_SIZE] = A1[ADDR1_BUS_SIZE - 1: 0];

                @ (posedge CLK);
                // reading offset from a1
                address1[CACHE_OFFSET_SIZE - 1: 0] = A1[CACHE_ADDR_SIZE - 1: 0];

                cache_hit = 0;
                // data[CACHE_WAY * set + r], 0 <= r < CACHE_WAY, may be the line for address
                for (reg r = 0; r < CACHE_WAY; r++) begin
                    // check if line is valid ans has the tag that we need
                    if (data[CACHE_WAY * set + r][cache_line_len - 1] == 1 && data[CACHE_WAY * set + r][cache_line_len - 3 : CACHE_LINE_SIZE * 8] == tag) begin
                        // marking line as dirty
                        data[CACHE_WAY * set + r][cache_line_len - 1] = 1;
                        // writing data to cache
                        if (C1 == C1_WRITE8) begin
                            @ (posedge CLK)
                            data[CACHE_WAY * set + r][offset +: 8] = data1_0;
                        end
                        if (C1 == C1_WRITE16) begin
                            @ (posedge CLK)
                            data[CACHE_WAY * set + r][offset +: 16] = {data1_1, data1_0};
                        end
                        if (C1 == C1_WRITE32_RESPONCE) begin
                            @ (posedge CLK)
                            data[CACHE_WAY * set + r][offset +: 16] = {data1_1, data1_0};
                            @(posedge CLK)
                            data[CACHE_WAY * set + r][offset + 16 +: 16] = {data1_1, data1_0};
                        end
                        cache_hit = 1;
                    end
                end

                if (!cache_hit) begin

                    // we will fetch needed line from memory to 1st line in this cache block

                    // 1st line in this block is invalid - don't have to do anything 
                    if (data[CACHE_WAY * set][cache_line_len - 1] == 0);
                    // 2nd line in this block is invalid or valid but not dirty - copy 1st to 2nd
                    if (data[CACHE_WAY * set + 1][cache_line_len - 1] == 0 || data[CACHE_WAY * set + 1][cache_line_len - 1: cache_line_len - 2] == 2'b00) begin
                        data[CACHE_WAY * set + 1] = data[CACHE_WAY * set];
                    end
                    // 1st and 2nd are valid; 2nd is dirty -- write 2nd to mem, then copy 1st to 2nd
                    if (data[CACHE_WAY * set + 1][cache_line_len - 1] == 0 && data[CACHE_WAY * set + 1][cache_line_len - 1: cache_line_len - 2] == 2'b01) begin
                        
                        cmd2 = C2_WRITE_LINE;
                        address2[ADDR2_BUS_SIZE - 1 : 0] = {data[CACHE_WAY * set + 1][cache_line_len - 3: cache_line_len - 3 - CACHE_TAG_SIZE], set};
                        @(posedge CLK)
                        // giving control to mem
                        control2 = 0;

                        // sending data to mem 
                        for (reg [CACHE_OFFSET_SIZE - 1:0] offset = 4'b0000; offset < 4'b1111; offset++) begin
                            if (offset[0] == 0) begin 
                                @(posedge(CLK));
                                data2_1 = data[CACHE_WAY * set + 1][CACHE_LINE_SIZE * 8 + offset -: 8];
                            end
                            if (offset[0] == 1) begin
                                data2_0 = data[CACHE_WAY * set + 1][CACHE_LINE_SIZE * 8 + offset -: 8];
                            end
                        end

                        // regaining control 
                        control2 = 1;

                        // now we can safely write 1st line data to 2nd
                        data[CACHE_WAY * set + 1] = data[CACHE_WAY * set];

                    end

                    // now we are fetching needed data to 1st line of our cache block

                    cmd2 = C2_READ_LINE;
                    address2[ADDR2_BUS_SIZE - 1 : 0] = {tag, set};
                    @ (posedge CLK);
                    // giving control to mem
                    control2 = 0;

                    // this line becomes valid and not dirty
                    data[CACHE_WAY * set][cache_line_len - 1 : cache_line_len - 2] = 2'b10;

                    // recieving data from mem
                    for (reg [CACHE_OFFSET_SIZE - 1:0] offset = 4'b0000; offset < 4'b1111; offset++) begin
                        if (offset[0] == 0) begin 
                            @(posedge(CLK));
                            data[CACHE_WAY * set][CACHE_LINE_SIZE * 8 + offset -: 8] = data2_1;
                        end
                        if (offset[0] == 1) begin
                            data[CACHE_WAY * set][CACHE_LINE_SIZE * 8 + offset -: 8] = data2_0;
                        end
                    end

                    // regaining control    
                    control2 = 1;

                    // now  needed data is in 1st line if out cache block
                    // marking line as dirty
                    data[CACHE_WAY * set][cache_line_len - 1] = 1;
                    // writing data to cache
                    if (C1 == C1_WRITE8) begin
                        @ (posedge CLK)
                        data[CACHE_WAY * set][offset +: 8] = data1_0;
                    end
                    if (C1 == C1_WRITE16) begin
                        @ (posedge CLK)
                        data[CACHE_WAY * set][offset +: 16] = {data1_1, data1_0};
                    end
                    if (C1 == C1_WRITE32_RESPONCE) begin
                        @ (posedge CLK)
                        data[CACHE_WAY * set][offset +: 16] = {data1_1, data1_0};
                        @(posedge CLK)
                    data[CACHE_WAY * set][offset + 16 +: 16] = {data1_1, data1_0};
                    end

                end

                if (cache_hit) begin
                    hit_counter++;
                end
                if (!cache_hit) begin
                    miss_counter++;
                end

                // giving control back to cpu    
                control1 = 0;

            end

        endcase
    end
end

endmodule