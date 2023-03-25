`timescale 1ns / 1ps
`default_nettype none

module top_user_control
    (
        input wire i_clk,
        input wire i_rstn,

        input wire i_inc_sobel_thresh,
        input wire i_dec_sobel_thresh,

        output reg [7:0] o_sobel_thresh
    );

    wire w_inc_sobel_thresh;
    wire w_dec_sobel_thresh; 

    // Debounce buttons
    debouncer
    #(  .DELAY(240_000))
    inc_sobel_db
    (
        .i_clk(i_clk),
        .i_btn_in(i_inc_sobel_thresh),
        .o_btn_db(w_inc_sobel_thresh)
    );

    debouncer
    #(  .DELAY(240_000))
    dec_sobel_db
    (
        .i_clk(i_clk),
        .i_btn_in(i_dec_sobel_thresh),
        .o_btn_db(w_dec_sobel_thresh)
    );


    // Detect Positive Edge from buttons
    reg r1_inc_sobel_thresh;
    reg r2_inc_sobel_thresh; 
    wire p_inc_sobel_thresh;


    reg r1_dec_sobel_thresh;
    reg r2_dec_sobel_thresh;
    wire p_dec_sobel_thresh;

    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            { r2_inc_sobel_thresh, r1_inc_sobel_thresh } <= 0;
        end
        else begin
            { r2_inc_sobel_thresh, r1_inc_sobel_thresh } <= { r1_inc_sobel_thresh, w_inc_sobel_thresh };
        end 
    end

    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            { r2_dec_sobel_thresh, r1_dec_sobel_thresh } <= 0;
        end
        else begin
            { r2_dec_sobel_thresh, r1_dec_sobel_thresh } <= { r1_dec_sobel_thresh, w_dec_sobel_thresh };
        end 
    end

    assign p_inc_sobel_thresh = (~r2_inc_sobel_thresh & r1_inc_sobel_thresh);
    assign p_dec_sobel_thresh = (~r2_dec_sobel_thresh & r1_dec_sobel_thresh);

    // Control threshold
    localparam IDLE = 0,
                ACTIVE_INC = 1;

    localparam ACTIVE_DEC = 1; 

    reg state_inc;
    reg state_dec;
    always @(posedge i_clk)
    begin
        if(!i_rstn)
        begin
            state_inc      <= IDLE;
            state_dec      <= IDLE;  
            o_sobel_thresh <= 16;      
        end
        else begin

            // FSM for increase sobel threshold
            case(state_inc)
            IDLE: begin
                if(p_inc_sobel_thresh)
                    state_inc <= ACTIVE_INC;
            end
            ACTIVE_INC: begin
                if((o_sobel_thresh + 1) >= {(8){1'b1}})
                    o_sobel_thresh <= o_sobel_thresh; 
                else 
                    o_sobel_thresh <= o_sobel_thresh + 1; 

                state_inc      <= IDLE;
            end
            endcase 

            // FSM for decrease sobel threshold
            case(state_dec)
            IDLE: begin
                if(p_dec_sobel_thresh)
                    state_dec <= ACTIVE_DEC; 
            end
            ACTIVE_DEC: begin
                if((o_sobel_thresh - 1) <= 0)
                    o_sobel_thresh <= 0;
                else
                    o_sobel_thresh <= o_sobel_thresh - 1; 

                state_dec      <= IDLE;
            end
            endcase

        end
    end

endmodule