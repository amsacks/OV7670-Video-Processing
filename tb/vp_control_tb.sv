`timescale 1ns / 1ps

/*
 *  So far only verifies the first 
 *  current read line buffer (INCOMPLETE)
 * 
 */


module vp_control_tb();

    // Period (ns) of FPGA clock
    localparam T_CLK = 10;

    // Data Width and Row Length
    localparam DW = 8;
    localparam RL = 640; 

    // I/O signals of vp_control
    logic i_clk;
    logic i_rstn;

    logic [DW-1:0]      i_pixel_data;
    logic               i_pixel_data_valid;

    logic [9*DW-1:0]    o_pixel_data;
    logic               o_pixel_valid;


    // Instantiate device under test 
    vp_control
    #(  .DW(DW),
        .RL(RL))
    DUT
    (
        .i_clk(i_clk),
        .i_rstn(i_rstn),

        .i_pixel_data(i_pixel_data),
        .i_pixel_data_valid(i_pixel_data_valid),

        .o_pixel_data(o_pixel_data),
        .o_pixel_valid(o_pixel_valid)
    );

    // Testbench 
    logic [DW-1:0] tb_queue0 [$];
    logic [DW-1:0] tb_queue1 [$];
    logic [DW-1:0] tb_queue2 [$];
    logic [DW-1:0] tb_queue3 [$];
    logic [31:0] totalPixels;

    initial
    begin
        $dumpfile("DUT.vcd");
        $dumpvars(0, vp_control_tb);
    end


    initial
    begin
        i_clk = 0;
        i_rstn = 0; 
        i_pixel_data = 0;
        i_pixel_data_valid = 0;
    end

    // Create Clock
    always #(T_CLK/2) i_clk = ~i_clk;

    // Start testbench
    initial
    begin: TB
        applyReset();
        repeat(10) @(negedge i_clk);
        #(60_000)
        $display("SUCCESS!");
        $finish();
    end

    task applyReset();
    begin
        i_rstn = 0; 
        repeat (2) @(posedge i_clk);
        
        i_rstn = 1'b1;
        @(posedge i_clk);
    end
    endtask

    // Send data and keep track of total pixels in buffers
    always @(posedge i_clk)
    begin
        if(!i_rstn)
            totalPixels <= 0;
        else begin 

            if(o_pixel_valid)
                totalPixels <= totalPixels - 1'b1; 

            writeData(); 

            totalPixels <= (totalPixels >= 3*RL) ? 
                0 : totalPixels + 1'b1; 

            if(totalPixels > 0 && totalPixels <= RL)
                tb_queue0.push_front(i_pixel_data);
            else if(totalPixels > RL && totalPixels <= (2*RL))
                tb_queue1.push_front(i_pixel_data);
            else if(totalPixels > (2*RL) && totalPixels <= (3*RL))
                tb_queue2.push_front(i_pixel_data);
                
            end
    end

    task writeData(); 
    begin
        i_pixel_data <= $urandom_range(0, (1 << DW) - 1);
        i_pixel_data_valid <= 1'b1; 
    end
    endtask

    // Verify read enable takes place when there's enough pixels
    // to apply filter
    always @(posedge i_clk)
    begin
        if(i_rstn)
        begin
            if(totalPixels < (3*RL) && (DUT.rd_state != 1))
                assert(DUT.rd == 0)
                else
                   $fatal(1, "Reading with less than 3*RL pixels\n");

            if(totalPixels > (3*RL) && (DUT.rd_state != 0))
                assert(DUT.rd)
                else
                    $fatal(1, "Should read when more than 3*RL pixels\n");
        end
    end

    // Keep Track of which linebuffers are being read
    logic [2:0] rd_linebuffer;
    always @(posedge i_clk)
    begin
        if(!i_rstn)
            rd_linebuffer <= 0; 
        else begin
            if($rose(DUT.rd))
                rd_linebuffer <= rd_linebuffer + 1'b1;
        end 
    end

    // Check Output from linebuffer0
    logic [DW-1:0] tb_data01;
    logic [DW-1:0] tb_data02;
    logic [DW-1:0] tb_data03; 
    logic [3*DW - 1: 0] tb_expected0; 

    task LB0_Output();

    begin
        for(integer i = 0; i < RL; i=i+1)
        begin
            @(negedge i_clk);
            // o_data = { data1, data2 , data3 }
            
            // Special Case of first pixel
            if(i == 0) begin
                tb_data01 = tb_queue0.pop_back(); 
                tb_data02 = tb_queue0.pop_back();
                tb_data03 = tb_queue0.pop_back();
            end
            // Special Case of last 2 pixels
            else if(i >= (RL-2)) begin
                tb_data01 = tb_data02;
                tb_data02 = tb_data03;
                tb_data03 = {{(3*DW){1'bX}}};
            end

            else begin
                tb_data01 = tb_data02;
                tb_data02 = tb_data03; 
                tb_data03 = tb_queue0.pop_back(); 
            end

            tb_expected0 = { tb_data01, tb_data02, tb_data03 };
            assert(tb_expected0 === DUT.lb0data)
            else
                $fatal(1, "Expected Data LB0: 0x%h\nActual Data LB0: 0x%h\n",
                tb_expected0, DUT.lb0data);
        end
    end
    endtask 

    // Check Output from linebuffer1
    logic [DW-1:0] tb_data11;
    logic [DW-1:0] tb_data12;
    logic [DW-1:0] tb_data13; 
    logic [3*DW - 1: 0] tb_expected1; 

    task LB1_Output();

    begin
        for(integer i = 0; i < RL; i=i+1)
        begin
            @(negedge i_clk);
            // o_data = { data1, data2 , data3 }
            
            // Special Case of first pixel
            if(i == 0) begin
                tb_data11 = tb_queue1.pop_back(); 
                tb_data12 = tb_queue1.pop_back();
                tb_data13 = tb_queue1.pop_back();
            end
            // Special Case of last 2 pixels
            else if(i >= (RL-2)) begin
                tb_data11 = tb_data12;
                tb_data12 = tb_data13;
                tb_data13 = {{(3*DW){1'bX}}};
            end

            else begin
                tb_data11 = tb_data12;
                tb_data12 = tb_data13; 
                tb_data13 = tb_queue1.pop_back(); 
            end

            tb_expected1 = { tb_data11, tb_data12, tb_data13 };
            assert(tb_expected1 === DUT.lb1data)
            else
                $fatal(1, "Expected Data LB1: 0x%h\nActual Data LB1: 0x%h\n",
                tb_expected1, DUT.lb1data);
        end
    end
    endtask

    // Check Output from linebuffer2
    logic [DW-1:0] tb_data21;
    logic [DW-1:0] tb_data22;
    logic [DW-1:0] tb_data23; 
    logic [3*DW - 1: 0] tb_expected2; 

    task LB2_Output();

    begin
        for(integer i = 0; i < RL; i=i+1)
        begin
            @(negedge i_clk);
            // o_data = { data1, data2 , data3 }
            
            // Special Case of first pixel
            if(i == 0) begin
                tb_data21 = tb_queue2.pop_back();
                tb_data22 = tb_queue2.pop_back();
                tb_data23 = tb_queue2.pop_back();
            end
            // Special Case of last 2 pixels
            else if(i >= (RL-2)) begin
                tb_data21 = tb_data22;
                tb_data22 = tb_data23;
                tb_data23 = {{(3*DW){1'bX}}};
            end

            else begin
                tb_data21 = tb_data22;
                tb_data22 = tb_data23; 
                tb_data23 = tb_queue2.pop_back();
            end

            tb_expected2 = { tb_data21, tb_data22, tb_data23 };
            assert(tb_expected2 === DUT.lb2data)
            else
                $fatal(1, "Expected Data LB2: 0x%h\nActual Data LB2: 0x%h\n",
                tb_expected2, DUT.lb2data);
        end
    end
    endtask

    // Check Output from linebuffer1
    logic [DW-1:0] tb_data31;
    logic [DW-1:0] tb_data32;
    logic [DW-1:0] tb_data33; 
    logic [3*DW - 1: 0] tb_expected3; 

    task LB3_Output();


    begin
        for(integer i = 0; i < RL; i=i+1)
        begin
            @(negedge i_clk);
            // o_data = { data1, data2 , data3 }
            
            // Special Case of first pixel
            if(i == 0) begin
                tb_data31 = tb_queue3.pop_back();
                tb_data32 = tb_queue3.pop_back();
                tb_data33 = tb_queue3.pop_back();
            end
            // Special Case of last 2 pixels
            else if(i >= (RL-2)) begin
                tb_data31 = tb_data32;
                tb_data32 = tb_data33;
                tb_data33 = {{(3*DW){1'bX}}};
            end

            else begin
                tb_data31 = tb_data32;
                tb_data32 = tb_data33; 
                tb_data33 = tb_queue3.pop_back();
            end

            tb_expected3 = { tb_data31, tb_data32, tb_data33 };
            assert(tb_expected3 === DUT.lb3data)
            else
                $fatal(1, "Expected Data LB3: 0x%h\nActual Data LB3: 0x%h\n",
                tb_expected3, DUT.lb3data);
        end
    end
    endtask

    // Verify linebuffer output 
    always @(posedge o_pixel_valid)
    begin
        case(rd_linebuffer)
        0: fork
            LB0_Output();
            LB1_Output(); 
            LB2_Output();
        join
        endcase
    end

endmodule