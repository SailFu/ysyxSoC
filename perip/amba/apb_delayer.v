module apb_delayer #(
  parameter FREQ_RATIO    = 5,   // CPU/Device frequency ratio (r), must be >= 1
  parameter COUNTER_WIDTH = 16   // Delay counter width (s)
)(
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

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  // When r=1, no delay needed - simple passthrough
  generate
    if (FREQ_RATIO <= 1) begin : gen_passthrough
      // Direct passthrough - no delay
      assign out_paddr   = in_paddr;
      assign out_psel    = in_psel;
      assign out_penable = in_penable;
      assign out_pprot   = in_pprot;
      assign out_pwrite  = in_pwrite;
      assign out_pwdata  = in_pwdata;
      assign out_pstrb   = in_pstrb;
      assign in_pready   = out_pready;
      assign in_prdata   = out_prdata;
      assign in_pslverr  = out_pslverr;
    end else begin : gen_delayer
      // State machine states
      localparam IDLE        = 2'b00;
      localparam WAIT_DEVICE = 2'b01;
      localparam DELAY       = 2'b10;

      reg [1:0] state, next_state;
      reg [COUNTER_WIDTH-1:0] counter;
      reg [31:0] prdata_reg;
      reg        pslverr_reg;

      // State transition logic
      always @(posedge clock) begin
        if (reset) begin
          state <= IDLE;
        end else begin
          state <= next_state;
        end
      end

      // Next state logic
      always @(*) begin
        next_state = state;
        case (state)
          IDLE: begin
            // Transaction starts: psel=1, penable=0 (SETUP phase)
            if (in_psel && !in_penable) begin
              next_state = WAIT_DEVICE;
            end
          end
          WAIT_DEVICE: begin
            // Device responds: pready=1 (ACCESS phase complete)
            if (out_pready) begin
              // Check if we need to delay
              // counter will be k*(r-1) at this point, if > 0 go to DELAY
              if (counter > 0 || (FREQ_RATIO - 1) > 0) begin
                next_state = DELAY;
              end else begin
                next_state = IDLE;
              end
            end
          end
          DELAY: begin
            // Delay complete: counter decremented to 1 (will be 0 next cycle)
            if (counter <= 1) begin
              next_state = IDLE;
            end
          end
          default: next_state = IDLE;
        endcase
      end

      // Counter logic
      always @(posedge clock) begin
        if (reset) begin
          counter <= 0;
        end else begin
          case (state)
            IDLE: begin
              counter <= 0;
            end
            WAIT_DEVICE: begin
              // Accumulate (r-1) each cycle while waiting for device response
              // Extra delay = k * (r-1), total delay = k + k*(r-1) = k*r
              counter <= counter + (FREQ_RATIO - 1);
            end
            DELAY: begin
              // Decrement counter each cycle
              if (counter > 0) begin
                counter <= counter - 1;
              end
            end
            default: counter <= 0;
          endcase
        end
      end

      // Capture device response when it arrives
      always @(posedge clock) begin
        if (reset) begin
          prdata_reg  <= 32'b0;
          pslverr_reg <= 1'b0;
        end else if (state == WAIT_DEVICE && out_pready) begin
          prdata_reg  <= out_prdata;
          pslverr_reg <= out_pslverr;
        end
      end

      // Output signals to device (downstream)
      assign out_paddr   = in_paddr;
      assign out_psel    = in_psel && (state == IDLE || state == WAIT_DEVICE);
      assign out_penable = in_penable && (state == WAIT_DEVICE);
      assign out_pprot   = in_pprot;
      assign out_pwrite  = in_pwrite;
      assign out_pwdata  = in_pwdata;
      assign out_pstrb   = in_pstrb;

      // Output signals to upstream (CPU side)
      // Ready when in DELAY state and counter reaches 1 (or 0)
      assign in_pready  = (state == DELAY) && (counter <= 1);
      assign in_prdata  = prdata_reg;
      assign in_pslverr = pslverr_reg;
    end
  endgenerate

endmodule
