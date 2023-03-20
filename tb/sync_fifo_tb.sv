`timescale 1ns / 1ps

/*
 *  A simple self-check testbench that
 *  verifies what is written to FIFO is 
 *  read out in the same order; the status 
 *  flags are delayed one clock cycle; the 
 *  fill level stays within the depth range
 *  of FIFO
 *
 */


module sync_fifo_tb(); 

    // Period (ns) of CLK
    localparam T_CLK = 10; 

    // Data Width (DW) and Address Width (AW) of FIFO
    localparam DW_TB = 8; 
    localparam AW_TB = 10; 
    localparam DW_TB_MAX = DW_TB << 2;

    // Almost full/ Almost Empty Width (Must be smaller than AW_TB)
    localparam AFW_TB = 9;
    localparam AEW_TB = 3; 

    // I/O of FIFO
    logic                   i_clk;
    logic                   i_rstn; 

    logic                   i_wr;
    logic [DW_TB - 1 : 0]   i_data;
    logic                   o_full;
    logic                   o_almost_full;

    logic                   i_rd;
    logic [DW_TB - 1 : 0]   o_data;
    logic                   o_empty;
    logic                   o_almost_empty; 

    logic [AW_TB : 0]       o_fill;

    // Instantiate device under test
    sync_fifo
    #(  .DW(DW_TB),
        .AW(AW_TB),
        .AFW(AFW_TB),
        .AEW(AEW_TB)      )
    DUT
    (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        
        .i_wr(i_wr),
        .i_data(i_data),
        .o_full(o_full),
        .o_almost_full(o_almost_full),

        .i_rd(i_rd),
        .o_data(o_data),
        .o_empty(o_empty),
        .o_almost_empty(o_almost_empty),
        .o_fill(o_fill)
    );

    initial 
    begin
        $dumpfile("sync_fifo_tb.vcd");
        $dumpvars(0, sync_fifo_tb);
    end

    // Testbench queue
    logic [3*DW_TB - 1:0] tb_queue [$];

    // Initial Conditions
    initial
    begin
        i_clk = 0;
        i_rstn = 1'b1;
        i_wr = 0;
        i_rd = 0; 
    end

    // Create TB CLK
    always #(T_CLK/2) i_clk = ~i_clk;

    // Testbench initial block
    initial
    begin: TB
        integer i;
        AsyncReset();
        
        i_wr = 1'b1;
        i_rd = 0;
        @(negedge i_clk);
        $display("Writing Data.\n");
        for(i = 0; i < (1 << AW_TB) + 10; i++)
        begin
            WriteData();
            @(negedge i_clk);
        end

        i_wr = 0; 
        i_rd = 1'b1;
        @(negedge i_clk);
        $display("Reading Data.\n");
        for(i = 0; i < (1 << AW_TB); i++)
        begin
            @(negedge i_clk);
        end

        #(100);

        $display("FINISH!");
        $finish();
    end

    // Apply asynch negedge reset
    task AsyncReset();
        @(posedge i_clk);
        i_rstn = 1'b1;
        #(T_CLK/8)
        i_rstn = 1'b0;
        #(T_CLK/8)
        i_rstn = 1'b1; 
        #(T_CLK/8)
        @(posedge i_clk);
    endtask

    // Write Data
    task WriteData();
        i_data = $urandom_range(0, DW_TB_MAX-1);
        tb_queue.push_front(i_data);
    endtask

    // Verify reads from FIFO
    logic [DW_TB-1:0] tb_expected;
    logic [DW_TB-1:0] tb_actual;

    always @(posedge i_clk)
    begin
        if(i_rd && !o_empty)
        begin
            tb_expected = tb_queue.pop_back();
            tb_actual = o_data; 
            assert(tb_expected == tb_actual)
            else
                $fatal(1,"Expected Read Data: 0x%h\nActual Read Data: 0x%h\n\n",
                    tb_expected, tb_actual);
        end
    end

    // Verify that pointer difference does not exceed FIFO depth
    always @(posedge i_clk)
        if(DUT.wptr >= DUT.rptr)
            assert((DUT.wptr - DUT.rptr) <= (1<<AW_TB));
        else
            assert((DUT.rptr - DUT.wptr) <= (1<<AW_TB));

    // Verify that status flags are asserted one clock cycle late 
    property full_flag_assert_p;
        @(posedge i_clk) (!o_full && (o_fill == { 1'b0, {(AW_TB){1'b1}}}) && DUT.w_wr && (!DUT.w_rd))
                            |=> ##1 (o_full == 1'b1);
    endproperty
    full_flag_assert_p_chk: assert property(full_flag_assert_p)
                                $display("Full flag assert.\n");
                            else
                                $fatal(1, "Full flag did not assert one clock later.\n");

    property almost_full_flag_assert_p;
        @(posedge i_clk) (!o_almost_full && (o_fill == { 1'b0, {(AW_TB-AFW_TB){1'b0}}, {(AFW_TB){1'b1}}}) && DUT.w_wr && (!DUT.w_rd))
                            |=> ##1 (o_almost_full == 1'b1);
    endproperty
    almost_full_flag_assert_p_chk: assert property(almost_full_flag_assert_p)
                                        $display("Almost full flag assert.\n");
                                    else
                                        $fatal(1, "Almost full flag did not assert one clock later.\n");

    property empty_flag_assert_p;
        @(posedge i_clk)  (!o_empty && (o_fill == 1) && (!DUT.w_wr) && DUT.w_rd)
                            |=> ##1 (o_empty == 1'b1);
    endproperty
    empty_flag_assert_p_chk: assert property(empty_flag_assert_p)
                                $display("Empty flag assert.\n");
                            else
                                $fatal(1, "Empty flag did not assert one clock later.\n");

    property almost_empty_flag_assert_p;
        @(posedge i_clk)  (!o_almost_empty && (o_fill == (1<<AEW_TB)) && (!DUT.w_wr) && DUT.w_rd)
                            |=> ##1 (o_almost_empty == 1'b1);
    endproperty
    almost_empty_flag_assert_p_chk: assert property(almost_empty_flag_assert_p)
                                $display("Almost empty flag assert.\n");
                            else
                                $fatal(1, "Almost empty flag did not assert one clock later.\n");
                            


    // Verify that status flags are deasserted one clock cycle late
    property full_flag_deassert_p;
        @(posedge i_clk) (o_full && (o_fill == { 1'b0, {(AW_TB){1'b1}}}) && (!DUT.w_wr) && DUT.w_rd)  
                            |=> ##1 (!o_full); 
    endproperty
    full_flag_deassert_p_chk: assert property(full_flag_deassert_p)
                                    $display("Full flag deassert.\n");
                                else
                                    $fatal(1, "Full flag did not deassert one clock late.\n");
    property almost_full_flag_deassert_p;
        @(posedge i_clk) (o_almost_full && (o_fill == { 1'b0, {(AW_TB-AFW_TB){1'b0}}, {(AFW_TB){1'b1}}}) && (!DUT.w_wr) && DUT.w_rd)
                            |=> ##1 (!o_almost_full);
    endproperty
    almost_full_flag_deassert_p_chk: assert property(almost_full_flag_deassert_p)
                                        $display("Almost full flag deassert.\n");
                                     else
                                        $fatal(1, "Almost full flag did not deassert one clock late.\n");

    property empty_flag_deassert_p;
        @(posedge i_clk) (o_empty && (o_fill == 0) && DUT.w_wr && (!DUT.w_rd))
                                |=> ##1 (!o_empty);
    endproperty
    empty_flag_deassert_p_chk: assert property(empty_flag_deassert_p)
                                    $display("Empty flag deassert.\n");
                                else
                                    $fatal(1, "Empty flag did not deassert one clock late.\n");

    property almost_empty_flag_deassert_p;
        @(posedge i_clk) (o_almost_empty && (o_fill == (1<<AFW_TB)) && DUT.w_wr && (!DUT.w_rd))
                                |=> ##1 (!o_almost_empty);
    endproperty 
    almost_empty_flag_deassert_p_chk: assert property(almost_empty_flag_deassert_p)
                                        $display("Almost empty deassert.\n");
                                      else
                                        $fatal(1, "Almost empty flag did not deassert one clock late.\n");
    
endmodule