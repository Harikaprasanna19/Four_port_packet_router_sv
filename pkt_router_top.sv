//============================================================================
// File:    pkt_router_top.sv
// Author:  Capstone RTL Design
// Desc:    Top-level module for the 4-port Packet Router/Switch.
//
//          Architecture:
//            4x Input Stages --> 4x4 Crossbar --> 4x Output Stages
//                                                   |
//                                             Stats Registers (APB-lite)
//
//          Features:
//            - 4 input ports, 4 output ports (valid/ready handshake)
//            - Priority-based arbitration (4 levels, round-robin within)
//            - CRC-8 validation on input (bad packets dropped)
//            - Backpressure propagation (no data loss)
//            - APB-lite statistics interface
//            - Synchronous active-low reset
//============================================================================

module pkt_router_top
  import pkt_router_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,

  // Input ports (from external sources)
  input  logic [NUM_PORTS-1:0]      in_valid,
  input  data_t                     in_data    [NUM_PORTS],
  output logic [NUM_PORTS-1:0]      in_ready,

  // Output ports (to external sinks)
  output logic [NUM_PORTS-1:0]      out_valid,
  output data_t                     out_data   [NUM_PORTS],
  input  logic [NUM_PORTS-1:0]      out_ready,

  // APB-lite statistics interface
  input  logic                       apb_psel,
  input  logic                       apb_penable,
  input  logic                       apb_pwrite,
  input  logic [APB_ADDR_WIDTH-1:0]  apb_paddr,
  input  logic [APB_DATA_WIDTH-1:0]  apb_pwdata,
  output logic [APB_DATA_WIDTH-1:0]  apb_prdata,
  output logic                       apb_pready,
  output logic                       apb_pslverr
);

  //--------------------------------------------------------------------------
  // Internal signals: Input Stage -> Crossbar
  //--------------------------------------------------------------------------
  logic [NUM_PORTS-1:0]  istg_pkt_valid;
  data_t                 istg_pkt_data    [NUM_PORTS];
  logic [NUM_PORTS-1:0]  istg_pkt_sop;
  logic [NUM_PORTS-1:0]  istg_pkt_eop;
  port_id_t              istg_pkt_dest    [NUM_PORTS];
  priority_t             istg_pkt_priority[NUM_PORTS];
  logic [NUM_PORTS-1:0]  istg_pkt_ready;

  // Internal signals: Crossbar -> Output Stage
  logic [NUM_PORTS-1:0]  xbar_pkt_valid;
  data_t                 xbar_pkt_data    [NUM_PORTS];
  logic [NUM_PORTS-1:0]  xbar_pkt_sop;
  logic [NUM_PORTS-1:0]  xbar_pkt_eop;
  port_id_t              xbar_pkt_src     [NUM_PORTS];
  logic [NUM_PORTS-1:0]  xbar_pkt_ready;

  // Statistics signals
  logic [NUM_PORTS-1:0]  stat_pkt_routed;
  logic [NUM_PORTS-1:0]  stat_crc_error;
  logic [NUM_PORTS-1:0]  stat_pkt_dropped;

  //--------------------------------------------------------------------------
  // Input Stages (4 instances)
  //--------------------------------------------------------------------------
  genvar gi;
  generate
    for (gi = 0; gi < NUM_PORTS; gi++) begin : gen_input_stage
      pkt_input_stage #(
        .PORT_ID(gi[1:0])
      ) u_input_stage (
        .clk           (clk),
        .rst_n         (rst_n),

        // External input
        .in_valid      (in_valid[gi]),
        .in_data       (in_data[gi]),
        .in_ready      (in_ready[gi]),

        // To crossbar
        .pkt_valid     (istg_pkt_valid[gi]),
        .pkt_data      (istg_pkt_data[gi]),
        .pkt_sop       (istg_pkt_sop[gi]),
        .pkt_eop       (istg_pkt_eop[gi]),
        .pkt_dest      (istg_pkt_dest[gi]),
        .pkt_priority  (istg_pkt_priority[gi]),
        .pkt_ready     (istg_pkt_ready[gi]),

        // Statistics
        .stat_crc_error(stat_crc_error[gi]),
        .stat_pkt_drop (stat_pkt_dropped[gi])
      );
    end : gen_input_stage
  endgenerate

  //--------------------------------------------------------------------------
  // Crossbar
  //--------------------------------------------------------------------------
  pkt_crossbar u_crossbar (
    .clk             (clk),
    .rst_n           (rst_n),

    // From input stages
    .in_pkt_valid    (istg_pkt_valid),
    .in_pkt_data     (istg_pkt_data),
    .in_pkt_sop      (istg_pkt_sop),
    .in_pkt_eop      (istg_pkt_eop),
    .in_pkt_dest     (istg_pkt_dest),
    .in_pkt_priority (istg_pkt_priority),
    .in_pkt_ready    (istg_pkt_ready),

    // To output stages
    .out_pkt_valid   (xbar_pkt_valid),
    .out_pkt_data    (xbar_pkt_data),
    .out_pkt_sop     (xbar_pkt_sop),
    .out_pkt_eop     (xbar_pkt_eop),
    .out_pkt_src     (xbar_pkt_src),
    .out_pkt_ready   (xbar_pkt_ready),

    // Statistics
    .stat_pkt_routed (stat_pkt_routed)
  );

  //--------------------------------------------------------------------------
  // Output Stages (4 instances)
  //--------------------------------------------------------------------------
  generate
    for (gi = 0; gi < NUM_PORTS; gi++) begin : gen_output_stage
      pkt_output_stage #(
        .PORT_ID(gi[1:0])
      ) u_output_stage (
        .clk         (clk),
        .rst_n       (rst_n),

        // From crossbar
        .xbar_valid  (xbar_pkt_valid[gi]),
        .xbar_data   (xbar_pkt_data[gi]),
        .xbar_sop    (xbar_pkt_sop[gi]),
        .xbar_eop    (xbar_pkt_eop[gi]),
        .xbar_src    (xbar_pkt_src[gi]),
        .xbar_ready  (xbar_pkt_ready[gi]),

        // External output
        .out_valid   (out_valid[gi]),
        .out_data    (out_data[gi]),
        .out_ready   (out_ready[gi])
      );
    end : gen_output_stage
  endgenerate

  //--------------------------------------------------------------------------
  // Statistics Registers (APB-lite slave)
  //--------------------------------------------------------------------------
  pkt_stats_regs u_stats_regs (
    .clk              (clk),
    .rst_n            (rst_n),

    // APB-lite
    .apb_psel         (apb_psel),
    .apb_penable      (apb_penable),
    .apb_pwrite       (apb_pwrite),
    .apb_paddr        (apb_paddr),
    .apb_pwdata       (apb_pwdata),
    .apb_prdata       (apb_prdata),
    .apb_pready       (apb_pready),
    .apb_pslverr      (apb_pslverr),

    // Statistics pulses
    .stat_pkt_routed  (stat_pkt_routed),
    .stat_pkt_dropped (stat_pkt_dropped),
    .stat_crc_error   (stat_crc_error)
  );

endmodule : pkt_router_top
