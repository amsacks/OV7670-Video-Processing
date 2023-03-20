`timescale 1ns / 1ps
`default_nettype none

/*
 *  Accepts cam pixel data from cam_top
 *  through a ready/valid handshake; pixel
 *  data is converted to grayscale to reduce
 *  information in order to ease computation
 *  when applying a sobel filter (vp_control,
 *  conv); output FIFO buffer to deal with
 *  data mismatch 
 *
 */

module vp_top
    #(  parameter DW = 12,
        parameter RL = 640 )
    (
        input wire i_clk,
        input wire i_rstn,

        // Cam_top interface
        output reg          o_data_ready,
        input wire          i_data_valid,
        input wire [DW-1:0] i_data,       

        // Handshake with mem_top
        input wire           i_data_ready,
        output wire          o_data_valid,
        output wire [DW-1:0] o_data         
    );
    
    wire [DW-1:0]   w_gray_data;
    wire            w_gray_data_valid; 
    
    wire [9*DW-1:0] w_pixel_data;
    wire            w_pixel_valid;
    
    wire [DW-1:0]   w_convolved_data;
    wire            w_fifo_wr;
    wire            w_fifo_AF; 
    wire            w_fifo_AE; 
    
    /*
    Avoid deadlocks:
        - Wait for VALID signal from cam_top to be asserted
          before asserting READY (connected to read signal of
          afifo)
        - Only have o_data_ready as a tick, otherwise will cause
          two transactions  
    */
    
    reg state; 
    reg q_data_valid;
    
    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            state        <= 0; 
            o_data_ready <= 0;
            q_data_valid <= 0; 
        end
    else begin
            case(state)
            0: begin
            
                q_data_valid <= 0;
                o_data_ready <= 0; 
                
                if(i_data_valid)
                    begin
                        o_data_ready <= (!w_fifo_AF);
                        state        <= 1;  
                    end
            end
            1: begin
                q_data_valid <= o_data_ready;
                o_data_ready <= 0; 
                state <= 0; 
            end
            endcase  
        end
    end  
    
    grayscale
    vp_gray
    (
        .i_clk(i_clk), 
        .i_rstn(i_rstn),
        .i_data(i_data), 
        .i_data_valid(q_data_valid),
        .o_gray_data(w_gray_data), 
        .o_gray_data_valid(w_gray_data_valid)
    );
    
    vp_control
    #(  .DW(DW),  
        .RL(RL))
    vp_linebuffers
    (
        .i_clk(i_clk),
        .i_rstn(i_rstn),

        .i_pixel_data(w_gray_data), 
        .i_pixel_data_valid(w_gray_data_valid),

        .o_pixel_data(w_pixel_data),
        .o_pixel_valid(w_pixel_valid)
    );

    conv
    #(  .DW(DW))
    vp_sobel
    (   
        .i_clk(i_clk),
        .i_rstn(i_rstn),  
        .i_data(w_pixel_data),
        .i_valid(w_pixel_valid), 
        
        .o_data(w_convolved_data), 
        .o_valid(w_fifo_wr) 
    );

    sync_fifo
    #(  .DW(DW),
        .AW(4),
        .AFW(3),
        .AEW(1)         )
    vp_outputFIFO
    (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
    
        // Write Signals
        .i_wr(w_fifo_wr),
        .i_data(w_convolved_data),
        .o_full(), 
        .o_almost_full(w_fifo_AF),
                
        // Read Signals
        .i_rd(i_data_ready),
        .o_data(o_data),
        .o_empty(),
        .o_almost_empty(w_fifo_AE),      
    
        // FIFO fill level
        .o_fill()
    );

    assign o_data_valid = !w_fifo_AE;

endmodule