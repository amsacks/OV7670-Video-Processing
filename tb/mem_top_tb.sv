`timescale 1ns / 1ps

/*
 *  Verifies handshake between vp_top and mem_top
 *   
 * 
 */

module mem_top_tb();

    // Period (ns) of FPGA clock
    localparam T_CLK = 10;

    // Period (ns) of VGA clock
    localparam T_VCLK = 40; 

    // Data Width of Pixel Data
    localparam DW = 12;

    // mem_top I/O signals
    logic i_clk;
    logic i_clk25m;
    logic i_rstn;

    logic o_data_ready;
    logic i_data_valid;
    logic [DW-1:0] i_data;

    logic [18:0] i_vga_addr;
    logic [DW-1:0] o_vga_data;

    // Instantiate device under test 
    mem_top
    #(  .DW(DW))
    DUT
    (
        .i_clk(i_clk),
        .i_clk25m(i_clk25m),
        .i_rstn(i_rstn),

        .o_data_ready(o_data_ready),
        .i_data_valid(i_data_valid),
        .i_data(i_data),

        .i_vga_addr(i_vga_addr),
        .o_vga_data(o_vga_data)
    );

    // Testbench 
    logic [11:0] tb_queue [$];

    initial
    begin
        $dumpfile("DUT.vcd");
        $dumpvars(0, mem_top_tb);
    end


    initial
    begin
        i_clk = 0; 
        i_clk25m = 0; 
        i_rstn = 0; 

        i_data_valid = 0;
        i_data = 0;

        i_vga_addr = 0; 
    end

    // Create Clocks
    always #(T_CLK/2) i_clk = ~i_clk;
    always #(T_VCLK/2) i_clk25m = ~i_clk25m;

    // Testbench
    initial
    begin: TB
        
        applyResets();
        
        @(negedge i_clk);
        
        i_data_valid = 1'b1; 
        @(negedge i_clk);

        // Pad queue since BRAM read latency is one clock
        tb_queue.push_front({(DW){1'b0}});

        for (integer k = 0; k < 480; k=k+1)
        begin
            for(integer i = 0; i < 640; i=i+1)
            begin
                @(negedge i_clk);
                i_data = $urandom_range(0, (1 << DW) - 1);
                tb_queue.push_front(i_data);
            end 
        end

        i_data_valid = 0; 
        @(negedge i_clk);
        
        $display("SUCCESS\n");

        $finish();
    end

    // Asynchronous assertion, Synchronous deassertion
    task applyResets();
    begin
        i_clk  = 0;
        repeat (2) @(posedge i_clk);

        @(posedge i_clk);
        i_rstn = 1'b1;
        
        @(posedge i_clk);
        i_rstn  = 1'b1;
    end
    endtask

    // Verify one pixel data gets written per transaction
    always @(posedge i_clk)
    begin
        if(i_rstn)
        begin
            // When BRAM write enable is HIGH, a transaction takes place
            // except for last data
            if(DUT.r_data_valid) begin
                
                assert($past(i_data_valid & o_data_ready))
                else
                    $fatal(1, "BRAM is written only when valid and ready are HIGH\n");
                
                // BRAM write address always increments on a new transaction
                if($past(DUT.r_vp_addr == 307199))
                    assert(DUT.r_vp_addr == 0)
                    else
                        $fatal(1, "BRAM address needs to reset to 0\n");
                else
                    assert(DUT.r_vp_addr == ($past(DUT.r_vp_addr) + 1'b1))
                    else
                        $fatal(1, "BRAM write address did not increment on handshake.\n");
            end
        end 
    end
    

    // Verify reads from VGA
    logic [DW-1: 0] expected_data;
    logic [DW-1: 0] actual_data;

    always @(posedge i_clk25m)
    begin
        if($fell(i_data_valid))
        begin
            
            i_vga_addr <= i_vga_addr + 1'b1;

            expected_data = tb_queue.pop_back();
            actual_data = o_vga_data; 
            assert(expected_data === actual_data)
            else
                $fatal(1, "Expected BRAM data 0x%h \n Actual BRAM data 0x%h \n",
                expected_data, actual_data);
        end
    end


endmodule