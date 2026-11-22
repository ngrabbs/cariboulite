`timescale 1ns/1ps
module tb;
    reg clk = 0, rst = 1, swe = 1, full = 0, enabled = 1;
    reg [7:0] data = 0;
    wire push;
    wire [31:0] word_out;
    integer count = 0;
    always #8 clk = ~clk;

    smi_rx dut(.i_rst_b(rst), .i_sys_clk(clk), .i_enabled(enabled),
        .i_smi_swe_srw(swe), .i_smi_data(data), .i_fifo_full(full),
        .o_fifo_push(push), .o_fifo_data(word_out));

    task send(input [7:0] value);
        begin
            data = value; #9; swe = 0; #46; swe = 1; #18; data = 0; #25;
        end
    endtask
    task pair(input [12:0] i_sample, input [12:0] q_sample);
        begin
            send({3'b111, i_sample[12:8]});
            send({1'b0, i_sample[7:1]});
            send({1'b0, i_sample[0], q_sample[12:7]});
            send({1'b0, q_sample[6:0]});
        end
    endtask

    always @(posedge clk) if (push) begin
        case (count)
            0: if (word_out !== {2'b10, 13'h1abc, 1'b1, 2'b01, 13'h1ef0, 1'b0})
                   $fatal(1, "first pair = %h", word_out);
            1: if (word_out !== {2'b10, 13'h1234, 1'b1, 2'b01, 13'h0567, 1'b0})
                   $fatal(1, "second pair = %h", word_out);
            default: $fatal(1, "extra pair");
        endcase
        count = count + 1;
    end

    initial begin
        #3; rst = 0; #50; rst = 1; #50;
        send(0); send(8'he0);
        pair(13'h1abc, 13'h1ef0);
        full = 1; pair(13'h1fff, 13'h1fff); full = 0;
        enabled = 0; pair(13'h1fff, 13'h1fff); enabled = 1;
        pair(13'h1234, 13'h0567);
        #80; if (count != 2) $fatal(1, "missing pair");
        $display("PASS: SMI framing, restart, backpressure and RX isolation");
        $finish;
    end
endmodule
