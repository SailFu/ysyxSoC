module ps2_top_apb(
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

  input         ps2_clk,
  input         ps2_data
);

  // APB always ready, no errors
  assign in_pready = 1'b1;
  assign in_pslverr = 1'b0;

  // PS/2 clock edge detection
  reg [2:0] ps2_clk_sync;
  always @(posedge clock) begin
    if (reset)
      ps2_clk_sync <= 3'b111;
    else
      ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
  end
  wire ps2_clk_negedge = (ps2_clk_sync[2:1] == 2'b10);

  // PS/2 data synchronizer
  reg [1:0] ps2_data_sync;
  always @(posedge clock) begin
    if (reset)
      ps2_data_sync <= 2'b11;
    else
      ps2_data_sync <= {ps2_data_sync[0], ps2_data};
  end
  wire ps2_data_s = ps2_data_sync[1];

  // PS/2 receiver state machine
  reg [3:0] bit_cnt;
  reg [10:0] shift_reg;
  reg [7:0] scancode;
  reg scancode_valid;

  always @(posedge clock) begin
    if (reset) begin
      bit_cnt <= 4'd0;
      shift_reg <= 11'd0;
      scancode_valid <= 1'b0;
    end else begin
      scancode_valid <= 1'b0;
      
      if (ps2_clk_negedge) begin
        // Shift in data (LSB first: start, D0-D7, parity, stop)
        shift_reg <= {ps2_data_s, shift_reg[10:1]};
        
        if (bit_cnt == 4'd10) begin
          // Complete frame received
          bit_cnt <= 4'd0;
          // Extract data bits (bits 8:1 of shift_reg after final shift)
          // shift_reg[0] = start, shift_reg[8:1] = data, shift_reg[9] = parity, shift_reg[10] = stop
          scancode <= shift_reg[8:1];
          scancode_valid <= 1'b1;
        end else begin
          bit_cnt <= bit_cnt + 4'd1;
        end
      end
    end
  end

  // Simple FIFO (8 entries)
  reg [7:0] fifo [0:7];
  reg [2:0] wr_ptr, rd_ptr;
  reg [3:0] fifo_cnt;
  
  wire fifo_empty = (fifo_cnt == 4'd0);
  wire fifo_full  = (fifo_cnt == 4'd8);

  always @(posedge clock) begin
    if (reset) begin
      wr_ptr <= 3'd0;
      rd_ptr <= 3'd0;
      fifo_cnt <= 4'd0;
    end else begin
      // Write to FIFO
      if (scancode_valid && !fifo_full) begin
        fifo[wr_ptr] <= scancode;
        wr_ptr <= wr_ptr + 3'd1;
        fifo_cnt <= fifo_cnt + 4'd1;
      end
      
      // Read from FIFO (APB read at address 0)
      if (in_psel && in_penable && !in_pwrite && (in_paddr[2:0] == 3'b000) && !fifo_empty) begin
        rd_ptr <= rd_ptr + 3'd1;
        fifo_cnt <= fifo_cnt - 4'd1;
      end
      
      // Handle simultaneous read/write
      if (scancode_valid && !fifo_full && 
          in_psel && in_penable && !in_pwrite && (in_paddr[2:0] == 3'b000) && !fifo_empty) begin
        fifo_cnt <= fifo_cnt; // No change
      end
    end
  end

  // APB read data
  assign in_prdata = (in_paddr[2:0] == 3'b000) ? 
                     (fifo_empty ? 32'd0 : {24'd0, fifo[rd_ptr]}) : 
                     32'd0;

endmodule
