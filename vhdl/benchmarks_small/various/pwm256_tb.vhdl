-- Testbench for PWM256 - a 256 level PWM generator
-- Author: Niels Moseley
--         Symbiotic EDA / Moseley Instruments
-- 10-11-2018
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.all;

entity pwm256_tb is
end pwm256_tb;

architecture tb of pwm256_tb is
    signal clk  : std_logic := '0';
    signal rst_n: std_logic := '1';
    signal d_in : unsigned(7 downto 0) := "00000000";
    signal pwm  : std_logic;

    signal do_sim : std_logic := '1';
begin

    u_dut: entity work.pwm256
        port map
        (
            clk    => clk,
            rst_n  => rst_n,
            d_in   => d_in,
            pwm_out=> pwm
        );

    proc_sim: process
    begin
        d_in <= to_unsigned(128,8);
        rst_n <= '0';
        wait for 4 ns;
        rst_n <= '1';
        wait for 2*256 ns;
        d_in <= to_unsigned(10,8);
        wait for 2*256 ns;
        d_in <= to_unsigned(246,8);
        wait for 2*256 ns;
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