`timescale 1ns / 1ps

/*
 *  A self-check testbench that verifies
 *  pixel data captured is written to 
 *  output async FIFO; async FIFO is never full, 
 *  thereby no deadlocking occurs in the handshake;
 *  each clock cycle that valid and ready
 *  between cam_top and vp_top are asserted,
 *  ONE pixel data is transferred to vp_top  
 *
 */

module cam_top_tb(); 

    // Period (ns) of FPGA clock
    localparam T_SYS_CLK = 10;

    // Period (ns) of Camera Clock
    localparam T_PCLK = 41.667; 

    // Data Width of Pixel Data
    localparam DW = 12;

    // Number of Pixels per Row / Number of Rows per Frame
    localparam RL = 640;
    localparam ROW = 480; 

    // Number of Frames
    localparam FRAME = 2; 

    // cam_top I/O signals
    logic i_clk; 
    logic i_rstn_clk; 
    logic i_rstn_pclk; 
    logic i_cam_start;
    logic o_cam_done; 
    
    logic i_pclk;
    logic [7:0] i_pix_byte;
    logic       i_vsync;
    logic       i_href; 
    logic       o_reset;
    logic       o_pwdn; 
    logic       o_siod;
    logic       o_sioc; 

    wire        o_cam_data_valid; 
    wire [11:0] o_cam_data; 

    // I/O of vp_top
    wire vp_o_data_ready;
    wire vp_i_data_ready;
    wire vp_o_data_valid;
    wire [11:0] vp_o_data;

    // Instantiate vp_top
    vp_top
    #(  .DW(DW),
        .RL(RL) )
    vpDUT
    (
        .i_clk(i_clk),
        .i_rstn(i_rstn_clk),

        // Handshaking signals cam_top
        .o_data_ready(vp_o_data_ready),
        .i_data_valid(o_cam_data_valid),
        .i_data(o_cam_data), 

        // Handshaking signals mem_top
        .i_data_ready(vp_i_data_ready),
        .o_data_valid(vp_o_data_valid),
        .o_data(vp_o_data)
    );

    // Instantiate device under test 
    cam_top
    #(  .CAM_CONFIG_CLK(100_000_000))
    DUT
    (
        .i_clk(i_clk),
        .i_rstn_clk(i_rstn_clk),
        .i_rstn_pclk(i_rstn_pclk),

        .i_cam_start(i_cam_start),
        .o_cam_done(o_cam_done),

        .i_pclk(i_pclk),
        .i_pix_byte(i_pix_byte),
        .i_vsync(i_vsync),
        .i_href(i_href),
        .o_reset(o_reset),
        .o_pwdn(o_pwdn),
        .o_siod(o_siod),
        .o_sioc(o_sioc),

        .i_data_ready(vp_o_data_ready),
        .o_cam_data_valid(o_cam_data_valid),
        .o_cam_data(o_cam_data)
    );

    // Testbench 
    logic [11:0] pixel_data_queue [$];
    logic [7:0]  first_byte;

    initial
    begin
        $dumpfile("DUT.vcd");
        $dumpvars(0, cam_top_tb);
    end

    initial
    begin
        i_clk = 0;
        i_rstn_clk = 0;
        i_rstn_pclk = 0;

        i_cam_start = 0; 
        i_pclk = 0; 
        i_pix_byte = 0; 
        i_vsync = 0;
        i_href = 0;

    end

    // Create Clocks
    always #(T_SYS_CLK/2) i_clk = ~i_clk; 
    always #(T_PCLK/2)  i_pclk = ~i_pclk; 

    // Testbench
    initial
    begin: TB
        integer frame, row, pbyte;

        applyResets(); 
        
        // Skip camera initialization (tested with cam_init_tb.v)
        @(posedge i_pclk)
            force DUT.o_cam_done = 1'b1; 

        // Start VGA Frame (skipped)
        FrameStart();

        for(frame = 0; frame < FRAME; frame=frame+1)
        begin
            // Begin Frame (taking data)
            FrameStart();
            
            for(row = 0; row < ROW; row=row+1)
            begin

                for(pbyte = 0; pbyte < (2*RL); pbyte=pbyte+1)
                begin
                    @(negedge i_pclk);
                    
                    if(pbyte == 0)
                        i_href = 1'b1;
                    
                    // First Byte
                    if(pbyte % 2 == 0)
                    begin
                        i_pix_byte = $urandom_range(0, 255);
                        first_byte = i_pix_byte; 
                    end
                    // Second Byte
                    else begin
                        i_pix_byte = $urandom_range(0, 255);
                        pixel_data_queue.push_front({first_byte[3:0], i_pix_byte});
                    end
                end

                // Invalid data region (before next row) 
                @(negedge i_pclk)
                    i_href = 0; 
                repeat(288) @(posedge i_pclk);
            end

            // Invalid data region (before next frame)
            i_vsync = 0; 
            repeat(15680) @(negedge i_pclk);
        end

        $display("SUCCESS!\n");
        #(1_000_000);
        $finish(); 
    end

    // Asynchronous assertion, Synchronous deassertion
    task applyResets();
    begin
        i_rstn_clk  = 0;
        i_rstn_pclk = 0; 
        repeat (2) @(posedge i_pclk);

        @(posedge i_pclk);
        i_rstn_pclk = 1'b1;
        
        @(posedge i_clk);
        i_rstn_clk  = 1'b1;
    end
    endtask


    // VGA Timing of OV7670
    task FrameStart();
    begin
        i_vsync = 1'b1; 
        repeat(4704) @(posedge i_pclk);
        i_vsync = 0; 
        repeat(26656) @(posedge i_pclk);
    end
    endtask 


    // Verify that pixel data captured is correct
    logic [7:0] byte1;
    logic [7:0] byte2;
    logic [11:0] expected_cam_data;
    logic [11:0] actual_cam_data;

    always @(posedge i_pclk)
    begin
        if(i_rstn_pclk)
        begin
            if($rose(DUT.w_pix_valid))
            begin
                byte1 = $past(DUT.i_pix_byte, 2);
                byte2 = $past(DUT.i_pix_byte, 1);

                expected_cam_data = { byte1[3:0], byte2 };

                // From cam_top
                assert(expected_cam_data == DUT.w_pix_data)
                else
                    $fatal(1, "Expected Cam Data 0x%h\nActual Cam Data 0x%h\n",
                    expected_cam_data, DUT.w_pix_data);
                    
                // From sim
                actual_cam_data   = pixel_data_queue.pop_back();
                assert(expected_cam_data == actual_cam_data)
                else
                    $fatal(1, "Byte1 0x%h\nByte2 0x%h\nExpected 0x%h\nActual 0x%h",
                    byte1, byte2, expected_cam_data, actual_cam_data);
            end
        end    
    end
    
    // Verify  that the async fifo never gets filled (misses data)
    always @(posedge i_pclk)
    begin
        if(i_rstn_pclk)
        begin
            assert(DUT.cam_afifo.w_full !== 1'b1)
            else
                $fatal(1,"Async FIFO is full.\n");
        end
    end
    
    // Verify that only one pixel data is sent per handshake
    always @(posedge i_clk)
    begin
        if(i_rstn_clk)
        begin
            if(o_cam_data_valid & vp_o_data_ready)
                assert($past(o_cam_data) == $past(o_cam_data,2))
                else
                    $fatal(1, "More than one pixel data was sent during handshake.\n");
        end 
    end

    // Mimic handshake between mem_top and vp_top
    assign vp_i_data_ready = (vp_o_data_valid) ? 1'b1 : 0;

endmodule