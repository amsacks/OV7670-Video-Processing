`timescale 1ns / 1ps
/* 
 *  
 *  An asynchronous FIFO that allows the buffering of data between
 *  two clock domains. The empty and full status flags are asserted
 *  immediately, but are removed pessimistically (i.e. 2 clock cycles late)
 *  due to the latency of using double FFs to synchronize the write
 *  and read pointers between the clock domains.
 *                                  
 *  Formally verified.
 *
 *  NOTE:
 *  - AW must be greater than 3
 *  - Almost empty flag is asserted when FIFO level is within 4 from being empty
 *  - Almost full flag is asserted when FIFO level is within 4 from being full
 * 
 */
`default_nettype none

module async_fifo
    #(  parameter DW  = 4,
        parameter AW  = 4 ) 
    (   input wire              w_clk,
        input wire              w_rstn,
        input wire              w_en,
        input wire [DW-1:0]     i_dat,
        output reg              w_almost_full,
        output reg              w_full,
        
        input wire              r_clk, 
        input wire              r_rstn,
        input wire              r_en,
        output wire [DW-1:0]    o_dat,
        output reg              r_almost_empty, 
        output reg              r_empty
    );
    
    // Almost full parameter, 4 less than full
    localparam AF = (1 << AW) - 4;
  
    // Write domain logic
    wire [AW - 1 : 0] waddr;              // write address in memory 
    wire [AW     : 0] wgraynext;          
    wire [AW     : 0] wbinnext;
    wire              wfull_val;
    wire              walmost_full_val;
    
    reg [AW: 0] wbin;                     // write pointer in binary to address memory
    reg [AW: 0] wptr;                     // write pointer in gray for (almost) empty/(almost) full flags
    reg [AW: 0] wq1_rptr;
    reg [AW: 0] wq2_rptr; 
    
    initial { wq2_rptr, wq1_rptr }  = 0;
    initial { wbin, wptr } = 0;
    initial w_full = 0;
    
    // Read domain logic
    wire [AW - 1 :0] raddr;               // read address in memory 
    wire [AW     :0] rgraynext;
    wire [AW     :0] rbinnext; 
    wire             rempty_val;
    wire             ralmost_empty_val;

    reg [AW      :0] rbin;                // read pointer in binary to address memory
    reg [AW      :0] rptr;                // read pointer in gray for (almost) empty/(almost) full flags
    reg [AW      :0] rq1_wptr;            
    reg [AW      :0] rq2_wptr;
    
    initial { rq2_wptr, rq1_wptr } = 0;
    initial { rbin, rptr } = 0;
    initial r_empty = 1'b1; 
    
    // FIFO Memory Style: Synchronous Dual-Port RAM
    reg [DW-1:0] mem [0:((1<<AW)-1)]; 
    
    assign o_dat = mem[raddr]; 

    always @(posedge w_clk)
        if((w_en) && (!w_full)) 
            mem[waddr] <= i_dat; 
   
   /** =======================================================
      
                            Read-Domain Logic
   
       ======================================================= **/ 
       
    // Double FF to synchronize and recude metastability of 
    // write pointer in gray to read clock domain
    always @(posedge r_clk or negedge r_rstn)
        begin
            if(!r_rstn) {rq2_wptr, rq1_wptr} <= 0;
            else        {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr}; 
        end 
    
    // Register next binary and gray read pointers
    always @(posedge r_clk or negedge r_rstn)
        begin
            if(!r_rstn) {rbin, rptr} <= 0;
            else        {rbin, rptr} <= {rbinnext, rgraynext}; 
        end 
    
    // Read address and binary/gray read pointer logic
    assign raddr     =  rbin[AW-1:0];  
    assign rbinnext  =  rbin + { {(AW){1'b0}}, (r_en && (!r_empty)) };
    assign rgraynext = (rbinnext >> 1) ^ rbinnext; 
    
    // Logic for FIFO is empty
    always @(posedge r_clk or negedge r_rstn)
        begin
            if(!r_rstn) r_empty <= 1'b1;
            else        r_empty <= rempty_val; 
        end 
    assign rempty_val = (rq2_wptr == rgraynext); 
   
   // Logic for FIFO is almost empty in 3 steps.
   wire [AW :0] rq2_wptr_bin;  
   wire [AW :0] rbin_wbin_diff;
   
   // 1st: Convert write pointer in gray code to binary
   assign rq2_wptr_bin[AW] = rq2_wptr[AW]; 
   generate
        genvar k;
        for(k = AW - 1; k >= 0; k = k - 1)        
            begin
                assign rq2_wptr_bin[k] = rq2_wptr_bin[k+1] ^ rq2_wptr[k];
            end
        endgenerate
   
   // 2nd: Find difference between binary read and write pointers.
   /*      Check whether the difference is within the threshold.
            - There are two cases since a FIFO is a circular queue.
                Case 1: read pointer > write pointer. 
                    
                    Logic for difference: synchronized wptr_bin - rptr_bin + POINTER DEPTH
                     
                Case 2: read pointer <= write pointer                                             
            
                    Logic for difference: synchronized wptr_bin - rptr_bin
                    
   */
   assign rbin_wbin_diff     = (rbinnext > rq2_wptr_bin) ? (rq2_wptr_bin - rbinnext 
                                                              + (1 << (AW+1)))
                                                            : (rq2_wptr_bin - rbinnext);
   assign ralmost_empty_val  = (rbin_wbin_diff <= 4);

   always @(posedge r_clk or negedge r_rstn)
       begin
           if(!r_rstn)  r_almost_empty <= 1'b1;
           else         r_almost_empty <= ralmost_empty_val;
       end
       
       
    /** =======================================================
      
                            Write-Domain Logic
   
       ======================================================= **/   
       
    // Double FF to synchronize read pointer to write clock domain
    always @(posedge w_clk or negedge w_rstn)
        begin
            if(!w_rstn) {wq2_rptr, wq1_rptr} <= 0;
            else        {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr}; 
        end  
    
    // Write Binary and Gray pointer
    always @(posedge w_clk or negedge w_rstn)
        begin
            if(!w_rstn) {wbin, wptr} <= 0;
            else        {wbin, wptr} <= {wbinnext, wgraynext}; 
        end
           
    // Use binary to address FIFO memory. Use Gray for synchronizing and logic for almost empty/empty flags   
    assign waddr     = wbin[AW-1:0];
    assign wbinnext  = wbin + { {(AW){1'b0}}, (w_en && (!w_full)) };
    assign wgraynext = (wbinnext >> 1) ^ wbinnext; 
    
    
    // Logic for FIFO is full
    always @(posedge w_clk or negedge w_rstn)
        begin
            if(!w_rstn) w_full <= 1'b0;
            else        w_full <= wfull_val; 
        end 
    
    assign wfull_val = (wgraynext == {~wq2_rptr[AW:AW-1], 
                                    wq2_rptr[AW-2:0]});  
                         
    
    // Logic for FIFO is almost full (similar to logic for when FIFO is empty)
    wire [AW :0] wq2_rptr_bin;  
    wire [AW :0] wbin_rbin_diff;
    assign wq2_rptr_bin[AW] = wq2_rptr[AW]; 
    generate 
        genvar j;
        for(j = AW - 1; j >= 0; j = j - 1)
            begin
                assign wq2_rptr_bin[j] = wq2_rptr_bin[j+1] ^ wq2_rptr[j]; 
            end 
        endgenerate 
    
    assign wbin_rbin_diff  = (wbinnext > wq2_rptr_bin) ? (wbinnext - wq2_rptr_bin) 
                                                        : (wbinnext - wq2_rptr_bin
                                                           + (1 << (AW+1))); 
    assign walmost_full_val = (wbin_rbin_diff >=  AF);
                                                  
    always @(posedge w_clk or negedge w_rstn)
       begin
           if(!w_rstn) w_almost_full <= 1'b0; 
           else        w_almost_full <= walmost_full_val;
       end                                                                                               

`ifdef FORMAL

    // Setting up f_past_valid registers for three clock domains: read, write, global sim
    reg f_past_valid_rd;
    reg f_past_valid_wr;
    reg f_past_valid_gbl; 
    initial 
        begin
            f_past_valid_rd = 0;
            f_past_valid_wr = 0;
            f_past_valid_gbl = 0; 
        end 
    
    always @($global_clock)
        f_past_valid_gbl <= 1'b1;
    
    always @(posedge w_clk)
        f_past_valid_wr <= 1'b1;
    
    always @(posedge r_clk)
        f_past_valid_rd <= 1'b1;

    always @(*)
        if(!f_past_valid_gbl)
            assert((!f_past_valid_wr) && (!f_past_valid_rd)); 
`ifdef AFIFO

    // Setup the two read and write clocks
    localparam F_CLKBITS = 5;
    wire [F_CLKBITS-1:0] f_wclk_step;
    wire [F_CLKBITS-1:0] f_rclk_step;
    
    assign f_wclk_step = $anyconst; 
    assign f_rclk_step = $anyconst;
    always @(*)
        begin
            assume(f_wclk_step != 0);
            assume(f_rclk_step != 0);
        end
    
    reg [F_CLKBITS-1:0] f_wclk_count;
    reg [F_CLKBITS-1:0] f_rclk_count;
    always @($global_clock)
        begin
            f_wclk_count <= f_wclk_count + f_wclk_step;
            f_rclk_count <= f_rclk_count + f_rclk_step; 
        end 
    always @(*)
        begin
            assume(w_clk == (f_wclk_count[F_CLKBITS-1]));
            assume(r_clk == (f_rclk_count[F_CLKBITS-1]));
        end 
`endif
    
    // Assume reset input wires are asynch asserted, but only synch de-asserted
    //initial assume (w_rstn == 1'b0);
    //initial assume (r_rstn == 1'b0); 
    initial assume(w_rstn == r_rstn);
    
    always @($global_clock)
        assume($fell(w_rstn) == $fell(r_rstn));
    always @($global_clock)
        if(!$rose(w_clk))
            assume(!$rose(w_rstn));
    always @($global_clock)
        if(!$rose(r_clk))
            assume(!$rose(r_rstn));
    always @($global_clock)
        if(!w_rstn)
            assert(rbin == 0); 
    
    // Assume that input wires can only change on clock edges
    // Assert that the full/empty flags are stable, 
    always @($global_clock)
        if(f_past_valid_gbl)
        begin
            if(!$rose(w_clk))
            begin
                assume($stable(w_en));
                assume($stable(i_dat));
                assert($stable(w_full) || (!w_rstn));
            end
            
            if(!$rose(r_clk))
            begin
                assume($stable(r_en));
                assert((r_empty) || ($stable(o_dat)));
                assert((!r_rstn) || ($stable(r_empty)));
            end 
        end 
    
    // Assert cross clock values are in a known configuration
    always @($global_clock)
        if((!f_past_valid_wr) || (!w_rstn))   // Either at reset or at initial start of formal
        begin
            assume(w_en == 0);
            
            assert(wptr == 0);
            assert(wbin == 0);
            assert(!w_full); 
            
            assert(wq1_rptr == 0);
            assert(wq2_rptr == 0);
            assert(rq1_wptr == 0);
            assert(rq2_wptr == 0);
            
            assert(rbin == 0);
            assert(r_empty); 
        end
    
    always @($global_clock)
        if((!f_past_valid_rd) || (!r_rstn))
        begin
            assume(r_en == 0);
            
            assert(rptr == 0);
            assert(rbin == 0); 
            assert(wq1_rptr == 0);
            assert(wq2_rptr == 0);
            assert(rq1_wptr == 0);
            assert(rq2_wptr == 0);
            
        end 
    
    // Calculate the fill level of FIFO (needs to be between 0 and 2^(AW))
    wire [AW:0] f_fill;
    assign f_fill = (wbin - rbin);
    initial assert(f_fill == 0);
    always @($global_clock)
        assert(f_fill <= { 1'b1, {(AW){1'b0}} });
    
    // Assert that if FIFO is full, then w_full should be 1
    always @($global_clock)
        if(f_fill == { 1'b1, {(AW){1'b0}}})
            assert(w_full);
    
    // Assert that logic will detect if FIFO is about to be full
    always @($global_clock)
        if(f_fill == { 1'b0, {(AW){1'b1}}})
            assert((wfull_val)||(!w_en)||(w_full));
            
    // Assert that if FIFO is empty, then r_empty should be 1
    always @($global_clock)
        if(f_fill == 0)
            assert(r_empty);
    
    // Assert that logic will detect if FIFO is about to be empty
    always @($global_clock)
        if(f_fill == 1)
            assert((rempty_val)||(!r_en)||(r_empty));
    
    // Assert that the gray coded pointers are copies of the binary addresses 
    always @(*)
        begin
            assert(wptr == ((wbin >> 1) ^ wbin));
        end 
    always @(*)
        begin
            assert(rptr == ((rbin >> 1) ^ rbin));
        end 
    
    // Assert that the FIFO is full based off the read and write gray pointers are equal
    always @(*)
        assert( (rptr == { ~wptr[AW:AW-1], wptr[AW-2:0] }) 
                == (f_fill == { 1'b1, {(AW){1'b0}} }));
    // Assert that the pointers should only equal when FIFO is empty 
    always @(*)
        assert((rptr == wptr) == (f_fill == 0)); 
    
    // Examine fill/empty flags from read or write clock POV
    reg [AW:0] f_w2r_rbin; 
    reg [AW:0] f_w1r_rbin;
    reg [AW:0] f_r2w_wbin;
    reg [AW:0] f_r1w_wbin;
    wire [AW:0] f_w2r_fill;
    wire [AW:0] f_r2w_fill;
    
    /** Note: since formal has no metastability, no need to pass
    *   gray pointers but can use binary values across clock domains.
    **/
    initial { f_w2r_rbin, f_w1r_rbin } = 0;
    initial { f_r2w_wbin, f_r1w_wbin } = 0;
    always @(posedge w_clk or negedge w_rstn)
        if(!w_rstn)
            { f_w2r_rbin, f_w1r_rbin } <= 0;
        else
            { f_w2r_rbin, f_w1r_rbin } <= { f_w1r_rbin, rbin }; 
    always @(posedge r_clk or negedge r_rstn)
        if(!r_rstn)
            { f_r2w_wbin, f_r1w_wbin } <= 0;
        else
            { f_r2w_wbin, f_r1w_wbin } <= { f_r1w_wbin, wbin };
    
    // Calculate fill level from perspective of each clock domain
    // 1st: Assert each converted binary pointer is equal to its gray counterpart 
    always @(*)
        assert(rq1_wptr == ((f_r1w_wbin >> 1)^f_r1w_wbin));
    always @(*)
        assert(rq2_wptr == ((f_r2w_wbin >> 1)^f_r2w_wbin));
    always @(*)
        assert(wq1_rptr == ((f_w1r_rbin >> 1)^f_w1r_rbin));
    always @(*)
        assert(wq2_rptr == ((f_w2r_rbin >> 1)^f_w2r_rbin)); 
    assign f_w2r_fill = wbin - f_w2r_rbin; 
    assign f_r2w_fill = f_r2w_wbin - rbin; 
    
    // 2nd: Assert that fill is always less than or equal to full
    always @(*)
        assert(f_w2r_fill <= { 1'b1, {(AW){1'b0} }});
    always @(*)
        assert(f_r2w_fill <= { 1'b1, {(AW){1'b0} }});
    
    // From write clock POV, FIFO is full if gray pointers are =, 
    // except for the MSB. Assert this property of the FIFO.
    always @(*)
        if(wptr == {  ~wq2_rptr[AW:AW-1], wq2_rptr[AW-2:0] })
            assert(w_full);
    // For the read clock POV
    always @(*)
        if(rptr == rq2_wptr)
            assert(r_empty); 

    // Assert that at most one bit of gray coded pointer values
    // will ever change when crossing clock domains
    
    genvar i;
    generate 
        for(i = 0; i <= AW; i=i+1)
        begin: CHECK_ONEHOT_WGRAY
            always @(*)
                assert((wptr[i] == wgraynext[i])
                    ||(wptr ^ wgraynext ^ (1<<i) == 0));
            always @(*)
                assert((rq2_wptr[i] == rq1_wptr[i])
                    ||(rq2_wptr ^ rq1_wptr ^ (1<<i) == 0)); 
        end 
    endgenerate 
    
    genvar k; 
    generate
        for(k = 0; k <= AW; k=k+1)
        begin: CHECK_ONEHOT_RGRAY
            always @(*)
                assert((rptr[k] == rgraynext[k])
                    || (rptr ^ rgraynext ^ (1<<k) == 0));
            always @(*)
                assert((wq2_rptr[k] == wq1_rptr[k])
                    ||(wq2_rptr ^ wq1_rptr ^ (1<<k) == 0));
        end 
    endgenerate     

   /** FIFO contract: If two subsequent values are written, then 
                      those values must be read out later in the 
                      same order.
    **/
`ifdef AFIFO

   (* anyconst *) wire [AW:0] f_const_addr; 
                  wire [AW:0] f_const_next_addr;
    assign f_const_next_addr = f_const_addr + 1'b1; 
    
    (* anyconst *) reg [DW-1:0] f_const_first_data;
    (* anyconst *) reg [DW-1:0] f_const_next_data; 
   
                   reg f_addr_valid;
                   reg f_addr_next_valid; 
    always @(*)
        begin
            f_addr_valid = 1'b0;
            if((wbin > rbin) && (wbin > f_const_addr) && (rbin <= f_const_addr))
                // rbin <= addr < wbin
                f_addr_valid = 1'b1; 
            else if((wbin < rbin) && (wbin > f_const_addr))
                // addr < wbin < rbin
                f_addr_valid = 1'b1;
            else if((wbin < rbin) && (rbin <= f_const_addr))
                // wbin < rbin < addr
                f_addr_valid = 1'b1;  
        end               
   
    always @(*)
        begin
            f_addr_next_valid = 1'b0; 
            if((wbin > rbin)&&(wbin > f_const_next_addr)&&(rbin <= f_const_next_addr))
                // rbin <= addr < wbin
                f_addr_next_valid = 1'b1;
            else if ((wbin < rbin)&&(f_const_next_addr < wbin))
                // addr < wbin < rbin
                f_addr_next_valid = 1'b1;
            else if ((wbin < rbin)&&(rbin <= f_const_next_addr))
                // wbin < rbin < addr
                f_addr_next_valid = 1'b1;
        end 

    reg f_first_in_fifo;
    reg f_second_in_fifo;
    reg f_both_in_fifo;
    
    always @(*)
        f_first_in_fifo = (f_addr_valid) 
                        && (mem[f_const_addr[AW-1:0]] == f_const_first_data);    
    always @(*)
        f_second_in_fifo = (f_addr_next_valid)
                        && (mem[f_const_next_addr[AW-1:0]]==f_const_next_data);
    always @(*)
        f_both_in_fifo = (f_first_in_fifo) && (f_second_in_fifo);
    
    reg f_wait_for_first_read;
    reg f_read_first;
    reg f_read_second;
    reg f_wait_for_second_read;
    
    always @(*)
        f_wait_for_first_read = (f_both_in_fifo)
                               && ((!r_en)||(f_const_addr != rbin)||(r_empty));
    always @(*)
        f_read_first = (r_en) && (o_dat == f_const_first_data)&&(!r_empty)
                    && (rbin == f_const_addr)&&(f_both_in_fifo);
    always @(*)
        f_wait_for_second_read = (f_second_in_fifo)
                        && ((!r_en) || (r_empty))
                        && (f_const_next_addr == rbin); 
    always @(*)
        f_read_second = (r_en) && (o_dat == f_const_next_data) && (!r_empty)
                        && (rbin == f_const_next_addr)
                        && (f_second_in_fifo);   
   
   always @($global_clock)
        if((f_past_valid_gbl) && (w_rstn))
            begin
                if((!$past(f_read_first))&&($past(f_both_in_fifo)))
                    assert((f_wait_for_first_read) || (($rose(r_clk))&&(f_read_first)));
                if($past(f_read_first))
                    assert( ((!$rose(r_clk))&&(f_read_first))
                    || ($rose(r_clk)&&((f_read_second)
                                    || (f_wait_for_second_read))));
                if($past(f_wait_for_second_read))
                    assert((f_wait_for_second_read)
                            || (($rose(r_clk)) && (f_read_second)));
            end  
`endif
    
    
    always @(posedge w_clk)
        cover(w_rstn); 
    always @(posedge r_clk)
        cover(r_rstn); 
        
    always @($global_clock)
        if(f_past_valid_gbl)
            cover((r_empty)&&(!$past(r_empty)));
    
    always @(*)
        if(f_past_valid_gbl)
            cover(w_full); 
            
    always @(posedge w_clk)
        if(f_past_valid_wr)
            cover($past(w_full)&&($past(w_en))&&(w_full));
            
    always @(posedge w_clk)
	   if (f_past_valid_wr)
		  cover($past(w_full)&&(!w_full));
		  
    always @(posedge w_clk)
        cover((w_full)&&(w_en));
        
    always @(posedge w_clk)
        cover(w_en);
        
    always @(posedge r_clk)
        cover((r_empty) && (r_en));
    
`endif 
endmodule
