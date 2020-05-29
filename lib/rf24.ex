defmodule RF24 do
  import RF24.Util

  defstruct csn: nil,
            ce: nil,
            irq: nil,
            tx: nil,
            rx: nil,
            spi: nil,
            ce_pin: 87,
            # csn_pin: 5,
            csn_pin: 23,
            irq_pin: 89,
            spi_bus_name: "spidev1.0",
            p_variant: false,
            dynamic_payloads_enabled: nil,
            payload_size: 32,
            pipe0_reading_address: nil

  use GenServer

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    send(self(), :init)
    {:ok, struct(RF24, args)}
  end

  def radio_init(rf24) do
    with {:ok, ce} <- gpio_open(rf24.ce_pin, :output, initial_value: 0),
         {:ok, csn} <- gpio_open(rf24.csn_pin, :output, initial_value: 1),
         {:ok, irq} <- gpio_open(rf24.irq_pin, :input),
         :ok <- gpio_set_interrupts(irq, :both),
         {:ok, spi} <- spi_open(rf24.spi_bus_name, mode: 0, speed_hz: 10_000_000) do
      %{rf24 | ce: ce, csn: csn, irq: irq, spi: spi}
    end
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
    # gpio_write(rf24.ce, 1)
    gpio_write(rf24.ce, 0)
    gpio_write(rf24.csn, 1)

    Process.sleep(50)
    rf24 = write_reg(rf24, :NRF_CONFIG, 0x0C)

    rf24 =
      rf24
      |> set_retries(5, 15)
      |> set_data_rate(:RF24_250KBPS)

    setup = read_reg(rf24, :RF_SETUP)

    rf24 =
      rf24
      |> set_data_rate(:RF24_1MBPS)
      |> toggle_features()
      |> write_reg(:FEATURE, 0)
      |> write_reg(:DYNPD, 0)
      |> Map.put(:dynamic_payloads_enabled, false)
      |> write_reg(:NRF_STATUS, <<0b01110000::8>>)
      |> set_channel(76)
      |> flush_rx()
      |> flush_tx()
      |> power_up()
      |> enable_ptx()
      |> enable_ack_payload()
      |> enable_dynamic_payloads()

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
      |> open_writing_pipe(<<0xCE, 0xCC, 0xCE, 0xCC, 0xCE>>)
      |> open_reading_pipe(:RX_ADDR_P1, <<0xCC, 0xCE, 0xCC, 0xCE, 0xCC>>)
      |> power_up()
      |> enable_prx()

    gpio_write(rf24.ce, 1)

    # Restore the pipe0 adddress, if exists
    rf24 =
      if rf24.pipe0_reading_address do
        write_reg(rf24, :RX_ADDR_P0, rf24.pipe0_reading_address)
      else
        close_reading_pipe(rf24, :RX_ADDR_P0)
      end

    case read_reg_bin(rf24, :FEATURE) do
      # check for en_ack_pay being set
      <<_::5, _en_dpl::1, 1::1, _en_dy_ack::1>> ->
        rf24 = flush_tx(rf24)
        {:noreply, rf24}

      _ ->
        {:noreply, rf24}
    end

    {:noreply, rf24}
  end

  def handle_info({:circuits_gpio, _pin, _ts, _} = interupt, rf24) do
    IO.puts("interupt: #{inspect(interupt)}")
    %{rx_dr: rx} = status = read_status(rf24)
    IO.inspect(status, label: "status")

    # if tx do
    # end

    # if fail do
    # end

    if rx do
      payload = read_payload(rf24)
      IO.inspect(payload, label: "PAYLOAD")
      rf24 = reset_status(rf24)
      {:noreply, rf24}
    else
      {:noreply, rf24}
    end
  end
end
