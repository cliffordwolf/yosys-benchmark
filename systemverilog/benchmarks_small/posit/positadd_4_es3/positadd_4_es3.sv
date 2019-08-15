// Laurens van Dam
// Delft University of Technology
// May 2018
`timescale 1ns / 1ps
`default_nettype wire

import posit_defines_es3::*;

module positadd_4_es3 (clk, in1, in2, start, result, inf, zero, done);

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
    logic [NBITS-2:0] r0_in1_abs, r0_in2_abs;
    logic r0_operation;

    always @(posedge clk)
    begin
        r0_in1 <= (in1 === 'x) ? '0 : in1;
        r0_in2 <= (in2 === 'x) ? '0 : in2;
        r0_start <= (start === 'x) ? '0 : start;
    end

    // Extract posit characteristics, among others the regime & exponent scales
    posit_extract_es3 a_extract (
        .in1(r0_in1),
        .absolute(r0_in1_abs),
        .result(r0_a)
    );

    posit_extract_es3 b_extract (
        .in1(r0_in2),
        .absolute(r0_in2_abs),
        .result(r0_b)
    );

    value r0_low, r0_hi;

    logic r0_a_lt_b; // A larger than B
    assign r0_a_lt_b = r0_in1_abs[NBITS-2:0] >= r0_in2_abs[NBITS-2:0] ? '1 : '0;

    assign r0_operation = r0_a.sgn ~^ r0_b.sgn; // 1 = equal signs = add, 0 = unequal signs = subtract
    assign r0_low = r0_a_lt_b ? r0_b : r0_a;
    assign r0_hi = r0_a_lt_b ? r0_a : r0_b;

    logic unsigned [8:0] r0_scale_diff;
    assign r0_scale_diff = r0_hi.scale - r0_low.scale; // TODO this is dirty


    //  __
    // /_ |
    //  | |
    //  | |
    //  | |
    //  |_|
    logic r1_start;

    value r1_low, r1_hi;
    logic r1_operation;
    logic unsigned [8:0] r1_scale_diff;

    always @(posedge clk)
    begin
        r1_start <= r0_start;

        r1_low <= r0_low;
        r1_hi <= r0_hi;
        r1_operation <= r0_operation;
        r1_scale_diff <= r0_scale_diff;
    end

    // Difference in scales (regime and exponent)
    // Amount the smaller input has to be shifted (everything of the scale difference that the regime cannot cover)

    // Shift smaller magnitude based on scale difference
    logic [2*ABITS-4:0] r1_low_fraction_shifted; // TODO We lose some bits here
    shift_right #(
        .N(2*ABITS-3),
        .S(9)
    ) scale_matching_shift (
        .a({~r1_low.zero, r1_low.fraction, {ABITS{1'b0}}}),
        .b(r1_scale_diff), // Shift to right by scale difference
        .c(r1_low_fraction_shifted)
    );

    logic r1_truncated_after_equalizing;
    assign r1_truncated_after_equalizing = |r1_low_fraction_shifted[ABITS-4:0];

    // Add the fractions
    logic unsigned [ABITS-1:0] r1_fraction_sum_raw, r1_fraction_sum_raw_add, r1_fraction_sum_raw_sub;

    assign r1_fraction_sum_raw_add = {~r1_hi.zero, r1_hi.fraction, {2{1'b0}}} + r1_low_fraction_shifted[2*ABITS-4:ABITS-2];
    assign r1_fraction_sum_raw_sub = {~r1_hi.zero, r1_hi.fraction, {2{1'b0}}} - r1_low_fraction_shifted[2*ABITS-4:ABITS-2];
    assign r1_fraction_sum_raw = r1_operation ? r1_fraction_sum_raw_add : r1_fraction_sum_raw_sub;



    // Result normalization: shift until normalized (and fix the sign)
    // Find the hidden bit (leading zero counter)
    logic [4:0] r1_hidden_pos;
    logic signed [8:0] r1_scale_sum;
    LOD_N #(
        .N(32)
    ) hidden_bit_counter(
        .in({r1_fraction_sum_raw[ABITS-1:0], 2'b0}),
        .out(r1_hidden_pos)
    );

    assign r1_scale_sum = r1_fraction_sum_raw[ABITS-1] ? (r1_hi.scale + 1) : (~r1_fraction_sum_raw[ABITS-2] ? (r1_hi.scale - r1_hidden_pos + 1) : r1_hi.scale);



    //  ___
    // |__ \
    //    ) |
    //   / /
    //  / /_
    // |____|
    logic r2_start;
    value r2_hi, r2_low;

    value_sum r2_sum;
    logic unsigned [ABITS-1:0] r2_fraction_sum_raw;
    logic r2_truncated_after_equalizing, r2_out_rounded_zero;
    logic [4:0] r2_shift_amount_hiddenbit_out, r2_hidden_pos;
    logic signed [8:0] r2_scale_sum;
    logic r2_operation;

    always @(posedge clk)
    begin
        r2_start <= r1_start;
        r2_hi <= r1_hi;
        r2_low <= r1_low;
        r2_fraction_sum_raw <= r1_fraction_sum_raw;
        r2_truncated_after_equalizing <= r1_truncated_after_equalizing;
        r2_hidden_pos <= r1_hidden_pos;
        r2_scale_sum <= r1_scale_sum;
        r2_operation <= r1_operation;
    end

    logic [6:0] r2_regime_shift_amount;
    assign r2_regime_shift_amount = (r2_scale_sum[8] == 0) ? 1 + (r2_scale_sum >> ES) : -(r2_scale_sum >> ES);

    assign r2_sum.sgn = r2_hi.sgn;
    assign r2_sum.scale = r2_scale_sum;
    assign r2_sum.zero = (r2_operation == 1'b0 && r2_hi.scale == r2_low.scale && r2_hi.fraction == r2_low.fraction) ? '1 : (r2_hi.zero & r2_low.zero);
    assign r2_sum.inf = r2_hi.inf | r2_low.inf;

    assign r2_shift_amount_hiddenbit_out = r2_hidden_pos + 1;

    assign r2_out_rounded_zero = (r2_hidden_pos >= ABITS); // The hidden bit is shifted out of range, our sum becomes 0 (when truncated)

    // Normalize the sum output (shift left)
    logic [ABITS-1:0] r2_fraction_sum_normalized;
    shift_left #(
        .N(ABITS-0),
        .S(5)
    ) ls (
        .a(r2_fraction_sum_raw[ABITS-1:0]),
        .b(r2_shift_amount_hiddenbit_out),
        .c(r2_fraction_sum_normalized)
    );

    // STICKY BIT CALCULATION (all the bits from [msb, lsb], that is, msb is included)
    logic [ABITS-1:0] r2_fraction_leftover;
    logic [5:0] r2_leftover_shift;
    assign r2_leftover_shift = NBITS - ES - 2 - r2_regime_shift_amount;

    // Determine all fraction bits that are truncated in the final result
    shift_left #(
        .N(ABITS-0),
        .S(6)
    ) fraction_leftover_shift (
        .a(r2_fraction_sum_normalized), // exponent + fraction bits
        .b(r2_leftover_shift), // Shift to right by regime value (clip at maximum number of bits)
        .c(r2_fraction_leftover)
    );

    logic [ES-1:0] r2_result_exponent;
    assign r2_result_exponent = r2_scale_sum % (2 << ES);


    //  ____
    // |___ \
    //   __) |
    //  |__ <
    //  ___) |
    // |____/
    logic r3_start;

    value_sum r3_sum;
    logic [2*NBITS-1:0] r3_regime_exp_fraction;
    logic [6:0] r3_regime_shift_amount;
    logic r3_bafter, r3_sticky_bit, r3_out_rounded_zero;
    logic [ABITS-1:0] r3_fraction_leftover, r3_fraction_sum_normalized;
    logic r3_truncated_after_equalizing;
    logic [ES-1:0] r3_result_exponent;

    always @(posedge clk)
    begin
        r3_start <= r2_start;

        r3_sum <= r2_sum;
        r3_regime_shift_amount <= r2_regime_shift_amount;
        r3_out_rounded_zero <= r2_out_rounded_zero;

        r3_truncated_after_equalizing <= r2_truncated_after_equalizing;
        r3_fraction_leftover <= r2_fraction_leftover;
        r3_fraction_sum_normalized <= r2_fraction_sum_normalized;
        r3_result_exponent <= r2_result_exponent;
    end

    assign r3_sticky_bit = r3_truncated_after_equalizing | |r3_fraction_leftover[ABITS-2:0]; // Logical OR of all truncated fraction multiplication bits
    assign r3_bafter = r3_fraction_leftover[ABITS-1];

    logic [27:0] r3_fraction_truncated;
    assign r3_fraction_truncated = {r3_fraction_sum_normalized[ABITS-1:3], (r3_fraction_sum_normalized[2] | r3_sticky_bit)};

    assign r3_regime_exp_fraction = { {NBITS-1{~r3_sum.scale[8]}}, // Regime leading bits
                            r3_sum.scale[8], // Regime terminating bit
                            r3_result_exponent, // Exponent
                            r3_fraction_truncated[27:0] }; // Fraction


    logic [2*NBITS-1:0] r3_exp_fraction_shifted_for_regime;
    shift_right #(
        .N(2*NBITS),
        .S(7)
    ) shift_in_regime (
        .a(r3_regime_exp_fraction), // exponent + fraction bits
        .b(r3_regime_shift_amount), // Shift to right by regime value (clip at maximum number of bits)
        .c(r3_exp_fraction_shifted_for_regime)
    );

    // TODO Inward projection?
    // Determine result (without sign), the unsigned regime+exp+fraction
    logic [NBITS-2:0] r3_result_no_sign;
    assign r3_result_no_sign = r3_exp_fraction_shifted_for_regime[NBITS-1:1];

    // Perform rounding (based on sticky bit)
    logic r3_blast, r3_tie_to_even, r3_round_nearest;
    logic [NBITS-2:0] r3_result_no_sign_rounded;

    assign r3_blast = r3_result_no_sign[0];
    assign r3_tie_to_even = r3_blast & r3_bafter; // Value 1.5 -> round to 2 (even)
    assign r3_round_nearest = r3_bafter & r3_sticky_bit; // Value > 0.5: round to nearest

    assign r3_result_no_sign_rounded = (r3_tie_to_even | r3_round_nearest) ? (r3_result_no_sign + 1) : r3_result_no_sign;

    // In case the product is negative, take 2's complement of everything but the sign
    logic [NBITS-2:0] r3_signed_result_no_sign;
    assign r3_signed_result_no_sign = r3_sum.sgn ? -r3_result_no_sign_rounded[NBITS-2:0] : r3_result_no_sign_rounded[NBITS-2:0];

    // Final output
    assign result = (r3_out_rounded_zero | r3_sum.zero | r3_sum.inf) ? {r3_sum.inf, {NBITS-1{1'b0}}} : {r3_sum.sgn, r3_signed_result_no_sign[NBITS-2:0]};
    assign inf = r3_sum.inf;
    assign zero = ~r3_sum.inf & r3_sum.zero;
    assign done = r3_start;

endmodule
