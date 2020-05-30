defmodule RF24 do
  import RF24.Util

  # defmodule Address do
  #   defstruct [
  #     auto_ack?: false,
  #     index: 0,
  #     address: <<255,0xFC,0xE1,0xA8,0xA8>>
  #   ]
  # end

  defstruct csn: nil,
            ce: nil,
            irq: nil,
            tx: nil,
            rx: nil,
            spi: nil,
            ce_pin: 87,
            csn_pin: 23,
            irq_pin: 89,
            spi_bus_name: "spidev1.0",
            channel: 76,
            crc?: true,
            crc_2_bit?: true,
            auto_retransmit_delay: 5,
            auto_retransmit_count: 15,
            data_rate: :RF24_1MBPS

  # data_rate: :RF24_2MBPS
  # data_rate: :RF24_250KBPS

  use GenServer

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def open_reading_pipe(pid, child, addr)
      when byte_size(addr) in [3, 4, 5] and
             child in [
               :RX_ADDR_P0,
               :RX_ADDR_P1,
               :RX_ADDR_P2,
               :RX_ADDR_P3,
               :RX_ADDR_P4,
               :RX_ADDR_P5
             ] do
  end

  def open_writing_pipe(pid, addr) when byte_size(addr) in [3, 4, 5] do
  end

  def radio_init(rf24) do
    with {:ok, ce} <- gpio_open(rf24.ce_pin, :output, initial_value: 0),
         {:ok, csn} <- gpio_open(rf24.csn_pin, :output, initial_value: 1),
         {:ok, irq} <- gpio_open(rf24.irq_pin, :input),
         :ok <- gpio_set_interrupts(irq, :falling),
         {:ok, spi} <- spi_open(rf24.spi_bus_name, mode: 0, speed_hz: 10_000_000) do
      %{rf24 | ce: ce, csn: csn, irq: irq, spi: spi}
    end
  end

  def init(args) do
    send(self(), :init)
    {:ok, struct(RF24, args)}
  end

  def handle_info(:init, rf24) do
    with %RF24{} = rf24 <- radio_init(rf24) do
      send(self(), :reset)
      {:noreply, rf24}
    else
      error ->
        {:stop, error, rf24}
    end
  end

  def handle_info(:reset, rf24) do
    gpio_write(rf24.ce, 0)
    gpio_write(rf24.csn, 1)

    Process.sleep(50)

    rf24 =
      rf24
      # |> write_reg(:FEATURE, 0)
      # |> write_reg(:DYNPD, 0)
      # |> write_reg(:EN_AA, 0)
      |> write_reg(:FEATURE, 0b00000111)
      |> write_reg(:DYNPD, 0b00111111)
      |> write_reg(:EN_AA, 0b00111111)
      |> write_reg(:EN_RXADDR, 0)
      |> write_reg(:RX_ADDR_P0, <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>)
      |> write_reg(:RX_ADDR_P1, <<0xC2, 0xC2, 0xC2, 0xC2, 0xC2>>)
      |> write_reg(:RX_ADDR_P2, 0xC3)
      |> write_reg(:RX_ADDR_P3, 0xC4)
      |> write_reg(:RX_ADDR_P4, 0xC5)
      |> write_reg(:RX_ADDR_P5, 0xC6)
      |> write_reg(:TX_ADDR, <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>)
      |> set_crc()
      |> set_retries()
      |> set_data_rate()
      |> set_channel()
      |> flush_rx()
      |> flush_tx()
      |> power_up()
      |> enable_ptx()

    setup = read_reg(rf24, :RF_SETUP)

    if setup != 0x0 && setup != 0xFF do
      send(self(), :start_listening)
      {:noreply, rf24}
    else
      {:stop, {:reset_failure, setup}, rf24}
    end
  end

  def handle_info(:start_listening, rf24) do
    rf24 =
      rf24
      |> write_reg(:EN_RXADDR, <<0b00111111::8>>)
      |> power_up()
      |> enable_prx()

    gpio_write(rf24.ce, 1)
    {:noreply, rf24}
  end

  def handle_info({:circuits_gpio, _pin, _ts, _}, rf24) do
    IO.puts("interupt")
    rf24 =
      case read_reg_bin(rf24, :NRF_STATUS) do
        <<_::1, 1::1, tx::1, max_retry::1, pipe::3, tx_full::1>> ->
          write_reg(rf24, :NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)
          length = read_payload_length(rf24)
          payload = read_payload(rf24, length)

          IO.inspect(length, label: "length")
          IO.inspect(payload, label: "PAYLOAD from pipe: #{pipe}")

          rf24
        unk ->
          IO.inspect(unk, label: "unknown")
          rf24
      end

    {:noreply, rf24}
  end
end
