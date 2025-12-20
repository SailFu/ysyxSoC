// PSRAM Simulation Model for IS66WVS4M8ALL
// Supports SPI Mode and QPI Mode
// Commands: Quad IO Read (EBh), Quad IO Write (38h), Enter QPI (35h)
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
  localparam CMD_READ      = 8'hEB;  // Quad IO Read
  localparam CMD_WRITE     = 8'h38;  // Quad IO Write
  localparam CMD_ENTER_QPI = 8'h35;  // Enter QPI Mode
  localparam CMD_EXIT_QPI  = 8'hF5;  // Exit QPI Mode
  
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
  reg qpi_mode;         // QPI mode flag (0=SPI, 1=QPI)
  
  // Tri-state buffer for dio
  assign dio = dout_en ? dout : 4'bz;
  
  // Main state machine - posedge sck with async reset on ce_n
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      // Reset state on ce_n deassert, but preserve qpi_mode
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
          if (qpi_mode) begin
            // QPI mode: 4-bit command
            cmd <= {4'd0, dio[3:0]};
          end else begin
            // SPI mode: 1-bit command
            cmd <= {7'd0, dio[0]};
          end
        end
        
        S_CMD: begin
          if (qpi_mode) begin
            // QPI mode: command in 2 cycles (4-bit each)
            cmd <= {cmd[3:0], dio[3:0]};
            bit_cnt <= bit_cnt + 5'd1;
            if (bit_cnt == 5'd0) begin  // After 2nd nibble
              // Check command type after receiving full command
              state <= S_ADDR;
              bit_cnt <= 5'd0;
            end
          end else begin
            // SPI mode: command in 8 cycles (1-bit each)
            cmd <= {cmd[6:0], dio[0]};
            bit_cnt <= bit_cnt + 5'd1;
            if (bit_cnt == 5'd6) begin
              // Check if this is Enter QPI command
              if ({cmd[6:0], dio[0]} == CMD_ENTER_QPI) begin
                qpi_mode <= 1'b1;
                state <= S_IDLE;  // No address/data for this command
              end else begin
                state <= S_ADDR;
                bit_cnt <= 5'd0;
              end
            end
          end
        end
        
        S_ADDR: begin
          // Address always 4-bit in both QSPI and QPI modes
          addr <= {addr[19:0], dio[3:0]};
          bit_cnt <= bit_cnt + 5'd1;
          if (bit_cnt == 5'd5) begin  // 6 nibbles = 24 bits
            if (cmd == CMD_READ) begin
              state <= S_WAIT;
              bit_cnt <= 5'd0;
            end else if (cmd == CMD_WRITE) begin
              state <= S_DATA;
              bit_cnt <= 5'd0;
            end else if (cmd == CMD_EXIT_QPI) begin
              qpi_mode <= 1'b0;
              state <= S_IDLE;
            end else begin
              state <= S_IDLE;
            end
          end
        end
        
        S_WAIT: begin
          bit_cnt <= bit_cnt + 5'd1;
          if (bit_cnt == 5'd5) begin  // 6 wait cycles
            state <= S_DATA;
            bit_cnt <= 5'd0;
          end
        end
        
        S_DATA: begin
          if (cmd == CMD_WRITE) begin
            // Write: sample data on rising edge
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
              addr <= addr + 24'd1;
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
        dout_en <= 1'b1;
        dout <= mem[addr[21:0]][7:4];
      end else begin
        dout_en <= 1'b0;
      end
    end
  end
  
  // Initialize qpi_mode to SPI mode on power-up
  initial begin
    qpi_mode = 1'b0;
  end

endmodule
