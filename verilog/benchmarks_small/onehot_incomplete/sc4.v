module sc4 (enable,
    binary_out,
    encoder_in);

output reg [3:0] binary_out;
input [3:0] encoder_in;
input  enable;


//always @ (enable or encoder_in)
always @ (*)
begin
    binary_out = 0;
    if (enable) begin
        case (encoder_in)
            4'h1 : binary_out = 1;
            4'h2 : binary_out = 2;
            4'h3 : binary_out = 3;
            4'h4 : binary_out = 4;
            4'h5 : binary_out = 5;
            4'h6 : binary_out = 6;/*
            4'h7 : binary_out = i7;
            4'h8 : binary_out = i8;
            4'h9 : binary_out = i9;
            4'ha : binary_out = i10;
            4'hb : binary_out = i11;
            4'hc : binary_out = i12;
            4'hd : binary_out = i13;
            4'he : binary_out = i14;
            4'hf : binary_out = i15;*/
            //default: binary_out = 0;
        endcase
    end
end
endmodule
