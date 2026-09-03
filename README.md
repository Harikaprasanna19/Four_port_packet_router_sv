# Four_port_packet_router_sv
# Project — Packet Router RTL

## Overview

The capstone project is a 4-port packet router with CRC checking, crossbar switching, and statistics registers. Students will build a complete SystemVerilog class-based verification environment from scratch to verify this design.

The router accepts variable-length packets on four input ports, routes them to output ports based on a destination field in the header, computes and checks CRC-8, and maintains statistics counters accessible via a register interface.

## Architecture

```
        +-------------+     +-----------+     +--------------+
IN[0] ->| input_stage |---->|           |---->| output_stage |-> OUT[0]
IN[1] ->| input_stage |---->|  crossbar |---->| output_stage |-> OUT[1]
IN[2] ->| input_stage |---->|           |---->| output_stage |-> OUT[2]
IN[3] ->| input_stage |---->|           |---->| output_stage |-> OUT[3]
        +-------------+     +-----------+     +--------------+
                                  |
                            +------------+
                            | stats_regs |<-- APB register bus
                            +------------+
```

## RTL Files

| File                  | Description                                            |
| --------------------- | ------------------------------------------------------ |
| `pkt_router_pkg.sv`   | Package with type definitions, parameters, and structs |
| `pkt_router_if.sv`    | Interface definitions for packet and register ports    |
| `pkt_crc8.sv`         | CRC-8 computation module                               |
| `pkt_input_stage.sv`  | Input buffering, header parsing, and CRC check         |
| `pkt_crossbar.sv`     | Non-blocking crossbar switch with arbitration          |
| `pkt_output_stage.sv` | Output buffering and packet assembly                   |
| `pkt_stats_regs.sv`   | APB-accessible statistics and configuration registers  |
| `pkt_router_top.sv`   | Top-level integration of all submodules                |

## Full Specification

See `doc/capstone_spec.sv` for the complete design specification including:

- Packet format and field definitions
- Routing algorithm and priority scheme
- CRC polynomial and error handling
- Register map and access types
- Timing requirements and latency guarantees

## How to Compile

```
make compile
```

This verifies the RTL compiles cleanly. There is no testbench here — building the class-based verification environment is the student's task.

## Milestone Plan

1. **Milestone 1** — Define transaction class with `randomize()` constraints
2. **Milestone 2** — Create generator, input driver, and output driver (backpressure)
3. **Milestone 3** — Implement input and output monitors
4. **Milestone 4** — Build scoreboard with routing reference model and CRC check
5. **Milestone 5** — Add APB driver/monitor for statistics register reads
6. **Milestone 6** — Write directed tests for basic routing and error scenarios
7. **Milestone 7** — Add constrained-random stimulus, covergroups, and SVA assertions
8. **Final** — Close coverage holes, document bugs found, final regression

## Learning Outcomes

- Architect a layered SystemVerilog testbench (Generator → Driver → Monitor → Scoreboard → Coverage)
- Apply all verification concepts from Sessions 1–10 in an integrated project
- Use mailboxes, virtual interfaces, and `fork/join` to build concurrent TB components
- Practice coverage-driven verification methodology end-to-end
- Develop debugging skills on a realistic multi-port design with intentional RTL bugs
