//============================================================================
// File:    pkt_crossbar.sv
// Author:  Capstone RTL Design
// Desc:    4x4 crossbar switch with priority-based arbitration.
//          - Routes packets from input stages to output stages based on
//            dest_port field in packet header
//          - Higher priority packets win arbitration over lower priority
//          - Round-robin arbitration within the same priority level
//          - Once a packet starts transferring, it holds the path until EOP
//============================================================================

module pkt_crossbar
  import pkt_router_pkg::*;
(
  input  logic              clk,
  input  logic              rst_n,

  // From input stages (4 ports)
  input  logic [NUM_PORTS-1:0]      in_pkt_valid,
  input  data_t                     in_pkt_data   [NUM_PORTS],
  input  logic [NUM_PORTS-1:0]      in_pkt_sop,
  input  logic [NUM_PORTS-1:0]      in_pkt_eop,
  input  port_id_t                  in_pkt_dest   [NUM_PORTS],
  input  priority_t                 in_pkt_priority [NUM_PORTS],
  output logic [NUM_PORTS-1:0]      in_pkt_ready,

  // To output stages (4 ports)
  output logic [NUM_PORTS-1:0]      out_pkt_valid,
  output data_t                     out_pkt_data  [NUM_PORTS],
  output logic [NUM_PORTS-1:0]      out_pkt_sop,
  output logic [NUM_PORTS-1:0]      out_pkt_eop,
  output port_id_t                  out_pkt_src   [NUM_PORTS],
  input  logic [NUM_PORTS-1:0]      out_pkt_ready,

  // Statistics
  output logic [NUM_PORTS-1:0]      stat_pkt_routed  // Pulse per output port
);

  //--------------------------------------------------------------------------
  // Per-output-port arbitration state
  //--------------------------------------------------------------------------
  // Which input port is currently granted to each output port (-1 = none)
  logic [NUM_PORTS-1:0]  grant_active [NUM_PORTS]; // One-hot grant per output
  logic [NUM_PORTS-1:0]  grant_locked [NUM_PORTS]; // Lock during packet transfer
  logic [1:0]            rr_pointer   [NUM_PORTS]; // Round-robin pointer per output

  //--------------------------------------------------------------------------
  // Request matrix: request[out_port][in_port] = input wants this output
  //--------------------------------------------------------------------------
  logic [NUM_PORTS-1:0]  request [NUM_PORTS];
  priority_t             req_priority [NUM_PORTS][NUM_PORTS]; // Priority of each request

  // Build request matrix
  always_comb begin
    for (int op = 0; op < NUM_PORTS; op++) begin
      for (int ip = 0; ip < NUM_PORTS; ip++) begin
        request[op][ip]      = in_pkt_valid[ip] && (in_pkt_dest[ip] == op[1:0]);
        req_priority[op][ip] = in_pkt_priority[ip];
      end
    end
  end

  //--------------------------------------------------------------------------
  // Per-output-port arbiter
  //--------------------------------------------------------------------------
  logic [NUM_PORTS-1:0] new_grant [NUM_PORTS];

  genvar op;
  generate
    for (op = 0; op < NUM_PORTS; op++) begin : gen_arb

      // Priority-based round-robin arbiter for output port 'op'
      always_comb begin
        new_grant[op] = '0;

        if (grant_locked[op] != '0) begin
          // Locked: maintain current grant
          new_grant[op] = grant_locked[op];
        end else begin
          // Find highest priority among requesters
          priority_t highest_pri;
          highest_pri = 2'd0;

          // First pass: find highest priority
          for (int ip = 0; ip < NUM_PORTS; ip++) begin
            if (request[op][ip] && (req_priority[op][ip] >= highest_pri)) begin
              highest_pri = req_priority[op][ip];
            end
          end

          // Second pass: round-robin among highest priority requesters
          for (int i = 0; i < NUM_PORTS; i++) begin
            int ip;
            ip = (rr_pointer[op] + i) % NUM_PORTS;
            if (request[op][ip[1:0]] &&
                (req_priority[op][ip[1:0]] == highest_pri) &&
                (new_grant[op] == '0)) begin
              new_grant[op][ip[1:0]] = 1'b1;
            end
          end
        end
      end

      // Grant lock register: holds grant for duration of packet
      always_ff @(posedge clk) begin
        if (!rst_n) begin
          grant_locked[op] <= '0;
          grant_active[op] <= '0;
          rr_pointer[op]   <= '0;
        end else begin
          grant_active[op] <= new_grant[op];

          // Lock on SOP, release on EOP
          if (grant_locked[op] == '0) begin
            // Not locked: check if new grant has SOP
            for (int ip = 0; ip < NUM_PORTS; ip++) begin
              if (new_grant[op][ip] && in_pkt_sop[ip] && out_pkt_ready[op]) begin
                grant_locked[op] <= new_grant[op];
              end
            end
          end else begin
            // Locked: check for EOP to release
            for (int ip = 0; ip < NUM_PORTS; ip++) begin
              if (grant_locked[op][ip] && in_pkt_eop[ip] && out_pkt_ready[op]) begin
                grant_locked[op] <= '0;
                // Advance round-robin pointer past current winner
                rr_pointer[op] <= ip[1:0] + 2'd1;
              end
            end
          end
        end
      end

    end : gen_arb
  endgenerate

  //--------------------------------------------------------------------------
  // Crossbar data mux and output drive
  //--------------------------------------------------------------------------
  always_comb begin
    for (int op = 0; op < NUM_PORTS; op++) begin
      out_pkt_valid[op] = 1'b0;
      out_pkt_data[op]  = '0;
      out_pkt_sop[op]   = 1'b0;
      out_pkt_eop[op]   = 1'b0;
      out_pkt_src[op]   = '0;

      for (int ip = 0; ip < NUM_PORTS; ip++) begin
        if (grant_active[op][ip]) begin
          out_pkt_valid[op] = in_pkt_valid[ip];
          out_pkt_data[op]  = in_pkt_data[ip];
          out_pkt_sop[op]   = in_pkt_sop[ip];
          out_pkt_eop[op]   = in_pkt_eop[ip];
          out_pkt_src[op]   = ip[1:0];
        end
      end
    end
  end

  //--------------------------------------------------------------------------
  // Input ready: granted if the target output port's ready is asserted
  //--------------------------------------------------------------------------
  always_comb begin
    in_pkt_ready = '0;
    for (int op = 0; op < NUM_PORTS; op++) begin
      for (int ip = 0; ip < NUM_PORTS; ip++) begin
        if (grant_active[op][ip] && out_pkt_ready[op]) begin
          in_pkt_ready[ip] = 1'b1;
        end
      end
    end
  end

  //--------------------------------------------------------------------------
  // Statistics: pulse when a packet completes routing (EOP transferred)
  //--------------------------------------------------------------------------
  always_comb begin
    stat_pkt_routed = '0;
    for (int op = 0; op < NUM_PORTS; op++) begin
      stat_pkt_routed[op] = out_pkt_valid[op] && out_pkt_eop[op] && out_pkt_ready[op];
    end
  end

endmodule : pkt_crossbar
