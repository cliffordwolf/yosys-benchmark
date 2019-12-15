-- PWM256 - a 256 level PWM generator
-- Author: Niels Moseley
--         Symbiotic EDA / Moseley Instruments
-- 10-11-2018
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm256 is
    port
    (
        clk     : in std_logic;
        rst_n   : in  std_logic;
        d_in    : in unsigned(7 downto 0);
        pwm_out : out std_logic
    );
end pwm256;

architecture rtl of pwm256 is
    signal counter : unsigned(7 downto 0);
begin

    proc_clk: process(clk)
    begin
        if (rising_edge(clk)) then
            if (rst_n = '0') then
                counter <= (others => '0');
            else
                counter <= counter + 1;
            end if;
        end if;

        if (counter <= d_in) then
            pwm_out <= '1';
        else
            pwm_out <= '0';
        end if;
    end process proc_clk;

end rtl;
