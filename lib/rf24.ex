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

  # power: :PWR_18DBM

  # '00' –  -18dBm
  # '01' –  -12dBm
  # '10' –  -6dBm
  # '11' –    0dBm

  # data_rate: :RF24_2MBPS
  # data_rate: :RF24_250KBPS

  use GenServer

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def send(pid, payload, ack?) do
    GenServer.call(pid, {:send, payload, ack?})
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

  def handle_call({:send, payload, ack?}, _, rf24) do
    reply = send_payload(rf24, payload, ack?)
    {:reply, reply, rf24}
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
      |> toggle_features()
      |> write_reg(:EN_AA, 0)
      |> write_reg(:FEATURE, 0b00000110)
      |> write_reg(:DYNPD, 0b00111111)
      # |> write_reg(:EN_AA, 0b00111111)
      |> write_reg(:EN_RXADDR, 0)
      # |> write_reg(:RX_ADDR_P0, <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>)
      # |> write_reg(:TX_ADDR, <<0xCE,0xCC,0xCE,0xCC,0xCE>>)
      |> write_reg(:TX_ADDR, <<0xCE, 0xCC, 0xCE, 0xCC, 0xCE>>)
      |> write_reg(:RX_ADDR_P0, <<0xCE, 0xCC, 0xCE, 0xCC, 0xCE>>)
      |> write_reg(:RX_ADDR_P1, <<0xCE, 0xCC, 0xCE, 0xCC, 0xCE>>)
      |> write_reg(:RX_ADDR_P2, 0xC3)
      |> write_reg(:RX_ADDR_P3, 0xC4)
      |> write_reg(:RX_ADDR_P4, 0xC5)
      |> write_reg(:RX_ADDR_P5, 0xC6)
      |> write_reg(:RX_PW_P0, 32)
      |> write_reg(:RX_PW_P1, 32)
      |> write_reg(:RX_PW_P2, 32)
      |> write_reg(:RX_PW_P3, 32)
      |> write_reg(:RX_PW_P4, 32)
      |> write_reg(:RX_PW_P5, 32)
      |> set_crc()
      |> set_retries()
      |> set_data_rate()
      |> set_channel()
      |> flush_rx()
      |> flush_tx()
      # |> set_power()
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
        <<_::1, 1::1, _tx::1, _max_retry::1, pipe::3, tx_full::1>> ->
          write_reg(rf24, :NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)
          length = read_payload_length(rf24)
          payload = read_payload(rf24, length)

          send_ack_payload(rf24, 1, payload)
          IO.inspect(payload, label: "PAYLOAD from pipe: #{pipe}")

          rf24

        <<_::1, _::1, 1::1, _max_retry::1, pipe::3, tx_full::1>> ->
          IO.puts("packet sent")
          # gpio_write(rf24.ce, 1)
          write_reg(rf24, :NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)
          enable_prx(rf24)

        unk ->
          IO.inspect(unk, label: "UNKNOWN!!!", base: :binary)
          rf24
      end

    {:noreply, rf24}
  end
end
