defmodule RF24.Util do
  alias Circuits.{
    SPI,
    GPIO
  }

  use Bitwise

  import RF24Registers

  @doc """
  Write a register.

  `addr` can be an atom found in RF24Registers.reg/1 or an uint8 value.
  `value` can be a uint8 or a binary
  """
  def write_reg(rf24, addr, value) when is_atom(addr) do
    write_reg(rf24, reg(addr), value)
  end

  def write_reg(rf24, addr, value) when value <= 255 do
    write_reg(rf24, addr, <<value::8>>)
  end

  def write_reg(rf24, addr, value) when addr <= 31 and is_binary(value) do
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b001::3, addr::5>>)
    {:ok, _return} = spi_transfer(rf24.spi, value)
    unselect(rf24)
  end

  @doc "Reads a value in a register. Takes the same addr values as write_reg"
  def read_reg(rf24, addr) do
    <<value>> = read_reg_bin(rf24, addr)
    value
  end

  @doc "Same as read_reg but returns the binary value"
  def read_reg_bin(rf24, addr) when is_atom(addr) do
    read_reg_bin(rf24, reg(addr))
  end

  def read_reg_bin(rf24, addr) when addr <= 31 do
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b000::3, addr::5>>)
    {:ok, value} = spi_transfer(rf24.spi, <<0xFF::8>>)
    unselect(rf24)
    value
  end

  @doc "Reads the SETUP_AW register and returns the value in bits"
  def read_addr_width(rf24) do
    case read_reg_bin(rf24, :SETUP_AW) do
      <<_::5, 0::3>> -> raise("invalid address width?")
      # 3 bytes 24 bits
      <<_::5, 0b01::3>> -> 24
      # 4 bytes 32 bits
      <<_::5, 0b10::3>> -> 32
      # 5 bytes 40 bits
      <<_::5, 0b11::3>> -> 40
    end
  end

  @doc "Writes the address width. width must be one of 3, 4, or 5"
  def write_address_width(rf24, 3) do
    write_reg(rf24, :SETUP_AW, <<0::6, 0b01::2>>)
  end

  def write_address_width(rf24, 4) do
    write_reg(rf24, :SETUP_AW, <<0::6, 0b10::2>>)
  end

  def write_address_width(rf24, 5) do
    write_reg(rf24, :SETUP_AW, <<0::6, 0b11::2>>)
  end

  def write_rx_pipe_addr(rf24, pipe, addr) when pipe <= 5 and byte_size(addr) in [3, 4, 5] do
    reg =
      case pipe do
        0x0 -> :RX_ADDR_P0
        0x1 -> :RX_ADDR_P1
        0x2 -> :RX_ADDR_P2
        0x3 -> :RX_ADDR_P3
        0x4 -> :RX_ADDR_P4
        0x5 -> :RX_ADDR_P5
      end

    write_rx_pipe_addr(rf24, reg, addr)
  end

  def write_rx_pipe_addr(rf24, pipe, addr) when is_atom(pipe) and byte_size(addr) in [3, 4, 5] do
    rf24
    |> write_address_width(byte_size(addr))
    |> write_reg(pipe, addr)
  end

  @doc "Wrapper around read_reg to set the rx addr on a pipe"
  def read_rx_pipe_addr(rf24, pipe) when pipe <= 5 do
    reg =
      case pipe do
        0x0 -> :RX_ADDR_P0
        0x1 -> :RX_ADDR_P1
        0x2 -> :RX_ADDR_P2
        0x3 -> :RX_ADDR_P3
        0x4 -> :RX_ADDR_P4
        0x5 -> :RX_ADDR_P5
      end

    read_rx_pipe_addr(rf24, reg)
  end

  def read_rx_pipe_addr(rf24, pipe) when pipe in [:RX_ADDR_P0, :RX_ADDR_P1] do
    addr_width = read_addr_width(rf24)
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b000::3, reg(pipe)::5>>)
    {:ok, value} = spi_transfer(rf24.spi, <<0xFF::size(addr_width)>>)
    unselect(rf24)
    value
  end

  def read_rx_pipe_addr(rf24, pipe)
      when pipe in [:RX_ADDR_P2, :RX_ADDR_P3, :RX_ADDR_P4, :RX_ADDR_P5] do
    addr_width = read_addr_width(rf24)
    base_width = addr_width - 8
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b000::3, reg(:RX_ADDR_P1)::5>>)
    {:ok, <<base::size(base_width), _::8>>} = spi_transfer(rf24.spi, <<0xFF::size(addr_width)>>)
    unselect(rf24)
    <<addr::8>> = read_reg_bin(rf24, pipe)
    <<base::size(base_width), addr::8>>
  end

  @doc "Wrapper around write_reg to set the tx addr"
  def write_tx_addr(rf24, address) when byte_size(address) in [3, 4, 5] do
    rf24 = write_address_width(rf24, byte_size(address))
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b001::3, reg(:TX_ADDR)::5>>)
    {:ok, _} = spi_transfer(rf24.spi, address)
    unselect(rf24)
  end

  @doc "Wrapper around read_reg to get the tx addr"
  def read_tx_addr(rf24) do
    adress_width = read_addr_width(rf24)
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b000::3, reg(:TX_ADDR)::5>>)
    {:ok, value} = spi_transfer(rf24.spi, <<0xFF::size(adress_width)>>)
    unselect(rf24)
    value
  end

  @doc "Reads the length of the data in the R_RX_PAYLOAD register"
  def read_payload_length(rf24) do
    select(rf24)
    {:ok, <<_, length>>} = spi_transfer(rf24.spi, <<0b01100000, 0xFF>>)
    unselect(rf24)
    length
  end

  @doc "Reads `length` payload from the :R_RX_PAYLOAD"
  def read_payload(rf24, length) do
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<instr(:R_RX_PAYLOAD)>>)
    {:ok, payload} = spi_transfer(rf24.spi, :binary.copy(<<0xFF>>, length))
    unselect(rf24)
    payload
  end

  @doc """
  Set SETUP_RETR register. 
  Will write the values stored in state if not supplied explicitly.
  """
  def write_retries(%{} = rf24) do
    write_retries(rf24, rf24.auto_retransmit_delay, rf24.auto_retransmit_count)
  end

  def write_retries(rf24, delay, count) when delay <= 15 and count <= 15 do
    # write_reg(SETUP_RETR, (delay & 0xf) << ARD | (count & 0xf) << ARC);
    write_reg(
      %{rf24 | auto_retransmit_delay: delay, auto_retransmit_count: count},
      :SETUP_RETR,
      <<delay::4, count::4>>
    )
  end

  @doc "Sets the RF_CH register. `channel` must be <= 125"
  def write_channel(rf24) do
    write_channel(rf24, rf24.channel)
  end

  def write_channel(rf24, channel) when channel <= 125 do
    write_reg(%{rf24 | channel: channel}, :RF_CH, channel)
  end

  @doc """
  Sets the datarate.
  channel must be one of 

      :RF24_250KBPS, :RF24_1MBPS, :RF24_2MBPS
  """
  def write_data_rate(rf24) do
    write_data_rate(rf24, rf24.data_rate)
  end

  def write_data_rate(rf24, data_rate)
      when data_rate in [:RF24_250KBPS, :RF24_1MBPS, :RF24_2MBPS] do
    <<cont_wave::1, _::1, _rf_dr_low::1, pll_lock::1, _rf_dr_high::1, rf_pwr::2, _::1>> =
      read_reg_bin(rf24, :RF_SETUP)

    case data_rate do
      :RF24_250KBPS ->
        value = <<cont_wave::1, 0::1, 1::1, pll_lock::1, 0::1, rf_pwr::2, 0::1>>
        write_reg(%{rf24 | data_rate: :RF24_250KBPS}, :RF_SETUP, value)

      :RF24_2MBPS ->
        value = <<cont_wave::1, 0::1, 0::1, pll_lock::1, 1::1, rf_pwr::2, 0::1>>
        write_reg(%{rf24 | data_rate: :RF24_2MBPS}, :RF_SETUP, value)

      :RF24_1MBPS ->
        value = <<cont_wave::1, 0::1, 0::1, pll_lock::1, 0::1, rf_pwr::2, 0::1>>
        write_reg(%{rf24 | data_rate: :RF24_1MBPS}, :RF_SETUP, value)
    end
  end

  @doc "Configures crc enabled and crc encoding"
  def write_crc(rf24) do
    <<_::4, _en_crc::1, _crco::1, pwr_up::1, prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)
    crc? = if rf24.crc?, do: 1, else: 0
    crc_2_bit? = if rf24.crc_2_bit?, do: 1, else: 0
    write_reg(rf24, :NRF_CONFIG, <<0::4, crc?::1, crc_2_bit?::1, pwr_up::1, prim_rx::1>>)
  end

  @doc """
  Enter transmit mode. 
  Packets will not be sent until there is a pulse on the CE pin
  """
  def enable_ptx(rf24) do
    # unset bit 0 on NRF_CONFIG
    <<head::7, _prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)
    write_reg(rf24, :NRF_CONFIG, <<head::7, 0::1>>)
  end

  @doc """
  Enter receive mode.
  Packets will not be received until there is a pulse on the CE pin
  """
  def enable_prx(rf24) do
    # set bit 0 on NRF_CONFIG
    <<head::7, _prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)
    write_reg(rf24, :NRF_CONFIG, <<head::7, 1::1>>)
  end

  @doc """
  unsets the `PWR_UP` bit on the CONFIG register if it is set.
  """
  def power_up(rf24) do
    # unsets bit 1 on NRF_CONFIG if it is high
    case read_reg_bin(rf24, :NRF_CONFIG) do
      # bit 1 is high
      <<head::6, 0::1, prim_rx::1>> ->
        write_reg(rf24, :NRF_CONFIG, <<head::6, 1::1, prim_rx::1>>)

      # bit 1 is already low
      <<_head::6, 1::1, _prim_rx::1>> ->
        rf24
    end
  end

  @doc "drop the RX fifo"
  def flush_rx(rf24) do
    rf24 = select(rf24)
    {:ok, _} = spi_transfer(rf24.spi, <<instr(:FLUSH_RX)>>)
    unselect(rf24)
  end

  @doc "drop the TX fifo"
  def flush_tx(rf24) do
    rf24 = select(rf24)
    {:ok, _} = spi_transfer(rf24.spi, <<instr(:FLUSH_TX)>>)
    unselect(rf24)
  end

  @doc """
  Send a payload.
  if ack? is true, the W_ACK_PAYLOAD instruction is used,
  else the W_TX_PAYLOAD is used. 
  User is responsible for ensuring the correct flags are set
  in the FEATURE register
  """
  def send_payload(rf24, payload, ack?)

  def send_payload(rf24, payload, true) when byte_size(payload) <= 32 do
    send_payload(rf24, payload, 0b10100000)
  end

  def send_payload(rf24, payload, false) when byte_size(payload) <= 32 do
    send_payload(rf24, payload, 0b10110000)
  end

  def send_payload(rf24, payload, instr) do
    rf24 = enable_ptx(rf24)
    rf24 = select(rf24)
    {:ok, status} = spi_transfer(rf24.spi, <<instr>>)
    {:ok, _} = spi_transfer(rf24.spi, payload)
    unselect(rf24)

    gpio_write(rf24.ce, 0)

    Process.sleep(10)
    gpio_write(rf24.ce, 1)

    status
  end

  @doc "Write an ack packet for a pipe"
  def send_ack_payload(rf24, pipe, payload) when byte_size(payload) <= 32 do
    rf24 = enable_ptx(rf24)

    rf24 = select(rf24)
    {:ok, _} = spi_transfer(rf24.spi, <<0b10101::5, pipe::3>>)
    {:ok, _} = spi_transfer(rf24.spi, payload)

    gpio_write(rf24.ce, 0)
    Process.sleep(10)
    gpio_write(rf24.ce, 1)

    unselect(rf24)
  end

  # this register is undocumented. Stuff doesn't work without it tho.
  # i have no idea what it is
  @doc false
  def toggle_features(rf24) do
    rf24 = select(rf24)
    {:ok, _} = spi_transfer(rf24.spi, <<instr(:ACTIVATE), 0x73::8>>)
    unselect(rf24)
  end

  @doc false
  def select(rf24) do
    gpio_write(rf24.csn, 0)
    rf24
  end

  @doc false
  def unselect(rf24) do
    gpio_write(rf24.csn, 1)
    rf24
  end

  @doc false
  def gpio_open(pin, mode, opts \\ []) do
    GPIO.open(pin, mode, opts)
  end

  @doc false
  def gpio_write(gpio, value) do
    GPIO.write(gpio, value)
  end

  @doc false
  def gpio_set_interrupts(gpio, mode) do
    GPIO.set_interrupts(gpio, mode)
  end

  @doc false
  def spi_open(bus, opts) do
    SPI.open(bus, opts)
  end

  @doc false
  def spi_transfer(spi, data) do
    SPI.transfer(spi, data)
  end

  @doc "Initialize the radio. Doesn't actually check for success."
  def radio_init(rf24) do
    with {:ok, ce} <- gpio_open(rf24.ce_pin, :output, initial_value: 0),
         {:ok, csn} <- gpio_open(rf24.csn_pin, :output, initial_value: 1),
         {:ok, irq} <- gpio_open(rf24.irq_pin, :input),
         :ok <- gpio_set_interrupts(irq, :falling),
         {:ok, spi} <- spi_open(rf24.spi_bus_name, mode: 0, speed_hz: 10_000_000) do
      %{rf24 | ce: ce, csn: csn, irq: irq, spi: spi}
    end
  end
end
