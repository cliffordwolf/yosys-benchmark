

def rtl_muladd(name, AW, BW, CW, AREG, BREG, CREG, MREG, PREG, Asigned, Bsigned, Csigned, CEA, CEB, CEC, CEM, CEP):
    return """(* top *)
module {name} #(parameter AW={AW}, BW={BW}, CW={CW}, AREG={AREG}, BREG={BREG}, CREG={CREG}, MREG={MREG}, PREG={PREG}) (input clk, CEA, CEB, CEC, CEM, CEP, input {Asigned}[AW-1:0] A, input {Bsigned}[BW-1:0] B, input {Csigned}[CW-1:0] C, output reg {Msigned}[CW-1:0] P);
reg {Asigned}[AW-1:0] Ar;
reg {Bsigned}[BW-1:0] Br;
reg {Csigned}[CW-1:0] Cr;
reg {Msigned}[CW-1:0] Mr;
generate
    if (AREG) begin
        always @(posedge clk) if ({CEA}) Ar <= A;
    end
    else
        always @* Ar <= A;
    if (BREG) begin
        always @(posedge clk) if ({CEB}) Br <= B;
    end
    else
        always @* Br <= B;
    if (CREG) begin
        always @(posedge clk) if ({CEC}) Cr <= C;
    end
    else
        always @* Cr <= C;
    if (MREG) begin
        always @(posedge clk) if ({CEM}) Mr <= Ar * Br;
    end
    else
        always @* Mr <= Ar * Br;
    if (PREG) begin
        always @(posedge clk) if ({CEP}) P <= Cr + Mr;
    end
    else
        always @* P <= Cr + Mr;
endgenerate
endmodule""".format(name=name, AW=AW, BW=BW, CW=CW,
                    AREG='1' if AREG else '0', BREG='1' if BREG else '0', CREG='1' if CREG else '0',  MREG='1' if MREG else '0', PREG='1' if PREG else '0',
                    Asigned='signed ' if Asigned else '', Bsigned='signed ' if Bsigned else '', Csigned='signed ' if Csigned else '', Msigned='signed ' if Asigned and Bsigned and Csigned else '',
                    CEA='CEA' if CEA else '1', CEB='CEB' if CEB else '1', CEC='CEC' if CEC else '1', CEM='CEM' if CEM else '1', CEP='CEP' if CEP else '1')

# https://stackoverflow.com/a/1482316
from itertools import chain, combinations
def powerset(iterable):
    "powerset([1,2,3]) --> () (1,) (2,) (3,) (1,2) (1,3) (2,3) (1,2,3)"
    s = list(iterable)
    return chain.from_iterable(combinations(s, r) for r in range(len(s)+1))

def gen_muladd(aRange, bRange, cRange, reg="ABCP"):
    for A in aRange:
        for B in bRange:
            for C in cRange:
                for R in map(lambda i:''.join(i), powerset(reg)): # Register existence
                    for E in map(lambda i:''.join(i), powerset(R)): # Enable
                        with open("muladd_%s_%s_%s_%s_%s.v" % (A,B,C,R,E), "w") as f:
                            print(rtl_muladd('muladd_%s_%s_%s_%s_%s' % (A,B,C,R,E),               # name
                                             A.rstrip('s'), B.rstrip('s'), C.rstrip('s'),      # [ABC]W
                                             'A' in R, 'B' in R, 'C' in R, 'M' in R, 'P' in R, # [ABCMP]REG
                                             's' in A, 's' in B, 's' in C,                     # [ABC]_signed
                                             'A' in E, 'B' in E, 'C' in E, 'M' in E, 'P' in E, # CE[ABCMP]
                                             ), file=f)
