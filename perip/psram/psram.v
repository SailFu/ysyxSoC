// PSRAM Simulation Model for IS66WVS4M8ALL
// Supports SPI Mode Quad IO Read (EBh) and Quad IO Write (38h) commands
// verilator lint_off MULTIDRIVEN
// verilator lint_off CASEINCOMPLETE

`timescale 1ns/1ps

module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  // PSRAM size: 4MB = 2^22 bytes
  localparam MEM_SIZE = 4 * 1024 * 1024;
  
  // Storage array (8-bit word)
  reg [7:0] mem [0:MEM_SIZE-1];
  
  // Command codes
  localparam CMD_READ  = 8'hEB;  // Quad IO Read
  localparam CMD_WRITE = 8'h38;  // Quad IO Write
  
  // State machine states
  localparam S_IDLE = 3'd0;
  localparam S_CMD  = 3'd1;
  localparam S_ADDR = 3'd2;
  localparam S_WAIT = 3'd3;
  localparam S_DATA = 3'd4;
  
  reg [2:0] state;
  reg [7:0] cmd;
  reg [23:0] addr;
  reg [4:0] bit_cnt;    // Counter for bits/nibbles
  reg [7:0] data_buf;   // Buffer for read/write data
  reg [3:0] dout;       // Output data
  reg dout_en;          // Output enable
  
  // Tri-state buffer for dio
  assign dio = dout_en ? dout : 4'bz;
  
  // Main state machine - posedge sck with async reset on ce_n
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      // Reset all state on ce_n deassert
      state <= S_IDLE;
      bit_cnt <= 5'd0;
      cmd <= 8'd0;
      addr <= 24'd0;
      data_buf <= 8'd0;
    end else begin
      case (state)
        S_IDLE: begin
          state <= S_CMD;
          bit_cnt <= 5'd0;
          cmd <= {7'd0, dio[0]};
        end
        
        S_CMD: begin
          cmd <= {cmd[6:0], dio[0]};
          bit_cnt <= bit_cnt + 5'd1;
          if (bit_cnt == 5'd6) begin
            state <= S_ADDR;
            bit_cnt <= 5'd0;
          end
        end
        
        S_ADDR: begin
          addr <= {addr[19:0], dio[3:0]};
          bit_cnt <= bit_cnt + 5'd1;
          if (bit_cnt == 5'd5) begin
            // cmd now contains full command byte
            if (cmd == CMD_READ) begin
              state <= S_WAIT;
              bit_cnt <= 5'd0;
            end else if (cmd == CMD_WRITE) begin
              state <= S_DATA;
              bit_cnt <= 5'd0;
            end else begin
              state <= S_IDLE;
            end
          end
        end
        
        S_WAIT: begin
          bit_cnt <= bit_cnt + 5'd1;
          if (bit_cnt == 5'd5) begin
            state <= S_DATA;
            bit_cnt <= 5'd0;
          end
        end
        
        S_DATA: begin
          if (cmd == CMD_WRITE) begin
            if (bit_cnt[0] == 1'b0) begin
              data_buf[7:4] <= dio[3:0];
            end else begin
              mem[addr[21:0]] <= {data_buf[7:4], dio[3:0]};
              addr <= addr + 24'd1;
            end
            bit_cnt <= bit_cnt + 5'd1;
          end else begin
            // Read: just increment counter
            if (bit_cnt[0] == 1'b1) begin
              addr <= addr + 24'd1;  // Advance after reading low nibble
            end
            bit_cnt <= bit_cnt + 5'd1;
          end
        end
        
        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end
  
  // Read data output - negedge sck with async reset on ce_n
  always @(negedge sck or posedge ce_n) begin
    if (ce_n) begin
      dout_en <= 1'b0;
      dout <= 4'd0;
    end else begin
      if (state == S_DATA && cmd == CMD_READ) begin
        dout_en <= 1'b1;
        if (bit_cnt[0] == 1'b0) begin
          dout <= mem[addr[21:0]][7:4];
        end else begin
          dout <= mem[addr[21:0]][3:0];
        end
      end else if (state == S_WAIT && bit_cnt == 5'd5) begin
        // Prepare first data nibble at end of wait
        dout_en <= 1'b1;
        dout <= mem[addr[21:0]][7:4];
      end else begin
        dout_en <= 1'b0;
      end
    end
  end

endmodule
