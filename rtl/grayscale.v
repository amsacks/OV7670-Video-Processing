`timescale 1ns / 1ps
`default_nettype none

/*
 *  Converts RGB444 into grayscale
 *  using the luminosity method
 *  by the formula: 
 *  Grayscale = 0.299*R + 0.587*G + 0.114*B   
 *  
 *  Utilize bit-shifts and fixed-point arthmetic
 *  to reduce complexity, resources, while 
 *  still being somewhat precise
 *
 *  NOTE: 
 *  - Incoming pixel data format
 *     { R[3:0] , G[3:0], B[3:0]
 *  - Uses Q4.4 notation for fixed-point 
 * 
 */

module grayscale
    (   input wire         i_clk, 
        input wire         i_rstn, 
        
        input  wire [11:0] i_data,
        input  wire        i_data_valid, 
        
        output reg  [11:0] o_gray_data,
        output reg         o_gray_data_valid
    );
    
    wire [7:0] R;
    wire [7:0] G;
    wire [7:0] B;
    
    // Convert incoming RGB444 data into Q4.4 fixed-point format to increase resolution
    // to 1/16 = 0.0625 
    assign R = (i_data[11:8] << 4); 
    assign G = (i_data[7:4]  << 4);
    assign B = (i_data[3:0]  << 4);  
    
    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            o_gray_data       <= 0;
            o_gray_data_valid <= 0; 
        end
    else begin
        
        o_gray_data       <= 0;
        o_gray_data_valid <= 0; 
        
            if(i_data_valid)
            begin
                o_gray_data <= (R >> 2) + (R >> 5) +
                                (G >> 1) + (G >> 4) + 
                                (B >> 4) + (B >> 5); 
                o_gray_data_valid <= 1; 
            end 
        end
    end 
            
endmodule
