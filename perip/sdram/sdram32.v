// 32-bit SDRAM Wrapper for AXI SDRAM Controller
// Combines two 16-bit SDRAM models into a 32-bit interface
// For simulation only
//
// Note: The AXI SDRAM controller (sdram_axi_core.v) uses address bit 26 
// to select between two ranks. For simulation, we want both chips to 
// respond together to provide 32-bit data, so we OR the CS signals.
// 
// Port naming matches SDRAMIO_AXI Scala interface (sdram_* prefix)

module sdram32 (
  input         sdram_clk,
  input         sdram_cke,
  input  [1:0]  sdram_cs,     // 2 chip selects from controller
  input         sdram_ras,
  input         sdram_cas,
  input         sdram_we,
  input  [12:0] sdram_a,
  input  [1:0]  sdram_ba,
  input  [3:0]  sdram_dqm,    // 4-bit mask (low 2 for chip0, high 2 for chip1)
  inout  [31:0] sdram_dq      // 32-bit data (low 16 for chip0, high 16 for chip1)
);

  // Combined chip select - both chips respond when either CS is active (low)
  // This simulates a 32-bit wide SDRAM array
  wire cs_combined = sdram_cs[0] & sdram_cs[1];  // Active low: 0 when any chip is selected

  // Low 16-bit SDRAM (chip 0)
  sdram u_sdram_lo (
    .clk  (sdram_clk),
    .cke  (sdram_cke),
    .cs   (cs_combined),
    .ras  (sdram_ras),
    .cas  (sdram_cas),
    .we   (sdram_we),
    .a    (sdram_a),
    .ba   (sdram_ba),
    .dqm  (sdram_dqm[1:0]),
    .dq   (sdram_dq[15:0])
  );

  // High 16-bit SDRAM (chip 1)
  sdram u_sdram_hi (
    .clk  (sdram_clk),
    .cke  (sdram_cke),
    .cs   (cs_combined),
    .ras  (sdram_ras),
    .cas  (sdram_cas),
    .we   (sdram_we),
    .a    (sdram_a),
    .ba   (sdram_ba),
    .dqm  (sdram_dqm[3:2]),
    .dq   (sdram_dq[31:16])
  );

endmodule
