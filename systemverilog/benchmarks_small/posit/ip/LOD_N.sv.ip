// Leading-One-Detector with configurable number of bits
module LOD_N (in, out);
    function [31:0] log2;
        input reg [31:0] value;
        begin
            value = value - 1;
            for (log2 = 0; value > 0; log2 = log2 + 1)
            begin
                value = value >> 1;
            end
        end
    endfunction

    parameter N = 64;
    parameter S = log2(N);

    input [N-1:0] in;
    output [S-1:0] out;
    logic vld;

    LOD #(.N(N)) l1 (
        .in(in),
        .out(out),
        .vld(vld)
    );
endmodule

// Leading-One-Detector
module LOD (in, out, vld);
    function [31:0] log2;
        input reg [31:0] value;
        begin
            value = value - 1;

            for (log2 = 0; value > 0; log2 = log2 + 1)
            begin
                value = value >> 1;
            end
        end
    endfunction


    parameter N = 64;
    parameter S = log2(N);

    input [N-1:0] in;
    output [S-1:0] out;
    output vld;

    /* verilator lint_off WIDTH */
    generate
        if (N == 2)
        begin
            assign vld = |in;
            assign out = ~in[1] & in[0];
        end
        else if (N & (N - 1))
        begin
            LOD #(1 << S) LOD (
                {1 << S {1'b0}} | in,
                out,
                vld
            );
        end
        else
        begin
            wire [S-2:0] out_l, out_h;
            wire out_vl, out_vh;

            LOD #(N >> 1) l (
                in[(N >> 1) - 1:0],
                out_l,
                out_vl
            );

            LOD #(N >> 1) h (
                in[N - 1:N >> 1],
                out_h,
                out_vh
            );

            assign vld = out_vl | out_vh;
            assign out = out_vh ? {1'b0, out_h} : {out_vl, out_l};
        end
    endgenerate
    /* verilator lint_on WIDTH */
endmodule
