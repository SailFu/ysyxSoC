module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  // APB always ready, no errors
  assign in_pready = 1'b1;
  assign in_pslverr = 1'b0;
  assign in_prdata = 32'd0;

  // NVBoard VGA Logic: Stream sampling
  // NVBoard samples 1 pixel every CYCLES_PER_UPDATE cycles (must match C++ loop).
  // We must hold the pixel for N cycles and output continuously (no blanking).
  localparam CYCLES_PER_UPDATE = 1;

  localparam H_DISPLAY = 640;
  localparam V_DISPLAY = 480;
  // No blanking allowed for NVBoard stream mode
  localparam H_TOTAL   = 640; 
  localparam V_TOTAL   = 480; 
  localparam SIZE      = H_DISPLAY * V_DISPLAY;

  // Large array for simulation
  reg [23:0] vram [0:SIZE-1];

  // Internal registers
  reg [18:0] addr_ptr; // Points to current pixel in VRAM

  // Pixel counters
  reg [9:0] h_cnt;
  reg [9:0] v_cnt;
  
  // Clock divider for NVBoard synchronization
  reg [7:0] clk_div;

  // VGA timing/pixel generation
  always @(posedge clock) begin
    if (reset) begin
      h_cnt <= 10'd0;
      v_cnt <= 10'd0;
      clk_div <= 8'd0;
      // Initialize VRAM? No, Verilator does it.
    end else begin
      if (clk_div == CYCLES_PER_UPDATE - 1) begin
        clk_div <= 8'd0;
        
        // Advance pixel every 128 cycles
        if (h_cnt == H_TOTAL - 1) begin
          h_cnt <= 10'd0;
          if (v_cnt == V_TOTAL - 1) begin
            v_cnt <= 10'd0;
          end else begin
            v_cnt <= v_cnt + 10'd1;
          end
        end else begin
          h_cnt <= h_cnt + 10'd1;
        end
      end else begin
        clk_div <= clk_div + 8'd1;
      end
    end
  end

  // APB interface
  // Offset 0x00: Data Register (Write pixel at addr_ptr, then incr addr_ptr)
  // Offset 0x04: Address Register (Set addr_ptr)
  
  always @(posedge clock) begin
    if (reset) begin
      addr_ptr <= 19'd0;
    end else if (in_psel && in_penable && in_pwrite) begin
      // Address decoding using in_paddr[2] (0x0 vs 0x4)
      if (in_paddr[2]) begin // 0x4: Address Register
         addr_ptr <= in_pwdata[18:0];
      end else begin         // 0x0: Data Register
         vram[addr_ptr] <= in_pwdata[23:0];
         if (addr_ptr == SIZE - 1) 
           addr_ptr <= 19'd0;
         else 
           addr_ptr <= addr_ptr + 19'd1;
      end
    end
  end

  // Video Output Logic with VRAM read
  wire [18:0] pixel_addr = v_cnt * H_DISPLAY + h_cnt;
  wire [23:0] pixel_color = vram[pixel_addr];

  // Determine output activity (always active for NVBoard stream)
  wire display_active = 1'b1;

  assign vga_r = display_active ? pixel_color[23:16] : 8'd0;
  assign vga_g = display_active ? pixel_color[15:8]  : 8'd0;
  assign vga_b = display_active ? pixel_color[7:0]   : 8'd0;

  // Signals for NVBoard - Valid hardcoded to 1 (BLANK_N)
  assign vga_hsync = 1'b1; // Unused
  assign vga_vsync = 1'b1; // Unused
  assign vga_valid = 1'b1; // BLANK_N = 1 (Active)

endmodule
