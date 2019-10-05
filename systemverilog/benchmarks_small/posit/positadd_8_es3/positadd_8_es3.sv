// Laurens van Dam
// Delft University of Technology
// May 2018

`timescale 1ns / 1ps
`default_nettype wire

//`include "posit_defines_es3.sv"
import posit_defines_es3::*;

module positadd_8_es3 (clk, in1, in2, start, result, inf, zero, done);

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


    //  __
    // /_ |
    //  | |
    //  | |
    //  | |
    //  |_|
    logic r1_start;

    value r1_low, r1_hi;

    logic r1_operation;

    always @(posedge clk)
    begin
        r1_start <= r0_start;

        r1_low <= r0_low;
        r1_hi <= r0_hi;
        r1_operation <= r0_operation;
    end

    // Difference in scales (regime and exponent)
    // Amount the smaller input has to be shifted (everything of the scale difference that the regime cannot cover)
    logic unsigned [8:0] r1_scale_diff;
    assign r1_scale_diff = r1_hi.scale - r1_low.scale; // TODO this is dirty

    // Shift smaller magnitude based on scale difference
    logic [2*ABITS-1:0] r1_low_fraction_shifted; // TODO We lose some bits here
    shift_right #(
        .N(2*ABITS),
        .S(9)
    ) scale_matching_shift (
        .a({~r1_low.zero, r1_low.fraction, {ABITS+3{1'b0}}}),
        .b(r1_scale_diff), // Shift to right by scale difference
        .c(r1_low_fraction_shifted)
    );

    logic r1_truncated_after_equalizing;
    assign r1_truncated_after_equalizing = |r1_low_fraction_shifted[ABITS-1:0];

    // Add the fractions
    logic unsigned [ABITS:0] r1_fraction_sum_raw, r1_fraction_sum_raw_add, r1_fraction_sum_raw_sub;

    assign r1_fraction_sum_raw_add = {~r1_hi.zero, r1_hi.fraction, {3{1'b0}}} + r1_low_fraction_shifted[2*ABITS-1:ABITS];
    assign r1_fraction_sum_raw_sub = {~r1_hi.zero, r1_hi.fraction, {3{1'b0}}} - r1_low_fraction_shifted[2*ABITS-1:ABITS];
    assign r1_fraction_sum_raw = r1_operation ? r1_fraction_sum_raw_add : r1_fraction_sum_raw_sub;


    //  __   ____
    // /_ | |  _ \
    //  | | | |_) |
    //  | | |  _ <
    //  | | | |_) |
    //  |_| |____/
    logic r1b_start;

    value r1b_low, r1b_hi;
    value_sum r1b_sum;
    logic unsigned [ABITS:0] r1b_fraction_sum_raw;
    logic r1b_truncated_after_equalizing;

    always @(posedge clk)
    begin
        r1b_start <= r1_start;

        r1b_low <= r1_low;
        r1b_hi <= r1_hi;
        r1b_fraction_sum_raw <= r1_fraction_sum_raw;
        r1b_truncated_after_equalizing <= r1_truncated_after_equalizing;
    end

    logic r1b_operation;
    assign r1b_operation = r1b_low.sgn ~^ r1b_hi.sgn;

    // Result normalization: shift until normalized (and fix the sign)
    // Find the hidden bit (leading zero counter)
    logic [4:0] r1b_hidden_pos;
    LOD_N #(
        .N(32)
    ) hidden_bit_counter(
        .in({r1b_fraction_sum_raw[ABITS:0], 1'b0}),
        .out(r1b_hidden_pos)
    );

    logic signed [8:0] r1b_scale_sum;
    assign r1b_scale_sum = r1b_fraction_sum_raw[ABITS] ? (r1b_hi.scale + 1) : (~r1b_fraction_sum_raw[ABITS-1] ? (r1b_hi.scale - r1b_hidden_pos + 1) : r1b_hi.scale);

    assign r1b_sum.sgn = r1b_hi.sgn;
    assign r1b_sum.scale = r1b_scale_sum;
    assign r1b_sum.zero = (r1b_operation == 1'b0 && r1b_hi.scale == r1b_low.scale && r1b_hi.fraction == r1b_low.fraction) ? '1 : (r1b_hi.zero & r1b_low.zero);
    assign r1b_sum.inf = r1b_hi.inf | r1b_low.inf;

    logic [4:0] r1b_shift_amount_hiddenbit_out;
    assign r1b_shift_amount_hiddenbit_out = r1b_hidden_pos + 1;

    logic r1b_out_rounded_zero;
    assign r1b_out_rounded_zero = (r1b_hidden_pos >= ABITS); // The hidden bit is shifted out of range, our sum becomes 0 (when truncated)


    //  ___
    // |__ \
    //    ) |
    //   / /
    //  / /_
    // |____|
    logic r2_start;

    value_sum r2_sum;
    logic unsigned [ABITS:0] r2_fraction_sum_raw;
    logic r2_truncated_after_equalizing, r2_out_rounded_zero;
    logic [4:0] r2_shift_amount_hiddenbit_out;

    always @(posedge clk)
    begin
        r2_start <= r1b_start;

        r2_sum <= r1b_sum;
        r2_fraction_sum_raw <= r1b_fraction_sum_raw;
        r2_shift_amount_hiddenbit_out <= r1b_shift_amount_hiddenbit_out;
        r2_truncated_after_equalizing <= r1b_truncated_after_equalizing;
        r2_out_rounded_zero <= r1b_out_rounded_zero;
    end

    // Normalize the sum output (shift left)
    logic [ABITS:0] r2_fraction_sum_normalized;
    shift_left #(
        .N(ABITS+1),
        .S(5)
    ) ls (
        .a(r2_fraction_sum_raw[ABITS:0]),
        .b(r2_shift_amount_hiddenbit_out),
        .c(r2_fraction_sum_normalized)
    );

    // PACK INTO POSIT
    logic [ES-1:0] r2_result_exponent;
    assign r2_result_exponent = r2_sum.scale % (2 << ES);

    logic [6:0] r2_regime_shift_amount;
    assign r2_regime_shift_amount = (r2_sum.scale[8] == 0) ? 1 + (r2_sum.scale >> ES) : -(r2_sum.scale >> ES);

    // STICKY BIT CALCULATION (all the bits from [msb, lsb], that is, msb is included)
    logic [5:0] r2_leftover_shift;
    assign r2_leftover_shift = NBITS - ES - 2 - r2_regime_shift_amount;


    //  ___    ____
    // |__ \  |  _ \
    //    ) | | |_) |
    //   / /  |  _ <
    //  / /_  | |_) |
    // |____| |____/
    logic r2b_start;

    value_sum r2b_sum;
    logic r2b_truncated_after_equalizing, r2b_out_rounded_zero;

    logic [5:0] r2b_leftover_shift;
    logic [ABITS:0] r2b_fraction_leftover, r2b_fraction_sum_normalized;
    logic [ES-1:0] r2b_result_exponent;
    logic [6:0] r2b_regime_shift_amount;

    always @(posedge clk)
    begin
        r2b_start <= r2_start;

        r2b_sum <= r2_sum;
        r2b_truncated_after_equalizing <= r2_truncated_after_equalizing;
        r2b_out_rounded_zero <= r2_out_rounded_zero;
        r2b_fraction_sum_normalized <= r2_fraction_sum_normalized;
        r2b_leftover_shift <= r2_leftover_shift;
        r2b_result_exponent <= r2_result_exponent;
        r2b_regime_shift_amount <= r2_regime_shift_amount;
    end

    // Determine all fraction bits that are truncated in the final result
    shift_left #(
        .N(ABITS+1),
        .S(6)
    ) fraction_leftover_shift (
        .a(r2b_fraction_sum_normalized), // exponent + fraction bits
        .b(r2b_leftover_shift), // Shift to right by regime value (clip at maximum number of bits)
        .c(r2b_fraction_leftover)
    );

    logic r2b_sticky_bit;
    assign r2b_sticky_bit = r2b_truncated_after_equalizing | |r2b_fraction_leftover[ABITS-1:0]; // Logical OR of all truncated fraction multiplication bits

    logic r2b_bafter;
    assign r2b_bafter = r2b_fraction_leftover[ABITS];
    // END STICKY BIT CALCULATION

    logic [27:0] r2b_fraction_truncated;
    assign r2b_fraction_truncated = {r2b_fraction_sum_normalized[ABITS:4], (r2b_fraction_sum_normalized[3] | r2b_sticky_bit)};

    logic [2*NBITS-1:0] r2b_regime_exp_fraction;
    assign r2b_regime_exp_fraction = { {NBITS-1{~r2b_sum.scale[8]}}, // Regime leading bits
                            r2b_sum.scale[8], // Regime terminating bit
                            r2b_result_exponent, // Exponent
                            r2b_fraction_truncated[27:0] }; // Fraction


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

    always @(posedge clk)
    begin
        r3_start <= r2b_start;

        r3_sum <= r2b_sum;
        r3_regime_exp_fraction <= r2b_regime_exp_fraction;
        r3_regime_shift_amount <= r2b_regime_shift_amount;
        r3_bafter <= r2b_bafter;
        r3_sticky_bit <= r2b_sticky_bit;
        r3_out_rounded_zero <= r2b_out_rounded_zero;
    end

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


    //  ____    ____
    // |___ \  |  _ \
    //   __) | | |_) |
    //  |__ <  |  _ <
    //  ___) | | |_) |
    // |____/  |____/
    logic r3b_start;

    value_sum r3b_sum;
    logic [NBITS-2:0] r3b_result_no_sign;
    logic r3b_bafter, r3b_sticky_bit, r3b_out_rounded_zero;

    always @(posedge clk)
    begin
        r3b_start <= r3_start;

        r3b_sum <= r3_sum;
        r3b_result_no_sign <= r3_result_no_sign;
        r3b_sticky_bit <= r3_sticky_bit;
        r3b_out_rounded_zero <= r3_out_rounded_zero;
        r3b_bafter <= r3_bafter;
    end

    // Perform rounding (based on sticky bit)
    logic r3b_blast, r3b_tie_to_even, r3b_round_nearest;
    logic [NBITS-2:0] r3b_result_no_sign_rounded;

    assign r3b_blast = r3b_result_no_sign[0];
    assign r3b_tie_to_even = r3b_blast & r3b_bafter; // Value 1.5 -> round to 2 (even)
    assign r3b_round_nearest = r3b_bafter & r3b_sticky_bit; // Value > 0.5: round to nearest

    assign r3b_result_no_sign_rounded = (r3b_tie_to_even | r3b_round_nearest) ? (r3b_result_no_sign + 1) : r3b_result_no_sign;

    // In case the product is negative, take 2's complement of everything but the sign
    logic [NBITS-2:0] r3b_signed_result_no_sign;
    assign r3b_signed_result_no_sign = r3b_sum.sgn ? -r3b_result_no_sign_rounded[NBITS-2:0] : r3b_result_no_sign_rounded[NBITS-2:0];


    //   ___     ___
    //  / _ \   / _ \
    // | (_) | | (_) |
    //  \__, |  \__, |
    //    / /     / /
    //   /_/     /_/
    logic r99_start;

    value_sum r99_sum;
    logic r99_out_rounded_zero;
    logic [NBITS-2:0] r99_signed_result_no_sign;

    always @(posedge clk)
    begin
        r99_start <= r3b_start;

        r99_out_rounded_zero <= r3b_out_rounded_zero;
        r99_sum <= r3b_sum;
        r99_signed_result_no_sign <= r3b_signed_result_no_sign;
    end

    // Final output
    assign result = (r99_out_rounded_zero | r99_sum.zero | r99_sum.inf) ? {r99_sum.inf, {NBITS-1{1'b0}}} : {r99_sum.sgn, r99_signed_result_no_sign[NBITS-2:0]};
    assign inf = r99_sum.inf;
    assign zero = ~r99_sum.inf & r99_sum.zero;
    assign done = r99_start;

endmodule
