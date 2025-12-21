module gpio_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

  // Address offsets within GPIO address space
  // 0x0: LED output register (16 bits)
  // 0x4: Switch input register (16 bits, read-only)
  // 0x8: 7-segment display register (32 bits, 4 bits per digit)
  // 0xc: Reserved

  // Internal registers
  reg [15:0] led_reg;      // LED output register
  reg [31:0] seg_reg;      // 7-segment display register

  // APB always ready, no errors
  assign in_pready = 1'b1;
  assign in_pslverr = 1'b0;

  // Address decode (only lower 4 bits matter within 16-byte space)
  wire [3:0] addr_offset = in_paddr[3:0];

  // Write logic
  wire wr_en = in_psel && in_penable && in_pwrite;

  always @(posedge clock) begin
    if (reset) begin
      led_reg <= 16'h0;
      seg_reg <= 32'h0;
    end else if (wr_en) begin
      case (addr_offset)
        4'h0: begin  // LED register
          if (in_pstrb[0]) led_reg[7:0]  <= in_pwdata[7:0];
          if (in_pstrb[1]) led_reg[15:8] <= in_pwdata[15:8];
        end
        4'h8: begin  // 7-segment register
          if (in_pstrb[0]) seg_reg[7:0]   <= in_pwdata[7:0];
          if (in_pstrb[1]) seg_reg[15:8]  <= in_pwdata[15:8];
          if (in_pstrb[2]) seg_reg[23:16] <= in_pwdata[23:16];
          if (in_pstrb[3]) seg_reg[31:24] <= in_pwdata[31:24];
        end
        default: ;  // Ignore writes to other addresses
      endcase
    end
  end

  // Read logic
  reg [31:0] rdata;
  always @(*) begin
    case (addr_offset)
      4'h0: rdata = {16'h0, led_reg};
      4'h4: rdata = {16'h0, gpio_in};  // Read switch state
      4'h8: rdata = seg_reg;
      default: rdata = 32'h0;
    endcase
  end
  assign in_prdata = rdata;

  // Output assignments
  assign gpio_out = led_reg;

  // 7-segment display decoding
  // Each 4-bit nibble encodes a hex digit (0-F)
  // Segment encoding: bit[7]=DP, [6:0]=GFEDCBA (active high)
  function [7:0] hex_to_seg;
    input [3:0] hex;
    begin
      case (hex)
        4'h0: hex_to_seg = 8'b00111111;  // 0
        4'h1: hex_to_seg = 8'b00000110;  // 1
        4'h2: hex_to_seg = 8'b01011011;  // 2
        4'h3: hex_to_seg = 8'b01001111;  // 3
        4'h4: hex_to_seg = 8'b01100110;  // 4
        4'h5: hex_to_seg = 8'b01101101;  // 5
        4'h6: hex_to_seg = 8'b01111101;  // 6
        4'h7: hex_to_seg = 8'b00000111;  // 7
        4'h8: hex_to_seg = 8'b01111111;  // 8
        4'h9: hex_to_seg = 8'b01101111;  // 9
        4'hA: hex_to_seg = 8'b01110111;  // A
        4'hB: hex_to_seg = 8'b01111100;  // b
        4'hC: hex_to_seg = 8'b00111001;  // C
        4'hD: hex_to_seg = 8'b01011110;  // d
        4'hE: hex_to_seg = 8'b01111001;  // E
        4'hF: hex_to_seg = 8'b01110001;  // F
        default: hex_to_seg = 8'b00000000;
      endcase
    end
  endfunction

  assign gpio_seg_0 = hex_to_seg(seg_reg[3:0]);
  assign gpio_seg_1 = hex_to_seg(seg_reg[7:4]);
  assign gpio_seg_2 = hex_to_seg(seg_reg[11:8]);
  assign gpio_seg_3 = hex_to_seg(seg_reg[15:12]);
  assign gpio_seg_4 = hex_to_seg(seg_reg[19:16]);
  assign gpio_seg_5 = hex_to_seg(seg_reg[23:20]);
  assign gpio_seg_6 = hex_to_seg(seg_reg[27:24]);
  assign gpio_seg_7 = hex_to_seg(seg_reg[31:28]);

endmodule
