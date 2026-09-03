//============================================================================
// File:    pkt_stats_regs.sv
// Author:  Capstone RTL Design
// Desc:    APB-lite slave providing read-only statistics registers.
//          Registers:
//            0x00-0x0C: packets_routed[0:3]   (per output port)
//            0x10-0x1C: packets_dropped[0:3]  (per input port, CRC fail)
//            0x20-0x2C: crc_errors[0:3]       (per input port)
//          All counters are 32-bit. Read-only (writes are ignored).
//          Counters clear on reset only.
//============================================================================

module pkt_stats_regs
  import pkt_router_pkg::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // APB-lite slave interface
  input  logic                       apb_psel,
  input  logic                       apb_penable,
  input  logic                       apb_pwrite,
  input  logic [APB_ADDR_WIDTH-1:0]  apb_paddr,
  input  logic [APB_DATA_WIDTH-1:0]  apb_pwdata,
  output logic [APB_DATA_WIDTH-1:0]  apb_prdata,
  output logic                       apb_pready,
  output logic                       apb_pslverr,

  // Statistics inputs (active-high pulses)
  input  logic [NUM_PORTS-1:0]       stat_pkt_routed,  // Per output port
  input  logic [NUM_PORTS-1:0]       stat_pkt_dropped, // Per input port
  input  logic [NUM_PORTS-1:0]       stat_crc_error    // Per input port
);

  //--------------------------------------------------------------------------
  // Counter registers (32-bit each, no saturation - wraps on overflow)
  //--------------------------------------------------------------------------
  logic [31:0] pkts_routed  [NUM_PORTS];
  logic [31:0] pkts_dropped [NUM_PORTS];
  logic [31:0] crc_errors   [NUM_PORTS];

  //--------------------------------------------------------------------------
  // Counter increment logic
  //--------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_PORTS; i++) begin
        pkts_routed[i]  <= '0;
        pkts_dropped[i] <= '0;
        crc_errors[i]   <= '0;
      end
    end else begin
      for (int i = 0; i < NUM_PORTS; i++) begin
        // Packets routed (per output port)
        if (stat_pkt_routed[i])
          pkts_routed[i] <= pkts_routed[i] + 32'd1;

        // Packets dropped (per input port, CRC failure)
        if (stat_pkt_dropped[i])
          pkts_dropped[i] <= pkts_dropped[i] + 32'd1;

        // CRC errors (per input port)
        if (stat_crc_error[i])
          crc_errors[i] <= crc_errors[i] + 32'd1;
      end
    end
  end

  //--------------------------------------------------------------------------
  // APB-lite read logic
  //--------------------------------------------------------------------------
  logic apb_rd_phase;
  assign apb_rd_phase = apb_psel && apb_penable && !apb_pwrite;

  always_comb begin
    apb_prdata  = '0;
    apb_pslverr = 1'b0;

    if (apb_rd_phase) begin
      case (apb_paddr)
        ADDR_PKTS_ROUTED_0:  apb_prdata = pkts_routed[0];
        ADDR_PKTS_ROUTED_1:  apb_prdata = pkts_routed[1];
        ADDR_PKTS_ROUTED_2:  apb_prdata = pkts_routed[2];
        ADDR_PKTS_ROUTED_3:  apb_prdata = pkts_routed[3];
        ADDR_PKTS_DROPPED_0: apb_prdata = pkts_dropped[0];
        ADDR_PKTS_DROPPED_1: apb_prdata = pkts_dropped[1];
        ADDR_PKTS_DROPPED_2: apb_prdata = pkts_dropped[2];
        ADDR_PKTS_DROPPED_3: apb_prdata = pkts_dropped[3];
        ADDR_CRC_ERRORS_0:   apb_prdata = crc_errors[0];
        ADDR_CRC_ERRORS_1:   apb_prdata = crc_errors[1];
        ADDR_CRC_ERRORS_2:   apb_prdata = crc_errors[2];
        ADDR_CRC_ERRORS_3:   apb_prdata = crc_errors[3];
        default:             apb_pslverr = 1'b1; // Invalid address
      endcase
    end
  end

  // APB always responds in 1 wait state (ready on enable phase)
  assign apb_pready = apb_psel && apb_penable;

endmodule : pkt_stats_regs
