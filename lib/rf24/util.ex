defmodule RF24.Util do
  alias Circuits.{
    SPI,
    GPIO
  }

  import RF24Registers

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
    write_reg(rf24, reg(addr), value)
  end

  def write_reg(rf24, addr, value) when value <= 255 do
    write_reg(rf24, addr, <<value::8>>)
  end

  def write_reg(rf24, addr, value) when addr <= 31 and is_binary(value) do
    IO.puts("WRITE_REG #{inspect(addr, base: :hex)} #{inspect(value, base: :hex)}")
    rf24 = select(rf24)
    {:ok, _status} = spi_transfer(rf24.spi, <<0b001::3, addr::5>>)
    {:ok, _} = spi_transfer(rf24.spi, value)
    unselect(rf24)
  end

  def enable_ack_payload(rf24) do
    <<_::5, _en_dpl::1, _en_ack_pay::1, en_dy_ack::1>> = read_reg_bin(rf24, :FEATURE)

    rf24
    |> write_reg(:FEATURE, <<0::5, 1::1, 1::1, en_dy_ack::1>>)
    |> write_reg(:DYNPD, <<0::2, 0b11111111::6>>)
  end

  def enable_dynamic_payloads(rf24) do
    <<_::5, _en_dpl::1, en_ack_pay::1, en_dy_ack::1>> = read_reg_bin(rf24, :FEATURE)

    rf24
    |> write_reg(:FEATURE, <<0::5, 1::1, en_ack_pay::1, en_dy_ack::1>>)
    |> write_reg(:DYNPD, <<0::2, 0b11111111::6>>)
  end

  def open_writing_pipe(rf24, address) when byte_size(address) in [3, 4, 5] do
    rf24
    |> set_address_width(byte_size(address))
    |> write_reg(:RX_ADDR_P0, address)
    |> write_reg(:TX_ADDR, address)
    |> write_reg(:RX_PW_P0, 32)
  end

  def open_reading_pipe(rf24, num, address) do
    rf24
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
    read_reg_bin(rf24, reg(addr))
  end

  def read_reg_bin(rf24, addr) when addr <= 31 do
    rf24 = select(rf24)
    {:ok, value} = spi_transfer(rf24.spi, <<0b000::3, addr::5>>)
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
