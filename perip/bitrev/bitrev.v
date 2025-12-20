module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output reg miso
);
  
  reg [7:0] rx_data;
  reg [7:0] tx_data;
  reg [4:0] cnt; // 0-31

  // Rx Logic: Sample MOSI on SCK Rising Edge
  always @(posedge sck or posedge ss) begin
    if (ss) begin
      cnt <= 0;
      rx_data <= 0;
    end else begin
      if (cnt < 8) begin
        rx_data <= {rx_data[6:0], mosi}; // MSB First
      end
      cnt <= cnt + 1;
    end
  end

  // Tx Logic: Drive MISO on SCK Falling Edge
  always @(negedge sck or posedge ss) begin
    if (ss) begin
      miso <= 1'b1; // Idle High
      tx_data <= 0;
    end else begin
      // After 8 bits received (cnt=8 from posedge), start transmitting
      if (cnt == 8) begin
         // Capture received data, reverse it, and drive MSB
         tx_data <= {rx_data[0], rx_data[1], rx_data[2], rx_data[3], rx_data[4], rx_data[5], rx_data[6], rx_data[7]};
         miso <= rx_data[0]; 
         //$display("[BitRev] Loaded tx_data=%x from rx_data=%x (BitRev). Driving %b", 
         //         {rx_data[0], rx_data[1], rx_data[2], rx_data[3], rx_data[4], rx_data[5], rx_data[6], rx_data[7]}, rx_data, rx_data[0]);
      end else if (cnt > 8 && cnt <= 16) begin
         // Shift out remaining bits
         miso <= tx_data[6];
         tx_data <= {tx_data[6:0], 1'b1};
         //$display("[BitRev] Shift tx_data=%x. Driving %b", tx_data, tx_data[6]);
      end
    end
  end

  // Debug - uncomment to trace
  // always @(negedge sck) if (!ss) $display("[BitRev] Time=%0t cnt=%d mosi=%b rx_data=%x miso=%b", $time, cnt, mosi, rx_data, miso);

endmodule
