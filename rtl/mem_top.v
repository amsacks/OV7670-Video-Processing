`timescale 1ns / 1ps
`default_nettype none

/*
 *  Reads video processed data from vp_top via
 *  handshake; Generates appropriate BRAM write
 *  address based off handshake; vga_top reads
 *  from BRAM 
 * 
 *
 */

module mem_top
    #(  parameter DW = 12)
    (  
        input wire i_clk, 
        input wire i_clk25m,
        input wire i_rstn,
        
        // Handshake between mem_top and vp_top
        output wire          o_data_ready,
        input wire           i_data_valid,
        input wire [DW-1:0]  i_data,

        // vga_top interface
        input wire [18:0]    i_vga_addr, 
        output wire [DW-1:0] o_vga_data
    );
    
    reg        r_data_valid;   
    reg [11:0] r_vp_data;
    reg [18:0] r_vp_addr; 
    
    // Start reading vp output FIFO if there's data
    assign o_data_ready = i_data_valid;
    
    // BRAM Write Address Generator 
    always @(posedge i_clk)
    begin
        if(!i_rstn) 
        begin
            r_vp_addr    <= 0; 
            r_data_valid <= 0;
        end 
        else begin
            r_data_valid <=  0;
            if(i_data_valid) begin
                r_vp_addr    <= (r_vp_addr == 307199) ? 0 : r_vp_addr + 1'b1;
                r_data_valid <= 1'b1; 
            end
        end
    end
    
    mem_bram
    #(  .WIDTH(DW                 ), 
        .DEPTH(640*480)           )
     pixel_memory
     (
        // BRAM Write signals 
        .i_wclk(i_clk             ),
        .i_wr(r_data_valid        ), 
        .i_wr_addr(r_vp_addr      ),
        .i_bram_data(i_data       ),
        .i_bram_en(1'b1           ),
         
         // BRAM Read signals 
        .i_rclk(i_clk25m          ),
        .i_rd(1'b1                ),
        .i_rd_addr(i_vga_addr     ), 
        .o_bram_data(o_vga_data   )
     );
    
endmodule