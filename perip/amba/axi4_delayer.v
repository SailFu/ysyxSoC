// AXI4 Delay Module for Latency Calibration
// Scales device response times by frequency ratio r
// Timing: (t_device - t0) * r = t_upstream - t0
//
// Supports burst transfers up to 8 beats
// Read channel: delays each beat independently
// Write channel: delays final response (bvalid)

module axi4_delayer #(
  parameter FREQ_RATIO    = 5,   // CPU/Device frequency ratio (r), must be >= 1
  parameter COUNTER_WIDTH = 16,  // Delay counter width
  parameter MAX_BURST     = 8    // Maximum burst length supported
)(
  input         clock,
  input         reset,

  // Upstream interface (to CPU/Master)
  output        in_arready,
  input         in_arvalid,
  input  [3:0]  in_arid,
  input  [31:0] in_araddr,
  input  [7:0]  in_arlen,
  input  [2:0]  in_arsize,
  input  [1:0]  in_arburst,
  input         in_rready,
  output        in_rvalid,
  output [3:0]  in_rid,
  output [31:0] in_rdata,
  output [1:0]  in_rresp,
  output        in_rlast,
  output        in_awready,
  input         in_awvalid,
  input  [3:0]  in_awid,
  input  [31:0] in_awaddr,
  input  [7:0]  in_awlen,
  input  [2:0]  in_awsize,
  input  [1:0]  in_awburst,
  output        in_wready,
  input         in_wvalid,
  input  [31:0] in_wdata,
  input  [3:0]  in_wstrb,
  input         in_wlast,
  input         in_bready,
  output        in_bvalid,
  output [3:0]  in_bid,
  output [1:0]  in_bresp,

  // Downstream interface (to Device/Slave)
  input         out_arready,
  output        out_arvalid,
  output [3:0]  out_arid,
  output [31:0] out_araddr,
  output [7:0]  out_arlen,
  output [2:0]  out_arsize,
  output [1:0]  out_arburst,
  output        out_rready,
  input         out_rvalid,
  input  [3:0]  out_rid,
  input  [31:0] out_rdata,
  input  [1:0]  out_rresp,
  input         out_rlast,
  input         out_awready,
  output        out_awvalid,
  output [3:0]  out_awid,
  output [31:0] out_awaddr,
  output [7:0]  out_awlen,
  output [2:0]  out_awsize,
  output [1:0]  out_awburst,
  input         out_wready,
  output        out_wvalid,
  output [31:0] out_wdata,
  output [3:0]  out_wstrb,
  output        out_wlast,
  output        out_bready,
  input         out_bvalid,
  input  [3:0]  out_bid,
  input  [1:0]  out_bresp
);

  // When r=1, no delay needed - simple passthrough
  generate
    if (FREQ_RATIO <= 1) begin : gen_passthrough
      // Direct passthrough - no delay
      assign in_arready   = out_arready;
      assign out_arvalid  = in_arvalid;
      assign out_arid     = in_arid;
      assign out_araddr   = in_araddr;
      assign out_arlen    = in_arlen;
      assign out_arsize   = in_arsize;
      assign out_arburst  = in_arburst;
      assign out_rready   = in_rready;
      assign in_rvalid    = out_rvalid;
      assign in_rid       = out_rid;
      assign in_rdata     = out_rdata;
      assign in_rresp     = out_rresp;
      assign in_rlast     = out_rlast;
      assign in_awready   = out_awready;
      assign out_awvalid  = in_awvalid;
      assign out_awid     = in_awid;
      assign out_awaddr   = in_awaddr;
      assign out_awlen    = in_awlen;
      assign out_awsize   = in_awsize;
      assign out_awburst  = in_awburst;
      assign in_wready    = out_wready;
      assign out_wvalid   = in_wvalid;
      assign out_wdata    = in_wdata;
      assign out_wstrb    = in_wstrb;
      assign out_wlast    = in_wlast;
      assign out_bready   = in_bready;
      assign in_bvalid    = out_bvalid;
      assign in_bid       = out_bid;
      assign in_bresp     = out_bresp;
    end else begin : gen_delayer
      // =========================================================================
      // Read Channel Delay Logic
      // =========================================================================
      // State machine
      localparam R_IDLE  = 2'b00;  // Waiting for read request
      localparam R_WAIT  = 2'b01;  // Forwarding to device, waiting for response
      localparam R_DELAY = 2'b10;  // Delaying beats to upstream

      reg [1:0] r_state, r_state_next;
      
      // Cycle counter from t0 (arvalid assertion)
      reg [COUNTER_WIDTH-1:0] r_cycle_cnt;
      
      // Beat FIFO: stores {data, resp, last, arrival_cycle} for each beat
      reg [31:0]              r_fifo_data  [0:MAX_BURST-1];
      reg [1:0]               r_fifo_resp  [0:MAX_BURST-1];
      reg                     r_fifo_last  [0:MAX_BURST-1];
      reg [COUNTER_WIDTH-1:0] r_fifo_time  [0:MAX_BURST-1];  // Arrival cycle
      reg [3:0]               r_fifo_wr_ptr;
      reg [3:0]               r_fifo_rd_ptr;
      reg [3:0]               r_fifo_count;
      
      // Latched AR channel info
      reg [3:0]               r_id_reg;
      
      // Target release cycle for current beat
      wire [COUNTER_WIDTH-1:0] r_target_cycle;
      wire                     r_beat_ready;
      
      // Calculate target cycle: arrival_time * r
      // Since we count from t0, target = arrival_time * r
      assign r_target_cycle = r_fifo_time[r_fifo_rd_ptr] * FREQ_RATIO;
      assign r_beat_ready   = (r_fifo_count > 0) && (r_cycle_cnt >= r_target_cycle);
      
      // State register
      always @(posedge clock) begin
        if (reset)
          r_state <= R_IDLE;
        else
          r_state <= r_state_next;
      end
      
      // Next state logic
      always @(*) begin
        r_state_next = r_state;
        case (r_state)
          R_IDLE: begin
            if (in_arvalid && out_arready)
              r_state_next = R_WAIT;
          end
          R_WAIT: begin
            // Transition to DELAY when first beat arrives from device
            if (out_rvalid && out_rready)
              r_state_next = R_DELAY;
          end
          R_DELAY: begin
            // Stay in DELAY until all beats delivered to upstream
            if (r_beat_ready && in_rready && r_fifo_last[r_fifo_rd_ptr])
              r_state_next = R_IDLE;
          end
          default: r_state_next = R_IDLE;
        endcase
      end
      
      // Cycle counter: counts from 0 starting at arvalid
      always @(posedge clock) begin
        if (reset) begin
          r_cycle_cnt <= 0;
        end else begin
          case (r_state)
            R_IDLE: begin
              if (in_arvalid)
                r_cycle_cnt <= 1;  // Start counting from 1 (t0 = 0)
              else
                r_cycle_cnt <= 0;
            end
            R_WAIT, R_DELAY: begin
              r_cycle_cnt <= r_cycle_cnt + 1;
            end
            default: r_cycle_cnt <= 0;
          endcase
        end
      end
      
      // FIFO write: capture beats from device
      always @(posedge clock) begin
        if (reset) begin
          r_fifo_wr_ptr <= 0;
        end else begin
          if (r_state == R_IDLE && in_arvalid) begin
            r_fifo_wr_ptr <= 0;  // Reset on new transaction
          end else if ((r_state == R_WAIT || r_state == R_DELAY) && out_rvalid && out_rready) begin
            r_fifo_data[r_fifo_wr_ptr] <= out_rdata;
            r_fifo_resp[r_fifo_wr_ptr] <= out_rresp;
            r_fifo_last[r_fifo_wr_ptr] <= out_rlast;
            r_fifo_time[r_fifo_wr_ptr] <= r_cycle_cnt;  // Record arrival cycle
            r_fifo_wr_ptr <= r_fifo_wr_ptr + 1;
          end
        end
      end
      
      // FIFO read: release beats to upstream when delay expires
      always @(posedge clock) begin
        if (reset) begin
          r_fifo_rd_ptr <= 0;
        end else begin
          if (r_state == R_IDLE) begin
            r_fifo_rd_ptr <= 0;  // Reset on new transaction
          end else if (r_state == R_DELAY && r_beat_ready && in_rready) begin
            r_fifo_rd_ptr <= r_fifo_rd_ptr + 1;
          end
        end
      end
      
      // FIFO count
      always @(posedge clock) begin
        if (reset) begin
          r_fifo_count <= 0;
        end else begin
          if (r_state == R_IDLE && in_arvalid) begin
            r_fifo_count <= 0;
          end else begin
            case ({(r_state == R_WAIT || r_state == R_DELAY) && out_rvalid && out_rready,
                   r_state == R_DELAY && r_beat_ready && in_rready})
              2'b10: r_fifo_count <= r_fifo_count + 1;  // Write only
              2'b01: r_fifo_count <= r_fifo_count - 1;  // Read only
              // 2'b11: count unchanged (simultaneous read/write)
              default: ;
            endcase
          end
        end
      end
      
      // Latch AR ID
      always @(posedge clock) begin
        if (reset)
          r_id_reg <= 0;
        else if (r_state == R_IDLE && in_arvalid)
          r_id_reg <= in_arid;
      end
      
      // AR channel: forward to device
      assign out_arvalid  = in_arvalid && (r_state == R_IDLE);
      assign out_arid     = in_arid;
      assign out_araddr   = in_araddr;
      assign out_arlen    = in_arlen;
      assign out_arsize   = in_arsize;
      assign out_arburst  = in_arburst;
      assign in_arready   = out_arready && (r_state == R_IDLE);
      
      // R channel: controlled release from FIFO
      assign out_rready   = (r_state == R_WAIT) || (r_state == R_DELAY);  // Always ready to receive
      assign in_rvalid    = (r_state == R_DELAY) && r_beat_ready;
      assign in_rid       = r_id_reg;
      assign in_rdata     = r_fifo_data[r_fifo_rd_ptr];
      assign in_rresp     = r_fifo_resp[r_fifo_rd_ptr];
      assign in_rlast     = r_fifo_last[r_fifo_rd_ptr];

      // =========================================================================
      // Write Channel Delay Logic (Simplified: single beat only)
      // =========================================================================
      localparam W_IDLE  = 2'b00;
      localparam W_WAIT  = 2'b01;
      localparam W_DELAY = 2'b10;
      
      reg [1:0] w_state, w_state_next;
      reg [COUNTER_WIDTH-1:0] w_cycle_cnt;
      reg [COUNTER_WIDTH-1:0] w_resp_time;
      reg [3:0]  w_bid_reg;
      reg [1:0]  w_bresp_reg;
      
      wire [COUNTER_WIDTH-1:0] w_target_cycle;
      wire                     w_resp_ready;
      
      assign w_target_cycle = w_resp_time * FREQ_RATIO;
      assign w_resp_ready   = (w_cycle_cnt >= w_target_cycle);
      
      // State register
      always @(posedge clock) begin
        if (reset)
          w_state <= W_IDLE;
        else
          w_state <= w_state_next;
      end
      
      // Next state logic
      always @(*) begin
        w_state_next = w_state;
        case (w_state)
          W_IDLE: begin
            if (in_awvalid && out_awready)
              w_state_next = W_WAIT;
          end
          W_WAIT: begin
            if (out_bvalid && out_bready)
              w_state_next = W_DELAY;
          end
          W_DELAY: begin
            if (w_resp_ready && in_bready)
              w_state_next = W_IDLE;
          end
          default: w_state_next = W_IDLE;
        endcase
      end
      
      // Cycle counter
      always @(posedge clock) begin
        if (reset) begin
          w_cycle_cnt <= 0;
        end else begin
          case (w_state)
            W_IDLE: begin
              if (in_awvalid)
                w_cycle_cnt <= 1;
              else
                w_cycle_cnt <= 0;
            end
            W_WAIT, W_DELAY: begin
              w_cycle_cnt <= w_cycle_cnt + 1;
            end
            default: w_cycle_cnt <= 0;
          endcase
        end
      end
      
      // Capture response
      always @(posedge clock) begin
        if (reset) begin
          w_resp_time <= 0;
          w_bid_reg   <= 0;
          w_bresp_reg <= 0;
        end else if (w_state == W_WAIT && out_bvalid) begin
          w_resp_time <= w_cycle_cnt;
          w_bid_reg   <= out_bid;
          w_bresp_reg <= out_bresp;
        end
      end
      
      // AW channel: forward to device
      assign out_awvalid  = in_awvalid && (w_state == W_IDLE);
      assign out_awid     = in_awid;
      assign out_awaddr   = in_awaddr;
      assign out_awlen    = in_awlen;
      assign out_awsize   = in_awsize;
      assign out_awburst  = in_awburst;
      assign in_awready   = out_awready && (w_state == W_IDLE);
      
      // W channel: forward to device (passthrough)
      assign out_wvalid   = in_wvalid && (w_state == W_IDLE || w_state == W_WAIT);
      assign out_wdata    = in_wdata;
      assign out_wstrb    = in_wstrb;
      assign out_wlast    = in_wlast;
      assign in_wready    = out_wready && (w_state == W_IDLE || w_state == W_WAIT);
      
      // B channel: delayed response
      assign out_bready   = (w_state == W_WAIT);
      assign in_bvalid    = (w_state == W_DELAY) && w_resp_ready;
      assign in_bid       = w_bid_reg;
      assign in_bresp     = w_bresp_reg;
      
    end
  endgenerate

endmodule
