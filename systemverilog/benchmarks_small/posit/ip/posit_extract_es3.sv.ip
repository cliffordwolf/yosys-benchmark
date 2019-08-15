// Laurens van Dam
// Delft University of Technology
// May 2018

`timescale 1ns / 1ps
`default_nettype wire

// `include "posit_defines_es3.sv"
import posit_defines_es3::*;

module posit_extract_es3 (input wire [NBITS-1:0] in1, output wire [NBITS-2:0] absolute, output value result);
    logic [8:0] regime_scale;
    logic [4:0] regime_u, k0, k1;
    logic [NBITS-1:0] exp_fraction_u;
    logic [4:0] regime_width;
    logic [31:0] in_u;

    // Check if part without sign is non-zero (to determine inf and zero cases)
    logic posit_nonzero_without_sign;
    assign posit_nonzero_without_sign = |in1[NBITS-2:0];

    // Special case handling (inf, zero) for both inputs
    assign result.zero = ~(in1[NBITS-1] | posit_nonzero_without_sign);
    assign result.inf = in1[NBITS-1] & (~posit_nonzero_without_sign);

    assign result.sgn = in1[NBITS-1];

    // Unsigned input (*_u = unsigned)
    assign in_u = result.sgn ? -in1 : in1;

    // Leading-One detection for regime
    LOD_N #(
        .N(NBITS)
    ) xinst_k0(
        .in({in_u[NBITS-2:0], 1'b0}),
        .out(k0)
    );

    // Leading-Zero detection for regime
    LZD_N #(
        .N(NBITS)
    ) xinst_k1(
        .in({in_u[NBITS-3:0], 2'b0}),
        .out(k1)
    );

    // Determine absolute regime value depending on leading 0 or 1 regime bit
    assign regime_u = in_u[NBITS-2] ? k1 : k0;
    // Negative regime? Make the regime scale negative
    assign regime_scale = in_u[NBITS-2] ? (regime_u << ES) : -(regime_u << ES);
    // Number of bits occupied by regime
    assign regime_width = in_u[NBITS-2] ? (k1 + 1) : k0;

    // Shift away the regime resulting in only the exponent and fraction
    shift_left #(
        .N(32),
        .S(5)
    ) ls (
        .a({in_u[NBITS-3:0], 2'b0}),
        .b(regime_width),
        .c(exp_fraction_u)
    );

    assign result.fraction = exp_fraction_u[NBITS-ES-1:3];

    // Scale = k*(2^es) + 2^exp
    assign result.scale = regime_scale + exp_fraction_u[NBITS-1:NBITS-ES];

    assign absolute = in_u[NBITS-2:0];

endmodule
