`include "memory.sv"
`include "cache.sv"
`include "cpu.sv"

`timescale 1ns/1ps

module tb #(parameter

    ADDR1_BUS_SIZE = 15,
    DATA1_BUS_SIZE = 16,
    CTR1_BUS_SIZE = 3,

    ADDR2_BUS_SIZE = 15, 
    DATA2_BUS_SIZE = 16,
    CTR2_BUS_SIZE = 2,

    _SEED = 225526
);

typedef enum reg[CTR2_BUS_SIZE - 1: 0] { C2_NOP = 2'b00, C2_RESPONSE = 2'b01, C2_READ_LINE = 2'b10, C2_WRITE_LINE = 2'b11 } command2_names;
typedef enum reg[CTR1_BUS_SIZE - 1: 0] {C1_NOP = 3'b000, C1_READ8  = 3'b001, C1_READ16 = 3'b010, C1_READ32 = 3'b011, C1_INVALIDATE_LINE = 3'b100, C1_WRITE8 = 3'b101, C1_WRITE16 = 3'b110, C1_WRITE32_RESPONCE = 3'b111 } command1_names;

reg clk = 0;
always #1 clk = ~clk;

always #100 begin
 $display("[%0t] time", $time);
end

wire m_dump;
wire c_dump;
wire reset;

wire [ADDR1_BUS_SIZE - 1 : 0] a1;
wire [DATA1_BUS_SIZE - 1 : 0] d1;
wire [CTR1_BUS_SIZE - 1 : 0] c1;

wire [ADDR2_BUS_SIZE - 1 : 0] a2;
wire [DATA2_BUS_SIZE - 1 : 0] d2;
wire [CTR2_BUS_SIZE - 1 : 0] c2;

mem mem_(.CLK(clk), .M_DUMP(m_dump), .RESET(reset), .A2(a2), .D2(d2), .C2(c2));
cache cache_(.CLK(clk), .C_DUMP(c_dump), .RESET(reset), .A1(a1), .D1(d1), .C1(c1), .A2(a2), .D2(d2), .C2(c2));
cpu cpu_(.CLK(clk), .A1(a1), .D1(d1), .C1(c1));

endmodule