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
    # IO.puts("WRITE_REG #{inspect(addr, base: :hex)} #{inspect(value, base: :hex)}")
    rf24 = select(rf24)
    # {:ok, status} = spi_transfer(rf24.spi, <<0b001::3, addr::5>>)
    # {:ok, return} = spi_transfer(rf24.spi, value)

    # status = _SPI.transfer(W_REGISTER | (REGISTER_MASK & reg));
    reg = instr(:W_REGISTER) ||| (instr(:REGISTER_MASK) &&& addr)
    {:ok, status} = spi_transfer(rf24.spi, <<reg::8>>)
    {:ok, return} = spi_transfer(rf24.spi, value)
    IO.inspect(status, label: "[#{inspect(addr, base: :hex)}] WRITE STATUS")
    IO.inspect(return, label: "[#{inspect(addr, base: :hex)}] WRITE RETURN")
    unselect(rf24)
  end

  def enable_ack_payload(rf24) do
    <<_::5, _en_dpl::1, _en_ack_pay::1, en_dy_ack::1>> = read_reg_bin(rf24, :FEATURE)

    rf24
    |> write_reg(:FEATURE, <<0::5, 1::1, 1::1, en_dy_ack::1>>)
    |> write_reg(:DYNPD, <<0::2, 0b111111::6>>)
  end

  def enable_dynamic_payloads(rf24) do
    <<_::5, _en_dpl::1, en_ack_pay::1, en_dy_ack::1>> = read_reg_bin(rf24, :FEATURE)

    rf24
    |> write_reg(:FEATURE, <<0::5, 1::1, en_ack_pay::1, en_dy_ack::1>>)
    |> write_reg(:DYNPD, <<0::2, 0b111111::6>>)
  end

  def open_writing_pipe(rf24, address) when byte_size(address) in [3, 4, 5] do
    Logger.info("Opening writing pipe to #{inspect(address, base: :hex)}")

    rf24
    |> set_address_width(byte_size(address))
    |> write_reg(:RX_ADDR_P0, address)
    |> write_reg(:TX_ADDR, address)
    |> write_reg(:RX_PW_P0, rf24.payload_size)
  end

  def close_reading_pipe(rf24, child)
      when child in [:RX_ADDR_P0, :RX_ADDR_P1, :RX_ADDR_P2, :RX_ADDR_P3, :RX_ADDR_P4, :RX_ADDR_P5] do
    Logger.info("Closing writing pipe #{inspect(child)}")
    rf24
  end

  def open_reading_pipe(rf24, child, address)
      when child in [:RX_ADDR_P0, :RX_ADDR_P1, :RX_ADDR_P2, :RX_ADDR_P3, :RX_ADDR_P4, :RX_ADDR_P5] do
    Logger.info(
      "Opening reading pipe #{inspect(child)} with address: #{inspect(address, base: :hex)}"
    )

    # // If this is pipe 0, cache the address.  This is needed because
    # // openWritingPipe() will overwrite the pipe 0 address, so
    # // startListening() will have to restore it.
    rf24 =
      if child == :RX_ADDR_P0 do
        %{rf24 | pipe0_reading_address: address}
      else
        rf24
      end

    rf24
    |> write_reg(child, address)
    # :RX_ADDR_PX => RX_PW_PX are 7 addresses appart.
    |> write_reg(reg(child) + 7, rf24.payload_size)
    # enable RX on all pipes
    |> write_reg(:EN_RXADDR, <<0b00111111::8>>)

    # case read_reg(rf24, :EN_RXADDR) do
    # end

    # if child < 2 do
    #   # write_register(pgm_read_byte(&child_pipe[child]), reinterpret_cast<const uint8_t*>(&address), addr_width);
    #   write_reg()
    # else

    # end
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
    # {:ok, status} = spi_transfer(rf24.spi, <<0b000::3, addr::5>>)
    # {:ok, value} = spi_transfer(rf24.spi, <<0xff::8>>)

    # _SPI.transfer(R_REGISTER | (REGISTER_MASK & reg));
    # result = _SPI.transfer(0xff);
    reg = instr(:R_REGISTER) ||| (instr(:REGISTER_MASK) &&& addr)
    {:ok, status} = spi_transfer(rf24.spi, <<reg::8>>)
    {:ok, value} = spi_transfer(rf24.spi, <<0xFF::8>>)

    IO.inspect(status, label: "[#{inspect(addr, base: :hex)}] READ STATUS")
    IO.inspect(value, label: "[#{inspect(addr, base: :hex)}] READ VALUE")

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

  def read_payload(rf24) do
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<instr(:R_RX_PAYLOAD)>>)
    {:ok, payload} = spi_transfer(rf24.spi, <<0xFF::32>>)
    unselect(rf24)
    payload
  end

  def reset_status(rf24) do
    # write_register(NRF_STATUS, _BV(RX_DR) | _BV(MAX_RT) | _BV(TX_DS));
    <<_::1, _rx_dr::1, _tx_ds::1, _max_rt::1, pipe::3, tx_full::1>> =
      read_reg_bin(rf24, :NRF_STATUS)

    write_reg(rf24, :NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)
  end

  def set_retries(rf24, delay, count) when delay <= 15 and count <= 15 do
    # write_reg(SETUP_RETR, (delay & 0xf) << ARD | (count & 0xf) << ARC);
    write_reg(rf24, :SETUP_RETR, <<delay::4, count::4>>)
  end

  def set_channel(rf24, channel) when channel <= 125 do
    write_reg(rf24, :RF_CH, channel)
  end

  def get_channel(rf24) do
    read_reg(rf24, :RF_CH)
  end

  def set_data_rate(rf24, data_rate) do
    <<cont_wave::1, _::1, _rf_dr_low::1, pll_lock::1, _rf_dr_high::1, rf_pwr::2, _::1>> =
      read_reg_bin(rf24, :RF_SETUP)

    case data_rate do
      :RF24_250KBPS ->
        value = <<cont_wave::1, 0::1, 1::1, pll_lock::1, 0::1, rf_pwr::2, 0::1>>
        write_reg(%{rf24 | p_variant: true}, :RF_SETUP, value)

      :RF24_2MBPS ->
        value = <<cont_wave::1, 0::1, 0::1, pll_lock::1, 1::1, rf_pwr::2, 0::1>>
        write_reg(rf24, :RF_SETUP, value)

      :RF24_1MBPS ->
        value = <<cont_wave::1, 0::1, 0::1, pll_lock::1, 0::1, rf_pwr::2, 0::1>>
        write_reg(rf24, :RF_SETUP, value)
    end
  end

  def enable_ptx(rf24) do
    <<_::1, mask_rx_dr::1, mask_tx_ds::1, mask_max_rt::1, en_crc::1, crco::1, pwr_up::1,
      _prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)

    write_reg(
      rf24,
      :NRF_CONFIG,
      <<0::1, mask_rx_dr::1, mask_tx_ds::1, mask_max_rt::1, en_crc::1, crco::1, pwr_up::1, 0::1>>
    )
  end

  def enable_prx(rf24) do
    <<_::1, mask_rx_dr::1, mask_tx_ds::1, mask_max_rt::1, en_crc::1, crco::1, pwr_up::1,
      _prim_rx::1>> = read_reg_bin(rf24, :NRF_CONFIG)

    write_reg(
      rf24,
      :NRF_CONFIG,
      <<0::1, mask_rx_dr::1, mask_tx_ds::1, mask_max_rt::1, en_crc::1, crco::1, pwr_up::1, 1::1>>
    )
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

  def power_up(rf24) do
    case read_reg_bin(rf24, :NRF_CONFIG) do
      # bit 1 is high
      <<_::1, mask_rx_dr::1, mask_tx_ds::1, mask_max_rt::1, en_crc::1, crco::1, 0::1, prim_rx::1>> ->
        write_reg(
          rf24,
          :NRF_CONFIG,
          <<0::1, mask_rx_dr::1, mask_tx_ds::1, mask_max_rt::1, en_crc::1, crco::1, 1::1,
            prim_rx::1>>
        )

      <<_::1, _mask_rx_dr::1, _mask_tx_ds::1, _mask_max_rt::1, _en_crc::1, _crco::1, 1::1,
        _prim_rx::1>> ->
        rf24
    end
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
