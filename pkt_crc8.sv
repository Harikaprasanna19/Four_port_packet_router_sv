//============================================================================
// File:    pkt_crc8.sv
// Author:  Capstone RTL Design
// Desc:    CRC-8 calculator using polynomial 0x07 (x^8+x^2+x+1)
//          Processes 32 bits per clock cycle (byte-at-a-time internally).
//          Provides running CRC that can be checked at end of packet.
//============================================================================
// Usage:
//   1. Assert 'init' for one cycle to reset CRC to seed (0xFF)
//   2. Assert 'valid' with 'data_in' for each 32-bit word
//   3. After last word, 'crc_out' holds the computed CRC
//   4. For checking: feed all data including received CRC; result should be 0
//============================================================================
module pkt_crc8
  import pkt_router_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              init,       // Initialize CRC to seed
  input  logic              valid,      // Input data valid
  input  logic [31:0]       data_in,    // 32-bit input data
  output logic [CRC_WIDTH-1:0] crc_out  // Current CRC value
);
  //--------------------------------------------------------------------------
  // Internal signals
  //--------------------------------------------------------------------------
  logic [7:0] crc_reg;
  logic [7:0] crc_next;
  logic [7:0] crc_byte0, crc_byte1, crc_byte2, crc_byte3;
  //--------------------------------------------------------------------------
  // CRC-8 computation for a single byte
  //--------------------------------------------------------------------------
  function automatic logic [7:0] crc8_byte(
    input logic [7:0] crc_in,
    input logic [7:0] data_byte
  );
    logic [7:0] crc;
    crc = crc_in;
    for (int i = 7; i >= 0; i--) begin
      if (crc[7] ^ data_byte[i]) begin
        crc = {crc[6:0], 1'b0} ^ CRC_POLY;
      end else begin
        crc = {crc[6:0], 1'b0};
      end
    end
    return crc;
  endfunction
  //--------------------------------------------------------------------------
  // Process 4 bytes per cycle (MSB first: byte3, byte2, byte1, byte0)
  //--------------------------------------------------------------------------
  always_comb begin
    crc_byte3 = crc8_byte(crc_reg,  data_in[31:24]);
    crc_byte2 = crc8_byte(crc_byte3, data_in[23:16]);
    crc_byte1 = crc8_byte(crc_byte2, data_in[15:8]);
    crc_byte0 = crc8_byte(crc_byte1, data_in[7:0]);
    crc_next  = crc_byte0;
  end
  //--------------------------------------------------------------------------
  // CRC register
  //--------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      crc_reg <= 8'hFF;  // Seed value
    end else if (init) begin
      crc_reg <= 8'hFF;  // Re-initialize
    end else if (valid) begin
      crc_reg <= crc_next;
    end
  end
  assign crc_out = crc_reg;
endmodule : pkt_crc8
