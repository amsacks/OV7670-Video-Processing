`timescale 1ns / 1ps
`default_nettype none

/*
 *  Controls read and writes
 *  from the 4 linebuffers;
 *  writes from 3 linebuffers are
 *  immediately available as 
 *  the output pixel data to be
 *  fed into a 3x3 kernel for video
 *  processing
 *
 */

module vp_control
    #(  parameter DW = 8,
        parameter RL = 640)    
    (
        input wire           i_clk,
        input wire           i_rstn,

        input wire [DW-1:0]    i_pixel_data, 
        input wire             i_pixel_data_valid,

        output reg [9*DW-1:0]  o_pixel_data,
        output wire            o_pixel_valid
    );

    // (Total) Row length and (Total) Counter width
    localparam CW   = $clog2(RL);
    localparam RL_T = 3*RL;
    localparam CW_T = $clog2(RL_T); 

    reg [CW-1:0] pixelCounter;
    reg [1:0]    currWrlinebuffer; 
    reg [3:0]    dataValidlinebuffer;

    reg [CW-1:0] rdCounter;
    reg [1:0]    currRdlinebuffer; 
    reg [3:0]    rdlinebuffer;
    reg          rd;
    reg          rd_state;
    localparam IDLE = 0;
    localparam READ = 1;

    reg [CW_T - 1: 0] totalpixelCounter;

    wire [3*DW - 1: 0] lb0data,
                        lb1data,
                        lb2data,
                        lb3data;

    // Keep track of total pixel data in all linebuffers - FSM controls read by
    // waiting for sufficient data in linebuffers (i.e. 3 linebuffers are filled with data in order to apply 3x3 kernel conv)
    always @(posedge i_clk)
    begin
        if(!i_rstn)
            totalpixelCounter <= 0;
        else begin
            
            if(i_pixel_data_valid && !rd)
                totalpixelCounter <= totalpixelCounter + 1'b1;
            else if(!i_pixel_data_valid && rd)
                totalpixelCounter <= totalpixelCounter - 1'b1; 
  
        end
    end

    // FSM to control linebuffer reads
    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            rd            <= 0;
            rd_state      <= IDLE;
        end
        else begin
            case(rd_state)
            IDLE: begin
                if(totalpixelCounter >= (3*RL - 1))
                begin
                    rd            <= 1'b1;
                    rd_state      <= READ;
                end
            end
            READ: begin
                if(rdCounter == (RL -1))
                begin
                    rd <= 0; 
                    rd_state <= IDLE; 
                end
            end
            endcase
        end 
    end


    // Keep track of total pixels written to linebuffers - once a linebuffer is 
    // filled, move to the next linebuffer
    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            pixelCounter <= 0; 
        end
        else begin
            if(i_pixel_data_valid)
                pixelCounter <= (pixelCounter == (RL-1)) ? 0 : pixelCounter + 1'b1;
        end
    end

    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            currWrlinebuffer <= 0;
        end
        else begin
            if((pixelCounter == (RL-1)) && i_pixel_data_valid)
            begin
                currWrlinebuffer <= currWrlinebuffer + 1'b1; 
            end 
        end
    end

    always @(*)
    begin
        dataValidlinebuffer = 4'h0;
        dataValidlinebuffer[currWrlinebuffer] = i_pixel_data_valid;
    end

    // Keep track of number of reads from linebuffer - once a linebuffer is
    // read, read the next linebuffer 
    always @(posedge i_clk)
    begin
        if(!i_rstn)
            rdCounter <= 0;
        else begin
                if(rd)
                    rdCounter <= (rdCounter == (RL - 1)) ? 0 : rdCounter + 1'b1;  
            end
    end

    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin   
            currRdlinebuffer <= 0;
        end 
        else begin
            if((rdCounter == (RL-1)) && rd)
            begin
                currRdlinebuffer <= currRdlinebuffer + 1'b1; 
            end 
        end
    end

    always @(*)
    begin
        case(currRdlinebuffer)
        0: begin
            rdlinebuffer[0] = rd;
            rdlinebuffer[1] = rd; 
            rdlinebuffer[2] = rd;
            rdlinebuffer[3] = 0; 
        end
        1: begin
            rdlinebuffer[0] = 0;
            rdlinebuffer[1] = rd; 
            rdlinebuffer[2] = rd;
            rdlinebuffer[3] = rd;
        end
        2: begin
            rdlinebuffer[0] = rd;
            rdlinebuffer[1] = 0; 
            rdlinebuffer[2] = rd;
            rdlinebuffer[3] = rd;
        end
        3: begin
            rdlinebuffer[0] = rd;
            rdlinebuffer[1] = rd; 
            rdlinebuffer[2] = 0;
            rdlinebuffer[3] = rd;
        end
        endcase
    end

    // Zero read latency for linebuffer, apply combinatorial logic to access data
    assign o_pixel_valid = rd; 

    always @(*)
    begin
        case(currRdlinebuffer)
        0: begin
            o_pixel_data = {lb2data, lb1data, lb0data};
        end
        1: begin
            o_pixel_data = {lb3data, lb2data, lb1data};            
        end
        2: begin
            o_pixel_data = {lb0data, lb3data, lb2data};
        end
        3: begin
            o_pixel_data = {lb1data, lb0data, lb3data};
        end
        endcase
    end
    

    // Instantiate 4 linebuffers - make use of low-level 
    // parallelism by  
    linebuffer 
    #(  .DW(DW),
        .RL(RL)                             )
    lB0
    (
        .i_clk(i_clk                        ),
        .i_rstn(i_rstn                      ),
        .i_wr_data(dataValidlinebuffer[0]   ),
        .i_data(i_pixel_data                ), 

        .i_rd_data(rdlinebuffer[0]          ), 
        .o_data(lb0data                     )
    );

    linebuffer 
    #(  .DW(DW),
        .RL(RL)                             )           
    lB1
    (
        .i_clk(i_clk                        ),
        .i_rstn(i_rstn                      ),
        .i_wr_data(dataValidlinebuffer[1]   ),
        .i_data(i_pixel_data                ), 

        .i_rd_data(rdlinebuffer[1]          ), 
        .o_data(lb1data                     )
    );

    linebuffer 
    #(  .DW(DW),
        .RL(RL)                             )
    lB2
    (
        .i_clk(i_clk                        ),
        .i_rstn(i_rstn                      ),
        .i_wr_data(dataValidlinebuffer[2]   ),
        .i_data(i_pixel_data                ), 

        .i_rd_data(rdlinebuffer[2]          ), 
        .o_data(lb2data                     )
    );

    linebuffer 
    #(  .DW(DW),
        .RL(RL)                             )
    lB3
    (
        .i_clk(i_clk                        ),
        .i_rstn(i_rstn                      ),
        .i_wr_data(dataValidlinebuffer[3]   ),
        .i_data(i_pixel_data                ), 

        .i_rd_data(rdlinebuffer[3]          ), 
        .o_data(lb3data                     )
    );


endmodule
