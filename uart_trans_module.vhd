library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity uart_trans_module is 
generic (sys_clk   : integer := 100000000;                              --100 MHz system clock
         baud_rate : integer := 19200;                                  -- Baud rates: 1200,2400,4800,19200,38400,57600,115200.
         os_rate   : integer := 8;                                      -- over sampling.
         d_width   : integer := 8;                                      -- data width.
         parity    : integer := 1;                                      -- 1 -> parity / 0 -> no parity.
         parity_eo : std_logic := '0');                                 -- 0 -> even / 1 -> odd.
Port    (tx : out std_logic;
         rx : in std_logic;
----------------------------------------------------------------
         clk, reset : in std_logic;
         tx_en      : in std_logic;                                     --to enable module to read data at its input register.
         tx_data    : in std_logic_vector (d_width-1 downto 0);
         tx_busy    : out std_logic;                                    --after data is clucted in input buffer, this signal is set to indicate any new tx data will be ignored.
         rx_data    : out std_logic_vector (d_width-1 downto 0);        --rx_data received.
         rx_error   : out std_logic;                                    --will be set using the parity check.
         rx_busy    : out std_logic );                                  --notification needed bec. it can receive data anytime.
end uart_trans_module;

architecture Behavioral of uart_trans_module is
--SYSTEM SIGNALS
signal tx_buffer : std_logic_vector (d_width-1 downto 0); 
signal rx_buffer : std_logic_vector (d_width downto 0);         --including parity bit.
signal baud_count , os_count : integer := 0;
signal baud_sig , os_sig : std_logic;
--TX RELATED SIGNALS
constant tx_idle : std_logic_vector(1 downto 0) := "00";
constant tx_send : std_logic_vector(1 downto 0) := "01";
signal tx_state  : std_logic_vector(1 downto 0) := tx_idle;
signal tx_data_count : integer:= 0;
signal tx_parity : std_logic;
--RX RELATED SIGNALS
constant rx_idle : std_logic_vector(1 downto 0) := "00";
constant check_rx_start : std_logic_vector(1 downto 0) := "01";
constant rx_receive : std_logic_vector(1 downto 0) := "10";
constant rx_check_parity : std_logic_vector(1 downto 0) := "11";
signal rx_state  : std_logic_vector(1 downto 0) := rx_idle;
signal rx_os_count, rx_data_count, rx_data_1_count, rx_parity_count: integer := 0;
signal xor_bit : std_logic; 
signal rx_parity_bit : std_logic_vector (d_width downto 0);

begin

clocking_circuitry: Process(clk,reset) begin
    if reset = '1' then
        -- do reset procedure
        baud_count <= 0;
        os_count <= 0;
        baud_sig<= '0';
        os_sig<= '0';
    else
        if rising_edge(clk) then
            if baud_count < sys_clk/ baud_rate - 1 then
                baud_count <= baud_count + 1;
                baud_sig<= '0';
            else
                baud_count <= 0;
                baud_sig<= '1';             --baud_sig won't stay 'high' for more than one System clock cycle./otherwise error may occure in tx.   
            end if;    
            
            if os_count < (sys_clk/ baud_rate)/os_rate - 1 then
                os_count <= os_count + 1;
                os_sig<= '0';
            else
                os_count <= 0;
                os_sig<= '1';        
            end if;
        end if;    
    end if;
end process;

TX_circuitry: Process(baud_sig, clk, reset) begin
    if reset = '1' then
        --reset procedure
        tx <= '1';
        tx_state <= tx_idle;
    else
        if rising_edge(clk) then
            case tx_state is
                when tx_idle =>
                    if tx_en = '1' then
                        tx_buffer <= tx_data;
                        tx_state <= tx_send;
                    end if;
                    tx <= '1';
                    tx_busy <= '0'; 
                when tx_send =>
                    tx_busy <= '1';
                    if baud_sig = '1' then
                        if tx_data_count < d_width then
                            tx <= tx_buffer(tx_data_count);
                            tx_data_count <= tx_data_count + 1;
                            tx_state <= tx_send;
                        else     
                            --send parity bit if set otherwise return to idle.
                            if parity = 1 and tx_data_count = d_width then
                                --tx <= tx_buffer(d_width);
                                tx <= tx_parity;
                                tx_state <= tx_send;
                                tx_data_count <= tx_data_count + 1; 
                            else
                                tx_state <= tx_idle;  
                                tx_data_count <= 0;  
                            end if;     
                        end if;    
                    end if;    
                when others => tx_state <= tx_idle;    
            end case;    
        end if;        
    end if;
end process;

RX_circuitry: Process(reset,clk) begin
    if reset = '1' then
        --reset procedure
        rx_os_count <= 0;
        rx_state <= rx_idle;
        rx_busy <= '0';
        rx_data_count <= 0;
        rx_error <= '0';
        rx_parity_count <= 0;
    else
        if rising_edge(clk) then
            case rx_state is
                when rx_idle =>
                    rx_busy <= '0';
                    if rx = '0' and rx_os_count = 0 then    --mark the start of data.
                        rx_state <= check_rx_start; 
                    else
                        rx_state <= rx_idle;           
                    end if;
                    
                when check_rx_start =>
                    if os_sig = '1' then
                        if rx_os_count < os_rate and rx = '0' then
                            rx_os_count <= rx_os_count + 1;
                            rx_state <= check_rx_start;
                        else 
                            rx_state <= rx_idle;
                            rx_os_count <= 0;            
                        end if;
                    end if;
                    
                    if rx_os_count >= os_rate  then
                        rx_state <= rx_receive; 
                        rx_os_count <= 0;      
                    end if;
                    
                when rx_receive =>
                    rx_error <= '0';
                    rx_busy <= '1';
                    if rx_os_count < os_rate and os_sig = '1' then
                        rx_os_count <= rx_os_count + 1;
                        rx_state <= rx_receive;
                        if rx = '1' then
                            rx_data_1_count <= rx_data_1_count + 1;
                        end if;      
                    end if;
                    
                    if rx_os_count = os_rate then
                        if rx_data_1_count >= os_rate/2 then
                            rx_buffer <= '1' & rx_buffer(d_width downto 1);
                        else
                            rx_buffer <= '0' & rx_buffer(d_width downto 1);    
                        end if;    
                        rx_os_count <= 0; 
                        rx_data_1_count <= 0;
                        rx_data_count <= rx_data_count + 1;              
                    end if;
                    
                    if rx_data_count = d_width+1  then
                        rx_data_count <= 0;
                        rx_data <= rx_buffer(d_width-1 downto 0);
                        rx_state <= rx_check_parity;
                        rx_parity_bit(0) <= rx_buffer(0);
                    end if;   
                             
                when rx_check_parity =>
                    if parity = 1 then
                            if rx_parity_count < d_width then
                                rx_parity_bit(rx_parity_count+1) <= rx_parity_bit(rx_parity_count) xor rx_buffer(rx_parity_count+1);
                                rx_state <= rx_check_parity;
                                rx_parity_count <= rx_parity_count + 1;  
                            else
                                if rx_parity_bit(d_width) /= parity_eo then
                                    rx_error <= '1';
                                end if;   
                                rx_state <= rx_idle;
                                rx_parity_count <=0;    
                            end if;     
                     end if;    
                when others => rx_state <= rx_idle;
            end case;
        end if;
    end if;
end process;

--PARITY PROCEDURE (TRANSMITTER)
tx_parity_gen_and_check:process (reset,clk) 
variable data_count : integer range 0 to d_width + 1 := 0;
begin
    if reset = '1' then
        --reset procedure
            data_count := 0;
            tx_parity <= '0';
        else
            if rising_edge(clk) then
                if tx_state = tx_send then      --it is guaranteed that the parity will be calculated before the state transition as the sys clock is very high compared to baudrate.
                    if data_count < d_width  then
                        tx_parity <= tx_parity xor tx_buffer(data_count);
                        data_count := data_count + 1; 
                    else
                        tx_parity <= tx_parity xor parity_eo;       
                    end if; 
                else
                    tx_parity <= '0';        
                end if;  
            end if;
    end if;        
end process;

end Behavioral;
