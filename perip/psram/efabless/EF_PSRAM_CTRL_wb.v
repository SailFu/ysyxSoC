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

`timescale              1ns/1ps
`default_nettype        none

// verilator lint_off CASEINCOMPLETE

// PSRAM Controller with QPI Mode Support
// Automatically sends Enter QPI Mode command (35h) after reset
module EF_PSRAM_CTRL_wb (
    // WB bus Interface
    input   wire        clk_i,
    input   wire        rst_i,
    input   wire [31:0] adr_i,
    input   wire [31:0] dat_i,
    output  wire [31:0] dat_o,
    input   wire [3:0]  sel_i,
    input   wire        cyc_i,
    input   wire        stb_i,
    output  wire        ack_o,
    input   wire        we_i,

    // External Interface to Quad I/O
    output  wire            sck,
    output  wire            ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire [3:0]      douten
);

    // Main FSM states
    localparam  ST_INIT     = 2'd0,   // Send Enter QPI command
                ST_INIT_WAIT= 2'd1,   // Wait for init to complete
                ST_IDLE     = 2'd2,   // Ready for operations
                ST_WAIT     = 2'd3;   // Wait for read/write to complete

    // Init sequence states
    localparam  INIT_IDLE    = 2'd0,
                INIT_SEND    = 2'd1,
                INIT_DONE    = 2'd2;

    wire        mr_sck;
    wire        mr_ce_n;
    wire [3:0]  mr_din;
    wire [3:0]  mr_dout;
    wire        mr_doe;

    wire        mw_sck;
    wire        mw_ce_n;
    wire [3:0]  mw_din;
    wire [3:0]  mw_dout;
    wire        mw_doe;

    // PSRAM Reader and Writer wires
    wire        mr_rd;
    wire        mr_done;
    wire        mw_wr;
    wire        mw_done;

    // QPI mode control
    reg         qpi_mode;
    
    // Init sequence signals
    reg  [1:0]  init_state;
    reg  [3:0]  init_counter;
    reg         init_sck;
    reg         init_ce_n;
    reg  [3:0]  init_dout;
    reg         init_doe;
    wire        init_done;
    
    // Enter QPI Mode command: 0x35 (sent via SPI: 1-bit serial)
    wire [7:0]  CMD_ENTER_QPI = 8'h35;

    // WB Control Signals
    wire        wb_valid        =   cyc_i & stb_i;
    wire        wb_we           =   we_i & wb_valid;
    wire        wb_re           =   ~we_i & wb_valid;

    // Main FSM
    reg  [1:0]  state, nstate;
    
    always @ (posedge clk_i or posedge rst_i)
        if(rst_i)
            state <= ST_INIT;
        else
            state <= nstate;

    always @* begin
        case(state)
            ST_INIT:
                nstate = ST_INIT_WAIT;
            
            ST_INIT_WAIT:
                if(init_done)
                    nstate = ST_IDLE;
                else
                    nstate = ST_INIT_WAIT;
            
            ST_IDLE:
                if(wb_valid)
                    nstate = ST_WAIT;
                else
                    nstate = ST_IDLE;

            ST_WAIT:
                if((mw_done & wb_we) | (mr_done & wb_re))
                    nstate = ST_IDLE;
                else
                    nstate = ST_WAIT;
                    
            default:
                nstate = ST_INIT;
        endcase
    end
    
    // QPI mode register - set after init completes
    always @ (posedge clk_i or posedge rst_i)
        if(rst_i)
            qpi_mode <= 1'b0;
        else if(init_done)
            qpi_mode <= 1'b1;

    // Init sequence state machine
    // Sends 0x35 command via SPI (1-bit serial, 8 SCK cycles)
    always @ (posedge clk_i or posedge rst_i) begin
        if(rst_i) begin
            init_state <= INIT_IDLE;
            init_counter <= 4'd0;
            init_sck <= 1'b0;
            init_ce_n <= 1'b1;
            init_dout <= 4'd0;
            init_doe <= 1'b0;
        end else begin
            case(init_state)
                INIT_IDLE: begin
                    if(state == ST_INIT) begin
                        init_state <= INIT_SEND;
                        init_ce_n <= 1'b0;
                        init_counter <= 4'd0;
                        init_doe <= 1'b1;
                    end
                end
                
                INIT_SEND: begin
                    // Toggle SCK and send command bits
                    init_sck <= ~init_sck;
                    if(init_sck) begin
                        // On falling edge, advance counter
                        init_counter <= init_counter + 4'd1;
                        if(init_counter == 4'd7) begin
                            init_state <= INIT_DONE;
                            init_ce_n <= 1'b1;
                            init_doe <= 1'b0;
                        end
                    end
                    // Output command bit (MSB first, on dio[0])
                    init_dout <= {3'b0, CMD_ENTER_QPI[7 - init_counter[2:0]]};
                end
                
                INIT_DONE: begin
                    init_sck <= 1'b0;
                    init_ce_n <= 1'b1;
                    init_doe <= 1'b0;
                end
            endcase
        end
    end
    
    assign init_done = (init_state == INIT_DONE);

    wire [2:0]  size =  (sel_i == 4'b0001) ? 1 :
                        (sel_i == 4'b0010) ? 1 :
                        (sel_i == 4'b0100) ? 1 :
                        (sel_i == 4'b1000) ? 1 :
                        (sel_i == 4'b0011) ? 2 :
                        (sel_i == 4'b1100) ? 2 :
                        (sel_i == 4'b1111) ? 4 : 4;



    wire [7:0]  byte0 = (sel_i[0])          ? dat_i[7:0]   :
                        (sel_i[1] & size==1)? dat_i[15:8]  :
                        (sel_i[2] & size==1)? dat_i[23:16] :
                        (sel_i[3] & size==1)? dat_i[31:24] :
                        (sel_i[2] & size==2)? dat_i[23:16] :
                        dat_i[7:0];

    wire [7:0]  byte1 = (sel_i[1])          ? dat_i[15:8]  :
                        dat_i[31:24];

    wire [7:0]  byte2 = dat_i[23:16];

    wire [7:0]  byte3 = dat_i[31:24];

    wire [31:0] wdata = {byte3, byte2, byte1, byte0};

    assign mr_rd    = ( (state==ST_IDLE ) & wb_re );
    assign mw_wr    = ( (state==ST_IDLE ) & wb_we );

    PSRAM_READER MR (
        .clk(clk_i),
        .rst_n(~rst_i),
        .addr({adr_i[23:2],2'b0}),
        .rd(mr_rd),
        .size(3'd4),
        .qpi_mode(qpi_mode),
        .done(mr_done),
        .line(dat_o),
        .sck(mr_sck),
        .ce_n(mr_ce_n),
        .din(mr_din),
        .dout(mr_dout),
        .douten(mr_doe)
    );

    PSRAM_WRITER MW (
        .clk(clk_i),
        .rst_n(~rst_i),
        .addr({adr_i[23:0]}),
        .wr(mw_wr),
        .size(size),
        .qpi_mode(qpi_mode),
        .done(mw_done),
        .line(wdata),
        .sck(mw_sck),
        .ce_n(mw_ce_n),
        .din(mw_din),
        .dout(mw_dout),
        .douten(mw_doe)
    );

    // Mux outputs based on current operation
    // During init: use init signals
    // During normal operation: use reader/writer signals
    wire in_init = (state == ST_INIT) || (state == ST_INIT_WAIT);
    
    assign sck  = in_init ? init_sck : (wb_we ? mw_sck  : mr_sck);
    assign ce_n = in_init ? init_ce_n : (wb_we ? mw_ce_n : mr_ce_n);
    assign dout = in_init ? init_dout : (wb_we ? mw_dout : mr_dout);
    assign douten = in_init ? {4{init_doe}} : (wb_we ? {4{mw_doe}} : {4{mr_doe}});

    assign mw_din = din;
    assign mr_din = din;
    assign ack_o = wb_we ? mw_done : mr_done;
    
endmodule
