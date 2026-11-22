`include "lvds_clock_sync.v"
module lvds_tx (
    input i_rst_b,
    input i_ddr_clk,
    input i_sys_clk,
    output reg [1:0] o_ddr_data,
    input i_fifo_empty,
    output o_fifo_pull,
    input [31:0] i_fifo_data,
    input [3:0] i_sample_gap,
    input i_tx_state,
    input i_debug_lb
);
    localparam [3:0] sync_frames = 4'd10;
    localparam [31:0] loopback_frame = 32'h84037048;
    reg [3:0] zero_frames;
    reg [32:0] shift;
    wire frame_strobe, clock_ready;
    wire tx_ready = i_tx_state && !i_debug_lb;

    lvds_clock_sync word_clock (
        .i_rst_b(i_rst_b),
        .i_ddr_clk(i_ddr_clk),
        .i_sys_clk(i_sys_clk),
        .o_lvds_ready_ddr(clock_ready),
        .o_data_sbe_ddr(frame_strobe)
    );
    assign o_fifo_pull = clock_ready && frame_strobe && tx_ready &&
                         zero_frames == 0 && !i_fifo_empty;

    always @(posedge i_ddr_clk) begin
        if (!clock_ready) begin
            zero_frames <= sync_frames;
            shift <= 0;
            o_ddr_data <= 0;
        end else begin
            o_ddr_data <= shift[32:31];
            shift <= {shift[30:0], 2'b00};

            if (frame_strobe) begin
                shift[31:0] <= 0;
                if (zero_frames != 0) begin
                    zero_frames <= zero_frames - 1'b1;
                end else if (i_debug_lb && !i_tx_state) begin
                    shift[31:0] <= loopback_frame;
                end else if (o_fifo_pull) begin
                    shift[31:0] <= i_fifo_data;
                    zero_frames <= i_sample_gap;
                end else begin
                    zero_frames <= sync_frames;
                end
            end
        end
    end
endmodule
