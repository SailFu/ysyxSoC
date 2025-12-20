/*
	Copyright 2020 Efabless Corp.

	Author: Mohamed Shalan (mshalan@efabless.com)

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at:
	http://www.apache.org/licenses/LICENSE-2.0
	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
*/
/*
    QSPI/QPI PSRAM Controller

    Pseudostatic RAM (PSRAM) is DRAM combined with a self-refresh circuit.
    It appears externally as slower SRAM, albeit with a density/cost advantage
    over true SRAM, and without the access complexity of DRAM.

    The controller was designed after https://www.issi.com/WW/pdf/66-67WVS4M8ALL-BLL.pdf
    utilizing both EBh and 38h commands for reading and writting.
    
    Modified to support QPI mode (4-4-4) for improved efficiency.
*/

`timescale              1ns/1ps
`default_nettype        none

// QPI Mode Reader - Using EBH Command
module PSRAM_READER (
    input   wire            clk,
    input   wire            rst_n,
    input   wire [23:0]     addr,
    input   wire            rd,
    input   wire [2:0]      size,
    input   wire            qpi_mode,   // QPI mode enable
    output  wire            done,
    output  wire [31:0]     line,

    output  reg             sck,
    output  reg             ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire            douten
);

    localparam  IDLE = 1'b0,
                READ = 1'b1;

    // QPI mode: 2(cmd) + 6(addr) + 6(wait) + data = 14 + size*2
    // SPI mode: 8(cmd) + 6(addr) + 6(wait) + data = 20 + size*2
    wire [7:0]  FINAL_COUNT = qpi_mode ? (13 + size*2) : (19 + size*2);
    wire [7:0]  CMD_END     = qpi_mode ? 8'd1 : 8'd7;   // Command phase end
    wire [7:0]  ADDR_END    = qpi_mode ? 8'd7 : 8'd13;  // Address phase end
    wire [7:0]  WAIT_END    = qpi_mode ? 8'd13 : 8'd19; // Wait phase end
    wire [7:0]  DATA_START  = qpi_mode ? 8'd14 : 8'd20; // Data phase start

    reg         state, nstate;
    reg [7:0]   counter;
    reg [23:0]  saddr;
    reg [7:0]   data [3:0];

    wire[7:0]   CMD_EBH = 8'heb;

    always @*
        case (state)
            IDLE: if(rd) nstate = READ; else nstate = IDLE;
            READ: if(done) nstate = IDLE; else nstate = READ;
        endcase

    always @ (posedge clk or negedge rst_n)
        if(!rst_n) state <= IDLE;
        else state <= nstate;

    // Drive the Serial Clock (sck) @ clk/2
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            sck <= 1'b0;
        else if(~ce_n)
            sck <= ~ sck;
        else if(state == IDLE)
            sck <= 1'b0;

    // ce_n logic
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            ce_n <= 1'b1;
        else if(state == READ)
            ce_n <= 1'b0;
        else
            ce_n <= 1'b1;

    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            counter <= 8'b0;
        else if(sck & ~done)
            counter <= counter + 1'b1;
        else if(state == IDLE)
            counter <= 8'b0;

    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            saddr <= 24'b0;
        else if((state == IDLE) && rd)
            saddr <= {addr[23:0]};

    // Sample with the negedge of sck
    wire[1:0] byte_index_qpi = {counter[7:1] - 8'd7}[1:0];
    wire[1:0] byte_index_spi = {counter[7:1] - 8'd10}[1:0];
    wire[1:0] byte_index = qpi_mode ? byte_index_qpi : byte_index_spi;
    
    always @ (posedge clk)
        if(counter >= DATA_START && counter <= FINAL_COUNT)
            if(sck)
                data[byte_index] <= {data[byte_index][3:0], din};

    // Command and address output
    assign dout     =   qpi_mode ? (
                        // QPI mode: 4-bit command
                        (counter == 0)  ?   CMD_EBH[7:4]        :
                        (counter == 1)  ?   CMD_EBH[3:0]        :
                        (counter == 2)  ?   saddr[23:20]        :
                        (counter == 3)  ?   saddr[19:16]        :
                        (counter == 4)  ?   saddr[15:12]        :
                        (counter == 5)  ?   saddr[11:8]         :
                        (counter == 6)  ?   saddr[7:4]          :
                        (counter == 7)  ?   saddr[3:0]          :
                        4'h0
                    ) : (
                        // SPI mode: 1-bit command
                        (counter < 8)   ?   {3'b0, CMD_EBH[7 - counter]}:
                        (counter == 8)  ?   saddr[23:20]        :
                        (counter == 9)  ?   saddr[19:16]        :
                        (counter == 10) ?   saddr[15:12]        :
                        (counter == 11) ?   saddr[11:8]         :
                        (counter == 12) ?   saddr[7:4]          :
                        (counter == 13) ?   saddr[3:0]          :
                        4'h0
                    );

    assign douten   = qpi_mode ? (counter <= 8) : (counter < 14);

    assign done     = (counter == FINAL_COUNT+1);

    generate
        genvar i;
        for(i=0; i<4; i=i+1)
            assign line[i*8+7: i*8] = data[i];
    endgenerate


endmodule

// QPI Mode Writer - Using 38H Command
module PSRAM_WRITER (
    input   wire            clk,
    input   wire            rst_n,
    input   wire [23:0]     addr,
    input   wire [31: 0]    line,
    input   wire [2:0]      size,
    input   wire            wr,
    input   wire            qpi_mode,   // QPI mode enable
    output  wire            done,

    output  reg             sck,
    output  reg             ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire            douten
);
    localparam  IDLE = 1'b0,
                WRITE = 1'b1;

    // QPI mode: 2(cmd) + 6(addr) + data = 8 + size*2
    // SPI mode: 8(cmd) + 6(addr) + data = 14 + size*2
    wire[7:0]   FINAL_COUNT = qpi_mode ? (7 + size*2) : (13 + size*2);
    wire[7:0]   DATA_START  = qpi_mode ? 8'd8 : 8'd14;

    reg         state, nstate;
    reg [7:0]   counter;
    reg [23:0]  saddr;

    wire[7:0]   CMD_38H = 8'h38;

    always @*
        case (state)
            IDLE: if(wr) nstate = WRITE; else nstate = IDLE;
            WRITE: if(done) nstate = IDLE; else nstate = WRITE;
        endcase

    always @ (posedge clk or negedge rst_n)
        if(!rst_n) state <= IDLE;
        else state <= nstate;

    // Drive the Serial Clock (sck) @ clk/2
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            sck <= 1'b0;
        else if(~ce_n)
            sck <= ~ sck;
        else if(state == IDLE)
            sck <= 1'b0;

    // ce_n logic
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            ce_n <= 1'b1;
        else if(state == WRITE)
            ce_n <= 1'b0;
        else
            ce_n <= 1'b1;

    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            counter <= 8'b0;
        else if(sck & ~done)
            counter <= counter + 1'b1;
        else if(state == IDLE)
            counter <= 8'b0;

    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            saddr <= 24'b0;
        else if((state == IDLE) && wr)
            saddr <= addr;

    assign dout     =   qpi_mode ? (
                        // QPI mode: 4-bit command
                        (counter == 0)  ?   CMD_38H[7:4]        :
                        (counter == 1)  ?   CMD_38H[3:0]        :
                        (counter == 2)  ?   saddr[23:20]        :
                        (counter == 3)  ?   saddr[19:16]        :
                        (counter == 4)  ?   saddr[15:12]        :
                        (counter == 5)  ?   saddr[11:8]         :
                        (counter == 6)  ?   saddr[7:4]          :
                        (counter == 7)  ?   saddr[3:0]          :
                        (counter == 8)  ?   line[7:4]           :
                        (counter == 9)  ?   line[3:0]           :
                        (counter == 10) ?   line[15:12]         :
                        (counter == 11) ?   line[11:8]          :
                        (counter == 12) ?   line[23:20]         :
                        (counter == 13) ?   line[19:16]         :
                        (counter == 14) ?   line[31:28]         :
                        line[27:24]
                    ) : (
                        // SPI mode: 1-bit command
                        (counter < 8)   ?   {3'b0, CMD_38H[7 - counter]}:
                        (counter == 8)  ?   saddr[23:20]        :
                        (counter == 9)  ?   saddr[19:16]        :
                        (counter == 10) ?   saddr[15:12]        :
                        (counter == 11) ?   saddr[11:8]         :
                        (counter == 12) ?   saddr[7:4]          :
                        (counter == 13) ?   saddr[3:0]          :
                        (counter == 14) ?   line[7:4]           :
                        (counter == 15) ?   line[3:0]           :
                        (counter == 16) ?   line[15:12]         :
                        (counter == 17) ?   line[11:8]          :
                        (counter == 18) ?   line[23:20]         :
                        (counter == 19) ?   line[19:16]         :
                        (counter == 20) ?   line[31:28]         :
                        line[27:24]
                    );

    assign douten   = (~ce_n);

    assign done     = (counter == FINAL_COUNT + 1);


endmodule
