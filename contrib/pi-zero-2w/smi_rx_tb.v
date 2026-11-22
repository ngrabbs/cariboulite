module tb;
    reg clk=0, rst=1, swe=1, full=0, almost_full=0;
    reg [7:0] data=0;
    wire push, req;
    wire [31:0] word_out;
    integer count=0;
    always #8 clk=~clk;
    smi_rx dut(.i_rst_b(rst),.i_sys_clk(clk),.i_smi_swe_srw(swe),
        .i_smi_data_in(data),.i_tx_fifo_full(full),.i_tx_fifo_almost_full(almost_full),
        .o_tx_fifo_push(push),.o_tx_fifo_pushed_data(word_out),.o_smi_write_req(req));
    task send(input [7:0] b);
        begin
            data=b; #9; swe=0; #46; swe=1; #18; data=0; #25;
        end
    endtask
    always @(posedge clk) if (push) begin
        if (count==0 && word_out!==32'he8902ee1) $fatal(1,"pair 0 = %h",word_out);
        if (count==1 && word_out!==32'h12345679) $fatal(1,"pair 1 = %h",word_out);
        if (count>1) $fatal(1,"Extra pair");
        count=count+1;
    end
    initial begin
        #3; rst=0; #50; rst=1; #50;
        send(0); send(8'he1); send(8'h2e); send(8'h90); send(8'he8);
        send(8'h11); send(8'h11); almost_full=1; full=1;
        send(8'h22); send(8'h22); if (req) $fatal(1,"No backpressure");
        full=0; almost_full=0;
        send(8'h79); send(8'h56); send(8'h34); send(8'h12);
        #80; if (count!=2) $fatal(1,"Missing pair");
        $display("PASS: ordered complete pairs across a full FIFO");
        $finish;
    end
endmodule
