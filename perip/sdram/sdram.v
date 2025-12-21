// MT48LC16M16A2 SDRAM Simulation Model
// For ysyxSoC simulation only

module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
);

  localparam CMD_NOP       = 4'b0111;
  localparam CMD_ACTIVE    = 4'b0011;
  localparam CMD_READ      = 4'b0101;
  localparam CMD_WRITE     = 4'b0100;
  localparam CMD_PRECHARGE = 4'b0010;
  localparam CMD_REFRESH   = 4'b0001;
  localparam CMD_LOAD_MODE = 4'b0000;

  localparam COL_BITS  = 9;
  localparam ROW_BITS  = 13;
  localparam BANK_BITS = 2;
  localparam DATA_BITS = 16;
  localparam MEM_ADDR_BITS = 22; 
  
  reg [DATA_BITS-1:0] mem [0:(1<<MEM_ADDR_BITS)-1];

  reg [2:0] cas_latency;
  reg [2:0] burst_length_code;
  reg [ROW_BITS-1:0] active_row [0:3];
  reg [3:0] row_active;

  reg [DATA_BITS-1:0] read_pipe_data [0:4];
  reg [4:0] read_pipe_valid;
  
  reg read_burst_pending;
  reg [BANK_BITS-1:0] read_burst_bank;
  reg [ROW_BITS-1:0] read_burst_row;
  reg [COL_BITS-1:0] read_burst_col;

  reg burst_write_active;
  reg [BANK_BITS-1:0] burst_bank;
  reg [ROW_BITS-1:0] burst_row;
  reg [COL_BITS-1:0] burst_col_next;
  
  reg dq_oe;
  reg [DATA_BITS-1:0] dq_out;
  
  assign dq = dq_oe ? dq_out : {DATA_BITS{1'bz}};

  function [MEM_ADDR_BITS-1:0] calc_addr;
    input [BANK_BITS-1:0] bank;
    input [ROW_BITS-1:0] row;
    input [COL_BITS-1:0] col;
    begin
      calc_addr = {bank, row[10:0], col[COL_BITS-1:0]};
    end
  endfunction

  wire [3:0] cmd = {cs, ras, cas, we};
  integer i;
  
  initial begin
    $display("[SDRAM Model] Initialized. Size: 8MB");
    cas_latency = 3'd2;
    burst_length_code = 3'b001;
    row_active = 4'b0;
    dq_oe = 0;
    dq_out = 16'h0;
    read_pipe_valid = 5'b0;
    burst_write_active = 0;
    read_burst_pending = 0;
    for (i = 0; i < 4; i = i + 1) active_row[i] = 0;
    for (i = 0; i < 5; i = i + 1) read_pipe_data[i] = 16'h0;
  end

  // Read Pipeline Logic using Next State variables for clarity
  reg [4:0] next_read_pipe_valid;
  
  always @(posedge clk) begin
    if (!cke) begin
      dq_oe <= 1'b0;
    end else begin
      // Default: Shift Valid
      next_read_pipe_valid = {read_pipe_valid[3:0], 1'b0};
      
      // Shift Data Pipeline
      read_pipe_data[4] <= read_pipe_data[3];
      read_pipe_data[3] <= read_pipe_data[2];
      read_pipe_data[2] <= read_pipe_data[1];
      read_pipe_data[1] <= read_pipe_data[0];
      read_pipe_data[0] <= 16'h0;

      // Handle Command
      case (cmd)
        CMD_LOAD_MODE: begin
          burst_length_code <= a[2:0];
          cas_latency <= a[6:4];
          burst_write_active <= 1'b0;
          // $display("[SDRAM] LOAD_MODE: CAS=%0d", a[6:4]);
        end
        
        CMD_ACTIVE: begin
          active_row[ba] <= a[ROW_BITS-1:0];
          row_active[ba] <= 1'b1;
          burst_write_active <= 1'b0;
          // $display("[SDRAM] ACTIVE: Bank=%0d", ba);
        end
        
        CMD_READ: begin
          if (row_active[ba]) begin
            // 1st word injection
            read_pipe_data[0] <= mem[calc_addr(ba, active_row[ba], a[COL_BITS-1:0])];
            next_read_pipe_valid[0] = 1'b1; // Override bit 0
            
            // Pending 2nd word
            read_burst_pending <= 1'b1;
            read_burst_bank <= ba;
            read_burst_row <= active_row[ba];
            read_burst_col <= a[COL_BITS-1:0] + 1;

            // $display("[SDRAM] READ: Bank=%0d, Row=%0d, Col=%0d, Data=%04h", 
            //          ba, active_row[ba], a[COL_BITS-1:0],
            //          mem[calc_addr(ba, active_row[ba], a[COL_BITS-1:0])]);
          end
          burst_write_active <= 1'b0;
        end
        
        CMD_WRITE: begin
          if (row_active[ba]) begin
            if (!dqm[0]) mem[calc_addr(ba, active_row[ba], a[COL_BITS-1:0])][7:0] <= dq[7:0];
            if (!dqm[1]) mem[calc_addr(ba, active_row[ba], a[COL_BITS-1:0])][15:8] <= dq[15:8];
            
            burst_write_active <= 1'b1;
            burst_bank <= ba;
            burst_row <= active_row[ba];
            burst_col_next <= a[COL_BITS-1:0] + 1;
            
            // $display("[SDRAM] WRITE(0) Data=%04h DQM=%b", dq, dqm);
          end
        end
        
        CMD_NOP: begin
          if (burst_write_active) begin
             if (!dqm[0]) mem[calc_addr(burst_bank, burst_row, burst_col_next)][7:0] <= dq[7:0];
             if (!dqm[1]) mem[calc_addr(burst_bank, burst_row, burst_col_next)][15:8] <= dq[15:8];
             burst_write_active <= 1'b0;
             // $display("[SDRAM] WRITE(1) Data=%04h DQM=%b", dq, dqm);
          end
        end
        
        CMD_PRECHARGE: begin
           if (a[10]) row_active <= 4'b0000;
           else row_active[ba] <= 1'b0;
           burst_write_active <= 1'b0;
        end
        
        default: begin
           // Ignore other commands
           burst_write_active <= 1'b0;
        end
      endcase
      
      // Handle Pending Burst Read
      if (read_burst_pending) begin
        read_pipe_data[0] <= mem[calc_addr(read_burst_bank, read_burst_row, read_burst_col)];
        next_read_pipe_valid[0] = 1'b1; // Override bit 0
        read_burst_pending <= 1'b0;
        // $display("[SDRAM] READ(Burst): Data=%04h", mem[calc_addr(read_burst_bank, read_burst_row, read_burst_col)]);
      end
      
      // Update Valid
      read_pipe_valid <= next_read_pipe_valid;
      
      // Output Logic
      dq_oe <= 1'b0;
      // Note: checking OLD read_pipe which holds data for NEXT cycle
      // CL=2: Need to drive at T1.5 (Negedge) to be stable for T2.0 (Posedge) sample.
      // Index 0 holds data from T0->T1 transition. Old Index 0 at T1 is valid.
      // So use Index 0 for CL=2.
      if (read_pipe_valid[0]) begin 
         dq_oe <= 1'b1;
         dq_out <= read_pipe_data[0];
         // $display("[SDRAM] DQ Drive: %x at time %t", read_pipe_data[0], $time);
      end
    end
  end

endmodule
