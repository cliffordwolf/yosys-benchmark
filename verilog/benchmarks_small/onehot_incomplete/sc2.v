module sc2 (i1 ,
            i2 ,
            i3 ,
            i4 ,
            i5 ,
            i6 ,
            i7 ,
            i8 ,
            i9 ,
            i10,
            i11,
            i12,
            i13,
            i14,
            i15,
	    binary_out,
            encoder_in,
            enable
);

input [3:0]   i1 ;
input [3:0]   i2 ;
input [3:0]   i3 ;
input [3:0]   i4 ;
input [3:0]   i5 ;
input [3:0]   i6 ;
input [3:0]   i7 ;
input [3:0]   i8 ;
input [3:0]   i9 ;
input [3:0]   i10 ;
input [3:0]   i11 ;
input [3:0]   i12 ;
input [3:0]   i13 ;
input [3:0]   i14 ;
input [3:0]   i15 ;

output reg [3:0] binary_out  ;

input [15:0] encoder_in ;
input  enable ;

always @ (*)
begin
    binary_out = 0;
    if (enable) begin
        case (encoder_in)
            16'h0002 : binary_out = i1;
            16'h0004 : binary_out = i2;
            16'h0008 : binary_out = i3;
            16'h0010 : binary_out = i4;
            16'h0020 : binary_out = i5;
            16'h0040 : binary_out = i6;
            16'h0080 : binary_out = i7;
            16'h0100 : binary_out = i8;
            16'h0200 : binary_out = i9;
            16'h0400 : binary_out = i10;
            16'h0800 : binary_out = i11;
            16'h1000 : binary_out = i12;
            16'h2000 : binary_out = i13;
            16'h4000 : binary_out = i14; /*
            16'h8000 : binary_out = i15;*/
        endcase
    end
end
endmodule
