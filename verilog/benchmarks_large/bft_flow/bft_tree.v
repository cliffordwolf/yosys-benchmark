/* Butterfly Fat Tree NoC enhanced with in-order routing capability supported by lightweight flow control and pruning of switch crossbar.
 * RTL for the entire NoC with a simulation and implementation framework targeting Xilinx FPGAs. FCCM 2019 Artifact.
 * Reference: https://git.uwaterloo.ca/watcag-public/bft-flow
 */

//`define UNIT_TEST_REACHABILITY2
//`define UNIT_TEST_REACHABILITY4
//`define UNIT_TEST_TRIANGLE_T
//`define UNIT_TEST_TRIANGLE_PI
`define LOCAL   1
`define ROOT    0
`define UNIT_TEST_RND
//`define DEBUG
//`define DUMP

// Testbench commands
`define Cmd [5:0]
`define Cmd_IDLE 6'd0
`define Cmd_01   6'd1
`define Cmd_02   6'd2
`define Cmd_03   6'd3
`define Cmd_10   6'd4
`define Cmd_12   6'd5
`define Cmd_13   6'd6
`define Cmd_20   6'd7
`define Cmd_21   6'd8
`define Cmd_23   6'd9
`define Cmd_30   6'd10
`define Cmd_31   6'd11
`define Cmd_32   6'd12
// deflection tests start here
`define Cmd_02_12     6'd13
`define Cmd_01_12     6'd14
`define Cmd_40_70     6'd15
`define Cmd_02_25     6'd16
`define Cmd_swap      6'd17
// randomized stress test
`define Cmd_RND       6'd18

`define RANDOM 0
`define LOCAL 1
`define BITREV 2
`define TORNADO 3
//mux.h
// Mux direction controls
`define NONE    3'b000
`define LEFT    3'b100
`define RIGHT   3'b101
`define U0      3'b110
`define U1      3'b111

// Module defined parameters
`define TREE

module bft_tree #(
	parameter WRAP		= 1,
	parameter N		= 128, //The system size of the NoC. It should be a positive multiple of 2
    parameter D_W=32,
	parameter A_W		= $clog2(N)+1,
	parameter LEVELS	= $clog2(N),
	parameter FD		= 32,
parameter HR=1
) (
	input  wire clk,
	input  wire rst,
	input  wire ce,

	input	wire	[((A_W+D_W+1)*N)-1:0]	peo_p,
	input	wire	[N-1:0]			peo_v_p,
	input	wire	[N-1:0]			peo_l_p,
	output	reg	[N-1:0]			peo_r_p,

	output	reg	[((A_W+D_W+1)*N)-1:0]	pei_p,
	output	reg	[N-1:0]			pei_v_p,
	output	reg	[N-1:0]			pei_l_p,
	input	wire	[N-1:0]			pei_r_p

);

	wire	[A_W+D_W:0]	grid_up		[LEVELS-1:0][2*N-1:0];	
	wire			grid_up_v	[LEVELS-1:0][2*N-1:0];	
	wire 			grid_up_r	[LEVELS-1:0][2*N-1:0];	
	wire 			grid_up_l	[LEVELS-1:0][2*N-1:0];	

	wire 	[A_W+D_W:0] 	grid_dn 	[LEVELS-1:0][2*N-1:0];	
	wire 		 	grid_dn_v 	[LEVELS-1:0][2*N-1:0];	
	wire 	 		grid_dn_r 	[LEVELS-1:0][2*N-1:0];	
	wire 	 		grid_dn_l 	[LEVELS-1:0][2*N-1:0];	

	reg 	[A_W+D_W:0] 	peo 		[N-1:0];	
	reg 	[N-1:0]	 	peo_v 		;	
	wire 	[N-1:0]		peo_r 		;	
	reg 	[N-1:0]		peo_l 		;	

	wire 	[A_W+D_W:0] 	pei 		[N-1:0];	
	wire 	[N-1:0]	 	pei_v 		;	
	reg 	[N-1:0]	 	pei_r 		;	
	wire 	[N-1:0]	 	pei_l 		;	

	
	localparam integer TYPE_LEVELS=11;
	// tree 
`ifdef TREE
	localparam TYPE = {32'd0,32'd0,32'd0,32'd0,32'd0,32'd0,32'd0,32'd0,32'd0,32'd0,32'd0};
`endif
	// xbar 
`ifdef XBAR
	localparam TYPE = {32'd1,32'd1,32'd1,32'd1,32'd1,32'd1,32'd1,32'd1,32'd1,32'd1,32'd1};
`endif
	// mesh0 0.5 
`ifdef MESH0
	localparam TYPE = {32'd1,32'd0,32'd1,32'd0,32'd1,32'd0,32'd1,32'd0,32'd1,32'd0,32'd1};
`endif
	// mesh0 0.67 
`ifdef MESH1
	localparam TYPE = {32'd1,32'd1,32'd0,32'd1,32'd1,32'd0,32'd1,32'd1,32'd0,32'd1,32'd1};
`endif

	genvar m, n, l, m1;
	integer r;

	genvar x;
	generate for (x = 0; x < N; x = x + 1) begin: routeout
		always @(posedge clk) 
		begin
			peo[x]	<= peo_p[(x+1)*(A_W+D_W+1)-1:x*(A_W+D_W+1)];
			pei_p[(x+1)*(A_W+D_W+1)-1:x*(A_W+D_W+1)]	<= pei[x]; 
		end
	end endgenerate

	always@(posedge clk)
	begin
		peo_v	<= peo_v_p;
		peo_l	<= peo_l_p;
		peo_r_p	<= peo_r;

		pei_v_p	<= pei_v;
		pei_l_p	<= pei_l;
		pei_r	<= pei_r_p;
	end
	
	generate if(N>2) begin: n2
	for (l = 1; l < LEVELS; l = l + 1) begin : ls
		for (m = 0; m < N/(1<<(l+1)); m = m + 1) begin : ms
			for (n = 0; n < (1<<(l)); n = n + 1) begin : ns
				if(((TYPE >> (32*(TYPE_LEVELS-1-l))) & {32{1'b1}})==1) begin: pi_level
					pi_switch_top #(.WRAP(WRAP), .D_W(D_W),.A_W(A_W), .N(N), 
						.posl(l), .posx(m*(1<<l)+n),.FD(FD-2*(HR*(1<<(l>>1)))),.HR(HR*(1<<(l>>1))))
					sb(.clk(clk), .rst(rst ), .ce(ce),
						.s_axis_l_wdata(grid_up[l-1][m*(1<<(l+1))+n]),
						.s_axis_l_wvalid(grid_up_v[l-1][m*(1<<(l+1))+n]),
						.s_axis_l_wready(grid_up_r[l-1][m*(1<<(l+1))+n]),
						.s_axis_l_wlast(grid_up_l[l-1][m*(1<<(l+1))+n]),
						.s_axis_r_wdata(grid_up[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_r_wvalid(grid_up_v[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_r_wready(grid_up_r[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_r_wlast(grid_up_l[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_u0_wdata(grid_dn[l][m*(1<<(l+1))+n]),
						.s_axis_u0_wvalid(grid_dn_v[l][m*(1<<(l+1))+n]),
						.s_axis_u0_wready(grid_dn_r[l][m*(1<<(l+1))+n]),
						.s_axis_u0_wlast(grid_dn_l[l][m*(1<<(l+1))+n]),
						.s_axis_u1_wdata(grid_dn[l][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_u1_wvalid(grid_dn_v[l][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_u1_wready(grid_dn_r[l][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_u1_wlast(grid_dn_l[l][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_l_wdata(grid_dn[l-1][m*(1<<(l+1))+n]),
						.m_axis_l_wvalid(grid_dn_v[l-1][m*(1<<(l+1))+n]),
						.m_axis_l_wready(grid_dn_r[l-1][m*(1<<(l+1))+n]),
						.m_axis_l_wlast(grid_dn_l[l-1][m*(1<<(l+1))+n]),
						.m_axis_r_wdata(grid_dn[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_r_wvalid(grid_dn_v[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_r_wready(grid_dn_r[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_r_wlast(grid_dn_l[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_u0_wdata(grid_up[l][m*(1<<(l+1))+n]),
						.m_axis_u0_wvalid(grid_up_v[l][m*(1<<(l+1))+n]),
						.m_axis_u0_wready(grid_up_r[l][m*(1<<(l+1))+n]),
						.m_axis_u0_wlast(grid_up_l[l][m*(1<<(l+1))+n]),
						.m_axis_u1_wdata(grid_up[l][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_u1_wvalid(grid_up_v[l][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_u1_wready(grid_up_r[l][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_u1_wlast(grid_up_l[l][m*(1<<(l+1))+n+(1<<(l))])
						);
		    		end
				if(((TYPE >> (32*(TYPE_LEVELS-1-l))) & {32{1'b1}})==0) begin: t_level
					t_switch_top #(.WRAP(WRAP), .D_W(D_W),.A_W(A_W), .N(N), 
						.posl(l), .posx(m*(1<<l)+n),.FD(FD-2*(HR*(1<<(l>>1)))),.HR(HR*(1<<(l>>1))))
					sb(.clk(clk), .rst(rst), .ce(ce),
						.s_axis_l_wdata(grid_up[l-1][m*(1<<(l+1))+n]),
						.s_axis_l_wvalid(grid_up_v[l-1][m*(1<<(l+1))+n]),
						.s_axis_l_wready(grid_up_r[l-1][m*(1<<(l+1))+n]),
						.s_axis_l_wlast(grid_up_l[l-1][m*(1<<(l+1))+n]),
						.s_axis_r_wdata(grid_up[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_r_wvalid(grid_up_v[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_r_wready(grid_up_r[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_r_wlast(grid_up_l[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.s_axis_u0_wdata(grid_dn[l][m*(1<<(l+1))+n]),
						.s_axis_u0_wvalid(grid_dn_v[l][m*(1<<(l+1))+n]),
						.s_axis_u0_wready(grid_dn_r[l][m*(1<<(l+1))+n]),
						.s_axis_u0_wlast(grid_dn_l[l][m*(1<<(l+1))+n]),
						.m_axis_l_wdata(grid_dn[l-1][m*(1<<(l+1))+n]),
						.m_axis_l_wvalid(grid_dn_v[l-1][m*(1<<(l+1))+n]),
						.m_axis_l_wready(grid_dn_r[l-1][m*(1<<(l+1))+n]),
						.m_axis_l_wlast(grid_dn_l[l-1][m*(1<<(l+1))+n]),
						.m_axis_r_wdata(grid_dn[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_r_wvalid(grid_dn_v[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_r_wready(grid_dn_r[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_r_wlast(grid_dn_l[l-1][m*(1<<(l+1))+n+(1<<(l))]),
						.m_axis_u0_wdata(grid_up[l][m*(1<<(l+1))+n]),
						.m_axis_u0_wvalid(grid_up_v[l][m*(1<<(l+1))+n]),
						.m_axis_u0_wready(grid_up_r[l][m*(1<<(l+1))+n]),
						.m_axis_u0_wlast(grid_up_l[l][m*(1<<(l+1))+n])
						);
		    		end
			end
		end
	end
	end endgenerate
	
	generate for (m = 0; m < N/2; m = m + 1) begin : xs
		if(((TYPE >> (32*(TYPE_LEVELS-1))) & {32{1'b1}})==1) begin: pi_level0
			pi_switch_top #(.WRAP(WRAP), .D_W(D_W),.A_W(A_W), .N(N), .posl(0), .posx(m),.FD(FD-2*HR),.HR(HR))
				sb(.clk(clk), .rst(rst), .ce(ce),
					.s_axis_l_wdata(peo[2*m]),
					.s_axis_l_wvalid(peo_v[2*m]),
					.s_axis_l_wready(peo_r[2*m]),
					.s_axis_l_wlast(peo_l[2*m]),
					.s_axis_r_wdata(peo[2*m+1]),
					.s_axis_r_wvalid(peo_v[2*m+1]),
					.s_axis_r_wready(peo_r[2*m+1]),
					.s_axis_r_wlast(peo_l[2*m+1]),
					.s_axis_u0_wdata(grid_dn[0][2*m]),
					.s_axis_u0_wvalid(grid_dn_v[0][2*m]),
					.s_axis_u0_wready(grid_dn_r[0][2*m]),
					.s_axis_u0_wlast(grid_dn_l[0][2*m]),
					.s_axis_u1_wdata(grid_dn[0][2*m+1]),
					.s_axis_u1_wvalid(grid_dn_v[0][2*m+1]),
					.s_axis_u1_wready(grid_dn_r[0][2*m+1]),
					.s_axis_u1_wlast(grid_dn_l[0][2*m+1]),
					.m_axis_l_wdata(pei[2*m]),
					.m_axis_l_wvalid(pei_v[2*m]),
					.m_axis_l_wready(pei_r[2*m]),
					.m_axis_l_wlast(pei_l[2*m]),
					.m_axis_r_wdata(pei[2*m+1]),
					.m_axis_r_wvalid(pei_v[2*m+1]),
					.m_axis_r_wready(pei_r[2*m+1]),
					.m_axis_r_wlast(pei_l[2*m+1]),
					.m_axis_u0_wdata(grid_up[0][2*m]),
					.m_axis_u0_wvalid(grid_up_v[0][2*m]),
					.m_axis_u0_wready(grid_up_r[0][2*m]),
					.m_axis_u0_wlast(grid_up_l[0][2*m]),
					.m_axis_u1_wdata(grid_up[0][2*m+1]),
					.m_axis_u1_wvalid(grid_up_v[0][2*m+1]),
					.m_axis_u1_wready(grid_up_r[0][2*m+1]),
					.m_axis_u1_wlast(grid_up_l[0][2*m+1])
					);
		end
		if(((TYPE >> (32*(TYPE_LEVELS-1))) & {32{1'b1}})==0) begin: t_level0
			t_switch_top #(.WRAP(WRAP), .D_W(D_W), .N(N),.A_W(A_W), .posl(0), .posx(m),.FD(FD-2*HR),.HR(HR))
				sb(.clk(clk), .rst(rst), .ce(ce),
					.s_axis_l_wdata(peo[2*m]),
					.s_axis_l_wvalid(peo_v[2*m]),
					.s_axis_l_wready(peo_r[2*m]),
					.s_axis_l_wlast(peo_l[2*m]),
					.s_axis_r_wdata(peo[2*m+1]),
					.s_axis_r_wvalid(peo_v[2*m+1]),
					.s_axis_r_wready(peo_r[2*m+1]),
					.s_axis_r_wlast(peo_l[2*m+1]),
					.s_axis_u0_wdata(grid_dn[0][2*m]),
					.s_axis_u0_wvalid(grid_dn_v[0][2*m]),
					.s_axis_u0_wready(grid_dn_r[0][2*m]),
					.s_axis_u0_wlast(grid_dn_l[0][2*m]),
					.m_axis_l_wdata(pei[2*m]),
					.m_axis_l_wvalid(pei_v[2*m]),
					.m_axis_l_wready(pei_r[2*m]),
					.m_axis_l_wlast(pei_l[2*m]),
					.m_axis_r_wdata(pei[2*m+1]),
					.m_axis_r_wvalid(pei_v[2*m+1]),
					.m_axis_r_wready(pei_r[2*m+1]),
					.m_axis_r_wlast(pei_l[2*m+1]),
					.m_axis_u0_wdata(grid_up[0][2*m]),
					.m_axis_u0_wvalid(grid_up_v[0][2*m]),
					.m_axis_u0_wready(grid_up_r[0][2*m]),
					.m_axis_u0_wlast(grid_up_l[0][2*m])
					);
		end
	end endgenerate
endmodule

module shadow_reg_combi 
#(
	parameter	D_W	= 32,
	parameter	A_W	= 32,
	parameter	posl	= 0,
	parameter	posx	= 0
)
(
	input	wire			clk, 
	input 	wire 			rst, 
	input 	wire 			i_v,
	input 	wire	[A_W+D_W:0]	i_d, 
	output 	wire 			i_b,
	output 	wire 			o_v,
	output 	wire 	[A_W+D_W:0] 	o_d, 
	input 	wire 			o_b // unregistered from DOR logic
);

   // shadow register
   reg	s_v_r, o_b_r;
   reg [A_W+D_W-1:0] s_d_r;
   always @(posedge clk) begin
	   if(rst) begin
		   o_b_r <= 1'b0;
		   s_v_r <= 1'b0;
		   s_d_r <= {D_W{1'b0}};
	   end else begin
		   o_b_r <= o_b;
		   if(o_b & !o_b_r & !s_v_r) begin
			s_v_r <= i_v;
			s_d_r <= i_d;
		   end else if (!o_b) begin
			s_v_r <= 1'b0;
			s_d_r <= 0;/////has not been tested
		   end
	   end
   end
   assign o_v = (o_b_r)?s_v_r:i_v;
   assign o_d = (o_b_r)?s_d_r:i_d;
   assign i_b = o_b_r; // input backpressure is registered
endmodule 

module client_top
#(
	parameter N 	= 2,		// total number of clients
	parameter D_W	= 32,		// data width
	parameter A_W	= $clog2(N)+1,	// address width
	parameter WRAP  = 1,            // wrapping means throttling of reinjection
	parameter PAT   = `RANDOM,      // default RANDOM pattern
	parameter RATE  = 10,           // rate of injection (in percent) 
	parameter LIMIT = 16,           // when to stop injectin packets
	parameter SIGMA = 4,            // radius for LOCAL traffic
	parameter posx 	= 2		// position
)
(
	input				clk,
	input				rst,
	input				ce,
	input		`Cmd		cmd,
	
	input		[A_W+D_W-1:0]	s_axis_c_wdata,
	input				s_axis_c_wvalid,
	output	wire			s_axis_c_wready,
	input				s_axis_c_wlast,

	output	wire	[A_W+D_W-1:0]	m_axis_c_wdata,
	output	wire			m_axis_c_wvalid,
	input				m_axis_c_wready,
	output	wire			m_axis_c_wlast,

	output	wire			done
);


`ifdef HYPERFLEX

wire lol;
assign	s_axis_c_wready	= ~lol;

client
#(
	.N		(N		), 	
	.D_W		(D_W		),
	.A_W		(A_W		),
	.WRAP		(WRAP		),	
	.PAT		(PAT		),
	.RATE  		(RATE		),
	.LIMIT		(LIMIT		),
	.SIGMA		(SIGMA		),
	.posx		(posx		)
)
client_inst
(
	.clk		(clk		),
	.rst		(rst		),
	.ce		(ce		),
	.cmd		(cmd		),
	
	.c_i		(s_axis_c_wdata	),
	.c_i_v		(s_axis_c_wvalid),
	.c_i_bp		(lol),

	.c_o		(m_axis_c_wdata	),
	.c_o_v		(m_axis_c_wvalid),
	.c_o_bp		(~m_axis_c_wready),

	.done		(done		)
);
`else	
wire	[A_W+D_W:0]	c_i_d_c;
wire			c_i_v_c;
wire			c_i_b_c;

wire	[A_W+D_W:0]	c_o_d_c;
wire			c_o_v_c;
wire			c_o_b_c;

assign	c_i_d_c		= bp_o_d_c;
assign	c_i_v_c		= bp_o_v_c;
assign	bp_o_b_c	= c_i_b_c;

assign	m_axis_c_wdata	= c_o_d_c[A_W+D_W-1:0];
assign	m_axis_c_wvalid	= c_o_v_c;
assign	c_o_b_c		= ~m_axis_c_wready;
assign	m_axis_c_wlast	= c_o_d_c[A_W+D_W];

client
#(
	.N		(N		), 	
	.D_W		(D_W		),
	.A_W		(A_W		),
	.WRAP		(WRAP		),	
	.PAT		(PAT		),
	.RATE  		(RATE		),
	.LIMIT		(LIMIT		),
	.SIGMA		(SIGMA		),
	.posx		(posx		)
)
client_inst
(
	.clk		(clk		),
	.rst		(rst		),
	.ce		(ce		),
	.cmd		(cmd		),
	
	.c_i		(c_i_d_c	),
	.c_i_v		(c_i_v_c	),
	.c_i_bp		(c_i_b_c	),

	.c_o		(c_o_d_c	),
	.c_o_v		(c_o_v_c	),
	.c_o_bp		(c_o_b_c	),

	.done		(done		)
);

wire			bp_i_v_c;
wire			bp_i_b_c;
wire	[A_W+D_W:0]	bp_i_d_c;

assign	bp_i_v_c	= s_axis_c_wvalid;
assign	bp_i_d_c	= {s_axis_c_wlast, s_axis_c_wdata};
assign	s_axis_c_wready	= ~bp_i_b_c;

wire			bp_o_v_c;
wire			bp_o_b_c;
wire	[A_W+D_W:0]	bp_o_d_c;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_C
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_c	),
	.i_d		(bp_i_d_c	), 
	.i_b		(bp_i_b_c	),
	.o_v		(bp_o_v_c	),
	.o_d		(bp_o_d_c	), 
	.o_b		(bp_o_b_c	) 
);
`endif
endmodule

module client 
#(
	parameter N 	= 2,		// total number of clients
	parameter D_W	= 32,		// data width
	parameter A_W	= $clog2(N)+1,	// address width
	parameter WRAP  = 1,            // wrapping means throttling of reinjection
	parameter PAT   = `RANDOM,      // default RANDOM pattern
	parameter RATE  = 10,           // rate of injection (in percent) 
	parameter LIMIT = 16,           // when to stop injectin packets
	parameter SIGMA = 4,            // radius for LOCAL traffic
	parameter posx 	= 2,		// position
	parameter filename = "posx"
)
(
	input				clk,
	input				rst,
	input				ce,
	input		`Cmd		cmd,
	
	input		[A_W+D_W:0]	c_i,
	input				c_i_v,
	output	wire			c_i_bp,

	output	reg	[A_W+D_W:0]	c_o,
	output	reg			c_o_v,
	input				c_o_bp,

	output	wire			done
);

assign	c_i_bp	= 1'b0;

`ifdef SYNTHETIC

integer	r, attempts,sent;
reg 			done_sig;
reg	[A_W-1:0]	next;
reg			next_v;
reg 	[D_W-1:0] 	tmp;

always@(posedge clk)
begin
	if (rst==1'b1)
	begin
		c_o		<= 'b0;
		c_o_v		<= 1'b0;
		r		<= 'b0;
		attempts	<= 0;
		sent		<= 0;
	end
	else
	begin
		r	<= {$random}%100;
		if (c_o_bp==1'b0)
		begin
			if(((attempts<LIMIT & {r} < RATE) | attempts > sent | cmd!=`Cmd_RND)) 
			begin
				c_o_v			<= 1'b1;
				c_o[A_W+D_W-1:D_W]	<= next;
				if(next_v==1) 
				begin
					sent		<= sent + 1;
					tmp		= ((posx)*LIMIT+sent); // send packetid instead
					c_o[D_W-1:0]	<= tmp;
					$display("Time%0d: Sent packet from PE(%0d) to PE(%0d) with packetid=%0d , data=%0d ",now,posx,next,((posx)*LIMIT+sent),tmp);
				end
			end
			else
			begin
				c_o_v	<= 1'b0;
			end
		end
		else
		begin
		//	c_o_v	<= 1'b0;
		end
	
		if ((attempts<LIMIT & {r} < RATE) | cmd!=`Cmd_RND)
		begin
			attempts	<= attempts + 1;
			$display("Time%0d: Attempted packetid=%0d at PE(%0d) attempts=%0d sent=%0d",now,(posx*LIMIT+attempts),posx, attempts, sent);

		end
		
		if(c_i_v==1'b1) 
		begin
			$display("Time%0d: Received packet at PE(%0d) with data=%0d packetid=%0d ",now-1,posx,c_i[D_W-1:0],c_i[D_W-1:0]);
		end
	end
end

always @(*) 
begin
	next_v = 0;
	next = 0;
	if (cmd != `Cmd_IDLE) 
	begin				
		next_v = 1;
		case (cmd)
			default: ;
			`Cmd_01: if (posx==0) next=2'd01; else begin next_v=0; end
			`Cmd_02: if (posx==0) next=2'd10; else begin next_v=0; end
			`Cmd_03: if (posx==0) next=2'd11; else begin next_v=0; end
			`Cmd_10: if (posx==1) next=2'd00; else begin next_v=0; end
			`Cmd_12: if (posx==1) next=2'd10; else begin next_v=0; end
			`Cmd_13: if (posx==1) next=2'd11; else begin next_v=0; end
			`Cmd_20: if (posx==2) next=2'd00; else begin next_v=0; end
			`Cmd_21: if (posx==2) next=2'd01; else begin next_v=0; end
			`Cmd_23: if (posx==2) next=2'd11; else begin next_v=0; end
			`Cmd_30: if (posx==3) next=2'd00; else begin next_v=0; end
			`Cmd_31: if (posx==3) next=2'd01; else begin next_v=0; end
			`Cmd_32: if (posx==3) next=2'd10; else begin next_v=0; end
			`Cmd_02_12: if (posx==0) next=2'd10; else if (posx==1) next=2'd10; else begin next_v=0; end
			`Cmd_01_12: if (posx==0) next=2'd01; else if (posx==1) next=2'd10; else begin next_v=0; end
			`Cmd_40_70: if (posx==4) next=2'd00; else if (posx==7) next=2'd00; else begin next_v=0; end
			`Cmd_02_25: if (posx==0) next=2'd10; else if (posx==2) next=3'd101; else begin next_v=0; end
			`Cmd_swap: if (posx==0) next=2'd01; else if (posx==1) next=2'd00; else begin next_v=0; end
			// randomized testing
			`Cmd_RND: 
				case (PAT)
				`RANDOM: begin 
					next=get_safe_rnd({$random}%N); 
				end
				`LOCAL: begin 
					next=get_safe_rnd(local_window(local_rnd(posx),N)); 
				end
				`BITREV: begin 
					next=bitrev(posx) % N; 
				end
				`TORNADO: begin 
					next=tornado(posx, N); 
				end
				endcase
		endcase
	end 
end

	integer now=0;
	always @(posedge clk) begin
		now     <= now + 1;
		if(now==0 && posx==0) begin
			$display("RATE=%0d , N=%0d",RATE,N);
		end
		if(attempts==sent & attempts==LIMIT & ~c_i_v) begin
//			$display("Time%0d, PE=%0d, attempts=%d, sent=%d\n",now,posx,attempts,sent);
			done_sig <= 1;
		end else begin
			done_sig <= 0;
		end
	end
	
	assign done = done_sig;


	// avoid self-packets for now
	function integer get_safe_rnd(input integer tmp);
		get_safe_rnd=(tmp==posx)?((tmp+1)%N):tmp%N;
	endfunction

	function integer local_rnd(input integer i);
		local_rnd = i + {$random} % SIGMA - SIGMA/2;
	endfunction

	// avoiding SystemVerilog for
	// iverilog compatibility
	function integer local_window(input integer r, input integer max);
		local_window = (r < 0)? 0 : (r >= max) ? (max-1) : r;
	endfunction

	function [9:0] bitrev(input [9:0] i);
		bitrev = {i[0],i[1],i[2],i[3],i[4],i[5],i[6],i[7],i[8],i[9]};
	endfunction

	function integer tornado(input integer i, input integer max);
		tornado = (i + max/2-1) % max;
	endfunction

`elsif REAL

integer		r, attempts,sent;
reg		done_sig;
reg	[31:0]	next	[0:99999999];
reg			next_v;
reg 	[D_W-1:0] 	tmp;
initial
begin
	`ifdef SIM_AXIIC
		//$readmemh(filename,next);
$readmemh("autogen_0.trace",next);
	`endif
	`ifndef SIM_AXIIC
		$readmemh($sformatf("autogen_%0d.trace",posx),next);
	`endif
end

always@(posedge clk)
begin
	if (rst==1'b1)
	begin
		c_o		<= 'b0;
		c_o_v		<= 1'b0;
		r		<= 'b0;
		attempts	<= 0;
		sent		<= 0;
	end
	else
	begin
		r	<= {$random}%100;
		if (c_o_bp==1'b0)
		begin
			if(((next[sent][11:8]!=4'hf & {r} < RATE) | attempts > sent | cmd!=`Cmd_RND)) 
			begin
				if(next[sent][A_W-1:0]!=posx)
				begin
					c_o_v			<= 1'b1;
					c_o[A_W+D_W-1:D_W]	<= next[sent][A_W-1:0];
					sent		<= sent + 1;
					tmp		= ((posx)*1485078+sent); // send packetid instead
					c_o[D_W-1:0]	<= tmp;
					$display("Time%0d: Sent packet from PE(%0d) to PE(%0d) with packetid=%0d , data=%0d ",now,posx,next[sent][A_W-1:0],((posx)*1485078+sent),tmp);
				end
				else
				begin
					sent	<= sent + 1;
					c_o_v	<= 1'b0;
					$display("Time%0d: Sent packet from PE(%0d) to PE(%0d) with packetid=%0d , data=%0d ",now,posx,next[sent][A_W-1:0],((posx)*1485078+sent),((posx)*1485078+sent));
			$display("Time%0d: Received packet at PE(%0d) with data=%0d packetid=%0d ",now,posx,((posx)*1485078+sent),((posx)*1485078+sent));
				end
			end
			else
			begin
				c_o_v	<= 1'b0;
			end
		end
		else
		begin
			//c_o_v	<= 1'b0;
		end
	
		if ((next[attempts][11:8]!=4'hf & {r} < RATE) | cmd!=`Cmd_RND)
		begin
			attempts	<= attempts + 1;
			$display("Time%0d: Attempted packetid=%0d at PE(%0d) attempts=%0d sent=%0d",now,(posx*1485078+attempts),posx, attempts, sent);

		end
		
		if(c_i_v==1'b1) 
		begin
			$display("Time%0d: Received packet at PE(%0d) with data=%0d packetid=%0d ",now-1,posx,c_i[D_W-1:0],c_i[D_W-1:0]);
		end
	end
end

	integer now=0;
	always @(posedge clk) begin
		now     <= now + 1;
		if(now==0 && posx==0) begin
			$display("RATE=%0d , N=%0d",RATE,N);
		end
		if(attempts==sent & next[sent][11:8]==4'hf & ~c_i_v) begin
//			$display("Time%0d, PE=%0d, attempts=%d, sent=%d\n",now,posx,attempts,sent);
			done_sig <= 1;
		end else begin
			done_sig <= 0;
		end
	end

assign done = done_sig;
`endif
endmodule

module Mux2 #(
	parameter W = 32
) (
	input wire s,
	input wire [W-1:0] i0,
	input wire [W-1:0] i1,
	output wire [W-1:0] o
);
	assign o = s ? i1 : i0;
endmodule


module Mux3 #(
	parameter W = 32
) (
	input wire [1:0] s,
	input wire [W-1:0] i0,
	input wire [W-1:0] i1,
	input wire [W-1:0] i2,
	output wire [W-1:0] o
);
	assign o = s[1] ? i2 : s[0] ? i1 : i0;
endmodule


module Mux4 #(
	parameter W = 32
) (
	input wire [1:0] s,
	input wire [W-1:0] i0,
	input wire [W-1:0] i1,
	input wire [W-1:0] i2,
	input wire [W-1:0] i3,
	output wire [W-1:0] o
);
	assign o = s[1] ? (s[0]? i3 : i2) : (s[0] ? i1 : i0);
endmodule


module pi_route #(
	parameter N	= 8,		// number of clients
	parameter A_W	= $clog2(N)+1,	// log number of clients
	parameter D_W	= 32,
	parameter posl  = 0,		// which level
	parameter posx 	= 0		// which position
) (
	input  	wire 			clk		,	// clock
	input  	wire 			rst		,	// reset
	input  	wire 			ce		,	// clock enable
	input  	wire 			l_i_v		,	// left input valid
	input  	wire 			r_i_v		,	// right input valid
	input  	wire 			u0_i_v		,	// up0 input valid
	input  	wire 			u1_i_v		,	// up1 input valid
	output  wire 			l_i_bp		,	// left input is backpressured
	output  wire 			r_i_bp		,	// right input is backpressured
	output  wire 			u0_i_bp		,	// up0 input is backpressured
	output  wire 			u1_i_bp		,	// up1 input is backpressured
	input  	wire	[A_W-1:0]	l_i_addr	,	// left input addr
	input  	wire	[A_W-1:0] 	r_i_addr	,	// right input addr
	input  	wire 	[A_W-1:0] 	u0_i_addr	, 	// up0 input addr
	input  	wire 	[A_W-1:0] 	u1_i_addr	, 	// up0 input addr
	input  	wire	[D_W-1:0]	l_i_data	,	// left input addr
	input  	wire	[D_W-1:0] 	r_i_data	,	// right input addr
	input  	wire 	[D_W-1:0] 	u0_i_data	, 	// up0 input addr
	input  	wire 	[D_W-1:0] 	u1_i_data	, 	// up0 input addr
	output 	wire			l_o_v		,	// valid for l mux
	output 	wire			r_o_v		,	// valid for r mux
	output 	wire			u0_o_v		,	// valid for u0 mux
	output 	wire			u1_o_v		,	// valid for u1 mux
	input	wire			l_o_bp		,	// left output is backpressured
	input	wire			r_o_bp		,	// right output is backpressured
	input	wire			u0_o_bp		,	// up0 output is backpressured
	input	wire			u1_o_bp		,	// up1 output is backpressured
	output 	reg	[2:0] 		l_sel		,	// select for l mux
	output 	reg	[2:0] 		r_sel		,	// select for r mux
	output 	reg	[2:0] 		u0_sel		,	// select for u0 mux
	output 	reg	[2:0] 		u1_sel			// select for u1 mux
);

wire		l_wins, l_wants_r, l_wants_u0, l_wants_u1, l_gets_r, l_gets_u0, l_gets_u1;
wire 		r_wins, r_wants_l, r_wants_u0, r_wants_u1, r_gets_l, r_gets_u1, r_gets_u0;
wire 		u0_wins, u0_wants_l, u0_wants_r, u0_gets_l, u0_gets_r;
wire 		u1_wins, u1_wants_l, u1_wants_r, u1_gets_l, u1_gets_r;

reg	[1:0]	rr; //0->L, 1->R,2->U0,3->U1

always@(posedge clk)
begin
	if(rst)
	begin
		rr	<= 0;
	end
	else
	begin
		case(rr)
			0:
			begin
				if(r_i_bp)
				begin
					rr	<= 1;
				end
				else if(u0_i_bp)
				begin
					rr	<= 2;
				end
				else if(u1_i_bp)
				begin
					rr	<= 3;
				end
			end
			1:
			begin
				if(u0_i_bp)
				begin
					rr	<= 2;
				end
				else if(u1_i_bp)
				begin
					rr	<= 3;
				end
				else if(l_i_bp)
				begin
					rr	<= 0;
				end
			end
			2:
			begin
				if(u1_i_bp)
				begin
					rr	<= 3;
				end
				else if(l_i_bp)
				begin
					rr	<= 0;
				end
				else if(r_i_bp)
				begin
					rr	<= 1;
				end
			end
			3:
			begin
				if(l_i_bp)
				begin
					rr	<= 0;
				end
				else if(r_i_bp)
				begin
					rr	<= 1;
				end
				else if(u0_i_bp)
				begin
					rr	<= 2;
				end
			end
		endcase
	end
end


always@*
begin
	case({r_gets_l, u0_gets_l, u1_gets_l})
		3'b100:
		begin
			l_sel	<= `RIGHT -3'b001;
		end
		3'b010:
		begin
			l_sel	<= `U0 -3'b001;
		end
		3'b001:
		begin
			l_sel	<= `U1-3'b001;
		end
		default:
		begin
			l_sel	<= `LEFT;
		end

	endcase
end

always@*
begin
	case({l_gets_r, u0_gets_r, u1_gets_r})
		3'b100:
		begin
			r_sel	<= `LEFT;
		end
		3'b010:
		begin
			r_sel	<= `U0-3'b001;			
		end
		3'b001:
		begin
			r_sel	<= `U1-3'b001;
		end
		default:
		begin
			r_sel	<= 3'b000;
		end

	endcase
end

always@*
begin
	case({l_gets_u0})
		1'b1:
		begin
			u0_sel	<= `LEFT;
		end
		default:
		begin
			u0_sel	<= `U0;
		end

	endcase
end
always@*
begin
	case({r_gets_u1})
		1'b1:
		begin
			u1_sel	<= `RIGHT;
		end
		default:
		begin
			u1_sel	<= `U1;
		end

	endcase
end

assign	l_wins	= ( (rr==0) | (rr==2) | (rr==1 & ~u1_wants_r) ) & ~(u0_wants_r & rr==2);
assign	r_wins	= ( (rr==1) | (rr==3) | (rr==0 & ~u0_wants_l) ) & ~(u1_wants_l & rr==3);
assign	u0_wins	= ( (rr==2) | (rr==0) ) & ~(l_wants_r & rr==0);
assign	u1_wins = ( (rr==3) | (rr==1) ) & ~(r_wants_l & rr==1);

assign l_wants_r 	= l_i_v & l_i_addr[posl] & l_i_addr[A_W-1:posl+1]==posx[A_W-1:posl];
assign l_wants_u0 	= l_i_v & l_i_addr[A_W-1:posl+1]!=posx[A_W-1:posl];// & l_i_addr[posl] ;
assign l_wants_u1 	= 1'b0;//'`l_i_v & l_i_addr[A_W-1:posl+1]!=posx[A_W-1:posl] & ~l_i_addr[posl];

assign r_wants_l 	= r_i_v & ~r_i_addr[posl] & r_i_addr[A_W-1:posl+1]==posx[A_W-1:posl];
assign r_wants_u0 	= 1'b0;//r_i_v & r_i_addr[A_W-1:posl+1]!=posx[A_W-1:posl] & r_i_addr[posl] ;
assign r_wants_u1 	= r_i_v & r_i_addr[A_W-1:posl+1]!=posx[A_W-1:posl];// & ~r_i_addr[posl];
	
assign u0_wants_l 	= u0_i_v & ~u0_i_addr[posl];
assign u0_wants_r 	= u0_i_v & u0_i_addr[posl];
	
assign u1_wants_l 	= u1_i_v & ~u1_i_addr[posl];
assign u1_wants_r 	= u1_i_v & u1_i_addr[posl];

assign	l_gets_r	= 	(~r_o_bp) & (l_wants_r)  & ( (l_wins)  | (~u0_wants_r & ~u1_wants_r) );
assign	u0_gets_r	= 	(~r_o_bp) & (u0_wants_r) & ( (u0_wins) | (~l_wants_r & ~u1_wants_r) );
assign	u1_gets_r	= 	(~r_o_bp) & (u1_wants_r) & ( (u1_wins) | (~l_wants_r & ~u0_wants_r) );
				
assign	r_gets_l	= 	(~l_o_bp) & (r_wants_l)  & ( (r_wins)  | (~u0_wants_l & ~u1_wants_l) );
assign	u0_gets_l	= 	(~l_o_bp) & (u0_wants_l) & ( (u0_wins) | (~r_wants_l & ~u1_wants_l) );
assign	u1_gets_l	= 	(~l_o_bp) & (u1_wants_l) & ( (u1_wins) | (~r_wants_l & ~u0_wants_l) );

assign	l_gets_u0	= 	(~u0_o_bp) & (l_wants_u0)  & ( (l_wins)  | (~r_wants_u0) ) ;

assign	r_gets_u1	= 	(~u1_o_bp) & (r_wants_u1)  & ( (r_wins)  | (~l_wants_u1) ) ;

assign	l_i_bp		=	(l_wants_r  & ~l_gets_r)  | (l_wants_u0 & ~l_gets_u0) ;
assign	r_i_bp		=	(r_wants_l  & ~r_gets_l)  | (r_wants_u1 & ~r_gets_u1);
assign	u0_i_bp		=	(u0_wants_l & ~u0_gets_l) | (u0_wants_r & ~u0_gets_r) ;
assign	u1_i_bp		=	(u1_wants_l & ~u1_gets_l) | (u1_wants_r & ~u1_gets_r) ;

assign	l_o_v		=	r_gets_l  | u0_gets_l | u1_gets_l;
assign	r_o_v		=	l_gets_r  | u0_gets_r | u1_gets_r;
assign	u0_o_v		=	l_gets_u0 ;
assign	u1_o_v		=	r_gets_u1 ;

endmodule

module pi_switch_top
#
(
	parameter	N	= 2,			//number of clients
	parameter	WRAP	= 1,			//crossbar?
	parameter	A_W	= $clog2(N) + 1, 	//addr width
	parameter	D_W	= 32,			//data width
	parameter	posl	= 0,			//which level
	parameter	posx	= 0,		//which position
	parameter	DEBUG	= 1,
	parameter	FD	= 10,
	parameter	HR	= 4
)
(
	input  wire 			clk,		// clock
	input  wire 			rst,		// reset
	input  wire 			ce,		// clock enable
	
	input  	wire	[A_W+D_W-1:0] 	s_axis_l_wdata	,	
	output	wire			s_axis_l_wready	,
	input	wire			s_axis_l_wvalid	,
	input	wire			s_axis_l_wlast	,
	
	input  	wire	[A_W+D_W-1:0] 	s_axis_r_wdata	,
	output	wire			s_axis_r_wready	,
	input	wire			s_axis_r_wvalid	,
	input	wire			s_axis_r_wlast	,
	
	input  	wire	[A_W+D_W-1:0] 	s_axis_u0_wdata	,
	output	wire			s_axis_u0_wready, 
	input	wire			s_axis_u0_wvalid, 
	input	wire			s_axis_u0_wlast	,

	input  	wire	[A_W+D_W-1:0] 	s_axis_u1_wdata	,
	output	wire			s_axis_u1_wready, 
	input	wire			s_axis_u1_wvalid, 
	input	wire			s_axis_u1_wlast	,

	output 	wire	[A_W+D_W-1:0] 	m_axis_l_wdata	,
	input	wire			m_axis_l_wready	,
	output	wire			m_axis_l_wvalid	,
	output	wire			m_axis_l_wlast	,	

	output 	wire	[A_W+D_W-1:0] 	m_axis_r_wdata	,
	input	wire			m_axis_r_wready	,
	output	wire			m_axis_r_wvalid	,
	output	wire			m_axis_r_wlast	,	

	output 	wire	[A_W+D_W-1:0] 	m_axis_u0_wdata	,
	input	wire			m_axis_u0_wready,
	output	wire			m_axis_u0_wvalid,
	output	wire			m_axis_u0_wlast	,	

	output 	wire	[A_W+D_W-1:0] 	m_axis_u1_wdata	,
	input	wire			m_axis_u1_wready,
	output	wire			m_axis_u1_wvalid,
	output	wire			m_axis_u1_wlast	,	
	output 	wire 			done		// done
);
`ifdef HYPERFLEX

reg	[A_W+D_W:0]	s_axis_l_wdata_hr	[HR-1:0];
reg			s_axis_l_wvalid_hr	[HR-1:0];
reg			s_axis_l_wready_hr	[HR-1:0];

wire	[A_W+D_W:0]	pi_o_d_l;
wire			pi_o_v_l;
wire			pi_o_b_l;

assign	m_axis_l_wdata	= pi_o_d_l[A_W+D_W-1:0];
assign	m_axis_l_wvalid	= pi_o_v_l;
assign	pi_o_b_l	= ~m_axis_l_wready;
assign	m_axis_l_wlast	= pi_o_d_l[A_W+D_W];

assign	s_axis_l_wready	= s_axis_l_wready_hr[HR-1];

integer hr_l;
integer now=0;

always@(posedge clk)
begin
	now <= now + 1;
	s_axis_l_wdata_hr[0]	<= {s_axis_l_wlast,s_axis_l_wdata};
	s_axis_l_wvalid_hr[0]	<= s_axis_l_wvalid;
	s_axis_l_wready_hr[0]	<= ~l_fifo_full;
	for(hr_l=0;hr_l<HR-1;hr_l=hr_l+1)
	begin
		s_axis_l_wdata_hr[hr_l+1]	<= s_axis_l_wdata_hr[hr_l];
		s_axis_l_wvalid_hr[hr_l+1]	<= s_axis_l_wvalid_hr[hr_l];
		s_axis_l_wready_hr[hr_l+1]	<= s_axis_l_wready_hr[hr_l];
	end

end


wire			l_fifo_empty;
wire			l_fifo_done;
wire			l_fifo_full;

wire	[A_W+D_W:0]	pi_i_d_l;
wire			pi_i_v_l;
wire			pi_i_bp_l;

`ifdef SIM
fwft_fifo 
#(
	.fifo_dw	(A_W+D_W+1),
	.fifo_depth	(FD+2*HR),
	.LOC		("w"),
	.HR		(HR)
)
l_fifo
(
	.clk		(clk				),
	.rst		(rst				),
	.d_in		(s_axis_l_wdata_hr[HR-1]	),//
	.wr_en		(s_axis_l_wvalid_hr[HR-1]	),//
	.full_early		(l_fifo_full			),//
	.d_out		(pi_i_d_l			),//
	.d_valid_out	(pi_i_v_l			),//
	.rd_en		(~pi_i_bp_l & ~l_fifo_empty	),//
	.empty		(l_fifo_empty			),//
	.done		(l_fifo_done			) //
);
`endif
`ifdef XLNXSRLFIFO
fifo_generator_1 l_fifo
(
	.clk		(clk				),
	.srst		(rst				),
	.din		({s_axis_l_wvalid,s_axis_l_wdata_hr[HR-1]}	),//
	.wr_en		(s_axis_l_wvalid_hr[HR-1]	),//
	.full		(l_fifo_full			),//
	.dout		({pi_i_v_l,pi_i_d_l}			),//
	.rd_en		(~pi_i_bp_l & ~l_fifo_empty	),//
	.empty		(l_fifo_empty			)//
//	.done		(l_fifo_done			) //
);
`endif

reg	[A_W+D_W:0]	s_axis_r_wdata_hr	[HR-1:0];
reg			s_axis_r_wvalid_hr	[HR-1:0];
reg			s_axis_r_wready_hr	[HR-1:0];

wire	[A_W+D_W:0]	pi_o_d_r;
wire			pi_o_v_r;
wire			pi_o_b_r;

assign	m_axis_r_wdata	= pi_o_d_r[A_W+D_W-1:0];
assign	m_axis_r_wvalid	= pi_o_v_r;
assign	pi_o_b_r	= ~m_axis_r_wready;
assign	m_axis_r_wlast	= pi_o_d_r[A_W+D_W];

assign	s_axis_r_wready	= s_axis_r_wready_hr[HR-1];

integer hr_r;

always@(posedge clk)
begin
	s_axis_r_wdata_hr[0]	<= {s_axis_r_wlast,s_axis_r_wdata};
	s_axis_r_wvalid_hr[0]	<= s_axis_r_wvalid;
	s_axis_r_wready_hr[0]	<= ~r_fifo_full;
	for(hr_r=0;hr_r<HR-1;hr_r=hr_r+1)
	begin
		s_axis_r_wdata_hr[hr_r+1]	<= s_axis_r_wdata_hr[hr_r];
		s_axis_r_wvalid_hr[hr_r+1]	<= s_axis_r_wvalid_hr[hr_r];
		s_axis_r_wready_hr[hr_r+1]	<= s_axis_r_wready_hr[hr_r];
	end

end


wire			r_fifo_empty;
wire			r_fifo_done;
wire			r_fifo_full;

wire	[A_W+D_W:0]	pi_i_d_r;
wire			pi_i_v_r;
wire			pi_i_bp_r;
`ifdef SIM
fwft_fifo 
#(
	.fifo_dw	(A_W+D_W+1),
	.fifo_depth	(FD+2*HR),
	.LOC		("w"),
	.HR		(HR)
)
r_fifo
(
	.clk		(clk				),
	.rst		(rst				),
	.d_in		(s_axis_r_wdata_hr[HR-1]	),//
	.wr_en		(s_axis_r_wvalid_hr[HR-1]	),//
	.full_early		(r_fifo_full			),//
	.d_out		(pi_i_d_r			),//
	.d_valid_out	(pi_i_v_r			),//
	.rd_en		(~pi_i_bp_r & ~r_fifo_empty	),//
	.empty		(r_fifo_empty			),//
	.done		(r_fifo_done			) //
);
`endif

`ifdef XLNXSRLFIFO

fifo_generator_1 r_fifo
(
	.clk		(clk				),
	.srst		(rst				),
	.din		({s_axis_r_wvalid,s_axis_r_wdata_hr[HR-1]}	),//
	.wr_en		(s_axis_r_wvalid_hr[HR-1]	),//
	.full		(r_fifo_full			),//
	.dout		({pi_i_v_r,pi_i_d_r}			),//
	.rd_en		(~pi_i_bp_r & ~r_fifo_empty	),//
	.empty		(r_fifo_empty			)//
//	.done		(r_fifo_done			) //
);
`endif

reg	[A_W+D_W:0]	s_axis_u0_wdata_hr	[HR-1:0];
reg			s_axis_u0_wvalid_hr	[HR-1:0];
reg			s_axis_u0_wready_hr	[HR-1:0];

wire	[A_W+D_W:0]	pi_o_d_u0;
wire			pi_o_v_u0;
wire			pi_o_b_u0;

assign	m_axis_u0_wdata	= pi_o_d_u0[A_W+D_W-1:0];
assign	m_axis_u0_wvalid= pi_o_v_u0;
assign	pi_o_b_u0	= ~m_axis_u0_wready;
assign	m_axis_u0_wlast	= pi_o_d_u0[A_W+D_W];

assign	s_axis_u0_wready= s_axis_u0_wready_hr[HR-1];

integer hr_u0;

always@(posedge clk)
begin
	s_axis_u0_wdata_hr[0]	<= {s_axis_u0_wlast,s_axis_u0_wdata};
	s_axis_u0_wvalid_hr[0]	<= s_axis_u0_wvalid;
	s_axis_u0_wready_hr[0]	<= ~u0_fifo_full;
	for(hr_u0=0;hr_u0<HR-1;hr_u0=hr_u0+1)
	begin
		s_axis_u0_wdata_hr[hr_u0+1]	<= s_axis_u0_wdata_hr[hr_u0];
		s_axis_u0_wvalid_hr[hr_u0+1]	<= s_axis_u0_wvalid_hr[hr_u0];
		s_axis_u0_wready_hr[hr_u0+1]	<= s_axis_u0_wready_hr[hr_u0];
	end

end


wire			u0_fifo_empty;
wire			u0_fifo_done;
wire			u0_fifo_full;

wire	[A_W+D_W:0]	pi_i_d_u0;
wire			pi_i_v_u0;
wire			pi_i_bp_u0;

`ifdef SIM
fwft_fifo 
#(
	.fifo_dw	(A_W+D_W+1),
	.fifo_depth	(FD+2*HR),
	.LOC		("w"),
	.HR		(HR)
)
u0_fifo
(
	.clk		(clk				),
	.rst		(rst				),
	.d_in		(s_axis_u0_wdata_hr[HR-1]	),//
	.wr_en		(s_axis_u0_wvalid_hr[HR-1]	),//
	.full_early		(u0_fifo_full			),//
	.d_out		(pi_i_d_u0			),//
	.d_valid_out	(pi_i_v_u0			),//
	.rd_en		(~pi_i_bp_u0 & ~u0_fifo_empty	),//
	.empty		(u0_fifo_empty			),//
	.done		(u0_fifo_done			) //
);
`endif

`ifdef XLNXSRLFIFO
fifo_generator_1 u0_fifo
(
	.clk		(clk				),
	.srst		(rst				),
	.din		({s_axis_u0_wvalid,s_axis_u0_wdata_hr[HR-1]}	),//
	.wr_en		(s_axis_u0_wvalid_hr[HR-1]	),//
	.full		(u0_fifo_full			),//
	.dout		({pi_i_v_u0,pi_i_d_u0}			),//
	.rd_en		(~pi_i_bp_u0 & ~u0_fifo_empty	),//
	.empty		(u0_fifo_empty			)//
//	.done		(u0_fifo_done			) //
);
`endif

reg	[A_W+D_W:0]	s_axis_u1_wdata_hr	[HR-1:0];
reg			s_axis_u1_wvalid_hr	[HR-1:0];
reg			s_axis_u1_wready_hr	[HR-1:0];


wire	[A_W+D_W:0]	pi_o_d_u1;
wire			pi_o_v_u1;
wire			pi_o_b_u1;

assign	m_axis_u1_wdata	= pi_o_d_u1[A_W+D_W-1:0];
assign	m_axis_u1_wvalid= pi_o_v_u1;
assign	pi_o_b_u1	= ~m_axis_u1_wready;
assign	m_axis_u1_wlast	= pi_o_d_u1[A_W+D_W];

assign	s_axis_u1_wready= s_axis_u1_wready_hr[HR-1];

integer hr_u1;

always@(posedge clk)
begin
	s_axis_u1_wdata_hr[0]	<= {s_axis_u1_wlast,s_axis_u1_wdata};
	s_axis_u1_wvalid_hr[0]	<= s_axis_u1_wvalid;
	s_axis_u1_wready_hr[0]	<= ~u1_fifo_full;
	for(hr_u1=0;hr_u1<HR-1;hr_u1=hr_u1+1)
	begin
		s_axis_u1_wdata_hr[hr_u1+1]		<= s_axis_u1_wdata_hr[hr_u1];
		s_axis_u1_wvalid_hr[hr_u1+1]	<= s_axis_u1_wvalid_hr[hr_u1];
		s_axis_u1_wready_hr[hr_u1+1]	<= s_axis_u1_wready_hr[hr_u1];
	end

end


wire			u1_fifo_empty;
wire			u1_fifo_done;
wire			u1_fifo_full;

wire	[A_W+D_W:0]	pi_i_d_u1;
wire			pi_i_v_u1;
wire			pi_i_bp_u1;

`ifdef SIM
fwft_fifo 
#(
	.fifo_dw	(A_W+D_W+1),
	.fifo_depth	(FD+2*HR),
	.LOC		("w"),
	.HR		(HR)
)
u1_fifo
(
	.clk		(clk				),
	.rst		(rst				),
	.d_in		(s_axis_u1_wdata_hr[HR-1]	),//
	.wr_en		(s_axis_u1_wvalid_hr[HR-1]	),//
	.full_early		(u1_fifo_full			),//
	.d_out		(pi_i_d_u1			),//
	.d_valid_out	(pi_i_v_u1			),//
	.rd_en		(~pi_i_bp_u1 & ~u1_fifo_empty	),//
	.empty		(u1_fifo_empty			),//
	.done		(u1_fifo_done			) //
);
`endif
`ifdef XLNXSRLFIFO
fifo_generator_1 u1_fifo
(
	.clk		(clk				),
	.srst		(rst				),
	.din		({s_axis_u1_wvalid,s_axis_u1_wdata_hr[HR-1]}	),//
	.wr_en		(s_axis_u1_wvalid_hr[HR-1]	),//
	.full		(u1_fifo_full			),//
	.dout		({pi_i_v_u1,pi_i_d_u1}			),//
	.rd_en		(~pi_i_bp_u1 & ~u1_fifo_empty	),//
	.empty		(u1_fifo_empty			)//
//	.done		(u1_fifo_done			) //
);
`endif

pi_switch
#(
	.N		(N	),	
	.WRAP		(WRAP	),
	.A_W		(A_W	),
	.D_W		(D_W	),
	.posl  		(posl	),
	.posx 		(posx	)
)
pi_switch_inst
(
	.clk		(clk		),		// clock
	.rst		(rst		),		// reset
	.ce		(ce		),		// clock enable
	`ifdef SIM
	.done		(done		),	// done
	`endif
	.l_i		(pi_i_d_l	),	// left  input payload
	.l_i_bp		(pi_i_bp_l	),	// left  input backpressured
	.l_i_v		(pi_i_v_l	),	// left  input valid
	.r_i		(pi_i_d_r	),	// right input payload
	.r_i_bp		(pi_i_bp_r	),	// right input backpressured
	.r_i_v		(pi_i_v_r	),	// right input valid
	.u0_i		(pi_i_d_u0	),	// u0    input payload
	.u0_i_bp	(pi_i_bp_u0	),	// u0    input backpressured
	.u0_i_v		(pi_i_v_u0	),	// u0    input valid
	.u1_i		(pi_i_d_u1	),	// u1    input payload
	.u1_i_bp	(pi_i_bp_u1	),	// u1    input backpressured
	.u1_i_v		(pi_i_v_u1	),	// u1    input valid
	.l_o		(pi_o_d_l	),	// left  output payload
	.l_o_bp		(pi_o_b_l	),	// left  output backpressured
	.l_o_v		(pi_o_v_l	),	// left  output valid
	.r_o		(pi_o_d_r	),	// right output payload
	.r_o_bp		(pi_o_b_r	),	// right output backpressured
	.r_o_v		(pi_o_v_r	),	// right output valid
	.u0_o		(pi_o_d_u0	),	// u0    output payload
	.u0_o_bp	(pi_o_b_u0	),	// u0    output backpressured
	.u0_o_v		(pi_o_v_u0	),	// u0    output valid
	.u1_o		(pi_o_d_u1	),	// u1    output payload
	.u1_o_bp	(pi_o_b_u1	),	// u1    output backpressured
	.u1_o_v		(pi_o_v_u1	)	// u1    output valid
);
`else
reg     [A_W+D_W-1:0]   previous_l;
reg     [A_W+D_W-1:0]   previous_r;
reg     [A_W+D_W-1:0]   previous_u0;
reg     [A_W+D_W-1:0]   previous_u1;
integer now=0;



always@(posedge clk)
begin
	now <= now+1;
    if (previous_l!=m_axis_l_wdata )//&& m_axis_l_wready==1'b11 && m_axis_l_wvalid==1'1b1)
    begin
        $display("Time%0d: switching",now-1);
        previous_l <= m_axis_l_wdata;
    end
    if (previous_r!=m_axis_r_wdata )//&& m_axis_l_wready==1'b11 && m_axis_l_wvalid==1'1b1)
    begin
        $display("Time%0d: switching",now-1);
        previous_r <= m_axis_r_wdata;
    end
    if (previous_u0!=m_axis_u0_wdata )//&& m_axis_l_wready==1'b11 && m_axis_l_wvalid==1'1b1)
    begin
        $display("Time%0d: switching",now-1);
        previous_u0 <= m_axis_u0_wdata;
    end
    if (previous_u1!=m_axis_u1_wdata )//&& m_axis_l_wready==1'b11 && m_axis_l_wvalid==1'1b1)
    begin
        $display("Time%0d: switching",now-1);
        previous_u1 <= m_axis_u1_wdata;
    end
end


wire	[A_W+D_W:0]	pi_o_d_l;
wire			pi_o_v_l;
wire			pi_o_b_l;

wire	[A_W+D_W:0]	pi_o_d_r;
wire			pi_o_v_r;
wire			pi_o_b_r;

wire	[A_W+D_W:0]	pi_o_d_u0;
wire			pi_o_v_u0;
wire			pi_o_b_u0;

wire	[A_W+D_W:0]	pi_o_d_u1;
wire			pi_o_v_u1;
wire			pi_o_b_u1;

assign	m_axis_l_wdata	= pi_o_d_l[A_W+D_W-1:0];
assign	m_axis_l_wvalid	= pi_o_v_l;
assign	pi_o_b_l	= ~m_axis_l_wready;
assign	m_axis_l_wlast	= pi_o_d_l[A_W+D_W];

assign	m_axis_r_wdata	= pi_o_d_r[A_W+D_W-1:0];
assign	m_axis_r_wvalid	= pi_o_v_r;
assign	pi_o_b_r	= ~m_axis_r_wready;
assign	m_axis_r_wlast	= pi_o_d_r[A_W+D_W];

assign	m_axis_u0_wdata	= pi_o_d_u0[A_W+D_W-1:0];
assign	m_axis_u0_wvalid= pi_o_v_u0;
assign	pi_o_b_u0	= ~m_axis_u0_wready;
assign	m_axis_u0_wlast	= pi_o_d_u0[A_W+D_W];

assign	m_axis_u1_wdata	= pi_o_d_u1[A_W+D_W-1:0];
assign	m_axis_u1_wvalid= pi_o_v_u1;
assign	pi_o_b_u1	= ~m_axis_u1_wready;
assign	m_axis_u1_wlast	= pi_o_d_u1[A_W+D_W];

pi_switch
#(
	.N		(N	),	
	.WRAP		(WRAP	),
	.A_W		(A_W	),
	.D_W		(D_W	),
	.posl  		(posl	),
	.posx 		(posx	)
)
pi_switch_inst
(
	.clk		(clk		),		// clock
	.rst		(rst		),		// reset
	.ce		(ce		),		// clock enable
	`ifdef SIM
	.done		(done		),	// done
	`endif
	.l_i		(pi_i_d_l	),	// left  input payload
	.l_i_bp		(pi_i_b_l	),	// left  input backpressured
	.l_i_v		(pi_i_v_l	),	// left  input valid
	.r_i		(pi_i_d_r	),	// right input payload
	.r_i_bp		(pi_i_b_r	),	// right input backpressured
	.r_i_v		(pi_i_v_r	),	// right input valid
	.u0_i		(pi_i_d_u0	),	// u0    input payload
	.u0_i_bp	(pi_i_b_u0	),	// u0    input backpressured
	.u0_i_v		(pi_i_v_u0	),	// u0    input valid
	.u1_i		(pi_i_d_u1	),	// u1    input payload
	.u1_i_bp	(pi_i_b_u1	),	// u1    input backpressured
	.u1_i_v		(pi_i_v_u1	),	// u1    input valid
	.l_o		(pi_o_d_l	),	// left  input payload
	.l_o_bp		(pi_o_b_l	),	// left  input backpressured
	.l_o_v		(pi_o_v_l	),	// left  input valid
	.r_o		(pi_o_d_r	),	// right input payload
	.r_o_bp		(pi_o_b_r	),	// right input backpressured
	.r_o_v		(pi_o_v_r	),	// right input valid
	.u0_o		(pi_o_d_u0	),	// u0    input payload
	.u0_o_bp	(pi_o_b_u0	),	// u0    input backpressured
	.u0_o_v		(pi_o_v_u0	),	// u0    input valid
	.u1_o		(pi_o_d_u1	),	// u1    input payload
	.u1_o_bp	(pi_o_b_u1	),	// u1    input backpressured
	.u1_o_v		(pi_o_v_u1	)	// u1    input valid
);

wire	[A_W+D_W:0]	bp_i_d_l;
wire			bp_i_v_l;
wire			bp_i_b_l;

wire	[A_W+D_W:0]	bp_o_d_l;
wire			bp_o_v_l;
wire			bp_o_b_l;

wire	[A_W+D_W:0]	pi_i_d_l;
wire			pi_i_v_l;
wire			pi_i_b_l;

assign	bp_i_v_l	= s_axis_l_wvalid;
assign	bp_i_d_l	= {s_axis_l_wlast, s_axis_l_wdata};
assign	s_axis_l_wready	= ~bp_i_b_l;

assign	pi_i_v_l	= bp_o_v_l;
assign	pi_i_d_l	= bp_o_d_l;
assign	bp_o_b_l	= pi_i_b_l;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_L
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_l	),
	.i_d		(bp_i_d_l	), 
 	.i_b		(bp_i_b_l	),
 	.o_v		(bp_o_v_l	),
	.o_d		(bp_o_d_l	),	 
	.o_b		(bp_o_b_l	) // unregistered from DOR logic
);

wire	[A_W+D_W:0]	bp_i_d_r;
wire			bp_i_v_r;
wire			bp_i_b_r;

wire	[A_W+D_W:0]	bp_o_d_r;
wire			bp_o_v_r;
wire			bp_o_b_r;

wire	[A_W+D_W:0]	pi_i_d_r;
wire			pi_i_v_r;
wire			pi_i_b_r;

assign	bp_i_v_r	= s_axis_r_wvalid;
assign	bp_i_d_r	= {s_axis_r_wlast, s_axis_r_wdata};
assign	s_axis_r_wready	= ~bp_i_b_r;

assign	pi_i_v_r	= bp_o_v_r;
assign	pi_i_d_r	= bp_o_d_r;
assign	bp_o_b_r	= pi_i_b_r;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_R
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_r	),
	.i_d		(bp_i_d_r	), 
 	.i_b		(bp_i_b_r	),
 	.o_v		(bp_o_v_r	),
	.o_d		(bp_o_d_r	),	 
	.o_b		(bp_o_b_r	) // unregistered from DOR logic
);

wire	[A_W+D_W:0]	bp_i_d_u0;
wire			bp_i_v_u0;
wire			bp_i_b_u0;

wire	[A_W+D_W:0]	bp_o_d_u0;
wire			bp_o_v_u0;
wire			bp_o_b_u0;

wire	[A_W+D_W:0]	pi_i_d_u0;
wire			pi_i_v_u0;
wire			pi_i_b_u0;

assign	bp_i_v_u0	= s_axis_u0_wvalid;
assign	bp_i_d_u0	= {s_axis_u0_wlast, s_axis_u0_wdata};
assign	s_axis_u0_wready= ~bp_i_b_u0;

assign	pi_i_v_u0	= bp_o_v_u0;
assign	pi_i_d_u0	= bp_o_d_u0;
assign	bp_o_b_u0	= pi_i_b_u0;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_U0
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_u0	),
	.i_d		(bp_i_d_u0	), 
 	.i_b		(bp_i_b_u0	),
 	.o_v		(bp_o_v_u0	),
	.o_d		(bp_o_d_u0	),	 
	.o_b		(bp_o_b_u0	) // unregistered from DOR logic
);

wire	[A_W+D_W:0]	bp_i_d_u1;
wire			bp_i_v_u1;
wire			bp_i_b_u1;

wire	[A_W+D_W:0]	bp_o_d_u1;
wire			bp_o_v_u1;
wire			bp_o_b_u1;

wire	[A_W+D_W:0]	pi_i_d_u1;
wire			pi_i_v_u1;
wire			pi_i_b_u1;

assign	bp_i_v_u1	= s_axis_u1_wvalid;
assign	bp_i_d_u1	= {s_axis_u1_wlast, s_axis_u1_wdata};
assign	s_axis_u1_wready= ~bp_i_b_u1;

assign	pi_i_v_u1	= bp_o_v_u1;
assign	pi_i_d_u1	= bp_o_d_u1;
assign	bp_o_b_u1	= pi_i_b_u1;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_U1
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_u1	),
	.i_d		(bp_i_d_u1	), 
 	.i_b		(bp_i_b_u1	),
 	.o_v		(bp_o_v_u1	),
	.o_d		(bp_o_d_u1	),	 
	.o_b		(bp_o_b_u1	) // unregistered from DOR logic
);
`endif
endmodule

module pi_switch #(
	parameter N	= 4,		// number of clients
	parameter WRAP	= 1,		// crossbar?
	parameter A_W	= $clog2(N)+1,	// addr width
	parameter D_W	= 32,		// data width
	parameter posl  = 0,		// which level
	parameter posx 	= 0		// which position
) (
	input  wire 			clk,		// clock
	input  wire 			rst,		// reset
	input  wire 			ce,			// clock enable
	
	input  	wire	[A_W+D_W:0] 	l_i	,	// left  input payload
	output	wire			l_i_bp	,	// left  input backpressured
	input	wire			l_i_v	,	// left  input valid
	
	input  	wire	[A_W+D_W:0] 	r_i	,	// right input payload
	output	wire			r_i_bp	,	// right input backpressured
	input	wire			r_i_v	,	// right input valid
	
	input  	wire	[A_W+D_W:0] 	u0_i	,	// u0    input payload
	output	wire			u0_i_bp	,	// u0    input backpressured
	input	wire			u0_i_v	,	// u0    input valid

	input  	wire	[A_W+D_W:0] 	u1_i	,	// u1    input payload
	output	wire			u1_i_bp	,	// u1    input backpressured
	input	wire			u1_i_v	,	// u1    input valid

	output 	wire	[A_W+D_W:0] 	l_o	,	// left  input payload
	input	wire			l_o_bp	,	// left  input backpressured
	output	wire			l_o_v	,	// left  input valid

	output 	wire	[A_W+D_W:0] 	r_o	,	// right input payload
	input	wire			r_o_bp	,	// right input backpressured
	output	wire			r_o_v	,	// right input valid

	output 	wire	[A_W+D_W:0] 	u0_o	,	// u0    input payload
	input	wire			u0_o_bp	,	// u0    input backpressured
	output	wire			u0_o_v	,	// u0    input valid

	output 	wire	[A_W+D_W:0] 	u1_o	,	// u1    input payload
	input	wire			u1_o_bp	,	// u1    input backpressured
	output	wire			u1_o_v	,	// u1    input valid
	output 	wire 			done		// done
);
	wire	[2:0] l_sel;	// left select
	wire	[2:0] r_sel;	// right select
	wire	[2:0] u0_sel;	// up0 select
	wire	[2:0] u1_sel;	// up1 select
	
	wire	[A_W+D_W:0] l_o_c;   // left wire
	wire	[A_W+D_W:0] r_o_c;   // left wire
	wire	[A_W+D_W:0] u0_o_c;  // up0 wire
	wire	[A_W+D_W:0] u1_o_c;  // up1 wire

	reg	[A_W+D_W:0] l_o_r;    // left wire
	reg	[A_W+D_W:0] r_o_r;    // left wire
	reg	[A_W+D_W:0] u0_o_r;   // up0 wire
	reg	[A_W+D_W:0] u1_o_r;   // up1 wire

	wire	[A_W-1:0]	l_i_addr;
	wire	[A_W-1:0]	r_i_addr;
	wire	[A_W-1:0]	u0_i_addr;
	wire	[A_W-1:0]	u1_i_addr;
	
	wire	[D_W-1:0]	l_i_d;
	wire	[D_W-1:0]	r_i_d;
	wire	[D_W-1:0]	u0_i_d;
	wire	[D_W-1:0]	u1_i_d;

	wire			l_o_v_c;
	wire			r_o_v_c;
	wire			u0_o_v_c;
	wire			u1_o_v_c;

	assign	l_i_addr	= l_i[A_W+D_W-1:D_W];
	assign	r_i_addr	= r_i[A_W+D_W-1:D_W];
	assign	u0_i_addr	= u0_i[A_W+D_W-1:D_W];
	assign	u1_i_addr	= u1_i[A_W+D_W-1:D_W];

	assign	l_i_d		= l_i[D_W-1:0];
	assign	r_i_d		= r_i[D_W-1:0];
	assign	u0_i_d		= u0_i[D_W-1:0];
	assign	u1_i_d		= u1_i[D_W-1:0];

	pi_route #(.N(N), .A_W(A_W), .D_W(D_W), .posx(posx), .posl(posl)) 
	r(
		.clk		(clk			), 
		.rst		(rst			), 
		.ce		(ce			), 
		.l_i_v		(l_i_v			),
		.l_i_bp		(l_i_bp			),
		.l_i_addr	(l_i_addr		),
		.l_i_data	(l_i_d			),
		.r_i_v		(r_i_v			),
		.r_i_bp		(r_i_bp			),
		.r_i_addr	(r_i_addr		),
	       	.r_i_data	(r_i_d			),
		.u0_i_v		(u0_i_v			),
		.u0_i_bp	(u0_i_bp		),
		.u0_i_addr 	(u0_i_addr		),
		.u0_i_data	(u0_i_d			),
		.u1_i_v		(u1_i_v			),	
		.u1_i_bp	(u1_i_bp		),	
		.u1_i_addr 	(u1_i_addr		),
		.u1_i_data	(u1_i_d			),
		.l_o_v		(l_o_v_c		), 
		.r_o_v		(r_o_v_c		), 
		.u0_o_v		(u0_o_v_c		), 
		.u1_o_v		(u1_o_v_c		),
		.l_o_bp		(l_o_bp			), 
		.r_o_bp		(r_o_bp			), 
		.u0_o_bp	(u0_o_bp		), 
		.u1_o_bp	(u1_o_bp		),
		.l_sel		(l_sel			),
		.r_sel		(r_sel			),
		.u0_sel		(u0_sel			),
		.u1_sel		(u1_sel			)
	);

		Mux3 #(.W(A_W+D_W)) l_mux(.s(l_sel[1:0]), .i0(r_i), .i1(u0_i), .i2(u1_i), .o(l_o_c));
		Mux3 #(.W(A_W+D_W)) r_mux(.s(r_sel[1:0]), .i0(l_i), .i1(u0_i), .i2(u1_i), .o(r_o_c));

assign	u1_o_c	= r_i;
assign	u0_o_c	= l_i;

reg	l_o_v_r,r_o_v_r,u0_o_v_r,u1_o_v_r;

`ifdef HYPERFLEX
assign	l_o = l_o_c;
assign	r_o = r_o_c;
assign	u0_o = u0_o_c;
assign	u1_o = u1_o_c;
	assign	l_o_v	= l_o_v_c;
	assign	r_o_v	= r_o_v_c;
	assign	u0_o_v	= u0_o_v_c;
	assign	u1_o_v	= u1_o_v_c;
`else	
	always @(posedge clk) begin
		if(rst) begin
			//now	<= 0;
			l_o_r	<= 0;
			r_o_r 	<= 0;
			u0_o_r 	<= 0;
			u1_o_r 	<= 0;
			l_o_v_r	<= 0;
			r_o_v_r	<= 0;
			u0_o_v_r<= 0;
			u1_o_v_r<= 0;
		end else begin
`ifdef DEBUG
			l_o_r 	<= l_sel[2]?{l_o_c}:0;
			r_o_r 	<= r_sel[2]?{r_o_c}:0;
			u0_o_r 	<= u0_sel[2]?{u0_o_c}:0;
			u1_o_r	<= u1_sel[2]?{u1_o_c}:0;

			l_o_v_r	<= l_o_bp ? l_o_v : l_o_v_c;
			r_o_v_r	<= r_o_bp ? r_o_v : r_o_v_c;
			u0_o_v_r<= u0_o_bp ? u0_o_v : u0_o_v_c;
			u1_o_v_r<= u1_o_bp ? u1_o_v : u1_o_v_c;
`endif
`ifndef DEBUG
			if(l_o_bp==1'b0)
			begin
				l_o_r 	<= {l_o_c};
			end
			if(r_o_bp==1'b0)
			begin
			
				r_o_r	<= {r_o_c};
			end
			if(u0_o_bp==1'b0)
			begin
				u0_o_r 	<= {u0_o_c};
			end
			if(u1_o_bp==1'b0)
			begin
				u1_o_r	<= {u1_o_c};
			end
			l_o_v_r	<= l_o_bp ? l_o_v : l_o_v_c;
			r_o_v_r	<= r_o_bp ? r_o_v : r_o_v_c;
			u0_o_v_r<= u0_o_bp ? u0_o_v : u0_o_v_c;
			u1_o_v_r<= u1_o_bp ? u1_o_v : u1_o_v_c;
`endif
		end
	end
		

	assign	l_o_v	= l_o_v_r;
	assign	r_o_v	= r_o_v_r;
	assign	u0_o_v	= u0_o_v_r;
	assign	u1_o_v	= u1_o_v_r;

	assign l_o	= {l_o_r};
	assign r_o	= {r_o_r};
	assign u0_o	= {u0_o_r};
	assign u1_o	= {u1_o_r};
`endif
	`ifdef SIM
	reg done_sig=0;
	always @(posedge clk) begin
		if(~l_i_v & ~r_i_v & ~u0_i_v & ~u1_i_v) begin
			done_sig <= 1;
		end else begin
			done_sig <= 0;
		end
	end
	assign done = done_sig;
	`endif
endmodule

//`include "mux.h"

module t_route #(
	parameter N	= 8,		// number of clients
	parameter A_W	= $clog2(N)+1,	// log number of clients
	parameter D_W	= 32,
	parameter posl  = 0,		// which level
	parameter posx 	= 0		// which position
) (
	input  	wire 			clk		,	// clock
	input  	wire 			rst		,	// reset
	input  	wire 			ce		,	// clock enable
	input  	wire 			l_i_v		,	// left input valid
	input  	wire 			r_i_v		,	// right input valid
	input  	wire 			u0_i_v		,	// up0 input valid
	output  wire 			l_i_bp		,	// left input is backpressured
	output  wire 			r_i_bp		,	// right input is backpressured
	output  wire 			u0_i_bp		,	// up0 input is backpressured
	input  	wire	[A_W-1:0]	l_i_addr	,	// left input addr
	input  	wire	[A_W-1:0] 	r_i_addr	,	// right input addr
	input  	wire 	[A_W-1:0] 	u0_i_addr	, 	// up0 input addr
	input  	wire	[D_W-1:0]	l_i_data	,	// left input addr
	input  	wire	[D_W-1:0] 	r_i_data	,	// right input addr
	input  	wire 	[D_W-1:0] 	u0_i_data	, 	// up0 input addr
	output 	wire			l_o_v		,	// valid for l mux
	output 	wire			r_o_v		,	// valid for r mux
	output 	wire			u0_o_v		,	// valid for u0 mux
	input	wire			l_o_bp		,	// left output is backpressured
	input	wire			r_o_bp		,	// right output is backpressured
	input	wire			u0_o_bp		,	// up0 output is backpressured
	output 	reg	     		l_sel		,	// select for l mux
	output 	reg	     		r_sel		,	// select for r mux
	output 	reg	     		u0_sel			// select for u0 mux
);

wire		l_wins, l_wants_r, l_wants_u0, l_gets_r, l_gets_u0;
wire 		r_wins, r_wants_l, r_wants_u0, r_gets_l, r_gets_u0;
wire 		u0_wins, u0_wants_l, u0_wants_r, u0_gets_l, u0_gets_r;

reg	[1:0]	rr; //0->L, 1->R,2->U0,3->U1

always@(posedge clk)
begin
	if(rst)
	begin
		rr	<= 0;
	end
	else
	begin
		case(rr)
			0:
			begin
				if(r_i_bp)
				begin
					rr	<= 1;
				end
				else if(u0_i_bp)
				begin
					rr	<= 2;
				end
			end
			1:
			begin
				if(u0_i_bp)
				begin
					rr	<= 2;
				end
				else if(l_i_bp)
				begin
					rr	<= 0;
				end
			end
			2:
			begin
				if(l_i_bp)
				begin
					rr	<= 0;
				end
				else if(r_i_bp)
				begin
					rr	<= 1;
				end
			end
		endcase
	end
end


always@*
begin
	case({r_gets_l, u0_gets_l})
		2'b10:
		begin
			l_sel	<= 1'b0;//`RIGHT -3'b001;
		end
		2'b01:
		begin
			l_sel	<= 1'b1;//`U0 -3'b001;
		end
		default:
		begin
			l_sel	<= 1'b0;
		end

	endcase
end

always@*
begin
	case({l_gets_r, u0_gets_r})
		2'b10:
		begin
			r_sel	<= 1'b0;//`LEFT;
		end
		2'b01:
		begin
			r_sel	<= 1'b1;//`U0-3'b001;			
		end
		default:
		begin
			r_sel	<= 1'b0;
		end

	endcase
end

always@*
begin
	case({l_gets_u0, r_gets_u0})
		2'b10:
		begin
			u0_sel	<= 1'b0;
		end
        2'b01:
        begin
            u0_sel  <= 1'b1;
        end
		default:
		begin
			u0_sel	<= 1'b0;
		end

	endcase
end

assign	l_wins	= ( (rr==0) );//| (rr==2 & ~u0_wants_r) | (rr==1 & ~r_wants_u0) ) ;
assign	r_wins	= ( (rr==1) );//| (rr==2 & ~u0_wants_l) | (rr==0 & ~l_wants_u0) ) ;
assign	u0_wins	= ( (rr==2) );//| (rr==0 & ~l_wants_r)  | (rr==1 & ~r_wants_l)  ) ;

assign l_wants_r 	= l_i_v & l_i_addr[posl] & l_i_addr[A_W-1:posl+1]==posx[A_W-1:posl];
assign l_wants_u0 	= l_i_v & l_i_addr[A_W-1:posl+1]!=posx[A_W-1:posl];// & l_i_addr[posl] ;

assign r_wants_l 	= r_i_v & ~r_i_addr[posl] & r_i_addr[A_W-1:posl+1]==posx[A_W-1:posl];
assign r_wants_u0 	= r_i_v & r_i_addr[A_W-1:posl+1]!=posx[A_W-1:posl];// & ~r_i_addr[posl];
	
assign u0_wants_l 	= u0_i_v & ~u0_i_addr[posl];
assign u0_wants_r 	= u0_i_v & u0_i_addr[posl];
	
assign	l_gets_r	= 	(~r_o_bp) & (l_wants_r)  & ( (l_wins)  | (~u0_wants_r) );
assign	u0_gets_r	= 	(~r_o_bp) & (u0_wants_r) & ( (u0_wins) | (~l_wants_r ) );
				
assign	r_gets_l	= 	(~l_o_bp) & (r_wants_l)  & ( (r_wins)  | (~u0_wants_l) );
assign	u0_gets_l	= 	(~l_o_bp) & (u0_wants_l) & ( (u0_wins) | (~r_wants_l ) );

assign	l_gets_u0	= 	(~u0_o_bp) & (l_wants_u0) & ( (l_wins) | (~r_wants_u0) ) ;
assign	r_gets_u0	= 	(~u0_o_bp) & (r_wants_u0) & ( (r_wins) | (~l_wants_u0) ) ;


assign	l_i_bp		=	(l_wants_r  & ~l_gets_r)  | (l_wants_u0 & ~l_gets_u0) ;
assign	r_i_bp		=	(r_wants_l  & ~r_gets_l)  | (r_wants_u0 & ~r_gets_u0);
assign	u0_i_bp		=	(u0_wants_l & ~u0_gets_l) | (u0_wants_r & ~u0_gets_r) ;

assign	l_o_v		=	r_gets_l  | u0_gets_l ;
assign	r_o_v		=	l_gets_r  | u0_gets_r ;
assign	u0_o_v		=	l_gets_u0 | r_gets_u0 ;

endmodule

module t_switch_top
#
(
	parameter	N	= 4,			//number of clients
	parameter	WRAP	= 1,			//crossbar?
	parameter	A_W	= $clog2(N) + 1, 	//addr width
	parameter	D_W	= 32,			//data width
	parameter	posl	= 0,			//which level
	parameter	posx	= 0,		//which position
	parameter	DEBUG	= 1,
	parameter	FD	= 32,
	parameter	HR	= 4
)
(
	input  wire 			clk,		// clock
	input  wire 			rst,		// reset
	input  wire 			ce,		// clock enable
	
	input  	wire	[A_W+D_W-1:0] 	s_axis_l_wdata	,	
	output	wire			s_axis_l_wready	,
	input	wire			s_axis_l_wvalid	,
	input	wire			s_axis_l_wlast	,
	
	input  	wire	[A_W+D_W-1:0] 	s_axis_r_wdata	,
	output	wire			s_axis_r_wready	,
	input	wire			s_axis_r_wvalid	,
	input	wire			s_axis_r_wlast	,
	
	input  	wire	[A_W+D_W-1:0] 	s_axis_u0_wdata	,
	output	wire			s_axis_u0_wready, 
	input	wire			s_axis_u0_wvalid, 
	input	wire			s_axis_u0_wlast	,

	output 	wire	[A_W+D_W-1:0] 	m_axis_l_wdata	,
	input	wire			m_axis_l_wready	,
	output	wire			m_axis_l_wvalid	,
	output	wire			m_axis_l_wlast	,	

	output 	wire	[A_W+D_W-1:0] 	m_axis_r_wdata	,
	input	wire			m_axis_r_wready	,
	output	wire			m_axis_r_wvalid	,
	output	wire			m_axis_r_wlast	,	

	output 	wire	[A_W+D_W-1:0] 	m_axis_u0_wdata	,
	input	wire			m_axis_u0_wready,
	output	wire			m_axis_u0_wvalid,
	output	wire			m_axis_u0_wlast	,	

	output 	wire 			done		// done
);
`ifdef HYPERFLEX

reg	[A_W+D_W:0]	s_axis_l_wdata_hr	[HR-1:0];
reg			s_axis_l_wvalid_hr	[HR-1:0];
reg			s_axis_l_wready_hr	[HR-1:0];

wire	[A_W+D_W:0]	t_o_d_l;
wire			t_o_v_l;
wire			t_o_b_l;

assign	m_axis_l_wdata	= t_o_d_l[A_W+D_W-1:0];
assign	m_axis_l_wvalid	= t_o_v_l;
assign	t_o_b_l	= ~m_axis_l_wready;
assign	m_axis_l_wlast	= t_o_d_l[A_W+D_W];

assign	s_axis_l_wready	= s_axis_l_wready_hr[HR-1];

integer hr_l;
integer now=0;

always@(posedge clk)
begin
	now <= now + 1;
	s_axis_l_wdata_hr[0]	<= {s_axis_l_wlast,s_axis_l_wdata};
	s_axis_l_wvalid_hr[0]	<= s_axis_l_wvalid;
	s_axis_l_wready_hr[0]	<= ~l_fifo_full;
	for(hr_l=0;hr_l<HR-1;hr_l=hr_l+1)
	begin
		s_axis_l_wdata_hr[hr_l+1]	<= s_axis_l_wdata_hr[hr_l];
		s_axis_l_wvalid_hr[hr_l+1]	<= s_axis_l_wvalid_hr[hr_l];
		s_axis_l_wready_hr[hr_l+1]	<= s_axis_l_wready_hr[hr_l];
	end

end


wire			l_fifo_empty;
wire			l_fifo_done;
wire			l_fifo_full;

wire	[A_W+D_W:0]	t_i_d_l;
wire			t_i_v_l;
wire			t_i_bp_l;


`ifdef SIM
fwft_fifo 
#(
	.fifo_dw	(A_W+D_W+1),
	.fifo_depth	(FD+2*HR),
	.LOC		("w"),
	.HR		(HR)
)
l_fifo
(
	.clk		(clk				),
	.rst		(rst				),
	.d_in		(s_axis_l_wdata_hr[HR-1]	),//
	.wr_en		(s_axis_l_wvalid_hr[HR-1]	),//
	.full_early	(l_fifo_full			),//
	.d_out		(t_i_d_l			),//
	.d_valid_out	(t_i_v_l			),//
	.rd_en		(~t_i_bp_l & ~l_fifo_empty	),//
	.empty		(l_fifo_empty			),//
	.done		(l_fifo_done			) //
);
`endif
`ifdef XLNXSRLFIFO
fifo_generator_1 l_fifo
(
	.clk		(clk				),
	.srst		(rst				),
	.din		({s_axis_l_wvalid,s_axis_l_wdata_hr[HR-1]}	),//
	.wr_en		(s_axis_l_wvalid_hr[HR-1]	),//
	.full		(l_fifo_full			),//
	.dout		({t_i_v_l,t_i_d_l}			),//
	.rd_en		(~t_i_bp_l & ~l_fifo_empty	),//
	.empty		(l_fifo_empty			)//
//	.done		(l_fifo_done			) //
);
`endif

reg	[A_W+D_W:0]	s_axis_r_wdata_hr	[HR-1:0];
reg			s_axis_r_wvalid_hr	[HR-1:0];
reg			s_axis_r_wready_hr	[HR-1:0];

wire	[A_W+D_W:0]	t_o_d_r;
wire			t_o_v_r;
wire			t_o_b_r;

assign	m_axis_r_wdata	= t_o_d_r[A_W+D_W-1:0];
assign	m_axis_r_wvalid	= t_o_v_r;
assign	t_o_b_r	= ~m_axis_r_wready;
assign	m_axis_r_wlast	= t_o_d_r[A_W+D_W];

assign	s_axis_r_wready	= s_axis_r_wready_hr[HR-1];

integer hr_r;

always@(posedge clk)
begin
	s_axis_r_wdata_hr[0]	<= {s_axis_r_wlast,s_axis_r_wdata};
	s_axis_r_wvalid_hr[0]	<= s_axis_r_wvalid;
	s_axis_r_wready_hr[0]	<= ~r_fifo_full;
	for(hr_r=0;hr_r<HR-1;hr_r=hr_r+1)
	begin
		s_axis_r_wdata_hr[hr_r+1]	<= s_axis_r_wdata_hr[hr_r];
		s_axis_r_wvalid_hr[hr_r+1]	<= s_axis_r_wvalid_hr[hr_r];
		s_axis_r_wready_hr[hr_r+1]	<= s_axis_r_wready_hr[hr_r];
	end

end


wire			r_fifo_empty;
wire			r_fifo_done;
wire			r_fifo_full;

wire	[A_W+D_W:0]	t_i_d_r;
wire			t_i_v_r;
wire			t_i_bp_r;

`ifdef SIM
fwft_fifo 
#(
	.fifo_dw	(A_W+D_W+1),
	.fifo_depth	(FD+2*HR),
	.LOC		("w"),
	.HR		(HR)
)
r_fifo
(
	.clk		(clk				),
	.rst		(rst				),
	.d_in		(s_axis_r_wdata_hr[HR-1]	),//
	.wr_en		(s_axis_r_wvalid_hr[HR-1]	),//
	.full_early		(r_fifo_full			),//
	.d_out		(t_i_d_r			),//
	.d_valid_out	(t_i_v_r			),//
	.rd_en		(~t_i_bp_r & ~r_fifo_empty	),//
	.empty		(r_fifo_empty			),//
	.done		(r_fifo_done			) //
);
`endif
`ifdef XLNXSRLFIFO

fifo_generator_1 r_fifo
(
	.clk		(clk				),
	.srst		(rst				),
	.din		({s_axis_r_wvalid,s_axis_r_wdata_hr[HR-1]}	),//
	.wr_en		(s_axis_r_wvalid_hr[HR-1]	),//
	.full		(r_fifo_full			),//
	.dout		({t_i_v_r,t_i_d_r}			),//
	.rd_en		(~t_i_bp_r & ~r_fifo_empty	),//
	.empty		(r_fifo_empty			)//
//	.done		(r_fifo_done			) //
);
`endif

reg	[A_W+D_W:0]	s_axis_u0_wdata_hr	[HR-1:0];
reg			s_axis_u0_wvalid_hr	[HR-1:0];
reg			s_axis_u0_wready_hr	[HR-1:0];

wire	[A_W+D_W:0]	t_o_d_u0;
wire			t_o_v_u0;
wire			t_o_b_u0;

assign	m_axis_u0_wdata	= t_o_d_u0[A_W+D_W-1:0];
assign	m_axis_u0_wvalid= t_o_v_u0;
assign	t_o_b_u0	= ~m_axis_u0_wready;
assign	m_axis_u0_wlast	= t_o_d_u0[A_W+D_W];

assign	s_axis_u0_wready= s_axis_u0_wready_hr[HR-1];

integer hr_u0;

always@(posedge clk)
begin
	s_axis_u0_wdata_hr[0]	<= {s_axis_u0_wlast,s_axis_u0_wdata};
	s_axis_u0_wvalid_hr[0]	<= s_axis_u0_wvalid;
	s_axis_u0_wready_hr[0]	<= ~u0_fifo_full;
	for(hr_u0=0;hr_u0<HR-1;hr_u0=hr_u0+1)
	begin
		s_axis_u0_wdata_hr[hr_u0+1]	<= s_axis_u0_wdata_hr[hr_u0];
		s_axis_u0_wvalid_hr[hr_u0+1]	<= s_axis_u0_wvalid_hr[hr_u0];
		s_axis_u0_wready_hr[hr_u0+1]	<= s_axis_u0_wready_hr[hr_u0];
	end

end


wire			u0_fifo_empty;
wire			u0_fifo_done;
wire			u0_fifo_full;

wire	[A_W+D_W:0]	t_i_d_u0;
wire			t_i_v_u0;
wire			t_i_bp_u0;

`ifdef SIM
fwft_fifo 
#(
	.fifo_dw	(A_W+D_W+1),
	.fifo_depth	(FD+2*HR),
	.LOC		("w"),
	.HR		(HR)
)
u0_fifo
(
	.clk		(clk				),
	.rst		(rst				),
	.d_in		(s_axis_u0_wdata_hr[HR-1]	),//
	.wr_en		(s_axis_u0_wvalid_hr[HR-1]	),//
	.full_early	(u0_fifo_full			),//
	.d_out		(t_i_d_u0			),//
	.d_valid_out	(t_i_v_u0			),//
	.rd_en		(~t_i_bp_u0 & ~u0_fifo_empty	),//
	.empty		(u0_fifo_empty			),//
	.done		(u0_fifo_done			) //
);
`endif
`ifdef XLNXSRLFIFO
fifo_generator_1 u0_fifo
(
	.clk		(clk				),
	.srst		(rst				),
	.din		({s_axis_u0_wvalid,s_axis_u0_wdata_hr[HR-1]}	),//
	.wr_en		(s_axis_u0_wvalid_hr[HR-1]	),//
	.full		(u0_fifo_full			),//
	.dout		({t_i_v_u0,t_i_d_u0}			),//
	.rd_en		(~t_i_bp_u0 & ~u0_fifo_empty	),//
	.empty		(u0_fifo_empty			)//
//	.done		(u0_fifo_done			) //
);
`endif
t_switch
#(
	.N		(N	),	
	.WRAP		(WRAP	),
	.A_W		(A_W	),
	.D_W		(D_W	),
	.posl  		(posl	),
	.posx 		(posx	)
)
t_switch_inst
(
	.clk		(clk		),		// clock
	.rst		(rst		),		// reset
	.ce		(ce		),		// clock enable
	`ifdef SIM
	.done		(done		),	// done
	`endif
	.l_i		(t_i_d_l	),	// left  input payload
	.l_i_bp		(t_i_bp_l	),	// left  input backpressured
	.l_i_v		(t_i_v_l	),	// left  input valid
	.r_i		(t_i_d_r	),	// right input payload
	.r_i_bp		(t_i_bp_r	),	// right input backpressured
	.r_i_v		(t_i_v_r	),	// right input valid
	.u0_i		(t_i_d_u0	),	// u0    input payload
	.u0_i_bp	(t_i_bp_u0	),	// u0    input backpressured
	.u0_i_v		(t_i_v_u0	),	// u0    input valid
	.l_o		(t_o_d_l	),	// left  input payload
	.l_o_bp		(t_o_b_l	),	// left  input backpressured
	.l_o_v		(t_o_v_l	),	// left  input valid
	.r_o		(t_o_d_r	),	// right input payload
	.r_o_bp		(t_o_b_r	),	// right input backpressured
	.r_o_v		(t_o_v_r	),	// right input valid
	.u0_o		(t_o_d_u0	),	// u0    input payload
	.u0_o_bp	(t_o_b_u0	),	// u0    input backpressured
	.u0_o_v		(t_o_v_u0	)	// u0    input valid
);
`else

reg     [A_W+D_W-1:0]   previous_l;
reg     [A_W+D_W-1:0]   previous_r;
reg     [A_W+D_W-1:0]   previous_u0;
integer now=0;



always@(posedge clk)
begin
	now <= now+1;
    if (previous_l!=m_axis_l_wdata )//&& m_axis_l_wready==1'b11 && m_axis_l_wvalid==1'1b1)
    begin
        $display("Time%0d: switching",now-1);
        previous_l <= m_axis_l_wdata;
    end
    if (previous_r!=m_axis_r_wdata )//&& m_axis_l_wready==1'b11 && m_axis_l_wvalid==1'1b1)
    begin
        $display("Time%0d: switching",now-1);
        previous_r <= m_axis_r_wdata;
    end
    if (previous_u0!=m_axis_u0_wdata )//&& m_axis_l_wready==1'b11 && m_axis_l_wvalid==1'1b1)
    begin
        $display("Time%0d: switching",now-1);
        previous_u0 <= m_axis_u0_wdata;
    end
end
wire	[A_W+D_W:0]	t_o_d_l;
wire			t_o_v_l;
wire			t_o_b_l;

wire	[A_W+D_W:0]	t_o_d_r;
wire			t_o_v_r;
wire			t_o_b_r;

wire	[A_W+D_W:0]	t_o_d_u0;
wire			t_o_v_u0;
wire			t_o_b_u0;

assign	m_axis_l_wdata		= t_o_d_l[A_W+D_W-1:0];
assign	m_axis_l_wvalid		= t_o_v_l;
assign	m_axis_l_wlast		= t_o_d_l[A_W+D_W];
assign	t_o_b_l			= ~m_axis_l_wready;

assign	m_axis_r_wdata		= t_o_d_r[A_W+D_W-1:0];
assign	m_axis_r_wvalid		= t_o_v_r;
assign	m_axis_r_wlast		= t_o_d_r[A_W+D_W];
assign	t_o_b_r			= ~m_axis_r_wready;

assign	m_axis_u0_wdata		= t_o_d_u0[A_W+D_W-1:0];
assign	m_axis_u0_wvalid	= t_o_v_u0;
assign	m_axis_u0_wlast		= t_o_d_u0[A_W+D_W];
assign	t_o_b_u0		= ~m_axis_u0_wready;

t_switch
#(
	.N		(N	),	
	.WRAP		(WRAP	),
	.A_W		(A_W	),
	.D_W		(D_W	),
	.posl  		(posl	),
	.posx 		(posx	)
)
t_switch_inst
(
	.clk		(clk		),		// clock
	.rst		(rst		),		// reset
	.ce		(ce		),		// clock enable
	`ifdef SIM
	.done		(done		),	// done
	`endif
	.l_i		(t_i_d_l	),	// left  input payload
	.l_i_bp		(t_i_b_l	),	// left  input backpressured
	.l_i_v		(t_i_v_l	),	// left  input valid
	.r_i		(t_i_d_r	),	// right input payload
	.r_i_bp		(t_i_b_r	),	// right input backpressured
	.r_i_v		(t_i_v_r	),	// right input valid
	.u0_i		(t_i_d_u0	),	// u0    input payload
	.u0_i_bp	(t_i_b_u0	),	// u0    input backpressured
	.u0_i_v		(t_i_v_u0	),	// u0    input valid
	.l_o		(t_o_d_l	),	// left  input payload
	.l_o_bp		(t_o_b_l	),	// left  input backpressured
	.l_o_v		(t_o_v_l	),	// left  input valid
	.r_o		(t_o_d_r	),	// right input payload
	.r_o_bp		(t_o_b_r	),	// right input backpressured
	.r_o_v		(t_o_v_r	),	// right input valid
	.u0_o		(t_o_d_u0	),	// u0    input payload
	.u0_o_bp	(t_o_b_u0	),	// u0    input backpressured
	.u0_o_v		(t_o_v_u0	)	// u0    input valid
);

wire	[A_W+D_W:0]	bp_i_d_l;
wire			bp_i_v_l;
wire			bp_i_b_l;

wire	[A_W+D_W:0]	bp_o_d_l;
wire			bp_o_v_l;
wire			bp_o_b_l;

wire	[A_W+D_W:0]	t_i_d_l;
wire			t_i_v_l;
wire			t_i_b_l;

assign	bp_i_v_l	= s_axis_l_wvalid;
assign	bp_i_d_l	= {s_axis_l_wlast, s_axis_l_wdata};
assign	s_axis_l_wready	= ~bp_i_b_l;

assign	t_i_v_l		= bp_o_v_l;
assign	t_i_d_l		= bp_o_d_l;
assign	bp_o_b_l	= t_i_b_l;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_L
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_l	),
	.i_d		(bp_i_d_l	), 
 	.i_b		(bp_i_b_l	),
 	.o_v		(bp_o_v_l	),
	.o_d		(bp_o_d_l	),	 
	.o_b		(bp_o_b_l	) // unregistered from DOR logic
);

wire	[A_W+D_W:0]	bp_i_d_r;
wire			bp_i_v_r;
wire			bp_i_b_r;

wire	[A_W+D_W:0]	bp_o_d_r;
wire			bp_o_v_r;
wire			bp_o_b_r;

wire	[A_W+D_W:0]	t_i_d_r;
wire			t_i_v_r;
wire			t_i_b_r;

assign	bp_i_v_r	= s_axis_r_wvalid;
assign	bp_i_d_r	= {s_axis_r_wlast, s_axis_r_wdata};
assign	s_axis_r_wready	= ~bp_i_b_r;

assign	t_i_v_r		= bp_o_v_r;
assign	t_i_d_r		= bp_o_d_r;
assign	bp_o_b_r	= t_i_b_r;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_R
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_r	),
	.i_d		(bp_i_d_r	), 
 	.i_b		(bp_i_b_r	),
 	.o_v		(bp_o_v_r	),
	.o_d		(bp_o_d_r	),	 
	.o_b		(bp_o_b_r	) // unregistered from DOR logic
);

wire	[A_W+D_W:0]	bp_i_d_u0;
wire			bp_i_v_u0;
wire			bp_i_b_u0;

wire	[A_W+D_W:0]	bp_o_d_u0;
wire			bp_o_v_u0;
wire			bp_o_b_u0;

wire	[A_W+D_W:0]	t_i_d_u0;
wire			t_i_v_u0;
wire			t_i_b_u0;

assign	bp_i_v_u0	= s_axis_u0_wvalid;
assign	bp_i_d_u0	= {s_axis_u0_wlast, s_axis_u0_wdata};
assign	s_axis_u0_wready= ~bp_i_b_u0;

assign	t_i_v_u0	= bp_o_v_u0;
assign	t_i_d_u0	= bp_o_d_u0;
assign	bp_o_b_u0	= t_i_b_u0;

shadow_reg_combi
#(
	.D_W		(D_W	),
	.A_W		(A_W	)
)
bp_U0
(
	.clk		(clk		), 
	.rst		(rst		), 
	.i_v		(bp_i_v_u0	),
	.i_d		(bp_i_d_u0	), 
 	.i_b		(bp_i_b_u0	),
 	.o_v		(bp_o_v_u0	),
	.o_d		(bp_o_d_u0	),	 
	.o_b		(bp_o_b_u0	) // unregistered from DOR logic
);

`endif
endmodule

module t_switch #(
	parameter N	= 4,		// number of clients
	parameter WRAP	= 1,		// crossbar?
	parameter A_W	= $clog2(N)+1,	// addr width
	parameter D_W	= 32,		// data width
	parameter posl  = 0,		// which level
	parameter posx 	= 0		// which position
) (
	input 	wire			clk	,	// clock
	input  	wire 			rst	,	// reset
	input  	wire 			ce	,	// clock enable

	input  	wire 	[A_W+D_W:0] 	l_i	,	// left input
	output	wire			l_i_bp	,	// left  input backpressured
	input	wire			l_i_v	,	// left  input valid
	
	input  	wire	[A_W+D_W:0] 	r_i	,	// right input payload
	output	wire			r_i_bp	,	// right input backpressured
	input	wire			r_i_v	,	// right input valid
	
	input  	wire	[A_W+D_W:0] 	u0_i	,	// u0    input payload
	output	wire			u0_i_bp	,	// u0    input backpressured
	input	wire			u0_i_v	,	// u0    input valid
	
	output 	wire	[A_W+D_W:0] 	l_o	,	// left  input payload
	input	wire			l_o_bp	,	// left  input backpressured
	output	wire			l_o_v	,	// left  input valid

	output 	wire	[A_W+D_W:0] 	r_o	,	// right input payload
	input	wire			r_o_bp	,	// right input backpressured
	output	wire			r_o_v	,	// right input valid

	output 	wire	[A_W+D_W:0] 	u0_o	,	// u0    input payload
	input	wire			u0_o_bp	,	// u0    input backpressured
	output	wire			u0_o_v	,	// u0    input valid

	output	wire			done
);
	
	wire	 	l_sel;		// left select
	wire	 	r_sel;		// right select
	wire 	 	u0_sel;		// up0 select

	wire 	[A_W+D_W:0] 	l_o_c;	// left wire
	wire 	[A_W+D_W:0] 	r_o_c;	// left wire
	wire 	[A_W+D_W:0] 	u0_o_c;	// up0 wire

	wire			l_o_v_c;
	wire			r_o_v_c;
	wire			u0_o_v_c;

	reg 	[A_W+D_W:0] 	l_o_r;	// left wire
	reg 	[A_W+D_W:0] 	r_o_r;	// left wire
	reg 	[A_W+D_W:0] 	u0_o_r; // up0 wire

	wire 	[A_W-1:0] 	l_i_addr;	// left address
	wire 	[A_W-1:0] 	r_i_addr;	// right address
	wire 	[A_W-1:0] 	u0_i_addr;	// up0 address

	wire	[D_W-1:0] 	l_i_d;		// left data
	wire 	[D_W-1:0] 	r_i_d;		// right data
	wire 	[D_W-1:0] 	u0_i_d;		// up0 data

	assign 	l_i_addr 	= l_i[A_W+D_W-1:D_W];
	assign 	r_i_addr 	= r_i[A_W+D_W-1:D_W];
	assign 	u0_i_addr 	= u0_i[A_W+D_W-1:D_W];

	assign 	l_i_d 		= l_i[D_W-1:0];
	assign 	r_i_d 		= r_i[D_W-1:0];
	assign 	u0_i_d 		= u0_i[D_W-1:0];

	t_route #(.N(N), .A_W(A_W), .D_W(D_W),.posx(posx), .posl(posl)) 
	r( 
		.clk		(clk			), 
		.rst		(rst			), 
		.ce		(ce			), 
		.l_i_v		(l_i_v			),
		.l_i_bp		(l_i_bp			),
		.l_i_addr	(l_i_addr		),
		.r_i_v		(r_i_v			),
		.r_i_bp		(r_i_bp			),
		.r_i_addr	(r_i_addr		),
		.u0_i_v		(u0_i_v			),
		.u0_i_bp	(u0_i_bp		),
		.u0_i_addr 	(u0_i_addr		),
		`ifdef SIM
		.u0_i_data	(u0_i_d			),
	       	.r_i_data	(r_i_d			),
		.l_i_data	(l_i_d			),
		`endif
		.l_o_v		(l_o_v_c		), 
		.r_o_v		(r_o_v_c		), 
		.u0_o_v		(u0_o_v_c		), 
		.l_o_bp		(l_o_bp			), 
		.r_o_bp		(r_o_bp			), 
		.u0_o_bp	(u0_o_bp		), 
		.l_sel		(l_sel			),
		.r_sel		(r_sel			),
		.u0_sel		(u0_sel			)
	);

		Mux2 #(.W(A_W+D_W)) l_mux(.s(l_sel), .i0(r_i), .i1(u0_i), .o(l_o_c));
		Mux2 #(.W(A_W+D_W)) r_mux(.s(r_sel), .i0(l_i), .i1(u0_i), .o(r_o_c));
		Mux2 #(.W(A_W+D_W)) u0_mux(.s(u0_sel), .i0(l_i), .i1(r_i), .o(u0_o_c));

reg	l_o_v_r,r_o_v_r,u0_o_v_r;

`ifdef HYPERFLEX
assign	l_o = l_o_c;
assign	r_o = r_o_c;
assign	u0_o = u0_o_c;
	assign	l_o_v	= l_o_v_c;
	assign	r_o_v	= r_o_v_c;
	assign	u0_o_v	= u0_o_v_c;
`else	
	always @(posedge clk) begin
		if(rst) begin
			l_o_r 	<= 0;
			r_o_r 	<= 0;
			u0_o_r 	<= 0;
			l_o_v_r	<= 0;
			r_o_v_r	<= 0;
			u0_o_v_r<= 0;
		end else begin
`ifdef DEBUG
			l_o_r 	<= l_sel[2]?{l_o_c}:0;
			r_o_r 	<= r_sel[2]?{r_o_c}:0;
			u0_o_r 	<= u0_sel[2]?{u0_o_c}:0;

			l_o_v_r	<= l_o_bp ? l_o_v : l_o_v_c;
			r_o_v_r	<= r_o_bp ? r_o_v : r_o_v_c;
			u0_o_v_r<= u0_o_bp ? u0_o_v : u0_o_v_c;
`endif
`ifndef DEBUG
            if(l_o_bp==1'b0)
            begin
			    l_o_r 	<= {l_o_c};
            end
            if(r_o_bp==1'b0)
            begin
			    r_o_r 	<= {r_o_c};
            end
            if(u0_o_bp==1'b0)
            begin
			    u0_o_r 	<= {u0_o_c};
            end

			l_o_v_r	<= l_o_bp ? l_o_v : l_o_v_c;
			r_o_v_r	<= r_o_bp ? r_o_v : r_o_v_c;
			u0_o_v_r<= u0_o_bp ? u0_o_v : u0_o_v_c;
`endif
		end
	end
			
	assign l_o 	= {l_o_r};
	assign r_o 	= {r_o_r};
	assign u0_o 	= {u0_o_r};
	
	assign	l_o_v	= l_o_v_r;
	assign	r_o_v	= r_o_v_r;
	assign	u0_o_v	= u0_o_v_r;
`endif
	reg done_sig=0;
	always @(posedge clk) begin
		if(~l_i_v & ~r_i_v & ~u0_i_v) begin
			done_sig <= 1;
		end else begin
			done_sig <= 0;
		end
	end
        assign done = done_sig;
endmodule
