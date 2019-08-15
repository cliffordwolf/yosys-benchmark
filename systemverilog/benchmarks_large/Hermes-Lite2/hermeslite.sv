//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.
// Steve Haynal KF7O 2018


//-----------------------------------------------------------------------------
// transfer signal to another clock domain
//-----------------------------------------------------------------------------
module sync (
  input clock,
  input sig_in,
  output sig_out
);

parameter DEPTH = 2;

(*preserve*) reg [DEPTH-1:0] sync_chain = {DEPTH{1'b0}};

always @(posedge clock)
  sync_chain <= {sig_in, sync_chain[DEPTH-1:1]};

assign sig_out = sync_chain[0];

endmodule


//-----------------------------------------------------------------------------
// transfer change as pulse to another domain
//-----------------------------------------------------------------------------
module sync_pulse (
  input clock,
  input sig_in,
  output sig_out
);

parameter DEPTH = 3;

(*preserve*) reg [DEPTH-1:0] sync_chain = {DEPTH{1'b0}};

always @(posedge clock)
  sync_chain <= {sig_in, sync_chain[DEPTH-1:1]};

assign sig_out = sync_chain[0] ^ sync_chain[1];

endmodule
// OpenHPSDR downstream (PC->Card) protocol unpacker

module dsopenhpsdr1 (
  clk,
  eth_port,
  eth_broadcast,
  eth_valid,
  eth_data,
  eth_unreachable,
  eth_metis_discovery,

  run,
  wide_spectrum,

  watchdog_up,
  
  cmd_addr,
  cmd_data,
  cmd_cnt,
  cmd_ptt,
  cmd_resprqst,

  dseth_tdata,
  dsethiq_tvalid,
  dsethiq_tlast,
  dsethlr_tvalid,
  dsethlr_tlast,

  dsethasmi_tvalid,
  dsethasmi_tlast,
  asmi_cnt,
  dsethasmi_erase,
  dsethasmi_erase_ack
);

input               clk;

input   [15:0]      eth_port;
input               eth_broadcast;
input               eth_valid;
input   [ 7:0]      eth_data;
input               eth_unreachable;
output logic        eth_metis_discovery;

output logic        run = 1'b0;
output logic        wide_spectrum = 1'b0;

input               watchdog_up;

output logic  [5:0] cmd_addr = 6'h0;
output logic [31:0] cmd_data = 32'h00;
output logic        cmd_cnt = 1'b0;
output logic        cmd_ptt = 1'b0;
output logic        cmd_resprqst = 1'b0;

output logic  [7:0] dseth_tdata;
output logic        dsethiq_tvalid;
output logic        dsethiq_tlast;
output logic        dsethlr_tvalid;
output logic        dsethlr_tlast;
output logic        dsethasmi_tvalid;
output logic        dsethasmi_tlast;
output logic [13:0] asmi_cnt = 14'h000;
output logic        dsethasmi_erase;
input               dsethasmi_erase_ack;


localparam START        = 'h00,
           PREAMBLE     = 'h01,
           DECODE       = 'h02,
           RUNSTOP      = 'h03,
           DISCOVERY    = 'h04,
           ENDPOINT     = 'h05,
           SEQNO3       = 'h06,
           SEQNO2       = 'h07,
           SEQNO1       = 'h08,           
           SEQNO0       = 'h09,
           ASMI_DECODE  = 'h2a,
           ASMI_CNT3    = 'h2b,
           ASMI_CNT2    = 'h2c,
           ASMI_CNT1    = 'h2d,
           ASMI_CNT0    = 'h2e,                                 
           ASMI_PROGRAM = 'h2f,
           ASMI_ERASE   = 'h20,
           SYNC2        = 'h10,
           SYNC1        = 'h11,
           SYNC0        = 'h12,
           CMDCTRL      = 'h13,
           CMDDATA3     = 'h14,
           CMDDATA2     = 'h15,
           CMDDATA1     = 'h16,
           CMDDATA0     = 'h17,
           PUSHL1       = 'h18,
           PUSHL0       = 'h19,
           PUSHR1       = 'h1a,
           PUSHR0       = 'h1b,
           PUSHI1       = 'h1c,
           PUSHI0       = 'h1d,
           PUSHQ1       = 'h1e,
           PUSHQ0       = 'h1f;


logic   [ 5:0]  state = START;
logic   [ 5:0]  state_next;

logic   [ 7:0]  pushcnt = 8'h00;
logic   [ 7:0]  pushcnt_next; 

//logic           framecnt = 1'b0;
//logic           framecnt_next; 

logic           run_next;
logic           wide_spectrum_next;

logic   [5:0]   cmd_addr_next;
logic   [31:0]  cmd_data_next;
logic           cmd_cnt_next;
logic           cmd_ptt_next;
logic           cmd_resprqst_next;

logic           watchdog_clr;

logic   [ 9:0]  watchdog_cnt = 10'h00;

logic   [13:0]  asmi_cnt_next;

// State
always @ (posedge clk) begin
  pushcnt <= pushcnt_next;
  //framecnt <= framecnt_next;
  cmd_resprqst <= cmd_resprqst_next;
  cmd_addr <= cmd_addr_next;
  cmd_ptt <= cmd_ptt_next;
  cmd_data <= cmd_data_next;
  cmd_cnt <= cmd_cnt_next; 
  asmi_cnt <= asmi_cnt_next; 
  if ((eth_unreachable) | &watchdog_cnt) begin
    state <= START;
    run <= 1'b0;
    wide_spectrum <= 1'b0;
  end else if (~eth_valid) begin
    state <= START;
  end else begin
    state <= state_next;
    run <= run_next;
    wide_spectrum <= wide_spectrum_next;
  end
end

// FSM Combinational
always @* begin

  // Next State
  state_next = START;
  run_next = run;
  wide_spectrum_next = wide_spectrum;
  pushcnt_next = pushcnt;
  //framecnt_next = framecnt;
  cmd_resprqst_next = cmd_resprqst;
  cmd_addr_next = cmd_addr;
  cmd_ptt_next = cmd_ptt;
  cmd_data_next = cmd_data;
  cmd_cnt_next = cmd_cnt;
  asmi_cnt_next = asmi_cnt;

  // Combinational output
  eth_metis_discovery = 1'b0;
  dsethiq_tvalid = 1'b0;
  dsethlr_tvalid = 1'b0;
  watchdog_clr   = 1'b0;
  dsethiq_tlast  = 1'b0;
  dsethlr_tlast  = 1'b0;

  dsethasmi_tvalid = 1'b0;
  dsethasmi_tlast  = 1'b0;
  dsethasmi_erase  = 1'b0;

  case (state)
    START: begin
      //framecnt_next = 1'b0;
      if ((eth_data == 8'hef) & (eth_port == 1024)) state_next = PREAMBLE;
    end

    PREAMBLE: begin
      if ((eth_data == 8'hfe) & (eth_port == 1024)) state_next = DECODE;
    end

    DECODE: begin
      if (eth_data == 8'h01) state_next = ENDPOINT;
      else if (eth_data == 8'h04) state_next = RUNSTOP;
      else if ((eth_data == 8'h02) & eth_broadcast) state_next = DISCOVERY;
      else if (eth_data == 8'h03) state_next = ASMI_DECODE;
    end

    RUNSTOP: begin
      run_next = eth_data[0];
      wide_spectrum_next = eth_data[1];
    end

    DISCOVERY: begin
      eth_metis_discovery = 1'b1;
    end

    ASMI_DECODE: begin
      pushcnt_next = 8'h00;
      if (eth_data == 8'h01) state_next = ASMI_CNT3;
      else if (eth_data == 8'h02) begin 
        dsethasmi_erase = 1'b1;
        state_next = ASMI_ERASE;
      end
    end

    ASMI_CNT3: begin
      state_next = ASMI_CNT2;
    end

    ASMI_CNT2: begin
      state_next = ASMI_CNT1;
    end

    ASMI_CNT1: begin
      state_next = ASMI_CNT0;
      asmi_cnt_next = {eth_data[5:0],asmi_cnt[7:0]};
    end  

    ASMI_CNT0: begin
      state_next = ASMI_PROGRAM;
      asmi_cnt_next = {asmi_cnt[13:8],eth_data};
    end     

    ASMI_PROGRAM: begin
      dsethasmi_tvalid = 1'b1;
      pushcnt_next = pushcnt + 8'h01;
      if (&pushcnt) begin
        dsethasmi_tlast = 1'b1;
      end else begin
        state_next = ASMI_PROGRAM;
      end
    end

    ASMI_ERASE: begin
      dsethasmi_erase = 1'b1;
      if (~dsethasmi_erase_ack) state_next = ASMI_ERASE;
    end

    ENDPOINT: begin
      // FIXME: Can use end point for other information
      if (eth_data == 8'h02) state_next = SEQNO3;
    end

    SEQNO3: begin
      state_next = SEQNO2;
    end

    SEQNO2: begin
      state_next = SEQNO1;
    end

    SEQNO1: begin
      state_next = SEQNO0;
    end

    SEQNO0: begin
      // Decrement watchdog on begin of data packet
      watchdog_clr = 1'b1;
      state_next = SYNC2;
    end

    SYNC2: begin
      pushcnt_next = 6'h00;
      if (eth_data == 8'h7f) state_next = SYNC1;
    end

    SYNC1: begin
      pushcnt_next = 6'h00;
      if (eth_data == 8'h7f) state_next = SYNC0;
    end

    SYNC0: begin
      pushcnt_next = 6'h00;
      if (eth_data == 8'h7f) state_next = CMDCTRL;
    end

    CMDCTRL: begin
      cmd_resprqst_next = eth_data[7];
      cmd_addr_next = eth_data[6:1];
      cmd_ptt_next = eth_data[0];
      state_next = CMDDATA3;
    end

    CMDDATA3: begin
      cmd_data_next = {eth_data,cmd_data[23:0]};
      state_next = CMDDATA2;
    end

    CMDDATA2: begin
      cmd_data_next = {cmd_data[31:24],eth_data,cmd_data[15:0]};
      state_next = CMDDATA1;
    end

    CMDDATA1: begin
      cmd_data_next = {cmd_data[31:16],eth_data,cmd_data[7:0]};
      state_next = CMDDATA0;
    end

    CMDDATA0: begin
      cmd_data_next = {cmd_data[31:8],eth_data};
      cmd_cnt_next = ~cmd_cnt;
      state_next = PUSHL1;
    end

    PUSHL1: begin
      dsethlr_tvalid = 1'b1;
      state_next = PUSHL0;
    end

    PUSHL0: begin
      dsethlr_tvalid = 1'b1;
      state_next = PUSHR1;
    end

    PUSHR1: begin
      dsethlr_tvalid = 1'b1;
      state_next = PUSHR0;
    end

    PUSHR0: begin
      dsethlr_tvalid = 1'b1;
      dsethlr_tlast  = 1'b1;
      pushcnt_next = pushcnt + 6'h01;
      state_next = PUSHI1;
    end

    PUSHI1: begin
      dsethiq_tvalid = cmd_ptt;
      state_next = PUSHI0;
    end

    PUSHI0: begin
      dsethiq_tvalid = cmd_ptt;
      state_next = PUSHQ1;
    end

    PUSHQ1: begin
      dsethiq_tvalid = cmd_ptt;
      state_next = PUSHQ0;
    end

    PUSHQ0: begin
      dsethiq_tvalid = cmd_ptt;
      dsethiq_tlast  = cmd_ptt;
      if (&pushcnt[5:0]) begin
        if (~pushcnt[6]) begin
          //framecnt_next = 1'b1;
          state_next = SYNC2;
        end
      end else state_next = PUSHL1;
    end

    default: begin
      state_next = START;
    end

  endcase
end

assign dseth_tdata = eth_data;


// Watch dog logic, stop if sending too much
// without receiving packets
always @(posedge clk) begin
  if (~run | watchdog_clr) begin
    watchdog_cnt <= 10'h00;
  end else if (watchdog_up) begin
    watchdog_cnt <= watchdog_cnt + 10'h01;
  end
end 

endmodule

//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

//  Copyright P Harman VK6APH  2012




// Simple Clock Domain Crossing module that double buffers data
// also simulation version to model CDC issues - in progress

`timescale 1 ns/100 ps

module cdc_sync #(parameter SIZE=1)
  (input  wire [SIZE-1:0] siga,
   input  wire            rstb, clkb, 
   output reg  [SIZE-1:0] sigb);

`ifdef SIMULATION
wire [SIZE-1:0] y1;
reg  [SIZE-1:0] q1a, q1b;
reg  [SIZE-1:0] DLY = 1'b0;

assign y1 = (~DLY & q1a) | (DLY & q1b);

always @(posedge clkb)
begin
  if (rstb)
    {sigb,q1b,q1a} <= '0;
  else
    {sigb,q1b,q1a} <= {y1,q1a,siga};
end
`else // synthesis
reg [SIZE-1:0] q1;

always @(posedge clkb)
begin
  if (rstb)
    {sigb,q1} <= 2'b00;
  else
    {sigb,q1} <= {q1,siga};
end
`endif
endmodule/*

--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------


---------------------------------------------------------------------------------
  Copywrite (C) Phil Harman VK6PH May 2014
---------------------------------------------------------------------------------
  
  The code implements an Iambic CW keyer.  The following features are supported:
    
    * Variable speed control from 1 to 60 WPM
    * Dot and Dash memory
    * Straight, Bug, Iambic Mode A or B Modes
    * Variable character weighting
    * Automatic Letter spacing
    * Paddle swap
    
  Dot and Dash memory works by registering an alternative paddle closure whilst a paddle is pressed.
  The alternate paddle closure can occur at any time during a paddle closure and is not limited to being 
  half way through the current dot or dash. This feature could be added if required.
  
  In Straight mode, closing the DASH paddle will result in the output following the input state.  This enables a 
  straight morse key or external Iambic keyer to be connected.
  
  In Bug mode closing the dot paddle will send repeated dots.
  
  The CWX input simply cases the output to follow the input and is intended for use with PC keyboard to CW programs.
  
  The difference between Iambic Mode A and B lies in what the keyer does when both paddles are released. In Mode A the 
  keyer completes the element being sent when both paddles are released. In Mode B the keyer sends an additional
  element opposite to the one being sent when the paddles are released. 
  
  Automatic Letter Space works as follows: When enabled, if you pause for more than one dot time between a dot or dash
  the keyer will interpret this as a letter-space and will not send the next dot or dash until the letter-space time has been met.
  The normal letter-space is 3 dot periods. The keyer has a paddle event memory so that you can enter dots or dashes during the
  inter-letter space and the keyer will send them as they were entered. 

  Speed calculation -  Using standard PARIS timing, dot_period(mS) = 1200/WPM
  
  Changes:
  
  2014 May 8  - First release
       N0v 14 - Added individual inputs for iambic and keyer_mode

  2019 July 21 - Optimized to reduce resources and work with Hermes-Lite 2.0 kf7o


*/

module iambic (
  input clock,              // 2.5 MHz       
  input [5:0] cw_speed,     // 1 to 60 WPM
  input iambic,             // 0 = straight/bug,  1 = Iambic 
  input keyer_mode,         // 0 = Mode A, 1 = Mode B
  input [7:0] weight,       // 33 to 66, nominal is 50
  input letter_space,       // 0 = off, 1 = on
  input dot_key,            // dot paddle  input, active high
  input dash_key,           // dash paddle input, active high
  input CWX,                // CW data from PC active high
  input paddle_swap,        // swap if set
  output reg keyer_out,     // keyer output, active high
  input IO5                 // additional CW key via digital input IO5, debounced, inverted
);


logic [9:0]   cw_speed_dot17;


// Cheap divide 6 bits -> 10 bits
// cw_speed_dot17 is the dot time in units of 2.5 MHz clock divided by 64
// cw_speed of 5wpm is (551 * 64 * 17)/2.5e6 = 239.752ms
// This is close to 1200/5 = 240ms
// The slowest speed is a bit more than 2wpm, 0-2wpm are rounded to this
// div = 64
// dt = 1.0/2.5e6
// for i in range(1,64): 
//   ms = 1200.0/i/1000
//   units = int(round((ms/17.0)*2.5e6/div))
//   approximate = units * 17 * div * dt
//   error = 100*abs(approximate-ms)/ms
//   print("{0} : cw_speed_dot17 = {1}; // real:{2:.2f}ms approximate:{3:.2f}ms error:{4:.2f}%".format(i,units,1000*ms,1000*approximate,error))

always @* begin
  case (cw_speed) 
    0  : cw_speed_dot17 = 1023;
    1  : cw_speed_dot17 = 1023;
    2  : cw_speed_dot17 = 1023;
    3  : cw_speed_dot17 = 919; // real:400.00ms approximate:399.95ms error:0.01%
    4  : cw_speed_dot17 = 689; // real:300.00ms approximate:299.85ms error:0.05%
    5  : cw_speed_dot17 = 551; // real:240.00ms approximate:239.80ms error:0.09%
    6  : cw_speed_dot17 = 460; // real:200.00ms approximate:200.19ms error:0.10%
    7  : cw_speed_dot17 = 394; // real:171.43ms approximate:171.47ms error:0.02%
    8  : cw_speed_dot17 = 345; // real:150.00ms approximate:150.14ms error:0.10%
    9  : cw_speed_dot17 = 306; // real:133.33ms approximate:133.17ms error:0.12%
    10 : cw_speed_dot17 = 276; // real:120.00ms approximate:120.12ms error:0.10%
    11 : cw_speed_dot17 = 251; // real:109.09ms approximate:109.24ms error:0.13%
    12 : cw_speed_dot17 = 230; // real:100.00ms approximate:100.10ms error:0.10%
    13 : cw_speed_dot17 = 212; // real:92.31ms approximate:92.26ms error:0.05%
    14 : cw_speed_dot17 = 197; // real:85.71ms approximate:85.73ms error:0.02%
    15 : cw_speed_dot17 = 184; // real:80.00ms approximate:80.08ms error:0.10%
    16 : cw_speed_dot17 = 172; // real:75.00ms approximate:74.85ms error:0.19%
    17 : cw_speed_dot17 = 162; // real:70.59ms approximate:70.50ms error:0.12%
    18 : cw_speed_dot17 = 153; // real:66.67ms approximate:66.59ms error:0.12%
    19 : cw_speed_dot17 = 145; // real:63.16ms approximate:63.10ms error:0.09%
    20 : cw_speed_dot17 = 138; // real:60.00ms approximate:60.06ms error:0.10%
    21 : cw_speed_dot17 = 131; // real:57.14ms approximate:57.01ms error:0.23%
    22 : cw_speed_dot17 = 125; // real:54.55ms approximate:54.40ms error:0.27%
    23 : cw_speed_dot17 = 120; // real:52.17ms approximate:52.22ms error:0.10%
    24 : cw_speed_dot17 = 115; // real:50.00ms approximate:50.05ms error:0.10%
    25 : cw_speed_dot17 = 110; // real:48.00ms approximate:47.87ms error:0.27%
    26 : cw_speed_dot17 = 106; // real:46.15ms approximate:46.13ms error:0.05%
    27 : cw_speed_dot17 = 102; // real:44.44ms approximate:44.39ms error:0.12%
    28 : cw_speed_dot17 = 98; // real:42.86ms approximate:42.65ms error:0.48%
    29 : cw_speed_dot17 = 95; // real:41.38ms approximate:41.34ms error:0.09%
    30 : cw_speed_dot17 = 92; // real:40.00ms approximate:40.04ms error:0.10%
    31 : cw_speed_dot17 = 89; // real:38.71ms approximate:38.73ms error:0.06%
    32 : cw_speed_dot17 = 86; // real:37.50ms approximate:37.43ms error:0.19%
    33 : cw_speed_dot17 = 84; // real:36.36ms approximate:36.56ms error:0.53%
    34 : cw_speed_dot17 = 81; // real:35.29ms approximate:35.25ms error:0.12%
    35 : cw_speed_dot17 = 79; // real:34.29ms approximate:34.38ms error:0.28%
    36 : cw_speed_dot17 = 77; // real:33.33ms approximate:33.51ms error:0.53%
    37 : cw_speed_dot17 = 75; // real:32.43ms approximate:32.64ms error:0.64%
    38 : cw_speed_dot17 = 73; // real:31.58ms approximate:31.77ms error:0.60%
    39 : cw_speed_dot17 = 71; // real:30.77ms approximate:30.90ms error:0.42%
    40 : cw_speed_dot17 = 69; // real:30.00ms approximate:30.03ms error:0.10%
    41 : cw_speed_dot17 = 67; // real:29.27ms approximate:29.16ms error:0.38%
    42 : cw_speed_dot17 = 66; // real:28.57ms approximate:28.72ms error:0.53%
    43 : cw_speed_dot17 = 64; // real:27.91ms approximate:27.85ms error:0.19%
    44 : cw_speed_dot17 = 63; // real:27.27ms approximate:27.42ms error:0.53%
    45 : cw_speed_dot17 = 61; // real:26.67ms approximate:26.55ms error:0.45%
    46 : cw_speed_dot17 = 60; // real:26.09ms approximate:26.11ms error:0.10%
    47 : cw_speed_dot17 = 59; // real:25.53ms approximate:25.68ms error:0.57%
    48 : cw_speed_dot17 = 57; // real:25.00ms approximate:24.81ms error:0.77%
    49 : cw_speed_dot17 = 56; // real:24.49ms approximate:24.37ms error:0.48%
    50 : cw_speed_dot17 = 55; // real:24.00ms approximate:23.94ms error:0.27%
    51 : cw_speed_dot17 = 54; // real:23.53ms approximate:23.50ms error:0.12%
    52 : cw_speed_dot17 = 53; // real:23.08ms approximate:23.07ms error:0.05%
    53 : cw_speed_dot17 = 52; // real:22.64ms approximate:22.63ms error:0.05%
    54 : cw_speed_dot17 = 51; // real:22.22ms approximate:22.20ms error:0.12%
    55 : cw_speed_dot17 = 50; // real:21.82ms approximate:21.76ms error:0.27%
    56 : cw_speed_dot17 = 49; // real:21.43ms approximate:21.32ms error:0.48%
    57 : cw_speed_dot17 = 48; // real:21.05ms approximate:20.89ms error:0.77%
    58 : cw_speed_dot17 = 48; // real:20.69ms approximate:20.89ms error:0.97%
    59 : cw_speed_dot17 = 47; // real:20.34ms approximate:20.45ms error:0.57%
    60 : cw_speed_dot17 = 46; // real:20.00ms approximate:20.02ms error:0.10%
    61 : cw_speed_dot17 = 45; // real:19.67ms approximate:19.58ms error:0.45%
    62 : cw_speed_dot17 = 44; // real:19.35ms approximate:19.15ms error:1.06%
    63 : cw_speed_dot17 = 44; // real:19.05ms approximate:19.15ms error:0.53%
  endcase // cw_speed
end // always @ *
   
   logic dot_cnt_rst, dot_cnt; //dh
   
// Counter that counts 1/17 the time of a dot .2176/17
// This is to match the weight offset
// A weight of 51 is then 51/17= 3 or 3x a dot time
always @(posedge clock) begin
  if (dot_cnt_rst || dot_cnt == 0) begin
    dot_cnt <= (cw_speed_dot17 << 6);
  end else begin
    dot_cnt <= dot_cnt - 1;
  end
end

assign dot_done = (dot_cnt == 0);

        
                        
localparam  LOOP        = 0,
            PREDOT      = 1,
            PREDASH     = 2,
            SENDDOT     = 3,
            SENDDASH    = 4,
            DOTDELAY    = 5,
            DELAYDOT    = DOTDELAY, // dh[??]
            DASHDELAY   = 6,
            DELAYDASH   = DASHDELAY,
            DOTHELD     = 7,
            DASHHELD    = 8,
            LETTERSPACE = 9;  
   
        
reg dot_memory = 0;
reg dash_memory = 0;  
reg [4:0] key_state = 0;  

reg  [DELAYDASH-1:0] delay;
wire [DELAYDOT-1:0]  dot_delay;
wire [DELAYDASH-1:0] dash_delay;


// swap paddles if set
wire dot, dash;
assign dot  = paddle_swap ? dash_key : dot_key;
assign dash = paddle_swap ? dot_key  : dash_key;
    



// dh: declaring nets
   logic delay_reset, dot_memory_next;
   logic [16:0] delay_next, key_state_next, dash_memory_next;
   
always @* begin

  keyer_out   = 1'b0;
  delay_reset = 1'b0;


  if (dot_done) delay_next = delay + 1;
  else delay_next = delay;

  case (key_state)
    // wait for key press
    LOOP: begin
      dot_memory_next  = 1'b0;
      dash_memory_next = 1'b0;
      delay_reset = 1'b1;
      if(!iambic) begin           // Straight/External key or bug
        if (dash) keyer_out = 1'b1;
        else if (dot) key_state_next = SENDDOT;
        else keyer_out = CWX;   // neither so use CWX
      
      end else begin
        if (dot) key_state_next = SENDDOT;
        else if (dash) key_state_next = SENDDASH;
        else keyer_out = (CWX | IO5);  // neither so use CWX or IO5 ext CW digital input
      end   
    end 
    
    SENDDOT: begin 
      keyer_out = 1'b1;
      if (delay == 8'd17) begin
        delay_reset = 1'b1;
        key_state_next = DOTDELAY;        // add inter-character spacing of one dot length
      end
        
      // if Mode A and both paddles are released then clear dash memory
      if (keyer_mode == 0) begin  
        if (!dot & !dash) dash_memory_next = 1'b0;
      end else if (dash) begin            // set dash memory
        dash_memory_next = 1'b1;
      end
    end

    SENDDASH: begin
      keyer_out = 1'b1;
      if (delay == weight) begin
        delay_reset = 1'b1;
        key_state_next = DASHDELAY;       // add inter-character spacing of one dot length
      end
        
      // if Mode A and both padles are relesed then clear dot memory
      if (keyer_mode == 0) begin  
        if (!dot & !dash) dot_memory_next = 0;
      end else if (dot) begin               // set dot memory  
        dot_memory_next = 1'b1;
      end
    end
    
    // add dot delay at end of the dot and check for dash memory, then check if paddle still held
    DOTDELAY: begin
      if (delay == 8'd17) begin

        delay_reset = 1'b1;
        dot_memory_next  = 1'b0;
        dash_memory_next = 1'b0;
        key_state_next = LOOP;

        if(!iambic) begin                   // just return if in bug mode
          ;
        end else if (dash_memory | dash) begin             // dash has been set during the dot so service
          key_state_next = SENDDASH;
        end else if (dot) begin
          key_state_next = SENDDOT;
        end else if (letter_space) begin        // Letter space enabled so clear any pending dots or dashes 
          key_state_next = LETTERSPACE;
        end
      end else if (dash) begin
        dash_memory_next = 1'b1;
      end
    end
        
    // add dot delay at end of the dash and check for dot memory, then check if paddle still held
    DASHDELAY: begin
      if (delay == 8'd17) begin

        delay_reset = 1'b1;
        dot_memory_next  = 1'b0;
        dash_memory_next = 1'b0;
        key_state_next = LOOP;

        if(!iambic) begin                  
          ;
        end else if (dot_memory | dot) begin             
          key_state_next = SENDDOT;
        end else if (dash) begin
          key_state_next = SENDDASH;
        end else if (letter_space) begin      
          key_state_next = LETTERSPACE;
        end
      end else if (dot) begin
        dot_memory_next = 1'b1;
      end
    end
    
    // Add letter space (2 x dot delay) to end of character and check if a paddle is pressed during this time. 
    LETTERSPACE: begin
      if (delay == 8'd34) begin

        delay_reset = 1'b1;
        dot_memory_next  = 1'b0;
        dash_memory_next = 1'b0;
        key_state_next = LOOP;

        if (dot_memory) key_state_next = SENDDOT;
        else if (dash_memory) key_state_next = SENDDASH;
      
      end else begin       
        // save any key presses during the letter space delay
        if (dot)   dot_memory_next = 1'b1;
        if (dash) dash_memory_next = 1'b1;
      end
    end  
    
    default: key_state_next = LOOP;
  endcase
end





endmodule
// megafunction wizard: %ALTPLL%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altpll 

// ============================================================
// File Name: ad9866pll.v
// Megafunction Name(s):
// 			altpll
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 16.1.2 Build 203 01/18/2017 SJ Lite Edition
// ************************************************************


//Copyright (C) 2017  Intel Corporation. All rights reserved.
//Your use of Intel Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Intel Program License 
//Subscription Agreement, the Intel Quartus Prime License Agreement,
//the Intel MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Intel and sold by Intel or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module ad9866pll (
	areset,
	inclk0,
	c0,
	c1,
	c2,
	locked);

	input	  areset;
	input	  inclk0;
	output	  c0;
	output	  c1;
	output	  c2;
	output	  locked;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri0	  areset;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [0:0] sub_wire2 = 1'h0;
	wire [4:0] sub_wire3;
	wire  sub_wire7;
	wire  sub_wire0 = inclk0;
	wire [1:0] sub_wire1 = {sub_wire2, sub_wire0};
	wire [2:2] sub_wire6 = sub_wire3[2:2];
	wire [1:1] sub_wire5 = sub_wire3[1:1];
	wire [0:0] sub_wire4 = sub_wire3[0:0];
	wire  c0 = sub_wire4;
	wire  c1 = sub_wire5;
	wire  c2 = sub_wire6;
	wire  locked = sub_wire7;
/*
	altpll	altpll_component (
				.areset (areset),
				.inclk (sub_wire1),
				.clk (sub_wire3),
				.locked (sub_wire7),
				.activeclock (),
				.clkbad (),
				.clkena ({6{1'b1}}),
				.clkloss (),
				.clkswitch (1'b0),
				.configupdate (1'b0),
				.enable0 (),
				.enable1 (),
				.extclk (),
				.extclkena ({4{1'b1}}),
				.fbin (1'b1),
				.fbmimicbidir (),
				.fbout (),
				.fref (),
				.icdrclk (),
				.pfdena (1'b1),
				.phasecounterselect ({4{1'b1}}),
				.phasedone (),
				.phasestep (1'b1),
				.phaseupdown (1'b1),
				.pllena (1'b1),
				.scanaclr (1'b0),
				.scanclk (1'b0),
				.scanclkena (1'b1),
				.scandata (1'b0),
				.scandataout (),
				.scandone (),
				.scanread (1'b0),
				.scanwrite (1'b0),
				.sclkout0 (),
				.sclkout1 (),
				.vcooverrange (),
				.vcounderrange ());
	defparam
		altpll_component.bandwidth_type = "AUTO",
		altpll_component.clk0_divide_by = 1,
		altpll_component.clk0_duty_cycle = 50,
		altpll_component.clk0_multiply_by = 1,
		altpll_component.clk0_phase_shift = "0",
		altpll_component.clk1_divide_by = 1,
		altpll_component.clk1_duty_cycle = 50,
		altpll_component.clk1_multiply_by = 2,
		altpll_component.clk1_phase_shift = "0",
		altpll_component.clk2_divide_by = 5,
		altpll_component.clk2_duty_cycle = 50,
		altpll_component.clk2_multiply_by = 16,
		altpll_component.clk2_phase_shift = "0",
		altpll_component.compensate_clock = "CLK0",
		altpll_component.inclk0_input_frequency = 13020,
		altpll_component.intended_device_family = "Cyclone IV E",
		altpll_component.lpm_hint = "CBX_MODULE_PREFIX=ad9866pll",
		altpll_component.lpm_type = "altpll",
		altpll_component.operation_mode = "NORMAL",
		altpll_component.pll_type = "AUTO",
		altpll_component.port_activeclock = "PORT_UNUSED",
		altpll_component.port_areset = "PORT_USED",
		altpll_component.port_clkbad0 = "PORT_UNUSED",
		altpll_component.port_clkbad1 = "PORT_UNUSED",
		altpll_component.port_clkloss = "PORT_UNUSED",
		altpll_component.port_clkswitch = "PORT_UNUSED",
		altpll_component.port_configupdate = "PORT_UNUSED",
		altpll_component.port_fbin = "PORT_UNUSED",
		altpll_component.port_inclk0 = "PORT_USED",
		altpll_component.port_inclk1 = "PORT_UNUSED",
		altpll_component.port_locked = "PORT_USED",
		altpll_component.port_pfdena = "PORT_UNUSED",
		altpll_component.port_phasecounterselect = "PORT_UNUSED",
		altpll_component.port_phasedone = "PORT_UNUSED",
		altpll_component.port_phasestep = "PORT_UNUSED",
		altpll_component.port_phaseupdown = "PORT_UNUSED",
		altpll_component.port_pllena = "PORT_UNUSED",
		altpll_component.port_scanaclr = "PORT_UNUSED",
		altpll_component.port_scanclk = "PORT_UNUSED",
		altpll_component.port_scanclkena = "PORT_UNUSED",
		altpll_component.port_scandata = "PORT_UNUSED",
		altpll_component.port_scandataout = "PORT_UNUSED",
		altpll_component.port_scandone = "PORT_UNUSED",
		altpll_component.port_scanread = "PORT_UNUSED",
		altpll_component.port_scanwrite = "PORT_UNUSED",
		altpll_component.port_clk0 = "PORT_USED",
		altpll_component.port_clk1 = "PORT_USED",
		altpll_component.port_clk2 = "PORT_USED",
		altpll_component.port_clk3 = "PORT_UNUSED",
		altpll_component.port_clk4 = "PORT_UNUSED",
		altpll_component.port_clk5 = "PORT_UNUSED",
		altpll_component.port_clkena0 = "PORT_UNUSED",
		altpll_component.port_clkena1 = "PORT_UNUSED",
		altpll_component.port_clkena2 = "PORT_UNUSED",
		altpll_component.port_clkena3 = "PORT_UNUSED",
		altpll_component.port_clkena4 = "PORT_UNUSED",
		altpll_component.port_clkena5 = "PORT_UNUSED",
		altpll_component.port_extclk0 = "PORT_UNUSED",
		altpll_component.port_extclk1 = "PORT_UNUSED",
		altpll_component.port_extclk2 = "PORT_UNUSED",
		altpll_component.port_extclk3 = "PORT_UNUSED",
		altpll_component.self_reset_on_loss_lock = "ON",
		altpll_component.width_clock = 5;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ACTIVECLK_CHECK STRING "0"
// Retrieval info: PRIVATE: BANDWIDTH STRING "1.000"
// Retrieval info: PRIVATE: BANDWIDTH_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: BANDWIDTH_FREQ_UNIT STRING "MHz"
// Retrieval info: PRIVATE: BANDWIDTH_PRESET STRING "Low"
// Retrieval info: PRIVATE: BANDWIDTH_USE_AUTO STRING "1"
// Retrieval info: PRIVATE: BANDWIDTH_USE_PRESET STRING "0"
// Retrieval info: PRIVATE: CLKBAD_SWITCHOVER_CHECK STRING "0"
// Retrieval info: PRIVATE: CLKLOSS_CHECK STRING "0"
// Retrieval info: PRIVATE: CLKSWITCH_CHECK STRING "0"
// Retrieval info: PRIVATE: CNX_NO_COMPENSATE_RADIO STRING "0"
// Retrieval info: PRIVATE: CREATE_CLKBAD_CHECK STRING "0"
// Retrieval info: PRIVATE: CREATE_INCLK1_CHECK STRING "0"
// Retrieval info: PRIVATE: CUR_DEDICATED_CLK STRING "c0"
// Retrieval info: PRIVATE: CUR_FBIN_CLK STRING "c0"
// Retrieval info: PRIVATE: DEVICE_SPEED_GRADE STRING "8"
// Retrieval info: PRIVATE: DIV_FACTOR0 NUMERIC "1"
// Retrieval info: PRIVATE: DIV_FACTOR1 NUMERIC "1"
// Retrieval info: PRIVATE: DIV_FACTOR2 NUMERIC "5"
// Retrieval info: PRIVATE: DUTY_CYCLE0 STRING "50.00000000"
// Retrieval info: PRIVATE: DUTY_CYCLE1 STRING "50.00000000"
// Retrieval info: PRIVATE: DUTY_CYCLE2 STRING "50.00000000"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE0 STRING "76.800003"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE1 STRING "153.600006"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE2 STRING "245.759995"
// Retrieval info: PRIVATE: EXPLICIT_SWITCHOVER_COUNTER STRING "0"
// Retrieval info: PRIVATE: EXT_FEEDBACK_RADIO STRING "0"
// Retrieval info: PRIVATE: GLOCKED_COUNTER_EDIT_CHANGED STRING "1"
// Retrieval info: PRIVATE: GLOCKED_FEATURE_ENABLED STRING "0"
// Retrieval info: PRIVATE: GLOCKED_MODE_CHECK STRING "0"
// Retrieval info: PRIVATE: GLOCK_COUNTER_EDIT NUMERIC "1048575"
// Retrieval info: PRIVATE: HAS_MANUAL_SWITCHOVER STRING "1"
// Retrieval info: PRIVATE: INCLK0_FREQ_EDIT STRING "76.800"
// Retrieval info: PRIVATE: INCLK0_FREQ_UNIT_COMBO STRING "MHz"
// Retrieval info: PRIVATE: INCLK1_FREQ_EDIT STRING "100.000"
// Retrieval info: PRIVATE: INCLK1_FREQ_EDIT_CHANGED STRING "1"
// Retrieval info: PRIVATE: INCLK1_FREQ_UNIT_CHANGED STRING "1"
// Retrieval info: PRIVATE: INCLK1_FREQ_UNIT_COMBO STRING "MHz"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: INT_FEEDBACK__MODE_RADIO STRING "1"
// Retrieval info: PRIVATE: LOCKED_OUTPUT_CHECK STRING "1"
// Retrieval info: PRIVATE: LONG_SCAN_RADIO STRING "1"
// Retrieval info: PRIVATE: LVDS_MODE_DATA_RATE STRING "Not Available"
// Retrieval info: PRIVATE: LVDS_MODE_DATA_RATE_DIRTY NUMERIC "0"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT0 STRING "deg"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT1 STRING "deg"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT2 STRING "ps"
// Retrieval info: PRIVATE: MIG_DEVICE_SPEED_GRADE STRING "Any"
// Retrieval info: PRIVATE: MIRROR_CLK0 STRING "0"
// Retrieval info: PRIVATE: MIRROR_CLK1 STRING "0"
// Retrieval info: PRIVATE: MIRROR_CLK2 STRING "0"
// Retrieval info: PRIVATE: MULT_FACTOR0 NUMERIC "1"
// Retrieval info: PRIVATE: MULT_FACTOR1 NUMERIC "1"
// Retrieval info: PRIVATE: MULT_FACTOR2 NUMERIC "16"
// Retrieval info: PRIVATE: NORMAL_MODE_RADIO STRING "1"
// Retrieval info: PRIVATE: OUTPUT_FREQ0 STRING "76.80000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ1 STRING "153.60000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ2 STRING "100.00000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE0 STRING "1"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE1 STRING "1"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE2 STRING "0"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT0 STRING "MHz"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT1 STRING "MHz"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT2 STRING "MHz"
// Retrieval info: PRIVATE: PHASE_RECONFIG_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: PHASE_RECONFIG_INPUTS_CHECK STRING "0"
// Retrieval info: PRIVATE: PHASE_SHIFT0 STRING "0.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT1 STRING "0.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT2 STRING "0.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT_STEP_ENABLED_CHECK STRING "0"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT0 STRING "deg"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT1 STRING "ns"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT2 STRING "ps"
// Retrieval info: PRIVATE: PLL_ADVANCED_PARAM_CHECK STRING "0"
// Retrieval info: PRIVATE: PLL_ARESET_CHECK STRING "1"
// Retrieval info: PRIVATE: PLL_AUTOPLL_CHECK NUMERIC "1"
// Retrieval info: PRIVATE: PLL_ENHPLL_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PLL_FASTPLL_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PLL_FBMIMIC_CHECK STRING "0"
// Retrieval info: PRIVATE: PLL_LVDS_PLL_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PLL_PFDENA_CHECK STRING "0"
// Retrieval info: PRIVATE: PLL_TARGET_HARCOPY_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PRIMARY_CLK_COMBO STRING "inclk0"
// Retrieval info: PRIVATE: RECONFIG_FILE STRING "ad9866pll.mif"
// Retrieval info: PRIVATE: SACN_INPUTS_CHECK STRING "0"
// Retrieval info: PRIVATE: SCAN_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: SELF_RESET_LOCK_LOSS STRING "1"
// Retrieval info: PRIVATE: SHORT_SCAN_RADIO STRING "0"
// Retrieval info: PRIVATE: SPREAD_FEATURE_ENABLED STRING "0"
// Retrieval info: PRIVATE: SPREAD_FREQ STRING "50.000"
// Retrieval info: PRIVATE: SPREAD_FREQ_UNIT STRING "KHz"
// Retrieval info: PRIVATE: SPREAD_PERCENT STRING "0.500"
// Retrieval info: PRIVATE: SPREAD_USE STRING "0"
// Retrieval info: PRIVATE: SRC_SYNCH_COMP_RADIO STRING "0"
// Retrieval info: PRIVATE: STICKY_CLK0 STRING "1"
// Retrieval info: PRIVATE: STICKY_CLK1 STRING "1"
// Retrieval info: PRIVATE: STICKY_CLK2 STRING "1"
// Retrieval info: PRIVATE: SWITCHOVER_COUNT_EDIT NUMERIC "1"
// Retrieval info: PRIVATE: SWITCHOVER_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: USE_CLK0 STRING "1"
// Retrieval info: PRIVATE: USE_CLK1 STRING "1"
// Retrieval info: PRIVATE: USE_CLK2 STRING "1"
// Retrieval info: PRIVATE: USE_CLKENA0 STRING "0"
// Retrieval info: PRIVATE: USE_CLKENA1 STRING "0"
// Retrieval info: PRIVATE: USE_CLKENA2 STRING "0"
// Retrieval info: PRIVATE: USE_MIL_SPEED_GRADE NUMERIC "0"
// Retrieval info: PRIVATE: ZERO_DELAY_RADIO STRING "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: BANDWIDTH_TYPE STRING "AUTO"
// Retrieval info: CONSTANT: CLK0_DIVIDE_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK0_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK0_MULTIPLY_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK0_PHASE_SHIFT STRING "0"
// Retrieval info: CONSTANT: CLK1_DIVIDE_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK1_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK1_MULTIPLY_BY NUMERIC "2"
// Retrieval info: CONSTANT: CLK1_PHASE_SHIFT STRING "0"
// Retrieval info: CONSTANT: CLK2_DIVIDE_BY NUMERIC "5"
// Retrieval info: CONSTANT: CLK2_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK2_MULTIPLY_BY NUMERIC "16"
// Retrieval info: CONSTANT: CLK2_PHASE_SHIFT STRING "0"
// Retrieval info: CONSTANT: COMPENSATE_CLOCK STRING "CLK0"
// Retrieval info: CONSTANT: INCLK0_INPUT_FREQUENCY NUMERIC "13020"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altpll"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "NORMAL"
// Retrieval info: CONSTANT: PLL_TYPE STRING "AUTO"
// Retrieval info: CONSTANT: PORT_ACTIVECLOCK STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_ARESET STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_CLKBAD0 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CLKBAD1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CLKLOSS STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CLKSWITCH STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CONFIGUPDATE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_FBIN STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_INCLK0 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_INCLK1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_LOCKED STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_PFDENA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASECOUNTERSELECT STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASEDONE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASESTEP STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASEUPDOWN STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PLLENA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANACLR STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANCLK STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANCLKENA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANDATA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANDATAOUT STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANDONE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANREAD STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANWRITE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clk0 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk1 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk2 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk3 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clk4 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clk5 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena0 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena2 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena3 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena4 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena5 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk0 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk2 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk3 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: SELF_RESET_ON_LOSS_LOCK STRING "ON"
// Retrieval info: CONSTANT: WIDTH_CLOCK NUMERIC "5"
// Retrieval info: USED_PORT: @clk 0 0 5 0 OUTPUT_CLK_EXT VCC "@clk[4..0]"
// Retrieval info: USED_PORT: areset 0 0 0 0 INPUT GND "areset"
// Retrieval info: USED_PORT: c0 0 0 0 0 OUTPUT_CLK_EXT VCC "c0"
// Retrieval info: USED_PORT: c1 0 0 0 0 OUTPUT_CLK_EXT VCC "c1"
// Retrieval info: USED_PORT: c2 0 0 0 0 OUTPUT_CLK_EXT VCC "c2"
// Retrieval info: USED_PORT: inclk0 0 0 0 0 INPUT_CLK_EXT GND "inclk0"
// Retrieval info: USED_PORT: locked 0 0 0 0 OUTPUT GND "locked"
// Retrieval info: CONNECT: @areset 0 0 0 0 areset 0 0 0 0
// Retrieval info: CONNECT: @inclk 0 0 1 1 GND 0 0 0 0
// Retrieval info: CONNECT: @inclk 0 0 1 0 inclk0 0 0 0 0
// Retrieval info: CONNECT: c0 0 0 0 0 @clk 0 0 1 0
// Retrieval info: CONNECT: c1 0 0 0 0 @clk 0 0 1 1
// Retrieval info: CONNECT: c2 0 0 0 0 @clk 0 0 1 2
// Retrieval info: CONNECT: locked 0 0 0 0 @locked 0 0 0 0
// Retrieval info: GEN_FILE: TYPE_NORMAL ad9866pll.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ad9866pll.ppf TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ad9866pll.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ad9866pll.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ad9866pll.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ad9866pll_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ad9866pll_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
// Retrieval info: CBX_MODULE_PREFIX: ON

`timescale 1us/1ns

module nco2 (
  state,
  clk_2x,
  rst,
  phi0,
  phi1,
  cos,
  sin,
);

input             state;
input             clk_2x;
input             rst;
input     [31:0]  phi0;
input     [31:0]  phi1;
output    [18:0]  sin;
output    [18:0]  cos;

logic [31:0]      angle0 = 32'h00;
logic [31:0]      angle1 = 32'h00;

parameter         CALCTYPE = 0;


always @(posedge clk_2x) begin
  if (rst) begin 
    angle0 <= 32'h00;
    angle1 <= 32'h00;
  end else begin
    angle1 <= angle0 + (state ? phi1 : phi0);
    angle0 <= angle1;
  end
end


sincos #(.CALCTYPE(CALCTYPE)) sincos_i (
  .clk(clk_2x),
  .angle(angle1[31:12]),
  .cos(cos),
  .sin(sin)
);

endmodule 



`timescale 1us/1ns

module sincos (
  clk,
  angle,
  cos,
  sin
);

parameter CALCTYPE = 0;

input                       clk;
input               [19:0]  angle;
output logic        [18:0]  sin;
output logic        [18:0]  cos;

//Pipestage 1
logic   [7:0]   coarse;
logic   [9:0]   fine;
logic   [1:0]   quadrant;
assign {quadrant,coarse,fine} = angle;

logic   [7:0]   coarse_addr;
logic           sin_sign, cos_sign;

logic   [8:0]   fine_addr;
logic           fine_sign;

always @(posedge clk) begin
  coarse_addr <= quadrant[0] ? ~coarse : coarse;
  sin_sign    <= quadrant[1] ? 1'b1 : 1'b0;
  cos_sign    <= (quadrant[1] ^ quadrant[0]) ? 1'b1 : 1'b0;

  fine_addr   <= fine[9] ? fine[8:0] : ~fine[8:0];
  fine_sign   <= fine[9] ? 1'b0 : 1'b1;
end 


//Pipestage2
//Sign magnitude values to make full use of Cyclone IV multipliers
logic  [18:0]   coarse_sin, coarse_cos, coarse_sinp, coarse_cosp;
logic           fine_sign_d1, fine_sign_pd1;
          
always @(posedge clk) begin
  coarse_sinp[18]          <=  sin_sign;
  coarse_cosp[18]          <=  cos_sign;
  fine_sign_pd1            <=  fine_sign;
end // always @(posedge clk)

coarserom #(.init_file("sincos_coarse.txt")) coarserom_i (
  .address(coarse_addr),
  .clock(clk),
  .q({coarse_sinp[17:0],coarse_cosp[17:0]})
);

// Extra pipe to map into optimum RAM and multiplier
always @(posedge clk) begin
  coarse_sin <= coarse_sinp;
  coarse_cos <= coarse_cosp;
  fine_sign_d1 <= fine_sign_pd1;
end


//Pipestage2,3
logic  [9:0]   scsf, ccsf;
logic  [35:0]   scsf_ff, ccsf_ff;

logic  unsigned [17:0]  sin_opa, sin_opb, cos_opa, cos_opb;
logic  unsigned [35:0]  sin_mult_res, cos_mult_res;

generate
  if (CALCTYPE == 0) begin: CALCROM
    
    logic   [8:0]   fine_sin;

    finerom #(.init_file("sin_fine.txt")) finerom_i (
      .address(fine_addr),
      .clock(clk),
      .q(fine_sin)
    );

    assign sin_opa = coarse_sinp[17:0];
    assign sin_opb = {9'h00,fine_sin};
    assign scsf_ff = sin_mult_res;
    assign cos_opa = coarse_cosp[17:0];
    assign cos_opb = {9'h00,fine_sin};
    assign ccsf_ff = cos_mult_res;
    
    assign scsf = scsf_ff[26:17];
    assign ccsf = ccsf_ff[26:17];

  end else if (CALCTYPE == 1) begin: CALCMULT

    logic  [17:0]   fine_sin;

    // 9x9 unsigned multiply
    always @(posedge clk) begin
      // 1'b1 is used below as tables are centered around midpoint, 
      // it will be half after shifting
      // 9'h193 is an approximation of 2*pi*64
      fine_sin <= 9'h193 * {fine_addr[8:1],1'b1};
    end

    assign sin_opa = coarse_sinp[17:0];
    assign sin_opb = fine_sin;
    assign scsf_ff = sin_mult_res;
    assign cos_opa = coarse_cosp[17:0];
    assign cos_opb = fine_sin;
    assign ccsf_ff = cos_mult_res;

    // Only 10 bits required for correction factor
    assign scsf = scsf_ff[35:26];
    assign ccsf = ccsf_ff[35:26];

  end else if (CALCTYPE == 2) begin: CALCLOGIC8

    logic  [15:0]   fine_sin;

    // 8x8 unsigned multiply in logic
    always @(posedge clk) begin
      fine_sin <= 8'hca * {fine_addr[8:2],1'b1};
    end

    // Restrict output to 8 bits to reduce LUT usage
    assign sin_opa = coarse_sinp[17:0];
    assign sin_opb = {10'h00,fine_sin[15:8]};
    assign scsf_ff = sin_mult_res;
    assign cos_opa = coarse_cosp[17:0];
    assign cos_opb = {10'h00,fine_sin[15:8]};
    assign ccsf_ff = cos_mult_res;

    // Only 10 bits required for correction factor
    assign scsf = scsf_ff[25:16];
    assign ccsf = ccsf_ff[25:16];

  end else if (CALCTYPE == 3) begin: CALCLOGIC7

    logic  [13:0]   fine_sin;

    always @(posedge clk) begin
      // 7x7
      fine_sin <= 7'h65 * {fine_addr[8:3],1'b1};
    end

    // Restrict output to 7 bits to reduce LUT usage
    assign sin_opa = coarse_sinp[17:0];
    assign sin_opb = {11'h00,fine_sin[13:7]};
    assign scsf_ff = sin_mult_res;
    assign cos_opa = coarse_cosp[17:0];
    assign cos_opb = {11'h00,fine_sin[13:7]};
    assign ccsf_ff = cos_mult_res;
 
    // Only 10 bits required for correction factor
    assign scsf = scsf_ff[24:15];
    assign ccsf = ccsf_ff[24:15];

  end else if (CALCTYPE == 4) begin: CALCLOGIC7_10

    logic  [16:0]   fine_sin;

    always @(posedge clk) begin
      // 7x10
      fine_sin <= 7'h65 * {fine_addr[8:0],1'b1};
    end

    // Restrict output to 8 bits to reduce LUT usage
    assign sin_opa = coarse_sinp[17:0];
    assign sin_opb = {10'h00,fine_sin[16:9]};
    assign scsf_ff = sin_mult_res;
    assign cos_opa = coarse_cosp[17:0];
    assign cos_opb = {10'h00,fine_sin[16:9]};
    assign ccsf_ff = cos_mult_res;
 
    // Only 10 bits required for correction factor
    assign scsf = scsf_ff[25:16];
    assign ccsf = ccsf_ff[25:16];

  end

endgenerate

`ifdef SIMULATION

logic  unsigned [17:0]  isin_opa, isin_opb, icos_opa, icos_opb;

always @(posedge clk) begin
  isin_opa <= sin_opa;
  isin_opb <= sin_opb;
  sin_mult_res <= isin_opa * isin_opb;
end

always @(posedge clk) begin
  icos_opa <= cos_opa;
  icos_opb <= cos_opb;
  cos_mult_res <= icos_opa * icos_opb;
end


`else

lpm_mult #( .lpm_hint("DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5"),
            .lpm_pipeline(2),
            .lpm_representation("UNSIGNED"),
            .lpm_type("LPM_MULT"),
            .lpm_widtha(18),
            .lpm_widthb(18),
            .lpm_widthp(36))
sinmult (   .clock(clk),
            .dataa(sin_opa),
            .datab(sin_opb),
            .result(sin_mult_res),
            .aclr(1'b0),
            .clken(1'b1),
            .sclr(1'b0),
            .sum());


lpm_mult #( .lpm_hint("DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5"),
            .lpm_pipeline(2),
            .lpm_representation("UNSIGNED"),
            .lpm_type("LPM_MULT"),
            .lpm_widtha(18),
            .lpm_widthb(18),
            .lpm_widthp(36)) 
cosmult (   .clock(clk),
            .dataa(cos_opa),
            .datab(cos_opb),
            .result(cos_mult_res),
            .aclr(1'b0),
            .clken(1'b1),
            .sclr(1'b0),
            .sum());

`endif

//    assign sin_mult_res = sin_opa * sin_opb;
//    always @(posedge clk) begin
//      sin_opa <= coarse_sinp[17:0];
//      sin_opb <= {9'h00,fine_sin};
//      scsf_ff <= sin_mult_res;
//    end
//
//    assign cos_mult_res = cos_opa * cos_opb;
//    always @(posedge clk) begin
//      cos_opa <= coarse_cosp[17:0];
//      cos_opb <= {9'h00,fine_sin};
//      ccsf_ff <= cos_mult_res;
//    end


// Pipestate3
logic           cop, sop;
logic  [18:0]   sc, cc;
always @(posedge clk) begin
  sc <= coarse_sin;
  cc <= coarse_cos;
end

//Compute operation for correction factor
always @(posedge clk) begin
  case ({coarse_cos[18],coarse_sin[18],fine_sign_d1})
    3'b000: cop <= 1'b1;
    3'b001: cop <= 1'b0;
    3'b010: cop <= 1'b0;
    3'b011: cop <= 1'b1;
    3'b100: cop <= 1'b0;
    3'b101: cop <= 1'b1;
    3'b110: cop <= 1'b1;
    3'b111: cop <= 1'b0;
  endcase 
end

//Compute operation for correction factor
always @(posedge clk) begin
  case ({coarse_sin[18],coarse_cos[18],fine_sign_d1})
    3'b000: sop <= 1'b0;
    3'b001: sop <= 1'b1;
    3'b010: sop <= 1'b1;
    3'b011: sop <= 1'b0;
    3'b100: sop <= 1'b1;
    3'b101: sop <= 1'b0;
    3'b110: sop <= 1'b0;
    3'b111: sop <= 1'b1;
  endcase
end


//Pipestage4
always @(posedge clk) begin
  sin[17:0] <= sop ? (sc[17:0] - {1'b0,ccsf}) : (sc[17:0] + {1'b0,ccsf});
  cos[17:0] <= cop ? (cc[17:0] - {1'b0,scsf}) : (cc[17:0] + {1'b0,scsf});

  sin[18]   <= sc[18];
  cos[18]   <= cc[18];
end

endmodule
`timescale 1us/1ns

module nco1 (
  clk,
  rst,
  phi,
  cos,
  sin
);

input             clk;
input             rst;
input     [31:0]  phi;
output    [18:0]  sin;
output    [18:0]  cos;

logic [31:0]      angle = 32'h00;

parameter         CALCTYPE = 0;

always @(posedge clk) begin
  if (rst) angle <= 32'h00;
  else angle <= angle + phi;
end


sincos #(.CALCTYPE(CALCTYPE)) sincos_i (
  .clk(clk),
  .angle(angle[31:12]),
  .cos(cos),
  .sin(sin)
);

endmodule 



`timescale 1us/1ns

module mixtx1 (
  clk,
  rst,
  phi,
  i_sig,
  q_sig,
  i_result,
  q_result
);

input                 clk;
input                 rst;
input         [31:0]  phi;
input  signed [17:0]  i_sig;
input  signed [17:0]  q_sig;
output signed [17:0]  i_result;
output signed [17:0]  q_result;

logic         [18:0]  sin, ssin;
logic         [18:0]  cos, scos;

logic  signed [17:0]  ssin_q, scos_q;
logic  signed [35:0]  qa_data_d, qb_data_d;
logic  signed [19:0]  q_data_d;
logic  signed [35:0]  ia_data_d, ib_data_d;
logic  signed [19:0]  i_data_d;
logic  signed [17:0]  i_rounded, q_rounded;

nco1 #(.CALCTYPE(3)) nco1_i (
  .clk(clk),
  .rst(rst),
  .phi(phi),
  .cos(cos),
  .sin(sin)
);

assign ssin = {sin[18],~sin[17:0]} + 19'h01;
assign scos = {cos[18],~cos[17:0]} + 19'h01;

always @(posedge clk) begin
  ssin_q <= sin[18] ? ssin[18:1] : sin[18:1];
  scos_q <= cos[18] ? scos[18:1] : cos[18:1];
end

always @(posedge clk) begin
  qa_data_d <= $signed(i_sig) * ssin_q;
  qb_data_d <= $signed(q_sig) * scos_q;
end

always @(posedge clk) begin
  ia_data_d <= $signed(i_sig) * scos_q;
  ib_data_d <= $signed(q_sig) * ssin_q;
end

assign i_data_d = ia_data_d[34:15] - ib_data_d[34:15];
assign q_data_d = qa_data_d[34:15] + qb_data_d[34:15];

always @(posedge clk) begin
  i_rounded <= i_data_d[19:2] + {17'h00,i_data_d[1]};
  q_rounded <= q_data_d[19:2] + {17'h00,q_data_d[1]};
end

assign i_result = i_rounded;
assign q_result = q_rounded;


endmodule 




module finerom (
  address,
  clock,
  q);

  parameter init_file = "missing.txt";

  input [8:0]  address;
  input   clock;
  output reg [8:0]  q;

  reg [8:0] rom[511:0];

  initial
  begin
    $readmemb(init_file, rom);
  end

  always @ (posedge clock)
  begin
    q <= rom[address];
  end

endmodule


module coarserom (
  address,
  clock,
  q);

  parameter init_file = "missing.txt";

  input [7:0]  address;
  input   clock;
  output reg [35:0]  q;

  reg [35:0] rom[255:0];

  initial
  begin
    $readmemb(init_file, rom);
  end

  always @ (posedge clock)
  begin
    q <= rom[address];
  end

endmodule

`timescale 1us/1ns

module mix1 (
  clk,
  rst,
  phi,
  adc,
  i_data,
  q_data
);

input                 clk;
input                 rst;
input         [31:0]  phi;
input  signed [11:0]  adc;
output signed [17:0]  i_data;
output signed [17:0]  q_data;

logic         [18:0]  sin, ssin;
logic         [18:0]  cos, scos;

logic  signed [17:0]  ssin_q, scos_q;
logic  signed [35:0]  i_data_d, q_data_d;  

nco1 #(.CALCTYPE(3)) nco1_i (
  .clk(clk),
  .rst(rst),
  .phi(phi),
  .cos(cos),
  .sin(sin)
);

assign ssin = {sin[18],~sin[17:0]} + 19'h01;
assign scos = {cos[18],~cos[17:0]} + 19'h01;

always @(posedge clk) begin
  ssin_q <= sin[18] ? ssin[18:1] : sin[18:1];
  scos_q <= cos[18] ? scos[18:1] : cos[18:1];
end


always @(posedge clk) begin
  i_data_d <= $signed(adc) * scos_q;
  q_data_d <= $signed(adc) * ssin_q;
end

assign i_data = i_data_d[28:11] + {17'h00,i_data_d[10]};
assign q_data = q_data_d[28:11] + {17'h00,q_data_d[10]};

endmodule 



`timescale 1us/1ns

module mix2 (
  clk,
  clk_2x,
  rst,
  phi0,
  phi1,
  adc,
  mixdata0_i,
  mixdata0_q,
  mixdata1_i,
  mixdata1_q
);

input                 clk;
input                 clk_2x;
input                 rst;
input         [31:0]  phi0;
input         [31:0]  phi1;
input  signed [11:0]  adc;
output logic signed [17:0]  mixdata0_i; //dh 
output logic signed [17:0]  mixdata0_q;	//dh 
output logic signed [17:0]  mixdata1_i;	//dh 
output logic signed [17:0]  mixdata1_q;	//dh 

parameter CALCTYPE = 0;

logic         [18:0]  sin, ssin;
logic         [18:0]  cos, scos;

logic  signed [17:0]  ssin_q, scos_q;
logic  signed [35:0]  i_data_d, q_data_d;  
logic  signed [18:0]  i_rounded, q_rounded;

logic signed  [11:0]  adci, adcq;

logic                 state = 1'b0;


nco2 #(.CALCTYPE(CALCTYPE)) nco2_i (
  .state(state),
  .clk_2x(clk_2x),
  .rst(rst),
  .phi0(phi0),
  .phi1(phi1),
  .cos(cos),
  .sin(sin)
);

always @(posedge clk_2x) begin
  state <= ~state;
end

assign ssin = {sin[18],~sin[17:0]} + 19'h01;
assign scos = {cos[18],~cos[17:0]} + 19'h01;

always @(posedge clk_2x) begin
  ssin_q <= sin[18] ? ssin[18:1] : sin[18:1];
  scos_q <= cos[18] ? scos[18:1] : cos[18:1];
end

always @(posedge clk_2x) begin
  adci <= adc;
  adcq <= adc;
end

always @(posedge clk_2x) begin
  i_data_d <= $signed(adci) * scos_q;
  q_data_d <= $signed(adcq) * ssin_q;
end

assign i_rounded = i_data_d[28:11] + {17'h00,i_data_d[10]};
assign q_rounded = q_data_d[28:11] + {17'h00,q_data_d[10]};

always @(posedge clk_2x) begin
  if (~state) begin
    mixdata0_i <= i_rounded;
    mixdata0_q <= q_rounded;
  end else begin
    mixdata1_i <= i_rounded;
    mixdata1_q <= q_rounded;
  end
end

endmodule 


// megafunction wizard: %ALTPLL%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altpll 

// ============================================================
// File Name: ethpll.v
// Megafunction Name(s):
// 			altpll
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 16.1.2 Build 203 01/18/2017 SJ Lite Edition
// ************************************************************


//Copyright (C) 2017  Intel Corporation. All rights reserved.
//Your use of Intel Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Intel Program License 
//Subscription Agreement, the Intel Quartus Prime License Agreement,
//the Intel MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Intel and sold by Intel or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module ethpll (
	inclk0,
	c0,
	c1,
	c2,
	c3,
	c4,
	locked);

	input	  inclk0;
	output	  c0;
	output	  c1;
	output	  c2;
	output	  c3;
	output	  c4;
	output	  locked;
/*
	wire [0:0] sub_wire2 = 1'h0;
	wire [4:0] sub_wire3;
	wire  sub_wire9;
	wire  sub_wire0 = inclk0;
	wire [1:0] sub_wire1 = {sub_wire2, sub_wire0};
	wire [4:4] sub_wire8 = sub_wire3[4:4];
	wire [3:3] sub_wire7 = sub_wire3[3:3];
	wire [2:2] sub_wire6 = sub_wire3[2:2];
	wire [1:1] sub_wire5 = sub_wire3[1:1];
	wire [0:0] sub_wire4 = sub_wire3[0:0];
	wire  c0 = sub_wire4;
	wire  c1 = sub_wire5;
	wire  c2 = sub_wire6;
	wire  c3 = sub_wire7;
	wire  c4 = sub_wire8;
	wire  locked = sub_wire9;

	altpll	altpll_component (
				.inclk (sub_wire1),
				.clk (sub_wire3),
				.locked (sub_wire9),
				.activeclock (),
				.areset (1'b0),
				.clkbad (),
				.clkena ({6{1'b1}}),
				.clkloss (),
				.clkswitch (1'b0),
				.configupdate (1'b0),
				.enable0 (),
				.enable1 (),
				.extclk (),
				.extclkena ({4{1'b1}}),
				.fbin (1'b1),
				.fbmimicbidir (),
				.fbout (),
				.fref (),
				.icdrclk (),
				.pfdena (1'b1),
				.phasecounterselect ({4{1'b1}}),
				.phasedone (),
				.phasestep (1'b1),
				.phaseupdown (1'b1),
				.pllena (1'b1),
				.scanaclr (1'b0),
				.scanclk (1'b0),
				.scanclkena (1'b1),
				.scandata (1'b0),
				.scandataout (),
				.scandone (),
				.scanread (1'b0),
				.scanwrite (1'b0),
				.sclkout0 (),
				.sclkout1 (),
				.vcooverrange (),
				.vcounderrange ());
	defparam
		altpll_component.bandwidth_type = "AUTO",
		altpll_component.clk0_divide_by = 1,
		altpll_component.clk0_duty_cycle = 50,
		altpll_component.clk0_multiply_by = 1,
		altpll_component.clk0_phase_shift = "0",
		altpll_component.clk1_divide_by = 1,
		altpll_component.clk1_duty_cycle = 50,
		altpll_component.clk1_multiply_by = 1,
		altpll_component.clk1_phase_shift = "3000",
		altpll_component.clk2_divide_by = 50,
		altpll_component.clk2_duty_cycle = 50,
		altpll_component.clk2_multiply_by = 1,
		altpll_component.clk2_phase_shift = "0",
		altpll_component.clk3_divide_by = 5,
		altpll_component.clk3_duty_cycle = 50,
		altpll_component.clk3_multiply_by = 1,
		altpll_component.clk3_phase_shift = "11000",
		altpll_component.clk4_divide_by = 10,
		altpll_component.clk4_duty_cycle = 50,
		altpll_component.clk4_multiply_by = 1,
		altpll_component.clk4_phase_shift = "0",
		altpll_component.compensate_clock = "CLK0",
		altpll_component.inclk0_input_frequency = 8000,
		altpll_component.intended_device_family = "Cyclone IV E",
		altpll_component.lpm_hint = "CBX_MODULE_PREFIX=ethpll",
		altpll_component.lpm_type = "altpll",
		altpll_component.operation_mode = "NORMAL",
		altpll_component.pll_type = "AUTO",
		altpll_component.port_activeclock = "PORT_UNUSED",
		altpll_component.port_areset = "PORT_UNUSED",
		altpll_component.port_clkbad0 = "PORT_UNUSED",
		altpll_component.port_clkbad1 = "PORT_UNUSED",
		altpll_component.port_clkloss = "PORT_UNUSED",
		altpll_component.port_clkswitch = "PORT_UNUSED",
		altpll_component.port_configupdate = "PORT_UNUSED",
		altpll_component.port_fbin = "PORT_UNUSED",
		altpll_component.port_inclk0 = "PORT_USED",
		altpll_component.port_inclk1 = "PORT_UNUSED",
		altpll_component.port_locked = "PORT_USED",
		altpll_component.port_pfdena = "PORT_UNUSED",
		altpll_component.port_phasecounterselect = "PORT_UNUSED",
		altpll_component.port_phasedone = "PORT_UNUSED",
		altpll_component.port_phasestep = "PORT_UNUSED",
		altpll_component.port_phaseupdown = "PORT_UNUSED",
		altpll_component.port_pllena = "PORT_UNUSED",
		altpll_component.port_scanaclr = "PORT_UNUSED",
		altpll_component.port_scanclk = "PORT_UNUSED",
		altpll_component.port_scanclkena = "PORT_UNUSED",
		altpll_component.port_scandata = "PORT_UNUSED",
		altpll_component.port_scandataout = "PORT_UNUSED",
		altpll_component.port_scandone = "PORT_UNUSED",
		altpll_component.port_scanread = "PORT_UNUSED",
		altpll_component.port_scanwrite = "PORT_UNUSED",
		altpll_component.port_clk0 = "PORT_USED",
		altpll_component.port_clk1 = "PORT_USED",
		altpll_component.port_clk2 = "PORT_USED",
		altpll_component.port_clk3 = "PORT_USED",
		altpll_component.port_clk4 = "PORT_USED",
		altpll_component.port_clk5 = "PORT_UNUSED",
		altpll_component.port_clkena0 = "PORT_UNUSED",
		altpll_component.port_clkena1 = "PORT_UNUSED",
		altpll_component.port_clkena2 = "PORT_UNUSED",
		altpll_component.port_clkena3 = "PORT_UNUSED",
		altpll_component.port_clkena4 = "PORT_UNUSED",
		altpll_component.port_clkena5 = "PORT_UNUSED",
		altpll_component.port_extclk0 = "PORT_UNUSED",
		altpll_component.port_extclk1 = "PORT_UNUSED",
		altpll_component.port_extclk2 = "PORT_UNUSED",
		altpll_component.port_extclk3 = "PORT_UNUSED",
		altpll_component.self_reset_on_loss_lock = "OFF",
		altpll_component.width_clock = 5;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ACTIVECLK_CHECK STRING "0"
// Retrieval info: PRIVATE: BANDWIDTH STRING "1.000"
// Retrieval info: PRIVATE: BANDWIDTH_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: BANDWIDTH_FREQ_UNIT STRING "MHz"
// Retrieval info: PRIVATE: BANDWIDTH_PRESET STRING "Low"
// Retrieval info: PRIVATE: BANDWIDTH_USE_AUTO STRING "1"
// Retrieval info: PRIVATE: BANDWIDTH_USE_PRESET STRING "0"
// Retrieval info: PRIVATE: CLKBAD_SWITCHOVER_CHECK STRING "0"
// Retrieval info: PRIVATE: CLKLOSS_CHECK STRING "0"
// Retrieval info: PRIVATE: CLKSWITCH_CHECK STRING "0"
// Retrieval info: PRIVATE: CNX_NO_COMPENSATE_RADIO STRING "0"
// Retrieval info: PRIVATE: CREATE_CLKBAD_CHECK STRING "0"
// Retrieval info: PRIVATE: CREATE_INCLK1_CHECK STRING "0"
// Retrieval info: PRIVATE: CUR_DEDICATED_CLK STRING "c0"
// Retrieval info: PRIVATE: CUR_FBIN_CLK STRING "c0"
// Retrieval info: PRIVATE: DEVICE_SPEED_GRADE STRING "8"
// Retrieval info: PRIVATE: DIV_FACTOR0 NUMERIC "1"
// Retrieval info: PRIVATE: DIV_FACTOR1 NUMERIC "1"
// Retrieval info: PRIVATE: DIV_FACTOR2 NUMERIC "1"
// Retrieval info: PRIVATE: DIV_FACTOR3 NUMERIC "1"
// Retrieval info: PRIVATE: DIV_FACTOR4 NUMERIC "1"
// Retrieval info: PRIVATE: DUTY_CYCLE0 STRING "50.00000000"
// Retrieval info: PRIVATE: DUTY_CYCLE1 STRING "50.00000000"
// Retrieval info: PRIVATE: DUTY_CYCLE2 STRING "50.00000000"
// Retrieval info: PRIVATE: DUTY_CYCLE3 STRING "50.00000000"
// Retrieval info: PRIVATE: DUTY_CYCLE4 STRING "50.00000000"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE0 STRING "125.000000"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE1 STRING "125.000000"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE2 STRING "2.500000"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE3 STRING "25.000000"
// Retrieval info: PRIVATE: EFF_OUTPUT_FREQ_VALUE4 STRING "12.500000"
// Retrieval info: PRIVATE: EXPLICIT_SWITCHOVER_COUNTER STRING "0"
// Retrieval info: PRIVATE: EXT_FEEDBACK_RADIO STRING "0"
// Retrieval info: PRIVATE: GLOCKED_COUNTER_EDIT_CHANGED STRING "1"
// Retrieval info: PRIVATE: GLOCKED_FEATURE_ENABLED STRING "0"
// Retrieval info: PRIVATE: GLOCKED_MODE_CHECK STRING "0"
// Retrieval info: PRIVATE: GLOCK_COUNTER_EDIT NUMERIC "1048575"
// Retrieval info: PRIVATE: HAS_MANUAL_SWITCHOVER STRING "1"
// Retrieval info: PRIVATE: INCLK0_FREQ_EDIT STRING "125.000"
// Retrieval info: PRIVATE: INCLK0_FREQ_UNIT_COMBO STRING "MHz"
// Retrieval info: PRIVATE: INCLK1_FREQ_EDIT STRING "100.000"
// Retrieval info: PRIVATE: INCLK1_FREQ_EDIT_CHANGED STRING "1"
// Retrieval info: PRIVATE: INCLK1_FREQ_UNIT_CHANGED STRING "1"
// Retrieval info: PRIVATE: INCLK1_FREQ_UNIT_COMBO STRING "MHz"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: INT_FEEDBACK__MODE_RADIO STRING "1"
// Retrieval info: PRIVATE: LOCKED_OUTPUT_CHECK STRING "1"
// Retrieval info: PRIVATE: LONG_SCAN_RADIO STRING "1"
// Retrieval info: PRIVATE: LVDS_MODE_DATA_RATE STRING "Not Available"
// Retrieval info: PRIVATE: LVDS_MODE_DATA_RATE_DIRTY NUMERIC "0"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT0 STRING "deg"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT1 STRING "deg"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT2 STRING "deg"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT3 STRING "ps"
// Retrieval info: PRIVATE: LVDS_PHASE_SHIFT_UNIT4 STRING "ps"
// Retrieval info: PRIVATE: MIG_DEVICE_SPEED_GRADE STRING "Any"
// Retrieval info: PRIVATE: MIRROR_CLK0 STRING "0"
// Retrieval info: PRIVATE: MIRROR_CLK1 STRING "0"
// Retrieval info: PRIVATE: MIRROR_CLK2 STRING "0"
// Retrieval info: PRIVATE: MIRROR_CLK3 STRING "0"
// Retrieval info: PRIVATE: MIRROR_CLK4 STRING "0"
// Retrieval info: PRIVATE: MULT_FACTOR0 NUMERIC "1"
// Retrieval info: PRIVATE: MULT_FACTOR1 NUMERIC "1"
// Retrieval info: PRIVATE: MULT_FACTOR2 NUMERIC "1"
// Retrieval info: PRIVATE: MULT_FACTOR3 NUMERIC "1"
// Retrieval info: PRIVATE: MULT_FACTOR4 NUMERIC "1"
// Retrieval info: PRIVATE: NORMAL_MODE_RADIO STRING "1"
// Retrieval info: PRIVATE: OUTPUT_FREQ0 STRING "100.00000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ1 STRING "100.00000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ2 STRING "2.50000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ3 STRING "25.00000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ4 STRING "12.50000000"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE0 STRING "0"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE1 STRING "0"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE2 STRING "1"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE3 STRING "1"
// Retrieval info: PRIVATE: OUTPUT_FREQ_MODE4 STRING "1"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT0 STRING "MHz"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT1 STRING "MHz"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT2 STRING "MHz"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT3 STRING "MHz"
// Retrieval info: PRIVATE: OUTPUT_FREQ_UNIT4 STRING "MHz"
// Retrieval info: PRIVATE: PHASE_RECONFIG_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: PHASE_RECONFIG_INPUTS_CHECK STRING "0"
// Retrieval info: PRIVATE: PHASE_SHIFT0 STRING "0.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT1 STRING "135.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT2 STRING "0.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT3 STRING "99.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT4 STRING "0.00000000"
// Retrieval info: PRIVATE: PHASE_SHIFT_STEP_ENABLED_CHECK STRING "0"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT0 STRING "deg"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT1 STRING "deg"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT2 STRING "deg"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT3 STRING "deg"
// Retrieval info: PRIVATE: PHASE_SHIFT_UNIT4 STRING "ps"
// Retrieval info: PRIVATE: PLL_ADVANCED_PARAM_CHECK STRING "0"
// Retrieval info: PRIVATE: PLL_ARESET_CHECK STRING "0"
// Retrieval info: PRIVATE: PLL_AUTOPLL_CHECK NUMERIC "1"
// Retrieval info: PRIVATE: PLL_ENHPLL_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PLL_FASTPLL_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PLL_FBMIMIC_CHECK STRING "0"
// Retrieval info: PRIVATE: PLL_LVDS_PLL_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PLL_PFDENA_CHECK STRING "0"
// Retrieval info: PRIVATE: PLL_TARGET_HARCOPY_CHECK NUMERIC "0"
// Retrieval info: PRIVATE: PRIMARY_CLK_COMBO STRING "inclk0"
// Retrieval info: PRIVATE: RECONFIG_FILE STRING "ethpll.mif"
// Retrieval info: PRIVATE: SACN_INPUTS_CHECK STRING "0"
// Retrieval info: PRIVATE: SCAN_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: SELF_RESET_LOCK_LOSS STRING "0"
// Retrieval info: PRIVATE: SHORT_SCAN_RADIO STRING "0"
// Retrieval info: PRIVATE: SPREAD_FEATURE_ENABLED STRING "0"
// Retrieval info: PRIVATE: SPREAD_FREQ STRING "50.000"
// Retrieval info: PRIVATE: SPREAD_FREQ_UNIT STRING "KHz"
// Retrieval info: PRIVATE: SPREAD_PERCENT STRING "0.500"
// Retrieval info: PRIVATE: SPREAD_USE STRING "0"
// Retrieval info: PRIVATE: SRC_SYNCH_COMP_RADIO STRING "0"
// Retrieval info: PRIVATE: STICKY_CLK0 STRING "1"
// Retrieval info: PRIVATE: STICKY_CLK1 STRING "1"
// Retrieval info: PRIVATE: STICKY_CLK2 STRING "1"
// Retrieval info: PRIVATE: STICKY_CLK3 STRING "1"
// Retrieval info: PRIVATE: STICKY_CLK4 STRING "1"
// Retrieval info: PRIVATE: SWITCHOVER_COUNT_EDIT NUMERIC "1"
// Retrieval info: PRIVATE: SWITCHOVER_FEATURE_ENABLED STRING "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: USE_CLK0 STRING "1"
// Retrieval info: PRIVATE: USE_CLK1 STRING "1"
// Retrieval info: PRIVATE: USE_CLK2 STRING "1"
// Retrieval info: PRIVATE: USE_CLK3 STRING "1"
// Retrieval info: PRIVATE: USE_CLK4 STRING "1"
// Retrieval info: PRIVATE: USE_CLKENA0 STRING "0"
// Retrieval info: PRIVATE: USE_CLKENA1 STRING "0"
// Retrieval info: PRIVATE: USE_CLKENA2 STRING "0"
// Retrieval info: PRIVATE: USE_CLKENA3 STRING "0"
// Retrieval info: PRIVATE: USE_CLKENA4 STRING "0"
// Retrieval info: PRIVATE: USE_MIL_SPEED_GRADE NUMERIC "0"
// Retrieval info: PRIVATE: ZERO_DELAY_RADIO STRING "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: BANDWIDTH_TYPE STRING "AUTO"
// Retrieval info: CONSTANT: CLK0_DIVIDE_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK0_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK0_MULTIPLY_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK0_PHASE_SHIFT STRING "0"
// Retrieval info: CONSTANT: CLK1_DIVIDE_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK1_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK1_MULTIPLY_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK1_PHASE_SHIFT STRING "3000"
// Retrieval info: CONSTANT: CLK2_DIVIDE_BY NUMERIC "50"
// Retrieval info: CONSTANT: CLK2_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK2_MULTIPLY_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK2_PHASE_SHIFT STRING "0"
// Retrieval info: CONSTANT: CLK3_DIVIDE_BY NUMERIC "5"
// Retrieval info: CONSTANT: CLK3_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK3_MULTIPLY_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK3_PHASE_SHIFT STRING "11000"
// Retrieval info: CONSTANT: CLK4_DIVIDE_BY NUMERIC "10"
// Retrieval info: CONSTANT: CLK4_DUTY_CYCLE NUMERIC "50"
// Retrieval info: CONSTANT: CLK4_MULTIPLY_BY NUMERIC "1"
// Retrieval info: CONSTANT: CLK4_PHASE_SHIFT STRING "0"
// Retrieval info: CONSTANT: COMPENSATE_CLOCK STRING "CLK0"
// Retrieval info: CONSTANT: INCLK0_INPUT_FREQUENCY NUMERIC "8000"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altpll"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "NORMAL"
// Retrieval info: CONSTANT: PLL_TYPE STRING "AUTO"
// Retrieval info: CONSTANT: PORT_ACTIVECLOCK STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_ARESET STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CLKBAD0 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CLKBAD1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CLKLOSS STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CLKSWITCH STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_CONFIGUPDATE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_FBIN STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_INCLK0 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_INCLK1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_LOCKED STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_PFDENA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASECOUNTERSELECT STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASEDONE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASESTEP STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PHASEUPDOWN STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_PLLENA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANACLR STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANCLK STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANCLKENA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANDATA STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANDATAOUT STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANDONE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANREAD STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_SCANWRITE STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clk0 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk1 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk2 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk3 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk4 STRING "PORT_USED"
// Retrieval info: CONSTANT: PORT_clk5 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena0 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena2 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena3 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena4 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_clkena5 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk0 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk1 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk2 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: PORT_extclk3 STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: SELF_RESET_ON_LOSS_LOCK STRING "OFF"
// Retrieval info: CONSTANT: WIDTH_CLOCK NUMERIC "5"
// Retrieval info: USED_PORT: @clk 0 0 5 0 OUTPUT_CLK_EXT VCC "@clk[4..0]"
// Retrieval info: USED_PORT: c0 0 0 0 0 OUTPUT_CLK_EXT VCC "c0"
// Retrieval info: USED_PORT: c1 0 0 0 0 OUTPUT_CLK_EXT VCC "c1"
// Retrieval info: USED_PORT: c2 0 0 0 0 OUTPUT_CLK_EXT VCC "c2"
// Retrieval info: USED_PORT: c3 0 0 0 0 OUTPUT_CLK_EXT VCC "c3"
// Retrieval info: USED_PORT: c4 0 0 0 0 OUTPUT_CLK_EXT VCC "c4"
// Retrieval info: USED_PORT: inclk0 0 0 0 0 INPUT_CLK_EXT GND "inclk0"
// Retrieval info: USED_PORT: locked 0 0 0 0 OUTPUT GND "locked"
// Retrieval info: CONNECT: @inclk 0 0 1 1 GND 0 0 0 0
// Retrieval info: CONNECT: @inclk 0 0 1 0 inclk0 0 0 0 0
// Retrieval info: CONNECT: c0 0 0 0 0 @clk 0 0 1 0
// Retrieval info: CONNECT: c1 0 0 0 0 @clk 0 0 1 1
// Retrieval info: CONNECT: c2 0 0 0 0 @clk 0 0 1 2
// Retrieval info: CONNECT: c3 0 0 0 0 @clk 0 0 1 3
// Retrieval info: CONNECT: c4 0 0 0 0 @clk 0 0 1 4
// Retrieval info: CONNECT: locked 0 0 0 0 @locked 0 0 0 0
// Retrieval info: GEN_FILE: TYPE_NORMAL ethpll.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ethpll.ppf TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ethpll.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ethpll.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ethpll.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ethpll_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ethpll_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
// Retrieval info: CBX_MODULE_PREFIX: ON


module cw_support(
  clk,
  millisec_pulse,
  cw_hang_time,
  dot_key,
  dash_key,
  dot_key_debounced,
  dash_key_debounced,
  cw_power_on,
  cw_keydown
);

input         clk;
input         millisec_pulse;

input [9:0]   cw_hang_time;

input         dot_key;
input         dash_key;

input         dot_key_debounced;
input         dash_key_debounced;

output logic  cw_power_on = 1'b0;
output        cw_keydown;


// TX sequence logic. Delay CW envelope until T/R relay switches and the amp power turns on.
logic [16:0] cw_delay_line = 17'b0; // Delay CW press/release one mSec per unit. There is additional delay from debounce ext_cwkey.
logic [9:0]  cw_power_timeout = 10'b0;  // Keep power on after the key goes up. Delay is one mSec per count starting from key down.
logic        cw_count_state;    // State 0: first count for KEY_UP_TIMEOUT; State 1: second count for cw_hang_time.
localparam KEY_UP_TIMEOUT = 10'd41; // Minimum timeout. Must be the delay line time plus waveform decay time plus ending time.


always @(posedge clk)       // Delay the CW key press and release while preserving the timing.
  if (millisec_pulse)
    cw_delay_line <= {cw_delay_line[15:0], dot_key_debounced};
assign cw_keydown = cw_delay_line[16];

always @(posedge clk) begin   // Turn on CW power and T/R relay at first key press and hold for the delay time.
  if (dot_key) begin      // Start timing when the key first goes down.
    cw_power_timeout <= KEY_UP_TIMEOUT;
    cw_count_state <= 1'b0;
    cw_power_on <= 1'b1;
  end else if (millisec_pulse) begin  // Check every millisecond
    if (cw_power_timeout != 0) begin
      cw_power_timeout <= cw_power_timeout - 1'b1;
    end else if (cw_count_state == 1'b0) begin  // First count for KEY_UP_TIMEOUT, the minimum count.
      cw_power_timeout <= cw_hang_time;
      cw_count_state <= 1'b1;
    end else begin    // Second count for extra time cw_hang_time.
      cw_power_on <= 1'b0;
    end
  end
end

endmodule
module led_flash (
  clk,
  cnt,
  sig,
  led
);
input       clk;
input       cnt;
input       sig;
output logic led; //dh

localparam  STATE_CLR   = 2'b00,
            STATE_SET   = 2'b01,
            STATE_WAIT1 = 2'b10,
            STATE_WAIT2 = 2'b11;

logic [1:0] state = STATE_CLR;
logic [1:0] state_next;

always @(posedge clk) state <= state_next;

// LED remains on for 2-3 ticks of cnt
always @* begin
  state_next = state;
  
  case (state)
    STATE_CLR: begin
      led = 1'b1; // 1 clears LED
      if (sig) state_next = STATE_SET;
    end

    STATE_SET: begin
      led = 1'b0;
      if (cnt) state_next = STATE_WAIT1;
    end 

    STATE_WAIT1: begin
      led = 1'b0;
      if (cnt) state_next = STATE_WAIT2;
    end

    STATE_WAIT2: begin
      led = 1'b0;
      if (cnt) state_next = STATE_CLR;
    end
  endcase 
end 

endmodule 



module control(
  // Internal
  clk,
  clk_ad9866,
  clk_125,
  
  ethup,
  have_dhcp_ip,
  have_fixed_ip,
  network_speed,
  ad9866up,

  rxclip,
  rxgoodlvl,
  rxclrstatus,
  run,
  tx_hang,

  cmd_addr,
  cmd_data,
  cmd_rqst,
  cmd_requires_resp,
  cmd_ptt,

  tx_on,
  cw_keydown,

  resp_rqst,
  resp,

  // External
  rffe_rfsw_sel,

  rffe_ad9866_rst_n,
  rffe_ad9866_sdio,
  rffe_ad9866_sclk,
  rffe_ad9866_sen_n,

`ifdef BETA2
  rffe_ad9866_pga,
`else
  rffe_ad9866_pga5,
`endif

  // Power
  pwr_clk3p3,
  pwr_clk1p2,
  pwr_envpa, 

`ifdef BETA2
  pwr_clkvpa,
`else
  pwr_envop,
  pwr_envbias,
`endif

  // Clock
  clk_recovered,

  sda1_i,
  sda1_o,
  sda1_t,
  scl1_i,
  scl1_o,
  scl1_t,

  sda2_i,
  sda2_o,
  sda2_t,
  scl2_i,
  scl2_o,
  scl2_t,

  sda3_i,
  sda3_o,
  sda3_t,
  scl3_i,
  scl3_o,
  scl3_t,

  // IO
  io_led_d2,
  io_led_d3,
  io_led_d4,
  io_led_d5,
  io_lvds_rxn,
  io_lvds_rxp,
  //io_lvds_txn,
 // io_lvds_txp,
  io_cn8,
  io_cn9,
  io_cn10,

  io_db1_2,       // BETA2,BETA3: io_db24
  io_db1_3,       // BETA2,BETA3: io_db22_3
  io_db1_4,       // BETA2,BETA3: io_db22_2
  io_db1_5,       // BETA2,BETA3: io_cn4_6
  io_db1_6,       // BETA2,BETA3: io_cn4_7    
  io_phone_tip,   // BETA2,BETA3: io_cn4_2
  io_phone_ring,  // BETA2,BETA3: io_cn4_3
  io_tp2,
  
`ifndef BETA2
  io_tp7,
  io_tp8,  
  io_tp9,
`endif

  // PA
`ifdef BETA2
  pa_tr,
  pa_en
`else
  pa_inttr,
  pa_exttr
`endif
);

// Internal
input           clk;
input           clk_ad9866;
input           clk_125;

input           ethup;
input           have_dhcp_ip;
input           have_fixed_ip;
input  [1:0]    network_speed;
input           ad9866up;

input           rxclip;
input           rxgoodlvl;
output logic    rxclrstatus = 1'b0;
input           run;
input           tx_hang;

input  [5:0]    cmd_addr;
input  [31:0]   cmd_data;
input           cmd_rqst;
input           cmd_requires_resp;
input           cmd_ptt;

output          tx_on;
output          cw_keydown;

input           resp_rqst;
output [39:0]   resp;

// External
output          rffe_rfsw_sel;

output          rffe_ad9866_rst_n;

output          rffe_ad9866_sdio;
output          rffe_ad9866_sclk;
output          rffe_ad9866_sen_n;

`ifdef BETA2
output  [5:0]   rffe_ad9866_pga;
`else
output          rffe_ad9866_pga5;
`endif

// Power
output logic    pwr_clk3p3 = 1'b0;
output logic    pwr_clk1p2 = 1'b0;
output          pwr_envpa; 

`ifdef BETA2
output          pwr_clkvpa;
`else
output          pwr_envop;
output          pwr_envbias;
`endif

// Clock
output          clk_recovered;

input           sda1_i;
output          sda1_o;
output          sda1_t;
input           scl1_i;
output          scl1_o;
output          scl1_t;

input           sda2_i;
output          sda2_o;
output          sda2_t;
input           scl2_i;
output          scl2_o;
output          scl2_t;

input           sda3_i;
output          sda3_o;
output          sda3_t;
input           scl3_i;
output          scl3_o;
output          scl3_t;

// IO
output          io_led_d2;
output          io_led_d3;
output          io_led_d4;
output          io_led_d5;
input           io_lvds_rxn;
input           io_lvds_rxp;
//input           io_lvds_txn;
//input           io_lvds_txp;
input           io_cn8;
input           io_cn9;
input           io_cn10;

input           io_db1_2;       // BETA2;BETA3: io_db24
input           io_db1_3;       // BETA2;BETA3: io_db22_3
input           io_db1_4;       // BETA2;BETA3: io_db22_2
output          io_db1_5;       // BETA2;BETA3: io_cn4_6
input           io_db1_6;       // BETA2;BETA3: io_cn4_7    
input           io_phone_tip;   // BETA2;BETA3: io_cn4_2
input           io_phone_ring;  // BETA2;BETA3: io_cn4_3
input           io_tp2;
  
`ifndef BETA2
input           io_tp7;
input           io_tp8;  
input           io_tp9;
`endif

  // PA
`ifdef BETA2
output          pa_tr;
output          pa_en;
`else
output          pa_inttr;
output          pa_exttr;
`endif

parameter     HERMES_SERIALNO = 8'h0;


logic         vna = 1'b0;                    // Selects vna mode when set.
logic         pa_enable = 1'b0;
logic         tr_disable = 1'b0;
logic [9:0]   cw_hang_time;

logic [11:0]  fwd_pwr;
logic [11:0]  rev_pwr;
logic [11:0]  bias_current;
logic [11:0]  temperature;  

logic         cmd_ack_i2c, cmd_ack_ad9866;
logic         ptt;

logic [39:0]  iresp = {8'h00, 8'b00011110, 8'h00, 8'h00, HERMES_SERIALNO};
logic [ 1:0]  resp_addr = 2'b00;

logic         cmd_resp_rqst;

logic         cmd_ack;
logic [ 5:0]  resp_cmd_addr = 6'h00, resp_cmd_addr_next;
logic [31:0]  resp_cmd_data = 32'h00, resp_cmd_data_next;

logic         int_ptt = 1'b0;

logic [8:0]   led_count;
logic         led_saturate;
logic [11:0]  millisec_count;
logic         millisec_pulse;

logic         ext_txinhibit, ext_cwkey, ext_ptt;

logic         slow_adc_rst, ad9866_rst;
logic         clk_i2c_rst;
logic         clk_i2c_start;

logic [15:0]  resetcounter = 16'h0000;
logic         resetsaturate;

logic [ 1:0]  clip_cnt = 2'b00;

logic         led_d2, led_d3, led_d4, led_d5;

logic         disable_syncfreq = 1'b0;

logic [ 5:0]  pwrcnt = 6'h10;
//logic [ 2:0]  pwrphase = 3'b100;

  
localparam RESP_START   = 2'b00,
           RESP_ACK     = 2'b01,
           RESP_WAIT    = 2'b10;

logic [1:0]   resp_state = RESP_START, resp_state_next;


logic         cw_keydown;
logic         cw_power_on;




/////////////////////////////////////////////////////
// Reset

// Most FPGA logic is reset when ethernet is up and ad9866 PLL is locked
// AD9866 is released from reset

assign resetsaturate = &resetcounter;

always @ (posedge clk)
  if (~resetsaturate & ethup) resetcounter <= resetcounter + 16'h01;

// At ~410us
assign clk_i2c_rst = ~(|resetcounter[15:10]);

// At ~820us
assign clk_i2c_start = (|resetcounter[15:11]);

// At ~6.5ms
assign slow_adc_rst = ~(|resetcounter[15:14]);

// At ~13ms
assign rffe_ad9866_rst_n = resetcounter[15];

// At ~26ms
assign ad9866_rst = ~resetsaturate | ~ad9866up;



always @(posedge clk) begin
  if (cmd_rqst) begin
    int_ptt <= cmd_ptt;
    if (cmd_addr == 6'h09) begin
      vna          <= cmd_data[23];      // 1 = enable vna mode
      pa_enable    <= cmd_data[19];
      tr_disable   <= cmd_data[18];
    end
    else if (cmd_addr == 6'h10) begin
      cw_hang_time <= {cmd_data[31:24], cmd_data[17:16]};
    end
    else if (cmd_addr == 6'h00) begin
      disable_syncfreq <= cmd_data[12];
    end
  end
end


i2c i2c_i (
  .clk(clk),
  .rst(clk_i2c_rst),
  .init_start(clk_i2c_start),

  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_rqst(cmd_rqst),
  .cmd_ack(cmd_ack_i2c),

  .scl1_i(scl1_i),
  .scl1_o(scl1_o),
  .scl1_t(scl1_t),
  .sda1_i(sda1_i),
  .sda1_o(sda1_o),
  .sda1_t(sda1_t),
  .scl2_i(scl2_i),
  .scl2_o(scl2_o),
  .scl2_t(scl2_t),
  .sda2_i(sda2_i),
  .sda2_o(sda2_o),
  .sda2_t(sda2_t)
);

slow_adc slow_adc_i (
  .clk(clk),
  .rst(slow_adc_rst),
  .ain0(fwd_pwr),
  .ain1(temperature),
  .ain2(bias_current),
  .ain3(rev_pwr),
  .scl_i(scl3_i),
  .scl_o(scl3_o),
  .scl_t(scl3_t),
  .sda_i(sda3_i),
  .sda_o(sda3_o),
  .sda_t(sda3_t)
);



// 6.5 ms debounce with 2.5MHz clock 
debounce de_phone_tip(.clean_pb(ext_cwkey), .pb(~io_phone_tip), .clk(clk));
assign io_db1_5 = cw_keydown;

debounce de_phone_ring(.clean_pb(ext_ptt), .pb(~io_phone_ring), .clk(clk));
debounce de_txinhibit(.clean_pb(ext_txinhibit), .pb(~io_cn8), .clk(clk));


assign tx_on = (int_ptt | cw_keydown | ext_ptt | tx_hang) & ~ext_txinhibit & run;

// Gererate two slow pulses for timing.  millisec_pulse occurs every one millisecond.
// led_saturate occurs every 64 milliseconds.
always @(posedge clk) begin	// clock is 2.5 MHz
  if (millisec_count == 12'd2500) begin
    millisec_count <= 12'b0;
    millisec_pulse <= 1'b1;
    led_count <= led_count + 1'b1;
  end else begin
    millisec_count <= millisec_count + 1'b1;
    millisec_pulse <= 1'b0;
  end
end
assign led_saturate = &led_count[5:0];

//led_flash led_run(.clk(clk), .cnt(led_saturate), .sig(run), .led(io_led_d2));
//led_flash led_tx(.clk(clk), .cnt(led_saturate), .sig(tx_on), .led(io_led_d3));
led_flash led_rxgoodlvl(.clk(clk), .cnt(led_saturate), .sig(rxgoodlvl), .led(led_d4));
led_flash led_rxclip(.clk(clk), .cnt(led_saturate), .sig(rxclip), .led(led_d5));

// For test, measure the ad9866 clock, if it is 
logic [5:0] fast_clk_cnt;
always @(posedge clk_ad9866) begin
  // Count when 1x, at 76.8 MHz we should see 62 ticks when 1x is true
  if (millisec_count[1] & ~(&fast_clk_cnt)) fast_clk_cnt <= fast_clk_cnt + 6'h01;
  // Clear when 01 to prepare for next count
  else if (millisec_count[0]) fast_clk_cnt <= 6'h00;
end

logic good_fast_clk;
always @(posedge clk) begin
  // Compute when 00
  if (millisec_count[1:0] == 2'b00) good_fast_clk <= ~(&fast_clk_cnt);
end

// Solid when connected to software
// Blinking to indicate good ethernet clock
assign io_led_d2 = run ? ~run : ~(ethup & led_count[8]);

// Blinking indicates fixed ip, solid indicates dhcp
assign io_led_d3 = run ? ~tx_on : ~((have_fixed_ip & led_count[8]) | have_dhcp_ip); 

// Blinks if 100 Mbps, solid if 1Gbs, off otherwise
assign io_led_d4 = run ? led_d4 : ~(((network_speed == 2'b01) & led_count[8]) | network_speed == 2'b10);

// Lights if ad9866 is up and the  clock is less than 80 MHz
assign io_led_d5 = run ? led_d5 : ~(ad9866up & good_fast_clk);

// Clear status
always @(posedge clk) rxclrstatus <= ~rxclrstatus;



cw_support cw_support_i(
  .clk(clk),
  .millisec_pulse(millisec_pulse),
  .dot_key(~io_phone_tip),
  .dash_key(~io_phone_ring),
  .dot_key_debounced(ext_cwkey),
  .dash_key_debounced(ext_ptt),
  .cw_power_on(cw_power_on),
  .cw_keydown(cw_keydown)
);



logic        tx_power_on;		// Is the power on?
assign tx_power_on = cw_power_on | tx_on;


// FIXME: External TR won't work in low power mode
`ifdef BETA2
assign pa_tr = tx_power_on & ~vna & (pa_enable | ~tr_disable);
assign pa_en = tx_power_on & ~vna & pa_enable;
assign pwr_envpa = tx_power_on;
`else
assign pwr_envbias = tx_power_on & ~vna & pa_enable;
assign pwr_envop = tx_power_on;
assign pa_exttr = tx_power_on;
assign pa_inttr = tx_power_on & ~vna & (pa_enable | ~tr_disable);
assign pwr_envpa = tx_power_on & ~vna & pa_enable;
`endif

assign rffe_rfsw_sel = ~vna & pa_enable;

`ifdef BETA2
assign pwr_clkvpa = 1'b0;
`endif

assign clk_recovered = 1'b0;


// AD9866 Ctrl
ad9866ctrl ad9866ctrl_i (
  .clk(clk),
  .rst(ad9866_rst),

  .rffe_ad9866_sdio(rffe_ad9866_sdio),
  .rffe_ad9866_sclk(rffe_ad9866_sclk),
  .rffe_ad9866_sen_n(rffe_ad9866_sen_n),

`ifdef BETA2
  .rffe_ad9866_pga(rffe_ad9866_pga),
`else
  .rffe_ad9866_pga5(rffe_ad9866_pga5),
`endif

  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_rqst(cmd_rqst),
  .cmd_ack(cmd_ack_ad9866)
);



// Response state machine
always @ (posedge clk) begin
  resp_state <= resp_state_next;
  resp_cmd_addr <= resp_cmd_addr_next;
  resp_cmd_data <= resp_cmd_data_next;
end 

// FSM Combinational
always @* begin
  // Next State
  resp_state_next = resp_state;
  resp_cmd_addr_next = resp_cmd_addr;
  resp_cmd_data_next = resp_cmd_data;

  // Combinational
  cmd_resp_rqst = 1'b0;

  case (resp_state)
    RESP_START: begin
      if (cmd_rqst & cmd_requires_resp) begin
        // Save data for response
        resp_cmd_addr_next = cmd_addr;
        resp_cmd_data_next = cmd_data;
        resp_state_next  = RESP_ACK;
      end 
    end 

    RESP_ACK: begin 
      // Will see acknowledge here if all I2C an SPI can start
      if (cmd_ack_i2c & cmd_ack_ad9866) begin 
        resp_state_next = RESP_WAIT;
      end else begin
        resp_state_next = RESP_START;
      end 
    end 

    RESP_WAIT: begin
      cmd_resp_rqst = 1'b1;
      if (resp_rqst) begin
        if (cmd_rqst & cmd_requires_resp) begin
          // Save data for response
          resp_cmd_addr_next = cmd_addr;
          resp_cmd_data_next = cmd_data;
          resp_state_next  = RESP_WAIT;
        end else begin 
          resp_state_next = RESP_START;
        end 
      end 
    end 

    default: begin
      resp_state_next = RESP_START;
    end 

  endcase
end 

// Resp request occurs relatively infrequently
// Output register iresp is updated on resp_rqst
// Output register iresp will be stable before required in any other clock domain
always @(posedge clk) begin
  if (resp_rqst) begin
    clip_cnt  <= 2'b00;
    resp_addr <= resp_addr + 2'b01; // Slot will be skipped if command response
    if (cmd_resp_rqst) begin
      // Command response
      iresp <= {1'b1,resp_cmd_addr,tx_on, resp_cmd_data}; // Queue size is 1
    end else begin
      case( resp_addr) 
        2'b00: iresp <= {3'b000,resp_addr,1'b0, ext_cwkey, ext_ptt, 7'b0001111,(&clip_cnt), 8'h00, 8'h00, HERMES_SERIALNO};
        2'b01: iresp <= {3'b000,resp_addr,1'b0, ext_cwkey, ext_ptt, 4'h0,temperature, 4'h0,fwd_pwr};
        2'b10: iresp <= {3'b000,resp_addr,1'b0, ext_cwkey, ext_ptt, 4'h0,rev_pwr, 4'h0,bias_current};
        2'b11: iresp <= {3'b000,resp_addr,1'b0, ext_cwkey, ext_ptt, 32'h0}; // Unused in HL
      endcase 
    end
  end else if (~(&clip_cnt)) begin
    clip_cnt <= clip_cnt + {1'b0,rxclip};
  end
end

assign resp = iresp;

// sync clock
always @(posedge clk_125) begin
  if (pwrcnt == 6'h00) begin
    //case(pwrphase)
    //  3'b000: pwrcnt <= 6'd59;
    //  3'b001: pwrcnt <= 6'd57;
    //  3'b010: pwrcnt <= 6'd58;
    //  3'b011: pwrcnt <= 6'd55;
    //  3'b100: pwrcnt <= 6'd58;
    //  3'b101: pwrcnt <= 6'd59;
    //  3'b110: pwrcnt <= 6'd56;
    //  3'b111: pwrcnt <= 6'd59;
    //endcase 
    //if (pwrphase == 3'b000) pwrphase <= 3'b110;
    //else pwrphase <= pwrphase - 3'b001;
    pwrcnt <= 6'd58;
  end else begin
    pwrcnt <= pwrcnt - 6'h01;
  end

  if (disable_syncfreq) begin
    pwr_clk3p3 <= 1'b0;
    pwr_clk1p2 <= 1'b0;
  end else begin
    if (pwrcnt == 6'h00) pwr_clk3p3 <= ~pwr_clk3p3;
    if (pwrcnt == 6'h11) pwr_clk1p2 <= ~pwr_clk1p2;
  end
end

endmodule // ioblock
`timescale 1ns / 1ps

module i2c (
    input  logic         clk,
    input  logic         rst,
    input  logic         init_start,

    // Command slave interface
    input  logic [5:0]   cmd_addr,
    input  logic [31:0]  cmd_data,
    input  logic         cmd_rqst,
    output logic         cmd_ack,   

    /*
     * I2C interface
     */
    input  logic         scl1_i,
    output logic         scl1_o,
    output logic         scl1_t,
    input  logic         sda1_i,
    output logic         sda1_o,
    output logic         sda1_t,    

    input  logic         scl2_i,
    output logic         scl2_o,
    output logic         scl2_t,
    input  logic         sda2_i,
    output logic         sda2_o,
    output logic         sda2_t
);

logic         scl_i, scl_o, scl_t, sda_i, sda_o, sda_t;
logic         en_i2c2, ready;

localparam [2:0]
  STATE_W0    = 3'h0,
  STATE_W1    = 3'h1,
  STATE_W2    = 3'h2,
  STATE_W3    = 3'h3,
  STATE_W4    = 3'h4,
  STATE_W5    = 3'h5,
  STATE_W6    = 3'h6,
  STATE_PASS  = 3'h7;


logic [ 2:0]  state = STATE_W0, state_next;

logic [ 5:0]  icmd_addr;
logic [31:0]  icmd_data;
logic         icmd_rqst;

always @(posedge clk) begin
  state <= state_next;
end 

always @* begin
  state_next = state;

  icmd_addr = cmd_addr;
  icmd_data = cmd_data;
  icmd_rqst = cmd_rqst;

  case(state)
    STATE_W0: begin
      icmd_addr = 6'h3c;
      icmd_data = {8'h06, 1'b1, 7'h6a, 8'h17, 8'h04};
      icmd_rqst = 1'b0;
      if (init_start & ready) begin
          icmd_rqst = 1'b1;
          state_next = STATE_W1;
      end
    end 

    STATE_W1: begin
      icmd_addr = 6'h3c;
      icmd_data = {8'h06, 1'b1, 7'h6a, 8'h18, 8'h40};
      icmd_rqst = 1'b0;
      if (init_start & ready) begin
          icmd_rqst = 1'b1;
          state_next = STATE_W2;
      end
    end 

    STATE_W2: begin
      icmd_addr = 6'h3c;
      icmd_data = {8'h06, 1'b1, 7'h6a, 8'h1e, 8'he8};
      icmd_rqst = 1'b0;
      if (init_start & ready) begin
          icmd_rqst = 1'b1;
          state_next = STATE_W3;
      end
    end 

    STATE_W3: begin
      icmd_addr = 6'h3c;
      icmd_data = {8'h06, 1'b1, 7'h6a, 8'h1f, 8'h80};
      icmd_rqst = 1'b0;
      if (init_start & ready) begin
          icmd_rqst = 1'b1;
          state_next = STATE_W4;
      end
    end     

    STATE_W4: begin
      icmd_addr = 6'h3c;
      icmd_data = {8'h06, 1'b1, 7'h6a, 8'h2d, 8'h01};
      icmd_rqst = 1'b0;
      if (init_start & ready) begin
          icmd_rqst = 1'b1;
          state_next = STATE_W5;
      end
    end 

    STATE_W5: begin
      icmd_addr = 6'h3c;
      icmd_data = {8'h06, 1'b1, 7'h6a, 8'h2e, 8'h10};
      icmd_rqst = 1'b0;
      if (init_start & ready) begin
          icmd_rqst = 1'b1;
          state_next = STATE_W6;
      end
    end 

    STATE_W6: begin
      icmd_addr = 6'h3c;
      icmd_data = {8'h06, 1'b1, 7'h6a, 8'h60, 8'h3b};
      icmd_rqst = 1'b0;
      if (init_start & ready) begin
          icmd_rqst = 1'b1;
          state_next = STATE_PASS;
      end
    end 

    STATE_PASS: begin
      if (~init_start) state_next = STATE_W0;
    end 

  endcase
end

i2c_bus2 i2c_bus2_i (
  .clk(clk),
  .rst(rst),

  .cmd_addr(icmd_addr),
  .cmd_data(icmd_data),
  .cmd_rqst(icmd_rqst),
  .cmd_ack(cmd_ack),  

  .en_i2c2(en_i2c2),
  .ready(ready),

  .scl_i(scl_i),
  .scl_o(scl_o),
  .scl_t(scl_t),
  .sda_i(sda_i),
  .sda_o(sda_o),
  .sda_t(sda_t)
);

assign scl_i = en_i2c2 ? scl2_i : scl1_i;
assign sda_i = en_i2c2 ? sda2_i : sda1_i;

assign scl1_o = scl_o;
assign scl2_o = scl_o;

assign scl1_t = en_i2c2 ? 1'b1 : scl_t;
assign scl2_t = en_i2c2 ? scl_t : 1'b1;

assign sda1_t = en_i2c2 ? 1'b1 : sda_t;
assign sda2_t = en_i2c2 ? sda_t : 1'b1;

endmodule/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2016 James C. Ahlstrom, N2ADR
//------------------------------------------------------------------------------

// 2016 Nov 26 - new VNA logic James Ahlstrom N2ADR

// This module scans a set of vna_count frequencies starting from Tx_frequency_in and adding freq_delta for each point.  Each
// point is the average of 1024 cordic I/Q outputs.  For each point, the frequency is changed, then there is a pause to allow things
// to stabilize, then the average is taken and returned with the output_strobe.  The PC receives the points as normal I/Q samples
// at a rate of 8000 sps.  A zero sample is output at the start of the scan and the next sample is for the first frequency.

// This module also sets the Tx frequency for the original VNA method in which the PC scans the frequencies.

module vna_scanner #(parameter CICRATE=0, RATE48=0) (
  input clock,
  input [31:0] freq_delta,
  output reg output_strobe,
  input signed [17:0] cordic_data_I,
  input signed [17:0] cordic_data_Q,
  output reg signed [23:0] out_data_I,
  output reg signed [23:0] out_data_Q,
  // VNA modes are PC-scan and FPGA-scan
  input vna,	// True for either scanning by the FPGA or PC
  input [31:0] Tx_frequency_in,
  output reg [31:0] Tx_frequency_out,
  input [15:0] vna_count
  );


reg [2:0] vna_state;		// state machine for both VNA modes
reg [13:0] vna_decimation;	// count up DECIMATION clocks, and then output a sample; increase bits for clock > 131 MHz
reg [15:0] vna_counter;		// count the number of scan points until we get to vna_count desired points
reg [9:0] data_counter;		// Add up 1024 cordic samples per output sample ; 2**10 = 1024
reg signed [27:0] vna_I, vna_Q;	// accumulator for I/Q cordic samples: 18 bit cordic * 10-bits = 28 bits

parameter DECIMATION = (RATE48 * CICRATE * 8) * 6;	// The decimation; the number of clocks per output sample

localparam VNA_STARTUP		= 0;	// States in the state machine
localparam VNA_PC_SCAN		= 1;
localparam VNA_TAKE_DATA	= 2;
localparam VNA_ZERO_DATA	= 3;
localparam VNA_RETURN_DATUM1	= 4;
localparam VNA_RETURN_DATUM2	= 5;
localparam VNA_CHANGE_FREQ	= 6;
localparam VNA_WAIT_STABILIZE	= 7;


always @(posedge clock)		// state machine for VNA
begin
	if ( ! vna)
	begin	// Not in VNA mode; operate as a regular receiver
		Tx_frequency_out <= Tx_frequency_in;
		vna_state <= VNA_STARTUP;
	end
	else case (vna_state)
	VNA_STARTUP:		// Start VNA mode; zero the Rx and Tx frequencies to synchronize the cordics to zero phase
	begin
		Tx_frequency_out <= 1'b0;
		vna_counter <= 1'd1;
		vna_decimation <= DECIMATION;
		output_strobe <= 1'b0;
		if (vna_count == 1'd0)
			vna_state <= VNA_PC_SCAN;
		else
			vna_state <= VNA_CHANGE_FREQ;
	end
	VNA_PC_SCAN:		// stay in this VNA state when the PC scans the VNA points
	begin
		Tx_frequency_out <= Tx_frequency_in;
		if (vna_count != 1'd0)		// change to vna_count
			vna_state <= VNA_STARTUP;
	end
	VNA_TAKE_DATA:		// add up points to produce a sample
	begin
		vna_decimation <= vna_decimation - 1'd1;
		vna_I <= vna_I + cordic_data_I;
		vna_Q <= vna_Q + cordic_data_Q;
		if (data_counter == 1'b0)
			vna_state <= VNA_RETURN_DATUM1;
		else
			data_counter <= data_counter - 1'd1;
	end
	VNA_ZERO_DATA:		// make a zero sample
	begin
		vna_decimation <= vna_decimation - 1'd1;
		if (data_counter == 1'b0)
			vna_state <= VNA_RETURN_DATUM1;
		else
			data_counter <= data_counter - 1'd1;
	end
	VNA_RETURN_DATUM1:		// Return the sample
	begin
		vna_decimation <= vna_decimation - 1'd1;
		out_data_I <= vna_I[27:4];
		out_data_Q <= vna_Q[27:4];
		vna_state <= VNA_RETURN_DATUM2;
	end
	VNA_RETURN_DATUM2:		// Return the sample
	begin
		vna_decimation <= vna_decimation - 1'd1;
		if (vna_count == 1'd0)		// change to vna_count
			vna_state <= VNA_STARTUP;
		else
		begin
			output_strobe <= 1'b1;
			vna_state <= VNA_CHANGE_FREQ;
		end
	end
	VNA_CHANGE_FREQ:		// done with samples; change frequency
	begin
		vna_decimation <= vna_decimation - 1'd1;
		output_strobe <= 1'b0;
		if (vna_counter == 1'd1)
		begin
			Tx_frequency_out <= Tx_frequency_in;	// starting frequency for scan
			vna_counter <= 1'd0;
		end
		else if (vna_counter == 1'd0)
			vna_counter <= vna_count;
		else
		begin
			vna_counter <= vna_counter - 1'd1;
			Tx_frequency_out <= Tx_frequency_out + freq_delta;	// freq_delta is the frequency to add for each point
		end
		vna_state <= VNA_WAIT_STABILIZE;
	end
	VNA_WAIT_STABILIZE:		// Output samples at 8000 sps.  Allow time for output to stabilize after a frequency change.
	begin
		if (vna_decimation == 1'b0)
		begin
			vna_I <= 1'd0;
			vna_Q <= 1'd0;
			vna_decimation <= DECIMATION - 1;
			data_counter <= 10'd1023;
			if (vna_counter == 0)
				vna_state <= VNA_ZERO_DATA;
			else
				vna_state <= VNA_TAKE_DATA;
		end
		else
			vna_decimation <= vna_decimation - 1'd1;
	end
	endcase
end
endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
//           Copyright (c) 2013 Phil Harman, VK6APH 
//------------------------------------------------------------------------------

// 2013 Jan 26 - varcic now accepts 2...40 as decimation and CFIR
//               replaced with Polyphase FIR - VK6APH

// 2015 Jan 31 - updated for Hermes-Lite 12bit Steve Haynal KF7O

module receiver #(parameter CICRATE=0) (
  input clock,                  //61.44 MHz
  input clock_2x,
  input [5:0] rate,             //48k....384k
  input [31:0] frequency,
  output out_strobe,
  input signed [11:0] in_data,
  output [23:0] out_data_I,
  output [23:0] out_data_Q,
  output signed [17:0] cordic_outdata_I,	// make cordic data available for VNA_SCAN_FPGA
  output signed [17:0] cordic_outdata_Q
  );

  //parameter CICRATE;

// gain adjustment, Hermes reduced by 6dB to match previous receiver code.
// Hermes-Lite gain reduced to calibrate QtRadio
wire signed [23:0] out_data_I2;
wire signed [23:0] out_data_Q2;
assign out_data_I = out_data_I2; //>>> 3);
assign out_data_Q = out_data_Q2; //>>> 3);


//------------------------------------------------------------------------------
//                               cordic
//------------------------------------------------------------------------------

cordic cordic_inst(
  .clock(clock),
  .in_data(in_data),             //12 bit 
  .frequency(frequency),         //32 bit
  .out_data_I(cordic_outdata_I), //18 bit
  .out_data_Q(cordic_outdata_Q)
  );

  
// Receive CIC filters followed by FIR filter
wire decimA_avail, decimB_avail;
wire signed [15:0] decimA_real, decimA_imag;
wire signed [15:0] decimB_real, decimB_imag;

localparam VARCICWIDTH = (CICRATE == 10) ? 36 : (CICRATE == 13) ? 36 : (CICRATE == 5) ? 43 : 39; // Last is default rate of 8
localparam ACCWIDTH = (CICRATE == 10) ? 28 : (CICRATE == 13) ? 30 : (CICRATE == 5) ? 25 : 27; // Last is default rate of 8


// CIC filter 
//I channel
cic #(.STAGES(3), .DECIMATION(CICRATE), .IN_WIDTH(18), .ACC_WIDTH(ACCWIDTH), .OUT_WIDTH(16))      
  cic_inst_I2(
    .clock(clock),
    .in_strobe(1'b1),
    .out_strobe(decimA_avail),
    .in_data(cordic_outdata_I),
    .out_data(decimA_real)
    );

//Q channel
cic #(.STAGES(3), .DECIMATION(CICRATE), .IN_WIDTH(18), .ACC_WIDTH(ACCWIDTH), .OUT_WIDTH(16))  
  cic_inst_Q2(
    .clock(clock),
    .in_strobe(1'b1),
    .out_strobe(),
    .in_data(cordic_outdata_Q),
    .out_data(decimA_imag)
    );


//  Variable CIC filter - in width = out width = 14 bits, decimation rate = 2 to 16 
//I channel
varcic #(.STAGES(5), .IN_WIDTH(16), .ACC_WIDTH(VARCICWIDTH), .OUT_WIDTH(16), .CICRATE(CICRATE))
  varcic_inst_I1(
    .clock(clock),
    .in_strobe(decimA_avail),
    .decimation(rate),
    .out_strobe(decimB_avail),
    .in_data(decimA_real),
    .out_data(decimB_real)
    );

//Q channel
varcic #(.STAGES(5), .IN_WIDTH(16), .ACC_WIDTH(VARCICWIDTH), .OUT_WIDTH(16), .CICRATE(CICRATE))
  varcic_inst_Q1(
    .clock(clock),
    .in_strobe(decimA_avail),
    .decimation(rate),
    .out_strobe(),
    .in_data(decimA_imag),
    .out_data(decimB_imag)
    );
				
firX8R8 fir2 (clock, clock_2x, decimB_avail, {{2{decimB_real[15]}},decimB_real}, {{2{decimB_imag[15]}},decimB_imag}, out_strobe, out_data_I2, out_data_Q2);

endmodule
// megafunction wizard: %RAM: 2-PORT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsyncram 

// ============================================================
// File Name: firram36.v
// Megafunction Name(s):
// 			altsyncram
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 14.0.1 Build 205 08/13/2014 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2014 Altera Corporation. All rights reserved.
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, the Altera Quartus II License Agreement,
//the Altera MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Altera and sold by Altera or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module firram36 (
	clock,
	data,
	rdaddress,
	wraddress,
	wren,
	q);

	input	  clock;
	input	[35:0]  data;
	input	[7:0]  rdaddress;
	input	[7:0]  wraddress;
	input	  wren;
	output	[35:0]  q;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri1	  clock;
	tri0	  wren;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [35:0] sub_wire0;
	wire [35:0] q = sub_wire0[35:0];
/*
	altsyncram	altsyncram_component (
				.address_a (wraddress),
				.address_b (rdaddress),
				.clock0 (clock),
				.data_a (data),
				.wren_a (wren),
				.q_b (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({36{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 256,
		altsyncram_component.numwords_b = 256,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "CLOCK0",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = 8,
		altsyncram_component.widthad_b = 8,
		altsyncram_component.width_a = 36,
		altsyncram_component.width_b = 36,
		altsyncram_component.width_byteena_a = 1;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ADDRESSSTALL_A NUMERIC "0"
// Retrieval info: PRIVATE: ADDRESSSTALL_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_SIZE NUMERIC "9"
// Retrieval info: PRIVATE: BlankMemory NUMERIC "1"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLRdata NUMERIC "0"
// Retrieval info: PRIVATE: CLRq NUMERIC "0"
// Retrieval info: PRIVATE: CLRrdaddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRrren NUMERIC "0"
// Retrieval info: PRIVATE: CLRwraddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRwren NUMERIC "0"
// Retrieval info: PRIVATE: Clock NUMERIC "0"
// Retrieval info: PRIVATE: Clock_A NUMERIC "0"
// Retrieval info: PRIVATE: Clock_B NUMERIC "0"
// Retrieval info: PRIVATE: IMPLEMENT_IN_LES NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: INIT_FILE_LAYOUT STRING "PORT_B"
// Retrieval info: PRIVATE: INIT_TO_SIM_X NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "0"
// Retrieval info: PRIVATE: JTAG_ID STRING "NONE"
// Retrieval info: PRIVATE: MAXIMUM_DEPTH NUMERIC "0"
// Retrieval info: PRIVATE: MEMSIZE NUMERIC "9216"
// Retrieval info: PRIVATE: MEM_IN_BITS NUMERIC "0"
// Retrieval info: PRIVATE: MIFfilename STRING ""
// Retrieval info: PRIVATE: OPERATION_MODE NUMERIC "2"
// Retrieval info: PRIVATE: OUTDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: OUTDATA_REG_B NUMERIC "1"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "0"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_MIXED_PORTS NUMERIC "2"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_A NUMERIC "3"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_B NUMERIC "3"
// Retrieval info: PRIVATE: REGdata NUMERIC "1"
// Retrieval info: PRIVATE: REGq NUMERIC "1"
// Retrieval info: PRIVATE: REGrdaddress NUMERIC "1"
// Retrieval info: PRIVATE: REGrren NUMERIC "1"
// Retrieval info: PRIVATE: REGwraddress NUMERIC "1"
// Retrieval info: PRIVATE: REGwren NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: USE_DIFF_CLKEN NUMERIC "0"
// Retrieval info: PRIVATE: UseDPRAM NUMERIC "1"
// Retrieval info: PRIVATE: VarWidth NUMERIC "0"
// Retrieval info: PRIVATE: WIDTH_READ_A NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_READ_B NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_WRITE_A NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_WRITE_B NUMERIC "36"
// Retrieval info: PRIVATE: WRADDR_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: WRADDR_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: WRCTRL_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: enable NUMERIC "0"
// Retrieval info: PRIVATE: rden NUMERIC "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: ADDRESS_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: ADDRESS_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_OUTPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altsyncram"
// Retrieval info: CONSTANT: NUMWORDS_A NUMERIC "256"
// Retrieval info: CONSTANT: NUMWORDS_B NUMERIC "256"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "DUAL_PORT"
// Retrieval info: CONSTANT: OUTDATA_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: OUTDATA_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: POWER_UP_UNINITIALIZED STRING "FALSE"
// Retrieval info: CONSTANT: READ_DURING_WRITE_MODE_MIXED_PORTS STRING "DONT_CARE"
// Retrieval info: CONSTANT: WIDTHAD_A NUMERIC "8"
// Retrieval info: CONSTANT: WIDTHAD_B NUMERIC "8"
// Retrieval info: CONSTANT: WIDTH_A NUMERIC "36"
// Retrieval info: CONSTANT: WIDTH_B NUMERIC "36"
// Retrieval info: CONSTANT: WIDTH_BYTEENA_A NUMERIC "1"
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT VCC "clock"
// Retrieval info: USED_PORT: data 0 0 36 0 INPUT NODEFVAL "data[35..0]"
// Retrieval info: USED_PORT: q 0 0 36 0 OUTPUT NODEFVAL "q[35..0]"
// Retrieval info: USED_PORT: rdaddress 0 0 8 0 INPUT NODEFVAL "rdaddress[7..0]"
// Retrieval info: USED_PORT: wraddress 0 0 8 0 INPUT NODEFVAL "wraddress[7..0]"
// Retrieval info: USED_PORT: wren 0 0 0 0 INPUT GND "wren"
// Retrieval info: CONNECT: @address_a 0 0 8 0 wraddress 0 0 8 0
// Retrieval info: CONNECT: @address_b 0 0 8 0 rdaddress 0 0 8 0
// Retrieval info: CONNECT: @clock0 0 0 0 0 clock 0 0 0 0
// Retrieval info: CONNECT: @data_a 0 0 36 0 data 0 0 36 0
// Retrieval info: CONNECT: @wren_a 0 0 0 0 wren 0 0 0 0
// Retrieval info: CONNECT: q 0 0 36 0 @q_b 0 0 36 0
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
//           Copyright (c) 2013 Phil Harman, VK6APH 
//------------------------------------------------------------------------------

// 2013 Jan 26 - varcic now accepts 2...40 as decimation and CFIR
//               replaced with Polyphase FIR - VK6APH

// 2015 Jan 31 - updated for Hermes-Lite 12bit Steve Haynal KF7O

module receiver_nco #(parameter CICRATE=10) (
  input clock,                  //61.44 MHz
  input clock_2x,
  input [5:0] rate,             //48k....384k
  input signed [17:0] mixdata_I,
  input signed [17:0] mixdata_Q,  
  output out_strobe,
  output [23:0] out_data_I,
  output [23:0] out_data_Q
  );

  //parameter CICRATE;

// gain adjustment, Hermes reduced by 6dB to match previous receiver code.
// Hermes-Lite gain reduced to calibrate QtRadio
wire signed [23:0] out_data_I2;
wire signed [23:0] out_data_Q2;
assign out_data_I = out_data_I2; //>>> 3);
assign out_data_Q = out_data_Q2; //>>> 3);

  
// Receive CIC filters followed by FIR filter
wire decimA_avail, decimB_avail;
wire signed [15:0] decimA_real, decimA_imag;
wire signed [15:0] decimB_real, decimB_imag;

parameter VARCICWIDTH = 36; /*(CICRAE == 10) ? 36 : (CICRATE == 13) ? 36 : (CICRATE == 5) ? 43 : 39; // Last is default rate of 8 */
parameter ACCWIDTH = (CICRATE == 10) ? 28 : (CICRATE == 13) ? 30 : (CICRATE == 5) ? 25 : 27; // Last is default rate of 8


// CIC filter 
//I channel
cic #(.STAGES(3), .DECIMATION(CICRATE), .IN_WIDTH(18), .ACC_WIDTH(ACCWIDTH), .OUT_WIDTH(16))      
  cic_inst_I2(
    .clock(clock),
    .in_strobe(1'b1),
    .out_strobe(decimA_avail),
    .in_data(mixdata_I),
    .out_data(decimA_real)
    );

//Q channel
cic #(.STAGES(3), .DECIMATION(CICRATE), .IN_WIDTH(18), .ACC_WIDTH(ACCWIDTH), .OUT_WIDTH(16))  
  cic_inst_Q2(
    .clock(clock),
    .in_strobe(1'b1),
    .out_strobe(),
    .in_data(mixdata_Q),
    .out_data(decimA_imag)
    );


//  Variable CIC filter - in width = out width = 14 bits, decimation rate = 2 to 16 
//I channel
varcic #(.STAGES(5), .IN_WIDTH(16), .ACC_WIDTH(VARCICWIDTH), .OUT_WIDTH(16), .CICRATE(CICRATE))
  varcic_inst_I1(
    .clock(clock),
    .in_strobe(decimA_avail),
    .decimation(rate),
    .out_strobe(decimB_avail),
    .in_data(decimA_real),
    .out_data(decimB_real)
    );

//Q channel
varcic #(.STAGES(5), .IN_WIDTH(16), .ACC_WIDTH(VARCICWIDTH), .OUT_WIDTH(16), .CICRATE(CICRATE))
  varcic_inst_Q1(
    .clock(clock),
    .in_strobe(decimA_avail),
    .decimation(rate),
    .out_strobe(),
    .in_data(decimA_imag),
    .out_data(decimB_imag)
    );
				
firX8R8 fir2 (clock, clock_2x, decimB_avail, {{2{decimB_real[15]}},decimB_real}, {{2{decimB_imag[15]}},decimB_imag}, out_strobe, out_data_I2, out_data_Q2);

endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// Polyphase decimating filter

// Based on firX8R8 by James Ahlstrom, N2ADR,  (C) 2011
// Modified for use with HPSDR and DC spur removed by Phil Harman, VK6APH, (C) 2013


// This is a decimate by 8 Polyphase FIR filter. Since it decimates by 8 the output signal
// level will be 1/8 the input level.  The filter coeficients are distributed between the 8 
// FIR filters such that the first FIR receives coeficients 0, 7, 15... the second 1, 8, 16.. the 
// third 2, 9, 17.. etc.  The coeficients are calculated as per normal but there is no need to 
// compensate for the sinx/x shape of the preceeding CIC filters. This is because the filter 
// decimates by 8 and the droop of the CIC at 1/8th its fs/2 is neglibible. 
// The filter coefficients are in the file "coefL8.txt". This is split into 8 individual 
// Quartus ROM *.mif files.

// The filter coefficients are also attenuated such that the result of the multiply and accumalate 
// does not exceed 24 bits. 

// Note: Gain is higher than previous filter code by 6dB so reduce outside this module.
// FIR filters
//
// ROM init file:   REQUIRED, with 256 or 512 coefficients.  See below.
// Number of taps:  NTAPS.
// Input bits:      18 fixed.
// Output bits:   OBITS, default 24.
// Adder bits:      ABITS, default 24.

// This requires eight MifFile's.
// Maximum NTAPS is 8 * (previous and current decimation) less overhead.
// Maximum NTAPS is 2048 (or less).

module firX8R8 (  
  input clock,
  input clock_2x,
  input x_avail,                  // new sample is available
  input signed [MBITS-1:0] x_real,      // x is the sample input
  input signed [MBITS-1:0] x_imag,
  output reg y_avail,             // new output is available
  output wire signed [OBITS-1:0] y_real,  // y is the filtered output
  output wire signed [OBITS-1:0] y_imag);
  
  localparam ADDRBITS = 7;          // Address bits for 18/36 X 256 rom/ram blocks
  localparam MBITS  = 18;           // multiplier bits == input bits  
  
  parameter
    TAPS      = NTAPS / 8,        // Must be even by 8
    ABITS     = 24,             // adder bits
    OBITS     = 24,             // output bits
    NTAPS     = 976;            // number of filter taps, even by 8 
  
  reg [4:0] wstate;               // state machine for write samples
  
  reg  [ADDRBITS-1:0] waddr;          // write sample memory address
  reg weA, weB, weC, weD, weE, weF, weG, weH;
  reg  signed [ABITS-1:0] Racc, Iacc;
  wire signed [ABITS-1:0] RaccA, RaccB, RaccC, RaccD;
  wire signed [ABITS-1:0] IaccA, IaccB, IaccC, IaccD; 
  wire banksel;
  
// Output is the result of adding 8 by 24 bit results so Racc and Iacc need to be 
// 24 + log2(8) = 24 + 3 = 27 bits wide to prevent DC spur.
// However, since we decimate by 8 the output will be 1/8 the input. Hence we 
// use 24 bits for the Accumulators. 

  assign y_real = Racc[ABITS-1:0];  
  assign y_imag = Iacc[ABITS-1:0];
  
  initial
  begin
    wstate = 0;
    waddr = 0;
  end
  
  always @(posedge clock)
  begin
    if (wstate == 8) wstate <= wstate + 1'd1; // used to set y_avail
    if (wstate == 9) begin
      wstate <= 0;                  // reset state machine and increment RAM write address
      waddr <= waddr + 1'd1;
    end
    if (x_avail)
    begin
      wstate <= wstate + 1'd1;
      case (wstate)
        0:  begin                   // wait for the first x input
            Racc <= RaccA;            // add accumulators
            Iacc <= IaccA;
          end
        1:  begin                   // wait for the next x input
            Racc <= Racc + RaccB;   
            Iacc <= Iacc + IaccB;
          end
        2:  begin 
            Racc <= Racc + RaccC;   
            Iacc <= Iacc + IaccC;
          end
        3:  begin
            Racc <= Racc + RaccD;   
            Iacc <= Iacc + IaccD;
          end
        4:  begin
            Racc <= Racc + RaccA;   
            Iacc <= Iacc + IaccA;
          end
        5:  begin
            Racc <= Racc + RaccB;   
            Iacc <= Iacc + IaccB;
          end
        6:  begin
            Racc <= Racc + RaccC;   
            Iacc <= Iacc + IaccC;
          end
        7: begin                    // wait for the last x input
            Racc <= Racc + RaccD;
            Iacc <= Iacc + IaccD;
          end
      endcase
    end
  end
  
  
  // Enable each FIR in sequence
  assign weA    = (x_avail && wstate == 0);
  assign weB    = (x_avail && wstate == 1);
  assign weC    = (x_avail && wstate == 2);
  assign weD    = (x_avail && wstate == 3);
  assign weE    = (x_avail && wstate == 4);
  assign weF    = (x_avail && wstate == 5);
  assign weG    = (x_avail && wstate == 6);
  assign weH    = (x_avail && wstate == 7);

  assign banksel = ~wstate[2];
    
  // at end of sequence indicate new data is available
  assign y_avail = (wstate == 8);

  fir256 #(.ifile("coefL4AE.mif"), .ABITS(ABITS), .TAPS(TAPS)) AE (
    .clock(clock_2x),
    .waddr(waddr),
    .ebanksel(banksel),
    .ewe(weA|weE),
    .x_real(x_real),
    .x_imag(x_imag),
    .Raccum(RaccA), 
    .Iaccum(IaccA)
  );

  fir256 #(.ifile("coefL4BF.mif"), .ABITS(ABITS), .TAPS(TAPS)) BF (
    .clock(clock_2x),
    .waddr(waddr),
    .ebanksel(banksel),
    .ewe(weB|weF),
    .x_real(x_real),
    .x_imag(x_imag),
    .Raccum(RaccB), 
    .Iaccum(IaccB)
  );

  fir256 #(.ifile("coefL4CG.mif"), .ABITS(ABITS), .TAPS(TAPS)) CG (
    .clock(clock_2x),
    .waddr(waddr),
    .ebanksel(banksel),
    .ewe(weC|weG),
    .x_real(x_real),
    .x_imag(x_imag),
    .Raccum(RaccC), 
    .Iaccum(IaccC)
  );

  fir256 #(.ifile("coefL4DH.mif"), .ABITS(ABITS), .TAPS(TAPS)) DH (
    .clock(clock_2x),
    .waddr(waddr),
    .ebanksel(banksel),
    .ewe(weD|weH),
    .x_real(x_real),
    .x_imag(x_imag),
    .Raccum(RaccD), 
    .Iaccum(IaccD)
  );

endmodule


// This filter waits until a new sample is written to memory at waddr.  Then
// it starts by multiplying that sample by coef[0], the next prior sample
// by coef[1], (etc.) and accumulating.  For R=8 decimation, coef[1] is the
// coeficient 8 prior to coef[0].
// When reading from the RAM we need to allow 3 clock pulses from presenting the 
// read address until the data is available. 

module fir256 #(parameter MBITS=18, ADDRBITS=7, ifile="missing.txt", ABITS=7, TAPS=0) //dh: don't use parameters before declaring them 
   (input clock,
    input [ADDRBITS-1:0]      waddr, // memory write address
    input 		      ebanksel,
    input 		      ewe, // memory write enable
    input signed [MBITS-1:0]  x_real, // sample to write
    input signed [MBITS-1:0]  x_imag,
    output logic signed [ABITS-1:0] Raccum, //dh
    output logic signed [ABITS-1:0] Iaccum  //dh
  );

  //localparam ADDRBITS = 7;                // Address bits for 18/36 X 256 rom/ram blocks
  //localparam MBITS    = 18;               // multiplier bits == input bits
  
  //parameter ABITS = 0;                  // adder bits
  //parameter TAPS    = 0;                  // number of filter taps, max 2**ADDRBITS

  reg [ADDRBITS-1:0] raddr, caddr;            // read address for sample and coef
  wire [MBITS*2-1:0] q;                 // I/Q sample read from memory
  reg  [MBITS*2-1:0] reg_q;
  wire signed [MBITS-1:0] q_real, q_imag;     // I/Q sample read from memory
  wire signed [MBITS-1:0] coef;             // coefficient read from memory
  reg  signed [MBITS-1:0] reg_coef;
  reg signed [MBITS*2-1:0] Rmult, Imult;        // multiplier result
  reg signed [MBITS*2-1:0] RmultSum, ImultSum;    // multiplier result
  reg [ADDRBITS:0] counter;               // count TAPS samples

  reg  we = 1'b0;                          // Internal we on fast clock
  reg  banksel = 1'b0;

  //wire [ADDRBITS-1:0] addr;

  //reg fir_step;                   // Pipeline register for fir

  always @(posedge clock) begin 
    if (ewe & ~we) begin 
      we <= 1'b1;
      banksel <= ebanksel;
    end
    else we <= 1'b0;
  end

  assign q_real = reg_q[MBITS*2-1:MBITS];
  assign q_imag = reg_q[MBITS-1:0];

  firromH #(.init_file(ifile)) rom ( {banksel,caddr}, clock, coef);    // coefficient ROM 18 X 256
  
  //assign addr = we ? waddr : raddr;

  firram36 ram (
    .clock(clock), 
    .data({x_real, x_imag}),
    .rdaddress({banksel,raddr}),
    .wraddress({banksel,waddr}),
    .wren(we),
    .q(q)
  );

  always @(posedge clock)
  begin
    if (we)   // Wait until a new sample is written to memory
      begin
        counter <= TAPS[ADDRBITS:0] + 4;     // count samples and pipeline latency (delay of 3 clocks from address being presented)
        raddr <= waddr;                  // read address -> newest sample
        caddr <= 1'd0;                 // start at coefficient zero
        Raccum <= 0;
        Iaccum <= 0;
        Rmult <= 0;
        Imult <= 0;
        //fir_step <= 1'b1;
      end
    else
      begin   // main pipeline here
        if (counter < (TAPS[ADDRBITS:0] + 2))
        begin
          //if (fir_step)
          //begin
            Rmult <= q_real * reg_coef;
            Raccum <= Raccum + Rmult[35:12] + Rmult[11];  // truncate 36 bits down to 24 bits to prevent DC spur
            //fir_step <= 1'b0;
          //end
          //else 
          //begin
            Imult <= q_imag * reg_coef;
            Iaccum <= Iaccum + Imult[35:12] + Imult[11];
            //fir_step <= 1'b1;
          //end
        end


        //if (~fir_step & (counter > 0))
        if (counter > 0)
        begin
          counter <= counter - 1'd1;
          raddr <= raddr - 1'd1;            // move to prior sample
          caddr <= caddr + 1'd1;            // move to next coefficient
          reg_q <= q;
          reg_coef <= coef;
        end
      end
  end
endmodule

`ifdef USE_ALTSYNCRAM

module firromH (
  address,
  clock,
  q);

  parameter init_file = "missing_file.mif";

  input [7:0]  address;
  input   clock;
  output  [17:0]  q;

  wire [17:0] sub_wire0;
  wire [17:0] q = sub_wire0[17:0];

  altsyncram  altsyncram_component (
    .address_a (address),
    .clock0 (clock),
    .q_a (sub_wire0),
    .aclr0 (1'b0),
    .aclr1 (1'b0),
    .address_b (1'b1),
    .addressstall_a (1'b0),
    .addressstall_b (1'b0),
    .byteena_a (1'b1),
    .byteena_b (1'b1),
    .clock1 (1'b1),
    .clocken0 (1'b1),
    .clocken1 (1'b1),
    .clocken2 (1'b1),
    .clocken3 (1'b1),
    .data_a ({18{1'b1}}),
    .data_b (1'b1),
    .eccstatus (),
    .q_b (),
    .rden_a (1'b1),
    .rden_b (1'b1),
    .wren_a (1'b0),
    .wren_b (1'b0));
  defparam
    altsyncram_component.address_aclr_a = "NONE",
    altsyncram_component.clock_enable_input_a = "BYPASS",
    altsyncram_component.clock_enable_output_a = "BYPASS",
    altsyncram_component.init_file = init_file,
    altsyncram_component.intended_device_family = "Cyclone IV E",
    altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
    altsyncram_component.lpm_type = "altsyncram",
    altsyncram_component.numwords_a = 256,
    altsyncram_component.operation_mode = "ROM",
    altsyncram_component.outdata_aclr_a = "NONE",
    altsyncram_component.outdata_reg_a = "CLOCK0",
    altsyncram_component.widthad_a = 8,
    altsyncram_component.width_a = 18,
    altsyncram_component.width_byteena_a = 1;
endmodule

`else

module firromH (
  address,
  clock,
  q);

  parameter init_file = "missing.txt";

  input [7:0]  address;
  input   clock;
  output logic [17:0]  q; //dh


  reg [17:0] rom[255:0];

  initial
  begin
    $readmemb(init_file, rom);
  end

  always @ (posedge clock)
  begin
    q <= rom[address];
  end

endmodule

`endif
`ifdef USE_ALTSYNCRAM

module firrom1_1025 (
  address,
  clock,
  q);

  parameter init_file = "missing_file.mif";

  input [10:0]  address;
  input   clock;
  output  [17:0]  q;

  wire [17:0] sub_wire0;
  wire [17:0] q = sub_wire0[17:0];

  altsyncram  altsyncram_component (
    .address_a (address),
    .clock0 (clock),
    .q_a (sub_wire0),
    .aclr0 (1'b0),
    .aclr1 (1'b0),
    .address_b (1'b1),
    .addressstall_a (1'b0),
    .addressstall_b (1'b0),
    .byteena_a (1'b1),
    .byteena_b (1'b1),
    .clock1 (1'b1),
    .clocken0 (1'b1),
    .clocken1 (1'b1),
    .clocken2 (1'b1),
    .clocken3 (1'b1),
    .data_a ({18{1'b1}}),
    .data_b (1'b1),
    .eccstatus (),
    .q_b (),
    .rden_a (1'b1),
    .rden_b (1'b1),
    .wren_a (1'b0),
    .wren_b (1'b0));
  defparam
    altsyncram_component.address_aclr_a = "NONE",
    altsyncram_component.clock_enable_input_a = "BYPASS",
    altsyncram_component.clock_enable_output_a = "BYPASS",
    altsyncram_component.init_file = init_file,
    altsyncram_component.intended_device_family = "Cyclone IV E",
    altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
    altsyncram_component.lpm_type = "altsyncram",
    altsyncram_component.numwords_a = 1025,
    altsyncram_component.operation_mode = "ROM",
    altsyncram_component.outdata_aclr_a = "NONE",
    altsyncram_component.outdata_reg_a = "CLOCK0",
    altsyncram_component.widthad_a = 11,
    altsyncram_component.width_a = 18,
    altsyncram_component.width_byteena_a = 1;
endmodule


`else

module firrom1_1025 (
  address,
  clock,
  q);

  parameter init_file = "missing.txt";

  input [10:0]  address;
  input   clock;
  output logic  [17:0]  q;

  reg [17:0] rom[1024:0];

  initial
  begin
    $readmemb(init_file, rom);
  end

  always @ (posedge clock)
  begin
    q <= rom[address];
  end

endmodule

`endif
`ifdef USE_ALTSYNCRAM

module firromI_1024 (
  address,
  clock,
  q);

  parameter init_file = "missing_file.mif";

  input [9:0]  address;
  input   clock;
  output  [17:0]  q;

  wire [17:0] sub_wire0;
  wire [17:0] q = sub_wire0[17:0];

  altsyncram  altsyncram_component (
    .address_a (address),
    .clock0 (clock),
    .q_a (sub_wire0),
    .aclr0 (1'b0),
    .aclr1 (1'b0),
    .address_b (1'b1),
    .addressstall_a (1'b0),
    .addressstall_b (1'b0),
    .byteena_a (1'b1),
    .byteena_b (1'b1),
    .clock1 (1'b1),
    .clocken0 (1'b1),
    .clocken1 (1'b1),
    .clocken2 (1'b1),
    .clocken3 (1'b1),
    .data_a ({18{1'b1}}),
    .data_b (1'b1),
    .eccstatus (),
    .q_b (),
    .rden_a (1'b1),
    .rden_b (1'b1),
    .wren_a (1'b0),
    .wren_b (1'b0));
  defparam
    altsyncram_component.address_aclr_a = "NONE",
    altsyncram_component.clock_enable_input_a = "BYPASS",
    altsyncram_component.clock_enable_output_a = "BYPASS",
    altsyncram_component.init_file = init_file,
    altsyncram_component.intended_device_family = "Cyclone IV E",
    altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
    altsyncram_component.lpm_type = "altsyncram",
    altsyncram_component.numwords_a = 1024,
    altsyncram_component.operation_mode = "ROM",
    altsyncram_component.outdata_aclr_a = "NONE",
    altsyncram_component.outdata_reg_a = "CLOCK0",
    altsyncram_component.widthad_a = 10,
    altsyncram_component.width_a = 18,
    altsyncram_component.width_byteena_a = 1;
endmodule


`else

module firromI_1024 (
  address,
  clock,
  q);

  parameter init_file = "missing.txt";

  input [9:0]  address;
  input   clock;
  output  reg [17:0]  q;

  reg [17:0] rom[1023:0];

  initial
  begin
    $readmemb(init_file, rom);
    q = 0;
  end

  always @ (posedge clock)
  begin
    q <= rom[address];
  end

endmodule

`endif//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// Based on code  by James Ahlstrom, N2ADR,  (C) 2011
// Modified for use with HPSDR by Phil Harman, VK6PH, (C) 2013



// Interpolate by 8 Polyphase FIR filter.
// Produce an output when calc is strobed true.  Output a strobe on req
// to request a new input sample.
// Input sample bits are 16 bits wide.


/*

	Interpolate by 8 Polyphase filter.
	
	The classic method of increasing the sampling rate of a system is to insert zeros between input samples.
	In the case of interpolating by 8 the input data would look as follows:
	
	X0,0,0,0,0,0,0,0,X1,0,0,0,0,0,0,0,X2....
	
	Where Xn represents an input sample. The effect of adding the zero samples is to cause the output to 
	contain images centered on multiples of the original sample rate.  So, we must also 
	filter this result down to the original bandwidth.  Once we have done this, we have a signal at the
	higher sample rate that only has frequency content within the original bandwidth.
	
	Note that when we multiply the coefficients by the zero samples, they make zero contribution to the result.
	Only the actual input samples, when multiplied by coefficients, contribute to the result. In which case these 
	are the only input samples that we need to process.
	Let's call the coefficients C0, C1, C2, C3, ....  So, when we enter an actual input sample, 
	the input samples (spaced 8 apart) get multiplied by C0, C8, C16, C24, ... to generate the first result ... 
	everything else is just zero.  When we enter the next data sample, the existing input samples have shifted and
	the non-zero results are generated by C1, C9, C17 ..... and so on.


	
	
	The format of the Polyphase filter is as follows:
	
	Input	
				+----+----+-----+ ........+
		---|->| C0 | C8 | C16 | ........|----0  <------ Output
			|	+----+----+-----+ ........+
			|
			|	+----+----+-----+ ........+
			|->| C1 | C9 | C17 | ........|----0
			|	+----+----+-----+ ........+
			|	
			|	+----+----+-----+ ........+
			|->| C2 | C10| C18 | ........|----0
			|	+----+----+-----+ ........+

			
						etc
			
							
			|	+----+----+-----+ ........+
			|->| C7 | C15| C23 | ........|----0
			|	+----+----+-----+ ........+


	Conceptually the filter operates as follows.  Each input sample at 48ksps is fed to each FIR. When an output sample is 
	requested the input samples are mutlipled by the coefficients the output is pointing to. Hence for 
	each input sample there are 8 outputs.

	As implemented, the input samples are stored in RAM. Each new sample is saved at the next RAM address.  When an output 
	value is requested (by strobing calc) the samples in RAM are multiplied by the coefficients held in ROM. After each sample and coefficient
	multiplication the RAM address is decremented and the ROM address incremented by 8.  This is repeated until all the samples 
	have been multiplied by a coefficient.
	
	Prior to the next request for an output value the ROM starting address is incremented by one. Hence for the first output
	coefficients C0, C8, C16.... are used, for the second output coefficients C1, C9, C18....are used etc.
	
	Once all 8 sets of coefficients have been processed a new input sample is requested. 
	


*/

module FirInterp8_1024(
	input clock,
	input calc,						// calculate an output sample
	output reg req,					// request the next input sample
	input signed [15:0] x_real,		// input samples
	input signed [15:0] x_imag,
	output reg signed [OBITS-1:0] y_real,	// output samples
	output reg signed [OBITS-1:0] y_imag
	);
	
	parameter OBITS			= 20;		// output bits
	parameter ABITS			= 24;		// adder bits
	parameter NTAPS			= 11'd1024;	// number of filter taps, even by 8, 1024-8 max
	parameter NTAPS_BITS		= 10;		// number of address bits for coefficient memory

	reg [3:0] rstate;		// state machine
	parameter rWait		= 0;
	parameter rAddr		= 1;
	parameter rAddrA		= 2;
	parameter rAddrB		= 3;
	parameter rRun			= 4;
	parameter rDone		= 5;
	parameter rEnd1		= 6;
	parameter rEnd2		= 7;
	parameter rEnd3		= 8;
	parameter rEnd4		= 9;

	// We need memory for NTAPS / 8 samples saved in memory
	reg  [6:0] waddr, raddr;			// write and read sample memory address
	reg  we;									// write enable for samples
	reg  signed [ABITS-1:0] Raccum, Iaccum;		// accumulators
	wire [35:0] q;							// I/Q sample read from memory
	reg  [35:0] reg_q;
	wire signed [17:0] q_real, q_imag;
	assign q_real = reg_q[35:18];
	assign q_imag = reg_q[17:0];
	reg  [NTAPS_BITS-1:0] caddr;		// read address for coefficient
	wire signed [17:0] coef;			// 18-bit coefficient read from memory
	reg  signed [17:0] reg_coef;
	reg  signed [35:0] Rmult, Imult;	// multiplier result
	reg  [2:0] phase;						// count 0, 1, ..., 7
	reg  [9:0] counter;					// count NTAPS/8 samples + latency


	initial
	begin
		rstate = rWait;
		waddr = 0;
		raddr = 0;
		req = 0;
		phase = 0;
		reg_coef = 0;
		Rmult = 0;
		Imult = 0;
		reg_q = 0;
		Raccum = 0;
		Iaccum = 0;
		caddr = 0;
		counter = 0;
		req = 0;
		y_real = 0;
		y_imag = 0;
	end

`ifdef USE_ALTSYNCRAM	
	firromI_1024 #(.init_file("coefI8_1024.mif")) rom (caddr, clock, coef);	// coefficient ROM 18 bits X NTAPS
`else 
	firromI_1024 #(.init_file("coefI8_1024.txt")) rom (caddr, clock, coef);	// coefficient ROM 18 bits X NTAPS
`endif 
	// sample RAM 36 bits X 128;  36 bit == 18 bits I and 18 bits Q
	// sign extend the input samples; they remain at 16 bits
	wire [35:0] sx_input;
	assign sx_input = {x_real[15], x_real[15], x_real, x_imag[15], x_imag[15], x_imag};
	firram36I_1024 ram (clock, sx_input, raddr, waddr, we, q);

	task next_addr;		// increment address and register the next sample and coef
		raddr <= raddr - 1'd1;		// move to prior sample
		caddr <= caddr + 4'd8;		// move to next coefficient
		reg_q <= q;
		reg_coef <= coef;
	endtask

	always @(posedge clock)
	begin
		case (rstate)
			rWait:
			begin
				if (calc)	// Wait until a new result is requested
				begin
					rstate <= rAddr;
					raddr <= waddr;		// read address -> newest sample
					caddr <= phase;		// start coefficient
					counter <= NTAPS / 11'd8 + 1'd1;	// count samples and pipeline latency
					Raccum <= 1'd0;
					Iaccum <= 1'd0;
					Rmult <= 1'd0;
					Imult <= 1'd0;
				end
			end
			rAddr:	// prime the memory pipeline
			begin
				rstate <= rAddrA;
				next_addr;
			end
			rAddrA:
			begin
				rstate <= rAddrB;
				next_addr;
			end
			rAddrB:
			begin
				rstate <= rRun;
				next_addr;
			end
			rRun:
			begin		// main pipeline here
				next_addr;
				Rmult <= q_real * reg_coef;
				Imult <= q_imag * reg_coef;
				Raccum <= Raccum + Rmult[35:12] + Rmult[11];		// Add the most significant bits
				Iaccum <= Iaccum + Imult[35:12] + Imult[11];
				counter <= counter - 1'd1;
				if (counter == 0)
				begin
					rstate <= rDone;
				end
			end
			rDone:
			begin
				// Input samples were 16 bits in 18
				// Coefficients were multiplied by 8
				//y_real <= Raccum[(ABITS-1-3) -: OBITS];
				//y_imag <= Iaccum[(ABITS-1-3) -: OBITS];
				y_real <= Raccum[20:1] + Raccum[1];			// truncate to 20 bits to eliminate DC component
				y_imag <= Iaccum[20:1] + Iaccum[1];
				if (phase == 3'b111)
					rstate <= rEnd1;
				else
					rstate <= rWait;
				phase <= phase + 1'd1;
			end
			rEnd1:		// This was the last output sample for this input sample
			begin
				rstate <= rEnd2;
				waddr <= waddr + 1'd1;	// next write address
			end
			rEnd2:
			begin
				rstate <= rEnd3;
				we <= 1'd1;	// write current new sample at new address
			end
			rEnd3:
			begin
				rstate <= rEnd4;
				we <= 1'd0;
				req <= 1'd1;			// request next sample
			end
			rEnd4:
			begin
				rstate <= rWait;
				req <= 1'd0;
			end
		endcase
	end
endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// Based on code  by James Ahlstrom, N2ADR,  (C) 2011
// Modified for use with HPSDR by Phil Harman, VK6PH, (C) 2013



// Interpolate by 5 Polyphase FIR filter. Used by the EER code since no CIC compensation required.
// Produce an output when calc is strobed true.  Output a strobe on req to request a new input sample.
// Input sample bits are 16 bits wide, outputs are 20 bits wide.


/*

	Interpolate by 5 Polyphase filter.

	The classic method of increasing the sampling rate of a system is to insert zeros between input samples.
	In the case of interpolating by 5 the input data would look as follows:

	X0,0,0,0,0,X1,0,0,0,0,X2....

	Where Xn represents an input sample. The effect of adding the zero samples is to cause the output to
	contain images centered on multiples of the original sample rate.  So, we must also
	filter this result down to the original bandwidth.  Once we have done this, we have a signal at the
	higher sample rate that only has frequency content within the original bandwidth.

	Note that when we multiply the coefficients by the zero samples, they make zero contribution to the result.
	Only the actual input samples, when multiplied by coefficients, contribute to the result. In which case these
	are the only input samples that we need to process.
	Let's call the coefficients C0, C1, C2, C3, ....  So, when we enter an actual input sample,
	the input samples (spaced 5 apart) get multiplied by C0, C5, C10, C15, ... to generate the first result ...
	everything else is just zero.  When we enter the next data sample, the existing input samples have shifted and
	the non-zero results are generated by C1, C6, C11 ..... and so on.




	The format of the Polyphase filter is as follows:

	Input
				+----+----+-----+ ........+
		---|->| C0 | C5 | C10 | ........|----0  <------ Output
			|	+----+----+-----+ ........+
			|
			|	+----+----+-----+ ........+
			|->| C1 | C6 | C11 | ........|----0
			|	+----+----+-----+ ........+
			|
			|	+----+----+-----+ ........+
			|->| C2 | C7 | C12 | ........|----0
			|	+----+----+-----+ ........+
			|
			|	+----+----+-----+ ........+
			|->| C3 | C8 | C13 | ........|----0
			|	+----+----+-----+ ........+
			|
			|	+----+----+-----+ ........+
			|->| C4 | C9 | C14 | ........|----0
				+----+----+-----+ ........+


	Conceptually the filter operates as follows.  Each input sample at 48ksps is fed to each FIR. When an output sample is
	requested the input samples are mutlipled by the coefficients the output is pointing to. Hence for
	each input sample there are 5 outputs.

	As implemented, the input samples are stored in RAM. Each new sample is saved at the next RAM address.  When an output
	value is requested (by strobing calc) the samples in RAM are multiplied by the coefficients held in ROM. After each sample and coefficient
	multiplication the RAM address is decremented and the ROM address incremented by 5.  This is repeated until all the samples
	have been multiplied by a coefficient.

	Prior to the next request for an output value the ROM starting address is incremented by one. Hence for the first output
	coefficients C0, C5, C10.... are used, for the second output coefficients C1, C6, C11....are used etc.

	Once all 5 sets of coefficients have been processed a new input sample is requested.



*/

module FirInterp5_1025_EER(
	input clock,
	input calc,								// calculate an output sample
	output reg req,						// request the next input sample
	input signed [15:0] x_real,		// input samples
	input signed [15:0] x_imag,
	output reg signed [OBITS-1:0] y_real,	// output samples
	output reg signed [OBITS-1:0] y_imag
	);

	parameter OBITS			= 20;		// output bits
	parameter ABITS			= 24;		// adder bits
	parameter NTAPS			= 11'd1025;	// number of filter taps, even by 5
	parameter NTAPS_BITS		= 11;		// number of address bits for coefficient memory

	reg [3:0] rstate;		// state machine
	parameter rWait		= 0;
	parameter rAddr		= 1;
	parameter rAddrA		= 2;
	parameter rAddrB		= 3;
	parameter rRun			= 4;
	parameter rDone		= 5;
	parameter rEnd1		= 6;
	parameter rEnd2		= 7;
	parameter rEnd3		= 8;
	parameter rEnd4		= 9;

	// We need memory for NTAPS / 5  = 205 samples saved in memory
	reg  [7:0] waddr, raddr;			// write and read sample memory address
	reg  we;									// write enable for samples
	reg  signed [ABITS-1:0] Raccum, Iaccum;		// accumulators
	wire [35:0] q;							// I/Q sample read from memory
	reg  [35:0] reg_q;
	wire signed [17:0] q_real, q_imag;
	assign q_real = reg_q[35:18];
	assign q_imag = reg_q[17:0];
	reg  [NTAPS_BITS-1:0] caddr;		// read address for coefficient
	wire signed [17:0] coef;			// 18-bit coefficient read from memory
	reg  signed [17:0] reg_coef;
	reg  signed [35:0] Rmult, Imult;	// multiplier result, 18 * 18
	reg  [2:0] phase;						// count 0, 1, 2, 3, 4
	reg  [8:0] counter;					// count NTAPS/5 samples + latency = 1025/5 + 1 = 206


	initial
	begin
		rstate = rWait;
		waddr = 0;
		req = 0;
		phase = 0;
	end

`ifdef USE_ALTSYNCRAM
	firrom1_1025 #(.init_file("coefI5_1025_EER.mif")) rom (caddr, clock, coef);	// coefficient ROM 18 bits X NTAPS
`else
	firrom1_1025 #(.init_file("coefI5_1025_EER.txt")) rom (caddr, clock, coef);	// coefficient ROM 18 bits X NTAPS
`endif

	// sample RAM 36 bits X 205;  36 bit == 18 bits I and 18 bits Q
	// sign extend the input samples; they remain at 16 bits
	wire [35:0] sx_input;
	assign sx_input = {x_real[15], x_real[15], x_real, x_imag[15], x_imag[15], x_imag};

	firram36I_205 ramEER (clock, sx_input, raddr, waddr, we, q);

	task next_addr;					// increment address and register the next sample and coef
		raddr <= raddr - 1'd1;		// move to prior sample
		caddr <= caddr + 11'd5;		// move to next coefficient. Note caddr never gets to 1025, 1024 is the max
		reg_q <= q;
		reg_coef <= coef;
	endtask

	always @(posedge clock)
	begin
		case (rstate)
			rWait:
			begin
				if (calc)	// Wait until a new result is requested
				begin
					rstate <= rAddr;
					raddr <= waddr;		// read address -> newest sample
					caddr <= phase;		// start coefficient
					counter <= NTAPS / 11'd5 + 11'd1;	// count samples and pipeline latency
					Raccum <= 1'd0;
					Iaccum <= 1'd0;
					Rmult <= 1'd0;
					Imult <= 1'd0;
				end
			end
			rAddr:	// prime the memory pipeline
			begin
				rstate <= rAddrA;
				next_addr;
			end
			rAddrA:
			begin
				rstate <= rAddrB;
				next_addr;
			end
			rAddrB:
			begin
				rstate <= rRun;
				next_addr;
			end
			rRun:
			begin		// main pipeline here
				next_addr;
				Rmult <= q_real * reg_coef;
				Imult <= q_imag * reg_coef;
				Raccum <= Raccum + Rmult[35:12] + Rmult[11];		// Add the most significant bits
				Iaccum <= Iaccum + Imult[35:12] + Imult[11];
				counter <= counter - 1'd1;
				if (counter == 0)											// count == 0 is never applied
				begin
					rstate <= rDone;
				end
			end
			rDone:
			begin
				// Input samples were 16 bits in 18
				// Coefficients were multiplied by 8
				y_real <= Raccum[20:1] + Raccum[1];			// truncate to 20 bits to eliminate DC component
				y_imag <= Iaccum[20:1] + Iaccum[1];
				if (phase == 3'b100) begin 					// once we reach 4 restart
					phase <= 3'd0;
					rstate <= rEnd1;
				end
				else begin
					rstate <= rWait;
					phase <= phase + 1'd1;
				end
			end
			rEnd1:		// This was the last output sample for this input sample
			begin
				rstate <= rEnd2;
				waddr <= waddr + 1'd1;	// next write address
			end
			rEnd2:
			begin
				rstate <= rEnd3;
				we <= 1'd1;	// write current new sample at new address
			end
			rEnd3:
			begin
				rstate <= rEnd4;
				we <= 1'd0;
				req <= 1'd1;			// request next sample
			end
			rEnd4:
			begin
				rstate <= rWait;
				req <= 1'd0;
			end
		endcase
	end
endmodule
// megafunction wizard: %LPM_MULT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsquare 

// ============================================================
// File Name: square.v
// Megafunction Name(s):
// 			altsquare
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 18.1.0 Build 625 09/12/2018 SJ Lite Edition
// ************************************************************


//Copyright (C) 2018  Intel Corporation. All rights reserved.
//Your use of Intel Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Intel Program License 
//Subscription Agreement, the Intel Quartus Prime License Agreement,
//the Intel FPGA IP License Agreement, or other applicable license
//agreement, including, without limitation, that your use is for
//the sole purpose of programming logic devices manufactured by
//Intel and sold by Intel or its authorized distributors.  Please
//refer to the applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module square (
	dataa,
	result);

	input	[15:0]  dataa;
	output	[31:0]  result;

	wire [31:0] sub_wire0;
	wire [31:0] result = sub_wire0[31:0];
/*
	altsquare	altsquare_component (
				.data (dataa),
				.result (sub_wire0),
				.aclr (1'b0),
				.clock (1'b1),
				.ena (1'b1),
				.sclr (1'b0));
	defparam
		altsquare_component.data_width = 16,
		altsquare_component.lpm_type = "ALTSQUARE",
		altsquare_component.pipeline = 0,
		altsquare_component.representation = "SIGNED",
		altsquare_component.result_width = 32;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: AutoSizeResult NUMERIC "1"
// Retrieval info: PRIVATE: B_isConstant NUMERIC "0"
// Retrieval info: PRIVATE: ConstantB NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: LPM_PIPELINE NUMERIC "1"
// Retrieval info: PRIVATE: Latency NUMERIC "0"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: SignedMult NUMERIC "1"
// Retrieval info: PRIVATE: USE_MULT NUMERIC "0"
// Retrieval info: PRIVATE: ValidConstant NUMERIC "0"
// Retrieval info: PRIVATE: WidthA NUMERIC "16"
// Retrieval info: PRIVATE: WidthB NUMERIC "8"
// Retrieval info: PRIVATE: WidthP NUMERIC "32"
// Retrieval info: PRIVATE: aclr NUMERIC "0"
// Retrieval info: PRIVATE: clken NUMERIC "0"
// Retrieval info: PRIVATE: new_diagram STRING "1"
// Retrieval info: PRIVATE: optimize NUMERIC "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: DATA_WIDTH NUMERIC "16"
// Retrieval info: CONSTANT: LPM_TYPE STRING "ALTSQUARE"
// Retrieval info: CONSTANT: PIPELINE NUMERIC "0"
// Retrieval info: CONSTANT: REPRESENTATION STRING "SIGNED"
// Retrieval info: CONSTANT: RESULT_WIDTH NUMERIC "32"
// Retrieval info: USED_PORT: dataa 0 0 16 0 INPUT NODEFVAL "dataa[15..0]"
// Retrieval info: USED_PORT: result 0 0 32 0 OUTPUT NODEFVAL "result[31..0]"
// Retrieval info: CONNECT: @data 0 0 16 0 dataa 0 0 16 0
// Retrieval info: CONNECT: result 0 0 32 0 @result 0 0 32 0
// Retrieval info: GEN_FILE: TYPE_NORMAL square.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL square.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL square.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL square.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL square_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL square_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// Based on code  by James Ahlstrom, N2ADR,  (C) 2011
// Modified for use with HPSDR by Phil Harman, VK6PH, (C) 2013

// Interpolating CIC filter, order 5.
// Produce an output when clock_en is true.  Output a strobe on req
// to request an input from the next filter.

module CicInterpM5(
    input clock,
    input clock_en,             // enable an output sample
    output reg req,             // request the next input sample
    input signed [IBITS-1:0] x_real,    // input samples
    input signed [IBITS-1:0] x_imag,
    output signed [OBITS-1:0] y_real,   // output samples
    output signed [OBITS-1:0] y_imag
    );
    
    parameter RRRR = 320;       // interpolation; limited by size of counter
    parameter IBITS = 20;       // input bits
    parameter OBITS = 16;       // output bits
    parameter GBITS = 34;       //log2(RRRR ** 4);  // growth bits: growth is R**M / R
    // Note: log2() rounds UP to the next integer - Not available in Verilog!
    localparam CBITS = IBITS + GBITS;   // calculation bits

    reg [8:0] counter;      // increase for higher maximum RRRR  **** was [7:0]

    reg signed [CBITS-1:0] x0, x1, x2, x3, x4, x5, dx0, dx1, dx2, dx3, dx4;     // variables for comb, real
    reg signed [CBITS-1:0] y1, y2, y3, y4, y5;  // variables for integrator, real
    reg signed [CBITS-1:0] q0, q1, q2, q3, q4, q5, dq0, dq1, dq2, dq3, dq4;     // variables for comb, imag
    reg signed [CBITS-1:0] s1, s2, s3, s4, s5;  // variables for integrator, imag

    wire signed [CBITS-1:0] sxtxr, sxtxi;
    assign sxtxr = {{(CBITS - IBITS){x_real[IBITS-1]}}, x_real};    // sign extended
    assign sxtxi = {{(CBITS - IBITS){x_imag[IBITS-1]}}, x_imag};
    assign y_real = y5[CBITS-1 -:OBITS] + y5[(CBITS-1)-OBITS];      // output data  with truncation to remove DC spur
    assign y_imag = s5[CBITS-1 -:OBITS] + s5[(CBITS-1)-OBITS];
    
    initial
    begin
        counter = 0;
        req = 0;
        x0 = 0;
        x1 = 0;
        x2 = 0;
        x3 = 0;
        x4 = 0;
        x5 = 0;
        q0 = 0;
        q1 = 0;
        q2 = 0;
        q3 = 0;
        q4 = 0;
        q5 = 0;
        y1 = 0;
        y2 = 0;
        y3 = 0;
        y4 = 0;
        y5 = 0;
        s1 = 0;
        s2 = 0;
        s3 = 0;
        s4 = 0;
        s5 = 0;
        dx0 = 0;
        dx1 = 0;
        dx2 = 0;
        dx3 = 0;
        dx4 = 0;
        dq0 = 0;
        dq1 = 0;
        dq2 = 0;
        dq3 = 0;
        dq4 = 0;
    end

    always @(posedge clock)
    begin
        if (clock_en)
        begin
            // (x0, q0) -> comb -> (x5, q5) -> interpolate -> integrate -> (y5, s5)
            if (counter == RRRR - 1)
            begin   // Process the sample (x0, q0) to get (x5, q5)
                counter <= 1'd0;
                x0 <= sxtxr;
                q0 <= sxtxi;
                req <= 1'd1;
                // Comb for real data
                x1 <= x0 - dx0;
                x2 <= x1 - dx1;         
                x3 <= x2 - dx2;             
                x4 <= x3 - dx3;             
                x5 <= x4 - dx4;         
                dx0 <= x0;
                dx1 <= x1;
                dx2 <= x2;
                dx3 <= x3;
                dx4 <= x4;
                // Comb for imaginary data
                q1 <= q0 - dq0;
                q2 <= q1 - dq1;
                q3 <= q2 - dq2;
                q4 <= q3 - dq3;
                q5 <= q4 - dq4;
                dq0 <= q0;
                dq1 <= q1;
                dq2 <= q2;
                dq3 <= q3;
                dq4 <= q4;
            end
            else
            begin
                counter <= counter + 1'd1;
                x5 <= 0;    // stuff a zero for (x5, q5)
                q5 <= 0;
                req <= 1'd0;
            end
            // Integrate the sample (x5, q5) to get the output (y5, s5)
            // Integrator for real data; input is x5
            y1 <= y1 + x5;
            y2 <= y2 + y1;
            y3 <= y3 + y2;
            y4 <= y4 + y3;
            y5 <= y5 + y4;
            // Integrator for imaginary data; input is q5
            s1 <= s1 + q5;
            s2 <= s2 + s1;
            s3 <= s3 + s2;
            s4 <= s4 + s3;
            s5 <= s5 + s4;
        end
        else
        begin
            req <= 1'd0;
        end
    end
endmodule

// megafunction wizard: %ALTSQRT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: ALTSQRT 

// ============================================================
// File Name: sqroot.v
// Megafunction Name(s):
// 			ALTSQRT
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 16.1.2 Build 203 01/18/2017 SJ Lite Edition
// ************************************************************


//Copyright (C) 2017  Intel Corporation. All rights reserved.
//Your use of Intel Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Intel Program License 
//Subscription Agreement, the Intel Quartus Prime License Agreement,
//the Intel MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Intel and sold by Intel or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module sqroot (
	clk,
	radical,
	q,
	remainder);

	input	  clk;
	input	[31:0]  radical;
	output	[15:0]  q;
	output	[16:0]  remainder;

	wire [15:0] sub_wire0;
	wire [16:0] sub_wire1;
	wire [15:0] q = sub_wire0[15:0];
	wire [16:0] remainder = sub_wire1[16:0];
/*
	altsqrt	ALTSQRT_component (
				.clk (clk),
				.radical (radical),
				.q (sub_wire0),
				.remainder (sub_wire1)
				// synopsys translate_off
				,
				.aclr (),
				.ena ()
				// synopsys translate_on
				);
	defparam
		ALTSQRT_component.pipeline = 10,
		ALTSQRT_component.q_port_width = 16,
		ALTSQRT_component.r_port_width = 17,
		ALTSQRT_component.width = 32;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: PIPELINE NUMERIC "10"
// Retrieval info: CONSTANT: Q_PORT_WIDTH NUMERIC "16"
// Retrieval info: CONSTANT: R_PORT_WIDTH NUMERIC "17"
// Retrieval info: CONSTANT: WIDTH NUMERIC "32"
// Retrieval info: USED_PORT: clk 0 0 0 0 INPUT NODEFVAL "clk"
// Retrieval info: USED_PORT: q 0 0 16 0 OUTPUT NODEFVAL "q[15..0]"
// Retrieval info: USED_PORT: radical 0 0 32 0 INPUT NODEFVAL "radical[31..0]"
// Retrieval info: USED_PORT: remainder 0 0 17 0 OUTPUT NODEFVAL "remainder[16..0]"
// Retrieval info: CONNECT: @clk 0 0 0 0 clk 0 0 0 0
// Retrieval info: CONNECT: @radical 0 0 32 0 radical 0 0 32 0
// Retrieval info: CONNECT: q 0 0 16 0 @q 0 0 16 0
// Retrieval info: CONNECT: remainder 0 0 17 0 @remainder 0 0 17 0
// Retrieval info: GEN_FILE: TYPE_NORMAL sqroot.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL sqroot.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL sqroot.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL sqroot.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL sqroot_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL sqroot_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
// megafunction wizard: %LPM_COUNTER%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: LPM_COUNTER 

// ============================================================
// File Name: counter.v
// Megafunction Name(s):
// 			LPM_COUNTER
//
// Simulation Library Files(s):
// 			lpm
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 16.1.2 Build 203 01/18/2017 SJ Lite Edition
// ************************************************************


//Copyright (C) 2017  Intel Corporation. All rights reserved.
//Your use of Intel Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Intel Program License 
//Subscription Agreement, the Intel Quartus Prime License Agreement,
//the Intel MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Intel and sold by Intel or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module counter (
	clock,
	q);

	input	  clock;
	output	[10:0]  q;

	wire [10:0] sub_wire0;
	wire [10:0] q = sub_wire0[10:0];
/*
	lpm_counter	LPM_COUNTER_component (
				.clock (clock),
				.q (sub_wire0),
				.aclr (1'b0),
				.aload (1'b0),
				.aset (1'b0),
				.cin (1'b1),
				.clk_en (1'b1),
				.cnt_en (1'b1),
				.cout (),
				.data ({11{1'b0}}),
				.eq (),
				.sclr (1'b0),
				.sload (1'b0),
				.sset (1'b0),
				.updown (1'b1));
	defparam
		LPM_COUNTER_component.lpm_direction = "UP",
		LPM_COUNTER_component.lpm_modulus = 1024,
		LPM_COUNTER_component.lpm_port_updown = "PORT_UNUSED",
		LPM_COUNTER_component.lpm_type = "LPM_COUNTER",
		LPM_COUNTER_component.lpm_width = 11;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ACLR NUMERIC "0"
// Retrieval info: PRIVATE: ALOAD NUMERIC "0"
// Retrieval info: PRIVATE: ASET NUMERIC "0"
// Retrieval info: PRIVATE: ASET_ALL1 NUMERIC "1"
// Retrieval info: PRIVATE: CLK_EN NUMERIC "0"
// Retrieval info: PRIVATE: CNT_EN NUMERIC "0"
// Retrieval info: PRIVATE: CarryIn NUMERIC "0"
// Retrieval info: PRIVATE: CarryOut NUMERIC "0"
// Retrieval info: PRIVATE: Direction NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: ModulusCounter NUMERIC "1"
// Retrieval info: PRIVATE: ModulusValue NUMERIC "1024"
// Retrieval info: PRIVATE: SCLR NUMERIC "0"
// Retrieval info: PRIVATE: SLOAD NUMERIC "0"
// Retrieval info: PRIVATE: SSET NUMERIC "0"
// Retrieval info: PRIVATE: SSET_ALL1 NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: nBit NUMERIC "11"
// Retrieval info: PRIVATE: new_diagram STRING "1"
// Retrieval info: LIBRARY: lpm lpm.lpm_components.all
// Retrieval info: CONSTANT: LPM_DIRECTION STRING "UP"
// Retrieval info: CONSTANT: LPM_MODULUS NUMERIC "1024"
// Retrieval info: CONSTANT: LPM_PORT_UPDOWN STRING "PORT_UNUSED"
// Retrieval info: CONSTANT: LPM_TYPE STRING "LPM_COUNTER"
// Retrieval info: CONSTANT: LPM_WIDTH NUMERIC "11"
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT NODEFVAL "clock"
// Retrieval info: USED_PORT: q 0 0 11 0 OUTPUT NODEFVAL "q[10..0]"
// Retrieval info: CONNECT: @clock 0 0 0 0 clock 0 0 0 0
// Retrieval info: CONNECT: q 0 0 11 0 @q 0 0 11 0
// Retrieval info: GEN_FILE: TYPE_NORMAL counter.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL counter.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL counter.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL counter.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL counter_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL counter_bb.v FALSE
// Retrieval info: LIB_FILE: lpm
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------

// 2013 Jan 26	- Modified to accept decimation values from 1-40. VK6APH 

module varcic(decimation, clock, in_strobe,  out_strobe, in_data, out_data );

  //design parameters
  parameter STAGES = 5;
  parameter IN_WIDTH = 18;
  parameter ACC_WIDTH = 45;
  parameter OUT_WIDTH = 18;
  parameter CICRATE = 12;
  
  input [5:0] decimation; 
  
  input clock;
  input in_strobe;
  output reg out_strobe;

  input signed [IN_WIDTH-1:0] in_data;
  output reg signed [OUT_WIDTH-1:0] out_data;


//------------------------------------------------------------------------------
//                               control
//------------------------------------------------------------------------------
reg [15:0] sample_no = 0;

always @(posedge clock)
  if (in_strobe)
    begin
    if (sample_no == (decimation - 1))
      begin
      sample_no <= 0;
      out_strobe <= 1;
      end
    else
      begin
      sample_no <= sample_no + 8'd1;
      out_strobe <= 0;
      end
    end

  else
    out_strobe <= 0;


//------------------------------------------------------------------------------
//                                stages
//------------------------------------------------------------------------------
wire signed [ACC_WIDTH-1:0] integrator_data [0:STAGES];
wire signed [ACC_WIDTH-1:0] comb_data [0:STAGES];


assign integrator_data[0] = in_data;
assign comb_data[0] = integrator_data[STAGES];


genvar i;
generate
  for (i=0; i<STAGES; i=i+1)
    begin : cic_stages

    cic_integrator #(ACC_WIDTH) cic_integrator_inst(
      .clock(clock),
      .strobe(in_strobe),
      .in_data(integrator_data[i]),
      .out_data(integrator_data[i+1])
      );


    cic_comb #(ACC_WIDTH) cic_comb_inst(
      .clock(clock),
      .strobe(out_strobe),
      .in_data(comb_data[i]),
      .out_data(comb_data[i+1])
      );
    end
endgenerate


//------------------------------------------------------------------------------
//                            output rounding
//------------------------------------------------------------------------------

/*
-----------------------------------------------------
 Output rounding calculations for 5 stages 

 sample rate (ksps)  decimation 	 bit growth
  48                  16            34-14 = 20
  96                   8            29-14 = 15
 192                   4            24-14 = 10
 384                   2            19-14 = 5
-------------------------------------------------------		  
*/		
// also math.log(growthN,2) * 5

// FIXME: Should be cleaner way to do all this...
localparam GROWTH2  =  5;
localparam GROWTH4  = 10;
localparam GROWTH8  = 15;
localparam GROWTH16 = 20;

localparam MSB2  =  (IN_WIDTH + GROWTH2)  - 1;           
localparam LSB2  =  (IN_WIDTH + GROWTH2)  - OUT_WIDTH;   

localparam MSB4  =  (IN_WIDTH + GROWTH4)  - 1;            
localparam LSB4  =  (IN_WIDTH + GROWTH4)  - OUT_WIDTH;  

localparam MSB8  =  (IN_WIDTH + GROWTH8)  - 1;           
localparam LSB8  =  (IN_WIDTH + GROWTH8)  - OUT_WIDTH;  

localparam MSB16 =  (IN_WIDTH + GROWTH16) - 1;       
localparam LSB16 =  (IN_WIDTH + GROWTH16) - OUT_WIDTH;


localparam GROWTH3  =  8;
localparam GROWTH6  = 13;
localparam GROWTH12  = 18;
localparam GROWTH24 = 23;

localparam MSB3  =  (IN_WIDTH + GROWTH3)  - 1;           
localparam LSB3  =  (IN_WIDTH + GROWTH3)  - OUT_WIDTH;   

localparam MSB6  =  (IN_WIDTH + GROWTH6)  - 1;            
localparam LSB6  =  (IN_WIDTH + GROWTH6)  - OUT_WIDTH;  

localparam MSB12  =  (IN_WIDTH + GROWTH12)  - 1;           
localparam LSB12  =  (IN_WIDTH + GROWTH12)  - OUT_WIDTH;  

localparam MSB24 =  (IN_WIDTH + GROWTH24) - 1;       
localparam LSB24 =  (IN_WIDTH + GROWTH24) - OUT_WIDTH;


localparam GROWTH5  =  12;
localparam GROWTH10  = 17;
localparam GROWTH20  = 22;
localparam GROWTH40 = 27;

localparam MSB5  =  (IN_WIDTH + GROWTH5)  - 1;           
localparam LSB5  =  (IN_WIDTH + GROWTH5)  - OUT_WIDTH;   

localparam MSB10  =  (IN_WIDTH + GROWTH10)  - 1;            
localparam LSB10  =  (IN_WIDTH + GROWTH10)  - OUT_WIDTH;  

localparam MSB20  =  (IN_WIDTH + GROWTH20)  - 1;           
localparam LSB20  =  (IN_WIDTH + GROWTH20)  - OUT_WIDTH;  

localparam MSB40 =  (IN_WIDTH + GROWTH40) - 1;       
localparam LSB40 =  (IN_WIDTH + GROWTH40) - OUT_WIDTH;

generate
  if (CICRATE == 10)
    always @(posedge clock)
      case (decimation)
         2: out_data <= comb_data[STAGES][MSB2:LSB2]   + comb_data[STAGES][LSB2-1];
         4: out_data <= comb_data[STAGES][MSB4:LSB4]   + comb_data[STAGES][LSB4-1];
         8: out_data <= comb_data[STAGES][MSB8:LSB8]   + comb_data[STAGES][LSB8-1];
        default: out_data <= comb_data[STAGES][MSB16:LSB16] + comb_data[STAGES][LSB16-1];        
      endcase
  else if (CICRATE == 13)
    always @(posedge clock)
      case (decimation)
         2: out_data <= comb_data[STAGES][MSB2:LSB2]   + comb_data[STAGES][LSB2-1];
         4: out_data <= comb_data[STAGES][MSB4:LSB4]   + comb_data[STAGES][LSB4-1];
         8: out_data <= comb_data[STAGES][MSB8:LSB8]   + comb_data[STAGES][LSB8-1];
        default: out_data <= comb_data[STAGES][MSB16:LSB16] + comb_data[STAGES][LSB16-1];        
      endcase
  else if (CICRATE == 5)
    always @(posedge clock)
      case (decimation)
         5: out_data <= comb_data[STAGES][MSB5:LSB5]   + comb_data[STAGES][LSB5-1];
         10: out_data <= comb_data[STAGES][MSB10:LSB10]   + comb_data[STAGES][LSB10-1];
         20: out_data <= comb_data[STAGES][MSB20:LSB20]   + comb_data[STAGES][LSB20-1];
        default: out_data <= comb_data[STAGES][MSB40:LSB40] + comb_data[STAGES][LSB40-1];    
      endcase 
  else
    always @(posedge clock)
      case (decimation)
         3: out_data <= comb_data[STAGES][MSB3:LSB3]   + comb_data[STAGES][LSB3-1];
         6: out_data <= comb_data[STAGES][MSB6:LSB6]   + comb_data[STAGES][LSB6-1];
         12: out_data <= comb_data[STAGES][MSB12:LSB12]   + comb_data[STAGES][LSB12-1];
        default: out_data <= comb_data[STAGES][MSB24:LSB24] + comb_data[STAGES][LSB24-1];        
      endcase
endgenerate    


endmodule

  
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Algorithm by Darrell Harmon modified by Cathy Moss
//            Code Copyright (c) 2009 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------


module cpl_cordic(
  input clock,
  input signed [WF-1:0] frequency,
  input signed [IN_WIDTH-1:0] in_data_I,
  input signed [IN_WIDTH-1:0] in_data_Q,
  output signed [WO-1:0] out_data_I,
  output signed [WO-1:0] out_data_Q
  );


parameter IN_WIDTH   = 16; //ADC bitwidth
parameter EXTRA_BITS = 5;  //spur reduction 6 dB per bit
parameter OUT_WIDTH = WR;  //23-bit output width

//internal params
localparam WR =  IN_WIDTH + EXTRA_BITS + 2; //23-bit data regs
localparam WZ =  IN_WIDTH + EXTRA_BITS - 1; //20-bit angle regs
localparam STG = IN_WIDTH + EXTRA_BITS - 2; //19 stages
localparam WO = OUT_WIDTH;

localparam WF = 32; //NCO freq,  -Pi..Pi per clock cycle
localparam WP = 32; //NCO phase, 0..2*Pi







//------------------------------------------------------------------------------
//                             arctan table
//------------------------------------------------------------------------------
localparam WT = 32;

wire signed [WT-1:0] atan_table [1:WT-1];


//     atan_table[00] = 32'b01000000000000000000000000000000; //1073741824  FYI
assign atan_table[01] = 32'b00100101110010000000101000111011; //633866811
assign atan_table[02] = 32'b00010011111101100111000010110111; //334917815
assign atan_table[03] = 32'b00001010001000100010001110101000; //170009512
assign atan_table[04] = 32'b00000101000101100001101010000110; //85334662
assign atan_table[05] = 32'b00000010100010111010111111000011; //42708931
assign atan_table[06] = 32'b00000001010001011110110000111101; //21359677
assign atan_table[07] = 32'b00000000101000101111100010101010; //10680490
assign atan_table[08] = 32'b00000000010100010111110010100111; //5340327
assign atan_table[09] = 32'b00000000001010001011111001011101; //2670173
assign atan_table[10] = 32'b00000000000101000101111100110000; //1335088
assign atan_table[11] = 32'b00000000000010100010111110011000; //667544
assign atan_table[12] = 32'b00000000000001010001011111001100; //333772
assign atan_table[13] = 32'b00000000000000101000101111100110; //166886
assign atan_table[14] = 32'b00000000000000010100010111110011; //83443
assign atan_table[15] = 32'b00000000000000001010001011111010; //41722
assign atan_table[16] = 32'b00000000000000000101000101111101; //20861
assign atan_table[17] = 32'b00000000000000000010100010111110; //10430
assign atan_table[18] = 32'b00000000000000000001010001011111; //5215
assign atan_table[19] = 32'b00000000000000000000101000110000; //2608
assign atan_table[20] = 32'b00000000000000000000010100011000; //1304
assign atan_table[21] = 32'b00000000000000000000001010001100; //652
assign atan_table[22] = 32'b00000000000000000000000101000110; //326
assign atan_table[23] = 32'b00000000000000000000000010100011; //163
assign atan_table[24] = 32'b00000000000000000000000001010001; //81
assign atan_table[25] = 32'b00000000000000000000000000101001; //41
assign atan_table[26] = 32'b00000000000000000000000000010100; //20
assign atan_table[27] = 32'b00000000000000000000000000001010; //10
assign atan_table[28] = 32'b00000000000000000000000000000101; //5
assign atan_table[29] = 32'b00000000000000000000000000000011; //3
assign atan_table[30] = 32'b00000000000000000000000000000001; //1
assign atan_table[31] = 32'b00000000000000000000000000000001; //1








//------------------------------------------------------------------------------
//                              registers
//------------------------------------------------------------------------------
//NCO
reg [WP-1:0] phase = 0;
wire [1:0] quadrant = phase[WP-1:WP-2];


//stage outputs
reg signed [WR-1:0] X [0:STG-1];
reg signed [WR-1:0] Y [0:STG-1];
reg signed [WZ-1:0] Z [0:STG-1];






//------------------------------------------------------------------------------
//                               stage 0
//------------------------------------------------------------------------------
//input word sign-extended by 2 bits, padded at the right with EXTRA_BITS of zeros
wire signed [WR-1:0] in_data_I_ext = {{2{in_data_I[IN_WIDTH-1]}}, in_data_I, {EXTRA_BITS{1'b0}}};
wire signed [WR-1:0] in_data_Q_ext = {{2{in_data_Q[IN_WIDTH-1]}}, in_data_Q, {EXTRA_BITS{1'b0}}};



always @(posedge clock)
  begin
  //rotate to the required quadrant, pre-rotate by +Pi/4. 
  //the gain of this stage is 2.0, overall cordic gain is Sqrt(2)*1.647
  case (quadrant)
    0: begin X[0] <=  in_data_I_ext - in_data_Q_ext;   Y[0] <=  in_data_I_ext + in_data_Q_ext; end
    1: begin X[0] <= -in_data_I_ext - in_data_Q_ext;   Y[0] <=  in_data_I_ext - in_data_Q_ext; end
    2: begin X[0] <= -in_data_I_ext + in_data_Q_ext;   Y[0] <= -in_data_I_ext - in_data_Q_ext; end
    3: begin X[0] <=  in_data_I_ext + in_data_Q_ext;   Y[0] <= -in_data_I_ext + in_data_Q_ext; end
  endcase

  //subtract quadrant and Pi/4 from the angle
  Z[0] <= {~phase[WP-3], ~phase[WP-3], phase[WP-4:WP-WZ-1]};

  //advance NCO
  if (frequency == 1'b0)
    // For zero frequency, synchronize phase to other cordics.
    phase <= 1'b0;
  else
    //advance NCO
    phase <= phase + frequency;
  end






//------------------------------------------------------------------------------
//                           stages 1 to STG-1
//------------------------------------------------------------------------------
genvar n;


generate
  for (n=0; n<=(STG-2); n=n+1)
    begin : stages
    //data from prev stage, shifted
    wire signed [WR-1:0] X_shr = {{(n+1){X[n][WR-1]}}, X[n][WR-1:n+1]};
    wire signed [WR-1:0] Y_shr = {{(n+1){Y[n][WR-1]}}, Y[n][WR-1:n+1]};


    //rounded arctan
    wire [WZ-2-n:0] atan = atan_table[n+1][WT-2-n:WT-WZ] + atan_table[n+1][WT-WZ-1];


    //the sign of the residual
    wire Z_sign = Z[n][WZ-1-n];


    always @(posedge clock)
      begin
      //add/subtract shifted and rounded data
      X[n+1] <= Z_sign ? X[n] + Y_shr + Y[n][n] : X[n] - Y_shr - Y[n][n];
      Y[n+1] <= Z_sign ? Y[n] - X_shr - X[n][n] : Y[n] + X_shr + X[n][n];

      //update angle
      if (n < STG-2)
        begin : angles
        Z[n+1][WZ-2-n:0] <= Z_sign ? Z[n][WZ-2-n:0] + atan : Z[n][WZ-2-n:0] - atan;
        end
      end
    end
endgenerate






//------------------------------------------------------------------------------
//                                 output
//------------------------------------------------------------------------------
generate
  if (OUT_WIDTH == WR)
    begin
    assign out_data_I = X[STG-1];
    assign out_data_Q = Y[STG-1];
    end
    
  else
    begin
    reg signed [WO-1:0] rounded_I =0;
    reg signed [WO-1:0] rounded_Q =0;

    always @(posedge clock)
      begin
      rounded_I <= X[STG-1][WR-1 : WR-WO] + X[STG-1][WR-1-WO];
      rounded_Q <= Y[STG-1][WR-1 : WR-WO] + Y[STG-1][WR-1-WO];
      end
      
    assign out_data_I = rounded_I;
    assign out_data_Q = rounded_Q;
    end
endgenerate



endmodule
module radio (

  clk,
  clk_2x,

  cw_keydown,
  tx_on,
  tx_cw_key,    // CW waveform is active, tx_cw_level is not zero
  tx_hang,

  // Transmit
  tx_tdata,
  tx_tid,
  tx_tlast,
  tx_tready,
  tx_tvalid,

  tx_data_dac,

  clk_envelope,
  tx_envelope_pwm_out,
  tx_envelope_pwm_out_inv,

  // Optional audio stream for repurposed programming or EER
  lr_tdata,
  lr_tid,
  lr_tlast,
  lr_tready,
  lr_tvalid,

  // Receive
  rx_data_adc,

  rx_tdata,
  rx_tlast,
  rx_tready,
  rx_tvalid,
  rx_tuser,

  // Command slave interface
  cmd_addr,
  cmd_data,
  cmd_rqst,
  cmd_ack
);

parameter         NR = 3;
parameter         NT = 1;
parameter         LRDATA = 0;
parameter         VNA = 1;
parameter         CWSHAPE = 1;
parameter         CLK_FREQ = 76800000;

parameter         RECEIVER2 = 0;
parameter         QS1R = 0;

// B57 = 2^57.   M2 = B57/OSC
// 61440000
//localparam M2 = 32'd2345624805;
// 61440000-400
//localparam M2 = 32'd2345640077;
localparam M2 = (CLK_FREQ == 61440000) ? 32'd2345640077 : (CLK_FREQ == 79872000) ? 32'd1804326773 : (CLK_FREQ == 76800000) ? 32'd1876499845 : 32'd1954687338;

// M3 = 2^24 to round as version 2.7
localparam M3 = 32'd16777216;

localparam CICRATE = (CLK_FREQ == 61440000) ? 6'd10 : (CLK_FREQ == 79872000) ? 6'd13 : (CLK_FREQ == 76800000) ? 6'd05 : 6'd08;
localparam GBITS = (CLK_FREQ == 61440000) ? 30 : (CLK_FREQ == 79872000) ? 31 : (CLK_FREQ == 76800000) ? 31 : 31;
localparam RRRR = (CLK_FREQ == 61440000) ? 160 : (CLK_FREQ == 79872000) ? 208 : (CLK_FREQ == 76800000) ? 200 : 192;

// Decimation rates
localparam RATE48  = (CLK_FREQ == 61440000) ? 6'd16 : (CLK_FREQ == 79872000) ? 6'd16 : (CLK_FREQ == 76800000) ? 6'd40 : 6'd24;
localparam RATE96  =  RATE48  >> 1;
localparam RATE192 =  RATE96  >> 1;
localparam RATE384 =  RATE192 >> 1;


input             clk;
input             clk_2x;

input             cw_keydown;
input             tx_on;
output logic            tx_cw_key;
output logic            tx_hang;

input             clk_envelope;
output logic            tx_envelope_pwm_out;
output logic            tx_envelope_pwm_out_inv;

input   [31:0]    tx_tdata;
input   [ 2:0]    tx_tid;
input             tx_tlast;
output logic            tx_tready;
input             tx_tvalid;

input   [31:0]    lr_tdata;
input   [ 2:0]    lr_tid;
input             lr_tlast;
output logic            lr_tready;
input             lr_tvalid;

output logic  [11:0]    tx_data_dac;

input   [11:0]    rx_data_adc;

output logic  [23:0]    rx_tdata;
output logic            rx_tlast;
input             rx_tready;
output logic            rx_tvalid;
output logic  [ 1:0]    rx_tuser;


// Command slave interface
input   [5:0]     cmd_addr;
input   [31:0]    cmd_data;
input             cmd_rqst;
output logic            cmd_ack;


logic [ 1:0]        tx_predistort = 2'b00;
logic [ 1:0]        tx_predistort_next;

logic               pure_signal = 1'b0;
logic               pure_signal_next;

logic               vna = 1'b0;
logic               vna_next;
logic  [15:0]       vna_count;
logic  [15:0]       vna_count_next;

logic  [ 1:0]       rx_rate = 2'b00;
logic  [ 1:0]       rx_rate_next;

logic  [ 4:0]       last_chan = 5'h0;
logic  [ 4:0]       last_chan_next;

logic  [ 4:0]       chan = 5'h0;
logic  [ 4:0]       chan_next;

logic               duplex = 1'b0;
logic               duplex_next;

logic               pa_mode = 1'b0;
logic               pa_mode_next;
logic  [ 9:0]       PWM_min = 10'd0; // minimum width of TX envelope PWM pulse
logic  [ 9:0]       PWM_min_next;
logic  [ 9:0]       PWM_max = 10'd1023; // maximum width of TX envelope PWM pulse
logic  [ 9:0]       PWM_max_next;

logic   [5:0]       rate;
logic   [11:0]      adcpipe [0:3];


logic [23:0]  rx_data_i [0:NR-1];
logic [23:0]  rx_data_q [0:NR-1];
logic         rx_data_rdy [0:NR-1];

logic [63:0]  freqcomp;
logic [31:0]  freqcompp [0:3];
logic [5:0]   chanp [0:3];


logic [31:0]  rx_phase [0:NR];    // The Rx phase calculated from the frequency sent by the PC.
logic [31:0]  tx_phase0;

// Always one more so that dangling assignment can be made
logic signed [17:0]   mixdata_i [0:NR];
logic signed [17:0]   mixdata_q [0:NR]; 


genvar c;

localparam 
  CMD_IDLE    = 2'b00,
  CMD_FREQ1   = 2'b01,
  CMD_FREQ2   = 2'b11,
  CMD_FREQ3   = 2'b10;

logic [1:0]   cmd_state = CMD_IDLE;
logic [1:0]   cmd_state_next;

// Command Slave State Machine
always @(posedge clk) begin
  cmd_state <= cmd_state_next;
  vna <= vna_next;
  vna_count <= vna_count_next;
  rx_rate <= rx_rate_next;
  pure_signal <= pure_signal_next;
  tx_predistort <= tx_predistort_next;
  last_chan <= last_chan_next;
  duplex <= duplex_next;
  pa_mode <= pa_mode_next;
  PWM_min <= PWM_min_next;
  PWM_max <= PWM_max_next;
end

always @* begin
  cmd_state_next = cmd_state;
  cmd_ack = 1'b0;
  vna_next = vna;
  vna_count_next = vna_count;
  rx_rate_next = rx_rate;
  pure_signal_next = pure_signal;
  tx_predistort_next = tx_predistort;
  last_chan_next = last_chan;
  duplex_next = duplex;
  pa_mode_next = pa_mode;
  PWM_min_next = PWM_min;
  PWM_max_next = PWM_max;

  case(cmd_state)

    CMD_IDLE: begin
      if (cmd_rqst) begin
        case (cmd_addr)
          // Frequency changes
          6'h01:    cmd_state_next    = CMD_FREQ1;
          6'h02:    cmd_state_next    = CMD_FREQ1;
          6'h03:    cmd_state_next    = CMD_FREQ1;
          6'h04:    cmd_state_next    = CMD_FREQ1;
          6'h05:    cmd_state_next    = CMD_FREQ1;
          6'h06:    cmd_state_next    = CMD_FREQ1;
          6'h07:    cmd_state_next    = CMD_FREQ1;
          6'h08:    cmd_state_next    = CMD_FREQ1;
          6'h12:    cmd_state_next    = CMD_FREQ1;
          6'h13:    cmd_state_next    = CMD_FREQ1;
          6'h14:    cmd_state_next    = CMD_FREQ1;
          6'h15:    cmd_state_next    = CMD_FREQ1;
          6'h16:    cmd_state_next    = CMD_FREQ1;

          // Control with no acknowledge
          6'h00: begin
            rx_rate_next              = cmd_data[25:24];
            pa_mode_next              = cmd_data[16];
            last_chan_next            = cmd_data[7:3];
            duplex_next               = cmd_data[2];
          end

          6'h09: begin
            vna_next         = cmd_data[23];
            vna_count_next   = cmd_data[15:0];
          end
          6'h0a:    pure_signal_next  = cmd_data[22];

          6'h11: begin
            // TX envelope PWM min and max
            PWM_min_next = {cmd_data[31:24], cmd_data[17:16]};
            PWM_max_next = {cmd_data[15:8], cmd_data[1:0]};
          end

          6'h2b: begin
            //predistortion control sub index
            if(cmd_data[31:24]==8'h00) begin
              tx_predistort_next      = cmd_data[17:16];
            end
          end

          default:  cmd_state_next = cmd_state;
        endcase 
      end        
    end

    CMD_FREQ1: begin
      cmd_state_next = CMD_FREQ2;
    end

    CMD_FREQ2: begin
      cmd_state_next = CMD_FREQ3;
    end

    CMD_FREQ3: begin
      cmd_state_next = CMD_IDLE;
      cmd_ack = 1'b1;
    end
  endcase
end


// Frequency computation
// Always compute frequency
// This really should be done on the PC and not in the FPGA....
// This is not guarded by CDC handshake, but use of freqcomp
// is guarded by CDC handshake
assign freqcomp = cmd_data * M2 + M3;

// Pipeline freqcomp
always @ (posedge clk) begin
  // Pipeline to allow 2 cycles for multiply
  if (cmd_state == CMD_FREQ2) begin
    freqcompp[0] <= freqcomp[56:25];
    freqcompp[1] <= freqcomp[56:25];
    freqcompp[2] <= freqcomp[56:25];
    freqcompp[3] <= freqcomp[56:25];
    chanp[0] <= cmd_addr;
    chanp[1] <= cmd_addr;
    chanp[2] <= cmd_addr;
    chanp[3] <= cmd_addr;
  end
end

// TX0 and RX0
always @ (posedge clk) begin
  if (cmd_state == CMD_FREQ3) begin
    if (chanp[0] == 6'h01) begin 
      tx_phase0 <= freqcompp[0]; 
      if (!duplex && (last_chan == 5'b00000)) rx_phase[0] <= freqcompp[0];
    end

    if (chanp[0] == 6'h02) begin 
      if (!duplex && (last_chan == 5'b00000)) rx_phase[0] <= tx_phase0;
      else rx_phase[0] <= freqcompp[0];
    end
  end
end

// RX > 1
generate
  for (c = 1; c < NR; c = c + 1) begin: RXIFFREQ
    always @ (posedge clk) begin
      if (cmd_state == CMD_FREQ3) begin
        if (chanp[c/8] == ((c < 7) ? c+2 : c+11)) begin
          rx_phase[c] <= freqcompp[c/8]; 
        end
      end
    end
  end
endgenerate

// Pipeline for adc fanout
always @ (posedge clk) begin
  adcpipe[0] <= rx_data_adc;
  adcpipe[1] <= rx_data_adc;
  adcpipe[2] <= rx_data_adc;
  adcpipe[3] <= rx_data_adc;
end

// set the decimation rate 40 = 48k.....2 = 960k
always @ (rx_rate) begin
  case (rx_rate)
    0: rate <= RATE48;     //  48ksps
    1: rate <= RATE96;     //  96ksps
    2: rate <= RATE192;    //  192ksps
    3: rate <= RATE384;    //  384ksps
    default: rate <= RATE48;
  endcase
end

logic [31:0]  tx0_phase;    // For VNAscan, starts at tx_phase0 and increments for vna_count points; else tx_phase0.

generate if (VNA == 1) begin: VNA1

// VNA scanning code added by Jim Ahlstrom, N2ADR, May 2018.
// The firmware can scan frequencies for the VNA if vna_count > 0. The vna then controls the Rx and Tx frequencies.
// The starting frequency is tx_phase0, the increment is rx_phase[0], and there are vna_count points.

logic [31:0]  rx0_phase;    // For VNAscan, equals tx0_phase; else rx_phase[0].
// This firmware supports two VNA modes: scanning by the PC (original method) and scanning in the FPGA.
// The VNA bit must be turned on for either.  So VNA is one for either method, and zero otherwise.
// The scan method depends on the number of VNA scan points, vna_count.  This is zero for the original method.
// wire VNA_SCAN_PC   = vna & (vna_count == 0);    // The PC changes the frequency for VNA.
wire VNA_SCAN_FPGA = vna & (vna_count != 0);    // The firmware changes the frequency.

wire signed [17:0] cordic_data_I, cordic_data_Q;
wire vna_strobe, rx0_strobe;
wire signed [23:0] vna_out_I, vna_out_Q, rx0_out_I, rx0_out_Q;

assign rx_data_rdy[0] = VNA_SCAN_FPGA ? vna_strobe : rx0_strobe;
assign rx_data_i[0] = VNA_SCAN_FPGA ? vna_out_I : rx0_out_I;
assign rx_data_q[0] = VNA_SCAN_FPGA ? vna_out_Q : rx0_out_Q;

// This module is a replacement for receiver zero when the FPGA scans in VNA mode.
vna_scanner #(.CICRATE(CICRATE), .RATE48(RATE48)) rx_vna (  // use this output for VNA_SCAN_FPGA
    //control
    .clock(clk),
    .freq_delta(rx_phase[0]),
    .output_strobe(vna_strobe),
    //input
    .cordic_data_I(cordic_data_I),
    .cordic_data_Q(cordic_data_Q),
    //output
    .out_data_I(vna_out_I),
    .out_data_Q(vna_out_Q),
    // VNA mode data
    .vna(vna),
    .Tx_frequency_in(tx_phase0),
    .Tx_frequency_out(tx0_phase),
    .vna_count(vna_count)
    );


  // First receiver
  // If in VNA mode use the Tx[0] phase word for the first receiver phase
  assign rx0_phase = vna ? tx0_phase : rx_phase[0];

  mix2 #(.CALCTYPE(3)) mix2_0 (
    .clk(clk),
    .clk_2x(clk_2x),
    .rst(1'b0),
    .phi0(rx0_phase),
    .phi1(rx_phase[1]),
    .adc(adcpipe[0]), 
    .mixdata0_i(mixdata_i[0]),
    .mixdata0_q(mixdata_q[0]),
    .mixdata1_i(mixdata_i[1]),
    .mixdata1_q(mixdata_q[1])
  );

  receiver_nco #(.CICRATE(CICRATE)) receiver_0 (
    .clock(clk),
    .clock_2x(clk_2x),
    .rate(rate),
    .mixdata_I(mixdata_i[0]),
    .mixdata_Q(mixdata_q[0]),
    .out_strobe(rx0_strobe),
    .out_data_I(rx0_out_I),
    .out_data_Q(rx0_out_Q)
  );

  assign cordic_data_I = mixdata_i[0];
  assign cordic_data_Q = mixdata_q[0];

//  receiver #(.CICRATE(CICRATE)) receiver_0_inst (
//    .clock(clk),
//    .clock_2x(clk_2x),
//    .rate(rate),
//    .frequency(rx0_phase),
//    .out_strobe(rx0_strobe),
//    .in_data(adcpipe[0]),
//    .out_data_I(rx0_out_I),
//    .out_data_Q(rx0_out_Q),
//    .cordic_outdata_I(cordic_data_I),
//    .cordic_outdata_Q(cordic_data_Q)
//  );

  //for (c = 1; c < NR; c = c + 1) begin: MDC
  //  if((c==3 && NR>3) || (c==1 && NR<=3)) begin
  //      receiver #(.CICRATE(CICRATE)) receiver_inst (
  //        .clock(clk),
  //        .clock_2x(clk_2x),
  //        .rate(rate),
  //        .frequency(rx_phase[c]),
  //        .out_strobe(rx_data_rdy[c]),
  //        .in_data((tx_on & pure_signal) ? tx_data_dac : adcpipe[c/8]), //tx_data was pipelined here once
  //        .out_data_I(rx_data_i[c]),
  //        .out_data_Q(rx_data_q[c])
  //      );
  //  end else begin
  //      receiver_nco #(.CICRATE(CICRATE)) receiver_inst (
  //        .clock(clk),
  //        .clock_2x(clk_2x),
  //        .rate(rate),
  //        .frequency(rx_phase[c]),
  //        .out_strobe(rx_data_rdy[c]),
  //        .in_data(adcpipe[c/8]),
  //        .out_data_I(rx_data_i[c]),
  //        .out_data_Q(rx_data_q[c])
  //      );
  //  end
  //end

  for (c = 1; c < NR; c = c + 1) begin: MDC

    if (c == 2) begin
      // Build double mixer
      mix2 #(.CALCTYPE(3)) mix2_i (
        .clk(clk),
        .clk_2x(clk_2x),
        .rst(1'b0),
        .phi0(rx_phase[c]),
        .phi1(rx_phase[c+1]),
        .adc(adcpipe[c/8]), 
        .mixdata0_i(mixdata_i[c]),
        .mixdata0_q(mixdata_q[c]),
        .mixdata1_i(mixdata_i[c+1]),
        .mixdata1_q(mixdata_q[c+1])
      );
    end

    if (c == 4) begin
      // Build double mixer
      // Receiver 3 (zero indexed so fourth RX) is feedback for puresignal
      // Will need to split this later if more than 4 receivers
      mix2 #(.CALCTYPE(4)) mix2_i (
        .clk(clk),
        .clk_2x(clk_2x),
        .rst(1'b0),
        .phi0(rx_phase[c]),
        .phi1(rx_phase[c+1]),
        .adc( (tx_on & pure_signal) ? tx_data_dac : adcpipe[c/8]),
        .mixdata0_i(mixdata_i[c]),
        .mixdata0_q(mixdata_q[c]),
        .mixdata1_i(mixdata_i[c+1]),
        .mixdata1_q(mixdata_q[c+1])
      );
    end

    receiver_nco #(.CICRATE(CICRATE)) receiver_inst (
      .clock(clk),
      .clock_2x(clk_2x),
      .rate(rate),
      .mixdata_I(mixdata_i[c]),
      .mixdata_Q(mixdata_q[c]),
      .out_strobe(rx_data_rdy[c]),
      .out_data_I(rx_data_i[c]),
      .out_data_Q(rx_data_q[c])
    );

  end

end else if (RECEIVER2==1) begin

  assign tx0_phase = tx_phase0;

  for (c = 0; c < NR; c = c + 1) begin: RECV2
    if((c==3 && NR>3) || (c==1 && NR<=3)) begin
        receiver2 receiver_inst (
          .clock(clk),
          .reset(1'b0),
          .sample_rate(rate),
          .frequency(rx_phase[c]),
          .out_strobe(rx_data_rdy[c]),
          .in_data((tx_on & pure_signal) ? { {4{tx_data_dac[11]}},tx_data_dac} : { {4{adcpipe[c/8][11]}},adcpipe[c/8]}), //tx_data was pipelined here once
          .out_data_I(rx_data_i[c]),
          .out_data_Q(rx_data_q[c])
        );
    end else begin
        receiver2 receiver_inst (
          .clock(clk),
          .reset(1'b0),
          .sample_rate(rate),
          .frequency(rx_phase[c]),
          .out_strobe(rx_data_rdy[c]),
          .in_data({ {4{adcpipe[c/8][11]}},adcpipe[c/8]}),
          .out_data_I(rx_data_i[c]),
          .out_data_Q(rx_data_q[c])
        );
    end
  end

end else if (QS1R==1) begin

  assign tx0_phase = tx_phase0;

  for (c = 0; c < NR; c = c + 1) begin: RECV2
    if((c==3 && NR>3) || (c==1 && NR<=3)) begin
        qs1r_receiver receiver_inst (
          .clock(clk),
          .rate(rx_rate),
          .frequency(rx_phase[c]),
          .out_strobe(rx_data_rdy[c]),
          .in_data((tx_on & pure_signal) ? { {4{tx_data_dac[11]}},tx_data_dac} : { {4{adcpipe[c/8][11]}},adcpipe[c/8]}), //tx_data was pipelined here once
          .out_data_I(rx_data_i[c]),
          .out_data_Q(rx_data_q[c])
        );
    end else begin
        qs1r_receiver receiver_inst (
          .clock(clk),
          .rate(rx_rate),
          .frequency(rx_phase[c]),
          .out_strobe(rx_data_rdy[c]),
          .in_data({ {4{adcpipe[c/8][11]}},adcpipe[c/8]}),
          .out_data_I(rx_data_i[c]),
          .out_data_Q(rx_data_q[c])
        );
    end
  end

end else begin

  assign tx0_phase = tx_phase0;

  // Default to receiver type 1
  for (c = 0; c < NR; c = c + 1) begin: MDC
    if((c==3 && NR>3) || (c==1 && NR<=3)) begin
        receiver #(.CICRATE(CICRATE)) receiver_inst (
          .clock(clk),
          .clock_2x(clk_2x),
          .rate(rate),
          .frequency(rx_phase[c]),
          .out_strobe(rx_data_rdy[c]),
          .in_data((tx_on & pure_signal) ? tx_data_dac : adcpipe[c/8]), //tx_data was pipelined here once
          .out_data_I(rx_data_i[c]),
          .out_data_Q(rx_data_q[c])
        );
    end else begin
        receiver #(.CICRATE(CICRATE)) receiver_inst (
          .clock(clk),
          .clock_2x(clk_2x),
          .rate(rate),
          .frequency(rx_phase[c]),
          .out_strobe(rx_data_rdy[c]),
          .in_data(adcpipe[c/8]),
          .out_data_I(rx_data_i[c]),
          .out_data_Q(rx_data_q[c])
        );
    end
  end
end endgenerate


// Send RX data upstream
localparam 
  RXUS_WAIT1  = 2'b00,
  RXUS_I      = 2'b10,
  RXUS_Q      = 2'b11,
  RXUS_WAIT0  = 2'b01;

logic [1:0]   rxus_state = RXUS_WAIT1;
logic [1:0]   rxus_state_next;

always @(posedge clk) begin
  rxus_state <= rxus_state_next;
  chan <= chan_next;
end

always @* begin
  // Sequential
  rxus_state_next = rxus_state;
  chan_next = chan;

  // Combinational
  rx_tdata  = 24'h0;
  rx_tlast  = 1'b0;
  rx_tvalid = 1'b0;
  rx_tuser  = 2'b00;

  case(rxus_state)
    RXUS_WAIT1: begin
      chan_next = 5'h0;
      if (rx_data_rdy[0] & rx_tready) begin
        rxus_state_next = RXUS_I;
      end
    end

    RXUS_I: begin
      rx_tvalid = 1'b1;
      rx_tdata = rx_data_i[chan];
      rx_tuser = 2'b00; // Bit 0 will appear as left mic LSB in VNA mode, add VNA here
      rxus_state_next = RXUS_Q;
    end

    RXUS_Q: begin
      rx_tvalid = 1'b1;
      rx_tdata = rx_data_q[chan];

      if (chan == last_chan) begin
        rx_tlast = 1'b1;
        rxus_state_next = RXUS_WAIT0;
      end else begin
        chan_next = chan + 5'h1;
        rxus_state_next = RXUS_I;
      end
    end

    RXUS_WAIT0: begin
      chan_next = 5'h0;
      if (~rx_data_rdy[0]) begin
        rxus_state_next = RXUS_WAIT1;
      end
    end

  endcase // rxus_state
end



//---------------------------------------------------------
//                 Transmitter code
//---------------------------------------------------------

/*
    The gain distribution of the transmitter code is as follows.
    Since the CIC interpolating filters do not interpolate by 2^n they have an overall loss.

    The overall gain in the interpolating filter is ((RM)^N)/R.  So in this case its 2560^4.
    This is normalised by dividing by ceil(log2(2560^4)).

    In which case the normalized gain would be (2560^4)/(2^46) = .6103515625

    The CORDIC has an overall gain of 1.647.

    Since the CORDIC takes 16 bit I & Q inputs but output needs to be truncated to 14 bits, in order to
    interface to the DAC, the gain is reduced by 1/4 to 0.41175

    We need to be able to drive to DAC to its full range in order to maximise the S/N ratio and
    minimise the amount of PA gain.  We can increase the output of the CORDIC by multiplying it by 4.
    This is simply achieved by setting the CORDIC output width to 16 bits and assigning bits [13:0] to the DAC.

    The gain distripution is now:

    0.61 * 0.41174 * 4 = 1.00467

    This means that the DAC output will wrap if a full range 16 bit I/Q signal is received.
    This can be prevented by reducing the output of the CIC filter.

    If we subtract 1/128 of the CIC output from itself the level becomes

    1 - 1/128 = 0.9921875

    Hence the overall gain is now

    0.61 * 0.9921875 * 0.41174 * 4 = 0.996798


*/

generate if (NT == 0) begin
  // No transmit
  assign tx_tready = 1'b0;
  assign tx_data_dac = 12'h000;
  assign tx_hang = 1'b0;

end else begin

  // At least one transmit
  logic signed [15:0] tx_fir_i;
  logic signed [15:0] tx_fir_q;
  
  logic         req2;
  logic [19:0]  y1_r, y1_i;
  logic [15:0]  y2_r, y2_i;
  
  logic signed [15:0] tx_cordic_i_out;
  logic signed [15:0] tx_cordic_q_out;
  
  logic signed [15:0] tx_i;
  logic signed [15:0] tx_q;
  
  logic signed [15:0] txsum;
  logic signed [15:0] txsumq;
  
  logic [31:0]  tx_phase [0:NT-1];    // The Tx phase calculated from the frequency sent by the PC.
  
  logic [18:0]        tx_cw_level;

// TX 
for (c = 0; c < NT; c = c + 1) begin: TXIFFREQ
  if (c == 0) begin
    assign tx_phase[0] = tx0_phase;
  end else begin
    always @ (posedge clk) begin
      if (cmd_state == CMD_FREQ3) begin
        if (chanp[c/8] == ((c < 7) ? c+2 : c+11)) begin
          tx_phase[c] <= freqcompp[c/8]; 
        end
      end
    end
  end
end

  // latch I&Q data on strobe from FIR
  // No backpressure from FIR for now
  always @ (posedge clk) begin
    if (tx_tready) begin
      tx_fir_i <= tx_tdata[31:16];
      tx_fir_q <= tx_tdata[15:0];
    end
  end

  // Hang TX until fifo drains
  assign tx_hang = tx_tvalid;

  // Interpolate I/Q samples from 48 kHz to the clock frequency
  FirInterp8_1024 fi (clk, req2, tx_tready, tx_fir_i, tx_fir_q, y1_r, y1_i);  // req2 enables an output sample, tx_tready requests next input sample.

  // GBITS reduced to 30
  CicInterpM5 #(.RRRR(RRRR), .IBITS(20), .OBITS(16), .GBITS(GBITS)) in2 ( clk, 1'd1, req2, y1_r, y1_i, y2_r, y2_i);

//---------------------------------------------------------
//    CORDIC NCO
//---------------------------------------------------------

  // Code rotates input at set frequency and produces I & Q
  assign          tx_i = vna ? 16'h4d80 : (tx_cw_key ? {1'b0, tx_cw_level[18:4]} : y2_i);    // select vna mode if active. Set CORDIC for max DAC output
  assign          tx_q = (vna | tx_cw_key) ? 16'h0 : y2_r;                   // taking into account CORDICs gain i.e. 0x7FFF/1.7


  // NOTE:  I and Q inputs reversed to give correct sideband out
  cpl_cordic #(.OUT_WIDTH(16)) cordic_inst (
    .clock(clk), 
    .frequency(tx_phase[0]),
    .in_data_I(tx_i),
    .in_data_Q(tx_q), 
    .out_data_I(tx_cordic_i_out), 
    .out_data_Q(tx_cordic_q_out)
  );

/*
  We can use either the I or Q output from the CORDIC directly to drive the DAC.

    exp(jw) = cos(w) + j sin(w)

  When multplying two complex sinusoids f1 and f2, you get only f1 + f2, no
  difference frequency.

      Z = exp(j*f1) * exp(j*f2) = exp(j*(f1+f2))
        = cos(f1 + f2) + j sin(f1 + f2)
*/

  // the CORDIC output is stable on the negative edge of the clock
if (NT == 1) begin: SINGLETX
  //gain of 4
  assign txsum = (tx_cordic_i_out  >>> 2); // + {15'h0000, tx_cordic_i_out[1]};
  assign txsumq = (tx_cordic_q_out  >>> 2);

end else begin: DUALTX
  logic signed [15:0] tx_cordic_tx2_i_out;
  logic signed [15:0] tx_cordic_tx2_q_out;

  cpl_cordic #(.OUT_WIDTH(16)) cordic_tx2_inst (
    .clock(clk), 
    .frequency(tx_phase[1]), 
    .in_data_I(tx_i),
    .in_data_Q(tx_q), 
    .out_data_I(tx_cordic_tx2_i_out), 
    .out_data_Q(tx_cordic_tx2_q_out)
  );

  assign txsum = (tx_cordic_i_out + tx_cordic_tx2_i_out) >>> 3;
  assign txsumq = (tx_cordic_q_out + tx_cordic_tx2_q_out) >>> 3;
end

// LFSR for dither
//reg [15:0] lfsr = 16'h0001;
//always @ (negedge clk or negedge extreset)
//    if (~extreset) lfsr <= 16'h0001;
//    else lfsr <= {lfsr[0],lfsr[15],lfsr[14] ^ lfsr[0], lfsr[13] ^ lfsr[0], lfsr[12], lfsr[11] ^ lfsr[0], lfsr[10:1]};


//generate

case (LRDATA)
  0: begin // Left/Right downstream (PC->Card) audio data not used
    assign lr_tready = 1'b0;
    assign tx_envelope_pwm_out = 1'b0;
    assign tx_envelope_pwm_out_inv = 1'b0;

   always @ (posedge clk)
      tx_data_dac <= txsum[11:0]; // + {10'h0,lfsr[2:1]};
  end
  1: begin: PD1 // TX predistortion
    // apply amplitude & phase linearity correction

    /*
    Lookup tables
    These are sent continuously in the unused audio out packets sent to the radio.
    The left channel is an index into the table and the right channel has the value.
    Indexes 0-4097 go into DACLUTI and 4096-8191 go to DACLUTQ.
    The values are sent as signed 16bit numbers but the value is never bigger than 13 bits.

    DACLUTI has the out of phase distortion and DACLUTQ has the in phase distortion.

    The tables can represent arbitary functions, for now my console software just uses a power series

    DACLUTI[x] = 0x + gain2*sin(phase2)*x^2 +  gain3*sin(phase3)*x^3 + gain4*sin(phase4)*x^4 + gain5*sin(phase5)*x^5
    DACLUTQ[x] = 1x + gain2*cos(phase2)*x^2 +  gain3*cos(phase3)*x^3 + gain4*cos(phase4)*x^4 + gain5*cos(phase5)*x^5

    The table indexes are signed so the tables are in 2's complement order ie. 0,1,2...2047,-2048,-2047...-1.

    The table values are scaled to keep the output of DACLUTI[I]-DACLUTI[Q]+DACLUTQ[(I+Q)/root2] to fit in 12 bits,
    the intermediate values and table values can be larger.
    Zero input produces centre of the dac range output(signed 0) so with some settings one end or the other of the dac range is not used.

    The predistortion is turned on and off by a new command and control packet this follows the last of the 32 receiver frequencies.
    There is a sub index so this can be used for many other things.
    control cc packet

    c0 101011x
    c1 sub index 0 for predistortion control-
    c2 mode 0 off 1 on, (higher numbers can be used to experiment without so much fpga recompilation).

    */

    // lookup tables for dac phase and amplitude linearity correction
    logic signed [12:0] DACLUTI[4096];
    logic signed [12:0] DACLUTQ[4096];

    logic signed [15:0] distorted_dac;

    logic signed [15:0] iplusq;
    logic signed [15:0] iplusq_over_root2;

    logic signed [15:0] txsumr;
    logic signed [15:0] txsumqr;
    logic signed [15:0] iplusqr;

    assign tx_envelope_pwm_out = 1'b0;
    assign tx_envelope_pwm_out_inv = 1'b0;
    //FSM to write DACLUTI and DACLUTQ
    assign lr_tready = 1'b1; // Always ready
    always @(posedge clk) begin
      if (lr_tvalid) begin
        if (lr_tdata[12+16]) begin // Always write??
          DACLUTQ[lr_tdata[(11+16):16]] <= lr_tdata[12:0];
        end else begin
          DACLUTI[lr_tdata[(11+16):16]] <= lr_tdata[12:0];
        end
      end
    end

    assign iplusq = txsum+txsumq;

    always @ (posedge clk) begin
      txsumr<=txsum;
      txsumqr<=txsumq;
      iplusqr<=iplusq;
    end

    //approximation to dividing by root 2 to reduce lut size, the error can be corrected in the lut data
    assign iplusq_over_root2 = iplusqr+(iplusqr>>>2)+(iplusqr>>>3)+(iplusqr>>>5);

    logic signed [15:0] txsumr2;
    logic signed [15:0] txsumqr2;
    logic signed [15:0] iplusq_over_root2r;

    always @ (posedge clk) begin
      txsumr2<=txsumr;
      txsumqr2<=txsumqr;
      iplusq_over_root2r<=iplusq_over_root2;
    end
  
    assign distorted_dac = DACLUTI[txsumr2[11:0]]-DACLUTI[txsumqr2[11:0]]+DACLUTQ[iplusq_over_root2r[12:1]];

    always @ (posedge clk) begin
      case( tx_predistort[1:0] )
        0: tx_data_dac <= txsum[11:0];
        1: tx_data_dac <= distorted_dac[11:0];
        //other modes
        default: tx_data_dac <= txsum[11:0];
      endcase
    end
  end

  2: begin: EER1 // TX envelope PWM generation for ET/EER
    //   cannot be used with TX predistortion as it uses the same audio lrdata
    always @ (posedge clk)
      tx_data_dac <= txsum[11:0]; // + {10'h0,lfsr[2:1]};

    reg signed [15:0]tx_EER_fir_i;
    reg signed [15:0]tx_EER_fir_q;

    // latch I&Q data on strobe from FIR
    // FIXME: no backpressure from FIR for now
    always @ (posedge clk) begin
      if (lr_tready & lr_tvalid) begin
        tx_EER_fir_i = lr_tdata[31:16];
        tx_EER_fir_q = lr_tdata[15:0];
      end
    end

    // Interpolate by 5 FIR for Envelope generation - straight FIR, no CIC compensation.
    wire [19:0] I_EER, Q_EER;
    wire EER_req;

    // Note: Coefficients are scaled by 0.85 so that unity I&Q input give unity amplitude envelope signal.
    FirInterp5_1025_EER fiEER (clk, EER_req, lr_tready, tx_EER_fir_i, tx_EER_fir_q, I_EER, Q_EER);   // EER_req enables an output sample, lr_tready requests next input sample.

    assign EER_req = (ramp == 10'd0 | ramp == 10'd1 | ramp == 10'd2 | ramp == 10'd3); // need an enable wide enough to be sampled by clk to enable EER FIR data out

    // calculate the envelope of the SSB signal using SQRT(I^2 + Q^2)
    wire [31:0] Isquare;
    wire [31:0] Qsquare;
    wire [32:0] sum;                // 32 bits + 32 bits requires 33 bit accumulator.
    wire [15:0] envelope;

    // use I&Q x 5 from EER iFIR output
    //square square_I (.clock(clk), .dataa(I_EER[19:4]), .result(Isquare));
    //square square_Q (.clock(clk), .dataa(Q_EER[19:4]), .result(Qsquare));
    square square_I (.dataa(I_EER[19:4]), .result(Isquare));
    square square_Q (.dataa(Q_EER[19:4]), .result(Qsquare));
    assign sum = Isquare + Qsquare;
    sqroot sqroot_inst (.clk(clk), .radical(sum[32:1]), .q(envelope));

    //--------------------------------------------------------
    // Generate 240 kHz PWM signal from Envelope
    //--------------------------------------------------------
    // Since the envelope will always have positive values we can ignore the sign bit.
    // Also use the top 10 bits since this is what the ramp uses.
    // clock clk_envelope runs at 245.76 MHz (1024 x 240 kHz).
    reg  [9:0] ramp = 0;
    reg PWM = 0;

    counter counter_inst (.clock(clk_envelope), .q(ramp));  // count to 1024 [10:0] = 240kHz, 640 [9:0] for 384kHz

    wire [14:0] envelope_scaled = envelope + (envelope >>> 2) + (envelope >>> 3);  // Multiply by 1.375, keep all bits for proper rounding
    wire [9:0] envelope_level = envelope_scaled[14:5];

    always @ (posedge clk_envelope)
    begin
      if ((ramp < PWM_min | envelope_level > ramp) && ramp < PWM_max)
        PWM <= 1'b1;
      else
        PWM <= 1'b0;
    end

    // FIXME: disable EER when VNA is enabled? is CW handled correctly?
    assign tx_envelope_pwm_out = (tx_on & pa_mode) ? PWM : 1'b0;  // PWM only when TX and EER mode are selected
    assign tx_envelope_pwm_out_inv = ~tx_envelope_pwm_out;

  end
endcase

//endgenerate

//----------------------------------------

localparam MAX_CWLEVEL = 19'h4d800; //(16'h4d80 << 4);

if (CWSHAPE == 1) begin: CW1

  logic [1:0]         cwstate;

  // 4 ms rise and fall, not shaped, but like HiQSDR
  // MAX CWLEVEL is picked to be 8*max cordic level for transmit
  // ADJUST if cordic max changes...  
  localparam  cwrx = 2'b00, 
              cw_keydowndown = 2'b01, 
              cw_keydownup = 2'b11;

  // CW state machine
  always @(posedge clk) begin 
    case (cwstate)
      cwrx: begin
        tx_cw_level <= 1'b0;
        if (cw_keydown) cwstate <= cw_keydowndown;
        else cwstate <= cwrx;
      end
  
      cw_keydowndown: begin
        if (tx_cw_level != MAX_CWLEVEL) tx_cw_level <= tx_cw_level + 1'b1;
        if (cw_keydown) cwstate <= cw_keydowndown;
        else cwstate <= cw_keydownup;
      end
  
      cw_keydownup: begin
        if (tx_cw_level == 0) cwstate <= cwrx;
        else begin
          cwstate <= cw_keydownup;
          tx_cw_level <= tx_cw_level - 1'b1;
        end
      end
    endcase
  end

  assign tx_cw_key = cwstate != cwrx;

end else begin

  assign tx_cw_key = cw_keydown;
  assign tx_cw_level = MAX_CWLEVEL;
end

end endgenerate

endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------

// 2015 Jan 31 - udated for Hermes-Lite 12bit Steve Haynal KF7O

module cic( clock, in_strobe, out_strobe, in_data, out_data );

//design parameters
parameter STAGES = 3;
parameter DECIMATION = 10;  
parameter IN_WIDTH = 18;

//computed parameters
//ACC_WIDTH = IN_WIDTH + Ceil(STAGES * Log2(DECIMATION))
//OUT_WIDTH = IN_WIDTH + Ceil(Log2(DECIMATION) / 2)
parameter ACC_WIDTH = IN_WIDTH  + 10;
parameter OUT_WIDTH = IN_WIDTH  + 2; // Hermes only uses ADC input width plus 2 here

input clock;
input in_strobe;
output reg out_strobe;
input signed [IN_WIDTH-1:0] in_data;
output signed [OUT_WIDTH-1:0] out_data;

//------------------------------------------------------------------------------
//                               control
//------------------------------------------------------------------------------
reg [15:0] sample_no = 0;

always @(posedge clock)
  if (in_strobe)
    begin
    if (sample_no == (DECIMATION-1))
      begin
      sample_no <= 0;
      out_strobe <= 1;
      end
    else
      begin
      sample_no <= sample_no + 8'd1;
      out_strobe <= 0;
      end
    end

  else
    out_strobe <= 0;






//------------------------------------------------------------------------------
//                                stages
//------------------------------------------------------------------------------
wire signed [ACC_WIDTH-1:0] integrator_data [0:STAGES];
wire signed [ACC_WIDTH-1:0] comb_data [0:STAGES];


assign integrator_data[0] = in_data;
assign comb_data[0] = integrator_data[STAGES];


genvar i;
generate
  for (i=0; i<STAGES; i=i+1)
    begin : cic_stages

    cic_integrator #(ACC_WIDTH) cic_integrator_inst(
      .clock(clock),
      .strobe(in_strobe),
      .in_data(integrator_data[i]),
      .out_data(integrator_data[i+1])
      );


    cic_comb #(ACC_WIDTH) cic_comb_inst(
      .clock(clock),
      .strobe(out_strobe),
      .in_data(comb_data[i]),
      .out_data(comb_data[i+1])
      );
    end
endgenerate







//------------------------------------------------------------------------------
//                            output rounding
//------------------------------------------------------------------------------
assign out_data = comb_data[STAGES][ACC_WIDTH-1:ACC_WIDTH-OUT_WIDTH] +
  {{(OUT_WIDTH-1){1'b0}}, comb_data[STAGES][ACC_WIDTH-OUT_WIDTH-1]};

//assign out_data = comb_data[STAGES][36:19] + comb_data[STAGES][18];


endmodule

// megafunction wizard: %ROM: 1-PORT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsyncram 

// ============================================================
// File Name: firromH.v
// Megafunction Name(s):
// 			altsyncram
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!	!!!!!!!!EDITED
//
// 9.0 Build 235 06/17/2009 SP 2 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2009 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module recv2_firromH (
	address,
	clock,
	q);

	parameter MifFile = "missing_file.mif";

	input	[6:0]  address;
	input	  clock;
	output	[17:0]  q;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri1	  clock;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [17:0] sub_wire0;
	wire [17:0] q = sub_wire0[17:0];
/*
	altsyncram	altsyncram_component (
				.clock0 (clock),
				.address_a (address),
				.q_a (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.address_b (1'b1),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_a ({18{1'b1}}),
				.data_b (1'b1),
				.eccstatus (),
				.q_b (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_a (1'b0),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_a = "NONE",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.init_file = MifFile,
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 128,
		altsyncram_component.operation_mode = "ROM",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_reg_a = "CLOCK0",
		altsyncram_component.widthad_a = 7,
		altsyncram_component.width_a = 18,
		altsyncram_component.width_byteena_a = 1;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ADDRESSSTALL_A NUMERIC "0"
// Retrieval info: PRIVATE: AclrAddr NUMERIC "0"
// Retrieval info: PRIVATE: AclrByte NUMERIC "0"
// Retrieval info: PRIVATE: AclrOutput NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_SIZE NUMERIC "9"
// Retrieval info: PRIVATE: BlankMemory NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: Clken NUMERIC "0"
// Retrieval info: PRIVATE: IMPLEMENT_IN_LES NUMERIC "0"
// Retrieval info: PRIVATE: INIT_FILE_LAYOUT STRING "PORT_A"
// Retrieval info: PRIVATE: INIT_TO_SIM_X NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "0"
// Retrieval info: PRIVATE: JTAG_ID STRING "NONE"
// Retrieval info: PRIVATE: MAXIMUM_DEPTH NUMERIC "0"
// Retrieval info: PRIVATE: MIFfilename STRING "xx.mif"
// Retrieval info: PRIVATE: NUMWORDS_A NUMERIC "128"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "0"
// Retrieval info: PRIVATE: RegAddr NUMERIC "1"
// Retrieval info: PRIVATE: RegOutput NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: SingleClock NUMERIC "1"
// Retrieval info: PRIVATE: UseDQRAM NUMERIC "0"
// Retrieval info: PRIVATE: WidthAddr NUMERIC "7"
// Retrieval info: PRIVATE: WidthData NUMERIC "18"
// Retrieval info: PRIVATE: rden NUMERIC "0"
// Retrieval info: CONSTANT: ADDRESS_ACLR_A STRING "NONE"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_OUTPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: INIT_FILE STRING "xx.mif"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: LPM_HINT STRING "ENABLE_RUNTIME_MOD=NO"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altsyncram"
// Retrieval info: CONSTANT: NUMWORDS_A NUMERIC "128"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "ROM"
// Retrieval info: CONSTANT: OUTDATA_ACLR_A STRING "NONE"
// Retrieval info: CONSTANT: OUTDATA_REG_A STRING "CLOCK0"
// Retrieval info: CONSTANT: WIDTHAD_A NUMERIC "7"
// Retrieval info: CONSTANT: WIDTH_A NUMERIC "18"
// Retrieval info: CONSTANT: WIDTH_BYTEENA_A NUMERIC "1"
// Retrieval info: USED_PORT: address 0 0 7 0 INPUT NODEFVAL address[6..0]
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT VCC clock
// Retrieval info: USED_PORT: q 0 0 18 0 OUTPUT NODEFVAL q[17..0]
// Retrieval info: CONNECT: @address_a 0 0 7 0 address 0 0 7 0
// Retrieval info: CONNECT: q 0 0 18 0 @q_a 0 0 18 0
// Retrieval info: CONNECT: @clock0 0 0 0 0 clock 0 0 0 0
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH_bb.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH_waveforms.html FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firromH_wave*.jpg FALSE
// Retrieval info: LIB_FILE: altera_mf
// megafunction wizard: %RAM: 2-PORT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsyncram 

// ============================================================
// File Name: firram48.v
// Megafunction Name(s):
// 			altsyncram
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 13.1.0 Build 162 10/23/2013 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2013 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module recv2_firram48 (
	clock,
	data,
	rdaddress,
	wraddress,
	wren,
	q);

	input	  clock;
	input	[47:0]  data;
	input	[6:0]  rdaddress;
	input	[6:0]  wraddress;
	input	  wren;
	output	[47:0]  q;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri1	  clock;
	tri0	  wren;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [47:0] sub_wire0;
	wire [47:0] q = sub_wire0[47:0];
/*
	altsyncram	altsyncram_component (
				.address_a (wraddress),
				.clock0 (clock),
				.data_a (data),
				.wren_a (wren),
				.address_b (rdaddress),
				.q_b (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({48{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 128,
		altsyncram_component.numwords_b = 128,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "CLOCK0",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = 7,
		altsyncram_component.widthad_b = 7,
		altsyncram_component.width_a = 48,
		altsyncram_component.width_b = 48,
		altsyncram_component.width_byteena_a = 1;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ADDRESSSTALL_A NUMERIC "0"
// Retrieval info: PRIVATE: ADDRESSSTALL_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_SIZE NUMERIC "8"
// Retrieval info: PRIVATE: BlankMemory NUMERIC "1"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLRdata NUMERIC "0"
// Retrieval info: PRIVATE: CLRq NUMERIC "0"
// Retrieval info: PRIVATE: CLRrdaddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRrren NUMERIC "0"
// Retrieval info: PRIVATE: CLRwraddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRwren NUMERIC "0"
// Retrieval info: PRIVATE: Clock NUMERIC "0"
// Retrieval info: PRIVATE: Clock_A NUMERIC "0"
// Retrieval info: PRIVATE: Clock_B NUMERIC "0"
// Retrieval info: PRIVATE: IMPLEMENT_IN_LES NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: INIT_FILE_LAYOUT STRING "PORT_B"
// Retrieval info: PRIVATE: INIT_TO_SIM_X NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "0"
// Retrieval info: PRIVATE: JTAG_ID STRING "NONE"
// Retrieval info: PRIVATE: MAXIMUM_DEPTH NUMERIC "0"
// Retrieval info: PRIVATE: MEMSIZE NUMERIC "6144"
// Retrieval info: PRIVATE: MEM_IN_BITS NUMERIC "0"
// Retrieval info: PRIVATE: MIFfilename STRING ""
// Retrieval info: PRIVATE: OPERATION_MODE NUMERIC "2"
// Retrieval info: PRIVATE: OUTDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: OUTDATA_REG_B NUMERIC "1"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "0"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_MIXED_PORTS NUMERIC "2"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_A NUMERIC "3"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_B NUMERIC "3"
// Retrieval info: PRIVATE: REGdata NUMERIC "1"
// Retrieval info: PRIVATE: REGq NUMERIC "1"
// Retrieval info: PRIVATE: REGrdaddress NUMERIC "1"
// Retrieval info: PRIVATE: REGrren NUMERIC "1"
// Retrieval info: PRIVATE: REGwraddress NUMERIC "1"
// Retrieval info: PRIVATE: REGwren NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: USE_DIFF_CLKEN NUMERIC "0"
// Retrieval info: PRIVATE: UseDPRAM NUMERIC "1"
// Retrieval info: PRIVATE: VarWidth NUMERIC "0"
// Retrieval info: PRIVATE: WIDTH_READ_A NUMERIC "48"
// Retrieval info: PRIVATE: WIDTH_READ_B NUMERIC "48"
// Retrieval info: PRIVATE: WIDTH_WRITE_A NUMERIC "48"
// Retrieval info: PRIVATE: WIDTH_WRITE_B NUMERIC "48"
// Retrieval info: PRIVATE: WRADDR_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: WRADDR_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: WRCTRL_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: enable NUMERIC "0"
// Retrieval info: PRIVATE: rden NUMERIC "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: ADDRESS_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: ADDRESS_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_OUTPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altsyncram"
// Retrieval info: CONSTANT: NUMWORDS_A NUMERIC "128"
// Retrieval info: CONSTANT: NUMWORDS_B NUMERIC "128"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "DUAL_PORT"
// Retrieval info: CONSTANT: OUTDATA_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: OUTDATA_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: POWER_UP_UNINITIALIZED STRING "FALSE"
// Retrieval info: CONSTANT: READ_DURING_WRITE_MODE_MIXED_PORTS STRING "DONT_CARE"
// Retrieval info: CONSTANT: WIDTHAD_A NUMERIC "7"
// Retrieval info: CONSTANT: WIDTHAD_B NUMERIC "7"
// Retrieval info: CONSTANT: WIDTH_A NUMERIC "48"
// Retrieval info: CONSTANT: WIDTH_B NUMERIC "48"
// Retrieval info: CONSTANT: WIDTH_BYTEENA_A NUMERIC "1"
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT VCC "clock"
// Retrieval info: USED_PORT: data 0 0 48 0 INPUT NODEFVAL "data[47..0]"
// Retrieval info: USED_PORT: q 0 0 48 0 OUTPUT NODEFVAL "q[47..0]"
// Retrieval info: USED_PORT: rdaddress 0 0 7 0 INPUT NODEFVAL "rdaddress[6..0]"
// Retrieval info: USED_PORT: wraddress 0 0 7 0 INPUT NODEFVAL "wraddress[6..0]"
// Retrieval info: USED_PORT: wren 0 0 0 0 INPUT GND "wren"
// Retrieval info: CONNECT: @address_a 0 0 7 0 wraddress 0 0 7 0
// Retrieval info: CONNECT: @address_b 0 0 7 0 rdaddress 0 0 7 0
// Retrieval info: CONNECT: @clock0 0 0 0 0 clock 0 0 0 0
// Retrieval info: CONNECT: @data_a 0 0 48 0 data 0 0 48 0
// Retrieval info: CONNECT: @wren_a 0 0 0 0 wren 0 0 0 0
// Retrieval info: CONNECT: q 0 0 48 0 @q_b 0 0 48 0
// Retrieval info: GEN_FILE: TYPE_NORMAL firram48.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram48.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram48.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram48.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram48_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram48_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
//
// cic - A Cascaded Integrator-Comb filter
//
// Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
// Copyright (c) 2013 Phil Harman, VK6PH
// Copyright (c) 2015 Jeremy McDermond, NH6Z
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Library General Public
// License as published by the Free Software Foundation; either
// version 2 of the License, or (at your option) any later version.
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Library General Public License for more details.
// You should have received a copy of the GNU Library General Public
// License along with this library; if not, write to the
// Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
// Boston, MA  02110-1301, USA.


// 2013 Jan 26	- Modified to accept decimation values from 1-40. VK6APH 

module recv2_cic(reset, decimation, clock, in_strobe,  out_strobe, in_data, out_data );

  //design parameters
  parameter STAGES = 5; //  Sections of both Comb and Integrate
  parameter MIN_DECIMATION = 2;  // If MIN = MAX, we are single-rate filter
  parameter MAX_DECIMATION = 40;
  parameter IN_WIDTH = 18;
  parameter OUT_WIDTH = 18;

  // derived parameters
  parameter ACC_WIDTH = IN_WIDTH + (STAGES * $clog2(MAX_DECIMATION));
  
  input [$clog2(MAX_DECIMATION):0] decimation; 
  
  input reset;
  input clock;
  input in_strobe;
  output reg out_strobe;

  input signed [IN_WIDTH-1:0] in_data;
  output signed [OUT_WIDTH-1:0] out_data;


//------------------------------------------------------------------------------
//                               control
//------------------------------------------------------------------------------
reg [$clog2(MAX_DECIMATION)-1:0] sample_no = 0;

generate
if(MIN_DECIMATION == MAX_DECIMATION)
	always @(posedge clock)
		if (in_strobe) 
			if (sample_no == (MAX_DECIMATION - 1'd1)) begin
				sample_no <= 0;
				out_strobe <= 1;
			end else begin
				sample_no <= sample_no + 1'd1;
     				out_strobe <= 0;
			end
		else
			out_strobe <= 0;
else
	always @(posedge clock)
		if (in_strobe) 
			if (sample_no == (decimation - 1'd1)) begin
				sample_no <= 0;
				out_strobe <= 1;
			end else begin
				sample_no <= sample_no + 1'd1;
     				out_strobe <= 0;
			end
		else
			out_strobe <= 0;
endgenerate

//------------------------------------------------------------------------------
//                                stages
//------------------------------------------------------------------------------
reg signed [ACC_WIDTH-1:0] integrator_data [1:STAGES] = '{default: '0};
reg signed [ACC_WIDTH-1:0] comb_data [1:STAGES] = '{default: '0};
reg signed [ACC_WIDTH-1:0] comb_last [0:STAGES] = '{default: '0};

always @(posedge clock) begin
	integer index;

	//  Integrators
	if(in_strobe) begin
		integrator_data[1] <= integrator_data[1] + in_data;
		for(index = 1; index < STAGES; index = index + 1) begin
			integrator_data[index + 1] <= integrator_data[index] + integrator_data[index+1];
		end
	end

	// Combs
	if(out_strobe) begin
		comb_data[1] <= integrator_data[STAGES] - comb_last[0];
		comb_last[0] <= integrator_data[STAGES];
		for(index = 1; index < STAGES; index = index + 1) begin
			comb_data[index + 1] <= comb_data[index] - comb_last[index];
			comb_last[index] <= comb_data[index]; 
		end
	end
end

//------------------------------------------------------------------------------
//                            output rounding
//------------------------------------------------------------------------------

genvar i;
generate
	if(MIN_DECIMATION == MAX_DECIMATION) begin
		assign out_data = comb_data[STAGES][ACC_WIDTH - 1 -: OUT_WIDTH] + comb_data[STAGES][ACC_WIDTH - OUT_WIDTH - 1];
	end else begin
		wire [$clog2(ACC_WIDTH)-1:0] msb [MAX_DECIMATION:MIN_DECIMATION];
		for(i = MIN_DECIMATION; i <= MAX_DECIMATION; i = i + 1) begin: round_position
			assign msb[i] = IN_WIDTH + ($clog2(i) * STAGES) - 1 ;
		end

		assign out_data = comb_data[STAGES][msb[decimation] -: OUT_WIDTH] + comb_data[STAGES][msb[decimation] - OUT_WIDTH];
	end
endgenerate

endmodule

/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
//           Copyright (c) 2013,2015 Phil Harman, VK6(A)PH 
//------------------------------------------------------------------------------

// 2013 Jan 26 - varcic now accepts 2...40 as decimation and CFIR
//               replaced with Polyphase FIR - VK6APH
// 2015 Apr 20 - cic now by Jeremy McDermond, NH6Z
//                  - single polyphase FIR Filter
//      Jul 25 - add reset to CORDIC, CIC and FIR for Sync operation



module receiver2(
  input reset,
  input clock,                  //122.88 MHz
  input [31:0] frequency,
  input [5:0] sample_rate,
  output out_strobe,
  input signed [15:0] in_data,
  output signed [23:0] out_data_I,
  output signed [23:0] out_data_Q
  );

wire signed [21:0] cordic_outdata_I;
wire signed [21:0] cordic_outdata_Q;
reg [5:0] rate0, rate1;

//------------------------------------------------------------------------------
//                               cordic
//------------------------------------------------------------------------------

recv2_cordic recv2_cordic_inst(
  .reset(reset),
  .clock(clock),
  .in_data(in_data),             //16 bit 
  .frequency(frequency),         //32 bit
  .out_data_I(cordic_outdata_I), //22 bit
  .out_data_Q(cordic_outdata_Q)
  );

  
 
// Select CIC decimation rates based on sample_rate
// Sample rate encoded as per receiver1

    always @ (sample_rate)              
    begin 
        case (sample_rate)  
          6'd40: begin rate0 <= 6'd32;  rate1 <= 6'd25; end  //48K
          6'd20: begin rate0 <= 6'd16;  rate1 <= 6'd25; end  //96K       
          6'd10: begin rate0 <= 6'd8;   rate1 <= 6'd25; end  //192K  
          6'd5: begin rate0 <=  6'd4;   rate1 <= 6'd25; end //384K      
          default: begin rate0 <= 6'd32; rate1 <= 6'd25; end
        endcase
    end 

  
// Receive CIC filters followed by FIR filter
wire decimA_avail, decimB_avail;
wire signed [17:0] decimA_real;
wire signed [17:0] decimA_imag;
wire signed [23:0] decimB_real, decimB_imag;

wire cic_outstrobe_2;
wire signed [23:0] cic_outdata_I2;
wire signed [23:0] cic_outdata_Q2;

//I channel
recv2_cic #(.STAGES(3), .MIN_DECIMATION(4), .MAX_DECIMATION(32), .IN_WIDTH(22), .OUT_WIDTH(18))
 cic_inst_I2(.reset(1'b0),
                 .decimation(rate0),
                 .clock(clock), 
                 .in_strobe(1'b1),
                 .out_strobe(decimA_avail),
                 .in_data(cordic_outdata_I),
                 .out_data(decimA_real)
                 );
                 
//Q channel
recv2_cic #(.STAGES(3), .MIN_DECIMATION(4), .MAX_DECIMATION(32), .IN_WIDTH(22), .OUT_WIDTH(18)) 
 cic_inst_Q2(.reset(1'b0),
                 .decimation(rate0),
                 .clock(clock), 
                 .in_strobe(1'b1),
                 .out_strobe(),
                 .in_data(cordic_outdata_Q),
                 .out_data(decimA_imag)
                 );         
            

wire cic_outstrobe_1;
wire signed [22:0] cic_outdata_I1;
wire signed [22:0] cic_outdata_Q1;


recv2_cic #(.STAGES(11), .MIN_DECIMATION(8), .MAX_DECIMATION(32), .IN_WIDTH(18), .OUT_WIDTH(24)) 
 varcic_inst_I1(.reset(1'b0),
                 .decimation(rate1),
                 .clock(clock), 
                 .in_strobe(decimA_avail),
                 .out_strobe(decimB_avail),
                 .in_data(decimA_real),
                 .out_data(decimB_real)
                 );
                 

//Q channel
recv2_cic #(.STAGES(11), .MIN_DECIMATION(8), .MAX_DECIMATION(32), .IN_WIDTH(18), .OUT_WIDTH(24)) 
 varcic_inst_Q1(.reset(1'b0),
                 .decimation(rate1),
                 .clock(clock), 
                 .in_strobe(decimA_avail),
                 .out_strobe(),
                 .in_data(decimA_imag),
                 .out_data(decimB_imag)
                 );
                 
        
// Polyphase decimate by 2 FIR Filter
recv2_firX2R2 fir3 (1'b0, clock, decimB_avail, decimB_real, decimB_imag, out_strobe, out_data_I, out_data_Q);


endmodule
/*
  HPSDR - High Performance Software Defined Radio

  Hermes code. 

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 Polyphase decimating filter

 Based on firX8R8 by James Ahlstrom, N2ADR,  (C) 2011
 Modified for use with HPSDR and DC spur removed by Phil Harman, VK6(A)PH, (C) 2013, 2016


 This is a decimate by 2 dual bank Polyphase FIR filter. 

 The coefficients are initially generated for a basic CIC compensating FIR designed for  256 TAPs, 0.01dB ripple, 110dB ultimate 
 rejection FIR. The FIR compensates for the passband droop of the preceding CIC filter. The coefficients were 
 calculated using Matlab (see filter_2.m).
 
 The Matlab coefficients are fractional so are converted to 18 bit integers by scalling the largest coefficient
 to  2^17 - 1. 
 
 Note that when designing the basic FIR that it decimates by 2 hence the output bandwith will be 1/4 the design
 sampling rate and the output will be 50% of the input levels. 
 
 The coefficients are then split into two files, one containing the even  coefficients (0 - 254) and the other
 the odd (1 - 255).  Conventionally these would then be used as the coeffients for the two FIRs that comprise the polyhase FIR.
 
 However, doing so would restrict the maximum sampling rate at the FIR output to 768ksps.  In order to double this, each set of
 coefficients is again split into two files. The even coefficients are then (0 - 126) and (128 - 254) and the odd (1 - 127) and 
 (129 - 255).  

 The coefficents are then converted to *.mif files so they can be loaded into a ROM. The files are 
 
 (0 - 126) 		= coefFa.mif
 (128 - 254) 	= coefFb.mif
 (1 - 127)     = coefEa.mif
 (129 - 255)	= coefEb.mif

 The generation of the mif files is done via an Excel spreadsheet (see Coeffficients.xlsx) 
 
 Hence each ROM needs to hold 18 x 64 coefficients.  However, due to the need to pipline the ROM addresses in practice a 
 18 x 128 ROM is used with the values > 64 equal to zero.  
 
 Note that the mif files are passed to each  ROM as a parameter.  This not supported by the Quartus ROM Megafunction the output
 of which needed to be  edited (against Altera's recommendations!) in order to be used.

 The speed increase is obtained by operating the Ea/Fa and Eb/Fb FIRs in paralled.  Hence a new input sample is fed to both a and b FIRs. 
 
 In order that the input data is multipled by the coefficients in the correct sequence the sample fed to Eb and Fb is sent
 to a RAM address that is equal to the Fa and Ea address plus the mumber of taps.  
 
 A (24+24) x 128 RAM is required due to the intial address offset of the Eb and Fb FIRs. 

   
   Each FIR works as follows:
   
    RAM address     0     1     2     3     4     5     6     7   etc
						-----------------------------------------------
						|     |     |     |     |     |     |     |     
						|	   |     |     |     |     |     |     |     
						------------------------------------------------
				
    Coeff address    0     1     2     3     4     5     6     7   etc
						-----------------------------------------------
						|     |     |     |     |     |     |     |     
						| h0  |  h1 | h2  | h3  | h4  | h5  | h6  | h7    
						------------------------------------------------	
				  
				  
    At reset the ROM and RAM addresses are set to 0 (64 in the case of the Eb/Fb RAM bank)
    The first sample is written to RAM address 0 (64). This cause the sample to be multiplied
    by h0 and accumulated. The RAM address is then decremented and the ROM address incremented.
    The sample in the new RAM address is multiplied by the coefficient from the new ROM address.  
    This process is repeated TAPS times. The code then waits for the next sample to arrive which 
    is written to RAM address + 1. This sample is then multiplied by h0 etc and the process is
    continued TAPS times.		
*/


module recv2_firX2R2 (
   input reset,	
	input clock,
	input x_avail,									// new sample is available
	input signed [INBITS-1:0] x_real,		// x is the sample input
	input signed [INBITS-1:0] x_imag,
	output y_avail,								// new output is available
	output wire signed [OBITS-1:0] y_real,	// y is the filtered output
	output wire signed [OBITS-1:0] y_imag);
	
	localparam ADDRBITS	= 7;					// Address bits for 48 x 128 RAM blocks
   localparam INBITS    = 24;					// width of I and Q input samples	
	
	parameter
		TAPS 			= 64,						   // Number of coefficients per FIR - total is 64 * 4 = 256
   	ABITS			= 24,							// adder bits
		OBITS			= 24;							// output bits
	
	reg [4:0] wstate;								// state machine for write samples
	
	reg  [ADDRBITS-1:0] waddr, raddr;		// write sample memory address
	wire weA, weB, weC, weD;
	reg  signed [ABITS-1:0] Racc, Iacc;
	wire signed [ABITS-1:0] RaccAa, RaccBa, RaccAb, RaccBb;
	wire signed [ABITS-1:0] IaccAa, IaccBa, IaccAb, IaccBb;	
	
// Output is the result of adding 2 by 24 bit results so Racc and Iacc need to be 
// 24 + log2(2) = 24 + 1 = 25 bits wide to prevent DC spur.
// However, since we decimate by 2 the output will be 1/2 the input. Hence we 
// use 24 bits for the Accumulators. 

	assign y_real = Racc[ABITS-1:0];  
	assign y_imag = Iacc[ABITS-1:0];
	
	initial
	begin
		wstate = 0;
		waddr = 0;
		raddr = 0;
	end
	
	always @(posedge clock)
	begin
		if (reset) 
			begin 
				wstate <= 0;
				waddr <= 0;
				raddr <= 0;
				Racc <= 0;
				Iacc <= 0;		
			end 
		else
		begin 
			if (wstate == 2) wstate <= wstate + 1'd1;	// used to set y_avail
			if (wstate == 3) begin
				wstate <= 0;									// reset state machine and increment RAM write address
				waddr <= waddr + 1'd1;
				raddr <= waddr;
			end
			if (x_avail)
			begin
				wstate <= wstate + 1'd1;
				case (wstate)
					0:	begin											// wait for the first x input
							Racc <= RaccAa + RaccAb;			// add accumulators from 'a' and 'b' FIRs
							Iacc <= IaccAa + IaccAb;
						end
					1:	begin											// wait for the next x input
							Racc <= Racc + RaccBa + RaccBb;		
							Iacc <= Iacc + IaccBa + IaccBb;
						end
				endcase
			end
		end
	end
	
	
	// Enable each FIR in sequence
   assign weA 		= (x_avail && wstate == 0);
	assign weB 		= (x_avail && wstate == 1);

	
	// at end of sequence indicate new data is available
	assign y_avail = (wstate == 2);
	
	// Dual bank polyphase decimate by 2 FIR. Note that second bank needs a RAM write offset of TAPS.

	recv2_fir256d #("coefEa.mif", ABITS, TAPS) A (reset, clock, waddr, raddr, weA, x_real, x_imag, RaccAa, IaccAa);				// first bank odd coeff
	recv2_fir256d #("coefEb.mif", ABITS, TAPS) B (reset, clock, (waddr + 7'd64), raddr, weA, x_real, x_imag, RaccAb, IaccAb);	// second bank 
	recv2_fir256d #("coefFa.mif", ABITS, TAPS) C (reset, clock, waddr, raddr, weB, x_real, x_imag, RaccBa, IaccBa);  				// first bank even coeff
	recv2_fir256d #("coefFb.mif", ABITS, TAPS) D (reset, clock, (waddr + 7'd64), raddr, weB, x_real, x_imag, RaccBb, IaccBb); 	// second bank  


endmodule


// This filter waits until a new sample is written to memory at waddr.  Then
// it starts by multiplying that sample by coef[0], the next prior sample
// by coef[1], (etc.) and accumulating.  For R=2 decimation, coef[1] is the
// coeficient prior to coef[0].
// When reading from the RAM and ROM we need to allow 3 clock pulses from presenting the 
// read address until the data is available. 

module recv2_fir256d(

	input reset,
	input clock,
	input [ADDRBITS-1:0] waddr,							// memory write address
	input [ADDRBITS-1:0] raddr,							// memory read address
	input we,													// memory write enable
	input signed [INBITS-1:0] x_real,					// sample to write
	input signed [INBITS-1:0] x_imag,
	output reg signed [ABITS-1:0] Raccum,
	output reg signed [ABITS-1:0] Iaccum
	);

	localparam ADDRBITS	= 7;								// Address bits for 18/36 x 128 ROM/RAM
	localparam COEFBITS	= 18;								// coefficient bits
	localparam INBITS		= 24;								// I and Q sample width 
	
	parameter MifFile	= "xx.mif";							// ROM coefficients
	parameter ABITS	= 0;									// adder bits
	parameter TAPS		= 0;									// number of filter taps

	reg [ADDRBITS-1:0] caddr;								// read address for  coef
	wire [INBITS*2-1:0] q;									// I/Q sample read from memory
	reg  [INBITS*2-1:0] reg_q;
	wire signed [INBITS-1:0] q_real, q_imag;			// I/Q sample read from memory
	wire signed [COEFBITS-1:0] coef; 	      		// coefficient read from memory
	reg signed  [COEFBITS-1:0] reg_coef; 				// coefficient read from memory
	reg signed  [41:0] Rmult, Imult;						// multiplier result   24 * 18 bits = 42 bits 
	reg signed  [41:0] RmultSum, ImultSum;				// multiplier result
	reg [ADDRBITS:0] counter;								// count TAPS samples, size to allow for pipeline latency
   reg [ADDRBITS-1:0] read_address;
	
	
	assign q_real = reg_q[INBITS*2-1:INBITS];
	assign q_imag = reg_q[INBITS-1:0];

	recv2_firromH #(MifFile) roma (caddr, clock, coef);		// coefficient ROM 18 X 128
	recv2_firram48 rama (clock, {x_real, x_imag}, read_address, waddr, we, q);  	// sample RAM 48 X 128;  48 bit = 24 bits I and 24 bits Q

	
	always @(posedge clock)
	begin
	   if(reset)
			begin 
				Rmult <= 0;
				Imult <= 0;
				Raccum <= 0;
				Iaccum <= 0;
			end 
		else if (we)		// Wait until a new sample is written to memory
			begin
				counter <= TAPS[ADDRBITS:0] + 7'd3;			// count samples and pipeline latency (delay of 3 clocks from address being presented)
				read_address <= raddr;						// RAM read address -> newest sample
				caddr <= 1'd0;									// start at coefficient zero
				Raccum <= 0;
				Iaccum <= 0;
			end
		else
			begin		// main pipeline here
				if (counter < (TAPS[ADDRBITS:0]) + 7'd1)
				begin
					Rmult <= q_real * reg_coef;
					Imult <= q_imag * reg_coef;
					Raccum <= Raccum + Rmult[39:16] + Rmult[15];  // Truncate 42 bits down to 24 bits to prevent DC spur.
					Iaccum <= Iaccum + Imult[39:16] + Imult[15];  // Multiply by 4 to match gain of previous code.
				end
				if (counter > 0)
				begin
					counter <= counter - 1'd1;
					read_address <= read_address - 1'd1;	// move to prior sample
					caddr <= caddr + 1'd1;						// move to next coefficient
					reg_q <= q;
					reg_coef <= coef;
				end
			end
	end
endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Algorithm by Darrell Harmon modified by Cathy Moss
//            Code Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------


module recv2_cordic( reset, clock, frequency, in_data, out_data_I, out_data_Q );

parameter IN_WIDTH   = 16; //ADC bitwidth
parameter EXTRA_BITS = 5;  //spur reduction 6 dB per bit

//internal params
localparam WR =  IN_WIDTH + EXTRA_BITS + 1; //22-bit data regs
localparam OUT_WIDTH = WR;                  //22-bit output width
localparam WZ =  IN_WIDTH + EXTRA_BITS - 1; //20-bit angle regs
localparam STG = IN_WIDTH + EXTRA_BITS - 2; //19 stages
localparam WO = OUT_WIDTH;

localparam WF = 32; //NCO freq,  -Pi..Pi per clock cycle
localparam WP = WF; //NCO phase, 0..2*Pi

input reset;
input clock;
input signed [WF-1:0] frequency;
input signed [IN_WIDTH-1:0] in_data;
output signed [WO-1:0] out_data_I;
output signed [WO-1:0] out_data_Q;






//------------------------------------------------------------------------------
//                             arctan table
//------------------------------------------------------------------------------
localparam WT = 32;

wire signed [WT-1:0] atan_table [1:WT-1];


//     atan_table[00] = 32'b01000000000000000000000000000000; //1073741824  FYI
assign atan_table[01] = 32'b00100101110010000000101000111011; //633866811
assign atan_table[02] = 32'b00010011111101100111000010110111; //334917815
assign atan_table[03] = 32'b00001010001000100010001110101000; //170009512
assign atan_table[04] = 32'b00000101000101100001101010000110; //85334662
assign atan_table[05] = 32'b00000010100010111010111111000011; //42708931
assign atan_table[06] = 32'b00000001010001011110110000111101; //21359677
assign atan_table[07] = 32'b00000000101000101111100010101010; //10680490
assign atan_table[08] = 32'b00000000010100010111110010100111; //5340327
assign atan_table[09] = 32'b00000000001010001011111001011101; //2670173
assign atan_table[10] = 32'b00000000000101000101111100110000; //1335088
assign atan_table[11] = 32'b00000000000010100010111110011000; //667544
assign atan_table[12] = 32'b00000000000001010001011111001100; //333772
assign atan_table[13] = 32'b00000000000000101000101111100110; //166886
assign atan_table[14] = 32'b00000000000000010100010111110011; //83443
assign atan_table[15] = 32'b00000000000000001010001011111010; //41722
assign atan_table[16] = 32'b00000000000000000101000101111101; //20861
assign atan_table[17] = 32'b00000000000000000010100010111110; //10430
assign atan_table[18] = 32'b00000000000000000001010001011111; //5215
assign atan_table[19] = 32'b00000000000000000000101000110000; //2608
assign atan_table[20] = 32'b00000000000000000000010100011000; //1304
assign atan_table[21] = 32'b00000000000000000000001010001100; //652
assign atan_table[22] = 32'b00000000000000000000000101000110; //326
assign atan_table[23] = 32'b00000000000000000000000010100011; //163
assign atan_table[24] = 32'b00000000000000000000000001010001; //81
assign atan_table[25] = 32'b00000000000000000000000000101001; //41
assign atan_table[26] = 32'b00000000000000000000000000010100; //20
assign atan_table[27] = 32'b00000000000000000000000000001010; //10
assign atan_table[28] = 32'b00000000000000000000000000000101; //5
assign atan_table[29] = 32'b00000000000000000000000000000011; //3
assign atan_table[30] = 32'b00000000000000000000000000000001; //1
assign atan_table[31] = 32'b00000000000000000000000000000001; //1








//------------------------------------------------------------------------------
//                              registers
//------------------------------------------------------------------------------
//NCO
reg [WP-1:0] phase;


//stage outputs
reg signed [WR-1:0] X [0:STG-1];
reg signed [WR-1:0] Y [0:STG-1];
reg signed [WZ-1:0] Z [0:STG-1];






//------------------------------------------------------------------------------
//                               stage 0
//------------------------------------------------------------------------------
//input word sign-extended by 1 bit, padded at the right with EXTRA_BITS of zeros
wire signed [WR-1:0] in_data_ext = {in_data[IN_WIDTH-1], in_data, {EXTRA_BITS{1'b0}}};
wire [1:0] quadrant = phase[WP-1:WP-2];


always @(posedge clock)
  begin
//  if (reset) begin 
//		X[0] <= 0;
//		Y[0] <= 0; 
//		Z[0] <= 0;
//		end 
//  else 
  begin
  //rotate to the required quadrant, pre-rotate by +Pi/4. Gain = Sqrt(2)
	  case (quadrant)
		 0: begin X[0] <=  in_data_ext;   Y[0] <=  in_data_ext; end
		 1: begin X[0] <= -in_data_ext;   Y[0] <=  in_data_ext; end
		 2: begin X[0] <= -in_data_ext;   Y[0] <= -in_data_ext; end
		 3: begin X[0] <=  in_data_ext;   Y[0] <= -in_data_ext; end
	  endcase
  end 

  //subtract quadrant and Pi/4 from the angle
  Z[0] <= {~phase[WP-3], ~phase[WP-3], phase[WP-4:WP-WZ-1]};

  //advance NCO
  if 
	(reset) phase <= 0;
  else
	phase <= phase + frequency;
  end






//------------------------------------------------------------------------------
//                           stages 1 to STG-1
//------------------------------------------------------------------------------
genvar n;


generate
  for (n=0; n<=(STG-2); n=n+1)
    begin : stages
    //data from prev stage, shifted
    wire signed [WR-1:0] X_shr = {{(n+1){X[n][WR-1]}}, X[n][WR-1:n+1]};
    wire signed [WR-1:0] Y_shr = {{(n+1){Y[n][WR-1]}}, Y[n][WR-1:n+1]};


    //rounded arctan
    wire [WZ-2-n:0] atan = atan_table[n+1][WT-2-n:WT-WZ] + atan_table[n+1][WT-WZ-1];


    //the sign of the residual
    wire Z_sign = Z[n][WZ-1-n];


    always @(posedge clock)
	//	if (!reset)
      begin
      //add/subtract shifted and rounded data
      X[n+1] <= Z_sign ? X[n] + Y_shr + Y[n][n] : X[n] - Y_shr - Y[n][n];
      Y[n+1] <= Z_sign ? Y[n] - X_shr - X[n][n] : Y[n] + X_shr + X[n][n];

      //update angle
      if (n < STG-2)
        begin : angles
        Z[n+1][WZ-2-n:0] <= Z_sign ? Z[n][WZ-2-n:0] + atan : Z[n][WZ-2-n:0] - atan;
        end
      end
    end
endgenerate






//------------------------------------------------------------------------------
//                                 output
//------------------------------------------------------------------------------
generate
  if (OUT_WIDTH == WR)
    begin
    assign out_data_I = X[STG-1];
    assign out_data_Q = Y[STG-1];
    end
    
  else
    begin
    reg signed [WO-1:0] rounded_I;
    reg signed [WO-1:0] rounded_Q;

    always @(posedge clock)
//	 if (reset)
//	 begin 
//		rounded_I <= 0;
//		rounded_Q <= 0;
//	 end 
//	 else 
      begin
      rounded_I <= X[STG-1][WR-1 : WR-WO] + X[STG-1][WR-1-WO];
      rounded_Q <= Y[STG-1][WR-1 : WR-WO] + Y[STG-1][WR-1-WO];
      end
      
    assign out_data_I = rounded_I;
    assign out_data_Q = rounded_Q;
    end
endgenerate



endmodule
// megafunction wizard: %RAM: 2-PORT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsyncram 

// ============================================================
// File Name: firram36I_1024.v
// Megafunction Name(s):
// 			altsyncram
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 14.0.1 Build 205 08/13/2014 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2014 Altera Corporation. All rights reserved.
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, the Altera Quartus II License Agreement,
//the Altera MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Altera and sold by Altera or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module firram36I_1024 (
	clock,
	data,
	rdaddress,
	wraddress,
	wren,
	q);

	input	  clock;
	input	[35:0]  data;
	input	[6:0]  rdaddress;
	input	[6:0]  wraddress;
	input	  wren;
	output	[35:0]  q;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri1	  clock;
	tri0	  wren;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [35:0] sub_wire0;
	wire [35:0] q = sub_wire0[35:0];
/*	altsyncram	altsyncram_component (
				.address_a (wraddress),
				.address_b (rdaddress),
				.clock0 (clock),
				.data_a (data),
				.wren_a (wren),
				.q_b (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({36{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 128,
		altsyncram_component.numwords_b = 128,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "CLOCK0",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = 7,
		altsyncram_component.widthad_b = 7,
		altsyncram_component.width_a = 36,
		altsyncram_component.width_b = 36,
		altsyncram_component.width_byteena_a = 1;
*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ADDRESSSTALL_A NUMERIC "0"
// Retrieval info: PRIVATE: ADDRESSSTALL_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_SIZE NUMERIC "9"
// Retrieval info: PRIVATE: BlankMemory NUMERIC "1"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLRdata NUMERIC "0"
// Retrieval info: PRIVATE: CLRq NUMERIC "0"
// Retrieval info: PRIVATE: CLRrdaddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRrren NUMERIC "0"
// Retrieval info: PRIVATE: CLRwraddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRwren NUMERIC "0"
// Retrieval info: PRIVATE: Clock NUMERIC "0"
// Retrieval info: PRIVATE: Clock_A NUMERIC "0"
// Retrieval info: PRIVATE: Clock_B NUMERIC "0"
// Retrieval info: PRIVATE: IMPLEMENT_IN_LES NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: INIT_FILE_LAYOUT STRING "PORT_B"
// Retrieval info: PRIVATE: INIT_TO_SIM_X NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "0"
// Retrieval info: PRIVATE: JTAG_ID STRING "NONE"
// Retrieval info: PRIVATE: MAXIMUM_DEPTH NUMERIC "0"
// Retrieval info: PRIVATE: MEMSIZE NUMERIC "4608"
// Retrieval info: PRIVATE: MEM_IN_BITS NUMERIC "0"
// Retrieval info: PRIVATE: MIFfilename STRING ""
// Retrieval info: PRIVATE: OPERATION_MODE NUMERIC "2"
// Retrieval info: PRIVATE: OUTDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: OUTDATA_REG_B NUMERIC "1"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "0"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_MIXED_PORTS NUMERIC "2"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_A NUMERIC "3"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_B NUMERIC "3"
// Retrieval info: PRIVATE: REGdata NUMERIC "1"
// Retrieval info: PRIVATE: REGq NUMERIC "1"
// Retrieval info: PRIVATE: REGrdaddress NUMERIC "1"
// Retrieval info: PRIVATE: REGrren NUMERIC "1"
// Retrieval info: PRIVATE: REGwraddress NUMERIC "1"
// Retrieval info: PRIVATE: REGwren NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: USE_DIFF_CLKEN NUMERIC "0"
// Retrieval info: PRIVATE: UseDPRAM NUMERIC "1"
// Retrieval info: PRIVATE: VarWidth NUMERIC "0"
// Retrieval info: PRIVATE: WIDTH_READ_A NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_READ_B NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_WRITE_A NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_WRITE_B NUMERIC "36"
// Retrieval info: PRIVATE: WRADDR_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: WRADDR_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: WRCTRL_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: enable NUMERIC "0"
// Retrieval info: PRIVATE: rden NUMERIC "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: ADDRESS_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: ADDRESS_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_OUTPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altsyncram"
// Retrieval info: CONSTANT: NUMWORDS_A NUMERIC "128"
// Retrieval info: CONSTANT: NUMWORDS_B NUMERIC "128"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "DUAL_PORT"
// Retrieval info: CONSTANT: OUTDATA_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: OUTDATA_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: POWER_UP_UNINITIALIZED STRING "FALSE"
// Retrieval info: CONSTANT: READ_DURING_WRITE_MODE_MIXED_PORTS STRING "DONT_CARE"
// Retrieval info: CONSTANT: WIDTHAD_A NUMERIC "7"
// Retrieval info: CONSTANT: WIDTHAD_B NUMERIC "7"
// Retrieval info: CONSTANT: WIDTH_A NUMERIC "36"
// Retrieval info: CONSTANT: WIDTH_B NUMERIC "36"
// Retrieval info: CONSTANT: WIDTH_BYTEENA_A NUMERIC "1"
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT VCC "clock"
// Retrieval info: USED_PORT: data 0 0 36 0 INPUT NODEFVAL "data[35..0]"
// Retrieval info: USED_PORT: q 0 0 36 0 OUTPUT NODEFVAL "q[35..0]"
// Retrieval info: USED_PORT: rdaddress 0 0 7 0 INPUT NODEFVAL "rdaddress[6..0]"
// Retrieval info: USED_PORT: wraddress 0 0 7 0 INPUT NODEFVAL "wraddress[6..0]"
// Retrieval info: USED_PORT: wren 0 0 0 0 INPUT GND "wren"
// Retrieval info: CONNECT: @address_a 0 0 7 0 wraddress 0 0 7 0
// Retrieval info: CONNECT: @address_b 0 0 7 0 rdaddress 0 0 7 0
// Retrieval info: CONNECT: @clock0 0 0 0 0 clock 0 0 0 0
// Retrieval info: CONNECT: @data_a 0 0 36 0 data 0 0 36 0
// Retrieval info: CONNECT: @wren_a 0 0 0 0 wren 0 0 0 0
// Retrieval info: CONNECT: q 0 0 36 0 @q_b 0 0 36 0
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_1024.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_1024.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_1024.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_1024.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_1024_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_1024_bb.v TRUE
// Retrieval info: LIB_FILE: altera_mf
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Algorithm by Darrell Harmon modified by Cathy Moss
//            Code Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------

// 2015 Jan 31 - updated for Hermes-Lite 12bit Steve Haynal KF7O


module cordic #(parameter IN_WIDTH=12, EXTRA_BITS=6) ( clock, frequency, in_data, out_data_I, out_data_Q );

//parameter IN_WIDTH   = 12; //ADC bitwidth
//parameter EXTRA_BITS = 6;  //spur reduction 6 dB per bit

//internal params
localparam WR =  IN_WIDTH + EXTRA_BITS + 1; //18-bit data regs
localparam OUT_WIDTH = 18;                  //18-bit output width
localparam WZ =  IN_WIDTH + EXTRA_BITS - 1; //16-bit angle regs
localparam STG = IN_WIDTH + EXTRA_BITS - 2; //15 stages
localparam WO = OUT_WIDTH;

localparam WF = 32; //NCO freq,  -Pi..Pi per clock cycle
localparam WP = WF; //NCO phase, 0..2*Pi

input clock;
input signed [WF-1:0] frequency;
input signed [IN_WIDTH-1:0] in_data;
output signed [WO-1:0] out_data_I;
output signed [WO-1:0] out_data_Q;


//------------------------------------------------------------------------------
//                             arctan table
//------------------------------------------------------------------------------
localparam WT = 32;

wire signed [WT-1:0] atan_table [1:WT-1];


//     atan_table[00] = 32'b01000000000000000000000000000000; //1073741824  FYI
assign atan_table[01] = 32'b00100101110010000000101000111011; //633866811
assign atan_table[02] = 32'b00010011111101100111000010110111; //334917815
assign atan_table[03] = 32'b00001010001000100010001110101000; //170009512
assign atan_table[04] = 32'b00000101000101100001101010000110; //85334662
assign atan_table[05] = 32'b00000010100010111010111111000011; //42708931
assign atan_table[06] = 32'b00000001010001011110110000111101; //21359677
assign atan_table[07] = 32'b00000000101000101111100010101010; //10680490
assign atan_table[08] = 32'b00000000010100010111110010100111; //5340327
assign atan_table[09] = 32'b00000000001010001011111001011101; //2670173
assign atan_table[10] = 32'b00000000000101000101111100110000; //1335088
assign atan_table[11] = 32'b00000000000010100010111110011000; //667544
assign atan_table[12] = 32'b00000000000001010001011111001100; //333772
assign atan_table[13] = 32'b00000000000000101000101111100110; //166886
assign atan_table[14] = 32'b00000000000000010100010111110011; //83443
assign atan_table[15] = 32'b00000000000000001010001011111010; //41722
assign atan_table[16] = 32'b00000000000000000101000101111101; //20861
assign atan_table[17] = 32'b00000000000000000010100010111110; //10430
assign atan_table[18] = 32'b00000000000000000001010001011111; //5215
assign atan_table[19] = 32'b00000000000000000000101000110000; //2608
assign atan_table[20] = 32'b00000000000000000000010100011000; //1304
assign atan_table[21] = 32'b00000000000000000000001010001100; //652
assign atan_table[22] = 32'b00000000000000000000000101000110; //326
assign atan_table[23] = 32'b00000000000000000000000010100011; //163
assign atan_table[24] = 32'b00000000000000000000000001010001; //81
assign atan_table[25] = 32'b00000000000000000000000000101001; //41
assign atan_table[26] = 32'b00000000000000000000000000010100; //20
assign atan_table[27] = 32'b00000000000000000000000000001010; //10
assign atan_table[28] = 32'b00000000000000000000000000000101; //5
assign atan_table[29] = 32'b00000000000000000000000000000011; //3
assign atan_table[30] = 32'b00000000000000000000000000000001; //1
assign atan_table[31] = 32'b00000000000000000000000000000001; //1








//------------------------------------------------------------------------------
//                              registers
//------------------------------------------------------------------------------
//NCO
reg [WP-1:0] phase = 0;


//stage outputs
reg signed [WR-1:0] X [0:STG-1];
reg signed [WR-1:0] Y [0:STG-1];
reg signed [WZ-1:0] Z [0:STG-1];






//------------------------------------------------------------------------------
//                               stage 0
//------------------------------------------------------------------------------
//input word sign-extended by 1 bit, padded at the right with EXTRA_BITS of zeros
wire signed [WR-1:0] in_data_ext = {in_data[IN_WIDTH-1], in_data, {EXTRA_BITS{1'b0}}};
wire [1:0] quadrant = phase[WP-1:WP-2];


always @(posedge clock)
  begin
  //rotate to the required quadrant, pre-rotate by +Pi/4. Gain = Sqrt(2)
  case (quadrant)
    0: begin X[0] <=  in_data_ext;   Y[0] <=  in_data_ext; end
    1: begin X[0] <= -in_data_ext;   Y[0] <=  in_data_ext; end
    2: begin X[0] <= -in_data_ext;   Y[0] <= -in_data_ext; end
    3: begin X[0] <=  in_data_ext;   Y[0] <= -in_data_ext; end
  endcase

  //subtract quadrant and Pi/4 from the angle
  Z[0] <= {~phase[WP-3], ~phase[WP-3], phase[WP-4:WP-WZ-1]};

  if (frequency == 1'b0)
    // For zero frequency, synchronize phase to other cordics.
    phase <= 1'b0;
  else
    //advance NCO
    phase <= phase + frequency;
  end






//------------------------------------------------------------------------------
//                           stages 1 to STG-1
//------------------------------------------------------------------------------
genvar n;


generate
  for (n=0; n<=(STG-2); n=n+1)
    begin : stages
    //data from prev stage, shifted
    wire signed [WR-1:0] X_shr = {{(n+1){X[n][WR-1]}}, X[n][WR-1:n+1]};
    wire signed [WR-1:0] Y_shr = {{(n+1){Y[n][WR-1]}}, Y[n][WR-1:n+1]};


    //rounded arctan
    wire [WZ-2-n:0] atan = atan_table[n+1][WT-2-n:WT-WZ] + atan_table[n+1][WT-WZ-1];


    //the sign of the residual
    wire Z_sign = Z[n][WZ-1-n];


    always @(posedge clock)
      begin
      //add/subtract shifted and rounded data
      X[n+1] <= Z_sign ? X[n] + Y_shr + Y[n][n] : X[n] - Y_shr - Y[n][n];
      Y[n+1] <= Z_sign ? Y[n] - X_shr - X[n][n] : Y[n] + X_shr + X[n][n];

      //update angle
      if (n < STG-2)
        begin : angles
        Z[n+1][WZ-2-n:0] <= Z_sign ? Z[n][WZ-2-n:0] + atan : Z[n][WZ-2-n:0] - atan;
        end
      end
    end
endgenerate






//------------------------------------------------------------------------------
//                                 output
//------------------------------------------------------------------------------
generate
  if (OUT_WIDTH == WR)
    begin
    assign out_data_I = X[STG-1];
    assign out_data_Q = Y[STG-1];
    end
    
  else
    begin
    reg signed [WR-1:0] rounded_I = 0;
    reg signed [WR-1:0] rounded_Q = 0;

    always @(posedge clock)
      begin
   //   rounded_I <= X[STG-1][WR-1 : WR-WO] +{{(WO-1){1'b0}},  X[STG-1][WR-1-WO]};
   //   rounded_Q <= Y[STG-1][WR-1 : WR-WO] +{{(WO-1){1'b0}},   Y[STG-1][WR-1-WO]};
   // rounding from http://zipcpu.com/dsp/2017/07/22/rounding.html
     rounded_I <= X[STG-1][WR-1 :0]
							+ {{(WO){1'b0}},
							X[STG-1][WR-WO],
							{(WR-WO-1){!X[STG-1][WR-WO]}}};
 		
		rounded_Q <= Y[STG-1][WR-1 :0]
							+ {{(WO){1'b0}},
							Y[STG-1][WR-WO],
							{(WR-WO-1){!Y[STG-1][WR-WO]}}};
 		
		
      end
      
    assign out_data_I = rounded_I[WR-1:WR-WO];
    assign out_data_Q = rounded_Q[WR-1:WR-WO];
    end
endgenerate



endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------



module qs1r_fir( clock, start, coeff, in_data, out_data, out_strobe );

parameter OUT_WIDTH = 32;
localparam MSB = 46;
localparam LSB = MSB - OUT_WIDTH + 1;

input clock;
input start;
input signed [23:0] coeff;
input signed [23:0] in_data;
output reg signed [OUT_WIDTH-1:0] out_data;
output reg out_strobe;


reg [2:0] state;
reg shift;
reg clear_mac;
reg even_sample;
wire last_sample;
wire [23:0] shr_out;
wire signed [55:0] mac_out;

initial
  begin
  shift = 0;
  clear_mac = 1; 
  state = 0;
  even_sample = 1;
  end


always @(posedge clock)
    case (state)
      0: //if start=1: write new sample to shiftreg, dump the oldest sample
        if (start) state <= state + 1'b1;

      1: //clear mac
        begin         
        clear_mac <= 1;
        state <= state + 1'b1;
        end
        
      2: //switch shiftreg to shift mode; enable mac
        begin         
        shift <= 1;
        clear_mac <= 0;
        state <= state + 1'b1;
        end
      

      3: //strobe 256 sample/coeff pairs into mac, then stop shifting
        if (last_sample) 
          begin
          shift <= 0;
          state <= state + 1'b1;
          end
          
      4, 5: //wait for the mac pipeline to finish
        state <= state + 1'b1;
        
      6: //round and register mac output, strobe every even out_data
        begin       
        out_data <= mac_out[MSB:LSB] + mac_out[LSB-1];
        if (even_sample) out_strobe <= 1;
        even_sample <= ~even_sample;
        state <= state + 1'b1;
        end

      7: //done, clear strobe
        begin
        out_strobe <= 0;     
        state <= 0;
        end

    endcase


//------------------------------------------------------------------------------
//                    circular shift register 256 x 24 bit
//------------------------------------------------------------------------------
wire [23:0] shr_in = start ? in_data : shr_out;


qs1r_fir_shiftreg fir_shiftreg_inst(
  .clock(clock),
  .clken(start | shift),
  .shiftin({start, shr_in}), //MSB bit flags the new sample
  .shiftout({last_sample, shr_out})
  );

//------------------------------------------------------------------------------
//                        multiplier / accumulator
//------------------------------------------------------------------------------
qs1r_fir_mac fir_mac_inst(
  .clock(clock),
  .clear(clear_mac),
  .in_data_1(shr_out),
  .in_data_2(coeff),
  .out_data(mac_out)
  );

endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------



module qs1r_cic_comb( clock, strobe,  in_data,  out_data );

parameter WIDTH = 64;

input clock;
input strobe;
input signed [WIDTH-1:0] in_data;
output reg signed [WIDTH-1:0] out_data;


reg signed [WIDTH-1:0] prev_data;
initial prev_data = 0;


always @(posedge clock)  
  if (strobe) 
    begin
    out_data <= in_data - prev_data;
    prev_data <= in_data;
    end



endmodule
(* blackbox *)
module lpm_mult #(parameter lpm_hint="DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=5",
                  lpm_pipeline=2,
                  lpm_representation="UNSIGNED",
                  lpm_type="LPM_MULT",
                  lpm_widtha=18,
                  lpm_widthb=18,
                  lpm_widthp=36)
 (input clock, [lpm_widtha-1:0] dataa, [lpm_widthb-1:0] datab,
  input aclr, clken, sclr,
  output [lpm_widthp:0] result, sum);
endmodule

// megafunction wizard: %LPM_MULT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: lpm_mult 

// ============================================================
// File Name: mult_24Sx24S.v
// Megafunction Name(s):
// 			lpm_mult
//
// Simulation Library Files(s):
// 			lpm
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 7.2 Build 207 03/18/2008 SP 3 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2007 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module qs1r_mult_24Sx24S (
	aclr,
	clock,
	dataa,
	datab,
	result);

	input	  aclr;
	input	  clock;
	input	[23:0]  dataa;
	input	[23:0]  datab;
	output	[47:0]  result;

	wire [47:0] sub_wire0;
	wire [47:0] result = sub_wire0[47:0];
/*
	lpm_mult	lpm_mult_component (
				.dataa (dataa),
				.datab (datab),
				.aclr (aclr),
				.clock (clock),
				.result (sub_wire0),
				.clken (1'b1),
				.sum (1'b0));
	defparam
		lpm_mult_component.lpm_hint = "MAXIMIZE_SPEED=5",
		lpm_mult_component.lpm_pipeline = 3,
		lpm_mult_component.lpm_representation = "SIGNED",
		lpm_mult_component.lpm_type = "LPM_MULT",
		lpm_mult_component.lpm_widtha = 24,
		lpm_mult_component.lpm_widthb = 24,
		lpm_mult_component.lpm_widthp = 48;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: AutoSizeResult NUMERIC "1"
// Retrieval info: PRIVATE: B_isConstant NUMERIC "0"
// Retrieval info: PRIVATE: ConstantB NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: PRIVATE: LPM_INE NUMERIC "3"
// Retrieval info: PRIVATE: Latency NUMERIC "1"
// Retrieval info: PRIVATE: OptionalSum NUMERIC "0"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: SignedMult NUMERIC "1"
// Retrieval info: PRIVATE: USE_MULT NUMERIC "1"
// Retrieval info: PRIVATE: ValidConstant NUMERIC "0"
// Retrieval info: PRIVATE: WidthA NUMERIC "24"
// Retrieval info: PRIVATE: WidthB NUMERIC "24"
// Retrieval info: PRIVATE: WidthP NUMERIC "48"
// Retrieval info: PRIVATE: WidthS NUMERIC "1"
// Retrieval info: PRIVATE: aclr NUMERIC "1"
// Retrieval info: PRIVATE: clken NUMERIC "0"
// Retrieval info: PRIVATE: optimize NUMERIC "1"
// Retrieval info: CONSTANT: LPM_HINT STRING "MAXIMIZE_SPEED=5"
// Retrieval info: CONSTANT: LPM_PIPELINE NUMERIC "3"
// Retrieval info: CONSTANT: LPM_REPRESENTATION STRING "SIGNED"
// Retrieval info: CONSTANT: LPM_TYPE STRING "LPM_MULT"
// Retrieval info: CONSTANT: LPM_WIDTHA NUMERIC "24"
// Retrieval info: CONSTANT: LPM_WIDTHB NUMERIC "24"
// Retrieval info: CONSTANT: LPM_WIDTHP NUMERIC "48"
// Retrieval info: USED_PORT: aclr 0 0 0 0 INPUT NODEFVAL aclr
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT NODEFVAL clock
// Retrieval info: USED_PORT: dataa 0 0 24 0 INPUT NODEFVAL dataa[23..0]
// Retrieval info: USED_PORT: datab 0 0 24 0 INPUT NODEFVAL datab[23..0]
// Retrieval info: USED_PORT: result 0 0 48 0 OUTPUT NODEFVAL result[47..0]
// Retrieval info: CONNECT: @dataa 0 0 24 0 dataa 0 0 24 0
// Retrieval info: CONNECT: result 0 0 48 0 @result 0 0 48 0
// Retrieval info: CONNECT: @datab 0 0 24 0 datab 0 0 24 0
// Retrieval info: CONNECT: @clock 0 0 0 0 clock 0 0 0 0
// Retrieval info: CONNECT: @aclr 0 0 0 0 aclr 0 0 0 0
// Retrieval info: LIBRARY: lpm lpm.lpm_components.all
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S_inst.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S_bb.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S_waveforms.html FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL mult_24Sx24S_wave*.jpg FALSE
// Retrieval info: LIB_FILE: lpm
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------


//coeff[0] is available 3 clock cycles after the start pulse

//start: coeff_idx <- 0
//start+1: coeff_idx latched in the ROM address register
//start+2: coeff latched in the ROM output register
//start+3: coeff is available at the output


module qs1r_fir_coeffs(
  input clock,
  input start,
  output signed [23:0] coeff
  );


reg [7:0] coeff_idx;


always @(posedge clock)
  if (start) coeff_idx <= 0; 
  else coeff_idx <= coeff_idx + 8'b1;          


qs1r_fir_coeffs_rom fir_coeffs_rom_inst(
  .clock(clock),
  .address(coeff_idx),
  .q(coeff)
  );



endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------



module qs1r_cic_integrator( clock, strobe, in_data,  out_data );

parameter WIDTH = 64;

input clock;
input strobe;
input signed [WIDTH-1:0] in_data;
output reg signed [WIDTH-1:0] out_data;


//initial out_data = 0; // this is NOT a valid RTL statement! Kirk Weedman KD7IRS


always @(posedge clock)
  if (strobe) out_data <= out_data + in_data;


endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------



module qs1r_varcic( extra_decimation, clock, in_strobe,  out_strobe, in_data, out_data );


  //design parameters
  parameter STAGES = 5;
  parameter DECIMATION = 320;  
  parameter IN_WIDTH = 22;


  //computed parameters
  //ACC_WIDTH = IN_WIDTH + Ceil(STAGES * Log2(decimation factor))
  //OUT_WIDTH = IN_WIDTH + Ceil(Log2(decimation factor) / 2)
  parameter ACC_WIDTH = 64;
  parameter OUT_WIDTH = 27;

  //00 = DECIMATION*4, 01 = DECIMATION*2, 10 = DECIMATION
  input [1:0] extra_decimation;
  
  input clock;
  input in_strobe;
  output reg out_strobe;

  input signed [IN_WIDTH-1:0] in_data;
  output reg signed [OUT_WIDTH-1:0] out_data;





//------------------------------------------------------------------------------
//                               control
//------------------------------------------------------------------------------
reg [15:0] sample_no;
initial sample_no = 16'd0;


always @(posedge clock)
  if (in_strobe)
    begin
    if (sample_no == ((DECIMATION << (2-extra_decimation))-1))
      begin
      sample_no <= 0;
      out_strobe <= 1;
      end
    else
      begin
      sample_no <= sample_no + 8'd1;
      out_strobe <= 0;
      end
    end

  else
    out_strobe <= 0;






//------------------------------------------------------------------------------
//                                stages
//------------------------------------------------------------------------------
wire signed [ACC_WIDTH-1:0] integrator_data [0:STAGES];
wire signed [ACC_WIDTH-1:0] comb_data [0:STAGES];


assign integrator_data[0] = in_data;
assign comb_data[0] = integrator_data[STAGES];


genvar i;
generate
  for (i=0; i<STAGES; i=i+1)
    begin : cic_stages

    qs1r_cic_integrator #(ACC_WIDTH) cic_integrator_inst(
      .clock(clock),
      .strobe(in_strobe),
      .in_data(integrator_data[i]),
      .out_data(integrator_data[i+1])
      );


    qs1r_cic_comb #(ACC_WIDTH) cic_comb_inst(
      .clock(clock),
      .strobe(out_strobe),
      .in_data(comb_data[i]),
      .out_data(comb_data[i+1])
      );
    end
endgenerate







//------------------------------------------------------------------------------
//                            output rounding
//------------------------------------------------------------------------------
localparam MSB0 = ACC_WIDTH - 1;            //63
localparam LSB0 = ACC_WIDTH - OUT_WIDTH;    //41

localparam MSB1 = MSB0 - STAGES;            //58
localparam LSB1 = LSB0 - STAGES;            //36

localparam MSB2 = MSB1 - STAGES;            //53
localparam LSB2 = LSB1 - STAGES;            //31


always @(posedge clock)
  case (extra_decimation)
    0: out_data <= comb_data[STAGES][MSB0:LSB0] + comb_data[STAGES][LSB0-1];
    1: out_data <= comb_data[STAGES][MSB1:LSB1] + comb_data[STAGES][LSB1-1];
    2: out_data <= comb_data[STAGES][MSB2:LSB2] + comb_data[STAGES][LSB2-1];
  endcase



endmodule

// megafunction wizard: %Shift register (RAM-based)%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altshift_taps 

// ============================================================
// File Name: fir_shiftreg.v
// Megafunction Name(s):
// 			altshift_taps
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 8.1 Build 163 10/28/2008 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2008 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module qs1r_fir_shiftreg (
	clken,
	clock,
	shiftin,
	shiftout,
	taps);

	input	  clken;
	input	  clock;
	input	[24:0]  shiftin;
	output	[24:0]  shiftout;
	output	[24:0]  taps;

	wire [24:0] sub_wire0;
	wire [24:0] sub_wire1;
	wire [24:0] taps = sub_wire0[24:0];
	wire [24:0] shiftout = sub_wire1[24:0];
/*
	altshift_taps	altshift_taps_component (
				.clken (clken),
				.clock (clock),
				.shiftin (shiftin),
				.taps (sub_wire0),
				.shiftout (sub_wire1)
				// synopsys translate_off
				,
				.aclr ()
				// synopsys translate_on
				);
	defparam
		altshift_taps_component.lpm_hint = "RAM_BLOCK_TYPE=AUTO",
		altshift_taps_component.lpm_type = "altshift_taps",
		altshift_taps_component.number_of_taps = 1,
		altshift_taps_component.tap_distance = 256,
		altshift_taps_component.width = 25;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ACLR NUMERIC "0"
// Retrieval info: PRIVATE: CLKEN NUMERIC "1"
// Retrieval info: PRIVATE: GROUP_TAPS NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: PRIVATE: NUMBER_OF_TAPS NUMERIC "1"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "3"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: TAP_DISTANCE NUMERIC "256"
// Retrieval info: PRIVATE: WIDTH NUMERIC "25"
// Retrieval info: CONSTANT: LPM_HINT STRING "RAM_BLOCK_TYPE=AUTO"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altshift_taps"
// Retrieval info: CONSTANT: NUMBER_OF_TAPS NUMERIC "1"
// Retrieval info: CONSTANT: TAP_DISTANCE NUMERIC "256"
// Retrieval info: CONSTANT: WIDTH NUMERIC "25"
// Retrieval info: USED_PORT: clken 0 0 0 0 INPUT VCC clken
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT NODEFVAL clock
// Retrieval info: USED_PORT: shiftin 0 0 25 0 INPUT NODEFVAL shiftin[24..0]
// Retrieval info: USED_PORT: shiftout 0 0 25 0 OUTPUT NODEFVAL shiftout[24..0]
// Retrieval info: USED_PORT: taps 0 0 25 0 OUTPUT NODEFVAL taps[24..0]
// Retrieval info: CONNECT: @shiftin 0 0 25 0 shiftin 0 0 25 0
// Retrieval info: CONNECT: shiftout 0 0 25 0 @shiftout 0 0 25 0
// Retrieval info: CONNECT: taps 0 0 25 0 @taps 0 0 25 0
// Retrieval info: CONNECT: @clock 0 0 0 0 clock 0 0 0 0
// Retrieval info: CONNECT: @clken 0 0 0 0 clken 0 0 0 0
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg_bb.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg_waveforms.html FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_shiftreg_wave*.jpg FALSE
// Retrieval info: LIB_FILE: altera_mf
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Algorithm by Darrell Harmon modified by Cathy Moss
//            Code Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------


module qs1r_cordic( clock, frequency, in_data, out_data_I, out_data_Q );

parameter IN_WIDTH   = 16; //ADC bitwidth
parameter EXTRA_BITS = 5;  //spur reduction 6 dB per bit

//internal params
localparam WR =  IN_WIDTH + EXTRA_BITS + 1; //22-bit data regs
localparam OUT_WIDTH = WR;                  //22-bit output width
localparam WZ =  IN_WIDTH + EXTRA_BITS - 1; //20-bit angle regs
localparam STG = IN_WIDTH + EXTRA_BITS - 2; //19 stages
localparam WO = OUT_WIDTH;

localparam WF = 32; //NCO freq,  -Pi..Pi per clock cycle
localparam WP = WF; //NCO phase, 0..2*Pi

input clock;
input signed [WF-1:0] frequency;
input signed [IN_WIDTH-1:0] in_data;
output signed [WO-1:0] out_data_I;
output signed [WO-1:0] out_data_Q;






//------------------------------------------------------------------------------
//                             arctan table
//------------------------------------------------------------------------------
localparam WT = 32;

wire signed [WT-1:0] atan_table [1:WT-1];


//     atan_table[00] = 32'b01000000000000000000000000000000; //1073741824  FYI
assign atan_table[01] = 32'b00100101110010000000101000111011; //633866811
assign atan_table[02] = 32'b00010011111101100111000010110111; //334917815
assign atan_table[03] = 32'b00001010001000100010001110101000; //170009512
assign atan_table[04] = 32'b00000101000101100001101010000110; //85334662
assign atan_table[05] = 32'b00000010100010111010111111000011; //42708931
assign atan_table[06] = 32'b00000001010001011110110000111101; //21359677
assign atan_table[07] = 32'b00000000101000101111100010101010; //10680490
assign atan_table[08] = 32'b00000000010100010111110010100111; //5340327
assign atan_table[09] = 32'b00000000001010001011111001011101; //2670173
assign atan_table[10] = 32'b00000000000101000101111100110000; //1335088
assign atan_table[11] = 32'b00000000000010100010111110011000; //667544
assign atan_table[12] = 32'b00000000000001010001011111001100; //333772
assign atan_table[13] = 32'b00000000000000101000101111100110; //166886
assign atan_table[14] = 32'b00000000000000010100010111110011; //83443
assign atan_table[15] = 32'b00000000000000001010001011111010; //41722
assign atan_table[16] = 32'b00000000000000000101000101111101; //20861
assign atan_table[17] = 32'b00000000000000000010100010111110; //10430
assign atan_table[18] = 32'b00000000000000000001010001011111; //5215
assign atan_table[19] = 32'b00000000000000000000101000110000; //2608
assign atan_table[20] = 32'b00000000000000000000010100011000; //1304
assign atan_table[21] = 32'b00000000000000000000001010001100; //652
assign atan_table[22] = 32'b00000000000000000000000101000110; //326
assign atan_table[23] = 32'b00000000000000000000000010100011; //163
assign atan_table[24] = 32'b00000000000000000000000001010001; //81
assign atan_table[25] = 32'b00000000000000000000000000101001; //41
assign atan_table[26] = 32'b00000000000000000000000000010100; //20
assign atan_table[27] = 32'b00000000000000000000000000001010; //10
assign atan_table[28] = 32'b00000000000000000000000000000101; //5
assign atan_table[29] = 32'b00000000000000000000000000000011; //3
assign atan_table[30] = 32'b00000000000000000000000000000001; //1
assign atan_table[31] = 32'b00000000000000000000000000000001; //1








//------------------------------------------------------------------------------
//                              registers
//------------------------------------------------------------------------------
//NCO
reg [WP-1:0] phase;


//stage outputs
reg signed [WR-1:0] X [0:STG-1];
reg signed [WR-1:0] Y [0:STG-1];
reg signed [WZ-1:0] Z [0:STG-1];






//------------------------------------------------------------------------------
//                               stage 0
//------------------------------------------------------------------------------
//input word sign-extended by 1 bit, padded at the right with EXTRA_BITS of zeros
wire signed [WR-1:0] in_data_ext = {in_data[IN_WIDTH-1], in_data, {EXTRA_BITS{1'b0}}};
wire [1:0] quadrant = phase[WP-1:WP-2];


always @(posedge clock)
  begin
  //rotate to the required quadrant, pre-rotate by +Pi/4. Gain = Sqrt(2)
  case (quadrant)
    0: begin X[0] <=  in_data_ext;   Y[0] <=  in_data_ext; end
    1: begin X[0] <= -in_data_ext;   Y[0] <=  in_data_ext; end
    2: begin X[0] <= -in_data_ext;   Y[0] <= -in_data_ext; end
    3: begin X[0] <=  in_data_ext;   Y[0] <= -in_data_ext; end
  endcase

  //subtract quadrant and Pi/4 from the angle
  Z[0] <= {~phase[WP-3], ~phase[WP-3], phase[WP-4:WP-WZ-1]};

  //advance NCO
  phase <= phase + frequency;
  end






//------------------------------------------------------------------------------
//                           stages 1 to STG-1
//------------------------------------------------------------------------------
genvar n;


generate
  for (n=0; n<=(STG-2); n=n+1)
    begin : stages
    //data from prev stage, shifted
    wire signed [WR-1:0] X_shr = {{(n+1){X[n][WR-1]}}, X[n][WR-1:n+1]};
    wire signed [WR-1:0] Y_shr = {{(n+1){Y[n][WR-1]}}, Y[n][WR-1:n+1]};


    //rounded arctan
    wire [WZ-2-n:0] atan = atan_table[n+1][WT-2-n:WT-WZ] + atan_table[n+1][WT-WZ-1];


    //the sign of the residual
    wire Z_sign = Z[n][WZ-1-n];


    always @(posedge clock)
      begin
      //add/subtract shifted and rounded data
      X[n+1] <= Z_sign ? X[n] + Y_shr + Y[n][n] : X[n] - Y_shr - Y[n][n];
      Y[n+1] <= Z_sign ? Y[n] - X_shr - X[n][n] : Y[n] + X_shr + X[n][n];

      //update angle
      if (n < STG-2)
        begin : angles
        Z[n+1][WZ-2-n:0] <= Z_sign ? Z[n][WZ-2-n:0] + atan : Z[n][WZ-2-n:0] - atan;
        end
      end
    end
endgenerate






//------------------------------------------------------------------------------
//                                 output
//------------------------------------------------------------------------------
generate
  if (OUT_WIDTH == WR)
    begin
    assign out_data_I = X[STG-1];
    assign out_data_Q = Y[STG-1];
    end
    
  else
    begin
    reg signed [WO-1:0] rounded_I;
    reg signed [WO-1:0] rounded_Q;

    always @(posedge clock)
      begin
      rounded_I <= X[STG-1][WR-1 : WR-WO] + X[STG-1][WR-1-WO];
      rounded_Q <= Y[STG-1][WR-1 : WR-WO] + Y[STG-1][WR-1-WO];
      end
      
    assign out_data_I = rounded_I;
    assign out_data_Q = rounded_Q;
    end
endgenerate



endmodule
// megafunction wizard: %ROM: 1-PORT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsyncram 

// ============================================================
// File Name: fir_coeffs_rom.v
// Megafunction Name(s):
// 			altsyncram
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 7.2 Build 207 03/18/2008 SP 3 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2007 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module qs1r_fir_coeffs_rom (
	address,
	clock,
	q);

	input	[7:0]  address;
	input	  clock;
	output	[23:0]  q;

	wire [23:0] sub_wire0;
	wire [23:0] q = sub_wire0[23:0];
/*
	altsyncram	altsyncram_component (
				.clock0 (clock),
				.address_a (address),
				.q_a (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.address_b (1'b1),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_a ({24{1'b1}}),
				.data_b (1'b1),
				.eccstatus (),
				.q_b (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_a (1'b0),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_a = "NONE",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
`ifdef NO_PLI
		altsyncram_component.init_file = "fir_coeffs_rom.rif"
`else
		altsyncram_component.init_file = "fir_coeffs_rom.hex"
`endif
,
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 256,
		altsyncram_component.operation_mode = "ROM",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_reg_a = "CLOCK0",
		altsyncram_component.widthad_a = 8,
		altsyncram_component.width_a = 24,
		altsyncram_component.width_byteena_a = 1;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ADDRESSSTALL_A NUMERIC "0"
// Retrieval info: PRIVATE: AclrAddr NUMERIC "0"
// Retrieval info: PRIVATE: AclrByte NUMERIC "0"
// Retrieval info: PRIVATE: AclrOutput NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_SIZE NUMERIC "8"
// Retrieval info: PRIVATE: BlankMemory NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: Clken NUMERIC "0"
// Retrieval info: PRIVATE: IMPLEMENT_IN_LES NUMERIC "0"
// Retrieval info: PRIVATE: INIT_FILE_LAYOUT STRING "PORT_A"
// Retrieval info: PRIVATE: INIT_TO_SIM_X NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "0"
// Retrieval info: PRIVATE: JTAG_ID STRING "NONE"
// Retrieval info: PRIVATE: MAXIMUM_DEPTH NUMERIC "0"
// Retrieval info: PRIVATE: MIFfilename STRING "fir_coeffs_rom.hex"
// Retrieval info: PRIVATE: NUMWORDS_A NUMERIC "256"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "0"
// Retrieval info: PRIVATE: RegAddr NUMERIC "1"
// Retrieval info: PRIVATE: RegOutput NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: SingleClock NUMERIC "1"
// Retrieval info: PRIVATE: UseDQRAM NUMERIC "0"
// Retrieval info: PRIVATE: WidthAddr NUMERIC "8"
// Retrieval info: PRIVATE: WidthData NUMERIC "24"
// Retrieval info: PRIVATE: rden NUMERIC "0"
// Retrieval info: CONSTANT: ADDRESS_ACLR_A STRING "NONE"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_OUTPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: INIT_FILE STRING "fir_coeffs_rom.hex"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: LPM_HINT STRING "ENABLE_RUNTIME_MOD=NO"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altsyncram"
// Retrieval info: CONSTANT: NUMWORDS_A NUMERIC "256"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "ROM"
// Retrieval info: CONSTANT: OUTDATA_ACLR_A STRING "NONE"
// Retrieval info: CONSTANT: OUTDATA_REG_A STRING "CLOCK0"
// Retrieval info: CONSTANT: WIDTHAD_A NUMERIC "8"
// Retrieval info: CONSTANT: WIDTH_A NUMERIC "24"
// Retrieval info: CONSTANT: WIDTH_BYTEENA_A NUMERIC "1"
// Retrieval info: USED_PORT: address 0 0 8 0 INPUT NODEFVAL address[7..0]
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT NODEFVAL clock
// Retrieval info: USED_PORT: q 0 0 24 0 OUTPUT NODEFVAL q[23..0]
// Retrieval info: CONNECT: @address_a 0 0 8 0 address 0 0 8 0
// Retrieval info: CONNECT: q 0 0 24 0 @q_a 0 0 24 0
// Retrieval info: CONNECT: @clock0 0 0 0 0 clock 0 0 0 0
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom_inst.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom_bb.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom_waveforms.html TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL fir_coeffs_rom_wave*.jpg FALSE
// Retrieval info: LIB_FILE: altera_mf
// megafunction wizard: %RAM: 2-PORT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsyncram 

// ============================================================
// File Name: memcic_ram.v
// Megafunction Name(s):
// 			altsyncram
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 7.2 Build 207 03/18/2008 SP 3 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2007 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module qs1r_memcic_ram (
	clock,
	data,
	rdaddress,
	wraddress,
	wren,
	q);

	input	  clock;
	input	[71:0]  data;
	input	[4:0]  rdaddress;
	input	[4:0]  wraddress;
	input	  wren;
	output	[71:0]  q;

	wire [71:0] sub_wire0;
	wire [71:0] q = sub_wire0[71:0];

/*
	altsyncram	altsyncram_component (
				.wren_a (wren),
				.clock0 (clock),
				.address_a (wraddress),
				.address_b (rdaddress),
				.data_a (data),
				.q_b (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({72{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 32,
		altsyncram_component.numwords_b = 32,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "CLOCK0",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = 5,
		altsyncram_component.widthad_b = 5,
		altsyncram_component.width_a = 72,
		altsyncram_component.width_b = 72,
		altsyncram_component.width_byteena_a = 1;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ADDRESSSTALL_A NUMERIC "0"
// Retrieval info: PRIVATE: ADDRESSSTALL_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_SIZE NUMERIC "8"
// Retrieval info: PRIVATE: BlankMemory NUMERIC "1"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLRdata NUMERIC "0"
// Retrieval info: PRIVATE: CLRq NUMERIC "0"
// Retrieval info: PRIVATE: CLRrdaddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRrren NUMERIC "0"
// Retrieval info: PRIVATE: CLRwraddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRwren NUMERIC "0"
// Retrieval info: PRIVATE: Clock NUMERIC "0"
// Retrieval info: PRIVATE: Clock_A NUMERIC "0"
// Retrieval info: PRIVATE: Clock_B NUMERIC "0"
// Retrieval info: PRIVATE: ECC NUMERIC "0"
// Retrieval info: PRIVATE: IMPLEMENT_IN_LES NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: INIT_FILE_LAYOUT STRING "PORT_B"
// Retrieval info: PRIVATE: INIT_TO_SIM_X NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "0"
// Retrieval info: PRIVATE: JTAG_ID STRING "NONE"
// Retrieval info: PRIVATE: MAXIMUM_DEPTH NUMERIC "0"
// Retrieval info: PRIVATE: MEMSIZE NUMERIC "2304"
// Retrieval info: PRIVATE: MEM_IN_BITS NUMERIC "0"
// Retrieval info: PRIVATE: MIFfilename STRING ""
// Retrieval info: PRIVATE: OPERATION_MODE NUMERIC "2"
// Retrieval info: PRIVATE: OUTDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: OUTDATA_REG_B NUMERIC "1"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "0"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_MIXED_PORTS NUMERIC "2"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_A NUMERIC "3"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_B NUMERIC "3"
// Retrieval info: PRIVATE: REGdata NUMERIC "1"
// Retrieval info: PRIVATE: REGq NUMERIC "1"
// Retrieval info: PRIVATE: REGrdaddress NUMERIC "1"
// Retrieval info: PRIVATE: REGrren NUMERIC "1"
// Retrieval info: PRIVATE: REGwraddress NUMERIC "1"
// Retrieval info: PRIVATE: REGwren NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: USE_DIFF_CLKEN NUMERIC "0"
// Retrieval info: PRIVATE: UseDPRAM NUMERIC "1"
// Retrieval info: PRIVATE: VarWidth NUMERIC "0"
// Retrieval info: PRIVATE: WIDTH_READ_A NUMERIC "72"
// Retrieval info: PRIVATE: WIDTH_READ_B NUMERIC "72"
// Retrieval info: PRIVATE: WIDTH_WRITE_A NUMERIC "72"
// Retrieval info: PRIVATE: WIDTH_WRITE_B NUMERIC "72"
// Retrieval info: PRIVATE: WRADDR_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: WRADDR_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: WRCTRL_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: enable NUMERIC "0"
// Retrieval info: PRIVATE: rden NUMERIC "0"
// Retrieval info: CONSTANT: ADDRESS_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: ADDRESS_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_OUTPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altsyncram"
// Retrieval info: CONSTANT: NUMWORDS_A NUMERIC "32"
// Retrieval info: CONSTANT: NUMWORDS_B NUMERIC "32"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "DUAL_PORT"
// Retrieval info: CONSTANT: OUTDATA_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: OUTDATA_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: POWER_UP_UNINITIALIZED STRING "FALSE"
// Retrieval info: CONSTANT: READ_DURING_WRITE_MODE_MIXED_PORTS STRING "DONT_CARE"
// Retrieval info: CONSTANT: WIDTHAD_A NUMERIC "5"
// Retrieval info: CONSTANT: WIDTHAD_B NUMERIC "5"
// Retrieval info: CONSTANT: WIDTH_A NUMERIC "72"
// Retrieval info: CONSTANT: WIDTH_B NUMERIC "72"
// Retrieval info: CONSTANT: WIDTH_BYTEENA_A NUMERIC "1"
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT NODEFVAL clock
// Retrieval info: USED_PORT: data 0 0 72 0 INPUT NODEFVAL data[71..0]
// Retrieval info: USED_PORT: q 0 0 72 0 OUTPUT NODEFVAL q[71..0]
// Retrieval info: USED_PORT: rdaddress 0 0 5 0 INPUT NODEFVAL rdaddress[4..0]
// Retrieval info: USED_PORT: wraddress 0 0 5 0 INPUT NODEFVAL wraddress[4..0]
// Retrieval info: USED_PORT: wren 0 0 0 0 INPUT VCC wren
// Retrieval info: CONNECT: @data_a 0 0 72 0 data 0 0 72 0
// Retrieval info: CONNECT: @wren_a 0 0 0 0 wren 0 0 0 0
// Retrieval info: CONNECT: q 0 0 72 0 @q_b 0 0 72 0
// Retrieval info: CONNECT: @address_a 0 0 5 0 wraddress 0 0 5 0
// Retrieval info: CONNECT: @address_b 0 0 5 0 rdaddress 0 0 5 0
// Retrieval info: CONNECT: @clock0 0 0 0 0 clock 0 0 0 0
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram_bb.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram_waveforms.html TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL memcic_ram_wave*.jpg FALSE
// Retrieval info: LIB_FILE: altera_mf
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------


//multiply-accumulate 256 24-bit signed values
//output width = 24*2 + Log2(256) = 56 bit


module qs1r_fir_mac(
  input clock,
  input clear,
  input signed [23:0] in_data_1,
  input signed [23:0] in_data_2,
  output reg signed [55:0] out_data
  );
wire signed [47:0] product;

always @(posedge clock)
  if (clear) out_data <= 0;
  else out_data <= out_data + product;


//pipelined multiplier: throughput = 1, latency = 3
qs1r_mult_24Sx24S mult_24Sx24S_inst(
  .aclr (clear),
  .clock (clock),
  .dataa (in_data_1),
  .datab (in_data_2),
  .result (product)
  );

endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------



/*
--------------------------------------------------------------------------------
Memory-based CIC decimator
--------------------------------------------------------------------------------
memory: 2 x M9K blocks
input 24-bit
output 24-bit
internal registers 72-bit
decimation <= 255
stages <= 16
F_in_strobe <= F_clock / (2*stages + 5)
in_strobe length = 1 clock cycle
--------------------------------------------------------------------------------
*/


module qs1r_memcic(
  input clock,
  input in_strobe,
  output reg out_strobe,
  input signed [23:0] in_data,
  output reg signed [23:0] out_data 
  );


parameter STAGES = 11;
parameter DECIMATION = 20; 
parameter ACC_WIDTH = 72; //must be <= 72

localparam MSB = ACC_WIDTH - 1;
localparam LSB = ACC_WIDTH - 24;




//------------------------------------------------------------------------------
//                             control regs
//------------------------------------------------------------------------------
reg [2:0] state;
wire is_comb = state[2];

reg [3:0] rdaddress; 
reg [3:0] wraddress; 
reg wren;
reg [7:0] sample_no;


initial
  begin
  state = 0;
  sample_no = 0;
  rdaddress = 0;
  wraddress = 0;
  wren = 0;
  out_strobe = 0; 
  end






//------------------------------------------------------------------------------
//                             computations
//------------------------------------------------------------------------------
reg signed [ACC_WIDTH-1:0] work_reg;


wire signed [ACC_WIDTH-1:0] new_intg_value = work_reg + ram_output;
wire signed [ACC_WIDTH-1:0] new_comb_value = work_reg - ram_output;


wire signed [ACC_WIDTH-1:0] ram_input = is_comb ? work_reg : new_intg_value;
wire signed [ACC_WIDTH-1:0] ram_output;

wire [71:ACC_WIDTH] zeros = 0;




//------------------------------------------------------------------------------
//                                 loop
//------------------------------------------------------------------------------
always @(posedge clock)
  case (state)

    //integrators
    //-----------

    0:                                
      begin
      out_strobe <= 0;

      if (in_strobe)
        begin
        work_reg <= in_data;
        rdaddress <= 1;
        state <= 1;
        end
      end

    1:                                
      begin
      rdaddress <= 2;
      wraddress <= 0;
      wren <= 1;
      state <= 2;
      end

    2:                                
      begin
      work_reg <= new_intg_value; 

      if (wraddress < (STAGES-1))
        begin
        rdaddress <= rdaddress + 4'd1;
        wraddress <= wraddress + 4'd1;
        end
      else
        begin
        wren <= 0;
        rdaddress <= 0;

        if (sample_no < (DECIMATION-1)) 
            begin 
            sample_no <= sample_no + 8'd1; 
            state <= 0;
            end
          else 
            begin 
            sample_no <= 0;
            state <= 4;
            end
        end
      end 


    //combs
    //-----

    4:
      begin
      rdaddress <= 1;
      state <= 5;
      end

    5:                               
      begin
      rdaddress <= 2;
      wraddress <= 0;
      wren <= 1;
      state <= 6;     
      end

    6:
      begin
      work_reg <= new_comb_value;

      if (wraddress < (STAGES-1))
        begin
        rdaddress <= rdaddress + 4'd1;
        wraddress <= wraddress + 4'd1;
        end
      else
        begin
        wren <= 0;
        state <= 7;
        end
      end

    7:
      begin
      out_data <= work_reg[MSB:LSB] + work_reg[LSB-1];
      out_strobe <= 1;
      rdaddress <= 0;
      state <= 0;
      end

    endcase






//------------------------------------------------------------------------------
//                                    RAM 
//------------------------------------------------------------------------------
//ram output data are available 3 cycles after the address counter change
//if ACC_WIDTH < 72, a few high bits of q() will be left dongling
qs1r_memcic_ram	memcic_ram_inst(
  .clock(clock),
  .rdaddress({is_comb, rdaddress}),
  .wraddress({is_comb, wraddress}),
  .wren(wren),
  .data({zeros, ram_input}),
  .q(ram_output)
  );



endmodule

/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------


//If you make any changes to this file, please leave a comment here





module qs1r_receiver(
  input clock,                  //122.88 MHz
  input [1:0] rate,             //00=48, 01=96, 10=192 kHz
  input [31:0] frequency,
  output out_strobe,

  input signed [15:0] in_data,

  output [23:0] out_data_I,
  output [23:0] out_data_Q
  );


  
  
  
  
//------------------------------------------------------------------------------
//                               cordic
//------------------------------------------------------------------------------
qs1r_cordic cordic_inst(
  .clock(clock),
  .in_data(in_data),             //16 bit 
  .frequency(frequency),         //32 bit
  .out_data_I(cordic_outdata_I), //22 bit
  .out_data_Q(cordic_outdata_Q)
  );
 

wire signed [21:0] cordic_outdata_I;
wire signed [21:0] cordic_outdata_Q;
  

  
  
  
  
//------------------------------------------------------------------------------
//         register-based CIC decimator #1, decimation factor 32/64/128
//------------------------------------------------------------------------------
//I channel
qs1r_varcic #(.STAGES(4), .DECIMATION(20), .IN_WIDTH(22), .ACC_WIDTH(50), .OUT_WIDTH(24))
  varcic_inst_I1(
    .clock(clock),
    .in_strobe(1'b1),
    .extra_decimation(rate),
    .out_strobe(cic_outstrobe_1),
    .in_data(cordic_outdata_I),
    .out_data(cic_outdata_I1)
    );


//Q channel
qs1r_varcic #(.STAGES(4), .DECIMATION(20), .IN_WIDTH(22), .ACC_WIDTH(50), .OUT_WIDTH(24))
  varcic_inst_Q1(
    .clock(clock),
    .in_strobe(1'b1),
    .extra_decimation(rate),
    .out_strobe(),
    .in_data(cordic_outdata_Q),
    .out_data(cic_outdata_Q1)
    );


wire cic_outstrobe_1;
wire signed [23:0] cic_outdata_I1;
wire signed [23:0] cic_outdata_Q1;






//------------------------------------------------------------------------------
//            memory-based CIC decimator #2, decimation factor 10
//------------------------------------------------------------------------------
//I channel
qs1r_memcic #(.STAGES(13), .DECIMATION(10), .ACC_WIDTH(68)) 
  memcic_inst_I(
    .clock(clock),
    .in_strobe(cic_outstrobe_1),
    .out_strobe(cic_outstrobe_2),
    .in_data(cic_outdata_I1),
    .out_data(cic_outdata_I2)
    );
	 

//Q channel
qs1r_memcic #(.STAGES(13), .DECIMATION(10), .ACC_WIDTH(68)) 
  memcic_inst_Q(
    .clock(clock),
    .in_strobe(cic_outstrobe_1),
    .out_strobe(),
    .in_data(cic_outdata_Q1),
    .out_data(cic_outdata_Q2)
    );
	 
	 
wire cic_outstrobe_2;
wire signed [23:0] cic_outdata_I2;
wire signed [23:0] cic_outdata_Q2;
	 

	 
	 
	 
	 
//------------------------------------------------------------------------------
//                     FIR coefficients and sequencing
//------------------------------------------------------------------------------
wire signed [23:0] fir_coeff;

qs1r_fir_coeffs fir_coeffs_inst(
  .clock(clock),
  .start(cic_outstrobe_2),
  .coeff(fir_coeff)
  );


  
  
  
  
//------------------------------------------------------------------------------
//                            FIR decimator
//------------------------------------------------------------------------------
qs1r_fir #(.OUT_WIDTH(24))
  fir_inst_I(
    .clock(clock),
    .start(cic_outstrobe_2), 
    .coeff(fir_coeff),
    .in_data(cic_outdata_I2),
    .out_data(out_data_I),
    .out_strobe(out_strobe)
    );


qs1r_fir #(.OUT_WIDTH(24))
  fir_inst_Q(
    .clock(clock),
    .start(cic_outstrobe_2),
    .coeff(fir_coeff),
    .in_data(cic_outdata_Q2),
    .out_data(out_data_Q),
    .out_strobe()
    );



endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------



module cic_comb( clock, strobe,  in_data,  out_data );

parameter WIDTH = 64;

input clock;
input strobe;
input signed [WIDTH-1:0] in_data;
output reg signed [WIDTH-1:0] out_data;

reg signed [WIDTH-1:0] prev_data = 0;

always @(posedge clock)  
  if (strobe) 
    begin
    out_data <= in_data - prev_data;
    prev_data <= in_data;
    end



endmodule
/*
--------------------------------------------------------------------------------
This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.
You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the
Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
Boston, MA  02110-1301, USA.
--------------------------------------------------------------------------------
*/


//------------------------------------------------------------------------------
//           Copyright (c) 2008 Alex Shovkoplyas, VE3NEA
//------------------------------------------------------------------------------



module cic_integrator( clock, strobe, in_data,  out_data );

parameter WIDTH = 64;

input clock;
input strobe;
input signed [WIDTH-1:0] in_data;
output reg signed [WIDTH-1:0] out_data = 0;

always @(posedge clock)
  if (strobe) out_data <= out_data + in_data;

endmodule
// megafunction wizard: %RAM: 2-PORT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: altsyncram 

// ============================================================
// File Name: firram36I_205.v
// Megafunction Name(s):
// 			altsyncram
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 16.1.2 Build 203 01/18/2017 SJ Lite Edition
// ************************************************************


//Copyright (C) 2017  Intel Corporation. All rights reserved.
//Your use of Intel Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Intel Program License 
//Subscription Agreement, the Intel Quartus Prime License Agreement,
//the Intel MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Intel and sold by Intel or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module firram36I_205 (
	clock,
	data,
	rdaddress,
	wraddress,
	wren,
	q);

	input	  clock;
	input	[35:0]  data;
	input	[7:0]  rdaddress;
	input	[7:0]  wraddress;
	input	  wren;
	output	[35:0]  q;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri1	  clock;
	tri0	  wren;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [35:0] sub_wire0;
	wire [35:0] q = sub_wire0[35:0];
/*
	altsyncram	altsyncram_component (
				.address_a (wraddress),
				.address_b (rdaddress),
				.clock0 (clock),
				.data_a (data),
				.wren_a (wren),
				.q_b (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({36{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 205,
		altsyncram_component.numwords_b = 205,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "CLOCK0",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = 8,
		altsyncram_component.widthad_b = 8,
		altsyncram_component.width_a = 36,
		altsyncram_component.width_b = 36,
		altsyncram_component.width_byteena_a = 1;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: ADDRESSSTALL_A NUMERIC "0"
// Retrieval info: PRIVATE: ADDRESSSTALL_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTEENA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_A NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_ENABLE_B NUMERIC "0"
// Retrieval info: PRIVATE: BYTE_SIZE NUMERIC "9"
// Retrieval info: PRIVATE: BlankMemory NUMERIC "1"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_INPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_A NUMERIC "0"
// Retrieval info: PRIVATE: CLOCK_ENABLE_OUTPUT_B NUMERIC "0"
// Retrieval info: PRIVATE: CLRdata NUMERIC "0"
// Retrieval info: PRIVATE: CLRq NUMERIC "0"
// Retrieval info: PRIVATE: CLRrdaddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRrren NUMERIC "0"
// Retrieval info: PRIVATE: CLRwraddress NUMERIC "0"
// Retrieval info: PRIVATE: CLRwren NUMERIC "0"
// Retrieval info: PRIVATE: Clock NUMERIC "0"
// Retrieval info: PRIVATE: Clock_A NUMERIC "0"
// Retrieval info: PRIVATE: Clock_B NUMERIC "0"
// Retrieval info: PRIVATE: IMPLEMENT_IN_LES NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: INDATA_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: INIT_FILE_LAYOUT STRING "PORT_B"
// Retrieval info: PRIVATE: INIT_TO_SIM_X NUMERIC "0"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: JTAG_ENABLED NUMERIC "0"
// Retrieval info: PRIVATE: JTAG_ID STRING "NONE"
// Retrieval info: PRIVATE: MAXIMUM_DEPTH NUMERIC "0"
// Retrieval info: PRIVATE: MEMSIZE NUMERIC "7380"
// Retrieval info: PRIVATE: MEM_IN_BITS NUMERIC "0"
// Retrieval info: PRIVATE: MIFfilename STRING ""
// Retrieval info: PRIVATE: OPERATION_MODE NUMERIC "2"
// Retrieval info: PRIVATE: OUTDATA_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: OUTDATA_REG_B NUMERIC "1"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "0"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_MIXED_PORTS NUMERIC "2"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_A NUMERIC "3"
// Retrieval info: PRIVATE: READ_DURING_WRITE_MODE_PORT_B NUMERIC "3"
// Retrieval info: PRIVATE: REGdata NUMERIC "1"
// Retrieval info: PRIVATE: REGq NUMERIC "1"
// Retrieval info: PRIVATE: REGrdaddress NUMERIC "1"
// Retrieval info: PRIVATE: REGrren NUMERIC "1"
// Retrieval info: PRIVATE: REGwraddress NUMERIC "1"
// Retrieval info: PRIVATE: REGwren NUMERIC "1"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: USE_DIFF_CLKEN NUMERIC "0"
// Retrieval info: PRIVATE: UseDPRAM NUMERIC "1"
// Retrieval info: PRIVATE: VarWidth NUMERIC "0"
// Retrieval info: PRIVATE: WIDTH_READ_A NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_READ_B NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_WRITE_A NUMERIC "36"
// Retrieval info: PRIVATE: WIDTH_WRITE_B NUMERIC "36"
// Retrieval info: PRIVATE: WRADDR_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: WRADDR_REG_B NUMERIC "0"
// Retrieval info: PRIVATE: WRCTRL_ACLR_B NUMERIC "0"
// Retrieval info: PRIVATE: enable NUMERIC "0"
// Retrieval info: PRIVATE: rden NUMERIC "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: ADDRESS_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: ADDRESS_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_A STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_INPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: CLOCK_ENABLE_OUTPUT_B STRING "BYPASS"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altsyncram"
// Retrieval info: CONSTANT: NUMWORDS_A NUMERIC "205"
// Retrieval info: CONSTANT: NUMWORDS_B NUMERIC "205"
// Retrieval info: CONSTANT: OPERATION_MODE STRING "DUAL_PORT"
// Retrieval info: CONSTANT: OUTDATA_ACLR_B STRING "NONE"
// Retrieval info: CONSTANT: OUTDATA_REG_B STRING "CLOCK0"
// Retrieval info: CONSTANT: POWER_UP_UNINITIALIZED STRING "FALSE"
// Retrieval info: CONSTANT: READ_DURING_WRITE_MODE_MIXED_PORTS STRING "DONT_CARE"
// Retrieval info: CONSTANT: WIDTHAD_A NUMERIC "8"
// Retrieval info: CONSTANT: WIDTHAD_B NUMERIC "8"
// Retrieval info: CONSTANT: WIDTH_A NUMERIC "36"
// Retrieval info: CONSTANT: WIDTH_B NUMERIC "36"
// Retrieval info: CONSTANT: WIDTH_BYTEENA_A NUMERIC "1"
// Retrieval info: USED_PORT: clock 0 0 0 0 INPUT VCC "clock"
// Retrieval info: USED_PORT: data 0 0 36 0 INPUT NODEFVAL "data[35..0]"
// Retrieval info: USED_PORT: q 0 0 36 0 OUTPUT NODEFVAL "q[35..0]"
// Retrieval info: USED_PORT: rdaddress 0 0 8 0 INPUT NODEFVAL "rdaddress[7..0]"
// Retrieval info: USED_PORT: wraddress 0 0 8 0 INPUT NODEFVAL "wraddress[7..0]"
// Retrieval info: USED_PORT: wren 0 0 0 0 INPUT GND "wren"
// Retrieval info: CONNECT: @address_a 0 0 8 0 wraddress 0 0 8 0
// Retrieval info: CONNECT: @address_b 0 0 8 0 rdaddress 0 0 8 0
// Retrieval info: CONNECT: @clock0 0 0 0 0 clock 0 0 0 0
// Retrieval info: CONNECT: @data_a 0 0 36 0 data 0 0 36 0
// Retrieval info: CONNECT: @wren_a 0 0 0 0 wren 0 0 0 0
// Retrieval info: CONNECT: q 0 0 36 0 @q_b 0 0 36 0
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_205.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_205.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_205.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_205.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_205_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL firram36I_205_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.


module rgmii_send (
  input [7:0] data,
  input tx_enable,
  output active,
  input clock,

  //hardware pins
  output [3:0]PHY_TX,
  output PHY_TX_EN
  );



//-----------------------------------------------------------------------------
//                            shift reg
//-----------------------------------------------------------------------------
localparam PREAMBLE_BYTES = 64'h55555555555555D5;
localparam PREAMB_LEN = 4'd8;
localparam HI_BIT = 8*PREAMB_LEN - 1;
reg [HI_BIT:0] shift_reg;
reg [3:0] bytes_left;






//-----------------------------------------------------------------------------
//                           state machine
//-----------------------------------------------------------------------------
localparam ST_IDLE = 1, ST_SEND = 2, ST_GAP = 4;
reg [2:0] state = ST_IDLE;


wire sending = tx_enable | (state == ST_SEND);
assign active = sending | (state == ST_GAP);


always @(posedge clock)
  begin
  if (sending) shift_reg <= {shift_reg[HI_BIT-8:0], data};
  else shift_reg <= PREAMBLE_BYTES;

  case (state)
    ST_IDLE:
      //receiving the first payload byte
      if (tx_enable) state <= ST_SEND;

    ST_SEND:
      //receiving payload data
      if (tx_enable) bytes_left <= PREAMB_LEN - 4'd1;
      //purging shift register
      else if (bytes_left != 0) bytes_left <= bytes_left - 4'd1;
      //starting inter-frame gap
      else begin bytes_left <= 4'd12; state <= ST_GAP; end

    ST_GAP:
      if (bytes_left != 0) bytes_left <= bytes_left - 4'd1;
      else state <= ST_IDLE;
    endcase
  end






//-----------------------------------------------------------------------------
//                             output
//-----------------------------------------------------------------------------
ddio_out	ddio_out_inst (
	.datain_h({sending, shift_reg[HI_BIT-4 -: 4]}),
	.datain_l({sending, shift_reg[HI_BIT -: 4]}),
	.outclock(clock),
	.dataout({PHY_TX_EN, PHY_TX})
	);




endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Phil Harman VK6APH, Alex Shovkoplyas, VE3NEA.


module udp_send (
  input reset,
  input clock,
  input tx_enable,
  input [7:0] data_in,
  input [15:0] length_in,
  input [15:0] local_port,
  input [15:0] destination_port,
  input [7:0] port_ID,				// determines offset from port base address of 1024
 // input [47:0] remote_mac,
 // input [31:0] remote_ip,
  output active,
  output [7:0] data_out,
  output [15:0] length_out
 // output reg [47:0] destination_mac,
//  output reg [31:0] destination_ip
  );


//udp header
localparam HDR_LEN = 16'd8;
localparam HI_BIT = HDR_LEN * 8 - 1;
assign length_out = HDR_LEN + length_in;
wire [15:0] checksum = 16'b0;						// no checksum needed with IP4
wire [HI_BIT:0] tx_bits = {(local_port + {8'd0,port_ID}), destination_port, length_out, checksum};

//shift reg
reg [HI_BIT:0] shift_reg;
assign data_out = shift_reg[HI_BIT -: 8];
reg [15:0] byte_no;

//state machine
localparam false = 1'b0, true = 1'b1;
reg sending = false;

always @(posedge clock)
  begin
  //tx data
  if (active) begin
	//	destination_mac <= remote_mac;
	//	destination_ip  <= remote_ip;
		shift_reg <= {shift_reg[HI_BIT-8:0], data_in};
  end
  else shift_reg <= tx_bits;
  //send while payload is coming
  if (tx_enable) begin
    byte_no <= length_in + 16'd7; //length_out -16'd1;
    sending <= true; end
  //purge shift register
  else if (byte_no != 0) byte_no <= byte_no - 15'd1;
  //done
  else sending <= false;
  end


assign active = (tx_enable | sending) && (byte_no != 0) ;  //last term prevents one too many bytes being sent



endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Phil Harman VK6APH
//  April 2016, N2ADR: Added xid, dhcp_seconds_timer


module dhcp (
  //rx in
  input rx_clock,
  input [7:0] rx_data,
  input rx_enable,
  input dhcp_rx_active,
  //rx out
  output reg [31:0] lease,      // DHCP supplied lease time in seconds
  output reg [31:0] server_ip,   // IP address of DHCP server

  //tx in
  input reset,
  input tx_clock,
  input udp_tx_enable,
  input tx_enable,
  input udp_tx_active,
  input [47:0] remote_mac,
  input [31:0] remote_ip,
  input [3:0] dhcp_seconds_timer,
  //tx out
  output reg dhcp_tx_request,
  output reg[7:0] tx_data,
  output reg [15:0] length,
  output reg[31:0] ip_accept,
  output reg dhcp_success,
  output reg dhcp_failed,

  //constants
  input [47:0] local_mac,
  output [47:0] dhcp_destination_mac,
  output [31:0] dhcp_destination_ip,
  output [15:0] dhcp_destination_port


  );

localparam TX_IDLE = 8'd0, DHCPDISCOVER = 8'd1, DHCPSEND = 8'd2, DHCPOFFER = 8'd3, DHCPREQUEST = 8'd4, DHCPRENEW = 8'd5;
localparam RX_IDLE = 8'd0, RX_OFFER_ACK = 8'd1, RX_DONE = 8'd2;

localparam DIS_TX_LEN = 16'd244;    // length of discover message
localparam REQ_TX_LEN = 16'd256;    // length of request message for boot (starting) state
localparam RENEW_TX_LEN = 16'd250;    // length of request message for lease renewal

reg [8:0] byte_no;
reg tx_request;
reg send_discovery;
reg is_renewal = 1'b0;    // Are we renewing the lease?
reg [8:0] state = TX_IDLE;

reg [47:0] destination_mac = 48'hFFFFFFFFFFFF;
reg [31:0] destination_ip = 32'hFFFFFFFF;
assign dhcp_destination_mac = destination_mac;
assign dhcp_destination_ip = destination_ip;

reg [15:0] xid_sum;    // random-ish number, constant after the first DHCP Discover
reg xid_done = 0;
wire [7:0] xid0, xid1, xid2, xid3;
assign xid0 = local_mac[15:8];  // this is the final transaction ID
assign xid1 = local_mac[7:0];
assign xid2 = xid_sum[15:8];
assign xid3 = xid_sum[7:0];

//---------------------------------------------------------------
//                DHCP Send
//---------------------------------------------------------------

always @ (posedge tx_clock)
begin
  case (state)
  TX_IDLE:
    begin
    if ( ! xid_done)
      xid_sum <= xid_sum + 1'd1;
    byte_no <= 9'b1;
    dhcp_tx_request <= 1'b0;
    send_discovery <= 1'b0;
      if (tx_enable) begin
        if (is_renewal)
          state <= DHCPRENEW;
        else
          state <= DHCPDISCOVER;
      end
      else if (send_request) state <= DHCPREQUEST;
    end

  DHCPDISCOVER:
    begin
    xid_done <= 1'b1;
    length <= DIS_TX_LEN;
    dhcp_tx_request <= 1'b1;
      if (udp_tx_enable) begin
        tx_data <= 8'h01;          // tx_data needs to be available before udp_tx_active
        send_discovery <= 1'b1;      // hence this is byte_no 0
        state <= DHCPSEND;
      end
    end

  DHCPREQUEST:
    begin
    length <= REQ_TX_LEN;
    dhcp_tx_request <= 1'b1;
      if (udp_tx_enable) begin      // tx_data needs to be available before udp_tx_active
        tx_data <= 8'h01;          // hence this is byte_no 0
        state <= DHCPSEND;
      end
    end

  DHCPRENEW:
    begin
    length <= RENEW_TX_LEN;
    dhcp_tx_request <= 1'b1;
      if (udp_tx_enable) begin      // tx_data needs to be available before udp_tx_active
        tx_data <= 8'h01;          // hence this is byte_no 0
        state <= DHCPSEND;
      end
    end

  DHCPSEND:
    begin
      if (byte_no < length) begin
        if (udp_tx_active) begin
          case (byte_no)
          1: tx_data <= 8'h01;
          2: tx_data <= 8'h06;
          3: tx_data <= 8'h0;
          4: tx_data <= xid0;
          5: tx_data <= xid1;
          6: tx_data <= xid2;
          7: tx_data <= xid3;
          8: tx_data <= 8'd0;
          9: tx_data <= {4'd0, dhcp_seconds_timer};
          10: tx_data <= 8'd0;    // 2 zeros
          12: tx_data <= is_renewal ? ip_accept[31:24] : 8'd0;    // ciaddr
          13: tx_data <= is_renewal ? ip_accept[23:16] : 8'd0;
          14: tx_data <= is_renewal ? ip_accept[15:8]  : 8'd0;
          15: tx_data <= is_renewal ? ip_accept[7:0]   : 8'd0;
          16: tx_data <= 8'd0;    // 12 zeros
          28: tx_data <= local_mac[47:40];    // chaddr
          29: tx_data <= local_mac[39:32];
          30: tx_data <= local_mac[31:24];
          31: tx_data <= local_mac[23:16];
          32: tx_data <= local_mac[15:8];
          33: tx_data <= local_mac[7:0];
          34: tx_data <= 8'd0;    // 202  zeros
         236: tx_data <= 8'h63;
         237: tx_data <= 8'h82;
         238: tx_data <= 8'h53;
         239: tx_data <= 8'h63;
         240: tx_data <= 8'h35;
         241: tx_data <= 8'h01;
         242: tx_data <= send_discovery ? 8'h01 : 8'h03;
         243: tx_data <= send_discovery ? 8'hFF : 8'h32;  // send discovery ends here
         244: tx_data <= 8'h04;                // start of REQUEST
         245: tx_data <= ip_accept[31:24];    // Requested IP
         246: tx_data <= ip_accept[23:16];
         247: tx_data <= ip_accept[15:8];
         248: tx_data <= ip_accept[7:0];
         249: tx_data <= is_renewal ? 8'hFF : 8'h36;    // Renewal Request ends here
         250: tx_data <= 8'h04;    // Original Request requires the Server Identifier
         251: tx_data <= remote_ip[31:24];
         252: tx_data <= remote_ip[23:16];
         253: tx_data <= remote_ip[15:8];
         254: tx_data <= remote_ip[7:0];
         255: tx_data <= 8'hFF;
        endcase
        byte_no <= byte_no + 9'd1;
       end
       end
    else  state <= TX_IDLE;     // all data sent so return to start
     end
  endcase
end

//-----------------------------------------------------------------------------
//                               output
//-----------------------------------------------------------------------------
assign dhcp_destination_port = 16'd67;

//--------------------------------------------------------------------
//                Transfer data from rx to tx clock domains
//--------------------------------------------------------------------
wire send_request;
sync sync_inst1(.clock(tx_clock), .sig_in(rx_send_request), .sig_out(send_request));



//---------------------------------------------------------------
//                DHCP Receive
//---------------------------------------------------------------
reg [8:0]  rx_state;
reg [8:0]  rx_byte_no;
reg rx_send_request;        // in rx_clock domain
reg [47:0] target_mac;
reg [47:0] temp_target_mac;
reg [15:0] option;        // holds DHCP options
reg [7:0]  skip;          // number of DHCP option bytes to skip
reg [31:0] temp_ip_accept;



always @ (posedge rx_clock)
begin
 if (state == DHCPSEND) rx_send_request <= 1'b0;   // Only clear send request when tx has seen it

 if (dhcp_rx_active && rx_enable)
    case (rx_state)
      RX_IDLE:
      begin
      rx_byte_no <= 9'd1;
        if (rx_data == 8'h02) begin         // look for udp packet type of 0x02
            rx_state <= RX_OFFER_ACK;
        end
      end

    RX_OFFER_ACK:
      begin
        case (rx_byte_no)
              4: begin  // Accept only our own transaction ID
                  if (rx_data != xid0) rx_state <= RX_DONE;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                end

              5: begin
                  if (rx_data != xid1) rx_state <= RX_DONE;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                end

              6: begin
                  if (rx_data != xid2) rx_state <= RX_DONE;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                end

              7: begin
                  if (rx_data != xid3) rx_state <= RX_DONE;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                end

//// whilst this works, and takes less LEs, but the negative slack is worse.
//        16,17,18,19: begin
//                  temp_ip_accept <= {temp_ip_accept[31-8:20],rx_data};
//                  rx_byte_no <=  rx_byte_no + 9'd1;
//                 end
              16: begin
                  temp_ip_accept[31:24] <= rx_data;      // get the offered IP address
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end

              17: begin
                  temp_ip_accept[23:16] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end

              18: begin
                  temp_ip_accept[15:8] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end

              19: begin
                  temp_ip_accept[7:0] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
// whilst this works, and takes less LEs, but the negative slack is worse.
//    28,29,30,31,32,33: begin
//                  if (rx_data != target_mac[271-8*rx_byte_no-:8]) rx_state <= RX_DONE;
//                  else rx_byte_no <=  rx_byte_no + 9'd1;
//                 end
//              34: begin
//                  ip_accept <= temp_ip_accept;              // for us so save the offered IP address
//                  rx_byte_no <=  rx_byte_no + 9'd1;
//                 end
                //compare target mac to our local_mac
              28: begin
                  target_mac[47:40] <= rx_data;        // get the target MAC address
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
              29: begin
                  target_mac[39:32] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
              30: begin
                  target_mac[31:24] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
              31: begin
                  target_mac[23:16] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
              32: begin
                  target_mac[15:8] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
              33: begin
                  target_mac[7:0]  <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
              34: begin
                  if (local_mac != target_mac) rx_state <= RX_DONE;    // not this MAC address so
                  else begin                              // wait for end of packet then re-start
                        ip_accept  <= temp_ip_accept;              // for us so save the offered IP address
                      rx_byte_no <=  rx_byte_no + 9'd1;
                      end
                 end

//          // read next two bytes and look for lease time, DHCP server IP address or end
              240: begin
                  option[15:8] <= rx_data;
                  if (rx_data == 8'hFF) begin // early exit if no padding in ACK
                    dhcp_success <= 1'b1;
                    dhcp_failed  <= 1'b0;
                    is_renewal <= 1'b1;
                    destination_mac <= remote_mac;  // save DHCP server addresses for renewal
                    destination_ip <= remote_ip;
                    rx_state <= RX_IDLE;
                  end else if (rx_data != 8'h00) begin // Handle pad
                    rx_byte_no <=  rx_byte_no + 9'd1;
                  end
                 end
              241: begin
                  option[7:0] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end
              242: begin
                  skip <= option[7:0];              // potentially skip these number of bytes
                  if (option == 16'h3501) begin // dhcp type since can be in any order
                    if(rx_data == 8'h02) begin          // if 0x02 then an offer so request it
                      rx_send_request <= 1'b1;
                      rx_state <= RX_DONE;            // wait until end of data then re-start
                    end
                    else if (rx_data == 8'h05) begin      // a DHCP ACK so read the options
                      rx_byte_no <=  240;
                    end
                    else begin                    // neither, so report a fail
                      dhcp_failed  <= 1'b1;
                      dhcp_success <= 1'b0;
                      rx_state <= RX_DONE;          // wait for end of packet then re-start
                    end
                  end
                  if (option == 16'h3304) begin           // get lease time
                    lease[31:24] <= rx_data;
                    rx_byte_no <= 243;
                  end
                  else if (option == 16'h3604) begin        // get DHCP sever IP address
                    server_ip[31:24] <= rx_data;
                    rx_byte_no <= 246;
                  end
                  else if (option[7:0] == 8'h01) begin // Handle size 1 option case
                    rx_byte_no <= 240;
                  end
                  else begin
                    rx_byte_no <= 249;
                    end
                  end

              243: begin
                  lease[23:16] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end

              244: begin
                  lease[15:8] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end

              245: begin
                  lease[7:0] <= rx_data;
                  rx_byte_no <= 240;
                  end

              246: begin
                  server_ip[23:16] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end

              247: begin
                  server_ip[15:8] <= rx_data;
                  rx_byte_no <=  rx_byte_no + 9'd1;
                 end

              248: begin
                  server_ip[7:0] <= rx_data;
                  rx_byte_no <= 240;
                end

              // we all ready have two 'skips' when we get here
              249: begin
                  if (skip - 2 == 0) rx_byte_no <= 240;      // skip over bytes then look again
                  else skip <= skip - 1'b1;
                end

          default: rx_byte_no <=  rx_byte_no + 9'd1;
        endcase

      end
    default: rx_state <= RX_IDLE;
  endcase

  else begin // !(dhcp_rx_active && rx_enable)
    if (!rx_enable) begin
      dhcp_success <= 1'b0;
      dhcp_failed <= 1'b0;
    end
    rx_state <= RX_IDLE;
  end
end

endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013, 2014 Phil Harman VK6(A)PH, Alex Shovkoplyas, VE3NEA.

module udp_recv(
  //input data stream
  input clock, 
  input rx_enable,
  input [7:0] data,
  input [31:0] to_ip,
  input broadcast,
  input [47:0] remote_mac,
  input [31:0] remote_ip,

  //constant input parameter
  input [31:0] local_ip,

  //output
  output active,
  output dhcp_active,				 
  output reg [15:0] to_port,					// port that data is being sent to.
  output reg [31:0] udp_destination_ip,   
  output reg [47:0] udp_destination_mac,
  output reg [15:0] udp_destination_port
  );

  

  

localparam IDLE = 4'd1, PORT = 4'd2, VERIFY = 4'd3, ST_PAYLOAD = 4'd4, ST_DONE = 4'd5;
reg[3:0] state;
reg [10:0] header_len, packet_len, byte_no;
reg dhcp_data;
reg [15:0] remote_port;

assign active      = rx_enable & (state == ST_PAYLOAD) & !dhcp_data;
assign dhcp_active = rx_enable & (state == ST_PAYLOAD) & dhcp_data;

always @(posedge clock)
  if (rx_enable)
    case (state)
	  IDLE:
        begin
        //save remote port address
        remote_port[15:8] <= data; 
        state <= PORT;
		  dhcp_data <= 1'b0;   
        end
		  
		PORT:
			begin
			remote_port <= {remote_port[15:8], data};
			byte_no <= 11'd3;
			state <= VERIFY;
			end 
	 
      VERIFY:
        begin        
			  case (byte_no)
				 // get the port the packet is addressed to
			    3:  to_port[15:8] <= data;
				 4:  to_port[7:0]  <= data;
			 
	           // verify DHCP, broadcast to port 1024  or the ip address its being sent to then save packet length				 
				 5: begin 
						if (to_port == 16'd68) dhcp_data <= 1'b1;				// check for DHCP data
						else if (broadcast) begin
								if (to_port != 16'd1024) state <= ST_DONE;
						end 
						else if (local_ip != to_ip ) state <= ST_DONE; 			// if not for this  ip then exit
						packet_len[10:8] <= data[2:0];
					 end
					 
             6: packet_len[7:0] <= data;  
				 
				 // skip the checksum then signal we have a udp packet available,save destination IP, MAC and port
				 8: begin
						udp_destination_ip   <= remote_ip;  
						udp_destination_mac  <= remote_mac;
						udp_destination_port <= remote_port;
						state <= ST_PAYLOAD;
					 end 
				  
				// default:  *** need to get this from ip_recv
				//	if (byte_no == header_len) state <= ST_PAYLOAD;
			  endcase  
			  
        byte_no <= byte_no + 11'd1;
        end
        
      ST_PAYLOAD:
        begin  
        //end of payload, ignore the ethernet crc that follows
        if (byte_no == packet_len) state <= ST_DONE;
        byte_no <= byte_no + 11'd1;
        end        
      endcase
      
  else //!rx_enable 
    state <= IDLE;
    
  
  
endmodule	//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.


//-----------------------------------------------------------------------------
// receive ethernet header; check destination mac address and discard packet
// if it is not for us; extract source mac address and packet type
//-----------------------------------------------------------------------------

module mac_recv(
  //input data stream
  input clock, 
  input rx_enable,
  input [7:0] data,

  //constant input parameter
  input [47:0] local_mac,

  //output
  output active,
  output reg broadcast,
  output reg is_arp,
  output reg [47:0] remote_mac
  );

  

  


//-----------------------------------------------------------------------------
//                            state machine
//-----------------------------------------------------------------------------
localparam ST_DST_ADDR = 5'd1, ST_SRC_ADDR = 5'd2, ST_PROTO = 5'd4, ST_PAYLOAD = 5'd8, ST_ERROR = 5'd16;
reg[4:0] state;

reg [2:0] byte_no;
reg unicast;
reg [47:0] temp_remote_mac;

localparam HI_MAC_BYTE = 3'd5, HI_PROTO_BYTE = 3'd1;
localparam false = 1'b0, true = 1'b1;

assign active = rx_enable & (state == ST_PAYLOAD);


always @(posedge clock)
  if (rx_enable)
    case (state)
      ST_DST_ADDR:
        begin
        //is broadcast addr
        if (data != 8'hFF) broadcast <= false;
        //is local mac addr
        if (data != local_mac[byte_no*8+7 -: 8]) unicast <= false; 
        //continue
        if (byte_no != 0) byte_no <= byte_no - 3'd1; 
        //dst addr done
        else begin byte_no <= HI_MAC_BYTE; state <= ST_SRC_ADDR; end
        end
        
      ST_SRC_ADDR:
        begin        
			  //save remote mac
			  temp_remote_mac <= {temp_remote_mac[39:0], data};
			  if (byte_no != 0) byte_no <= byte_no - 3'd1;
			  //good destination mac, protocol id follows
			  else if (broadcast | unicast) begin byte_no <= HI_PROTO_BYTE; state <= ST_PROTO; end
			  //bad destination mac, discard message
			  else state <= ST_ERROR;        
        end
        
      ST_PROTO:
			begin 
			  //protocol 0806 = arp, 0800 = ip
			  if (byte_no != 0) 
				 if (data != 8'h08) state <= ST_ERROR; 
				 else byte_no <= byte_no - 3'd1;
			  else if (data == 8'h06) begin
			  	 is_arp <= true; 
				 remote_mac <= temp_remote_mac;  // only update mac if protocol valid
				 state <= ST_PAYLOAD;
			  end
			  else if (data == 8'h00) begin
			  	 is_arp <= false;
				 remote_mac <= temp_remote_mac;  // only update mac if protocol vaild
				 state <= ST_PAYLOAD;
			  end
			  else state <= ST_ERROR;
		  end
      endcase
      
  else //!rx_enable 
    begin
    broadcast <= true;
    unicast <= true;
    byte_no <= HI_MAC_BYTE;
    state <= ST_DST_ADDR;
    end
    
  
  
endmodule
  
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.




module mac_send (
  input clock, 
  input reset,
  input tx_enable,
  output active,

  input [7:0] data_in,
  output [7:0] data_out,
  input [47:0] local_mac,
  input [47:0] destination_mac
  );
  
//tx bits and shift register
localparam MIN_PACKET_LEN = 6'd46;
localparam HEADER_LEN = 6'd14;
localparam SHR_LEN = 6'd12;
localparam HI_SHR_BIT = 12*8 - 1;
wire [HI_SHR_BIT:0] tx_bits = {destination_mac, local_mac};
reg [HI_SHR_BIT:0] shift_reg;
assign data_out = shift_reg[HI_SHR_BIT -: 8];
reg [5:0] byte_no;  


//crc32 calculation
wire [31:0] crc;  

crc32 crc32_inst (
  .clock(clock),
  .clear(!active),
  .enable(1'b1),
  .data(data_out),
  .result(crc)
  );  
  
  
//state
localparam ST_IDLE = 1, ST_HEADER = 2, ST_PAYLOAD = 4, ST_TAIL = 8, ST_CRC = 16;
reg [4:0] state = ST_IDLE;  


assign active = !reset && (tx_enable || (state != ST_IDLE));


always @(posedge clock)  
  if (reset) state <= ST_IDLE;
    
  else    
    begin
    //shift register
    if ((state == ST_IDLE) && !tx_enable) shift_reg <= tx_bits;
    else if ((state == ST_TAIL) && (byte_no == 0)) shift_reg[HI_SHR_BIT -: 32] <= {crc[7-:8],crc[15-:8],crc[23-:8],crc[31-:8]};
    else if (tx_enable) shift_reg <= {shift_reg[HI_SHR_BIT-8:0], data_in};
    else shift_reg <= {shift_reg[HI_SHR_BIT-8:0], 8'b0};


    case (state)
      //waitfor tx_enable to go high
      ST_IDLE:
        if (tx_enable) 
          begin
          byte_no <= HEADER_LEN-6'd2;
          state <= ST_HEADER;
          end
          
      ST_HEADER:
        //push header out of shr
        if (byte_no != 0) 
          byte_no <= (byte_no - 6'd1);
        //header sent, keep pushing payload into shr
        else
          begin
          byte_no <= (MIN_PACKET_LEN - SHR_LEN);// - 6'd1);
          state <= ST_PAYLOAD;
          end
        
      ST_PAYLOAD:
        //read into shr at least MIN_PACKET_LEN bytes
        if (byte_no != 0) byte_no <= byte_no - 6'd1; 
        //no more payload bytes
        else if (!tx_enable) 
          begin 
          byte_no <= SHR_LEN-6'd2; 
          state <= ST_TAIL;
          end
          
      ST_TAIL:
        //purge shr
        if (byte_no != 0) byte_no <= byte_no - 6'd1;
        //all bytes sent, append crc
        else
          begin 
          byte_no <= 4'd3; 
          state <= ST_CRC; 
          end
      
      ST_CRC:
        //push out 4 bytes of crc         
        if (byte_no != 0) byte_no <= byte_no - 6'd1;
        else state <= ST_IDLE;        
    endcase
  end
  
  
endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Phil Harman VK6APH, Alex Shovkoplyas, VE3NEA.
//  April 2016, N2ADR: Added dhcp_seconds_timer
//  January 2017, N2ADR: Added remote_mac_sync to the dhcp module
//  January 2017, N2ADR: Added ST_DHCP_RENEW states to allow IO to continue during DHCP lease renewal
//  2018 Steve Haynal KF7O


module network (

  // dhcp and mdio clock
  input clock_2_5MHz,

  // upstream
  input         tx_clock,
  input         udp_tx_request,
  input [15:0]  udp_tx_length,
  input [7:0]   udp_tx_data,
  output        udp_tx_enable,
  input         run,
  input [7:0]   port_id,

  // downstream
  input         rx_clock,
  output [15:0] to_port,
  output [7:0]  udp_rx_data,
  output        udp_rx_active,
  output        broadcast,
  output logic  dst_unreachable,

  // status and control
  input  [31:0] static_ip,
  input  [47:0] local_mac,
  output        speed_1gb,
  output        network_state_dhcp,
  output        network_state_fixedip,
  output [1:0]  network_speed,

  // phy
  output [3:0]  PHY_TX,
  output        PHY_TX_EN,
  input  [3:0]  PHY_RX,
  input         PHY_DV,

  inout         PHY_MDIO,
  output        PHY_MDC
);

wire udp_tx_active;
wire eeprom_ready;
wire [1:0] phy_speed;
wire phy_duplex;
wire dhcp_success;
wire icmp_rx_enable;
wire static_ip_assigned;
wire phy_connected = phy_duplex && (phy_speed[1] != phy_speed[0]);

reg speed_1gb_i = 1'b0;
//assign dhcp_timeout = (dhcp_seconds_timer == 15);


//-----------------------------------------------------------------------------
//                             state machine
//-----------------------------------------------------------------------------
//IP addresses
reg  [31:0] local_ip;
//wire [31:0] apipa_ip = {8'd192, 8'd168, 8'd22, 8'd248};
wire [31:0] apipa_ip = {8'd169, 8'd254, local_mac[15:0]};
//wire [31:0] ip_to_write;
assign static_ip_assigned = (static_ip != 32'hFFFFFFFF) && (static_ip != 32'd0);


localparam
  ST_START         = 4'd0,
  ST_EEPROM_START  = 4'd1,
  ST_EEPROM_READ   = 4'd2,
  ST_PHY_INIT      = 4'd3,
  ST_PHY_CONNECT   = 4'd4,
  ST_PHY_SETTLE    = 4'd5,
  ST_DHCP_REQUEST  = 4'd6,
  ST_DHCP          = 4'd7,
  ST_DHCP_RETRY    = 4'd8,
  ST_RUNNING       = 4'd9,
  ST_DHCP_RENEW_WAIT  = 4'd10,
  ST_DHCP_RENEW_REQ   = 4'd11,
  ST_DHCP_RENEW_ACK   = 4'd12;



// Set Tx_reset (no sdr send) if network_state is True
assign network_state_dhcp = reg_network_state_dhcp;   // network_state is low when we have an IP address
assign network_state_fixedip = reg_network_state_fixedip;
reg reg_network_state_dhcp = 1'b1;           // this is used in network.v to hold code in reset when high
reg reg_network_state_fixedip = 1'b1;
reg [3:0] state = ST_START;
reg [21:0] dhcp_timer;
reg dhcp_tx_enable;
reg [17:0] dhcp_renew_timer;  // holds number of seconds before DHCP IP address must be renewed
reg [3:0] dhcp_seconds_timer;   // number of seconds since the DHCP request started



//reset all child modules
wire rx_reset, tx_reset;
sync sync_inst1(.clock(rx_clock), .sig_in(state <= ST_PHY_SETTLE), .sig_out(rx_reset));
sync sync_inst2(.clock(tx_clock), .sig_in(state <= ST_PHY_SETTLE), .sig_out(tx_reset));


always @(negedge clock_2_5MHz)
  //if connection lost, wait until reconnects
  if ((state > ST_PHY_CONNECT) && !phy_connected) begin
    reg_network_state_dhcp <= 1'b1;
    reg_network_state_fixedip <= 1'b1;
    state <= ST_PHY_CONNECT;
  end

  else
  case (state)
    //set eeprom read request
    ST_START: begin
      speed_1gb_i <= 0;
      state <= ST_EEPROM_START;
    end
    //clear eeprom read request
    ST_EEPROM_START:
      state <= ST_EEPROM_READ;

    //wait for eeprom
    ST_EEPROM_READ: begin
      local_ip <= static_ip;
      //dhcp_timer <= 22'd2_500_000;    // set dhcp timer to one second
      //dhcp_seconds_timer <= 4'd0; // zero seconds have elapsed
      state <= ST_PHY_INIT;
    end

    //set phy initialization request
    ST_PHY_INIT:
      state <= ST_PHY_CONNECT;

    //clear phy initialization request
    //wait for phy to initialize and connect
    ST_PHY_CONNECT:
      if (phy_connected) begin
        dhcp_timer <= 22'd2500000; //1 second
        state <= ST_PHY_SETTLE;
        speed_1gb_i <= phy_speed[1];
      end

    //wait for connection to settle
    ST_PHY_SETTLE: begin
      //when network has settled, get ip address, if static IP assigned then use it else try DHCP
      if (dhcp_timer == 0) begin
        if (static_ip_assigned)
          state <= ST_RUNNING;
        else begin
          local_ip <= 32'h00_00_00_00;                // needs to be 0.0.0.0 for DHCP
          dhcp_timer <= 22'd2_500_000;    // set dhcp timer to one second
          dhcp_seconds_timer <= 4'd0; // zero seconds have elapsed
          state <= ST_DHCP_REQUEST;
        end
      end
      dhcp_timer <= dhcp_timer - 22'b1;          //no time out yet, count down
    end

    // send initial dhcp discover and request on power up
    ST_DHCP_REQUEST: begin
      dhcp_tx_enable <= 1'b1;           // set dhcp flag
      dhcp_enable <= 1'b1;              // enable dhcp receive
      state <= ST_DHCP;
    end

    // wait for dhcp success, fail or time out.  Do time out here since same clock speed for 100/1000T
    // If DHCP provided IP address then set lease timeout to lease/2 seconds.
    ST_DHCP: begin
      dhcp_tx_enable <= 1'b0;         // clear dhcp flag
      if (dhcp_success) begin
        local_ip <= ip_accept;
        dhcp_timer <= 22'd2_500_000;    // reset dhcp timers for next Renewal
        dhcp_seconds_timer <= 4'd0;
        reg_network_state_dhcp <= 1'b0;    // Let network code know we have a valid IP address so can run when needed.
        if (lease == 32'd0)
          dhcp_renew_timer <= 43_200;  // use 43,200 seconds (12 hours) if no lease time set
        else
          dhcp_renew_timer <= lease >> 1;  // set timer to half lease time.
        //    dhcp_renew_timer <= (32'd10 * 2_500_000);     // **** test code - set DHCP renew to 10 seconds ****
        state <= ST_DHCP_RENEW_WAIT;
      end
      else if (dhcp_timer == 0) begin  // another second has elapsed
        dhcp_renew_timer <= 18'h020000; // delay 50 ms
        dhcp_timer <= 22'd2_500_000;    // reset dhcp timer to one second
        dhcp_seconds_timer <= dhcp_seconds_timer + 4'd1;    // dhcp_seconds_timer still has its old value
        // Retransmit Discover at 1, 3, 7 seconds
        if (dhcp_seconds_timer == 0 || dhcp_seconds_timer == 2 || dhcp_seconds_timer == 6) begin
          state <= ST_DHCP_RETRY;     // retransmit the Discover request
        end
        else if (dhcp_seconds_timer == 14) begin    // no DHCP Offer received in 15 seconds; use apipa
          local_ip <= apipa_ip;
          state <= ST_RUNNING;
        end
      end
      else
        dhcp_timer <= dhcp_timer - 22'd1;
    end

    ST_DHCP_RETRY: begin  // Initial DHCP IP address was not obtained.  Try again.
      dhcp_enable <= 1'b0;                // disable dhcp receive
      if (dhcp_renew_timer == 0)
        state <= ST_DHCP_REQUEST;
      else
        dhcp_renew_timer <= dhcp_renew_timer - 18'h01;
    end

    // static ,DHCP or APIPA ip address obtained
    ST_RUNNING: begin
      dhcp_enable <= 1'b0;          // disable dhcp receive
      reg_network_state_fixedip <= 1'b0;    // let network.v know we have a valid IP address
    end

    // NOTE: reg_network_state is not set here so we can send DHCP packets whilst waiting for DHCP renewal.

    ST_DHCP_RENEW_WAIT: begin // Wait until the DHCP lease expires
      dhcp_enable <= 1'b0;        // disable dhcp receive

      if (dhcp_timer == 0) begin // another second has elapsed
        dhcp_renew_timer <= dhcp_renew_timer - 18'h01;
        dhcp_timer <= 22'd2_500_000;    // reset dhcp timer to one second
      end
      else begin
        dhcp_timer <= dhcp_timer - 22'h01;
      end

      if (dhcp_renew_timer == 0)
        state <= ST_DHCP_RENEW_REQ;
    end

    ST_DHCP_RENEW_REQ: begin // DHCP sends a request to renew the lease
      dhcp_tx_enable <= 1'b1;
      dhcp_enable <= 1'b1;
      dhcp_renew_timer <= 'd20;   // time to wait for ACK
      dhcp_timer <= 22'd2_500_000;    // reset dhcp timers for next Renewal
      state <= ST_DHCP_RENEW_ACK;
    end

    ST_DHCP_RENEW_ACK: begin  // Wait for an ACK from the DHCP server in response to the request
      dhcp_tx_enable <= 1'b0;
      if (dhcp_success) begin
        if (lease == 32'd0)
          dhcp_renew_timer <= 43_200;  // use 43,200 seconds (12 hours) if no lease time set
        else
          dhcp_renew_timer <= lease >> 1;  // set timer to half lease time.
        //  dhcp_renew_timer <= (32'd10 * 2_500_000);     // **** test code - set DHCP renew to 10 seconds ****
        dhcp_timer <= 22'd2_500_000;    // reset dhcp timers for next Renewal
        state <= ST_DHCP_RENEW_WAIT;
      end

      else if (dhcp_timer == 0) begin  // another second has elapsed
        dhcp_timer <= 22'd2_500_000;    // reset dhcp timer to one second
        dhcp_renew_timer <= dhcp_renew_timer - 1'd1;

      end
      else if (dhcp_renew_timer == 0) begin
        dhcp_renew_timer <= 18'd300; // time between renewal requests
        state <= ST_DHCP_RENEW_WAIT;
      end
      else begin
        dhcp_timer <= dhcp_timer - 18'h01;
      end

    end

  endcase


//-----------------------------------------------------------------------------
// writes configuration words to the phy registers, reads phy state
//-----------------------------------------------------------------------------
phy_cfg phy_cfg_inst(
  .clock(clock_2_5MHz),
  .init_request(state == ST_PHY_INIT),
  .allow_1Gbit(1'b1),
  .speed(phy_speed),
  .duplex(phy_duplex),
  .mdio_pin(PHY_MDIO),
  .mdc_pin(PHY_MDC)
);



//-----------------------------------------------------------------------------
//                           interconnections
//-----------------------------------------------------------------------------
localparam PT_ARP = 2'd0, PT_ICMP = 2'd1, PT_DHCP = 2'd2, PT_UDP = 2'd3;
localparam false = 1'b0, true = 1'b1;



reg tx_ready = false;
reg tx_start = false;
reg [1:0] tx_protocol;

wire tx_is_icmp = tx_protocol == PT_ICMP;
wire tx_is_arp = tx_protocol  == PT_ARP;
wire tx_is_udp = tx_protocol  == PT_UDP;
wire tx_is_dhcp = tx_protocol == PT_DHCP;



//udp = dhcp or udp, they have separate data
wire [7:0]  udp_data;
wire [15:0] udp_length;
wire [15:0] destination_port;
wire [31:0] to_ip;


//rgmii_recv out
wire          rgmii_rx_active_pipe;
wire [7:0]    rx_data_pipe;
reg           rgmii_rx_active;
reg [7:0]     rx_data;

//mac_recv in
wire mac_rx_enable = rgmii_rx_active;

wire rx_is_arp;

//ip_recv in
wire ip_rx_enable = mac_rx_active && !rx_is_arp;
//ip_recv out
wire ip_rx_active;
wire rx_is_icmp;

//udp_recv in
wire udp_rx_enable = ip_rx_active && !rx_is_icmp;
assign udp_tx_enable = tx_start && (tx_is_udp || tx_is_dhcp);
//udp_recv out
assign udp_rx_data = rx_data;

//arp in
wire arp_rx_enable = mac_rx_active && rx_is_arp;
wire arp_tx_enable = tx_start && tx_is_arp;
//arp out
wire arp_tx_request;
wire arp_tx_active;
wire [7:0] arp_tx_data;
wire [47:0] arp_destination_mac;

// icmp in
assign  icmp_rx_enable = ip_rx_active && rx_is_icmp;
wire icmp_tx_enable = tx_start && tx_is_icmp;
//icmp out
wire icmp_tx_request;
wire icmp_tx_active;
wire [7:0] icmp_data;
wire [15:0] icmp_length;
wire [47:0] icmp_destination_mac;
wire [31:0] icmp_destination_ip;

reg [15:0] run_destination_port;
reg [31:0] run_destination_ip;
reg [47:0] run_destination_mac;

//ip_send in
wire ip_tx_enable = icmp_tx_active || udp_tx_active;
wire [7:0] ip_tx_data_in = tx_is_icmp? icmp_data : udp_data;
wire [15:0] ip_tx_length = tx_is_icmp? icmp_length : udp_length;
wire [31:0] destination_ip = tx_is_icmp? icmp_destination_ip : (tx_is_dhcp ? dhcp_destination_ip : run_destination_ip); //udp_destination_ip_sync);

//ip_send out
wire [7:0] ip_tx_data;
wire ip_tx_active;

//mac_send in
wire mac_tx_enable = arp_tx_active || ip_tx_active;
wire [7:0] mac_tx_data_in = tx_is_arp? arp_tx_data : ip_tx_data;
wire [47:0] destination_mac = tx_is_arp  ? arp_destination_mac  :
     tx_is_icmp ? icmp_destination_mac :
     tx_is_dhcp ? dhcp_destination_mac : run_destination_mac; //udp_destination_mac_sync;
//mac_send out
wire [7:0] mac_tx_data;
wire mac_tx_active;

//rgmii_send in
wire [7:0] rgmii_tx_data_in = mac_tx_data;
wire rgmii_tx_enable = mac_tx_active;

reg  [7:0]  rgmii_tx_data_in_pipe;
reg         rgmii_tx_enable_pipe = 1'b0;



//rgmii_send out
wire        rgmii_tx_active;

//dhcp
wire [15:0]dhcp_udp_tx_length        = tx_is_dhcp ? dhcp_tx_length        : udp_tx_length;
wire [7:0] dhcp_udp_tx_data          = tx_is_dhcp ? dhcp_tx_data          : udp_tx_data;
wire [15:0]local_port                   = tx_is_dhcp ? 16'd68                  : 16'd1024;



// Hold destination port once run is set
always @(posedge tx_clock)
  if (!run) begin
    run_destination_port <= udp_destination_port_sync;
    run_destination_ip <= udp_destination_ip_sync;
    run_destination_mac <= udp_destination_mac_sync;
  end

wire [15:0]dhcp_udp_destination_port = tx_is_dhcp ? dhcp_destination_port : run_destination_port; //udp_destination_port_sync;
wire dhcp_rx_active;
wire mac_rx_active;


always @(posedge tx_clock)
  if (rgmii_tx_active) begin
    tx_ready <= false;
    tx_start <= false;
  end
  else if (tx_ready)
    tx_start <= true;
  else begin
    if (arp_tx_request) begin
      tx_protocol <= PT_ARP;
      tx_ready <= true;
    end
    else if (icmp_tx_request) begin
      tx_protocol <= PT_ICMP;
      tx_ready <= true;
    end
    else if (dhcp_tx_request) begin
      tx_protocol <= PT_DHCP;
      tx_ready <= true;
    end
    else if (udp_tx_request)  begin
      tx_protocol <= PT_UDP;
      tx_ready <= true;
    end;
  end



//-----------------------------------------------------------------------------
//                               receive
//-----------------------------------------------------------------------------

always @(posedge rx_clock) begin
  rx_data <= rx_data_pipe;
  rgmii_rx_active <= rgmii_rx_active_pipe;
end

rgmii_recv rgmii_recv_inst (
  //out
  .active(rgmii_rx_active_pipe),

  .reset(rx_reset),
  .clock(rx_clock),
  .speed_1gb(speed_1gb_i),
  .data(rx_data_pipe),
  .PHY_RX(PHY_RX),
  .PHY_DV(PHY_DV)
);

mac_recv mac_recv_inst(
  //in
  .rx_enable(mac_rx_enable),
  //out
  .active(mac_rx_active),
  .is_arp(rx_is_arp),
  .remote_mac(remote_mac),
  .clock(rx_clock),
  .data(rx_data),
  .local_mac(local_mac),
  .broadcast(broadcast)
);


ip_recv ip_recv_inst(
  // in
  .local_ip(local_ip),
  //out
  .active(ip_rx_active),
  .is_icmp(rx_is_icmp),
  .remote_ip(remote_ip),
  .clock(rx_clock),
  .rx_enable(ip_rx_enable),
  .broadcast(broadcast),
  .data(rx_data),

  .to_ip(to_ip)
);

udp_recv udp_recv_inst(
  //in
  .clock(rx_clock),
  .rx_enable(udp_rx_enable),
  .data(rx_data),
  .to_ip(to_ip),
  .local_ip(local_ip),
  .broadcast(broadcast),
  .remote_mac(remote_mac),
  .remote_ip(remote_ip),

  //out
  .active(udp_rx_active),
  .dhcp_active(dhcp_rx_active),
  .to_port(to_port),
  .udp_destination_ip(udp_destination_ip),
  .udp_destination_mac(udp_destination_mac),
  .udp_destination_port(udp_destination_port)
);

//-----------------------------------------------------------------------------
//                           receive/reply
//-----------------------------------------------------------------------------
arp arp_inst(
  //in
  .rx_enable(arp_rx_enable),
  .tx_enable(arp_tx_enable),
  //out
  .tx_active(arp_tx_active),
  .tx_data(arp_tx_data),
  .destination_mac(arp_destination_mac),
  .reset(tx_reset),
  .rx_clock(rx_clock),
  .rx_data(rx_data),
  .tx_clock(tx_clock),
  .local_mac(local_mac),
  .local_ip(local_ip),
  .tx_request(arp_tx_request),
  .remote_mac(remote_mac_sync)
);

icmp icmp_inst (
  //in
  .rx_enable(icmp_rx_enable),
  .tx_enable(icmp_tx_enable),
  //out
  .tx_request(icmp_tx_request),
  .tx_active(icmp_tx_active),
  .tx_data(icmp_data),
  .destination_mac(icmp_destination_mac),
  .destination_ip(icmp_destination_ip),
  .length(icmp_length),
  .dst_unreachable(dst_unreachable),

  .remote_mac(remote_mac_sync),
  .remote_ip(remote_ip_sync),
  .reset(tx_reset),
  .rx_clock(rx_clock),
  .rx_data(rx_data),
  .tx_clock(tx_clock)
);

wire dhcp_tx_request;
reg dhcp_enable;
wire [7:0]  dhcp_tx_data;
wire [15:0] dhcp_tx_length;
wire [47:0] dhcp_destination_mac;
wire [31:0] dhcp_destination_ip;
wire [15:0] dhcp_destination_port;
wire [31:0] ip_accept;                  // DHCP provided IP address
wire [31:0] lease;                      // time in seconds that DHCP supplied IP address is valid
wire [31:0] server_ip;                  // IP address of the DHCP that provided the IP address
wire erase;
wire EPCS_FIFO_enable;
wire [47:0]remote_mac;
wire [31:0]remote_ip;
wire [15:0]remote_port;


dhcp dhcp_inst(
  //rx in
  .rx_clock(rx_clock),
  .rx_data(rx_data),
  .rx_enable(dhcp_enable),
  .dhcp_rx_active(dhcp_rx_active),
  //rx out
  .lease(lease),
  .server_ip(server_ip),

  //tx in
  .reset(tx_reset),
  .tx_clock(tx_clock),
  .udp_tx_enable(udp_tx_enable),
  .tx_enable(dhcp_tx_enable),
  .udp_tx_active(udp_tx_active),
  .remote_mac(remote_mac_sync),             // MAC address of DHCP server
  .remote_ip(remote_ip_sync),               // IP address of DHCP server
  .dhcp_seconds_timer(dhcp_seconds_timer),

  // tx_out
  .dhcp_tx_request(dhcp_tx_request),
  .tx_data(dhcp_tx_data),
  .length(dhcp_tx_length),
  .ip_accept(ip_accept),                // IP address from DHCP server

  //constants
  .local_mac(local_mac),
  .dhcp_destination_mac(dhcp_destination_mac),
  .dhcp_destination_ip(dhcp_destination_ip),
  .dhcp_destination_port(dhcp_destination_port),

  // result
  .dhcp_success(dhcp_success),
  .dhcp_failed()

);

//-----------------------------------------------------------------------------
//                                rx to tx clock domain transfers
//-----------------------------------------------------------------------------
wire [47:0] remote_mac_sync;
wire [31:0] remote_ip_sync;
wire [15:0] udp_destination_port;
wire [15:0] udp_destination_port_sync;
wire [47:0] udp_destination_mac;
wire [47:0] udp_destination_mac_sync;
wire [31:0] udp_destination_ip;
wire [31:0] udp_destination_ip_sync;

cdc_sync #(48)cdc_sync_inst1 (.siga(remote_mac), .rstb(1'b0), .clkb(tx_clock), .sigb(remote_mac_sync));
cdc_sync #(32)cdc_sync_inst2 (.siga(remote_ip), .rstb(1'b0), .clkb(tx_clock), .sigb(remote_ip_sync));
cdc_sync #(32) cdc_sync_inst7 (.siga(udp_destination_ip), .rstb(1'b0), .clkb(tx_clock), .sigb(udp_destination_ip_sync));
cdc_sync #(48) cdc_sync_inst8 (.siga(udp_destination_mac), .rstb(1'b0), .clkb(tx_clock), .sigb(udp_destination_mac_sync));
cdc_sync #(16) cdc_sync_inst9 (.siga(udp_destination_port), .rstb(1'b0), .clkb(tx_clock), .sigb(udp_destination_port_sync));


//-----------------------------------------------------------------------------
//                               send
//-----------------------------------------------------------------------------

udp_send udp_send_inst (
  //in
  .reset(tx_reset),
  .clock(tx_clock),
  .tx_enable(udp_tx_enable),
  .data_in(dhcp_udp_tx_data),
  .length_in(dhcp_udp_tx_length),
  .local_port(local_port),
  .destination_port(dhcp_udp_destination_port),
  //out
  .active(udp_tx_active),
  .data_out(udp_data),
  .length_out(udp_length),
  .port_ID(port_id)
);

ip_send ip_send_inst (
  //in
  .data_in(ip_tx_data_in),
  .tx_enable(ip_tx_enable),
  .is_icmp(tx_is_icmp),
  .length(ip_tx_length),
  .destination_ip(destination_ip),
  //out
  .data_out(ip_tx_data),
  .active(ip_tx_active),

  .clock(tx_clock),
  .reset(tx_reset),
  .local_ip(local_ip)
);

mac_send mac_send_inst (
  //in
  .data_in(mac_tx_data_in),
  .tx_enable(mac_tx_enable),
  .destination_mac(destination_mac),
  //out
  .data_out(mac_tx_data),
  .active(mac_tx_active),

  .clock(tx_clock),
  .local_mac(local_mac),
  .reset(tx_reset)
);

always @(posedge tx_clock) begin
  rgmii_tx_data_in_pipe <= rgmii_tx_data_in;
  rgmii_tx_enable_pipe <= rgmii_tx_enable;
end

rgmii_send rgmii_send_inst (
  //in
  .data(rgmii_tx_data_in_pipe),
  .tx_enable(rgmii_tx_enable_pipe),
  .active(rgmii_tx_active),
  .clock(tx_clock),
  .PHY_TX(PHY_TX),
  .PHY_TX_EN(PHY_TX_EN)
);


//-----------------------------------------------------------------------------
//                              debug output
//-----------------------------------------------------------------------------
assign speed_1gb = speed_1gb_i; //phy_speed[1];
assign network_speed = phy_speed;
// {phy_connected,phy_speed[1],phy_speed[0], udp_rx_active, udp_rx_enable, rgmii_rx_active, rgmii_tx_active, mac_rx_active};


endmodule
// megafunction wizard: %ALTDDIO_IN%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: ALTDDIO_IN 

// ============================================================
// File Name: ddio_in.v
// Megafunction Name(s):
// 			ALTDDIO_IN
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 11.1 Build 259 01/25/2012 SP 2 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2011 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module ddio_in (
	datain,
	inclock,
	dataout_h,
	dataout_l);

	input	[4:0]  datain;
	input	  inclock;
	output	[4:0]  dataout_h;
	output	[4:0]  dataout_l;

	wire [4:0] sub_wire0;
	wire [4:0] sub_wire1;
	wire [4:0] dataout_h = sub_wire0[4:0];
	wire [4:0] dataout_l = sub_wire1[4:0];
/*
	altddio_in	ALTDDIO_IN_component (
				.datain (datain),
				.inclock (inclock),
				.dataout_h (sub_wire0),
				.dataout_l (sub_wire1),
				.aclr (1'b0),
				.aset (1'b0),
				.inclocken (1'b1),
				.sclr (1'b0),
				.sset (1'b0));
	defparam
		ALTDDIO_IN_component.intended_device_family = "Cyclone IV E",
		ALTDDIO_IN_component.invert_input_clocks = "ON",
		ALTDDIO_IN_component.lpm_hint = "UNUSED",
		ALTDDIO_IN_component.lpm_type = "altddio_in",
		ALTDDIO_IN_component.power_up_high = "OFF",
		ALTDDIO_IN_component.width = 5;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: INVERT_INPUT_CLOCKS STRING "ON"
// Retrieval info: CONSTANT: LPM_HINT STRING "UNUSED"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altddio_in"
// Retrieval info: CONSTANT: POWER_UP_HIGH STRING "OFF"
// Retrieval info: CONSTANT: WIDTH NUMERIC "5"
// Retrieval info: USED_PORT: datain 0 0 5 0 INPUT NODEFVAL "datain[4..0]"
// Retrieval info: CONNECT: @datain 0 0 5 0 datain 0 0 5 0
// Retrieval info: USED_PORT: dataout_h 0 0 5 0 OUTPUT NODEFVAL "dataout_h[4..0]"
// Retrieval info: CONNECT: dataout_h 0 0 5 0 @dataout_h 0 0 5 0
// Retrieval info: USED_PORT: dataout_l 0 0 5 0 OUTPUT NODEFVAL "dataout_l[4..0]"
// Retrieval info: CONNECT: dataout_l 0 0 5 0 @dataout_l 0 0 5 0
// Retrieval info: USED_PORT: inclock 0 0 0 0 INPUT_CLK_EXT NODEFVAL "inclock"
// Retrieval info: CONNECT: @inclock 0 0 0 0 inclock 0 0 0 0
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in.v TRUE FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in.qip TRUE FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in.bsf TRUE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in_inst.v FALSE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in_bb.v FALSE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in.inc TRUE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in.cmp TRUE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_in.ppf TRUE FALSE
// Retrieval info: LIB_FILE: altera_mf
// megafunction wizard: %FIFO%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: dcfifo 

// ============================================================
// File Name: icmp_fifo.v
// Megafunction Name(s):
// 			dcfifo
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 16.1.2 Build 203 01/18/2017 SJ Lite Edition
// ************************************************************


//Copyright (C) 2017  Intel Corporation. All rights reserved.
//Your use of Intel Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Intel Program License 
//Subscription Agreement, the Intel Quartus Prime License Agreement,
//the Intel MegaCore Function License Agreement, or other 
//applicable license agreement, including, without limitation, 
//that your use is for the sole purpose of programming logic 
//devices manufactured by Intel and sold by Intel or its 
//authorized distributors.  Please refer to the applicable 
//agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module icmp_fifo (
	aclr,
	data,
	rdclk,
	rdreq,
	wrclk,
	wrreq,
	q,
	rdempty,
	wrfull);

	input	  aclr;
	input	[7:0]  data;
	input	  rdclk;
	input	  rdreq;
	input	  wrclk;
	input	  wrreq;
	output	[7:0]  q;
	output	  rdempty;
	output	  wrfull;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri0	  aclr;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [7:0] sub_wire0;
	wire  sub_wire1;
	wire  sub_wire2;
	wire [7:0] q = sub_wire0[7:0];
	wire  rdempty = sub_wire1;
	wire  wrfull = sub_wire2;
/*
	dcfifo	dcfifo_component (
				.aclr (aclr),
				.data (data),
				.rdclk (rdclk),
				.rdreq (rdreq),
				.wrclk (wrclk),
				.wrreq (wrreq),
				.q (sub_wire0),
				.rdempty (sub_wire1),
				.wrfull (sub_wire2),
				.eccstatus (),
				.rdfull (),
				.rdusedw (),
				.wrempty (),
				.wrusedw ());
	defparam
		dcfifo_component.intended_device_family = "Cyclone IV E",
		dcfifo_component.lpm_hint = "RAM_BLOCK_TYPE=M9K",
		dcfifo_component.lpm_numwords = 1024,
		dcfifo_component.lpm_showahead = "ON",
		dcfifo_component.lpm_type = "dcfifo",
		dcfifo_component.lpm_width = 8,
		dcfifo_component.lpm_widthu = 10,
		dcfifo_component.overflow_checking = "ON",
		dcfifo_component.rdsync_delaypipe = 4,
		dcfifo_component.read_aclr_synch = "OFF",
		dcfifo_component.underflow_checking = "ON",
		dcfifo_component.use_eab = "ON",
		dcfifo_component.write_aclr_synch = "OFF",
		dcfifo_component.wrsync_delaypipe = 4;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: PRIVATE: AlmostEmpty NUMERIC "0"
// Retrieval info: PRIVATE: AlmostEmptyThr NUMERIC "-1"
// Retrieval info: PRIVATE: AlmostFull NUMERIC "0"
// Retrieval info: PRIVATE: AlmostFullThr NUMERIC "-1"
// Retrieval info: PRIVATE: CLOCKS_ARE_SYNCHRONIZED NUMERIC "1"
// Retrieval info: PRIVATE: Clock NUMERIC "4"
// Retrieval info: PRIVATE: Depth NUMERIC "1024"
// Retrieval info: PRIVATE: Empty NUMERIC "1"
// Retrieval info: PRIVATE: Full NUMERIC "1"
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: PRIVATE: LE_BasedFIFO NUMERIC "0"
// Retrieval info: PRIVATE: LegacyRREQ NUMERIC "0"
// Retrieval info: PRIVATE: MAX_DEPTH_BY_9 NUMERIC "0"
// Retrieval info: PRIVATE: OVERFLOW_CHECKING NUMERIC "0"
// Retrieval info: PRIVATE: Optimize NUMERIC "2"
// Retrieval info: PRIVATE: RAM_BLOCK_TYPE NUMERIC "2"
// Retrieval info: PRIVATE: SYNTH_WRAPPER_GEN_POSTFIX STRING "0"
// Retrieval info: PRIVATE: UNDERFLOW_CHECKING NUMERIC "0"
// Retrieval info: PRIVATE: UsedW NUMERIC "0"
// Retrieval info: PRIVATE: Width NUMERIC "8"
// Retrieval info: PRIVATE: dc_aclr NUMERIC "1"
// Retrieval info: PRIVATE: diff_widths NUMERIC "0"
// Retrieval info: PRIVATE: msb_usedw NUMERIC "0"
// Retrieval info: PRIVATE: output_width NUMERIC "8"
// Retrieval info: PRIVATE: rsEmpty NUMERIC "1"
// Retrieval info: PRIVATE: rsFull NUMERIC "0"
// Retrieval info: PRIVATE: rsUsedW NUMERIC "0"
// Retrieval info: PRIVATE: sc_aclr NUMERIC "0"
// Retrieval info: PRIVATE: sc_sclr NUMERIC "1"
// Retrieval info: PRIVATE: wsEmpty NUMERIC "0"
// Retrieval info: PRIVATE: wsFull NUMERIC "1"
// Retrieval info: PRIVATE: wsUsedW NUMERIC "0"
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone IV E"
// Retrieval info: CONSTANT: LPM_HINT STRING "RAM_BLOCK_TYPE=M9K"
// Retrieval info: CONSTANT: LPM_NUMWORDS NUMERIC "1024"
// Retrieval info: CONSTANT: LPM_SHOWAHEAD STRING "ON"
// Retrieval info: CONSTANT: LPM_TYPE STRING "dcfifo"
// Retrieval info: CONSTANT: LPM_WIDTH NUMERIC "8"
// Retrieval info: CONSTANT: LPM_WIDTHU NUMERIC "10"
// Retrieval info: CONSTANT: OVERFLOW_CHECKING STRING "ON"
// Retrieval info: CONSTANT: RDSYNC_DELAYPIPE NUMERIC "4"
// Retrieval info: CONSTANT: READ_ACLR_SYNCH STRING "OFF"
// Retrieval info: CONSTANT: UNDERFLOW_CHECKING STRING "ON"
// Retrieval info: CONSTANT: USE_EAB STRING "ON"
// Retrieval info: CONSTANT: WRITE_ACLR_SYNCH STRING "OFF"
// Retrieval info: CONSTANT: WRSYNC_DELAYPIPE NUMERIC "4"
// Retrieval info: USED_PORT: aclr 0 0 0 0 INPUT GND "aclr"
// Retrieval info: USED_PORT: data 0 0 8 0 INPUT NODEFVAL "data[7..0]"
// Retrieval info: USED_PORT: q 0 0 8 0 OUTPUT NODEFVAL "q[7..0]"
// Retrieval info: USED_PORT: rdclk 0 0 0 0 INPUT NODEFVAL "rdclk"
// Retrieval info: USED_PORT: rdempty 0 0 0 0 OUTPUT NODEFVAL "rdempty"
// Retrieval info: USED_PORT: rdreq 0 0 0 0 INPUT NODEFVAL "rdreq"
// Retrieval info: USED_PORT: wrclk 0 0 0 0 INPUT NODEFVAL "wrclk"
// Retrieval info: USED_PORT: wrfull 0 0 0 0 OUTPUT NODEFVAL "wrfull"
// Retrieval info: USED_PORT: wrreq 0 0 0 0 INPUT NODEFVAL "wrreq"
// Retrieval info: CONNECT: @aclr 0 0 0 0 aclr 0 0 0 0
// Retrieval info: CONNECT: @data 0 0 8 0 data 0 0 8 0
// Retrieval info: CONNECT: @rdclk 0 0 0 0 rdclk 0 0 0 0
// Retrieval info: CONNECT: @rdreq 0 0 0 0 rdreq 0 0 0 0
// Retrieval info: CONNECT: @wrclk 0 0 0 0 wrclk 0 0 0 0
// Retrieval info: CONNECT: @wrreq 0 0 0 0 wrreq 0 0 0 0
// Retrieval info: CONNECT: q 0 0 8 0 @q 0 0 8 0
// Retrieval info: CONNECT: rdempty 0 0 0 0 @rdempty 0 0 0 0
// Retrieval info: CONNECT: wrfull 0 0 0 0 @wrfull 0 0 0 0
// Retrieval info: GEN_FILE: TYPE_NORMAL icmp_fifo.v TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL icmp_fifo.inc FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL icmp_fifo.cmp FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL icmp_fifo.bsf FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL icmp_fifo_inst.v FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL icmp_fifo_bb.v FALSE
// Retrieval info: LIB_FILE: altera_mf
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.


module icmp (
  input reset, 
  input rx_clock,  
  input rx_enable,  
  input [7:0] rx_data,
  input tx_clock, 
  input tx_enable,
  input [47:0] remote_mac,
  input [31:0] remote_ip, 
 
  output logic  dst_unreachable,
  output logic tx_request, 
  output logic tx_active,
  output reg [7:0] tx_data,
  output reg [15:0] length, 
  output reg [47:0] destination_mac,  
  output reg [31:0] destination_ip
);


   

//-----------------------------------------------------------------------------
//                               receive
//-----------------------------------------------------------------------------
localparam HEADER_LEN = 16'd4;
localparam 
	ST_IDLE 		= 6'd1, 
	ST_HEADER 		= 6'd2, 
	ST_PAYLOAD 		= 6'd3, 
	ST_TXREQ 		= 6'd4, 
	ST_TX 			= 6'd5, 
	ST_DONE 		= 6'd6,
	ST_UNREACHABLE 	= 6'd7;
	
reg[5:0] state = ST_IDLE;
reg [2:0] byte_no;
reg [31:0] sum;				

wire fifo_full, sending_sync;

  
always @(posedge rx_clock)
    case (state)
      ST_IDLE:
      	begin
      	// clear ICMP dest unreachable flag
      	dst_unreachable <= 1'b0;
        //packet start
        if (rx_enable)
          begin 
          byte_no <= 2;
          sum <= 32'h0;
          destination_mac <= remote_mac;
          destination_ip <= remote_ip;
          // detection of ICMP dest/port unreachable packet
          if (rx_data == 8'h03) state <= ST_UNREACHABLE;
          else
            state <= (rx_data == 8'h08) ? ST_HEADER : ST_DONE; 
          end // if (rx_enable)
        end  

      ST_HEADER:    
        //premature end of packet
        if (!rx_enable) state <= ST_IDLE;
        //end of header
        else if (byte_no == 0) begin length <= HEADER_LEN; state <= ST_PAYLOAD; end
        //invalid header
        else if ((byte_no == 2) && (rx_data != 8'h00)) state <= ST_DONE;
        //next header byte
        else byte_no <= byte_no - 3'd1;

      ST_PAYLOAD: begin
        //end of payload data, reply
        if (!rx_enable) state <= ST_TXREQ;
        //not enough space in fifo
        else if (fifo_full) state <= ST_DONE;
        
        //Allow during fifo_full for timing as data is invalid
        if (rx_enable) begin
          //update checksum
          if (length[0]) sum <= sum + {24'b0, rx_data};  // sum is 32 bits so need to add 24 
          else sum <= sum + {16'd0, rx_data, 8'b0};      // need to form 16 bits from two 8 bit values hence toggle using length[0]  
          //count payload bytes
          length <= length + 16'd1;
        end
      end
      //wait for permission to send
      ST_TXREQ: if (sending_sync) state <= ST_TX;    

      //wait for the end of sending
      ST_TX: if (!sending_sync) state <= ST_IDLE;
      
      //end of discarded packet
      ST_DONE: if (!rx_enable) state <= ST_IDLE;
      
      // Detection of ICMP dest/port unreachable packet
      ST_UNREACHABLE:
        begin
          dst_unreachable <= 1'b1;
          state <= ST_DONE;
        end
    endcase
      
        

        
        
        
//-----------------------------------------------------------------------------
//                       storage for payload data
//-----------------------------------------------------------------------------
localparam false = 1'b0, true = 1'b1;
reg sending = false;


wire fifo_clear = state == ST_IDLE;
wire fifo_write = rx_enable && (state == ST_PAYLOAD);
wire fifo_read;
wire fifo_empty;
wire [7:0] fifo_data;

//fifo read and write clocks
//reg rx_clk_en = 1'b0;
//always @(negedge rx_clock)
//  rx_clk_en <= (state == ST_IDLE) || (state == ST_HEADER) || (state == ST_PAYLOAD);
//reg tx_clk_en = 1'b0;
//always @(negedge tx_clock) 
//  tx_clk_en <= sending;  
//wire fifo_clock = rx_clk_en? rx_clock : tx_clk_en? tx_clock : 1'b0; 


        
//icmp_fifo icmp_fifo_inst (
//  .clock(fifo_clock),
//  .data(rx_data),
//  .rdreq(fifo_read),
//  .sclr(fifo_clear),
//  .wrreq(fifo_write),
//  .empty(fifo_empty),
//  .full(fifo_full),
//  .q(fifo_data)
//  );

icmp_fifo icmp_fifo_inst (
  .aclr(fifo_clear),
  .data(rx_data),
  .rdclk(tx_clock),
  .rdreq(fifo_read),
  .wrclk(rx_clock),
  .wrreq(fifo_write),
  .q(fifo_data),
  .rdempty(fifo_empty),
  .wrfull(fifo_full)
);

  
//-----------------------------------------------------------------------------
//                            ip checksum
//-----------------------------------------------------------------------------

// To calculate:  sum all the data and keep the bottom 16 bits, the top bits being the carry bits.
// Add the carry bits to the bottom 16 bits then invert, the result is the check sum.
// No need to add with carry since sum can never be large enough to cause a carry.

wire [15:0] checksum = ~(sum[15:0] + sum[31:16]);



//-----------------------------------------------------------------------------
//                               send
//-----------------------------------------------------------------------------
//transfer {ST_TXREQ} to tx clock domain  
sync sync_inst1(.clock(tx_clock), .sig_in(state == ST_TXREQ), .sig_out(tx_request));  


//transfer {sending} to rx clock domain
sync sync_inst2(.clock(rx_clock), .sig_in(sending), .sig_out(sending_sync));  


localparam HDR_LEN = 3'd4;
reg [2:0] tx_byte_no;
reg [15:0] delay;


always @(posedge tx_clock)
  begin
  //(sending) flag
  if (reset | fifo_empty ) sending <= false;
  else if (tx_enable) sending <= true;
  //(tx_byte_no) update
  if (!sending) tx_byte_no <= 3'b100;
  else tx_byte_no <= {1'b0,tx_byte_no[2:1]};
  end
      
  
assign tx_active = (tx_enable | sending); // & ~fifo_empty;

assign fifo_read = (tx_byte_no == 3'h0) && sending && tx_active;

assign tx_data = (tx_byte_no[2])? 8'b0 :
                 (tx_byte_no[1])? checksum[15:8] :
                 (tx_byte_no[0])? checksum[7:0] :
                  fifo_data; 

  
endmodule
//-----------------------------------------------------------------------------
//                    Copyright (c) 2012 HPSDR Team
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// demultiplex phy nibbles, produce clock signal depending on speed
//-----------------------------------------------------------------------------


module rgmii_recv (
  input reset, 

  //receive: data and active are valid at posedge of clock
  input  clock, 
  input  speed_1gb,
  output reg [7:0] data,
  output active,
  
  //hardware pins
  input  [3:0]PHY_RX,     
  input  PHY_DV
  //input  PHY_RX_CLOCK
  );
  
  
  
  
//-----------------------------------------------------------------------------
//Altera application note AN 477: Designing RGMII Interfaces with FPGAs and HardCopy ASICs
// http://www.altera.com/literature/an/AN477.pdf
//
//Reduced Gigabit Media Independent Interface: (RGMII) 12/10/2000 Version 1.3 
// http://www.hp.com/rnd/pdfs/RGMIIv1_3.pdf
//
//KSZ9021RL/RN Gigabit Ethernet Transceiver with RGMII Support 
//http://www.micrel.com/_PDF/Ethernet/datasheets/ksz9021rl-rn_ds.pdf
//-----------------------------------------------------------------------------





//-----------------------------------------------------------------------------
//          de-multiplex nibbles presented at both clock edges
//-----------------------------------------------------------------------------
wire rxdv_wire, error;
wire [7:0] data_wire;


ddio_in  ddio_in_inst (      
  .datain({PHY_DV, PHY_RX}),
  .inclock(clock),
  .dataout_l({rxdv_wire, data_wire[3:0]}),
  .dataout_h({error, data_wire[7:4]})
  );  
  
  

// Realign data for two cases of divided clock when 100 Mbs

reg   [4:0] realigned_l = 'h0;
reg         data_coming = 'b0;
reg         realign     = 'b0;

always @(posedge clock) begin
  realigned_l <= {error, data_wire[7:4]};
  if (realign) {data_coming,data} <= {realigned_l[4] & ~reset,data_wire[3:0],realigned_l[3:0]};
  else {data_coming,data} <= {rxdv_wire & ~reset,data_wire};
end

always @(posedge clock) begin
  if (~speed_1gb) begin
    if (~realign & error & ~rxdv_wire) realign <= 1'b1;
    else if (realign & rxdv_wire & ~realigned_l[4]) realign <= 1'b0;
  end else
    realign <= 1'b0;
end
  
  
//-----------------------------------------------------------------------------
//                          preamble detector
//-----------------------------------------------------------------------------
localparam MIN_PREAMBLE_LENGTH = 3'd5;


reg [2:0] preamble_cnt;
reg payload_coming = 0;


always @(posedge clock) 
  //RX-DV low, nothing is being received
  if (!data_coming) begin payload_coming <= 1'b0; preamble_cnt <= MIN_PREAMBLE_LENGTH; end
  //RX-DV high, but payload is not being received yet
  else if (!payload_coming) 
    //count preamble bytes
    if (data == 8'h55) begin if (preamble_cnt != 0) preamble_cnt <= preamble_cnt - 3'd1; end
    //enough preamble bytes plus SFD, payload follows
    else if ((preamble_cnt == 0) && (data == 8'hD5)) payload_coming <= 1'b1;
    //wrong byte received, reset preamble byte count
    else preamble_cnt <= MIN_PREAMBLE_LENGTH;
      
      
assign active = data_coming & payload_coming;
      

  
endmodule
  //
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Phil Harman VK6APH, Alex Shovkoplyas, VE3NEA.


//-----------------------------------------------------------------------------
// decode arp packet, generate reply
//-----------------------------------------------------------------------------

module arp (
  input reset, //when PHY not connected
  input rx_clock,  
  input rx_enable,  
  input [7:0] rx_data,
  input tx_clock, 
  input [47:0] local_mac, 
  input [31:0] local_ip,
  input [47:0] remote_mac,
  input tx_enable,  
 
  output [7:0] tx_data,
  output reg [47:0] destination_mac,  
  output tx_request,   
  output tx_active
);






//-----------------------------------------------------------------------------
//                                receive
//-----------------------------------------------------------------------------
//rx_bits = {80'h_0806_0001_0800_0604_0001, destination_mac, 32'bx, 48'bx, local_ip};


localparam ST_IDLE = 5'd1, ST_RX = 5'd2, ST_TXREQ = 5'd4, ST_TX = 5'd8, ST_ERR = 5'd16; 
reg [4:0] state = ST_IDLE;


localparam RX_LEN = 5'd28;
reg [4:0] byte_no;
reg [31:0] remote_ip;
wire sending_sync;


always @(posedge rx_clock)
  case (state)
    ST_IDLE:
      //rx_enable is high, start reception
      if (rx_enable) 
        begin 
        destination_mac <= remote_mac; 
        byte_no <= RX_LEN - 5'd2;
        state <= ST_RX; 
        end
         
    ST_RX:
      //rx_enable low, abort reception
      if (!rx_enable) state <= ST_IDLE;      
      else
        begin
        case (byte_no)
          //arp operation, h0001 = request
          21: if (rx_data != 8'h00) state <= ST_ERR;
          20: if (rx_data != 8'h01) state <= ST_ERR;
			 
//			 13: remote_ip[31:24]  <= rx_data;
//			 12: remote_ip[23:16]  <= rx_data;
//			 11: remote_ip[15:8]   <= rx_data;
//			 10: remote_ip[7:0]    <= rx_data;
            
//          //save sender's ip 
          10,11,12,13: remote_ip <= {remote_ip[23:0], rx_data};  

//			  3: if (rx_data != local_ip[31-:8]) state <= ST_ERR;
//			  2: if (rx_data != local_ip[31-:8]) state <= ST_ERR;
//			  1: if (rx_data != local_ip[31-:8]) state <= ST_ERR;
//			  0: begin 
//					if (rx_data != local_ip[31-:8]) state <= ST_ERR;
//               else state <= ST_TXREQ; 
//			     end 	
          0,1,2,3: 
            //compare target ip to our local_ip     
            if (rx_data != local_ip[byte_no*8+7 -:8]) state <= ST_ERR;
            //packet received, request permission to send reply
            else if (byte_no == 0) state <= ST_TXREQ;      
          endcase    
          
         byte_no <= byte_no - 5'd1;
         end
      
    //wait for permission to send
    ST_TXREQ: if (sending_sync) state <= ST_TX;    

    //wait for the end of sending
    ST_TX: if (!sending_sync) state <= ST_IDLE;
    
    //end of discarded packet
    ST_ERR: if (!rx_enable) state <= ST_IDLE;
  endcase
        
    


  
  
//-----------------------------------------------------------------------------
//                                  send
//-----------------------------------------------------------------------------
//message to send
localparam TX_LEN = 5'd30;
wire [TX_LEN*8-1:0] tx_bits = {80'h_0806_0001_0800_0604_0002, local_mac, local_ip, destination_mac, remote_ip};
reg [4:0] tx_byte_no;
assign tx_data = tx_bits[tx_byte_no*8+7 -:8];
  
  
//transfer {ST_TXREQ} to tx clock domain  
sync sync_inst1(.clock(tx_clock), .sig_in(state == ST_TXREQ), .sig_out(tx_request));  


//transfer {sending} to rx clock domain
localparam false = 1'b0, true = 1'b1;
reg sending = false;
sync sync_inst2(.clock(rx_clock), .sig_in(sending), .sig_out(sending_sync));  


assign tx_active = tx_enable | sending;


always @(posedge tx_clock)
  begin
  //reset is high, stop sending
  if (reset) sending <= false;
  //permission granted, start sending
  else if (tx_enable) sending <= true;
  
  if (tx_active)   
    //last byte sent
    if (tx_byte_no == 5'd0) sending <= false;
    //send next byte
    else tx_byte_no <= tx_byte_no - 5'd1;
  else
    //load data to send
    tx_byte_no <= TX_LEN - 5'd1;
  end
    

  
endmodule


module ethernet (
    // Send to ethernet
    input  clock_2_5MHz,
    input  tx_clock,
    input  rx_clock,
    output Tx_fifo_rdreq_o,
    input [7:0] PHY_Tx_data_i,
    input [10:0] PHY_Tx_rdused_i,

    input [7:0] sp_fifo_rddata_i,
    input  sp_data_ready_i,
    output sp_fifo_rdreq_o,

    // Receive from ethernet
    output Rx_enable_o,
    output [7:0] Rx_fifo_data_o,

    // Status
    output this_MAC_o,
    output run_o,
    input [1:0] dipsw_i,
    input [7:0] AssignNR,
    output speed_1gb,

    //hardware pins
    output [3:0]PHY_TX,
    output PHY_TX_EN,
    input  [3:0]PHY_RX,
    input  RX_DV,
    inout  PHY_MDIO,
    output PHY_MDC);


parameter MAC=0;
parameter IP=0;
parameter Hermes_serialno=0;

wire [7:0] network_status;

wire dst_unreachable;
wire udp_tx_request;
wire run;
wire wide_spectrum;
wire discovery_reply;
wire [15:0] to_port;
wire broadcast;
wire udp_rx_active;
wire [7:0] udp_rx_data;
wire rx_fifo_enable;
wire [7:0] rx_fifo_data;

wire [7:0] udp_tx_data;
wire [10:0] udp_tx_length;
wire udp_tx_enable;
wire udp_tx_active;

wire network_state;
wire [47:0] local_mac;

wire discovery_reply_sync;
wire run_sync;
wire wide_spectrum_sync;

wire [31:0] static_ip;

assign static_ip = IP;
assign local_mac =  {MAC[47:2],~dipsw_i[1],MAC[0]};

network network_inst(

  .clock_2_5MHz(clock_2_5MHz),

  .tx_clock(tx_clock),
  .udp_tx_request(udp_tx_request),
  .udp_tx_length({5'h00,udp_tx_length}),
  .udp_tx_data(udp_tx_data),
  .udp_tx_enable(udp_tx_enable),
  //.udp_tx_active(udp_tx_active), // dh: not a port in network module
  .run(run_sync),
  .port_id(8'h00),

  .rx_clock(rx_clock),
  .to_port(to_port),
  .udp_rx_data(udp_rx_data),
  .udp_rx_active(udp_rx_active),
  .broadcast(broadcast),
  .dst_unreachable(dst_unreachable),

  .static_ip(static_ip),
  .local_mac(local_mac),
  .speed_1gb(speed_1gb),
  //.network_state(network_state), //dh
  //.network_status(network_status), //dh

  .PHY_TX(PHY_TX),
  .PHY_TX_EN(PHY_TX_EN),
  .PHY_RX(PHY_RX),
  .PHY_DV(RX_DV),
    
  .PHY_MDIO(PHY_MDIO),
  .PHY_MDC(PHY_MDC)
);

Rx_recv rx_recv_inst(
    .rx_clk(rx_clock),
    .run(run),
    .wide_spectrum(wide_spectrum),
    .dst_unreachable(dst_unreachable),
    .discovery_reply(discovery_reply),
    .to_port(to_port),
    .broadcast(broadcast),
    .rx_valid(udp_rx_active),
    .rx_data(udp_rx_data),
    .rx_fifo_data(Rx_fifo_data_o),
    .rx_fifo_enable(Rx_enable_o)
);

// Only synchronizing one signal as run and wide_spectrum can take time to resolve meta stable state

sync sync_inst1(.clock(tx_clock), .sig_in(discovery_reply), .sig_out(discovery_reply_sync));

sync sync_inst2(.clock(tx_clock), .sig_in(run), .sig_out(run_sync));
//assign run_sync = run;

sync sync_inst3(.clock(tx_clock), .sig_in(wide_spectrum), .sig_out(wide_spectrum_sync));
//assign wide_spectrum_sync = wide_spectrum;

wire Tx_reset;

Tx_send tx_send_inst(
    .tx_clock(tx_clock),
    .Tx_reset(Tx_reset),
    .run(run_sync),
    .wide_spectrum(wide_spectrum_sync),
    .IP_valid(1'b1),
    .Hermes_serialno(Hermes_serialno),
    .IDHermesLite(dipsw_i[0]),
    .AssignNR(AssignNR),
    .PHY_Tx_data(PHY_Tx_data_i),
    .PHY_Tx_rdused(PHY_Tx_rdused_i),
    .Tx_fifo_rdreq(Tx_fifo_rdreq_o),
    .This_MAC(local_mac),
    .discovery(discovery_reply_sync),
    .sp_fifo_rddata(sp_fifo_rddata_i),
    .have_sp_data(sp_data_ready_i),
    .sp_fifo_rdreq(sp_fifo_rdreq_o),
    .udp_tx_enable(udp_tx_enable),
    .udp_tx_active(udp_tx_active),
    .udp_tx_request(udp_tx_request),
    .udp_tx_data(udp_tx_data),
    .udp_tx_length(udp_tx_length)
);

//assign This_MAC_o = local_mac;
assign this_MAC_o = network_status[0];

// FIXME: run_sync is in eth tx clock domain but used in 76 domain outside
assign run_o = run_sync;

// Set Tx_reset (no sdr send) if not in RUNNING or DHCP RENEW state
assign Tx_reset = network_state;


endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.

//  25 Sept 2014 - Modified initial register values to correct for 0.12nS rather than 0.2nS steps.
//                 Also added write to register 106h to turn off Tx Data Pad Skews.  Both these
//						 changes are due to errors in the original data sheet which was corrected Feb 2014.


//-----------------------------------------------------------------------------
// initialize the PHY device on startup and when allow_1Gbit changes
// by writing config data to its MDIO registers; 
// continuously read PHY status from the MDIO registers
//-----------------------------------------------------------------------------

module phy_cfg(
  //input
  input clock,        //2.5 MHZ
  input init_request,
  input allow_1Gbit,  //speed selection jumper: open 
  
  //output
  output reg [1:0] speed,
  output reg duplex,
  
  //hardware pins
  inout mdio_pin,
  output mdc_pin  
);


//-----------------------------------------------------------------------------
//                           initialization data
//-----------------------------------------------------------------------------

//mdio register values
wire [15:0] values [14:0];
assign values[14] = {6'b0, allow_1Gbit, 9'b0};

// FIXME: This can be optiimized using writes with increment
// convet to more standard ROM
// program address 2 register 4
assign values[13] = 16'h0002;
assign values[12] = 16'h0004;
assign values[11] = 16'h4002;
assign values[10] = 16'h0077;

// program address 2 register 5
assign values[9] = 16'h0002;
assign values[8] = 16'h0005;
assign values[7] = 16'h4002;
assign values[6] = 16'h7777;

// program address 2 register 8
assign values[5] = 16'h0002;
assign values[4] = 16'h0008;
assign values[3] = 16'h4002;
assign values[2] = 16'b0000000111101111;

assign values[1] = 16'h1300;
assign values[0] = 16'hxxxx;


//mdio register addresses 
wire [4:0] addresses [14:0];
assign addresses[14] = 9;
assign addresses[13] = 5'h0d;
assign addresses[12] = 5'h0e;
assign addresses[11] = 5'h0d;
assign addresses[10] = 5'h0e;

assign addresses[9] = 5'h0d;
assign addresses[8] = 5'h0e;
assign addresses[7] = 5'h0d;
assign addresses[6] = 5'h0e;

assign addresses[5] = 5'h0d;
assign addresses[4] = 5'h0e;
assign addresses[3] = 5'h0d;
assign addresses[2] = 5'h0e;

assign addresses[1] = 0;
assign addresses[0] = 31; 

reg [3:0] word_no; 






//-----------------------------------------------------------------------------
//                            state machine
//-----------------------------------------------------------------------------

//phy initialization required 
//if allow_1Gbit input has changed or init_request input was raised
reg last_allow_1Gbit, init_required;

wire ready;
wire [15:0] rd_data;
reg rd_request, wr_request;


//state machine  
localparam READING = 1'b0, WRITING = 1'b1;  
reg state = READING;  


always @(posedge clock)  
  begin
  if (init_request || (allow_1Gbit != last_allow_1Gbit)) 
    init_required <= 1;
  
  if (ready)
    case (state)
      READING:
        begin
        speed <= rd_data[6:5];
        duplex <= rd_data[3];
        
        if (init_required)
          begin
          wr_request <= 1;
          word_no <= 14;
          last_allow_1Gbit <= allow_1Gbit;
          state  <= WRITING;
          init_required <= 0;
          end
        else
          rd_request <= 1'b1;
        end

      WRITING:
        begin
        if (word_no == 4'b1) state <= READING;   // *** should this be == 0?
        else wr_request <= 1;
        word_no <= word_no - 4'b1;		  
        end
      endcase
		
  else //!ready
    begin
    rd_request <= 0;
    wr_request <= 0;
    end
  end

        
        
        
        
//-----------------------------------------------------------------------------
//                        MDIO interface to PHY
//-----------------------------------------------------------------------------


mdio mdio_inst (
  .clock(clock), 
  .addr(addresses[word_no]), 
  .rd_request(rd_request),
  .wr_request(wr_request),
  .ready(ready),
  .rd_data(rd_data),
  .wr_data(values[word_no]),
  .mdio_pin(mdio_pin),
  .mdc_pin(mdc_pin)
  );  
  



  
  
endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Phil Harman VK6APH, Alex Shovkoplyas, VE3NEA.


module ip_recv(
  //input data stream
  input clock, 
  input rx_enable,
  input [7:0] data,
  input broadcast,
  input [31:0] local_ip,

  //output
  output active,
  output reg is_icmp,
  output reg [31:0] remote_ip,
  output reg [31:0] to_ip
  );

  

  

localparam ST_IDLE = 4'd1, ST_HEADER = 4'd2, ST_PAYLOAD = 4'd4, ST_DONE = 4'd8;
reg[3:0] state;
reg [10:0] header_len, packet_len, byte_no;
reg [31:0] temp_remote_ip;

assign active = rx_enable & (state == ST_PAYLOAD);


always @(posedge clock)
  if (rx_enable)
    case (state)
      ST_IDLE:
        begin
        //save header length
        header_len <= {data[3:0], 2'b0};
        byte_no <= 11'd2;												// need to skip the next byte
        //is protocol = IPv4?
        state <= (data[7:4] == 4'h4)? ST_HEADER : ST_DONE;
        end
    
      ST_HEADER:
        begin        
        case (byte_no)
          //save packet length
			  3: packet_len[10:8] <= data [2:0];	
			  4: packet_len[7:0]  <= data;

			  //determine the protocol
			 10: if (data == 8'd1) is_icmp <= 1'b1;
				  else if (data == 8'h11)   // then will be udp
						is_icmp <= 1'b0;
				  else state <= ST_DONE;	  // neither so exit
            
			    //save sender's ip
			 13: temp_remote_ip[31:24] <= data;
			 14: temp_remote_ip[23:16] <= data;
			 15: temp_remote_ip[15:8]  <= data;
			 16: temp_remote_ip[7:0]   <= data;
				
          //verify broadcast - or save to_ip		 
	  17: begin 
	     remote_ip <= temp_remote_ip;
	     if (broadcast) begin 
		if (data != 8'd255 && data != local_ip[31-:8]) state <= ST_DONE;  
	     end
	     else  to_ip[31-:8] <= data;  // save the ip address this packet is addressed to
	  end
	  
	  18: if (broadcast) begin
	     if (data != 8'd255 && data != local_ip[23-:8]) state <= ST_DONE;
	  end 
	  else  to_ip[23-:8] <= data;
	  
	  19: if (broadcast) begin 
	     if (data != 8'd255 && data != local_ip[15-:8]) state <= ST_DONE;
	  end 
	  else  to_ip[15-:8] <= data;
	  
	  
	  20: 	if (broadcast) begin
	     if(data != 8'd255) state <= ST_DONE; 
	     else if (byte_no == header_len) begin
		byte_no <= 11'd1;
		state <= ST_PAYLOAD;
	     end
	  end				
	  else begin
	     to_ip[7-:8] <= data;
	     if (byte_no == header_len) begin
		byte_no <= 11'd1;
		state <= ST_PAYLOAD;
	     end 
	  end 
          
          default
            if (byte_no == header_len) state <= ST_PAYLOAD;
        endcase    
          
        byte_no <= byte_no + 11'd1;
        end
        
      ST_PAYLOAD:
        begin  
        //end of payload, ignore the ethernet crc that follows
        if (byte_no == packet_len) state <= ST_DONE;
        byte_no <= byte_no + 11'd1;
        end        
      endcase
      
  else //!rx_enable 
    state <= ST_IDLE;
    
  
  
endmodule
  
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2013 Alex Shovkoplyas, VE3NEA.



//-----------------------------------------------------------------------------
//                         calculation of crc32 
//-----------------------------------------------------------------------------
module crc32 (
  input clock,
  input clear,
  input enable,
  input [7:0] data,
  output [31:0] result
  );
  
  
wire [511:0] crc_table = {
  32'h4DBDF21C, 32'h500AE278, 32'h76D3D2D4, 32'h6B64C2B0,
  32'h3B61B38C, 32'h26D6A3E8, 32'h000F9344, 32'h1DB88320,
  32'hA005713C, 32'hBDB26158, 32'h9B6B51F4, 32'h86DC4190,
  32'hD6D930AC, 32'hCB6E20C8, 32'hEDB71064, 32'hF0000000};
  
  
reg [31:0] prev_result;


//process low nibble, then high nibble
wire [31:0] crc_lo = prev_result[31:4] ^ crc_table[511-32*(prev_result[3:0] ^ data[3:0]) -: 32]; 
wire [31:0] crc_hi = crc_lo[31:4] ^ crc_table[511-32*(crc_lo[3:0] ^ data[7:4]) -: 32]; 
  

//clear, compute, or hold  
always @(posedge clock)
  if (clear) prev_result <= 32'b0;
  else if (enable) prev_result <= crc_hi;


assign result = crc_hi;



endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.


module ip_send (
  input reset,
  input clock,
  input tx_enable,
  output active,

  input [7:0] data_in,
  output [7:0] data_out,
  input is_icmp,
  input [15:0] length,
  input [31:0] local_ip,
  input [31:0] destination_ip
  );
  
  
  
//-----------------------------------------------------------------------------
//                              ip header
//-----------------------------------------------------------------------------
//icmp or udp code
wire [7:0] protocol_code = is_icmp? 8'd1 : 8'd17;


//packet = header + payload 
wire [15:0] ip_packet_length = 16'd20 + length;
  
  
//ip checksum: 16 bit one's complement of the one's complement sum
wire [19:0] sum = 20'h0C500 + {4'b0, ip_packet_length} + {12'b0, protocol_code} + 
  {4'b0, local_ip[31:16]} + {4'b0, local_ip[15:0]} + 
  {4'b0, destination_ip[31:16]} + {4'b0, destination_ip[15:0]};  
  
wire [16:0] checksum_and_carry = {1'b0, sum[15:0]} + {13'b0, sum[19:16]};
wire [15:0] checksum = ~({15'b0, checksum_and_carry[16]} + checksum_and_carry[15:0]);


//ip header
localparam HDR_LEN = 5'd22;
localparam HI_BIT = HDR_LEN * 8 - 1;
wire [HI_BIT:0] tx_bits = {16'h0800, 16'h4500, ip_packet_length, 40'h0000_0000_80, protocol_code, checksum, local_ip, destination_ip};
reg [4:0] byte_no;


//shift register
reg [HI_BIT:0] shift_reg;
assign data_out = shift_reg[HI_BIT -: 8];




//-----------------------------------------------------------------------------
//                            state machine
//-----------------------------------------------------------------------------
localparam false = 1'b0, true = 1'b1;
reg sending = false;

assign active = tx_enable | sending;

  
always @(posedge clock)  
  begin
  //tx data
  if (active) shift_reg <= {shift_reg[HI_BIT-8:0], data_in};
  else shift_reg <= tx_bits;
  
  //send while payload is coming
  if (tx_enable) begin byte_no <= HDR_LEN - 5'd1; sending <= true; end
  //purge shift register
  else if (byte_no != 0) byte_no <= byte_no - 5'd1;
  //done
  else sending <= false;
  end
  
  
endmodule
  // megafunction wizard: %ALTDDIO_OUT%
// GENERATION: STANDARD
// VERSION: WM1.0
// MODULE: ALTDDIO_OUT 

// ============================================================
// File Name: ddio_out.v
// Megafunction Name(s):
// 			ALTDDIO_OUT
//
// Simulation Library Files(s):
// 			altera_mf
// ============================================================
// ************************************************************
// THIS IS A WIZARD-GENERATED FILE. DO NOT EDIT THIS FILE!
//
// 12.0 Build 178 05/31/2012 SJ Web Edition
// ************************************************************


//Copyright (C) 1991-2012 Altera Corporation
//Your use of Altera Corporation's design tools, logic functions 
//and other software and tools, and its AMPP partner logic 
//functions, and any output files from any of the foregoing 
//(including device programming or simulation files), and any 
//associated documentation or information are expressly subject 
//to the terms and conditions of the Altera Program License 
//Subscription Agreement, Altera MegaCore Function License 
//Agreement, or other applicable license agreement, including, 
//without limitation, that your use is for the sole purpose of 
//programming logic devices manufactured by Altera and sold by 
//Altera or its authorized distributors.  Please refer to the 
//applicable agreement for further details.


// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
(* blackbox *)
module ddio_out (
	datain_h,
	datain_l,
	outclock,
	dataout);

	input	[4:0]  datain_h;
	input	[4:0]  datain_l;
	input	  outclock;
	output	[4:0]  dataout;
/*
	wire [4:0] sub_wire0;
	wire [4:0] dataout = sub_wire0[4:0];

	altddio_out	ALTDDIO_OUT_component (
				.datain_h (datain_h),
				.datain_l (datain_l),
				.outclock (outclock),
				.dataout (sub_wire0),
				.aclr (1'b0),
				.aset (1'b0),
				.oe (1'b1),
				.oe_out (),
				.outclocken (1'b1),
				.sclr (1'b0),
				.sset (1'b0));
	defparam
		ALTDDIO_OUT_component.extend_oe_disable = "OFF",
		ALTDDIO_OUT_component.intended_device_family = "Cyclone IV E",
		ALTDDIO_OUT_component.invert_output = "OFF",
		ALTDDIO_OUT_component.lpm_hint = "UNUSED",
		ALTDDIO_OUT_component.lpm_type = "altddio_out",
		ALTDDIO_OUT_component.oe_reg = "UNREGISTERED",
		ALTDDIO_OUT_component.power_up_high = "OFF",
		ALTDDIO_OUT_component.width = 5;

*/
endmodule

// ============================================================
// CNX file retrieval info
// ============================================================
// Retrieval info: LIBRARY: altera_mf altera_mf.altera_mf_components.all
// Retrieval info: PRIVATE: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: EXTEND_OE_DISABLE STRING "OFF"
// Retrieval info: CONSTANT: INTENDED_DEVICE_FAMILY STRING "Cyclone III"
// Retrieval info: CONSTANT: INVERT_OUTPUT STRING "OFF"
// Retrieval info: CONSTANT: LPM_HINT STRING "UNUSED"
// Retrieval info: CONSTANT: LPM_TYPE STRING "altddio_out"
// Retrieval info: CONSTANT: OE_REG STRING "UNREGISTERED"
// Retrieval info: CONSTANT: POWER_UP_HIGH STRING "OFF"
// Retrieval info: CONSTANT: WIDTH NUMERIC "5"
// Retrieval info: USED_PORT: datain_h 0 0 5 0 INPUT NODEFVAL "datain_h[4..0]"
// Retrieval info: CONNECT: @datain_h 0 0 5 0 datain_h 0 0 5 0
// Retrieval info: USED_PORT: datain_l 0 0 5 0 INPUT NODEFVAL "datain_l[4..0]"
// Retrieval info: CONNECT: @datain_l 0 0 5 0 datain_l 0 0 5 0
// Retrieval info: USED_PORT: dataout 0 0 5 0 OUTPUT NODEFVAL "dataout[4..0]"
// Retrieval info: CONNECT: dataout 0 0 5 0 @dataout 0 0 5 0
// Retrieval info: USED_PORT: outclock 0 0 0 0 INPUT_CLK_EXT NODEFVAL "outclock"
// Retrieval info: CONNECT: @outclock 0 0 0 0 outclock 0 0 0 0
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out.v TRUE FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out.qip TRUE FALSE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out.bsf TRUE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out_inst.v TRUE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out_bb.v TRUE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out.inc FALSE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out.cmp FALSE TRUE
// Retrieval info: GEN_FILE: TYPE_NORMAL ddio_out.ppf TRUE FALSE
// Retrieval info: LIB_FILE: altera_mf
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


//  Metis code copyright 2010, 2011, 2012, 2013 Alex Shovkoplyas, VE3NEA.


//-----------------------------------------------------------------------------
// read/write the registers of a PHY device using its MDIO interface
//
// set addr, wr_data and start_xx on posedge of clock
// keep addr and wr_data valid until ready changes to high
//-----------------------------------------------------------------------------

module mdio(
  //control
  input clock,
  input [4:0]addr,
  input rd_request,
  input wr_request,
  output ready,
  
  //data
  input [15:0] wr_data,
  output reg [15:0] rd_data,  
  
  //hardware pins
  inout mdio_pin,
  output mdc_pin
  );


//bits to send
`ifdef BETA2
wire [63:0] wr_bits = {32'hFFFFFFFF, 9'b010100100, addr, 2'b10, wr_data};
wire [63:0] rd_bits = {32'hFFFFFFFF, 9'b011000100, addr, 2'bxx, 16'hFFFF};
`else
wire [63:0] wr_bits = {32'hFFFFFFFF, 9'b010100111, addr, 2'b10, wr_data};  // PHYAD[4:0]=5'h7
wire [63:0] rd_bits = {32'hFFFFFFFF, 9'b011000111, addr, 2'bxx, 16'hFFFF}; // PHYAD[4:0]=5'h7
`endif

reg[ 5:0] bit_no;
  

//state  
localparam ST_IDLE = 3'd1, ST_READING = 3'd2, ST_WRITING = 3'd4;  
reg[2:0] state = ST_IDLE; 


//3-state mdio pin
reg mdio_high_z;
assign mdio_pin = mdio_high_z ? 1'bz : (state == ST_READING ? rd_bits[bit_no] : wr_bits[bit_no]);


//state machine  
always @(negedge clock)  
  case (state)
    ST_IDLE:
      begin
      mdio_high_z <= 0;
      bit_no <= 63; 
      if (rd_request) state <= ST_READING;
      else if (wr_request) state <= ST_WRITING;
      end

    ST_READING:
      begin
      if (bit_no == 18) mdio_high_z <= 1;
      rd_data <= {rd_data[14:0], mdio_pin};
      if (bit_no == 1) state <= ST_IDLE;
      bit_no <= bit_no - 6'b1;
      end

    ST_WRITING:
      begin
      if (bit_no == 0) state <= ST_IDLE; 
      bit_no <= bit_no - 6'b1;
      end

    default
      state <= ST_IDLE;
  endcase  

  


//control 
assign mdc_pin = clock;
assign ready = (state == ST_IDLE);






endmodule
//
//  Hermes Lite
// 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// (C) Steve Haynal KF7O 2014-2018

module ad9866ctrl (
  clk,
  rst,

  rffe_ad9866_sdio,
  rffe_ad9866_sclk,
  rffe_ad9866_sen_n,

`ifdef BETA2
  rffe_ad9866_pga,
`else
  rffe_ad9866_pga5,
`endif

  // Command slave interface
  cmd_addr,
  cmd_data,
  cmd_rqst,
  cmd_ack
);

input             clk;
input             rst;

output logic            rffe_ad9866_sdio;
output logic            rffe_ad9866_sclk;
output logic            rffe_ad9866_sen_n;

`ifdef BETA2
output logic  [5:0]     rffe_ad9866_pga;
`else
output logic            rffe_ad9866_pga5;
`endif

// Command slave interface
input  [5:0]      cmd_addr;
input  [31:0]     cmd_data;
input             cmd_rqst;
output logic      cmd_ack = 1'b0;   


// SPI
logic   [15:0]    datain;
logic             start;
logic   [3:0]     dut2_bitcount;
logic             dut2_state;
logic   [15:0]    dut2_data;
logic   [5:0]     dut1_pc;
logic             sdo;

logic             cmd_ack_next;
logic             istart;

logic   [8:0]     initarrayv;
// Tool problems if below is logic
reg     [8:0]     initarray [19:0];

localparam 
  CMD_IDLE    = 2'b00,
  CMD_TXGAIN  = 2'b01,
  CMD_RXGAIN  = 2'b11,
  CMD_WRITE   = 2'b10;

// Command slave
logic [1:0]       cmd_state = CMD_IDLE;
logic [1:0]       cmd_state_next;
logic [3:0]       tx_gain = 4'h0;
logic [3:0]       tx_gain_next;
logic [6:0]       rx_gain = 7'b1000000;
logic [6:0]       rx_gain_next;

logic [12:0]      icmd_data = 12'h000;

initial begin
  // First bit is 1'b1 for write enable to that address
  initarray[0] = {1'b0,8'h80}; // Address 0x00, enable 4 wire SPI
  initarray[1] = {1'b0,8'h00}; // Address 0x01,
  initarray[2] = {1'b0,8'h00}; // Address 0x02,
  initarray[3] = {1'b0,8'h00}; // Address 0x03,
  initarray[4] = {1'b0,8'h00}; // Address 0x04,
  initarray[5] = {1'b0,8'h00}; // Address 0x05,
  initarray[6] = {1'b1,8'h54}; // Address 0x06, Disable clkout2
  initarray[7] = {1'b1,8'h30}; // Address 0x07, Initiate DC offset calibration and RX filter on, 21 to 20 to disable RX filter
  initarray[8] = {1'b0,8'h4b}; // Address 0x08, RX filter f-3db at ~34 MHz after scaling
  initarray[9] = {1'b0,8'h00}; // Address 0x09,
  initarray[10] = {1'b0,8'h00}; // Address 0x0a,
  initarray[11] = {1'b1,8'h00}; // Address 0x0b, No RX gain on PGA
  initarray[12] = {1'b1,8'h43}; // Address 0x0c, TX twos complement and interpolation factor
  initarray[13] = {1'b1,8'h03}; // Address 0x0d, RX twos complement
  initarray[14] = {1'b1,8'h81}; // Address 0x0e, Enable/Disable IAMP
  initarray[15] = {1'b0,8'h00}; // Address 0x0f,
  initarray[16] = {1'b1,8'h80}; // Address 0x10, Select TX gain
  initarray[17] = {1'b1,8'h00}; // Address 0x11, Select TX gain
  initarray[18] = {1'b1,8'h00}; // Address 0x12,
  initarray[19] = {1'b0,8'h00}; // Address 0x13,
end

`ifdef BETA2
assign rffe_ad9866_pga = 6'b000000;
`else
assign rffe_ad9866_pga5 = 1'b0;
`endif


// Command Slave State Machine
always @(posedge clk) begin
  cmd_state <= cmd_state_next;
  tx_gain <= tx_gain_next;
  rx_gain <= rx_gain_next;
  cmd_ack <= cmd_ack_next;
end

always @* begin
  cmd_state_next = cmd_state;
  tx_gain_next = tx_gain;
  rx_gain_next = rx_gain;
  cmd_ack_next = cmd_ack;
  istart = 1'b0;

  icmd_data  = {cmd_data[20:16],cmd_data[7:0]};

  case(cmd_state)

    CMD_IDLE: begin
      if (cmd_rqst) begin
        cmd_ack_next = 1'b1; // Assume acknowledge
        // Accept possible write
        case (cmd_addr)
          // Hermes TX Gain Setting
          6'h09: begin
            if (tx_gain != cmd_data[31:28]) begin
              // Must update
              if (rffe_ad9866_sen_n) begin
                tx_gain_next = cmd_data[31:28];
                cmd_state_next = CMD_TXGAIN;
              end else begin
                cmd_ack_next = 1'b0;
              end
            end
          end

          // Hermes RX Gain Setting
          6'h0a: begin
            if (rx_gain != cmd_data[6:0]) begin
              // Must update
              if (rffe_ad9866_sen_n) begin
                rx_gain_next = cmd_data[6:0];
                cmd_state_next = CMD_RXGAIN;
              end else begin
                cmd_ack_next = 1'b0;
              end
            end
          end

          // Generic AD9866 write
          6'h3b: begin
            if (cmd_data[31:24] == 8'h06) begin
              // Must write
              if (rffe_ad9866_sen_n) cmd_state_next = CMD_WRITE;
              else cmd_ack_next = 1'b0;
            end
          end

          default: cmd_state_next = cmd_state;

        endcase 
      end        
    end

    CMD_TXGAIN: begin
      istart     = 1'b1;
      icmd_data  = {5'h0a,4'b0100,tx_gain};
      cmd_state_next = CMD_IDLE;
    end
    
    CMD_RXGAIN: begin
      istart          = 1'b1;
      icmd_data[12:6] = {5'h09,2'b01};
      icmd_data[5:0]  = rx_gain[6] ? rx_gain[5:0] : (rx_gain[5] ? ~rx_gain[5:0] : {1'b1,rx_gain[4:0]});
      cmd_state_next  = CMD_IDLE;
    end

    CMD_WRITE: begin
      istart          = 1'b1;
      icmd_data       = {cmd_data[20:16],cmd_data[7:0]};
      cmd_state_next  = CMD_IDLE;
    end

  endcase
end

// SPI interface
assign sdo       = 1'b0;

// Init program counter
always @(posedge clk) begin: AD9866_DUT1_FSM
    if (rst) begin
        dut1_pc <= 6'h00;
    end
    else begin
        if ((dut1_pc != 6'h3f) & rffe_ad9866_sen_n) begin
            dut1_pc <= (dut1_pc + 6'h01);
        end
        // Toggle LSB
        else if ((dut1_pc == 6'h3f) & rffe_ad9866_sen_n) begin
            dut1_pc <= 6'h3e;
        end
    end
end

always @* begin
    initarrayv = initarray[dut1_pc[5:1]];
    datain = {3'b000,icmd_data};   
    start = 1'b0;
    if (rffe_ad9866_sen_n) begin
        if (dut1_pc[5:1] <= 6'h13) begin
            if (dut1_pc[0] == 1'b0) begin
                
                datain = {3'h0,dut1_pc[5:1],initarrayv[7:0]};
                start = initarrayv[8];
            end
        end else begin
            start = istart;
        end
    end
end

//assign dataout = dut2_data[8-1:0];
assign rffe_ad9866_sdio = dut2_data[15];

// SPI state machine
always @(posedge clk) begin: AD9866_DUT2_FSM
  if (rst) begin
    rffe_ad9866_sen_n <= 1;
    rffe_ad9866_sclk <= 0;
    dut2_state <= 1'b0;
    dut2_data <= 0;
    dut2_bitcount <= 0;
  end
  else begin
    case (dut2_state)
      1'b0: begin
        rffe_ad9866_sclk <= 0;
        dut2_bitcount <= 15;
        if (start) begin
          dut2_data <= datain;
          rffe_ad9866_sen_n <= 0;
          dut2_state <= 1'b1;
        end
        else begin
          rffe_ad9866_sen_n <= 1;
        end
      end
      1'b1: begin
        dut2_state <= 1'b1;
        if ((!rffe_ad9866_sclk)) begin
          rffe_ad9866_sclk <= 1;
        end
        else begin
          dut2_data <= {dut2_data[15-1:0], sdo};
          dut2_bitcount <= (dut2_bitcount - 4'h1);
          rffe_ad9866_sclk <= 0;
          if ((dut2_bitcount == 0)) begin
            dut2_state <= 1'b0;
          end
        end
      end
    endcase
  end
end

endmodule // ad9866ctrl

/*

Copyright (c) 2015-2016 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`timescale 1ns / 1ps

/*
 * I2C master
 */
module i2c_master (
    input  wire        clk,
    input  wire        rst,

    /*
     * Host interface
     */
    input  wire [6:0]  cmd_address,
    input  wire        cmd_start,
    input  wire        cmd_read,
    input  wire        cmd_write,
    input  wire        cmd_write_multiple,
    input  wire        cmd_stop,
    input  wire        cmd_valid,
    output wire        cmd_ready,

    input  wire [7:0]  data_in,
    input  wire        data_in_valid,
    output wire        data_in_ready,
    input  wire        data_in_last,

    output wire [7:0]  data_out,
    output wire        data_out_valid,
    input  wire        data_out_ready,
    output wire        data_out_last,

    /*
     * I2C interface
     */
    input  wire        scl_i,
    output wire        scl_o,
    output wire        scl_t,
    input  wire        sda_i,
    output wire        sda_o,
    output wire        sda_t,

    /*
     * Status
     */
    output wire        busy,
    output wire        bus_control,
    output wire        bus_active,
    output wire        missed_ack,

    /*
     * Configuration
     */
    input  wire [15:0] prescale,
    input  wire        stop_on_idle
);

/*

I2C

Read
    __    ___ ___ ___ ___ ___ ___ ___         ___ ___ ___ ___ ___ ___ ___ ___     ___ ___ ___ ___ ___ ___ ___ ___        __
sda   \__/_6_X_5_X_4_X_3_X_2_X_1_X_0_\_R___A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_\_A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_\_A____/
    ____   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   ____
scl  ST \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ SP

Write
    __    ___ ___ ___ ___ ___ ___ ___ ___     ___ ___ ___ ___ ___ ___ ___ ___     ___ ___ ___ ___ ___ ___ ___ ___ ___    __
sda   \__/_6_X_5_X_4_X_3_X_2_X_1_X_0_/_W_\_A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_\_A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_/_N_\__/
    ____   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   ____
scl  ST \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ SP

Commands:

read
    read data byte
    set start to force generation of a start condition
    start is implied when bus is inactive or active with write or different address
    set stop to issue a stop condition after reading current byte
    if stop is set with read command, then data_out_last will be set

write
    write data byte
    set start to force generation of a start condition
    start is implied when bus is inactive or active with read or different address
    set stop to issue a stop condition after writing current byte

write multiple
    write multiple data bytes (until data_in_last)
    set start to force generation of a start condition
    start is implied when bus is inactive or active with read or different address
    set stop to issue a stop condition after writing block

stop
    issue stop condition if bus is active

Status:

busy
    module is communicating over the bus

bus_control
    module has control of bus in active state

bus_active
    bus is active, not necessarily controlled by this module

missed_ack
    strobed when a slave ack is missed

Parameters:

prescale
    set prescale to 1/4 of the minimum clock period in units
    of input clk cycles (prescale = Fclk / (FI2Cclk * 4))

stop_on_idle
    automatically issue stop when command input is not valid

Example of interfacing with tristate pins:
(this will work for any tristate bus)

assign scl_i = scl_pin;
assign scl_pin = scl_t ? 1'bz : scl_o;
assign sda_i = sda_pin;
assign sda_pin = sda_t ? 1'bz : sda_o;

Equivalent code that does not use *_t connections:
(we can get away with this because I2C is open-drain)

assign scl_i = scl_pin;
assign scl_pin = scl_o ? 1'bz : 1'b0;
assign sda_i = sda_pin;
assign sda_pin = sda_o ? 1'bz : 1'b0;

Example of two interconnected I2C devices:

assign scl_1_i = scl_1_o & scl_2_o;
assign scl_2_i = scl_1_o & scl_2_o;
assign sda_1_i = sda_1_o & sda_2_o;
assign sda_2_i = sda_1_o & sda_2_o;

Example of two I2C devices sharing the same pins:

assign scl_1_i = scl_pin;
assign scl_2_i = scl_pin;
assign scl_pin = (scl_1_o & scl_2_o) ? 1'bz : 1'b0;
assign sda_1_i = sda_pin;
assign sda_2_i = sda_pin;
assign sda_pin = (sda_1_o & sda_2_o) ? 1'bz : 1'b0;

Notes:

scl_o should not be connected directly to scl_i, only via AND logic or a tristate
I/O pin.  This would prevent devices from stretching the clock period.

*/

localparam [4:0]
    STATE_IDLE = 4'd0,
    STATE_ACTIVE_WRITE = 4'd1,
    STATE_ACTIVE_READ = 4'd2,
    STATE_START_WAIT = 4'd3,
    STATE_START = 4'd4,
    STATE_ADDRESS_1 = 4'd5,
    STATE_ADDRESS_2 = 4'd6,
    STATE_WRITE_1 = 4'd7,
    STATE_WRITE_2 = 4'd8,
    STATE_WRITE_3 = 4'd9,
    STATE_READ = 4'd10,
    STATE_STOP = 4'd11;

reg [4:0] state_reg = STATE_IDLE, state_next;

localparam [4:0]
    PHY_STATE_IDLE = 5'd0,
    PHY_STATE_ACTIVE = 5'd1,
    PHY_STATE_REPEATED_START_1 = 5'd2,
    PHY_STATE_REPEATED_START_2 = 5'd3,
    PHY_STATE_START_1 = 5'd4,
    PHY_STATE_START_2 = 5'd5,
    PHY_STATE_WRITE_BIT_1 = 5'd6,
    PHY_STATE_WRITE_BIT_2 = 5'd7,
    PHY_STATE_WRITE_BIT_3 = 5'd8,
    PHY_STATE_READ_BIT_1 = 5'd9,
    PHY_STATE_READ_BIT_2 = 5'd10,
    PHY_STATE_READ_BIT_3 = 5'd11,
    PHY_STATE_READ_BIT_4 = 5'd12,
    PHY_STATE_STOP_1 = 5'd13,
    PHY_STATE_STOP_2 = 5'd14,
    PHY_STATE_STOP_3 = 5'd15;

reg [4:0] phy_state_reg = STATE_IDLE, phy_state_next;

reg phy_start_bit;
reg phy_stop_bit;
reg phy_write_bit;
reg phy_read_bit;
reg phy_release_bus;

reg phy_tx_data;

reg phy_rx_data_reg = 1'b0, phy_rx_data_next;

reg [6:0] addr_reg = 7'd0, addr_next;
reg [7:0] data_reg = 8'd0, data_next;
reg last_reg = 1'b0, last_next;

reg mode_read_reg = 1'b0, mode_read_next;
reg mode_write_multiple_reg = 1'b0, mode_write_multiple_next;
reg mode_stop_reg = 1'b0, mode_stop_next;

reg [16:0] delay_reg = 16'd0, delay_next;
reg delay_scl_reg = 1'b0, delay_scl_next;
reg delay_sda_reg = 1'b0, delay_sda_next;

reg [3:0] bit_count_reg = 4'd0, bit_count_next;

reg cmd_ready_reg = 1'b0, cmd_ready_next;

reg data_in_ready_reg = 1'b0, data_in_ready_next;

reg [7:0] data_out_reg = 8'd0, data_out_next;
reg data_out_valid_reg = 1'b0, data_out_valid_next;
reg data_out_last_reg = 1'b0, data_out_last_next;

reg scl_i_reg = 1'b1;
reg sda_i_reg = 1'b1;

reg scl_o_reg = 1'b1, scl_o_next;
reg sda_o_reg = 1'b1, sda_o_next;

reg last_scl_i_reg = 1'b1;
reg last_sda_i_reg = 1'b1;

reg busy_reg = 1'b0;
reg bus_active_reg = 1'b0;
reg bus_control_reg = 1'b0, bus_control_next;
reg missed_ack_reg = 1'b0, missed_ack_next;

assign cmd_ready = cmd_ready_reg;

assign data_in_ready = data_in_ready_reg;

assign data_out = data_out_reg;
assign data_out_valid = data_out_valid_reg;
assign data_out_last = data_out_last_reg;

assign scl_o = scl_o_reg;
assign scl_t = scl_o_reg;
assign sda_o = sda_o_reg;
assign sda_t = sda_o_reg;

assign busy = busy_reg;
assign bus_active = bus_active_reg;
assign bus_control = bus_control_reg;
assign missed_ack = missed_ack_reg;

wire scl_posedge = scl_i_reg & ~last_scl_i_reg;
wire scl_negedge = ~scl_i_reg & last_scl_i_reg;
wire sda_posedge = sda_i_reg & ~last_sda_i_reg;
wire sda_negedge = ~sda_i_reg & last_sda_i_reg;

wire start_bit = sda_negedge & scl_i_reg;
wire stop_bit = sda_posedge & scl_i_reg;

always @* begin
    state_next = STATE_IDLE;

    phy_start_bit = 1'b0;
    phy_stop_bit = 1'b0;
    phy_write_bit = 1'b0;
    phy_read_bit = 1'b0;
    phy_tx_data = 1'b0;
    phy_release_bus = 1'b0;

    addr_next = addr_reg;
    data_next = data_reg;
    last_next = last_reg;

    mode_read_next = mode_read_reg;
    mode_write_multiple_next = mode_write_multiple_reg;
    mode_stop_next = mode_stop_reg;

    bit_count_next = bit_count_reg;

    cmd_ready_next = 1'b0;

    data_in_ready_next = 1'b0;

    data_out_next = data_out_reg;
    data_out_valid_next = data_out_valid_reg & ~data_out_ready;
    data_out_last_next = data_out_last_reg;

    missed_ack_next = 1'b0;

    // generate delays
    if (phy_state_reg != PHY_STATE_IDLE && phy_state_reg != PHY_STATE_ACTIVE) begin
        // wait for phy operation
        state_next = state_reg;
    end else begin
        // process states
        case (state_reg)
            STATE_IDLE: begin
                // line idle
                cmd_ready_next = 1'b1;

                if (cmd_ready & cmd_valid) begin
                    // command valid
                    if (cmd_read ^ (cmd_write | cmd_write_multiple)) begin
                        // read or write command
                        addr_next = cmd_address;
                        mode_read_next = cmd_read;
                        mode_write_multiple_next = cmd_write_multiple;
                        mode_stop_next = cmd_stop;

                        cmd_ready_next = 1'b0;

                        // start bit
                        if (bus_active) begin
                            state_next = STATE_START_WAIT;
                        end else begin
                            phy_start_bit = 1'b1;
                            bit_count_next = 4'd8;
                            state_next = STATE_ADDRESS_1;
                        end
                    end else begin
                        // invalid or unspecified - ignore
                        state_next = STATE_IDLE;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_ACTIVE_WRITE: begin
                // line active with current address and read/write mode
                cmd_ready_next = 1'b1;

                if (cmd_ready & cmd_valid) begin
                    // command valid
                    if (cmd_read ^ (cmd_write | cmd_write_multiple)) begin
                        // read or write command
                        addr_next = cmd_address;
                        mode_read_next = cmd_read;
                        mode_write_multiple_next = cmd_write_multiple;
                        mode_stop_next = cmd_stop;

                        cmd_ready_next = 1'b0;
                        
                        if (cmd_start || cmd_address != addr_reg || cmd_read) begin
                            // address or mode mismatch or forced start - repeated start

                            // repeated start bit
                            phy_start_bit = 1'b1;
                            bit_count_next = 4'd8;
                            state_next = STATE_ADDRESS_1;
                        end else begin
                            // address and mode match

                            // start write
                            data_in_ready_next = 1'b1;
                            state_next = STATE_WRITE_1;
                        end
                    end else if (cmd_stop && !(cmd_read || cmd_write || cmd_write_multiple)) begin
                        // stop command
                        phy_stop_bit = 1'b1;
                        state_next = STATE_IDLE;
                    end else begin
                        // invalid or unspecified - ignore
                        state_next = STATE_ACTIVE_WRITE;
                    end
                end else begin
                    if (stop_on_idle & cmd_ready & ~cmd_valid) begin
                        // no waiting command and stop_on_idle selected, issue stop condition
                        phy_stop_bit = 1'b1;
                        state_next = STATE_IDLE;
                    end else begin
                        state_next = STATE_ACTIVE_WRITE;
                    end
                end
            end
            STATE_ACTIVE_READ: begin
                // line active to current address
                cmd_ready_next = ~data_out_valid;

                if (cmd_ready & cmd_valid) begin
                    // command valid
                    if (cmd_read ^ (cmd_write | cmd_write_multiple)) begin
                        // read or write command
                        addr_next = cmd_address;
                        mode_read_next = cmd_read;
                        mode_write_multiple_next = cmd_write_multiple;
                        mode_stop_next = cmd_stop;

                        cmd_ready_next = 1'b0;
                        
                        if (cmd_start || cmd_address != addr_reg || cmd_write) begin
                            // address or mode mismatch or forced start - repeated start

                            // write nack for previous read
                            phy_write_bit = 1'b1;
                            phy_tx_data = 1'b1;
                            // repeated start bit
                            state_next = STATE_START;
                        end else begin
                            // address and mode match

                            // write ack for previous read
                            phy_write_bit = 1'b1;
                            phy_tx_data = 1'b0;
                            // start next read
                            bit_count_next = 4'd8;
                            data_next = 8'd0;
                            state_next = STATE_READ;
                        end
                    end else if (cmd_stop && !(cmd_read || cmd_write || cmd_write_multiple)) begin
                        // stop command
                        // write nack for previous read
                        phy_write_bit = 1'b1;
                        phy_tx_data = 1'b1;
                        // send stop bit
                        state_next = STATE_STOP;
                    end else begin
                        // invalid or unspecified - ignore
                        state_next = STATE_ACTIVE_READ;
                    end
                end else begin
                    if (stop_on_idle & cmd_ready & ~cmd_valid) begin
                        // no waiting command and stop_on_idle selected, issue stop condition
                        // write ack for previous read
                        phy_write_bit = 1'b1;
                        phy_tx_data = 1'b1;
                        // send stop bit
                        state_next = STATE_STOP;
                    end else begin
                        state_next = STATE_ACTIVE_READ;
                    end
                end
            end
            STATE_START_WAIT: begin
                // wait for bus idle

                if (bus_active) begin
                    state_next = STATE_START_WAIT;
                end else begin
                    // bus is idle, take control
                    phy_start_bit = 1'b1;
                    bit_count_next = 4'd8;
                    state_next = STATE_ADDRESS_1;
                end
            end
            STATE_START: begin
                // send start bit

                phy_start_bit = 1'b1;
                bit_count_next = 4'd8;
                state_next = STATE_ADDRESS_1;
            end
            STATE_ADDRESS_1: begin
                // send address
                bit_count_next = bit_count_reg - 1;
                if (bit_count_reg > 1) begin
                    // send address
                    phy_write_bit = 1'b1;
                    phy_tx_data = addr_reg[bit_count_reg-2];
                    state_next = STATE_ADDRESS_1;
                end else if (bit_count_reg > 0) begin
                    // send read/write bit
                    phy_write_bit = 1'b1;
                    phy_tx_data = mode_read_reg;
                    state_next = STATE_ADDRESS_1;
                end else begin
                    // read ack bit
                    phy_read_bit = 1'b1;
                    state_next = STATE_ADDRESS_2;
                end
            end
            STATE_ADDRESS_2: begin
                // read ack bit
                missed_ack_next = phy_rx_data_reg;

                if (mode_read_reg) begin
                    // start read
                    bit_count_next = 4'd8;
                    data_next = 1'b0;
                    state_next = STATE_READ;
                end else begin
                    // start write
                    data_in_ready_next = 1'b1;
                    state_next = STATE_WRITE_1;
                end
            end
            STATE_WRITE_1: begin
                data_in_ready_next = 1'b1;

                if (data_in_ready & data_in_valid) begin
                    // got data, start write
                    data_next = data_in;
                    last_next = data_in_last;
                    bit_count_next = 4'd8;
                    data_in_ready_next = 1'b0;
                    state_next = STATE_WRITE_2;
                end else begin
                    // wait for data
                    state_next = STATE_WRITE_1;
                end
            end
            STATE_WRITE_2: begin
                // send data
                bit_count_next = bit_count_reg - 1;
                if (bit_count_reg > 0) begin
                    // write data bit
                    phy_write_bit = 1'b1;
                    phy_tx_data = data_reg[bit_count_reg-1];
                    state_next = STATE_WRITE_2;
                end else begin
                    // read ack bit
                    phy_read_bit = 1'b1;
                    state_next = STATE_WRITE_3;
                end
            end
            STATE_WRITE_3: begin
                // read ack bit
                missed_ack_next = phy_rx_data_reg;

                if (mode_write_multiple_reg && !last_reg) begin
                    // more to write
                    state_next = STATE_WRITE_1;
                end else if (mode_stop_reg) begin
                    // last cycle and stop selected
                    phy_stop_bit = 1'b1;
                    state_next = STATE_IDLE;
                end else begin
                    // otherwise, return to bus active state
                    state_next = STATE_ACTIVE_WRITE;
                end
            end
            STATE_READ: begin
                // read data

                bit_count_next = bit_count_reg - 1;
                data_next = {data_reg[6:0], phy_rx_data_reg};
                if (bit_count_reg > 0) begin
                    // read next bit
                    phy_read_bit = 1'b1;
                    state_next = STATE_READ;
                end else begin
                    // output data word
                    data_out_next = data_next;
                    data_out_valid_next = 1'b1;
                    data_out_last_next = 1'b0;
                    if (mode_stop_reg) begin
                        // send nack and stop
                        data_out_last_next = 1'b1;
                        phy_write_bit = 1'b1;
                        phy_tx_data = 1'b1;
                        state_next = STATE_STOP;
                    end else begin
                        // return to bus active state
                        state_next = STATE_ACTIVE_READ;
                    end
                end
            end
            STATE_STOP: begin
                // send stop bit
                phy_stop_bit = 1'b1;
                state_next = STATE_IDLE;
            end
        endcase
    end
end

always @* begin
    phy_state_next = PHY_STATE_IDLE;

    phy_rx_data_next = phy_rx_data_reg;

    delay_next = delay_reg;
    delay_scl_next = delay_scl_reg;
    delay_sda_next = delay_sda_reg;

    scl_o_next = scl_o_reg;
    sda_o_next = sda_o_reg;

    bus_control_next = bus_control_reg;

    if (phy_release_bus) begin
        // release bus and return to idle state
        sda_o_next = 1'b1;
        scl_o_next = 1'b1;
        delay_scl_next = 1'b0;
        delay_sda_next = 1'b0;
        delay_next = 1'b0;
        phy_state_next = PHY_STATE_IDLE;
    end else if (delay_scl_reg) begin
        // wait for SCL to match command
        delay_scl_next = scl_o_reg & ~scl_i_reg;
        phy_state_next = phy_state_reg;
    end else if (delay_sda_reg) begin
        // wait for SDA to match command
        delay_sda_next = sda_o_reg & ~sda_i_reg;
        phy_state_next = phy_state_reg;
    end else if (delay_reg > 0) begin
        // time delay
        delay_next = delay_reg - 1;
        phy_state_next = phy_state_reg;
    end else begin
        case (phy_state_reg)
            PHY_STATE_IDLE: begin
                // bus idle - wait for start command
                sda_o_next = 1'b1;
                scl_o_next = 1'b1;
                if (phy_start_bit) begin
                    sda_o_next = 1'b0;
                    delay_next = prescale;
                    phy_state_next = PHY_STATE_START_1;
                end else begin
                    phy_state_next = PHY_STATE_IDLE;
                end
            end
            PHY_STATE_ACTIVE: begin
                // bus active
                if (phy_start_bit) begin
                    sda_o_next = 1'b1;
                    delay_next = prescale;
                    phy_state_next = PHY_STATE_REPEATED_START_1;
                end else if (phy_write_bit) begin
                    sda_o_next = phy_tx_data;
                    delay_next = prescale;
                    phy_state_next = PHY_STATE_WRITE_BIT_1;
                end else if (phy_read_bit) begin
                    sda_o_next = 1'b1;
                    delay_next = prescale;
                    phy_state_next = PHY_STATE_READ_BIT_1;
                end else if (phy_stop_bit) begin
                    sda_o_next = 1'b0;
                    delay_next = prescale;
                    phy_state_next = PHY_STATE_STOP_1;
                end else begin
                    phy_state_next = PHY_STATE_ACTIVE;
                end
            end
            PHY_STATE_REPEATED_START_1: begin
                // generate repeated start bit
                //         ______
                // sda XXX/      \_______
                //            _______
                // scl ______/       \___
                //

                scl_o_next = 1'b1;
                delay_scl_next = 1'b1;
                delay_next = prescale;
                phy_state_next = PHY_STATE_REPEATED_START_2;
            end
            PHY_STATE_REPEATED_START_2: begin
                // generate repeated start bit
                //         ______
                // sda XXX/      \_______
                //            _______
                // scl ______/       \___
                //

                sda_o_next = 1'b0;
                delay_next = prescale;
                phy_state_next = PHY_STATE_START_1;
            end
            PHY_STATE_START_1: begin
                // generate start bit
                //     ___
                // sda    \_______
                //     _______
                // scl        \___
                //

                scl_o_next = 1'b0;
                delay_next = prescale;
                phy_state_next = PHY_STATE_START_2;
            end
            PHY_STATE_START_2: begin
                // generate start bit
                //     ___
                // sda    \_______
                //     _______
                // scl        \___
                //

                bus_control_next = 1'b1;
                phy_state_next = PHY_STATE_ACTIVE;
            end
            PHY_STATE_WRITE_BIT_1: begin
                // write bit
                //      ________
                // sda X________X
                //        ____
                // scl __/    \__

                scl_o_next = 1'b1;
                delay_scl_next = 1'b1;
                delay_next = prescale << 1;
                phy_state_next = PHY_STATE_WRITE_BIT_2;
            end
            PHY_STATE_WRITE_BIT_2: begin
                // write bit
                //      ________
                // sda X________X
                //        ____
                // scl __/    \__

                scl_o_next = 1'b0;
                delay_next = prescale;
                phy_state_next = PHY_STATE_WRITE_BIT_3;
            end
            PHY_STATE_WRITE_BIT_3: begin
                // write bit
                //      ________
                // sda X________X
                //        ____
                // scl __/    \__

                phy_state_next = PHY_STATE_ACTIVE;
            end
            PHY_STATE_READ_BIT_1: begin
                // read bit
                //      ________
                // sda X________X
                //        ____
                // scl __/    \__

                scl_o_next = 1'b1;
                delay_scl_next = 1'b1;
                delay_next = prescale;
                phy_state_next = PHY_STATE_READ_BIT_2;
            end
            PHY_STATE_READ_BIT_2: begin
                // read bit
                //      ________
                // sda X________X
                //        ____
                // scl __/    \__

                phy_rx_data_next = sda_i_reg;
                delay_next = prescale;
                phy_state_next = PHY_STATE_READ_BIT_3;
            end
            PHY_STATE_READ_BIT_3: begin
                // read bit
                //      ________
                // sda X________X
                //        ____
                // scl __/    \__

                scl_o_next = 1'b0;
                delay_next = prescale;
                phy_state_next = PHY_STATE_READ_BIT_4;
            end
            PHY_STATE_READ_BIT_4: begin
                // read bit
                //      ________
                // sda X________X
                //        ____
                // scl __/    \__

                phy_state_next = PHY_STATE_ACTIVE;
            end
            PHY_STATE_STOP_1: begin
                // stop bit
                //                 ___
                // sda XXX\_______/
                //             _______
                // scl _______/

                scl_o_next = 1'b1;
                delay_scl_next = 1'b1;
                delay_next = prescale;
                phy_state_next = PHY_STATE_STOP_2;
            end
            PHY_STATE_STOP_2: begin
                // stop bit
                //                 ___
                // sda XXX\_______/
                //             _______
                // scl _______/

                sda_o_next = 1'b1;
                delay_next = prescale;
                phy_state_next = PHY_STATE_STOP_3;
            end
            PHY_STATE_STOP_3: begin
                // stop bit
                //                 ___
                // sda XXX\_______/
                //             _______
                // scl _______/

                bus_control_next = 1'b0;
                phy_state_next = PHY_STATE_IDLE;
            end
        endcase
    end
end

always @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        phy_state_reg <= PHY_STATE_IDLE;
        delay_reg <= 16'd0;
        delay_scl_reg <= 1'b0;
        delay_sda_reg <= 1'b0;
        cmd_ready_reg <= 1'b0;
        data_in_ready_reg <= 1'b0;
        data_out_valid_reg <= 1'b0;
        scl_o_reg <= 1'b1;
        sda_o_reg <= 1'b1;
        busy_reg <= 1'b0;
        bus_active_reg <= 1'b0;
        bus_control_reg <= 1'b0;
        missed_ack_reg <= 1'b0;
    end else begin
        state_reg <= state_next;
        phy_state_reg <= phy_state_next;

        delay_reg <= delay_next;
        delay_scl_reg <= delay_scl_next;
        delay_sda_reg <= delay_sda_next;

        cmd_ready_reg <= cmd_ready_next;
        data_in_ready_reg <= data_in_ready_next;
        data_out_valid_reg <= data_out_valid_next;

        scl_o_reg <= scl_o_next;
        sda_o_reg <= sda_o_next;

        busy_reg <= !(state_reg == STATE_IDLE || state_reg == STATE_ACTIVE_WRITE || state_reg == STATE_ACTIVE_READ) || !(phy_state_reg == PHY_STATE_IDLE || phy_state_reg == PHY_STATE_ACTIVE);

        if (start_bit) begin
            bus_active_reg <= 1'b1;
        end else if (stop_bit) begin
            bus_active_reg <= 1'b0;
        end else begin
            bus_active_reg <= bus_active_reg;
        end

        bus_control_reg <= bus_control_next;
        missed_ack_reg <= missed_ack_next;
    end

    phy_rx_data_reg <= phy_rx_data_next;

    addr_reg <= addr_next;
    data_reg <= data_next;
    last_reg <= last_next;

    mode_read_reg <= mode_read_next;
    mode_write_multiple_reg <= mode_write_multiple_next;
    mode_stop_reg <= mode_stop_next;

    bit_count_reg <= bit_count_next;

    data_out_reg <= data_out_next;
    data_out_last_reg <= data_out_last_next;

    scl_i_reg <= scl_i;
    sda_i_reg <= sda_i;
    last_scl_i_reg <= scl_i_reg;
    last_sda_i_reg <= sda_i_reg;
end

endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA



// ASMI_interface - copyright 2010, 2011 Phil Harman VK6APH

/*
	change log:


*/



module asmi_interface (clock, busy, erase, erase_ACK, IF_Rx_used, rdreq, IF_PHY_data,
					   erase_done, erase_done_ACK, send_more, send_more_ACK, num_blocks, NCONFIG); 

input 	wire 	clock;
input 	wire 	erase;
input 	wire 	[9:0] IF_Rx_used;
input  	wire  	erase_done_ACK;
input  	wire	send_more_ACK;
input   wire	[7:0] IF_PHY_data;
input   wire    [13:0] num_blocks;

output 	wire	busy;
output 	reg 	rdreq;
output 	reg 	erase_done;
output  reg		send_more;
output  reg		erase_ACK;
output  reg     NCONFIG;


reg		sector_erase;		// set to clear a sector of memory
reg 	[23:0]address; 		// address in EPCS16 to write to
reg 	write_enable; 
reg 	write;
reg     shift_bytes; 
reg 	[3:0]state;
reg 	[13:0]page; 		// counts number of 256 byte blocks we are writing 
reg 	[8:0]byte_count;	// holds number of bytes we have send to ASMI
reg     [21:0]reset_delay = 22'h0;  // delays reset after last frame sent


// reverse bit order into ASMI
wire [7:0]datain;
assign datain = {IF_PHY_data[0],IF_PHY_data[1],IF_PHY_data[2],IF_PHY_data[3],IF_PHY_data[4],IF_PHY_data[5],IF_PHY_data[6],IF_PHY_data[7]};

// state machine to manage ASMI inface

always @ (negedge clock) 
begin 
case (state)

0:	begin 
		sector_erase <= 0;				// reset sector erase
		write_enable <= 0;
		write <= 0;
		erase_ACK <= 0;
		erase_done <= 0;
		//address <= 24'h100000;			// set starting address to write to is top 1MB
		address <= 24'h0;
		byte_count <= 0;
		page <= 0;
		send_more <= 0;
		NCONFIG <= 0;
		if (erase) 
			 state <= 1'd1;
		else if(IF_Rx_used > 254) 		// if we have enough data in the Rx fifo then send to the EPCS16
			state <= 5;		 
	end

// do a sector erase	
1:	begin
		erase_ACK <= 1'b1; 	   	// let the Rx know we have seen the command
		write_enable <= 1'b1;
		sector_erase <= 1'b1;
		state <= 2;
	end 
// wait until erase has completed
2:	begin
		write_enable <= 0;
		sector_erase <= 0;
		if (busy) state <= 2;
		else if (address != 24'h1F0000) begin 
				address <= address + 24'h010000;
				state <= 1;
		end 
		else state <= 3;
	end
// let user know that erase has completed
3:	begin
		erase_done <= 1'b1;
		state <= 4;
	end 
// wait for the Tx to ack then return, loop here otherwise
4:	begin
		if (erase_done_ACK) state <= 0;
	end
	
// program EPCS16 with data from PC
5: 	begin 
	rdreq <= 1'b1;					
	byte_count <= 0; 				// reset byte counter
	state <= state + 1'b1;
	end 
// loop until we have sent 256 bytes
6:	begin
		if (byte_count == 9'd256) begin
			byte_count <= 0;				// reset byte counter
			shift_bytes <= 0;
			rdreq <= 0; 					// stop reading from fifo
			page <= page + 1'b1;			// increment the page counter
			state <= state + 1'b1;
		end 
		else begin
			write_enable <= 1'b1;			// enable write to the ASMI 
			shift_bytes <= 1'b1;			// enable loading data into the ASMI memory
			byte_count <= byte_count + 1'b1;
		end
	end 
// write the 256 bytes into the ASMI fifo and request more data
7:	begin
	write <= 1;
	state <= state + 1'b1;
	send_more <= 1'b1;		
	end 
// wait for request to be acknowledged and we have 255 more bytes ready then increment address by 256
// and get some more data 
8:	begin 
	write <= 0;
	write_enable <= 0;
		if (send_more_ACK) send_more <= 0;		// clear send flag once Tx has seen it
		if (page == num_blocks) begin			// all done so exit			
			 send_more <= 1'b1;					// let the PC know that the final block has been received.
			 state <= state + 1'b1;
		end 
		else if (!busy && IF_Rx_used > 254  && send_more == 0) begin
			address <= address + 24'd256;		// increment write address to point to next page boundry
			state <= 5;
		end
	end 

// delay so the final send_more is seen
9: 	begin
		if (send_more_ACK) begin 
			send_more <= 0;		
			state <= state + 1'b1;
		end 
	end 
	
// delay so the PC sees the final send more then when not busy reset the FPGA		
10:	begin
		if (&reset_delay) begin		
			if (!busy)							// wait until the last frame has been written then reset
				NCONFIG <= 1'b1;				// then reload FPGA from Flash	
		end 																
		else reset_delay <= reset_delay + 1'b1;
	end 
	
default: state <= 0;
		
endcase
end 


//----------------------------
// 			ASMI  
//----------------------------

//  If you enable wren in the MegaFunction then it must be set to 1 in order to write, protect or erase.

asmi_asmi_parallel_0 asmi_inst(
	.addr(address),
	.sector_erase(sector_erase),
	.busy(busy),
	.clkin(clock),
        .wren(write_enable),
        //.sector_protect(0),
	.datain(datain),
	.write(write),
	.shift_bytes(shift_bytes),
	.rden(1'b0),
	.read(1'b0),
	.reset(1'b0),
	.data_valid(),
	.dataout(),
	.illegal_erase(),
	.illegal_write()
); 


endmodule
//
//  Hermes Lite
//
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// (C) Steve Haynal KF7O 2014-2018
// This RTL originated from www.openhpsdr.org and has been modified to support
// the Hermes-Lite hardware described at http://github.com/softerhardware/Hermes-Lite2.

module hermeslite(

  // Power
  output          pwr_clk3p3,
  output          pwr_clk1p2,
  output          pwr_envpa, 

`ifdef BETA2
  output          pwr_clkvpa,
`else
  output          pwr_envop,
  output          pwr_envbias,
`endif

  // Ethernet PHY
  input           phy_clk125,
  output  [3:0]   phy_tx,
  output          phy_tx_en,
  output          phy_tx_clk,
  input   [3:0]   phy_rx,
  input           phy_rx_dv,
  input           phy_rx_clk,
  input           phy_rst_n,
  inout           phy_mdio,
  output          phy_mdc,

  // Clock
  output          clk_recovered,
  inout           clk_sda1,
  inout           clk_scl1,

  // RF Frontend
  output          rffe_ad9866_rst_n,

`ifdef HALFDUPLEX
  inout   [5:0]   rffe_ad9866_tx,
  inout   [5:0]   rffe_ad9866_rx,
  output          rffe_ad9866_rxsync,
  output          rffe_ad9866_rxclk,  
`else
  output  [5:0]   rffe_ad9866_tx,
  input   [5:0]   rffe_ad9866_rx,
  input           rffe_ad9866_rxsync,
  input           rffe_ad9866_rxclk,  
`endif

  output          rffe_ad9866_txquiet_n,
  output          rffe_ad9866_txsync,
  output          rffe_ad9866_sdio,
  output          rffe_ad9866_sclk,
  output          rffe_ad9866_sen_n,
  input           rffe_ad9866_clk76p8,
  output          rffe_rfsw_sel,

`ifdef BETA2
  output  [5:0]   rffe_ad9866_pga,
`else
  output          rffe_ad9866_mode,
  output          rffe_ad9866_pga5,
`endif

  // IO
  output          io_led_d2,
  output          io_led_d3,
  output          io_led_d4,
  output          io_led_d5,
  input           io_lvds_rxn,
  input           io_lvds_rxp,
  output          io_lvds_txn, // also TX envelope PWM inverted
  output          io_lvds_txp, // also TX envelope PWM
  input           io_cn8,
  input           io_cn9,
  input           io_cn10,
  inout           io_adc_scl,
  inout           io_adc_sda,
  inout           io_scl2,
  inout           io_sda2,
  input           io_db1_2,       // BETA2,BETA3: io_db24
  input           io_db1_3,       // BETA2,BETA3: io_db22_3
  input           io_db1_4,       // BETA2,BETA3: io_db22_2
  output          io_db1_5,       // BETA2,BETA3: io_cn4_6
  input           io_db1_6,       // BETA2,BETA3: io_cn4_7    
  input           io_phone_tip,   // BETA2,BETA3: io_cn4_2
  input           io_phone_ring,  // BETA2,BETA3: io_cn4_3
  input           io_tp2,
  
`ifndef BETA2
  input           io_tp7,
  input           io_tp8,  
  input           io_tp9,
`endif

  // PA
`ifdef BETA2
  output          pa_tr,
  output          pa_en
`else
  output          pa_inttr,
  output          pa_exttr
`endif
);


// PARAMETERS
parameter       NR = 4; // Recievers
localparam      NT = 1; // Transmitters

// Ethernet Interface
`ifdef BETA2
localparam       HERMES_SERIALNO = 8'd46;     // Serial number of this version
localparam       MAC = {8'h00,8'h1c,8'hc0,8'ha2,8'h12,8'hdd};
`else 
localparam       HERMES_SERIALNO = 8'd66;     // Serial number of this version
localparam       MAC = {8'h00,8'h1c,8'hc0,8'ha2,8'h13,8'hdd};
`endif
localparam       IP = {8'd0,8'd0,8'd0,8'd0};

// ADC Oscillator
localparam       CLK_FREQ = 76800000;

// Downstream audio channel usage:
//   0=not used, 1=predistortion, 2=TX envelope PWM
//   when using the TX envelope PWM reduce the number of receivers (NR) above by 1
localparam      LRDATA = 0;

logic   [5:0]   cmd_addr;
logic   [31:0]  cmd_data;
logic           cmd_cnt;
logic           cmd_ptt;
logic           cmd_requires_resp;         

logic           tx_on, tx_on_ad9866sync;
logic           cw_keydown, cw_keydown_ad9866sync;
logic           tx_cw_waveform;     // CW waveform is active. Keep transmit enabled while waveform decays to zero.

logic   [7:0]   dseth_tdata;

logic   [31:0]  dsiq_tdata;
logic           dsiq_tready;    // controls reading of fifo
logic           dsiq_tvalid;
logic           dsethiq_tvalid;
logic           dsethiq_tlast;

logic   [31:0]  dslr_tdata;
logic           dslr_tready;    // controls reading of fifo
logic           dslr_tvalid;
logic           dsethlr_tvalid;
logic           dsethlr_tlast;

logic  [23:0]   rx_tdata;
logic           rx_tlast;
logic           rx_tready;
logic           rx_tvalid;
logic  [ 1:0]   rx_tuser;

logic  [23:0]   usiq_tdata;
logic           usiq_tlast;
logic           usiq_tready;
logic           usiq_tvalid;
logic  [ 1:0]   usiq_tuser;
logic  [10:0]   usiq_tlength;

logic           response_inp_tready;
logic   [37:0]  response_out_tdata;
logic           response_out_tvalid;
logic           response_out_tready;

logic           bs_tvalid;
logic           bs_tready;
logic [11:0]    bs_tdata;

logic           cmd_rqst_usopenhpsdr1;

logic           clock_125_mhz_0_deg;
logic           clock_125_mhz_90_deg;
logic           clock_25_mhz;
logic           clock_12p5_mhz;
logic           ethpll_locked;
logic           clock_ethtxint;
logic           clock_ethtxext;
logic           clock_ethrxint;
logic           speed_1gb;
logic           speed_1gb_clksel = 1'b0;

logic           phy_rx_clk_div2 = 1'b0;
logic           ethup;

logic           clk_ad9866;
logic           clk_ad9866_2x;
logic           clk_envelope;
logic           ad9866up;

logic           run, run_sync, run_iosync;
logic           tx_hang, tx_hang_iosync;
logic           wide_spectrum, wide_spectrum_sync;
logic           discovery_reply, discovery_reply_sync;

logic           dst_unreachable;

logic           udp_tx_request;
logic [ 7:0]    udp_tx_data;
logic [10:0]    udp_tx_length;
logic           udp_tx_enable;

logic [15:0]    to_port;
logic           broadcast;
logic           udp_rx_active;
logic [ 7:0]    udp_rx_data;

logic           network_state_dhcp, network_state_fixedip;
logic [ 1:0]    network_speed;

logic [47:0]    local_mac;

logic           cmd_rqst_ad9866;
logic [11:0]    rx_data;
logic [11:0]    tx_data;

logic           sda1_i;
logic           sda1_o;
logic           sda1_t;
logic           scl1_i;
logic           scl1_o;
logic           scl1_t;

logic           sda2_i;
logic           sda2_o;
logic           sda2_t;
logic           scl2_i;
logic           scl2_o;
logic           scl2_t;

logic           sda3_i;
logic           sda3_o;
logic           sda3_t;
logic           scl3_i;
logic           scl3_o;
logic           scl3_t;

logic           cmd_rqst_io;
logic           clk_ctrl;

logic           rxclip, rxclip_iosync;
logic           rxgoodlvl, rxgoodlvl_iosync;
logic           rxclrstatus, rxclrstatus_ad9866sync;

logic [39:0]    resp;
logic           resp_rqst, resp_rqst_iosync;

logic           watchdog_up, watchdog_up_sync;

logic           dsethasmi_erase, dsethasmi_erase_ack;
logic           usethasmi_send_more, usethasmi_erase_done, usethasmi_ack;
logic [13:0]    asmi_cnt = 14'h0000;
logic           dsethasmi_tvalid;

logic [ 7:0]    asmi_data;
logic [ 9:0]    asmi_rx_used;
logic           asmi_rdreq;
logic           asmi_reconfig;

/////////////////////////////////////////////////////
// Clocks

ethpll ethpll_inst (
    .inclk0   (phy_clk125),   //  refclk.clk
    .c0 (clock_125_mhz_0_deg), // outclk0.clk
    .c1 (clock_125_mhz_90_deg), // outclk1.clk
    .c2 (clk_ctrl), // outclk2.clk
    .c3 (clock_25_mhz),
    .c4 (clock_12p5_mhz),
    .locked (ethpll_locked)
);

always @(posedge clk_ctrl)
  speed_1gb_clksel <= speed_1gb;

altclkctrl #(
    .clock_type("AUTO"),
    //.intended_device_family("Cyclone IV E"),
    //.ena_register_mode("none"),
    //.implement_in_les("OFF"),
    .number_of_clocks(2),
    //.use_glitch_free_switch_over_implementation("OFF"),
    .width_clkselect(1)
    //.lpm_type("altclkctrl"),
    //.lpm_hint("unused")
    ) ethtxint_clkmux_i 
(
    .clkselect(speed_1gb_clksel),
    .ena(1'b1),
    .inclk({clock_125_mhz_0_deg,clock_12p5_mhz}),
    .outclk(clock_ethtxint)
);


altclkctrl #(
    .clock_type("AUTO"),
    //.intended_device_family("Cyclone IV E"),
    //.ena_register_mode("none"),
    //.implement_in_les("OFF"),
    .number_of_clocks(2),
    //.use_glitch_free_switch_over_implementation("OFF"),
    .width_clkselect(1)
    //.lpm_type("altclkctrl"),
    //.lpm_hint("unused")
    ) ethtxext_clkmux_i 
(
    .clkselect(speed_1gb_clksel),
    .ena(1'b1),
    .inclk({clock_125_mhz_90_deg,clock_25_mhz}),
    .outclk(clock_ethtxext)
);

assign phy_tx_clk = clock_ethtxext;

always @(posedge phy_rx_clk) begin
  phy_rx_clk_div2 <= ~phy_rx_clk_div2;
end

assign clock_ethrxint = speed_1gb_clksel ? phy_rx_clk : phy_rx_clk_div2; 

// Infer above as altclkctrl does not map correctly in Quartus for this case
//altclkctrl #(
//    .clock_type("AUTO"),
//    //.intended_device_family("Cyclone IV E"),
//    //.ena_register_mode("none"),
//    //.implement_in_les("OFF"),
//    .number_of_clocks(2),
//    //.use_glitch_free_switch_over_implementation("OFF"),
//    .width_clkselect(1)
//    //.lpm_type("altclkctrl"),
//    //.lpm_hint("unused")
//    ) ethrxint_clkmux_i 
//(
//    .clkselect(speed_1gb_clksel),
//    .ena(1'b1),
//    .inclk({phy_rx_clk,phy_rx_clk_div2}),
//    .outclk(clock_ethrxint)
//);


// phy_rst_n will go high after ~50ms due to RC
// ethpll_locked will go high once pll is locked
assign ethup = ethpll_locked & phy_rst_n;

// ethup starts I2C configuration of the Versa
// the PLL may lock twice the frequency changes


ad9866pll ad9866pll_inst (
  .inclk0   (rffe_ad9866_clk76p8),   //  refclk.clk
  .areset   (~ethup),      //   reset.reset
  .c0 (clk_ad9866), // outclk0.clk
  .c1 (clk_ad9866_2x), // outclk1.clk
  .c2 (clk_envelope),
  .locked (ad9866up)
);



/////////////////////////////////////////////////////
// Network

assign local_mac =  {MAC[47:2],~io_cn10,MAC[0]};

network network_inst(

  .clock_2_5MHz(clk_ctrl),

  .tx_clock(clock_ethtxint),
  .udp_tx_request(udp_tx_request),
  .udp_tx_length({5'h00,udp_tx_length}),
  .udp_tx_data(udp_tx_data),
  .udp_tx_enable(udp_tx_enable),
  .run(run_sync),
  .port_id(8'h00),

  .rx_clock(clock_ethrxint),
  .to_port(to_port),
  .udp_rx_data(udp_rx_data),
  .udp_rx_active(udp_rx_active),
  .broadcast(broadcast),
  .dst_unreachable(dst_unreachable),

  .static_ip(IP),
  .local_mac(local_mac),
  .speed_1gb(speed_1gb),
  .network_state_dhcp(network_state_dhcp),
  .network_state_fixedip(network_state_fixedip),
  .network_speed(network_speed),

  .PHY_TX(phy_tx),
  .PHY_TX_EN(phy_tx_en),
  .PHY_RX(phy_rx),
  .PHY_DV(phy_rx_dv),
    
  .PHY_MDIO(phy_mdio),
  .PHY_MDC(phy_mdc)
);



///////////////////////////////////////////////
// Downstream ethrxint clock domain

sync_pulse sync_pulse_watchdog (
  .clock(clock_ethrxint),
  .sig_in(watchdog_up),
  .sig_out(watchdog_up_sync)
);

dsopenhpsdr1 dsopenhpsdr1_i (
  .clk(clock_ethrxint),
  .eth_port(to_port),
  .eth_broadcast(broadcast),
  .eth_valid(udp_rx_active),
  .eth_data(udp_rx_data),
  .eth_unreachable(dst_unreachable),
  .eth_metis_discovery(discovery_reply),

  .run(run),
  .wide_spectrum(wide_spectrum),

  .watchdog_up(watchdog_up_sync),

  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_cnt(cmd_cnt),
  .cmd_ptt(cmd_ptt),
  .cmd_resprqst(cmd_requires_resp),

  .dseth_tdata(dseth_tdata),
  .dsethiq_tvalid(dsethiq_tvalid),
  .dsethiq_tlast(dsethiq_tlast),
  .dsethlr_tvalid(dsethlr_tvalid),
  .dsethlr_tlast(dsethlr_tlast),

  .dsethasmi_tvalid(dsethasmi_tvalid),
  .dsethasmi_tlast(),
  .asmi_cnt(asmi_cnt),
  .dsethasmi_erase(dsethasmi_erase),
  .dsethasmi_erase_ack(dsethasmi_erase_ack)
);

dsiq_fifo #(.depth(8192)) dsiq_fifo_i (
  .wr_clk(clock_ethrxint),
  .wr_tdata(dseth_tdata),
  .wr_tvalid(dsethiq_tvalid),
  .wr_tready(),
  .wr_tlast(dsethiq_tlast),

  .rd_clk(clk_ad9866),
  .rd_tdata(dsiq_tdata),
  .rd_tvalid(dsiq_tvalid),
  .rd_tready(dsiq_tready)
  );


generate 

case (LRDATA)
  0: begin // Left/Right downstream (PC->Card) audio data not used
    assign dslr_tvalid = 1'b0;
    assign dslr_tdata = 32'h0;
  end
  1: begin: PD2 // TX predistortion
    // simple fifo to get predistortion tables
    dslr_fifo dslr_fifo_i (
      .wr_clk(clock_ethrxint),
      .wr_tdata(dseth_tdata),
      .wr_tvalid(dsethlr_tvalid),
      .wr_tready(),

      .rd_clk(clk_ad9866),
      .rd_tdata(dslr_tdata),
      .rd_tvalid(dslr_tvalid),
      .rd_tready(dslr_tready)
    );
  end
  2: begin // TX envelope PWM generation for ET/EER
    // need to use same fifo as the TX I/Q data to keep the envelope in sync
    dsiq_fifo #(.depth(16384)) dslr_fifo_i (
      .wr_clk(clock_ethrxint),
      .wr_tdata(dseth_tdata),
      .wr_tvalid(dsethlr_tvalid),
      .wr_tready(),
      .wr_tlast(dsethlr_tlast),

      .rd_clk(clk_ad9866),
      .rd_tdata(dslr_tdata),
      .rd_tvalid(dslr_tvalid),
      .rd_tready(dslr_tready)
    );
  end
endcase

endgenerate

///////////////////////////////////////////////
// Upstream ethtxint clock domain

sync sync_inst1(.clock(clock_ethtxint), .sig_in(discovery_reply), .sig_out(discovery_reply_sync));
sync sync_inst2(.clock(clock_ethtxint), .sig_in(run), .sig_out(run_sync));
sync sync_inst3(.clock(clock_ethtxint), .sig_in(wide_spectrum), .sig_out(wide_spectrum_sync));

sync_pulse sync_pulse_usopenhpsdr1 (
  .clock(clock_ethtxint),
  .sig_in(cmd_cnt),
  .sig_out(cmd_rqst_usopenhpsdr1)
);

usopenhpsdr1 #(.NR(NR), .HERMES_SERIALNO(HERMES_SERIALNO)) usopenhpsdr1_i (
  .clk(clock_ethtxint),
  .have_ip(~(network_state_dhcp & network_state_fixedip)), // network_state is on sync 2.5 MHz domain
  .run(run_sync),
  .wide_spectrum(wide_spectrum_sync),
  .idhermeslite(io_cn9),
  .mac(local_mac),
  .discovery(discovery_reply_sync),

  .udp_tx_enable(udp_tx_enable),
  .udp_tx_request(udp_tx_request),
  .udp_tx_data(udp_tx_data),
  .udp_tx_length(udp_tx_length),

  .bs_tdata(bs_tdata),
  .bs_tready(bs_tready),
  .bs_tvalid(bs_tvalid),

  .us_tdata(usiq_tdata),
  .us_tlast(usiq_tlast),
  .us_tready(usiq_tready),
  .us_tvalid(usiq_tvalid),
  .us_tuser(usiq_tuser),
  .us_tlength(usiq_tlength),

  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_rqst(cmd_rqst_usopenhpsdr1),

  .resp(resp),
  .resp_rqst(resp_rqst),

  .watchdog_up(watchdog_up),

  .usethasmi_send_more(usethasmi_send_more),
  .usethasmi_erase_done(usethasmi_erase_done),
  .usethasmi_ack(usethasmi_ack)
);

usiq_fifo usiq_fifo_i (
  .wr_clk(clk_ad9866),
  .wr_tdata(rx_tdata),
  .wr_tvalid(rx_tvalid),
  .wr_tready(rx_tready),
  .wr_tlast(rx_tlast),
  .wr_tuser(rx_tuser),

  .rd_clk(clock_ethtxint),
  .rd_tdata(usiq_tdata),
  .rd_tvalid(usiq_tvalid),
  .rd_tready(usiq_tready),
  .rd_tlast(usiq_tlast),
  .rd_tuser(usiq_tuser),
  .rd_tlength(usiq_tlength)
);


usbs_fifo usbs_fifo_i (
  .wr_clk(clk_ad9866),
  .wr_tdata(rx_data),
  .wr_tvalid(1'b1),
  .wr_tready(),

  .rd_clk(clock_ethtxint),
  .rd_tdata(bs_tdata),
  .rd_tvalid(bs_tvalid),
  .rd_tready(bs_tready)
);


///////////////////////////////////////////////
// AD9866 clock domain

sync_pulse sync_pulse_ad9866 (
  .clock(clk_ad9866),
  .sig_in(cmd_cnt),
  .sig_out(cmd_rqst_ad9866)
);

sync_pulse sync_rxclrstatus_ad9866 (
  .clock(clk_ad9866),
  .sig_in(rxclrstatus),
  .sig_out(rxclrstatus_ad9866sync)
);

sync sync_ad9866_tx_on (
  .clock(clk_ad9866),
  .sig_in(tx_on),
  .sig_out(tx_on_ad9866sync)
);

sync sync_ad9866_cw_keydown (
  .clock(clk_ad9866),
  .sig_in(cw_keydown),
  .sig_out(cw_keydown_ad9866sync)
);


ad9866 ad9866_i (
  .clk(clk_ad9866),
  .clk_2x(clk_ad9866_2x),

  .tx_data(tx_data),
  .rx_data(rx_data),
  .tx_en(tx_on_ad9866sync | tx_cw_waveform),

  .rxclip(rxclip),
  .rxgoodlvl(rxgoodlvl),
  .rxclrstatus(rxclrstatus_ad9866sync),

  .rffe_ad9866_tx(rffe_ad9866_tx),
  .rffe_ad9866_rx(rffe_ad9866_rx),
  .rffe_ad9866_rxsync(rffe_ad9866_rxsync),
  .rffe_ad9866_rxclk(rffe_ad9866_rxclk),  
  .rffe_ad9866_txquiet_n(rffe_ad9866_txquiet_n),
  .rffe_ad9866_txsync(rffe_ad9866_txsync),

`ifdef BETA2
  .rffe_ad9866_mode()
`else
  .rffe_ad9866_mode(rffe_ad9866_mode)
`endif
);


radio #(
  .NR(NR), 
  .NT(NT),
  .LRDATA(LRDATA),
  .CLK_FREQ(CLK_FREQ)
) 
radio_i 
(
  .clk(clk_ad9866),
  .clk_2x(clk_ad9866_2x),

  .cw_keydown(cw_keydown_ad9866sync),
  .tx_on(tx_on_ad9866sync),
  .tx_cw_key(tx_cw_waveform),
  .tx_hang(tx_hang),

  // Transmit
  .tx_tdata({dsiq_tdata[7:0],dsiq_tdata[15:8],dsiq_tdata[23:16],dsiq_tdata[31:24]}),
  .tx_tid(3'h0),
  .tx_tlast(1'b1),
  .tx_tready(dsiq_tready),
  .tx_tvalid(dsiq_tvalid),

  .tx_data_dac(tx_data),

  .clk_envelope(clk_envelope),
  .tx_envelope_pwm_out(io_lvds_txp),
  .tx_envelope_pwm_out_inv(io_lvds_txn),

  // Optional Audio Stream
  .lr_tdata({dslr_tdata[7:0],dslr_tdata[15:8],dslr_tdata[23:16],dslr_tdata[31:24]}),
  .lr_tid(3'h0),
  .lr_tlast(1'b1),
  .lr_tready(dslr_tready),
  .lr_tvalid(dslr_tvalid),

  // Receive
  .rx_data_adc(rx_data),

  .rx_tdata(rx_tdata),
  .rx_tlast(rx_tlast),
  .rx_tready(rx_tready),
  .rx_tvalid(rx_tvalid),
  .rx_tuser(rx_tuser),

  // Command Slave
  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_rqst(cmd_rqst_ad9866),
  .cmd_ack() // No need for ack from radio yet
);




///////////////////////////////////////////////
// IO clock domain

sync_pulse syncio_cmd_rqst (
  .clock(clk_ctrl),
  .sig_in(cmd_cnt),
  .sig_out(cmd_rqst_io)
);

// Clocks are really synchronous so save time
sync_pulse #(.DEPTH(2)) syncio_rqst_io (
  .clock(clk_ctrl),
  .sig_in(resp_rqst),
  .sig_out(resp_rqst_iosync)
);

sync syncio_rxclip (
  .clock(clk_ctrl),
  .sig_in(rxclip),
  .sig_out(rxclip_iosync)
);

sync syncio_rxgoodlvl (
  .clock(clk_ctrl),
  .sig_in(rxgoodlvl),
  .sig_out(rxgoodlvl_iosync)
);

sync syncio_run (
  .clock(clk_ctrl),
  .sig_in(run),
  .sig_out(run_iosync)
);

sync syncio_txhang (
  .clock(clk_ctrl),
  .sig_in(tx_hang),
  .sig_out(tx_hang_iosync)
);


control #(.HERMES_SERIALNO(HERMES_SERIALNO)) control_i (
  // Internal
  .clk(clk_ctrl),
  .clk_ad9866(clk_ad9866), // Just for measurement
  .clk_125(clock_125_mhz_0_deg),

  .ethup(ethup),
  .have_dhcp_ip(~network_state_dhcp),
  .have_fixed_ip(~network_state_fixedip),
  .network_speed(network_speed),
  .ad9866up(ad9866up),

  .rxclip(rxclip_iosync),
  .rxgoodlvl(rxgoodlvl_iosync),
  .rxclrstatus(rxclrstatus),
  .run(run_iosync),
  .tx_hang(tx_hang_iosync),

  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_rqst(cmd_rqst_io),
  .cmd_ptt(cmd_ptt),
  .cmd_requires_resp(cmd_requires_resp),

  .tx_on(tx_on),
  .cw_keydown(cw_keydown),

  .resp_rqst(resp_rqst_iosync),
  .resp(resp),  

  // External
  .rffe_rfsw_sel(rffe_rfsw_sel),

  // AD9866
  .rffe_ad9866_rst_n(rffe_ad9866_rst_n),

  .rffe_ad9866_sdio(rffe_ad9866_sdio),
  .rffe_ad9866_sclk(rffe_ad9866_sclk),
  .rffe_ad9866_sen_n(rffe_ad9866_sen_n),

`ifdef BETA2
  .rffe_ad9866_pga(rffe_ad9866_pga),
`else
  .rffe_ad9866_pga5(rffe_ad9866_pga5),
`endif

  // Power
  .pwr_clk3p3(pwr_clk3p3),
  .pwr_clk1p2(pwr_clk1p2),
  .pwr_envpa(pwr_envpa), 

`ifdef BETA2
  .pwr_clkvpa(pwr_clkvpa),
`else
  .pwr_envop(pwr_envop),
  .pwr_envbias(pwr_envbias),
`endif

  // Clock
  .clk_recovered(clk_recovered),
 
  .sda1_i(sda1_i),
  .sda1_o(sda1_o),
  .sda1_t(sda1_t),
  .scl1_i(scl1_i),
  .scl1_o(scl1_o),
  .scl1_t(scl1_t),

  .sda2_i(sda2_i),
  .sda2_o(sda2_o),
  .sda2_t(sda2_t),
  .scl2_i(scl2_i),
  .scl2_o(scl2_o),
  .scl2_t(scl2_t),

  .sda3_i(sda3_i),
  .sda3_o(sda3_o),
  .sda3_t(sda3_t),
  .scl3_i(scl3_i),
  .scl3_o(scl3_o),
  .scl3_t(scl3_t),

  // IO
  .io_led_d2(io_led_d2),
  .io_led_d3(io_led_d3),
  .io_led_d4(io_led_d4),
  .io_led_d5(io_led_d5),
  .io_lvds_rxn(io_lvds_rxn),
  .io_lvds_rxp(io_lvds_rxp),
  //.io_lvds_txn(io_lvds_txn),
  //.io_lvds_txp(io_lvds_txp),
  .io_cn8(io_cn8),
  .io_cn9(io_cn9),
  .io_cn10(io_cn10),

  .io_db1_2(io_db1_2),     
  .io_db1_3(io_db1_3),     
  .io_db1_4(io_db1_4),     
  .io_db1_5(io_db1_5),     
  .io_db1_6(io_db1_6),       
  .io_phone_tip(io_phone_tip), 
  .io_phone_ring(io_phone_ring),
  .io_tp2(io_tp2),
  
`ifndef BETA2
  .io_tp7(io_tp7),
  .io_tp8(io_tp8),  
  .io_tp9(io_tp9),
`endif

  // PA
`ifdef BETA2
  .pa_tr(pa_tr),
  .pa_en(pa_en)
`else
  .pa_inttr(pa_inttr),
  .pa_exttr(pa_exttr)
`endif
);


assign scl1_i = clk_scl1;
assign clk_scl1 = scl1_t ? 1'bz : scl1_o;
assign sda1_i = clk_sda1;
assign clk_sda1 = sda1_t ? 1'bz : sda1_o;

assign scl2_i = io_scl2;
assign io_scl2 = scl2_t ? 1'bz : scl2_o;
assign sda2_i = io_sda2;
assign io_sda2 = sda2_t ? 1'bz : sda2_o;

assign scl3_i = io_adc_scl;
assign io_adc_scl = scl3_t ? 1'bz : scl3_o;
assign sda3_i = io_adc_sda;
assign io_adc_sda = sda3_t ? 1'bz : sda3_o;

asmi_fifo asmi_fifo_i (
  .wrclk (clock_ethrxint),
  .wrreq(dsethasmi_tvalid), 
  .data (dseth_tdata),

  .rdreq (asmi_rdreq),
  .rdclk (clk_ctrl),  
  .q (asmi_data),
  .rdusedw(asmi_rx_used),

  .aclr(1'b0)
);


asmi_interface asmi_interface_i (
  .clock(clk_ctrl),
  .busy(),
  .erase(dsethasmi_erase),
  .erase_ACK(dsethasmi_erase_ack),
  .IF_Rx_used(asmi_rx_used),
  .rdreq(asmi_rdreq),
  .IF_PHY_data(asmi_data),
  .erase_done(usethasmi_erase_done),
  .erase_done_ACK(usethasmi_ack),
  .send_more(usethasmi_send_more),
  .send_more_ACK(usethasmi_ack),
  .num_blocks(asmi_cnt),
  .NCONFIG(asmi_reconfig)
); 



`ifdef FACTORY

remote_update_fac remote_update_fac_i (
  .clk(clk_ctrl),
  .rst(~ethpll_locked),
  .bootapp(io_cn8)
);


`else

remote_update_app remote_update_app_i (
  .clk(clk_ctrl),
  .rst(~ethpll_locked),
  .reconfig(asmi_reconfig)
);

`endif


endmodule

module slow_adc(
  input  logic         clk,
  input  logic         rst,

  output logic [11:0]  ain0,
  output logic [11:0]  ain1,
  output logic [11:0]  ain2,
  output logic [11:0]  ain3,

  input  logic         scl_i,
  output logic         scl_o,
  output logic         scl_t,
  input  logic         sda_i,
  output logic         sda_o,
  output logic         sda_t
);

logic [6:0]  cmd_address;
logic        cmd_start;
logic        cmd_read;
logic        cmd_write;
logic        cmd_write_multiple;
logic        cmd_stop;
logic        cmd_valid;
logic        cmd_ready;

logic [7:0]  data_in;
logic        data_in_valid;
logic        data_in_ready;
logic        data_in_last;

logic [7:0]  data_out;
logic        data_out_valid;
logic        data_out_ready;
logic        data_out_last;

logic [3:0]  state, next_state;
logic [3:0]  msbnibble;

i2c_master i2c_master_i (
  .clk(clk),
  .rst(rst),
  /*
   * Host interface
   */
  .cmd_address(cmd_address),
  .cmd_start(cmd_start),
  .cmd_read(cmd_read),
  .cmd_write(cmd_write),
  .cmd_write_multiple(cmd_write_multiple),
  .cmd_stop(cmd_stop),
  .cmd_valid(cmd_valid),
  .cmd_ready(cmd_ready),

  .data_in(data_in),
  .data_in_valid(data_in_valid),
  .data_in_ready(data_in_ready),
  .data_in_last(data_in_last),

  .data_out(data_out),
  .data_out_valid(data_out_valid),
  .data_out_ready(data_out_ready),
  .data_out_last(data_out_last),

  /*
   * I2C interface
   */
  .scl_i(scl_i),
  .scl_o(scl_o),
  .scl_t(scl_t),
  .sda_i(sda_i),
  .sda_o(sda_o),
  .sda_t(sda_t),

  /*
   * Status
   */
  .busy(),
  .bus_control(),
  .bus_active(),
  .missed_ack(),

  /*
   * Configuration
   */
  .prescale(16'h0002),
  .stop_on_idle(1'b0)
);



// Control
localparam [3:0]
  READ0  = 4'h0,
  READ1  = 4'h1,
  READ2  = 4'h2,
  READ3  = 4'h3,
  READ4  = 4'h4,
  READ5  = 4'h5,
  READ6  = 4'h6,
  READ7  = 4'h7,
  WRITE0 = 4'h8,
  WRITE1 = 4'h9;

always @(posedge clk) begin
  if (rst) begin
    state <= WRITE0;
  end else begin
    state <= next_state;
  end
end

assign cmd_address = 7'h34;
assign cmd_write_multiple = 1'b0;
assign cmd_start = 1'b0;
assign data_in = 8'h07;
assign data_out_ready = 1'b1;
assign data_in_last = 1'b1;

always @* begin
  next_state = state;

  cmd_valid = 1'b1; 
  cmd_read = 1'b1;
  cmd_write = 1'b0;
  cmd_stop = 1'b0;

  data_in_valid = 1'b0;

  case(state)

    WRITE0: begin
      cmd_read = 1'b0;
      cmd_write = 1'b1;
      cmd_stop = 1'b1;
      if (cmd_ready) next_state = WRITE1;
    end

    WRITE1: begin
      data_in_valid = 1'b1;
      if (data_in_ready) next_state = READ0;
    end

    READ0: if (data_out_valid) next_state = READ1;
    READ1: if (data_out_valid) next_state = READ2;
    READ2: if (data_out_valid) next_state = READ3;
    READ3: if (data_out_valid) next_state = READ4;
    READ4: if (data_out_valid) next_state = READ5;
    READ5: if (data_out_valid) next_state = READ6;
    READ6: if (data_out_valid) next_state = READ7;

    READ7: begin
      cmd_stop = 1'b1;
      if (data_out_valid) next_state = WRITE0;
    end
  endcase
end


always @(posedge clk) begin
  if (data_out_valid) begin
    if (~state[0]) msbnibble <= data_out[3:0];
      
    case(state)
      READ1: ain0 <= {msbnibble,data_out};
      READ3: ain1 <= {msbnibble,data_out};
      READ5: ain2 <= {msbnibble,data_out};
      READ7: ain3 <= {msbnibble,data_out};
    endcase
  end
end

endmodule


//altremote_update CBX_AUTO_BLACKBOX="ALL" CBX_SINGLE_OUTPUT_FILE="ON" check_app_pof="false" config_device_addr_width=24 DEVICE_FAMILY="Cyclone IV E" in_data_width=24 is_epcq="false" operation_mode="remote" out_data_width=29 busy clock ctl_nupdt data_in data_out param read_param read_source reconfig reset reset_timer write_param
//VERSION_BEGIN 18.1 cbx_altremote_update 2018:09:12:13:04:09:SJ cbx_cycloneii 2018:09:12:13:04:09:SJ cbx_lpm_add_sub 2018:09:12:13:04:09:SJ cbx_lpm_compare 2018:09:12:13:04:09:SJ cbx_lpm_counter 2018:09:12:13:04:09:SJ cbx_lpm_decode 2018:09:12:13:04:09:SJ cbx_lpm_shiftreg 2018:09:12:13:04:09:SJ cbx_mgl 2018:09:12:14:15:07:SJ cbx_nadder 2018:09:12:13:04:09:SJ cbx_nightfury 2018:09:12:13:04:09:SJ cbx_stratix 2018:09:12:13:04:09:SJ cbx_stratixii 2018:09:12:13:04:09:SJ  VERSION_END
// synthesis VERILOG_INPUT_VERSION VERILOG_2001
// altera message_off 10463



// Copyright (C) 2018  Intel Corporation. All rights reserved.
//  Your use of Intel Corporation's design tools, logic functions 
//  and other software and tools, and its AMPP partner logic 
//  functions, and any output files from any of the foregoing 
//  (including device programming or simulation files), and any 
//  associated documentation or information are expressly subject 
//  to the terms and conditions of the Intel Program License 
//  Subscription Agreement, the Intel Quartus Prime License Agreement,
//  the Intel FPGA IP License Agreement, or other applicable license
//  agreement, including, without limitation, that your use is for
//  the sole purpose of programming logic devices manufactured by
//  Intel and sold by Intel or its authorized distributors.  Please
//  refer to the applicable agreement for further details.



//synthesis_resources = cycloneive_rublock 1 lpm_counter 2 reg 62 
//synopsys translate_off
`timescale 1 ps / 1 ps
//synopsys translate_on
(* ALTERA_ATTRIBUTE = {"suppress_da_rule_internal=c104;suppress_da_rule_internal=C101;suppress_da_rule_internal=C103"} *)
module  altera_remote_update_core
	( 
	busy,
	clock,
	ctl_nupdt,
	data_in,
	data_out,
	param,
	read_param,
	read_source,
	reconfig,
	reset,
	reset_timer,
	write_param) /* synthesis synthesis_clearbox=1 */;
	output   busy;
	input   clock;
	input   ctl_nupdt;
	input   [23:0]  data_in;
	output   [28:0]  data_out;
	input   [2:0]  param;
	input   read_param;
	input   [1:0]  read_source;
	input   reconfig;
	input   reset;
	input   reset_timer;
	input   write_param;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri0   ctl_nupdt;
	tri0   [23:0]  data_in;
	tri0   [2:0]  param;
	tri0   read_param;
	tri0   [1:0]  read_source;
	tri0   reconfig;
	tri0   reset_timer;
	tri0   write_param;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	reg	[0:0]	check_busy_dffe;
	reg	[0:0]	dffe1a0;
	reg	[0:0]	dffe1a1;
	wire	[1:0]	wire_dffe1a_ena;
	reg	[0:0]	dffe2a0;
	reg	[0:0]	dffe2a1;
	reg	[0:0]	dffe2a2;
	wire	[2:0]	wire_dffe2a_ena;
	reg	[0:0]	dffe3a0;
	reg	[0:0]	dffe3a1;
	reg	[0:0]	dffe3a2;
	wire	[2:0]	wire_dffe3a_ena;
	reg	[28:0]	dffe7a;
	wire	[28:0]	wire_dffe7a_ena;
	reg	dffe8;
	reg	[6:0]	dffe9a;
	wire	[6:0]	wire_dffe9a_ena;
	reg	idle_state;
	reg	idle_write_wait;
	reg	read_address_state;
	wire	wire_read_address_state_ena;
	reg	read_data_state;
	reg	read_init_counter_state;
	reg	read_init_state;
	reg	read_post_state;
	reg	read_pre_data_state;
	reg	read_source_update_state;
	reg	write_data_state;
	reg	write_init_counter_state;
	reg	write_init_state;
	reg	write_load_state;
	reg	write_post_data_state;
	reg	write_pre_data_state;
	reg	write_source_update_state;
	reg	write_wait_state;
	wire  [5:0]   wire_cntr5_q;
	wire  [4:0]   wire_cntr6_q;
	wire  wire_sd4_regout;
	wire  bit_counter_all_done;
	wire  bit_counter_clear;
	wire  bit_counter_enable;
	wire  [5:0]  bit_counter_param_start;
	wire  bit_counter_param_start_match;
	wire  [6:0]  combine_port;
	wire  global_gnd;
	wire  global_vcc;
	wire  idle;
	wire  [6:0]  param_decoder_param_latch;
	wire  [22:0]  param_decoder_select;
	wire  power_up;
	wire  read_address;
	wire  read_data;
	wire  read_init;
	wire  read_init_counter;
	wire  read_post;
	wire  read_pre_data;
	wire  read_source_update;
	wire  rsource_load;
	wire  [1:0]  rsource_parallel_in;
	wire  rsource_serial_out;
	wire  rsource_shift_enable;
	wire  [2:0]  rsource_state_par_ini;
	wire  rsource_update_done;
	wire  rublock_captnupdt;
	wire  rublock_clock;
	wire  rublock_reconfig;
	wire  rublock_reconfig_st;
	wire  rublock_regin;
	wire  rublock_regout;
	wire  rublock_regout_reg;
	wire  rublock_shiftnld;
	wire  select_shift_nloop;
	wire  shift_reg_clear;
	wire  shift_reg_load_enable;
	wire  shift_reg_serial_in;
	wire  shift_reg_serial_out;
	wire  shift_reg_shift_enable;
	wire  [5:0]  start_bit_decoder_out;
	wire  [22:0]  start_bit_decoder_param_select;
	wire  [1:0]  w4w;
	wire  [5:0]  w53w;
	wire  [4:0]  w83w;
	wire  width_counter_all_done;
	wire  width_counter_clear;
	wire  width_counter_enable;
	wire  [4:0]  width_counter_param_width;
	wire  width_counter_param_width_match;
	wire  [4:0]  width_decoder_out;
	wire  [22:0]  width_decoder_param_select;
	wire  write_data;
	wire  write_init;
	wire  write_init_counter;
	wire  write_load;
	wire  write_post_data;
	wire  write_pre_data;
	wire  write_source_update;
	wire  write_wait;
	wire  [2:0]  wsource_state_par_ini;
	wire  wsource_update_done;

	// synopsys translate_off
	initial 
		 check_busy_dffe[0:0] = 0;
	// synopsys translate_on
	// synopsys translate_off
	initial
		dffe1a0 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe1a0 <= 1'b0;
		else if  (wire_dffe1a_ena[0:0] == 1'b1)   dffe1a0 <= ((rsource_load & rsource_parallel_in[0]) | ((~ rsource_load) & dffe1a1[0:0]));
	// synopsys translate_off
	initial
		dffe1a1 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe1a1 <= 1'b0;
		else if  (wire_dffe1a_ena[1:1] == 1'b1)   dffe1a1 <= (rsource_parallel_in[1] & rsource_load);
	assign
		wire_dffe1a_ena = {2{(rsource_load | rsource_shift_enable)}};
	// synopsys translate_off
	initial
		dffe2a0 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe2a0 <= 1'b0;
		else if  (wire_dffe2a_ena[0:0] == 1'b1)   dffe2a0 <= ((rsource_load & rsource_state_par_ini[0]) | ((~ rsource_load) & dffe2a1[0:0]));
	// synopsys translate_off
	initial
		dffe2a1 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe2a1 <= 1'b0;
		else if  (wire_dffe2a_ena[1:1] == 1'b1)   dffe2a1 <= ((rsource_load & rsource_state_par_ini[1]) | ((~ rsource_load) & dffe2a2[0:0]));
	// synopsys translate_off
	initial
		dffe2a2 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe2a2 <= 1'b0;
		else if  (wire_dffe2a_ena[2:2] == 1'b1)   dffe2a2 <= (rsource_state_par_ini[2] & rsource_load);
	assign
		wire_dffe2a_ena = {3{(rsource_load | global_vcc)}};
	// synopsys translate_off
	initial
		dffe3a0 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe3a0 <= 1'b0;
		else if  (wire_dffe3a_ena[0:0] == 1'b1)   dffe3a0 <= ((rsource_load & wsource_state_par_ini[0]) | ((~ rsource_load) & dffe3a1[0:0]));
	// synopsys translate_off
	initial
		dffe3a1 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe3a1 <= 1'b0;
		else if  (wire_dffe3a_ena[1:1] == 1'b1)   dffe3a1 <= ((rsource_load & wsource_state_par_ini[1]) | ((~ rsource_load) & dffe3a2[0:0]));
	// synopsys translate_off
	initial
		dffe3a2 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe3a2 <= 1'b0;
		else if  (wire_dffe3a_ena[2:2] == 1'b1)   dffe3a2 <= (wsource_state_par_ini[2] & rsource_load);
	assign
		wire_dffe3a_ena = {3{(rsource_load | global_vcc)}};
	// synopsys translate_off
	initial
		dffe7a[0:0] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[0:0] <= 1'b0;
		else if  (wire_dffe7a_ena[0:0] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[0:0] <= 1'b0;
			else  dffe7a[0:0] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[2]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[0]))) | ((~ shift_reg_load_enable) & dffe7a[1:1]));
	// synopsys translate_off
	initial
		dffe7a[1:1] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[1:1] <= 1'b0;
		else if  (wire_dffe7a_ena[1:1] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[1:1] <= 1'b0;
			else  dffe7a[1:1] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[3]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[1]))) | ((~ shift_reg_load_enable) & dffe7a[2:2]));
	// synopsys translate_off
	initial
		dffe7a[2:2] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[2:2] <= 1'b0;
		else if  (wire_dffe7a_ena[2:2] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[2:2] <= 1'b0;
			else  dffe7a[2:2] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[4]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[2]))) | ((~ shift_reg_load_enable) & dffe7a[3:3]));
	// synopsys translate_off
	initial
		dffe7a[3:3] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[3:3] <= 1'b0;
		else if  (wire_dffe7a_ena[3:3] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[3:3] <= 1'b0;
			else  dffe7a[3:3] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[5]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[3]))) | ((~ shift_reg_load_enable) & dffe7a[4:4]));
	// synopsys translate_off
	initial
		dffe7a[4:4] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[4:4] <= 1'b0;
		else if  (wire_dffe7a_ena[4:4] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[4:4] <= 1'b0;
			else  dffe7a[4:4] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[6]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[4]))) | ((~ shift_reg_load_enable) & dffe7a[5:5]));
	// synopsys translate_off
	initial
		dffe7a[5:5] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[5:5] <= 1'b0;
		else if  (wire_dffe7a_ena[5:5] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[5:5] <= 1'b0;
			else  dffe7a[5:5] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[7]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[5]))) | ((~ shift_reg_load_enable) & dffe7a[6:6]));
	// synopsys translate_off
	initial
		dffe7a[6:6] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[6:6] <= 1'b0;
		else if  (wire_dffe7a_ena[6:6] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[6:6] <= 1'b0;
			else  dffe7a[6:6] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[8]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[6]))) | ((~ shift_reg_load_enable) & dffe7a[7:7]));
	// synopsys translate_off
	initial
		dffe7a[7:7] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[7:7] <= 1'b0;
		else if  (wire_dffe7a_ena[7:7] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[7:7] <= 1'b0;
			else  dffe7a[7:7] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[9]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[7]))) | ((~ shift_reg_load_enable) & dffe7a[8:8]));
	// synopsys translate_off
	initial
		dffe7a[8:8] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[8:8] <= 1'b0;
		else if  (wire_dffe7a_ena[8:8] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[8:8] <= 1'b0;
			else  dffe7a[8:8] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[10]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[8]))) | ((~ shift_reg_load_enable) & dffe7a[9:9]));
	// synopsys translate_off
	initial
		dffe7a[9:9] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[9:9] <= 1'b0;
		else if  (wire_dffe7a_ena[9:9] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[9:9] <= 1'b0;
			else  dffe7a[9:9] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[11]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[9]))) | ((~ shift_reg_load_enable) & dffe7a[10:10]));
	// synopsys translate_off
	initial
		dffe7a[10:10] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[10:10] <= 1'b0;
		else if  (wire_dffe7a_ena[10:10] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[10:10] <= 1'b0;
			else  dffe7a[10:10] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[12]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[10]))) | ((~ shift_reg_load_enable) & dffe7a[11:11]));
	// synopsys translate_off
	initial
		dffe7a[11:11] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[11:11] <= 1'b0;
		else if  (wire_dffe7a_ena[11:11] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[11:11] <= 1'b0;
			else  dffe7a[11:11] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[13]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[11]))) | ((~ shift_reg_load_enable) & dffe7a[12:12]));
	// synopsys translate_off
	initial
		dffe7a[12:12] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[12:12] <= 1'b0;
		else if  (wire_dffe7a_ena[12:12] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[12:12] <= 1'b0;
			else  dffe7a[12:12] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[14]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[12]))) | ((~ shift_reg_load_enable) & dffe7a[13:13]));
	// synopsys translate_off
	initial
		dffe7a[13:13] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[13:13] <= 1'b0;
		else if  (wire_dffe7a_ena[13:13] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[13:13] <= 1'b0;
			else  dffe7a[13:13] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[15]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[13]))) | ((~ shift_reg_load_enable) & dffe7a[14:14]));
	// synopsys translate_off
	initial
		dffe7a[14:14] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[14:14] <= 1'b0;
		else if  (wire_dffe7a_ena[14:14] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[14:14] <= 1'b0;
			else  dffe7a[14:14] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[16]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[14]))) | ((~ shift_reg_load_enable) & dffe7a[15:15]));
	// synopsys translate_off
	initial
		dffe7a[15:15] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[15:15] <= 1'b0;
		else if  (wire_dffe7a_ena[15:15] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[15:15] <= 1'b0;
			else  dffe7a[15:15] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[17]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[15]))) | ((~ shift_reg_load_enable) & dffe7a[16:16]));
	// synopsys translate_off
	initial
		dffe7a[16:16] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[16:16] <= 1'b0;
		else if  (wire_dffe7a_ena[16:16] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[16:16] <= 1'b0;
			else  dffe7a[16:16] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[18]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[16]))) | ((~ shift_reg_load_enable) & dffe7a[17:17]));
	// synopsys translate_off
	initial
		dffe7a[17:17] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[17:17] <= 1'b0;
		else if  (wire_dffe7a_ena[17:17] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[17:17] <= 1'b0;
			else  dffe7a[17:17] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[19]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[17]))) | ((~ shift_reg_load_enable) & dffe7a[18:18]));
	// synopsys translate_off
	initial
		dffe7a[18:18] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[18:18] <= 1'b0;
		else if  (wire_dffe7a_ena[18:18] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[18:18] <= 1'b0;
			else  dffe7a[18:18] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[20]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[18]))) | ((~ shift_reg_load_enable) & dffe7a[19:19]));
	// synopsys translate_off
	initial
		dffe7a[19:19] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[19:19] <= 1'b0;
		else if  (wire_dffe7a_ena[19:19] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[19:19] <= 1'b0;
			else  dffe7a[19:19] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[21]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[19]))) | ((~ shift_reg_load_enable) & dffe7a[20:20]));
	// synopsys translate_off
	initial
		dffe7a[20:20] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[20:20] <= 1'b0;
		else if  (wire_dffe7a_ena[20:20] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[20:20] <= 1'b0;
			else  dffe7a[20:20] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[22]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[20]))) | ((~ shift_reg_load_enable) & dffe7a[21:21]));
	// synopsys translate_off
	initial
		dffe7a[21:21] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[21:21] <= 1'b0;
		else if  (wire_dffe7a_ena[21:21] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[21:21] <= 1'b0;
			else  dffe7a[21:21] <= ((shift_reg_load_enable & ((((param[2] & (~ param[1])) & (~ param[0])) & data_in[23]) | ((~ ((param[2] & (~ param[1])) & (~ param[0]))) & data_in[21]))) | ((~ shift_reg_load_enable) & dffe7a[22:22]));
	// synopsys translate_off
	initial
		dffe7a[22:22] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[22:22] <= 1'b0;
		else if  (wire_dffe7a_ena[22:22] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[22:22] <= 1'b0;
			else  dffe7a[22:22] <= ((~ shift_reg_load_enable) & dffe7a[23:23]);
	// synopsys translate_off
	initial
		dffe7a[23:23] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[23:23] <= 1'b0;
		else if  (wire_dffe7a_ena[23:23] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[23:23] <= 1'b0;
			else  dffe7a[23:23] <= ((~ shift_reg_load_enable) & dffe7a[24:24]);
	// synopsys translate_off
	initial
		dffe7a[24:24] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[24:24] <= 1'b0;
		else if  (wire_dffe7a_ena[24:24] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[24:24] <= 1'b0;
			else  dffe7a[24:24] <= ((~ shift_reg_load_enable) & dffe7a[25:25]);
	// synopsys translate_off
	initial
		dffe7a[25:25] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[25:25] <= 1'b0;
		else if  (wire_dffe7a_ena[25:25] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[25:25] <= 1'b0;
			else  dffe7a[25:25] <= ((~ shift_reg_load_enable) & dffe7a[26:26]);
	// synopsys translate_off
	initial
		dffe7a[26:26] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[26:26] <= 1'b0;
		else if  (wire_dffe7a_ena[26:26] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[26:26] <= 1'b0;
			else  dffe7a[26:26] <= ((~ shift_reg_load_enable) & dffe7a[27:27]);
	// synopsys translate_off
	initial
		dffe7a[27:27] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[27:27] <= 1'b0;
		else if  (wire_dffe7a_ena[27:27] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[27:27] <= 1'b0;
			else  dffe7a[27:27] <= ((~ shift_reg_load_enable) & dffe7a[28:28]);
	// synopsys translate_off
	initial
		dffe7a[28:28] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe7a[28:28] <= 1'b0;
		else if  (wire_dffe7a_ena[28:28] == 1'b1) 
			if (shift_reg_clear == 1'b1) dffe7a[28:28] <= 1'b0;
			else  dffe7a[28:28] <= ((~ shift_reg_load_enable) & shift_reg_serial_in);
	assign
		wire_dffe7a_ena = {29{((shift_reg_load_enable | shift_reg_shift_enable) | shift_reg_clear)}};
	// synopsys translate_off
	initial
		dffe8 = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe8 <= 1'b0;
		else  dffe8 <= rublock_regout;
	// synopsys translate_off
	initial
		dffe9a[0:0] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe9a[0:0] <= 1'b0;
		else if  (wire_dffe9a_ena[0:0] == 1'b1)   dffe9a[0:0] <= combine_port[0:0];
	// synopsys translate_off
	initial
		dffe9a[1:1] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe9a[1:1] <= 1'b0;
		else if  (wire_dffe9a_ena[1:1] == 1'b1)   dffe9a[1:1] <= combine_port[1:1];
	// synopsys translate_off
	initial
		dffe9a[2:2] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe9a[2:2] <= 1'b0;
		else if  (wire_dffe9a_ena[2:2] == 1'b1)   dffe9a[2:2] <= combine_port[2:2];
	// synopsys translate_off
	initial
		dffe9a[3:3] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe9a[3:3] <= 1'b0;
		else if  (wire_dffe9a_ena[3:3] == 1'b1)   dffe9a[3:3] <= combine_port[3:3];
	// synopsys translate_off
	initial
		dffe9a[4:4] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe9a[4:4] <= 1'b0;
		else if  (wire_dffe9a_ena[4:4] == 1'b1)   dffe9a[4:4] <= combine_port[4:4];
	// synopsys translate_off
	initial
		dffe9a[5:5] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe9a[5:5] <= 1'b0;
		else if  (wire_dffe9a_ena[5:5] == 1'b1)   dffe9a[5:5] <= combine_port[5:5];
	// synopsys translate_off
	initial
		dffe9a[6:6] = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) dffe9a[6:6] <= 1'b0;
		else if  (wire_dffe9a_ena[6:6] == 1'b1)   dffe9a[6:6] <= combine_port[6:6];
	assign
		wire_dffe9a_ena = {7{(idle & (write_param | read_param))}};
	// synopsys translate_off
	initial
		idle_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) idle_state <= {1{1'b1}};
		else  idle_state <= ((((((idle & (~ read_param)) & (~ write_param)) | write_wait) | (read_data & width_counter_all_done)) | (read_post & width_counter_all_done)) | power_up);
	// synopsys translate_off
	initial
		idle_write_wait = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) idle_write_wait <= 1'b0;
		else  idle_write_wait <= (((((((idle & (~ read_param)) & (~ write_param)) | write_wait) | (read_data & width_counter_all_done)) | (read_post & width_counter_all_done)) | power_up) & write_load);
	// synopsys translate_off
	initial
		read_address_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) read_address_state <= 1'b0;
		else if  (wire_read_address_state_ena == 1'b1)   read_address_state <= (((read_param | write_param) & ((param[2] & (~ param[1])) & (~ param[0]))) & (~ (~ idle)));
	assign
		wire_read_address_state_ena = (read_param | write_param);
	// synopsys translate_off
	initial
		read_data_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) read_data_state <= 1'b0;
		else  read_data_state <= (((read_init_counter & bit_counter_param_start_match) | (read_pre_data & bit_counter_param_start_match)) | ((read_data & (~ width_counter_param_width_match)) & (~ width_counter_all_done)));
	// synopsys translate_off
	initial
		read_init_counter_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) read_init_counter_state <= 1'b0;
		else  read_init_counter_state <= rsource_update_done;
	// synopsys translate_off
	initial
		read_init_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) read_init_state <= 1'b0;
		else  read_init_state <= (idle & read_param);
	// synopsys translate_off
	initial
		read_post_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) read_post_state <= 1'b0;
		else  read_post_state <= (((read_data & width_counter_param_width_match) & (~ width_counter_all_done)) | (read_post & (~ width_counter_all_done)));
	// synopsys translate_off
	initial
		read_pre_data_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) read_pre_data_state <= 1'b0;
		else  read_pre_data_state <= ((read_init_counter & (~ bit_counter_param_start_match)) | (read_pre_data & (~ bit_counter_param_start_match)));
	// synopsys translate_off
	initial
		read_source_update_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) read_source_update_state <= 1'b0;
		else  read_source_update_state <= ((read_init | read_source_update) & (~ rsource_update_done));
	// synopsys translate_off
	initial
		write_data_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_data_state <= 1'b0;
		else  write_data_state <= (((write_init_counter & bit_counter_param_start_match) | (write_pre_data & bit_counter_param_start_match)) | ((write_data & (~ width_counter_param_width_match)) & (~ bit_counter_all_done)));
	// synopsys translate_off
	initial
		write_init_counter_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_init_counter_state <= 1'b0;
		else  write_init_counter_state <= wsource_update_done;
	// synopsys translate_off
	initial
		write_init_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_init_state <= 1'b0;
		else  write_init_state <= (idle & write_param);
	// synopsys translate_off
	initial
		write_load_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_load_state <= 1'b0;
		else  write_load_state <= ((write_data & bit_counter_all_done) | (write_post_data & bit_counter_all_done));
	// synopsys translate_off
	initial
		write_post_data_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_post_data_state <= 1'b0;
		else  write_post_data_state <= (((write_data & width_counter_param_width_match) & (~ bit_counter_all_done)) | (write_post_data & (~ bit_counter_all_done)));
	// synopsys translate_off
	initial
		write_pre_data_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_pre_data_state <= 1'b0;
		else  write_pre_data_state <= ((write_init_counter & (~ bit_counter_param_start_match)) | (write_pre_data & (~ bit_counter_param_start_match)));
	// synopsys translate_off
	initial
		write_source_update_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_source_update_state <= 1'b0;
		else  write_source_update_state <= ((write_init | write_source_update) & (~ wsource_update_done));
	// synopsys translate_off
	initial
		write_wait_state = 0;
	// synopsys translate_on
	always @ ( posedge clock or  posedge reset)
		if (reset == 1'b1) write_wait_state <= 1'b0;
		else  write_wait_state <= write_load;
	lpm_counter   cntr5
	( 
	.aclr(reset),
	.clock(clock),
	.cnt_en(bit_counter_enable),
	.cout(),
	.eq(),
	.q(wire_cntr5_q),
	.sclr(bit_counter_clear)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.aload(1'b0),
	.aset(1'b0),
	.cin(1'b1),
	.clk_en(1'b1),
	.data({6{1'b0}}),
	.sload(1'b0),
	.sset(1'b0),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		cntr5.lpm_direction = "UP",
		cntr5.lpm_port_updown = "PORT_UNUSED",
		cntr5.lpm_width = 6,
		cntr5.lpm_type = "lpm_counter";
	lpm_counter   cntr6
	( 
	.aclr(reset),
	.clock(clock),
	.cnt_en(width_counter_enable),
	.cout(),
	.eq(),
	.q(wire_cntr6_q),
	.sclr(width_counter_clear)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.aload(1'b0),
	.aset(1'b0),
	.cin(1'b1),
	.clk_en(1'b1),
	.data({5{1'b0}}),
	.sload(1'b0),
	.sset(1'b0),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		cntr6.lpm_direction = "UP",
		cntr6.lpm_port_updown = "PORT_UNUSED",
		cntr6.lpm_width = 5,
		cntr6.lpm_type = "lpm_counter";
	cycloneive_rublock   sd4
	( 
	.captnupdt(rublock_captnupdt),
	.clk(rublock_clock),
	.rconfig(rublock_reconfig),
	.regin(rublock_regin),
	.regout(wire_sd4_regout),
	.rsttimer(reset_timer),
	.shiftnld(rublock_shiftnld));
	assign
		bit_counter_all_done = (((((wire_cntr5_q[0] & (~ wire_cntr5_q[1])) & (~ wire_cntr5_q[2])) & wire_cntr5_q[3]) & (~ wire_cntr5_q[4])) & wire_cntr5_q[5]),
		bit_counter_clear = (rsource_update_done | wsource_update_done),
		bit_counter_enable = (((((((((rsource_update_done | wsource_update_done) | read_init_counter) | write_init_counter) | read_pre_data) | write_pre_data) | read_data) | write_data) | read_post) | write_post_data),
		bit_counter_param_start = start_bit_decoder_out,
		bit_counter_param_start_match = ((((((~ w53w[0]) & (~ w53w[1])) & (~ w53w[2])) & (~ w53w[3])) & (~ w53w[4])) & (~ w53w[5])),
		busy = (~ idle),
		combine_port = {read_param, write_param, read_source, param},
		data_out = {((read_address & dffe7a[26]) | ((~ read_address) & dffe7a[28])), ((read_address & dffe7a[25]) | ((~ read_address) & dffe7a[27])), ((read_address & dffe7a[24]) | ((~ read_address) & dffe7a[26])), ((read_address & dffe7a[23]) | ((~ read_address) & dffe7a[25])), ((read_address & dffe7a[22]) | ((~ read_address) & dffe7a[24])), ((read_address & dffe7a[21]) | ((~ read_address) & dffe7a[23])), ((read_address & dffe7a[20]) | ((~ read_address) & dffe7a[22])), ((read_address & dffe7a[19]) | ((~ read_address) & dffe7a[21])), ((read_address & dffe7a[18]) | ((~ read_address) & dffe7a[20])), ((read_address & dffe7a[17]) | ((~ read_address) & dffe7a[19])), ((read_address & dffe7a[16]) | ((~ read_address) & dffe7a[18])), ((read_address & dffe7a[15]) | ((~ read_address) & dffe7a[17])), ((read_address & dffe7a[14]) | ((~ read_address) & dffe7a[16])), ((read_address & dffe7a[13]) | ((~ read_address) & dffe7a[15])), ((read_address & dffe7a[12]) | ((~ read_address) & dffe7a[14])), ((read_address & dffe7a[11]) | ((~ read_address) & dffe7a[13])), ((read_address & dffe7a[10]) | ((~ read_address) & dffe7a[12])), ((read_address & dffe7a[9]) | ((~ read_address) & dffe7a[11])), ((read_address & dffe7a[8]) | ((~ read_address) & dffe7a[10])), ((read_address & dffe7a[7]) | ((~ read_address) & dffe7a[9])), ((read_address & dffe7a[6]) | ((~ read_address) & dffe7a[8])), ((read_address & dffe7a[5]) | ((~ read_address) & dffe7a[7])), ((read_address & dffe7a[4]) | ((~ read_address) & dffe7a[6])), ((read_address & dffe7a[3]) | ((~ read_address) & dffe7a[5])), ((read_address & dffe7a[2]) | ((~ read_address) & dffe7a[4])), ((read_address & dffe7a[1]) | ((~ read_address) & dffe7a[3])), ((read_address & dffe7a[0]) | ((~ read_address) & dffe7a[2])), ((~ read_address) & dffe7a[1]), ((~ read_address) & dffe7a[0])},
		global_gnd = 1'b0,
		global_vcc = 1'b1,
		idle = idle_state,
		param_decoder_param_latch = dffe9a,
		param_decoder_select = {(((((((~ param_decoder_param_latch[0]) & param_decoder_param_latch[1]) & param_decoder_param_latch[2]) & param_decoder_param_latch[3]) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & param_decoder_param_latch[2]) & param_decoder_param_latch[3]) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), ((((((param_decoder_param_latch[0] & param_decoder_param_latch[1]) & (~ param_decoder_param_latch[2])) & param_decoder_param_latch[3]) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & param_decoder_param_latch[1]) & (~ param_decoder_param_latch[2])) & param_decoder_param_latch[3]) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), ((((((param_decoder_param_latch[0] & (~ param_decoder_param_latch[1])) & (~ param_decoder_param_latch[2])) & param_decoder_param_latch[3]) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & param_decoder_param_latch[1]) & param_decoder_param_latch[2]) & (~ param_decoder_param_latch[3])) & (~ param_decoder_param_latch[4])) & param_decoder_param_latch[5]) & (~ param_decoder_param_latch[6])), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & param_decoder_param_latch[2]) & (~ param_decoder_param_latch[3])) & (~ param_decoder_param_latch[4])) & param_decoder_param_latch[5]) & (~ param_decoder_param_latch[6])), ((((((param_decoder_param_latch[0] & param_decoder_param_latch[1]) & (~ param_decoder_param_latch[2])) & (~ param_decoder_param_latch[3])) & (~ param_decoder_param_latch[4])) & param_decoder_param_latch[5]) & (~ param_decoder_param_latch[6])), (((((((~ param_decoder_param_latch[0]) & param_decoder_param_latch[1]) & (~ param_decoder_param_latch[2]
)) & (~ param_decoder_param_latch[3])) & (~ param_decoder_param_latch[4])) & param_decoder_param_latch[5]) & (~ param_decoder_param_latch[6])), ((((((param_decoder_param_latch[0] & (~ param_decoder_param_latch[1])) & (~ param_decoder_param_latch[2])) & (~ param_decoder_param_latch[3])) & (~ param_decoder_param_latch[4])) & param_decoder_param_latch[5]) & (~ param_decoder_param_latch[6])), ((((((param_decoder_param_latch[0] & param_decoder_param_latch[1]) & param_decoder_param_latch[2]) & (~ param_decoder_param_latch[3])) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & param_decoder_param_latch[2]) & (~ param_decoder_param_latch[3])) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & (~ param_decoder_param_latch[2])) & (~ param_decoder_param_latch[3])) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), ((((((param_decoder_param_latch[0] & param_decoder_param_latch[1]) & param_decoder_param_latch[2]) & param_decoder_param_latch[3]) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & param_decoder_param_latch[2]) & param_decoder_param_latch[3]) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & (~ param_decoder_param_latch[2])) & param_decoder_param_latch[3]) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & param_decoder_param_latch[2]) & (~ param_decoder_param_latch[3])) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5]
)) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & (~ param_decoder_param_latch[2])) & (~ param_decoder_param_latch[3])) & param_decoder_param_latch[4]) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), ((((((param_decoder_param_latch[0] & param_decoder_param_latch[1]) & (~ param_decoder_param_latch[2])) & param_decoder_param_latch[3]) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & param_decoder_param_latch[1]) & (~ param_decoder_param_latch[2])) & param_decoder_param_latch[3]) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & (~ param_decoder_param_latch[2])) & param_decoder_param_latch[3]) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & param_decoder_param_latch[2]) & (~ param_decoder_param_latch[3])) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6]), (((((((~ param_decoder_param_latch[0]) & (~ param_decoder_param_latch[1])) & (~ param_decoder_param_latch[2])) & (~ param_decoder_param_latch[3])) & (~ param_decoder_param_latch[4])) & (~ param_decoder_param_latch[5])) & param_decoder_param_latch[6])},
		power_up = (((((((((((((((~ idle) & (~ read_init)) & (~ read_source_update)) & (~ read_init_counter)) & (~ read_pre_data)) & (~ read_data)) & (~ read_post)) & (~ write_init)) & (~ write_init_counter)) & (~ write_source_update)) & (~ write_pre_data)) & (~ write_data)) & (~ write_post_data)) & (~ write_load)) & (~ write_wait)),
		read_address = read_address_state,
		read_data = read_data_state,
		read_init = read_init_state,
		read_init_counter = read_init_counter_state,
		read_post = read_post_state,
		read_pre_data = read_pre_data_state,
		read_source_update = read_source_update_state,
		rsource_load = (idle & (write_param | read_param)),
		rsource_parallel_in = {((w4w[1] & read_param) | write_param), ((w4w[0] & read_param) | write_param)},
		rsource_serial_out = dffe1a0[0:0],
		rsource_shift_enable = (read_source_update | write_source_update),
		rsource_state_par_ini = {read_param, {2{global_gnd}}},
		rsource_update_done = dffe2a0[0:0],
		rublock_captnupdt = (~ write_load),
		rublock_clock = (~ (clock | idle_write_wait)),
		rublock_reconfig = rublock_reconfig_st,
		rublock_reconfig_st = (idle & reconfig),
		rublock_regin = (((((rublock_regout_reg & (~ select_shift_nloop)) & (~ read_source_update)) & (~ write_source_update)) | (((shift_reg_serial_out & select_shift_nloop) & (~ read_source_update)) & (~ write_source_update))) | ((read_source_update | write_source_update) & rsource_serial_out)),
		rublock_regout = wire_sd4_regout,
		rublock_regout_reg = dffe8,
		rublock_shiftnld = (((((((read_pre_data | write_pre_data) | read_data) | write_data) | read_post) | write_post_data) | read_source_update) | write_source_update),
		select_shift_nloop = ((read_data & (~ width_counter_param_width_match)) | (write_data & (~ width_counter_param_width_match))),
		shift_reg_clear = rsource_update_done,
		shift_reg_load_enable = (idle & write_param),
		shift_reg_serial_in = (rublock_regout_reg & select_shift_nloop),
		shift_reg_serial_out = dffe7a[0:0],
		shift_reg_shift_enable = (((read_data | write_data) | read_post) | write_post_data),
		start_bit_decoder_out = (((((((((((((((((((((({1'b0, {4{start_bit_decoder_param_select[0]}}, 1'b0} | {6{1'b0}}) | {1'b0, {4{start_bit_decoder_param_select[2]}}, 1'b0}) | {6{1'b0}}) | {1'b0, {3{start_bit_decoder_param_select[4]}}, 1'b0, start_bit_decoder_param_select[4]}) | {1'b0, {4{start_bit_decoder_param_select[5]}}, 1'b0}) | {6{1'b0}}) | {1'b0, {2{start_bit_decoder_param_select[7]}}, {3{1'b0}}}) | {6{1'b0}}) | {1'b0, {2{start_bit_decoder_param_select[9]}}, 1'b0, start_bit_decoder_param_select[9], 1'b0}) | {1'b0, {2{start_bit_decoder_param_select[10]}}, {3{1'b0}}}) | {6{1'b0}}) | {1'b0, {2{start_bit_decoder_param_select[12]}}, 1'b0, start_bit_decoder_param_select[12], 1'b0}) | {start_bit_decoder_param_select[13], {2{1'b0}}, start_bit_decoder_param_select[13], 1'b0, start_bit_decoder_param_select[13]}) | {6{1'b0}}) | {start_bit_decoder_param_select[15], {3{1'b0}}, {2{start_bit_decoder_param_select[15]}}}) | {{2{1'b0}}, {2{start_bit_decoder_param_select[16]}}, {2{1'b0}}}) | {start_bit_decoder_param_select[17], {2{1'b0}}, start_bit_decoder_param_select[17], {2{1'b0}}}) | {start_bit_decoder_param_select[18], {2{1'b0}}, start_bit_decoder_param_select[18], 1'b0, start_bit_decoder_param_select[18]}) | {6{1'b0}}) | {start_bit_decoder_param_select[20], {3{1'b0}}, {2{start_bit_decoder_param_select[20]}}}) | {{2{1'b0}}, {2{start_bit_decoder_param_select[21]}}, {2{1'b0}}}) | {start_bit_decoder_param_select[22], {2{1'b0}}, start_bit_decoder_param_select[22], {2{1'b0}}}),
		start_bit_decoder_param_select = param_decoder_select,
		w4w = read_source,
		w53w = (wire_cntr5_q ^ bit_counter_param_start),
		w83w = (wire_cntr6_q ^ width_counter_param_width),
		width_counter_all_done = (((((~ wire_cntr6_q[0]) & (~ wire_cntr6_q[1])) & wire_cntr6_q[2]) & wire_cntr6_q[3]) & wire_cntr6_q[4]),
		width_counter_clear = (rsource_update_done | wsource_update_done),
		width_counter_enable = ((read_data | write_data) | read_post),
		width_counter_param_width = width_decoder_out,
		width_counter_param_width_match = (((((~ w83w[0]) & (~ w83w[1])) & (~ w83w[2])) & (~ w83w[3])) & (~ w83w[4])),
		width_decoder_out = (((((((((((((((((((((({{3{1'b0}}, width_decoder_param_select[0], 1'b0} | {{2{width_decoder_param_select[1]}}, {3{1'b0}}}) | {{3{1'b0}}, width_decoder_param_select[2], 1'b0}) | {{3{width_decoder_param_select[3]}}, 1'b0, width_decoder_param_select[3]}) | {{4{1'b0}}, width_decoder_param_select[4]}) | {{3{1'b0}}, width_decoder_param_select[5], 1'b0}) | {{2{width_decoder_param_select[6]}}, {3{1'b0}}}) | {{3{1'b0}}, width_decoder_param_select[7], 1'b0}) | {{2{width_decoder_param_select[8]}}, {3{1'b0}}}) | {{2{1'b0}}, width_decoder_param_select[9], 1'b0, width_decoder_param_select[9]}) | {{3{1'b0}}, width_decoder_param_select[10], 1'b0}) | {{2{width_decoder_param_select[11]}}, {3{1'b0}}}) | {{2{1'b0}}, width_decoder_param_select[12], 1'b0, width_decoder_param_select[12]}) | {{4{1'b0}}, width_decoder_param_select[13]}) | {1'b0, {2{width_decoder_param_select[14]}}, {2{1'b0}}}) | {{4{1'b0}}, width_decoder_param_select[15]}) | {width_decoder_param_select[16], 1'b0, {2{width_decoder_param_select[16]}}, 1'b0}) | {{4{1'b0}}, width_decoder_param_select[17]}) | {{4{1'b0}}, width_decoder_param_select[18]}) | {1'b0, {2{width_decoder_param_select[19]}}, {2{1'b0}}}) | {{4{1'b0}}, width_decoder_param_select[20]}) | {width_decoder_param_select[21], 1'b0, {2{width_decoder_param_select[21]}}, 1'b0}) | {{4{1'b0}}, width_decoder_param_select[22]}),
		width_decoder_param_select = param_decoder_select,
		write_data = write_data_state,
		write_init = write_init_state,
		write_init_counter = write_init_counter_state,
		write_load = write_load_state,
		write_post_data = write_post_data_state,
		write_pre_data = write_pre_data_state,
		write_source_update = write_source_update_state,
		write_wait = write_wait_state,
		wsource_state_par_ini = {write_param, {2{global_gnd}}},
		wsource_update_done = dffe3a0[0:0];
endmodule //altera_remote_update_core
//VALID FILE
//altasmi_parallel CBX_AUTO_BLACKBOX="ALL" CBX_SINGLE_OUTPUT_FILE="ON" DATA_WIDTH="STANDARD" DEVICE_FAMILY="Cyclone IV E" ENABLE_SIM="FALSE" EPCS_TYPE="EPCS16" FLASH_RSTPIN="FALSE" PAGE_SIZE=256 PORT_BULK_ERASE="PORT_USED" PORT_DIE_ERASE="PORT_UNUSED" PORT_EN4B_ADDR="PORT_UNUSED" PORT_EX4B_ADDR="PORT_UNUSED" PORT_FAST_READ="PORT_UNUSED" PORT_ILLEGAL_ERASE="PORT_USED" PORT_ILLEGAL_WRITE="PORT_USED" PORT_RDID_OUT="PORT_UNUSED" PORT_READ_ADDRESS="PORT_UNUSED" PORT_READ_DUMMYCLK="PORT_UNUSED" PORT_READ_RDID="PORT_UNUSED" PORT_READ_SID="PORT_USED" PORT_READ_STATUS="PORT_UNUSED" PORT_SECTOR_ERASE="PORT_USED" PORT_SECTOR_PROTECT="PORT_USED" PORT_SHIFT_BYTES="PORT_USED" PORT_WREN="PORT_USED" PORT_WRITE="PORT_USED" USE_ASMIBLOCK="ON" USE_EAB="ON" WRITE_DUMMY_CLK=0 addr bulk_erase busy clkin data_valid datain dataout epcs_id illegal_erase illegal_write rden read read_sid reset sector_erase sector_protect shift_bytes wren write INTENDED_DEVICE_FAMILY="Cyclone IV E" ALTERA_INTERNAL_OPTIONS=SUPPRESS_DA_RULE_INTERNAL=C106
//VERSION_BEGIN 18.1 cbx_a_gray2bin 2018:09:12:13:04:09:SJ cbx_a_graycounter 2018:09:12:13:04:09:SJ cbx_altasmi_parallel 2018:09:12:13:04:09:SJ cbx_altdpram 2018:09:12:13:04:09:SJ cbx_altera_counter 2018:09:12:13:04:09:SJ cbx_altera_syncram 2018:09:12:13:04:09:SJ cbx_altera_syncram_nd_impl 2018:09:12:13:04:09:SJ cbx_altsyncram 2018:09:12:13:04:09:SJ cbx_arriav 2018:09:12:13:04:09:SJ cbx_cyclone 2018:09:12:13:04:09:SJ cbx_cycloneii 2018:09:12:13:04:09:SJ cbx_fifo_common 2018:09:12:13:04:09:SJ cbx_lpm_add_sub 2018:09:12:13:04:09:SJ cbx_lpm_compare 2018:09:12:13:04:09:SJ cbx_lpm_counter 2018:09:12:13:04:09:SJ cbx_lpm_decode 2018:09:12:13:04:09:SJ cbx_lpm_mux 2018:09:12:13:04:09:SJ cbx_mgl 2018:09:12:14:15:07:SJ cbx_nadder 2018:09:12:13:04:09:SJ cbx_nightfury 2018:09:12:13:04:09:SJ cbx_scfifo 2018:09:12:13:04:09:SJ cbx_stratix 2018:09:12:13:04:09:SJ cbx_stratixii 2018:09:12:13:04:09:SJ cbx_stratixiii 2018:09:12:13:04:09:SJ cbx_stratixv 2018:09:12:13:04:09:SJ cbx_util_mgl 2018:09:12:13:04:09:SJ cbx_zippleback 2018:09:12:13:04:09:SJ  VERSION_END
// synthesis VERILOG_INPUT_VERSION VERILOG_2001
// altera message_off 10463



// Copyright (C) 2018  Intel Corporation. All rights reserved.
//  Your use of Intel Corporation's design tools, logic functions 
//  and other software and tools, and its AMPP partner logic 
//  functions, and any output files from any of the foregoing 
//  (including device programming or simulation files), and any 
//  associated documentation or information are expressly subject 
//  to the terms and conditions of the Intel Program License 
//  Subscription Agreement, the Intel Quartus Prime License Agreement,
//  the Intel FPGA IP License Agreement, or other applicable license
//  agreement, including, without limitation, that your use is for
//  the sole purpose of programming logic devices manufactured by
//  Intel and sold by Intel or its authorized distributors.  Please
//  refer to the applicable agreement for further details.



//synthesis_resources = a_graycounter 6 cycloneive_asmiblock 1 lpm_compare 2 lpm_counter 2 lut 76 mux21 1 reg 130 
//synopsys translate_off
`timescale 1 ps / 1 ps
//synopsys translate_on
(* ALTERA_ATTRIBUTE = {"SUPPRESS_DA_RULE_INTERNAL=C106"} *)
(* blackbox *)
module  asmi_asmi_parallel_0
	( 
	addr,
	bulk_erase,
	busy,
	clkin,
	data_valid,
	datain,
	dataout,
	epcs_id,
	illegal_erase,
	illegal_write,
	rden,
	read,
	read_sid,
	reset,
	sector_erase,
	sector_protect,
	shift_bytes,
	wren,
	write) /* synthesis synthesis_clearbox=1 */;
	input   [23:0]  addr;
	input   bulk_erase;
	output   busy;
	input   clkin;
	output   data_valid;
	input   [7:0]  datain;
	output   [7:0]  dataout;
	output   [7:0]  epcs_id;
	output   illegal_erase;
	output   illegal_write;
	input   rden;
	input   read;
	input   read_sid;
	input   reset;
	input   sector_erase;
	input   sector_protect;
	input   shift_bytes;
	input   wren;
	input   write;
/*
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri0   bulk_erase;
	tri0   [7:0]  datain;
	tri0   read;
	tri0   read_sid;
	tri0   reset;
	tri0   sector_erase;
	tri0   sector_protect;
	tri0   shift_bytes;
	tri1   wren;
	tri0   write;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire  [2:0]   wire_addbyte_cntr_q;
	wire  [2:0]   wire_gen_cntr_q;
	wire  [2:0]   wire_read_flag_status_cntr_q;
	wire  [1:0]   wire_spstage_cntr_q;
	wire  [1:0]   wire_stage_cntr_q;
	wire  [1:0]   wire_wrstage_cntr_q;
	wire  wire_sd2_data0out;
	reg	add_msb_reg;
	wire	wire_add_msb_reg_ena;
	wire	[23:0]	wire_addr_reg_d;
	reg	[23:0]	addr_reg;
	wire	[23:0]	wire_addr_reg_ena;
	wire	[7:0]	wire_asmi_opcode_reg_d;
	reg	[7:0]	asmi_opcode_reg;
	wire	[7:0]	wire_asmi_opcode_reg_ena;
	reg	buf_empty_reg;
	reg	bulk_erase_reg;
	wire	wire_bulk_erase_reg_ena;
	reg	busy_det_reg;
	reg	clr_read_reg;
	reg	clr_read_reg2;
	reg	clr_rstat_reg;
	reg	clr_secprot_reg;
	reg	clr_secprot_reg1;
	reg	clr_sid_reg;
	reg	clr_write_reg;
	reg	clr_write_reg2;
	reg	cnt_bfend_reg;
	reg	do_wrmemadd_reg;
	reg	dvalid_reg;
	wire	wire_dvalid_reg_ena;
	wire	wire_dvalid_reg_sclr;
	reg	dvalid_reg2;
	reg	end1_cyc_reg;
	reg	end1_cyc_reg2;
	reg	end_op_hdlyreg;
	reg	end_op_reg;
	reg	end_pgwrop_reg;
	wire	wire_end_pgwrop_reg_ena;
	reg	end_rbyte_reg;
	wire	wire_end_rbyte_reg_ena;
	wire	wire_end_rbyte_reg_sclr;
	reg	end_read_reg;
	reg	[7:0]	epcs_id_reg2;
	reg	ill_erase_reg;
	reg	ill_write_reg;
	reg	illegal_write_prot_reg;
	reg	max_cnt_reg;
	reg	maxcnt_shift_reg;
	reg	maxcnt_shift_reg2;
	reg	ncs_reg;
	wire	wire_ncs_reg_sclr;
	wire	[7:0]	wire_pgwrbuf_dataout_d;
	reg	[7:0]	pgwrbuf_dataout;
	wire	[7:0]	wire_pgwrbuf_dataout_ena;
	reg	read_bufdly_reg;
	wire	[7:0]	wire_read_data_reg_d;
	reg	[7:0]	read_data_reg;
	wire	[7:0]	wire_read_data_reg_ena;
	wire	[7:0]	wire_read_dout_reg_d;
	reg	[7:0]	read_dout_reg;
	wire	[7:0]	wire_read_dout_reg_ena;
	reg	read_reg;
	wire	wire_read_reg_ena;
	reg	read_sid_reg;
	wire	wire_read_sid_reg_ena;
	reg	sec_erase_reg;
	wire	wire_sec_erase_reg_ena;
	reg	sec_prot_reg;
	wire	wire_sec_prot_reg_ena;
	reg	shftpgwr_data_reg;
	reg	shift_op_reg;
	reg	sprot_rstat_reg;
	reg	stage2_reg;
	reg	stage3_dly_reg;
	reg	stage3_reg;
	reg	stage4_reg;
	reg	start_sppoll_reg;
	wire	wire_start_sppoll_reg_ena;
	reg	start_sppoll_reg2;
	reg	start_wrpoll_reg;
	wire	wire_start_wrpoll_reg_ena;
	reg	start_wrpoll_reg2;
	wire	[7:0]	wire_statreg_int_d;
	reg	[7:0]	statreg_int;
	wire	[7:0]	wire_statreg_int_ena;
	reg	streg_datain_reg;
	wire	wire_streg_datain_reg_ena;
	reg	write_prot_reg;
	wire	wire_write_prot_reg_ena;
	reg	write_reg;
	wire	wire_write_reg_ena;
	reg	write_rstat_reg;
	wire	[7:0]	wire_wrstat_dreg_d;
	reg	[7:0]	wrstat_dreg;
	wire	[7:0]	wire_wrstat_dreg_ena;
	wire  wire_cmpr4_aeb;
	wire  wire_cmpr5_aeb;
	wire  [8:0]   wire_pgwr_data_cntr_q;
	wire  [8:0]   wire_pgwr_read_cntr_q;
	wire	wire_mux211_dataout;
	wire  [7:0]   wire_scfifo3_q;
	wire  addr_overdie;
	wire  addr_overdie_pos;
	wire  [23:0]  addr_reg_overdie;
	wire  [7:0]  b4addr_opcode;
	wire  be_write_prot;
	wire  [7:0]  berase_opcode;
	wire  bp0_wire;
	wire  bp1_wire;
	wire  bp2_wire;
	wire  bp3_wire;
	wire  buf_empty;
	wire  bulk_erase_wire;
	wire  busy_wire;
	wire  clkin_wire;
	wire  clr_addmsb_wire;
	wire  clr_endrbyte_wire;
	wire  clr_read_wire;
	wire  clr_read_wire2;
	wire  clr_rstat_wire;
	wire  clr_secprot_wire;
	wire  clr_secprot_wire1;
	wire  clr_sid_wire;
	wire  clr_write_wire;
	wire  clr_write_wire2;
	wire  cnt_bfend_wire_in;
	wire  data0out_wire;
	wire  data_valid_wire;
	wire  [3:0]  datain_wire;
	wire  [3:0]  dataout_wire;
	wire  [7:0]  derase_opcode;
	wire  do_4baddr;
	wire  do_bulk_erase;
	wire  do_die_erase;
	wire  do_ex4baddr;
	wire  do_fast_read;
	wire  do_fread_epcq;
	wire  do_freadwrv_polling;
	wire  do_memadd;
	wire  do_polling;
	wire  do_read;
	wire  do_read_nonvolatile;
	wire  do_read_rdid;
	wire  do_read_sid;
	wire  do_read_stat;
	wire  do_read_volatile;
	wire  do_sec_erase;
	wire  do_sec_prot;
	wire  do_secprot_wren;
	wire  do_sprot_polling;
	wire  do_sprot_rstat;
	wire  do_wait_dummyclk;
	wire  do_wren;
	wire  do_write;
	wire  do_write_polling;
	wire  do_write_rstat;
	wire  do_write_volatile;
	wire  do_write_volatile_rstat;
	wire  do_write_volatile_wren;
	wire  do_write_wren;
	wire  dummy_read_buf;
	wire  end1_cyc_gen_cntr_wire;
	wire  end1_cyc_normal_in_wire;
	wire  end1_cyc_reg_in_wire;
	wire  end_add_cycle;
	wire  end_add_cycle_mux_datab_wire;
	wire  end_fast_read;
	wire  end_one_cyc_pos;
	wire  end_one_cycle;
	wire  end_op_wire;
	wire  end_operation;
	wire  end_ophdly;
	wire  end_pgwr_data;
	wire  end_read;
	wire  end_read_byte;
	wire  end_read_flag_status;
	wire  end_wrstage;
	wire  [7:0]  exb4addr_opcode;
	wire  [7:0]  fast_read_opcode;
	wire  fast_read_wire;
	wire  freadwrv_sdoin;
	wire  ill_erase_wire;
	wire  ill_write_wire;
	wire  illegal_erase_b4out_wire;
	wire  illegal_write_b4out_wire;
	wire  in_operation;
	wire  load_opcode;
	wire  [4:0]  mask_prot;
	wire  [4:0]  mask_prot_add;
	wire  [4:0]  mask_prot_check;
	wire  [4:0]  mask_prot_comp_ntb;
	wire  [4:0]  mask_prot_comp_tb;
	wire  memadd_sdoin;
	wire  ncs_reg_ena_wire;
	wire  not_busy;
	wire  oe_wire;
	wire  [8:0]  page_size_wire;
	wire  [8:0]  pagewr_buf_not_empty;
	wire  [7:0]  prot_wire;
	wire  rden_wire;
	wire  [7:0]  rdid_opcode;
	wire  [7:0]  rdummyclk_opcode;
	wire  reach_max_cnt;
	wire  read_buf;
	wire  read_bufdly;
	wire  [7:0]  read_data_reg_in_wire;
	wire  [7:0]  read_opcode;
	wire  read_rdid_wire;
	wire  read_sid_wire;
	wire  read_status_wire;
	wire  read_wire;
	wire  [7:0]  rflagstat_opcode;
	wire  [7:0]  rnvdummyclk_opcode;
	wire  [7:0]  rsid_opcode;
	wire  rsid_sdoin;
	wire  [7:0]  rstat_opcode;
	wire  scein_wire;
	wire  sdoin_wire;
	wire  sec_erase_wire;
	wire  sec_protect_wire;
	wire  [7:0]  secprot_opcode;
	wire  secprot_sdoin;
	wire  [7:0]  serase_opcode;
	wire  shift_bytes_wire;
	wire  shift_opcode;
	wire  shift_opdata;
	wire  shift_pgwr_data;
	wire  sid_load;
	wire  st_busy_wire;
	wire  stage2_wire;
	wire  stage3_wire;
	wire  stage4_wire;
	wire  start_frpoll;
	wire  start_poll;
	wire  start_sppoll;
	wire  start_wrpoll;
	wire  to_sdoin_wire;
	wire  [7:0]  wren_opcode;
	wire  wren_wire;
	wire  [7:0]  write_opcode;
	wire  write_prot_true;
	wire  write_sdoin;
	wire  write_wire;
	wire  [7:0]  wrvolatile_opcode;

	a_graycounter   addbyte_cntr
	( 
	.aclr(reset),
	.clk_en((((((wire_stage_cntr_q[1] & wire_stage_cntr_q[0]) & end_one_cyc_pos) & (((((((do_read_sid | do_write) | do_sec_erase) | do_die_erase) | do_read_rdid) | do_read) | do_fast_read) | do_read_nonvolatile)) | addr_overdie) | end_operation)),
	.clock((~ clkin_wire)),
	.q(wire_addbyte_cntr_q),
	.qbin(),
	.sclr((end_operation | addr_overdie))
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.cnt_en(1'b1),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		addbyte_cntr.width = 3,
		addbyte_cntr.lpm_type = "a_graycounter";
	a_graycounter   gen_cntr
	( 
	.aclr(reset),
	.clk_en((((((in_operation & (~ end_ophdly)) & (~ clr_rstat_wire)) & (~ clr_sid_wire)) | do_wait_dummyclk) | addr_overdie)),
	.clock(clkin_wire),
	.q(wire_gen_cntr_q),
	.qbin(),
	.sclr(((end1_cyc_reg_in_wire | addr_overdie) | do_wait_dummyclk))
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.cnt_en(1'b1),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		gen_cntr.width = 3,
		gen_cntr.lpm_type = "a_graycounter";
	a_graycounter   read_flag_status_cntr
	( 
	.aclr(reset),
	.clk_en(((((start_sppoll & end_operation) & (~ end_read_flag_status)) & (~ st_busy_wire)) | (clr_secprot_wire1 | ((start_sppoll & st_busy_wire) & stage3_wire)))),
	.clock(clkin_wire),
	.q(wire_read_flag_status_cntr_q),
	.qbin(),
	.sclr((clr_secprot_wire1 | ((start_sppoll & st_busy_wire) & stage3_wire)))
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.cnt_en(1'b1),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		read_flag_status_cntr.width = 3,
		read_flag_status_cntr.lpm_type = "a_graycounter";
	a_graycounter   spstage_cntr
	( 
	.aclr(reset),
	.clk_en(((((do_sec_prot & end_operation) & (~ do_sprot_polling)) | (((do_sec_prot & end_operation) & do_sprot_polling) & end_read_flag_status)) | clr_secprot_wire1)),
	.clock((~ clkin_wire)),
	.q(wire_spstage_cntr_q),
	.qbin(),
	.sclr(clr_secprot_wire1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.cnt_en(1'b1),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		spstage_cntr.width = 2,
		spstage_cntr.lpm_type = "a_graycounter";
	a_graycounter   stage_cntr
	( 
	.aclr(reset),
	.clk_en(((((((((((((((in_operation & end_one_cycle) & (~ (stage3_wire & (~ end_add_cycle)))) & (~ (stage4_wire & (~ end_read)))) & (~ (stage4_wire & (~ end_fast_read)))) & (~ ((((do_write | do_sec_erase) | do_die_erase) | do_bulk_erase) & write_prot_true))) & (~ (do_write & (~ pagewr_buf_not_empty[8])))) & (~ (stage3_wire & st_busy_wire))) & (~ ((do_write & shift_pgwr_data) & (~ end_pgwr_data)))) & (~ (stage2_wire & do_wren))) & (~ ((((stage3_wire & (do_sec_erase | do_die_erase)) & (~ do_wren)) & (~ do_read_stat)) & (~ do_read_rdid)))) & (~ (stage3_wire & ((do_write_volatile | do_read_volatile) | do_read_nonvolatile)))) | ((stage3_wire & do_fast_read) & do_wait_dummyclk)) | addr_overdie) | end_ophdly)),
	.clock(clkin_wire),
	.q(wire_stage_cntr_q),
	.qbin(),
	.sclr((end_operation | addr_overdie))
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.cnt_en(1'b1),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		stage_cntr.width = 2,
		stage_cntr.lpm_type = "a_graycounter";
	a_graycounter   wrstage_cntr
	( 
	.aclr(reset),
	.clk_en((((((((((do_write | do_sec_erase) | do_bulk_erase) | do_die_erase) & (~ write_prot_true)) | do_4baddr) | do_ex4baddr) & end_wrstage) & (~ st_busy_wire)) | clr_write_wire2)),
	.clock((~ clkin_wire)),
	.q(wire_wrstage_cntr_q),
	.qbin(),
	.sclr(clr_write_wire2)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.cnt_en(1'b1),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		wrstage_cntr.width = 2,
		wrstage_cntr.lpm_type = "a_graycounter";
	cycloneive_asmiblock   sd2
	( 
	.data0out(wire_sd2_data0out),
	.dclkin(clkin_wire),
	.oe(oe_wire),
	.scein(scein_wire),
	.sdoin((sdoin_wire | datain_wire[0])));
	// synopsys translate_off
	initial
		add_msb_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) add_msb_reg <= 1'b0;
		else if  (wire_add_msb_reg_ena == 1'b1) 
			if (clr_addmsb_wire == 1'b1) add_msb_reg <= 1'b0;
			else  add_msb_reg <= addr_reg[23];
	assign
		wire_add_msb_reg_ena = ((((((((do_read | do_fast_read) | do_write) | do_sec_erase) | do_die_erase) & (~ (((do_write | do_sec_erase) | do_die_erase) & (~ do_memadd)))) & wire_stage_cntr_q[1]) & wire_stage_cntr_q[0]) | clr_addmsb_wire);
	// synopsys translate_off
	initial
		addr_reg[0:0] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[0:0] <= 1'b0;
		else if  (wire_addr_reg_ena[0:0] == 1'b1)   addr_reg[0:0] <= wire_addr_reg_d[0:0];
	// synopsys translate_off
	initial
		addr_reg[1:1] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[1:1] <= 1'b0;
		else if  (wire_addr_reg_ena[1:1] == 1'b1)   addr_reg[1:1] <= wire_addr_reg_d[1:1];
	// synopsys translate_off
	initial
		addr_reg[2:2] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[2:2] <= 1'b0;
		else if  (wire_addr_reg_ena[2:2] == 1'b1)   addr_reg[2:2] <= wire_addr_reg_d[2:2];
	// synopsys translate_off
	initial
		addr_reg[3:3] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[3:3] <= 1'b0;
		else if  (wire_addr_reg_ena[3:3] == 1'b1)   addr_reg[3:3] <= wire_addr_reg_d[3:3];
	// synopsys translate_off
	initial
		addr_reg[4:4] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[4:4] <= 1'b0;
		else if  (wire_addr_reg_ena[4:4] == 1'b1)   addr_reg[4:4] <= wire_addr_reg_d[4:4];
	// synopsys translate_off
	initial
		addr_reg[5:5] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[5:5] <= 1'b0;
		else if  (wire_addr_reg_ena[5:5] == 1'b1)   addr_reg[5:5] <= wire_addr_reg_d[5:5];
	// synopsys translate_off
	initial
		addr_reg[6:6] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[6:6] <= 1'b0;
		else if  (wire_addr_reg_ena[6:6] == 1'b1)   addr_reg[6:6] <= wire_addr_reg_d[6:6];
	// synopsys translate_off
	initial
		addr_reg[7:7] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[7:7] <= 1'b0;
		else if  (wire_addr_reg_ena[7:7] == 1'b1)   addr_reg[7:7] <= wire_addr_reg_d[7:7];
	// synopsys translate_off
	initial
		addr_reg[8:8] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[8:8] <= 1'b0;
		else if  (wire_addr_reg_ena[8:8] == 1'b1)   addr_reg[8:8] <= wire_addr_reg_d[8:8];
	// synopsys translate_off
	initial
		addr_reg[9:9] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[9:9] <= 1'b0;
		else if  (wire_addr_reg_ena[9:9] == 1'b1)   addr_reg[9:9] <= wire_addr_reg_d[9:9];
	// synopsys translate_off
	initial
		addr_reg[10:10] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[10:10] <= 1'b0;
		else if  (wire_addr_reg_ena[10:10] == 1'b1)   addr_reg[10:10] <= wire_addr_reg_d[10:10];
	// synopsys translate_off
	initial
		addr_reg[11:11] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[11:11] <= 1'b0;
		else if  (wire_addr_reg_ena[11:11] == 1'b1)   addr_reg[11:11] <= wire_addr_reg_d[11:11];
	// synopsys translate_off
	initial
		addr_reg[12:12] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[12:12] <= 1'b0;
		else if  (wire_addr_reg_ena[12:12] == 1'b1)   addr_reg[12:12] <= wire_addr_reg_d[12:12];
	// synopsys translate_off
	initial
		addr_reg[13:13] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[13:13] <= 1'b0;
		else if  (wire_addr_reg_ena[13:13] == 1'b1)   addr_reg[13:13] <= wire_addr_reg_d[13:13];
	// synopsys translate_off
	initial
		addr_reg[14:14] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[14:14] <= 1'b0;
		else if  (wire_addr_reg_ena[14:14] == 1'b1)   addr_reg[14:14] <= wire_addr_reg_d[14:14];
	// synopsys translate_off
	initial
		addr_reg[15:15] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[15:15] <= 1'b0;
		else if  (wire_addr_reg_ena[15:15] == 1'b1)   addr_reg[15:15] <= wire_addr_reg_d[15:15];
	// synopsys translate_off
	initial
		addr_reg[16:16] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[16:16] <= 1'b0;
		else if  (wire_addr_reg_ena[16:16] == 1'b1)   addr_reg[16:16] <= wire_addr_reg_d[16:16];
	// synopsys translate_off
	initial
		addr_reg[17:17] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[17:17] <= 1'b0;
		else if  (wire_addr_reg_ena[17:17] == 1'b1)   addr_reg[17:17] <= wire_addr_reg_d[17:17];
	// synopsys translate_off
	initial
		addr_reg[18:18] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[18:18] <= 1'b0;
		else if  (wire_addr_reg_ena[18:18] == 1'b1)   addr_reg[18:18] <= wire_addr_reg_d[18:18];
	// synopsys translate_off
	initial
		addr_reg[19:19] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[19:19] <= 1'b0;
		else if  (wire_addr_reg_ena[19:19] == 1'b1)   addr_reg[19:19] <= wire_addr_reg_d[19:19];
	// synopsys translate_off
	initial
		addr_reg[20:20] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[20:20] <= 1'b0;
		else if  (wire_addr_reg_ena[20:20] == 1'b1)   addr_reg[20:20] <= wire_addr_reg_d[20:20];
	// synopsys translate_off
	initial
		addr_reg[21:21] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[21:21] <= 1'b0;
		else if  (wire_addr_reg_ena[21:21] == 1'b1)   addr_reg[21:21] <= wire_addr_reg_d[21:21];
	// synopsys translate_off
	initial
		addr_reg[22:22] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[22:22] <= 1'b0;
		else if  (wire_addr_reg_ena[22:22] == 1'b1)   addr_reg[22:22] <= wire_addr_reg_d[22:22];
	// synopsys translate_off
	initial
		addr_reg[23:23] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) addr_reg[23:23] <= 1'b0;
		else if  (wire_addr_reg_ena[23:23] == 1'b1)   addr_reg[23:23] <= wire_addr_reg_d[23:23];
	assign
		wire_addr_reg_d = {((({23{not_busy}} & addr[23:1]) | ({23{stage3_wire}} & addr_reg[22:0])) | ({23{addr_overdie}} & addr_reg_overdie[23:1])), ((not_busy & addr[0]) | (addr_overdie & addr_reg_overdie[0]))};
	assign
		wire_addr_reg_ena = {24{((((rden_wire | wren_wire) & not_busy) | (stage4_wire & addr_overdie)) | (stage3_wire & ((((do_write | do_sec_erase) | do_die_erase) & do_memadd) | (do_read | do_fast_read))))}};
	// synopsys translate_off
	initial
		asmi_opcode_reg[0:0] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[0:0] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[0:0] == 1'b1)   asmi_opcode_reg[0:0] <= wire_asmi_opcode_reg_d[0:0];
	// synopsys translate_off
	initial
		asmi_opcode_reg[1:1] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[1:1] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[1:1] == 1'b1)   asmi_opcode_reg[1:1] <= wire_asmi_opcode_reg_d[1:1];
	// synopsys translate_off
	initial
		asmi_opcode_reg[2:2] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[2:2] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[2:2] == 1'b1)   asmi_opcode_reg[2:2] <= wire_asmi_opcode_reg_d[2:2];
	// synopsys translate_off
	initial
		asmi_opcode_reg[3:3] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[3:3] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[3:3] == 1'b1)   asmi_opcode_reg[3:3] <= wire_asmi_opcode_reg_d[3:3];
	// synopsys translate_off
	initial
		asmi_opcode_reg[4:4] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[4:4] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[4:4] == 1'b1)   asmi_opcode_reg[4:4] <= wire_asmi_opcode_reg_d[4:4];
	// synopsys translate_off
	initial
		asmi_opcode_reg[5:5] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[5:5] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[5:5] == 1'b1)   asmi_opcode_reg[5:5] <= wire_asmi_opcode_reg_d[5:5];
	// synopsys translate_off
	initial
		asmi_opcode_reg[6:6] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[6:6] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[6:6] == 1'b1)   asmi_opcode_reg[6:6] <= wire_asmi_opcode_reg_d[6:6];
	// synopsys translate_off
	initial
		asmi_opcode_reg[7:7] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) asmi_opcode_reg[7:7] <= 1'b0;
		else if  (wire_asmi_opcode_reg_ena[7:7] == 1'b1)   asmi_opcode_reg[7:7] <= wire_asmi_opcode_reg_d[7:7];
	assign
		wire_asmi_opcode_reg_d = {(((((((((((((((((({7{(load_opcode & do_read_sid)}} & rsid_opcode[7:1]) | ({7{(load_opcode & do_read_rdid)}} & rdid_opcode[7:1])) | ({7{(((load_opcode & do_sec_prot) & (~ do_wren)) & (~ do_read_stat))}} & secprot_opcode[7:1])) | ({7{(load_opcode & do_read)}} & read_opcode[7:1])) | ({7{(load_opcode & do_fast_read)}} & fast_read_opcode[7:1])) | ({7{((((load_opcode & do_read_volatile) & (~ do_write_volatile)) & (~ do_wren)) & (~ do_read_stat))}} & rdummyclk_opcode[7:1])) | ({7{((((load_opcode & do_write_volatile) & (~ do_read_volatile)) & (~ do_wren)) & (~ do_read_stat))}} & wrvolatile_opcode[7:1])) | ({7{(load_opcode & do_read_nonvolatile)}} & rnvdummyclk_opcode[7:1])) | ({7{(load_opcode & ((do_write & (~ do_read_stat)) & (~ do_wren)))}} & write_opcode[7:1])) | ({7{((load_opcode & do_read_stat) & (~ do_polling))}} & rstat_opcode[7:1])) | ({7{((load_opcode & do_read_stat) & do_polling)}} & rflagstat_opcode[7:1])) | ({7{(((load_opcode & do_sec_erase) & (~ do_wren)) & (~ do_read_stat))}} & serase_opcode[7:1])) | ({7{(((load_opcode & do_die_erase) & (~ do_wren)) & (~ do_read_stat))}} & derase_opcode[7:1])) | ({7{(((load_opcode & do_bulk_erase) & (~ do_wren)) & (~ do_read_stat))}} & berase_opcode[7:1])) | ({7{(load_opcode & do_wren)}} & wren_opcode[7:1])) | ({7{(load_opcode & ((do_4baddr & (~ do_read_stat)) & (~ do_wren)))}} & b4addr_opcode[7:1])) | ({7{(load_opcode & ((do_ex4baddr & (~ do_read_stat)) & (~ do_wren)))}} & exb4addr_opcode[7:1])) | ({7{shift_opcode}} & asmi_opcode_reg[6:0])), ((((((((((((((((((load_opcode & do_read_sid) & rsid_opcode[0]) | ((load_opcode & do_read_rdid) & rdid_opcode[0])) | ((((load_opcode & do_sec_prot) & (~ do_wren)) & (~ do_read_stat)) & secprot_opcode[0])) | ((load_opcode & do_read) & read_opcode[0])) | ((load_opcode & do_fast_read) & fast_read_opcode[0])) | (((((load_opcode & do_read_volatile) & (~ do_write_volatile)) & (~ do_wren)) & (~ do_read_stat)) & rdummyclk_opcode[0])) | (((((load_opcode & do_write_volatile) & (~ do_read_volatile)) & (~ do_wren)) & (~ do_read_stat
)) & wrvolatile_opcode[0])) | ((load_opcode & do_read_nonvolatile) & rnvdummyclk_opcode[0])) | ((load_opcode & ((do_write & (~ do_read_stat)) & (~ do_wren))) & write_opcode[0])) | (((load_opcode & do_read_stat) & (~ do_polling)) & rstat_opcode[0])) | (((load_opcode & do_read_stat) & do_polling) & rflagstat_opcode[0])) | ((((load_opcode & do_sec_erase) & (~ do_wren)) & (~ do_read_stat)) & serase_opcode[0])) | ((((load_opcode & do_die_erase) & (~ do_wren)) & (~ do_read_stat)) & derase_opcode[0])) | ((((load_opcode & do_bulk_erase) & (~ do_wren)) & (~ do_read_stat)) & berase_opcode[0])) | ((load_opcode & do_wren) & wren_opcode[0])) | ((load_opcode & ((do_4baddr & (~ do_read_stat)) & (~ do_wren))) & b4addr_opcode[0])) | ((load_opcode & ((do_ex4baddr & (~ do_read_stat)) & (~ do_wren))) & exb4addr_opcode[0]))};
	assign
		wire_asmi_opcode_reg_ena = {8{(load_opcode | shift_opcode)}};
	// synopsys translate_off
	initial
		buf_empty_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) buf_empty_reg <= 1'b0;
		else  buf_empty_reg <= wire_cmpr5_aeb;
	// synopsys translate_off
	initial
		bulk_erase_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) bulk_erase_reg <= 1'b0;
		else if  (wire_bulk_erase_reg_ena == 1'b1) 
			if (clr_write_wire == 1'b1) bulk_erase_reg <= 1'b0;
			else  bulk_erase_reg <= bulk_erase;
	assign
		wire_bulk_erase_reg_ena = (((~ busy_wire) & wren_wire) | clr_write_wire);
	// synopsys translate_off
	initial
		busy_det_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) busy_det_reg <= 1'b0;
		else  busy_det_reg <= (~ busy_wire);
	// synopsys translate_off
	initial
		clr_read_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_read_reg <= 1'b0;
		else  clr_read_reg <= ((do_read_sid | do_sec_prot) | (end_operation & (do_read | do_fast_read)));
	// synopsys translate_off
	initial
		clr_read_reg2 = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_read_reg2 <= 1'b0;
		else  clr_read_reg2 <= clr_read_reg;
	// synopsys translate_off
	initial
		clr_rstat_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_rstat_reg <= 1'b0;
		else  clr_rstat_reg <= end_operation;
	// synopsys translate_off
	initial
		clr_secprot_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_secprot_reg <= 1'b0;
		else  clr_secprot_reg <= (((wire_spstage_cntr_q[1] & wire_spstage_cntr_q[0]) & end_read_flag_status) | do_read_sid);
	// synopsys translate_off
	initial
		clr_secprot_reg1 = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_secprot_reg1 <= 1'b0;
		else  clr_secprot_reg1 <= clr_secprot_reg;
	// synopsys translate_off
	initial
		clr_sid_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_sid_reg <= 1'b0;
		else  clr_sid_reg <= end_ophdly;
	// synopsys translate_off
	initial
		clr_write_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_write_reg <= 1'b0;
		else  clr_write_reg <= (((((((((((((((do_write | do_sec_erase) | do_bulk_erase) | do_die_erase) | do_4baddr) | do_ex4baddr) & wire_wrstage_cntr_q[1]) & (~ wire_wrstage_cntr_q[0])) & end_operation) | write_prot_true) | (do_write & (~ pagewr_buf_not_empty[8]))) | (((((((~ do_write) & (~ do_sec_erase)) & (~ do_bulk_erase)) & (~ do_die_erase)) & (~ do_4baddr)) & (~ do_ex4baddr)) & end_operation)) | do_read_sid) | do_sec_prot) | do_read) | do_fast_read);
	// synopsys translate_off
	initial
		clr_write_reg2 = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) clr_write_reg2 <= 1'b0;
		else  clr_write_reg2 <= clr_write_reg;
	// synopsys translate_off
	initial
		cnt_bfend_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) cnt_bfend_reg <= 1'b0;
		else  cnt_bfend_reg <= cnt_bfend_wire_in;
	// synopsys translate_off
	initial
		do_wrmemadd_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) do_wrmemadd_reg <= 1'b0;
		else  do_wrmemadd_reg <= (wire_wrstage_cntr_q[1] & wire_wrstage_cntr_q[0]);
	// synopsys translate_off
	initial
		dvalid_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) dvalid_reg <= 1'b0;
		else if  (wire_dvalid_reg_ena == 1'b1) 
			if (wire_dvalid_reg_sclr == 1'b1) dvalid_reg <= 1'b0;
			else  dvalid_reg <= (end_read_byte & end_one_cyc_pos);
	assign
		wire_dvalid_reg_ena = (do_read | do_fast_read),
		wire_dvalid_reg_sclr = (end_op_wire | end_operation);
	// synopsys translate_off
	initial
		dvalid_reg2 = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) dvalid_reg2 <= 1'b0;
		else  dvalid_reg2 <= dvalid_reg;
	// synopsys translate_off
	initial
		end1_cyc_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) end1_cyc_reg <= 1'b0;
		else  end1_cyc_reg <= end1_cyc_reg_in_wire;
	// synopsys translate_off
	initial
		end1_cyc_reg2 = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) end1_cyc_reg2 <= 1'b0;
		else  end1_cyc_reg2 <= end_one_cycle;
	// synopsys translate_off
	initial
		end_op_hdlyreg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) end_op_hdlyreg <= 1'b0;
		else  end_op_hdlyreg <= end_operation;
	// synopsys translate_off
	initial
		end_op_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) end_op_reg <= 1'b0;
		else  end_op_reg <= end_op_wire;
	// synopsys translate_off
	initial
		end_pgwrop_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) end_pgwrop_reg <= 1'b0;
		else if  (wire_end_pgwrop_reg_ena == 1'b1) 
			if (clr_write_wire == 1'b1) end_pgwrop_reg <= 1'b0;
			else  end_pgwrop_reg <= buf_empty;
	assign
		wire_end_pgwrop_reg_ena = (((cnt_bfend_reg & do_write) & shift_pgwr_data) | clr_write_wire);
	// synopsys translate_off
	initial
		end_rbyte_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) end_rbyte_reg <= 1'b0;
		else if  (wire_end_rbyte_reg_ena == 1'b1) 
			if (wire_end_rbyte_reg_sclr == 1'b1) end_rbyte_reg <= 1'b0;
			else  end_rbyte_reg <= (((do_read | do_fast_read) & wire_stage_cntr_q[1]) & (~ wire_stage_cntr_q[0]));
	assign
		wire_end_rbyte_reg_ena = (((wire_gen_cntr_q[2] & (~ wire_gen_cntr_q[1])) & wire_gen_cntr_q[0]) | clr_endrbyte_wire),
		wire_end_rbyte_reg_sclr = (clr_endrbyte_wire | addr_overdie);
	// synopsys translate_off
	initial
		end_read_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) end_read_reg <= 1'b0;
		else  end_read_reg <= ((((~ rden_wire) & (do_read | do_fast_read)) & data_valid_wire) & end_read_byte);
	// synopsys translate_off
	initial
		epcs_id_reg2 = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) epcs_id_reg2 <= 8'b0;
		else if  (sid_load == 1'b1)   epcs_id_reg2 <= {read_dout_reg[7:0]};
	// synopsys translate_off
	initial
		ill_erase_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) ill_erase_reg <= 1'b0;
		else  ill_erase_reg <= illegal_erase_b4out_wire;
	// synopsys translate_off
	initial
		ill_write_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) ill_write_reg <= 1'b0;
		else  ill_write_reg <= illegal_write_b4out_wire;
	// synopsys translate_off
	initial
		illegal_write_prot_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) illegal_write_prot_reg <= 1'b0;
		else  illegal_write_prot_reg <= do_write;
	// synopsys translate_off
	initial
		max_cnt_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) max_cnt_reg <= 1'b0;
		else  max_cnt_reg <= wire_cmpr4_aeb;
	// synopsys translate_off
	initial
		maxcnt_shift_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) maxcnt_shift_reg <= 1'b0;
		else  maxcnt_shift_reg <= (((reach_max_cnt & shift_bytes_wire) & wren_wire) & (~ do_write));
	// synopsys translate_off
	initial
		maxcnt_shift_reg2 = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) maxcnt_shift_reg2 <= 1'b0;
		else  maxcnt_shift_reg2 <= maxcnt_shift_reg;
	// synopsys translate_off
	initial
		ncs_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) ncs_reg <= 1'b0;
		else if  (ncs_reg_ena_wire == 1'b1) 
			if (wire_ncs_reg_sclr == 1'b1) ncs_reg <= 1'b0;
			else  ncs_reg <= 1'b1;
	assign
		wire_ncs_reg_sclr = (end_operation | addr_overdie_pos);
	// synopsys translate_off
	initial
		pgwrbuf_dataout[0:0] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[0:0] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[0:0] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[0:0] <= 1'b0;
			else  pgwrbuf_dataout[0:0] <= wire_pgwrbuf_dataout_d[0:0];
	// synopsys translate_off
	initial
		pgwrbuf_dataout[1:1] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[1:1] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[1:1] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[1:1] <= 1'b0;
			else  pgwrbuf_dataout[1:1] <= wire_pgwrbuf_dataout_d[1:1];
	// synopsys translate_off
	initial
		pgwrbuf_dataout[2:2] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[2:2] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[2:2] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[2:2] <= 1'b0;
			else  pgwrbuf_dataout[2:2] <= wire_pgwrbuf_dataout_d[2:2];
	// synopsys translate_off
	initial
		pgwrbuf_dataout[3:3] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[3:3] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[3:3] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[3:3] <= 1'b0;
			else  pgwrbuf_dataout[3:3] <= wire_pgwrbuf_dataout_d[3:3];
	// synopsys translate_off
	initial
		pgwrbuf_dataout[4:4] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[4:4] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[4:4] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[4:4] <= 1'b0;
			else  pgwrbuf_dataout[4:4] <= wire_pgwrbuf_dataout_d[4:4];
	// synopsys translate_off
	initial
		pgwrbuf_dataout[5:5] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[5:5] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[5:5] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[5:5] <= 1'b0;
			else  pgwrbuf_dataout[5:5] <= wire_pgwrbuf_dataout_d[5:5];
	// synopsys translate_off
	initial
		pgwrbuf_dataout[6:6] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[6:6] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[6:6] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[6:6] <= 1'b0;
			else  pgwrbuf_dataout[6:6] <= wire_pgwrbuf_dataout_d[6:6];
	// synopsys translate_off
	initial
		pgwrbuf_dataout[7:7] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) pgwrbuf_dataout[7:7] <= 1'b0;
		else if  (wire_pgwrbuf_dataout_ena[7:7] == 1'b1) 
			if (clr_write_wire == 1'b1) pgwrbuf_dataout[7:7] <= 1'b0;
			else  pgwrbuf_dataout[7:7] <= wire_pgwrbuf_dataout_d[7:7];
	assign
		wire_pgwrbuf_dataout_d = {(({7{read_bufdly}} & wire_scfifo3_q[7:1]) | ({7{(~ read_bufdly)}} & pgwrbuf_dataout[6:0])), (read_bufdly & wire_scfifo3_q[0])};
	assign
		wire_pgwrbuf_dataout_ena = {8{((read_bufdly | shift_pgwr_data) | clr_write_wire)}};
	// synopsys translate_off
	initial
		read_bufdly_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_bufdly_reg <= 1'b0;
		else  read_bufdly_reg <= read_buf;
	// synopsys translate_off
	initial
		read_data_reg[0:0] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[0:0] <= 1'b0;
		else if  (wire_read_data_reg_ena[0:0] == 1'b1)   read_data_reg[0:0] <= wire_read_data_reg_d[0:0];
	// synopsys translate_off
	initial
		read_data_reg[1:1] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[1:1] <= 1'b0;
		else if  (wire_read_data_reg_ena[1:1] == 1'b1)   read_data_reg[1:1] <= wire_read_data_reg_d[1:1];
	// synopsys translate_off
	initial
		read_data_reg[2:2] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[2:2] <= 1'b0;
		else if  (wire_read_data_reg_ena[2:2] == 1'b1)   read_data_reg[2:2] <= wire_read_data_reg_d[2:2];
	// synopsys translate_off
	initial
		read_data_reg[3:3] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[3:3] <= 1'b0;
		else if  (wire_read_data_reg_ena[3:3] == 1'b1)   read_data_reg[3:3] <= wire_read_data_reg_d[3:3];
	// synopsys translate_off
	initial
		read_data_reg[4:4] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[4:4] <= 1'b0;
		else if  (wire_read_data_reg_ena[4:4] == 1'b1)   read_data_reg[4:4] <= wire_read_data_reg_d[4:4];
	// synopsys translate_off
	initial
		read_data_reg[5:5] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[5:5] <= 1'b0;
		else if  (wire_read_data_reg_ena[5:5] == 1'b1)   read_data_reg[5:5] <= wire_read_data_reg_d[5:5];
	// synopsys translate_off
	initial
		read_data_reg[6:6] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[6:6] <= 1'b0;
		else if  (wire_read_data_reg_ena[6:6] == 1'b1)   read_data_reg[6:6] <= wire_read_data_reg_d[6:6];
	// synopsys translate_off
	initial
		read_data_reg[7:7] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_data_reg[7:7] <= 1'b0;
		else if  (wire_read_data_reg_ena[7:7] == 1'b1)   read_data_reg[7:7] <= wire_read_data_reg_d[7:7];
	assign
		wire_read_data_reg_d = {read_data_reg_in_wire[7:0]};
	assign
		wire_read_data_reg_ena = {8{(((((do_read | do_fast_read) & wire_stage_cntr_q[1]) & (~ wire_stage_cntr_q[0])) & end_one_cyc_pos) & end_read_byte)}};
	// synopsys translate_off
	initial
		read_dout_reg[0:0] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[0:0] <= 1'b0;
		else if  (wire_read_dout_reg_ena[0:0] == 1'b1)   read_dout_reg[0:0] <= wire_read_dout_reg_d[0:0];
	// synopsys translate_off
	initial
		read_dout_reg[1:1] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[1:1] <= 1'b0;
		else if  (wire_read_dout_reg_ena[1:1] == 1'b1)   read_dout_reg[1:1] <= wire_read_dout_reg_d[1:1];
	// synopsys translate_off
	initial
		read_dout_reg[2:2] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[2:2] <= 1'b0;
		else if  (wire_read_dout_reg_ena[2:2] == 1'b1)   read_dout_reg[2:2] <= wire_read_dout_reg_d[2:2];
	// synopsys translate_off
	initial
		read_dout_reg[3:3] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[3:3] <= 1'b0;
		else if  (wire_read_dout_reg_ena[3:3] == 1'b1)   read_dout_reg[3:3] <= wire_read_dout_reg_d[3:3];
	// synopsys translate_off
	initial
		read_dout_reg[4:4] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[4:4] <= 1'b0;
		else if  (wire_read_dout_reg_ena[4:4] == 1'b1)   read_dout_reg[4:4] <= wire_read_dout_reg_d[4:4];
	// synopsys translate_off
	initial
		read_dout_reg[5:5] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[5:5] <= 1'b0;
		else if  (wire_read_dout_reg_ena[5:5] == 1'b1)   read_dout_reg[5:5] <= wire_read_dout_reg_d[5:5];
	// synopsys translate_off
	initial
		read_dout_reg[6:6] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[6:6] <= 1'b0;
		else if  (wire_read_dout_reg_ena[6:6] == 1'b1)   read_dout_reg[6:6] <= wire_read_dout_reg_d[6:6];
	// synopsys translate_off
	initial
		read_dout_reg[7:7] = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_dout_reg[7:7] <= 1'b0;
		else if  (wire_read_dout_reg_ena[7:7] == 1'b1)   read_dout_reg[7:7] <= wire_read_dout_reg_d[7:7];
	assign
		wire_read_dout_reg_d = {read_dout_reg[6:0], (data0out_wire | dataout_wire[1])};
	assign
		wire_read_dout_reg_ena = {8{((stage4_wire & ((do_read | do_fast_read) | do_read_sid)) | (stage3_wire & (((do_read_stat | do_read_rdid) | do_read_volatile) | do_read_nonvolatile)))}};
	// synopsys translate_off
	initial
		read_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_reg <= 1'b0;
		else if  (wire_read_reg_ena == 1'b1) 
			if (clr_read_wire == 1'b1) read_reg <= 1'b0;
			else  read_reg <= read;
	assign
		wire_read_reg_ena = (((~ busy_wire) & rden_wire) | clr_read_wire);
	// synopsys translate_off
	initial
		read_sid_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) read_sid_reg <= 1'b0;
		else if  (wire_read_sid_reg_ena == 1'b1) 
			if (clr_sid_wire == 1'b1) read_sid_reg <= 1'b0;
			else  read_sid_reg <= read_sid;
	assign
		wire_read_sid_reg_ena = ((~ busy_wire) | clr_sid_wire);
	// synopsys translate_off
	initial
		sec_erase_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) sec_erase_reg <= 1'b0;
		else if  (wire_sec_erase_reg_ena == 1'b1) 
			if (clr_write_wire == 1'b1) sec_erase_reg <= 1'b0;
			else  sec_erase_reg <= sector_erase;
	assign
		wire_sec_erase_reg_ena = (((~ busy_wire) & wren_wire) | clr_write_wire);
	// synopsys translate_off
	initial
		sec_prot_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) sec_prot_reg <= 1'b0;
		else if  (wire_sec_prot_reg_ena == 1'b1) 
			if (clr_secprot_wire == 1'b1) sec_prot_reg <= 1'b0;
			else  sec_prot_reg <= sector_protect;
	assign
		wire_sec_prot_reg_ena = (((~ busy_wire) & wren_wire) | clr_secprot_wire);
	// synopsys translate_off
	initial
		shftpgwr_data_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) shftpgwr_data_reg <= 1'b0;
		else
			if (end_operation == 1'b1) shftpgwr_data_reg <= 1'b0;
			else  shftpgwr_data_reg <= (((wire_stage_cntr_q[1] & (~ wire_stage_cntr_q[0])) & wire_wrstage_cntr_q[1]) & wire_wrstage_cntr_q[0]);
	// synopsys translate_off
	initial
		shift_op_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) shift_op_reg <= 1'b0;
		else  shift_op_reg <= ((~ wire_stage_cntr_q[1]) & wire_stage_cntr_q[0]);
	// synopsys translate_off
	initial
		sprot_rstat_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) sprot_rstat_reg <= 1'b0;
		else
			if (clr_secprot_wire == 1'b1) sprot_rstat_reg <= 1'b0;
			else  sprot_rstat_reg <= ((do_sec_prot & wire_spstage_cntr_q[1]) & wire_spstage_cntr_q[0]);
	// synopsys translate_off
	initial
		stage2_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) stage2_reg <= 1'b0;
		else  stage2_reg <= ((~ wire_stage_cntr_q[1]) & wire_stage_cntr_q[0]);
	// synopsys translate_off
	initial
		stage3_dly_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) stage3_dly_reg <= 1'b0;
		else  stage3_dly_reg <= (wire_stage_cntr_q[1] & wire_stage_cntr_q[0]);
	// synopsys translate_off
	initial
		stage3_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) stage3_reg <= 1'b0;
		else  stage3_reg <= (wire_stage_cntr_q[1] & wire_stage_cntr_q[0]);
	// synopsys translate_off
	initial
		stage4_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) stage4_reg <= 1'b0;
		else  stage4_reg <= (wire_stage_cntr_q[1] & (~ wire_stage_cntr_q[0]));
	// synopsys translate_off
	initial
		start_sppoll_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) start_sppoll_reg <= 1'b0;
		else if  (wire_start_sppoll_reg_ena == 1'b1) 
			if (clr_secprot_wire == 1'b1) start_sppoll_reg <= 1'b0;
			else  start_sppoll_reg <= (wire_stage_cntr_q[1] & wire_stage_cntr_q[0]);
	assign
		wire_start_sppoll_reg_ena = (((do_sprot_rstat & do_polling) & end_one_cycle) | clr_secprot_wire);
	// synopsys translate_off
	initial
		start_sppoll_reg2 = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) start_sppoll_reg2 <= 1'b0;
		else
			if (clr_secprot_wire == 1'b1) start_sppoll_reg2 <= 1'b0;
			else  start_sppoll_reg2 <= start_sppoll_reg;
	// synopsys translate_off
	initial
		start_wrpoll_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) start_wrpoll_reg <= 1'b0;
		else if  (wire_start_wrpoll_reg_ena == 1'b1) 
			if (clr_write_wire == 1'b1) start_wrpoll_reg <= 1'b0;
			else  start_wrpoll_reg <= (wire_stage_cntr_q[1] & wire_stage_cntr_q[0]);
	assign
		wire_start_wrpoll_reg_ena = (((do_write_rstat & do_polling) & end_one_cycle) | clr_write_wire);
	// synopsys translate_off
	initial
		start_wrpoll_reg2 = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) start_wrpoll_reg2 <= 1'b0;
		else
			if (clr_write_wire == 1'b1) start_wrpoll_reg2 <= 1'b0;
			else  start_wrpoll_reg2 <= start_wrpoll_reg;
	// synopsys translate_off
	initial
		statreg_int[0:0] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[0:0] <= 1'b0;
		else if  (wire_statreg_int_ena[0:0] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[0:0] <= 1'b0;
			else  statreg_int[0:0] <= wire_statreg_int_d[0:0];
	// synopsys translate_off
	initial
		statreg_int[1:1] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[1:1] <= 1'b0;
		else if  (wire_statreg_int_ena[1:1] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[1:1] <= 1'b0;
			else  statreg_int[1:1] <= wire_statreg_int_d[1:1];
	// synopsys translate_off
	initial
		statreg_int[2:2] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[2:2] <= 1'b0;
		else if  (wire_statreg_int_ena[2:2] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[2:2] <= 1'b0;
			else  statreg_int[2:2] <= wire_statreg_int_d[2:2];
	// synopsys translate_off
	initial
		statreg_int[3:3] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[3:3] <= 1'b0;
		else if  (wire_statreg_int_ena[3:3] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[3:3] <= 1'b0;
			else  statreg_int[3:3] <= wire_statreg_int_d[3:3];
	// synopsys translate_off
	initial
		statreg_int[4:4] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[4:4] <= 1'b0;
		else if  (wire_statreg_int_ena[4:4] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[4:4] <= 1'b0;
			else  statreg_int[4:4] <= wire_statreg_int_d[4:4];
	// synopsys translate_off
	initial
		statreg_int[5:5] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[5:5] <= 1'b0;
		else if  (wire_statreg_int_ena[5:5] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[5:5] <= 1'b0;
			else  statreg_int[5:5] <= wire_statreg_int_d[5:5];
	// synopsys translate_off
	initial
		statreg_int[6:6] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[6:6] <= 1'b0;
		else if  (wire_statreg_int_ena[6:6] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[6:6] <= 1'b0;
			else  statreg_int[6:6] <= wire_statreg_int_d[6:6];
	// synopsys translate_off
	initial
		statreg_int[7:7] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) statreg_int[7:7] <= 1'b0;
		else if  (wire_statreg_int_ena[7:7] == 1'b1) 
			if (clr_rstat_wire == 1'b1) statreg_int[7:7] <= 1'b0;
			else  statreg_int[7:7] <= wire_statreg_int_d[7:7];
	assign
		wire_statreg_int_d = {read_dout_reg[7:0]};
	assign
		wire_statreg_int_ena = {8{(((end_operation | ((do_polling & end_one_cyc_pos) & stage3_dly_reg)) & do_read_stat) | clr_rstat_wire)}};
	// synopsys translate_off
	initial
		streg_datain_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) streg_datain_reg <= 1'b0;
		else if  (wire_streg_datain_reg_ena == 1'b1) 
			if (end_operation == 1'b1) streg_datain_reg <= 1'b0;
			else  streg_datain_reg <= wrstat_dreg[7];
	assign
		wire_streg_datain_reg_ena = (((do_sec_prot & (~ wire_spstage_cntr_q[1])) & wire_spstage_cntr_q[0]) | end_operation);
	// synopsys translate_off
	initial
		write_prot_reg = 0;
	// synopsys translate_on
	always @ ( negedge clkin_wire or  posedge reset)
		if (reset == 1'b1) write_prot_reg <= 1'b0;
		else if  (wire_write_prot_reg_ena == 1'b1) 
			if (clr_write_wire == 1'b1) write_prot_reg <= 1'b0;
			else  write_prot_reg <= ((((do_write | do_sec_erase) & (~ mask_prot_comp_ntb[4])) & (~ prot_wire[0])) | be_write_prot);
	assign
		wire_write_prot_reg_ena = (((((((do_sec_erase | do_write) | do_bulk_erase) | do_die_erase) & (~ wire_wrstage_cntr_q[1])) & wire_wrstage_cntr_q[0]) & end_ophdly) | clr_write_wire);
	// synopsys translate_off
	initial
		write_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) write_reg <= 1'b0;
		else if  (wire_write_reg_ena == 1'b1) 
			if (clr_write_wire == 1'b1) write_reg <= 1'b0;
			else  write_reg <= write;
	assign
		wire_write_reg_ena = (((~ busy_wire) & wren_wire) | clr_write_wire);
	// synopsys translate_off
	initial
		write_rstat_reg = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) write_rstat_reg <= 1'b0;
		else
			if (clr_write_wire == 1'b1) write_rstat_reg <= 1'b0;
			else  write_rstat_reg <= ((((((do_write | do_sec_erase) | do_bulk_erase) | do_die_erase) | do_4baddr) | do_ex4baddr) & (((~ wire_wrstage_cntr_q[1]) & (~ wire_wrstage_cntr_q[0])) | (wire_wrstage_cntr_q[1] & (~ wire_wrstage_cntr_q[0]))));
	// synopsys translate_off
	initial
		wrstat_dreg[0:0] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[0:0] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[0:0] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[0:0] <= 1'b0;
			else  wrstat_dreg[0:0] <= wire_wrstat_dreg_d[0:0];
	// synopsys translate_off
	initial
		wrstat_dreg[1:1] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[1:1] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[1:1] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[1:1] <= 1'b0;
			else  wrstat_dreg[1:1] <= wire_wrstat_dreg_d[1:1];
	// synopsys translate_off
	initial
		wrstat_dreg[2:2] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[2:2] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[2:2] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[2:2] <= 1'b0;
			else  wrstat_dreg[2:2] <= wire_wrstat_dreg_d[2:2];
	// synopsys translate_off
	initial
		wrstat_dreg[3:3] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[3:3] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[3:3] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[3:3] <= 1'b0;
			else  wrstat_dreg[3:3] <= wire_wrstat_dreg_d[3:3];
	// synopsys translate_off
	initial
		wrstat_dreg[4:4] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[4:4] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[4:4] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[4:4] <= 1'b0;
			else  wrstat_dreg[4:4] <= wire_wrstat_dreg_d[4:4];
	// synopsys translate_off
	initial
		wrstat_dreg[5:5] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[5:5] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[5:5] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[5:5] <= 1'b0;
			else  wrstat_dreg[5:5] <= wire_wrstat_dreg_d[5:5];
	// synopsys translate_off
	initial
		wrstat_dreg[6:6] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[6:6] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[6:6] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[6:6] <= 1'b0;
			else  wrstat_dreg[6:6] <= wire_wrstat_dreg_d[6:6];
	// synopsys translate_off
	initial
		wrstat_dreg[7:7] = 0;
	// synopsys translate_on
	always @ ( posedge clkin_wire or  posedge reset)
		if (reset == 1'b1) wrstat_dreg[7:7] <= 1'b0;
		else if  (wire_wrstat_dreg_ena[7:7] == 1'b1) 
			if (clr_secprot_wire == 1'b1) wrstat_dreg[7:7] <= 1'b0;
			else  wrstat_dreg[7:7] <= wire_wrstat_dreg_d[7:7];
	assign
		wire_wrstat_dreg_d = {(({7{not_busy}} & datain[7:1]) | ({7{stage3_wire}} & wrstat_dreg[6:0])), (not_busy & datain[0])};
	assign
		wire_wrstat_dreg_ena = {8{(((wren_wire & not_busy) | (((do_sec_prot & stage3_wire) & (~ wire_spstage_cntr_q[1])) & wire_spstage_cntr_q[0])) | clr_secprot_wire)}};
	lpm_compare   cmpr4
	( 
	.aeb(wire_cmpr4_aeb),
	.agb(),
	.ageb(),
	.alb(),
	.aleb(),
	.aneb(),
	.dataa({page_size_wire[8:0]}),
	.datab({wire_pgwr_data_cntr_q[8:0]})
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.aclr(1'b0),
	.clken(1'b1),
	.clock(1'b0)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		cmpr4.lpm_width = 9,
		cmpr4.lpm_type = "lpm_compare";
	lpm_compare   cmpr5
	( 
	.aeb(wire_cmpr5_aeb),
	.agb(),
	.ageb(),
	.alb(),
	.aleb(),
	.aneb(),
	.dataa({wire_pgwr_data_cntr_q[8:0]}),
	.datab({wire_pgwr_read_cntr_q[8:0]})
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.aclr(1'b0),
	.clken(1'b1),
	.clock(1'b0)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		cmpr5.lpm_width = 9,
		cmpr5.lpm_type = "lpm_compare";
	lpm_counter   pgwr_data_cntr
	( 
	.aclr(reset),
	.clk_en(((((shift_bytes_wire & wren_wire) & (~ reach_max_cnt)) & (~ do_write)) | clr_write_wire2)),
	.clock(clkin_wire),
	.cout(),
	.eq(),
	.q(wire_pgwr_data_cntr_q),
	.sclr(clr_write_wire2)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.aload(1'b0),
	.aset(1'b0),
	.cin(1'b1),
	.cnt_en(1'b1),
	.data({9{1'b0}}),
	.sload(1'b0),
	.sset(1'b0),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		pgwr_data_cntr.lpm_direction = "UP",
		pgwr_data_cntr.lpm_port_updown = "PORT_UNUSED",
		pgwr_data_cntr.lpm_width = 9,
		pgwr_data_cntr.lpm_type = "lpm_counter";
	lpm_counter   pgwr_read_cntr
	( 
	.aclr(reset),
	.clk_en((read_buf | clr_write_wire2)),
	.clock(clkin_wire),
	.cout(),
	.eq(),
	.q(wire_pgwr_read_cntr_q),
	.sclr(clr_write_wire2)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_off
	`endif
	,
	.aload(1'b0),
	.aset(1'b0),
	.cin(1'b1),
	.cnt_en(1'b1),
	.data({9{1'b0}}),
	.sload(1'b0),
	.sset(1'b0),
	.updown(1'b1)
	`ifndef FORMAL_VERIFICATION
	// synopsys translate_on
	`endif
	);
	defparam
		pgwr_read_cntr.lpm_direction = "UP",
		pgwr_read_cntr.lpm_port_updown = "PORT_UNUSED",
		pgwr_read_cntr.lpm_width = 9,
		pgwr_read_cntr.lpm_type = "lpm_counter";
	assign		wire_mux211_dataout = (do_fast_read === 1'b1) ? end_add_cycle_mux_datab_wire : (wire_addbyte_cntr_q[1] & (~ wire_addbyte_cntr_q[0]));
	scfifo   scfifo3
	( 
	.aclr(reset),
	.almost_empty(),
	.almost_full(),
	.clock(clkin_wire),
	.data({datain[7:0]}),
	.eccstatus(),
	.empty(),
	.full(),
	.q(wire_scfifo3_q),
	.rdreq((read_buf | dummy_read_buf)),
	.sclr(clr_write_wire2),
	.usedw(),
	.wrreq(((shift_bytes_wire & wren_wire) & (~ do_write))));
	defparam
		scfifo3.lpm_numwords = 258,
		scfifo3.lpm_width = 8,
		scfifo3.lpm_widthu = 9,
		scfifo3.use_eab = "ON",
		scfifo3.lpm_type = "scfifo";
	assign
		addr_overdie = 1'b0,
		addr_overdie_pos = 1'b0,
		addr_reg_overdie = {24{1'b0}},
		b4addr_opcode = {8{1'b0}},
		be_write_prot = ((do_bulk_erase | do_die_erase) & (((bp3_wire | bp2_wire) | bp1_wire) | bp0_wire)),
		berase_opcode = 8'b11000111,
		bp0_wire = statreg_int[2],
		bp1_wire = statreg_int[3],
		bp2_wire = statreg_int[4],
		bp3_wire = statreg_int[6],
		buf_empty = buf_empty_reg,
		bulk_erase_wire = bulk_erase_reg,
		busy = busy_wire,
		busy_wire = ((((((((((((((do_read_rdid | do_read_sid) | do_read) | do_fast_read) | do_write) | do_sec_prot) | do_read_stat) | do_sec_erase) | do_bulk_erase) | do_die_erase) | do_4baddr) | do_read_volatile) | do_fread_epcq) | do_read_nonvolatile) | do_ex4baddr),
		clkin_wire = clkin,
		clr_addmsb_wire = (((((wire_stage_cntr_q[1] & (~ wire_stage_cntr_q[0])) & end_add_cycle) & end_one_cyc_pos) | (((~ do_read) & (~ do_fast_read)) & clr_write_wire2)) | ((((do_sec_erase | do_die_erase) & (~ do_wren)) & (~ do_read_stat)) & end_operation)),
		clr_endrbyte_wire = (((((do_read | do_fast_read) & (~ wire_gen_cntr_q[2])) & wire_gen_cntr_q[1]) & wire_gen_cntr_q[0]) | clr_read_wire2),
		clr_read_wire = clr_read_reg,
		clr_read_wire2 = clr_read_reg2,
		clr_rstat_wire = clr_rstat_reg,
		clr_secprot_wire = clr_secprot_reg,
		clr_secprot_wire1 = clr_secprot_reg1,
		clr_sid_wire = clr_sid_reg,
		clr_write_wire = clr_write_reg,
		clr_write_wire2 = clr_write_reg2,
		cnt_bfend_wire_in = ((wire_gen_cntr_q[2] & (~ wire_gen_cntr_q[1])) & wire_gen_cntr_q[0]),
		data0out_wire = wire_sd2_data0out,
		data_valid = data_valid_wire,
		data_valid_wire = dvalid_reg2,
		datain_wire = {{4{1'b0}}},
		dataout = {read_data_reg[7:0]},
		dataout_wire = {{4{1'b0}}},
		derase_opcode = {8{1'b0}},
		do_4baddr = 1'b0,
		do_bulk_erase = (((((((((~ do_read_nonvolatile) & (~ read_rdid_wire)) & (~ read_sid_wire)) & (~ sec_protect_wire)) & (~ (read_wire | fast_read_wire))) & (~ write_wire)) & (~ read_status_wire)) & (~ sec_erase_wire)) & bulk_erase_wire),
		do_die_erase = 1'b0,
		do_ex4baddr = 1'b0,
		do_fast_read = 1'b0,
		do_fread_epcq = 1'b0,
		do_freadwrv_polling = 1'b0,
		do_memadd = do_wrmemadd_reg,
		do_polling = ((do_write_polling | do_sprot_polling) | do_freadwrv_polling),
		do_read = ((((~ read_rdid_wire) & (~ read_sid_wire)) & (~ sec_protect_wire)) & read_wire),
		do_read_nonvolatile = 1'b0,
		do_read_rdid = 1'b0,
		do_read_sid = (((~ do_read_nonvolatile) & (~ read_rdid_wire)) & read_sid_wire),
		do_read_stat = ((((((((((~ do_read_nonvolatile) & (~ read_rdid_wire)) & (~ read_sid_wire)) & (~ sec_protect_wire)) & (~ (read_wire | fast_read_wire))) & (~ write_wire)) & read_status_wire) | do_write_rstat) | do_sprot_rstat) | do_write_volatile_rstat),
		do_read_volatile = 1'b0,
		do_sec_erase = ((((((((~ do_read_nonvolatile) & (~ read_rdid_wire)) & (~ read_sid_wire)) & (~ sec_protect_wire)) & (~ (read_wire | fast_read_wire))) & (~ write_wire)) & (~ read_status_wire)) & sec_erase_wire),
		do_sec_prot = ((((~ do_read_nonvolatile) & (~ read_rdid_wire)) & (~ read_sid_wire)) & sec_protect_wire),
		do_secprot_wren = ((do_sec_prot & (~ wire_spstage_cntr_q[1])) & (~ wire_spstage_cntr_q[0])),
		do_sprot_polling = ((do_sec_prot & wire_spstage_cntr_q[1]) & wire_spstage_cntr_q[0]),
		do_sprot_rstat = sprot_rstat_reg,
		do_wait_dummyclk = 1'b0,
		do_wren = ((do_write_wren | do_secprot_wren) | do_write_volatile_wren),
		do_write = ((((((~ do_read_nonvolatile) & (~ read_rdid_wire)) & (~ read_sid_wire)) & (~ sec_protect_wire)) & (~ (read_wire | fast_read_wire))) & write_wire),
		do_write_polling = (((((((do_write | do_sec_erase) | do_bulk_erase) | do_die_erase) | do_4baddr) | do_ex4baddr) & wire_wrstage_cntr_q[1]) & (~ wire_wrstage_cntr_q[0])),
		do_write_rstat = write_rstat_reg,
		do_write_volatile = 1'b0,
		do_write_volatile_rstat = 1'b0,
		do_write_volatile_wren = 1'b0,
		do_write_wren = ((~ wire_wrstage_cntr_q[1]) & wire_wrstage_cntr_q[0]),
		dummy_read_buf = maxcnt_shift_reg2,
		end1_cyc_gen_cntr_wire = ((wire_gen_cntr_q[2] & (~ wire_gen_cntr_q[1])) & (~ wire_gen_cntr_q[0])),
		end1_cyc_normal_in_wire = ((((((((((((~ wire_stage_cntr_q[0]) & (~ wire_stage_cntr_q[1])) & (~ wire_gen_cntr_q[2])) & wire_gen_cntr_q[1]) & wire_gen_cntr_q[0]) | ((~ ((~ wire_stage_cntr_q[0]) & (~ wire_stage_cntr_q[1]))) & end1_cyc_gen_cntr_wire)) | (do_read & end_read)) | (do_fast_read & end_fast_read)) | ((((do_write | do_sec_erase) | do_bulk_erase) | do_die_erase) & write_prot_true)) | (do_write & (~ pagewr_buf_not_empty[8]))) | ((do_read_stat & start_poll) & (~ st_busy_wire))) | (do_read_rdid & end_op_wire)),
		end1_cyc_reg_in_wire = end1_cyc_normal_in_wire,
		end_add_cycle = wire_mux211_dataout,
		end_add_cycle_mux_datab_wire = (wire_addbyte_cntr_q[2] & wire_addbyte_cntr_q[1]),
		end_fast_read = end_read_reg,
		end_one_cyc_pos = end1_cyc_reg2,
		end_one_cycle = end1_cyc_reg,
		end_op_wire = ((((((((((((wire_stage_cntr_q[1] & (~ wire_stage_cntr_q[0])) & ((((((~ do_read) & (~ do_fast_read)) & (~ (do_write & shift_pgwr_data))) & end_one_cycle) | (do_read & end_read)) | (do_fast_read & end_fast_read))) | ((((wire_stage_cntr_q[1] & wire_stage_cntr_q[0]) & do_read_stat) & end_one_cycle) & (~ do_polling))) | ((((((do_read_rdid & end_one_cyc_pos) & wire_stage_cntr_q[1]) & wire_stage_cntr_q[0]) & wire_addbyte_cntr_q[2]) & wire_addbyte_cntr_q[1]) & (~ wire_addbyte_cntr_q[0]))) | (((start_poll & do_read_stat) & do_polling) & (~ st_busy_wire))) | ((((~ wire_stage_cntr_q[1]) & wire_stage_cntr_q[0]) & (do_wren | (do_4baddr | (do_ex4baddr | (do_bulk_erase & (~ do_read_stat)))))) & end_one_cycle)) | ((((do_write | do_sec_erase) | do_bulk_erase) | do_die_erase) & write_prot_true)) | ((do_write & shift_pgwr_data) & end_pgwr_data)) | (do_write & (~ pagewr_buf_not_empty[8]))) | (((((wire_stage_cntr_q[1] & wire_stage_cntr_q[0]) & do_sec_prot) & (~ do_wren)) & (~ do_read_stat)) & end_one_cycle)) | ((((((wire_stage_cntr_q[1] & wire_stage_cntr_q[0]) & (do_sec_erase | do_die_erase)) & (~ do_wren)) & (~ do_read_stat)) & end_add_cycle) & end_one_cycle)) | (((wire_stage_cntr_q[1] & wire_stage_cntr_q[0]) & end_one_cycle) & ((do_write_volatile | do_read_volatile) | (do_read_nonvolatile & wire_addbyte_cntr_q[1])))),
		end_operation = end_op_reg,
		end_ophdly = end_op_hdlyreg,
		end_pgwr_data = end_pgwrop_reg,
		end_read = end_read_reg,
		end_read_byte = (end_rbyte_reg & (~ addr_overdie)),
		end_read_flag_status = wire_read_flag_status_cntr_q[0],
		end_wrstage = end_operation,
		epcs_id = {epcs_id_reg2[7:0]},
		exb4addr_opcode = {8{1'b0}},
		fast_read_opcode = {8{1'b0}},
		fast_read_wire = 1'b0,
		freadwrv_sdoin = 1'b0,
		ill_erase_wire = ill_erase_reg,
		ill_write_wire = ill_write_reg,
		illegal_erase = ill_erase_wire,
		illegal_erase_b4out_wire = (((do_sec_erase | do_bulk_erase) | do_die_erase) & write_prot_true),
		illegal_write = ill_write_wire,
		illegal_write_b4out_wire = ((do_write & write_prot_true) | (do_write & (~ pagewr_buf_not_empty[8]))),
		in_operation = busy_wire,
		load_opcode = (((((~ wire_stage_cntr_q[1]) & (~ wire_stage_cntr_q[0])) & (~ wire_gen_cntr_q[2])) & (~ wire_gen_cntr_q[1])) & wire_gen_cntr_q[0]),
		mask_prot = {((((prot_wire[1] | prot_wire[2]) | prot_wire[3]) | prot_wire[4]) | prot_wire[5]), (((prot_wire[1] | prot_wire[2]) | prot_wire[3]) | prot_wire[4]), ((prot_wire[1] | prot_wire[2]) | prot_wire[3]), (prot_wire[1] | prot_wire[2]), prot_wire[1]},
		mask_prot_add = {(mask_prot[4] & addr_reg[20]), (mask_prot[3] & addr_reg[19]), (mask_prot[2] & addr_reg[18]), (mask_prot[1] & addr_reg[17]), (mask_prot[0] & addr_reg[16])},
		mask_prot_check = {(mask_prot[4] ^ mask_prot_add[4]), (mask_prot[3] ^ mask_prot_add[3]), (mask_prot[2] ^ mask_prot_add[2]), (mask_prot[1] ^ mask_prot_add[1]), (mask_prot[0] ^ mask_prot_add[0])},
		mask_prot_comp_ntb = {(mask_prot_check[4] | mask_prot_comp_ntb[3]), (mask_prot_check[3] | mask_prot_comp_ntb[2]), (mask_prot_check[2] | mask_prot_comp_ntb[1]), (mask_prot_check[1] | mask_prot_comp_ntb[0]), mask_prot_check[0]},
		mask_prot_comp_tb = {(mask_prot_add[4] | mask_prot_comp_tb[3]), (mask_prot_add[3] | mask_prot_comp_tb[2]), (mask_prot_add[2] | mask_prot_comp_tb[1]), (mask_prot_add[1] | mask_prot_comp_tb[0]), mask_prot_add[0]},
		memadd_sdoin = add_msb_reg,
		ncs_reg_ena_wire = (((((~ wire_stage_cntr_q[1]) & wire_stage_cntr_q[0]) & end_one_cyc_pos) | addr_overdie_pos) | end_operation),
		not_busy = busy_det_reg,
		oe_wire = 1'b0,
		page_size_wire = 9'b100000000,
		pagewr_buf_not_empty = {(pagewr_buf_not_empty[7] | wire_pgwr_data_cntr_q[8]), (pagewr_buf_not_empty[6] | wire_pgwr_data_cntr_q[7]), (pagewr_buf_not_empty[5] | wire_pgwr_data_cntr_q[6]), (pagewr_buf_not_empty[4] | wire_pgwr_data_cntr_q[5]), (pagewr_buf_not_empty[3] | wire_pgwr_data_cntr_q[4]), (pagewr_buf_not_empty[2] | wire_pgwr_data_cntr_q[3]), (pagewr_buf_not_empty[1] | wire_pgwr_data_cntr_q[2]), (pagewr_buf_not_empty[0] | wire_pgwr_data_cntr_q[1]), wire_pgwr_data_cntr_q[0]},
		prot_wire = {((bp2_wire & bp1_wire) & bp0_wire), ((bp2_wire & bp1_wire) & (~ bp0_wire)), ((bp2_wire & (~ bp1_wire)) & bp0_wire), ((bp2_wire & (~ bp1_wire)) & (~ bp0_wire)), (((~ bp2_wire) & bp1_wire) & bp0_wire), (((~ bp2_wire) & bp1_wire) & (~ bp0_wire)), (((~ bp2_wire) & (~ bp1_wire)) & bp0_wire), (((~ bp2_wire) & (~ bp1_wire)) & (~ bp0_wire))},
		rden_wire = rden,
		rdid_opcode = {8{1'b0}},
		rdummyclk_opcode = {8{1'b0}},
		reach_max_cnt = max_cnt_reg,
		read_buf = (((((end_one_cycle & do_write) & (~ do_read_stat)) & (~ do_wren)) & ((wire_stage_cntr_q[1] & (~ wire_stage_cntr_q[0])) | (wire_addbyte_cntr_q[1] & (~ wire_addbyte_cntr_q[0])))) & (~ buf_empty)),
		read_bufdly = read_bufdly_reg,
		read_data_reg_in_wire = {read_dout_reg[7:0]},
		read_opcode = 8'b00000011,
		read_rdid_wire = 1'b0,
		read_sid_wire = read_sid_reg,
		read_status_wire = 1'b0,
		read_wire = read_reg,
		rflagstat_opcode = 8'b00000101,
		rnvdummyclk_opcode = {8{1'b0}},
		rsid_opcode = 8'b10101011,
		rsid_sdoin = (do_read_sid & stage3_wire),
		rstat_opcode = 8'b00000101,
		scein_wire = (~ ncs_reg),
		sdoin_wire = to_sdoin_wire,
		sec_erase_wire = sec_erase_reg,
		sec_protect_wire = sec_prot_reg,
		secprot_opcode = 8'b00000001,
		secprot_sdoin = (stage3_wire & streg_datain_reg),
		serase_opcode = 8'b11011000,
		shift_bytes_wire = shift_bytes,
		shift_opcode = shift_op_reg,
		shift_opdata = stage2_wire,
		shift_pgwr_data = shftpgwr_data_reg,
		sid_load = (end_ophdly & do_read_sid),
		st_busy_wire = statreg_int[0],
		stage2_wire = stage2_reg,
		stage3_wire = stage3_reg,
		stage4_wire = stage4_reg,
		start_frpoll = 1'b0,
		start_poll = ((start_wrpoll | start_sppoll) | start_frpoll),
		start_sppoll = start_sppoll_reg2,
		start_wrpoll = start_wrpoll_reg2,
		to_sdoin_wire = ((((((shift_opdata & asmi_opcode_reg[7]) | rsid_sdoin) | memadd_sdoin) | write_sdoin) | secprot_sdoin) | freadwrv_sdoin),
		wren_opcode = 8'b00000110,
		wren_wire = wren,
		write_opcode = 8'b00000010,
		write_prot_true = write_prot_reg,
		write_sdoin = ((((do_write & stage4_wire) & wire_wrstage_cntr_q[1]) & wire_wrstage_cntr_q[0]) & pgwrbuf_dataout[7]),
		write_wire = write_reg,
		wrvolatile_opcode = {8{1'b0}};
*/ //dh: combloop
endmodule //asmi_asmi_parallel_0
//VALID FILE

module dsiq_fifo (
  wr_clk,
  wr_tdata,
  wr_tvalid,
  wr_tready,
  wr_tlast,

  rd_clk,
  rd_tdata,
  rd_tvalid,
  rd_tready
);

input         wr_clk;
input [7:0]   wr_tdata;
input         wr_tvalid;
output        wr_tready;
input         wr_tlast;

input         rd_clk;
output [31:0] rd_tdata;
output        rd_tvalid;
input         rd_tready;

parameter     depth   = 8192;

localparam    wrbits  = (depth == 16384) ? 14 : 13;
localparam    wrlimit = (depth == 16384) ? 14'h2000 : 13'h1000;

localparam    rdbits  = (depth == 16384) ? 12 : 11;
localparam    rdlimit = (depth == 16384) ? 12'h800 : 11'h400;

logic [31:0]  ird_tdata;

logic         wr_treadyn;
logic         rd_tvalidn;

logic         allow_push = 1'b1;
logic [(wrbits-1):0]  wr_tlength;

logic         allow_pop  = 1'b0;
logic [(rdbits-1):0]  rd_tlength;

// If FIFO fills, drop write data
// again until only half full
always @ (posedge wr_clk) begin
  if (wr_treadyn) begin
    allow_push <= 1'b0;
  end else if (wr_tlast & (wr_tlength <= wrlimit)) begin
    allow_push <= 1'b1;
  end 
end 

dcfifo_mixed_widths #(
  .intended_device_family("Cyclone IV E"),
  .lpm_numwords(depth), 
  .lpm_showahead ("ON"),
  .lpm_type("dcfifo_mixed_widths"),
  .lpm_width(8),
  .lpm_widthu(wrbits),
  .lpm_widthu_r(rdbits),
  .lpm_width_r(32),
  .overflow_checking("ON"),
  .rdsync_delaypipe(4),
  .underflow_checking("ON"),
  .use_eab("ON"),
  .wrsync_delaypipe(4)
) fifo_i (
  .wrclk (wr_clk),
  .wrreq (wr_tvalid & allow_push),  
  .wrfull (wr_treadyn),
  .wrempty (),
  .wrusedw (wr_tlength),
  .data (wr_tdata),

  .rdclk (rd_clk),
  .rdreq (rd_tready & allow_pop),
  .rdfull (),
  .rdempty (rd_tvalidn),
  .rdusedw (rd_tlength),
  .q (ird_tdata),

  .aclr (1'b0),
  .eccstatus ()
);

// If FIFO empties, drop write data
// again until only half full
always @ (posedge rd_clk) begin
  if (rd_tvalidn) begin
    allow_pop <= 1'b0;
  end else if (rd_tlength >= rdlimit) begin
    allow_pop <= 1'b1;
  end 
end 
assign rd_tdata = allow_pop ? ird_tdata : 32'h0;

assign wr_tready = ~wr_treadyn & allow_push;
assign rd_tvalid = ~rd_tvalidn & allow_pop;

endmodule 



module dslr_fifo (
  wr_clk,
  wr_tdata,
  wr_tvalid,
  wr_tready,

  rd_clk,
  rd_tdata,
  rd_tvalid,
  rd_tready
);

input         wr_clk;
input [7:0]   wr_tdata;
input         wr_tvalid;
output        wr_tready;

input         rd_clk;
output [31:0] rd_tdata;
output        rd_tvalid;
input         rd_tready;

logic         wr_treadyn;
logic         rd_tvalidn;

dcfifo_mixed_widths #(
  .intended_device_family("Cyclone IV E"),
  .lpm_numwords(8192), 
  .lpm_showahead ("ON"),
  .lpm_type("dcfifo_mixed_widths"),
  .lpm_width(8),
  .lpm_widthu(13),
  .lpm_widthu_r(11),
  .lpm_width_r(32),
  .overflow_checking("ON"),
  .rdsync_delaypipe(4),
  .underflow_checking("ON"),
  .use_eab("ON"),
  .wrsync_delaypipe(4)
) fifo_i (
  .wrclk (wr_clk),
  .wrreq (wr_tvalid),  
  .wrfull (wr_treadyn),
  .wrempty (),
  .wrusedw (),
  .data (wr_tdata),

  .rdclk (rd_clk),
  .rdreq (rd_tready),
  .rdfull (),
  .rdempty (rd_tvalidn),
  .rdusedw (),
  .q (rd_tdata),

  .aclr (1'b0),
  .eccstatus ()
);

assign wr_tready = ~wr_treadyn;
assign rd_tvalid = ~rd_tvalidn;

endmodule 



module usiq_fifo (
  wr_clk,
  wr_tdata,
  wr_tvalid,
  wr_tready,
  wr_tlast,
  wr_tuser,

  rd_clk,
  rd_tdata,
  rd_tvalid,
  rd_tready,
  rd_tlast,
  rd_tuser,
  rd_tlength
);

input         wr_clk;
input [23:0]  wr_tdata;
input         wr_tvalid;
output        wr_tready;
input         wr_tlast;
input [1:0]   wr_tuser;

input         rd_clk;
output [23:0] rd_tdata;
output        rd_tvalid;
input         rd_tready;
output        rd_tlast;
output [1:0]  rd_tuser;
output [10:0] rd_tlength;

logic         wr_treadyn;
logic         rd_tvalidn;
logic  [26:0] rd_data;

dcfifo #(
  .add_usedw_msb_bit("ON"),
  .intended_device_family("Cyclone IV E"),
  .lpm_numwords(1024), 
  .lpm_showahead ("ON"),
  .lpm_type("dcfifo"),
  .lpm_width(27),
  .lpm_widthu(11), 
  .overflow_checking("ON"),
  .rdsync_delaypipe(4),
  .underflow_checking("ON"),
  .use_eab("ON"),
  .wrsync_delaypipe(4)
) fifo_i (
  .wrclk (wr_clk),
  .wrreq (wr_tvalid),
  .wrfull (wr_treadyn),
  .wrempty (),
  .wrusedw (),
  .data ({wr_tuser,wr_tlast,wr_tdata}),

  .rdclk (rd_clk),
  .rdreq (rd_tready),
  .rdfull (),
  .rdempty (rd_tvalidn),
  .rdusedw (rd_tlength),
  .q (rd_data),

  .aclr (1'b0),
  .eccstatus ()  
);

assign wr_tready = ~wr_treadyn;
assign rd_tvalid = ~rd_tvalidn;
assign rd_tlast  = rd_data[24];
assign rd_tdata  = rd_data[23:0];
assign rd_tuser  = rd_data[26:25];

endmodule 



module usbs_fifo (
  wr_clk,
  wr_tdata,
  wr_tvalid,
  wr_tready,

  rd_clk,
  rd_tdata,
  rd_tvalid,
  rd_tready
);

input         wr_clk;
input [11:0]  wr_tdata;
input         wr_tvalid;
output        wr_tready;

input         rd_clk;
output [11:0] rd_tdata;
output logic  rd_tvalid = 1'b0;
input         rd_tready;

logic         rd_tvalidn;

logic         bs_ad9866_full, bs_ad9866_empty;
logic         bs_ad9866_push = 1'b0;

logic         bs_full, bs_empty;


// BS AD9866 State
always @ (posedge wr_clk) begin
  if (bs_ad9866_empty) begin
    bs_ad9866_push <= 1'b1;
  end else if (bs_ad9866_full) begin
    bs_ad9866_push <= 1'b0;
  end 
end 

assign wr_tready = bs_ad9866_push & ~bs_ad9866_full;

dcfifo #(
  .intended_device_family("Cyclone IV E"),
  .lpm_numwords(2048), 
  .lpm_showahead ("ON"),
  .lpm_type("dcfifo"),
  .lpm_width(12),
  .lpm_widthu(11), 
  .overflow_checking("ON"),
  .rdsync_delaypipe(4),
  .underflow_checking("ON"),
  .use_eab("ON"),
  .wrsync_delaypipe(4)
) fifo_i (
  .wrclk (wr_clk),
  .wrreq (bs_ad9866_push & ~bs_ad9866_full),
  .wrfull (bs_ad9866_full),
  .wrempty (bs_ad9866_empty),
  .wrusedw (),
  .data (wr_tdata),

  .rdclk (rd_clk),
  .rdreq (rd_tready),
  .rdfull (bs_full),
  .rdempty (bs_empty),
  .rdusedw (),
  .q (rd_tdata),

  .aclr (1'b0),
  .eccstatus ()  
);

// BS State
always @ (posedge rd_clk) begin
  if (bs_full) begin
    rd_tvalid <= 1'b1;
  end else if (bs_empty) begin
    rd_tvalid <= 1'b0;
  end 
end 

endmodule 


(* blackbox *)
module asmi_fifo (
  aclr,
  data,
  rdclk,
  rdreq,
  wrclk,
  wrreq,
  q,
  rdusedw);

  input   aclr;
  input [7:0]  data;
  input   rdclk;
  input   rdreq;
  input   wrclk;
  input   wrreq;
  output  [7:0]  q;
  output  [9:0]  rdusedw;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
  tri0    aclr;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

  wire [7:0] sub_wire0;
  wire [9:0] sub_wire1;
  wire [7:0] q = sub_wire0[7:0];
  wire [9:0] rdusedw = sub_wire1[9:0];
/*
  dcfifo  dcfifo_component (
        .wrclk (wrclk),
        .rdreq (rdreq),
        .aclr (aclr),
        .rdclk (rdclk),
        .wrreq (wrreq),
        .data (data),
        .q (sub_wire0),
        .rdusedw (sub_wire1)
        // synopsys translate_off
        ,
        .rdempty (),
        .rdfull (),
        .wrempty (),
        .wrfull (),
        .wrusedw ()
        // synopsys translate_on
        );
  defparam
    dcfifo_component.intended_device_family = "Cyclone IV E",
    dcfifo_component.lpm_numwords = 1024,
    dcfifo_component.lpm_showahead = "OFF",
    dcfifo_component.lpm_type = "dcfifo",
    dcfifo_component.lpm_width = 8,
    dcfifo_component.lpm_widthu = 10,
    dcfifo_component.overflow_checking = "ON",
    dcfifo_component.rdsync_delaypipe = 4,
    dcfifo_component.underflow_checking = "ON",
    dcfifo_component.use_eab = "ON",
    dcfifo_component.write_aclr_synch = "OFF",
    dcfifo_component.wrsync_delaypipe = 4;
*/

endmodule

module remote_update_fac (
  clk,
  rst,
  bootapp
 );

input clk;
input rst;
input bootapp;

logic reconfig = 1'b0;
logic busy;
logic write;

logic [2:0] param;
logic [23:0] data_in;



localparam START      = 'b000,
           ANF        = 'b001,
           ANF_BUSY   = 'b011,
           WRITE      = 'b010,
           WRITE_BUSY = 'b110,
           REBOOT     = 'b100,
           DONE       = 'b101;

logic   [ 2:0]  state = START;
logic   [ 2:0]  state_next;


always @ (posedge clk) begin
  if (rst) begin
    state <= START;
  end else begin
    state <= state_next;
  end 
end

// FSM Combinational
always @* begin

  // Next State
  state_next = state;

  // Combinational output
  write = 1'b0;
  reconfig = 1'b0;
  param = 3'b000;
  data_in = 24'h000000;


  case (state)
    START: begin
      if (~busy) state_next = ANF;
      param = 3'b101;
      data_in = 24'h01;
    end

    ANF: begin
      write = 1'b1;
      param = 3'b101;
      data_in = 24'h01;
      if (busy) state_next = ANF_BUSY;
    end

    ANF_BUSY: begin
      param = 3'b100;
      data_in = 24'h040000;
      if (~busy) state_next = WRITE;
    end


    WRITE: begin
      write = 1'b1;
      param = 3'b100;
      data_in = 24'h040000;
      if (busy) state_next = WRITE_BUSY;
    end

    WRITE_BUSY: begin
      if (~busy) state_next = REBOOT;
    end

    REBOOT: begin
      reconfig = bootapp;
      //if (busy) state_next = DONE;
      state_next = DONE;
    end

    DONE: begin
      state_next = DONE;
    end

    default: begin
      state_next = START;
    end

  endcase
end



altera_remote_update_core remote_update_core (
  .read_param  (1'b0), 
  .param       (param),      
  .reconfig    (reconfig),   
  .reset_timer (1'b0),
  .clock       (clk),      
  .reset       (rst),      
  .busy        (busy),       
  .data_out    (),   
  .read_source (2'b00),
  .write_param (write),
  .data_in     (data_in),    
  .ctl_nupdt   (1'b0)        
);

endmodule
//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// (C) Phil Harman VK6APH 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013 


// Push Button debounce routine
// Found on the Internet, author unknown
// used to debounce a switch or push button.
// Input is pb and outout clean_pb.
// Button must be stable for debounce time before state changes,
// debounce time is dependent on clk and counter_bits


//  Phil Harman VK6APH 15th February 2006

module debounce(clean_pb, pb, clk);
	
	output clean_pb;
	input pb, clk;
	
reg [13:0] count;
reg [3:0] pb_history;
reg clean_pb;

always @ (posedge clk)
begin
	pb_history <= {pb_history[2:0], pb};
	
	if (pb_history[3] != pb_history[2])
		count <= 1'b0;
	else if(&count)
		clean_pb <= pb_history[3];
	else
		count <= count + 1'b1;
end 
endmodule

module remote_update_app (
  clk,
  rst,
  reconfig
 );


input clk;
input rst;
input reconfig;

logic reset_timer = 1'b0;

always @ (posedge clk) reset_timer <= ~reset_timer;

altera_remote_update_core remote_update_core (
  .read_param  (1'b0), 
  .param       (3'b000),      
  .reconfig    (reconfig),   
  .reset_timer (reset_timer),
  .clock       (clk),      
  .reset       (rst),      
  .busy        (),       
  .data_out    (),   
  .read_source (2'b00),
  .write_param (1'b0),
  .data_in     (24'h000000),    
  .ctl_nupdt   (1'b0)        
);

endmodule
//
//  Hermes Lite
// 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// (C) Steve Haynal KF7O 2014-2018

module ad9866 (
  clk,
  clk_2x,

  tx_data,
  rx_data,
  tx_en,

  rxclip,
  rxgoodlvl,
  rxclrstatus,

  rffe_ad9866_tx,
  rffe_ad9866_rx,
  rffe_ad9866_rxsync,
  rffe_ad9866_rxclk,  
  rffe_ad9866_txquiet_n,
  rffe_ad9866_txsync,
  rffe_ad9866_mode
);

input             clk;
input             clk_2x;

input   [11:0]    tx_data;
output logic  [11:0]    rx_data;
input             tx_en;

output logic       rxclip = 1'b0;
output logic       rxgoodlvl = 1'b0;
input             rxclrstatus;

`ifdef HALFDUPLEX
inout   [5:0]     rffe_ad9866_tx;
inout   [5:0]     rffe_ad9866_rx;
output logic            rffe_ad9866_rxsync;
output logic            rffe_ad9866_rxclk; 
`else
output logic  [5:0]     rffe_ad9866_tx;
input   [5:0]     rffe_ad9866_rx;
input             rffe_ad9866_rxsync;
input             rffe_ad9866_rxclk; 
`endif
output logic            rffe_ad9866_txquiet_n;
output logic            rffe_ad9866_txsync;

output logic            rffe_ad9866_mode;


// TX Path
logic   [11:0]    tx_data_d1;
logic             tx_sync;
logic             tx_en_d1;

// RX Path
logic   [11:0]    rx_data_assemble;
logic    [5:0]    rffe_ad9866_rx_d1, rffe_ad9866_rx_d2;
logic             rffe_ad9866_rxsync_d1;


logic             rxclipp, rxclipn;
logic             rxgoodlvlp, rxgoodlvln;



// TX Path

`ifdef HALFDUPLEX
always @(posedge clk) tx_en_d1 <= tx_en;

always @(posedge clk) tx_data_d1 <= tx_data;
assign rffe_ad9866_tx = tx_en_d1 ? tx_data_d1[11:6] : 6'bZ;
assign rffe_ad9866_rx = tx_en_d1 ? tx_data_d1[5:0]  : 6'bZ;
assign rffe_ad9866_txsync = tx_en_d1;
assign rffe_ad9866_txquiet_n = clk;

`else
always @(posedge clk_2x) begin
  tx_en_d1 <= tx_en;
  tx_sync <= ~tx_sync;
  if (tx_en_d1) begin
    if (tx_sync) begin 
      tx_data_d1 <= tx_data;
      rffe_ad9866_tx <= tx_data_d1[5:0];
    end else begin
      rffe_ad9866_tx <= tx_data_d1[11:6];
    end
    rffe_ad9866_txsync <= tx_sync;
  end else begin
    rffe_ad9866_tx <= 6'h00;
    rffe_ad9866_txsync <= 1'b0;
  end
end

assign rffe_ad9866_txquiet_n = tx_en_d1; 

`endif

// RX Path

`ifdef HALFDUPLEX
always @(posedge clk) rx_data_assemble <= {rffe_ad9866_tx,rffe_ad9866_rx};
assign rffe_ad9866_rxsync = ~tx_en_d1;
assign rffe_ad9866_rxclk = clk;
assign rffe_ad9866_mode = 1'b0;

`else
// Assume that ad9866_rxclk is synchronous to ad9866clk
// Don't know the phase relation
always @(posedge clk_2x) begin
  rffe_ad9866_rx_d1 <= rffe_ad9866_rx;
  rffe_ad9866_rx_d2 <= rffe_ad9866_rx_d1;
  rffe_ad9866_rxsync_d1 <= rffe_ad9866_rxsync;
  if (rffe_ad9866_rxsync_d1) rx_data_assemble <= {rffe_ad9866_rx_d2,rffe_ad9866_rx_d1};
end
assign rffe_ad9866_mode = 1'b1;
`endif

always @ (posedge clk) rx_data <= rx_data_assemble;


assign rxclipp = (rx_data == 12'b011111111111);
assign rxclipn = (rx_data == 12'b100000000000);

// Like above but 2**11.585 = (4096-1024) = 3072
assign rxgoodlvlp = (rx_data[11:9] == 3'b011);
assign rxgoodlvln = (rx_data[11:9] == 3'b100);

always @(posedge clk) begin
  if (rxclrstatus) rxclip <= 1'b0;
  if (rxclipp | rxclipn) rxclip <= 1'b1;
end

always @(posedge clk) begin
  if (rxclrstatus) rxgoodlvl <= 1'b0;
  if (rxgoodlvlp | rxgoodlvln) rxgoodlvl <= 1'b1;
end

endmodule // ad9866


// OpenHPSDR upstream (Card->PC) protocol packer

module usopenhpsdr1 (
  clk,
  have_ip,
  run,
  wide_spectrum,
  idhermeslite,
  mac,
  discovery,
  
  udp_tx_enable,
  udp_tx_request,
  udp_tx_data,
  udp_tx_length,

  bs_tdata,
  bs_tready,
  bs_tvalid,

  us_tdata,
  us_tlast,
  us_tready,
  us_tvalid,
  us_tuser,
  us_tlength,

  // Command slave interface
  cmd_addr,
  cmd_data,
  cmd_rqst,

  resp,
  resp_rqst,

  watchdog_up,

  usethasmi_send_more,
  usethasmi_erase_done,
  usethasmi_ack
);

input               clk;
input               have_ip;
input               run;
input               wide_spectrum;
input               idhermeslite;
input [47:0]        mac;
input               discovery;

input               udp_tx_enable;
output logic              udp_tx_request;
output logic [7:0]        udp_tx_data;
output logic [10:0] udp_tx_length = 'd0;

input [11:0]        bs_tdata;
output logic              bs_tready;
input               bs_tvalid;

input [23:0]        us_tdata;
input               us_tlast;
output logic              us_tready;
input               us_tvalid;
input [ 1:0]        us_tuser;
input [10:0]        us_tlength;

// Command slave interface
input  [5:0]        cmd_addr;
input  [31:0]       cmd_data;
input               cmd_rqst;

input  [39:0]       resp;
output logic        resp_rqst = 1'b0;

output logic        watchdog_up = 1'b0;

input               usethasmi_send_more;
input               usethasmi_erase_done;
output logic              usethasmi_ack;



parameter           NR = 8'h0;
parameter           HERMES_SERIALNO = 8'h0;


localparam START        = 4'h0,
           WIDE1        = 4'h1,
           WIDE2        = 4'h2,
           WIDE3        = 4'h3,
           WIDE4        = 4'h4,
           DISCOVER1    = 4'h5,
           DISCOVER2    = 4'h6,
           UDP1         = 4'h7,
           UDP2         = 4'h8,
           SYNC_RESP    = 4'h9,
           RXDATA2      = 4'ha,
           RXDATA1      = 4'hb,
           RXDATA0      = 4'hc,
           MIC1         = 4'hd,
           MIC0         = 4'he,
           PAD          = 4'hf;

logic   [ 3:0]  state = START;
logic   [ 3:0]  state_next;

logic   [10:0]  byte_no = 11'h00;
logic   [10:0]  byte_no_next; 

logic   [10:0]  udp_tx_length_next;

logic   [31:0]  ep6_seq_no = 32'h0;
logic   [31:0]  ep6_seq_no_next;

logic   [31:0]  ep4_seq_no = 32'h0;
logic   [31:0]  ep4_seq_no_next;

logic   [ 7:0]  discover_data = 'd0, discover_data_next;
logic   [ 7:0]  wide_data = 'd0, wide_data_next;
logic   [ 7:0]  udp_data = 'd0, udp_data_next;

// Allow for at least 12 receivers in a round of sample data
logic   [ 6:0]  round_bytes = 7'h00, round_bytes_next;

logic   [6:0]   bs_cnt = 7'h1, bs_cnt_next;
logic   [6:0]   set_bs_cnt = 7'h1;

logic           resp_rqst_next;

logic           watchdog_up_next;

logic           vna = 1'b0;

logic           vna_mic_bit = 1'b0, vna_mic_bit_next;

// Command Slave State Machine
always @(posedge clk) begin
  if (cmd_rqst) begin
    case (cmd_addr)
      6'h00: begin  
        // Shift no of receivers by speed
        set_bs_cnt <= ((cmd_data[7:3] + 1'b1) << cmd_data[25:24]);
      end

      6'h09: begin
        vna <= cmd_data[23];
      end
    endcase 
  end
end


// State
always @ (posedge clk) begin
  state <= state_next;

  byte_no <= byte_no_next;
  discover_data <= discover_data_next;
  wide_data <= wide_data_next;
  udp_data <= udp_data_next;

  udp_tx_length <= udp_tx_length_next;
  
  bs_cnt <= bs_cnt_next;

  round_bytes <= round_bytes_next;

  resp_rqst <= resp_rqst_next;

  watchdog_up <= watchdog_up_next;

  vna_mic_bit <= vna_mic_bit_next;

  if (~run) begin
    ep6_seq_no <= 32'h0;
    ep4_seq_no <= 32'h0;
  end else begin
    ep6_seq_no <= ep6_seq_no_next;
    // Synchronize sequence number lower 2 bits as some software may require this
    ep4_seq_no <= (bs_tvalid) ? ep4_seq_no_next : {ep4_seq_no_next[31:2],2'b00};
  end 
end 


// FSM Combinational
always @* begin

  // Next State
  state_next = state;

  byte_no_next = byte_no;
  discover_data_next = discover_data;
  wide_data_next = wide_data;
  udp_data_next = udp_data;

  udp_tx_length_next = udp_tx_length;

  round_bytes_next = round_bytes;

  ep6_seq_no_next = ep6_seq_no;
  ep4_seq_no_next = ep4_seq_no;

  bs_cnt_next = bs_cnt;

  resp_rqst_next = resp_rqst;

  watchdog_up_next = watchdog_up;

  vna_mic_bit_next = vna_mic_bit;

  // Combinational
  udp_tx_data = udp_data;
  udp_tx_request = 1'b0;
  us_tready = 1'b0;
  bs_tready = 1'b0;

  usethasmi_ack = 1'b0;

  case (state)
    START: begin
 
      if (discovery | usethasmi_erase_done | usethasmi_send_more) begin 
        udp_tx_length_next = 'h3c;
        state_next = DISCOVER1;

      end else if ((us_tlength > 11'd333) & us_tvalid & have_ip & run) begin // wait until there is enough data in fifo
        udp_tx_length_next = 'd1032;
        state_next = UDP1;
      
      end else if (bs_tvalid & ~(|bs_cnt)) begin 
        bs_cnt_next = set_bs_cnt; // Set count until next wide data
        watchdog_up_next = ~watchdog_up; 
        udp_tx_length_next = 'd1032;
        if (wide_spectrum) state_next = WIDE1;
      end
    end

    DISCOVER1: begin
      byte_no_next = 'h3a;
      udp_tx_data = discover_data;
      udp_tx_request = 1'b1;
      discover_data_next = 8'hef;
      if (udp_tx_enable) state_next = DISCOVER2;
    end // DISCOVER1:

    DISCOVER2: begin
      byte_no_next = byte_no - 11'd1;
      udp_tx_data = discover_data;      
      case (byte_no[5:0])
        6'h3a: discover_data_next = 8'hfe;
        6'h39: discover_data_next = usethasmi_erase_done ? 8'h03 : (usethasmi_send_more ? 8'h04 : (run ? 8'h03 : 8'h02));
        6'h38: discover_data_next = mac[47:40];
        6'h37: discover_data_next = mac[39:32];
        6'h36: discover_data_next = mac[31:24];
        6'h35: discover_data_next = mac[23:16];
        6'h34: discover_data_next = mac[15:8];
        6'h33: discover_data_next = mac[7:0];
        6'h32: discover_data_next = HERMES_SERIALNO;
        //6'h31: discover_data_next = IDHermesLite ? 8'h06 : 8'h01;
        // FIXME: Really needed for CW skimmer? Why so much?
        6'h30: discover_data_next = "H";
        6'h2f: discover_data_next = "E";
        6'h2e: discover_data_next = "R";
        6'h2d: discover_data_next = "M";
        6'h2c: discover_data_next = "E";
        6'h2b: discover_data_next = "S";
        6'h2a: discover_data_next = "L";
        6'h29: discover_data_next = "T";
        6'h28: discover_data_next = NR[7:0];
        6'h00: begin
          discover_data_next = idhermeslite ? 8'h06 : 8'h01;
          if (usethasmi_erase_done | usethasmi_send_more) byte_no_next = 6'h00;
          else state_next = START;
        end
        default: begin
          discover_data_next = idhermeslite ? 8'h06 : 8'h01;
        end
      endcase

      // Always acknowledge
      usethasmi_ack = byte_no[5:0] <= 6'h38;
    end

    // start sending UDP/IP data
    WIDE1: begin
      byte_no_next = 'h406;
      udp_tx_data = wide_data;
      udp_tx_request = 1'b1;
      wide_data_next = 8'hef;
      if (udp_tx_enable) state_next = WIDE2;
    end 

    WIDE2: begin
      byte_no_next = byte_no - 11'd1;
      udp_tx_data = wide_data;
      case (byte_no[2:0])
        3'h6: wide_data_next = 8'hfe;
        3'h5: wide_data_next = 8'h01;
        3'h4: wide_data_next = 8'h04;
        3'h3: wide_data_next = ep4_seq_no[31:24];
        3'h2: wide_data_next = ep4_seq_no[23:16];
        3'h1: wide_data_next = ep4_seq_no[15:8];
        3'h0: begin
          wide_data_next = ep4_seq_no[7:0];
          ep4_seq_no_next = ep4_seq_no + 'h1;
          state_next = WIDE3;
        end
        default: wide_data_next = 8'hxx;
      endcase
    end

    WIDE3: begin
      byte_no_next = byte_no - 11'd1;
      udp_tx_data = wide_data;
      //wide_data_next = {{4{bs_tdata[11]}}, bs_tdata};
      wide_data_next = bs_tdata[7:0];

      // Allow for one extra to keep udp_tx_data mux stable
      state_next = (&byte_no) ? START : WIDE4;
    end 

    WIDE4: begin
      byte_no_next = byte_no - 11'd1;
      udp_tx_data = wide_data;
      //wide_data_next = bs_tdata[7:0];
      wide_data_next = {{4{bs_tdata[11]}}, bs_tdata[11:8]};
      bs_tready = 1'b1; // Pop data

      // Escape if something goes wrong
      state_next = (&byte_no) ? START : WIDE3;
    end

    UDP1: begin
      byte_no_next = 'h406;
      udp_tx_request = 1'b1;
      udp_data_next = 8'hef;
      if (udp_tx_enable) state_next = UDP2;
    end
    
    UDP2: begin
      byte_no_next = byte_no - 11'd1;
      case (byte_no[2:0])
        3'h6: udp_data_next = 8'hfe;
        3'h5: udp_data_next = 8'h01;
        3'h4: udp_data_next = 8'h06;
        3'h3: udp_data_next = ep6_seq_no[31:24];
        3'h2: udp_data_next = ep6_seq_no[23:16];
        3'h1: udp_data_next = ep6_seq_no[15:8]; 
        3'h0: begin
          udp_data_next = ep6_seq_no[7:0];
          ep6_seq_no_next = ep6_seq_no + 'h1;
          bs_cnt_next = bs_cnt - 7'd1;
          state_next = SYNC_RESP;
        end
        default: udp_data_next = 8'hxx;
      endcase // byte_no
    end // UDP2:

    SYNC_RESP: begin
      byte_no_next = byte_no - 11'd1;
      round_bytes_next = 'd0;
      case (byte_no[8:0])
        9'h1ff: udp_data_next = 8'h7f;
        9'h1fe: udp_data_next = 8'h7f;
        9'h1fd: udp_data_next = 8'h7f;
        9'h1fc: udp_data_next = resp[39:32];
        9'h1fb: udp_data_next = resp[31:24];
        9'h1fa: udp_data_next = resp[23:16];
        9'h1f9: udp_data_next = resp[15:8];
        9'h1f8: begin 
          udp_data_next = resp[7:0];
          resp_rqst_next = ~resp_rqst; 
          state_next = RXDATA2; 
        end 
        default: udp_data_next = 8'hxx; 
      endcase
    end

    RXDATA2: begin
      byte_no_next = byte_no - 11'd1;
      round_bytes_next = round_bytes + 7'd1;
      udp_data_next = us_tdata[23:16];
      vna_mic_bit_next = us_tuser[0]; // Save mic bit for use laster with mic data

      if (|byte_no[8:0]) begin
        state_next = RXDATA1;
      end else begin 
        state_next = byte_no[9] ? SYNC_RESP : START;
      end
    end      

    RXDATA1: begin
      byte_no_next = byte_no - 11'd1;
      round_bytes_next = round_bytes + 7'd1;
      udp_data_next = us_tdata[15:8];

      if (|byte_no[8:0]) begin
        state_next = RXDATA0;        
      end else begin
        state_next = byte_no[9] ? SYNC_RESP : START; 
      end
    end   

    RXDATA0: begin
      byte_no_next = byte_no - 11'd1;
      round_bytes_next = round_bytes + 7'd1;
      udp_data_next = us_tdata[7:0];
      us_tready = 1'b1; // Pop next word

      if (|byte_no[8:0]) begin
        if (us_tlast) begin 
          state_next = MIC1;
        end else begin
          state_next = RXDATA2;
        end
      end else begin 
        state_next = byte_no[9] ? SYNC_RESP : START;
      end
    end 

    MIC1: begin
      byte_no_next = byte_no - 11'd1;
      round_bytes_next = round_bytes + 7'd1;
      udp_data_next = 'd0;
      
      if (|byte_no[8:0]) begin
        state_next = MIC0;
      end else begin 
        state_next = byte_no[9] ? SYNC_RESP : START;
      end   
    end 

    MIC0: begin
      byte_no_next = byte_no - 11'd1;
      round_bytes_next = 'd0;
      udp_data_next = vna ? {7'h00,vna_mic_bit} : 8'h00; // VNA, may need to be in MIC1

      if (|byte_no[8:0]) begin
        // Enough room for another round of data?
        state_next = (byte_no[8:0] > round_bytes) ? RXDATA2 : PAD;
      end else begin
        state_next = byte_no[9] ? SYNC_RESP : START;
      end
    end

    PAD: begin
      byte_no_next = byte_no - 11'd1;
      udp_data_next = 8'h00;

      if (~(|byte_no[8:0])) begin
        state_next = byte_no[9] ? SYNC_RESP : START;
      end 
    end 

    default: state_next = START;

  endcase // state
end // always @*


endmodule
`timescale 1ns / 1ps

module i2c_bus2
(
  clk,
  rst,

  cmd_addr,
  cmd_data,
  cmd_rqst,
  cmd_ack,

  en_i2c2,
  ready,

  scl_i,
  scl_o,
  scl_t,
  sda_i,
  sda_o,
  sda_t
);

input         clk;
input         rst;

// Command slave interface
input  [5:0]  cmd_addr;
input  [31:0] cmd_data;
input         cmd_rqst;
output logic  cmd_ack;

output  logic en_i2c2;
output  logic ready;    
 
input         scl_i;
output logic  scl_o;
output logic  scl_t;
input         sda_i;
output logic  sda_o;
output logic  sda_t;

logic [6:0]   cmd_address;
logic         cmd_start;
logic         cmd_read;
logic         cmd_write;
logic         cmd_write_multiple;
logic         cmd_stop;
logic         cmd_valid;
logic         cmd_ready;

logic [7:0]   data_in;
logic         data_in_valid;
logic         data_in_ready;
logic         data_in_last;

logic [7:0]   data_out;
logic         data_out_valid;
logic         data_out_ready;
logic         data_out_last;

logic [2:0]   state, state_next;
logic         busy, missed_ack;

logic [6:0]   cmd_reg, cmd_next;
logic [7:0]   data0_reg, data0_next, data1_reg, data1_next;

logic         cmd_ack_reg, cmd_ack_next;

logic [6:0]   filter_select_reg, filter_select_next;

logic         en_i2c2_next;




// Control
localparam [2:0]
  STATE_IDLE          = 3'h0,
  STATE_CMDADDR       = 3'h1,
  STATE_WRITE_DATA0   = 3'h2,
  STATE_WRITE_DATA1   = 3'h3,
  STATE_FCMDADDR      = 3'h5,
  STATE_WRITE_FDATA0  = 3'h6,
  STATE_WRITE_FDATA1  = 3'h7,
  STATE_WRITE_FDATA2  = 3'h4;



always @(posedge clk) begin
  if (rst) begin
    state <= STATE_IDLE;
    cmd_reg <= 'h0;
    data0_reg <= 'h0;
    data1_reg <= 'h0;
    cmd_ack_reg <= 1'b0;
    filter_select_reg <= 'h0;
  end else begin
    state <= state_next;
    cmd_reg <= cmd_next;
    data0_reg <= data0_next;
    data1_reg <= data1_next;
    cmd_ack_reg <= cmd_ack_next;
    filter_select_reg <= filter_select_next;
    en_i2c2 <= en_i2c2_next;
  end
end

assign cmd_address = cmd_reg;
assign cmd_start = 1'b0;
assign cmd_read = 1'b0;
assign cmd_write_multiple = 1'b0;
assign cmd_stop = 1'b0;

assign data_in_last = 1'b1;

assign data_out_ready = 1'b1;

assign cmd_ack = cmd_ack_reg;


always @* begin
  state_next = state;

  cmd_valid = 1'b0; 
  cmd_write = 1'b0;
  //cmd_stop = 1'b0;
  cmd_ack_next = cmd_ack;

  data_in = data0_reg;
  data_in_valid = 1'b0;

  filter_select_next = filter_select_reg;

  cmd_next = cmd_reg;
  data0_next = data0_reg;
  data1_next = data1_reg; 
  en_i2c2_next = en_i2c2;

  ready = 1'b0;
  
  case(state)

    STATE_IDLE: begin
      ready = ~busy;
      if (cmd_rqst) begin
        cmd_ack_next = 1'b1;
        if (((cmd_addr == 6'h3d) | (cmd_addr == 6'h3c)) & (cmd_data[31:24] == 8'h06)) begin
          // Must send
          if (~busy) begin
            cmd_next = cmd_data[22:16];
            data0_next  = cmd_data[15:8];
            data1_next = cmd_data[7:0];
            en_i2c2_next = (cmd_addr == 6'h3d);
            state_next = STATE_CMDADDR;
          end else begin
            cmd_ack_next = 1'b0; // Missed
          end
        end

        // Filter select update
        if (cmd_addr == 6'h00) begin
          if (cmd_data[23:17] != filter_select_reg) begin
            // Must send
            if (~busy) begin
              filter_select_next = cmd_data[23:17];
              cmd_next = 'h20;
              data0_next = 'h0a;
              data1_next = {1'b0,cmd_data[23:17]};
              en_i2c2_next = 1'b1;
              state_next = STATE_FCMDADDR;
            end else begin
              cmd_ack_next = 1'b0; // Missed
            end
          end
        end
      end
    end

    STATE_CMDADDR: begin
      cmd_valid = 1'b1;
      cmd_write = 1'b1;
      if (cmd_ready) state_next = STATE_WRITE_DATA0;
    end

    STATE_WRITE_DATA0: begin
      cmd_valid = 1'b1;
      cmd_write = 1'b1;
      data_in_valid = 1'b1;
      data_in = data0_reg;
      if (data_in_ready) state_next = STATE_WRITE_DATA1;
    end

    STATE_WRITE_DATA1: begin
      cmd_valid = 1'b1;
      cmd_write = 1'b1;
      data_in_valid = 1'b1;
      data_in = data1_reg;
      if (data_in_ready) state_next = STATE_IDLE;
    end

    STATE_FCMDADDR: begin
      cmd_valid = 1'b1;
      cmd_write = 1'b1;
      if (cmd_ready) state_next = STATE_WRITE_FDATA0;
    end

    STATE_WRITE_FDATA0: begin
      cmd_valid = 1'b1;
      cmd_write = 1'b1;
      data_in_valid = 1'b1;
      data_in = data0_reg;
      if (data_in_ready) state_next = STATE_WRITE_FDATA1;
    end

    STATE_WRITE_FDATA1: begin
      cmd_valid = 1'b1;
      cmd_write = 1'b1;
      data_in_valid = 1'b1;
      data_in = data1_reg;
      if (data_in_ready) state_next = STATE_WRITE_FDATA2;
    end

    STATE_WRITE_FDATA2: begin
      cmd_valid = 1'b1;
      cmd_write = 1'b1;
      data_in_valid = 1'b1;
      data_in = 'h00;
      if (data_in_ready) state_next = STATE_IDLE;
    end

  endcase
end


i2c_master i2c_master_i (
  .clk(clk),
  .rst(rst),
  /*
   * Host interface
   */
  .cmd_address(cmd_address),
  .cmd_start(cmd_start),
  .cmd_read(cmd_read),
  .cmd_write(cmd_write),
  .cmd_write_multiple(cmd_write_multiple),
  .cmd_stop(cmd_stop),
  .cmd_valid(cmd_valid),
  .cmd_ready(cmd_ready),

  .data_in(data_in),
  .data_in_valid(data_in_valid),
  .data_in_ready(data_in_ready),
  .data_in_last(data_in_last),

  .data_out(data_out),
  .data_out_valid(data_out_valid),
  .data_out_ready(data_out_ready),
  .data_out_last(data_out_last),

  // I2C
  .scl_i(scl_i),
  .scl_o(scl_o),
  .scl_t(scl_t),
  .sda_i(sda_i),
  .sda_o(sda_o),
  .sda_t(sda_t),

  // Status
  .busy(busy),
  .bus_control(),
  .bus_active(),
  .missed_ack(missed_ack),

  // Configuration
  .prescale(16'h0002),
  .stop_on_idle(1'b1)
);

endmodule

//-----------------------------------------------------------------------------
//                          old protocol RX recv
//-----------------------------------------------------------------------------

//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

//  Metis code copyright 2010, 2011, 2012, 2013, 2014, 2015 Phil Harman VK6(A)PH
// 2015 Steve Haynal KF7O

module Rx_recv (
	input rx_clk,
	output reg run,
	output reg wide_spectrum,
	output discovery_reply,
	input [15:0] to_port,
	input broadcast,
	input rx_valid,
	input [7:0] rx_data,
	output [7:0] rx_fifo_data,
	output reg rx_fifo_enable,
        input dst_unreachable
);

// Receive states
localparam	START = 3'h0,
			PREAMBLE1 = 3'h1,
			PREAMBLE2 = 3'h2,
			METIS_DISCOVERY = 3'h3,
			WRITEIP= 3'h4,
			RUN = 3'h5,
			SEND_TO_FIFO = 3'h6;

reg [2:0] rx_state;
reg [10:0] byte_cnt;

assign discovery_reply = (rx_state == METIS_DISCOVERY);

always @ (posedge rx_clk)						

case (rx_state)

START:
	begin
		rx_fifo_enable <= 1'b0;
		if (rx_valid && rx_data == 8'hef && to_port == 1024) rx_state <= PREAMBLE1;
                else if (dst_unreachable) begin
                   run <= 1'b0;
                   wide_spectrum <= 1'b0;
                   rx_state <= START;
                end
		else rx_state <= START;
	end

PREAMBLE1:
	begin
		if (rx_valid && rx_data == 8'hfe && to_port == 1024) rx_state <= PREAMBLE2;
		else rx_state <= START;
	end

// byte_cnt is 1 starting in PREAMBLE2
PREAMBLE2:
	begin
		if (rx_valid && rx_data == 8'h01) rx_state <= SEND_TO_FIFO;
		else if (rx_valid && rx_data == 8'h04) rx_state <= RUN;	
		else if (rx_valid && broadcast && rx_data == 8'h02) rx_state <= METIS_DISCOVERY;
		else if (rx_valid && broadcast && !run && rx_data == 8'h03) rx_state <= WRITEIP;
		else rx_state <= START;
	end

METIS_DISCOVERY:
	begin
		rx_state <= START;
	end

WRITEIP:
	begin
		rx_state <= START;
	end

RUN:
	begin
		run <= rx_data[0];
		wide_spectrum <= rx_data[1];
		rx_state <= START;
	end

SEND_TO_FIFO:
	begin
		if (byte_cnt == 11'h02 && rx_data != 8'h02) rx_state <= START;
		else if (byte_cnt == 11'h406) begin
			rx_fifo_enable <= 1'b0;
			rx_state <= START;
		// Wait until sequence numbers (3,4,5,6) are done as ignored in Hermes-Lite
		end else if (byte_cnt >= 11'h006) rx_fifo_enable <= 1'b1; 
	end

endcase

always @ (posedge rx_clk)
	if (rx_state == START) byte_cnt <= 11'h000;
	else byte_cnt <= byte_cnt + 11'h001;

// Add pipestage to match rx_fifo_enable
//always @ (posedge rx_clk) rx_fifo_data <= rx_data;
assign rx_fifo_data = rx_data;

endmodule

//-----------------------------------------------------------------------------
//                          old protocol TX send
//-----------------------------------------------------------------------------

//
//  HPSDR - High Performance Software Defined Radio
//
//  Metis code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

//  Metis code copyright 2010, 2011, 2012, 2013, 2014, 2015 Phil Harman VK6(A)PH
// 2015 Steve Haynal KF7O

module Tx_send (
	input tx_clock,
	input Tx_reset,
	input run,
	input wide_spectrum,
	input IP_valid,
	input [7:0] Hermes_serialno,
	input IDHermesLite,
	input  [8:0]AssignNR,

	input [7:0] PHY_Tx_data,
	input [10:0] PHY_Tx_rdused,
	output reg Tx_fifo_rdreq,

	input [47:0] This_MAC,
	input discovery,

	input [7:0] sp_fifo_rddata,
	input have_sp_data,
	output reg sp_fifo_rdreq,

	input udp_tx_enable,
	input udp_tx_active,
	output reg udp_tx_request,
	output [7:0] udp_tx_data,
	output reg [10:0] udp_tx_length
);


// HPSDR specific			
parameter HPSDR_frame = 8'h01;  	// HPSDR Frame type
parameter Type_1 = 8'hEF;	    	// Ethernet Frame type
parameter Type_2 = 8'hFE;

localparam
	START = 0,
	UDP1  = 1,
	UDP2  = 2,
	WIDE1 = 3,
	WIDE2 = 4,
	DISCOVER1 = 5,
	DISCOVER2 = 6;

reg [31:0] sequence_number = 0;
reg [31:0] spec_seq_number = 0;

reg [2:0] state;             	

reg [10:0] byte_no;

reg [7:0] tx_data;

assign udp_tx_data = tx_data;

wire [7:0] emuID [0:9];
assign emuID[0]  = IDHermesLite ? 8'h06 : 8'h01;
// emuID for SkimSrv / aka CW Skimmer HERMESLT
assign emuID[1]  = "H";
assign emuID[2]  = "E";
assign emuID[3]  = "R";
assign emuID[4]  = "M";
assign emuID[5]  = "E";
assign emuID[6]  = "S";
assign emuID[7]  = "L";
assign emuID[8]  = "T";
assign emuID[9]  = AssignNR;

always @ (posedge tx_clock)	
begin
case(state)

START:
	begin
		byte_no <= 11'd0;
		udp_tx_request <= 1'b0;
		udp_tx_length <= 11'd0;

		if (run == 1'b0) begin
			sequence_number <= 32'd0;  		// reset sequence numbers when not running.
			spec_seq_number <= 32'd0;
		end 
		if (discovery && IP_valid) begin		// only respond if we have a valid IP address
			udp_tx_request <= 1'b1;
			udp_tx_length <= 11'd60;
			state <= DISCOVER1;
		end 		
		else if (PHY_Tx_rdused > 11'd1023  && !Tx_reset && run) begin	// wait until we have at least 1024 bytes in Tx fifo													
			udp_tx_request <= 1'b1;
			udp_tx_length <= 11'd1032;
			state <= UDP1;
		end	
		else if (have_sp_data && wide_spectrum) begin		// Spectrum fifo has data available
			udp_tx_request <= 1'b1;
			udp_tx_length <= 11'd1032;
			state <= WIDE1;
		end
   end

// start sending UDP/IP data   
UDP1:
	begin
		udp_tx_request <= 1'b1;
		if (udp_tx_enable) begin
			tx_data <= Type_1;
			state <= UDP2;
		end
	end

UDP2:
	begin
		if (byte_no < 11'd1031) begin // Total-1 	
			if (udp_tx_active) begin
				case (byte_no)
					 11'd0: tx_data <= Type_2;					
					 11'd1: tx_data <= HPSDR_frame; 
					 11'd2: tx_data <= 8'h06;
					 11'd3: tx_data <= sequence_number[31:24];
					 11'd4: tx_data <= sequence_number[23:16];
					 11'd5: begin tx_data <= sequence_number[15:8]; Tx_fifo_rdreq <= 1'b1; end
					 11'd6: begin tx_data <= sequence_number[7:0]; Tx_fifo_rdreq <= 1'b1; end  	
					 11'd1029: begin Tx_fifo_rdreq <= 1'b0; tx_data <= PHY_Tx_data; end // Total-3
					 default: tx_data <= PHY_Tx_data;		 
				endcase				
				byte_no <= byte_no + 11'd1;
			end 
		end
		else begin
			sequence_number <= sequence_number + 1'b1;
			state <= START;
		end
	end

// start sending UDP/IP data   
WIDE1:
	begin
		udp_tx_request <= 1'b1;
		if (udp_tx_enable) begin
			tx_data <= Type_1;
			state <= WIDE2;
		end
	end

WIDE2:
	begin
		if (byte_no < 11'd1031) begin // Total-1 	
			if (udp_tx_active) begin
				case (byte_no)
					 11'd0: tx_data <= Type_2;					
					 11'd1: tx_data <= HPSDR_frame; 
					 11'd2: tx_data <= 8'h04;
					 11'd3: tx_data <= spec_seq_number[31:24];
					 11'd4: tx_data <= spec_seq_number[23:16];
					 11'd5: begin tx_data <= spec_seq_number[15:8]; sp_fifo_rdreq <= 1'b1; end
					 11'd6: begin tx_data <= spec_seq_number[7:0]; sp_fifo_rdreq <= 1'b1; end  	
					 11'd1029: begin sp_fifo_rdreq <= 1'b0; tx_data <= sp_fifo_rddata; end // Total-3
					 default: tx_data <= sp_fifo_rddata;		 
				endcase				
				byte_no <= byte_no + 11'd1;
			end 
		end
		else begin
			spec_seq_number <= spec_seq_number + 1'b1; 
			state <= START;
		end
	end

DISCOVER1:
	begin
		udp_tx_request <= 1'b1;
		if (udp_tx_enable) begin
			tx_data <= Type_1;
			state <= DISCOVER2;
		end
	end

DISCOVER2:
	begin
		if (byte_no < 11'd59) begin // Total-1
			if (udp_tx_active) begin
				case (byte_no)
					 11'd0: tx_data <= Type_2;					
					 11'd1: tx_data <= run ? 8'h03 : 8'h02;
					 11'd2: tx_data <= This_MAC[47:40];
					 11'd3: tx_data <= This_MAC[39:32];
					 11'd4: tx_data <= This_MAC[31:24];
					 11'd5: tx_data <= This_MAC[23:16];
					 11'd6: tx_data <= This_MAC[15:8];
					 11'd7: tx_data <= This_MAC[7:0];
					 11'd8: tx_data <= Hermes_serialno;
					 11'd9: tx_data <= emuID[0]; // IDHermesLite ? 8'h06 : 8'h01;
					 11'd10: tx_data <= emuID[1]; // "H"
					 11'd11: tx_data <= emuID[2]; // "E"
					 11'd12: tx_data <= emuID[3]; // "R"
					 11'd13: tx_data <= emuID[4]; // "M"
					 11'd14: tx_data <= emuID[5]; // "E"
					 11'd15: tx_data <= emuID[6]; // "S"
					 11'd16: tx_data <= emuID[7]; // "L"
					 11'd17: tx_data <= emuID[8]; // "T"
					 11'd18: tx_data <= emuID[9]; // NR
					 default: tx_data <= emuID[0];
				endcase				
				byte_no <= byte_no + 11'd1;
			end
		end
		else begin
			state <= START;
		end
	end
endcase
end

endmodule

// Altera IP blackboxes used in this design
(* blackbox *)
module altclkctrl
 #(parameter clock_type="auto",
  intended_device_family="unused",
  ena_register_mode="falling_edge",
  implement_in_les="off",
  number_of_clocks="4",
  use_glitch_free_switch_over_implementation="OFF",
  width_clkselect=2,
  lpm_type="altclkctrl",
  lpm_hint="unused")
 ( input wire [width_clkselect-1:0] clkselect,
   input wire ena,
   input wire [number_of_clocks-1:0] inclk,
   output wire outclk);

endmodule

module dcfifo_mixed_widths ( data, rdclk, wrclk, aclr, rdreq, wrreq,
                eccstatus, rdfull, wrfull, rdempty, wrempty, rdusedw, wrusedw, q);
    parameter lpm_width = 1;
    parameter lpm_widthu = 1;
    parameter lpm_width_r = lpm_width;
    parameter lpm_widthu_r = lpm_widthu;
    parameter lpm_numwords = 2;
    parameter delay_rdusedw = 1;
    parameter delay_wrusedw = 1;
    parameter rdsync_delaypipe = 0;
    parameter wrsync_delaypipe = 0;
    parameter intended_device_family = "Stratix";
    parameter lpm_showahead = "OFF";
    parameter underflow_checking = "ON";
    parameter overflow_checking = "ON";
    parameter clocks_are_synchronized = "FALSE";
    parameter use_eab = "ON";
    parameter add_ram_output_register = "OFF";
    parameter lpm_hint = "USE_EAB=ON";
    parameter lpm_type = "dcfifo_mixed_widths";
    parameter add_usedw_msb_bit = "OFF";
    parameter read_aclr_synch = "OFF";
    parameter write_aclr_synch = "OFF";
    parameter enable_ecc = "FALSE";
// INPUT PORT DECLARATION
    input [lpm_width-1:0] data;
    input rdclk;
    input wrclk;
    input aclr;
    input rdreq;
    input wrreq;

// OUTPUT PORT DECLARATION
    output rdfull;
    output wrfull;
    output rdempty;
    output wrempty;
    output [lpm_widthu_r-1:0] rdusedw;
    output [lpm_widthu-1:0] wrusedw;
    output [lpm_width_r-1:0] q;
    output [1:0] eccstatus;
endmodule

(* blackbox *)
module a_graycounter (clock, cnt_en, clk_en, updown, aclr, sclr,
                        q, qbin);
    parameter width  = 3;
    parameter pvalue = 0;
    parameter lpm_hint = "UNUSED";
    parameter lpm_type = "a_graycounter";
    input  clock;
    input  cnt_en;
    input  clk_en;
    input  updown;
    input  aclr;
    input  sclr;
    output [width-1:0] q;
    output [width-1:0] qbin;
endmodule

(* blackbox *)
module  cycloneive_asmiblock (
        dclkin,
        scein,
        oe,
        sdoin,
        data0out
        );

input dclkin;
input scein;
input oe;
input sdoin;
output data0out;

parameter lpm_type = "cycloneive_asmiblock";
parameter enable_sim = "false";
endmodule

(* blackbox *)
module lpm_compare (
    dataa,   // Value to be compared to datab[]. (Required)
    datab,   // Value to be compared to dataa[]. (Required)
    clock,   // Clock for pipelined usage.
    aclr,    // Asynchronous clear for pipelined usage.
    clken,   // Clock enable for pipelined usage.

    // One of the following ports must be present.
    alb,     // High (1) if dataa[] < datab[].
    aeb,     // High (1) if dataa[] == datab[].
    agb,     // High (1) if dataa[] > datab[].
    aleb,    // High (1) if dataa[] <= datab[].
    aneb,    // High (1) if dataa[] != datab[].
    ageb     // High (1) if dataa[] >= datab[].
);

// GLOBAL PARAMETER DECLARATION
    parameter lpm_width = 1;  // Width of the dataa[] and datab[] ports. (Required)
    parameter lpm_representation = "UNSIGNED";  // Type of comparison performed: 
                                                // "SIGNED", "UNSIGNED"
    parameter lpm_pipeline = 0; // Specifies the number of Clock cycles of latency
                                // associated with the alb, aeb, agb, ageb, aleb,
                                //  or aneb output.
    parameter lpm_type = "lpm_compare";
    parameter lpm_hint = "UNUSED";

// INPUT PORT DECLARATION   
    input  [lpm_width-1:0] dataa;
    input  [lpm_width-1:0] datab;
    input  clock;
    input  aclr;
    input  clken;

// OUTPUT PORT DECLARATION
    output alb;
    output aeb;
    output agb;
    output aleb;
    output aneb;
    output ageb;

endmodule

(* blackbox *)
module lpm_counter ( 
    clock,  // Positive-edge-triggered clock. (Required)
    clk_en, // Clock enable input. Enables all synchronous activities.
    cnt_en, // Count enable input. Disables the count when low (0) without 
            // affecting sload, sset, or sclr.
    updown, // Controls the direction of the count. High (1) = count up. 
            //                                      Low (0) = count down.
    aclr,   // Asynchronous clear input.
    aset,   // Asynchronous set input.
    aload,  // Asynchronous load input. Asynchronously loads the counter with
            // the value on the data input.
    sclr,   // Synchronous clear input. Clears the counter on the next active 
            // clock edge.
    sset,   // Synchronous set input. Sets the counter on the next active clock edge.
    sload,  // Synchronous load input. Loads the counter with data[] on the next
            // active clock edge.
    data,   // Parallel data input to the counter.
    cin,    // Carry-in to the low-order bit.
    q,      // Data output from the counter.
    cout,   // Carry-out of the MSB.
    eq      // Counter decode output. Active high when the counter reaches the specified
            // count value.
);

// GLOBAL PARAMETER DECLARATION
    parameter lpm_width = 1;    //The number of bits in the count, or the width of the q[]
                                // and data[] ports, if they are used. (Required)
    parameter lpm_direction = "UNUSED"; // Direction of the count.
    parameter lpm_modulus = 0;          // The maximum count, plus one.
    parameter lpm_avalue = "UNUSED";    // Constant value that is loaded when aset is high.
    parameter lpm_svalue = "UNUSED";    // Constant value that is loaded on the rising edge
                                        // of clock when sset is high.
    parameter lpm_pvalue = "UNUSED";
    parameter lpm_port_updown = "PORT_CONNECTIVITY";
    parameter lpm_type = "lpm_counter";
    parameter lpm_hint = "UNUSED";

// INPUT PORT DECLARATION
    input  clock; 
    input  clk_en;
    input  cnt_en;
    input  updown;
    input  aclr;
    input  aset;
    input  aload;
    input  sclr;
    input  sset;
    input  sload;
    input  [lpm_width-1:0] data;
    input  cin;

// OUTPUT PORT DECLARATION
    output [lpm_width-1:0] q;
    output cout;
    output [15:0] eq;
endmodule

(* blackbox *)
module scfifo ( data,
                clock,
                wrreq,
                rdreq,
                aclr,
                sclr,
                q,
                eccstatus,
                usedw,
                full,
                empty,
                almost_full,
                almost_empty);

// GLOBAL PARAMETER DECLARATION
    parameter lpm_width               = 1;
    parameter lpm_widthu              = 1;
    parameter lpm_numwords            = 2;
    parameter lpm_showahead           = "OFF";
    parameter lpm_type                = "scfifo";
    parameter lpm_hint                = "USE_EAB=ON";
    parameter intended_device_family  = "Stratix";
    parameter underflow_checking      = "ON";
    parameter overflow_checking       = "ON";
    parameter allow_rwcycle_when_full = "OFF";
    parameter use_eab                 = "ON";
    parameter add_ram_output_register = "OFF";
    parameter almost_full_value       = 0;
    parameter almost_empty_value      = 0;
    parameter maximum_depth           = 0;
    parameter enable_ecc              = "FALSE";

// LOCAL_PARAMETERS_BEGIN

    parameter showahead_area          = ((lpm_showahead == "ON")  && (add_ram_output_register == "OFF"));
    parameter showahead_speed         = ((lpm_showahead == "ON")  && (add_ram_output_register == "ON"));
    parameter legacy_speed            = ((lpm_showahead == "OFF") && (add_ram_output_register == "ON"));
    parameter ram_block_type = "AUTO";
    input  [lpm_width-1:0] data;
    input  clock;
    input  wrreq;
    input  rdreq;
    input  aclr;
    input  sclr;

// OUTPUT PORT DECLARATION
    output [lpm_width-1:0] q;
    output [lpm_widthu-1:0] usedw;
    output full;
    output empty;
    output almost_full;
    output almost_empty;
    output [1:0] eccstatus;
endmodule

(* blackbox *)
module  cycloneive_rublock
        (
        clk,
        shiftnld,
        captnupdt,
        regin,
        rsttimer,
        rconfig,
        regout
        );

        parameter sim_init_config = "factory";
        parameter sim_init_watchdog_value = 0;
        parameter sim_init_status = 0;
        parameter lpm_type = "cycloneive_rublock";

        input clk;
        input shiftnld;
        input captnupdt;
        input regin;
        input rsttimer;
        input rconfig;

        output regout;

endmodule

(* blackbox *)
module dcfifo ( data, rdclk, wrclk, aclr, rdreq, wrreq,
                eccstatus, rdfull, wrfull, rdempty, wrempty, rdusedw, wrusedw, q);

// GLOBAL PARAMETER DECLARATION
    parameter lpm_width = 1;
    parameter lpm_widthu = 1;
    parameter lpm_numwords = 2;
    parameter delay_rdusedw = 1;
    parameter delay_wrusedw = 1;
    parameter rdsync_delaypipe = 0;
    parameter wrsync_delaypipe = 0;
    parameter intended_device_family = "Stratix";
    parameter lpm_showahead = "OFF";
    parameter underflow_checking = "ON";
    parameter overflow_checking = "ON";
    parameter clocks_are_synchronized = "FALSE";
    parameter use_eab = "ON";
    parameter add_ram_output_register = "OFF";
    parameter lpm_hint = "USE_EAB=ON";
    parameter lpm_type = "dcfifo";
    parameter add_usedw_msb_bit = "OFF";
    parameter read_aclr_synch = "OFF";
    parameter write_aclr_synch = "OFF";
    parameter enable_ecc = "FALSE";

// LOCAL_PARAMETERS_BEGIN

    parameter add_width = 1;
    parameter ram_block_type = "AUTO";

// LOCAL_PARAMETERS_END

// INPUT PORT DECLARATION
    input [lpm_width-1:0] data;
    input rdclk;
    input wrclk;
    input aclr;
    input rdreq;
    input wrreq;
    output rdfull;
    output wrfull;
    output rdempty;
    output wrempty;
    output [lpm_widthu-1:0] rdusedw;
    output [lpm_widthu-1:0] wrusedw;
    output [lpm_width-1:0] q;
    output [1:0] eccstatus;
endmodule

