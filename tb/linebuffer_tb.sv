`timescale 1ns / 1ps

/*
 *  A simple self-check testbench that verifies
 *  read/write pointers always increment with an 
 *  enable signal and stay within the range of
 * [0, RL_TB-1]; the data written is read correctly 
 *  for an entire row length; 
 *
 */

module linebuffer_tb();

    // Period (ns) of CLK
    localparam T_CLK = 10; 
    
    // Data Width (DW) and Row Length (RL)
    localparam DW_TB     = 12;
    localparam RL_TB     = 640; 
    localparam DW_TB_MAX = (DW_TB << 2); 
    
    // I/O of linebuffer
    reg                     i_clk;
    reg                     i_rstn;
    reg [DW_TB - 1:0]       i_data;
    reg                     i_wr_data;
    reg                     i_rd_data;
    
    wire [3*DW_TB - 1 :0]   o_data;
    
    // Instantiate device under test
    linebuffer
    #(  .DW(DW_TB           ),
        .RL(RL_TB           )) 
    DUT
    (
        .i_clk(i_clk        ),
        .i_rstn(i_rstn      ), 
        .i_data(i_data      ),
        .i_wr_data(i_wr_data), 
        .i_rd_data(i_rd_data),
        .o_data(o_data      )
    );
    
    // Testbench queue
    logic [3*DW_TB - 1:0] tb_queue [$]; 
    
    // Initial Conditions
    initial
        begin
            i_clk       = 0;
            i_rstn      = 0;
            i_wr_data   = 0; 
            i_rd_data   = 0; 
        end 
   
   // Create TB CLK
   always #(T_CLK/2) i_clk = ~i_clk; 
   
   // Testbench initial block
   initial
        begin: TB

            // Apply synchronous reset
            Reset(); 
            @(negedge i_clk); 
            
            // Write Data
            i_wr_data = 1'b1; 
            i_rd_data = 0;
            
            for(integer i = 0; i < RL_TB; i++)
            begin 
                WriteData();
                
                // Special Case of first pixel
                if(i == 0)      tb_queue[0] = { {(2*DW_TB){1'bX}}, i_data};
                else if(i == 1) tb_queue[0] = { tb_queue[0], i_data};
                else if(i == 2) tb_queue[0] = { tb_queue[0], i_data};
                else            tb_queue.push_front({tb_queue[0], i_data});
                
                /* Special Case of last pixel   
                        wptr never writes to locations beyond RL_TB, then
                        when rptr is RL_TB-2, rptr+2 will point to invalid data
                        and be seen at o_data on that clock edge.
                */ 
                if(i == RL_TB-1)
                begin
                    tb_queue.push_front({tb_queue[0], {(DW_TB){1'bX}}});
                    tb_queue.push_front({tb_queue[0], {(DW_TB){1'bX}}});
                    tb_queue.push_front({tb_queue[0], {(DW_TB){1'bX}}});  
                end 
                @(negedge i_clk);
                
            end 
            
            // Read Data
            i_wr_data = 0;
            i_rd_data = 1'b1;
            @(negedge i_clk); 
            
            for(integer i = 0; i < RL_TB; i++)
            begin
                // Do not read last row, loops around
                if(i == RL_TB-1)
                    i_rd_data = 0; 
                @(negedge i_clk); 
            end 
            
            #(100_000); 
            
            $display("SUCCESS!\n"); 
            $finish(); 
        end

    // Create synchronous negedge reset
    task Reset();
        begin
            i_rstn = 0;
            repeat(2) @(posedge i_clk); 
            i_rstn = 1'b1; 
            @(posedge i_clk);   
        end
    endtask
   
    // Create pseudorandom data to write 
    task WriteData(); 
        begin
            i_data = $urandom_range(0, DW_TB_MAX - 1);
        end 
    endtask
   
    // Verify Read/Write pointers do not exceed Row Length (point to valid memory locations)
    always @(posedge i_clk) 
    if(i_rstn)
        begin
            assert(DUT.wptr >= 0 && DUT.wptr <= RL_TB)
            else
                $fatal("Write Pointer %d, is an invalid memory location.\n", DUT.wptr);
            assert(DUT.rptr >= 0 && DUT.rptr <= RL_TB)
            else
                $fatal("Read Pointer %d, is an invalid memory location.\n", DUT.rptr);           
        end
    
    // Verify Read/Write pointers wrap around and increment on a read/write enable signal
    always @(posedge i_clk)
    if(i_rstn)
        begin
            // Write pointer
            if($past(DUT.wptr == RL_TB - 1) && $past(i_wr_data))
                assert(DUT.wptr == 0); 
            else if($past(i_wr_data))
                assert(DUT.wptr == ($past(DUT.wptr) + 1'b1));
                
            // Read pointer           
            if($past(DUT.rptr == RL_TB - 1) && $past(i_rd_data))
                assert(DUT.rptr == 0); 
            else if($past(i_rd_data))
                assert(DUT.rptr == ($past(DUT.rptr) + 1'b1));    
        end 
    
    // Verify output data
    logic [3*DW_TB - 1:0] expected_o_data;
    
    always @(posedge i_clk)
    if(i_rstn)
        begin
            if(i_rd_data)
            begin
                expected_o_data = tb_queue.pop_back(); 
                assert(o_data === expected_o_data)
                else
                    $fatal("Expected: 0x%h\n Actual: 0x%h\n\n",
                        expected_o_data, o_data);
            end                          
        end
    else
        assert(o_data === {(3*DW_TB){1'bX}}); 
  
endmodule
