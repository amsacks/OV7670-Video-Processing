`timescale 1ns / 1ps
`default_nettype none

module top
    (   input wire i_top_clk,
        input wire i_top_rst,
        
        input wire  i_top_cam_start, 
        output wire o_top_cam_done, 
            
        input wire i_top_inc_sobel_thresh,
        input wire i_top_dec_sobel_thresh,

        // I/O to camera
        input wire       i_top_pclk, 
        input wire [7:0] i_top_pix_byte,
        input wire       i_top_pix_vsync,
        input wire       i_top_pix_href,
        output wire      o_top_reset,
        output wire      o_top_pwdn,
        output wire      o_top_xclk,
        output wire      o_top_siod,
        output wire      o_top_sioc,
        
        // I/O to VGA 
        output wire [3:0] o_top_vga_red,
        output wire [3:0] o_top_vga_green,
        output wire [3:0] o_top_vga_blue,
        output wire       o_top_vga_vsync,
        output wire       o_top_vga_hsync
    );
    
    // cam_top to vp_top
    wire        w_vp_top_data_ready;
    wire        w_cam_top_data_valid;
    wire [11:0] w_cam_top_data;
    
    // vp_top to mem_top
    wire        w_mem_top_data_ready;
    wire        w_mem_top_data_valid;
    wire [7:0]  w_vp_top_data;
    
    // vga_top to mem_top
    wire [7:0] w_vga_pix_data;
    wire [18:0] w_vga_pix_addr; 
           
    // Reset synchronizers for all clock domains
    reg r1_rstn_top_clk,    r2_rstn_top_clk;
    reg r1_rstn_pclk,       r2_rstn_pclk;
    reg r1_rstn_clk25m,     r2_rstn_clk25m; 
        
    wire w_clk25m; 
    
    // Generate clocks for camera and VGA
    clk_wiz_1
    clock_gen
    (
        .clk_in1(i_top_clk          ),
        .clk_out1(w_clk25m          ),
        .clk_out2(o_top_xclk        )
    );
    
    wire w_rstn_btn_db; 
    
    // Debounce top level button - invert reset to have debounced negedge reset
  
    debouncer 
    #(  .DELAY(240_000)         )
    top_btn_db
    (
        .i_clk(i_top_clk        ),
        .i_btn_in(~i_top_rst    ),
        .o_btn_db(w_rstn_btn_db )
    ); 
    
    // Double FF for negedge reset synchronization 
    always @(posedge i_top_clk or negedge w_rstn_btn_db)
        begin
            if(!w_rstn_btn_db) {r2_rstn_top_clk, r1_rstn_top_clk} <= 0; 
            else               {r2_rstn_top_clk, r1_rstn_top_clk} <= {r1_rstn_top_clk, 1'b1}; 
        end 
    always @(posedge w_clk25m or negedge w_rstn_btn_db)
        begin
            if(!w_rstn_btn_db) {r2_rstn_clk25m, r1_rstn_clk25m} <= 0; 
            else               {r2_rstn_clk25m, r1_rstn_clk25m} <= {r1_rstn_clk25m, 1'b1}; 
        end
    always @(posedge i_top_pclk or negedge w_rstn_btn_db)
        begin
            if(!w_rstn_btn_db) {r2_rstn_pclk, r1_rstn_pclk} <= 0; 
            else               {r2_rstn_pclk, r1_rstn_pclk} <= {r1_rstn_pclk, 1'b1}; 
        end 
    
    // FPGA-camera interface
    cam_top 
    #(  .CAM_CONFIG_CLK(100_000_000)            )
    OV7670_cam
    (
        .i_clk(i_top_clk                        ),
        .i_rstn_clk(r2_rstn_top_clk             ),
        .i_rstn_pclk(r2_rstn_pclk               ),
        
        // I/O for camera init
        .i_cam_start(i_top_cam_start            ),
        .o_cam_done(o_top_cam_done              ), 
        
        // I/O camera
        .i_pclk(i_top_pclk                      ),
        .i_pix_byte(i_top_pix_byte              ), 
        .i_vsync(i_top_pix_vsync                ), 
        .i_href(i_top_pix_href                  ),
        .o_reset(o_top_reset                    ),
        .o_pwdn(o_top_pwdn                      ),
        .o_siod(o_top_siod                      ),
        .o_sioc(o_top_sioc                      ), 
        
        // Handshake with vp_top
        .i_data_ready(w_vp_top_data_ready       ),
        .o_cam_data_valid(w_cam_top_data_valid  ),
        .o_cam_data(w_cam_top_data              )
    );
    

    wire [7:0] w_sobel_thresh; 
    
    top_user_control
    control_filters
    (
        .i_clk(i_top_clk                            ),
        .i_rstn(r2_rstn_top_clk                     ),

        .i_inc_sobel_thresh(i_top_inc_sobel_thresh  ),
        .i_dec_sobel_thresh(i_top_dec_sobel_thresh  ),
        
        .o_sobel_thresh(w_sobel_thresh              )
    );

    vp_top
    #(  .DW(8                               ),
        .RL(640)                            ) 
    videoprocessing_sobel
    (
        .i_clk(i_top_clk                    ),
        .i_rstn(r2_rstn_top_clk             ),

        .i_threshold(w_sobel_thresh         ),

        // Handshake with cam_top
        .o_data_ready(w_vp_top_data_ready   ),
        .i_data_valid(w_cam_top_data_valid  ),
        .i_data(w_cam_top_data              ),       

        // Handshake with mem_top
        .i_data_ready(w_mem_top_data_ready  ),
        .o_data_valid(w_mem_top_data_valid  ),
        .o_data(w_vp_top_data               )         
    );
    
    mem_top
    #(  .DW(8)                              )
    memory
    (
        .i_clk(i_top_clk                    ), 
        .i_rstn(r2_rstn_top_clk             ), 
        
        // Handshake with vp_top
        .o_data_ready(w_mem_top_data_ready  ),
        .i_data_valid(w_mem_top_data_valid  ), 
        .i_data(w_vp_top_data               ),
        
        // vga_top interface        
        .i_clk25m(w_clk25m                  ),
        .i_vga_addr(w_vga_pix_addr          ),
        .o_vga_data(w_vga_pix_data          )
    ); 

    vga_top
    display_interface
    (
        .i_clk25m(w_clk25m             ),
        .i_rstn_clk25m(r2_rstn_clk25m  ), 
        
        // VGA timing signals
        .o_VGA_x(                      ),
        .o_VGA_y(                      ), 
        .o_VGA_vsync(o_top_vga_vsync   ),
        .o_VGA_hsync(o_top_vga_hsync   ), 
        .o_VGA_video(                  ),
        
        // VGA RGB Pixel Data
        .o_VGA_r(o_top_vga_red         ),
        .o_VGA_g(o_top_vga_green       ),
        .o_VGA_b(o_top_vga_blue        ), 
        
        // VGA read/write from/to BRAM
        .i_pix_data(w_vga_pix_data     ), 
        .o_pix_addr(w_vga_pix_addr     )
    );
    
    
endmodule
