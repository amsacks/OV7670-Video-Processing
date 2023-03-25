`timescale 1ns / 1ns

/* 
 *  Self-check test bench that verifies the
 *  pixel data retrieved from cam_top is 
 *  correctly streamed to vp_top, then converted to grayscale,
 *  streamed to mem_top and then is read sequentially in
 *  BRAM; self-check on multi-clock reset in top
 *  
 */
 
module top_tb();

    // Period (ns) and frequency (Hz) of FPGA clock
    localparam T_SYS_CLK = 10;
    localparam F_SYS_CLK = 100_000_000;
    
    // Period (ns) and frequency (Hz) of VGA Pixel clock
    localparam T_VGA_CLK = 40; 
    localparam F_VGA_CLK = 25_000_000; 
    
    // Period (ns) and frequency (Hz) of PCLK
    localparam T_P_CLK = 41.667;
    localparam F_P_CLK = 24_000_000;

    // Number of clocks for button debounce
    localparam DELAY = 240_000; 
    
    // VGA Frame Timing 
    localparam nFrames = 2,
                nRows   = 640,
                nPixelsPerRow = 480;  
    
    // top I/O signals
    logic       i_top_clk;
    logic       i_top_rst;
    
    logic       i_top_cam_start;
    logic       o_top_cam_done;
    
    logic       i_top_inc_sobel_thresh;
    logic       i_top_dec_sobel_thresh;
    
    logic       i_top_pclk;
    logic [7:0] i_top_pix_byte;
    logic       i_top_pix_vsync;
    logic       i_top_pix_href;
    logic       o_top_reset;
    logic       o_top_pwdn;
    logic       o_top_xclk;
    logic       o_top_siod;
    logic       o_top_sioc; 
    
    logic [3:0] o_top_vga_red,
                o_top_vga_green,
                o_top_vga_blue;
    logic       o_top_vsync;
    logic       o_top_hsync;
    
    // Instantiate device under test 
    top
    DUT
    (   
        .i_top_clk(i_top_clk                ),
        .i_top_rst(i_top_rst                ),
        
        // I/O for cam initalization 
        .i_top_cam_start(i_top_cam_start    ), 
        .o_top_cam_done(o_top_cam_done      ), 
        
        // Buttons for sobel threshold
        .i_top_inc_sobel_thresh(i_top_inc_sobel_thresh ),
        .i_top_dec_sobel_thresh(i_top_dec_sobel_thresh ), 
        
        // I/O to cameraInternal Clock
        .i_top_pclk(i_top_pclk              ), 
        .i_top_pix_byte(i_top_pix_byte      ),
        .i_top_pix_vsync(i_top_pix_vsync    ),
        .i_top_pix_href(i_top_pix_href      ),
        .o_top_reset(o_top_reset            ),
        .o_top_pwdn(o_top_pwdn              ),
        .o_top_xclk(o_top_xclk              ),
        .o_top_siod(o_top_siod              ),
        .o_top_sioc(o_top_sioc              ),
        
        // I/O to VGA 
        .o_top_vga_red(o_top_vga_red        ),
        .o_top_vga_green(o_top_vga_green    ),
        .o_top_vga_blue(o_top_vga_blue      ),
        .o_top_vga_vsync(o_top_vsync        ),
        .o_top_vga_hsync(o_top_hsync        )
    );

    // Testbench queue
    logic [11:0] pixel_data_queue [$];
    logic [11:0] first_pixel_byte;

    initial
        begin
            i_top_clk = 0;
            i_top_pclk= 0;
            i_top_rst = 0;
            
            i_top_dec_sobel_thresh = 0;
            i_top_inc_sobel_thresh = 0;
            
            i_top_cam_start = 0;
            i_top_pix_vsync = 0;
            i_top_pix_href = 0; 
        end 
    
    // Create Clocks
    always #(T_SYS_CLK/2) i_top_clk = ~i_top_clk;
    always #(T_P_CLK/2)   i_top_pclk= ~i_top_pclk; 
    
    initial
    begin: TB 
        integer frame, row, pix_byte;  
        
        // Sample a '0' from i_top_rst as to pass assertion $fell(DUT.top_btn_db.o_btn_db)
        repeat(DELAY+1) @(posedge i_top_clk); 
        
        // Start simulation in known state
        TopResetDb();      
        
        i_top_cam_start = 1'b1; 
        repeat(DELAY) @(posedge i_top_clk);
        
        // Skip initialization (tested in cam_init_tb) and start first frame 
        @(posedge i_top_pclk) 
            force DUT.OV7670_cam.o_cam_done = 1'b1; 
        FrameStart(); 
        
        //    Simulate VGA Frame Timing   
        //    http://web.mit.edu/6.111/www/f2016/tools/OV7670_2006.pdf (page 7)   
        //    Note: tline = 784*tpclk
        
        for(frame = 0; frame < nFrames; frame=frame+1)
        begin
            // Start frame to start sending pixel data to BRAM
            FrameStart();  
            
            for(row = 1; row < nRows+1; row=row+1)
            begin
            
                for(pix_byte = 0; pix_byte < (2*nPixelsPerRow); pix_byte=pix_byte+1)
                begin
                    @(negedge i_top_pclk)
                    begin
                        if(pix_byte == 0)                         
                            i_top_pix_href = 1'b1;
                        
                        // First byte
                        if(pix_byte % 2 == 0)                       
                        begin
                            first_pixel_byte = { $urandom() % 4096 }; //row*(pix_byte/2); 
                            i_top_pix_byte   = { 4'hF , first_pixel_byte[11:8] };
                        end
                        // Second byte, add to queue for testing 
                        else
                        begin
                            i_top_pix_byte = first_pixel_byte[7:0];                      
                            pixel_data_queue.push_front(first_pixel_byte);        
                        end
                    end       
                      
                end 

                // Invalid Data region (before next row)
                @(negedge i_top_pclk) i_top_pix_href = 0;
                repeat(144*2) @(posedge i_top_pclk); 
            end 
                        
            // Last row -> end of frame
            i_top_pix_vsync = 0; 
            repeat(10*784*2) @(negedge i_top_pclk); 
                   
            // Finish sim
            if(frame == nFrames - 1)
            begin                
                $display("SUCCESS!\n");
                $finish();    
            end    
        end 

    end // testbench 
    
    
    // 1st: Top Reset to Multi-clock resets 
     
    // Simulate top rst button debounce 
    task TopResetDb();
    begin
        i_top_rst = 0; 
        @(posedge i_top_clk);
        assert(DUT.top_btn_db.i_btn_in == 1'b1);
        
        i_top_rst = 1'b1; 
        repeat(DELAY+1) @(posedge i_top_clk);
        assert(DUT.top_btn_db.i_btn_in == 0);
        
        i_top_rst = 0; 
    end
    endtask
    
    // Verify that top rst to mutli-clock reset are asserted/deasserted properly
    property top_rst_db_p;
        @(posedge i_top_clk) $fell(i_top_rst) 
                                |-> $fell(DUT.top_btn_db.o_btn_db)
                                ##(DELAY+1) $rose(DUT.top_btn_db.o_btn_db);
    endproperty
    top_rst_assert_db_p_chk: assert property(top_rst_db_p)
                                $display("Multi-clock resets pass.\n"); 
                             else
                                $fatal("Multi-clock resets fail.\n"); 
 
    // Verify that negedge multi-clock resets are asserted once top rst debounce samples '1'  
    always @(posedge i_top_clk)
    begin
        if($fell(DUT.top_btn_db.o_btn_db))
        begin
            assert(DUT.OV7670_cam.i_rstn_clk == 0) 
                $display("100 MHz Multi-clock reset is 0.\n"); 
            else 
                $fatal("100 MHz MultiYou are not receiving the ACK after the addres-clock reset is NOT 0.\n");
        end
    end
    always @(posedge i_top_pclk)
    begin
        if($fell(DUT.top_btn_db.o_btn_db))
        begin
            assert(DUT.OV7670_cam.i_rstn_pclk == 0) 
                $display("24 MHz Multi-clock reset is 0.\n");
            else
                $fatal("24 MHz Multi-clock reset is NOT 0.\n");
        end
    end

    task FrameStart();    // VGA Timing of OV7670
    begin
        i_top_pix_vsync = 1'b1; 
        repeat(3*784*2) @(posedge i_top_pclk);
        i_top_pix_vsync = 0; 
        repeat(17*784*2) @(posedge i_top_pclk); 
    end
    endtask    

    always @(posedge DUT.w_clk25m)
    begin
        if($fell(DUT.top_btn_db.o_btn_db))
        begin
            assert(DUT.display_interface.i_rstn_clk25m == 0)
                $display("25 MHz Multi-clock reset is 0.\n");
            else
                $fatal("25 MHz Multi-clock reset is NOT 0.\n");
        end 
    end 
           

    //   2nd: Verify that all captured pixel data gets sent to vp_top
    //          - Check that Async FIFO is never empty or full         
     
    // Never full
    always @(posedge i_top_pclk)
    begin
        if(DUT.r2_rstn_pclk)
        begin

            assert(DUT.OV7670_cam.cam_afifo.w_full !== 1'b1)
            else
                $fatal(1, "Async FIFO should not be full.\n"); 
          
            
        end 
    end 
    
    // Never empty after a read
    always @(posedge i_top_clk)
    begin
        if(DUT.r2_rstn_top_clk)  
        begin
            if(DUT.w_vp_top_data_ready)
                assert(DUT.OV7670_cam.cam_afifo.r_empty !== 1'b1)
                else
                    $fatal(1, "Async FIFO should not be empty.\n"); 
        end

    end 
    
    // Verify that pixel data captured is correct
    // Verify pixel data is sent to vp_top via handshake
    logic [11:0] expected_cam_data;
    logic [11:0] actual_cam_data;
    logic [11:0] gray_data_queue [$]; 
    
    always @(posedge i_top_clk)
    begin
        if(DUT.r2_rstn_top_clk)
        begin
            if(DUT.OV7670_cam.i_data_ready & DUT.OV7670_cam.o_cam_data_valid)
            begin
                 
                
                expected_cam_data = pixel_data_queue.pop_back(); 
                actual_cam_data = $past(DUT.w_cam_top_data);
                     
                assert(expected_cam_data == actual_cam_data)
                    //$display("0x%h is sent to vp_top\n", actual_cam_data);
                else
                    $fatal(1, "Expected Cam Data 0x%h\nActual Cam Data 0x%h\n",
                    expected_cam_data, actual_cam_data);
         
                gray_data_queue.push_front(expected_cam_data);
         
            end
        end    
    end
    
    // 3rd: Check that all data retrieved by vp_top is converted to 8-bit grayscaled
    logic [11:0] cam_to_vp_data;

    logic [7:0]  R_tb;
    logic [7:0]  G_tb;
    logic [7:0]  B_tb; 
    logic [11:0] gray_data;
    logic [7:0]  expected_gray_data; 
    logic [7:0]  actual_gray_data;   
    
    always @(posedge i_top_clk)
    begin
        if(DUT.r2_rstn_top_clk)
        begin
            if($fell(DUT.videoprocessing_sobel.r_data_valid))
            begin
            
                cam_to_vp_data = gray_data_queue.pop_back(); 
                
                // RGB444 into Q4.4 format
                R_tb = cam_to_vp_data[11:8] << 4; 
                G_tb = cam_to_vp_data[7:4]  << 4;
                B_tb = cam_to_vp_data[3:0]  << 4; 
                
                // Convert RGB444 into 8-bit grayscale
                gray_data =  (R_tb >> 2) + (R_tb >> 5) +
                             (G_tb >> 1) + (G_tb >> 4) + 
                             (B_tb >> 4) + (B_tb >> 5); 
                                            
                // Convert fixed-point Q4.4 grayscaled data into an 8-bit                     
                expected_gray_data = gray_data[11:4];
                
                actual_gray_data = DUT.videoprocessing_sobel.w_gray_byte;
                
                assert(expected_gray_data == actual_gray_data)
                    $display("8-bit Grayscaled: 0x%h\n", actual_gray_data);
                else
                    $fatal(1, "Expected grayscaled: 0x%h\nActual grayscaled: 0x%h\n", 
                        expected_gray_data, actual_gray_data);  
         
            end 
        end 
    end 
    
    //  4th: Verify that all sobel-filtered data is sent to mem_top via handshake
      
    // Just store whatever data results from sobel filter
    logic [7:0] BRAM_data_queue  [$];
    logic [7:0] sobel_data_queue [$];
    always @(posedge i_top_clk)
    begin
    
        if(DUT.videoprocessing_sobel.w_sobel_data_valid)
        begin
            sobel_data_queue.push_front(DUT.videoprocessing_sobel.w_sobel_data);
            BRAM_data_queue.push_front(DUT.videoprocessing_sobel.w_sobel_data);
        end 
        
    end 
    
    // Check vp_top/mem_top handshake
    logic [7:0] expected_vp_top_data;
    logic [7:0] actual_vp_top_data;
    
    always @(posedge i_top_clk)
    begin
        if(DUT.w_mem_top_data_ready & DUT.w_mem_top_data_valid)
        begin
            expected_vp_top_data = sobel_data_queue.pop_back(); 
            actual_vp_top_data = DUT.w_vp_top_data;
                       
            assert(expected_vp_top_data === actual_vp_top_data)
                $display("Sobel-filtered data 0x%h\n", actual_vp_top_data);
            else
                $fatal(1, "Expected sobel-filtered data 0x%h\nActual sobel-filtered data 0x%h\n",
                        expected_vp_top_data, actual_vp_top_data); 
  
        end
    end

    // 5th: Verify that data written to BRAM is read sequentially

    wire [9:0]  VGA_x = DUT.display_interface.o_VGA_x;
    wire [9:0]  VGA_y = DUT.display_interface.o_VGA_y;
    
    logic [7:0] expected_VGA_read;
    logic [7:0] actual_VGA_read;
    
    always @(posedge DUT.w_clk25m)
    begin
        // one clock cycle BRAM delay, shift X to right by 1
        if( (((VGA_x > 0 && VGA_x < 640) && (VGA_y < 480))
            || ((VGA_x == 799) && ((VGA_y == 524) || (VGA_y < 480))))
            && DUT.display_interface.r_SM_state == 'd2)
        begin        
            expected_VGA_read   = BRAM_data_queue.pop_back(); 
            actual_VGA_read     = DUT.display_interface.i_pix_data;
            assert(actual_VGA_read === expected_VGA_read)
                $display("VGA Pixel Read Byte: 0x%h.\n", actual_VGA_read); 
            else
                $fatal(1, "Expected VGA Pixel Read: 0x%h, Actual VGA Pixel Byte Read: 0x%h\n",
                      expected_VGA_read, actual_VGA_read);
        end
    end 

   // Check that all handshakes have asserted VALID while READY is HIGH
    property handshake_cam_top_to_vp_top_p;
        @(posedge i_top_clk) $rose(DUT.w_cam_top_data_valid) 
                                |=> DUT.w_cam_top_data_valid[*1:$] 
                                    ##0 (DUT.w_vp_top_data_ready); 
    endproperty

    assert property(handshake_cam_top_to_vp_top_p);

    property handshake_vp_top_to_mem_top_p; 
        @(posedge i_top_clk) $rose(DUT.w_mem_top_data_valid)
                                |=> DUT.w_mem_top_data_valid[*1:$]
                                    ##0 (DUT.w_mem_top_data_ready); 
    endproperty
    
    assert property (handshake_vp_top_to_mem_top_p); 


endmodule
