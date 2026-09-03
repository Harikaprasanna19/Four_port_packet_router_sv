//============================================================================
// File:    pkt_input_stage.sv
// Author:  Capstone RTL Design
// Desc:    Input stage for one port of the packet router.
//          - Accepts data via valid/ready handshake
//          - Parses header to extract dest_port, priority, length
//          - Accumulates payload words and computes running CRC
//          - Validates CRC on last payload word
//          - Outputs complete packet to crossbar with routing info
//============================================================================

module pkt_input_stage
  import pkt_router_pkg::*;
#(
  parameter port_id_t PORT_ID = 2'd0
)(
  input  logic              clk,
  input  logic              rst_n,

  // External interface (from source)
  input  logic              in_valid,
  input  data_t             in_data,
  output logic              in_ready,

  // To crossbar - packet data
  output logic              pkt_valid,    // Packet word available
  output data_t             pkt_data,     // Packet word (header or payload)
  output logic              pkt_sop,      // Start of packet (header word)
  output logic              pkt_eop,      // End of packet (last payload word)
  output port_id_t          pkt_dest,     // Destination port from header
  output priority_t         pkt_priority, // Priority from header
  input  logic              pkt_ready,    // Crossbar can accept

  // Statistics outputs
  output logic              stat_crc_error,  // Pulse: CRC error detected
  output logic              stat_pkt_drop    // Pulse: packet dropped (CRC fail)
);

  //--------------------------------------------------------------------------
  // State machine
  //--------------------------------------------------------------------------
  typedef enum logic [1:0] {
    ST_IDLE,      // Waiting for header
    ST_PAYLOAD,   // Receiving payload words
    ST_CHECK,     // CRC check result available
    ST_DROP       // Draining bad packet (CRC error)
  } state_t;

  state_t           state, state_next;

  //--------------------------------------------------------------------------
  // Internal signals
  //--------------------------------------------------------------------------
  pkt_header_t      hdr_reg;
  logic [3:0]       word_cnt;       // Counts payload words received (0-based)
  logic [3:0]       pkt_len_minus1; // pkt_length - 1 for comparison

  // CRC signals
  logic             crc_init;
  logic             crc_valid;
  logic [31:0]      crc_data;
  crc_t             crc_out;
  logic             crc_good;

  // FIFO signals
  logic             fifo_wr_en;
  logic             fifo_rd_en;
  logic             fifo_full;
  logic             fifo_empty;
  data_t            fifo_wr_data;
  data_t            fifo_rd_data;

  // Packet metadata stored alongside FIFO
  logic             is_header_word;
  logic             is_last_word;

  // Small FIFO for buffering incoming packet (depth = MAX_PKT_LEN + 1)
  // Using a simple shift-register FIFO for the packet buffer
  localparam int BUF_DEPTH = MAX_PKT_LEN + 1; // header + 16 payload
  data_t            pkt_buf [BUF_DEPTH];
  logic [4:0]       buf_wr_ptr;
  logic [4:0]       buf_rd_ptr;
  logic [4:0]       buf_count;
  logic             buf_valid;  // Packet fully received and CRC-checked

  //--------------------------------------------------------------------------
  // CRC instance
  //--------------------------------------------------------------------------
  pkt_crc8 u_crc (
    .clk     (clk),
    .rst_n   (rst_n),
    .init    (crc_init),
    .valid   (crc_valid),
    .data_in (crc_data),
    .crc_out (crc_out)
  );

  //--------------------------------------------------------------------------
  // State register
  //--------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n)
      state <= ST_IDLE;
    else
      state <= state_next;
  end

  //--------------------------------------------------------------------------
  // Packet buffer write logic
  //--------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      buf_wr_ptr <= '0;
      hdr_reg    <= '0;
      word_cnt   <= '0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (in_valid && in_ready) begin
            // Capture header
            hdr_reg    <= parse_header(in_data);
            pkt_buf[0] <= in_data;
            buf_wr_ptr <= 5'd1;
            word_cnt   <= '0;
          end
        end

        ST_PAYLOAD: begin
          if (in_valid && in_ready) begin
            pkt_buf[buf_wr_ptr] <= in_data;
            buf_wr_ptr          <= buf_wr_ptr + 1;
            word_cnt            <= word_cnt + 1;
          end
        end

        ST_CHECK: begin
          // Reset write pointer for next packet
          buf_wr_ptr <= '0;
          word_cnt   <= '0;
        end

        ST_DROP: begin
          buf_wr_ptr <= '0;
          word_cnt   <= '0;
        end
      endcase
    end
  end

  //--------------------------------------------------------------------------
  // Derived signals
  //--------------------------------------------------------------------------
  assign pkt_len_minus1 = hdr_reg.pkt_length[3:0] - 4'd1;

  // CRC is good when residue is zero (all data including CRC byte fed through)
  assign crc_good = (crc_out == 8'h00);

  //--------------------------------------------------------------------------
  // State machine next-state logic
  //--------------------------------------------------------------------------
  always_comb begin
    state_next = state;
    case (state)
      ST_IDLE: begin
        if (in_valid && in_ready)
          state_next = ST_PAYLOAD;
      end

      ST_PAYLOAD: begin
        if (in_valid && in_ready) begin
          if (word_cnt == pkt_len_minus1)
            state_next = ST_CHECK;
        end
      end

      ST_CHECK: begin
        if (crc_good)
          state_next = ST_IDLE;
        else
          state_next = ST_DROP;
      end

      ST_DROP: begin
        state_next = ST_IDLE;
      end
    endcase
  end

  //--------------------------------------------------------------------------
  // CRC control: initialize on new packet, feed data during header+payload
  //--------------------------------------------------------------------------
  always_comb begin
    crc_init  = 1'b0;
    crc_valid = 1'b0;
    crc_data  = '0;

    case (state)
      ST_IDLE: begin
        if (in_valid && in_ready) begin
          crc_init  = 1'b1;   // Initialize CRC
          crc_valid = 1'b1;   // Feed header word
          crc_data  = in_data;
        end
      end

      ST_PAYLOAD: begin
        if (in_valid && in_ready) begin
          crc_valid = 1'b1;
          crc_data  = in_data;
        end
      end

      default: begin
        crc_init  = 1'b0;
        crc_valid = 1'b0;
      end
    endcase
  end

  //--------------------------------------------------------------------------
  // Input ready: accept data when in IDLE or PAYLOAD state
  //--------------------------------------------------------------------------
  assign in_ready = (state == ST_IDLE) || (state == ST_PAYLOAD);

  //--------------------------------------------------------------------------
  // Output to crossbar
  // Forward stored packet only after CRC check passes
  //--------------------------------------------------------------------------
  logic [4:0] out_rd_ptr;
  logic [4:0] out_words_remaining;
  logic       outputting;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      out_rd_ptr         <= '0;
      out_words_remaining <= '0;
      outputting         <= 1'b0;
    end else begin
      if (state == ST_CHECK && crc_good) begin
        // Start outputting the buffered packet
        out_rd_ptr         <= '0;
        out_words_remaining <= buf_wr_ptr; // Total words (header + payload)
        outputting         <= 1'b1;
      end else if (outputting && pkt_ready) begin
        if (out_words_remaining == 5'd1) begin
          outputting <= 1'b0;
          out_words_remaining <= '0;
        end else begin
          out_rd_ptr          <= out_rd_ptr + 1;
          out_words_remaining <= out_words_remaining - 1;
        end
      end
    end
  end

  assign pkt_valid    = outputting;
  assign pkt_data     = pkt_buf[out_rd_ptr];
  assign pkt_sop      = outputting && (out_rd_ptr == '0);
  assign pkt_eop      = outputting && (out_words_remaining == 5'd1);
  assign pkt_dest     = hdr_reg.dest_port;
  assign pkt_priority = hdr_reg.prio;

  //--------------------------------------------------------------------------
  // Statistics pulses
  //--------------------------------------------------------------------------
  assign stat_crc_error = (state == ST_CHECK) && !crc_good;
  assign stat_pkt_drop  = (state == ST_CHECK) && !crc_good;

endmodule : pkt_input_stage
