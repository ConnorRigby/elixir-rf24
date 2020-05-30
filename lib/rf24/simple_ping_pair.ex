defmodule RF24.SimplePingPair do
  @moduledoc """
  Sample receiver process that will log
  all received packets via Elixir's Logger.

  This can be considered a complement to
  [this arduino example](https://github.com/nRF24/RF24/blob/master/examples/pingpair_irq_simple/pingpair_irq_simple.ino)
  """

  use GenServer
  require Logger

  @doc "args are passed directly to RF24"
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def send_ping(packet \\ <<111::little-8>>) do
    GenServer.cast(__MODULE__, {:send_ping, packet})
  end

  @impl GenServer
  def init(args) do
    {:ok, pid} = RF24.start_link(args)

    address = <<0xCE, 0xCC, 0xCE, 0xCC, 0xCE>>
    # have to delay here to wait for the radio to settle
    Process.send_after(self(), {:change_tx_address, address}, 3000)
    Process.send_after(self(), {:change_rx0_address, address}, 3000)

    {:ok, %{rf24: pid}}
  end

  @impl GenServer
  def handle_cast({:send_ping, packet}, state) do
    RF24.send(state.rf24, packet, true)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:change_tx_address, addr}, state) do
    Logger.info("Setting TX address=#{inspect(addr, base: :hex)}")
    RF24.set_tx_address(state.rf24, addr)
    {:noreply, state}
  end

  def handle_info({:change_rx0_address, addr}, state) do
    Logger.info("Setting RX0 address=#{inspect(addr, base: :hex)}")
    RF24.set_rx_pipe_address(state.rf24, 0, addr)
    {:noreply, state}
  end

  def handle_info({RF24, {:packet_received, 1, <<111::little-8>>}}, state) do
    Logger.info("Received PING. Sending PONG")
    RF24.send(state.rf24, <<222::little-8>>, true)
    {:noreply, state}
  end

  def handle_info({RF24, {:packet_received, 1, <<222::little-8>>}}, state) do
    Logger.info("Received PONG.")
    {:noreply, state}
  end

  def handle_info({RF24, {:packet_received, pipe, payload}}, state) do
    Logger.info("unknown packet received on pipe ##{pipe}: #{inspect(payload, pretty: true)}")
    {:noreply, state}
  end

  def handle_info({RF24, {:packet_sent, _pipe}}, state) do
    Logger.info("packet sent")
    {:noreply, state}
  end

  def handle_info({RF24, {:packet_error, pipe}}, state) do
    Logger.error("packet failed to send on pipe ##{pipe}")
    {:noreply, state}
  end
end
