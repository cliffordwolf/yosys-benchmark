

def rtl_macc(name, AW, BW, AREG, BREG, MREG, Asigned, Bsigned, CEA, CEB, CEM, CEP):
    return """(* top *)
module {0} #(parameter AW={1}, BW={2}, AREG={3}, BREG={4}, MREG={5}) (input clk, CEA, CEB, CEM, CEP, input {6}[AW-1:0] A, input {7}[BW-1:0] B, output reg {8}[{9}-1:0] P);
reg {6}[AW-1:0] Ar;
reg {7}[BW-1:0] Br;
reg {8}[AW+BW-1:0] Mr;
generate
    if (AREG) begin
        always @(posedge clk) if ({10}) Ar <= A;
    end
    else
        always @* Ar <= A;
    if (BREG) begin
        always @(posedge clk) if ({11}) Br <= B;
    end
    else
        always @* Br <= B;
    if (MREG) begin
        always @(posedge clk) if ({12}) Mr <= Ar * Br;
    end
    else
        always @* Mr <= Ar * Br;
    always @(posedge clk) if ({13}) P <= P + Mr;
endgenerate
endmodule""".format(name, AW, BW, 
                    '1' if AREG else '0', '1' if BREG else '0', '1' if MREG else '0',
                    'signed ' if Asigned else '', 'signed ' if Bsigned else '', 'signed ' if Asigned and Bsigned else '',
                    int(AW)+int(BW)+5,
                    'CEA' if CEA else '1', 'CEB' if CEB else '1', 'CEM' if CEM else '1', 'CEP' if CEP else '1')

# https://stackoverflow.com/a/1482316
from itertools import chain, combinations
def powerset(iterable):
    "powerset([1,2,3]) --> () (1,) (2,) (3,) (1,2) (1,3) (2,3) (1,2,3)"
    s = list(iterable)
    return chain.from_iterable(combinations(s, r) for r in range(len(s)+1))

def gen_macc(aRange, bRange, reg="AB"):
    for A in aRange:
        for B in bRange:
            for R in map(lambda i:''.join(i), powerset(reg.replace('P',''))): # Register existence
                for E in map(lambda i:''.join(i), powerset(R + 'P' if 'P' in reg else '')): # Enable
                    with open("macc_%s_%s_%s_%s.v" % (A,B,R,E), "w") as f:
                        print(rtl_macc('macc_%s_%s_%s_%s' % (A,B,R,E),          # name
                                      A.rstrip('s'), B.rstrip('s'),             # [AB]W
                                      'A' in R, 'B' in R, 'M' in R,             # [ABM]REG
                                      's' in A, 's' in B,                       # [AB]_signed
                                      'A' in E, 'B' in E, 'M' in E, 'P' in E,   # CE[ABMP]
                                      ), file=f)
                    if A != B:
                        with open("macc_%s_%s_%s_%s.v" % (B,A,R,E), "w") as f:
                            print(rtl_macc('macc_%s_%s_%s_%s' % (B,A,R,E),          # name
                                          B.rstrip('s'), A.rstrip('s'),             # [AB]W
                                          'B' in R, 'A' in R, 'M' in R,             # [ABM]REG
                                          's' in B, 's' in A,                       # [AB]_signed
                                          'B' in E, 'A' in E, 'M' in E, 'P' in E,   # CE[ABMP]
                                          ), file=f)
