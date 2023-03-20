`timescale 1ns / 1ps
`default_nettype none

/*
 *  Creates a three-word read memory that is a 
 *  first word fall through
 * 
 *  NOTE 
 *  o_data is not registered and available immediately  
 *
 */

module linebuffer
   #(   parameter DW = 12,
        parameter RL = 640)
    (   input wire              i_clk,
        input wire              i_rstn,
        
        input wire              i_wr_data,
        input wire [DW-1:0]     i_data, 
        
        input wire              i_rd_data,
        output wire [3*DW-1:0]  o_data
    );
    
    // Pointer Width 
    localparam PW = $clog2(RL); 
 
    reg [DW-1:0] line [RL-1:0];
    reg [PW-1:0] wptr;
    reg [PW-1:0] rptr;
    
    always @(posedge i_clk)
    begin
        if(i_wr_data)
            line[wptr] <= i_data;
    end
    
    always @(posedge i_clk)
    begin
        if(!i_rstn)
            wptr <= 0;
        else if(i_wr_data)
            wptr <= (wptr == RL - 1) ? 0 : wptr + 1'b1;
    end 
       
    always @(posedge i_clk)
    begin
        if(!i_rstn)
            rptr <= 0; 
        else if(i_rd_data)
            rptr <= (rptr == RL - 1) ? 0 : rptr + 1'b1; 
    end
    
    // First Word Fall Through  
    assign o_data = { line[rptr], line[rptr+1], line[rptr+2] }; 
        
endmodule
