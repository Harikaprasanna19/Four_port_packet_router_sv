//============================================================================
// File:    pkt_output_stage.sv
// Author:  Capstone RTL Design
// Desc:    Output stage for one port of the packet router.
//          - Buffers crossbar output in a small FIFO (depth 4 packets)
//          - Implements backpressure toward the crossbar when FIFO is full
//          - Drives valid/ready handshake to external consumer
//          - Ensures no data loss under backpressure conditions
//============================================================================

module pkt_output_stage
  import pkt_router_pkg::*;
#(
  parameter port_id_t PORT_ID = 2'd0
)(
  input  logic              clk,
  input  logic              rst_n,

  // From crossbar
  input  logic              xbar_valid,
  input  data_t             xbar_data,
  input  logic              xbar_sop,
  input  logic              xbar_eop,
  input  port_id_t          xbar_src,
  output logic              xbar_ready,

  // External interface (to sink)
  output logic              out_valid,
  output data_t             out_data,
  input  logic              out_ready
);

  //--------------------------------------------------------------------------
  // Output FIFO (simple synchronous FIFO)
  //--------------------------------------------------------------------------
  localparam int FIFO_DEPTH_WORDS = (MAX_PKT_LEN + 1) * FIFO_DEPTH; // 68 words
  localparam int FIFO_ADDR_WIDTH  = $clog2(FIFO_DEPTH_WORDS);

  data_t  fifo_mem [FIFO_DEPTH_WORDS];
  logic [FIFO_ADDR_WIDTH-1:0] wr_ptr;
  logic [FIFO_ADDR_WIDTH-1:0] rd_ptr;
  logic [FIFO_ADDR_WIDTH:0]   fifo_count; // Extra bit for full detection

  logic fifo_full;
  logic fifo_empty;
  logic fifo_wr_en;
  logic fifo_rd_en;

  assign fifo_full  = (fifo_count >= FIFO_DEPTH_WORDS[FIFO_ADDR_WIDTH:0]);
  assign fifo_empty = (fifo_count == '0);

  assign fifo_wr_en = xbar_valid && xbar_ready;
  assign fifo_rd_en = out_valid && out_ready;

  //--------------------------------------------------------------------------
  // FIFO write
  //--------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (fifo_wr_en) begin
      fifo_mem[wr_ptr] <= xbar_data;
      wr_ptr <= (wr_ptr == FIFO_ADDR_WIDTH'(FIFO_DEPTH_WORDS - 1)) ?
                '0 : wr_ptr + 1;
    end
  end

  //--------------------------------------------------------------------------
  // FIFO read
  //--------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_ptr <= '0;
    end else if (fifo_rd_en) begin
      rd_ptr <= (rd_ptr == FIFO_ADDR_WIDTH'(FIFO_DEPTH_WORDS - 1)) ?
                '0 : rd_ptr + 1;
    end
  end

  //--------------------------------------------------------------------------
  // FIFO count
  //--------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fifo_count <= '0;
    end else begin
      case ({fifo_wr_en, fifo_rd_en})
        2'b10:   fifo_count <= fifo_count + 1;
        2'b01:   fifo_count <= fifo_count - 1;
        default: fifo_count <= fifo_count; // Both or neither
      endcase
    end
  end

  //--------------------------------------------------------------------------
  // Backpressure to crossbar: ready when FIFO not full
  //--------------------------------------------------------------------------
  assign xbar_ready = !fifo_full;

  //--------------------------------------------------------------------------
  // Output drive: valid when FIFO not empty
  //--------------------------------------------------------------------------
  assign out_valid = !fifo_empty;
  assign out_data  = fifo_mem[rd_ptr];

endmodule : pkt_output_stage
