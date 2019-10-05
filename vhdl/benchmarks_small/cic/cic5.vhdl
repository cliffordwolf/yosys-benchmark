-- cic5 - a 5th order CIC decimation filter
--        with 5x decimation factor
--
-- Author: Niels Moseley
--         Symbiotic EDA / Moseley Instruments
-- 12-11-2018
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cic5 is
    port
    (
        clk         : in std_logic;
        rst_n       : in std_logic;
        d_in        : in signed(15 downto 0);
        d_out       : out signed(27 downto 0);
        d_out_valid : out std_logic     -- high for one clock cycle
    );
end cic5;

architecture rtl of cic5 is
    signal decimation_cnt : unsigned(2 downto 0);

    type state5_t is array(1 to 5) of signed(27 downto 0);

    signal int_s   : state5_t;    -- integrator states
    signal comb_s  : state5_t;
begin

    proc_clk: process(clk)
        variable tmp : state5_t;
    begin
        if (rising_edge(clk)) then
            if (rst_n = '0') then
                -- reset all integrator states
                for I in 1 to 5 loop
                    int_s(I)  <= (others => '0');
                    comb_s(I) <= (others => '0');
                end loop;

                decimation_cnt <= (others => '0');
                d_out          <= (others => '0');
                d_out_valid    <= '0';
            else
                -- default updates when clocked
                decimation_cnt <= decimation_cnt + 1;
                d_out_valid    <= '0';

                -- calculate new integrator states
                int_s(1) <= int_s(1) + resize(d_in, int_s(1)'length);
                for I in 2 to 5 loop
                    int_s(I) <= int_s(I) + int_s(I-1);
                end loop;

                -- check if we can output new data at the
                -- reduced rate
                if (decimation_cnt = to_unsigned(4,decimation_cnt'length)) then
                    decimation_cnt <= to_unsigned(0, decimation_cnt'length);
                    
                    -- calculate the CIC comb filters at the lower rate
                    -- and update their filter states
                    tmp(1)    := int_s(5) - comb_s(1);  -- calculate comb #1 output
                    comb_s(1) <= int_s(5);              -- update comb #1 filter state
                    for I in 2 to 5 loop
                        tmp(I)    := tmp(I-1) - comb_s(I);
                        comb_s(I) <= tmp(I-1);
                    end loop;

                    -- output a signal!
                    d_out <= tmp(5);
                    d_out_valid <= '1';
                end if;
            end if;
        end if;
    end process proc_clk;

end rtl;
