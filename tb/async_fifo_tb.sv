`timescale 1ns / 1ps

/*
 *  A simple self-check testbench that mainly 
 *  checks for the correct assertion/deassertion 
 *  of full/empty and almost full/almost empty flags. 
 *
 *  NOTE:
 *  - Must have AW_TB be greater than 3
 *  - Not complete: needs work on being able to apply
 *      for different  read/write clocks.
 *  
 */

module async_fifo_tb();

    // Period (ns) and frequency (Hz) of Read/Write CLK
    localparam T_RCLK = 20;
    localparam F_RCLK = 50_000_000;
    
    localparam T_WCLK = 10;
    localparam F_WCLK = 100_000_000; 

    // Data Width and Address Width of FIFO
    localparam DW_TB = 10;   
    localparam AW_TB = 10; 
    localparam DATA_VAL_MAX = (DW_TB << 2); 

    // Almost full parameter
    localparam AF_TB = (1 << AW_TB) - 4;

    // Write Domain I/O for DUT
    logic w_clk;
    logic w_rstn;
    logic w_en; 
    logic [DW_TB - 1: 0] i_dat;
    wire w_almost_full; 
    wire w_full;

    // Read Domain I/O for DUT
    logic r_clk;
    logic r_rstn;
    logic r_en;
    wire [DW_TB - 1: 0] o_dat; 
    wire r_almost_empty;
    wire r_empty; 

    // Instantiate device under test 
    async_fifo
    #(  .DW(DW_TB                       ), 
        .AW(AW_TB                       ))
    DUT
    (
        .w_clk(w_clk                    ),
        .w_rstn(w_rstn                  ),
        .w_en(w_en                      ),
        .i_dat(i_dat                    ),
        .w_almost_full(w_almost_full    ),
        .w_full(w_full                  ),

        .r_clk(r_clk                    ),
        .r_rstn(r_rstn                  ),
        .r_en(r_en                      ),
        .o_dat(o_dat                    ),
        .r_almost_empty(r_almost_empty  ),
        .r_empty(r_empty                )
    );
    
    // Testbench queue for data in and keep track of total FIFO fill level
    logic [DW_TB-1:0] tb_queue [$];
    logic [31:0] total_in_fifo = 0; 
    
    // Number of test cases
    localparam N_TB_WRITES              = (2 << AW_TB) - 2;
    localparam N_TB_READS               = (2 << AW_TB) + 10; 
    localparam N_TB_WRITES_AND_READS    = (2 << AW_TB) + 20;

    initial
    begin
        $dumpfile("DUT.vcd");
        $dumpvars(0,DUT);
    end

    initial
    begin
        w_clk = 0;
        w_rstn = 0; 
        w_en = 0;
        i_dat = {DW_TB{1'b0}}; 

        r_clk = 0;
        r_rstn = 0;
        r_en = 0; 
    end

    // Create Read/Write Clocks
    always #(T_RCLK/2) r_clk = ~r_clk;
    always #(T_WCLK/2) w_clk = ~w_clk;


    initial
    begin:TB
        integer j; 
        
        ApplyReset();
        
        @(negedge w_clk); 
        
        // Write to FIFO
        $display("Writing to FIFO.\n");
        w_en = 1'b1;
        r_en = 0;
        for(j = 0; j < N_TB_WRITES; j++)
        begin
            // Disable write enable before next posedge
            if(j == (N_TB_WRITES - 1))
                w_en = 0; 
               
            if(!w_full && w_en)
                writeFIFO(); 
            @(negedge w_clk); 
        end 

        
        @(negedge r_clk); 
        
        // Read from FIFO
        $display("Reading from FIFO.\n"); 
        r_en = 1'b1;
        for(j = 0; j < N_TB_READS; j++)
        begin
            if(!r_en)
                $fatal("Cannot read from FIFO when r_en is 0.\n"); 
            
            @(negedge r_clk); 
        end
        
        
        @(negedge r_clk);  
        w_en = 1'b1; 
        r_en = 1'b1; 
        
        // Write and Read FIFO
        $display("Writing and Reading FIFO.\n"); 
        
        for(j = 0; j < N_TB_WRITES_AND_READS; j++)
        begin
        
            // Disable write enable before next posedge
            if(j == (N_TB_WRITES_AND_READS - 1))
            begin
                w_en = 0;
            end     
            
            if(!w_full && w_en)
                writeFIFO();
            @(negedge w_clk);
            
        end 
                
        // Read from FIFO
        @(negedge r_clk);
        $display("Reading FIFO.\n"); 
        for(j = 0; j < N_TB_READS; j++)
            @(negedge r_clk);  
            
        $display("FINISH!"); 
        $finish();
    end // testbench

    /**
        Tasks and properties below.
    **/

    // Asynchronous assertion and Synchronous release of resets
    task ApplyReset();
    begin
        w_rstn    = 0;
        r_rstn    = 0;
        repeat(2) @(posedge w_clk);
        @(posedge w_clk)
        w_rstn    = 1;

        @(posedge r_clk)
            r_rstn    = 1;
    end    
    endtask
    
    // Verify task ApplyReset
    property reset_deassert_p;
        @(posedge w_clk) $rose(w_rstn)
                            |-> $rose(r_rstn);
    endproperty
    
    reset_deassert_p_chk: assert property(reset_deassert_p)
                            $display("Task ApplyReset correct.\n"); 
                          else
                            $fatal("Task ApplyReset incorrect.\n"); 
    
    // Write pseudorandom data within range of data width to FIFO
    task writeFIFO(); 
        i_dat = $urandom_range(0, DATA_VAL_MAX-1);
        tb_queue.push_front(i_dat);  
    endtask
    
    always @(posedge w_clk)
    begin
        if(!w_full && w_en)
            total_in_fifo = total_in_fifo + 1'b1;
    end 
    
    
    
    // Verify FIFO reads
    logic [DW_TB-1:0] tb_expected;
    logic [DW_TB-1:0] tb_actual;
    
    always @(posedge r_clk)
    begin
        if(!r_empty && r_en)
        begin
            tb_expected = tb_queue.pop_back(); 
            tb_actual   = o_dat;
            total_in_fifo = total_in_fifo - 1'b1; 
            assert(tb_expected == tb_actual)
                $display("Read data: 0x%h\n", o_dat); 
            else
                $fatal("Read FAIL. Expected: 0x%h, Actual: 0x%h\n", 
                tb_expected, tb_actual); 
        end
    end
    
    // Verify that empty/full flags
    property full_immediate_assertion_p;
        @(posedge w_clk) (DUT.wgraynext == { ~DUT.wq2_rptr[AW_TB:AW_TB-1],
                                            DUT.wq2_rptr[AW_TB-2:0] })
                          |=> (w_full == 1'b1); 
        
    endproperty 
    full_immediate_assertion_p_chk: assert property(full_immediate_assertion_p)
                                       $display("Full flag is asserted.\n"); 
                                    else
                                       $fatal("Full flag is NOT asserted.\n"); 
    
    property empty_immediate_assertion_p;
        @(posedge r_clk) (DUT.rq2_wptr == DUT.rgraynext)
                            |=> (r_empty == 1'b1);  
        
    endproperty 
    empty_immediate_assertion_p_chk: assert property(empty_immediate_assertion_p)
                                        $display("Empty flag is asserted.\n"); 
                                     else
                                        $fatal("Empty flag is NOT asserted.\n");
    
    // Verify that empty/full flags are deasserted pessimistically
    property full_pessimistic_deassertion_no_write_p;
        @(posedge w_clk) (w_full == 1'b1 && r_en == 1'b1 && !w_en)
                            |=> (DUT.rptr ^ DUT.rgraynext)
                            |-> ##2 (DUT.wgraynext != { ~DUT.wq2_rptr[AW_TB:AW_TB-1],
                                            DUT.wq2_rptr[AW_TB-2:0] });
                            
                 
    endproperty
    full_pessimistic_deassertion_p_no_write_chk: assert property(full_pessimistic_deassertion_no_write_p)
                                           $display("Full flag is deasserted pessimistically, no write.\n"); 
                                        else
                                           $fatal("Full flag is NOT deasserted pessimistically, no write.\n");
    
    property full_pessimistic_deassertion_with_write_p;
        @(posedge w_clk) (w_full == 1'b1 && r_en == 1'b1 && w_en == 1'b1)
                            |=> (w_full == 0); 
    endproperty
    full_pessimistic_deassertion_p_with_write_chk: assert property(full_pessimistic_deassertion_with_write_p)
                                           $display("Full flag is deasserted pessimistically, with write.\n"); 
                                        else
                                           $fatal("Full flag is NOT deasserted pessimistically, with write.\n");
    
    property empty_pessimistic_deassertion_p;
        @(posedge r_clk) ((r_empty == 1'b1 && w_en == 1'b1))
                            |->  ##4 (r_empty == 0);                       
    endproperty
    empty_pessimistic_deassertion_p_chk: assert property(empty_pessimistic_deassertion_p)
                                            $display("Empty flag is deasserted pessimistically.\n");
                                         else
                                            $fatal("Empty flag is NOT deasserted pessimistically.\n");
    
    // Property that almost empty/almost full flags are asserted correctly
    property almost_full_immediate_assertion_p; 
        @(posedge w_clk) (DUT.wbin_rbin_diff >= AF_TB)
                            |=> (w_almost_full == 1'b1); 
        
    endproperty
    almost_full_immediate_assertion_p_chk: assert property(almost_full_immediate_assertion_p)
                                              $display("Almost full is asserted.\n"); 
                                           else
                                              $fatal("Almost full is NOT asserted.\n");
                                              
    property almost_empty_immediate_assertion_p; 
        @(posedge r_clk) disable iff(r_rstn) (DUT.rbin_wbin_diff <= 4)
                            |=> (r_almost_empty == 1'b1); 
    endproperty
    almost_empty_immediate_assertion_p_chk: assert property(almost_empty_immediate_assertion_p)
                                                $display("Almost empty is asserted.\n"); 
                                            else
                                                $fatal("Almost empty is NOT asserted.\n"); 
 
    // Property that almost empty/almost full flags are deasserted correctly
    property almost_full_pessimistic_deassertion_p; 
        @(posedge w_clk) (DUT.wbin_rbin_diff < AF_TB)
                            |=> (w_almost_full == 1'b0);    
    endproperty
    almost_full_pessimistic_deassertion_p_chk: assert property(almost_full_pessimistic_deassertion_p)
                                                  $display("Almost full flag is deasserted.\n");
                                               else
                                                  $fatal("Almost full flag is NOT deasserted.\n");

    property almost_empty_pessimistic_deassertion_p; 
        @(posedge r_clk) disable iff(r_rstn) (DUT.rbin_wbin_diff > 4)
                            |=> (r_almost_empty == 1'b0); 
                
    endproperty
    almost_empty_pessimistic_deassertion_p_chk: assert property(almost_empty_pessimistic_deassertion_p)
                                                  $display("Almost empty flag is deasserted.\n");
                                               else
                                                  $fatal("Almost empty flag is NOT deasserted.\n");

endmodule
 