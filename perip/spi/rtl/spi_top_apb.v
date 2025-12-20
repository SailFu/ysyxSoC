// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

wire wb_ack_o;
wire [31:0] wb_dat_o;
wire [31:0] wb_dat_i;
wire [4:0] wb_adr_i;
wire wb_we_i;
wire wb_stb_i;
wire wb_cyc_i;

// XIP State Machine
reg [3:0] state;
reg [31:0] xip_data;

localparam ST_IDLE = 4'd0;
localparam ST_SS   = 4'd1;
localparam ST_TX1  = 4'd2;
localparam ST_TX0  = 4'd3;
localparam ST_CTRL = 4'd4;
localparam ST_WAIT = 4'd5; // Wait for interrupt
localparam ST_SS_OFF = 4'd7;
localparam ST_RX   = 4'd8;
localparam ST_DONE = 4'd9;

wire xip_req = in_penable && in_psel && !in_pwrite && (in_paddr >= flash_addr_start && in_paddr <= flash_addr_end);
wire normal_req = in_penable && in_psel && !(in_paddr >= flash_addr_start && in_paddr <= flash_addr_end);

always @(posedge clock) begin
  if (reset) begin
      state <= ST_IDLE;
      xip_data <= 0;
  end else begin
      case(state)
          ST_IDLE: if (xip_req) state <= ST_SS;
          ST_SS:   if (wb_ack_o) state <= ST_TX1;
          ST_TX1:  if (wb_ack_o) state <= ST_TX0;
          ST_TX0:  if (wb_ack_o) state <= ST_CTRL;
          ST_CTRL: if (wb_ack_o) state <= ST_WAIT;
          ST_WAIT: if (spi_irq_out) state <= ST_SS_OFF; // Wait for interrupt
          ST_SS_OFF: if (wb_ack_o) state <= ST_RX;
          ST_RX:   if (wb_ack_o) begin 
              xip_data <= wb_dat_o; 
              state <= ST_DONE; 
          end
          ST_DONE: state <= ST_IDLE; // Handshake done
          default: state <= ST_IDLE;
      endcase
  end
end

// Mux Logic
// Address Mapping:
// SS: 0x18 (24) -> 5'h18
// TX1: 0x04 -> 5'h04
// TX0: 0x00 -> 5'h00
// CTRL: 0x10 -> 5'h10
// RX0: 0x00 -> 5'h00

assign wb_adr_i = (state == ST_IDLE) ? in_paddr[4:0] :
                  (state == ST_SS || state == ST_SS_OFF) ? 5'h18 :
                  (state == ST_TX1) ? 5'h04 :
                  (state == ST_TX0 || state == ST_RX) ? 5'h00 :
                  (state == ST_CTRL || state == ST_WAIT) ? 5'h10 : 5'h00;

assign wb_dat_i = (state == ST_IDLE) ? in_pwdata :
                  (state == ST_SS) ? 32'h01 : // SS=1 (Slave 0)
                  (state == ST_SS_OFF) ? 32'h00 : // SS=0
                  (state == ST_TX1) ? {8'h03, in_paddr[23:0]} : // Cmd + Addr
                  (state == ST_TX0) ? 32'h00 : // Dummy
                  (state == ST_CTRL) ? 32'h1540 : // IE|GO|TxNEG|LEN64 (enable interrupt)
                  32'h0;

assign wb_we_i  = (state == ST_IDLE) ? in_pwrite :
                  (state == ST_SS || state == ST_SS_OFF || 
                   state == ST_TX1 || state == ST_TX0 || state == ST_CTRL); // Writes

assign wb_stb_i = (state == ST_IDLE) ? normal_req :
                  (state != ST_DONE && state != ST_WAIT); // No bus request during WAIT (use interrupt)

assign wb_cyc_i = wb_stb_i;

// APB Output
assign in_pready  = (state == ST_IDLE) ? (normal_req ? wb_ack_o : 1'b0) : (state == ST_DONE);
// Byte Swap for XIP Data (Little Endian CPU expects B0 at [7:0])
// SPI RX: B0 B1 B2 B3 (MSB First Shift) -> [31:24]=B0 ...
wire [31:0] xip_bswap = {xip_data[7:0], xip_data[15:8], xip_data[23:16], xip_data[31:24]};
assign in_prdata  = (state == ST_DONE) ? xip_bswap : wb_dat_o;
assign in_pslverr = 1'b0;

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(wb_adr_i),
  .wb_dat_i(wb_dat_i),
  .wb_dat_o(wb_dat_o),
  .wb_sel_i(4'b1111), // Assuming full word access
  .wb_we_i (wb_we_i),
  .wb_stb_i(wb_stb_i),
  .wb_cyc_i(wb_cyc_i),
  .wb_ack_o(wb_ack_o),
  .wb_err_o(),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

`endif // FAST_FLASH

endmodule
