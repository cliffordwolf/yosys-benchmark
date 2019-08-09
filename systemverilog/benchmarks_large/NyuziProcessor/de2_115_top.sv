// diego: Since this project uses altera IP, and
// we don't want to integrate vendor specific IP in benchmark suite,
// blackboxes will fulfill the missing cells.
`define VENDOR_ALTERA
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

`ifndef __CONFIG_V
`define __CONFIG_V

//
// Configurable parameters
// - THREADS_PER_CORE must be 2 or greater.
// - Number of cache ways must be 1, 2, 4, or 8 (TLB_WAYS does not have
//   this constraint). This is a limitation in the cache_lru module.
// - L1D_WAYS/L1I_WAYS must be greater than or equal to THREADS_PER_CORE,
//   otherwise the system may livelock on a cache miss.
// - The number of cache sets must be a power of two.
// - If you change the number of L2 ways, you must also modify the
//   flush_l2_cache function in testbench/soc_tb.sv. Comments above
//   that function describe how and why.
// - NUM_CORES must be 1-16. To synthesize more cores, increase the
//   width of core_id_t in defines.sv (as above, comments there describe why).
// - L1D_SETS sets must be 64 or fewer (page size / cache line size). This
//   avoids aliasing in the virtually indexed/physically tagged L1 cache by
//   preventing the same physical address from appearing in different cache
//   sets (see dcache_tag_stage).
// - The size of a cache is sets * ways * cache line size (64 bytes)
//

`define NUM_CORES 1
`define THREADS_PER_CORE 4
`define L1D_WAYS 4
`define L1D_SETS 64        // 16k
`define L1I_WAYS 4
`define L1I_SETS 64        // 16k
`define L2_WAYS 8
`define L2_SETS 256        // 128k
`define AXI_DATA_WIDTH 32
`define ITLB_ENTRIES 64
`define DTLB_ENTRIES 64
`define TLB_WAYS 4

// Picked random part version and number to have unique pattern to verify.
// The manufacturer ID is chosen to be the last possible ID.
`define JTAG_PART_VERSION 4
`define JTAG_PART_NUMBER 'hd20d
`define JTAG_MANUFACTURER_ID {4'b1111,  7'b1111101}

`endif



//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

`ifndef __DEFINES_SVH
`define __DEFINES_SVH

//`include "config.svh"

package defines;

//
// Floating point types
//

parameter FLOAT32_EXP_WIDTH = 8;
parameter FLOAT32_SIG_WIDTH = 23;

// IEEE 754 Binary 32 encoding
typedef struct packed {
    logic sign;
    logic[FLOAT32_EXP_WIDTH - 1:0] exponent;
    logic[FLOAT32_SIG_WIDTH - 1:0] significand;
} float32_t;

//
// Execution pipeline defines
//

parameter NUM_VECTOR_LANES = 16;
parameter NUM_REGISTERS = 32;
parameter TOTAL_THREADS = `THREADS_PER_CORE * `NUM_CORES;

typedef logic[31:0] scalar_t;
typedef scalar_t[NUM_VECTOR_LANES - 1:0] vector_t;
typedef logic[$clog2(`THREADS_PER_CORE) - 1:0] local_thread_idx_t;
typedef logic[`THREADS_PER_CORE - 1:0] local_thread_bitmap_t; // One bit per thread
typedef logic[4:0] register_idx_t;
typedef logic[$clog2(NUM_VECTOR_LANES) - 1:0] subcycle_t;
typedef logic[NUM_VECTOR_LANES - 1:0] vector_mask_t;
typedef logic[14:0] syscall_index_t;

parameter CORE_ID_WIDTH = $clog2(`NUM_CORES);

// The width of core_id_t is hardcoded to work around some tool issues.
// For one core, CORE_ID_WIDTH will be 0, but if I made the range
// [CORE_ID_WIDTH - 1:0], the range would be [-1:0], which is invalid. I tried
// defining CORE_ID_WIDTH as (`NUM_CORES == 1 ? 1 : $clog2(`NUM_CORES)), which
// works fine on many tools, but crashes Synopsys Design Compiler. This limits
// to 16 cores. To synthesize more, increase this width.
// XXX CORE_ID_WIDTH was previously a `define. the workaround above may work
// now that it is a parameter, but I haven't tested.
typedef logic[3:0] core_id_t;

// CORE_PERF_EVENTS should match the number of signals in the assignment to
// core_perf_events in core.sv and L2_PERF_EVENTS must match the number of
// signals in the assignment to l2_perf_events in l2_cache.sv.
parameter CORE_PERF_EVENTS = 14;
parameter L2_PERF_EVENTS = 3;

//
// Instruction encodings
//

parameter INSTRUCTION_NOP = 32'd0;
parameter REG_RA = register_idx_t'(31);

// Immediate/register arithmetic operation encodings
typedef enum logic[5:0] {
    OP_OR                   = 6'b000000,    // Bitwise logical or
    OP_AND                  = 6'b000001,    // bitwise logical and
    OP_SYSCALL              = 6'b000010,    // raise syscall trap
    OP_XOR                  = 6'b000011,    // bitwise logical exclusive or
    OP_ADD_I                = 6'b000101,    // Add integer
    OP_SUB_I                = 6'b000110,    // Subtract integer
    OP_MULL_I               = 6'b000111,    // Multiply integer low
    OP_MULH_U               = 6'b001000,    // Unsigned multiply, return high bits
    OP_ASHR                 = 6'b001001,    // Arithmetic shift right (sign extend)
    OP_SHR                  = 6'b001010,    // Logical shift right (no sign extend)
    OP_SHL                  = 6'b001011,    // Logical shift left
    OP_CLZ                  = 6'b001100,    // Count leading zeroes
    OP_SHUFFLE              = 6'b001101,    // Shuffle vector lanes
    OP_CTZ                  = 6'b001110,    // Count trailing zeroes
    OP_MOVE                 = 6'b001111,
    OP_CMPEQ_I              = 6'b010000,    // Integer equal
    OP_CMPNE_I              = 6'b010001,    // Integer not equal
    OP_CMPGT_I              = 6'b010010,    // Integer greater (signed)
    OP_CMPGE_I              = 6'b010011,    // Integer greater or equal (signed)
    OP_CMPLT_I              = 6'b010100,    // Integer less than (signed)
    OP_CMPLE_I              = 6'b010101,    // Integer less than or equal (signed)
    OP_CMPGT_U              = 6'b010110,    // Integer greater than (unsigned)
    OP_CMPGE_U              = 6'b010111,    // Integer greater or equal (unsigned)
    OP_CMPLT_U              = 6'b011000,    // Integer less than (unsigned)
    OP_CMPLE_U              = 6'b011001,    // Integer less than or equal (unsigned)
    OP_GETLANE              = 6'b011010,    // Getlane
    OP_FTOI                 = 6'b011011,    // Float to integer
    OP_RECIPROCAL           = 6'b011100,    // Reciprocal estimate
    OP_SEXT8                = 6'b011101,    // Sign extend 8 bit value
    OP_SEXT16               = 6'b011110,    // Sign extend 16 bit value
    OP_MULH_I               = 6'b011111,    // Signed multiply high
    OP_ADD_F                = 6'b100000,    // Add floating point
    OP_SUB_F                = 6'b100001,    // Subtract floating point
    OP_MUL_F                = 6'b100010,    // Multiply floating point
    OP_ITOF                 = 6'b101010,    // Integer to float
    OP_CMPGT_F              = 6'b101100,    // Floating point greater than
    OP_CMPLT_F              = 6'b101110,    // Floating point less than
    OP_CMPGE_F              = 6'b101101,    // Floating point greater or equal
    OP_CMPLE_F              = 6'b101111,    // Floating point less than or equal
    OP_CMPEQ_F              = 6'b110000,    // Floating point equal
    OP_CMPNE_F              = 6'b110001,    // Floating point not-equal
    OP_BREAKPOINT           = 6'b111110
} alu_op_t;

// Operation type field encodings for memory instructions
typedef enum logic[3:0] {
    MEM_B                   = 4'b0000,  // Byte (8 bit)
    MEM_BX                  = 4'b0001,  // Byte, sign extended
    MEM_S                   = 4'b0010,  // Short (16 bit)
    MEM_SX                  = 4'b0011,  // Short, sign extended
    MEM_L                   = 4'b0100,  // Long (32 bit)
    MEM_SYNC                = 4'b0101,  // Synchronized
    MEM_CONTROL_REG         = 4'b0110,  // Control register
    MEM_BLOCK               = 4'b0111,  // Vector block
    MEM_BLOCK_M             = 4'b1000,
    MEM_SCGATH              = 4'b1101,  // Vector scatter/gather
    MEM_SCGATH_M            = 4'b1110
} memory_op_t;

// Operation type field encodings for cache control instructions
typedef enum logic[2:0] {
    CACHE_DTLB_INSERT       = 3'b000,
    CACHE_DINVALIDATE       = 3'b001,
    CACHE_DFLUSH            = 3'b010,
    CACHE_IINVALIDATE       = 3'b011,
    CACHE_MEMBAR            = 3'b100,
    CACHE_TLB_INVAL         = 3'b101,
    CACHE_TLB_INVAL_ALL     = 3'b110,
    CACHE_ITLB_INSERT       = 3'b111
} cache_op_t;

// Operation type field encodings for branch instructions
typedef enum logic[2:0] {
    BRANCH_REGISTER         = 3'b000,
    BRANCH_ZERO             = 3'b001,
    BRANCH_NOT_ZERO         = 3'b010,
    BRANCH_ALWAYS           = 3'b011,
    BRANCH_CALL_OFFSET      = 3'b100,
    BRANCH_CALL_REGISTER    = 3'b110,
    BRANCH_ERET             = 3'b111
} branch_type_t;

// Control register indices
typedef enum logic [4:0] {
    CR_THREAD_ID            = 5'd0,
    CR_TRAP_HANDLER         = 5'd1,
    CR_TRAP_PC              = 5'd2,
    CR_TRAP_CAUSE           = 5'd3,
    CR_FLAGS                = 5'd4,
    CR_TRAP_ADDRESS         = 5'd5,
    CR_CYCLE_COUNT          = 5'd6,
    CR_TLB_MISS_HANDLER     = 5'd7,
    CR_SAVED_FLAGS          = 5'd8,
    CR_CURRENT_ASID         = 5'd9,
    CR_PAGE_DIR             = 5'd10,
    CR_SCRATCHPAD0          = 5'd11,
    CR_SCRATCHPAD1          = 5'd12,
    CR_SUBCYCLE             = 5'd13,
    CR_INTERRUPT_ENABLE     = 5'd14,
    CR_INTERRUPT_ACK        = 5'd15,
    CR_INTERRUPT_PENDING    = 5'd16,
    CR_INTERRUPT_TRIGGER    = 5'd17,
    CR_JTAG_DATA            = 5'd18,
    CR_SYSCALL_INDEX        = 5'd19,
    CR_SUSPEND_THREAD       = 5'd20,
    CR_RESUME_THREAD        = 5'd21,
    CR_PERF_EVENT_SELECT0   = 5'd22,
    CR_PERF_EVENT_SELECT1   = 5'd23,
    CR_PERF_EVENT_COUNT0_L  = 5'd24,
    CR_PERF_EVENT_COUNT0_H  = 5'd25,
    CR_PERF_EVENT_COUNT1_L  = 5'd26,
    CR_PERF_EVENT_COUNT1_H  = 5'd27
} control_register_t;

// Trap type encodings
typedef enum logic[3:0] {
    TT_RESET                = 4'd0,
    TT_ILLEGAL_INSTRUCTION  = 4'd1,
    TT_PRIVILEGED_OP        = 4'd2,
    TT_INTERRUPT            = 4'd3,
    TT_SYSCALL              = 4'd4,
    TT_UNALIGNED_ACCESS     = 4'd5,
    TT_PAGE_FAULT           = 4'd6,
    TT_TLB_MISS             = 4'd7,
    TT_ILLEGAL_STORE        = 4'd8,
    TT_SUPERVISOR_ACCESS    = 4'd9,
    TT_NOT_EXECUTABLE       = 4'd10,
    TT_BREAKPOINT           = 4'd11
} trap_type_t;

//
// Decoded instruction fields
//

typedef enum logic [1:0] {
    MASK_SRC_SCALAR1,
    MASK_SRC_SCALAR2,
    MASK_SRC_ALL_ONES
} mask_src_t;

typedef enum logic {
    OP1_SRC_VECTOR1,
    OP1_SRC_SCALAR1
} op1_src_t;

typedef enum logic [1:0] {
    OP2_SRC_SCALAR2,
    OP2_SRC_VECTOR2,
    OP2_SRC_IMMEDIATE
} op2_src_t;

typedef enum logic [1:0] {
    PIPE_MEM,
    PIPE_INT_ARITH,
    PIPE_FLOAT_ARITH
} pipeline_sel_t;

typedef struct packed {
    logic dcache;
    logic store;
    trap_type_t trap_type;
} trap_cause_t;

typedef logic[3:0] interrupt_id_t;

typedef struct packed {
    scalar_t pc;

    // Was this instruction injected by the on-chip debugger
    logic injected;

    // Piggybacked exceptions
    logic has_trap;
    trap_cause_t trap_cause;

    // Decoded instruction fields
    logic has_scalar1;
    register_idx_t scalar_sel1;
    logic has_scalar2;
    register_idx_t scalar_sel2;
    logic has_vector1;
    register_idx_t vector_sel1;
    logic has_vector2;
    register_idx_t vector_sel2;
    logic has_dest;
    logic dest_vector;
    register_idx_t dest_reg;
    alu_op_t alu_op;
    mask_src_t mask_src;
    op1_src_t op1_src;
    op2_src_t op2_src;
    logic store_value_vector;
    scalar_t immediate_value;
    logic branch;
    branch_type_t branch_type;
    logic call;
    pipeline_sel_t pipeline_sel;
    logic memory_access;
    memory_op_t memory_access_type;
    logic load;
    logic compare;
    subcycle_t last_subcycle; // count of last subcycle, not a boolean flag
    control_register_t creg_index;
    logic cache_control;
    cache_op_t cache_control_op;
} decoded_instruction_t;

//
// Cache defines
//

parameter PAGE_SIZE = 'h1000;
parameter PAGE_NUM_BITS  = 32 - $clog2(PAGE_SIZE);
parameter ASID_WIDTH = 8;
parameter CACHE_LINE_BYTES = NUM_VECTOR_LANES * 4; // Must be same as vector width
parameter CACHE_LINE_BITS = CACHE_LINE_BYTES * 8;
parameter CACHE_LINE_WORDS = CACHE_LINE_BYTES / 4;
parameter CACHE_LINE_OFFSET_WIDTH = $clog2(CACHE_LINE_BYTES);    // Byte offset into a cache line
parameter ICACHE_TAG_BITS = 32 - (CACHE_LINE_OFFSET_WIDTH + $clog2(`L1I_SETS));
parameter DCACHE_TAG_BITS = 32 - (CACHE_LINE_OFFSET_WIDTH + $clog2(`L1D_SETS));

typedef logic[CACHE_LINE_BITS - 1:0] cache_line_data_t;
typedef logic[PAGE_NUM_BITS - 1:0] page_index_t;

typedef struct packed {
    logic[PAGE_NUM_BITS - 1:0] ppage_idx;
    logic[32 - (PAGE_NUM_BITS + 5) - 1:0] unused;
    logic global_map;
    logic supervisor;
    logic executable;
    logic writable;
    logic present;
} tlb_entry_t;

typedef logic[$clog2(`L1D_WAYS) - 1:0] l1d_way_idx_t;
typedef logic[$clog2(`L1D_SETS) - 1:0] l1d_set_idx_t;
typedef logic[DCACHE_TAG_BITS - 1:0] l1d_tag_t;

typedef struct packed {
    l1d_tag_t tag;
    l1d_set_idx_t set_idx;
    logic[CACHE_LINE_OFFSET_WIDTH - 1:0] offset;
} l1d_addr_t;

typedef logic[$clog2(`L1I_WAYS) - 1:0] l1i_way_idx_t;
typedef logic[$clog2(`L1I_SETS) - 1:0] l1i_set_idx_t;
typedef logic[ICACHE_TAG_BITS - 1:0] l1i_tag_t;

typedef struct packed {
    l1i_tag_t tag;
    l1i_set_idx_t set_idx;
    logic[CACHE_LINE_OFFSET_WIDTH - 1:0] offset;
} l1i_addr_t;

typedef logic[$clog2(`L2_WAYS) - 1:0] l2_way_idx_t;
typedef logic[$clog2(`L2_SETS) - 1:0] l2_set_idx_t;
typedef logic[(31 - (CACHE_LINE_OFFSET_WIDTH + $clog2(`L2_SETS))):0] l2_tag_t;
typedef struct packed {
    l2_tag_t tag;
    l2_set_idx_t set_idx;
} l2_addr_t;

// Memory address expressed as multiple of cache line size
typedef logic[31 - CACHE_LINE_OFFSET_WIDTH:0] cache_line_index_t;

typedef enum logic {
    CT_ICACHE,
    CT_DCACHE
} cache_type_t;

typedef logic[$clog2(`THREADS_PER_CORE) - 1:0] l1_miss_entry_idx_t;

typedef enum logic[2:0] {
    L2REQ_LOAD,
    L2REQ_LOAD_SYNC,
    L2REQ_STORE,
    L2REQ_STORE_SYNC,
    L2REQ_FLUSH,
    L2REQ_IINVALIDATE,
    L2REQ_DINVALIDATE
} l2req_packet_type_t;

// L2 request
typedef struct packed {
    core_id_t core;
    l1_miss_entry_idx_t id;
    l2req_packet_type_t packet_type;
    cache_type_t cache_type;
    l2_addr_t address;
    logic[CACHE_LINE_BYTES - 1:0] store_mask;
    cache_line_data_t data;
} l2req_packet_t;

typedef enum logic[2:0] {
    L2RSP_LOAD_ACK,
    L2RSP_STORE_ACK,
    L2RSP_FLUSH_ACK,
    L2RSP_IINVALIDATE_ACK,
    L2RSP_DINVALIDATE_ACK
} l2rsp_packet_type_t;

// L2 response
typedef struct packed {
    logic status;
    core_id_t core;
    l1_miss_entry_idx_t id;
    l2rsp_packet_type_t packet_type;
    cache_type_t cache_type;
    l2_addr_t address;
    cache_line_data_t data;
} l2rsp_packet_t;

// I/O bus request
typedef struct packed {
    logic store;
    local_thread_idx_t thread_idx;
    scalar_t address;
    scalar_t value;
} ioreq_packet_t;

// I/O bus response
typedef struct packed {
    core_id_t core;
    local_thread_idx_t thread_idx;
    scalar_t read_value;
} iorsp_packet_t;

parameter AXI_ADDR_WIDTH = 32;

endpackage : defines

import defines::*;

// Non-cached I/O bus (peripheral register access) external interface
// write_en and read_en are mutually exclusive. When read_en is asserted, the
// data will appear on read_data one cycle later.
interface io_bus_interface;
    logic write_en;
    logic read_en;
    defines::scalar_t address;
    defines::scalar_t write_data;
    defines::scalar_t read_data;

    modport master(output write_en, read_en, address, write_data, input read_data);
    modport slave(input write_en, read_en, address, write_data, output read_data);
endinterface

// AMBA AXI-4 bus interface
// See table A10-1 and A10-3 for default values of optional signals not included here.
interface axi4_interface;
    // Global signals (Table A2-1)
    logic m_aclk;
    logic m_aresetn;

    // Write address channel (Table A2-2)
    logic [AXI_ADDR_WIDTH - 1:0] m_awaddr;
    logic [7:0] m_awlen;
    logic [2:0] m_awprot;
    logic m_awvalid;
    logic s_awready;

    // Write data channel (Table A2-3)
    logic [`AXI_DATA_WIDTH - 1:0] m_wdata;
    logic m_wlast;
    logic m_wvalid;
    logic s_wready;

    // Write response channel (Table A2-4)
    logic s_bvalid;
    logic m_bready;

    // Read address channel (Table A2-5)
    logic [AXI_ADDR_WIDTH - 1:0] m_araddr;
    logic [7:0] m_arlen;
    logic [2:0] m_arprot;
    logic m_arvalid;
    logic s_arready;

    // Read data channel (Table A2-6)
    logic [`AXI_DATA_WIDTH - 1:0] s_rdata;
    logic s_rvalid;
    logic m_rready;

    modport master(input s_awready, s_wready, s_bvalid, s_arready, s_rvalid, s_rdata,
        output m_awaddr, m_awlen, m_awvalid, m_wdata, m_wlast, m_wvalid, m_bready, m_araddr,
        m_arlen, m_arvalid, m_rready, m_aclk, m_aresetn, m_arprot, m_awprot);
    modport slave(input m_awaddr, m_awlen, m_awvalid, m_wdata, m_wlast, m_wvalid, m_bready,
        m_araddr, m_arlen, m_arvalid, m_rready, m_aclk, m_aresetn, m_arprot, m_awprot,
        output s_awready, s_wready, s_bvalid, s_arready, s_rvalid, s_rdata);
endinterface

interface jtag_interface;
    logic tck;
    logic trst_n;
    logic tdi;
    logic tdo;
    logic tms;

    modport host(input tdi, output tck, trst_n, tdo, tms);
    modport target(input tck, trst_n, tdi, tms, output tdo);
endinterface

`endif


//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Asynchronous FIFO, with two clock domains
// reset is asynchronous and is synchronized to each clock domain
// internally.
// NUM_ENTRIES must be a power of two and >= 2
//
//dh: blackboxes
(* blackbox *)
module SCFIFO #(parameter almost_empty_value=10,
                almost_full_value=100,
                lpm_numwords=200,
                lpm_width=200,
                lpm_showahead="ON")
   ( input wire aclr,
     output logic                    almost_empty,
     output logic                    almost_full,
     input wire                      clock,
     input wire [lpm_numwords-1:0]   data,
     output logic                    empty,
     output logic                    full,
     output logic [lpm_numwords-1:0] q,
     input wire                      rdreq,
     input wire                      sclr,
     input wire                      wrreq);
endmodule // SCFIFO

(* blackbox *)
module ALTSYNCRAM (
   // Port A declarations
   output [35:0] q_a,
   input [35:0]  data_a,
   input [7:0]   address_a,
   input         wren_a,
   input         rden_a,
   // Port B declarations
   output [35:0] q_b,
   input [35:0]  data_b,
   input [7:0]   address_b,
   input         wren_b,
   input         rden_b,
   // Control signals
   input         clock0, clock1,
   input         clocken0, clocken1, clocken2, clocken3,
   input         aclr0, aclr1,
   input         addressstall_a,
   input         addressstall_b);
   parameter OPERATION_MODE                = "NONE";
   parameter WIDTH_A =10;
   parameter WIDTHAD_A =10;
   parameter WIDTH_B=10;
   parameter WIDTHAD_B=10;
   parameter READ_DURING_WRITE_MIXED_PORTS ="DONT_CARE";

endmodule // altsyncram

module async_fifo
    #(parameter WIDTH = 32,
    parameter NUM_ENTRIES = 8)

    (input                  reset,

    // Read.
    input                   read_clk,
    input                   read_en,
    output [WIDTH - 1:0]    read_data,
    output logic            empty,

    // Write
    input                   write_clk,
    input                   write_en,
    output logic            full,
    input [WIDTH - 1:0]     write_data);

    localparam ADDR_WIDTH = $clog2(NUM_ENTRIES);

    logic[ADDR_WIDTH - 1:0] write_ptr_sync;
    logic[ADDR_WIDTH - 1:0] read_ptr;
    logic[ADDR_WIDTH - 1:0] read_ptr_gray;
    logic[ADDR_WIDTH - 1:0] read_ptr_nxt;
    logic[ADDR_WIDTH - 1:0] read_ptr_gray_nxt;
    logic reset_rsync;
    logic[ADDR_WIDTH - 1:0] read_ptr_sync;
    logic[ADDR_WIDTH - 1:0] write_ptr;
    logic[ADDR_WIDTH - 1:0] write_ptr_gray;
    logic[ADDR_WIDTH - 1:0] write_ptr_nxt;
    logic[ADDR_WIDTH - 1:0] write_ptr_gray_nxt;
    logic reset_wsync;
    logic [WIDTH - 1:0] fifo_data[0:NUM_ENTRIES - 1];

    assign read_ptr_nxt = read_ptr + 1;
    assign read_ptr_gray_nxt = read_ptr_nxt ^ (read_ptr_nxt >> 1);
    assign write_ptr_nxt = write_ptr + 1;
    assign write_ptr_gray_nxt = write_ptr_nxt ^ (write_ptr_nxt >> 1);

    //
    // Read clock domain
    //
    synchronizer #(.WIDTH(ADDR_WIDTH)) write_ptr_synchronizer(
        .clk(read_clk),
        .reset(reset_rsync),
        .data_o(write_ptr_sync),
        .data_i(write_ptr_gray));

    assign empty = write_ptr_sync == read_ptr_gray;

    synchronizer #(.RESET_STATE(1)) read_reset_synchronizer(
        .clk(read_clk),
        .reset(reset),
        .data_i(0),
        .data_o(reset_rsync));

    always_ff @(posedge read_clk, posedge reset_rsync)
    begin
        if (reset_rsync)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            read_ptr <= '0;
            read_ptr_gray <= '0;
            // End of automatics
        end
        else if (read_en && !empty)
        begin
            read_ptr <= read_ptr_nxt;
            read_ptr_gray <= read_ptr_gray_nxt;
        end
    end

    assign read_data = fifo_data[read_ptr];

    //
    // Write clock domain
    //
    synchronizer #(.WIDTH(ADDR_WIDTH)) read_ptr_synchronizer(
        .clk(write_clk),
        .reset(reset_wsync),
        .data_o(read_ptr_sync),
        .data_i(read_ptr_gray));

    assign full = write_ptr_gray_nxt == read_ptr_sync;

    synchronizer #(.RESET_STATE(1)) write_reset_synchronizer(
        .clk(write_clk),
        .reset(reset),
        .data_i(0),
        .data_o(reset_wsync));

    always_ff @(posedge write_clk, posedge reset_wsync)
    begin
        if (reset_wsync)
        begin
            `ifdef NEVER
            fifo_data <= 0;    // Suppress autoreset
            `endif

            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            write_ptr <= '0;
            write_ptr_gray <= '0;
            // End of automatics
        end
        else if (write_en && !full)
        begin
            fifo_data[write_ptr] <= write_data;
            write_ptr <= write_ptr_nxt;
            write_ptr_gray <= write_ptr_gray_nxt;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Asynchronous AXI->AXI bridge. This safely transfers AXI requests and
// responses between two clock domains.
//

module axi_async_bridge
    #(parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32)

    (input                      reset,

    // Slave Interface (from a master)
    input                       clk_s,
    axi4_interface.slave        axi_bus_s,

    // Master Interface (to a slave)
    input                       clk_m,
    axi4_interface.master       axi_bus_m);

    localparam CONTROL_FIFO_LENGTH = 2;    // requirement of async_fifo
    localparam DATA_FIFO_LENGTH = 8;

    //
    // Write address from master->slave
    //
    logic write_address_full;
    logic write_address_empty;

    async_fifo #(ADDR_WIDTH + 8, CONTROL_FIFO_LENGTH) write_address_fifo(
        .reset(reset),
        .write_clock(clk_s),
        .write_enable(!write_address_full && axi_bus_s.m_awvalid),
        .write_data({axi_bus_s.m_awaddr, axi_bus_s.m_awlen}),
        .full(write_address_full),
        .read_clock(clk_m),
        .read_enable(!write_address_empty && axi_bus_m.s_awready),
        .read_data({axi_bus_m.m_awaddr, axi_bus_m.m_awlen}),
        .empty(write_address_empty));

    assign axi_bus_s.s_awready = !write_address_full;
    assign axi_bus_m.m_awvalid = !write_address_empty;

    //
    // Write data from master->slave
    //
    logic write_data_full;
    logic write_data_empty;

    async_fifo #(DATA_WIDTH + 1, DATA_FIFO_LENGTH) write_data_fifo(
        .reset(reset),
        .write_clock(clk_s),
        .write_enable(!write_data_full && axi_bus_s.m_wvalid),
        .write_data({axi_bus_s.m_wdata, axi_bus_s.m_wlast}),
        .full(write_data_full),
        .read_clock(clk_m),
        .read_enable(!write_data_empty && axi_bus_m.s_wready),
        .read_data({axi_bus_m.m_wdata, axi_bus_m.m_wlast}),
        .empty(write_data_empty));

    assign axi_bus_s.s_wready = !write_data_full;
    assign axi_bus_m.m_wvalid = !write_data_empty;

    //
    // Write response from slave->master
    //
    logic write_response_full;
    logic write_response_empty;

    async_fifo #(1, CONTROL_FIFO_LENGTH) write_response_fifo(
        .reset(reset),
        .write_clock(clk_m),
        .write_enable(!write_response_full && axi_bus_m.s_bvalid),
        .write_data(1'b0),    // XXX pipe through actual error code
        .full(write_response_full),
        .read_clock(clk_s),
        .read_enable(!write_response_empty && axi_bus_s.m_bready),
        .read_data(/* unconnected */),
        .empty(write_response_empty));

    assign axi_bus_s.s_bvalid = !write_response_empty;
    assign axi_bus_m.m_bready = !write_response_full;

    //
    // Read address from master->slave
    //
    logic read_address_full;
    logic read_address_empty;

    async_fifo #(ADDR_WIDTH + 8, CONTROL_FIFO_LENGTH) read_address_fifo(
        .reset(reset),
        .write_clock(clk_s),
        .write_enable(!read_address_full && axi_bus_s.m_arvalid),
        .write_data({axi_bus_s.m_araddr, axi_bus_s.m_arlen}),
        .full(read_address_full),
        .read_clock(clk_m),
        .read_enable(!read_address_empty && axi_bus_m.s_arready),
        .read_data({axi_bus_m.m_araddr, axi_bus_m.m_arlen}),
        .empty(read_address_empty));

    assign axi_bus_s.s_arready = !read_address_full;
    assign axi_bus_m.m_arvalid = !read_address_empty;

    //
    // Read data from slave->master
    //
    logic read_data_full;
    logic read_data_empty;

    async_fifo #(DATA_WIDTH, DATA_FIFO_LENGTH) read_data_fifo(
        .reset(reset),
        .write_clock(clk_m),
        .write_enable(!read_data_full && axi_bus_m.s_rvalid),
        .write_data(axi_bus_m.s_rdata),
        .full(read_data_full),
        .read_clock(clk_s),
        .read_enable(!read_data_empty && axi_bus_s.m_rready),
        .read_data(axi_bus_s.s_rdata),
        .empty(read_data_empty));

    assign axi_bus_m.m_rready = !read_data_full;
    assign axi_bus_s.s_rvalid = !read_data_empty;
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// This routes AXI transactions between two masters and two slaves
// mapped into different regions of a common address space.
// XXX this should be reworked to support an arbitrary number of
// controlling masters.
//

module axi_interconnect
    #(parameter M1_BASE_ADDRESS = 32'hffffeee0)

    (input                      clk,
    input                       reset,

    // These interface control externally connected slaves
    // Slave Interface 0 (address 0x00000000 - M1_BASE_ADDRESS)
    // Slave Interface 1 (address M1_BASE_ADDRESS - 0xfffeffff)
    axi4_interface.master       axi_bus_s[1:0],

    // These interfaces are controlled by externally connected masters.
    // Interface 1 is read only.
    axi4_interface.slave        axi_bus_m[1:0]);

    typedef enum {
        STATE_ARBITRATE,
        STATE_ISSUE_ADDRESS,
        STATE_ACTIVE_BURST
    } burst_state_t;

    burst_state_t write_state;
    logic[31:0] write_burst_address;
    logic[7:0] write_burst_length;    // Like axi_awlen, this is number of transfers minus 1
    logic write_slave_select;
    logic read_selected_master;
    logic read_selected_slave;
    logic[7:0] read_burst_length;    // Like axi_arlen, this is number of transfers minus one
    logic[31:0] read_burst_address;
    burst_state_t read_state;
    logic axi_arready_m;
    logic axi_rready_m;
    logic axi_rvalid_m;

    //
    // Write handling. Only slave interface 0 does writes.
    // XXX I don't explicitly handle the response in the state machine, but it
    // works because everything is in the correct state when the transaction is finished.
    // This could introduce a subtle bug if the behavior of the core changed.
    //

    // Since only slave interface 0 supports writes, just hard wire these.
    assign axi_bus_s[0].m_awaddr = write_burst_address;
    assign axi_bus_s[0].m_awlen = write_burst_length;
    assign axi_bus_s[0].m_wdata = axi_bus_m[0].m_wdata;
    assign axi_bus_s[0].m_wlast = axi_bus_m[0].m_wlast;
    assign axi_bus_s[0].m_bready = axi_bus_m[0].m_bready;
    assign axi_bus_s[1].m_awaddr = write_burst_address - M1_BASE_ADDRESS;
    assign axi_bus_s[1].m_awlen = write_burst_length;
    assign axi_bus_s[1].m_wdata = axi_bus_m[0].m_wdata;
    assign axi_bus_s[1].m_wlast = axi_bus_m[0].m_wlast;
    assign axi_bus_s[1].m_bready = axi_bus_m[0].m_bready;

    assign axi_bus_s[0].m_awvalid = write_slave_select == 0 && write_state == STATE_ISSUE_ADDRESS;
    assign axi_bus_s[1].m_awvalid = write_slave_select == 1 && write_state == STATE_ISSUE_ADDRESS;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            write_state <= STATE_ARBITRATE;
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            write_burst_address <= '0;
            write_burst_length <= '0;
            write_slave_select <= '0;
            // End of automatics
        end
        else if (write_state == STATE_ACTIVE_BURST)
        begin
            // Burst is active.  Check to see when it is finished.
            if (axi_bus_m[0].s_wready && axi_bus_m[0].m_wvalid)
            begin
                write_burst_length <= write_burst_length - 8'd1;
                if (write_burst_length == 0)
                    write_state <= STATE_ARBITRATE;
            end
        end
        else if (write_state == STATE_ISSUE_ADDRESS)
        begin
            // Wait for the slave to accept the address and length
            if (axi_bus_m[0].s_awready)
                write_state <= STATE_ACTIVE_BURST;
        end
        else if (axi_bus_m[0].m_awvalid)
        begin
            // Start a new write transaction
            write_slave_select <=  axi_bus_m[0].m_awaddr >= M1_BASE_ADDRESS;
            write_burst_address <= axi_bus_m[0].m_awaddr;
            write_burst_length <= axi_bus_m[0].m_awlen;
            write_state <= STATE_ISSUE_ADDRESS;
        end
    end

    always_comb
    begin
        if (write_slave_select == 0)
        begin
            // Master Interface 0 is selected
            axi_bus_s[0].m_wvalid = axi_bus_m[0].m_wvalid && write_state == STATE_ACTIVE_BURST;
            axi_bus_s[1].m_wvalid = 0;
            axi_bus_m[0].s_awready = axi_bus_s[0].s_awready && write_state == STATE_ISSUE_ADDRESS;
            axi_bus_m[0].s_wready = axi_bus_s[0].s_wready && write_state == STATE_ACTIVE_BURST;
            axi_bus_m[0].s_bvalid = axi_bus_s[0].s_bvalid;
        end
        else
        begin
            // Master interface 1 is selected
            axi_bus_s[0].m_wvalid = 0;
            axi_bus_s[1].m_wvalid = axi_bus_m[0].m_wvalid && write_state == STATE_ACTIVE_BURST;
            axi_bus_m[0].s_awready = axi_bus_s[1].s_awready && write_state == STATE_ISSUE_ADDRESS;
            axi_bus_m[0].s_wready = axi_bus_s[1].s_wready && write_state == STATE_ACTIVE_BURST;
            axi_bus_m[0].s_bvalid = axi_bus_s[1].s_bvalid;
        end
    end

    //
    // Read handling.  Slave interface 1 has priority.
    //
    assign axi_arready_m = read_selected_slave ? axi_bus_s[1].s_arready : axi_bus_s[0].s_arready;
    assign axi_rready_m = read_selected_slave ? axi_bus_s[1].m_rready : axi_bus_s[0].m_rready;
    assign axi_rvalid_m = read_selected_slave ? axi_bus_s[1].s_rvalid : axi_bus_s[0].s_rvalid;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            read_state <= STATE_ARBITRATE;

            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            read_burst_address <= '0;
            read_burst_length <= '0;
            read_selected_master <= '0;
            read_selected_slave <= '0;
            // End of automatics
        end
        else if (read_state == STATE_ACTIVE_BURST)
        begin
            // Burst is active.  Check to see when it is finished.
            if (axi_rready_m && axi_rvalid_m)
            begin
                read_burst_length <= read_burst_length - 8'd1;
                if (read_burst_length == 0)
                    read_state <= STATE_ARBITRATE;
            end
        end
        else if (read_state == STATE_ISSUE_ADDRESS)
        begin
            // Wait for the slave to accept the address and length
            if (axi_arready_m)
                read_state <= STATE_ACTIVE_BURST;
        end
        else if (axi_bus_m[1].m_arvalid)
        begin
            // Start a read burst from slave 1
            read_state <= STATE_ISSUE_ADDRESS;
            read_burst_address <= axi_bus_m[1].m_araddr;
            read_burst_length <= axi_bus_m[1].m_arlen;
            read_selected_master <= 1'b1;
            read_selected_slave <= axi_bus_m[1].m_araddr >= M1_BASE_ADDRESS;
        end
        else if (axi_bus_m[0].m_arvalid)
        begin
            // Start a read burst from slave 0
            read_state <= STATE_ISSUE_ADDRESS;
            read_burst_address <= axi_bus_m[0].m_araddr;
            read_burst_length <= axi_bus_m[0].m_arlen;
            read_selected_master <= 1'b0;
            read_selected_slave <= axi_bus_m[0].m_araddr[31:28] != 0;
        end
    end

    always_comb
    begin
        if (read_state == STATE_ARBITRATE)
        begin
            axi_bus_m[0].s_rvalid = 0;
            axi_bus_m[1].s_rvalid = 0;
            axi_bus_s[0].m_rready = 0;
            axi_bus_s[1].m_rready = 0;
            axi_bus_m[0].s_arready = 0;
            axi_bus_m[1].s_arready = 0;
        end
        else if (read_selected_master == 0)
        begin
            axi_bus_m[0].s_rvalid = axi_rvalid_m;
            axi_bus_m[1].s_rvalid = 0;
            axi_bus_s[0].m_rready = axi_bus_m[0].m_rready && read_selected_slave == 0;
            axi_bus_s[1].m_rready = axi_bus_m[0].m_rready && read_selected_slave == 1;
            axi_bus_m[0].s_arready = axi_arready_m && read_state == STATE_ISSUE_ADDRESS;
            axi_bus_m[1].s_arready = 0;
        end
        else
        begin
            axi_bus_m[0].s_rvalid = 0;
            axi_bus_m[1].s_rvalid = axi_rvalid_m;
            axi_bus_s[0].m_rready = axi_bus_m[1].m_rready && read_selected_slave == 0;
            axi_bus_s[1].m_rready = axi_bus_m[1].m_rready && read_selected_slave == 1;
            axi_bus_m[0].s_arready = 0;
            axi_bus_m[1].s_arready = axi_arready_m && read_state == STATE_ISSUE_ADDRESS;
        end
    end

    assign axi_bus_s[0].m_arvalid = read_state == STATE_ISSUE_ADDRESS && read_selected_slave == 0;
    assign axi_bus_s[1].m_arvalid = read_state == STATE_ISSUE_ADDRESS && read_selected_slave == 1;
    assign axi_bus_s[0].m_araddr = read_burst_address;
    assign axi_bus_s[1].m_araddr = read_burst_address - M1_BASE_ADDRESS;
    assign axi_bus_m[0].s_rdata = read_selected_slave ? axi_bus_s[1].s_rdata : axi_bus_s[0].s_rdata;
    assign axi_bus_m[1].s_rdata = axi_bus_m[0].s_rdata;
    assign axi_bus_m[1].s_awready = '0;
    assign axi_bus_m[1].s_wready = '0;
    assign axi_bus_m[1].s_bvalid = '0;

    // We end up reusing read_burst_length to track how many beats are left
    // later.  At this point, the value of ARLEN should be ignored by slave
    // we are driving, so it won't break anything.
    assign axi_bus_s[0].m_arlen = read_burst_length;
    assign axi_bus_s[1].m_arlen = read_burst_length;
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Read only memory that uses AMBA AXI bus interface
//

module axi_rom
    #(parameter FILENAME = "")

    (input                      clk,
    input                       reset,

    // AXI interface
    axi4_interface.slave        axi_bus);

    localparam MAX_SIZE = 'h2000;

    logic[29:0] burst_address;
    logic[7:0] burst_count;
    logic burst_active;

    logic[31:0] rom_data[MAX_SIZE];
`ifdef BOOT_FILE
    initial
    begin
        // This is used during *synthesis* to load the contents of ROM memory.
        $readmemh(FILENAME, rom_data);
    end
`endif
    assign axi_bus.s_wready = 1;
    assign axi_bus.s_bvalid = 1;
    assign axi_bus.s_awready = 1;
    assign axi_bus.s_arready = !burst_active;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            burst_active <= 0;
            axi_bus.s_rvalid <= 0;
        end
        else if (burst_active)
        begin
            if (burst_count == 0 && axi_bus.m_rready)
            begin
                // End of burst
                axi_bus.s_rvalid <= 0;
                burst_active <= 0;
            end
            else
            begin
                axi_bus.s_rvalid <= 1;
                axi_bus.s_rdata <= rom_data[burst_address[$clog2(MAX_SIZE) - 1:0]];
                if (axi_bus.m_rready)
                begin
                    burst_address <= burst_address + 30'd1;
                    burst_count <= burst_count - 8'd1;
                end
            end
        end
        else if (axi_bus.m_arvalid)
        begin
            // Start a new burst
            burst_active <= 1;
            burst_address <= axi_bus.m_araddr[31:2];
            burst_count <= axi_bus.m_arlen + 8'd1;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// SRAM with an AXI interface and external loader interface
//
module axi_sram
    #(parameter MEM_SIZE = 'h40000) // Number of 32-bit words

    (input                      clk,
    input                       reset,

    // AXI interface
    axi4_interface.slave        axi_bus,

    // External loader interface. It is valid to access these when the
    // part is in reset; the reset signal only applies to the AXI state machine.
    input                       loader_we,
    input[31:0]                 loader_addr,
    input[31:0]                 loader_data);

    typedef enum {
        STATE_IDLE,
        STATE_READ_BURST,
        STATE_WRITE_BURST,
        STATE_WRITE_ACK
    } axi_state_t;

    logic[31:0] burst_address;
    logic[31:0] burst_address_nxt;
    logic[7:0] burst_count;
    logic[7:0] burst_count_nxt;
    axi_state_t state;
    axi_state_t state_nxt;
    logic do_read;
    logic do_write;
    logic[31:0] wr_addr;
    logic[31:0] wr_data;

    localparam SRAM_ADDR_WIDTH = $clog2(MEM_SIZE);

    always_comb
    begin
        if (loader_we)
        begin
            wr_addr = 32'(loader_addr[31:2]);
            wr_data = loader_data;
        end
        else // do write
        begin
            wr_addr = burst_address;
            wr_data = axi_bus.m_wdata;
        end
    end

    sram_1r1w #(.SIZE(MEM_SIZE), .DATA_WIDTH(32)) memory(
        .clk(clk),
        .read_en(do_read),
        .read_addr(burst_address_nxt[SRAM_ADDR_WIDTH - 1:0]),
        .read_data(axi_bus.s_rdata),
        .write_en(loader_we || do_write),
        .write_addr(wr_addr[SRAM_ADDR_WIDTH - 1:0]),
        .write_data(wr_data));

    assign axi_bus.s_awready = axi_bus.s_arready;

    // Drive external bus signals
    always_comb
    begin
        axi_bus.s_rvalid = 0;
        axi_bus.s_wready = 0;
        axi_bus.s_bvalid = 0;
        axi_bus.s_arready = 0;
        case (state)
            STATE_IDLE:        axi_bus.s_arready = 1;    // and s_awready
            STATE_READ_BURST:  axi_bus.s_rvalid = 1;
            STATE_WRITE_BURST: axi_bus.s_wready = 1;
            STATE_WRITE_ACK:   axi_bus.s_bvalid = 1;
        endcase
    end

    // Next state logic
    always_comb
    begin
        do_read = 0;
        do_write = 0;
        burst_address_nxt = burst_address;
        burst_count_nxt = burst_count;
        state_nxt = state;

        unique case (state)
            STATE_IDLE:
            begin
                // I've cheated here.  It's legal per the spec for s_arready/s_awready to go low
                // but not if m_arvalid/m_awvalid are already asserted (respectively), because
                // the client would assume the transfer completed (AMBA AXI and ACE protocol
                // spec rev E A3.2.1: "If READY is asserted, it is permitted to deassert READY
                // before VALID is asserted.")  I know that the client never asserts both
                // simultaneously, so I don't bother latching addresses separately.
                if (axi_bus.m_awvalid)
                begin
                    burst_address_nxt = 32'(axi_bus.m_awaddr[31:2]);
                    burst_count_nxt = axi_bus.m_awlen;
                    state_nxt = STATE_WRITE_BURST;
                end
                else if (axi_bus.m_arvalid)
                begin
                    do_read = 1;
                    burst_address_nxt = 32'(axi_bus.m_araddr[31:2]);
                    burst_count_nxt = axi_bus.m_arlen;
                    state_nxt = STATE_READ_BURST;
                end
            end

            STATE_READ_BURST:
            begin
                if (axi_bus.m_rready)
                begin
                    if (burst_count == 0)
                        state_nxt = STATE_IDLE;
                    else
                    begin
                        burst_address_nxt = burst_address + 1;
                        burst_count_nxt = burst_count - 1;
                        do_read = 1;
                    end
                end
            end

            STATE_WRITE_BURST:
            begin
                if (axi_bus.m_wvalid)
                begin
                    do_write = 1;
                    if (burst_count == 0)
                        state_nxt = STATE_WRITE_ACK;
                    else
                    begin
                        burst_address_nxt = burst_address + 1;
                        burst_count_nxt = burst_count - 1;
                    end
                end
            end

            STATE_WRITE_ACK:
            begin
                if (axi_bus.m_bready)
                    state_nxt = STATE_IDLE;
            end

            default:
                state_nxt = STATE_IDLE;
        endcase
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            state <= STATE_IDLE;
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            burst_address <= '0;
            burst_count <= '0;
            // End of automatics
        end
        else
        begin
`ifdef SIMULATION
            if (burst_address > MEM_SIZE)
            begin
                // Note that this isn't necessarily indicative of a hardware bug:
                // it could just be a bad memory address produced by software.
                $display("L2 cache accessed invalid address %x", burst_address);
                $finish;
            end
`endif

            burst_address <= burst_address_nxt;
            burst_count <= burst_count_nxt;
            state <= state_nxt;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Maintains a least recently used list for each cache set. Used to determine
// which cache way to load new cache lines into.
//
// There are two interfaces that update the LRU:
//
// Fill:
// The cache asserts fill_en and fill_set when it needs to load a cache line.
// One cycle later, this module sets fill_way to the least recently used way
// (which the cache will replace) and moves that way to the most recently used
// position.
//
// Access:
// During the first cycle of a cache loads, the client asserts access_en and
// access_set. If there was a cache hit, it asserts update_en and update_way
// one cycle later to update the accessed way to the MRU position. This
// must not assert update_en without having asserted access_en in the previous
// cycle, as the former fetches the old LRU value.
//
// If the client asserts fill_en and access_en simultaneously, which is legal,
// fill will take precedence. This is important:
// - To avoid evicting recently loaded lines when there are many fills back to
//   back, which would be inefficient.
// - To avoids livelock where two threads evict each other's lines back and
//   forth forever.
//

module cache_lru
    #(parameter NUM_SETS = 1,
    parameter NUM_WAYS = 4,    // Must be 1, 2, 4, or 8
    parameter SET_INDEX_WIDTH = $clog2(NUM_SETS),
    parameter WAY_INDEX_WIDTH = $clog2(NUM_WAYS))
    (input                                clk,
    input                                 reset,

    // Fill interface. Used to request LRU to replace when filling.
    input                                 fill_en,
    input [SET_INDEX_WIDTH - 1:0]         fill_set,
    output logic[WAY_INDEX_WIDTH - 1:0]   fill_way,

    // Access interface. Used to move a way to the MRU position when
    // it has been accessed.
    input                                 access_en,
    input [SET_INDEX_WIDTH - 1:0]         access_set,
    input                                 update_en,
    input [WAY_INDEX_WIDTH - 1:0]         update_way);

    localparam LRU_FLAG_BITS =
        NUM_WAYS == 1 ? 1 :
        NUM_WAYS == 2 ? 1 :
        NUM_WAYS == 4 ? 3 :
        7;    // NUM_WAYS = 8

    logic[LRU_FLAG_BITS - 1:0] lru_flags;
    logic update_lru_en;
    logic [SET_INDEX_WIDTH - 1:0] update_set;
    logic[LRU_FLAG_BITS - 1:0] update_flags;
    logic [SET_INDEX_WIDTH - 1:0] read_set;
    logic read_en;
    logic was_fill;
    logic[WAY_INDEX_WIDTH - 1:0] new_mru;
`ifdef SIMULATION
    logic was_access;
`endif

    assign read_en = access_en || fill_en;
    assign read_set = fill_en ? fill_set : access_set;
    assign new_mru = was_fill ? fill_way : update_way;
    assign update_lru_en = was_fill || update_en;

    initial
    begin
        // Must be 1, 2, 4, or 8
        assert(NUM_WAYS <= 8 && (NUM_WAYS & (NUM_WAYS - 1)) == 0);
    end

    // This uses a pseudo-LRU algorithm
    // Assuming four sets, the current state of each set is represented by
    // three bits. Imagine a tree:
    //
    //        b
    //      /   \
    //     a     c
    //    / \   / \
    //   0   1 2   3
    //
    // The leaves 0-3 represent ways, and the letters a, b, and c represent the 3 bits
    // which indicate a path to the *least recently used* way. A 0 stored in a interior
    // node indicates the  left node and a 1 the right. Each time an element is moved
    // to the MRU, the bits along its path are set to the opposite direction. This means
    // it will take at least two cycles for a node in the MRU to move to the LRU and
    // be evicted. A strict LRU would take three cycles for the node to move to the
    // LRU. So, this is close enough to LRU to work well, but much simpler to implement.
    //
    sram_1r1w #(
        .DATA_WIDTH(LRU_FLAG_BITS),
        .SIZE(NUM_SETS),
        .READ_DURING_WRITE("NEW_DATA")
    ) lru_data(
        // Fetch existing flags
        .read_en(read_en),
        .read_addr(read_set),
        .read_data(lru_flags),

        // Update LRU (from next stage)
        .write_en(update_lru_en),
        .write_addr(update_set),
        .write_data(update_flags),
        .*);

    // XXX I bet there's a way to programmatically create update_flags
    // and fill_way with a generate loop instead of hard-coding like
    // I've done here.
    generate
        case (NUM_WAYS)
            1:
            begin
                assign fill_way = 0;
                assign update_flags = 0;
            end

            2:
            begin
                assign fill_way = !lru_flags[0];
                assign update_flags[0] = !new_mru;
            end

            4:
            begin
                always_comb
                begin
                    casez (lru_flags)
                        3'b00?: fill_way = 0;
                        3'b10?: fill_way = 1;
                        3'b?10: fill_way = 2;
                        3'b?11: fill_way = 3;
                        default: fill_way = '0;
                    endcase
                end

                always_comb
                begin
                    case (new_mru)
                        2'd0: update_flags = {2'b11, lru_flags[0]};
                        2'd1: update_flags = {2'b01, lru_flags[0]};
                        2'd2: update_flags = {lru_flags[2], 2'b01};
                        2'd3: update_flags = {lru_flags[2], 2'b00};
                        default: update_flags = '0;
                    endcase
                end
            end

            8:
            begin
                always_comb
                begin
                    casez (lru_flags)
                        7'b00?0???: fill_way = 0;
                        7'b10?0???: fill_way = 1;
                        7'b?100???: fill_way = 2;
                        7'b?110???: fill_way = 3;
                        7'b???100?: fill_way = 4;
                        7'b???110?: fill_way = 5;
                        7'b???1?10: fill_way = 6;
                        7'b???1?11: fill_way = 7;
                        default: fill_way = '0;
                    endcase
                end

                always_comb
                begin
                    case (new_mru)
                        3'd0: update_flags = {2'b11, lru_flags[5], 1'b1, lru_flags[2:0]};
                        3'd1: update_flags = {2'b01, lru_flags[5], 1'b1, lru_flags[2:0]};
                        3'd2: update_flags = {lru_flags[6], 3'b011, lru_flags[2:0]};
                        3'd3: update_flags = {lru_flags[6], 3'b001, lru_flags[2:0]};
                        3'd4: update_flags = {lru_flags[6:4], 3'b011, lru_flags[0]};
                        3'd5: update_flags = {lru_flags[6:4], 3'b010, lru_flags[0]};
                        3'd6: update_flags = {lru_flags[6:4], 2'b00, lru_flags[1], 1'b1};
                        3'd7: update_flags = {lru_flags[6:4], 2'b00, lru_flags[1], 1'b0};
                        default: update_flags = '0;
                    endcase
                end
            end

            default:
            begin
                initial
                begin
                    $display("%m invalid number of ways");
                    $finish;
                end
            end
        endcase
    endgenerate

    always_ff @(posedge clk)
    begin
        update_set <= read_set;
        was_fill <= fill_en;
    end

`ifdef SIMULATION
    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            was_access <= 0;
        else
        begin
            // Can't update when the last cycle didn't perform an access.
            assert(!(update_en && !was_access));
            was_access <= access_en;    // Debug only
        end
    end
`endif
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Content addressable memory.
// Lookup is async: This asserts lookup_idx and lookup_hit the same cycle
// lookup_key is asserted. It registers the update signals on the edge of clk.
// If an update is performed to the same address as a lookup in the same clock
// cycle, it doesn't flag a match.
//

module cam
    #(parameter NUM_ENTRIES = 2,
    parameter KEY_WIDTH = 32,
    parameter INDEX_WIDTH = $clog2(NUM_ENTRIES))

    (input                           clk,
    input                            reset,

    // Lookup interface
    input [KEY_WIDTH - 1:0]          lookup_key,
    output logic[INDEX_WIDTH - 1:0]  lookup_idx,
    output logic                     lookup_hit,

    // Update interface
    input                            update_en,
    input [KEY_WIDTH - 1:0]          update_key,
    input [INDEX_WIDTH - 1:0]        update_idx,
    input                            update_valid);

    logic[KEY_WIDTH - 1:0] lookup_table[NUM_ENTRIES];
    logic[NUM_ENTRIES - 1:0] entry_valid;
    logic[NUM_ENTRIES - 1:0] hit_oh;

    genvar test_index;
    generate
        for (test_index = 0; test_index < NUM_ENTRIES; test_index++)
        begin : lookup_gen
            assign hit_oh[test_index] = entry_valid[test_index]
                && lookup_table[test_index] == lookup_key;
        end
    endgenerate

    assign lookup_hit = |hit_oh;
    oh_to_idx #(.NUM_SIGNALS(NUM_ENTRIES)) oh_to_idx_hit(
        .one_hot(hit_oh),
        .index(lookup_idx));

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            for (int i = 0; i < NUM_ENTRIES; i++)
                entry_valid[i] <= 1'b0;
        end
        else
        begin
            assert($onehot0(hit_oh));
            if (update_en)
                entry_valid[update_idx] <= update_valid;
        end
    end

    always_ff @(posedge clk)
    begin
        if (update_en)
            lookup_table[update_idx] <= update_key;
    end

`ifdef SIMULATION
    // Check for duplicate entries
    always_ff @(posedge clk, posedge reset)
    begin
        if (!reset && update_en && update_valid)
        begin : test
            for (int i = 0; i < NUM_ENTRIES; i++)
            begin
                if (entry_valid[i] && lookup_table[i] == update_key
                    && INDEX_WIDTH'(i) != update_idx)
                begin
                    $display("%m: added duplicate entry to CAM");
                    $display("  original slot %d new slot %d", i, update_idx);
                    $finish;
                end
            end
        end
    end
`endif

endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//


////`include "defines.svh"

import defines::*;

//
// Storage for control registers.
// Also contains interrupt handling logic.
//

module control_registers
    #(parameter CORE_ID = 0,
    parameter NUM_INTERRUPTS = 16,
    parameter NUM_PERF_EVENTS = 8,
    parameter EVENT_IDX_WIDTH = $clog2(NUM_PERF_EVENTS))
    (input                                  clk,
    input                                   reset,

    input [NUM_INTERRUPTS - 1:0]            interrupt_req,

    // To multiple stages
    output scalar_t                         cr_eret_address[`THREADS_PER_CORE],
    output logic                            cr_mmu_en[`THREADS_PER_CORE],
    output logic                            cr_supervisor_en[`THREADS_PER_CORE],
    output logic[ASID_WIDTH - 1:0]          cr_current_asid[`THREADS_PER_CORE],

    // To nyuzi
    output logic[TOTAL_THREADS - 1:0]       cr_suspend_thread,
    output logic[TOTAL_THREADS - 1:0]       cr_resume_thread,

    // To instruction_decode_stage
    output logic[`THREADS_PER_CORE - 1:0]   cr_interrupt_pending,
    output local_thread_bitmap_t            cr_interrupt_en,

    // From dcache_data_stage
    // dd_xxx signals are unregistered. dt_thread_idx represents thread going into
    // dcache_data_stage)
    input local_thread_idx_t                dt_thread_idx,
    input                                   dd_creg_write_en,
    input                                   dd_creg_read_en,
    input control_register_t                dd_creg_index,
    input scalar_t                          dd_creg_write_val,

    // From writeback_stage
    input                                   wb_trap,
    input                                   wb_eret,
    input trap_cause_t                      wb_trap_cause,
    input scalar_t                          wb_trap_pc,
    input scalar_t                          wb_trap_access_vaddr,
    input local_thread_idx_t                wb_rollback_thread_idx,
    input subcycle_t                        wb_trap_subcycle,
    input syscall_index_t                   wb_syscall_index,

    // To writeback_stage
    output scalar_t                         cr_creg_read_val,
    output subcycle_t                       cr_eret_subcycle[`THREADS_PER_CORE],
    output scalar_t                         cr_trap_handler,
    output scalar_t                         cr_tlb_miss_handler,

    // To/from performance_counters
    output logic[EVENT_IDX_WIDTH - 1:0]     cr_perf_event_select0,
    output logic[EVENT_IDX_WIDTH - 1:0]     cr_perf_event_select1,
    input[63:0]                             cr_perf_event_count0, //dh
    input[63:0]                             cr_perf_event_count1, //dh

    // To/from on_chip_debugger
    input scalar_t                          ocd_data_from_host,
    input                                   ocd_data_update,
    output scalar_t                         cr_data_to_host);

    // One is for current state. Maximum nested traps is TRAP_LEVELS - 1.
    localparam TRAP_LEVELS = 3;

    typedef struct packed {
        logic supervisor_en;
        logic mmu_en;
        logic interrupt_en;
    } flags_t;

    typedef struct packed {
        flags_t flags;
        scalar_t scratchpad0;
        scalar_t scratchpad1;

        // Information about last trap
        trap_cause_t trap_cause;
        scalar_t trap_pc;
        scalar_t trap_access_addr;
        subcycle_t trap_subcycle;
        syscall_index_t syscall_index;
    } trap_state_t;

    trap_state_t trap_state[`THREADS_PER_CORE][TRAP_LEVELS];
    scalar_t page_dir_base[`THREADS_PER_CORE];
    scalar_t cycle_count;
    logic[NUM_INTERRUPTS - 1:0] interrupt_mask[`THREADS_PER_CORE];
    logic[NUM_INTERRUPTS - 1:0] interrupt_pending[`THREADS_PER_CORE];
    logic[NUM_INTERRUPTS - 1:0] interrupt_edge_latched[`THREADS_PER_CORE];
    logic[NUM_INTERRUPTS - 1:0] int_trigger_type;
    logic[NUM_INTERRUPTS - 1:0] interrupt_req_prev;
    logic[NUM_INTERRUPTS - 1:0] interrupt_edge;
    scalar_t jtag_data;

    assign cr_data_to_host = jtag_data;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            for (int thread_idx = 0; thread_idx < `THREADS_PER_CORE; thread_idx++)
            begin
                trap_state[thread_idx][0] <= '0;
                trap_state[thread_idx][0].flags.supervisor_en <= 1'b1;
                cr_current_asid[thread_idx] <= '0;
                page_dir_base[thread_idx] <= '0;
                interrupt_mask[thread_idx] <= '0;
            end

            // AUTORESET gets confused by all of the structure accesses
            // below, so the resets are all manual here. Be sure to add all registers
            // accessed below here.
            jtag_data <= '0;
            cr_tlb_miss_handler <= '0;
            cr_trap_handler <= '0;
            cycle_count <= '0;
            int_trigger_type <= '0;
            cr_suspend_thread <= '0;
            cr_resume_thread <= '0;
            cr_perf_event_select0 <= '0;
            cr_perf_event_select1 <= '0;
        end
        else
        begin
            // Ensure a read and write don't occur in the same cycle
            assert(!(dd_creg_write_en && dd_creg_read_en));

            // A fault and eret are triggered from the same stage, so they
            // must not occur simultaneously (an eret can raise a fault if it
            // is not in supervisor mode, but wb_eret should not be asserted
            // in that case)
            assert(!(wb_trap && wb_eret));

            cycle_count <= cycle_count + 1;

            if (wb_trap)
            begin
                // Copy trap state
                for (int level = 0; level < TRAP_LEVELS - 1; level++)
                    trap_state[wb_rollback_thread_idx][level + 1] <= trap_state[wb_rollback_thread_idx][level];

                // Dispatch fault
                trap_state[wb_rollback_thread_idx][0].trap_cause <= wb_trap_cause;
                trap_state[wb_rollback_thread_idx][0].trap_pc <= wb_trap_pc;
                trap_state[wb_rollback_thread_idx][0].trap_access_addr <= wb_trap_access_vaddr;
                trap_state[wb_rollback_thread_idx][0].syscall_index <= wb_syscall_index;
                trap_state[wb_rollback_thread_idx][0].trap_subcycle <= wb_trap_subcycle;
                trap_state[wb_rollback_thread_idx][0].flags.interrupt_en <= 0;    // Disable interrupts for this thread
                trap_state[wb_rollback_thread_idx][0].flags.supervisor_en <= 1;
                if (wb_trap_cause.trap_type == TT_TLB_MISS)
                    trap_state[wb_rollback_thread_idx][0].flags.mmu_en <= 0;
            end

            if (wb_eret)
            begin
                // Restore nested interrupt state
                for (int level = 0; level < TRAP_LEVELS - 1; level++)
                    trap_state[wb_rollback_thread_idx][level] <= trap_state[wb_rollback_thread_idx][level + 1];
            end

            //
            // Write logic
            //
            cr_suspend_thread <= '0;
            cr_resume_thread <= '0;

            if (dd_creg_write_en)
            begin
                unique case (dd_creg_index)
                    CR_FLAGS:             trap_state[dt_thread_idx][0].flags <= flags_t'(dd_creg_write_val);
                    CR_SAVED_FLAGS:       trap_state[dt_thread_idx][1].flags <= flags_t'(dd_creg_write_val);
                    CR_TRAP_PC:           trap_state[dt_thread_idx][0].trap_pc <= dd_creg_write_val;
                    CR_TRAP_HANDLER:      cr_trap_handler <= dd_creg_write_val;
                    CR_TLB_MISS_HANDLER:  cr_tlb_miss_handler <= dd_creg_write_val;
                    CR_SCRATCHPAD0:       trap_state[dt_thread_idx][0].scratchpad0 <= dd_creg_write_val;
                    CR_SCRATCHPAD1:       trap_state[dt_thread_idx][0].scratchpad1 <= dd_creg_write_val;
                    CR_SUBCYCLE:          trap_state[dt_thread_idx][0].trap_subcycle <= subcycle_t'(dd_creg_write_val);
                    CR_CURRENT_ASID:      cr_current_asid[dt_thread_idx] <= dd_creg_write_val[ASID_WIDTH - 1:0];
                    CR_PAGE_DIR:          page_dir_base[dt_thread_idx] <= dd_creg_write_val;
                    CR_INTERRUPT_ENABLE:  interrupt_mask[dt_thread_idx] <= dd_creg_write_val[NUM_INTERRUPTS - 1:0];
                    CR_INTERRUPT_TRIGGER: int_trigger_type <= dd_creg_write_val[NUM_INTERRUPTS - 1:0];
                    CR_JTAG_DATA:         jtag_data <= dd_creg_write_val;
                    CR_SUSPEND_THREAD:    cr_suspend_thread <= dd_creg_write_val[TOTAL_THREADS - 1:0];
                    CR_RESUME_THREAD:     cr_resume_thread <= dd_creg_write_val[TOTAL_THREADS - 1:0];
                    CR_PERF_EVENT_SELECT0: cr_perf_event_select0 <= dd_creg_write_val[EVENT_IDX_WIDTH - 1:0];
                    CR_PERF_EVENT_SELECT1: cr_perf_event_select1 <= dd_creg_write_val[EVENT_IDX_WIDTH - 1:0];
                    default:
                        ;
                endcase
            end
            else if (ocd_data_update)
                jtag_data <= ocd_data_from_host;
        end
    end

    always @(posedge clk, posedge reset)
    begin
        if (reset)
            interrupt_req_prev <= '0;
        else
            interrupt_req_prev <= interrupt_req;
    end

    assign interrupt_edge = interrupt_req & ~interrupt_req_prev;

    genvar thread_idx;
    generate
        for (thread_idx = 0; thread_idx < `THREADS_PER_CORE; thread_idx++)
        begin : interrupt_gen
            logic[NUM_INTERRUPTS - 1:0] interrupt_ack;
            logic do_interrupt_ack;

            assign do_interrupt_ack = dt_thread_idx == thread_idx
                && dd_creg_write_en
                && dd_creg_index == CR_INTERRUPT_ACK;
            assign interrupt_ack = {NUM_INTERRUPTS{do_interrupt_ack}}
                & dd_creg_write_val[NUM_INTERRUPTS - 1:0];
            assign cr_interrupt_en[thread_idx] = trap_state[thread_idx][0].flags.interrupt_en;
            assign cr_supervisor_en[thread_idx] = trap_state[thread_idx][0].flags.supervisor_en;
            assign cr_mmu_en[thread_idx] = trap_state[thread_idx][0].flags.mmu_en;
            assign cr_eret_subcycle[thread_idx] = trap_state[thread_idx][0].trap_subcycle;
            assign cr_eret_address[thread_idx] = trap_state[thread_idx][0].trap_pc;

            // interrupt_edge_latched is set when a [positive] edge triggered
            // interrupt occurs.
            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                    interrupt_edge_latched[thread_idx] <= '0;
                else
                begin
                    interrupt_edge_latched[thread_idx] <=
                        (interrupt_edge_latched[thread_idx] & ~interrupt_ack)
                        | interrupt_edge;
                end
            end

            // If the trigger type is 1 (level triggered), interrupt pending is
            // determined by level. Otherwise check interrupt_latch, which stores
            // if an edge has been detected.
            assign interrupt_pending[thread_idx] = (int_trigger_type & interrupt_req)
                | (~int_trigger_type & interrupt_edge_latched[thread_idx]);

            // Output to pipeline indicates if any interrupts are pending for each
            // thread.
            assign cr_interrupt_pending[thread_idx] = |(interrupt_pending[thread_idx]
                & interrupt_mask[thread_idx]);
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        //
        // Read logic
        //
        if (dd_creg_read_en)
        begin
            unique case (dd_creg_index)
                CR_FLAGS:             cr_creg_read_val <= scalar_t'(trap_state[dt_thread_idx][0].flags);
                CR_SAVED_FLAGS:       cr_creg_read_val <= scalar_t'(trap_state[dt_thread_idx][1].flags);
                CR_THREAD_ID:         cr_creg_read_val <= scalar_t'({CORE_ID, dt_thread_idx});
                CR_TRAP_PC:           cr_creg_read_val <= trap_state[dt_thread_idx][0].trap_pc;
                CR_TRAP_CAUSE:        cr_creg_read_val <= scalar_t'(trap_state[dt_thread_idx][0].trap_cause);
                CR_TRAP_HANDLER:      cr_creg_read_val <= cr_trap_handler;
                CR_TRAP_ADDRESS:      cr_creg_read_val <= trap_state[dt_thread_idx][0].trap_access_addr;
                CR_TLB_MISS_HANDLER:  cr_creg_read_val <= cr_tlb_miss_handler;
                CR_CYCLE_COUNT:       cr_creg_read_val <= cycle_count;
                CR_SCRATCHPAD0:       cr_creg_read_val <= trap_state[dt_thread_idx][0].scratchpad0;
                CR_SCRATCHPAD1:       cr_creg_read_val <= trap_state[dt_thread_idx][0].scratchpad1;
                CR_SUBCYCLE:          cr_creg_read_val <= scalar_t'(trap_state[dt_thread_idx][0].trap_subcycle);
                CR_CURRENT_ASID:      cr_creg_read_val <= scalar_t'(cr_current_asid[dt_thread_idx]);
                CR_PAGE_DIR:          cr_creg_read_val <= page_dir_base[dt_thread_idx];
                CR_INTERRUPT_PENDING: cr_creg_read_val <= scalar_t'(interrupt_pending[dt_thread_idx]
                                                          & interrupt_mask[dt_thread_idx]);
                CR_INTERRUPT_ENABLE:  cr_creg_read_val <= scalar_t'(interrupt_mask[dt_thread_idx]);
                CR_INTERRUPT_TRIGGER: cr_creg_read_val <= scalar_t'(int_trigger_type);
                CR_JTAG_DATA:         cr_creg_read_val <= jtag_data;
                CR_SYSCALL_INDEX:     cr_creg_read_val <= scalar_t'(trap_state[dt_thread_idx][0].syscall_index);
                CR_PERF_EVENT_COUNT0_L: cr_creg_read_val <= cr_perf_event_count0[31:0];
                CR_PERF_EVENT_COUNT0_H: cr_creg_read_val <= cr_perf_event_count0[63:32];
                CR_PERF_EVENT_COUNT1_L: cr_creg_read_val <= cr_perf_event_count1[31:0];
                CR_PERF_EVENT_COUNT1_H: cr_creg_read_val <= cr_perf_event_count1[63:32];
                default:              cr_creg_read_val <= 32'hffffffff;
            endcase
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// A single instruction pipeline with L1 instruction & data caches and L2
// interface logic.
//

module core
    #(parameter CORE_ID = '0,
    parameter RESET_PC = '0,
    parameter NUM_INTERRUPTS = 16)

    (input                                 clk,
    input                                  reset,
    input local_thread_bitmap_t            thread_en,
    input [NUM_INTERRUPTS - 1:0]           interrupt_req,

    // From l1_l2_interface
    input                                  l2_ready,
    input                                  l2_response_valid,
    input l2rsp_packet_t                   l2_response,

    // To l1_l2_interface
    output logic                           l2i_request_valid,
    output l2req_packet_t                  l2i_request,

    // From io_request_queue
    input                                  ii_ready,
    input                                  ii_response_valid,
    input iorsp_packet_t                   ii_response,

    // To io_request_queue
    output logic                           ior_request_valid,
    output ioreq_packet_t                  ior_request,

    // From on_chip_debugger
    input                                  ocd_halt,
    input local_thread_idx_t               ocd_thread,
    input core_id_t                        ocd_core,
    input scalar_t                         ocd_inject_inst,
    input                                  ocd_inject_en,
    output logic                           injected_complete,
    output logic                           injected_rollback,
    input scalar_t                         ocd_data_from_host,
    input                                  ocd_data_update,
    output scalar_t                        cr_data_to_host,

    // To nyuzi
    output logic[TOTAL_THREADS - 1:0]      cr_suspend_thread,
    output logic[TOTAL_THREADS - 1:0]      cr_resume_thread);

    localparam EVENT_IDX_WIDTH = $clog2(CORE_PERF_EVENTS);
    localparam NUM_PERF_COUNTERS = 2;

    logic core_selected_debug;
    logic[CORE_PERF_EVENTS - 1:0] perf_events;
    logic[NUM_PERF_COUNTERS - 1:0][EVENT_IDX_WIDTH - 1:0] perf_event_select;

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    scalar_t            cr_creg_read_val;       // From control_registers of control_registers.v
    logic [ASID_WIDTH-1:0] cr_current_asid [`THREADS_PER_CORE];// From control_registers of control_registers.v
    scalar_t            cr_eret_address [`THREADS_PER_CORE];// From control_registers of control_registers.v
    subcycle_t          cr_eret_subcycle [`THREADS_PER_CORE];// From control_registers of control_registers.v
    local_thread_bitmap_t cr_interrupt_en;      // From control_registers of control_registers.v
    logic [`THREADS_PER_CORE-1:0] cr_interrupt_pending;// From control_registers of control_registers.v
    logic               cr_mmu_en [`THREADS_PER_CORE];// From control_registers of control_registers.v
    logic               cr_supervisor_en [`THREADS_PER_CORE];// From control_registers of control_registers.v
    scalar_t            cr_tlb_miss_handler;    // From control_registers of control_registers.v
    scalar_t            cr_trap_handler;        // From control_registers of control_registers.v
    logic               dd_cache_miss;          // From dcache_data_stage of dcache_data_stage.v
    cache_line_index_t  dd_cache_miss_addr;     // From dcache_data_stage of dcache_data_stage.v
    logic               dd_cache_miss_sync;     // From dcache_data_stage of dcache_data_stage.v
    local_thread_idx_t  dd_cache_miss_thread_idx;// From dcache_data_stage of dcache_data_stage.v
    control_register_t  dd_creg_index;          // From dcache_data_stage of dcache_data_stage.v
    logic               dd_creg_read_en;        // From dcache_data_stage of dcache_data_stage.v
    logic               dd_creg_write_en;       // From dcache_data_stage of dcache_data_stage.v
    scalar_t            dd_creg_write_val;      // From dcache_data_stage of dcache_data_stage.v
    logic               dd_dinvalidate_en;      // From dcache_data_stage of dcache_data_stage.v
    logic               dd_flush_en;            // From dcache_data_stage of dcache_data_stage.v
    logic               dd_iinvalidate_en;      // From dcache_data_stage of dcache_data_stage.v
    decoded_instruction_t dd_instruction;       // From dcache_data_stage of dcache_data_stage.v
    logic               dd_instruction_valid;   // From dcache_data_stage of dcache_data_stage.v
    logic               dd_io_access;           // From dcache_data_stage of dcache_data_stage.v
    scalar_t            dd_io_addr;             // From dcache_data_stage of dcache_data_stage.v
    logic               dd_io_read_en;          // From dcache_data_stage of dcache_data_stage.v
    local_thread_idx_t  dd_io_thread_idx;       // From dcache_data_stage of dcache_data_stage.v
    logic               dd_io_write_en;         // From dcache_data_stage of dcache_data_stage.v
    scalar_t            dd_io_write_value;      // From dcache_data_stage of dcache_data_stage.v
    vector_mask_t       dd_lane_mask;           // From dcache_data_stage of dcache_data_stage.v
    cache_line_data_t   dd_load_data;           // From dcache_data_stage of dcache_data_stage.v
    local_thread_bitmap_t dd_load_sync_pending; // From dcache_data_stage of dcache_data_stage.v
    logic               dd_membar_en;           // From dcache_data_stage of dcache_data_stage.v
    logic               dd_perf_dcache_hit;     // From dcache_data_stage of dcache_data_stage.v
    logic               dd_perf_dcache_miss;    // From dcache_data_stage of dcache_data_stage.v
    logic               dd_perf_dtlb_miss;      // From dcache_data_stage of dcache_data_stage.v
    l1d_addr_t          dd_request_vaddr;       // From dcache_data_stage of dcache_data_stage.v
    logic               dd_rollback_en;         // From dcache_data_stage of dcache_data_stage.v
    scalar_t            dd_rollback_pc;         // From dcache_data_stage of dcache_data_stage.v
    cache_line_index_t  dd_store_addr;          // From dcache_data_stage of dcache_data_stage.v
    cache_line_index_t  dd_store_bypass_addr;   // From dcache_data_stage of dcache_data_stage.v
    local_thread_idx_t  dd_store_bypass_thread_idx;// From dcache_data_stage of dcache_data_stage.v
    cache_line_data_t   dd_store_data;          // From dcache_data_stage of dcache_data_stage.v
    logic               dd_store_en;            // From dcache_data_stage of dcache_data_stage.v
    logic [CACHE_LINE_BYTES-1:0] dd_store_mask; // From dcache_data_stage of dcache_data_stage.v
    logic               dd_store_sync;          // From dcache_data_stage of dcache_data_stage.v
    local_thread_idx_t  dd_store_thread_idx;    // From dcache_data_stage of dcache_data_stage.v
    subcycle_t          dd_subcycle;            // From dcache_data_stage of dcache_data_stage.v
    logic               dd_suspend_thread;      // From dcache_data_stage of dcache_data_stage.v
    local_thread_idx_t  dd_thread_idx;          // From dcache_data_stage of dcache_data_stage.v
    logic               dd_trap;                // From dcache_data_stage of dcache_data_stage.v
    trap_cause_t        dd_trap_cause;          // From dcache_data_stage of dcache_data_stage.v
    logic               dd_update_lru_en;       // From dcache_data_stage of dcache_data_stage.v
    l1d_way_idx_t       dd_update_lru_way;      // From dcache_data_stage of dcache_data_stage.v
    l1d_way_idx_t       dt_fill_lru;            // From dcache_tag_stage of dcache_tag_stage.v
    decoded_instruction_t dt_instruction;       // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_instruction_valid;   // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_invalidate_tlb_all_en;// From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_invalidate_tlb_en;   // From dcache_tag_stage of dcache_tag_stage.v
    vector_mask_t       dt_mask_value;          // From dcache_tag_stage of dcache_tag_stage.v
    l1d_addr_t          dt_request_paddr;       // From dcache_tag_stage of dcache_tag_stage.v
    l1d_addr_t          dt_request_vaddr;       // From dcache_tag_stage of dcache_tag_stage.v
    l1d_tag_t           dt_snoop_tag [`L1D_WAYS];// From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_snoop_valid [`L1D_WAYS];// From dcache_tag_stage of dcache_tag_stage.v
    vector_t            dt_store_value;         // From dcache_tag_stage of dcache_tag_stage.v
    subcycle_t          dt_subcycle;            // From dcache_tag_stage of dcache_tag_stage.v
    l1d_tag_t           dt_tag [`L1D_WAYS];     // From dcache_tag_stage of dcache_tag_stage.v
    local_thread_idx_t  dt_thread_idx;          // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_tlb_hit;             // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_tlb_present;         // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_tlb_supervisor;      // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_tlb_writable;        // From dcache_tag_stage of dcache_tag_stage.v
    logic [ASID_WIDTH-1:0] dt_update_itlb_asid; // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_update_itlb_en;      // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_update_itlb_executable;// From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_update_itlb_global;  // From dcache_tag_stage of dcache_tag_stage.v
    page_index_t        dt_update_itlb_ppage_idx;// From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_update_itlb_present; // From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_update_itlb_supervisor;// From dcache_tag_stage of dcache_tag_stage.v
    page_index_t        dt_update_itlb_vpage_idx;// From dcache_tag_stage of dcache_tag_stage.v
    logic               dt_valid [`L1D_WAYS];   // From dcache_tag_stage of dcache_tag_stage.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx1_add_exponent;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] fx1_add_result_sign;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] fx1_equal;     // From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] [5:0] fx1_ftoi_lshift;// From fp_execute_stage1 of fp_execute_stage1.v
    decoded_instruction_t fx1_instruction;      // From fp_execute_stage1 of fp_execute_stage1.v
    logic               fx1_instruction_valid;  // From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] fx1_logical_subtract;// From fp_execute_stage1 of fp_execute_stage1.v
    vector_mask_t       fx1_mask_value;         // From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx1_mul_exponent;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] fx1_mul_sign;  // From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] fx1_mul_underflow;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] [31:0] fx1_multiplicand;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] [31:0] fx1_multiplier;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] fx1_result_inf;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] fx1_result_nan;// From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] [5:0] fx1_se_align_shift;// From fp_execute_stage1 of fp_execute_stage1.v
    scalar_t [NUM_VECTOR_LANES-1:0] fx1_significand_le;// From fp_execute_stage1 of fp_execute_stage1.v
    scalar_t [NUM_VECTOR_LANES-1:0] fx1_significand_se;// From fp_execute_stage1 of fp_execute_stage1.v
    subcycle_t          fx1_subcycle;           // From fp_execute_stage1 of fp_execute_stage1.v
    local_thread_idx_t  fx1_thread_idx;         // From fp_execute_stage1 of fp_execute_stage1.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx2_add_exponent;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_add_result_sign;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_equal;     // From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] [5:0] fx2_ftoi_lshift;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_guard;     // From fp_execute_stage2 of fp_execute_stage2.v
    decoded_instruction_t fx2_instruction;      // From fp_execute_stage2 of fp_execute_stage2.v
    logic               fx2_instruction_valid;  // From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_logical_subtract;// From fp_execute_stage2 of fp_execute_stage2.v
    vector_mask_t       fx2_mask_value;         // From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx2_mul_exponent;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_mul_sign;  // From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_mul_underflow;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_result_inf;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_result_nan;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_round;     // From fp_execute_stage2 of fp_execute_stage2.v
    scalar_t [NUM_VECTOR_LANES-1:0] fx2_significand_le;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] [63:0] fx2_significand_product;// From fp_execute_stage2 of fp_execute_stage2.v
    scalar_t [NUM_VECTOR_LANES-1:0] fx2_significand_se;// From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] fx2_sticky;    // From fp_execute_stage2 of fp_execute_stage2.v
    subcycle_t          fx2_subcycle;           // From fp_execute_stage2 of fp_execute_stage2.v
    local_thread_idx_t  fx2_thread_idx;         // From fp_execute_stage2 of fp_execute_stage2.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx3_add_exponent;// From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] fx3_add_result_sign;// From fp_execute_stage3 of fp_execute_stage3.v
    scalar_t [NUM_VECTOR_LANES-1:0] fx3_add_significand;// From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] fx3_equal;     // From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] [5:0] fx3_ftoi_lshift;// From fp_execute_stage3 of fp_execute_stage3.v
    decoded_instruction_t fx3_instruction;      // From fp_execute_stage3 of fp_execute_stage3.v
    logic               fx3_instruction_valid;  // From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] fx3_logical_subtract;// From fp_execute_stage3 of fp_execute_stage3.v
    vector_mask_t       fx3_mask_value;         // From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx3_mul_exponent;// From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] fx3_mul_sign;  // From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] fx3_mul_underflow;// From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] fx3_result_inf;// From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] fx3_result_nan;// From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] [63:0] fx3_significand_product;// From fp_execute_stage3 of fp_execute_stage3.v
    subcycle_t          fx3_subcycle;           // From fp_execute_stage3 of fp_execute_stage3.v
    local_thread_idx_t  fx3_thread_idx;         // From fp_execute_stage3 of fp_execute_stage3.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx4_add_exponent;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] fx4_add_result_sign;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] [31:0] fx4_add_significand;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] fx4_equal;     // From fp_execute_stage4 of fp_execute_stage4.v
    decoded_instruction_t fx4_instruction;      // From fp_execute_stage4 of fp_execute_stage4.v
    logic               fx4_instruction_valid;  // From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] fx4_logical_subtract;// From fp_execute_stage4 of fp_execute_stage4.v
    vector_mask_t       fx4_mask_value;         // From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] [7:0] fx4_mul_exponent;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] fx4_mul_sign;  // From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] fx4_mul_underflow;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] [5:0] fx4_norm_shift;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] fx4_result_inf;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] fx4_result_nan;// From fp_execute_stage4 of fp_execute_stage4.v
    logic [NUM_VECTOR_LANES-1:0] [63:0] fx4_significand_product;// From fp_execute_stage4 of fp_execute_stage4.v
    subcycle_t          fx4_subcycle;           // From fp_execute_stage4 of fp_execute_stage4.v
    local_thread_idx_t  fx4_thread_idx;         // From fp_execute_stage4 of fp_execute_stage4.v
    decoded_instruction_t fx5_instruction;      // From fp_execute_stage5 of fp_execute_stage5.v
    logic               fx5_instruction_valid;  // From fp_execute_stage5 of fp_execute_stage5.v
    vector_mask_t       fx5_mask_value;         // From fp_execute_stage5 of fp_execute_stage5.v
    vector_t            fx5_result;             // From fp_execute_stage5 of fp_execute_stage5.v
    subcycle_t          fx5_subcycle;           // From fp_execute_stage5 of fp_execute_stage5.v
    local_thread_idx_t  fx5_thread_idx;         // From fp_execute_stage5 of fp_execute_stage5.v
    decoded_instruction_t id_instruction;       // From instruction_decode_stage of instruction_decode_stage.v
    logic               id_instruction_valid;   // From instruction_decode_stage of instruction_decode_stage.v
    local_thread_idx_t  id_thread_idx;          // From instruction_decode_stage of instruction_decode_stage.v
    logic               ifd_alignment_fault;    // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_cache_miss;         // From ifetch_data_stage of ifetch_data_stage.v
    cache_line_index_t  ifd_cache_miss_paddr;   // From ifetch_data_stage of ifetch_data_stage.v
    local_thread_idx_t  ifd_cache_miss_thread_idx;// From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_executable_fault;   // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_inst_injected;      // From ifetch_data_stage of ifetch_data_stage.v
    scalar_t            ifd_instruction;        // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_instruction_valid;  // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_near_miss;          // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_page_fault;         // From ifetch_data_stage of ifetch_data_stage.v
    scalar_t            ifd_pc;                 // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_perf_icache_hit;    // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_perf_icache_miss;   // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_perf_itlb_miss;     // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_supervisor_fault;   // From ifetch_data_stage of ifetch_data_stage.v
    local_thread_idx_t  ifd_thread_idx;         // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_tlb_miss;           // From ifetch_data_stage of ifetch_data_stage.v
    logic               ifd_update_lru_en;      // From ifetch_data_stage of ifetch_data_stage.v
    l1i_way_idx_t       ifd_update_lru_way;     // From ifetch_data_stage of ifetch_data_stage.v
    l1i_way_idx_t       ift_fill_lru;           // From ifetch_tag_stage of ifetch_tag_stage.v
    logic               ift_instruction_requested;// From ifetch_tag_stage of ifetch_tag_stage.v
    l1i_addr_t          ift_pc_paddr;           // From ifetch_tag_stage of ifetch_tag_stage.v
    scalar_t            ift_pc_vaddr;           // From ifetch_tag_stage of ifetch_tag_stage.v
    l1i_tag_t           ift_tag [`L1I_WAYS];    // From ifetch_tag_stage of ifetch_tag_stage.v
    local_thread_idx_t  ift_thread_idx;         // From ifetch_tag_stage of ifetch_tag_stage.v
    logic               ift_tlb_executable;     // From ifetch_tag_stage of ifetch_tag_stage.v
    logic               ift_tlb_hit;            // From ifetch_tag_stage of ifetch_tag_stage.v
    logic               ift_tlb_present;        // From ifetch_tag_stage of ifetch_tag_stage.v
    logic               ift_tlb_supervisor;     // From ifetch_tag_stage of ifetch_tag_stage.v
    logic               ift_valid [`L1I_WAYS];  // From ifetch_tag_stage of ifetch_tag_stage.v
    local_thread_bitmap_t ior_pending;          // From io_request_queue of io_request_queue.v
    scalar_t            ior_read_value;         // From io_request_queue of io_request_queue.v
    logic               ior_rollback_en;        // From io_request_queue of io_request_queue.v
    local_thread_bitmap_t ior_wake_bitmap;      // From io_request_queue of io_request_queue.v
    decoded_instruction_t ix_instruction;       // From int_execute_stage of int_execute_stage.v
    logic               ix_instruction_valid;   // From int_execute_stage of int_execute_stage.v
    vector_mask_t       ix_mask_value;          // From int_execute_stage of int_execute_stage.v
    logic               ix_perf_cond_branch_not_taken;// From int_execute_stage of int_execute_stage.v
    logic               ix_perf_cond_branch_taken;// From int_execute_stage of int_execute_stage.v
    logic               ix_perf_uncond_branch;  // From int_execute_stage of int_execute_stage.v
    logic               ix_privileged_op_fault; // From int_execute_stage of int_execute_stage.v
    vector_t            ix_result;              // From int_execute_stage of int_execute_stage.v
    logic               ix_rollback_en;         // From int_execute_stage of int_execute_stage.v
    scalar_t            ix_rollback_pc;         // From int_execute_stage of int_execute_stage.v
    subcycle_t          ix_subcycle;            // From int_execute_stage of int_execute_stage.v
    local_thread_idx_t  ix_thread_idx;          // From int_execute_stage of int_execute_stage.v
    logic               l2i_dcache_lru_fill_en; // From l1_l2_interface of l1_l2_interface.v
    l1d_set_idx_t       l2i_dcache_lru_fill_set;// From l1_l2_interface of l1_l2_interface.v
    local_thread_bitmap_t l2i_dcache_wake_bitmap;// From l1_l2_interface of l1_l2_interface.v
    cache_line_data_t   l2i_ddata_update_data;  // From l1_l2_interface of l1_l2_interface.v
    logic               l2i_ddata_update_en;    // From l1_l2_interface of l1_l2_interface.v
    l1d_set_idx_t       l2i_ddata_update_set;   // From l1_l2_interface of l1_l2_interface.v
    l1d_way_idx_t       l2i_ddata_update_way;   // From l1_l2_interface of l1_l2_interface.v
    logic [`L1D_WAYS-1:0] l2i_dtag_update_en_oh;// From l1_l2_interface of l1_l2_interface.v
    l1d_set_idx_t       l2i_dtag_update_set;    // From l1_l2_interface of l1_l2_interface.v
    l1d_tag_t           l2i_dtag_update_tag;    // From l1_l2_interface of l1_l2_interface.v
    logic               l2i_dtag_update_valid;  // From l1_l2_interface of l1_l2_interface.v
    logic               l2i_icache_lru_fill_en; // From l1_l2_interface of l1_l2_interface.v
    l1i_set_idx_t       l2i_icache_lru_fill_set;// From l1_l2_interface of l1_l2_interface.v
    local_thread_bitmap_t l2i_icache_wake_bitmap;// From l1_l2_interface of l1_l2_interface.v
    cache_line_data_t   l2i_idata_update_data;  // From l1_l2_interface of l1_l2_interface.v
    logic               l2i_idata_update_en;    // From l1_l2_interface of l1_l2_interface.v
    l1i_set_idx_t       l2i_idata_update_set;   // From l1_l2_interface of l1_l2_interface.v
    l1i_way_idx_t       l2i_idata_update_way;   // From l1_l2_interface of l1_l2_interface.v
    logic [`L1I_WAYS-1:0] l2i_itag_update_en;   // From l1_l2_interface of l1_l2_interface.v
    l1i_set_idx_t       l2i_itag_update_set;    // From l1_l2_interface of l1_l2_interface.v
    l1i_tag_t           l2i_itag_update_tag;    // From l1_l2_interface of l1_l2_interface.v
    logic               l2i_itag_update_valid;  // From l1_l2_interface of l1_l2_interface.v
    logic               l2i_perf_store;         // From l1_l2_interface of l1_l2_interface.v
    logic               l2i_snoop_en;           // From l1_l2_interface of l1_l2_interface.v
    l1d_set_idx_t       l2i_snoop_set;          // From l1_l2_interface of l1_l2_interface.v
    decoded_instruction_t of_instruction;       // From operand_fetch_stage of operand_fetch_stage.v
    logic               of_instruction_valid;   // From operand_fetch_stage of operand_fetch_stage.v
    vector_mask_t       of_mask_value;          // From operand_fetch_stage of operand_fetch_stage.v
    vector_t            of_operand1;            // From operand_fetch_stage of operand_fetch_stage.v
    vector_t            of_operand2;            // From operand_fetch_stage of operand_fetch_stage.v
    vector_t            of_store_value;         // From operand_fetch_stage of operand_fetch_stage.v
    subcycle_t          of_subcycle;            // From operand_fetch_stage of operand_fetch_stage.v
    local_thread_idx_t  of_thread_idx;          // From operand_fetch_stage of operand_fetch_stage.v
    logic [1:0] [63:0]  perf_event_count;       // From performance_counters of performance_counters.v
    logic               sq_rollback_en;         // From l1_l2_interface of l1_l2_interface.v
    cache_line_data_t   sq_store_bypass_data;   // From l1_l2_interface of l1_l2_interface.v
    logic [CACHE_LINE_BYTES-1:0] sq_store_bypass_mask;// From l1_l2_interface of l1_l2_interface.v
    local_thread_bitmap_t sq_store_sync_pending;// From l1_l2_interface of l1_l2_interface.v
    logic               sq_store_sync_success;  // From l1_l2_interface of l1_l2_interface.v
    local_thread_bitmap_t ts_fetch_en;          // From thread_select_stage of thread_select_stage.v
    decoded_instruction_t ts_instruction;       // From thread_select_stage of thread_select_stage.v
    logic               ts_instruction_valid;   // From thread_select_stage of thread_select_stage.v
    logic               ts_perf_instruction_issue;// From thread_select_stage of thread_select_stage.v
    subcycle_t          ts_subcycle;            // From thread_select_stage of thread_select_stage.v
    local_thread_idx_t  ts_thread_idx;          // From thread_select_stage of thread_select_stage.v
    logic               wb_eret;                // From writeback_stage of writeback_stage.v
    logic               wb_inst_injected;       // From writeback_stage of writeback_stage.v
    logic               wb_perf_instruction_retire;// From writeback_stage of writeback_stage.v
    logic               wb_perf_interrupt;      // From writeback_stage of writeback_stage.v
    logic               wb_perf_store_rollback; // From writeback_stage of writeback_stage.v
    logic               wb_rollback_en;         // From writeback_stage of writeback_stage.v
    scalar_t            wb_rollback_pc;         // From writeback_stage of writeback_stage.v
    pipeline_sel_t      wb_rollback_pipeline;   // From writeback_stage of writeback_stage.v
    subcycle_t          wb_rollback_subcycle;   // From writeback_stage of writeback_stage.v
    local_thread_idx_t  wb_rollback_thread_idx; // From writeback_stage of writeback_stage.v
    local_thread_bitmap_t wb_suspend_thread_oh; // From writeback_stage of writeback_stage.v
    syscall_index_t     wb_syscall_index;       // From writeback_stage of writeback_stage.v
    logic               wb_trap;                // From writeback_stage of writeback_stage.v
    scalar_t            wb_trap_access_vaddr;   // From writeback_stage of writeback_stage.v
    trap_cause_t        wb_trap_cause;          // From writeback_stage of writeback_stage.v
    scalar_t            wb_trap_pc;             // From writeback_stage of writeback_stage.v
    subcycle_t          wb_trap_subcycle;       // From writeback_stage of writeback_stage.v
    logic               wb_writeback_en;        // From writeback_stage of writeback_stage.v
    logic               wb_writeback_last_subcycle;// From writeback_stage of writeback_stage.v
    vector_mask_t       wb_writeback_mask;      // From writeback_stage of writeback_stage.v
    register_idx_t      wb_writeback_reg;       // From writeback_stage of writeback_stage.v
    local_thread_idx_t  wb_writeback_thread_idx;// From writeback_stage of writeback_stage.v
    vector_t            wb_writeback_value;     // From writeback_stage of writeback_stage.v
    logic               wb_writeback_vector;    // From writeback_stage of writeback_stage.v
    // End of automatics

    //
    // Instruction Execution Pipeline
    //
    ifetch_tag_stage #(.RESET_PC(RESET_PC)) ifetch_tag_stage(.*);
    ifetch_data_stage ifetch_data_stage(.*);
    instruction_decode_stage instruction_decode_stage(.*);
    thread_select_stage thread_select_stage(.*);
    operand_fetch_stage operand_fetch_stage(.*);
    dcache_data_stage dcache_data_stage(.*);
    dcache_tag_stage dcache_tag_stage(.*);
    int_execute_stage int_execute_stage(.*);
    fp_execute_stage1 fp_execute_stage1(.*);
    fp_execute_stage2 fp_execute_stage2(.*);
    fp_execute_stage3 fp_execute_stage3(.*);
    fp_execute_stage4 fp_execute_stage4(.*);
    fp_execute_stage5 fp_execute_stage5(.*);
    writeback_stage writeback_stage(.*);

    control_registers #(
        .CORE_ID(CORE_ID),
        .NUM_INTERRUPTS(NUM_INTERRUPTS),
        .NUM_PERF_EVENTS(CORE_PERF_EVENTS)
    ) control_registers(
        .cr_perf_event_select0(perf_event_select[0]),
        .cr_perf_event_select1(perf_event_select[1]),
        .cr_perf_event_count0(perf_event_count[0]),
        .cr_perf_event_count1(perf_event_count[1]),
        .*);

    l1_l2_interface #(.CORE_ID(CORE_ID)) l1_l2_interface(.*);
    io_request_queue #(.CORE_ID(CORE_ID)) io_request_queue(.*);

    assign core_selected_debug = CORE_ID == ocd_core;

    always @(posedge clk)
    begin
        injected_complete <= wb_inst_injected & !wb_rollback_en;
        injected_rollback <= wb_inst_injected & wb_rollback_en;
    end

    // The number of signals in this assignment must match CORE_PERF_EVENTS
    // in defines.sv.
    assign perf_events = {
        ix_perf_cond_branch_not_taken,
        ix_perf_cond_branch_taken,
        ix_perf_uncond_branch,
        dd_perf_dtlb_miss,
        dd_perf_dcache_hit,
        dd_perf_dcache_miss,
        ifd_perf_itlb_miss,
        ifd_perf_icache_hit,
        ifd_perf_icache_miss,
        ts_perf_instruction_issue,
        wb_perf_instruction_retire,
        l2i_perf_store,
        wb_perf_store_rollback,
        wb_perf_interrupt
    };

    performance_counters #(
        .NUM_EVENTS(CORE_PERF_EVENTS),
        .NUM_COUNTERS(2)
    ) performance_counters(
        .*);
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Instruction pipeline L1 data cache data stage.
// - Detects cache miss or hit based on tag information fetched from last
//   stage.
// - Reads from cache data storage.
// - Drives signals to previous stage to update LRU
//

module dcache_data_stage(
    input                                     clk,
    input                                     reset,

    // To instruction_decode_stage
    output local_thread_bitmap_t              dd_load_sync_pending,

    // From dcache_tag_stage
    input                                     dt_instruction_valid,
    input decoded_instruction_t               dt_instruction,
    input vector_mask_t                       dt_mask_value,
    input local_thread_idx_t                  dt_thread_idx,
    input l1d_addr_t                          dt_request_vaddr,
    input l1d_addr_t                          dt_request_paddr,
    input                                     dt_tlb_hit,
    input                                     dt_tlb_present,
    input                                     dt_tlb_supervisor,
    input                                     dt_tlb_writable,
    input vector_t                            dt_store_value,
    input subcycle_t                          dt_subcycle,
    input                                     dt_valid[`L1D_WAYS],
    input l1d_tag_t                           dt_tag[`L1D_WAYS],

    // To dcache_tag_stage
    output logic                              dd_update_lru_en,
    output l1d_way_idx_t                      dd_update_lru_way,

    // To io_request_queue
    output logic                              dd_io_write_en,
    output logic                              dd_io_read_en,
    output local_thread_idx_t                 dd_io_thread_idx,
    output scalar_t                           dd_io_addr,
    output scalar_t                           dd_io_write_value,

    // To writeback_stage
    output logic                              dd_instruction_valid,
    output decoded_instruction_t              dd_instruction,
    output vector_mask_t                      dd_lane_mask,
    output local_thread_idx_t                 dd_thread_idx,
    output l1d_addr_t                         dd_request_vaddr,
    output subcycle_t                         dd_subcycle,
    output logic                              dd_rollback_en,
    output scalar_t                           dd_rollback_pc,
    output cache_line_data_t                  dd_load_data,
    output logic                              dd_suspend_thread,
    output logic                              dd_io_access,
    output logic                              dd_trap,
    output trap_cause_t                       dd_trap_cause,

    // From control registers
    input logic                               cr_supervisor_en[`THREADS_PER_CORE],

    // To control_registers
    // These signals are unregistered
    output logic                              dd_creg_write_en,
    output logic                              dd_creg_read_en,
    output control_register_t                 dd_creg_index,
    output scalar_t                           dd_creg_write_val,

    // From l1_l2_interface
    input                                     l2i_ddata_update_en,
    input l1d_way_idx_t                       l2i_ddata_update_way,
    input l1d_set_idx_t                       l2i_ddata_update_set,
    input cache_line_data_t                   l2i_ddata_update_data,
    input [`L1D_WAYS - 1:0]                   l2i_dtag_update_en_oh,
    input l1d_set_idx_t                       l2i_dtag_update_set,
    input l1d_tag_t                           l2i_dtag_update_tag,

     // To l1_l2_interface
    output logic                              dd_cache_miss,
    output cache_line_index_t                 dd_cache_miss_addr,
    output local_thread_idx_t                 dd_cache_miss_thread_idx,
    output logic                              dd_cache_miss_sync,
    output logic                              dd_store_en,
    output logic                              dd_flush_en,
    output logic                              dd_membar_en,
    output logic                              dd_iinvalidate_en,
    output logic                              dd_dinvalidate_en,
    output logic[CACHE_LINE_BYTES - 1:0]      dd_store_mask,
    output cache_line_index_t                 dd_store_addr,
    output cache_line_data_t                  dd_store_data,
    output local_thread_idx_t                 dd_store_thread_idx,
    output logic                              dd_store_sync,
    output cache_line_index_t                 dd_store_bypass_addr,
    output local_thread_idx_t                 dd_store_bypass_thread_idx,

    // From writeback_stage
    input logic                               wb_rollback_en,
    input local_thread_idx_t                  wb_rollback_thread_idx,
    input pipeline_sel_t                      wb_rollback_pipeline,

    // To performance_counters
    output logic                              dd_perf_dcache_hit,
    output logic                              dd_perf_dcache_miss,
    output logic                              dd_perf_dtlb_miss);

    logic memory_access_req;
    logic cached_access_req;
    logic cached_load_req;
    logic cached_store_req;
    logic creg_access_req;
    logic io_access_req;
    logic sync_access_req;
    logic cache_control_req;
    logic tlb_update_req;
    logic flush_req;
    logic iinvalidate_req;
    logic dinvalidate_req;
    logic membar_req;
    logic addr_in_io_region;
    logic unaligned_address;
    logic supervisor_fault;
    logic alignment_fault;
    logic privileged_op_fault;
    logic write_fault;
    logic tlb_miss;
    logic page_fault;
    logic any_fault;
    vector_mask_t word_store_mask;
    logic[3:0] byte_store_mask;
    logic[$clog2(CACHE_LINE_WORDS) - 1:0] cache_lane_idx;
    cache_line_data_t endian_twiddled_data;
    scalar_t lane_store_value;
    logic[CACHE_LINE_WORDS - 1:0] cache_lane_mask;
    logic[CACHE_LINE_WORDS - 1:0] subcycle_mask;
    logic[`L1D_WAYS - 1:0] way_hit_oh;
    l1d_way_idx_t way_hit_idx;
    logic cache_hit;
    scalar_t dcache_request_addr;
    logic squash_instruction;
    logic cache_near_miss;
    logic[$clog2(NUM_VECTOR_LANES) - 1:0] scgath_lane;
    logic tlb_read;
    logic fault_store_flag;
    logic lane_enabled;

    // Unlike earlier stages, this commits instruction side effects like stores,
    // so it needs to check if there is a rollback (which would be for the
    // instruction issued immediately before this one) and avoid updates if so.
    // squash_instruction indicates a rollback is requested from the previous
    // instruction, but it does not get set when this stage requests a rollback.
    assign squash_instruction = wb_rollback_en
        && wb_rollback_thread_idx == dt_thread_idx
        && wb_rollback_pipeline == PIPE_MEM;
    assign scgath_lane = ~dt_subcycle;

    // If a scatter/gather is active, need to check if the lane is active.
    // This is more than an optimization: if the lane is masked, we need to
    // ignore the pointer to not raise a fault if it is invalid.
    idx_to_oh #(
        .NUM_SIGNALS(CACHE_LINE_WORDS),
        .DIRECTION("LSB0")
    ) idx_to_oh_subcycle(
        .one_hot(subcycle_mask),
        .index(dt_subcycle));

    assign lane_enabled = !dt_instruction.memory_access
        || dt_instruction.memory_access_type != MEM_SCGATH_M
        || (dt_mask_value & subcycle_mask) != 0;

    // Decode request type. If this instruction is squashed, ignore (same as
    // dt_instruction_valid being false). These do not consider if the
    // request is legal or possible, just what the instruction is asking to do.
    assign addr_in_io_region = dt_request_paddr ==? 32'hffff????;
    assign sync_access_req = dt_instruction.memory_access_type == MEM_SYNC;

    // Note the last part that checks the store mask. If the store mask is zero
    // don't mark this as a memory access request. This is more than an optimization:
    // when performing a scatter store,
    assign memory_access_req = dt_instruction_valid
        && !squash_instruction
        && dt_instruction.memory_access
        && dt_instruction.memory_access_type != MEM_CONTROL_REG
        && lane_enabled;
    assign io_access_req = memory_access_req && addr_in_io_region;
    assign cached_access_req = memory_access_req && !addr_in_io_region;
    assign cached_load_req = cached_access_req && dt_instruction.load;
    assign cached_store_req = cached_access_req && !dt_instruction.load;
    assign cache_control_req = dt_instruction_valid
        && !squash_instruction
        && dt_instruction.cache_control;
    assign flush_req = cache_control_req
        && dt_instruction.cache_control_op == CACHE_DFLUSH
        && !addr_in_io_region;
    assign iinvalidate_req = cache_control_req
        && dt_instruction.cache_control_op == CACHE_IINVALIDATE
        && !addr_in_io_region;
    assign dinvalidate_req = cache_control_req
        && dt_instruction.cache_control_op == CACHE_DINVALIDATE
        && !addr_in_io_region;
    assign membar_req = cache_control_req
        && dt_instruction.cache_control_op == CACHE_MEMBAR;
    assign tlb_update_req = cache_control_req
        && (dt_instruction.cache_control_op == CACHE_DTLB_INSERT
            || dt_instruction.cache_control_op == CACHE_ITLB_INSERT
            || dt_instruction.cache_control_op == CACHE_TLB_INVAL
            || dt_instruction.cache_control_op == CACHE_TLB_INVAL_ALL);
    assign creg_access_req = dt_instruction_valid
        && !squash_instruction
        && dt_instruction.memory_access
        && dt_instruction.memory_access_type == MEM_CONTROL_REG;

    // Determine if this instruction accessed the TLB (and thus possibly
    // missed it)
    always_comb
    begin
        tlb_read = 0;
        if (dt_instruction_valid && !squash_instruction)
        begin
            if (dt_instruction.memory_access)
            begin
                tlb_read = dt_instruction.memory_access_type != MEM_CONTROL_REG
                    && lane_enabled;
            end
            else if (dt_instruction.cache_control)
            begin
                // Only these cache control opertions perform a virtual->physical
                // address translation.
                tlb_read = dt_instruction.cache_control_op == CACHE_DFLUSH
                    || dt_instruction.cache_control_op == CACHE_DINVALIDATE;
            end
        end
    end

    assign tlb_miss = tlb_read && !dt_tlb_hit;

    // Check for faults. This will set a fault type, and the signal 'any_fault', which
    // will cause side effects of subsequent memory operations to be disabled. Each
    // of this is only true if the operation is actually requested.
    always_comb
    begin
        unique case (dt_instruction.memory_access_type)
            MEM_S, MEM_SX: unaligned_address = dt_request_paddr.offset[0];
            MEM_L, MEM_SYNC, MEM_SCGATH, MEM_SCGATH_M: unaligned_address = |dt_request_paddr.offset[1:0];
            MEM_BLOCK, MEM_BLOCK_M: unaligned_address = dt_request_paddr.offset != 0;
            default: unaligned_address = 0;
        endcase
    end

    assign alignment_fault = (cached_access_req || io_access_req) && unaligned_address;
    assign privileged_op_fault = (creg_access_req || tlb_update_req || dinvalidate_req)
        && !cr_supervisor_en[dt_thread_idx];
    assign page_fault = memory_access_req
        && dt_tlb_hit
        && !dt_tlb_present;
    assign supervisor_fault = memory_access_req
        && dt_tlb_hit
        && dt_tlb_present
        && dt_tlb_supervisor
        && !cr_supervisor_en[dt_thread_idx];
    assign write_fault = (cached_store_req || (io_access_req && !dt_instruction.load))
        && dt_tlb_hit
        && dt_tlb_present
        && !supervisor_fault
        && !dt_tlb_writable;
    assign any_fault = alignment_fault || privileged_op_fault || page_fault
        || supervisor_fault || write_fault;

    // *** Everything below this point needs to check tlb_miss (if applicable)
    // and any_fault before enabling operations. ***

    // L1 data cache or store buffer access
    assign dd_store_en = cached_store_req
        && !tlb_miss
        && !any_fault;
    assign dcache_request_addr = {dt_request_paddr[31:CACHE_LINE_OFFSET_WIDTH],
        {CACHE_LINE_OFFSET_WIDTH{1'b0}}};
    assign cache_lane_idx = dt_request_paddr.offset[CACHE_LINE_OFFSET_WIDTH - 1:2];
    assign dd_store_bypass_addr = dt_request_paddr[31:CACHE_LINE_OFFSET_WIDTH];
    assign dd_store_bypass_thread_idx = dt_thread_idx;
    assign dd_store_addr = dt_request_paddr[31:CACHE_LINE_OFFSET_WIDTH];
    assign dd_store_sync = sync_access_req;
    assign dd_store_thread_idx = dt_thread_idx;

    // Noncached I/O memory access
    assign dd_io_write_en = io_access_req
        && !dt_instruction.load
        && !tlb_miss
        && !any_fault;
    assign dd_io_read_en = io_access_req
        && dt_instruction.load
        && !tlb_miss
        && !any_fault;
    assign dd_io_write_value = dt_store_value[0];
    assign dd_io_thread_idx = dt_thread_idx;
    assign dd_io_addr = {16'd0, dt_request_paddr[15:0]};

    // Control register access
    assign dd_creg_write_en = creg_access_req
        && !dt_instruction.load
        && !any_fault;
    assign dd_creg_read_en = creg_access_req
        && dt_instruction.load
        && !any_fault;
    assign dd_creg_write_val = dt_store_value[0];
    assign dd_creg_index = dt_instruction.creg_index;

    // Cache control
    // Unlike other operations, these check dt_tlb_present, as these will not raise
    // a fault if the page is not present.
    assign dd_flush_en = flush_req
        && dt_tlb_hit
        && dt_tlb_present
        && !io_access_req // XXX should a cache control of IO address raise exception?
        && !any_fault;
    assign dd_iinvalidate_en = iinvalidate_req
        && dt_tlb_hit
        && dt_tlb_present
        && !io_access_req
        && !any_fault;
    assign dd_dinvalidate_en = dinvalidate_req
        && dt_tlb_hit
        && dt_tlb_present
        && !io_access_req
        && !any_fault;
    assign dd_membar_en = membar_req
        && dt_instruction.cache_control_op == CACHE_MEMBAR;

    //
    // Check for cache hit
    //
    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < `L1D_WAYS; way_idx++)
        begin : hit_check_gen
            assign way_hit_oh[way_idx] = dt_request_paddr.tag == dt_tag[way_idx]
                && dt_valid[way_idx];
        end
    endgenerate

    // Treat a synchronized load as a cache miss the first time it occurs, because
    // it needs to send it to the L2 cache to register it.
    assign cache_hit = |way_hit_oh
        && (!sync_access_req || dd_load_sync_pending[dt_thread_idx])
        && dt_tlb_hit;

    //
    // Store alignment
    //
    idx_to_oh #(
        .NUM_SIGNALS(CACHE_LINE_WORDS),
        .DIRECTION("LSB0")
    ) idx_to_oh_cache_lane(
        .one_hot(cache_lane_mask),
        .index(cache_lane_idx));

    always_comb
    begin
        word_store_mask = 0;
        unique case (dt_instruction.memory_access_type)
            MEM_BLOCK, MEM_BLOCK_M:    // Block vector access
                word_store_mask = dt_mask_value;

            MEM_SCGATH, MEM_SCGATH_M:    // Scatter/Gather access
            begin
                if ((dt_mask_value & subcycle_mask) != 0)
                    word_store_mask = cache_lane_mask;
                else
                    word_store_mask = 0;
            end

            default:    // Scalar access
                word_store_mask = cache_lane_mask;
        endcase
    end

    // Endian swap vector data
    genvar swap_word;
    generate
        for (swap_word = 0; swap_word < CACHE_LINE_BYTES / 4; swap_word++)
        begin : swap_word_gen
            assign endian_twiddled_data[swap_word * 32+:8] = dt_store_value[swap_word][24+:8];
            assign endian_twiddled_data[swap_word * 32 + 8+:8] = dt_store_value[swap_word][16+:8];
            assign endian_twiddled_data[swap_word * 32 + 16+:8] = dt_store_value[swap_word][8+:8];
            assign endian_twiddled_data[swap_word * 32 + 24+:8] = dt_store_value[swap_word][0+:8];
        end
    endgenerate

    assign lane_store_value = dt_store_value[scgath_lane];

    // byte_store_mask and dd_store_data.
    always_comb
    begin
        unique case (dt_instruction.memory_access_type)
            MEM_B, MEM_BX: // Byte
            begin
                dd_store_data = {CACHE_LINE_WORDS * 4{dt_store_value[0][7:0]}};
                case (dt_request_paddr.offset[1:0])
                    2'd0: byte_store_mask = 4'b1000;
                    2'd1: byte_store_mask = 4'b0100;
                    2'd2: byte_store_mask = 4'b0010;
                    2'd3: byte_store_mask = 4'b0001;
                    default: byte_store_mask = 4'b0000;
                endcase
            end

            MEM_S, MEM_SX: // 16 bits
            begin
                dd_store_data = {CACHE_LINE_WORDS * 2{dt_store_value[0][7:0], dt_store_value[0][15:8]}};
                if (dt_request_paddr.offset[1] == 1'b0)
                    byte_store_mask = 4'b1100;
                else
                    byte_store_mask = 4'b0011;
            end

            MEM_L, MEM_SYNC: // 32 bits
            begin
                byte_store_mask = 4'b1111;
                dd_store_data = {CACHE_LINE_WORDS{dt_store_value[0][7:0], dt_store_value[0][15:8],
                    dt_store_value[0][23:16], dt_store_value[0][31:24]}};
            end

            MEM_SCGATH, MEM_SCGATH_M:
            begin
                byte_store_mask = 4'b1111;
                dd_store_data = {CACHE_LINE_WORDS{lane_store_value[7:0], lane_store_value[15:8],
                    lane_store_value[23:16], lane_store_value[31:24]}};
            end

            default: // Vector
            begin
                byte_store_mask = 4'b1111;
                dd_store_data = endian_twiddled_data;
            end
        endcase
    end

    // Generate store mask signals. word_store_mask corresponds to lanes,
    // byte_store_mask corresponds to bytes within a word. byte_store_mask
    // always has all bits set if word_store_mask has more than one bit set:
    // either select some number of words within the cache line for
    // a vector transfer or some bytes within a word for a scalar transfer.
    genvar mask_idx;
    generate
        for (mask_idx = 0; mask_idx < CACHE_LINE_BYTES; mask_idx++)
        begin : store_mask_gen
            assign dd_store_mask[mask_idx] = word_store_mask[
                (CACHE_LINE_BYTES - mask_idx - 1) / 4]
                & byte_store_mask[mask_idx & 3];
        end
    endgenerate

    oh_to_idx #(.NUM_SIGNALS(`L1D_WAYS)) encode_hit_way(
        .one_hot(way_hit_oh),
        .index(way_hit_idx));

    sram_1r1w #(
        .DATA_WIDTH(CACHE_LINE_BITS),
        .SIZE(`L1D_WAYS * `L1D_SETS),
        .READ_DURING_WRITE("NEW_DATA")
    ) l1d_data(
        // Instruction pipeline access.
        .read_en(cache_hit && cached_load_req),
        .read_addr({way_hit_idx, dt_request_paddr.set_idx}),
        .read_data(dd_load_data),

        // Update from L2 cache interface
        .write_en(l2i_ddata_update_en),
        .write_addr({l2i_ddata_update_way, l2i_ddata_update_set}),
        .write_data(l2i_ddata_update_data),
        .*);

    // cache_near_miss indicates a cache miss is occurring in the cycle this is
    // filling the same line. If this suspends the thread, it will never
    // receive a wakeup. Instead, roll the thread back and let it retry.
    // Do not be set for a synchronized load, even if the data is in the L1
    // cache: it must do a round trip to the L2 cache to latch the address.
    assign cache_near_miss = !cache_hit
        && dt_tlb_hit
        && cached_load_req
        && |l2i_dtag_update_en_oh
        && l2i_dtag_update_set == dt_request_paddr.set_idx
        && l2i_dtag_update_tag == dt_request_paddr.tag
        && !sync_access_req
        && !any_fault;

    assign dd_cache_miss = cached_load_req
        && !cache_hit
        && dt_tlb_hit
        && !cache_near_miss
        && !any_fault;
    assign dd_cache_miss_addr = dcache_request_addr[31:CACHE_LINE_OFFSET_WIDTH];
    assign dd_cache_miss_thread_idx = dt_thread_idx;
    assign dd_cache_miss_sync = sync_access_req;

    assign dd_update_lru_en = cache_hit && cached_access_req && !any_fault;
    assign dd_update_lru_way = way_hit_idx;

    // Always treat the first synchronized load as a cache miss, even if data is
    // present. This is to register request with L2 cache. The second request will
    // not be a miss if the data is in the cache (there is a window where it could
    // be evicted before the thread can fetch it, in which case it will retry.
    // load_sync_pending tracks if this is the first or second request.
    //
    // Interrupts are different than rollbacks because they can occur in the middle
    // of a synchronized load/store. Detect these and cancel the operation.
    genvar thread_idx;
    generate
        for (thread_idx = 0; thread_idx < `THREADS_PER_CORE; thread_idx++)
        begin : sync_pending_gen
            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                    dd_load_sync_pending[thread_idx] <= 0;
                else if (cached_load_req && sync_access_req && dt_thread_idx == local_thread_idx_t'(thread_idx))
                begin
                    // Track if this is the first or restarted request.
                    dd_load_sync_pending[thread_idx] <= !dd_load_sync_pending[thread_idx];
                end
            end
        end
    endgenerate

    assign fault_store_flag = dt_instruction.memory_access
        && !dt_instruction.load;

    always_ff @(posedge clk)
    begin
        dd_instruction <= dt_instruction;
        dd_lane_mask <= dt_mask_value;
        dd_thread_idx <= dt_thread_idx;
        dd_request_vaddr <= dt_request_vaddr;
        dd_subcycle <= dt_subcycle;
        dd_rollback_pc <= dt_instruction.pc;
        dd_io_access <= io_access_req;

        // Check for TLB miss first, since permission bits are not valid if
        // there is a TLB miss. The order of the remaining items should match
        // that in instruction_decode_stage for consistency.
        if (tlb_miss)
            dd_trap_cause <= {1'b1, fault_store_flag, TT_TLB_MISS};
        else if (page_fault)
            dd_trap_cause <= {1'b1, fault_store_flag, TT_PAGE_FAULT};
        else if (supervisor_fault)
            dd_trap_cause <= {1'b1, fault_store_flag, TT_SUPERVISOR_ACCESS};
        else if (alignment_fault)
            dd_trap_cause <= {1'b1, fault_store_flag, TT_UNALIGNED_ACCESS};
        else if (privileged_op_fault)
            dd_trap_cause <= {2'b00, TT_PRIVILEGED_OP};
        else // write fault
            dd_trap_cause <= {2'b11, TT_ILLEGAL_STORE};
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            dd_instruction_valid <= '0;
            dd_perf_dcache_hit <= '0;
            dd_perf_dcache_miss <= '0;
            dd_perf_dtlb_miss <= '0;
            dd_rollback_en <= '0;
            dd_suspend_thread <= '0;
            dd_trap <= '0;
            // End of automatics
        end
        else
        begin
            // Make sure data is not present in more than one way.
            assert(!cached_load_req || $onehot0(way_hit_oh));

            // Make sure this decodes only one type of instruction
            assert($onehot0({cached_load_req, cached_store_req, io_access_req,
                flush_req, iinvalidate_req, dinvalidate_req,
                membar_req, tlb_update_req, creg_access_req}));

            dd_instruction_valid <= dt_instruction_valid
                && !squash_instruction;

            // Rollback on cache miss
            dd_rollback_en <= cached_load_req && !cache_hit && dt_tlb_hit && !any_fault;

            // Suspend the thread if there is a cache miss.
            // In the near miss case (described above), don't suspend thread.
            dd_suspend_thread <= cached_load_req
                && dt_tlb_hit
                && !cache_hit
                && !cache_near_miss
                && !any_fault;

            dd_trap <= any_fault || tlb_miss;

            // Perf events
            dd_perf_dcache_hit <= cached_load_req && !any_fault && !tlb_miss
                 && cache_hit;
            dd_perf_dcache_miss <= cached_load_req && !any_fault && !tlb_miss
                && !cache_hit;
            dd_perf_dtlb_miss <= tlb_miss;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Instruction Pipeline L1 Data Cache Tag Stage.
// Contains tags and cache line states, which it queries when a memory access
// occurs. There is one cycle of latency to fetch these, so the next stage
// will handle the result. The L1 data cache is set associative. There is a
// separate block of tag ram for each way, which this reads in parallel. The
// next stage will check them to see if there is a cache hit on one of the
// ways. This also contains the translation lookaside buffer, which will
// convert the virtual memory address to a physical one. The cache is
// virtually indexed and physically tagged: the tag memories contain physical
// addresses, translated by the TLB.
//
// This also performs snoops from the l1_l2_interface when there are writes
// from this or other cores. Snoop addresses are physical addresses, but the
// tag memory is virtually indexed. To avoid aliasing, the size of a way must
// be the same size or smaller than a virtual page
// (cache line size * num sets <= page_size).
//

module dcache_tag_stage
    (input                                      clk,
    input                                       reset,

    // From operand_fetch_stage
    input vector_t                              of_operand1,
    input vector_mask_t                         of_mask_value,
    input vector_t                              of_store_value,
    input                                       of_instruction_valid,
    input decoded_instruction_t                 of_instruction,
    input local_thread_idx_t                    of_thread_idx,
    input subcycle_t                            of_subcycle,

    // From dcache_data_stage
    input                                       dd_update_lru_en,
    input l1d_way_idx_t                         dd_update_lru_way,

    // To dcache_data_stage
    output logic                                dt_instruction_valid,
    output decoded_instruction_t                dt_instruction,
    output vector_mask_t                        dt_mask_value,
    output local_thread_idx_t                   dt_thread_idx,
    output l1d_addr_t                           dt_request_vaddr,
    output l1d_addr_t                           dt_request_paddr,
    output logic                                dt_tlb_hit,
    output logic                                dt_tlb_writable,
    output vector_t                             dt_store_value,
    output subcycle_t                           dt_subcycle,
    output logic                                dt_valid[`L1D_WAYS],
    output l1d_tag_t                            dt_tag[`L1D_WAYS],
    output logic                                dt_tlb_supervisor,
    output logic                                dt_tlb_present,

    // To ifetch_tag_stage
    output logic                                dt_invalidate_tlb_en,
    output logic                                dt_invalidate_tlb_all_en,
    output logic                                dt_update_itlb_en,
    output [ASID_WIDTH - 1:0]                   dt_update_itlb_asid,
    output page_index_t                         dt_update_itlb_vpage_idx,
    output page_index_t                         dt_update_itlb_ppage_idx,
    output logic                                dt_update_itlb_present,
    output logic                                dt_update_itlb_supervisor,
    output logic                                dt_update_itlb_global,
    output logic                                dt_update_itlb_executable,

    // From l1_l2_interface
    input                                       l2i_dcache_lru_fill_en,
    input l1d_set_idx_t                         l2i_dcache_lru_fill_set,
    input [`L1D_WAYS - 1:0]                     l2i_dtag_update_en_oh,
    input l1d_set_idx_t                         l2i_dtag_update_set,
    input l1d_tag_t                             l2i_dtag_update_tag,
    input                                       l2i_dtag_update_valid,
    input                                       l2i_snoop_en,
    input l1d_set_idx_t                         l2i_snoop_set,

    // To l1_l2_interface
    output logic                                dt_snoop_valid[`L1D_WAYS],
    output l1d_tag_t                            dt_snoop_tag[`L1D_WAYS],
    output l1d_way_idx_t                        dt_fill_lru,

    // From control_registers
    input                                       cr_mmu_en[`THREADS_PER_CORE],
    input logic                                 cr_supervisor_en[`THREADS_PER_CORE],
    input [ASID_WIDTH - 1:0]                    cr_current_asid[`THREADS_PER_CORE],

    // From writeback_stage
    input logic                                 wb_rollback_en,
    input local_thread_idx_t                    wb_rollback_thread_idx);

    l1d_addr_t request_addr_nxt;
    logic cache_load_en;
    logic instruction_valid;
    logic[$clog2(NUM_VECTOR_LANES) - 1:0] scgath_lane;
    page_index_t tlb_ppage_idx;
    logic tlb_hit;
    page_index_t ppage_idx;
    scalar_t fetched_addr;
    logic tlb_lookup_en;
    logic valid_cache_control;
    logic update_dtlb_en;
    logic tlb_writable;
    logic tlb_present;
    logic tlb_supervisor;
    tlb_entry_t new_tlb_value;

    assign instruction_valid = of_instruction_valid
        && (!wb_rollback_en || wb_rollback_thread_idx != of_thread_idx)
        && of_instruction.pipeline_sel == PIPE_MEM;
    assign valid_cache_control = instruction_valid
        && of_instruction.cache_control;
    assign cache_load_en = instruction_valid
        && of_instruction.memory_access_type != MEM_CONTROL_REG
        && of_instruction.memory_access      // Not cache control
        && of_instruction.load;
    assign scgath_lane = ~of_subcycle;
    assign request_addr_nxt = of_operand1[scgath_lane] + of_instruction.immediate_value;
    assign new_tlb_value = of_store_value[0];
    assign dt_invalidate_tlb_en = valid_cache_control
        && of_instruction.cache_control_op == CACHE_TLB_INVAL
        && cr_supervisor_en[of_thread_idx];
    assign dt_invalidate_tlb_all_en = valid_cache_control
        && of_instruction.cache_control_op == CACHE_TLB_INVAL_ALL
        && cr_supervisor_en[of_thread_idx];
    assign update_dtlb_en = valid_cache_control
        && of_instruction.cache_control_op == CACHE_DTLB_INSERT
        && cr_supervisor_en[of_thread_idx];
    assign dt_update_itlb_en = valid_cache_control
        && of_instruction.cache_control_op == CACHE_ITLB_INSERT
        && cr_supervisor_en[of_thread_idx];
    assign dt_update_itlb_supervisor = new_tlb_value.supervisor;
    assign dt_update_itlb_global = new_tlb_value.global_map;
    assign dt_update_itlb_present = new_tlb_value.present;
    assign tlb_lookup_en = instruction_valid
        && of_instruction.memory_access_type != MEM_CONTROL_REG
        && !update_dtlb_en
        && !dt_invalidate_tlb_en
        && !dt_invalidate_tlb_all_en;
    assign dt_update_itlb_vpage_idx = of_operand1[0][31-:PAGE_NUM_BITS];
    assign dt_update_itlb_ppage_idx = new_tlb_value.ppage_idx;
    assign dt_update_itlb_executable = new_tlb_value.executable;
    assign dt_update_itlb_asid = cr_current_asid[of_thread_idx];

    initial
    begin
        // Cannot use more than 64 dcache sets
        assert(`L1D_SETS <= 64);
        assert((`L1D_SETS & (`L1D_SETS - 1)) == 0);
    end

    //
    // Way metadata
    //
    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < `L1D_WAYS; way_idx++)
        begin : way_tag_gen
            // Valid flags are flops instead of SRAM because they need
            // to all be cleared on reset.
            logic line_valid[`L1D_SETS];

            sram_2r1w #(
                .DATA_WIDTH($bits(l1d_tag_t)),
                .SIZE(`L1D_SETS),
                .READ_DURING_WRITE("NEW_DATA")
            ) sram_tags(
                .read1_en(cache_load_en),
                .read1_addr(request_addr_nxt.set_idx),
                .read1_data(dt_tag[way_idx]),
                .read2_en(l2i_snoop_en),
                .read2_addr(l2i_snoop_set),
                .read2_data(dt_snoop_tag[way_idx]),
                .write_en(l2i_dtag_update_en_oh[way_idx]),
                .write_addr(l2i_dtag_update_set),
                .write_data(l2i_dtag_update_tag),
                .*);

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                begin
                    for (int set_idx = 0; set_idx < `L1D_SETS; set_idx++)
                        line_valid[set_idx] <= 0;
                end
                else
                begin
                    if (l2i_dtag_update_en_oh[way_idx])
                        line_valid[l2i_dtag_update_set] <= l2i_dtag_update_valid;
                end
            end

            always_ff @(posedge clk)
            begin
                // Fetch cache line state for pipeline
                if (cache_load_en)
                begin
                    if (l2i_dtag_update_en_oh[way_idx] && l2i_dtag_update_set == request_addr_nxt.set_idx)
                        dt_valid[way_idx] <= l2i_dtag_update_valid;    // Bypass
                    else
                        dt_valid[way_idx] <= line_valid[request_addr_nxt.set_idx];
                end

                // Fetch cache line state for snoop
                if (l2i_snoop_en)
                begin
                    if (l2i_dtag_update_en_oh[way_idx] && l2i_dtag_update_set == l2i_snoop_set)
                        dt_snoop_valid[way_idx] <= l2i_dtag_update_valid;    // Bypass
                    else
                        dt_snoop_valid[way_idx] <= line_valid[l2i_snoop_set];
                end
            end
        end
    endgenerate

    tlb #(
        .NUM_ENTRIES(`DTLB_ENTRIES),
        .NUM_WAYS(`TLB_WAYS)
    ) dtlb(
        .lookup_en(tlb_lookup_en),
        .update_en(update_dtlb_en),
        .invalidate_en(dt_invalidate_tlb_en),
        .invalidate_all_en(dt_invalidate_tlb_all_en),
        .request_vpage_idx(request_addr_nxt[31-:PAGE_NUM_BITS]),
        .request_asid(cr_current_asid[of_thread_idx]),
        .update_ppage_idx(new_tlb_value.ppage_idx),
        .update_present(new_tlb_value.present),
        .update_exe_writable(new_tlb_value.writable),
        .update_supervisor(new_tlb_value.supervisor),
        .update_global(new_tlb_value.global_map),
        .lookup_ppage_idx(tlb_ppage_idx),
        .lookup_hit(tlb_hit),
        .lookup_present(tlb_present),
        .lookup_exe_writable(tlb_writable),
        .lookup_supervisor(tlb_supervisor),
        .*);

    // This combinational logic is after the flip flops,
    // so these signals are delayed one cycle from other signals
    // in this module.
    always_comb
    begin
        if (cr_mmu_en[dt_thread_idx])
        begin
            dt_tlb_hit = tlb_hit;
            dt_tlb_writable = tlb_writable;
            dt_tlb_present = tlb_present;
            dt_tlb_supervisor = tlb_supervisor;
            ppage_idx = tlb_ppage_idx;
        end
        else
        begin
            dt_tlb_hit = 1;
            dt_tlb_writable = 1;
            dt_tlb_present = 1;
            dt_tlb_supervisor = 0;
            ppage_idx = fetched_addr[31-:PAGE_NUM_BITS];
        end
    end

    cache_lru #(
        .NUM_WAYS(`L1D_WAYS),
        .NUM_SETS(`L1D_SETS)
    ) lru(
        .fill_en(l2i_dcache_lru_fill_en),
        .fill_set(l2i_dcache_lru_fill_set),
        .fill_way(dt_fill_lru),
        .access_en(instruction_valid),
        .access_set(request_addr_nxt.set_idx),
        .update_en(dd_update_lru_en),
        .update_way(dd_update_lru_way),
        .*);

    always_ff @(posedge clk)
    begin
        dt_instruction <= of_instruction;
        dt_mask_value <= of_mask_value;
        dt_thread_idx <= of_thread_idx;
        dt_store_value <= of_store_value;
        dt_subcycle <= of_subcycle;
        fetched_addr <= request_addr_nxt;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            dt_instruction_valid <= '0;
        else
        begin
            assert($onehot0(l2i_dtag_update_en_oh));
            dt_instruction_valid <= instruction_valid;
        end
    end

    assign dt_request_paddr = {ppage_idx, fetched_addr[31 - PAGE_NUM_BITS:0]};
    assign dt_request_vaddr = fetched_addr;
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

module de2_115_top(
    input                       clk50,

    // Buttons
    input                       reset_btn,    // KEY[0]

    // Der blinkenlights
    output logic[17:0]          red_led,
    output logic[8:0]           green_led,
    output logic[6:0]           hex0,
    output logic[6:0]           hex1,
    output logic[6:0]           hex2,
    output logic[6:0]           hex3,

    // UART
    output                      uart_tx,
    input                       uart_rx,

    // SDRAM
    output                      dram_clk,
    output                      dram_cke,
    output                      dram_cs_n,
    output                      dram_ras_n,
    output                      dram_cas_n,
    output                      dram_we_n,
    output [1:0]                dram_ba,
    output [12:0]               dram_addr,
    output [3:0]                dram_dqm,
    inout [31:0]                dram_dq,

    // VGA
    output [7:0]                vga_r,
    output [7:0]                vga_g,
    output [7:0]                vga_b,
    output                      vga_clk,
    output                      vga_blank_n,
    output                      vga_hs,
    output                      vga_vs,
    output                      vga_sync_n,

    // SD card
    output                      sd_clk,
    input                       sd_do,
    output                      sd_di,
    output                      sd_cs,

    // PS/2
    input                       ps2_clk,
    input                       ps2_data);
`ifdef BOOT_FILE
    parameter  bootrom="empty.hex";
`endif

    localparam BOOT_ROM_BASE = 32'hfffee000;
    localparam NUM_PERIPHERALS = 5;

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    logic               frame_interrupt;        // From vga_controller of vga_controller.v
    logic               perf_dram_page_hit;     // From sdram_controller of sdram_controller.v
    logic               perf_dram_page_miss;    // From sdram_controller of sdram_controller.v
    logic               timer_interrupt;        // From timer of timer.v
    // End of automatics

    axi4_interface axi_bus_s[1:0]();
    axi4_interface axi_bus_m[1:0]();
    logic reset;
    logic clk;
    scalar_t peripheral_read_data[NUM_PERIPHERALS];
    io_bus_interface peripheral_io_bus[NUM_PERIPHERALS - 1:0]();
    io_bus_interface nyuzi_io_bus();
    jtag_interface jtag();
    enum logic[$clog2(NUM_PERIPHERALS) - 1:0] {
        IO_UART,
        IO_SDCARD,
        IO_PS2,
        IO_VGA,
        IO_TIMER
    } io_bus_source;
    logic uart_rx_interrupt;
    logic ps2_rx_interrupt;
    logic virt_tdo;
    logic virt_tck;
    logic virt_tdi;
    logic virt_data_reg;
    /* verilator lint_off UNDRIVEN */
    logic virt_reset;
    /* verilator lint_on UNDRIVEN */

    assign clk = clk50;

    nyuzi #(.RESET_PC(BOOT_ROM_BASE)) nyuzi(
        .interrupt_req({11'd0,
            frame_interrupt,
            ps2_rx_interrupt,
            uart_rx_interrupt,
            timer_interrupt,
            1'b0}),
        .axi_bus(axi_bus_m[0]),
        .io_bus(nyuzi_io_bus),
        .jtag(jtag),
        .*);
`ifdef BOOT_FILE
    axi_interconnect #(.M1_BASE_ADDRESS(BOOT_ROM_BASE)) axi_interconnect(
`else
    axi_interconnect axi_interconenct(
`endif
        .axi_bus_s(axi_bus_s),
        .axi_bus_m(axi_bus_m),
        .*);

    // Synchronize from two asynchronous sources, reset_btn is the
    // pushbutton on the dev board (which goes low when pressed),
    // and virt_reset comes from the virtual JTAG.
    synchronizer reset_synchronizer(
        .clk(clk),
        .reset(0),
        .data_o(reset),
        .data_i(!reset_btn || virt_reset));

    // Boot ROM.  Execution starts here. The boot ROM path is relative
    // to the directory that the synthesis tool is invoked from (this
    // directory).
  `ifdef BOOT_FILE
    axi_rom #(.FILENAME(bootrom)) boot_rom(
  `else
    axi_rom boot_rom(
  `endif
        .axi_bus(axi_bus_s[1]),
        .*);

    sdram_controller #(
        .DATA_WIDTH(32),
        .ROW_ADDR_WIDTH(13),
        .COL_ADDR_WIDTH(10),

        // 50 Mhz = 20ns clock.  Each value is clocks of delay minus one.
        // Timing values based on datasheet for A3V64S40ETP SDRAM parts
        // on the DE2-115 board.
        .T_REFRESH(390),            // 64 ms / 8192 rows = 7.8125 uS
        .T_POWERUP(10000),          // 200 us
        .T_ROW_PRECHARGE(1),        // 21 ns
        .T_AUTO_REFRESH_CYCLE(3),   // 75 ns
        .T_RAS_CAS_DELAY(1),        // 21 ns
        .T_CAS_LATENCY(1)           // 21 ns (2 cycles)
    ) sdram_controller(
        .axi_bus(axi_bus_s[0]),
        .*);

    // We always access the full word width, so hard code these to active (low)
    assign dram_dqm = 4'b0000;

    vga_controller #(.BASE_ADDRESS('h180)) vga_controller(
        .io_bus(peripheral_io_bus[IO_VGA]),
        .axi_bus(axi_bus_m[1]),
        .*);

`ifdef WITH_LOGIC_ANALYZER
    logic[87:0] capture_data;
    logic capture_enable;
    logic trigger;
    logic[31:0] event_count;

    assign capture_data = { perf_dram_page_hit };
    assign capture_enable = 1;
    assign trigger = event_count == 120;

    logic_analyzer #(.CAPTURE_WIDTH_BITS($bits(capture_data)),
        .CAPTURE_SIZE(128)) logic_analyzer(.*);

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            event_count <= 0;
        else if (capture_enable)
            event_count <= event_count + 1;
    end
`else
    uart #(.BASE_ADDRESS('h40)) uart(
        .io_bus(peripheral_io_bus[IO_UART]),
        .rx_interrupt(uart_rx_interrupt),
        .*);
`endif

    spi_controller #(.BASE_ADDRESS('hc0)) spi_controller(
        .io_bus(peripheral_io_bus[IO_SDCARD]),
        .spi_clk(sd_clk),
        .spi_cs_n(sd_cs),
        .spi_miso(sd_do),
        .spi_mosi(sd_di),
        .*);

    ps2_controller #(.BASE_ADDRESS('h80)) ps2_controller(
        .io_bus(peripheral_io_bus[IO_PS2]),
        .rx_interrupt(ps2_rx_interrupt),
        .*);

    timer #(.BASE_ADDRESS('h240)) timer(
        .io_bus(peripheral_io_bus[IO_TIMER]),
        .*);

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            red_led <= 0;
            green_led <= 0;
            hex0 <= 7'b1111111;
            hex1 <= 7'b1111111;
            hex2 <= 7'b1111111;
            hex3 <= 7'b1111111;
        end
        else
        begin
            if (nyuzi_io_bus.write_en)
            begin
                case (nyuzi_io_bus.address)
                    'h00: red_led <= nyuzi_io_bus.write_data[17:0];
                    'h04: green_led <= nyuzi_io_bus.write_data[8:0];
                    'h08: hex0 <= nyuzi_io_bus.write_data[6:0];
                    'h0c: hex1 <= nyuzi_io_bus.write_data[6:0];
                    'h10: hex2 <= nyuzi_io_bus.write_data[6:0];
                    'h14: hex3 <= nyuzi_io_bus.write_data[6:0];
                endcase
            end

            casez (nyuzi_io_bus.address)
                'h4?: io_bus_source <= IO_UART;
                'hc?: io_bus_source <= IO_SDCARD;
                'h8?: io_bus_source <= IO_PS2;
                default: io_bus_source <= IO_UART;
            endcase
        end
    end

    assign nyuzi_io_bus.read_data = peripheral_read_data[io_bus_source];

    genvar io_idx;
    generate
        for (io_idx = 0; io_idx < NUM_PERIPHERALS; io_idx++)
        begin : io_gen
            assign peripheral_io_bus[io_idx].write_en = nyuzi_io_bus.write_en;
            assign peripheral_io_bus[io_idx].read_en = nyuzi_io_bus.read_en;
            assign peripheral_io_bus[io_idx].address = nyuzi_io_bus.address;
            assign peripheral_io_bus[io_idx].write_data = nyuzi_io_bus.write_data;
            assign peripheral_read_data[io_idx] = peripheral_io_bus[io_idx].read_data;
        end
    endgenerate

    assign jtag.tck = 0;
    assign jtag.tdi = 0;
    assign jtag.tms = 0;
    assign jtag.trst_n = 0;

// It's a little weird to have this in a VENDOR_ALTERA ifdef, since this file
// is Altera specific, but this is done so Verilator can still run a lint pass
// on this file to check for errors in CI.
`ifdef VENDOR_ALTERA
    //
    // This virtual JTAG block is independent of the JTAG OCD interface on Nyuzi.
    // It's used only to be able to reset the processor from the test harness.
    // It only has one data register, with one bit, which contains the reset
    // state.
    //
    sld_virtual_jtag #(
        .sld_auto_instance_index("NO"),
        .sld_instance_index(0),
        .sld_ir_width(4)
    ) virtual_jtag(
        .tck(virt_tck),
        .tdi(virt_tdi),
        .tdo(virt_data_reg),
        .virtual_state_sdr(virt_sdr),   // Shift data register
        .virtual_state_udr(virt_udr)    // Update data register
    );

    always @(posedge virt_tck)
    begin
        if (virt_sdr)
            virt_data_reg <= virt_tdi;
        else if (virt_udr)
            virt_reset <= virt_data_reg;
    end
`endif
endmodule
// dh
` ifdef VENDOR_ALTERA
(* blackbox *)
module sld_virtual_jtag #(parameter sld_auto_instance_index="NO",
                                    sld_instance_index=0,
				    sld_ir_width=4)
(input wire tck,
 input wire tdi,
 output logic tdo,
 output logic virtual_state_sdr,
 output logic virtual_state_udr);
 endmodule
`endif
//

//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Floating Point Execute Stage 1
//
// Floating Point Addition
// - Determine which operand has the larger absolute value
// - Swap if necessary so the larger operand is in the larger-exponent lane
//   (_le)
// - Compute alignment shift count
// Float to int conversion
// - Steer significand down smaller-exponent lane
// Floating point multiplication
// - Add exponents/multiply significands
// The floating point pipeline also handles integer multiplication. This
// stages passes through the integer value to the multiplier in the next
// stage.
//

module fp_execute_stage1(
    input                                           clk,
    input                                           reset,

    // From writeback_stage
    input logic                                     wb_rollback_en,
    input local_thread_idx_t                        wb_rollback_thread_idx,

    // From operand_fetch_stage
    input vector_t                                  of_operand1,
    input vector_t                                  of_operand2,
    input vector_mask_t                             of_mask_value,
    input                                           of_instruction_valid,
    input decoded_instruction_t                     of_instruction,
    input local_thread_idx_t                        of_thread_idx,
    input subcycle_t                                of_subcycle,

    // To fp_execute_stage2
    output logic                                    fx1_instruction_valid,
    output decoded_instruction_t                    fx1_instruction,
    output vector_mask_t                            fx1_mask_value,
    output local_thread_idx_t                       fx1_thread_idx,
    output subcycle_t                               fx1_subcycle,
    output logic[NUM_VECTOR_LANES - 1:0]            fx1_result_inf,
    output logic[NUM_VECTOR_LANES - 1:0]            fx1_result_nan,
    output logic[NUM_VECTOR_LANES - 1:0]            fx1_equal,
    output logic[NUM_VECTOR_LANES - 1:0][5:0]       fx1_ftoi_lshift,

    // Floating point addition/subtraction
    output scalar_t[NUM_VECTOR_LANES - 1:0]         fx1_significand_le,  // Larger exponent
    output scalar_t[NUM_VECTOR_LANES - 1:0]         fx1_significand_se,  // Smaller exponent
    output logic[NUM_VECTOR_LANES - 1:0][5:0]       fx1_se_align_shift,
    output logic[NUM_VECTOR_LANES - 1:0][7:0]       fx1_add_exponent,
    output logic[NUM_VECTOR_LANES - 1:0]            fx1_logical_subtract,
    output logic[NUM_VECTOR_LANES - 1:0]            fx1_add_result_sign,

    // Floating point multiplication
    output logic[NUM_VECTOR_LANES - 1:0][31:0]      fx1_multiplicand,
    output logic[NUM_VECTOR_LANES - 1:0][31:0]      fx1_multiplier,
    output logic[NUM_VECTOR_LANES - 1:0][7:0]       fx1_mul_exponent,
    output logic[NUM_VECTOR_LANES - 1:0]            fx1_mul_underflow,
    output logic[NUM_VECTOR_LANES - 1:0]            fx1_mul_sign);

    logic fmul;
    logic imul;
    logic ftoi;
    logic itof;
    logic compare;

    assign fmul = of_instruction.alu_op == OP_MUL_F;
    assign imul = of_instruction.alu_op == OP_MULL_I || of_instruction.alu_op == OP_MULH_U
        || of_instruction.alu_op == OP_MULH_I;
    assign ftoi = of_instruction.alu_op == OP_FTOI;
    assign itof = of_instruction.alu_op == OP_ITOF;
    assign compare = of_instruction.alu_op == OP_CMPGT_F
        || of_instruction.alu_op == OP_CMPLT_F
        || of_instruction.alu_op == OP_CMPGE_F
        || of_instruction.alu_op == OP_CMPLE_F
        || of_instruction.alu_op == OP_CMPEQ_F
        || of_instruction.alu_op == OP_CMPNE_F;

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_VECTOR_LANES; lane_idx++)
        begin : lane_logic_gen
            float32_t fop1;
            float32_t fop2;
            logic[FLOAT32_SIG_WIDTH:0] full_significand1;    // Note extra bit
            logic[FLOAT32_SIG_WIDTH:0] full_significand2;
            logic op1_hidden_bit;
            logic op2_hidden_bit;
            logic op1_larger;
            logic[FLOAT32_EXP_WIDTH - 1:0] exp_difference;
            logic subtract;
            logic[FLOAT32_EXP_WIDTH - 1:0] mul_exponent;
            logic fop1_inf;
            logic fop1_nan;
            logic fop2_inf;
            logic fop2_nan;
            logic logical_subtract;
            logic result_nan;
            logic equal;
            logic mul_exponent_underflow;
            logic mul_exponent_carry;
            logic[5:0] ftoi_rshift;
            logic[5:0] ftoi_lshift_nxt;

            assign fop1 = of_operand1[lane_idx];
            assign fop2 = of_operand2[lane_idx];
            assign op1_hidden_bit = fop1.exponent != 0;    // Check for subnormal numbers
            assign op2_hidden_bit = fop2.exponent != 0;
            assign full_significand1 = {op1_hidden_bit, fop1.significand};
            assign full_significand2 = {op2_hidden_bit, fop2.significand};
            assign subtract = of_instruction.alu_op != OP_ADD_F;    // This also include compares
            assign fop1_inf = fop1.exponent == 8'hff && fop1.significand == 0;
            assign fop1_nan = fop1.exponent == 8'hff && fop1.significand != 0;
            assign fop2_inf = fop2.exponent == 8'hff && fop2.significand == 0;
            assign fop2_nan = fop2.exponent == 8'hff && fop2.significand != 0;

            // Compute how much to shift the significand right to truncate
            // fractional digits
            always_comb
            begin
                if (fop2.exponent < 8'd118)
                begin
                    ftoi_rshift = 6'd32;    // Number is less than one, set to 0
                    ftoi_lshift_nxt = 0;
                end
                else if (fop2.exponent < 8'd150)
                begin
                    ftoi_rshift = 6'(8'd150 - fop2.exponent);  // Truncate significand
                    ftoi_lshift_nxt = 0;
                end
                else
                begin
                    ftoi_rshift = 6'd0;    // No fractional bits that fit in precision
                    ftoi_lshift_nxt = 6'(fop2.exponent - 8'd150);
                end
            end

            always_comb
            begin
                if (itof)
                    logical_subtract = of_operand2[lane_idx][31]; // Check high bit to see if this is negative
                else if (ftoi)
                    logical_subtract = fop2.sign; // If negative, inverter in stg 3 will convert to 2s complement
                else
                    logical_subtract = fop1.sign ^ fop2.sign ^ subtract;
            end

            always_comb
            begin
                if (itof)
                    result_nan = 0;
                else if (fmul)
                    result_nan = fop1_nan || fop2_nan || (fop1_inf && of_operand2[lane_idx] == 0)
                        || (fop2_inf && of_operand1[lane_idx] == 0);
                else if (ftoi)
                    result_nan = fop2_nan || fop2_inf || fop2.exponent >= 8'd159;
                else if (compare)
                    result_nan = fop1_nan || fop2_nan;
                else
                    result_nan = fop1_nan || fop2_nan || (fop1_inf && fop2_inf && logical_subtract);
            end

            // This will be overridden if result_nan is true.
            assign equal = (fop1_inf && fop2_inf && fop1.sign == fop2.sign)
                || (!fop1_inf && !fop2_inf && fop1 == fop2);

            // The result exponent for multiplication is the sum of the exponents. Convert these
            // from biased to unbiased representation by inverting the MSB, then add.
            // XXX handle underflow
            assign {mul_exponent_underflow, mul_exponent_carry, mul_exponent}
                =  {2'd0, fop1.exponent} + {2'd0, fop2.exponent} - 10'd127;

            // Subtle: In the case where values are equal, leave operand1 in the _le slot. This properly
            // handles the sign for +/- zero.
            assign op1_larger = fop1.exponent > fop2.exponent
                    || (fop1.exponent == fop2.exponent && full_significand1 >= full_significand2);
            assign exp_difference = op1_larger ? fop1.exponent - fop2.exponent
                : fop2.exponent - fop1.exponent;

            always_ff @(posedge clk)
            begin
                fx1_result_nan[lane_idx] <= result_nan;
                fx1_result_inf[lane_idx] <= !itof && !result_nan && (fop1_inf || fop2_inf
                    || (fmul && mul_exponent_carry && !mul_exponent_underflow));
                fx1_equal[lane_idx] <= equal;
                fx1_mul_underflow[lane_idx] <= mul_exponent_underflow;

                // Floating point addition pipeline.
                // - If this is a float<->int conversion, the value goes down the small exponent path.
                //   The large exponent is set to zero.
                // - For addition/subtraction, sort into significand_le (the larger value) and
                //   sigificand_se (the smaller).
                if (op1_larger || ftoi || itof)
                begin
                    if (ftoi || itof)
                        fx1_significand_le[lane_idx] <= 0;
                    else
                        fx1_significand_le[lane_idx] <= scalar_t'(full_significand1);

                    if (itof)
                    begin
                        // Convert int to float
                        fx1_significand_se[lane_idx] <= of_operand2[lane_idx];
                        fx1_add_exponent[lane_idx] <= 8'd127 + 8'd23;
                        fx1_add_result_sign[lane_idx] <= of_operand2[lane_idx][31];
                    end
                    else
                    begin
                        // Add/Subtract/Compare, first operand has larger value
                        fx1_significand_se[lane_idx] <= scalar_t'(full_significand2);
                        fx1_add_exponent[lane_idx] <= fop1.exponent;
                        fx1_add_result_sign[lane_idx] <= fop1.sign;    // Larger magnitude sign wins
                    end
                end
                else
                begin
                    // Add/Subtract/Comapare, second operand has larger value
                    fx1_significand_le[lane_idx] <= scalar_t'(full_significand2);
                    fx1_significand_se[lane_idx] <= scalar_t'(full_significand1);
                    fx1_add_exponent[lane_idx] <= fop2.exponent;
                    fx1_add_result_sign[lane_idx] <= fop2.sign ^ subtract;
                end

                fx1_logical_subtract[lane_idx] <= logical_subtract;
                if (itof)
                    fx1_se_align_shift[lane_idx] <= 0;
                else if (ftoi)
                begin
                    // Shift to truncate fractional bits
                    fx1_se_align_shift[lane_idx] <= ftoi_rshift[5:0];
                end
                else
                begin
                    // Compute how much to shift significand to make exponents be equal.
                    // Shift up to 27 bits, even though the significand is only 24 bits.
                    // This allows shifting out the guard and round bits.
                    fx1_se_align_shift[lane_idx] <= exp_difference < 8'd27 ? 6'(exp_difference) : 6'd27;
                end

                fx1_ftoi_lshift[lane_idx] <= ftoi_lshift_nxt;

                // Multiplication pipeline.
                // XXX this is a pass through now. For a more optimal implementation, this could do
                // booth encoding.
                if (imul)
                begin
                    // Unsigned multiply
                    fx1_multiplicand[lane_idx] <= of_operand1[lane_idx];
                    fx1_multiplier[lane_idx] <= of_operand2[lane_idx];
                end
                else
                begin
                    fx1_multiplicand[lane_idx] <= scalar_t'(full_significand1);
                    fx1_multiplier[lane_idx] <= scalar_t'(full_significand2);
                end

                fx1_mul_exponent[lane_idx] <= mul_exponent;
                fx1_mul_sign[lane_idx] <= fop1.sign ^ fop2.sign;
            end
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        fx1_instruction <= of_instruction;
        fx1_mask_value <= of_mask_value;
        fx1_thread_idx <= of_thread_idx;
        fx1_subcycle <= of_subcycle;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            fx1_instruction_valid <= '0;
        else
        begin
            fx1_instruction_valid <= of_instruction_valid
                && (!wb_rollback_en || wb_rollback_thread_idx != of_thread_idx)
                && of_instruction.pipeline_sel == PIPE_FLOAT_ARITH;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Floating Point Execute Stage 2
//
// Floating Point Addition
// - Shift smaller operand to align with larger
// Floating Point multiplication
// - Perform actual operation (XXX placeholder, see below)
// Float to int conversion
// - Shift significand right to truncate fractional bit positions
//

module fp_execute_stage2(
    input                                       clk,
    input                                       reset,

    // From writeback_stage
    input logic                                 wb_rollback_en,
    input local_thread_idx_t                    wb_rollback_thread_idx,
    input pipeline_sel_t                        wb_rollback_pipeline,

    // From fp_execute_stage1
    input vector_mask_t                         fx1_mask_value,
    input                                       fx1_instruction_valid,
    input decoded_instruction_t                 fx1_instruction,
    input local_thread_idx_t                    fx1_thread_idx,
    input subcycle_t                            fx1_subcycle,
    input [NUM_VECTOR_LANES - 1:0]              fx1_result_inf,
    input [NUM_VECTOR_LANES - 1:0]              fx1_result_nan,
    input [NUM_VECTOR_LANES - 1:0]              fx1_equal,
    input [NUM_VECTOR_LANES - 1:0][5:0]         fx1_ftoi_lshift,

    // Floating point addition/subtraction
    input scalar_t[NUM_VECTOR_LANES - 1:0]      fx1_significand_le,
    input scalar_t[NUM_VECTOR_LANES - 1:0]      fx1_significand_se,
    input [NUM_VECTOR_LANES - 1:0]              fx1_logical_subtract,
    input [NUM_VECTOR_LANES - 1:0][5:0]         fx1_se_align_shift,
    input [NUM_VECTOR_LANES - 1:0][7:0]         fx1_add_exponent,
    input [NUM_VECTOR_LANES - 1:0]              fx1_add_result_sign,

    // Floating point multiplication
    input [NUM_VECTOR_LANES - 1:0][7:0]         fx1_mul_exponent,
    input [NUM_VECTOR_LANES - 1:0]              fx1_mul_sign,
    input [NUM_VECTOR_LANES - 1:0][31:0]        fx1_multiplicand,
    input [NUM_VECTOR_LANES - 1:0][31:0]        fx1_multiplier,
    input [NUM_VECTOR_LANES - 1:0]              fx1_mul_underflow,

    // To fp_execute_stage3
    output logic                                fx2_instruction_valid,
    output decoded_instruction_t                fx2_instruction,
    output vector_mask_t                        fx2_mask_value,
    output local_thread_idx_t                   fx2_thread_idx,
    output subcycle_t                           fx2_subcycle,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_result_inf,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_result_nan,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_equal,
    output logic[NUM_VECTOR_LANES - 1:0][5:0]   fx2_ftoi_lshift,

    // Floating point addition/subtraction
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_logical_subtract,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_add_result_sign,
    output scalar_t[NUM_VECTOR_LANES - 1:0]     fx2_significand_le,
    output scalar_t[NUM_VECTOR_LANES - 1:0]     fx2_significand_se,
    output logic[NUM_VECTOR_LANES - 1:0][7:0]   fx2_add_exponent,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_guard,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_round,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_sticky,

    // Floating point multiplication
    output logic[NUM_VECTOR_LANES - 1:0][63:0]  fx2_significand_product,
    output logic[NUM_VECTOR_LANES - 1:0][7:0]   fx2_mul_exponent,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_mul_underflow,
    output logic[NUM_VECTOR_LANES - 1:0]        fx2_mul_sign);

    logic imulhs;

    assign imulhs = fx1_instruction.alu_op == OP_MULH_I;

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_VECTOR_LANES; lane_idx++)
        begin : lane_logic_gen
            scalar_t aligned_significand;
            logic guard;
            logic round;
            logic[24:0] sticky_bits;
            logic sticky;
            logic[63:0] sext_multiplicand;
            logic[63:0] sext_multiplier;

            assign {aligned_significand, guard, round, sticky_bits} = {fx1_significand_se[lane_idx], 27'd0} >>
                fx1_se_align_shift[lane_idx];
            assign sticky = |sticky_bits;

            // Sign extend multiply operands
            assign sext_multiplicand = {{32{fx1_multiplicand[lane_idx][31] && imulhs}},
                fx1_multiplicand[lane_idx]};
            assign sext_multiplier = {{32{fx1_multiplier[lane_idx][31] && imulhs}},
                fx1_multiplier[lane_idx]};

            always_ff @(posedge clk)
            begin
                fx2_significand_le[lane_idx] <= fx1_significand_le[lane_idx];
                fx2_significand_se[lane_idx] <= aligned_significand;
                fx2_add_exponent[lane_idx] <= fx1_add_exponent[lane_idx];
                fx2_logical_subtract[lane_idx] <= fx1_logical_subtract[lane_idx];
                fx2_add_result_sign[lane_idx] <= fx1_add_result_sign[lane_idx];
                fx2_guard[lane_idx] <= guard;
                fx2_round[lane_idx] <= round;
                fx2_sticky[lane_idx] <= sticky;
                fx2_mul_exponent[lane_idx] <= fx1_mul_exponent[lane_idx];
                fx2_mul_underflow[lane_idx] <= fx1_mul_underflow[lane_idx];
                fx2_mul_sign[lane_idx] <= fx1_mul_sign[lane_idx];
                fx2_result_inf[lane_idx] <= fx1_result_inf[lane_idx];
                fx2_result_nan[lane_idx] <= fx1_result_nan[lane_idx];
                fx2_equal[lane_idx] <= fx1_equal[lane_idx];
                fx2_ftoi_lshift[lane_idx] <= fx1_ftoi_lshift[lane_idx];

                // XXX Simple version. Should have a wallace tree here to collect partial products.
                fx2_significand_product[lane_idx] <= sext_multiplicand * sext_multiplier;
            end
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        fx2_instruction <= fx1_instruction;
        fx2_mask_value <= fx1_mask_value;
        fx2_thread_idx <= fx1_thread_idx;
        fx2_subcycle <= fx1_subcycle;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            fx2_instruction_valid <= '0;
        else
        begin
            fx2_instruction_valid <= fx1_instruction_valid
                && (!wb_rollback_en || wb_rollback_thread_idx != fx1_thread_idx
                || wb_rollback_pipeline != PIPE_MEM);
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Floating Point Execute Stage 3
//
// Floating Point Addition
// - Add/subtract significands
// - Rounding for subtraction
// Int-to-float/float-to-int
// - Convert negative values to 2's complement.
// Floating point multiplication
// - pass through
//

module fp_execute_stage3(
    input                                       clk,
    input                                       reset,

    // From fp_execute_stage2
    input vector_mask_t                         fx2_mask_value,
    input                                       fx2_instruction_valid,
    input decoded_instruction_t                 fx2_instruction,
    input local_thread_idx_t                    fx2_thread_idx,
    input subcycle_t                            fx2_subcycle,
    input [NUM_VECTOR_LANES - 1:0]              fx2_result_inf,
    input [NUM_VECTOR_LANES - 1:0]              fx2_result_nan,
    input [NUM_VECTOR_LANES - 1:0]              fx2_equal,
    input [NUM_VECTOR_LANES - 1:0][5:0]         fx2_ftoi_lshift,

    // Floating point addition/subtraction
    input scalar_t[NUM_VECTOR_LANES - 1:0]      fx2_significand_le,
    input scalar_t[NUM_VECTOR_LANES - 1:0]      fx2_significand_se,
    input[NUM_VECTOR_LANES - 1:0]               fx2_logical_subtract,
    input[NUM_VECTOR_LANES - 1:0][7:0]          fx2_add_exponent,
    input[NUM_VECTOR_LANES - 1:0]               fx2_add_result_sign,
    input[NUM_VECTOR_LANES - 1:0]               fx2_guard,
    input[NUM_VECTOR_LANES - 1:0]               fx2_round,
    input[NUM_VECTOR_LANES - 1:0]               fx2_sticky,

    // Floating point multiplication
    input [NUM_VECTOR_LANES - 1:0][63:0]        fx2_significand_product,
    input [NUM_VECTOR_LANES - 1:0][7:0]         fx2_mul_exponent,
    input [NUM_VECTOR_LANES - 1:0]              fx2_mul_underflow,
    input [NUM_VECTOR_LANES - 1:0]              fx2_mul_sign,

    // To fp_execute_stage4
    output logic                                fx3_instruction_valid,
    output decoded_instruction_t                fx3_instruction,
    output vector_mask_t                        fx3_mask_value,
    output local_thread_idx_t                   fx3_thread_idx,
    output subcycle_t                           fx3_subcycle,
    output logic[NUM_VECTOR_LANES - 1:0]        fx3_result_inf,
    output logic[NUM_VECTOR_LANES - 1:0]        fx3_result_nan,
    output logic[NUM_VECTOR_LANES - 1:0]        fx3_equal,
    output logic[NUM_VECTOR_LANES - 1:0][5:0]   fx3_ftoi_lshift,

    // Floating point addition/subtraction
    output scalar_t[NUM_VECTOR_LANES - 1:0]     fx3_add_significand,
    output logic[NUM_VECTOR_LANES - 1:0][7:0]   fx3_add_exponent,
    output logic[NUM_VECTOR_LANES - 1:0]        fx3_add_result_sign,
    output logic[NUM_VECTOR_LANES - 1:0]        fx3_logical_subtract,

    // Floating point multiplication
    output logic[NUM_VECTOR_LANES - 1:0][63:0]  fx3_significand_product,
    output logic[NUM_VECTOR_LANES - 1:0][7:0]   fx3_mul_exponent,
    output logic[NUM_VECTOR_LANES - 1:0]        fx3_mul_underflow,
    output logic[NUM_VECTOR_LANES - 1:0]        fx3_mul_sign);

    logic ftoi;

    assign ftoi = fx2_instruction.alu_op == OP_FTOI;

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_VECTOR_LANES; lane_idx++)
        begin : lane_logic_gen
            logic carry_in;
            scalar_t unnormalized_sum;
            logic sum_odd;
            logic round_up;
            logic round_tie;
            logic do_round;
            logic _unused;

            // Round-to-nearest, round half to even. Compute the value of the low bit
            // of the sum to predict if the result is odd.
            assign sum_odd = fx2_significand_le[lane_idx][0] ^ fx2_significand_se[lane_idx][0];
            assign round_tie = (fx2_guard[lane_idx] && !(fx2_round[lane_idx] || fx2_sticky[lane_idx]));
            assign round_up = (fx2_guard[lane_idx] && (fx2_round[lane_idx] || fx2_sticky[lane_idx]));
            assign do_round = (round_up || (sum_odd && round_tie));

            // For logical subtraction, rounding reduces the unnormalized sum because
            // it rounds the subtrahend up. Since this inverts the second parameter
            // to perform a subtraction, a +1 is normally necessary. Round down by
            // not doing that. For logical addition, rounding increases the unnormalized
            // sum. Do these by setting carry_in appropriately.
            //
            // For float<->int conversions, overload this to handle changing between signed-magnitude
            // and two's complement format. LE is set to zero and fx2_logical_subtract indicates
            // if it needs a conversion.
            assign carry_in = fx2_logical_subtract[lane_idx] ^ (do_round && !ftoi);
            assign {unnormalized_sum, _unused} = {fx2_significand_le[lane_idx], 1'b1}
                + {(fx2_significand_se[lane_idx] ^ {32{fx2_logical_subtract[lane_idx]}}), carry_in};

            always_ff @(posedge clk)
            begin
                fx3_result_inf[lane_idx] <= fx2_result_inf[lane_idx];
                fx3_result_nan[lane_idx] <= fx2_result_nan[lane_idx];
                fx3_equal[lane_idx] <= fx2_equal[lane_idx];
                fx3_equal[lane_idx] <= fx2_equal[lane_idx];
                fx3_ftoi_lshift[lane_idx] <= fx2_ftoi_lshift[lane_idx];

                // Addition
                fx3_add_significand[lane_idx] <= unnormalized_sum;
                fx3_add_exponent[lane_idx] <= fx2_add_exponent[lane_idx];
                fx3_logical_subtract[lane_idx] <= fx2_logical_subtract[lane_idx];
                fx3_add_result_sign[lane_idx] <= fx2_add_result_sign[lane_idx];

                // Multiplication
                fx3_significand_product[lane_idx] <= fx2_significand_product[lane_idx];
                fx3_mul_exponent[lane_idx] <= fx2_mul_exponent[lane_idx];
                fx3_mul_underflow[lane_idx] <= fx2_mul_underflow[lane_idx];
                fx3_mul_sign[lane_idx] <= fx2_mul_sign[lane_idx];
            end
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        fx3_instruction <= fx2_instruction;
        fx3_mask_value <= fx2_mask_value;
        fx3_thread_idx <= fx2_thread_idx;
        fx3_subcycle <= fx2_subcycle;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            fx3_instruction_valid <= '0;
        else
            fx3_instruction_valid <= fx2_instruction_valid;
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Floating Point Execute Stage 4
//
// Floating point addition/multiplication
// - Finds leading zero to determine how much to shift to normalize for
//   addition
// - Passes through multiplication result. Could have second stage of wallace
//   tree here.
//

module fp_execute_stage4(
    input                                       clk,
    input                                       reset,

    // From fp_execute_stage3
    input vector_mask_t                         fx3_mask_value,
    input                                       fx3_instruction_valid,
    input decoded_instruction_t                 fx3_instruction,
    input local_thread_idx_t                    fx3_thread_idx,
    input subcycle_t                            fx3_subcycle,
    input [NUM_VECTOR_LANES - 1:0]              fx3_result_inf,
    input [NUM_VECTOR_LANES - 1:0]              fx3_result_nan,
    input [NUM_VECTOR_LANES - 1:0]              fx3_equal,
    input [NUM_VECTOR_LANES - 1:0][5:0]         fx3_ftoi_lshift,

    // Floating point addition/subtraction
    input scalar_t[NUM_VECTOR_LANES - 1:0]      fx3_add_significand,
    input[NUM_VECTOR_LANES - 1:0][7:0]          fx3_add_exponent,
    input[NUM_VECTOR_LANES - 1:0]               fx3_add_result_sign,
    input[NUM_VECTOR_LANES - 1:0]               fx3_logical_subtract,

    // Floating point multiplication
    input [NUM_VECTOR_LANES - 1:0][63:0]        fx3_significand_product,
    input [NUM_VECTOR_LANES - 1:0][7:0]         fx3_mul_exponent,
    input [NUM_VECTOR_LANES - 1:0]              fx3_mul_underflow,
    input [NUM_VECTOR_LANES - 1:0]              fx3_mul_sign,

    // To fp_execute_stage5
    output logic                                fx4_instruction_valid,
    output decoded_instruction_t                fx4_instruction,
    output vector_mask_t                        fx4_mask_value,
    output local_thread_idx_t                   fx4_thread_idx,
    output subcycle_t                           fx4_subcycle,
    output logic [NUM_VECTOR_LANES - 1:0]       fx4_result_inf,
    output logic [NUM_VECTOR_LANES - 1:0]       fx4_result_nan,
    output logic [NUM_VECTOR_LANES - 1:0]       fx4_equal,

    // Floating point addition/subtraction
    output logic[NUM_VECTOR_LANES - 1:0][7:0]   fx4_add_exponent,
    output logic[NUM_VECTOR_LANES - 1:0][31:0]  fx4_add_significand,
    output logic[NUM_VECTOR_LANES - 1:0]        fx4_add_result_sign,
    output logic[NUM_VECTOR_LANES - 1:0]        fx4_logical_subtract,
    output logic[NUM_VECTOR_LANES - 1:0][5:0]   fx4_norm_shift,

    // Floating point multiplication
    output logic[NUM_VECTOR_LANES - 1:0][63:0]  fx4_significand_product,
    output logic[NUM_VECTOR_LANES - 1:0][7:0]   fx4_mul_exponent,
    output logic[NUM_VECTOR_LANES - 1:0]        fx4_mul_underflow,
    output logic[NUM_VECTOR_LANES - 1:0]        fx4_mul_sign);

    logic ftoi;

    assign ftoi = fx3_instruction.alu_op == OP_FTOI;

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_VECTOR_LANES; lane_idx++)
        begin : lane_logic_gen
            logic[5:0] leading_zeroes;

            // Determine normalization shift count for add/sub.
            always_comb
            begin
                // The 24th and 0th bit positions will get chopped already. The
                // normalization shift measures how far the value needs to be shifted to
                // make the leading one be truncated.
                leading_zeroes = 0;
                unique casez (fx3_add_significand[lane_idx])
                    32'b1???????????????????????????????: leading_zeroes = 0;
                    32'b01??????????????????????????????: leading_zeroes = 1;
                    32'b001?????????????????????????????: leading_zeroes = 2;
                    32'b0001????????????????????????????: leading_zeroes = 3;
                    32'b00001???????????????????????????: leading_zeroes = 4;
                    32'b000001??????????????????????????: leading_zeroes = 5;
                    32'b0000001?????????????????????????: leading_zeroes = 6;
                    32'b00000001????????????????????????: leading_zeroes = 7;
                    32'b000000001???????????????????????: leading_zeroes = 8;
                    32'b0000000001??????????????????????: leading_zeroes = 9;
                    32'b00000000001?????????????????????: leading_zeroes = 10;
                    32'b000000000001????????????????????: leading_zeroes = 11;
                    32'b0000000000001???????????????????: leading_zeroes = 12;
                    32'b00000000000001??????????????????: leading_zeroes = 13;
                    32'b000000000000001?????????????????: leading_zeroes = 14;
                    32'b0000000000000001????????????????: leading_zeroes = 15;
                    32'b00000000000000001???????????????: leading_zeroes = 16;
                    32'b000000000000000001??????????????: leading_zeroes = 17;
                    32'b0000000000000000001?????????????: leading_zeroes = 18;
                    32'b00000000000000000001????????????: leading_zeroes = 19;
                    32'b000000000000000000001???????????: leading_zeroes = 20;
                    32'b0000000000000000000001??????????: leading_zeroes = 21;
                    32'b00000000000000000000001?????????: leading_zeroes = 22;
                    32'b000000000000000000000001????????: leading_zeroes = 23;
                    32'b0000000000000000000000001???????: leading_zeroes = 24;
                    32'b00000000000000000000000001??????: leading_zeroes = 25;
                    32'b000000000000000000000000001?????: leading_zeroes = 26;
                    32'b0000000000000000000000000001????: leading_zeroes = 27;
                    32'b00000000000000000000000000001???: leading_zeroes = 28;
                    32'b000000000000000000000000000001??: leading_zeroes = 29;
                    32'b0000000000000000000000000000001?: leading_zeroes = 30;
                    32'b00000000000000000000000000000001: leading_zeroes = 31;
                    32'b00000000000000000000000000000000: leading_zeroes = 32;
                    default: leading_zeroes = 0;
                endcase
            end

            always_ff @(posedge clk)
            begin
                fx4_add_significand[lane_idx] <= fx3_add_significand[lane_idx];
                fx4_norm_shift[lane_idx] <= ftoi ? fx3_ftoi_lshift[lane_idx] : leading_zeroes;
                fx4_add_exponent[lane_idx] <= fx3_add_exponent[lane_idx];
                fx4_add_result_sign[lane_idx] <= fx3_add_result_sign[lane_idx];
                fx4_logical_subtract[lane_idx] <= fx3_logical_subtract[lane_idx];
                fx4_significand_product[lane_idx] <= fx3_significand_product[lane_idx];
                fx4_mul_exponent[lane_idx] <= fx3_mul_exponent[lane_idx];
                fx4_mul_underflow[lane_idx] <= fx3_mul_underflow[lane_idx];
                fx4_mul_sign[lane_idx] <= fx3_mul_sign[lane_idx];
                fx4_result_inf[lane_idx] <= fx3_result_inf[lane_idx];
                fx4_result_nan[lane_idx] <= fx3_result_nan[lane_idx];
                fx4_equal[lane_idx] <= fx3_equal[lane_idx];
            end
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        fx4_instruction <= fx3_instruction;
        fx4_mask_value <= fx3_mask_value;
        fx4_thread_idx <= fx3_thread_idx;
        fx4_subcycle <= fx3_subcycle;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            fx4_instruction_valid <= '0;
        else
            fx4_instruction_valid <= fx3_instruction_valid;
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Floating Point Execute Stage 5
//
// Floating point addition/multiplication
// - Normalization shift
// - Post normalization rounding (for addition overflow)
//

module fp_execute_stage5(
    input                                   clk,
    input                                   reset,

    // From fp_execute_stage4
    input vector_mask_t                     fx4_mask_value,
    input                                   fx4_instruction_valid,
    input decoded_instruction_t             fx4_instruction,
    input local_thread_idx_t                fx4_thread_idx,
    input subcycle_t                        fx4_subcycle,
    input [NUM_VECTOR_LANES - 1:0]          fx4_result_inf,
    input [NUM_VECTOR_LANES - 1:0]          fx4_result_nan,
    input [NUM_VECTOR_LANES - 1:0]          fx4_equal,

    // Floating point addition/subtraction
    input [NUM_VECTOR_LANES - 1:0][7:0]     fx4_add_exponent,
    input scalar_t[NUM_VECTOR_LANES - 1:0]  fx4_add_significand,
    input [NUM_VECTOR_LANES - 1:0]          fx4_add_result_sign,
    input [NUM_VECTOR_LANES - 1:0]          fx4_logical_subtract,
    input [NUM_VECTOR_LANES - 1:0][5:0]     fx4_norm_shift,

    // Floating point multiplication
    input [NUM_VECTOR_LANES - 1:0][63:0]    fx4_significand_product,
    input [NUM_VECTOR_LANES - 1:0][7:0]     fx4_mul_exponent,
    input [NUM_VECTOR_LANES - 1:0]          fx4_mul_underflow,
    input [NUM_VECTOR_LANES - 1:0]          fx4_mul_sign,

    // To writeback_stage
    output logic                            fx5_instruction_valid,
    output decoded_instruction_t            fx5_instruction,
    output vector_mask_t                    fx5_mask_value,
    output local_thread_idx_t               fx5_thread_idx,
    output subcycle_t                       fx5_subcycle,
    output vector_t                         fx5_result);

    logic fmul;
    logic imull;
    logic imulh;
    logic ftoi;

    assign fmul = fx4_instruction.alu_op == OP_MUL_F;
    assign imull = fx4_instruction.alu_op == OP_MULL_I;
    assign imulh = fx4_instruction.alu_op == OP_MULH_U || fx4_instruction.alu_op == OP_MULH_I;
    assign ftoi = fx4_instruction.alu_op == OP_FTOI;

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_VECTOR_LANES; lane_idx++)
        begin : lane_logic_gen
            logic[22:0] add_result_significand;
            logic[7:0] add_result_exponent;
            logic[7:0] adjusted_add_exponent;
            scalar_t shifted_significand;
            logic add_subnormal;
            scalar_t add_result;
            logic add_round;
            logic add_overflow;
            logic mul_normalize_shift;
            logic[22:0] mul_normalized_significand;
            logic[22:0] mul_rounded_significand;
            scalar_t fmul_result;
            logic[7:0] mul_exponent;
            logic mul_guard;
            logic mul_round;
            logic[21:0] mul_sticky_bits;
            logic mul_sticky;
            logic mul_round_tie;
            logic mul_round_up;
            logic mul_do_round;
            logic compare_result;
            logic sum_zero;
            logic mul_hidden_bit;
            logic mul_round_overflow;

            assign adjusted_add_exponent = fx4_add_exponent[lane_idx]
                - FLOAT32_EXP_WIDTH'(fx4_norm_shift[lane_idx]) + FLOAT32_EXP_WIDTH'(8);
            assign add_subnormal = fx4_add_exponent[lane_idx] == 0 || fx4_add_significand[lane_idx] == 0;
            assign shifted_significand = fx4_add_significand[lane_idx] << fx4_norm_shift[lane_idx];

            // Because this can only shift one bit out, can only round to even here.
            // shifted_significand[7] is the guard bit. shifted_significand[8] indicates whether
            // the result is even or odd.
            assign add_round = shifted_significand[7] && shifted_significand[8] && !fx4_logical_subtract[lane_idx];
            assign add_result_significand = add_subnormal ? fx4_add_significand[lane_idx][22:0]
                : (shifted_significand[30:8] + FLOAT32_SIG_WIDTH'(add_round));    // Round up using truncated bit
            assign add_result_exponent = add_subnormal ? '0 : adjusted_add_exponent;
            assign add_overflow = add_result_exponent == 8'hFF && !fx4_result_nan[lane_idx];

            always_comb
            begin
                if (fx4_result_inf[lane_idx] || add_overflow)
                    add_result = {fx4_add_result_sign[lane_idx], 8'hff, 23'd0};
                else if (fx4_result_nan[lane_idx])
                    add_result = {32'h7fffffff};
                else if (add_result_significand == 0 && add_subnormal)
                begin
                    // IEEE754-2008, 6.3: "When the sum of two operands with opposite signs
                    // (or the difference of two operands with like signs) is exactly zero,
                    // the sign of that sum (or difference) shall be +0.
                    // XXX this will pick up some additional cases like -0.0 + 0.0."
                    add_result = 0;
                end
                else
                    add_result = {fx4_add_result_sign[lane_idx], add_result_exponent, add_result_significand};
            end

            assign sum_zero = add_subnormal && add_result_significand == 0;

            // If the operation is unordered (either operand is NaN), treat the result as false
            always_comb
            begin
                unique case (fx4_instruction.alu_op)
                    OP_CMPGT_F: compare_result = !fx4_add_result_sign[lane_idx] && !fx4_equal[lane_idx] && !fx4_result_nan[lane_idx];
                    OP_CMPGE_F: compare_result = (!fx4_add_result_sign[lane_idx] || fx4_equal[lane_idx]) && !fx4_result_nan[lane_idx];
                    OP_CMPLT_F: compare_result = fx4_add_result_sign[lane_idx] && !fx4_equal[lane_idx] && !fx4_result_nan[lane_idx];
                    OP_CMPLE_F: compare_result = (fx4_add_result_sign[lane_idx] || fx4_equal[lane_idx]) && !fx4_result_nan[lane_idx];
                    OP_CMPEQ_F: compare_result = fx4_equal[lane_idx] && !fx4_result_nan[lane_idx];
                    OP_CMPNE_F: compare_result = !fx4_equal[lane_idx] || fx4_result_nan[lane_idx];
                    default: compare_result = 0;
                endcase
            end

            // If the operands for multiplication are both normalized (start with a leading 1), then the
            // the maximum normalization shift is one place.
            // XXX does not handle subnormal product
            assign mul_normalize_shift = !fx4_significand_product[lane_idx][47];
            assign {mul_normalized_significand, mul_guard, mul_round, mul_sticky_bits} = mul_normalize_shift
                ? {fx4_significand_product[lane_idx][45:0], 1'b0}
                : fx4_significand_product[lane_idx][46:0];
            assign mul_sticky = |mul_sticky_bits;
            assign mul_round_tie = mul_guard && !(mul_round || mul_sticky);
            assign mul_round_up = mul_guard && (mul_round || mul_sticky);
            assign mul_do_round = mul_round_up || (mul_round_tie && mul_normalized_significand[0]);
            assign mul_rounded_significand = mul_normalized_significand + FLOAT32_SIG_WIDTH'(mul_do_round);
            assign mul_hidden_bit = mul_normalize_shift ? fx4_significand_product[lane_idx][46] : 1'b1;
            assign mul_round_overflow = mul_do_round && mul_rounded_significand == 0;
            always_comb
            begin
                if (!mul_hidden_bit)
                    mul_exponent = 0;    // Is subnormal
                else if (mul_normalize_shift && !mul_round_overflow)
                    mul_exponent = fx4_mul_exponent[lane_idx];
                else
                    mul_exponent = fx4_mul_exponent[lane_idx] + FLOAT32_EXP_WIDTH'(1);
            end

            always_comb
            begin
                if (fx4_result_inf[lane_idx])
                    fmul_result = {fx4_mul_sign[lane_idx], 8'hff, 23'd0};
                else if (fx4_result_nan[lane_idx])
                    fmul_result = {32'h7fffffff};
                else
                    fmul_result = {fx4_mul_sign[lane_idx], mul_exponent, mul_rounded_significand};
            end

            always_ff @(posedge clk)
            begin
                if (ftoi)
                begin
                    if (fx4_result_nan[lane_idx])
                        fx5_result[lane_idx] <= 32'h80000000;    // nan signal indicates an invalid conversion
                    else
                        fx5_result[lane_idx] <= shifted_significand;
                end
                else if (fx4_instruction.compare)
                    fx5_result[lane_idx] <= scalar_t'(compare_result);
                else if (imull)
                    fx5_result[lane_idx] <= fx4_significand_product[lane_idx][31:0];
                else if (imulh)
                    fx5_result[lane_idx] <= fx4_significand_product[lane_idx][63:32];
                else if (fmul)
                    fx5_result[lane_idx] <= fx4_mul_underflow[lane_idx] ? 32'h00000000 : fmul_result;
                else
                    fx5_result[lane_idx] <= add_result;
            end
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        fx5_instruction <= fx4_instruction;
        fx5_mask_value <= fx4_mask_value;
        fx5_thread_idx <= fx4_thread_idx;
        fx5_subcycle <= fx4_subcycle;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            fx5_instruction_valid <= '0;
        else
            fx5_instruction_valid <= fx4_instruction_valid;
    end
endmodule
//
// Copyright 2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// General Purpose Input/Output
// Bidirectional pins that can be driven and read
//
module gpio_controller
    #(parameter BASE_ADDRESS = 0,
    parameter NUM_PINS = 8,
    parameter ENABLE_SYNCHRONIZER = 0)

    (input                      clk,
    input                      reset,
    io_bus_interface.slave    io_bus,

    // To/from SD card
    inout[NUM_PINS - 1:0]     gpio_value);

    localparam DIRECTION_REG = BASE_ADDRESS;
    localparam VALUE_REG = BASE_ADDRESS + 4;

    logic[NUM_PINS - 1:0] direction;
    logic[NUM_PINS - 1:0] output_value;

    genvar pin_idx;
    generate
        for (pin_idx = 0; pin_idx < NUM_PINS; pin_idx++)
        begin : pin_dir_gen
            assign gpio_value[pin_idx] = direction[pin_idx]
                ? output_value[pin_idx] : 1'bZ;
        end
    endgenerate

    generate
        if (ENABLE_SYNCHRONIZER)
        begin
            synchronizer #(.WIDTH(NUM_PINS)) input_synchronizer(
                .data_o(io_bus.read_data),
                .data_i(gpio_value),
                .*);
        end
        else
        begin
            always_ff @(posedge clk)
                io_bus.read_data <= gpio_value;
        end
    endgenerate

    always_ff @(posedge reset, posedge clk)
    begin
        if (reset)
        begin
            direction <= 0;
            output_value <= 0;
        end
        else if (io_bus.write_en)
        begin
            if (io_bus.address == DIRECTION_REG)
                direction <= io_bus.write_data[NUM_PINS - 1:0];
            else if (io_bus.address == VALUE_REG)
                output_value <= io_bus.write_data[NUM_PINS - 1:0];
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Convert a binary index to a one hot signal (Binary encoder)
// If DIRECTION is "LSB0", index 0 is the least significant bit
// If "MSB0", index 0 is the most significant bit
//

module idx_to_oh
    #(parameter NUM_SIGNALS = 4,
    parameter DIRECTION = "LSB0",
    parameter INDEX_WIDTH = $clog2(NUM_SIGNALS))

    (output logic[NUM_SIGNALS - 1:0]       one_hot,
    input [INDEX_WIDTH - 1:0]              index);

    always_comb
    begin : convert
        one_hot = 0;
        if (DIRECTION == "LSB0")
            one_hot[index] = 1'b1;
        else
            one_hot[NUM_SIGNALS - 32'(index) - 1] = 1'b1;
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

////`include "defines.svh"

import defines::*;

//
// Instruction Pipeline - Instruction Fetch Data Stage
// - If PC selected in the ifetch_tag_stage is in the instruction cache, reads
//   the contents of the cache line.
// - Drives signals to update LRU in previous stage
// - Detects alignment fault and TLB misses.
//

module ifetch_data_stage(
    input                            clk,
    input                            reset,

    // From ifetch_tag_stage.
    // If ift_instruction_requested is low, the other signals in this group are
    // undefined.
    input                            ift_instruction_requested,
    input l1i_addr_t                 ift_pc_paddr,
    input scalar_t                   ift_pc_vaddr,
    input local_thread_idx_t         ift_thread_idx,
    input                            ift_tlb_hit,
    input                            ift_tlb_present,
    input                            ift_tlb_executable,
    input                            ift_tlb_supervisor,
    input l1i_tag_t                  ift_tag[`L1I_WAYS],
    input                            ift_valid[`L1I_WAYS],

    // To ifetch_tag_stage
    output logic                     ifd_update_lru_en,
    output l1i_way_idx_t             ifd_update_lru_way,
    output logic                     ifd_near_miss,

    // From l1_l2_interface
    input                            l2i_idata_update_en,
    input l1i_way_idx_t              l2i_idata_update_way,
    input l1i_set_idx_t              l2i_idata_update_set,
    input cache_line_data_t          l2i_idata_update_data,
    input [`L1I_WAYS - 1:0]          l2i_itag_update_en,
    input l1i_set_idx_t              l2i_itag_update_set,
    input l1i_tag_t                  l2i_itag_update_tag,

    // To l1_l2_interface
    output logic                     ifd_cache_miss,
    output cache_line_index_t        ifd_cache_miss_paddr,
    output local_thread_idx_t        ifd_cache_miss_thread_idx,    // also to ifetch_tag

    // From control registers
    input logic                      cr_supervisor_en[`THREADS_PER_CORE],

    // To instruction_decode_stage
    output scalar_t                  ifd_instruction,
    output logic                     ifd_instruction_valid,
    output scalar_t                  ifd_pc,
    output local_thread_idx_t        ifd_thread_idx,
    output logic                     ifd_alignment_fault,
    output logic                     ifd_tlb_miss,
    output logic                     ifd_supervisor_fault,
    output logic                     ifd_page_fault,
    output logic                     ifd_executable_fault,
    output logic                     ifd_inst_injected,

    // From writeback_stage
    input                            wb_rollback_en,
    input local_thread_idx_t         wb_rollback_thread_idx,

    // To performance_counters
    output logic                     ifd_perf_icache_hit,
    output logic                     ifd_perf_icache_miss,
    output logic                     ifd_perf_itlb_miss,

    // from core
    input                            core_selected_debug,

    // From on_chip_debugger
    input                            ocd_halt,
    input scalar_t                   ocd_inject_inst,
    input logic                      ocd_inject_en,
    input local_thread_idx_t         ocd_thread);

    logic cache_hit;
    logic[`L1I_WAYS - 1:0] way_hit_oh;
    l1i_way_idx_t way_hit_idx;
    logic[CACHE_LINE_BITS - 1:0] fetched_cache_line;
    scalar_t fetched_word;
    logic[$clog2(CACHE_LINE_WORDS) - 1:0] cache_lane_idx;
    logic alignment_fault;
    logic squash_instruction;
    logic ocd_halt_latched;

    assign squash_instruction = wb_rollback_en && wb_rollback_thread_idx
        == ift_thread_idx;

    //
    // Check for cache hit
    //
    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < `L1I_WAYS; way_idx++)
        begin : hit_check_gen
            assign way_hit_oh[way_idx] = ift_pc_paddr.tag == ift_tag[way_idx]
                && ift_valid[way_idx];
        end
    endgenerate

    assign cache_hit = |way_hit_oh && ift_tlb_hit;

    oh_to_idx #(.NUM_SIGNALS(`L1I_WAYS)) oh_to_idx_hit_way(
        .one_hot(way_hit_oh),
        .index(way_hit_idx));

    // ifd_near_miss is high if the cache line requested in the last stage
    // is filled this cycle. Treating this as a cache miss would fetch
    // duplicate lines into the cache set. Blocking the thread would hang
    // (because the wakeup signal is happening this cycle). The cache interface
    // updates the tag, then the data a cycle later, so the data will appear in
    // the next cycle. In order to pick up the data, this signal goes back to
    // the previous stage to make it retry the same PC.
    assign ifd_near_miss = !cache_hit
        && ift_tlb_hit
        && ift_instruction_requested
        && |l2i_itag_update_en
        && l2i_itag_update_set == ift_pc_paddr.set_idx
        && l2i_itag_update_tag == ift_pc_paddr.tag;
    assign ifd_cache_miss = !cache_hit
        && ift_tlb_hit
        && ift_instruction_requested
        && !ifd_near_miss
        && !squash_instruction;
    assign ifd_cache_miss_paddr = {ift_pc_paddr.tag, ift_pc_paddr.set_idx};
    assign ifd_cache_miss_thread_idx = ift_thread_idx;
    assign alignment_fault = ift_pc_paddr[1:0] != 0;

    //
    // Cache data
    //
    sram_1r1w #(
        .DATA_WIDTH(CACHE_LINE_BITS),
        .SIZE(`L1I_WAYS * `L1I_SETS),
        .READ_DURING_WRITE("NEW_DATA")
    ) sram_l1i_data(
        .read_en(cache_hit && ift_instruction_requested),
        .read_addr({way_hit_idx, ift_pc_paddr.set_idx}),
        .read_data(fetched_cache_line),
        .write_en(l2i_idata_update_en),
        .write_addr({l2i_idata_update_way, l2i_idata_update_set}),
        .write_data(l2i_idata_update_data),
        .*);

    assign cache_lane_idx = ~ifd_pc[CACHE_LINE_OFFSET_WIDTH - 1:2];
    assign fetched_word = fetched_cache_line[32 * cache_lane_idx+:32];
    assign ifd_instruction = ocd_halt_latched
        ? ocd_inject_inst
        : {fetched_word[7:0], fetched_word[15:8], fetched_word[23:16], fetched_word[31:24]};

    assign ifd_update_lru_en = cache_hit && ift_instruction_requested;
    assign ifd_update_lru_way = way_hit_idx;

    always_ff @(posedge clk)
    begin
        ifd_pc <= ift_pc_vaddr;
        ifd_thread_idx <= ocd_halt ? ocd_thread : ift_thread_idx;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            ifd_alignment_fault <= '0;
            ifd_executable_fault <= '0;
            ifd_inst_injected <= '0;
            ifd_instruction_valid <= '0;
            ifd_page_fault <= '0;
            ifd_perf_icache_hit <= '0;
            ifd_perf_icache_miss <= '0;
            ifd_perf_itlb_miss <= '0;
            ifd_supervisor_fault <= '0;
            ifd_tlb_miss <= '0;
            ocd_halt_latched <= '0;
            // End of automatics
        end
        else
        begin
            // Ensure more than one way isn't a hit (way_hit_oh is undefined
            // if an instruction wasn't requested).
            assert(!ift_instruction_requested || $onehot0(way_hit_oh));

            ocd_halt_latched <= ocd_halt;
            if (ocd_halt)
            begin
                ifd_instruction_valid <= ocd_inject_en && core_selected_debug;
                ifd_inst_injected <= 1;
                ifd_alignment_fault <= 0;
                ifd_supervisor_fault <= 0;
                ifd_tlb_miss <= 0;
                ifd_page_fault <= 0;
                ifd_executable_fault <= 0;
            end
            else
            begin
                // ifd_instruction_valid should be ignored if any of the other
                // fault signals are set.
                ifd_instruction_valid <= ift_instruction_requested && !squash_instruction
                    && cache_hit && ift_tlb_hit;
                ifd_inst_injected <= 0;
                ifd_alignment_fault <= ift_instruction_requested && !squash_instruction
                    && alignment_fault;
                ifd_supervisor_fault <= ift_instruction_requested && !squash_instruction
                    && ift_tlb_hit && ift_tlb_present && ift_tlb_supervisor
                    && !cr_supervisor_en[ift_thread_idx];
                ifd_tlb_miss <= ift_instruction_requested && !squash_instruction
                    && !ift_tlb_hit;
                ifd_page_fault <= ift_instruction_requested && !squash_instruction
                    && ift_tlb_hit && !ift_tlb_present;
                ifd_executable_fault <= ift_instruction_requested && !squash_instruction
                    && ift_tlb_hit && ift_tlb_present && !ift_tlb_executable;

                // These faults can't occur together. The first require
                // a TLB entry to read the bits, the second require a page to be present.
                assert(!ifd_tlb_miss || !ifd_supervisor_fault);
                assert(!ifd_tlb_miss || !ifd_page_fault);
                assert(!ifd_tlb_miss || !ifd_executable_fault);
                assert(!ifd_tlb_miss || !ifd_instruction_valid);
                assert(!ifd_page_fault || !ifd_supervisor_fault);
                assert(!ifd_page_fault || !ifd_executable_fault);

                // Perf counters
                ifd_perf_icache_hit <= cache_hit && ift_instruction_requested;
                ifd_perf_icache_miss <= !cache_hit
                    && ift_tlb_hit
                    && ift_instruction_requested
                    && !squash_instruction;
                ifd_perf_itlb_miss <= ift_instruction_requested && !ift_tlb_hit;
            end
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Instruction Pipeline - Instruction Fetch Tag Stage
// - Selects a program counter from one of the threads to fetch from the
//   instruction cache. It tries to fetch an instruction from a different
//   thread every cycle whenever possible.
// - Reads instruction cache tag memory to determine if the cache line is
//   resident.
// - Reads translation lookaside buffer to translate from virtual to physical
//   address.
//

module ifetch_tag_stage
    #(parameter RESET_PC = 0)

    (input                              clk,
    input                               reset,

    // From ifetch_data_stage
    input                               ifd_update_lru_en,
    input l1i_way_idx_t                 ifd_update_lru_way,
    input                               ifd_cache_miss,
    input                               ifd_near_miss,
    input local_thread_idx_t            ifd_cache_miss_thread_idx,

    // To ifetch_data_stage
    output logic                        ift_instruction_requested,
    output l1i_addr_t                   ift_pc_paddr,
    output scalar_t                     ift_pc_vaddr,
    output local_thread_idx_t           ift_thread_idx,
    output logic                        ift_tlb_hit,
    output logic                        ift_tlb_present,
    output logic                        ift_tlb_executable,
    output logic                        ift_tlb_supervisor,
    output l1i_tag_t                    ift_tag[`L1I_WAYS],
    output logic                        ift_valid[`L1I_WAYS],

    // From l1_l2_interface
    input                               l2i_icache_lru_fill_en,
    input l1i_set_idx_t                 l2i_icache_lru_fill_set,
    input [`L1I_WAYS - 1:0]             l2i_itag_update_en,
    input l1i_set_idx_t                 l2i_itag_update_set,
    input l1i_tag_t                     l2i_itag_update_tag,
    input                               l2i_itag_update_valid,
    input local_thread_bitmap_t         l2i_icache_wake_bitmap,
    output l1i_way_idx_t                ift_fill_lru,

    // From control_registers
    input                               cr_mmu_en[`THREADS_PER_CORE],
    input [ASID_WIDTH - 1:0]            cr_current_asid[`THREADS_PER_CORE],

    // From dcache_tag_stage
    input                               dt_invalidate_tlb_en,
    input                               dt_invalidate_tlb_all_en,
    input [ASID_WIDTH - 1:0]            dt_update_itlb_asid,
    input page_index_t                  dt_update_itlb_vpage_idx,
    input                               dt_update_itlb_en,
    input                               dt_update_itlb_supervisor,
    input                               dt_update_itlb_global,
    input                               dt_update_itlb_present,
    input                               dt_update_itlb_executable,
    input page_index_t                  dt_update_itlb_ppage_idx,

    // From writeback_stage
    input                               wb_rollback_en,
    input local_thread_idx_t            wb_rollback_thread_idx,
    input scalar_t                      wb_rollback_pc,

    // From thread_select_stage
    input local_thread_bitmap_t         ts_fetch_en,

    // From on_chip_debugger
    input                               ocd_halt,
    input local_thread_idx_t            ocd_thread);

    scalar_t next_program_counter[`THREADS_PER_CORE];
    local_thread_idx_t selected_thread_idx;
    scalar_t last_selected_pc;
    l1i_addr_t pc_to_fetch;
    local_thread_bitmap_t can_fetch_thread_bitmap;
    local_thread_bitmap_t selected_thread_oh;
    local_thread_bitmap_t last_selected_thread_oh;
    local_thread_bitmap_t icache_wait_threads;
    local_thread_bitmap_t icache_wait_threads_nxt;
    local_thread_bitmap_t cache_miss_thread_oh;
    local_thread_bitmap_t thread_sleep_mask_oh;
    logic cache_fetch_en;
    page_index_t tlb_ppage_idx;
    page_index_t ppage_idx;
    logic tlb_hit;
    logic tlb_supervisor;
    logic tlb_present;
    logic tlb_executable;
    page_index_t request_vpage_idx;
    logic[ASID_WIDTH - 1:0] request_asid;

    initial
    begin
        assert((`L1I_SETS & (`L1I_SETS - 1)) == 0);
    end

    //
    // Pick which thread to fetch next.
    // Only consider threads that are not blocked, but do not skip threads that
    // are being rolled back in the current cycle because the rollback signals
    // have a long combinational path that is a critical path for clock speed.
    // Instead, when the selected thread is rolled back in the same cycle,
    // invalidate the instruction by deasserting ift_instruction_requested. This
    // wastes a cycle, but should be infrequent.
    //
    assign can_fetch_thread_bitmap = ts_fetch_en & ~icache_wait_threads;

    // If an instruction is updating the TLB, can't access it to translate the next
    // address, so skip instruction fetch this cycle.
    assign cache_fetch_en = |can_fetch_thread_bitmap && !dt_update_itlb_en
        && !dt_invalidate_tlb_en && !dt_invalidate_tlb_all_en
        && !ocd_halt;

    rr_arbiter #(.NUM_REQUESTERS(`THREADS_PER_CORE)) thread_select_arbiter(
        .request(can_fetch_thread_bitmap),
        .update_lru(cache_fetch_en),
        .grant_oh(selected_thread_oh),
        .*);

    oh_to_idx #(.NUM_SIGNALS(`THREADS_PER_CORE)) oh_to_idx_selected_thread(
        .one_hot(selected_thread_oh),
        .index(selected_thread_idx));

    //
    // Program counter update logic
    //
    genvar thread_idx;
    generate
        for (thread_idx = 0; thread_idx < `THREADS_PER_CORE; thread_idx++)
        begin : pc_logic_gen
            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                    next_program_counter[thread_idx] <= RESET_PC;
                else if (wb_rollback_en && wb_rollback_thread_idx == local_thread_idx_t'(thread_idx))
                    next_program_counter[thread_idx] <= wb_rollback_pc;
                else if ((ifd_cache_miss || ifd_near_miss) && last_selected_thread_oh[thread_idx])
                    next_program_counter[thread_idx] <= next_program_counter[thread_idx] - 4;
                else if (selected_thread_oh[thread_idx] && cache_fetch_en)
                    next_program_counter[thread_idx] <= next_program_counter[thread_idx] + 4;
            end
        end
    endgenerate

    assign pc_to_fetch = next_program_counter[ocd_halt ? ocd_thread : selected_thread_idx];

    //
    // Cache way metadata
    //
    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < `L1I_WAYS; way_idx++)
        begin : way_tag_gen
            // Valid flags are flops instead of SRAM because they need
            // to simultaneously be cleared on reset.
            logic line_valid[`L1I_SETS];

            sram_1r1w #(
                .DATA_WIDTH($bits(l1i_tag_t)),
                .SIZE(`L1I_SETS),
                .READ_DURING_WRITE("NEW_DATA")
            ) sram_tags(
                .read_en(cache_fetch_en),
                .read_addr(pc_to_fetch.set_idx),
                .read_data(ift_tag[way_idx]),
                .write_en(l2i_itag_update_en[way_idx]),
                .write_addr(l2i_itag_update_set),
                .write_data(l2i_itag_update_tag),
                .*);

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                begin
                    for (int set_idx = 0; set_idx < `L1I_SETS; set_idx++)
                        line_valid[set_idx] <= 0;
                end
                else
                begin
                    if (l2i_itag_update_en[way_idx])
                        line_valid[l2i_itag_update_set] <= l2i_itag_update_valid;
                end
            end

            always_ff @(posedge clk)
            begin
                // Fetch cache line state for pipeline
                if (l2i_itag_update_en[way_idx] && l2i_itag_update_set == pc_to_fetch.set_idx)
                    ift_valid[way_idx] <= l2i_itag_update_valid;    // Bypass
                else
                    ift_valid[way_idx] <= line_valid[pc_to_fetch.set_idx];
            end
        end
    endgenerate

    // TLB inputs
    always_comb
    begin
        if (cache_fetch_en)
        begin
            request_vpage_idx = pc_to_fetch[31-:PAGE_NUM_BITS];
            request_asid = cr_current_asid[selected_thread_idx];
        end
        else
        begin
            request_vpage_idx = dt_update_itlb_vpage_idx;
            request_asid = dt_update_itlb_asid;
        end
    end

    tlb #(
        .NUM_ENTRIES(`DTLB_ENTRIES),
        .NUM_WAYS(`TLB_WAYS)
    ) itlb(
        .lookup_en(cache_fetch_en),
        .update_en(dt_update_itlb_en),
        .update_present(dt_update_itlb_present),
        .update_exe_writable(dt_update_itlb_executable),
        .update_supervisor(dt_update_itlb_supervisor),
        .update_global(dt_update_itlb_global),
        .invalidate_en(dt_invalidate_tlb_en),
        .invalidate_all_en(dt_invalidate_tlb_all_en),
        .update_ppage_idx(dt_update_itlb_ppage_idx),
        .lookup_ppage_idx(tlb_ppage_idx),
        .lookup_hit(tlb_hit),
        .lookup_exe_writable(tlb_executable),
        .lookup_present(tlb_present),
        .lookup_supervisor(tlb_supervisor),
        .*);

    // These combinational signals are after the output flops of this stage (and
    // the TLB has one cycle of latency). All inputs to this should be registered.
    always_comb
    begin
        if (cr_mmu_en[ift_thread_idx])
        begin
            ift_tlb_hit = tlb_hit;
            ift_tlb_present = tlb_present;
            ift_tlb_executable = tlb_executable;
            ift_tlb_supervisor = tlb_supervisor;
            ppage_idx = tlb_ppage_idx;
        end
        else
        begin
            // Address translation disabled, use identity mapping.
            ift_tlb_hit = 1;
            ift_tlb_present = 1;
            ift_tlb_executable = 1;
            ift_tlb_supervisor = 0;
            ppage_idx = last_selected_pc[31-:PAGE_NUM_BITS];
        end
    end

    cache_lru #(
        .NUM_WAYS(`L1I_WAYS),
        .NUM_SETS(`L1I_SETS)
    ) cache_lru(
        .fill_en(l2i_icache_lru_fill_en),
        .fill_set(l2i_icache_lru_fill_set),
        .fill_way(ift_fill_lru),
        .access_en(cache_fetch_en),
        .access_set(pc_to_fetch.set_idx),
        .update_en(ifd_update_lru_en),
        .update_way(ifd_update_lru_way),
        .*);

    //
    // Track which threads are waiting on instruction cache misses. Avoid fetching
    // them until the L2 cache fills the miss. If a rollback occurs while a thread
    // is waiting, wait until that miss to be filled by the L2 cache. This avoids
    // a race condition that would occur when that response subsequently arrived.
    //
    idx_to_oh #(.NUM_SIGNALS(`THREADS_PER_CORE)) idx_to_oh_miss_thread(
        .one_hot(cache_miss_thread_oh),
        .index(ifd_cache_miss_thread_idx));

    assign thread_sleep_mask_oh = cache_miss_thread_oh & {`THREADS_PER_CORE{ifd_cache_miss}};
    assign icache_wait_threads_nxt = (icache_wait_threads | thread_sleep_mask_oh)
        & ~l2i_icache_wake_bitmap;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            icache_wait_threads <= '0;
            ift_instruction_requested <= '0;
            // End of automatics
        end
        else
        begin
            icache_wait_threads <= icache_wait_threads_nxt;
            ift_instruction_requested <= cache_fetch_en
                && !((ifd_cache_miss || ifd_near_miss) && ifd_cache_miss_thread_idx == selected_thread_idx)
                && !(wb_rollback_en && wb_rollback_thread_idx == selected_thread_idx);
        end
    end

    always_ff @(posedge clk)
    begin
        last_selected_pc <= pc_to_fetch;
        ift_thread_idx <= selected_thread_idx;
        last_selected_thread_oh <= selected_thread_oh;
    end

    assign ift_pc_paddr = {ppage_idx, last_selected_pc[31 - PAGE_NUM_BITS:0]};
    assign ift_pc_vaddr = last_selected_pc;
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Instruction Pipeline - Instruction Decode Stage
// Populate the decoded_instruction_t structure with fields from
// the instruction. The structure contains control fields will be
// used later in the pipeline.
//
// This also handles interrupts. When an interrupt is pending, an existing
// instruction is replaced with one that has the trap flag set. This works
// similar to the way traps from earlier stages in the pipeline are handled
// and is necessary to make sure interrupts are precise (from the software
// perspective, the interrupt appears  to occur on a boundary between two
// instructions, with every prior instruction executing, and every subsequent
// instruction not). We must do it this way because:
// - Instructions can retire out of order
// - There may be pending instructions in the pipeline for the thread that
//   will cause a rollback in a subsequent cycle.
//
// Register port to operand mapping
//                                               store
//       format           op1     op2    mask    value
// +-------------------+-------+-------+-------+-------+
// | R - scalar/scalar |   s1  |   s2  |       |       |
// | R - vector/scalar |   v1  |   s2  |  s1   |       |
// | R - vector/vector |   v1  |   v2  |  s2   |       |
// | I - scalar        |   s1  |  imm  |  n/a  |       |
// | I - vector        |   v1  |  imm  |  s2   |       |
// | M - scalar        |   s1  |  imm  |  n/a  |  s2   |
// | M - block         |   s1  |  imm  |  s2   |  v2   |
// | M - scatter/gather|   v1  |  imm  |  s2   |  v2   |
// | C                 |   s1  |  imm  |       |       |
// | B                 |   s1  |       |       |       |
// +-------------------+-------+-------+-------+-------+
//

module instruction_decode_stage(
    input                         clk,
    input                         reset,

    // From ifetch_data_stage
    input                         ifd_instruction_valid,
    input scalar_t                ifd_instruction,
    input                         ifd_inst_injected,
    input scalar_t                ifd_pc,
    input local_thread_idx_t      ifd_thread_idx,
    input                         ifd_alignment_fault,
    input                         ifd_supervisor_fault,
    input                         ifd_page_fault,
    input                         ifd_executable_fault,
    input                         ifd_tlb_miss,

    // From dcache_data_stage
    input local_thread_bitmap_t   dd_load_sync_pending,

    // From l1_l2_interface
    input local_thread_bitmap_t   sq_store_sync_pending,

    // To thread_select_stage
    output decoded_instruction_t  id_instruction,
    output logic                  id_instruction_valid,
    output local_thread_idx_t     id_thread_idx,

    // From io_request_queue
    input local_thread_bitmap_t   ior_pending,

    // From control_registers
    input local_thread_bitmap_t   cr_interrupt_en,
    input local_thread_bitmap_t   cr_interrupt_pending,

    // From on_chip_debugger
    input                         ocd_halt,

    // From writeback_stage
    input                         wb_rollback_en,
    input local_thread_idx_t      wb_rollback_thread_idx);

    localparam T = 1'b1;
    localparam F = 1'b0;

    typedef enum logic[2:0] {
        IMM_ZERO,
        IMM_23_15,  // Masked immediate arithmetic
        IMM_23_10,  // Unmasked immediate arithmetic
        IMM_24_15,  // Masked memory access
        IMM_24_10,  // Unmasked memory access
        IMM_24_5,   // Small branch offset (multiply by four)
        IMM_24_0,   // Large branch offset (multiply by four)
        IMM_EXT_19  // 19 bit extended immediate value
    } imm_loc_t;

    typedef enum logic[1:0] {
        SCLR1_NONE,
        SCLR1_14_10,
        SCLR1_4_0
    } scalar1_loc_t;

    typedef enum logic[2:0] {
        SCLR2_NONE,
        SCLR2_19_15,
        SCLR2_14_10,
        SCLR2_9_5
    } scalar2_loc_t;

    struct packed {
        logic illegal;
        logic dest_vector;
        logic has_dest;
        imm_loc_t imm_loc;
        scalar1_loc_t scalar1_loc;
        scalar2_loc_t scalar2_loc;
        logic has_vector1;
        logic has_vector2;
        logic vector_sel2_9_5;    // Else is src2. Only for stores.
        logic op1_vector;
        op2_src_t op2_src;
        mask_src_t mask_src;
        logic store_value_vector;
        logic call;
    } dlut_out;

    decoded_instruction_t decoded_instr_nxt;
    logic nop;
    logic fmt_r;
    logic fmt_i;
    logic fmt_m;
    logic getlane;
    logic compare;
    alu_op_t alu_op;
    memory_op_t memory_access_type;
    register_idx_t scalar_sel2;
    logic has_trap;
    logic syscall;
    logic breakpoint;
    logic raise_interrupt;
    local_thread_bitmap_t masked_interrupt_flags;
    logic unary_arith;

    // I originally tried to structure the instruction set so that this could
    // determine the format of the instruction from the first 7 bits. Those
    // index into this ROM table that returns the decoded information. This
    // has become less true as the instruction set has evolved. Also, synthesis
    // tools just turn this into random logic. Should revisit this at some point.
    always_comb
    begin
        unique casez (ifd_instruction[31:25])
            // Format R (register arithmetic)
            7'b110_000_?: dlut_out = {F, F, T, IMM_ZERO, SCLR1_4_0, SCLR2_19_15,   F, F, F, F, OP2_SRC_SCALAR2, MASK_SRC_ALL_ONES, F, F};
            7'b110_001_?: dlut_out = {F, T, T, IMM_ZERO, SCLR1_4_0, SCLR2_19_15,   T, F, F, T, OP2_SRC_SCALAR2, MASK_SRC_ALL_ONES, F, F};
            7'b110_010_?: dlut_out = {F, T, T, IMM_ZERO, SCLR1_14_10, SCLR2_19_15, T, F, F, T, OP2_SRC_SCALAR2, MASK_SRC_SCALAR1, F, F};
            7'b110_100_?: dlut_out = {F, T, T, IMM_ZERO, SCLR1_14_10, SCLR2_NONE,  T, T, F, T, OP2_SRC_VECTOR2, MASK_SRC_ALL_ONES, F, F};
            7'b110_101_?: dlut_out = {F, T, T, IMM_ZERO, SCLR1_4_0, SCLR2_14_10,   T, T, F, T, OP2_SRC_VECTOR2, MASK_SRC_SCALAR2, F, F};

            // Format I (immediate arithmetic)
            7'b0_00_????: dlut_out = {F, F, T, IMM_23_10, SCLR1_4_0, SCLR2_NONE,   F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b0_01_????: dlut_out = {F, T, T, IMM_23_10, SCLR1_4_0, SCLR2_NONE,   T, F, F, T, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b0_10_????: dlut_out = {F, F, T, IMM_EXT_19, SCLR1_4_0, SCLR2_NONE,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b0_11_????: dlut_out = {F, T, T, IMM_23_15, SCLR1_4_0, SCLR2_14_10,  T, F, F, T, OP2_SRC_IMMEDIATE, MASK_SRC_SCALAR2, F, F};

            // Format M (memory)
            // Store
            7'b10_0_0000: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_9_5,     F, F, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_0_0001: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_9_5,     F, F, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_0_0010: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_9_5,     T, F, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_0_0011: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_9_5,     F, F, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_0_0100: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_9_5,     F, F, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_0_0101: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_9_5,     F, F, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_0_0110: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_9_5,     F, F, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_0_0111: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    F, T, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, T, F};
            7'b10_0_1000: dlut_out = {F, F, F, IMM_24_15, SCLR1_4_0, SCLR2_14_10, F, T, T, F, OP2_SRC_IMMEDIATE, MASK_SRC_SCALAR2, T, F};
            7'b10_0_1101: dlut_out = {F, F, F, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, T, T, T, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, T, F};
            7'b10_0_1110: dlut_out = {F, F, F, IMM_24_15, SCLR1_4_0, SCLR2_14_10, T, T, T, T, OP2_SRC_IMMEDIATE, MASK_SRC_SCALAR2, T, F};

            // Load
            7'b10_1_0000: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_0001: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_0010: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_0011: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_0100: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_0101: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_0110: dlut_out = {F, F, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_0111: dlut_out = {F, T, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_1000: dlut_out = {F, T, T, IMM_24_15, SCLR1_4_0, SCLR2_14_10, T, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_SCALAR2, F, F};
            7'b10_1_1101: dlut_out = {F, T, T, IMM_24_10, SCLR1_4_0, SCLR2_NONE,    T, T, F, T, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b10_1_1110: dlut_out = {F, T, T, IMM_24_15, SCLR1_4_0, SCLR2_14_10, T, T, F, T, OP2_SRC_IMMEDIATE, MASK_SRC_SCALAR2, F, F};

            // Format C (cache control)
            7'b1110_000: dlut_out = {F, F, F,  IMM_24_15, SCLR1_4_0, SCLR2_9_5,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1110_001: dlut_out = {F, F, F,  IMM_24_15, SCLR1_4_0, SCLR2_NONE,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1110_010: dlut_out = {F, F, F,  IMM_24_15, SCLR1_4_0, SCLR2_NONE,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1110_011: dlut_out = {F, F, F,  IMM_24_15, SCLR1_4_0, SCLR2_NONE,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1110_100: dlut_out = {F, F, F,  IMM_24_15, SCLR1_NONE, SCLR2_NONE, F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1110_101: dlut_out = {F, F, F,  IMM_24_15, SCLR1_4_0, SCLR2_NONE,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1110_110: dlut_out = {F, F, F,  IMM_24_15, SCLR1_NONE, SCLR2_NONE, F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1110_111: dlut_out = {F, F, F,  IMM_24_15, SCLR1_4_0, SCLR2_9_5,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};

            // Format B (branch)
            7'b1111_000: dlut_out = {F, F, F, IMM_24_5, SCLR1_4_0, SCLR2_NONE,   F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1111_001: dlut_out = {F, F, F, IMM_24_5, SCLR1_4_0, SCLR2_NONE,   F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1111_010: dlut_out = {F, F, F, IMM_24_5, SCLR1_4_0, SCLR2_NONE,   F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1111_011: dlut_out = {F, F, F, IMM_24_0, SCLR1_NONE, SCLR2_NONE,  F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
            7'b1111_100: dlut_out = {F, F, T, IMM_24_0, SCLR1_NONE, SCLR2_NONE,  F, F, F, F, OP2_SRC_SCALAR2, MASK_SRC_ALL_ONES, F, T};
            7'b1111_110: dlut_out = {F, F, T, IMM_24_5, SCLR1_4_0, SCLR2_NONE,   F, F, F, F, OP2_SRC_SCALAR2, MASK_SRC_ALL_ONES, F, T};
            7'b1111_111: dlut_out = {F, F, T, IMM_24_5, SCLR1_4_0, SCLR2_NONE,   F, F, F, F, OP2_SRC_SCALAR2, MASK_SRC_ALL_ONES, F, F};

            // Invalid instruction format
            default: dlut_out = {T, F, F, IMM_ZERO, SCLR1_NONE, SCLR2_NONE, F, F, F, F, OP2_SRC_IMMEDIATE, MASK_SRC_ALL_ONES, F, F};
        endcase
    end

    assign fmt_r = ifd_instruction[31:29] == 3'b110;    // register arithmetic
    assign fmt_i = ifd_instruction[31] == 1'b0;    // immediate arithmetic
    assign fmt_m = ifd_instruction[31:30] == 2'b10;
    assign getlane = (fmt_r || fmt_i) && alu_op == OP_GETLANE;

    assign syscall = fmt_i && 6'(ifd_instruction[28:24]) == OP_SYSCALL;
    assign breakpoint = fmt_r && ifd_instruction[25:20] == OP_BREAKPOINT;
    assign nop = ifd_instruction == INSTRUCTION_NOP;
    assign has_trap = (ifd_instruction_valid
        && (dlut_out.illegal || syscall || breakpoint || raise_interrupt))
        || ifd_alignment_fault || ifd_tlb_miss
        || ifd_supervisor_fault
        || ifd_page_fault || ifd_executable_fault;

    // Check for TLB miss first, since permission bits are not valid if there
    // is a TLB miss. The order of the remaining faults should match that in
    // dcache_data_stage for consistency.
    always_comb
    begin
        if (raise_interrupt)
            decoded_instr_nxt.trap_cause = {2'b00, TT_INTERRUPT};
        else if (ifd_tlb_miss)
            decoded_instr_nxt.trap_cause = {2'b00, TT_TLB_MISS};
        else if (ifd_page_fault)
            decoded_instr_nxt.trap_cause = {2'b00, TT_PAGE_FAULT};
        else if (ifd_supervisor_fault)
            decoded_instr_nxt.trap_cause = {2'b00, TT_SUPERVISOR_ACCESS};
        else if (ifd_alignment_fault)
            decoded_instr_nxt.trap_cause = {2'b00, TT_UNALIGNED_ACCESS};
        else if (ifd_executable_fault)
            decoded_instr_nxt.trap_cause = {2'b00, TT_NOT_EXECUTABLE};
        else if (dlut_out.illegal)
            decoded_instr_nxt.trap_cause = {2'b00, TT_ILLEGAL_INSTRUCTION};
        else if (syscall)
            decoded_instr_nxt.trap_cause = {2'b00, TT_SYSCALL};
        else if (breakpoint)
            decoded_instr_nxt.trap_cause = {2'b00, TT_BREAKPOINT};
        else
            decoded_instr_nxt.trap_cause = {2'b00, TT_RESET};
    end

    assign decoded_instr_nxt.injected = ifd_inst_injected;

    // Subtle: Certain instructions need to be issued twice, including I/O
    // requests and synchronized memory accesses. The first queues the
    // transaction and the second collects the result. Because the first
    // instruction updates internal state, bad things would happen if an
    // interrupt were dispatched between them. To avoid this, don't dispatch
    // an interrupt if the first instruction has been issued (indicated by
    // dd_load_sync_pending, ior_pending, or sq_store_sync_pending).
    assign masked_interrupt_flags = cr_interrupt_pending & cr_interrupt_en
        & ~ior_pending & ~dd_load_sync_pending & ~sq_store_sync_pending;
    assign raise_interrupt = masked_interrupt_flags[ifd_thread_idx] && !ocd_halt;
    assign decoded_instr_nxt.has_trap = has_trap;

    assign unary_arith = fmt_r && (alu_op == OP_CLZ
        || alu_op == OP_CTZ
        || alu_op == OP_MOVE
        || alu_op == OP_FTOI
        || alu_op == OP_RECIPROCAL
        || alu_op == OP_SEXT8
        || alu_op == OP_SEXT16
        || alu_op == OP_ITOF)
        && dlut_out.mask_src != MASK_SRC_SCALAR1;
    assign decoded_instr_nxt.has_scalar1 = dlut_out.scalar1_loc != SCLR1_NONE && !nop
        && !has_trap && !unary_arith;
    always_comb
    begin
        unique case (dlut_out.scalar1_loc)
            SCLR1_14_10: decoded_instr_nxt.scalar_sel1 = ifd_instruction[14:10];
            default: decoded_instr_nxt.scalar_sel1 = ifd_instruction[4:0]; //  src1
        endcase
    end

    assign decoded_instr_nxt.has_scalar2 = dlut_out.scalar2_loc != SCLR2_NONE && !nop
        && !has_trap;

    // XXX: assigning this directly to decoded_instr_nxt.scalar_sel2 causes Verilator issues when
    // other blocks read it. Added another signal to work around this.
    always_comb
    begin
        unique case (dlut_out.scalar2_loc)
            SCLR2_14_10: scalar_sel2 = ifd_instruction[14:10];
            SCLR2_19_15: scalar_sel2 = ifd_instruction[19:15];
            SCLR2_9_5: scalar_sel2 = ifd_instruction[9:5];
            default: scalar_sel2 = 0;
        endcase
    end

    assign decoded_instr_nxt.scalar_sel2 = scalar_sel2;
    assign decoded_instr_nxt.has_vector1 = dlut_out.has_vector1 && !nop && !has_trap;
    assign decoded_instr_nxt.vector_sel1 = ifd_instruction[4:0];
    assign decoded_instr_nxt.has_vector2 = dlut_out.has_vector2 && !nop && !has_trap;
    always_comb
    begin
        if (dlut_out.vector_sel2_9_5)
            decoded_instr_nxt.vector_sel2 = ifd_instruction[9:5];
        else
            decoded_instr_nxt.vector_sel2 = ifd_instruction[19:15];
    end

    assign decoded_instr_nxt.has_dest = dlut_out.has_dest && !nop && !has_trap;

    assign decoded_instr_nxt.dest_vector = dlut_out.dest_vector && !compare
        && !getlane;
    assign decoded_instr_nxt.dest_reg = dlut_out.call ? REG_RA : ifd_instruction[9:5];
    assign decoded_instr_nxt.call = dlut_out.call;
    always_comb
    begin
        if (fmt_i)
            alu_op = alu_op_t'({1'b0, ifd_instruction[28:24]});
        else if (dlut_out.call)
            alu_op = OP_MOVE;    // Treat a call as move ra, pc
        else
            alu_op = alu_op_t'(ifd_instruction[25:20]); // Format R
    end

    assign decoded_instr_nxt.alu_op = alu_op;
    assign decoded_instr_nxt.mask_src = dlut_out.mask_src;
    assign decoded_instr_nxt.store_value_vector = dlut_out.store_value_vector;

    // Decode operand source ports, checking specifically for PC operands
    always_comb
    begin
        if (dlut_out.op1_vector)
            decoded_instr_nxt.op1_src = OP1_SRC_VECTOR1;
        else
            decoded_instr_nxt.op1_src = OP1_SRC_SCALAR1;
    end

    assign decoded_instr_nxt.op2_src = dlut_out.op2_src;

    always_comb
    begin
        unique case (dlut_out.imm_loc)
            IMM_EXT_19: decoded_instr_nxt.immediate_value = { ifd_instruction[23:10], ifd_instruction[4:0], 13'd0 };
            IMM_23_15: decoded_instr_nxt.immediate_value = scalar_t'($signed(ifd_instruction[23:15]));
            IMM_23_10: decoded_instr_nxt.immediate_value = scalar_t'($signed(ifd_instruction[23:10]));
            IMM_24_15: decoded_instr_nxt.immediate_value = scalar_t'($signed(ifd_instruction[24:15]));
            IMM_24_10: decoded_instr_nxt.immediate_value = scalar_t'($signed(ifd_instruction[24:10]));

            // Branch offsets are multiplied by four
            IMM_24_5: decoded_instr_nxt.immediate_value = scalar_t'($signed({ifd_instruction[24:5], 2'b00}));
            IMM_24_0: decoded_instr_nxt.immediate_value = scalar_t'($signed({ifd_instruction[24:0], 2'b00}));
            default: decoded_instr_nxt.immediate_value = 0;
        endcase
    end

    assign decoded_instr_nxt.branch_type = branch_type_t'(ifd_instruction[27:25]);
    assign decoded_instr_nxt.branch = ifd_instruction[31:28] == 4'b1111
        && !has_trap;
    assign decoded_instr_nxt.pc = ifd_pc;

    always_comb
    begin
        if (has_trap)
            decoded_instr_nxt.pipeline_sel = PIPE_INT_ARITH;
        else if (fmt_r || fmt_i)
        begin
            if (alu_op[5] || alu_op == OP_MULL_I || alu_op == OP_MULH_U
                 || alu_op == OP_MULH_I || alu_op == OP_FTOI)
                decoded_instr_nxt.pipeline_sel = PIPE_FLOAT_ARITH;
            else
                decoded_instr_nxt.pipeline_sel = PIPE_INT_ARITH;
        end
        else if (ifd_instruction[31:28] == 4'b1111)
            decoded_instr_nxt.pipeline_sel = PIPE_INT_ARITH; // branches evaluated in integer pipeline
        else
            decoded_instr_nxt.pipeline_sel = PIPE_MEM;
    end

    assign memory_access_type = memory_op_t'(ifd_instruction[28:25]);
    assign decoded_instr_nxt.memory_access_type = memory_access_type;
    assign decoded_instr_nxt.memory_access = ifd_instruction[31:30] == 2'b10
        && !has_trap;
    assign decoded_instr_nxt.load = ifd_instruction[29]
        && fmt_m;
    assign decoded_instr_nxt.cache_control = ifd_instruction[31:28] == 4'b1110
         && !has_trap;
    assign decoded_instr_nxt.cache_control_op = cache_op_t'(ifd_instruction[27:25]);

    always_comb
    begin
        if (ifd_instruction[31:30] == 2'b10
            && (memory_access_type == MEM_SCGATH
            || memory_access_type == MEM_SCGATH_M))
        begin
            // Scatter/Gather access
            decoded_instr_nxt.last_subcycle = subcycle_t'(NUM_VECTOR_LANES - 1);
        end
        else
            decoded_instr_nxt.last_subcycle = 0;
    end

    assign decoded_instr_nxt.creg_index = control_register_t'(ifd_instruction[4:0]);

    assign compare = (fmt_r || fmt_i)
        && (alu_op == OP_CMPEQ_I
        || alu_op == OP_CMPNE_I
        || alu_op == OP_CMPGT_I
        || alu_op == OP_CMPGE_I
        || alu_op == OP_CMPLT_I
        || alu_op == OP_CMPLE_I
        || alu_op == OP_CMPGT_U
        || alu_op == OP_CMPGE_U
        || alu_op == OP_CMPLT_U
        || alu_op == OP_CMPLE_U
        || alu_op == OP_CMPGT_F
        || alu_op == OP_CMPLT_F
        || alu_op == OP_CMPGE_F
        || alu_op == OP_CMPLE_F
        || alu_op == OP_CMPEQ_F
        || alu_op == OP_CMPNE_F);
    assign decoded_instr_nxt.compare = compare;

    always_ff @(posedge clk)
    begin
        id_instruction <= decoded_instr_nxt;
        id_thread_idx <= ifd_thread_idx;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            id_instruction_valid <= '0;
        else
        begin
            // Piggyback ifetch faults and TLB misses inside instructions, marking
            // the instruction valid if these conditions occur
            id_instruction_valid <= (ifd_instruction_valid || has_trap)
                && (!wb_rollback_en || wb_rollback_thread_idx != ifd_thread_idx);
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Instruction Pipeline Integer Execute Stage
// - Performs simple operations that only require a single stage like integer
//   addition or bitwise logical operations.
// - Detects branches
//
// (despite the name, this stage also handles floating point reciprocal
// estimates)
//

module int_execute_stage(
    input                             clk,
    input                             reset,

    // From operand_fetch_stage
    input vector_t                    of_operand1,
    input vector_t                    of_operand2,
    input vector_mask_t               of_mask_value,
    input                             of_instruction_valid,
    input decoded_instruction_t       of_instruction,
    input local_thread_idx_t          of_thread_idx,
    input subcycle_t                  of_subcycle,

    // From writeback_stage
    input logic                       wb_rollback_en,
    input local_thread_idx_t          wb_rollback_thread_idx,

    // To writeback_stage
    output logic                      ix_instruction_valid,
    output decoded_instruction_t      ix_instruction,
    output vector_t                   ix_result,
    output vector_mask_t              ix_mask_value,
    output local_thread_idx_t         ix_thread_idx,
    output logic                      ix_rollback_en,
    output scalar_t                   ix_rollback_pc,
    output subcycle_t                 ix_subcycle,
    output logic                      ix_privileged_op_fault,

    // From control_registers
    input scalar_t                    cr_eret_address[`THREADS_PER_CORE],
    input                             cr_supervisor_en[`THREADS_PER_CORE],

    // To performance_counters
    output logic                      ix_perf_uncond_branch,
    output logic                      ix_perf_cond_branch_taken,
    output logic                      ix_perf_cond_branch_not_taken);

    vector_t vector_result;
    logic eret;
    logic privileged_op_fault;
    logic branch_taken;
    logic conditional_branch;
    logic valid_instruction;

    genvar lane;
    generate
        for (lane = 0; lane < NUM_VECTOR_LANES; lane++)
        begin : lane_alu_gen
            scalar_t lane_operand1;
            scalar_t lane_operand2;
            scalar_t lane_result;
            scalar_t difference;
            logic borrow;
            logic negative;
            logic overflow;
            logic zero;
            logic signed_gtr;
            logic[5:0] lz;
            logic[5:0] tz;
            scalar_t reciprocal;
            float32_t fp_operand;
            logic[5:0] reciprocal_estimate;
            logic shift_in_sign;
            scalar_t rshift;

            assign lane_operand1 = of_operand1[lane];
            assign lane_operand2 = of_operand2[lane];
            assign {borrow, difference} = {1'b0, lane_operand1} - {1'b0, lane_operand2};
            assign negative = difference[31];
            assign overflow = lane_operand2[31] == negative && lane_operand1[31] != lane_operand2[31];
            assign zero = difference == 0;
            assign signed_gtr = overflow == negative;

            // Count leading zeroes
            always_comb
            begin
                unique casez (lane_operand2)
                    32'b1???????????????????????????????: lz = 0;
                    32'b01??????????????????????????????: lz = 1;
                    32'b001?????????????????????????????: lz = 2;
                    32'b0001????????????????????????????: lz = 3;
                    32'b00001???????????????????????????: lz = 4;
                    32'b000001??????????????????????????: lz = 5;
                    32'b0000001?????????????????????????: lz = 6;
                    32'b00000001????????????????????????: lz = 7;
                    32'b000000001???????????????????????: lz = 8;
                    32'b0000000001??????????????????????: lz = 9;
                    32'b00000000001?????????????????????: lz = 10;
                    32'b000000000001????????????????????: lz = 11;
                    32'b0000000000001???????????????????: lz = 12;
                    32'b00000000000001??????????????????: lz = 13;
                    32'b000000000000001?????????????????: lz = 14;
                    32'b0000000000000001????????????????: lz = 15;
                    32'b00000000000000001???????????????: lz = 16;
                    32'b000000000000000001??????????????: lz = 17;
                    32'b0000000000000000001?????????????: lz = 18;
                    32'b00000000000000000001????????????: lz = 19;
                    32'b000000000000000000001???????????: lz = 20;
                    32'b0000000000000000000001??????????: lz = 21;
                    32'b00000000000000000000001?????????: lz = 22;
                    32'b000000000000000000000001????????: lz = 23;
                    32'b0000000000000000000000001???????: lz = 24;
                    32'b00000000000000000000000001??????: lz = 25;
                    32'b000000000000000000000000001?????: lz = 26;
                    32'b0000000000000000000000000001????: lz = 27;
                    32'b00000000000000000000000000001???: lz = 28;
                    32'b000000000000000000000000000001??: lz = 29;
                    32'b0000000000000000000000000000001?: lz = 30;
                    32'b00000000000000000000000000000001: lz = 31;
                    32'b00000000000000000000000000000000: lz = 32;
                    default: lz = 0;
                endcase
            end

            // Count trailing zeroes
            always_comb
            begin
                unique casez (lane_operand2)
                    32'b00000000000000000000000000000000: tz = 32;
                    32'b10000000000000000000000000000000: tz = 31;
                    32'b?1000000000000000000000000000000: tz = 30;
                    32'b??100000000000000000000000000000: tz = 29;
                    32'b???10000000000000000000000000000: tz = 28;
                    32'b????1000000000000000000000000000: tz = 27;
                    32'b?????100000000000000000000000000: tz = 26;
                    32'b??????10000000000000000000000000: tz = 25;
                    32'b???????1000000000000000000000000: tz = 24;
                    32'b????????100000000000000000000000: tz = 23;
                    32'b?????????10000000000000000000000: tz = 22;
                    32'b??????????1000000000000000000000: tz = 21;
                    32'b???????????100000000000000000000: tz = 20;
                    32'b????????????10000000000000000000: tz = 19;
                    32'b?????????????1000000000000000000: tz = 18;
                    32'b??????????????100000000000000000: tz = 17;
                    32'b???????????????10000000000000000: tz = 16;
                    32'b????????????????1000000000000000: tz = 15;
                    32'b?????????????????100000000000000: tz = 14;
                    32'b??????????????????10000000000000: tz = 13;
                    32'b???????????????????1000000000000: tz = 12;
                    32'b????????????????????100000000000: tz = 11;
                    32'b?????????????????????10000000000: tz = 10;
                    32'b??????????????????????1000000000: tz = 9;
                    32'b???????????????????????100000000: tz = 8;
                    32'b????????????????????????10000000: tz = 7;
                    32'b?????????????????????????1000000: tz = 6;
                    32'b??????????????????????????100000: tz = 5;
                    32'b???????????????????????????10000: tz = 4;
                    32'b????????????????????????????1000: tz = 3;
                    32'b?????????????????????????????100: tz = 2;
                    32'b??????????????????????????????10: tz = 1;
                    32'b???????????????????????????????1: tz = 0;
                    default: tz = 0;
                endcase
            end

            // Right shift
            assign shift_in_sign = of_instruction.alu_op == OP_ASHR ? lane_operand1[31] : 1'd0;
            assign rshift = scalar_t'({{32{shift_in_sign}}, lane_operand1} >> lane_operand2[4:0]);

            // Reciprocal estimate
            assign fp_operand = lane_operand2;
            reciprocal_rom rom(
                .significand(fp_operand.significand[22:17]),
                .reciprocal_estimate);

            always_comb
            begin
                if (fp_operand.exponent == 0)
                begin
                    // A subnormal will overflow the exponent field, so convert to infinity.
                    // This also handles division by zero.
                    reciprocal = {fp_operand.sign, 8'hff, 23'd0}; // inf
                end
                else if (fp_operand.exponent == 8'hff)
                begin
                    if (fp_operand.significand != 0)
                        reciprocal = {1'b0, 8'hff, 23'h7fffff}; // Division by NaN = NaN
                    else
                        reciprocal = {fp_operand.sign, 8'h00, 23'h000000}; // Division by +/-inf = +/-0.0
                end
                else
                begin
                    reciprocal = {fp_operand.sign, 8'd253 - fp_operand.exponent + 8'((fp_operand.significand[22:17] == 0)),
                        reciprocal_estimate, {17{1'b0}}};
                end
            end

            always_comb
            begin
                unique case (of_instruction.alu_op)
                    OP_ASHR,
                    OP_SHR: lane_result = rshift;
                    OP_SHL: lane_result = lane_operand1 << lane_operand2[4:0];
                    OP_MOVE: lane_result = lane_operand2;
                    OP_OR: lane_result = lane_operand1 | lane_operand2;
                    OP_CLZ: lane_result = scalar_t'(lz);
                    OP_CTZ: lane_result = scalar_t'(tz);
                    OP_AND: lane_result = lane_operand1 & lane_operand2;
                    OP_XOR: lane_result = lane_operand1 ^ lane_operand2;
                    OP_ADD_I: lane_result = lane_operand1 + lane_operand2;
                    OP_SUB_I: lane_result = difference;
                    OP_CMPEQ_I: lane_result = {{31{1'b0}}, zero};
                    OP_CMPNE_I: lane_result = {{31{1'b0}}, !zero};
                    OP_CMPGT_I: lane_result = {{31{1'b0}}, signed_gtr && !zero};
                    OP_CMPGE_I: lane_result = {{31{1'b0}}, signed_gtr || zero};
                    OP_CMPLT_I: lane_result = {{31{1'b0}}, !signed_gtr && !zero};
                    OP_CMPLE_I: lane_result = {{31{1'b0}}, !signed_gtr || zero};
                    OP_CMPGT_U: lane_result = {{31{1'b0}}, !borrow && !zero};
                    OP_CMPGE_U: lane_result = {{31{1'b0}}, !borrow || zero};
                    OP_CMPLT_U: lane_result = {{31{1'b0}}, borrow && !zero};
                    OP_CMPLE_U: lane_result = {{31{1'b0}}, borrow || zero};
                    OP_SEXT8: lane_result = scalar_t'($signed(lane_operand2[7:0]));
                    OP_SEXT16: lane_result = scalar_t'($signed(lane_operand2[15:0]));
                    OP_SHUFFLE,
                    OP_GETLANE: lane_result = of_operand1[~lane_operand2];
                    OP_RECIPROCAL: lane_result = reciprocal;
                    default: lane_result = 0;
                endcase
            end

            assign vector_result[lane] = lane_result;
        end
    endgenerate

    assign valid_instruction = of_instruction_valid
        && (!wb_rollback_en || wb_rollback_thread_idx != of_thread_idx)
        && of_instruction.pipeline_sel == PIPE_INT_ARITH;
    assign eret = valid_instruction
        && of_instruction.branch
        && of_instruction.branch_type == BRANCH_ERET;
    assign privileged_op_fault = eret && !cr_supervisor_en[of_thread_idx];

    always_comb
    begin
        branch_taken = 0;
        conditional_branch = 0;

        if (valid_instruction
            && of_instruction.branch
            && !privileged_op_fault)
        begin
            unique case (of_instruction.branch_type)
                BRANCH_ZERO:
                begin
                    branch_taken = of_operand1[0] == 0;
                    conditional_branch = 1;
                end

                BRANCH_NOT_ZERO:
                begin
                    branch_taken = of_operand1[0] != 0;
                    conditional_branch = 1;
                end

                BRANCH_ALWAYS,
                BRANCH_CALL_OFFSET,
                BRANCH_CALL_REGISTER,
                BRANCH_REGISTER,
                BRANCH_ERET:
                begin
                    branch_taken = 1;
                end

                default:
                    ;
            endcase
        end
    end


    always_ff @(posedge clk)
    begin
        ix_instruction <= of_instruction;
        ix_result <= vector_result;
        ix_mask_value <= of_mask_value;
        ix_thread_idx <= of_thread_idx;
        ix_subcycle <= of_subcycle;

        // Branch handling
        unique case (of_instruction.branch_type)
            BRANCH_CALL_REGISTER,
            BRANCH_REGISTER: ix_rollback_pc <= of_operand1[0];
            BRANCH_ERET: ix_rollback_pc <= cr_eret_address[of_thread_idx];
            default:
                ix_rollback_pc <= of_instruction.pc + of_instruction.immediate_value;
        endcase
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            ix_instruction_valid <= '0;
            ix_perf_cond_branch_not_taken <= '0;
            ix_perf_cond_branch_taken <= '0;
            ix_perf_uncond_branch <= '0;
            ix_privileged_op_fault <= '0;
            ix_rollback_en <= '0;
            // End of automatics
        end
        else
        begin
            if (valid_instruction)
            begin
                ix_instruction_valid <= 1;
                ix_privileged_op_fault <= privileged_op_fault;
                ix_rollback_en <= branch_taken;
            end
            else
            begin
                ix_instruction_valid <= 0;
                ix_rollback_en <= 0;
            end

            ix_perf_uncond_branch <= !conditional_branch && branch_taken;
            ix_perf_cond_branch_taken <= conditional_branch && branch_taken;
            ix_perf_cond_branch_not_taken <= conditional_branch && !branch_taken;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Accepts IO requests from all cores and serializes requests to external
// IO interface. Sends responses back to cores.
//

module io_interconnect(
    input                            clk,
    input                            reset,

    // From core
    input [`NUM_CORES - 1:0]         ior_request_valid,
    input ioreq_packet_t             ior_request[`NUM_CORES],

    // To core
    output logic                     ii_ready[`NUM_CORES],
    output logic                     ii_response_valid,
    output iorsp_packet_t            ii_response,
    io_bus_interface.master          io_bus);

    core_id_t grant_idx;
    logic[`NUM_CORES - 1:0] grant_oh;
    logic request_sent;
    core_id_t request_core;
    local_thread_idx_t request_thread_idx;
    ioreq_packet_t grant_request;

    genvar request_idx;
    generate
        for (request_idx = 0; request_idx < `NUM_CORES; request_idx++)
        begin : handshake_gen
            assign ii_ready[request_idx] = grant_oh[request_idx];
        end
    endgenerate

    genvar grant_idx_bit;
    generate
        if (`NUM_CORES > 1)
        begin
            rr_arbiter #(.NUM_REQUESTERS(`NUM_CORES)) request_arbiter(
                .request(ior_request_valid),
                .update_lru(1'b1),
                .grant_oh(grant_oh),
                .*);

            oh_to_idx #(.NUM_SIGNALS(`NUM_CORES)) oh_to_idx_grant(
                .one_hot(grant_oh),
                .index(grant_idx[CORE_ID_WIDTH - 1:0]));

            // Ensure high bits are zeroed. Notes in defines.sv
            // describe why the core ID width needs to be hardcoded.
            for (grant_idx_bit = CORE_ID_WIDTH; grant_idx_bit < $bits(grant_idx);
                grant_idx_bit++)
            begin : grant_bit_gen
                assign grant_idx[grant_idx_bit] = 0;
            end

            assign grant_request = ior_request[grant_idx[CORE_ID_WIDTH - 1:0]];
        end
        else
        begin
            assign grant_oh[0] = ior_request_valid[0];
            assign grant_idx = 0;
            assign grant_request = ior_request[0];
        end
    endgenerate

    assign io_bus.write_en = |grant_oh && grant_request.store;
    assign io_bus.read_en = |grant_oh && !grant_request.store;
    assign io_bus.write_data = grant_request.value;
    assign io_bus.address = grant_request.address;

    always_ff @(posedge clk)
    begin
        ii_response.core <= request_core;
        ii_response.thread_idx <= request_thread_idx;
        ii_response.read_value <= io_bus.read_data;
        if (|ior_request_valid)
        begin
            request_core <= grant_idx;
            request_thread_idx <= grant_request.thread_idx;
        end
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            ii_response_valid <= '0;
            request_sent <= '0;
            // End of automatics
        end
        else
        begin
            request_sent <= |ior_request_valid;
            ii_response_valid <= request_sent;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Handles non-cacheable memory operations to memory mapped registers
// These always block the thread until the transaction is complete.
//

module io_request_queue
    #(parameter CORE_ID = 0)

    (input                                 clk,
    input                                  reset,

    // From dcache_data_stage
    input                                  dd_io_write_en,
    input                                  dd_io_read_en,
    input local_thread_idx_t               dd_io_thread_idx,
    input scalar_t                         dd_io_addr,
    input scalar_t                         dd_io_write_value,

    // To writeback_stage
    output scalar_t                        ior_read_value,
    output logic                           ior_rollback_en,

    // To instruction_decode_stage
    output local_thread_bitmap_t           ior_pending,

    // To thread_select_stage
    output local_thread_bitmap_t           ior_wake_bitmap,

    // From io_interconnect
    input                                  ii_ready,
    input                                  ii_response_valid,
    input iorsp_packet_t                   ii_response,

    // To io_interconnect
    output logic                           ior_request_valid,
    output ioreq_packet_t                  ior_request);

    struct packed {
        logic valid;
        logic request_sent;
        logic store;
        scalar_t address;
        scalar_t value;
    } pending_request[`THREADS_PER_CORE];
    local_thread_bitmap_t wake_thread_oh;
    local_thread_bitmap_t send_request;
    local_thread_bitmap_t send_grant_oh;
    local_thread_idx_t send_grant_idx;

    genvar thread_idx;
    generate
        for (thread_idx = 0; thread_idx < `THREADS_PER_CORE; thread_idx++)
        begin : io_request_gen
            assign send_request[thread_idx] = pending_request[thread_idx].valid
                && !pending_request[thread_idx].request_sent;
            assign ior_pending[thread_idx] = (pending_request[thread_idx].valid
                && pending_request[thread_idx].request_sent) || send_grant_oh[thread_idx];

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                    pending_request[thread_idx] <= 0;
                else
                begin
                    if ((dd_io_write_en | dd_io_read_en) && dd_io_thread_idx
                        == local_thread_idx_t'(thread_idx))
                    begin
                        if (pending_request[thread_idx].valid)
                        begin
                            // Request completed
                            pending_request[thread_idx].valid <= 0;
                        end
                        else
                        begin
                            // Request initiated
                            pending_request[thread_idx].valid <= 1;
                            pending_request[thread_idx].store <= dd_io_write_en;
                            pending_request[thread_idx].address <= dd_io_addr;
                            pending_request[thread_idx].value <= dd_io_write_value;
                            pending_request[thread_idx].request_sent <= 0;
                        end
                    end

                    if (ii_response_valid && ii_response.core == CORE_ID && ii_response.thread_idx
                        == local_thread_idx_t'(thread_idx))
                    begin
                        // Ensure there isn't a response for an entry that isn't pending
                        assert(pending_request[thread_idx].valid);

                        pending_request[thread_idx].value <= ii_response.read_value;
                    end

                    if (ii_ready && |send_grant_oh && send_grant_idx == local_thread_idx_t'(thread_idx))
                        pending_request[thread_idx].request_sent <= 1;
                end
            end
        end
    endgenerate

    rr_arbiter #(.NUM_REQUESTERS(`THREADS_PER_CORE)) request_arbiter(
        .request(send_request),
        .update_lru(1'b1),
        .grant_oh(send_grant_oh),
        .*);

    oh_to_idx #(.NUM_SIGNALS(`THREADS_PER_CORE)) oh_to_idx_send_thread(
        .one_hot(send_grant_oh),
        .index(send_grant_idx));

    idx_to_oh #(.NUM_SIGNALS(`THREADS_PER_CORE)) idx_to_oh_wake_thread(
        .index(ii_response.thread_idx),
        .one_hot(wake_thread_oh));

    assign ior_wake_bitmap = (ii_response_valid && ii_response.core == CORE_ID)
        ? wake_thread_oh : local_thread_bitmap_t'(0);

    // Send request
    assign ior_request_valid = |send_request;
    assign ior_request.store = pending_request[send_grant_idx].store;
    assign ior_request.address = pending_request[send_grant_idx].address;
    assign ior_request.value = pending_request[send_grant_idx].value;
    assign ior_request.thread_idx = send_grant_idx;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            ior_rollback_en <= '0;
            // End of automatics
        end
        else
        begin
            if ((dd_io_write_en || dd_io_read_en) && !pending_request[dd_io_thread_idx].valid)
                ior_rollback_en <= 1;    // Start request
            else
                ior_rollback_en <= 0;    // Complete request
        end
    end

    always_ff @(posedge clk)
        ior_read_value <= pending_request[dd_io_thread_idx].value;
endmodule
//
// Copyright 2017 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// JTAG Test Access Point (TAP) controller.
// This contains the JTAG state machine logic.
//
// The JTAG clock (TCK) is not a separate clock domain. This instead samples
// TCK, TDI, and TMS on the rising edge of the system clock, which simplifies
// the logic. When this detects a change of TCK beween two samples, it reads
// the data signals. Thus it may read them up to one system clock period after
// the TCK edge. IEEE 1149.1-2001 requires signal to be driven on the falling
// edge of TCK and sampled on the rising edge. So the JTAG clock frequency must
// be lower than a submultiple  of the system clock frequency (probably a maximum
// of 1/8).
//

module jtag_tap_controller
    #(parameter INSTRUCTION_WIDTH = 1)

    (input                                  clk,
    input                                   reset,

    jtag_interface.target                   jtag,

    // data_shift_val is the value to be sent out TDO when
    // shifting a data register.
    input                                   data_shift_val,
    output logic                            capture_dr,
    output logic                            shift_dr,
    output logic                            update_dr,
    output logic[INSTRUCTION_WIDTH - 1:0]   jtag_instruction,
    output logic                            update_ir);

    typedef enum int {
        JTAG_RESET,
        JTAG_IDLE,
        JTAG_SELECT_DR_SCAN,
        JTAG_CAPTURE_DR,
        JTAG_SHIFT_DR,
        JTAG_EXIT1_DR,
        JTAG_PAUSE_DR,
        JTAG_EXIT2_DR,
        JTAG_UPDATE_DR,
        JTAG_SELECT_IR_SCAN,
        JTAG_CAPTURE_IR,
        JTAG_SHIFT_IR,
        JTAG_EXIT1_IR,
        JTAG_PAUSE_IR,
        JTAG_EXIT2_IR,
        JTAG_UPDATE_IR
    } jtag_state_t;

    jtag_state_t state_ff;
    jtag_state_t state_nxt;
    logic last_tck;
    logic tck_rising_edge;
    logic tck_falling_edge;
    logic tck_sync;
    logic tms_sync;
    logic tdi_sync;
    logic trst_sync_n;

    always_comb
    begin
        state_nxt = state_ff;
        unique case (state_ff)
            JTAG_IDLE:
                if (tms_sync)
                    state_nxt = JTAG_SELECT_DR_SCAN;

            JTAG_SELECT_DR_SCAN:
                if (tms_sync)
                    state_nxt = JTAG_SELECT_IR_SCAN;
                else
                    state_nxt = JTAG_CAPTURE_DR;

            JTAG_CAPTURE_DR:
                if (tms_sync)
                    state_nxt = JTAG_EXIT1_DR;
                else
                    state_nxt = JTAG_SHIFT_DR;

            JTAG_SHIFT_DR:
                if (tms_sync)
                    state_nxt = JTAG_EXIT1_DR;

            JTAG_EXIT1_DR:
                if (tms_sync)
                    state_nxt = JTAG_UPDATE_DR;
                else
                    state_nxt = JTAG_PAUSE_DR;

            JTAG_PAUSE_DR:
                if (tms_sync)
                    state_nxt = JTAG_EXIT2_DR;

            JTAG_EXIT2_DR:
                if (tms_sync)
                    state_nxt = JTAG_UPDATE_DR;
                else
                    state_nxt = JTAG_SHIFT_DR;

            JTAG_UPDATE_DR:
                state_nxt = JTAG_IDLE;

            JTAG_SELECT_IR_SCAN:
                if (tms_sync)
                    state_nxt = JTAG_IDLE;
                else
                    state_nxt = JTAG_CAPTURE_IR;

            JTAG_CAPTURE_IR:
                if (tms_sync)
                    state_nxt = JTAG_EXIT1_IR;
                else
                    state_nxt = JTAG_SHIFT_IR;

            JTAG_SHIFT_IR:
                if (tms_sync)
                    state_nxt = JTAG_EXIT1_IR;

            JTAG_EXIT1_IR:
                if (tms_sync)
                    state_nxt = JTAG_UPDATE_IR;
                else
                    state_nxt = JTAG_PAUSE_IR;

            JTAG_PAUSE_IR:
                if (tms_sync)
                    state_nxt = JTAG_EXIT2_IR;

            JTAG_EXIT2_IR:
                if (tms_sync)
                    state_nxt = JTAG_UPDATE_IR;
                else
                    state_nxt = JTAG_SHIFT_IR;

            JTAG_UPDATE_IR:
                if (tms_sync)
                    state_nxt = JTAG_SELECT_DR_SCAN;
                else
                    state_nxt = JTAG_IDLE;

            JTAG_RESET:
                if (!tms_sync)
                    state_nxt = JTAG_IDLE;

            default:
                state_nxt = JTAG_RESET;
        endcase
    end

    // Sample signals into this clock domain.
    synchronizer #(.WIDTH(4)) synchronizer(
        .data_i({jtag.tck, jtag.tms, jtag.tdi, jtag.trst_n}),
        .data_o({tck_sync, tms_sync, tdi_sync, trst_sync_n}),
        .*);

    assign tck_rising_edge = !last_tck && tck_sync;
    assign tck_falling_edge = last_tck && !tck_sync;

    assign update_ir = state_ff == JTAG_UPDATE_IR && tck_rising_edge;
    assign capture_dr = state_ff == JTAG_CAPTURE_DR && tck_rising_edge;
    assign shift_dr = state_ff == JTAG_SHIFT_DR && tck_rising_edge;
    assign update_dr = state_ff == JTAG_UPDATE_DR && tck_rising_edge;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            state_ff <= JTAG_RESET;
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            jtag.tdo <= '0;
            jtag_instruction <= '0;
            last_tck <= '0;
            // End of automatics
        end
        else if (!trst_sync_n)
            state_ff <= JTAG_RESET;
        else
        begin
            if (state_ff == JTAG_RESET)
                jtag_instruction <= '0;

            last_tck <= tck_sync;
            if (tck_rising_edge)
            begin
                state_ff <= state_nxt;
                if (state_ff == JTAG_SHIFT_IR)
                    jtag_instruction <= {tdi_sync, jtag_instruction[INSTRUCTION_WIDTH - 1:1]};
            end
            else if (tck_falling_edge)
                jtag.tdo <= state_ff == JTAG_SHIFT_IR ? jtag_instruction[0] : data_shift_val;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// This module is in each core and handles communications between
// L1 and L2 caches. It hides the L2 protocol from the execution pipeline,
// making it easier to experiment with alternate protocols and interconnects.
// Additional things this module handles:
// - Tracks pending load misses from L1 instruction and data caches
//   (l1_load_miss_queue).
// - Tracks pending stores from pipeline (l1_store_queue).
// - Arbitrates miss sources and sends L2 cache requests.
// - Processes L2 responses, updating L1 instruction and data caches.
//
// This processes L2 responses using a three stage pipeline:
// 1. Sends store address from the response to L1D tag memory (which
//    has one cycle of latency) to snoop it.
// 2. Checks the snoop responses. If the data are in the cache, selects the
//    way for update. For load responses, update tag memory.
// 3. Update L1D data memory. It must do this a cycle after updating the
//    tags to avoid a race condition becausethey are checked in this sequence
//    by the instruction pipeline during load accesses.
//
// l2i_request_valid does not depend combinationally on l2_ready (to avoid a
// loop), but the opposite is not true (see l2_cache_arb_stage).
//

module l1_l2_interface
    #(parameter CORE_ID = 0)
    (input                                        clk,
    input                                         reset,

    // From l2_cache
    input                                         l2_ready,
    input                                         l2_response_valid,
    input l2rsp_packet_t                          l2_response,

    // To l2_cache
    output logic                                  l2i_request_valid,
    output l2req_packet_t                         l2i_request,

    // To ifetch_tag_stage
    output logic                                  l2i_icache_lru_fill_en,
    output l1i_set_idx_t                          l2i_icache_lru_fill_set,
    output logic[`L1I_WAYS - 1:0]                 l2i_itag_update_en,
    output l1i_set_idx_t                          l2i_itag_update_set,
    output l1i_tag_t                              l2i_itag_update_tag,
    output logic                                  l2i_itag_update_valid,

    // To instruction_decode_stage
    output local_thread_bitmap_t                  sq_store_sync_pending,

    // From ifetch_tag_stage
    input l1i_way_idx_t                           ift_fill_lru,

    // From ifetch_data_stage
    input logic                                   ifd_cache_miss,
    input cache_line_index_t                      ifd_cache_miss_paddr,
    input local_thread_idx_t                      ifd_cache_miss_thread_idx,

    // To ifetch_data_stage
    output logic                                  l2i_idata_update_en,
    output l1i_way_idx_t                          l2i_idata_update_way,
    output l1i_set_idx_t                          l2i_idata_update_set,
    output cache_line_data_t                      l2i_idata_update_data,

    // To thread_select_stage
    output local_thread_bitmap_t                  l2i_dcache_wake_bitmap,
    output local_thread_bitmap_t                  l2i_icache_wake_bitmap,

    // From dcache_tag_stage
    input logic                                   dt_snoop_valid[`L1D_WAYS],
    input l1d_tag_t                               dt_snoop_tag[`L1D_WAYS],
    input l1d_way_idx_t                           dt_fill_lru,

    // To dcache_tag_stage
    output logic                                  l2i_snoop_en,
    output l1d_set_idx_t                          l2i_snoop_set,
    output logic[`L1D_WAYS - 1:0]                 l2i_dtag_update_en_oh,
    output l1d_set_idx_t                          l2i_dtag_update_set,
    output l1d_tag_t                              l2i_dtag_update_tag,
    output logic                                  l2i_dtag_update_valid,
    output logic                                  l2i_dcache_lru_fill_en,
    output l1d_set_idx_t                          l2i_dcache_lru_fill_set,

    // From dcache_data_stage
    input                                         dd_cache_miss,
    input cache_line_index_t                      dd_cache_miss_addr,
    input local_thread_idx_t                      dd_cache_miss_thread_idx,
    input                                         dd_cache_miss_sync,
    input                                         dd_store_en,
    input                                         dd_flush_en,
    input                                         dd_membar_en,
    input                                         dd_iinvalidate_en,
    input                                         dd_dinvalidate_en,
    input [CACHE_LINE_BYTES - 1:0]                dd_store_mask,
    input cache_line_index_t                      dd_store_addr,
    input cache_line_data_t                       dd_store_data,
    input local_thread_idx_t                      dd_store_thread_idx,
    input                                         dd_store_sync,
    input cache_line_index_t                      dd_store_bypass_addr,
    input local_thread_idx_t                      dd_store_bypass_thread_idx,

    // To dcache_data_stage
    output logic                                  l2i_ddata_update_en,
    output l1d_way_idx_t                          l2i_ddata_update_way,
    output l1d_set_idx_t                          l2i_ddata_update_set,
    output cache_line_data_t                      l2i_ddata_update_data,

    // To writeback_stage
    output logic[CACHE_LINE_BYTES - 1:0]          sq_store_bypass_mask,
    output logic                                  sq_store_sync_success,
    output cache_line_data_t                      sq_store_bypass_data,
    output logic                                  sq_rollback_en,

    // To core
    output logic                                  l2i_perf_store);

    logic[`L1D_WAYS - 1:0] snoop_hit_way_oh;    // Only snoops dcache
    l1d_way_idx_t snoop_hit_way_idx;
    logic[`L1I_WAYS - 1:0] ifill_way_oh;
    logic[`L1D_WAYS - 1:0] dupdate_way_oh;
    l1d_way_idx_t dupdate_way_idx;
    logic ack_for_me;
    logic icache_update_en;
    logic dcache_update_en;
    logic dcache_l2_response_valid;
    l1_miss_entry_idx_t dcache_l2_response_idx;
    logic icache_l2_response_valid;
    l1_miss_entry_idx_t icache_l2_response_idx;
    logic storebuf_l2_response_valid;
    l1_miss_entry_idx_t storebuf_l2_response_idx;
    local_thread_bitmap_t dcache_miss_wake_bitmap;
    logic storebuf_dequeue_ack;
    logic icache_dequeue_ready;
    logic icache_dequeue_ack;
    logic dcache_dequeue_ready;
    logic dcache_dequeue_ack;
    cache_line_index_t dcache_dequeue_addr;
    logic dcache_dequeue_sync;
    cache_line_index_t icache_dequeue_addr;
    l1_miss_entry_idx_t dcache_dequeue_idx;
    l1_miss_entry_idx_t icache_dequeue_idx;
    logic response_stage2_valid;
    l2rsp_packet_t response_stage2;
    l1d_set_idx_t dcache_set_stage1;
    l1i_set_idx_t icache_set_stage1;
    l1d_set_idx_t dcache_set_stage2;
    l1i_set_idx_t icache_set_stage2;
    l1d_tag_t dcache_tag_stage2;
    l1i_tag_t icache_tag_stage2;
    logic storebuf_l2_sync_success;
    logic response_iinvalidate;
    logic response_dinvalidate;

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    cache_line_index_t  sq_dequeue_addr;        // From l1_store_queue of l1_store_queue.v
    cache_line_data_t   sq_dequeue_data;        // From l1_store_queue of l1_store_queue.v
    logic               sq_dequeue_dinvalidate; // From l1_store_queue of l1_store_queue.v
    logic               sq_dequeue_flush;       // From l1_store_queue of l1_store_queue.v
    l1_miss_entry_idx_t sq_dequeue_idx;         // From l1_store_queue of l1_store_queue.v
    logic               sq_dequeue_iinvalidate; // From l1_store_queue of l1_store_queue.v
    logic [CACHE_LINE_BYTES-1:0] sq_dequeue_mask;// From l1_store_queue of l1_store_queue.v
    logic               sq_dequeue_ready;       // From l1_store_queue of l1_store_queue.v
    logic               sq_dequeue_sync;        // From l1_store_queue of l1_store_queue.v
    local_thread_bitmap_t sq_wake_bitmap;       // From l1_store_queue of l1_store_queue.v
    // End of automatics

    l1_store_queue l1_store_queue(.*);

    l1_load_miss_queue l1_load_miss_queue_dcache(
        // Enqueue requests
        .cache_miss(dd_cache_miss),
        .cache_miss_addr(dd_cache_miss_addr),
        .cache_miss_thread_idx(dd_cache_miss_thread_idx),
        .cache_miss_sync(dd_cache_miss_sync),

        // Next request
        .dequeue_ready(dcache_dequeue_ready),
        .dequeue_ack(dcache_dequeue_ack),
        .dequeue_addr(dcache_dequeue_addr),
        .dequeue_idx(dcache_dequeue_idx),
        .dequeue_sync(dcache_dequeue_sync),

        // Wake threads when a transaction is complete
        .l2_response_valid(dcache_l2_response_valid),
        .l2_response_idx(dcache_l2_response_idx),
        .wake_bitmap(dcache_miss_wake_bitmap),
        .*);

    assign l2i_dcache_wake_bitmap = dcache_miss_wake_bitmap | sq_wake_bitmap;

    l1_load_miss_queue l1_load_miss_queue_icache(
        // Enqueue requests
        .cache_miss(ifd_cache_miss),
        .cache_miss_addr(ifd_cache_miss_paddr),
        .cache_miss_thread_idx(ifd_cache_miss_thread_idx),
        .cache_miss_sync('0),

        // Next request
        .dequeue_ready(icache_dequeue_ready),
        .dequeue_ack(icache_dequeue_ack),
        .dequeue_addr(icache_dequeue_addr),
        .dequeue_idx(icache_dequeue_idx),
        .dequeue_sync(),

        // Wake threads when a transaction is complete
        .l2_response_valid(icache_l2_response_valid),
        .l2_response_idx(icache_l2_response_idx),
        .wake_bitmap(l2i_icache_wake_bitmap),
        .*);

    /////////////////////////////////////////////////
    // Response pipeline stage 1
    /////////////////////////////////////////////////

    assign dcache_set_stage1 = l2_response.address[$clog2(`L1D_SETS) - 1:0];
    assign icache_set_stage1 = l2_response.address[$clog2(`L1I_SETS) - 1:0];
    assign l2i_snoop_en = l2_response_valid && l2_response.cache_type == CT_DCACHE;
    assign l2i_snoop_set = dcache_set_stage1;
    assign l2i_dcache_lru_fill_en = l2_response_valid && l2_response.cache_type == CT_DCACHE
        && l2_response.packet_type == L2RSP_LOAD_ACK && l2_response.core == CORE_ID;
    assign l2i_dcache_lru_fill_set = dcache_set_stage1;
    assign l2i_icache_lru_fill_en = l2_response_valid && l2_response.cache_type == CT_ICACHE
        && l2_response.packet_type == L2RSP_LOAD_ACK && l2_response.core == CORE_ID;
    assign l2i_icache_lru_fill_set = icache_set_stage1;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            response_stage2_valid <= 0;
        else
        begin
            // Should not get a wake from miss queue and store queue in the same cycle.
            assert((dcache_miss_wake_bitmap & sq_wake_bitmap) == 0);
            response_stage2_valid <= l2_response_valid;
        end
    end

    always_ff @(posedge clk)
        response_stage2 <= l2_response;

    /////////////////////////////////////////////////
    // Response pipeline stage 2
    /////////////////////////////////////////////////

    assign {icache_tag_stage2, icache_set_stage2} = response_stage2.address;
    assign {dcache_tag_stage2, dcache_set_stage2} = response_stage2.address;

    //
    // Check snoop result
    //
    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < `L1D_WAYS; way_idx++)
        begin : snoop_hit_check_gen
            assign snoop_hit_way_oh[way_idx] = dt_snoop_tag[way_idx] == dcache_tag_stage2
                && dt_snoop_valid[way_idx];
        end
    endgenerate

    oh_to_idx #(.NUM_SIGNALS(`L1D_WAYS)) convert_snoop_request_pending(
        .index(snoop_hit_way_idx),
        .one_hot(snoop_hit_way_oh));

    //
    // Determine fill way. If this data is already in this cache set, update the
    // way that has the data. This handles write updates and cache synonyms
    // (two virtual addresses point to the same physical address).
    //
    always_comb
    begin
        if (|snoop_hit_way_oh)
            dupdate_way_idx = snoop_hit_way_idx; // Update existing dcache line
        else
            dupdate_way_idx = dt_fill_lru;     // Fill new dcache line
    end

    idx_to_oh #(.NUM_SIGNALS(`L1D_WAYS)) idx_to_oh_dfill_way(
        .index(dupdate_way_idx),
        .one_hot(dupdate_way_oh));

    idx_to_oh #(.NUM_SIGNALS(`L1I_WAYS)) idx_to_oh_ifill_way(
        .index(ift_fill_lru),
        .one_hot(ifill_way_oh));

    assign ack_for_me = response_stage2_valid && response_stage2.core == CORE_ID;

    //
    // Update data cache tag
    //
    assign response_dinvalidate = response_stage2.packet_type == L2RSP_DINVALIDATE_ACK;
    assign dcache_update_en = (ack_for_me && ((response_stage2.packet_type == L2RSP_LOAD_ACK
        && response_stage2.cache_type == CT_DCACHE) || response_stage2.packet_type == L2RSP_STORE_ACK))
        || (response_stage2_valid && response_dinvalidate && |snoop_hit_way_oh);
    assign l2i_dtag_update_en_oh = dupdate_way_oh & {`L1D_WAYS{dcache_update_en}};
    assign l2i_dtag_update_tag = dcache_tag_stage2;
    assign l2i_dtag_update_set = dcache_set_stage2;
    assign l2i_dtag_update_valid = !response_dinvalidate;

    //
    // Update instruction cache tag. For a fill, mark the line valid and update the tag.
    // For a invalidate, mark all ways for the selected set invalid
    //
    assign response_iinvalidate = response_stage2_valid
        && response_stage2.packet_type == L2RSP_IINVALIDATE_ACK;
    assign icache_update_en = (ack_for_me && response_stage2.cache_type == CT_ICACHE)
        || response_iinvalidate;
    assign l2i_itag_update_en = response_iinvalidate ? {`L1I_WAYS{1'b1}}
        : (ifill_way_oh & {`L1I_WAYS{icache_update_en}});
    assign l2i_itag_update_tag = icache_tag_stage2;
    assign l2i_itag_update_set = icache_set_stage2;
    assign l2i_itag_update_valid = !response_iinvalidate;

    // Wake up entries that have had their miss satisfied.
    assign icache_l2_response_valid = ack_for_me && response_stage2.cache_type == CT_ICACHE;
    assign dcache_l2_response_valid = ack_for_me && response_stage2.packet_type == L2RSP_LOAD_ACK
        && response_stage2.cache_type == CT_DCACHE;
    assign storebuf_l2_response_valid = ack_for_me
        && (response_stage2.packet_type == L2RSP_STORE_ACK
        || response_stage2.packet_type == L2RSP_FLUSH_ACK
        || response_stage2.packet_type == L2RSP_IINVALIDATE_ACK
        || response_stage2.packet_type == L2RSP_DINVALIDATE_ACK);
    assign dcache_l2_response_idx = response_stage2.id;
    assign icache_l2_response_idx = response_stage2.id;
    assign storebuf_l2_response_idx = response_stage2.id;
    assign storebuf_l2_sync_success = response_stage2.status;

    /////////////////////////////////////////////////
    // Response pipeline stage 3
    /////////////////////////////////////////////////

    always_ff @(posedge clk)
    begin
        l2i_ddata_update_way <= dupdate_way_idx;
        l2i_ddata_update_set <= dcache_set_stage2;
        l2i_ddata_update_data <= response_stage2.data;
        l2i_idata_update_way <= ift_fill_lru;
        l2i_idata_update_set <= icache_set_stage2;
        l2i_idata_update_data <= response_stage2.data;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            l2i_ddata_update_en <= '0;
            l2i_idata_update_en <= '0;
            // End of automatics
        end
        else
        begin
            // Make sure more than one snoop way isn't a hit
            assert(!response_stage2_valid || response_stage2.cache_type != CT_DCACHE
                || $onehot0(snoop_hit_way_oh));

            // Ensure only one dequeue type is set
            assert(!sq_dequeue_ready || $onehot0({sq_dequeue_flush, sq_dequeue_iinvalidate,
                sq_dequeue_dinvalidate}));

            // Can only send one request per cycle
            assert($onehot0({dcache_dequeue_ack, icache_dequeue_ack, storebuf_dequeue_ack}));

            // These are latched to delay then one cycle from the tag updates
            // Update cache line for data cache
            l2i_ddata_update_en <= dcache_update_en || (|snoop_hit_way_oh && response_stage2_valid
                && response_stage2.packet_type == L2RSP_STORE_ACK);

            // Update cache line for instruction cache
            l2i_idata_update_en <= icache_update_en;
        end
    end

    /////////////////////////////////////////////////
    // Request logic
    /////////////////////////////////////////////////

    always_comb
    begin
        l2i_request_valid = 0;
        l2i_request = 0;
        storebuf_dequeue_ack = 0;
        icache_dequeue_ack = 0;
        dcache_dequeue_ack = 0;
        l2i_perf_store = 0;

        l2i_request.core = CORE_ID;

        // Assert the request
        if (dcache_dequeue_ready)
        begin
            // Send data cache request packet
            l2i_request_valid = 1;
            l2i_request.packet_type = dcache_dequeue_sync ? L2REQ_LOAD_SYNC : L2REQ_LOAD;
            l2i_request.id = dcache_dequeue_idx;
            l2i_request.address = dcache_dequeue_addr;
            l2i_request.cache_type = CT_DCACHE;
            if (l2_ready)
                dcache_dequeue_ack = 1;
        end
        else if (icache_dequeue_ready)
        begin
            // Send instruction cache request packet
            l2i_request_valid = 1;
            l2i_request.packet_type = L2REQ_LOAD;
            l2i_request.id = icache_dequeue_idx;
            l2i_request.address = icache_dequeue_addr;
            l2i_request.cache_type = CT_ICACHE;
            if (l2_ready)
                icache_dequeue_ack = 1;
        end
        else if (sq_dequeue_ready)
        begin
            // Send store request
            l2i_request_valid = 1;
            if (sq_dequeue_flush)
                l2i_request.packet_type = L2REQ_FLUSH;
            else if (sq_dequeue_sync)
                l2i_request.packet_type = L2REQ_STORE_SYNC;
            else if (sq_dequeue_iinvalidate)
                l2i_request.packet_type = L2REQ_IINVALIDATE;
            else if (sq_dequeue_dinvalidate)
                l2i_request.packet_type = L2REQ_DINVALIDATE;
            else
                l2i_request.packet_type = L2REQ_STORE;

            l2i_request.id = sq_dequeue_idx;
            l2i_request.address = sq_dequeue_addr;
            l2i_request.data = sq_dequeue_data;
            l2i_request.store_mask = sq_dequeue_mask;
            l2i_request.cache_type = CT_DCACHE;
            if (l2_ready)
            begin
                storebuf_dequeue_ack = 1;
                l2i_perf_store = l2i_request.packet_type == L2REQ_STORE;
            end
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Tracks pending L1 misses. Detects and consolidates multiple misses
// for the same address. Wakes threads when loads complete.
//

module l1_load_miss_queue(
    input                                   clk,
    input                                   reset,

    // Enqueue request
    input                                   cache_miss,
    input cache_line_index_t                cache_miss_addr,
    input local_thread_idx_t                cache_miss_thread_idx,
    input                                   cache_miss_sync,

    // Dequeue request
    output logic                            dequeue_ready,
    input                                   dequeue_ack,
    output cache_line_index_t               dequeue_addr,
    output l1_miss_entry_idx_t              dequeue_idx,
    output logic                            dequeue_sync,

    // Wake
    input                                   l2_response_valid,
    input l1_miss_entry_idx_t               l2_response_idx,
    output local_thread_bitmap_t            wake_bitmap);

    struct packed {
        logic valid;
        logic request_sent;
        local_thread_bitmap_t waiting_threads;
        cache_line_index_t address;
        logic sync;
    } pending_entries[`THREADS_PER_CORE];

    local_thread_bitmap_t collided_miss_oh;
    local_thread_bitmap_t miss_thread_oh;
    logic request_unique;
    local_thread_bitmap_t send_grant_oh;
    local_thread_bitmap_t arbiter_request;
    local_thread_idx_t send_grant_idx;

    idx_to_oh #(.NUM_SIGNALS(`THREADS_PER_CORE)) idx_to_oh_miss_thread(
        .index(cache_miss_thread_idx),
        .one_hot(miss_thread_oh));

    rr_arbiter #(.NUM_REQUESTERS(`THREADS_PER_CORE)) request_arbiter(
        .request(arbiter_request),
        .update_lru(1'b1),
        .grant_oh(send_grant_oh),
        .*);

    oh_to_idx #(.NUM_SIGNALS(`THREADS_PER_CORE)) oh_to_idx_send_grant(
        .index(send_grant_idx),
        .one_hot(send_grant_oh));

    // Request out
    assign dequeue_ready = |arbiter_request;
    assign dequeue_addr = pending_entries[send_grant_idx].address;
    assign dequeue_idx = send_grant_idx;
    assign dequeue_sync = pending_entries[send_grant_idx].sync;

    assign request_unique = !(|collided_miss_oh);

    assign wake_bitmap = l2_response_valid ? pending_entries[l2_response_idx].waiting_threads : local_thread_bitmap_t'(0);

    genvar wait_entry;
    generate
        for (wait_entry = 0; wait_entry < `THREADS_PER_CORE; wait_entry++)
        begin : wait_logic_gen
            // Synchronized requests cannot be combined with other requests.
            assign collided_miss_oh[wait_entry] = pending_entries[wait_entry].valid
                && pending_entries[wait_entry].address == cache_miss_addr
                && !pending_entries[wait_entry].sync
                && !cache_miss_sync;
            assign arbiter_request[wait_entry] = pending_entries[wait_entry].valid
                && !pending_entries[wait_entry].request_sent;

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                    pending_entries[wait_entry] <= 0;
                else
                begin
                    if (dequeue_ack && send_grant_oh[wait_entry])
                    begin
                        // Send a new L2 request
                        pending_entries[wait_entry].request_sent <= 1;

                        // Ensure this doesn't dequeue an entry that has already been
                        // sent.
                        assert(pending_entries[wait_entry].valid);
                        assert(!pending_entries[wait_entry].request_sent);
                    end
                    else if (cache_miss && miss_thread_oh[wait_entry] && request_unique)
                    begin
                        // Enqueue a cache miss
                        pending_entries[wait_entry].waiting_threads <= miss_thread_oh;
                        pending_entries[wait_entry].valid <= 1;
                        pending_entries[wait_entry].address <= cache_miss_addr;
                        pending_entries[wait_entry].request_sent <= 0;
                        pending_entries[wait_entry].sync <= cache_miss_sync;

                        // Ensure this entry isn't already in use or a response
                        // isn't coming in this cycle (lower level logic should prevent
                        // the latter)
                        assert(!pending_entries[wait_entry].valid);
                        assert(!(l2_response_valid && l2_response_idx == l1_miss_entry_idx_t'(wait_entry)));
                    end
                    else if (l2_response_valid && l2_response_idx == l1_miss_entry_idx_t'(wait_entry))
                    begin
                        // Got an L2 response
                        pending_entries[wait_entry].valid <= 0;

                        // Ensure there isn't a response to an entry that isn't valid
                        // or hasn't been sent.
                        assert(pending_entries[wait_entry].valid);
                        assert(pending_entries[wait_entry].request_sent);
                    end

                    if (cache_miss && collided_miss_oh[wait_entry])
                    begin
                        // Miss is already pending, add waiting thread
                        pending_entries[wait_entry].waiting_threads <= pending_entries[wait_entry].waiting_threads
                            | miss_thread_oh;

                        // Upper level 'near_miss' logic prevents triggering a miss in the same
                        // cycle it is satisfied.
                        assert(!(l2_response_valid && l2_response_idx == l1_miss_entry_idx_t'(wait_entry)));
                    end
                end
            end
        end
    endgenerate

`ifdef SIMULATION
    always_ff @(posedge clk, posedge reset)
    begin
         if (!reset)
             assert($onehot0(collided_miss_oh));
    end
`endif
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Queues store requests from the instruction pipeline, sends store requests to
// L2 interconnect, and processes responses. Cache control commands go through
// here as well.
// A memory barrier request waits until all pending store requests finish.
// It acts like a store in terms of rollback logic, but doesn't enqueue
// anything.
//

module l1_store_queue(
    input                                  clk,
    input                                  reset,

    // To instruction_decode_stage
    output local_thread_bitmap_t           sq_store_sync_pending,

    // From dache_data_stage
    input                                  dd_store_en,
    input                                  dd_flush_en,
    input                                  dd_membar_en,
    input                                  dd_iinvalidate_en,
    input                                  dd_dinvalidate_en,
    input cache_line_index_t               dd_store_addr,
    input [CACHE_LINE_BYTES - 1:0]         dd_store_mask,
    input cache_line_data_t                dd_store_data,
    input                                  dd_store_sync,
    input local_thread_idx_t               dd_store_thread_idx,
    input cache_line_index_t               dd_store_bypass_addr,
    input local_thread_idx_t               dd_store_bypass_thread_idx,

    // To writeback_stage
    output logic [CACHE_LINE_BYTES - 1:0]  sq_store_bypass_mask,
    output cache_line_data_t               sq_store_bypass_data,
    output logic                           sq_store_sync_success,

    // From l1_l2_interface
    input                                  storebuf_dequeue_ack,
    input                                  storebuf_l2_response_valid,
    input l1_miss_entry_idx_t              storebuf_l2_response_idx,
    input                                  storebuf_l2_sync_success,

    // To l1_l2_interface
    output logic                           sq_dequeue_ready,
    output cache_line_index_t              sq_dequeue_addr,
    output l1_miss_entry_idx_t             sq_dequeue_idx,
    output logic[CACHE_LINE_BYTES - 1:0]   sq_dequeue_mask,
    output cache_line_data_t               sq_dequeue_data,
    output logic                           sq_dequeue_sync,
    output logic                           sq_dequeue_flush,
    output logic                           sq_dequeue_iinvalidate,
    output logic                           sq_dequeue_dinvalidate,
    output logic                           sq_rollback_en,
    output local_thread_bitmap_t           sq_wake_bitmap);

    struct packed {
        logic sync;
        logic flush;
        logic iinvalidate;
        logic dinvalidate;
        logic request_sent;
        logic response_received;
        logic sync_success;
        logic thread_waiting;
        logic valid;
        cache_line_data_t data;
        logic[CACHE_LINE_BYTES - 1:0] mask;
        cache_line_index_t address;
    } pending_stores[`THREADS_PER_CORE];
    local_thread_bitmap_t rollback;
    local_thread_bitmap_t send_request;
    local_thread_idx_t send_grant_idx;
    local_thread_bitmap_t send_grant_oh;

    rr_arbiter #(.NUM_REQUESTERS(`THREADS_PER_CORE)) request_arbiter(
        .request(send_request),
        .update_lru(1'b1),
        .grant_oh(send_grant_oh),
        .*);

    oh_to_idx #(.NUM_SIGNALS(`THREADS_PER_CORE)) oh_to_idx_send_grant(
        .index(send_grant_idx),
        .one_hot(send_grant_oh));

    genvar thread_idx;
    generate
        for (thread_idx = 0; thread_idx < `THREADS_PER_CORE; thread_idx++)
        begin : thread_store_buf_gen
            logic update_store_entry;
            logic can_write_combine;
            logic store_requested_this_entry;
            logic send_this_cycle;
            logic restarted_sync_request;
            logic got_response_this_entry;
            logic membar_requested_this_entry;
            logic enqueue_cache_control;

            assign send_request[thread_idx] = pending_stores[thread_idx].valid
                && !pending_stores[thread_idx].request_sent;
            assign store_requested_this_entry = dd_store_en && dd_store_thread_idx == local_thread_idx_t'(thread_idx);
            assign membar_requested_this_entry = dd_membar_en && dd_store_thread_idx == local_thread_idx_t'(thread_idx);
            assign send_this_cycle = send_grant_oh[thread_idx] && storebuf_dequeue_ack;
            assign can_write_combine = pending_stores[thread_idx].valid
                && pending_stores[thread_idx].address == dd_store_addr
                && !pending_stores[thread_idx].flush
                && !pending_stores[thread_idx].iinvalidate
                && !pending_stores[thread_idx].dinvalidate
                && !dd_store_sync
                && !pending_stores[thread_idx].request_sent
                && !send_this_cycle
                && !dd_flush_en
                && !dd_iinvalidate_en
                && !dd_dinvalidate_en;
            assign restarted_sync_request = pending_stores[thread_idx].valid
                && pending_stores[thread_idx].response_received
                && pending_stores[thread_idx].sync;
            assign update_store_entry = store_requested_this_entry
                && (!pending_stores[thread_idx].valid || can_write_combine || got_response_this_entry)
                && !restarted_sync_request;
            assign got_response_this_entry = storebuf_l2_response_valid
                && storebuf_l2_response_idx == local_thread_idx_t'(thread_idx);
            assign sq_wake_bitmap[thread_idx] = got_response_this_entry
                && pending_stores[thread_idx].thread_waiting;
            assign enqueue_cache_control = dd_store_thread_idx == local_thread_idx_t'(thread_idx)
                && (!pending_stores[thread_idx].valid || got_response_this_entry)
                && (dd_flush_en || dd_dinvalidate_en || dd_iinvalidate_en);
            assign sq_store_sync_pending[thread_idx] = pending_stores[thread_idx].valid
                && pending_stores[thread_idx].sync;

            always_comb
            begin
                rollback[thread_idx] = 0;
                if (dd_store_thread_idx == local_thread_idx_t'(thread_idx)
                     && (dd_flush_en || dd_dinvalidate_en || dd_iinvalidate_en || dd_store_en))
                begin
                    // Trigger a rollback if the store buffer is full.
                    // - On the first synchronized store request, always suspend the thread, even
                    //   when there is space in the buffer, because this must wait for a response.
                    // - If the store entry is full, but it got a response this cycle,
                    //   allow enqueuing a new one. This is simpler, because it avoids
                    //   needing to handle the lost wakeup issue (like the near miss case
                    //   in the data cache)
                    if (dd_store_sync)
                        rollback[thread_idx] = !restarted_sync_request;
                    else if (pending_stores[thread_idx].valid && !can_write_combine
                        && !got_response_this_entry)
                        rollback[thread_idx] = 1;
                end
                else if (membar_requested_this_entry && pending_stores[thread_idx].valid
                    && !got_response_this_entry)
                    rollback[thread_idx] = 1;
            end

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                    pending_stores[thread_idx] <= 0;
                else
                begin
                    if ((dd_store_en || dd_flush_en || dd_membar_en
                        || dd_iinvalidate_en || dd_dinvalidate_en)
                        && dd_store_thread_idx == thread_idx)
                    begin
                        // Can't issue a new request if the thread is waiting.
                        assert(!pending_stores[thread_idx].thread_waiting);
                    end

                    if (dd_store_en && dd_store_thread_idx == thread_idx
                        && pending_stores[thread_idx].sync
                        && pending_stores[thread_idx].valid)
                    begin
                        // A synchronized store is already pending for this thread.
                        // This must be the second pass to pick up the result. Ensure
                        // some constraints are true:

                        // The thread should be unblocked until the L2 cache responds.
                        assert(pending_stores[thread_idx].response_received);

                        // The restarted store should be synchronized
                        assert(dd_store_sync);

                        // The request should be for the same address.
                        assert(dd_store_addr == pending_stores[thread_idx].address);
                    end

                    if (send_this_cycle)
                        pending_stores[thread_idx].request_sent <= 1;

                    if (update_store_entry)
                    begin
                        assert(!enqueue_cache_control);

                        for (int byte_lane = 0; byte_lane < CACHE_LINE_BYTES; byte_lane++)
                        begin
                            if (dd_store_mask[byte_lane])
                                pending_stores[thread_idx].data[byte_lane * 8+:8] <= dd_store_data[byte_lane * 8+:8];
                        end

                        if (can_write_combine)
                            pending_stores[thread_idx].mask <= pending_stores[thread_idx].mask | dd_store_mask;
                        else
                            pending_stores[thread_idx].mask <= dd_store_mask;
                    end

                    if (sq_wake_bitmap[thread_idx])
                        pending_stores[thread_idx].thread_waiting <= 0;
                    else if (rollback[thread_idx])
                        pending_stores[thread_idx].thread_waiting <= 1;

                    if (store_requested_this_entry)
                    begin
                        // Attempt to enqueue a new request. This may happen the same cycle
                        // an old request is satisfied. In this case, replace the old entry.
                        if (restarted_sync_request)
                        begin
                            // This is the restarted request after a synchronized load/store.
                            // Clear the entry.
                            assert(pending_stores[thread_idx].response_received);
                            assert(!got_response_this_entry);
                            assert(!pending_stores[thread_idx].flush);
                            assert(!rollback[thread_idx]);
                            assert(dd_store_sync);    // Restarted instruction must be synchronized
                            assert(!enqueue_cache_control);
                            pending_stores[thread_idx].valid <= 0;
                        end
                        else if (update_store_entry && !can_write_combine)
                        begin
                            // New store

                            // Ensure this entry isn't in use (or that it is being cleared this
                            // cycle)
                            assert(!pending_stores[thread_idx].valid || got_response_this_entry);

                            assert(!enqueue_cache_control);

                            pending_stores[thread_idx].valid <= 1;
                            pending_stores[thread_idx].address <= dd_store_addr;
                            pending_stores[thread_idx].sync <= dd_store_sync;
                            pending_stores[thread_idx].flush <= 0;
                            pending_stores[thread_idx].iinvalidate <= 0;
                            pending_stores[thread_idx].dinvalidate <= 0;
                            pending_stores[thread_idx].request_sent <= 0;
                            pending_stores[thread_idx].response_received <= 0;
                        end
                    end
                    else if (enqueue_cache_control)
                    begin
                        assert(!rollback[thread_idx]);

                        pending_stores[thread_idx].valid <= 1;
                        pending_stores[thread_idx].address <= dd_store_addr;
                        pending_stores[thread_idx].sync <= 0;
                        pending_stores[thread_idx].flush <= dd_flush_en;
                        pending_stores[thread_idx].iinvalidate <= dd_iinvalidate_en;
                        pending_stores[thread_idx].dinvalidate <= dd_dinvalidate_en;
                        pending_stores[thread_idx].request_sent <= 0;
                        pending_stores[thread_idx].response_received <= 0;
                    end

                    // If this got a response *and* hasn't queued a new one over the top of it in the
                    // same cycle, clear it.
                    if (got_response_this_entry && (!store_requested_this_entry || !update_store_entry)
                        && !enqueue_cache_control)
                    begin
                        // Ensure a response isn't sent for an entry that hasn't been sent.
                        assert(pending_stores[thread_idx].valid);
                        assert(pending_stores[thread_idx].request_sent);

                        // Ensure a response isn't sent multiple times
                        assert(!pending_stores[thread_idx].response_received);

                        // When the L2 cache responds to a synchronized memory transaction, the
                        // entry is still valid until the thread wakes back up and retrives the
                        // result. If it is not synchronized, finish the transaction.
                        if (pending_stores[thread_idx].sync)
                        begin
                            pending_stores[thread_idx].response_received <= 1;
                            pending_stores[thread_idx].sync_success <= storebuf_l2_sync_success;
                        end
                        else
                            pending_stores[thread_idx].valid <= 0;
                    end
                end
            end
        end
    endgenerate

    // New request out.
    // XXX may want to register this to reduce latency.
    assign sq_dequeue_ready = |send_grant_oh;
    assign sq_dequeue_idx = send_grant_idx;
    assign sq_dequeue_addr = pending_stores[send_grant_idx].address;
    assign sq_dequeue_mask = pending_stores[send_grant_idx].mask;
    assign sq_dequeue_data = pending_stores[send_grant_idx].data;
    assign sq_dequeue_sync = pending_stores[send_grant_idx].sync;
    assign sq_dequeue_flush = pending_stores[send_grant_idx].flush;
    assign sq_dequeue_iinvalidate = pending_stores[send_grant_idx].iinvalidate;
    assign sq_dequeue_dinvalidate = pending_stores[send_grant_idx].dinvalidate;

    always_ff @(posedge clk)
    begin
        sq_store_bypass_data <= pending_stores[dd_store_bypass_thread_idx].data;
        if (dd_store_bypass_addr == pending_stores[dd_store_bypass_thread_idx].address
            && pending_stores[dd_store_bypass_thread_idx].valid
            && !pending_stores[dd_store_bypass_thread_idx].flush
            && !pending_stores[dd_store_bypass_thread_idx].iinvalidate
            && !pending_stores[dd_store_bypass_thread_idx].dinvalidate)
        begin
            // There is a store for this address, set mask
            sq_store_bypass_mask <= pending_stores[dd_store_bypass_thread_idx].mask;
        end
        else
            sq_store_bypass_mask <= 0;

        sq_store_sync_success <= pending_stores[dd_store_thread_idx].sync_success;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            sq_rollback_en <= '0;
            // End of automatics
        end
        else
        begin
            // Only one request can be active per cycle.
            assert($onehot0({dd_store_en, dd_flush_en, dd_membar_en, dd_iinvalidate_en,
                dd_dinvalidate_en}));

            // Check that above is true for dequeued entries
            assert(!sq_dequeue_ready || $onehot0({pending_stores[send_grant_idx].flush,
                pending_stores[send_grant_idx].dinvalidate, pending_stores[send_grant_idx].iinvalidate,
                pending_stores[send_grant_idx].sync}));

            // Can't assert wake and sleep signals in same cycle
            assert((sq_wake_bitmap & rollback) == 0);

            sq_rollback_en <= |rollback;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// L2 Bus Interface
// Receives L2 cache misses and writeback requests from the L2 pipeline and
// drives system memory interface to fulfill them. When fills complete,
// this reissues them to the L2 pipeline via the arbiter.
//
// If a load miss is already pending for a line, this set a flag on the FIFO
// entry that will skip the load. It will, however, still reissue it to the
// L2 pipeline.
//
// The interface to system memory is the AMBA AXI interface.
// http://www.arm.com/products/system-ip/amba-specifications.php
//
// I've tried to keep all bus logic consolidated in this module to make it
// easier to swap this out for other bus implementations (eg Wishbone).
//
// Todo: This should issue the address for the next bus transaction before it
// has finished the previous data transfer to improve utilization, especially
// in systems with larger memory latency.
//

module l2_axi_bus_interface(
    input                                  clk,
    input                                  reset,

    axi4_interface.master                  axi_bus,

    // To l2_cache_arb_stage
    output logic                           l2bi_request_valid,
    output l2req_packet_t                  l2bi_request,
    output cache_line_data_t               l2bi_data_from_memory,
    output logic                           l2bi_stall,
    output logic                           l2bi_collided_miss,

    // From l2_cache_read_stage
    input                                  l2r_needs_writeback,
    input l2_tag_t                         l2r_writeback_tag,
    input cache_line_data_t                l2r_data,
    input                                  l2r_l2_fill,
    input                                  l2r_restarted_flush,
    input                                  l2r_cache_hit,
    input                                  l2r_request_valid,
    input l2req_packet_t                   l2r_request,

    // To performance_counters
    output logic                           l2bi_perf_l2_writeback);

    typedef enum {
        STATE_IDLE,
        STATE_WRITE_ISSUE_ADDRESS,
        STATE_WRITE_TRANSFER,
        STATE_READ_ISSUE_ADDRESS,
        STATE_READ_TRANSFER,
        STATE_READ_COMPLETE
    } bus_interface_state_t;

    typedef struct packed {
        cache_line_index_t address;
        cache_line_data_t data;
        logic flush;
        core_id_t core;
        l1_miss_entry_idx_t id;
    } writeback_fifo_entry_t;

    localparam FIFO_SIZE = 8;

    // This is the number of stages before this one in the pipeline. Assert the
    // signal to stop accepting new packets this number of cycles early so
    // requests that are already in the L2 pipeline don't overrun the FIFOs.
    localparam L2REQ_LATENCY = 4;
    localparam BURST_BEATS = CACHE_LINE_BITS / `AXI_DATA_WIDTH;
    localparam BURST_OFFSET_WIDTH = $clog2(BURST_BEATS);

    l2_addr_t miss_addr;
    cache_line_index_t writeback_address;
    logic enqueue_writeback_request;
    logic enqueue_fill_request;
    logic duplicate_request;
    cache_line_data_t writeback_data;
    logic[`AXI_DATA_WIDTH - 1:0] writeback_lanes[BURST_BEATS];
    logic writeback_fifo_empty;
    logic fill_queue_empty;
    logic fill_request_pending;
    logic writeback_pending;
    logic writeback_complete;
    logic writeback_fifo_almost_full;
    logic fill_queue_almost_full;
    bus_interface_state_t state_ff;
    bus_interface_state_t state_nxt;
    logic[BURST_OFFSET_WIDTH - 1:0] burst_offset_ff;
    logic[BURST_OFFSET_WIDTH - 1:0] burst_offset_nxt;
    logic[`AXI_DATA_WIDTH - 1:0] fill_buffer[0:BURST_BEATS - 1];
    logic restart_flush_request;
    logic fill_dequeue_en;
    l2req_packet_t lmq_out_request;
    writeback_fifo_entry_t writeback_fifo_in;
    writeback_fifo_entry_t writeback_fifo_out;

    assign miss_addr = l2r_request.address;
    assign enqueue_writeback_request = l2r_request_valid && l2r_needs_writeback
        && ((l2r_request.packet_type == L2REQ_FLUSH && l2r_cache_hit && !l2r_restarted_flush)
        || l2r_l2_fill);
    assign enqueue_fill_request = l2r_request_valid && !l2r_cache_hit && !l2r_l2_fill
        && (l2r_request.packet_type == L2REQ_LOAD
        || l2r_request.packet_type == L2REQ_STORE
        || l2r_request.packet_type == L2REQ_LOAD_SYNC
        || l2r_request.packet_type == L2REQ_STORE_SYNC);
    assign writeback_pending = !writeback_fifo_empty;
    assign fill_request_pending = !fill_queue_empty;

    l2_cache_pending_miss_cam l2_cache_pending_miss_cam(
        .request_valid(l2r_request_valid),
        .request_addr({miss_addr.tag, miss_addr.set_idx}),
        .*);

    assign writeback_fifo_in.address = {l2r_writeback_tag, miss_addr.set_idx}; // Old address
    assign writeback_fifo_in.data = l2r_data; // Old line to writeback
    assign writeback_fifo_in.flush = l2r_request.packet_type == L2REQ_FLUSH;
    assign writeback_fifo_in.core = l2r_request.core;
    assign writeback_fifo_in.id = l2r_request.id;

    sync_fifo #(
        .WIDTH($bits(writeback_fifo_entry_t)),
        .SIZE(FIFO_SIZE),
        .ALMOST_FULL_THRESHOLD(FIFO_SIZE - L2REQ_LATENCY)
    ) pending_writeback_fifo(
        .clk(clk),
        .reset(reset),
        .flush_en(1'b0),
        .almost_full(writeback_fifo_almost_full),
        .enqueue_en(enqueue_writeback_request),
        .enqueue_value(writeback_fifo_in),
        .almost_empty(),
        .empty(writeback_fifo_empty),
        .dequeue_en(writeback_complete),
        .dequeue_value(writeback_fifo_out),
        .full(/* ignore */));

    assign writeback_address = writeback_fifo_out.address;
    assign writeback_data = writeback_fifo_out.data;

    sync_fifo #(
        .WIDTH($bits(l2req_packet_t) + 1),
        .SIZE(FIFO_SIZE),
        .ALMOST_FULL_THRESHOLD(FIFO_SIZE - L2REQ_LATENCY)
    ) pending_fill_fifo(
        .clk(clk),
        .reset(reset),
        .flush_en(1'b0),
        .almost_full(fill_queue_almost_full),
        .enqueue_en(enqueue_fill_request),
        .enqueue_value({duplicate_request, l2r_request}),
        .empty(fill_queue_empty),
        .almost_empty(),
        .dequeue_en(fill_dequeue_en),
        .dequeue_value({l2bi_collided_miss, lmq_out_request}),
        .full(/* ignore */));

    // Stop accepting new L2 packets until space is available in the queues
    assign l2bi_stall = fill_queue_almost_full || writeback_fifo_almost_full;

    // AMBA AXI and ACE Protocol Specification, rev E, A3.4.1:
    // length field is is burst length - 1
    assign axi_bus.m_awlen = 8'(BURST_BEATS - 1);
    assign axi_bus.m_arlen = 8'(BURST_BEATS - 1);
    assign axi_bus.m_bready = 1'b1;
    assign axi_bus.m_awprot = 3'b000;
    assign axi_bus.m_arprot = 3'b000;
    assign axi_bus.m_aclk = clk;
    assign axi_bus.m_aresetn = !reset;

    // Flatten array
    genvar fill_buffer_idx;
    generate
        for (fill_buffer_idx = 0; fill_buffer_idx < BURST_BEATS; fill_buffer_idx++)
        begin : mem_lane_gen
            assign l2bi_data_from_memory[fill_buffer_idx * `AXI_DATA_WIDTH+:`AXI_DATA_WIDTH]
                = fill_buffer[BURST_BEATS - fill_buffer_idx - 1];
        end
    endgenerate

    logic wait_axi_write_response;

    // Bus state machine
    always_comb
    begin
        state_nxt = state_ff;
        fill_dequeue_en = 0;
        burst_offset_nxt = burst_offset_ff;
        writeback_complete = 0;
        restart_flush_request = 0;

        unique case (state_ff)
            STATE_IDLE:
            begin
                // Writebacks take precendence over loads to avoid a race condition
                // where this loads stale data. Since loads can also enqueue writebacks,
                // it ensures this doesn't overrun the write FIFO.
                if (writeback_pending)
                begin
                    if (!wait_axi_write_response)
                        state_nxt = STATE_WRITE_ISSUE_ADDRESS;
                end
                else if (fill_request_pending)
                begin
                    if (l2bi_collided_miss
                        || (lmq_out_request.store_mask == {CACHE_LINE_BYTES{1'b1}}
                        && lmq_out_request.packet_type == L2REQ_STORE))
                    begin
                        // Skip the read and restart the request immediately if:
                        // 1. If there is already a pending L2 miss for this cache
                        //    line. Some other request has filled it, so
                        //    don't need to do anything but (try to) pick up the
                        //    result. That could result in another miss in some
                        //    cases, in which case must make another pass through
                        //    here.
                        // 2. It is a store that replaces the entire line.
                        //    Let this flow through the read miss queue instead
                        //    of handling it immediately in the pipeline
                        //    because it must go through the pending miss unit
                        //    to reconcile any other misses that may be in progress.
                        state_nxt = STATE_READ_COMPLETE;
                    end
                    else
                        state_nxt = STATE_READ_ISSUE_ADDRESS;
                end
            end

            STATE_WRITE_ISSUE_ADDRESS:
            begin
                burst_offset_nxt = 0;
                if (axi_bus.s_awready)
                    state_nxt = STATE_WRITE_TRANSFER;
            end

            STATE_WRITE_TRANSFER:
            begin
                if (axi_bus.s_wready)
                begin
                    if (burst_offset_ff == {BURST_OFFSET_WIDTH{1'b1}})
                    begin
                        writeback_complete = 1;
                        restart_flush_request = writeback_fifo_out.flush;
                        state_nxt = STATE_IDLE;
                    end

                    burst_offset_nxt = burst_offset_ff + BURST_OFFSET_WIDTH'(1);
                end
            end

            STATE_READ_ISSUE_ADDRESS:
            begin
                burst_offset_nxt = 0;
                if (axi_bus.s_arready)
                    state_nxt = STATE_READ_TRANSFER;
            end

            STATE_READ_TRANSFER:
            begin
                if (axi_bus.s_rvalid)
                begin
                    if (burst_offset_ff == {BURST_OFFSET_WIDTH{1'b1}})
                        state_nxt = STATE_READ_COMPLETE;

                    burst_offset_nxt = burst_offset_ff + BURST_OFFSET_WIDTH'(1);
                end
            end

            STATE_READ_COMPLETE:
            begin
                // Push the response back into the L2 pipeline
                state_nxt = STATE_IDLE;
                fill_dequeue_en = 1'b1;
            end
        endcase
    end

    genvar writeback_lane;
    generate
        for (writeback_lane = 0; writeback_lane < BURST_BEATS; writeback_lane++)
        begin : writeback_lane_gen
            assign writeback_lanes[writeback_lane] = writeback_data[
                writeback_lane * `AXI_DATA_WIDTH+:`AXI_DATA_WIDTH];
        end
    endgenerate

    always_comb
    begin
        l2bi_request = lmq_out_request;
        if (restart_flush_request)
        begin
            // For this request, the other fields in the request packet are ignored.
            // To avoid creating a mux for them, we just leave them assigned to
            // the load_reuqest fields.
            l2bi_request_valid = 1'b1;
            l2bi_request.packet_type = L2REQ_FLUSH;
            l2bi_request.core = writeback_fifo_out.core;
            l2bi_request.id = writeback_fifo_out.id;
            l2bi_request.cache_type = CT_DCACHE;
        end
        else
            l2bi_request_valid = fill_dequeue_en;
    end

    always_ff @(posedge clk, posedge reset)
    begin : update
        if (reset)
        begin
            state_ff <= STATE_IDLE;
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            axi_bus.m_arvalid <= '0;
            axi_bus.m_awvalid <= '0;
            axi_bus.m_rready <= '0;
            axi_bus.m_wlast <= '0;
            axi_bus.m_wvalid <= '0;
            burst_offset_ff <= '0;
            l2bi_perf_l2_writeback <= '0;
            wait_axi_write_response <= '0;
            // End of automatics
        end
        else
        begin
            state_ff <= state_nxt;
            burst_offset_ff <= burst_offset_nxt;

            // Write response state machine
            if (state_ff == STATE_WRITE_ISSUE_ADDRESS)
                wait_axi_write_response <= 1;
            else if (axi_bus.s_bvalid)
                wait_axi_write_response <= 0;

            // Register AXI output signals
            axi_bus.m_arvalid <= state_nxt == STATE_READ_ISSUE_ADDRESS;
            axi_bus.m_rready <= state_nxt == STATE_READ_TRANSFER;
            axi_bus.m_awvalid <= state_nxt == STATE_WRITE_ISSUE_ADDRESS;
            axi_bus.m_wvalid <= state_nxt == STATE_WRITE_TRANSFER;
            axi_bus.m_wlast <= state_nxt == STATE_WRITE_TRANSFER
                && burst_offset_nxt == BURST_OFFSET_WIDTH'(BURST_BEATS - 1);
            l2bi_perf_l2_writeback <= enqueue_writeback_request
                && !writeback_fifo_almost_full;
        end
    end

    always_ff @(posedge clk)
    begin
        if (state_ff == STATE_READ_TRANSFER && axi_bus.s_rvalid)
            fill_buffer[burst_offset_ff] <= axi_bus.s_rdata;

        axi_bus.m_araddr <= {l2bi_request.address, {CACHE_LINE_OFFSET_WIDTH{1'b0}}};
        axi_bus.m_awaddr <= {writeback_address, {CACHE_LINE_OFFSET_WIDTH{1'b0}}};
        axi_bus.m_wdata <= writeback_lanes[~burst_offset_nxt];
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// l2 request arbiter stage.
// Selects among core L2 requests and restarted request from fill interface.
// Restarted requests take precedence to avoid the miss queue filling up.
// l2_ready depends combinationally on the valid signals in the request
// packets, so valid bits must not be dependent on l2_ready to avoid a
// combinational loop.
//

module l2_cache_arb_stage(
    input                                 clk,
    input                                 reset,

    // From cores
    input [`NUM_CORES - 1:0]              l2i_request_valid,
    input l2req_packet_t                  l2i_request[`NUM_CORES],
    output logic                          l2_ready[`NUM_CORES],

    // To l2_cache_tag_stage
    output logic                          l2a_request_valid,
    output l2req_packet_t                 l2a_request,
    output cache_line_data_t              l2a_data_from_memory,
    output logic                          l2a_l2_fill,
    output logic                          l2a_restarted_flush,

    // From l2_axi_bus_interface
    input                                 l2bi_request_valid,
    input l2req_packet_t                  l2bi_request,
    input cache_line_data_t               l2bi_data_from_memory,
    input                                 l2bi_stall,
    input                                 l2bi_collided_miss);

    logic can_accept_request;
    l2req_packet_t grant_request;
    logic[`NUM_CORES - 1:0] grant_oh;
    logic restarted_flush;

    assign can_accept_request = !l2bi_request_valid && !l2bi_stall;
    assign restarted_flush = l2bi_request.packet_type == L2REQ_FLUSH;

    genvar request_idx;
    generate
        for (request_idx = 0; request_idx < `NUM_CORES; request_idx++)
        begin : handshake_gen
            assign l2_ready[request_idx] = grant_oh[request_idx] && can_accept_request;
        end
    endgenerate

    generate
        if (`NUM_CORES > 1)
        begin
            core_id_t grant_idx;

            rr_arbiter #(.NUM_REQUESTERS(`NUM_CORES)) request_arbiter(
                .request(l2i_request_valid),
                .update_lru(can_accept_request),
                .grant_oh(grant_oh),
                .*);

            oh_to_idx #(.NUM_SIGNALS(`NUM_CORES)) oh_to_idx_grant(
                .one_hot(grant_oh),
                .index(grant_idx[CORE_ID_WIDTH - 1:0]));

            assign grant_request = l2i_request[grant_idx[CORE_ID_WIDTH - 1:0]];
        end
        else
        begin
            // Single core
            assign grant_oh[0] = l2i_request_valid[0];
            assign grant_request = l2i_request[0];
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        l2a_data_from_memory <= l2bi_data_from_memory;
        if (l2bi_request_valid)
        begin
            // Restarted request from external bus interface
            l2a_request <= l2bi_request;
            l2a_l2_fill <= !l2bi_collided_miss && !restarted_flush;
            l2a_restarted_flush <= restarted_flush;
        end
        else
        begin
            // New request from a core
            l2a_request <= grant_request;
            l2a_l2_fill <= 0;
            l2a_restarted_flush <= 0;
        end
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            l2a_request_valid <= 0;
        else
        begin
            if (l2bi_request_valid)
            begin
                // Restarted request from external bus interface
                // These messages types should not cause a cache miss, and thus should
                // not be restarted
                assert(l2bi_request.packet_type != L2REQ_IINVALIDATE);
                assert(l2bi_request.packet_type != L2REQ_DINVALIDATE);
                l2a_request_valid <= 1;
            end
            else if (|l2i_request_valid && can_accept_request)
                l2a_request_valid <= 1;
            else
            begin
                // No request this cycle
                l2a_request_valid <= 0;
            end
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Tracks pending cache misses (fills) in the L2 cache pipeline.
// This module detects duplicate loads/stores in the system memory request
// queue. These not only waste memory bandwidth, but can cause data to be
// overwritten.
//
// Each time a cache miss goes past this unit, it records that it is pending.
// When a restarted request goes past, this clears the pending line.
// For each transaction, this asserts the 'duplicate_reqest' signal if
// another transaction for that line is pending.
//
// The pending miss for the line may be anywhere in the L2 pipeline,
// not just the l2 bus interface. Because of this, QUEUE_SIZE must be greater
// than or equal to the number of entries in the bus interface request queue
// + the number of pipeline stages.
//

module l2_cache_pending_miss_cam
    #(parameter QUEUE_SIZE = 16,
    parameter QUEUE_ADDR_WIDTH = $clog2(QUEUE_SIZE))
    (input                   clk,
    input                    reset,
    input                    request_valid,
    input cache_line_index_t request_addr,
    input                    enqueue_fill_request,
    input                    l2r_l2_fill,
    output logic             duplicate_request);

    logic[QUEUE_ADDR_WIDTH - 1:0] cam_hit_entry;
    logic cam_hit;
    logic[QUEUE_SIZE - 1:0] empty_entries;    // 1 if entry is empty
    logic[QUEUE_SIZE - 1:0] next_empty_oh;
    logic[QUEUE_ADDR_WIDTH - 1:0] next_empty;

    assign next_empty_oh = empty_entries & ~(empty_entries - QUEUE_SIZE'(1));

    oh_to_idx #(.NUM_SIGNALS(QUEUE_SIZE)) oh_to_idx_next_empty(
        .one_hot(next_empty_oh),
        .index(next_empty));

    assign duplicate_request = cam_hit && !l2r_l2_fill;

    cam #(
        .NUM_ENTRIES(QUEUE_SIZE),
        .KEY_WIDTH($bits(cache_line_index_t))
    ) cam_pending_miss(
        .clk(clk),
        .reset(reset),
        .lookup_key(request_addr),
        .lookup_idx(cam_hit_entry),
        .lookup_hit(cam_hit),
        .update_en(request_valid && (cam_hit ? l2r_l2_fill
            : enqueue_fill_request)),
        .update_key(request_addr),
        .update_idx(cam_hit ? cam_hit_entry : next_empty),
        .update_valid(cam_hit ? !l2r_l2_fill : enqueue_fill_request));

    always_ff @(posedge clk, posedge reset)
    begin
        // Make sure the queue isn't full
        assert(reset || empty_entries != 0);

        if (reset)
            empty_entries <= {QUEUE_SIZE{1'b1}};
        else if (cam_hit & l2r_l2_fill)
            empty_entries[cam_hit_entry] <= 1'b1;
        else if (!cam_hit && enqueue_fill_request)
            empty_entries[next_empty] <= 1'b0;
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// L2 cache pipeline - read stage
// - Checks for cache hit.
// - Drives signals to update LRU flags in previous stage.
// - Reads cache memory
//   * If this is a restarted cache fill request and the replaced line
//     is dirty, reads the old data to that this will write back to
//     system memory.
//   * If this is a cache flush request and this was a cache hit, reads
//     the data in the line to write back.
//   * If this is a cache hit, reads the data in the line.
// - Drives signals to update dirty flags in previous stage
//   * If this is a flush request, clears the dirty bit
//   * If this is a store request, sets the dirty bit
// - Drives signals to update tags in prevous stage if this is a cache fill.
// - Tracks synchronized load/store state.
//

module l2_cache_read_stage(
    input                                     clk,
    input                                     reset,

    // From l2_cache_tag_stage
    input                                     l2t_request_valid,
    input l2req_packet_t                      l2t_request,
    input                                     l2t_valid[`L2_WAYS],
    input l2_tag_t                            l2t_tag[`L2_WAYS],
    input                                     l2t_dirty[`L2_WAYS],
    input                                     l2t_l2_fill,
    input                                     l2t_restarted_flush,
    input l2_way_idx_t                        l2t_fill_way,
    input cache_line_data_t                   l2t_data_from_memory,

    // To l2_cache_tag_stage
    // Update metadata.
    output logic[`L2_WAYS - 1:0]              l2r_update_dirty_en,
    output l2_set_idx_t                       l2r_update_dirty_set,
    output logic                              l2r_update_dirty_value,
    output logic[`L2_WAYS - 1:0]              l2r_update_tag_en,
    output l2_set_idx_t                       l2r_update_tag_set,
    output logic                              l2r_update_tag_valid,
    output l2_tag_t                           l2r_update_tag_value,
    output logic                              l2r_update_lru_en,
    output l2_way_idx_t                       l2r_update_lru_hit_way,

    // From l2_cache_update_stage
    input                                     l2u_write_en,
    input [$clog2(`L2_WAYS * `L2_SETS) - 1:0] l2u_write_addr,
    input cache_line_data_t                   l2u_write_data,

    // To l2_cache_update_stage
    output logic                              l2r_request_valid,
    output l2req_packet_t                     l2r_request,
    output cache_line_data_t                  l2r_data,    // Also to bus interface unit
    output logic                              l2r_cache_hit,
    output logic[$clog2(`L2_WAYS * `L2_SETS) - 1:0] l2r_hit_cache_idx,
    output logic                              l2r_l2_fill,
    output logic                              l2r_restarted_flush,
    output cache_line_data_t                  l2r_data_from_memory,
    output logic                              l2r_store_sync_success,

    // To l2_axi_bus_interface
    output l2_tag_t                           l2r_writeback_tag,
    output logic                              l2r_needs_writeback,

    // To performance_counters
    output logic                              l2r_perf_l2_miss,
    output logic                              l2r_perf_l2_hit);

    localparam GLOBAL_THREAD_IDX_WIDTH = $clog2(TOTAL_THREADS);

    // Track synchronized load/stores, and determine if a synchronized store
    // was successful.
    cache_line_index_t load_sync_address[TOTAL_THREADS];
    logic load_sync_address_valid[TOTAL_THREADS];
    logic can_store_sync;

    logic[`L2_WAYS - 1:0] hit_way_oh;
    logic cache_hit;
    l2_way_idx_t hit_way_idx;
    logic[$clog2(`L2_WAYS * `L2_SETS) - 1:0] read_address;
    logic load;
    logic store;
    logic update_dirty;
    logic update_tag;
    logic flush_first_pass;
    l2_way_idx_t writeback_way;
    logic hit_or_miss;
    logic dinvalidate;
    l2_way_idx_t tag_update_way;
    logic[GLOBAL_THREAD_IDX_WIDTH - 1:0] request_sync_slot;

    assign load = l2t_request.packet_type == L2REQ_LOAD
        || l2t_request.packet_type == L2REQ_LOAD_SYNC;
    assign store = l2t_request.packet_type == L2REQ_STORE
        || l2t_request.packet_type == L2REQ_STORE_SYNC;
    assign writeback_way = l2t_request.packet_type == L2REQ_FLUSH
        ? hit_way_idx : l2t_fill_way;
    assign dinvalidate = l2t_request.packet_type == L2REQ_DINVALIDATE;

    //
    // Check for cache hit
    //
    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < `L2_WAYS; way_idx++)
        begin : hit_way_gen
            assign hit_way_oh[way_idx] = l2t_request.address.tag == l2t_tag[way_idx] && l2t_valid[way_idx];
        end
    endgenerate

    assign cache_hit = |hit_way_oh && l2t_request_valid;

    oh_to_idx #(.NUM_SIGNALS(`L2_WAYS)) oh_to_idx_hit_way(
        .one_hot(hit_way_oh),
        .index(hit_way_idx));

    // If this is a fill, read the old (potentially dirty line) so it
    // can be written back. If it is a cache hit, read the line data.
    assign read_address = {(l2t_l2_fill ? l2t_fill_way : hit_way_idx),
        l2t_request.address.set_idx};

    //
    // Cache memory
    //
    sram_1r1w #(
        .DATA_WIDTH(CACHE_LINE_BITS),
        .SIZE(`L2_WAYS * `L2_SETS),
        .READ_DURING_WRITE("NEW_DATA")
    ) sram_l2_data(
        .read_en(l2t_request_valid && (cache_hit || l2t_l2_fill)),
        .read_addr(read_address),
        .read_data(l2r_data),
        .write_en(l2u_write_en),
        .write_addr(l2u_write_addr),
        .write_data(l2u_write_data),
        .*);

    //
    // Update dirty bits. If this is a fill, initialize the dirty bit to the correct
    // value depending on whether this is a write. If it is a cache hit, update the
    // dirty bit only if this is a store.
    //
    assign flush_first_pass = l2t_request.packet_type == L2REQ_FLUSH
        && !l2t_restarted_flush;
    assign update_dirty = l2t_request_valid && (l2t_l2_fill
        || (cache_hit && (store || flush_first_pass)));
    assign l2r_update_dirty_set = l2t_request.address.set_idx;
    assign l2r_update_dirty_value = store;    // This is zero if this is a flush

    genvar dirty_update_idx;
    generate
        for (dirty_update_idx = 0; dirty_update_idx < `L2_WAYS; dirty_update_idx++)
        begin : dirty_update_gen
            assign l2r_update_dirty_en[dirty_update_idx] = update_dirty
                && (l2t_l2_fill ? l2t_fill_way == l2_way_idx_t'(dirty_update_idx)
                : hit_way_oh[dirty_update_idx]);
        end
    endgenerate

    //
    // Update tag memory. If this is a fill, make the new line valid. If it is an
    // invalidate make it invalid.
    //
    assign update_tag = l2t_l2_fill || (cache_hit && dinvalidate);
    assign tag_update_way = l2t_l2_fill ? l2t_fill_way : hit_way_idx;
    genvar tag_idx;
    generate
        for (tag_idx = 0; tag_idx < `L2_WAYS; tag_idx++)
        begin : tag_update_gen
            assign l2r_update_tag_en[tag_idx] = update_tag && tag_update_way == l2_way_idx_t'(tag_idx);
        end
    endgenerate

    assign l2r_update_tag_set = l2t_request.address.set_idx;
    assign l2r_update_tag_valid = !dinvalidate;
    assign l2r_update_tag_value = l2t_request.address.tag;

    //
    // Update LRU
    //
    assign l2r_update_lru_en = cache_hit && (load || store);
    assign l2r_update_lru_hit_way = hit_way_idx;

    //
    // Synchronized requests
    //
    assign request_sync_slot = GLOBAL_THREAD_IDX_WIDTH'({l2t_request.core, l2t_request.id});
    assign can_store_sync = load_sync_address[request_sync_slot]
        == {l2t_request.address.tag, l2t_request.address.set_idx}
        && load_sync_address_valid[request_sync_slot]
        && l2t_request.packet_type == L2REQ_STORE_SYNC;

    // Used for perf counters below
    assign hit_or_miss = l2t_request_valid
        && (l2t_request.packet_type == L2REQ_STORE || can_store_sync
        || l2t_request.packet_type == L2REQ_LOAD ) && !l2t_l2_fill;

    always_ff @(posedge clk)
    begin
        l2r_request <= l2t_request;
        l2r_cache_hit <= cache_hit;
        l2r_l2_fill <= l2t_l2_fill;
        l2r_writeback_tag <= l2t_tag[writeback_way];
        l2r_needs_writeback <= l2t_dirty[writeback_way] && l2t_valid[writeback_way];
        l2r_data_from_memory <= l2t_data_from_memory;
        l2r_hit_cache_idx <= read_address;
        l2r_restarted_flush <= l2t_restarted_flush;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            for (int i = 0; i < TOTAL_THREADS; i++)
            begin
                load_sync_address_valid[i] <= '0;
                load_sync_address[i] <= '0;
            end

            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            l2r_perf_l2_hit <= '0;
            l2r_perf_l2_miss <= '0;
            l2r_request_valid <= '0;
            l2r_store_sync_success <= '0;
            // End of automatics
        end
        else
        begin
            // A fill and cache hit cannot occur at the same time.
            assert(!l2t_l2_fill || !cache_hit);

            // Make sure there isn't a hit on more than one way
            assert(!l2t_request_valid || $onehot0(hit_way_oh));

            l2r_request_valid <= l2t_request_valid;

            if (l2t_request_valid && (cache_hit || l2t_l2_fill))
            begin
                // Track synchronized load/stores
                unique case (l2t_request.packet_type)
                    L2REQ_LOAD_SYNC:
                    begin
                        load_sync_address[request_sync_slot] <= {l2t_request.address.tag, l2t_request.address.set_idx};
                        load_sync_address_valid[request_sync_slot] <= 1;
                    end

                    L2REQ_STORE,
                    L2REQ_STORE_SYNC:
                    begin
                        // Don't invalidate if the sync store is not successful. Otherwise
                        // threads can livelock.
                        if (l2t_request.packet_type == L2REQ_STORE || can_store_sync)
                        begin
                            // Invalidate
                            for (int entry_idx = 0; entry_idx < TOTAL_THREADS; entry_idx++)
                            begin
                                if (load_sync_address[entry_idx] == {l2t_request.address.tag, l2t_request.address.set_idx})
                                    load_sync_address_valid[entry_idx] <= 0;
                            end
                        end
                    end

                    default:
                        ;
                endcase

                l2r_store_sync_success <= can_store_sync;
            end
            else
                l2r_store_sync_success <= 0;

            // Perf events
            l2r_perf_l2_miss <= hit_or_miss && !(|hit_way_oh);
            l2r_perf_l2_hit <= hit_or_miss && |hit_way_oh;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// The L2 cache has a four stage pipeline:
//  - Arbitrate: selects one request from cores, or a restarted request
//    (described below) to send to the next stage.
//  - Tag: issues address to tag ram ways, checks LRU.
//  - Read: checks for cache hit, reads cache memory
//  - Update: generates signals to update cache memory and broadcasts response
//    to cores.
// When the cache detects a cache miss (after the read stage), it puts it into
// a fill request queue. The system memory interface fetches the data, then
// restarts the request (with the new data) at the beginning of the L2 pipeline.
// If the evicted line has unwritten data, the read stage reads it from cache
// memory and puts it into a writeback queue in the system memory interface.
//
// The L2 cache is physically indexed/physically tagged, and thus all addresses
// used here are physical. Address translation is done by TLBs in the L1 caches.
//

module l2_cache(
    input                                 clk,
    input                                 reset,

    // From l1_l2_interface
    input [`NUM_CORES - 1:0]              l2i_request_valid,
    input l2req_packet_t                  l2i_request[`NUM_CORES],

    // To l1_l2_interface
    output logic                          l2_ready[`NUM_CORES],
    output logic                          l2_response_valid,
    output l2rsp_packet_t                 l2_response,

    // External bus interface
    axi4_interface.master                 axi_bus,

    // To performance_counters
    output logic[L2_PERF_EVENTS - 1:0]    l2_perf_events);

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    cache_line_data_t   l2a_data_from_memory;   // From l2_cache_arb_stage of l2_cache_arb_stage.v
    logic               l2a_l2_fill;            // From l2_cache_arb_stage of l2_cache_arb_stage.v
    l2req_packet_t      l2a_request;            // From l2_cache_arb_stage of l2_cache_arb_stage.v
    logic               l2a_request_valid;      // From l2_cache_arb_stage of l2_cache_arb_stage.v
    logic               l2a_restarted_flush;    // From l2_cache_arb_stage of l2_cache_arb_stage.v
    logic               l2bi_collided_miss;     // From l2_axi_bus_interface of l2_axi_bus_interface.v
    cache_line_data_t   l2bi_data_from_memory;  // From l2_axi_bus_interface of l2_axi_bus_interface.v
    logic               l2bi_perf_l2_writeback; // From l2_axi_bus_interface of l2_axi_bus_interface.v
    l2req_packet_t      l2bi_request;           // From l2_axi_bus_interface of l2_axi_bus_interface.v
    logic               l2bi_request_valid;     // From l2_axi_bus_interface of l2_axi_bus_interface.v
    logic               l2bi_stall;             // From l2_axi_bus_interface of l2_axi_bus_interface.v
    logic               l2r_cache_hit;          // From l2_cache_read_stage of l2_cache_read_stage.v
    cache_line_data_t   l2r_data;               // From l2_cache_read_stage of l2_cache_read_stage.v
    cache_line_data_t   l2r_data_from_memory;   // From l2_cache_read_stage of l2_cache_read_stage.v
    logic [$clog2(`L2_WAYS*`L2_SETS)-1:0] l2r_hit_cache_idx;// From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_l2_fill;            // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_needs_writeback;    // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_perf_l2_hit;        // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_perf_l2_miss;       // From l2_cache_read_stage of l2_cache_read_stage.v
    l2req_packet_t      l2r_request;            // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_request_valid;      // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_restarted_flush;    // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_store_sync_success; // From l2_cache_read_stage of l2_cache_read_stage.v
    logic [`L2_WAYS-1:0] l2r_update_dirty_en;   // From l2_cache_read_stage of l2_cache_read_stage.v
    l2_set_idx_t        l2r_update_dirty_set;   // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_update_dirty_value; // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_update_lru_en;      // From l2_cache_read_stage of l2_cache_read_stage.v
    l2_way_idx_t        l2r_update_lru_hit_way; // From l2_cache_read_stage of l2_cache_read_stage.v
    logic [`L2_WAYS-1:0] l2r_update_tag_en;     // From l2_cache_read_stage of l2_cache_read_stage.v
    l2_set_idx_t        l2r_update_tag_set;     // From l2_cache_read_stage of l2_cache_read_stage.v
    logic               l2r_update_tag_valid;   // From l2_cache_read_stage of l2_cache_read_stage.v
    l2_tag_t            l2r_update_tag_value;   // From l2_cache_read_stage of l2_cache_read_stage.v
    l2_tag_t            l2r_writeback_tag;      // From l2_cache_read_stage of l2_cache_read_stage.v
    cache_line_data_t   l2t_data_from_memory;   // From l2_cache_tag_stage of l2_cache_tag_stage.v
    logic               l2t_dirty [`L2_WAYS];   // From l2_cache_tag_stage of l2_cache_tag_stage.v
    l2_way_idx_t        l2t_fill_way;           // From l2_cache_tag_stage of l2_cache_tag_stage.v
    logic               l2t_l2_fill;            // From l2_cache_tag_stage of l2_cache_tag_stage.v
    l2req_packet_t      l2t_request;            // From l2_cache_tag_stage of l2_cache_tag_stage.v
    logic               l2t_request_valid;      // From l2_cache_tag_stage of l2_cache_tag_stage.v
    logic               l2t_restarted_flush;    // From l2_cache_tag_stage of l2_cache_tag_stage.v
    l2_tag_t            l2t_tag [`L2_WAYS];     // From l2_cache_tag_stage of l2_cache_tag_stage.v
    logic               l2t_valid [`L2_WAYS];   // From l2_cache_tag_stage of l2_cache_tag_stage.v
    logic [$clog2(`L2_WAYS*`L2_SETS)-1:0] l2u_write_addr;// From l2_cache_update_stage of l2_cache_update_stage.v
    cache_line_data_t   l2u_write_data;         // From l2_cache_update_stage of l2_cache_update_stage.v
    logic               l2u_write_en;           // From l2_cache_update_stage of l2_cache_update_stage.v
    // End of automatics

    l2_cache_arb_stage l2_cache_arb_stage(.*);
    l2_cache_tag_stage l2_cache_tag_stage(.*);
    l2_cache_read_stage l2_cache_read_stage(.*);
    l2_cache_update_stage l2_cache_update_stage(.*);

    l2_axi_bus_interface l2_axi_bus_interface(.*);

    // The number of signals in this assignment must match L2_PERF_EVENTS
    // in defines.sv.
    assign l2_perf_events = {
        l2r_perf_l2_hit,
        l2r_perf_l2_miss,
        l2bi_perf_l2_writeback
    };
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// L2 cache pipeline - tag stage.
// Performs tag lookup. Results will be available in the next stage.
// Also reads the LRU
//

module l2_cache_tag_stage(
    input                                 clk,
    input                                 reset,

    // From l2_cache_arb_stage
    input                                 l2a_request_valid,
    input l2req_packet_t                  l2a_request,
    input cache_line_data_t               l2a_data_from_memory,
    input                                 l2a_l2_fill,
    input                                 l2a_restarted_flush,

    // From l2_cache_read_stage
    input [`L2_WAYS - 1:0]                l2r_update_dirty_en,
    input l2_set_idx_t                    l2r_update_dirty_set,
    input                                 l2r_update_dirty_value,
    input [`L2_WAYS - 1:0]                l2r_update_tag_en,
    input l2_set_idx_t                    l2r_update_tag_set,
    input                                 l2r_update_tag_valid,
    input l2_tag_t                        l2r_update_tag_value,
    input                                 l2r_update_lru_en,
    input l2_way_idx_t                    l2r_update_lru_hit_way,

    // To l2_cache_read_stage
    output logic                          l2t_request_valid,
    output l2req_packet_t                 l2t_request,
    output logic                          l2t_valid[`L2_WAYS],
    output l2_tag_t                       l2t_tag[`L2_WAYS],
    output logic                          l2t_dirty[`L2_WAYS],
    output logic                          l2t_l2_fill,
    output l2_way_idx_t                   l2t_fill_way,
    output cache_line_data_t              l2t_data_from_memory,
    output logic                          l2t_restarted_flush);

    initial
    begin
        assert((`L2_SETS & (`L2_SETS - 1)) == 0);
    end

    cache_lru #(
        .NUM_SETS(`L2_SETS),
        .NUM_WAYS(`L2_WAYS)
    ) cache_lru(
        .fill_en(l2a_l2_fill),
        .fill_set(l2a_request.address.set_idx),
        .fill_way(l2t_fill_way),    // Output to next stage
        .access_en(l2a_request_valid),
        .access_set(l2a_request.address.set_idx),
        .update_en(l2r_update_lru_en),
        .update_way(l2r_update_lru_hit_way),
        .*);

    //
    // Way metadata
    //
    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < `L2_WAYS; way_idx++)
        begin : way_tags_gen
            logic line_valid[`L2_SETS];

            sram_1r1w #(
                .DATA_WIDTH($bits(l2_tag_t)),
                .SIZE(`L2_SETS),
                .READ_DURING_WRITE("NEW_DATA")
            ) sram_tags(
                .read_en(l2a_request_valid),
                .read_addr(l2a_request.address.set_idx),
                .read_data(l2t_tag[way_idx]),
                .write_en(l2r_update_tag_en[way_idx]),
                .write_addr(l2r_update_tag_set),
                .write_data(l2r_update_tag_value),
                .*);

            sram_1r1w #(
                .DATA_WIDTH(1),
                .SIZE(`L2_SETS),
                .READ_DURING_WRITE("NEW_DATA")
            ) sram_dirty_flags(
                .read_en(l2a_request_valid),
                .read_addr(l2a_request.address.set_idx),
                .read_data(l2t_dirty[way_idx]),
                .write_en(l2r_update_dirty_en[way_idx]),
                .write_addr(l2r_update_dirty_set),
                .write_data(l2r_update_dirty_value),
                .*);

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                begin
                    for (int set_idx = 0; set_idx < `L2_SETS; set_idx++)
                        line_valid[set_idx] <= 0;
                end
                else if (l2r_update_tag_en[way_idx])
                    line_valid[l2r_update_tag_set] <= l2r_update_tag_valid;
            end

            always_ff @(posedge clk)
            begin
                if (l2a_request_valid)
                begin
                    if (l2r_update_tag_en[way_idx] && l2r_update_tag_set
                        == l2a_request.address.set_idx)
                        l2t_valid[way_idx] <= l2r_update_tag_valid;    // Bypass
                    else
                        l2t_valid[way_idx] <= line_valid[l2a_request.address.set_idx];
                end
            end
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        l2t_data_from_memory <= l2a_data_from_memory;
        l2t_request <= l2a_request;
        l2t_l2_fill <= l2a_l2_fill;
        l2t_restarted_flush <= l2a_restarted_flush;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            l2t_request_valid <= 0;
        else
            l2t_request_valid <= l2a_request_valid;
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// L2 cache pipeline - update stage.
// - Update cache data if this is a cache fill or store.
//   This applies the store mask and requested data to the original data.
// - Sends response packet to cores.
//

module l2_cache_update_stage(
    input                                          clk,
    input                                          reset,

    // From l2_cache_read_stage
    input                                          l2r_request_valid,
    input l2req_packet_t                           l2r_request,
    input cache_line_data_t                        l2r_data,
    input                                          l2r_cache_hit,
    input logic[$clog2(`L2_WAYS * `L2_SETS) - 1:0] l2r_hit_cache_idx,
    input                                          l2r_l2_fill,
    input                                          l2r_restarted_flush,
    input cache_line_data_t                        l2r_data_from_memory,
    input                                          l2r_store_sync_success,
    input                                          l2r_needs_writeback,

    // To l2_cache_read_stage
    output logic                                   l2u_write_en,
    output logic[$clog2(`L2_WAYS * `L2_SETS) - 1:0] l2u_write_addr,
    output cache_line_data_t                       l2u_write_data,

    // To cores
    output logic                                   l2_response_valid,
    output l2rsp_packet_t                          l2_response);

    cache_line_data_t original_data;
    logic update_data;
    l2rsp_packet_type_t response_type;
    logic completed_flush;

    assign original_data = l2r_l2_fill ? l2r_data_from_memory : l2r_data;
    assign update_data = l2r_request.packet_type == L2REQ_STORE
        || (l2r_request.packet_type == L2REQ_STORE_SYNC && l2r_store_sync_success);

    genvar byte_lane;
    generate
        for (byte_lane = 0; byte_lane < CACHE_LINE_BYTES; byte_lane++)
        begin : lane_mask_gen
            assign l2u_write_data[byte_lane * 8+:8] = (l2r_request.store_mask[byte_lane] && update_data)
                ? l2r_request.data[byte_lane * 8+:8]
                : original_data[byte_lane * 8+:8];
        end
    endgenerate

    assign l2u_write_en = l2r_request_valid
        && (l2r_l2_fill || (l2r_cache_hit && (l2r_request.packet_type == L2REQ_STORE
        || l2r_request.packet_type == L2REQ_STORE_SYNC)));
    assign l2u_write_addr = l2r_hit_cache_idx;

    // Response packet type
    always_comb
    begin
        unique case (l2r_request.packet_type)
            L2REQ_LOAD,
            L2REQ_LOAD_SYNC:
                response_type = L2RSP_LOAD_ACK;

            L2REQ_STORE,
            L2REQ_STORE_SYNC:
                response_type = L2RSP_STORE_ACK;

            L2REQ_FLUSH:
                response_type = L2RSP_FLUSH_ACK;

            L2REQ_IINVALIDATE:
                response_type = L2RSP_IINVALIDATE_ACK;

            L2REQ_DINVALIDATE:
                response_type = L2RSP_DINVALIDATE_ACK;

            default:
                response_type = L2RSP_LOAD_ACK;
        endcase
    end

    // Check that this is either:
    // - The first pass for a flush request and the data wasn't in the cache
    // - The second pass for a flush request that has written its data back
    assign completed_flush = l2r_request.packet_type == L2REQ_FLUSH
        && (l2r_restarted_flush || !l2r_cache_hit || !l2r_needs_writeback);

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            l2_response_valid <= 0;
        else
        begin
            if (l2r_request_valid
                && ((l2r_cache_hit && l2r_request.packet_type != L2REQ_FLUSH)
                || l2r_l2_fill
                || completed_flush
                || l2r_request.packet_type == L2REQ_DINVALIDATE
                || l2r_request.packet_type == L2REQ_IINVALIDATE))
            begin
                // Restarted flush must have packet type L2REQ_FLUSH
                assert(!l2r_restarted_flush || l2r_request.packet_type == L2REQ_FLUSH);

                // Cannot be both a fill and restarted flush
                assert(!l2r_restarted_flush || !l2r_l2_fill);

                l2_response_valid <= 1;
            end
            else
                l2_response_valid <= 0;
        end
    end

    always_ff @(posedge clk)
    begin
        l2_response.status <= l2r_request.packet_type == L2REQ_STORE_SYNC
            ? l2r_store_sync_success : 1'b1;
        l2_response.core <= l2r_request.core;
        l2_response.id <= l2r_request.id;
        l2_response.packet_type <= response_type;
        l2_response.cache_type <= l2r_request.cache_type;
        l2_response.data <= l2u_write_data;
        l2_response.address <= l2r_request.address;
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Quick and dirty embedded logic analyzer
// BAUD_DIVIDE should be: clk rate / target baud rate
// Each cycle that capture_enable is asserted, capture_data is
// stored into a circular buffer. When trigger is asserted (it only
// needs to be asserted for one cycle), this will transmit the contents
// of the circular buffer over the UART. Each entry will be padded to a
// multiple of bytes and sent a byte at a time, starting at the least
// significant bit of capture_data.
//

module logic_analyzer
    #(parameter CAPTURE_WIDTH_BITS = 32,
    parameter CAPTURE_SIZE = 64,
    parameter BAUD_DIVIDE = 1)

    (input                          clk,
    input                           reset,
    input[CAPTURE_WIDTH_BITS - 1:0] capture_data,
    input                           capture_enable,
    input                           trigger,
    output logic                    uart_tx);

    localparam CAPTURE_INDEX_WIDTH = $clog2(CAPTURE_SIZE);
    localparam CAPTURE_WIDTH_BYTES = (CAPTURE_WIDTH_BITS + 7) / 8;

    localparam STATE_CAPTURE = 0;
    localparam STATE_DUMP = 1;
    localparam STATE_STOPPED = 2;

    logic[1:0] state;
    logic wrapped;
    logic[CAPTURE_INDEX_WIDTH - 1:0] capture_entry;
    logic[CAPTURE_INDEX_WIDTH - 1:0] dump_entry;
    logic[$clog2(CAPTURE_WIDTH_BYTES) - 1:0] dump_byte;
    logic[CAPTURE_INDEX_WIDTH - 1:0] dump_entry_nxt;
    logic[$clog2(CAPTURE_WIDTH_BYTES) - 1:0] dump_byte_nxt;
    logic tx_enable = 0;
    logic[7:0] tx_char;
    logic[CAPTURE_WIDTH_BITS - 1:0] dump_value;

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    logic               tx_ready;               // From uart_transmit of uart_transmit.v
    // End of automatics

    sram_1r1w #(.DATA_WIDTH(CAPTURE_WIDTH_BITS), .SIZE(CAPTURE_SIZE)) capture_mem(
        .clk(clk),
        .read_en(1'b1),
        .read_addr(dump_entry_nxt),
        .read_data(dump_value),
        .write_en(state == STATE_CAPTURE && capture_enable),
        .write_addr(capture_entry),
        .write_data(capture_data));

    uart_transmit #(.DIVISOR_WIDTH(12)) uart_transmit(
        .clocks_per_bit(50000000 / 921600),
        .tx_en(tx_enable), //dh
        .*);

    assign tx_char = dump_value[(dump_byte * 8)+:8];

    always_comb
    begin
        dump_entry_nxt = dump_entry;
        dump_byte_nxt = dump_byte;

        case (state)
            STATE_CAPTURE:
            begin
                if (trigger)
                begin
                    if (wrapped)
                        dump_entry_nxt = capture_entry + 1;
                    else
                        dump_entry_nxt = 0;

                    dump_byte_nxt = 0;
                end
            end

            STATE_DUMP:
            begin
                if (tx_ready)
                begin
                    if (dump_byte == CAPTURE_WIDTH_BYTES - 1)
                        dump_entry_nxt = dump_entry + 1;

                    if (tx_ready && tx_enable)
                    begin
                        if (dump_byte == CAPTURE_WIDTH_BYTES - 1)
                            dump_byte_nxt = 0;
                        else
                            dump_byte_nxt = dump_byte + 1;
                    end
                end
            end
        endcase
    end

    always_ff @(posedge clk, posedge reset)
    begin : update

        if (reset)
        begin
            state <= STATE_CAPTURE;
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            capture_entry <= '0;
            dump_byte <= '0;
            dump_entry <= '0;
            tx_enable <= '0;
            wrapped <= '0;
            // End of automatics
        end
        else
        begin
            case (state)
                STATE_CAPTURE:
                begin
                    // Capturing
                    if (capture_enable)
                    begin
                        capture_entry <= capture_entry + 1;
                        if (capture_entry == CAPTURE_SIZE- 1)
                            wrapped <= 1;
                    end

                    if (trigger)
                        state <= STATE_DUMP;
                end

                STATE_DUMP:
                begin
                    // Dumping
                    if (tx_ready)
                    begin
                        tx_enable <= 1;    // Note: delayed by one cycle (as is capture ram)

                        if (dump_entry == capture_entry)
                            state <= STATE_STOPPED;
                    end
                end

                STATE_STOPPED:
                    tx_enable <= 0;
            endcase

            dump_entry <= dump_entry_nxt;
            dump_byte <= dump_byte_nxt;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Top level block for processor. Contains all cores and L2 cache, connects
// to AXI system bus.
//

module nyuzi
    #(parameter RESET_PC = 0,
    parameter NUM_INTERRUPTS = 16)

    (input                          clk,
    input                           reset,
    axi4_interface.master           axi_bus,
    io_bus_interface.master         io_bus,
    jtag_interface.target           jtag,
    input [NUM_INTERRUPTS - 1:0]    interrupt_req);

    l2req_packet_t l2i_request[`NUM_CORES];
    logic[`NUM_CORES - 1:0] l2i_request_valid;
    ioreq_packet_t ior_request[`NUM_CORES];
    logic[`NUM_CORES - 1:0] ior_request_valid;
    logic[TOTAL_THREADS - 1:0] thread_en;
    scalar_t cr_data_to_host[`NUM_CORES];
    scalar_t data_to_host;
    logic[`NUM_CORES - 1:0] core_injected_complete;
    logic[`NUM_CORES - 1:0] core_injected_rollback;
    logic[`NUM_CORES - 1:0][TOTAL_THREADS - 1:0] core_suspend_thread;
    logic[`NUM_CORES - 1:0][TOTAL_THREADS - 1:0] core_resume_thread;
    logic[TOTAL_THREADS - 1:0] thread_suspend_mask;
    logic[TOTAL_THREADS - 1:0] thread_resume_mask;

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    logic               ii_ready [`NUM_CORES];  // From io_interconnect of io_interconnect.v
    iorsp_packet_t      ii_response;            // From io_interconnect of io_interconnect.v
    logic               ii_response_valid;      // From io_interconnect of io_interconnect.v
    logic               l2_ready [`NUM_CORES];  // From l2_cache of l2_cache.v
    l2rsp_packet_t      l2_response;            // From l2_cache of l2_cache.v
    logic               l2_response_valid;      // From l2_cache of l2_cache.v
    core_id_t           ocd_core;               // From on_chip_debugger of on_chip_debugger.v
    scalar_t            ocd_data_from_host;     // From on_chip_debugger of on_chip_debugger.v
    logic               ocd_data_update;        // From on_chip_debugger of on_chip_debugger.v
    logic               ocd_halt;               // From on_chip_debugger of on_chip_debugger.v
    logic               ocd_inject_en;          // From on_chip_debugger of on_chip_debugger.v
    scalar_t            ocd_inject_inst;        // From on_chip_debugger of on_chip_debugger.v
    local_thread_idx_t  ocd_thread;             // From on_chip_debugger of on_chip_debugger.v
    // End of automatics

    initial
    begin
        // Check config (see config.svh for rules)
        assert(`NUM_CORES >= 1 && `NUM_CORES <= (1 << CORE_ID_WIDTH));
        assert(`L1D_WAYS >= `THREADS_PER_CORE);
        assert(`L1I_WAYS >= `THREADS_PER_CORE);
    end

    // Thread enable
    always @*
    begin
        thread_suspend_mask = '0;
        thread_resume_mask = '0;
        for (int i = 0; i < `NUM_CORES; i++)
        begin
            thread_suspend_mask |= core_suspend_thread[i];
            thread_resume_mask |= core_resume_thread[i];
        end
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            thread_en <= 1;
        else
            thread_en <= (thread_en | thread_resume_mask) & ~thread_suspend_mask;
    end

    l2_cache l2_cache(
        .l2_perf_events(),
        .*);

    io_interconnect io_interconnect(.*);

    on_chip_debugger on_chip_debugger(
        .jtag(jtag),
        .injected_complete(|core_injected_complete),
        .injected_rollback(|core_injected_rollback),
        .*);

    generate
        if (`NUM_CORES > 1)
            assign data_to_host = cr_data_to_host[CORE_ID_WIDTH'(ocd_core)];
        else
            assign data_to_host = cr_data_to_host[0];
    endgenerate

    genvar core_idx;
    generate
        for (core_idx = 0; core_idx < `NUM_CORES; core_idx++)
        begin : core_gen
            core #(
                .CORE_ID(core_id_t'(core_idx)),
                .NUM_INTERRUPTS(NUM_INTERRUPTS),
                .RESET_PC(RESET_PC)
            ) core(
                .l2i_request_valid(l2i_request_valid[core_idx]),
                .l2i_request(l2i_request[core_idx]),
                .l2_ready(l2_ready[core_idx]),
                .thread_en(thread_en[core_idx * `THREADS_PER_CORE+:`THREADS_PER_CORE]),
                .ior_request_valid(ior_request_valid[core_idx]),
                .ior_request(ior_request[core_idx]),
                .ii_ready(ii_ready[core_idx]),
                .ii_response(ii_response),
                .cr_data_to_host(cr_data_to_host[core_idx]),
                .injected_complete(core_injected_complete[core_idx]),
                .injected_rollback(core_injected_rollback[core_idx]),
                .cr_suspend_thread(core_suspend_thread[core_idx]),
                .cr_resume_thread(core_resume_thread[core_idx]),
                .*);
        end
    endgenerate
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Convert a one-hot signal to a binary index corresponding to the active bit.
// (Binary encoder)
// If DIRECTION is "LSB0", index 0 corresponds to the least significant bit
// If "MSB0", index 0 corresponds to the most significant bit
//

module oh_to_idx
    #(parameter NUM_SIGNALS = 4,
    parameter DIRECTION = "LSB0",
    parameter INDEX_WIDTH = $clog2(NUM_SIGNALS))

    (input[NUM_SIGNALS - 1:0]         one_hot,
    output logic[INDEX_WIDTH - 1:0]   index);

    always_comb
    begin : convert
        index = 0;
        for (int oh_index = 0; oh_index < NUM_SIGNALS; oh_index++)
        begin
            if (one_hot[oh_index])
            begin
                if (DIRECTION == "LSB0")
                    index |= oh_index[INDEX_WIDTH - 1:0];    // Use 'or' to avoid synthesizing priority encoder
                else
                    index |= INDEX_WIDTH'(NUM_SIGNALS - oh_index - 1);
            end
        end
    end
endmodule
//
// Copyright 2017 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// On chip debugger (OCD) controller.
//
// This is experimental and a work in progress.
//
// This acts as an interface between an external JTAG host and the cores
// and exposes debugging functionality like reading and writing memory
// and registers. It works by allowing the host to inject instructions
// into a core's execution pipeline, and facilitating bidirectional data
// transfer between the host and target.
//
// There are two distinct types of signals labeled 'instruction' in this
// module: the contents of the JTAG instruction register, which determines
// the data register that is being transferred, and the machine instruction
// that is injected into the execution pipeline. Usually when comments
// refer to instructions, they mean the latter.
//
//  Limitations:
//  - If an instruction has to be rolled back (for example, cache miss), this
//    will not automatically restart it. The debugger should query the
//    status of the instruction and reissue it.
//  - If the instruction queue is full when this attempts to inject one, the
//    instruction will be lost. There's no way to detect this.
//  - When the halt signal is asserted, the processor will stop fetching new
//    instructions, but any instructions already in the pipeline or in instruction
//    queues will complete over subsequent cycles.
//  - As such, there's no way to immediately halt when an exception occurs.
//  - There's no provision for single stepping.
//  - This can't execute in "monitor mode," as the processor must be halted for it
//    to work.
//  - Halting between two issues of an uninterruptable instruction (sync memory op,
//    or I/O memory transfer), can put the processor into a bad state.
//  - Halting during a multi-cycle instruction (scatter/gather memory access)
//    causes undefined behavior.
//

module on_chip_debugger
    (input                          clk,
    input                           reset,

    jtag_interface.target           jtag,

    // To/From Cores
    output logic                    ocd_halt,
    output local_thread_idx_t       ocd_thread,
    output core_id_t                ocd_core,
    output scalar_t                 ocd_inject_inst,
    output logic                    ocd_inject_en,
    output scalar_t                 ocd_data_from_host,
    output logic                    ocd_data_update,
    input scalar_t                  data_to_host,
    input                           injected_complete,
    input                           injected_rollback);

    // JEDEC Standard Manufacturer's Identification Code standard, JEP-106
    // These constants are specified in config.sv
    localparam JTAG_IDCODE = {
        4'(`JTAG_PART_VERSION),
        16'(`JTAG_PART_NUMBER),
        11'(`JTAG_MANUFACTURER_ID),
        1'b1
    };

    typedef enum logic[1:0] {
        READY = 2'd0,
        ISSUED = 2'd1,
        ROLLED_BACK = 2'd2
    } machine_inst_status_t;

    typedef struct packed {
        core_id_t core;
        local_thread_idx_t thread;
        logic halt;
    } debug_control_t;

    typedef enum logic[3:0] {
        INST_IDCODE = 4'd0,
        INST_EXTEST = 4'd1,
        INST_INTEST = 4'd2,
        INST_CONTROL = 4'd3,
        INST_INJECT_INST = 4'd4,
        INST_TRANSFER_DATA = 4'd5,
        INST_STATUS = 4'd6,
        INST_BYPASS = 4'd15
    } jtag_instruction_t;

    logic data_shift_val;
    logic[31:0] data_shift_reg;
    debug_control_t control;
    machine_inst_status_t machine_inst_status;
    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    logic               capture_dr;             // From jtag_tap_controller of jtag_tap_controller.v
    logic [3:0]         jtag_instruction;       // From jtag_tap_controller of jtag_tap_controller.v
    logic               shift_dr;               // From jtag_tap_controller of jtag_tap_controller.v
    logic               update_dr;              // From jtag_tap_controller of jtag_tap_controller.v
    logic               update_ir;              // From jtag_tap_controller of jtag_tap_controller.v
    // End of automatics

    assign ocd_halt = control.halt;
    assign ocd_thread = control.thread;
    assign ocd_core = control.core;

    jtag_tap_controller #(.INSTRUCTION_WIDTH(4)) jtag_tap_controller(
        .jtag(jtag),
        .*);

    assign data_shift_val = data_shift_reg[0];
    assign ocd_inject_en = update_dr && jtag_instruction == INST_INJECT_INST;

    always @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            control <= '0;
            machine_inst_status <= READY;
        end
        else
        begin
            if (update_dr && jtag_instruction == INST_CONTROL)
                control <= debug_control_t'(data_shift_reg);

            // Only one of these can be asserted
            assert($onehot0({injected_rollback, injected_complete}));

            if (injected_rollback)
                machine_inst_status <= ROLLED_BACK;
            else if (injected_complete)
                machine_inst_status <= READY;
            else if (update_dr && jtag_instruction == INST_INJECT_INST)
                machine_inst_status <= ISSUED;
        end
    end

    // When ocd_data_update is asserted, the JTAG_DATA control register
    // will receive the value that was shifted into the TRANSFER_DATA
    // JTAG register.
    assign ocd_data_from_host = data_shift_reg;
    assign ocd_data_update = update_dr && jtag_instruction == INST_TRANSFER_DATA;

    always @(posedge clk)
    begin
        if (capture_dr)
        begin
            unique case (jtag_instruction)
                INST_IDCODE: data_shift_reg <= JTAG_IDCODE;
                INST_CONTROL: data_shift_reg <= 32'(control);
                INST_TRANSFER_DATA: data_shift_reg <= data_to_host;
                INST_STATUS: data_shift_reg <= 32'(machine_inst_status);
                default: data_shift_reg <= '0;
            endcase
        end
        else if (shift_dr)
        begin
            unique case (jtag_instruction)
                INST_BYPASS: data_shift_reg <= 32'(jtag.tdi);
                INST_CONTROL: data_shift_reg <= 32'({jtag.tdi, data_shift_reg[$bits(debug_control_t) - 1:1]});
                INST_STATUS: data_shift_reg <= 32'({jtag.tdi, data_shift_reg[$bits(machine_inst_status_t) - 1:1]});
                // Default covers any 32 bit transfer (most instructions)
                default: data_shift_reg <= 32'({jtag.tdi, data_shift_reg[31:1]});
            endcase
        end
        else if (update_dr)
        begin
            if (jtag_instruction == INST_INJECT_INST)
                ocd_inject_inst <= data_shift_reg;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Contains vector and scalar register files and fetches values
// from them.
//

module operand_fetch_stage(
    input                             clk,
    input                             reset,

    // From thread_select_stage
    input                             ts_instruction_valid,
    input decoded_instruction_t       ts_instruction,
    input local_thread_idx_t          ts_thread_idx,
    input subcycle_t                  ts_subcycle,

    // To fp_execute_stage1/int_execute_stage/dcache_tag_stage
    output vector_t                   of_operand1,
    output vector_t                   of_operand2,
    output vector_mask_t              of_mask_value,
    output vector_t                   of_store_value,
    output decoded_instruction_t      of_instruction,
    output logic                      of_instruction_valid,
    output local_thread_idx_t         of_thread_idx,
    output subcycle_t                 of_subcycle,

    // From writeback_stage
    input                             wb_rollback_en,
    input local_thread_idx_t          wb_rollback_thread_idx,
    input                             wb_writeback_en,
    input local_thread_idx_t          wb_writeback_thread_idx,
    input                             wb_writeback_vector,
    input vector_t                    wb_writeback_value,
    input vector_mask_t               wb_writeback_mask,
    input register_idx_t              wb_writeback_reg);

    scalar_t scalar_val1;
    scalar_t scalar_val2;
    vector_t vector_val1;
    vector_t vector_val2;

    sram_2r1w #(
        .DATA_WIDTH($bits(scalar_t)),
        .SIZE(32 * `THREADS_PER_CORE),
        .READ_DURING_WRITE("DONT_CARE")
    ) scalar_registers(
        .read1_en(ts_instruction_valid && ts_instruction.has_scalar1),
        .read1_addr({ts_thread_idx, ts_instruction.scalar_sel1}),
        .read1_data(scalar_val1),
        .read2_en(ts_instruction_valid && ts_instruction.has_scalar2),
        .read2_addr({ts_thread_idx, ts_instruction.scalar_sel2}),
        .read2_data(scalar_val2),
        .write_en(wb_writeback_en && !wb_writeback_vector),
        .write_addr({wb_writeback_thread_idx, wb_writeback_reg}),
        .write_data(wb_writeback_value[0]),
        .*);

    genvar lane;
    generate
        for (lane = 0; lane < NUM_VECTOR_LANES; lane++)
        begin : vector_lane_gen
            sram_2r1w #(
                .DATA_WIDTH($bits(scalar_t)),
                .SIZE(32 * `THREADS_PER_CORE),
                .READ_DURING_WRITE("DONT_CARE")
            ) vector_registers (
                .read1_en(ts_instruction.has_vector1),
                .read1_addr({ts_thread_idx, ts_instruction.vector_sel1}),
                .read1_data(vector_val1[lane]),
                .read2_en(ts_instruction.has_vector2),
                .read2_addr({ts_thread_idx, ts_instruction.vector_sel2}),
                .read2_data(vector_val2[lane]),
                .write_en(wb_writeback_en && wb_writeback_vector && wb_writeback_mask[NUM_VECTOR_LANES - lane - 1]),
                .write_addr({wb_writeback_thread_idx, wb_writeback_reg}),
                .write_data(wb_writeback_value[lane]),
                .*);
        end
    endgenerate

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            of_instruction_valid <= 0;
        else
        begin
            of_instruction_valid <= ts_instruction_valid
                && (!wb_rollback_en || wb_rollback_thread_idx != ts_thread_idx);
        end
    end

    always_ff @(posedge clk)
    begin
        of_instruction <= ts_instruction;
        of_thread_idx <= ts_thread_idx;
        of_subcycle <= ts_subcycle;
    end

    assign of_store_value = of_instruction.store_value_vector
            ? vector_val2
            : {{NUM_VECTOR_LANES - 1{32'd0}}, scalar_val2};

    always_comb
    begin
        unique case (of_instruction.op1_src)
            OP1_SRC_VECTOR1: of_operand1 = vector_val1;
            default:         of_operand1 = {NUM_VECTOR_LANES{scalar_val1}};    // OP_SRC_SCALAR1
        endcase

        unique case (of_instruction.op2_src)
            OP2_SRC_SCALAR2: of_operand2 = {NUM_VECTOR_LANES{scalar_val2}};
            OP2_SRC_VECTOR2: of_operand2 = vector_val2;
            default:         of_operand2 = {NUM_VECTOR_LANES{of_instruction.immediate_value}}; // OP2_SRC_IMMEDIATE
        endcase

        unique case (of_instruction.mask_src)
            MASK_SRC_SCALAR1: of_mask_value = scalar_val1[NUM_VECTOR_LANES - 1:0];
            MASK_SRC_SCALAR2: of_mask_value = scalar_val2[NUM_VECTOR_LANES - 1:0];
            default:          of_mask_value = {NUM_VECTOR_LANES{1'b1}};    // MASK_SRC_ALL_ONES
        endcase
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Collects statistics from various modules used for performance measuring and tuning.
// Counts the number of discrete events in each category.
//

module performance_counters
    #(parameter NUM_EVENTS = 1,
    parameter EVENT_IDX_WIDTH = $clog2(NUM_EVENTS),
    parameter NUM_COUNTERS = 2,
    parameter COUNTER_IDX_WIDTH = $clog2(NUM_COUNTERS))

    (input                                              clk,
    input                                               reset,
    input [NUM_EVENTS - 1:0]                            perf_events,
    input [NUM_COUNTERS - 1:0][EVENT_IDX_WIDTH - 1:0]   perf_event_select,
    output logic [NUM_COUNTERS - 1:0][63:0]                   perf_event_count); // dh: this originally was set to wire, why?

    always_ff @(posedge clk, posedge reset)
    begin : update
        if (reset)
        begin
            for (int i = 0; i < NUM_COUNTERS; i++)
                perf_event_count[i] <= 0;
        end
        else
        begin
            for (int i = 0; i < NUM_COUNTERS; i++)
            begin
                if (perf_events[perf_event_select[i]])
                    perf_event_count[i] <= perf_event_count[i] + 1;
            end
        end
    end
endmodule
//
// Copyright 2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// PS/2 keyboard or mouse controller. Only supports receiving.
//

module ps2_controller
    #(parameter BASE_ADDRESS = 0)

    (input                      clk,
    input                       reset,
    io_bus_interface.slave      io_bus,
    output logic                rx_interrupt,

    // PS/2 Interface
    input                       ps2_clk,
    input                       ps2_data);

    localparam STATUS_REG = BASE_ADDRESS;
    localparam DATA_REG = BASE_ADDRESS + 4;
    localparam FIFO_LENGTH = 16;

    typedef enum logic[1:0] {
        STATE_WAIT_START,
        STATE_READ_CHARACTER,
        STATE_READ_PARITY,
        STATE_READ_STOP_BIT
    } receive_state_t;

    logic ps2_clk_sync;
    logic ps2_data_sync;
    logic ps2_clk_prev;
    receive_state_t state_ff;
    logic[2:0] bit_count;
    logic[7:0] receive_byte;
    logic[7:0] dequeue_data;
    logic read_fifo_empty;
    logic fifo_almost_full;
    logic enqueue_en;

    assign rx_interrupt = !read_fifo_empty;

    synchronizer #(.WIDTH(2), .RESET_STATE(2'b11)) input_synchronizer(
        .data_i({ps2_clk, ps2_data}),
        .data_o({ps2_clk_sync, ps2_data_sync}),
        .*);

    // If the FIFO hits the almost full threshold, we dequeue an entry (dropping the oldest
    // character). Use the almost full threshold instead of full because the Altera specs
    // say it is not allowed to enqueue into a full FIFO. Although it seems like this should
    // be legal if read is also asserted, I'm being conservative.
    sync_fifo #(.WIDTH(8), .SIZE(FIFO_LENGTH), .ALMOST_FULL_THRESHOLD(FIFO_LENGTH - 1)) input_fifo(
        .flush_en(0),
        .full(),
        .almost_full(fifo_almost_full),
        .enqueue_en(enqueue_en),
        .enqueue_value(receive_byte),
        .empty(read_fifo_empty),
        .almost_empty(),
        .dequeue_en((io_bus.read_en && io_bus.address == DATA_REG && !read_fifo_empty) || fifo_almost_full),
        .dequeue_value(dequeue_data),
        .*);

    always @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            ps2_clk_prev <= 1;
            state_ff <= STATE_WAIT_START;
            bit_count <= 0;
            enqueue_en <= 0;
        end
        else
        begin
            if (io_bus.address == STATUS_REG)
                io_bus.read_data <= scalar_t'(!read_fifo_empty);
            else
                io_bus.read_data <= scalar_t'(dequeue_data);

            ps2_clk_prev <= ps2_clk_sync;
            enqueue_en <= 0;
            if (ps2_clk_sync == 0 && ps2_clk_prev == 1)
            begin
                // Valid data on the falling edge
                case (state_ff)
                    STATE_WAIT_START:
                    begin
                        if (ps2_data_sync == 0)
                        begin
                            state_ff <= STATE_READ_CHARACTER;
                            bit_count <= 0;
                        end
                    end

                    STATE_READ_CHARACTER:
                    begin
                        bit_count <= bit_count + 3'd1;
                        if (bit_count == 7)
                            state_ff <= STATE_READ_PARITY;

                        receive_byte <= {ps2_data_sync, receive_byte[7:1]};
                    end

                    STATE_READ_PARITY:
                    begin
                        // XXX not checking parity

                        state_ff <= STATE_READ_STOP_BIT;
                    end

                    STATE_READ_STOP_BIT:
                    begin
                        // XXX not checking that stop bit is high

                        state_ff <= STATE_WAIT_START;
                        enqueue_en <= 1;
                    end
                endcase
            end
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// This file is autogenerated by tools/misc/make_reciprocal_rom.py
//

module reciprocal_rom(
    input [5:0] significand,
    output logic[5:0] reciprocal_estimate);

    always_comb
    begin
        case (significand)
            6'h0: reciprocal_estimate = 6'h0;
            6'h1: reciprocal_estimate = 6'h3e;
            6'h2: reciprocal_estimate = 6'h3c;
            6'h3: reciprocal_estimate = 6'h3a;
            6'h4: reciprocal_estimate = 6'h38;
            6'h5: reciprocal_estimate = 6'h36;
            6'h6: reciprocal_estimate = 6'h35;
            6'h7: reciprocal_estimate = 6'h33;
            6'h8: reciprocal_estimate = 6'h31;
            6'h9: reciprocal_estimate = 6'h30;
            6'ha: reciprocal_estimate = 6'h2e;
            6'hb: reciprocal_estimate = 6'h2d;
            6'hc: reciprocal_estimate = 6'h2b;
            6'hd: reciprocal_estimate = 6'h2a;
            6'he: reciprocal_estimate = 6'h29;
            6'hf: reciprocal_estimate = 6'h27;
            6'h10: reciprocal_estimate = 6'h26;
            6'h11: reciprocal_estimate = 6'h25;
            6'h12: reciprocal_estimate = 6'h23;
            6'h13: reciprocal_estimate = 6'h22;
            6'h14: reciprocal_estimate = 6'h21;
            6'h15: reciprocal_estimate = 6'h20;
            6'h16: reciprocal_estimate = 6'h1f;
            6'h17: reciprocal_estimate = 6'h1e;
            6'h18: reciprocal_estimate = 6'h1d;
            6'h19: reciprocal_estimate = 6'h1c;
            6'h1a: reciprocal_estimate = 6'h1b;
            6'h1b: reciprocal_estimate = 6'h1a;
            6'h1c: reciprocal_estimate = 6'h19;
            6'h1d: reciprocal_estimate = 6'h18;
            6'h1e: reciprocal_estimate = 6'h17;
            6'h1f: reciprocal_estimate = 6'h16;
            6'h20: reciprocal_estimate = 6'h15;
            6'h21: reciprocal_estimate = 6'h14;
            6'h22: reciprocal_estimate = 6'h13;
            6'h23: reciprocal_estimate = 6'h12;
            6'h24: reciprocal_estimate = 6'h11;
            6'h25: reciprocal_estimate = 6'h11;
            6'h26: reciprocal_estimate = 6'h10;
            6'h27: reciprocal_estimate = 6'hf;
            6'h28: reciprocal_estimate = 6'he;
            6'h29: reciprocal_estimate = 6'he;
            6'h2a: reciprocal_estimate = 6'hd;
            6'h2b: reciprocal_estimate = 6'hc;
            6'h2c: reciprocal_estimate = 6'hb;
            6'h2d: reciprocal_estimate = 6'hb;
            6'h2e: reciprocal_estimate = 6'ha;
            6'h2f: reciprocal_estimate = 6'h9;
            6'h30: reciprocal_estimate = 6'h9;
            6'h31: reciprocal_estimate = 6'h8;
            6'h32: reciprocal_estimate = 6'h7;
            6'h33: reciprocal_estimate = 6'h7;
            6'h34: reciprocal_estimate = 6'h6;
            6'h35: reciprocal_estimate = 6'h6;
            6'h36: reciprocal_estimate = 6'h5;
            6'h37: reciprocal_estimate = 6'h4;
            6'h38: reciprocal_estimate = 6'h4;
            6'h39: reciprocal_estimate = 6'h3;
            6'h3a: reciprocal_estimate = 6'h3;
            6'h3b: reciprocal_estimate = 6'h2;
            6'h3c: reciprocal_estimate = 6'h2;
            6'h3d: reciprocal_estimate = 6'h1;
            6'h3e: reciprocal_estimate = 6'h1;
            6'h3f: reciprocal_estimate = 6'h0;
            default: reciprocal_estimate = 6'h0;
        endcase
    end
endmodule

//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Round robin arbiter
// Units that want to access a shared resource assert their bit in the 'request'
// bitmap. The arbiter picks a unit and sets the appropriate bit in the one hot
// signal grant_oh. This does not register grant_oh, which is valid the same
// cycle as the request. The update_lru signal indicates the granted unit has
// used the resource and should not receive access again until other requestors
// have had a turn.
//

module rr_arbiter
    #(parameter NUM_REQUESTERS = 4)

    (input                              clk,
    input                               reset,
    input[NUM_REQUESTERS - 1:0]         request,
    input                               update_lru,
    output logic[NUM_REQUESTERS - 1:0]  grant_oh);

    logic[NUM_REQUESTERS - 1:0] priority_oh_nxt;
    logic[NUM_REQUESTERS - 1:0] priority_oh;

    localparam BIT_IDX_WIDTH = $clog2(NUM_REQUESTERS);

    always_comb
    begin
        for (int grant_idx = 0; grant_idx < NUM_REQUESTERS; grant_idx++)
        begin
            grant_oh[grant_idx] = 0;
            for (int priority_idx = 0; priority_idx < NUM_REQUESTERS; priority_idx++)
            begin
                logic granted;

                granted = request[grant_idx] & priority_oh[priority_idx];
                for (logic[BIT_IDX_WIDTH - 1:0] bit_idx = priority_idx[BIT_IDX_WIDTH - 1:0];
                    bit_idx != grant_idx[BIT_IDX_WIDTH - 1:0]; bit_idx++)
                begin
                    granted &= !request[bit_idx];
                end

                grant_oh[grant_idx] |= granted;
            end
        end
    end

    // rotate left
    assign priority_oh_nxt = {grant_oh[NUM_REQUESTERS - 2:0],
        grant_oh[NUM_REQUESTERS - 1]};

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            priority_oh <= 1;
        else if (request != 0 && update_lru)
        begin
            assert($onehot0(priority_oh_nxt));
            priority_oh <= priority_oh_nxt;
        end
    end
endmodule
//
// Copyright 2011-2017 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// The scoreboard tracks register dependencies betwen instructions
// issued by the same thread. For example, if a thread issued the
// following instructions in sequence:
//
//   add_i s0, s1, s2
//   add_i s3, s0, s4
//
// The second instruction has a read-after-write (RAW) dependency on s0.
// It cannot be issued until the first instruction completes.
// This works by keeping a bitmap for all registers and marking the destination
// for each instruction as 'busy' when it is issued. When checking if the next
// instruction can be issued, it looks at the source registers and halts
// if the busy bit is set for any of them.
//

module scoreboard(
    input                           clk,
    input                           reset,
    input decoded_instruction_t     next_instruction,
    output logic                    scoreboard_can_issue,
    input                           will_issue,
    input                           writeback_en,
    input                           wb_writeback_vector,
    input register_idx_t            wb_writeback_reg,
    input                           rollback_en,
    input pipeline_sel_t            wb_rollback_pipeline);

    localparam SCOREBOARD_ENTRIES = NUM_REGISTERS * 2;

    // This represents the longest path between the thread select and
    // writeback stages:
    // operand_fetch -> dcache_tag -> dcache_data -> writeback
    // It does not include the floating point pipeline, as that does not
    // generate traps.
    localparam ROLLBACK_STAGES = 4;

    typedef logic[SCOREBOARD_ENTRIES - 1:0] scoreboard_bitmap_t;
    typedef logic[5:0] ext_register_idx_t;  // 0-31 are scalar, 32-63 vector

    logic[ROLLBACK_STAGES - 1:0] has_writeback;
    ext_register_idx_t writeback_reg[ROLLBACK_STAGES];
    scoreboard_bitmap_t scoreboard_regs;
    scoreboard_bitmap_t scoreboard_regs_nxt;
    scoreboard_bitmap_t dest_bitmap;
    scoreboard_bitmap_t dep_bitmap;
    scoreboard_bitmap_t rollback_bitmap;
    scoreboard_bitmap_t writeback_bitmap;
    scoreboard_bitmap_t clear_bitmap;
    scoreboard_bitmap_t set_bitmap;

    // Handle rollback for a thread (for example, if it takes a branch)
    // Why not just clear the entire scoreboard?
    // - Instructions in the floating point pipeline *after* the stage that
    //   issues the rollback should still retire (thus their destinations
    //   are still pending).
    // - Likewise for memory instructions when the integer pipeline causes
    //   a rollback.
    always_comb
    begin
        rollback_bitmap = 0;
        if (rollback_en)
        begin
            for (int i = 0; i < ROLLBACK_STAGES - 1; i++)
                if (has_writeback[i])
                    rollback_bitmap[writeback_reg[i]] = 1;

            // The memory pipeline is one stage longer than the integer
            // pipeline, so include that stage if it generated the rollback.
            if (has_writeback[ROLLBACK_STAGES - 1]
                && wb_rollback_pipeline == PIPE_MEM)
                rollback_bitmap[writeback_reg[ROLLBACK_STAGES - 1]] = 1;
        end
    end

    // Dependencies
    always_comb
    begin
        dep_bitmap = 0;
        if (next_instruction.has_dest)
        begin
            if (next_instruction.dest_vector)
                dep_bitmap[{1'b1, next_instruction.dest_reg}] = 1;
            else
                dep_bitmap[{1'b0, next_instruction.dest_reg}] = 1;
        end

        if (next_instruction.has_scalar1)
            dep_bitmap[{1'b0, next_instruction.scalar_sel1}] = 1;

        if (next_instruction.has_scalar2)
            dep_bitmap[{1'b0, next_instruction.scalar_sel2}] = 1;

        if (next_instruction.has_vector1)
            dep_bitmap[{1'b1, next_instruction.vector_sel1}] = 1;

        if (next_instruction.has_vector2)
            dep_bitmap[{1'b1, next_instruction.vector_sel2}] = 1;
    end

    // Destination
    always_comb
    begin
        dest_bitmap = 0;
        if (next_instruction.has_dest)
        begin
            if (next_instruction.dest_vector)
                dest_bitmap[{1'b1, next_instruction.dest_reg}] = 1;
            else
                dest_bitmap[{1'b0, next_instruction.dest_reg}] = 1;
        end
    end

    // Registers to clear when a writeback occurs
    always_comb
    begin
        writeback_bitmap = 0;
        if (writeback_en)
        begin
            if (wb_writeback_vector)
                writeback_bitmap[{1'b1, wb_writeback_reg}] = 1;
            else
                writeback_bitmap[{1'b0, wb_writeback_reg}] = 1;
        end
    end

    assign clear_bitmap = rollback_bitmap | writeback_bitmap;
    assign set_bitmap = dest_bitmap
        & {SCOREBOARD_ENTRIES{will_issue}};
    assign scoreboard_regs_nxt = (scoreboard_regs & ~clear_bitmap)
        | set_bitmap;
    assign scoreboard_can_issue = (scoreboard_regs & dep_bitmap) == 0;

    always @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            scoreboard_regs <= '0;
            has_writeback <= '0;
        end
        else
        begin
            scoreboard_regs <= scoreboard_regs_nxt;
            has_writeback <= {has_writeback[ROLLBACK_STAGES - 2:0],
                will_issue && next_instruction.has_dest};
        end
    end

    always @(posedge clk)
    begin
        if (will_issue)
            writeback_reg[0] <= {next_instruction.dest_vector, next_instruction.dest_reg};

        for (int i = 1; i < ROLLBACK_STAGES; i++)
            writeback_reg[i] <= writeback_reg[i - 1];
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Drives control signals for single data rate (SDR) SDRAM, including
// auto refresh at appropriate intervals. An AXI bus interface initiates
// reads and writes.
// For performance, this lazily keeps rows open after accesses, tracking them
// independently for each bank and closing them only when necessary.
//

module sdram_controller
    #(parameter DATA_WIDTH = 32,
    parameter ROW_ADDR_WIDTH = 12, // 4096 rows
    parameter COL_ADDR_WIDTH = 8, // 256 columns

    // These are expressed in numbers of clocks. Each one is the number
    // of clocks of delay minus one. Compute this by dividing timing
    // specification for the part by the clock interval.
    parameter T_POWERUP = 10000,
    parameter T_ROW_PRECHARGE = 1,
    parameter T_AUTO_REFRESH_CYCLE = 3,
    parameter T_RAS_CAS_DELAY = 1,
    parameter T_REFRESH = 750,
    parameter T_CAS_LATENCY = 1)

    (input                                  clk,
    input                                   reset,

    // Interface to SDRAM
    output logic                            dram_clk,
    output logic                            dram_cke,
    output logic                            dram_cs_n,
    output logic                            dram_ras_n,
    output logic                            dram_cas_n,
    output logic                            dram_we_n,
    output logic[1:0]                       dram_ba,
    output logic[12:0]                      dram_addr,
    inout [DATA_WIDTH - 1:0]                dram_dq,

    // Interface to bus
    axi4_interface.slave                    axi_bus,

    // Performance counter events
    output logic                            perf_dram_page_miss,
    output logic                            perf_dram_page_hit);

    localparam SDRAM_BURST_LENGTH = 8;
    localparam SDRAM_BURST_IDX_WIDTH = $clog2(SDRAM_BURST_LENGTH);
    localparam NUM_BANKS = 4;
    localparam MEMORY_SIZE = (1 << (ROW_ADDR_WIDTH + COL_ADDR_WIDTH)) * NUM_BANKS
        * (DATA_WIDTH / 8);
    localparam INTERNAL_ADDR_WIDTH = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + $clog2(NUM_BANKS);
    localparam SDRAM_ADDR_WIDTH = $size(dram_addr);

    typedef enum {
        STATE_INIT0,
        STATE_INIT1,
        STATE_INIT2,
        STATE_INIT3,
        STATE_IDLE,
        STATE_AUTO_REFRESH0,
        STATE_AUTO_REFRESH1,
        STATE_OPEN_ROW,
        STATE_READ_BURST,
        STATE_WRITE_BURST,
        STATE_CAS_WAIT,
        STATE_POWERUP,
        STATE_CLOSE_ROW
    } burst_state_t;

    typedef enum logic[3:0] {
        CMD_MODE_REGISTER_SET = 4'b0000,
        CMD_AUTO_REFRESH      = 4'b0001,
        CMD_PRECHARGE         = 4'b0010,
        CMD_ACTIVATE          = 4'b0011,
        CMD_WRITE             = 4'b0100,
        CMD_READ              = 4'b0101,
        CMD_NOP               = 4'b1000
    } sdram_cmd_t;

    localparam TIMER_WIDTH = 15;

    // latched addresses and lengths are in terms of DATA_WIDTH transfers, not bytes.
    logic[TIMER_WIDTH - 1:0] refresh_timer_ff;
    logic[TIMER_WIDTH - 1:0] refresh_timer_nxt;
    logic[TIMER_WIDTH - 1:0] timer_ff;
    logic[TIMER_WIDTH - 1:0] timer_nxt;
    sdram_cmd_t command;
    burst_state_t state_ff;
    burst_state_t state_nxt;
    logic[SDRAM_BURST_IDX_WIDTH - 1:0] burst_offset_ff;
    logic[SDRAM_BURST_IDX_WIDTH - 1:0] burst_offset_nxt;
    logic[ROW_ADDR_WIDTH - 1:0] active_row[NUM_BANKS];
    logic bank_active[NUM_BANKS];
    logic output_enable;
    logic[DATA_WIDTH - 1:0] write_data;
    logic[INTERNAL_ADDR_WIDTH - 1:0] write_address;
    logic[7:0] write_length; // Like axi_bus.m_awlen, is num transfers - 1
    logic write_pending;
    logic[INTERNAL_ADDR_WIDTH - 1:0] read_address;
    logic[7:0] read_length;    // Like axi_bus.m_arlen, is num_transfers - 1
    logic read_pending;
    logic lfifo_empty;
    logic sfifo_full;
    logic[$clog2(NUM_BANKS) - 1:0] write_bank;
    logic[COL_ADDR_WIDTH - 1:0] write_column;
    logic[ROW_ADDR_WIDTH - 1:0] write_row;
    logic[$clog2(NUM_BANKS) - 1:0] read_bank;
    logic[COL_ADDR_WIDTH - 1:0] read_column;
    logic[ROW_ADDR_WIDTH - 1:0] read_row;
    logic lfifo_enqueue;
    logic access_is_read_ff;
    logic access_is_read_nxt;

    assign axi_bus.s_arready = !read_pending;
    assign axi_bus.s_awready = !write_pending;
    assign axi_bus.s_rvalid = !lfifo_empty;
    assign axi_bus.s_wready = !sfifo_full;
    assign axi_bus.s_bvalid = !reset;    // Hack: pretend we always have a write result

    // Each fifo can hold an entire SDRAM burst to avoid delays due
    // to the external bus.

    sync_fifo #(.WIDTH(DATA_WIDTH), .SIZE(SDRAM_BURST_LENGTH)) load_fifo(
        .clk(clk),
        .reset(reset),
        .flush_en(1'b0),
        .full(),
        .almost_empty(),
        .almost_full(),
        .empty(lfifo_empty),
        .enqueue_value(dram_dq),
        .enqueue_en(lfifo_enqueue),
        .dequeue_en(axi_bus.m_rready && axi_bus.s_rvalid),
        .dequeue_value(axi_bus.s_rdata));

    sync_fifo #(.WIDTH(DATA_WIDTH), .SIZE(SDRAM_BURST_LENGTH)) store_fifo(
        .clk(clk),
        .reset(reset),
        .flush_en(1'b0),
        .full(sfifo_full),
        .almost_empty(),
        .almost_full(),
        .dequeue_value(write_data),
        .dequeue_en(output_enable),
        .enqueue_value(axi_bus.m_wdata),
        .enqueue_en(axi_bus.s_wready && axi_bus.m_wvalid),
        .empty());

    assign {dram_cs_n, dram_ras_n, dram_cas_n, dram_we_n} = command;
    assign dram_cke = 1;
    assign dram_clk = clk;
    assign {write_row, write_bank, write_column} = write_address;
    assign {read_row, read_bank, read_column} = read_address;

    assign dram_dq = output_enable ? write_data : {DATA_WIDTH{1'hZ}};

    initial
    begin
        // Currently a requirement because narrowing or expanding isn't implemented.
        assert(`AXI_DATA_WIDTH == DATA_WIDTH);
    end

    // Next state logic. When there is a delay between states, timer_ff tracks
    // how many cycles are remaining. state_ff will point to the *next* state
    // during this interval, but the  control signals associated with the state
    // (in the case below) won't be asserted until the timer counts down to zero.
    always_comb
    begin
        // Default values
        output_enable = 0;
        command = CMD_NOP;
        timer_nxt = TIMER_WIDTH'(0);
        burst_offset_nxt = 0;
        state_nxt = state_ff;
        dram_ba = 0;
        dram_addr = 0;
        perf_dram_page_miss = 0;
        perf_dram_page_hit = 0;
        access_is_read_nxt = access_is_read_ff;

        lfifo_enqueue = 0;
        if (refresh_timer_ff != 0)
            refresh_timer_nxt = refresh_timer_ff - TIMER_WIDTH'(1);
        else
            refresh_timer_nxt = TIMER_WIDTH'(0);

        if (timer_ff != 0)
            timer_nxt = timer_ff - TIMER_WIDTH'(1); // Wait for timer to expire
        else
        begin
            // Progress to next state.
            unique case (state_ff)
                STATE_POWERUP:
                begin
                    timer_nxt = TIMER_WIDTH'(T_POWERUP);    // Wait for clock to be stable
                    state_nxt = STATE_INIT0;
                end

                STATE_INIT0:
                begin
                    // Step 1: send precharge all command
                    dram_addr = {SDRAM_ADDR_WIDTH{1'b1}};
                    command = CMD_PRECHARGE;
                    timer_nxt = TIMER_WIDTH'(T_ROW_PRECHARGE);
                    state_nxt = STATE_INIT1;
                end

                STATE_INIT1:
                begin
                    // Step 2: send two auto refresh commands
                    dram_addr = {SDRAM_ADDR_WIDTH{1'b1}};
                    command = CMD_AUTO_REFRESH;
                    timer_nxt = TIMER_WIDTH'(T_AUTO_REFRESH_CYCLE);
                    state_nxt = STATE_INIT2;
                end

                STATE_INIT2:
                begin
                    dram_addr = {SDRAM_ADDR_WIDTH{1'b1}};
                    command = CMD_AUTO_REFRESH;
                    timer_nxt = TIMER_WIDTH'(T_AUTO_REFRESH_CYCLE);
                    state_nxt = STATE_INIT3;
                end

                STATE_INIT3:
                begin
                    // Step 3: set the mode register
                    // CAS latency is hardcoded to 2 clocks
                    command = CMD_MODE_REGISTER_SET;
                    dram_addr = SDRAM_ADDR_WIDTH'('b000_0_00_010_0_011);
                    dram_ba = 2'b00;
                    state_nxt = STATE_IDLE;
                end

                STATE_IDLE:
                begin
                    if (refresh_timer_ff == 0)
                    begin
                        // Need to perform an auto-refresh cycle.  If any rows are open,
                        // precharge all of them now.  Otherwise proceed directly to
                        // refresh.
                        if (bank_active[0] | bank_active[1] | bank_active[2] | bank_active[3])
                            state_nxt = STATE_AUTO_REFRESH0;
                        else
                            state_nxt = STATE_AUTO_REFRESH1;
                    end
                    else if (lfifo_empty && read_pending
                        && (!write_pending || write_address != read_address))
                    begin
                        // Start a read burst. Reads have priority to avoid starving
                        // the VGA controller, but we check above to ensure there isn't
                        // a write already pending for this address (otherwise we will
                        // get stale data).
                        access_is_read_nxt = 1;
                        if (!bank_active[read_bank])
                        begin
                            // Row is not open in this bank, need to pen it.
                            perf_dram_page_miss = 1;
                            state_nxt = STATE_OPEN_ROW;
                        end
                        else if (read_row != active_row[read_bank])
                        begin
                            // Different row is already open in this bank, close it first.
                            perf_dram_page_miss = 1;
                            state_nxt = STATE_CLOSE_ROW;
                        end
                        else
                        begin
                            perf_dram_page_hit = 1;
                            state_nxt = STATE_CAS_WAIT;
                        end
                    end
                    else if (write_pending && sfifo_full
                        && (!read_pending || write_address == read_address))
                    begin
                        // Start a write burst.
                        // Don't start the burst if a read is pending and the FIFO is full.
                        // This is a hack to avoid starving the VGA controller.  However, do
                        // start the write if the read is for data we are about to write
                        // (write_address == read_address above), which avoids a nasty race
                        // condition that corrrupts data.
                        access_is_read_nxt = 0;
                        if (!bank_active[write_bank])
                        begin
                            // Row is not open, do that
                            perf_dram_page_miss = 1;
                            state_nxt = STATE_OPEN_ROW;
                        end
                        else if (write_row != active_row[write_bank])
                        begin
                            // Different row open in this bank, close
                            perf_dram_page_miss = 1;
                            state_nxt = STATE_CLOSE_ROW;
                        end
                        else
                        begin
                            perf_dram_page_hit = 1;
                            state_nxt = STATE_WRITE_BURST;
                        end
                    end
                end

                STATE_CLOSE_ROW:
                begin
                    // Precharge a single bank that has an open row in preparation
                    // for a transfer.
                    dram_addr =  {SDRAM_ADDR_WIDTH{1'b0}};
                    if (access_is_read_ff)
                        dram_ba = read_bank;
                    else
                        dram_ba = write_bank;

                    command = CMD_PRECHARGE;
                    timer_nxt = TIMER_WIDTH'(T_ROW_PRECHARGE);
                    state_nxt = STATE_OPEN_ROW;
                end

                STATE_OPEN_ROW:
                begin
                    if (access_is_read_ff)
                    begin
                        dram_ba = read_bank;
                        dram_addr = SDRAM_ADDR_WIDTH'(read_row);
                        state_nxt = STATE_CAS_WAIT;
                    end
                    else
                    begin
                        dram_ba = write_bank;
                        dram_addr = SDRAM_ADDR_WIDTH'(write_row);
                        state_nxt = STATE_WRITE_BURST;
                    end
                    command = CMD_ACTIVATE;
                    timer_nxt = TIMER_WIDTH'(T_RAS_CAS_DELAY);
                end

                STATE_CAS_WAIT:
                begin
                    command = CMD_READ;
                    dram_addr = SDRAM_ADDR_WIDTH'(read_column);
                    dram_ba = read_bank;
                    timer_nxt = TIMER_WIDTH'(T_CAS_LATENCY);
                    state_nxt = STATE_READ_BURST;
                end

                STATE_READ_BURST:
                begin
                    lfifo_enqueue = 1;
                    burst_offset_nxt = burst_offset_ff + SDRAM_BURST_IDX_WIDTH'(1);
                    if (burst_offset_ff == SDRAM_BURST_IDX_WIDTH'(SDRAM_BURST_LENGTH - 1))
                        state_nxt = STATE_IDLE;
                end

                STATE_WRITE_BURST:
                begin
                    output_enable = 1;
                    if (burst_offset_ff == 0)
                    begin
                        // On first cycle
                        dram_ba = write_bank;
                        dram_addr = SDRAM_ADDR_WIDTH'(write_column);
                        command = CMD_WRITE;
                    end

                    burst_offset_nxt = burst_offset_ff + SDRAM_BURST_IDX_WIDTH'(1);
                    if (burst_offset_ff == SDRAM_BURST_IDX_WIDTH'(SDRAM_BURST_LENGTH - 1))
                        state_nxt = STATE_IDLE;
                end

                STATE_AUTO_REFRESH0:
                begin
                    // Precharge all banks before auto-refresh
                    dram_addr = SDRAM_ADDR_WIDTH'('b0010000000000);    // XXX parameterize
                    command = CMD_PRECHARGE;
                    timer_nxt = TIMER_WIDTH'(T_ROW_PRECHARGE);
                    state_nxt = STATE_AUTO_REFRESH1;
                end

                STATE_AUTO_REFRESH1:
                begin
                    command = CMD_AUTO_REFRESH;
                    timer_nxt = TIMER_WIDTH'(T_AUTO_REFRESH_CYCLE);
                    refresh_timer_nxt = TIMER_WIDTH'(T_REFRESH);
                    state_nxt = STATE_IDLE;
                end

                default:
                    state_nxt = STATE_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin : doreset
            for (int i = 0; i < NUM_BANKS; i++)
            begin
                active_row[i] <= 0;
                bank_active[i] <= 0;
            end

            state_ff <= STATE_INIT0;
            refresh_timer_ff <= TIMER_WIDTH'(T_REFRESH);

            access_is_read_ff <= '0;
            burst_offset_ff <= '0;
            read_address <= '0;
            read_length <= '0;
            read_pending <= '0;
            timer_ff <= '0;
            write_address <= '0;
            write_length <= '0;
            write_pending <= '0;
        end
        else
        begin
            //
            // SDRAM control
            //
            state_ff <= state_nxt;
            timer_ff <= timer_nxt;
            burst_offset_ff <= burst_offset_nxt;
            refresh_timer_ff <= refresh_timer_nxt;
            access_is_read_ff <= access_is_read_nxt;
            if (state_ff == STATE_OPEN_ROW)
            begin
                if (access_is_read_ff)
                begin
                    active_row[read_bank] <= read_row;
                    bank_active[read_bank] <= 1;
                end
                else
                begin
                    active_row[write_bank] <= write_row;
                    bank_active[write_bank] <= 1;
                end
            end
            else if (state_ff == STATE_AUTO_REFRESH0)
            begin
                // The precharge all command will close all active banks
                for (int i = 0; i < NUM_BANKS; i++)
                    bank_active[i] <= 0;
            end

            //
            // AXI Bus Interface
            //
            if (write_pending && state_ff == STATE_WRITE_BURST &&
                state_nxt != STATE_WRITE_BURST)
            begin
                // The bus transfer may be longer than the SDRAM burst.
                // Determine if we are done yet.
                write_length <= write_length - 8'(SDRAM_BURST_LENGTH);
                write_address <= write_address + INTERNAL_ADDR_WIDTH'(SDRAM_BURST_LENGTH);
                if (write_length == SDRAM_BURST_LENGTH - 1)
                    write_pending <= 0;
            end
            else if (axi_bus.m_awvalid && !write_pending)
            begin
                // Start a write burst

                // Ensure the the burst is aligned on an SDRAM burst boundary.
                assert(((axi_bus.m_awlen + 1) & (SDRAM_BURST_LENGTH - 1)) == 0);
                assert((axi_bus.m_awaddr & (SDRAM_BURST_LENGTH - 1)) == 0);

`ifdef SIMULATION
                // Make sure memory address is in memory range
                if (axi_bus.m_awaddr >= MEMORY_SIZE)
                begin
                    $display("sdram: write address out of range %x", axi_bus.m_awaddr);
                    $finish;
                end
`endif

                // axi_bus.m_awaddr is in terms of bytes.  Convert to # of transfers.
                write_address <= INTERNAL_ADDR_WIDTH'(axi_bus.m_awaddr[AXI_ADDR_WIDTH - 1:$clog2(DATA_WIDTH / 8)]);
                write_length <= axi_bus.m_awlen;
                write_pending <= 1'b1;
            end

            if (read_pending && state_ff == STATE_READ_BURST &&
                state_nxt != STATE_READ_BURST)
            begin
                read_length <= read_length - 8'(SDRAM_BURST_LENGTH);
                read_address <= read_address + INTERNAL_ADDR_WIDTH'(SDRAM_BURST_LENGTH);
                if (read_length == SDRAM_BURST_LENGTH - 1)
                    read_pending <= 0;
            end
            else if (axi_bus.m_arvalid && !read_pending)
            begin
                // Start a read burst

                // Ensure the the burst is aligned on an SDRAM burst boundary.
                assert(((axi_bus.m_arlen + 1) & (SDRAM_BURST_LENGTH - 1)) == 0);
                assert((axi_bus.m_araddr & (SDRAM_BURST_LENGTH - 1)) == 0);

`ifdef SIMULATION
                // Make sure memory address is in memory range
                if (axi_bus.m_araddr >= MEMORY_SIZE)
                begin
                    $display("sdram: read address out of range %x", axi_bus.m_araddr);
                    $finish;
                end
`endif

                // axi_bus.m_araddr is in terms of bytes.  Convert to # of transfers.
                read_address <= INTERNAL_ADDR_WIDTH'(axi_bus.m_araddr[AXI_ADDR_WIDTH - 1:$clog2(DATA_WIDTH / 8)]);
                read_length <= axi_bus.m_arlen;
                read_pending <= 1'b1;
            end
        end
    end
endmodule
//
// Copyright 2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Serial Peripheral Interface (SPI) bus controller
// It is hard coded to act as a master, and to run in "mode 0"
// (shift data out on falling edge, sample on rising, clock idles low)
//

module spi_controller
    #(parameter BASE_ADDRESS = 0)

    (input                      clk,
    input                       reset,
    io_bus_interface.slave      io_bus,

    // SPI interface
    output logic                spi_clk,
    output logic                spi_cs_n,
    input                       spi_miso,
    output logic                spi_mosi);

    localparam TX_REG = BASE_ADDRESS;
    localparam RX_REG = BASE_ADDRESS + 4;
    localparam RX_STATUS_REG = BASE_ADDRESS + 8;
    localparam CONTROL_REG = BASE_ADDRESS + 12;
    localparam DIVISOR_REG = BASE_ADDRESS + 16;

    logic transfer_active;
    logic[2:0] transfer_count;
    logic[7:0] miso_byte;    // Master in slave out
    logic[7:0] mosi_byte;    // Master out slave in
    logic[7:0] divider_countdown;
    logic[7:0] divider_rate;

    always_ff @(posedge reset, posedge clk)
    begin
        if (reset)
        begin
            transfer_active <= 0;
            spi_clk <= 0;
            spi_cs_n <= 1;
            divider_rate <= 1;
            spi_mosi <= 1;
        end
        else
        begin
            if (io_bus.address == RX_REG)
                io_bus.read_data <= scalar_t'(miso_byte);
            else // RX_STATUS_REG
                io_bus.read_data <= scalar_t'(!transfer_active);

            // Control register
            if (io_bus.write_en)
            begin
                if (io_bus.address == CONTROL_REG)
                    spi_cs_n <= io_bus.write_data[0];
                else if (io_bus.address == DIVISOR_REG)
                    divider_rate <= io_bus.write_data[7:0];
            end

            if (transfer_active)
            begin
                if (divider_countdown == 0)
                begin
                    divider_countdown <= divider_rate;
                    spi_clk <= !spi_clk;
                    if (spi_clk)
                    begin
                        // Falling edge
                        if (transfer_count == 0)
                            transfer_active <= 0;
                        else
                        begin
                            transfer_count <= transfer_count - 3'd1;

                            // Shift out a bit
                            {spi_mosi, mosi_byte} <= {mosi_byte, 1'd0};
                        end
                    end
                    else
                    begin
                        // Rising edge
                        miso_byte <= {miso_byte[6:0], spi_miso};
                    end
                end
                else
                    divider_countdown <= divider_countdown - 8'd1;
            end
            else if (io_bus.write_en && io_bus.address == TX_REG)
            begin
                assert(spi_clk == 0);

                // Start new transfer
                transfer_active <= 1;
                transfer_count <= 7;
                divider_countdown <= divider_rate;

                // Set up first bit
                {spi_mosi, mosi_byte} <= {io_bus.write_data[7:0], 1'd0};
            end
            else
                spi_mosi <= 1;  // High when there is no activity
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Block SRAM with 1 read port and 1 write port.
// Reads and writes are performed synchronously. The read value appears
// on the next clock edge after the address and read_en are asserted
// If read_en is not asserted, the value of read_data is undefined during
// the next cycle. The READ_DURING_WRITE parameter determines what happens
// if a read and a write are performed to the same address in the same cycle:
//  - "NEW_DATA" this will return the newly written data ("read-after-write").
//  - "DONT_CARE" The results are undefined. This can be used to improve clock
//    speed.
// This does not clear memory contents on reset.
//
module sram_1r1w
    #(parameter DATA_WIDTH = 32,
    parameter SIZE = 1024,
    parameter READ_DURING_WRITE = "NEW_DATA",
    parameter ADDR_WIDTH = $clog2(SIZE))

    (input                         clk,
    input                          read_en,
    input [ADDR_WIDTH - 1:0]       read_addr,
    output logic[DATA_WIDTH - 1:0] read_data,
    input                          write_en,
    input [ADDR_WIDTH - 1:0]       write_addr,
    input [DATA_WIDTH - 1:0]       write_data);

`ifdef VENDOR_ALTERA
    logic[DATA_WIDTH - 1:0] data_from_ram;

    // Not all Altera FPGA families support READ_DURING_WRITE_MIXED_PORTS
    // (which I found out the hard way). I just set that to DONT_CARE and
    // insert my own logic to bypass results.
    ALTSYNCRAM #(
        .OPERATION_MODE("DUAL_PORT"),
        .WIDTH_A(DATA_WIDTH),
        .WIDTHAD_A(ADDR_WIDTH),
        .WIDTH_B(DATA_WIDTH),
        .WIDTHAD_B(ADDR_WIDTH),
        .READ_DURING_WRITE_MIXED_PORTS("DONT_CARE")
    ) data0(
        .clock0(clk),
        .clock1(clk),

        // Write port
        .wren_a(write_en),
        .address_a(write_addr),
        .data_a(write_data),
        .q_a(),

        // Read port
        .rden_b(read_en),
        .address_b(read_addr),
        .q_b(data_from_ram));

    generate
        if (READ_DURING_WRITE == "NEW_DATA")
        begin
            logic pass_thru_en;
            logic[DATA_WIDTH - 1:0] pass_thru_data;

            always_ff @(posedge clk)
            begin
                pass_thru_en <= write_en && read_en && read_addr == write_addr;
                pass_thru_data <= write_data;
            end

            assign read_data = pass_thru_en ? pass_thru_data : data_from_ram;
        end
        else
        begin
            assign read_data = data_from_ram;
        end
    endgenerate
`elsif VENDOR_XILINX
    // If you get an error [Synth 8-439] module 'xpm_memory_sdpram' not found,
    // you must set the property XPM_LIBRARIES on the project.
    // https://www.xilinx.com/support/answers/67815.html

    localparam XPM_MEM_SIZE = (1 << ADDR_WIDTH) * DATA_WIDTH; // Memory size in bits

    logic[DATA_WIDTH - 1:0] data_from_ram;

    xpm_memory_sdpram # (
        .MEMORY_SIZE        (XPM_MEM_SIZE),    // Size in bits
        .MEMORY_PRIMITIVE   ("auto"),          // Left Vivado choosing
        .CLOCKING_MODE      ("common_clock"),  // Clock both port A and port B with clka
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  (""    ),
        .USE_MEM_INIT       (0),               // No init
        .WAKEUP_TIME        ("disable_sleep"), // Dynamic power saving Disabled
        .MESSAGE_CONTROL    (0),               // Dynamic message reporting Disabled
        .ECC_MODE           ("no_ecc"),        // No ECC
        .AUTO_SLEEP_TIME    (0),               // Reserved

        // Port A module parameters
        .WRITE_DATA_WIDTH_A (DATA_WIDTH),
        .BYTE_WRITE_WIDTH_A (DATA_WIDTH),
        .ADDR_WIDTH_A       (ADDR_WIDTH),

        // Port B module parameters
        .READ_DATA_WIDTH_B  (DATA_WIDTH),
        .ADDR_WIDTH_B       (ADDR_WIDTH),
        .READ_RESET_VALUE_B ("0"),
        .READ_LATENCY_B     (1),               // Read data output to port doutb takes 1 clk
        .WRITE_MODE_B       ("read_first")     // Seems to be the best choice according to ug974
    ) data0 (
        .sleep          (1'b0),

        // Port A module ports
        .clka           (clk),
        .ena            (write_en),
        .wea            (write_en),
        .addra          (write_addr),
        .dina           (write_data),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),

        // Port B module ports
        .clkb           (clk),
        .rstb           (1'b0),
        .enb            (read_en),
        .regceb         (1'b1),
        .addrb          (read_addr),
        .doutb          (data_from_ram),
        .sbiterrb       (),
        .dbiterrb       ()
    );

    generate
        if (READ_DURING_WRITE == "NEW_DATA") begin
            logic pass_thru_en;
            logic[DATA_WIDTH - 1:0] pass_thru_data;

            always_ff @(posedge clk) begin
                pass_thru_en <= write_en && read_en && read_addr == write_addr;
                pass_thru_data <= write_data;
            end

            assign read_data = pass_thru_en ? pass_thru_data : data_from_ram;
        end else begin
            assign read_data = data_from_ram;
        end
    endgenerate
`elsif MEMORY_COMPILER
    generate
        `define _GENERATE_SRAM1R1W
        `include "srams.inc"
        `undef     _GENERATE_SRAM1R1W
    endgenerate
`else
    // Simulation
    logic[DATA_WIDTH - 1:0] data[SIZE];

    // Note: use always here instead of always_ff so Modelsim will allow
    // initializing the array in the initial block (see below).
    always @(posedge clk)
    begin
        if (write_en)
            data[write_addr] <= write_data;

        if (write_addr == read_addr && write_en && read_en)
        begin
            if (READ_DURING_WRITE == "NEW_DATA")
                read_data <= write_data;    // Bypass
            else
                read_data <= DATA_WIDTH'($random()); // ensure it is really "don't care"
        end
        else if (read_en)
            read_data <= data[read_addr];
        else
            read_data <= DATA_WIDTH'($random());
    end

    initial
    begin
`ifndef VERILATOR
        // Initialize RAM with random values. This is unneeded on Verilator
        // (which already does randomizes memory), but is necessary on
        // 4-state simulators because memory is initially filled with Xs.
        // This was causing x-propagation bugs in some modules previously.
        for (int i = 0; i < SIZE; i++)
            data[i] = DATA_WIDTH'($random());
`endif

        if ($test$plusargs("dumpmems") != 0)
            $display("sram1r1w %d %d", DATA_WIDTH, SIZE);
    end
`endif
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Block SRAM with 2 read ports and 1 write port.
// Reads and writes are performed synchronously. The read value appears
// on the next clock edge after the address and readx_en are asserted
// If readx_en is not asserted, the value of readx_data is undefined during
// the next cycle. The READ_DURING_WRITE parameter determines what happens
// if a read and a write are performed to the same address in the same cycle:
//  - "NEW_DATA" this will return the newly written data ("read-after-write").
//  - "DONT_CARE" The results are undefined. This can be used to improve clock
//    speed.
// This does not clear memory contents on reset.
//
module sram_2r1w
    #(parameter DATA_WIDTH = 32,
    parameter SIZE = 1024,
    parameter READ_DURING_WRITE = "NEW_DATA",
    parameter ADDR_WIDTH = $clog2(SIZE))

    (input                           clk,
    input                            read1_en,
    input [ADDR_WIDTH - 1:0]         read1_addr,
    output logic[DATA_WIDTH - 1:0]   read1_data,
    input                            read2_en,
    input [ADDR_WIDTH - 1:0]         read2_addr,
    output logic[DATA_WIDTH - 1:0]   read2_data,
    input                            write_en,
    input [ADDR_WIDTH - 1:0]         write_addr,
    input [DATA_WIDTH - 1:0]         write_data);

`ifdef VENDOR_ALTERA
    logic[DATA_WIDTH - 1:0] data_from_ram1;
    logic[DATA_WIDTH - 1:0] data_from_ram2;

    // Not all Altera FPGA families support READ_DURING_WRITE_MIXED_PORTS
    // (which I found out the hard way). I just set that to DONT_CARE and
    // insert my own logic to bypass results.
    ALTSYNCRAM #(
        .OPERATION_MODE("DUAL_PORT"),
        .WIDTH_A(DATA_WIDTH),
        .WIDTHAD_A(ADDR_WIDTH),
        .WIDTH_B(DATA_WIDTH),
        .WIDTHAD_B(ADDR_WIDTH),
        .READ_DURING_WRITE_MIXED_PORTS("DONT_CARE")
    ) data0(
        .clock0(clk),
        .clock1(clk),

        // Write port
        .wren_a(write_en),
        .address_a(write_addr),
        .data_a(write_data),
        .q_a(),

        // Read port
        .rden_b(read1_en),
        .address_b(read1_addr),
        .q_b(data_from_ram1));

    ALTSYNCRAM #(
        .OPERATION_MODE("DUAL_PORT"),
        .WIDTH_A(DATA_WIDTH),
        .WIDTHAD_A(ADDR_WIDTH),
        .WIDTH_B(DATA_WIDTH),
        .WIDTHAD_B(ADDR_WIDTH),
        .READ_DURING_WRITE_MIXED_PORTS("DONT_CARE")
    ) data1(
        .clock0(clk),
        .clock1(clk),

        // Write port
        .wren_a(write_en),
        .address_a(write_addr),
        .data_a(write_data),
        .q_a(),

        // Read port
        .rden_b(read2_en),
        .address_b(read2_addr),
        .q_b(data_from_ram2));

    generate
        if (READ_DURING_WRITE == "NEW_DATA")
        begin
            logic pass_thru1_en;
            logic pass_thru2_en;
            logic[DATA_WIDTH - 1:0] pass_thru_data;

            always_ff @(posedge clk)
            begin
                pass_thru1_en <= write_en && read1_en && read1_addr == write_addr;
                pass_thru2_en <= write_en && read2_en && read2_addr == write_addr;
                pass_thru_data <= write_data;
            end

            assign read1_data = pass_thru1_en ? pass_thru_data : data_from_ram1;
            assign read2_data = pass_thru2_en ? pass_thru_data : data_from_ram2;
        end
        else
        begin
            assign read1_data = data_from_ram1;
            assign read2_data = data_from_ram2;
        end
    endgenerate
`elsif VENDOR_XILINX
    // If you get an error [Synth 8-439] module 'xpm_memory_sdpram' not found,
    // you must set the property XPM_LIBRARIES on the project.
    // https://www.xilinx.com/support/answers/67815.html

    localparam XPM_MEM_SIZE = (1 << ADDR_WIDTH) * DATA_WIDTH; // Memory size in bits

    logic[DATA_WIDTH - 1:0] data_from_ram1;
    logic[DATA_WIDTH - 1:0] data_from_ram2;

    xpm_memory_sdpram # (
        .MEMORY_SIZE        (XPM_MEM_SIZE),    // Size in bits
        .MEMORY_PRIMITIVE   ("auto"),          // Left Vivado choosing
        .CLOCKING_MODE      ("common_clock"),  // Clock both port A and port B with clka
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  (""    ),
        .USE_MEM_INIT       (0),               // No init
        .WAKEUP_TIME        ("disable_sleep"), // Dynamic power saving Disabled
        .MESSAGE_CONTROL    (0),               // Dynamic message reporting Disabled
        .ECC_MODE           ("no_ecc"),        // No ECC
        .AUTO_SLEEP_TIME    (0),               // Reserved

        // Port A module parameters
        .WRITE_DATA_WIDTH_A (DATA_WIDTH),
        .BYTE_WRITE_WIDTH_A (DATA_WIDTH),
        .ADDR_WIDTH_A       (ADDR_WIDTH),

        // Port B module parameters
        .READ_DATA_WIDTH_B  (DATA_WIDTH),
        .ADDR_WIDTH_B       (ADDR_WIDTH),
        .READ_RESET_VALUE_B ("0"),
        .READ_LATENCY_B     (1),               // Read data output to port doutb takes 1 clk
        .WRITE_MODE_B       ("read_first")     // Seems to be the best choice according to ug974
    ) data0 (
        .sleep          (1'b0),

        // Port A module ports
        .clka           (clk),
        .ena            (write_en),
        .wea            (write_en),
        .addra          (write_addr),
        .dina           (write_data),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),

        // Port B module ports
        .clkb           (clk),
        .rstb           (1'b0),
        .enb            (read1_en),
        .regceb         (1'b1),
        .addrb          (read1_addr),
        .doutb          (data_from_ram1),
        .sbiterrb       (),
        .dbiterrb       ()
    );

    xpm_memory_sdpram # (
        .MEMORY_SIZE        (XPM_MEM_SIZE),
        .MEMORY_PRIMITIVE   ("auto"),
        .CLOCKING_MODE      ("common_clock"),
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  (""    ),
        .USE_MEM_INIT       (0),
        .WAKEUP_TIME        ("disable_sleep"),
        .MESSAGE_CONTROL    (0),
        .ECC_MODE           ("no_ecc"),
        .AUTO_SLEEP_TIME    (0),

        // Port A module parameters
        .WRITE_DATA_WIDTH_A (DATA_WIDTH),
        .BYTE_WRITE_WIDTH_A (DATA_WIDTH),
        .ADDR_WIDTH_A       (ADDR_WIDTH),

        // Port B module parameters
        .READ_DATA_WIDTH_B  (DATA_WIDTH),
        .ADDR_WIDTH_B       (ADDR_WIDTH),
        .READ_RESET_VALUE_B ("0"),
        .READ_LATENCY_B     (1),
        .WRITE_MODE_B       ("read_first")
    ) data1 (
        .sleep          (1'b0),

        // Port A module ports
        .clka           (clk),
        .ena            (write_en),
        .wea            (write_en),
        .addra          (write_addr),
        .dina           (write_data),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),

        // Port B module ports
        .clkb           (clk),
        .rstb           (1'b0),
        .enb            (read2_en),
        .regceb         (1'b1),
        .addrb          (read2_addr),
        .doutb          (data_from_ram2),
        .sbiterrb       (),
        .dbiterrb       ()
    );

    generate
        if (READ_DURING_WRITE == "NEW_DATA") begin
            logic pass_thru1_en;
            logic pass_thru2_en;
            logic[DATA_WIDTH - 1:0] pass_thru_data;

            always_ff @(posedge clk) begin
                pass_thru1_en <= write_en && read1_en && read1_addr == write_addr;
                pass_thru2_en <= write_en && read2_en && read2_addr == write_addr;
                pass_thru_data <= write_data;
            end

            assign read1_data = pass_thru1_en ? pass_thru_data : data_from_ram1;
            assign read2_data = pass_thru2_en ? pass_thru_data : data_from_ram2;
        end else begin
            assign read1_data = data_from_ram1;
            assign read2_data = data_from_ram2;
        end
    endgenerate
`elsif MEMORY_COMPILER
    generate
        `define _GENERATE_SRAM2R1W
        `include "srams.inc"
        `undef     _GENERATE_SRAM2R1W
    endgenerate
`else
    // Simulation
    logic[DATA_WIDTH - 1:0] data[SIZE];

    // Note: use always here instead of always_ff so Modelsim will allow
    // initializing the array in the initial block (see below).
    always @(posedge clk)
    begin
        if (write_en)
            data[write_addr] <= write_data;

        if (write_addr == read1_addr && write_en && read1_en)
        begin
            if (READ_DURING_WRITE == "NEW_DATA")
                read1_data <= write_data;    // Bypass
            else
                read1_data <= DATA_WIDTH'($random()); // ensure it is really "don't care"
        end
        else if (read1_en)
            read1_data <= data[read1_addr];
        else
            read1_data <= DATA_WIDTH'($random());

        if (write_addr == read2_addr && write_en && read2_en)
        begin
            if (READ_DURING_WRITE == "NEW_DATA")
                read2_data <= write_data;    // Bypass
            else
                read2_data <= DATA_WIDTH'($random());
        end
        else if (read2_en)
            read2_data <= data[read2_addr];
        else
            read2_data <= DATA_WIDTH'($random());
    end

    initial
    begin
`ifndef VERILATOR
        // Initialize RAM with random values. This is unneeded on Verilator
        // (which already does randomizes memory), but is necessary on
        // 4-state simulators because memory is initially filled with Xs.
        // This was causing x-propagation bugs in some modules previously.
        for (int i = 0; i < SIZE; i++)
            data[i] = DATA_WIDTH'($random());
`endif

        if ($test$plusargs("dumpmems") != 0)
            $display("sram2r1w %d %d", DATA_WIDTH, SIZE);
    end
`endif
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// First-in, first-out queue, with synchronous read/write
// - SIZE must be a power of two and greater than or equal to 4.
// - almost_full asserts when there are ALMOST_FULL_THRESHOLD or more entries
//   queued.
// - almost_empty asserts when there are ALMOST_EMPTY_THRESHOLD or fewer
//   entries queued.
// - almost_full is still asserted when full is asserted, as is almost_empty
//   when empty is asserted.
// - flush takes precedence over enqueue/dequeue if it is asserted
//   simultaneously. It is synchronous, unlike reset.
// - It is not legal to assert enqueue when the FIFO is full or dequeue when it
//   is empty (The former is true even if there is a dequeue and enqueue in the
//   same cycle, which wouldn't change the count). Doing this will trigger an
//   error in the simulator and have incorrect behavior in synthesis.
// - dequeue_value will contain the next value to be dequeued even if dequeue_en is
//   not asserted.
//
module sync_fifo
    #(parameter WIDTH = 64,
    parameter SIZE = 4,
    parameter ALMOST_FULL_THRESHOLD = SIZE,
    parameter ALMOST_EMPTY_THRESHOLD = 1)

    (input                       clk,
    input                        reset,
    input                        flush_en,    // flush is synchronous, unlike reset
    output logic                 full,
    output logic                 almost_full,
    input                        enqueue_en,
    input [WIDTH - 1:0]          enqueue_value,
    output logic                 empty,
    output logic                 almost_empty,
    input                        dequeue_en,
    output logic[WIDTH - 1:0]    dequeue_value);

`ifdef VENDOR_ALTERA
    SCFIFO #(
        .almost_empty_value(ALMOST_EMPTY_THRESHOLD + 1),
        .almost_full_value(ALMOST_FULL_THRESHOLD),
        .lpm_numwords(SIZE),
        .lpm_width(WIDTH),
        .lpm_showahead("ON")
    ) scfifo(
        .aclr(reset),
        .almost_empty(almost_empty),
        .almost_full(almost_full),
        .clock(clk),
        .data(enqueue_value),
        .empty(empty),
        .full(full),
        .q(dequeue_value),
        .rdreq(dequeue_en),
        .sclr(flush_en),
        .wrreq(enqueue_en));
`elsif MEMORY_COMPILER
    generate
        `define _GENERATE_FIFO
        `include "srams.inc"
        `undef     _GENERATE_FIFO
    endgenerate
`else
    // Simulation
    localparam ADDR_WIDTH = $clog2(SIZE);

    logic[ADDR_WIDTH - 1:0] head;
    logic[ADDR_WIDTH - 1:0] tail;
    logic[ADDR_WIDTH:0] count;
    logic[WIDTH - 1:0] data[SIZE];

    assign almost_full = count >= (ADDR_WIDTH + 1)'(ALMOST_FULL_THRESHOLD);
    assign almost_empty = count <= (ADDR_WIDTH + 1)'(ALMOST_EMPTY_THRESHOLD);
    assign full = count == SIZE;
    assign empty = count == 0;
    assign dequeue_value = data[head];

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            head <= 0;
            tail <= 0;
            count <= 0;
        end
        else
        begin
            if (flush_en)
            begin
                head <= 0;
                tail <= 0;
                count <= 0;
            end
            else
            begin
                if (enqueue_en)
                begin
                    assert(!full);
                    tail <= tail + 1;
                    data[tail] <= enqueue_value;
                end

                if (dequeue_en)
                begin
                    assert(!empty);
                    head <= head + 1;
                end

                if (enqueue_en && !dequeue_en)
                    count <= count + 1;
                else if (dequeue_en && !enqueue_en)
                    count <= count - 1;
            end
        end
    end

    initial
    begin
        if ($test$plusargs("dumpmems") != 0)
            $display("sync_fifo %d %d", WIDTH, SIZE);
    end
`endif
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Transfer a signal into a clock domain, avoiding metastability and
// race conditions due to propagation delay.
//

module synchronizer
    #(parameter WIDTH = 1,
    parameter RESET_STATE = 0)

    (input                      clk,
    input                       reset,
    output logic[WIDTH - 1:0]   data_o,
    input [WIDTH - 1:0]         data_i);

    logic[WIDTH - 1:0] sync0;
    logic[WIDTH - 1:0] sync1;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            sync0 <= WIDTH'(RESET_STATE);
            sync1 <= WIDTH'(RESET_STATE);
            data_o <= WIDTH'(RESET_STATE);
        end
        else
        begin
            sync0 <= data_i;
            sync1 <= sync0;
            data_o <= sync1;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Instruction Pipeline Thread Select Stage
// - Contains an instruction FIFO for each thread
// - Each cycle, picks a thread to issue using a round robin scheduling
//   algorithm, avoiding various types of conflicts:
//   * inter-instruction register dependencies (read-after-write,
//     write-after-write, write-after-read), tracked using a scoreboard for
//     each thread.
//   * writeback hazards between the pipelines of different lengths, tracked
//     with a shared shift register.
// - Tracks dcache misses and suspends threads until they are resolved.
//

module thread_select_stage(
    input                              clk,
    input                              reset,

    // From instruction_decode_stage
    input decoded_instruction_t        id_instruction,
    input                              id_instruction_valid,
    input local_thread_idx_t           id_thread_idx,

    // To ifetch_tag_stage
    output local_thread_bitmap_t       ts_fetch_en,

    // To operand_fetch_stage
    output logic                       ts_instruction_valid,
    output decoded_instruction_t       ts_instruction,
    output local_thread_idx_t          ts_thread_idx,
    output subcycle_t                  ts_subcycle,

    // From writeback_stage
    input                              wb_writeback_en,
    input local_thread_idx_t           wb_writeback_thread_idx,
    input                              wb_writeback_vector,
    input register_idx_t               wb_writeback_reg,
    input                              wb_writeback_last_subcycle,
    input local_thread_idx_t           wb_rollback_thread_idx,
    input                              wb_rollback_en,
    input pipeline_sel_t               wb_rollback_pipeline,
    input subcycle_t                   wb_rollback_subcycle,

    // From nyuzi
    input local_thread_bitmap_t        thread_en,

    // From dcache_data_stage
    input local_thread_bitmap_t        wb_suspend_thread_oh,
    input local_thread_bitmap_t        l2i_dcache_wake_bitmap,
    input local_thread_bitmap_t        ior_wake_bitmap,

    // To performance_counters
    output logic                       ts_perf_instruction_issue);

    localparam THREAD_FIFO_SIZE = 8;

    // Difference between longest and shortest execution pipeline
    localparam WRITEBACK_ALLOC_STAGES = 4;

    decoded_instruction_t thread_instr[`THREADS_PER_CORE];
    decoded_instruction_t issue_instr;
    local_thread_bitmap_t thread_blocked;
    local_thread_bitmap_t can_issue_thread;
    local_thread_bitmap_t thread_issue_oh;
    local_thread_idx_t issue_thread_idx;
    logic[WRITEBACK_ALLOC_STAGES - 1:0] writeback_allocate;
    logic[WRITEBACK_ALLOC_STAGES - 1:0] writeback_allocate_nxt;
    subcycle_t current_subcycle[`THREADS_PER_CORE];
    logic issue_last_subcycle[`THREADS_PER_CORE];

`ifdef SIMULATION
    // Used for visualizer app
    enum logic[2:0] {
        TS_WAIT_ICACHE = 0,
        TS_WAIT_DCACHE = 1,
        TS_WAIT_RAW = 2,
        TS_WAIT_WRITEBACK_CONFLICT = 3,
        TS_READY = 4
    } thread_state[`THREADS_PER_CORE];
`endif

    //
    // Per-thread instruction FIFOs & scoreboards
    //
    genvar thread_idx;
    generate
        for (thread_idx = 0; thread_idx < `THREADS_PER_CORE; thread_idx++)
        begin : thread_logic_gen
            logic ififo_almost_full;
            logic ififo_empty;
            logic writeback_conflict;
            logic rollback_this_thread;
            logic enqueue_this_thread;
            logic writeback_this_thread;
            logic scoreboard_can_issue;

            assign enqueue_this_thread = id_instruction_valid
                && id_thread_idx == local_thread_idx_t'(thread_idx);

            sync_fifo #(
                .WIDTH($bits(id_instruction)),
                .SIZE(THREAD_FIFO_SIZE),
                .ALMOST_FULL_THRESHOLD(THREAD_FIFO_SIZE - 3)
            ) instruction_fifo(
                .flush_en(rollback_this_thread),
                .full(),
                .almost_full(ififo_almost_full),
                .enqueue_en(enqueue_this_thread),
                .enqueue_value(id_instruction),
                .empty(ififo_empty),
                .almost_empty(),
                .dequeue_en(issue_last_subcycle[thread_idx]),
                .dequeue_value(thread_instr[thread_idx]),
                .*);

            assign writeback_this_thread = wb_writeback_en
                && wb_writeback_thread_idx == local_thread_idx_t'(thread_idx)
                && wb_writeback_last_subcycle;
            assign rollback_this_thread = wb_rollback_en
                && wb_rollback_thread_idx == local_thread_idx_t'(thread_idx);

            scoreboard scoreboard(
                .next_instruction(thread_instr[thread_idx]),
                .will_issue(thread_issue_oh[thread_idx]),
                .writeback_en(writeback_this_thread),
                .rollback_en(rollback_this_thread),
                .*);

            // This signal goes back to the ifetch_tag_stage to enable fetching more
            // instructions. Deassert fetch enable a few cycles before the FIFO
            // fills up because there are several stages in-between.
            assign ts_fetch_en[thread_idx] = !ififo_almost_full && thread_en[thread_idx];

            always_comb
            begin
                // There can be a writeback conflict even if the instruction doesn't
                // write back to a register (if it cause a rollback, for example)
                unique case (thread_instr[thread_idx].pipeline_sel)
                    PIPE_INT_ARITH: writeback_conflict = writeback_allocate[0];
                    PIPE_MEM: writeback_conflict = writeback_allocate[1];
                    default: writeback_conflict = 0;
                endcase
            end

            // Only check the scoreboard on the first subcycle. The scoreboard only
            // tracks register granularity, not individual vector lanes. In most
            // cases, this is fine, but with a multi-cycle operation (like a gather
            // load), which writes back to the same register multiple times, this
            // would delay the load.
            assign can_issue_thread[thread_idx] = !ififo_empty
                && (scoreboard_can_issue || current_subcycle[thread_idx] != 0)
                && thread_en[thread_idx]
                && !rollback_this_thread
                && !writeback_conflict
                && !thread_blocked[thread_idx];
            assign issue_last_subcycle[thread_idx] = thread_issue_oh[thread_idx]
                && current_subcycle[thread_idx] == thread_instr[thread_idx].last_subcycle;

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                    current_subcycle[thread_idx] <= 0;
                else if (wb_rollback_en && wb_rollback_thread_idx == local_thread_idx_t'(thread_idx))
                    current_subcycle[thread_idx] <= wb_rollback_subcycle;
                else if (issue_last_subcycle[thread_idx])
                    current_subcycle[thread_idx] <= 0;
                else if (thread_issue_oh[thread_idx])
                    current_subcycle[thread_idx] <= current_subcycle[thread_idx] + subcycle_t'(1);
            end

`ifdef SIMULATION
            // Used for visualizer tool. There can be multiple events that prevent
            // a thread from executing, but I picked a order that seemed logical
            // to prioritize them so there is only one "state."
            // XXX does not capture rollbacks.
            always_comb
            begin
                if (ififo_empty)
                    thread_state[thread_idx] = TS_WAIT_ICACHE;
                else if (thread_blocked[thread_idx])
                    thread_state[thread_idx] = TS_WAIT_DCACHE;
                else if (!scoreboard_can_issue && current_subcycle[thread_idx] == 0)
                    thread_state[thread_idx] = TS_WAIT_RAW;
                else if (writeback_conflict)
                    thread_state[thread_idx] = TS_WAIT_WRITEBACK_CONFLICT;
                else
                    thread_state[thread_idx] = TS_READY;
            end
`endif
        end
    endgenerate

    // At the writeback stage, the floating point, integer, and memory
    // pipelines merge. Since these have different lengths, there is
    // a structural hazard where two instructions issued in different
    // cycles could arrive during the same cycle. Avoid that by tracking
    // instruction issue and not scheduling instructions that would
    // collide. Track instructions even if they don't write back to a
    // register, since they may have other side effects that the writeback
    // stage handles (for example, a store instruction can raise an exception)
    always_comb
    begin
        writeback_allocate_nxt = {1'b0, writeback_allocate[WRITEBACK_ALLOC_STAGES - 1:1]};
        if (|thread_issue_oh)
        begin
            unique case (issue_instr.pipeline_sel)
                PIPE_FLOAT_ARITH: writeback_allocate_nxt[3] = 1'b1;
                PIPE_MEM: writeback_allocate_nxt[0] = 1'b1;
                default:
                    ;
            endcase
        end
    end

    //
    // Choose which thread to issue
    //
    rr_arbiter #(.NUM_REQUESTERS(`THREADS_PER_CORE)) thread_select_arbiter(
        .request(can_issue_thread),
        .update_lru(1'b1),
        .grant_oh(thread_issue_oh),
        .*);

    oh_to_idx #(.NUM_SIGNALS(`THREADS_PER_CORE)) thread_oh_to_idx(
        .one_hot(thread_issue_oh),
        .index(issue_thread_idx));

    assign issue_instr = thread_instr[issue_thread_idx];

    always_ff @(posedge clk)
    begin
        ts_instruction <= issue_instr;
        ts_thread_idx <= issue_thread_idx;
        ts_subcycle <= current_subcycle[issue_thread_idx];
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            thread_blocked <= '0;
            ts_instruction_valid <= '0;
            ts_perf_instruction_issue <= '0;
            writeback_allocate <= '0;
            // End of automatics
        end
        else
        begin
            // Should not get a wake from l1 cache and io queue in the same cycle
            assert((l2i_dcache_wake_bitmap & ior_wake_bitmap) == 0);

            // Check for suspending a thread that isn't running
            assert((wb_suspend_thread_oh & thread_blocked) == 0);

            // Check for waking a thread that isn't suspended (or about to be suspended, see note below)
            assert(((l2i_dcache_wake_bitmap | ior_wake_bitmap) & ~(thread_blocked | wb_suspend_thread_oh)) == 0);

            // Don't issue blocked threads
            assert((thread_issue_oh & thread_blocked) == 0);

            // Only one thread should be blocked per cycle
            assert($onehot0(wb_suspend_thread_oh));

            ts_instruction_valid <= |thread_issue_oh;

            // The writeback stage asserts the suspend signal a cycle after a dcache
            // miss occurs. It is possible a cache miss is already pending for that
            // address, and that it gets filled in the next cycle. In this case,
            // suspend and wake will be asserted simultaneously. Wake will win
            // because of the order of this expression. This is intended, since
            // cache data is now available and the thread won't be rolled back.
            thread_blocked <= (thread_blocked | wb_suspend_thread_oh)
                & ~(l2i_dcache_wake_bitmap | ior_wake_bitmap);

            writeback_allocate <= writeback_allocate_nxt;
            ts_perf_instruction_issue <= |thread_issue_oh;
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Programmable interrupt timer
//

module timer
    #(parameter BASE_ADDRESS = 0)

    (input                    clk,
    input                     reset,

    // IO bus interface
    io_bus_interface.slave    io_bus,

    // Interrupt
    output logic              timer_interrupt);

    logic[31:0] counter;

    assign io_bus.read_data = '0;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            counter <= '0;
            timer_interrupt <= '0;
            // End of automatics
        end
        else
        begin
            if (io_bus.write_en && io_bus.address == BASE_ADDRESS)
                counter <= io_bus.write_data;
            else if (counter != 0)
                counter <= counter - 1;

            timer_interrupt <= counter == 0;
        end
    end
endmodule
//
// Copyright 2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Translation lookaside buffer.
// Caches virtual to physical address translations.
//

module tlb
    #(parameter NUM_ENTRIES = 64,
    parameter NUM_WAYS = 4)

    (input                    clk,
    input                     reset,

    // Command
    // (exe_writable means executable for icache, writable for dcache)
    input                     lookup_en,
    input                     update_en,
    input                     invalidate_en,
    input                     invalidate_all_en,
    input page_index_t        request_vpage_idx,
    input [ASID_WIDTH - 1:0]  request_asid,
    input page_index_t        update_ppage_idx,
    input                     update_present,
    input                     update_exe_writable,
    input                     update_supervisor,
    input                     update_global,

    // Response
    output page_index_t       lookup_ppage_idx,
    output logic              lookup_hit,
    output logic              lookup_present,
    output logic              lookup_exe_writable,
    output logic              lookup_supervisor);

    localparam NUM_SETS = NUM_ENTRIES / NUM_WAYS;
    localparam SET_INDEX_WIDTH = $clog2(NUM_SETS);
    localparam WAY_INDEX_WIDTH = $clog2(NUM_WAYS);

    logic[NUM_WAYS - 1:0] way_hit_oh;
    page_index_t way_ppage_idx[NUM_WAYS];
    logic way_present[NUM_WAYS];
    logic way_exe_writable[NUM_WAYS];
    logic way_supervisor[NUM_WAYS];
    page_index_t request_vpage_idx_latched;
    page_index_t update_ppage_idx_latched;
    logic[SET_INDEX_WIDTH - 1:0] request_set_idx;
    logic[SET_INDEX_WIDTH - 1:0] update_set_idx;
    logic update_en_latched;
    logic update_valid;
    logic invalidate_en_latched;
    logic tlb_read_en;
    logic[NUM_WAYS - 1:0] way_update_oh;
    logic[NUM_WAYS - 1:0] next_way_oh;
    logic update_present_latched;
    logic update_exe_writable_latched;
    logic update_supervisor_latched;
    logic update_global_latched;
    logic[ASID_WIDTH - 1:0] request_asid_latched;

    //
    // Stage 1: lookup
    //
    assign request_set_idx = request_vpage_idx[SET_INDEX_WIDTH - 1:0];
    assign update_set_idx = request_vpage_idx_latched[SET_INDEX_WIDTH - 1:0];
    assign tlb_read_en = lookup_en || update_en || invalidate_en;

    genvar way_idx;
    generate
        for (way_idx = 0; way_idx < NUM_WAYS; way_idx++)
        begin : way_gen
            page_index_t way_vpage_idx;
            logic way_valid;
            logic entry_valid[NUM_SETS];
            logic[ASID_WIDTH - 1:0] way_asid;
            logic way_global;

            sram_1r1w #(
                .SIZE(NUM_SETS),
                .DATA_WIDTH(PAGE_NUM_BITS * 2 + 4 + ASID_WIDTH),
                .READ_DURING_WRITE("NEW_DATA")
            ) tlb_paddr_sram(
                .read_en(tlb_read_en),
                .read_addr(request_set_idx),
                .read_data({way_vpage_idx,
                    way_asid,
                    way_ppage_idx[way_idx],
                    way_present[way_idx],
                    way_exe_writable[way_idx],
                    way_supervisor[way_idx],
                    way_global}),
                .write_en(way_update_oh[way_idx]),
                .write_addr(update_set_idx),
                .write_data({request_vpage_idx_latched,
                    request_asid_latched,
                    update_ppage_idx_latched,
                    update_present_latched,
                    update_exe_writable_latched,
                    update_supervisor_latched,
                    update_global_latched}),
                .*);

            always_ff @(posedge clk, posedge reset)
            begin
                if (reset)
                begin
                    for (int set_idx = 0; set_idx < NUM_SETS; set_idx++)
                        entry_valid[set_idx] <= 0;
                end
                else
                begin
                    if (invalidate_all_en)
                    begin
                        for (int set_idx = 0; set_idx < NUM_SETS; set_idx++)
                            entry_valid[set_idx] <= 0;
                    end
                    else if (way_update_oh[way_idx])
                        entry_valid[update_set_idx] <= update_valid;
                end
            end

            always_ff @(posedge clk)
            begin
                if (!tlb_read_en)
                    way_valid <= 0;
                else if (way_update_oh[way_idx] && update_set_idx == request_set_idx)
                    way_valid <= update_valid;  // Bypass
                else
                    way_valid <= entry_valid[request_set_idx];
            end

            assign way_hit_oh[way_idx] = way_valid
                && way_vpage_idx == request_vpage_idx_latched
                && (way_asid == request_asid_latched || way_global
                    || (update_en_latched && update_global_latched));
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        update_ppage_idx_latched <= update_ppage_idx;
        update_present_latched <= update_present;
        update_exe_writable_latched <= update_exe_writable;
        update_supervisor_latched <= update_supervisor;
        update_global_latched <= update_global;
        request_asid_latched <= request_asid;
        request_vpage_idx_latched <= request_vpage_idx;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            invalidate_en_latched <= '0;
            update_en_latched <= '0;
            // End of automatics
        end
        else
        begin
            assert($onehot0({lookup_en, update_en, invalidate_en, invalidate_all_en}));
            update_en_latched <= update_en;
            invalidate_en_latched <= invalidate_en;
        end
    end

    //
    // Stage 2: output/update
    //
    assign lookup_hit = |way_hit_oh;
    always_comb
    begin
        // Enabled mux. Use OR to avoid inferring priority encoder.
        lookup_ppage_idx = 0;
        lookup_present = 0;
        lookup_exe_writable = 0;
        lookup_supervisor = 0;
        for (int way = 0; way < NUM_WAYS; way++)
        begin
            if (way_hit_oh[way])
            begin
                lookup_ppage_idx |= way_ppage_idx[way];
                lookup_present |= way_present[way];
                lookup_exe_writable |= way_exe_writable[way];
                lookup_supervisor |= way_supervisor[way];
            end
        end
    end

    always_comb
    begin
        if (update_en_latched || invalidate_en_latched)
        begin
            if (lookup_hit)
                way_update_oh = way_hit_oh;
            else
                way_update_oh = next_way_oh;
        end
        else
            way_update_oh = '0;
    end

    // If there is an invalidate, clear the valid bit
    assign update_valid = update_en_latched;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            next_way_oh <= NUM_WAYS'(1);
            /*AUTORESET*/
        end
        else
        begin
            // Make sure we don't have duplicate entries in a set
            assert($onehot0(way_hit_oh));
            if (update_en)
            begin
                // Rotate
                next_way_oh <= {next_way_oh[NUM_WAYS - 2:0], next_way_oh[NUM_WAYS - 1]};
            end
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Serial receive logic
//

module uart_receive
    #(parameter DIVISOR_WIDTH = 16)
    (input                        clk,
    input                         reset,
    input[DIVISOR_WIDTH - 1:0]    clocks_per_bit,
    input                         uart_rx,
    output[7:0]                   rx_char,
    output logic                  rx_char_valid,
    output logic                  rx_frame_error);

    typedef enum {
        STATE_WAIT_START,
        STATE_READ_CHARACTER,
        STATE_STOP_BITS
    } receive_state_t;

    receive_state_t state_ff;
    receive_state_t state_nxt;
    logic[DIVISOR_WIDTH - 1:0] sample_count_ff;
    logic[DIVISOR_WIDTH - 1:0] sample_count_nxt;
    logic[7:0] shift_register;
    logic[3:0] bit_count_ff;
    logic[3:0] bit_count_nxt;
    logic do_shift;
    logic rx_sync;

    assign rx_char = shift_register;

    // If it's out of sync, rx_sync is 0 from a new start bit.
    // Sampling it at the end may be sufficient to indicate frame error.
    assign rx_frame_error = !rx_sync;

    synchronizer #(.RESET_STATE(1)) rx_synchronizer(
        .clk(clk),
        .reset(reset),
        .data_i(uart_rx),
        .data_o(rx_sync));

    always_comb
    begin
        bit_count_nxt = bit_count_ff;
        state_nxt = state_ff;
        sample_count_nxt = sample_count_ff;
        rx_char_valid = 0;
        do_shift = 0;

        unique case (state_ff)
            STATE_WAIT_START:
            begin
                if (!rx_sync)
                begin
                    state_nxt = STATE_READ_CHARACTER;
                    // We are at the beginning of the start bit. Next
                    // sample point is in middle of first data bit.
                    // Set divider to 1.5 times bit duration.
                    sample_count_nxt = clocks_per_bit + {1'b0, clocks_per_bit[DIVISOR_WIDTH - 1:1]};
                end
            end

            STATE_READ_CHARACTER:
            begin
                if (sample_count_ff == 0)
                begin
                    sample_count_nxt = clocks_per_bit;
                    do_shift = 1;
                    if (bit_count_ff == 7)
                    begin
                        state_nxt = STATE_STOP_BITS;
                        bit_count_nxt = 0;
                    end
                    else
                        bit_count_nxt = bit_count_ff + 4'd1;
                end
                else
                    sample_count_nxt = sample_count_ff - DIVISOR_WIDTH'(1);
            end

            STATE_STOP_BITS:
            begin
                if (sample_count_ff == 0)
                begin
                    state_nxt = STATE_WAIT_START;
                    rx_char_valid = 1;
                end
                else
                    sample_count_nxt = sample_count_ff - DIVISOR_WIDTH'(1);
            end
        endcase
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            state_ff <= STATE_WAIT_START;
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            bit_count_ff <= '0;
            sample_count_ff <= '0;
            shift_register <= '0;
            // End of automatics
        end
        else
        begin
            state_ff <= state_nxt;
            sample_count_ff <= sample_count_nxt;
            bit_count_ff <= bit_count_nxt;
            if (do_shift)
                shift_register <= {rx_sync, shift_register[7:1]};
        end
    end
endmodule

//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Serial port interface.
//

module uart
    #(parameter BASE_ADDRESS = 0)

    (input                    clk,
    input                     reset,

    // IO bus interface
    io_bus_interface.slave    io_bus,
    output logic              rx_interrupt,

    // UART interface
    output logic              uart_tx,
    input                     uart_rx);

    localparam STATUS_REG = BASE_ADDRESS;
    localparam RX_REG = BASE_ADDRESS + 4;
    localparam TX_REG = BASE_ADDRESS + 8;
    localparam DIVISOR_REG = BASE_ADDRESS + 12;
    localparam FIFO_LENGTH = 8;
    localparam DIVISOR_WIDTH = 16;

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    logic               rx_char_valid;          // From uart_receive of uart_receive.v
    logic               tx_ready;               // From uart_transmit of uart_transmit.v
    // End of automatics
    logic[7:0] rx_fifo_char;
    logic rx_fifo_empty;
    logic rx_fifo_read;
    logic rx_fifo_full;
    logic rx_fifo_overrun;
    logic rx_fifo_overrun_dq;
    logic rx_fifo_frame_error;
    logic[7:0] rx_char;
    logic rx_frame_error;
    logic tx_en;
    logic[DIVISOR_WIDTH - 1:0] clocks_per_bit;

    assign rx_interrupt = !rx_fifo_empty;

    assign tx_en = io_bus.write_en && io_bus.address == TX_REG;

    uart_transmit #(.DIVISOR_WIDTH(DIVISOR_WIDTH)) uart_transmit(
        .tx_char(io_bus.write_data[7:0]),
        .*);

    uart_receive #(.DIVISOR_WIDTH(DIVISOR_WIDTH)) uart_receive(.*);

    assign rx_fifo_read = io_bus.address == RX_REG && io_bus.read_en;

    // Logic for Overrun Error (OE) bit
    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            rx_fifo_overrun <= 0;
            clocks_per_bit <= 1;
        end
        else
        begin
            if (io_bus.address == DIVISOR_REG && io_bus.write_en)
                clocks_per_bit <= io_bus.write_data[DIVISOR_WIDTH - 1:0];

            case (io_bus.address)
                STATUS_REG:
                begin
                    io_bus.read_data[31:4] <= 0;
                    io_bus.read_data[3:0] <= {rx_fifo_frame_error, rx_fifo_overrun, !rx_fifo_empty, tx_ready};
                end

                default:
                begin
                    io_bus.read_data[31:8] <= 0;
                    io_bus.read_data[7:0] <= rx_fifo_char;
                end
            endcase

            if (rx_fifo_read)
                rx_fifo_overrun <= 0;

            if (rx_char_valid && rx_fifo_full)
                rx_fifo_overrun <= 1;
        end
    end

    assign rx_fifo_overrun_dq = rx_char_valid && rx_fifo_full;

    // Up to ALMOST_FULL_THRESHOLD characters can be filled. FIFO is
    // automatically dequeued and OE bit is asserted when a character is queued
    // after this point. The OE bit is deasserted when rx_fifo_read or the
    // number of stored characters is lower than the threshold.
    sync_fifo #(
        .WIDTH(9),
        .SIZE(FIFO_LENGTH),
        .ALMOST_FULL_THRESHOLD(FIFO_LENGTH - 1)
    ) rx_fifo(
        .clk(clk),
        .reset(reset),
        .almost_empty(),
        .almost_full(rx_fifo_full),
        .full(),
        .empty(rx_fifo_empty),
        .dequeue_value({rx_fifo_frame_error, rx_fifo_char}),
        .enqueue_en(rx_char_valid),
        .flush_en(1'b0),
        .enqueue_value({rx_frame_error, rx_char}),
        .dequeue_en(rx_fifo_read || rx_fifo_overrun_dq));
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// Serial transmit logic
//

module uart_transmit
    #(parameter DIVISOR_WIDTH = 16)
    (input                        clk,
    input                         reset,
    input[DIVISOR_WIDTH - 1:0]    clocks_per_bit,
    input                         tx_en,
    output logic                  tx_ready,
    input[7:0]                    tx_char,
    output logic                  uart_tx);

    localparam START_BIT = 1'b0;
    localparam STOP_BIT = 1'b1;

    logic[9:0] tx_shift;
    logic[3:0] shift_count;
    logic[DIVISOR_WIDTH - 1:0] next_edge_clocks;
    logic transmit_active;

    assign transmit_active = shift_count != 0;
    assign uart_tx = transmit_active ? tx_shift[0] : 1'b1;
    assign tx_ready = !transmit_active;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            next_edge_clocks <= '0;
            shift_count <= '0;
            tx_shift <= '0;
            // End of automatics
        end
        else
        begin
            if (transmit_active)
            begin
                if (next_edge_clocks == 0)
                begin
                    shift_count <= shift_count - 4'd1;
                    tx_shift <= {1'b0, tx_shift[9:1]};
                    next_edge_clocks <= clocks_per_bit;
                end
                else
                    next_edge_clocks <= next_edge_clocks - DIVISOR_WIDTH'(1);
            end
            else if (tx_en)
            begin
                shift_count <= 4'd10;
                tx_shift <= {STOP_BIT, tx_char, START_BIT};
                next_edge_clocks <= clocks_per_bit;
            end
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Drive VGA display.  This is an AXI master that DMAs color
// data from a memory framebuffer and sends it to an ADV7123 VGA
// DAC with timing signals.
//

module vga_controller
    #(parameter BASE_ADDRESS = 0)
    (input                      clk,
    input                       reset,

    // I/O bus control register access
    io_bus_interface.slave      io_bus,
    output logic                frame_interrupt,

    // DMA access to memory
    axi4_interface.master       axi_bus,

    // To DAC
    output [7:0]                vga_r,
    output [7:0]                vga_g,
    output [7:0]                vga_b,
    output logic                vga_clk,
    output logic                vga_blank_n,
    output logic                vga_hs,
    output logic                vga_vs,
    output logic                vga_sync_n);

    // The burst length is twice that of a CPU cache line fill to ensure
    // sufficient memory bandwidth even when ping-ponging.
    localparam BURST_LENGTH = 64;
    localparam PIXEL_FIFO_LENGTH = 128;

    typedef enum {
        STATE_WAIT_FRAME_START,
        STATE_WAIT_FIFO_SPACE,
        STATE_ISSUE_ADDR,
        STATE_BURST_ACTIVE
    } dma_state_t;

    /*AUTOLOGIC*/
    // Beginning of automatic wires (for undeclared instantiated-module outputs)
    logic               in_visible_region;      // From vga_sequencer of vga_sequencer.v
    logic               pixel_en;               // From vga_sequencer of vga_sequencer.v
    logic               start_frame;            // From vga_sequencer of vga_sequencer.v
    // End of automatics
    logic[31:0] vram_addr;
    logic[7:0] _ignore_alpha;
    logic pixel_fifo_empty;
    logic pixel_fifo_almost_empty;
    logic[31:0] fb_base_address;
    logic[31:0] fb_length;
    dma_state_t axi_state;
    logic[7:0] burst_count;
    logic[18:0] pixel_count;
    logic sequencer_en;

    assign frame_interrupt = start_frame;
    assign vga_blank_n = in_visible_region;
    assign vga_sync_n = 1'b0;    // Not used
    assign vga_clk = pixel_en;    // This is a bid odd: using enable as external clock.

    // Buffer data to the display from SDRAM. The enqueue threshold is large
    // enough to enqueue an entire burst from memory. Empty the FIFO at the
    // beginning of the vblank period so it will resynchronize if there was
    // an underrun.
    sync_fifo #(
        .WIDTH(24),
        .SIZE(PIXEL_FIFO_LENGTH),
        .ALMOST_EMPTY_THRESHOLD(PIXEL_FIFO_LENGTH - BURST_LENGTH - 1)) pixel_fifo(
        .clk(clk),
        .reset(reset),
        .flush_en(start_frame),
        .almost_full(),
        .empty(pixel_fifo_empty),
        .almost_empty(pixel_fifo_almost_empty),
        .dequeue_value({vga_r, vga_g, vga_b}),
        .enqueue_value(axi_bus.s_rdata[31:8]),
        .enqueue_en(axi_bus.s_rvalid),
        .full(),
        .dequeue_en(pixel_en && in_visible_region && !pixel_fifo_empty));

    // DMA state machine
    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            vram_addr <= '0;
            axi_state <= STATE_WAIT_FRAME_START;

            /*AUTORESET*/
            // Beginning of autoreset for uninitialized flops
            burst_count <= '0;
            pixel_count <= '0;
            // End of automatics
        end
        else
        begin
            // Check for FIFO underrun
            assert(!(pixel_en && in_visible_region && pixel_fifo_empty));

            unique case (axi_state)
                // This state exists so this will automatically resynchronize in the event
                // of a FIFO underrun. At the beginning of the vblank interval,
                // simultaneously clear the FIFO and start the first DMA transaction.
                STATE_WAIT_FRAME_START:
                begin
                    if (start_frame && sequencer_en)
                    begin
                        // Ensure there is no data left in the FIFO (which
                        // would imply we fetched too much)
                        assert(pixel_fifo_empty);

                        axi_state <= STATE_ISSUE_ADDR;
                        pixel_count <= 0;
                        vram_addr <= fb_base_address;
                    end
                end

                // Wait until there is enough free space in the FIFO to accept
                // an entire burst from memory.
                STATE_WAIT_FIFO_SPACE:
                begin
                    if (pixel_fifo_almost_empty)
                        axi_state <= STATE_ISSUE_ADDR;
                end

                STATE_ISSUE_ADDR:
                begin
                    if (axi_bus.s_arready)
                        axi_state <= STATE_BURST_ACTIVE;
                end

                STATE_BURST_ACTIVE:
                begin
                    if (axi_bus.s_rvalid)
                    begin
                        if (burst_count == BURST_LENGTH - 1)
                        begin
                            // Burst complete
                            burst_count <= 0;
                            if (pixel_count == 19'(fb_length - BURST_LENGTH))
                            begin
                                // Frame complete
                                axi_state <= STATE_WAIT_FRAME_START;
                            end
                            else
                            begin
                                if (!sequencer_en)
                                    axi_state <= STATE_WAIT_FRAME_START; // Abort frame
                                else if (pixel_fifo_almost_empty)
                                    axi_state <= STATE_ISSUE_ADDR;
                                else
                                    axi_state <= STATE_WAIT_FIFO_SPACE;

                                vram_addr <= vram_addr + BURST_LENGTH * 4;
                                pixel_count <= pixel_count + 19'(BURST_LENGTH);
                            end
                        end
                        else
                            burst_count <= burst_count + 8'd1;
                    end
                end

                default: axi_state <= STATE_WAIT_FRAME_START;
            endcase
        end
    end

    assign axi_bus.m_rready = 1'b1;    // The request is only made when there is enough room.
    assign axi_bus.m_arlen = 8'(BURST_LENGTH - 1);
    assign axi_bus.m_arvalid = axi_state == STATE_ISSUE_ADDR;
    assign axi_bus.m_araddr = vram_addr;
    assign axi_bus.m_awaddr = '0;
    assign axi_bus.m_awlen = '0;

    // Write channels not used.
    assign axi_bus.m_wdata = '0;
    assign axi_bus.m_awvalid = '0;
    assign axi_bus.m_wlast = 0;
    assign axi_bus.m_wvalid = 0;
    assign axi_bus.m_bready = 0;

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            sequencer_en <= 0;
            fb_base_address <= '0;
            fb_length <= '0;
        end
        else if (io_bus.write_en)
        begin
            case (io_bus.address)
                BASE_ADDRESS: sequencer_en <= io_bus.write_data[0];
                BASE_ADDRESS + 8: fb_base_address <= io_bus.write_data;
                BASE_ADDRESS + 12: fb_length <= io_bus.write_data;
            endcase
        end
    end

    assign io_bus.read_data = '0;

    vga_sequencer vga_sequencer(
        .prog_write_en(io_bus.write_en && io_bus.address == BASE_ADDRESS + 4),
        .prog_data(io_bus.write_data),
        .*);
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//
// This generates timing signals for the VGA interface.
// Software uploads a small microcode program that this runs. It
// contains two counters and supports two instructions:
// INITCNT: load a value into the selected counter
// LOOP: decrement the selected counter and branch to an address if the
//       value is not zero.
// The frame_done bit will restart the microprogram from the beginning.
//
// The pixel rate (25 Mhz) is one half the input clock rate. This executes
// one instruction per pixel clock (although it's in the main clock domain,
// using pixel_en to clock gate for each pixel).
//
module vga_sequencer(
    input                       clk,
    input                       reset,
    output logic                vga_vs,
    output logic                vga_hs,
    output logic                start_frame,
    output logic                in_visible_region,
    output logic                pixel_en,
    input                       sequencer_en,
    input                       prog_write_en,
    input[31:0]                 prog_data);

    localparam MAX_INSTRUCTIONS = 48;

    typedef logic[$clog2(MAX_INSTRUCTIONS) - 1:0] progaddr_t;
    typedef logic[12:0] counter_t;

    typedef enum logic {
        INITCNT,
        LOOP
    } instruction_type_t;

    typedef struct packed {
        instruction_type_t instruction_type;
        logic counter_select;
        counter_t immediate_value;

        // VGA synchronization signals
        logic vsync;
        logic hsync;
        logic frame_done;
        logic in_visible_region;
    } uop_t;

    uop_t current_uop;
    counter_t counter[2];
    counter_t counter_nxt;
    progaddr_t pc;
    progaddr_t pc_nxt;
    progaddr_t prog_load_addr;
    logic branch_en;

    sram_1r1w #(
        .DATA_WIDTH($bits(uop_t)),
        .SIZE(MAX_INSTRUCTIONS)
    ) instruction_memory(
        .read_en(1'b1),
        .read_addr(pc_nxt),
        .read_data(current_uop),
        .write_en(prog_write_en),
        .write_addr(prog_load_addr),
        .write_data(prog_data[$bits(uop_t) - 1:0]),
        .*);

    assign counter_nxt = current_uop.instruction_type == INITCNT
        ? current_uop.immediate_value
        : counter[current_uop.counter_select] - counter_t'(1);
    assign vga_vs = current_uop.vsync && sequencer_en;
    assign vga_hs = current_uop.hsync && sequencer_en;
    assign start_frame = pc == 0 && sequencer_en;
    assign in_visible_region = current_uop.in_visible_region && sequencer_en;
    assign branch_en = current_uop.frame_done || (current_uop.instruction_type == LOOP
        && counter_nxt != 0);

    always_comb
    begin
        if (pixel_en)
        begin
            if (branch_en)
                pc_nxt = progaddr_t'(current_uop.immediate_value);
            else
                pc_nxt = pc + progaddr_t'(1);
        end
        else
            pc_nxt = pc;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
        begin
            counter[0] <= '0;
            counter[1] <= '0;
            pc <= '0;
            prog_load_addr <= '0;
        end
        else
        begin
            // Divide 50 Mhz clock by two to derive 25 Mhz pixel rate
            pixel_en <= !pixel_en;

            if (sequencer_en)
            begin
                if (pixel_en)
                    counter[current_uop.counter_select] <= counter_nxt;

                pc <= pc_nxt;
                prog_load_addr <= '0;
            end
            else if (prog_write_en)
            begin
                pc <= '0;
                prog_load_addr <= prog_load_addr + progaddr_t'(1);
            end
        end
    end
endmodule
//
// Copyright 2011-2015 Jeff Bush
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

//`include "defines.svh"

import defines::*;

//
// Instruction Pipeline Writeback Stage
// - Selects result from appropriate pipeline (memory, integer, floating point)
// - Aligns memory read results
// - Writes results back to register file
// - Handles rollbacks. Most are raised earlier in the pipeline, but it
//   handles them here to avoid having to reconcile multiple rollbacks in
//   the same cycle.
//   * Branch
//   * Data cache miss
//   * Exception
//
// Exceptions and interrupts are precise in this architecture. This is
// complicated by the fact that instructions may retire out of order because
// the execution pipelines have different lengths. It's also possible, after
// a rollback, for earlier instructions from the same thread to arrive at
// this stage (because they were in the longer floating point pipeline).
// The rollback signal does not flush later stages of the multicycle pipeline
// for this reason.
//

module writeback_stage(
    input                                 clk,
    input                                 reset,

    // From fp_execute_stage5 (floating point pipline)
    input                                 fx5_instruction_valid,
    input decoded_instruction_t           fx5_instruction,
    input vector_t                        fx5_result,
    input vector_mask_t                   fx5_mask_value,
    input local_thread_idx_t              fx5_thread_idx,
    input subcycle_t                      fx5_subcycle,

    // From int_execute_stage (integer pipeline)
    input                                 ix_instruction_valid,
    input decoded_instruction_t           ix_instruction,
    input vector_t                        ix_result,
    input local_thread_idx_t              ix_thread_idx,
    input vector_mask_t                   ix_mask_value,
    input logic                           ix_rollback_en,
    input scalar_t                        ix_rollback_pc,
    input subcycle_t                      ix_subcycle,
    input                                 ix_privileged_op_fault,

    // From dcache_data_stage (memory pipeline)
    input                                 dd_instruction_valid,
    input decoded_instruction_t           dd_instruction,
    input vector_mask_t                   dd_lane_mask,
    input local_thread_idx_t              dd_thread_idx,
    input l1d_addr_t                      dd_request_vaddr,
    input subcycle_t                      dd_subcycle,
    input                                 dd_rollback_en,
    input scalar_t                        dd_rollback_pc,
    input cache_line_data_t               dd_load_data,
    input                                 dd_suspend_thread,
    input                                 dd_io_access,
    input logic                           dd_trap,
    input trap_cause_t                    dd_trap_cause,

    // From l1_store_queue
    input [CACHE_LINE_BYTES - 1:0]        sq_store_bypass_mask,
    input cache_line_data_t               sq_store_bypass_data,
    input                                 sq_store_sync_success,
    input                                 sq_rollback_en,

    // From io_request_queue
    input scalar_t                        ior_read_value,
    input logic                           ior_rollback_en,

    // From control_registers
    input scalar_t                        cr_creg_read_val,
    input scalar_t                        cr_trap_handler,
    input scalar_t                        cr_tlb_miss_handler,
    input subcycle_t                      cr_eret_subcycle[`THREADS_PER_CORE],

    // To control_registers
    output logic                          wb_trap,
    output trap_cause_t                   wb_trap_cause,
    output scalar_t                       wb_trap_pc,
    output scalar_t                       wb_trap_access_vaddr,
    output subcycle_t                     wb_trap_subcycle,
    output syscall_index_t                wb_syscall_index,
    output logic                          wb_eret,

    // Rollback signals to all stages
    output logic                          wb_rollback_en,
    output local_thread_idx_t             wb_rollback_thread_idx,
    output scalar_t                       wb_rollback_pc,
    output pipeline_sel_t                 wb_rollback_pipeline,
    output subcycle_t                     wb_rollback_subcycle,

    // To operand_fetch_stage/thread_select_stage
    output logic                          wb_writeback_en,
    output local_thread_idx_t             wb_writeback_thread_idx,
    output logic                          wb_writeback_vector,
    output vector_t                       wb_writeback_value,
    output vector_mask_t                  wb_writeback_mask,
    output register_idx_t                 wb_writeback_reg,
    output logic                          wb_writeback_last_subcycle,

    // To thread_select_stage
    output local_thread_bitmap_t          wb_suspend_thread_oh,

    // to on_chip_debugger
    output logic                          wb_inst_injected,

    // To performance_counters
    output logic                          wb_perf_instruction_retire,
    output logic                          wb_perf_store_rollback,
    output logic                          wb_perf_interrupt);

    scalar_t mem_load_lane;
    logic[$clog2(CACHE_LINE_WORDS) - 1:0] mem_load_lane_idx;
    logic[7:0] byte_aligned;
    logic[15:0] half_aligned;
    logic[31:0] swapped_word_value;
    memory_op_t memory_op;
    cache_line_data_t endian_twiddled_data;
    logic[NUM_VECTOR_LANES - 1:0] scycle_vcompare_result;
    logic[NUM_VECTOR_LANES - 1:0] mcycle_vcompare_result;
    vector_mask_t dd_vector_lane_oh;
    cache_line_data_t bypassed_read_data;
    local_thread_bitmap_t thread_dd_oh;
    logic last_subcycle_dd;
    logic last_subcycle_ix;
    logic last_subcycle_fx;
    logic writeback_en_nxt;
    local_thread_idx_t writeback_thread_idx_nxt;
    logic writeback_vector_nxt;
    vector_t writeback_value_nxt;
    vector_mask_t writeback_mask_nxt;
    register_idx_t writeback_reg_nxt;
    logic writeback_last_subcycle_nxt;

    //
    // Rollback control logic
    //
    // These signals are not registered because the next instruction may be a
    // memory store and we must squash it before it applies its side effects.
    // This stage handles all rollbacks, so there can be only one asserted at a
    // time.
    //
    always_comb
    begin
        wb_rollback_en = 0;
        wb_rollback_pc = 0;
        wb_rollback_thread_idx = 0;
        wb_rollback_pipeline = PIPE_INT_ARITH;
        wb_trap = 0;
        wb_trap_cause = {2'b0, TT_RESET};
        wb_rollback_subcycle = 0;
        wb_trap_pc = 0;
        wb_trap_access_vaddr = 0;
        wb_trap_subcycle = dd_subcycle;
        wb_eret = 0;

        if (ix_instruction_valid && (ix_instruction.has_trap
            || ix_privileged_op_fault))
        begin
            // Fault piggybacked on instruction, which goes through the
            // integer pipeline, or fault detected in integer pipeline.
            wb_rollback_en = 1;
            if (ix_instruction.trap_cause.trap_type == TT_TLB_MISS)
                wb_rollback_pc = cr_tlb_miss_handler;
            else
                wb_rollback_pc = cr_trap_handler;

            wb_rollback_thread_idx = ix_thread_idx;
            wb_rollback_pipeline = PIPE_INT_ARITH;
            wb_trap = 1;
            if (ix_privileged_op_fault)
                wb_trap_cause = {2'b0, TT_PRIVILEGED_OP};
            else
                wb_trap_cause = ix_instruction.trap_cause;

            wb_trap_pc = ix_instruction.pc;
            wb_trap_access_vaddr = ix_instruction.pc;
            wb_trap_subcycle = ix_subcycle;
        end
        else if (dd_instruction_valid && dd_trap)
        begin
            // Memory access fault
            wb_rollback_en = 1'b1;
            if (dd_trap_cause.trap_type == TT_TLB_MISS)
                wb_rollback_pc = cr_tlb_miss_handler;
            else
                wb_rollback_pc = cr_trap_handler;

            wb_rollback_thread_idx = dd_thread_idx;
            wb_rollback_pipeline = PIPE_MEM;
            wb_trap = 1;
            wb_trap_cause = dd_trap_cause;
            wb_trap_pc = dd_instruction.pc;
            wb_trap_access_vaddr = dd_request_vaddr;
        end
        else if (ix_instruction_valid && ix_rollback_en)
        begin
            // Branch rollback from integer pipeline.
            wb_rollback_en = 1;
            wb_rollback_pc = ix_rollback_pc;
            wb_rollback_thread_idx = ix_thread_idx;
            wb_rollback_pipeline = PIPE_INT_ARITH;
            if (ix_instruction.branch_type == BRANCH_ERET)
            begin
                wb_eret = 1;
                wb_rollback_subcycle = cr_eret_subcycle[ix_thread_idx];
            end
            else
                wb_rollback_subcycle = ix_subcycle;
        end
        else if (dd_instruction_valid && (dd_rollback_en || sq_rollback_en || ior_rollback_en))
        begin
            // Rollback from memory pipeline because of a data cache miss,
            // store queue full, or when an IO request is sent.
            wb_rollback_en = 1;
            wb_rollback_pc = dd_rollback_pc;
            wb_rollback_thread_idx = dd_thread_idx;
            wb_rollback_pipeline = PIPE_MEM;
            wb_rollback_subcycle = dd_subcycle;
        end
    end

    assign wb_syscall_index = syscall_index_t'(ix_instruction.immediate_value);

    // Return if this instruction was injected by the on chip debugger.
    always_comb
    begin
        if (ix_instruction_valid)
            wb_inst_injected = ix_instruction.injected;
        else if (dd_instruction_valid)
            wb_inst_injected = dd_instruction.injected;
        else if (fx5_instruction_valid)
            wb_inst_injected = fx5_instruction.injected;
        else
            wb_inst_injected = 0;
    end

    idx_to_oh #(
        .NUM_SIGNALS(`THREADS_PER_CORE),
        .DIRECTION("LSB0")
    ) idx_to_oh_thread(
        .one_hot(thread_dd_oh),
        .index(dd_thread_idx));

    // Suspend thread if necessary
    assign wb_suspend_thread_oh = (dd_suspend_thread || sq_rollback_en || ior_rollback_en)
        ? thread_dd_oh : local_thread_bitmap_t'(0);

    // If there is a pending store for the value that was just read, merge it into
    // the data returned from the L1 data cache.
    genvar byte_lane;
    generate
        for (byte_lane = 0; byte_lane < CACHE_LINE_BYTES; byte_lane++)
        begin : lane_bypass_gen
            assign bypassed_read_data[byte_lane * 8+:8] = sq_store_bypass_mask[byte_lane]
                ? sq_store_bypass_data[byte_lane * 8+:8] : dd_load_data[byte_lane * 8+:8];
        end
    endgenerate

    assign memory_op = dd_instruction.memory_access_type;
    assign mem_load_lane_idx = ~dd_request_vaddr.offset[2+:$clog2(CACHE_LINE_WORDS)];
    assign mem_load_lane = bypassed_read_data[mem_load_lane_idx * 32+:32];

    // Byte memory load aligner.
    always_comb
    begin
        unique case (dd_request_vaddr.offset[1:0])
            2'd0: byte_aligned = mem_load_lane[31:24];
            2'd1: byte_aligned = mem_load_lane[23:16];
            2'd2: byte_aligned = mem_load_lane[15:8];
            2'd3: byte_aligned = mem_load_lane[7:0];
            default: byte_aligned = '0;
        endcase
    end

    // Halfword memory load aligner.
    always_comb
    begin
        unique case (dd_request_vaddr.offset[1])
            1'd0: half_aligned = {mem_load_lane[23:16], mem_load_lane[31:24]};
            1'd1: half_aligned = {mem_load_lane[7:0], mem_load_lane[15:8]};
            default: half_aligned = '0;
        endcase
    end

    assign swapped_word_value = {
        mem_load_lane[7:0],
        mem_load_lane[15:8],
        mem_load_lane[23:16],
        mem_load_lane[31:24]
    };

    // Endian swap memory load
    genvar swap_word;
    generate
        for (swap_word = 0; swap_word < CACHE_LINE_BYTES / 4; swap_word++)
        begin : swap_word_gen
            assign endian_twiddled_data[swap_word * 32+:8] = bypassed_read_data[swap_word * 32 + 24+:8];
            assign endian_twiddled_data[swap_word * 32 + 8+:8] = bypassed_read_data[swap_word * 32 + 16+:8];
            assign endian_twiddled_data[swap_word * 32 + 16+:8] = bypassed_read_data[swap_word * 32 + 8+:8];
            assign endian_twiddled_data[swap_word * 32 + 24+:8] = bypassed_read_data[swap_word * 32+:8];
        end
    endgenerate

    // Compress vector comparisons to one bit per lane.
    genvar mask_lane;
    generate
        for (mask_lane = 0; mask_lane < NUM_VECTOR_LANES; mask_lane++)
        begin : compare_result_gen
            assign scycle_vcompare_result[mask_lane] = ix_result[NUM_VECTOR_LANES - mask_lane - 1][0];
            assign mcycle_vcompare_result[mask_lane] = fx5_result[NUM_VECTOR_LANES - mask_lane - 1][0];
        end
    endgenerate

    idx_to_oh #(
        .NUM_SIGNALS(NUM_VECTOR_LANES),
        .DIRECTION("LSB0")
    ) convert_dd_lane(
        .one_hot(dd_vector_lane_oh),
        .index(dd_subcycle));

    assign last_subcycle_dd = dd_subcycle == dd_instruction.last_subcycle;
    assign last_subcycle_ix = ix_subcycle == ix_instruction.last_subcycle;
    assign last_subcycle_fx = fx5_subcycle == fx5_instruction.last_subcycle;

    always_comb
    begin
        writeback_en_nxt = 0;
        writeback_thread_idx_nxt = 0;
        writeback_mask_nxt = 0;
        writeback_value_nxt = 0;
        writeback_vector_nxt = 0;
        writeback_reg_nxt = 0;
        writeback_last_subcycle_nxt = 0;

        // wb_rollback_en is derived combinatorially from the instruction
        // that is about to retire, so this doesn't need to check
        // wb_rollback_thread_idx like other places.
        if (fx5_instruction_valid)
        begin
            //
            // Floating point pipeline result
            //
            if (fx5_instruction.has_dest && !wb_rollback_en)
                writeback_en_nxt = 1;

            writeback_thread_idx_nxt = fx5_thread_idx;
            writeback_mask_nxt = fx5_mask_value;
            if (fx5_instruction.compare)
                writeback_value_nxt = vector_t'(mcycle_vcompare_result);
            else
                writeback_value_nxt = fx5_result;

            writeback_vector_nxt = fx5_instruction.dest_vector;
            writeback_reg_nxt = fx5_instruction.dest_reg;
            writeback_last_subcycle_nxt = last_subcycle_fx;
        end
        else if (ix_instruction_valid)
        begin
            //
            // Integer pipeline result
            //
            if (ix_instruction.branch
                && (ix_instruction.branch_type == BRANCH_CALL_OFFSET
                || ix_instruction.branch_type == BRANCH_CALL_REGISTER))
            begin
                // Call is a special case: it both rolls back and writes
                // back a register (ra)
                writeback_en_nxt = 1;
            end
            else if (ix_instruction.has_dest && !wb_rollback_en)
            begin
                // This is a normal, non-rolled-back instruction
                writeback_en_nxt = 1;
            end

            writeback_thread_idx_nxt = ix_thread_idx;
            writeback_mask_nxt = ix_mask_value;
            if (ix_instruction.call)
                writeback_value_nxt = vector_t'(ix_instruction.pc + 32'd4);
            else if (ix_instruction.compare)
                writeback_value_nxt = vector_t'(scycle_vcompare_result);
            else
                writeback_value_nxt = ix_result;

            writeback_vector_nxt = ix_instruction.dest_vector;
            writeback_reg_nxt = ix_instruction.dest_reg;
            writeback_last_subcycle_nxt = last_subcycle_ix;
        end
        else if (dd_instruction_valid)
        begin
            //
            // Memory pipeline result
            //
            writeback_en_nxt = dd_instruction.has_dest && !wb_rollback_en;
            writeback_thread_idx_nxt = dd_thread_idx;
            if (!dd_instruction.cache_control)
            begin
                if (dd_instruction.load)
                begin
                    unique case (memory_op)
                        MEM_B:      writeback_value_nxt[0] = scalar_t'(byte_aligned);
                        MEM_BX:     writeback_value_nxt[0] = scalar_t'($signed(byte_aligned));
                        MEM_S:      writeback_value_nxt[0] = scalar_t'(half_aligned);
                        MEM_SX:     writeback_value_nxt[0] = scalar_t'($signed(half_aligned));
                        MEM_SYNC:   writeback_value_nxt[0] = swapped_word_value;
                        MEM_L:
                        begin
                            // Scalar Load
                            if (dd_io_access)
                            begin
                                writeback_mask_nxt = {NUM_VECTOR_LANES{1'b1}};
                                writeback_value_nxt[0] = ior_read_value;
                            end
                            else
                            begin
                                writeback_mask_nxt = {NUM_VECTOR_LANES{1'b1}};
                                writeback_value_nxt[0] = swapped_word_value;
                            end
                        end

                        MEM_CONTROL_REG:
                        begin
                            writeback_mask_nxt = {NUM_VECTOR_LANES{1'b1}};
                            writeback_value_nxt[0] = cr_creg_read_val;
                        end

                        MEM_BLOCK,
                        MEM_BLOCK_M:
                        begin
                            writeback_mask_nxt = dd_lane_mask;
                            writeback_value_nxt = endian_twiddled_data;
                        end

                        default:
                        begin
                            // Gather load
                            // Grab the appropriate lane.
                            writeback_mask_nxt = dd_vector_lane_oh & dd_lane_mask;
                            writeback_value_nxt = {NUM_VECTOR_LANES{swapped_word_value}};
                        end
                    endcase
                end
                else if (memory_op == MEM_SYNC)
                begin
                    // Synchronized stores are special because they write
                    // back (whether they were successful).
                    writeback_value_nxt[0] = scalar_t'(sq_store_sync_success);
                end
            end

            writeback_vector_nxt = dd_instruction.dest_vector;
            writeback_reg_nxt = dd_instruction.dest_reg;
            writeback_last_subcycle_nxt = last_subcycle_dd;
        end
    end

    always_ff @(posedge clk)
    begin
        wb_writeback_thread_idx <= writeback_thread_idx_nxt;
        wb_writeback_mask <= writeback_mask_nxt;
        wb_writeback_value <= writeback_value_nxt;
        wb_writeback_vector <= writeback_vector_nxt;
        wb_writeback_reg <= writeback_reg_nxt;
        wb_writeback_last_subcycle <= writeback_last_subcycle_nxt;
    end

    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            wb_writeback_en <= 0;
        else
        begin
            // Don't cause rollback if there isn't an instruction
            assert(!(sq_rollback_en && !dd_instruction_valid));

            // Only one pipeline should attempt to retire an instruction per cycle
            assert($onehot0({ix_instruction_valid, dd_instruction_valid, fx5_instruction_valid}));

            if (dd_instruction_valid && !dd_instruction.cache_control)
            begin
                if (dd_instruction.load)
                begin
                    // Loads should always have a destination register.
                    assert(dd_instruction.has_dest);

                    if (memory_op == MEM_B || memory_op == MEM_BX || memory_op == MEM_S
                        || memory_op == MEM_SX || memory_op == MEM_SYNC || memory_op == MEM_L
                        || memory_op == MEM_CONTROL_REG)
                    begin
                        // Must be scalar destination
                        assert(!dd_instruction.dest_vector);
                    end
                    else
                        assert(dd_instruction.dest_vector);
                end
                else if (memory_op == MEM_SYNC)
                begin
                    // Synchronized stores are special because they write back (whether they
                    // were successful).
                    assert(dd_instruction.has_dest && !dd_instruction.dest_vector);
                end
            end

            wb_writeback_en <= writeback_en_nxt;
            wb_perf_instruction_retire <= (fx5_instruction_valid || ix_instruction_valid
                || dd_instruction_valid) && (!wb_rollback_en
                || (ix_instruction_valid && ix_instruction.branch && !ix_privileged_op_fault));
            wb_perf_store_rollback <= sq_rollback_en;
            wb_perf_interrupt <= ix_instruction_valid && ix_instruction.has_trap
                && ix_instruction.trap_cause.trap_type == TT_INTERRUPT;
        end
    end

`ifdef SIMULATION
    always_ff @(posedge clk)
    begin
        // this will happen if there is a fault and no fault handler has
        // been set in the control register.
        if (wb_trap && wb_rollback_pc == 0)
        begin
            $display("thread %0d caught trap, no handler set, cause %0d address %08x", wb_rollback_thread_idx,
                wb_trap_cause, wb_trap_pc);
            $finish;
        end
    end
`endif
endmodule
