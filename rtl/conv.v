`timescale 1ns / 1ps
`default_nettype none

/*
 *  Pipelines a MAC operation
 *  by convolving a 2D Kernel 
 *  that specifies a sobel filter
 *
 */

module conv
    #(parameter DW = 12)
    (   input wire             i_clk, 
        input wire [9*DW-1: 0] i_data,
        input wire             i_valid, 
        
        output reg [DW-1: 0]   o_data, 
        output reg             o_valid 
    );
    
    integer i;
    
    // Data width of kernel values
    localparam KW = 8; 
    
    reg [KW-1:0] kernel1 [8:0];
    reg [KW-1:0] kernel2 [8:0]; 
    
    reg [(DW+KW)-1:0] multData1 [8:0];
    reg [(DW+KW)-1:0] multData2 [8:0];
    reg               multDataValid;
     
    reg [(DW+KW)-1:0] sumDataInt1;
    reg [(DW+KW)-1:0] sumDataInt2; 
    reg [(DW+KW)-1:0] sumData1;
    reg [(DW+KW)-1:0] sumData2;
    reg               sumDataValid; 
    
    reg [2*((DW+KW)-1):0]   convolved_data_int1;
    reg [2*((DW+KW)-1):0]   convolved_data_int2;
    wire[2*((DW+KW)-1)+1:0] convolved_data_int; 
    reg                     convolved_data_int_valid; 
    
    // 3x3 Kernels for sobel filter
    initial 
    begin
        kernel1[0] = 1;
        kernel1[1] = 0;
        kernel1[2] = -1;
        kernel1[3] = 2; 
        kernel1[4] = 0; 
        kernel1[5] = -2;
        kernel1[6] = 1;
        kernel1[7] = 0;
        kernel1[8] = -1;
        
        kernel2[0] = 1;
        kernel2[1] = 2;
        kernel2[2] = 1; 
        kernel2[3] = 0;
        kernel2[4] = 0;
        kernel2[5] = 0;
        kernel2[6] = -1; 
        kernel2[7] = -2; 
        kernel2[8] = -1; 
    end 
    
    always @(posedge i_clk)
    begin
        for(i = 0;i<9;i=i+1)
        begin
            multData1[i] <= $signed(kernel1[i]) * $signed({1'b0, i_data[i*DW+: DW]});
            multData2[i] <= $signed(kernel2[i]) * $signed({1'b0, i_data[i*DW+: DW]});
        end
        multDataValid <= i_valid; 
    end 
    
    always @(*)
    begin
        sumDataInt1 = 0;
        sumDataInt2 = 0; 
        for(i=0;i<9;i=i+1)
        begin
            sumDataInt1 = $signed(sumDataInt1) + $signed(multData1[i]);
            sumDataInt2 = $signed(sumDataInt2) + $signed(multData2[i]);
        end
    end


    always @(posedge i_clk)
    begin
        sumData1 <= sumDataInt1;
        sumData2 <= sumDataInt2;  
        sumDataValid <= multDataValid; 
    end

    always @(posedge i_clk)
    begin
        convolved_data_int1 <= $signed(sumData1) * $signed(sumData1);
        convolved_data_int2 <= $signed(sumData2) * $signed(sumData2);
        convolved_data_int_valid <= sumDataValid; 
    end 

    assign convolved_data_int = convolved_data_int1 + convolved_data_int2; 

    always @(posedge i_clk)
    begin
        o_data  <= (convolved_data_int > 4000) ? {(DW){1'b1}} : 0; 
        o_valid <=  convolved_data_int_valid;     
    end

    
endmodule
