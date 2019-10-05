// Laurens van Dam
// Delft University of Technology
// May 2018

`timescale 1ns / 1ps
`default_nettype wire

//`include "posit_defines_es3.sv"
import posit_defines_es3::*;

module positmult_4_es3 (clk, in1, in2, start, result, inf, zero, done);

    input wire clk, start;
    input wire [31:0] in1, in2;
    output wire [31:0] result;
    output wire inf, zero, done;


    //   ___
    //  / _ \
    // | | | |
    // | | | |
    // | |_| |
    //  \___/
    logic [31:0] r0_in1, r0_in2;
    logic r0_start;

    value r0_a, r0_b;

    always @(posedge clk)
    begin
        r0_in1 <= (in1 === 'x) ? '0 : in1;
        r0_in2 <= (in2 === 'x) ? '0 : in2;
        r0_start <= (start === 'x) ? '0 : start;
    end

    // Extract posit characteristics, among others the regime & exponent scales
    posit_extract_es3 a_extract (
        .in1(r0_in1),
        .absolute(),
        .result(r0_a)
    );

    posit_extract_es3 b_extract (
        .in1(r0_in2),
        .absolute(),
        .result(r0_b)
    );


    //  __
    // /_ |
    //  | |
    //  | |
    //  | |
    //  |_|
    logic r1_start;

    value r1_a, r1_b;
    value_product r1_product;

    always @(posedge clk)
    begin
        r1_start <= r0_start;

        r1_a <= r0_a;
        r1_b <= r0_b;
    end

    logic [MBITS-1:0] r1_fraction_mult, r1_result_fraction;

    logic [FHBITS-1:0] r1_r1, r1_r2;
    assign r1_r1 = {1'b1, r1_a.fraction}; // Add back hidden bit (fraction is without hidden bit)
    assign r1_r2 = {1'b1, r1_b.fraction}; // Add back hidden bit (fraction is without hidden bit)
    assign r1_fraction_mult = r1_r1 * r1_r2; // Unsigned multiplication of fractions

    // Check if the radix point needs to shift
    assign r1_product.scale   = r1_fraction_mult[MBITS-1] ? (r1_a.scale + r1_b.scale + 1) : (r1_a.scale + r1_b.scale);
    assign r1_result_fraction = r1_fraction_mult[MBITS-1] ? (r1_fraction_mult << 1) : (r1_fraction_mult << 2); // Shift hidden bit out

    assign r1_product.fraction = r1_result_fraction[MBITS-1:0];
    assign r1_product.sgn = r1_a.sgn ^ r1_b.sgn;
    assign r1_product.zero = r1_a.zero | r1_b.zero;
    assign r1_product.inf = r1_a.inf | r1_b.inf;


    //  ___
    // |__ \
    //    ) |
    //   / /
    //  / /_
    // |____|
    logic r2_start;
    value_product r2_product;

    always @(posedge clk)
    begin
        r2_start <= r1_start;
        r2_product <= r1_product;
    end

    logic [ES-1:0] r2_result_exponent;
    assign r2_result_exponent = r2_product.scale % (2 << ES);

    logic [6:0] r2_regime_shift_amount;
    // Positive scale -> Should shift with 1's with 1 extra (specification)
    // Negative scale -> Make value positive
    assign r2_regime_shift_amount = (r2_product.scale[9] == 0) ? 1 + (r2_product.scale >> ES) : -(r2_product.scale >> ES);

    // STICKY BIT CALCULATION (all the bits from [msb, lsb], that is, msb is included)
    logic [MBITS-1:0] r2_fraction_leftover;
    logic [4:0] r2_leftover_shift;
    assign r2_leftover_shift = NBITS - ES - 2 - r2_regime_shift_amount;
    // Determine all fraction bits that are truncated in the final result
    shift_left #(
        .N(MBITS),
        .S(5)
    ) fraction_leftover_shift (
        .a(r2_product.fraction), // exponent + fraction bits
        .b(r2_leftover_shift), // Shift to right by regime value (clip at maximum number of bits)
        .c(r2_fraction_leftover)
    );
    logic r2_sticky_bit;
    assign r2_sticky_bit = |r2_fraction_leftover[MBITS-2:0]; // Logical OR of all truncated fraction multiplication bits

    logic r2_bafter;
    assign r2_bafter = r2_fraction_leftover[MBITS-1];
    // END STICKY BIT CALCULATION

    logic [27:0] r2_fraction_truncated;
    assign r2_fraction_truncated = {r2_product.fraction[MBITS-1:MBITS-NBITS+5], (r2_product.fraction[MBITS-NBITS+4] | r2_sticky_bit)};

    logic [2*NBITS-1:0] r2_regime_exp_fraction;
    assign r2_regime_exp_fraction = { {NBITS{~r2_product.scale[9]}}, // Regime leading bits
                            r2_product.scale[9], // Regime terminating bit
                            r2_result_exponent, // Exponent
                            r2_fraction_truncated[27:0]}; // Fraction


    //  ____
    // |___ \
    //   __) |
    //  |__ <
    //  ___) |
    // |____/
    logic r3_start;
    value_product r3_product;
    logic [6:0] r3_regime_shift_amount;
    logic [2*NBITS-1:0] r3_regime_exp_fraction;
    logic r3_bafter, r3_sticky_bit;

    always @(posedge clk)
    begin
        r3_start <= r2_start;

        r3_product <= r2_product;
        r3_regime_exp_fraction <= r2_regime_exp_fraction;
        r3_regime_shift_amount <= r2_regime_shift_amount;
        r3_bafter <= r2_bafter;
        r3_sticky_bit <= r2_sticky_bit;
    end

    logic [2*NBITS-1:0] r3_exp_fraction_shifted_for_regime;
    shift_right #(
        .N(2*NBITS),
        .S(7)
    ) dsr2 (
        .a(r3_regime_exp_fraction), // exponent + fraction bits
        .b(r3_regime_shift_amount), // Shift to right by regime value (clip at maximum number of bits)
        .c(r3_exp_fraction_shifted_for_regime)
    );

    logic [NBITS-2:0] r3_result_no_sign;

    // Calculate the max k factor for this posit config
	logic signed [8:0] r3_max_k;
	assign r3_max_k = r3_product.scale[9] ? -240 : 240;
    // Determine if we have inward projection (which means the regime dominated)
    logic r3_inward_projection;
    assign r3_inward_projection = r3_product.scale[9] ? (r3_product.scale < r3_max_k) : (r3_product.scale > r3_max_k);

    // In case of inward projection, determine the regime
    logic [7:0] r3_inward_projection_k1;
    logic r3_inward_projection_k2;
    assign r3_inward_projection_k1 = r3_product.scale[9] ? -(-r3_product.scale >> ES) : (r3_product.scale >> ES);
    assign r3_inward_projection_k2 = (~|r3_inward_projection_k1 & r3_product.scale[9]) ? 1 : r3_inward_projection_k1[7];

    // Determine result (without sign), either a full regime part (inward projection) or the unsigned regime+exp+fraction
    assign r3_result_no_sign = r3_inward_projection ? (r3_inward_projection_k2 ? {{NBITS-2{1'b0}}, 1'b1} : {NBITS-1{1'b1}}) : r3_exp_fraction_shifted_for_regime[NBITS-1:1];

    // Perform rounding (based on sticky bit)
    logic r3_blast, r3_tie_to_even, r3_round_nearest;
    logic [NBITS-2:0] r3_result_no_sign_rounded;

    assign r3_blast = r3_result_no_sign[0];
    assign r3_tie_to_even = r3_blast & r3_bafter; // Value 1.5 -> round to 2 (even)
    assign r3_round_nearest = r3_bafter & r3_sticky_bit; // Value > 0.5: round to nearest

    assign r3_result_no_sign_rounded = (r3_tie_to_even | r3_round_nearest) ? (r3_result_no_sign + 1) : r3_result_no_sign;

    // In case the product is negative, take 2's complement of everything but the sign
    logic [NBITS-2:0] r3_signed_result_no_sign;
    assign r3_signed_result_no_sign = r3_product.sgn ? -r3_result_no_sign_rounded[NBITS-2:0] : r3_result_no_sign_rounded[NBITS-2:0];

    // Final output
    assign result = (r3_product.zero | r3_product.inf) ? {r3_product.inf, {NBITS-1{1'b0}}} : {r3_product.sgn, r3_signed_result_no_sign[NBITS-2:0]};
    assign inf = r3_product.inf;
    assign zero = ~r3_product.inf & r3_product.zero;
    assign done = r3_start;

endmodule
