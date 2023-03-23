`timescale 1ns / 1ps

module top_user_control_tb();

    // Period (ns) and frequency (Hz) of FPGA clock
    localparam T_SYS_CLK = 10;
    localparam F_SYS_CLK = 100_000_000;
    
    // I/O signals of DUT
    logic i_clk;
    logic i_rstn;

    logic i_inc_sobel_thresh;
    logic i_dec_sobel_thresh;
    logic [11:0] o_sobel_thresh;


    // Instantiate Device under test
    top_user_control
    DUT
    (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_inc_sobel_thresh(i_inc_sobel_thresh),
        .i_dec_sobel_thresh(i_dec_sobel_thresh),

        .o_sobel_thresh(o_sobel_thresh)
    );

    initial
    begin
        $dumpfile("DUT.vcd");
        $dumpvars(0, top_user_control_tb);
    end

    initial
    begin
        i_clk = 0;
        i_rstn = 0; 
        i_inc_sobel_thresh = 0;
        i_dec_sobel_thresh = 0;
    end

    // Create Clock
    always #(T_SYS_CLK/2) i_clk = ~i_clk;

    initial
    begin: TB
        applyReset(); 

        @(negedge i_clk);
        
        // Decrease threshold to 0
        for(integer i = 0; i < 100; i=i+1)
        begin
            decThreshold(); 
            repeat(240_001) @(posedge i_clk);
        end

        // Increase threshold to max
        for(integer k = 0; k < 100; k=k+1)
        begin
            incThreshold(); 
            repeat(240_001) @(posedge i_clk);
        end

        // Increase and Decresase threshold at same
        for(integer j = 0; j < 100; j=j+1)
        begin
            fork
                incThreshold(); 
                decThreshold();
                repeat(240_001) @(posedge i_clk);
            join 
        end

        $display("SUCCESS\n");
        $finish();

    end

    // Synchronous reset 
    task applyReset();
    begin
        i_rstn = 0; 
        repeat(2) @(posedge i_clk);
        
        i_rstn = 1'b1;
        @(posedge i_clk);
 
    end
    endtask 

    task incThreshold();
    begin
        repeat(240_002) @(negedge i_clk)
        i_inc_sobel_thresh = 1'b1;

        repeat(2) @(posedge i_clk)
        i_inc_sobel_thresh = 0;
    end
    endtask 

    task decThreshold();
    begin
        repeat(240_002) @(negedge i_clk)
        i_dec_sobel_thresh = 1'b1;
        
        repeat(2) @(posedge i_clk)
        i_dec_sobel_thresh = 0;
    end
    endtask 

    // Verify that sobel value changes as expected
    logic [11:0] expected_sobel_threshold; 
    logic [11:0] actual_sobel_threshold;
    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            expected_sobel_threshold = 1800; 
        end
        else begin

        if($past(DUT.p_inc_sobel_thresh, 2))
        begin
            if(expected_sobel_threshold + 200 >= {(12){1'b1}})
                expected_sobel_threshold = expected_sobel_threshold;
            else
                expected_sobel_threshold = expected_sobel_threshold + 200;
        end

        if($past(DUT.p_dec_sobel_thresh, 2))
        begin
            if(expected_sobel_threshold - 200 <= 0)
                expected_sobel_threshold = 0;
            else
                expected_sobel_threshold = expected_sobel_threshold - 200; 
        end
        
        actual_sobel_threshold = o_sobel_thresh; 

        assert(expected_sobel_threshold == actual_sobel_threshold)
        else
            $fatal(1, "Expected Threshold: 0x%h\nActual Threshold: 0x%h\n",
                    expected_sobel_threshold, actual_sobel_threshold);

        end
    end

    // Verify that the sobel threshold value always stays within
    // range
    always @*
        assert((o_sobel_thresh >= 0)
                && (o_sobel_thresh <= {(12){1'b1}}))
        else
            $fatal(1, "Invalid Threshold Value: 0x%h\n",
                        o_sobel_thresh);

endmodule