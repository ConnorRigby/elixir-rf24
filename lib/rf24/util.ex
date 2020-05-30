defmodule RF24.Util do
  alias Circuits.{
    SPI,
    GPIO
  }

  use Bitwise

  import RF24Registers
  require Logger

  def gpio_open(pin, mode, opts \\ []) do
    GPIO.open(pin, mode, opts)
  end

  def gpio_write(gpio, value) do
    GPIO.write(gpio, value)
  end

  def gpio_set_interrupts(gpio, mode) do
    GPIO.set_interrupts(gpio, mode)
  end

  def spi_open(bus, opts) do
    SPI.open(bus, opts)
  end

  def spi_transfer(spi, data) do
    SPI.transfer(spi, data)
  end

  def write_reg(rf24, addr, value) when is_atom(addr) do
    Logger.info("Write addr #{addr} #{inspect(value, base: :hex)}")
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

  # def open_writing_pipe(rf24, address) when byte_size(address) in [3, 4, 5] do
  #   Logger.info("Opening writing pipe to #{inspect(address, base: :hex)}")

  #   rf24
  #   |> set_address_width(byte_size(address))
  #   |> write_reg(:RX_ADDR_P0, address)
  #   |> write_reg(:TX_ADDR, address)
  #   |> write_reg(:RX_PW_P0, rf24.payload_size)
  # end

  # def open_reading_pipe(rf24, child, address)
  #     when child in [:RX_ADDR_P0, :RX_ADDR_P1, :RX_ADDR_P2, :RX_ADDR_P3, :RX_ADDR_P4, :RX_ADDR_P5] do
  #   Logger.info(
  #     "Opening reading pipe #{inspect(child)} with address: #{inspect(address, base: :hex)}"
  #   )

  #   rf24
  #   |> write_reg(child, address)
  #   # :RX_ADDR_PX => RX_PW_PX are 7 addresses appart.
  #   |> write_reg(reg(child) + 7, rf24.payload_size)
  #   # enable RX on all pipes
  #   |> write_reg(:EN_RXADDR, <<0b00111111::8>>)
  # end

  def read_tx_addr(rf24) do
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b000::3, reg(:TX_ADDR)::5>>)
    {:ok, value} = spi_transfer(rf24.spi, <<0xFF::40>>)
    unselect(rf24)
    value
  end

  def read_reg(rf24, addr) do
    <<value>> = read_reg_bin(rf24, addr)
    value
  end

  def read_reg_bin(rf24, addr) when is_atom(addr) do
    Logger.info("READ register #{addr}")
    read_reg_bin(rf24, reg(addr))
  end

  def read_reg_bin(rf24, addr) when addr <= 31 do
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b000::3, addr::5>>)
    {:ok, value} = spi_transfer(rf24.spi, <<0xFF::8>>)
    unselect(rf24)
    value
  end

  def read_status(rf24) do
    <<_::1, rx_dr::1, tx_ds::1, max_rt::1, pipe::3, tx_full::1>> = read_reg_bin(rf24, :NRF_STATUS)
    write_reg(rf24, :NRF_STATUS, <<0::1, 0::1, 0::1, 0::1, pipe::3, tx_full::1>>)

    %{
      rx_dr: rx_dr == 1,
      tx_ds: tx_ds == 1,
      max_rt: max_rt == 1,
      pipe: pipe,
      tx_full: tx_full == 1
    }
  end

  def set_address_width(rf24, 3) do
    write_reg(rf24, :SETUP_AW, <<0::6, 0b01::2>>)
  end

  def set_address_width(rf24, 4) do
    write_reg(rf24, :SETUP_AW, <<0::6, 0b10::2>>)
  end

  def set_address_width(rf24, 5) do
    write_reg(rf24, :SETUP_AW, <<0::6, 0b11::2>>)
  end

  def read_payload_length(rf24) do
    select(rf24)
    {:ok, <<_, length>>} = spi_transfer(rf24.spi, <<0b01100000, 0xFF>>)
    unselect(rf24)
    length
  end

  def read_payload(rf24, length) do
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<instr(:R_RX_PAYLOAD)>>)
    {:ok, payload} = spi_transfer(rf24.spi, :binary.copy(<<0xFF>>, length))
    unselect(rf24)
    payload
  end

  def reset_status(rf24) do
    # write_register(NRF_STATUS, _BV(RX_DR) | _BV(MAX_RT) | _BV(TX_DS));
    <<_::1, _rx_dr::1, _tx_ds::1, _max_rt::1, pipe::3, tx_full::1>> =
      read_reg_bin(rf24, :NRF_STATUS)

    write_reg(rf24, :NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)
  end

  def set_retries(%{} = rf24) do
    set_retries(rf24, rf24.auto_retransmit_delay, rf24.auto_retransmit_count)
  end

  def set_retries(rf24, delay, count) when delay <= 15 and count <= 15 do
    # write_reg(SETUP_RETR, (delay & 0xf) << ARD | (count & 0xf) << ARC);
    write_reg(
      %{rf24 | auto_retransmit_delay: delay, auto_retransmit_count: count},
      :SETUP_RETR,
      <<delay::4, count::4>>
    )
  end

  def set_channel(rf24) do
    set_channel(rf24, rf24.channel)
  end

  def set_channel(rf24, channel) when channel <= 125 do
    write_reg(%{rf24 | channel: channel}, :RF_CH, channel)
  end

  def set_data_rate(rf24) do
    set_data_rate(rf24, rf24.data_rate)
  end

  def set_data_rate(rf24, data_rate)
      when data_rate in [:RF24_250KBPS, :RF24_1MBPS, :RF24_2MBPS] do
    <<cont_wave::1, _::1, _rf_dr_low::1, pll_lock::1, _rf_dr_high::1, rf_pwr::2, 0::1>> =
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
  def set_crc(rf24) do
    <<_::4, _en_crc::1, _crco::1, pwr_up::1, prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)
    crc? = if rf24.crc?, do: 1, else: 0
    crc_2_bit? = if rf24.crc_2_bit?, do: 1, else: 0
    write_reg(rf24, :NRF_CONFIG, <<0::4, crc?::1, crc_2_bit?::1, pwr_up::1, prim_rx::1>>)
  end

  # unset bit 0 on NRF_CONFIG
  def enable_ptx(rf24) do
    <<head::7, _prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)
    write_reg(rf24, :NRF_CONFIG, <<head::7, 0::1>>)
  end

  # set bit 0 on NRF_CONFIG
  def enable_prx(rf24) do
    <<head::7, _prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)
    write_reg(rf24, :NRF_CONFIG, <<head::7, 1::1>>)
  end

  # unset bit 1 on NRF_CONFIG if it is high
  def power_up(rf24) do
    case read_reg_bin(rf24, :NRF_CONFIG) do
      # bit 1 is high
      <<head::6, 0::1, prim_rx::1>> ->
        write_reg(rf24, :NRF_CONFIG, <<head::6, 1::1, prim_rx::1>>)

      # bit 1 is already low
      <<_head::6, 1::1, _prim_rx::1>> ->
        rf24
    end
  end

  def toggle_features(rf24) do
    rf24 = select(rf24)
    {:ok, _} = spi_transfer(rf24.spi, <<instr(:ACTIVATE), 0x73::8>>)
    unselect(rf24)
  end

  def flush_rx(rf24) do
    rf24 = select(rf24)
    {:ok, _} = spi_transfer(rf24.spi, <<instr(:FLUSH_RX)>>)
    unselect(rf24)
  end

  def flush_tx(rf24) do
    rf24 = select(rf24)
    {:ok, _} = spi_transfer(rf24.spi, <<instr(:FLUSH_TX)>>)
    unselect(rf24)
  end

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

  def select(rf24) do
    gpio_write(rf24.csn, 0)
    rf24
  end

  def unselect(rf24) do
    gpio_write(rf24.csn, 1)
    rf24
  end
end
