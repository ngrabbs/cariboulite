module smi_rx (
    input i_rst_b,
    input i_sys_clk,
    output reg o_tx_fifo_push,
    output reg [31:0] o_tx_fifo_pushed_data,
    input i_tx_fifo_almost_full,
    input i_tx_fifo_full,
    output o_tx_fifo_clock,
    input i_smi_swe_srw,
    input [7:0] i_smi_data_in,
    output o_smi_write_req,
    output reg [7:0] o_trace_byte,
    output reg [3:0] o_trace_strobe,
    output reg o_trace_fifo
);
    reg [2:0] swe;
    reg [7:0] data_1, data_2, data_3;
    (* fsm_encoding = "none" *) reg [1:0] phase = 2'b00;
    reg [7:0] low_byte;
    reg [15:0] i_half;
    wire byte_ready = swe[1] & ~swe[2];

    assign o_smi_write_req = !i_tx_fifo_almost_full;
    assign o_tx_fifo_clock = i_sys_clk;

    always @(posedge i_sys_clk or negedge i_rst_b) begin
        if (!i_rst_b) begin
            swe <= 3'b111;
            data_1 <= 0;
            data_2 <= 0;
            data_3 <= 0;
            phase <= 0;
            low_byte <= 0;
            i_half <= 0;
            o_tx_fifo_push <= 0;
            o_tx_fifo_pushed_data <= 0;
            o_trace_strobe <= 0;
            o_trace_fifo <= 0;
            o_trace_byte <= 0;
        end else begin
            swe <= {swe[1:0], i_smi_swe_srw};
            data_1 <= i_smi_data_in;
            data_2 <= data_1;
            data_3 <= data_2;
            o_tx_fifo_push <= 0;
            if (byte_ready) begin
                o_trace_strobe[0] <= 1;
                if (data_3[0]) o_trace_strobe[1] <= 1;
                o_trace_byte <= data_3;
                case (phase)
                    2'd0: if (data_3[0]) begin
                        low_byte <= data_3;
                        phase <= 2'd1;
                    end
                    2'd1: begin
                        o_trace_strobe[2] <= 1;
                        i_half <= {data_3, low_byte};
                        phase <= 2'd2;
                    end
                    2'd2: begin
                        low_byte <= data_3;
                        phase <= data_3[0] ? 2'd1 : 2'd3;
                    end
                    2'd3: begin
                        o_trace_strobe[3] <= 1;
                        o_tx_fifo_pushed_data <= {data_3, low_byte, i_half};
                        o_tx_fifo_push <= !i_tx_fifo_full;
                        if (!i_tx_fifo_full) o_trace_fifo <= 1;
                        phase <= 2'd0;
                    end
                endcase
            end
        end
    end
endmodule
