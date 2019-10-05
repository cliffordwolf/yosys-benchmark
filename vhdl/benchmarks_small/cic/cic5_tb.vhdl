-- Testbench for cic5 - a 5th order CIC filter decimating 5x.
-- Author: Niels Moseley
--         Symbiotic EDA / Moseley Instruments
-- 12-11-2018
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.all;

entity cic5_tb is
end cic5_tb;

architecture tb of cic5_tb is
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '1';
    signal d_in         : signed(15 downto 0) := X"0000";
    signal d_out        : signed(27 downto 0) := X"0000000";
    signal d_out_valid  : std_logic := '0';

    signal do_sim : std_logic := '1';
begin

    u_dut: entity work.cic5
        port map
        (
            clk    => clk,
            rst_n  => rst_n,
            d_in   => d_in,
            d_out  => d_out,
            d_out_valid => d_out_valid
        );

    proc_sim: process
    begin
        d_in <= X"7FFF";
        rst_n <= '0';
        wait for 4 ns;
        rst_n <= '1';
        wait for 2*5*6 ns;
        -- after 5*6 clocks and 7FFF as input, the
        -- CIC filter's output must be stable.
        -- given that the gain is 3125x, the output
        -- should be 102396875.
        assert (d_out = to_signed(102396875, d_out'length)) report "CIC5 filter output not correct" severity error;
        do_sim <= '0';
        wait;
    end process proc_sim;

    proc_clk: process
    begin
        if (do_sim = '1') then
            clk <= not clk;
            wait for 1 ns;
        else
            wait;
        end if;
    end process proc_clk;

end tb;