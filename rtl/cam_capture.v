`timescale 1ns / 1ps
`default_nettype none

/* 
 *  Polls for when FPGA is done initializing OV7670 and skips first
 *  two VGA frames to allow for the register changes to settle; 
 *  outputs pixel data after 1st byte is registered and 2nd byte is at the 
 *  input; increments pixel address on the same cycle new pixel data is sent
 *
 *
 *   NOTE: 
 *   - For RGB444, format of pixel data 
 *      1st byte: {   X,    X,    X,    X, R[3], R[2], R[1], R[0]}
 *      2nd byte: {G[3], G[2], G[1], G[0], B[3], B[2], B[1], B[0]
 *   
 *   - Format of output pixel data:
 *      o_pix_data = {RRRR GGGG BBBB};
 *
 */

module cam_capture
    (   input wire         i_pclk,
        input wire         i_rstn,
        input wire         i_vsync,
        input wire         i_href,    
        input wire  [7:0]  i_D,
        input wire         i_cam_done,
        output reg  [11:0] o_pix_data,      
        output reg         o_pix_valid                   
    );
       
    // Negative/Positive Edge Detection of vsync for frame start/frame done signal
    reg         r1_vsync,    r2_vsync; 
    wire        frame_start, frame_done;
    
    initial { r1_vsync, r2_vsync } = 0; 
    always @(posedge i_pclk or negedge i_rstn)
    if(!i_rstn) {r2_vsync, r1_vsync} <= 2'b00;
    else        {r2_vsync, r1_vsync} <= {r1_vsync, i_vsync}; 
  
    assign frame_start = (r1_vsync == 0) && (r2_vsync == 1);    // Negative Edge of vsync
    assign frame_done  = (r1_vsync == 1) && (r2_vsync == 0);    // Positive Edge of vsync
     
    // FSM for capturing pixel data in pclk domain
    localparam [1:0] WAIT   = 2'd0,
                     IDLE   = 2'd1,
                     CAPTURE = 2'd2;
    
    reg        r_half_data;             
    reg [1:0]  SM_state;
    reg [3:0]  pixel_data;
                                                                         
    always @(posedge i_pclk or negedge i_rstn)
    if(!i_rstn) 
    begin
        SM_state    <= WAIT;
        o_pix_valid <= 0;
        o_pix_data  <= 0; 
        r_half_data <= 0; 
    end    
    else
        begin
        
            r_half_data <= 0; 
            o_pix_valid <= 0;

            case(SM_state)
                WAIT: 
                    begin
                        // Skip the first two frames on start-up
                        SM_state   <= (frame_start && i_cam_done) ? IDLE : WAIT;
                    end
                IDLE:        
                    begin
                        SM_state   <= (frame_start) ? CAPTURE : IDLE;
                    end
                CAPTURE:
                    begin
                        SM_state   <= (frame_done) ? IDLE : CAPTURE;
                        
                        if(i_href)
                            begin 
                                 // Register first byte
                                 if(!r_half_data)   
                                    pixel_data <= i_D[3:0];      
                                 r_half_data    <= ~r_half_data;                       
                                 o_pix_valid    <= (r_half_data) ? 1'b1 : 1'b0;
                                 o_pix_data     <= (r_half_data) ? {pixel_data, i_D} : o_pix_data; 
                            end 
                    end  
            endcase
        end
             
endmodule