`timescale 1ns / 1ps 
`default_nettype none 

/*
 *  Synchronous FIFO buffer that allows for (1 << AW)
 *  unique entries; FIFO is constructed from BRAM. 
 *  Output data is registered; Status flags are 
 *  registered and asserted/deasserted with one 
 *  clock cycle delay
 *
 *  NOTE:
 *  - AW must be greater than 3
 *  - Almost full  is asserted when 4 less than full
 *  - Almost empty is asserted when 4 more than empty
 *
 */


module sync_fifo
    #(	parameter DW = 8,    
        parameter AW = 4 )
    (
        input wire          i_clk,
        input wire          i_rstn,
    
        // Write Signals
        input wire          i_wr,
        input wire [DW-1:0] i_data,
        output reg          o_full, 
        output reg          o_almost_full,
                
        // Read Signals
        input wire          i_rd,
        output reg [DW-1:0] o_data,
        output reg          o_empty,
        output reg          o_almost_empty,      
    
        // FIFO fill level
        output reg [AW:0]   o_fill
    );

	// Define memory of FIFO of depth (1 << AW)
	reg [DW-1:0] mem [0: (1<<AW)-1];
    
    reg [AW:0]   wptr;
    reg [AW:0]   rptr;
    reg [AW-1:0] rptr_nxt; 

    // Valid Read/Write 
    wire w_rd = i_rd && !o_empty;
    wire w_wr = i_wr && !o_full;
    
    // Write to FIFO
    always @(posedge i_clk)
        if(w_wr)
            mem[wptr[AW-1:0]] <= i_data;
    
    // Read from FIFO
    always @(posedge i_clk) 
        o_data <= mem[ (w_rd) ? rptr_nxt : rptr[AW-1:0] ];

    // Update Read/Write Pointers
    always @(posedge i_clk or negedge i_rstn)
    begin
        if(!i_rstn)
        begin
            wptr <= 0;
            rptr <= 0;
        end
        else begin
            if(w_wr)
                wptr <= wptr + 1'b1;
            if(w_rd)
                rptr <= rptr + 1'b1;
        end
    end

    // Next read pointer
    always @(*)
        rptr_nxt = rptr[AW-1:0] + 1'b1;

    // Update FIFO status flags
    always @(posedge i_clk or negedge i_rstn)
    begin
        if(!i_rstn) 
        begin
            o_fill <= 0;
            o_full <= 0;
            o_empty <= 1'b1; 
        end 
        else begin
            
            // Fill level
            if(w_rd && (!w_wr))
                o_fill <= o_fill - 1'b1;
            else if((!w_rd) && w_wr)
                o_fill <= o_fill + 1'b1;
            
            // Empty Flag
            if((o_fill > 1) || ((o_fill == 1) && (!w_rd)))
                o_empty <= 0;
            else
                o_empty <= 1'b1;
            
            // Almost Empty Flag: 4 more than empty flag
            if((o_fill > 4) || ((o_fill == 4) && (!w_rd))) 
                o_almost_empty <= 0;
            else
                o_almost_empty <= 1'b1;

            // Full Flag
            if((o_fill < { 1'b0, {(AW){1'b1}}}) || ((o_fill == { 1'b0, {(AW){1'b1}}}) && (!w_wr)))
                o_full <= 0;
            else
                o_full <= 1'b1;
            
            // Almost Full Flag: 4 less than full flag
            if((o_fill < { 1'b0, {(AW-2){1'b1}}, 2'b00}) || ((o_fill == { 1'b0, {(AW-2){1'b1}}, 2'b00}) && (!w_wr)))
                o_almost_full <= 0;
            else
                o_almost_full <= 1'b1; 
        end
    end

endmodule
