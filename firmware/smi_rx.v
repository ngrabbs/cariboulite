module smi_rx (
    input i_rst_b,
    input i_sys_clk,
    input i_enabled,
    input i_smi_swe_srw,
    input [7:0] i_smi_data,
    input i_fifo_full,
    output reg o_fifo_push,
    output reg [31:0] o_fifo_data,
    output reg o_cond_tx,
    output [1:0] o_state
);
    reg [2:0] swe;
    reg [7:0] data_1, data_2, data_3;
    (* fsm_encoding = "none" *) reg [1:0] phase = 2'd0;
    reg [4:0] i_high;
    reg [6:0] i_middle;
    reg [6:0] iq_middle;
    reg modem_tx, cond_tx;

    assign o_state = phase;

    // Sample the write bus around the end of the strobe, in the FIFO clock domain.
    always @(posedge i_sys_clk or negedge i_rst_b) begin
        if (!i_rst_b) begin
            swe <= 3'b111;
            data_1 <= 0;
            data_2 <= 0;
            data_3 <= 0;
            phase <= 0;
            o_fifo_push <= 0;
            o_fifo_data <= 0;
            o_cond_tx <= 0;
            i_high <= 0;
            i_middle <= 0;
            iq_middle <= 0;
            modem_tx <= 0;
            cond_tx <= 0;
        end else begin
            swe <= {swe[1:0], i_smi_swe_srw};
            data_1 <= i_smi_data;
            data_2 <= data_1;
            data_3 <= data_2;
            o_fifo_push <= 0;
            if (!i_enabled) begin
                phase <= 0;
                o_cond_tx <= 0;
            end else if (swe[1] & ~swe[2]) begin
                // The top bit is only set on the first byte. A new marker
                // always restarts framing, including after a partial write.
                if (data_3[7]) begin
                    i_high <= data_3[4:0];
                    modem_tx <= data_3[6];
                    cond_tx <= data_3[5];
                    phase <= 1;
                end else begin
                    case (phase)
                        2'd1: begin
                            i_middle <= data_3[6:0];
                            phase <= 2;
                        end
                        2'd2: begin
                            iq_middle <= data_3[6:0];
                            phase <= 3;
                        end
                        2'd3: begin
                            o_fifo_data <= {2'b10, i_high, i_middle, iq_middle[6], modem_tx,
                                            2'b01, iq_middle[5:0], data_3[6:0], 1'b0};
                            o_fifo_push <= !i_fifo_full;
                            o_cond_tx <= cond_tx;
                            phase <= 0;
                        end
                        default: phase <= 0;
                    endcase
                end
            end
        end
    end
endmodule
