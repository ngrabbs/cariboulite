
/*
 *  Contribution by matteo serva
 *  https://github.com/matteoserva
 * 
 */
`include "lvds_clock_sync.v"
module lvds_tx (
    input        i_rst_b,
    input        i_ddr_clk,
    input        i_sys_clk,        // FPGA Clock
    output reg[1:0] o_ddr_data,

    input             i_fifo_empty,
    output            o_fifo_read_clk,
    output          o_fifo_pull,
    input      [31:0] i_fifo_data,
    input [3:0]     i_sample_gap,
    input             i_tx_state,
    input             i_sync_input,
    input           i_debug_lb,    
    output          o_tx_state_bit,
    output          o_sync_state_bit,
    output          o_heartbeat,
    output    [7:0] o_debug_word,
    output reg [31:0] o_last_iq_word,
    input [7:0]    i_tx_control_word,
);

    // STATES and PARAMS
    localparam
        tx_state_init    = 4'b0000,
        tx_state_sync    = 4'b0001,
        tx_state_pretx   = 4'b0010,
        tx_state_debugtx = 4'b1000;
        
    localparam sync_duration_frames = 8'd10;   // at least 2.5usec
    localparam zero_frame =   32'b00000000_00000000_00000000_00000000;
    localparam lb_frame =     32'b10000000_00000000_01000000_00000000;
    localparam sync_frame =   32'b10000000_00000001_01000000_00000000;
    localparam data_mask =    32'b00111111_11111110_00111111_11111110;
    localparam test_frame =   32'b00100000_00000000_00010000_00000000;
  // Internal Registers
    reg [7:0] r_sync_count;
    reg [3:0] r_state;

    reg [31:0] r_fifo_data;
    reg r_pulled;


    reg [3:0] reset_shift;

    //bus state check
    reg [9:0] lvds_start_delay_counter;
    reg [6:0] lvds_timeout_counter;
    reg lvds_heartbeat;
    wire lvds_ready;
    reg [2:0] lvds_heartbeat_synchronizer;
    wire lvds_heartbeat_sbe;
    wire lvds_hearbeat_lost;
    
  // Initial conditions
  initial begin
        r_fifo_data <= zero_frame;
  end

    assign o_fifo_read_clk = i_ddr_clk;
    assign o_tx_state_bit = 1'b0;
    assign o_sync_state_bit = 1'b0;
    
    assign o_fifo_pull =  r_pulled ;
    reg [3:0] debug_seen;
    assign o_debug_word = {debug_seen,r_state};
    wire framed = r_fifo_data[31:30] == 2'b10 && r_fifo_data[15:14] == 2'b01;
    wire nonzero_iq = |(r_fifo_data & 32'h3ffe3ffe);
    always @(posedge i_ddr_clk or negedge i_rst_b) begin
      if (!i_rst_b) begin
        debug_seen <= 0;
        o_last_iq_word <= 0;
      end else begin
        if (lvds_ready_syncd) debug_seen[0] <= 1;
        if (r_pulled && !i_fifo_empty) debug_seen[1] <= 1;
        if (w_data_sbe_ddr && framed) debug_seen[2] <= 1;
        if (w_data_sbe_ddr && framed && nonzero_iq) begin
          o_last_iq_word <= r_fifo_data;
          debug_seen[3] <= 1;
        end
      end
    end
    
    wire lvds_ready_syncd;
    wire w_data_sbe_ddr;
    lvds_clock_sync  lvds_clock_inst (
      .i_rst_b(i_rst_b),
      .i_ddr_clk(i_ddr_clk),
      .i_sys_clk(i_sys_clk),
      .o_lvds_ready_ddr(lvds_ready_syncd),
      .o_data_sbe_ddr(w_data_sbe_ddr),
    );
   
    /*
        LVDS BUS OUTPUT
    */

    reg [32:0] r_fifo_shift;
    always @(posedge i_ddr_clk) begin

            o_ddr_data[1:0] <= {r_fifo_shift[32], r_fifo_shift[31]};
            r_fifo_shift <= {r_fifo_shift[30:0], 2'd0};
        
            if(w_data_sbe_ddr) begin
                r_fifo_shift[31:0] <= r_fifo_data;
                lvds_heartbeat <= !lvds_heartbeat;
            end

    end
    


    /*
        HEARTBEAT
    */
    reg [31:0] r_clock_count;
    reg r_heartbeat;
    always @(posedge i_ddr_clk) begin
        begin
            r_clock_count <= r_clock_count + 1;
            r_heartbeat <= r_clock_count[20] && r_clock_count[21] && r_clock_count[22] && r_clock_count[23] && r_clock_count[24] && r_clock_count[25];
        end
    end
    assign o_heartbeat = r_heartbeat;
    
    
    
    // SYNC AND MANAGEMENT
  always @(posedge i_ddr_clk) begin
    if (lvds_ready_syncd == 1'b0) begin
            r_state <= tx_state_init;
            r_pulled <= 1'b0;
            r_fifo_data <= zero_frame;
            r_sync_count <= 8'd200;
    end else begin
        r_pulled <= 1'b0;
        case (r_state)
            tx_state_init:
                if( !i_fifo_empty) begin
                    r_state <= tx_state_sync;
                end
             tx_state_sync: 
             begin 
                        r_fifo_data <= zero_frame;
                        
                        if( i_fifo_empty == 1'b1 /*&& i_debug_lb == 1'b0*/  ) begin
                            r_sync_count <= sync_duration_frames;
                        end else if (r_sync_count == 8'd0) begin
                                r_state <= tx_state_pretx;
                                r_pulled <= 1'b1;
                        end else if (w_data_sbe_ddr) begin 
                            r_sync_count <= r_sync_count - 1;
                        end
                        
             end
             tx_state_pretx: begin
                r_fifo_data <= ({2'b00, i_fifo_data[31:18], 2'b00, i_fifo_data[15:2]} & data_mask) | sync_frame;
                r_state <= tx_state_debugtx;
             end
             tx_state_debugtx:
             begin

                
                if (w_data_sbe_ddr) begin
                    r_state <= tx_state_sync;
                end
                r_sync_count <= {4'd0,i_sample_gap};
             end
             
                                       
        endcase
   end     

  end

endmodule
