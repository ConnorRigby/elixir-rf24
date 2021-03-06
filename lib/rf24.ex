defmodule RF24 do
  @moduledoc """
  RF24 radio Interface.

  # Basic Usage

      iex(1)> {:ok, pid} = RF24.start_link()
      {:ok, #PID<0.1933.0>}
      # cause a remote device to send a few packets..
      iex(2)> flush()
      {RF24, 1, "Hello, world! x1"}
      {RF24, 1, "Hello, world! x2"}
      {RF24, 1, "Hello, world! x3"}
      iex(3)> RF24.send(pid, "Welcome to the world of radio!", true)
      <<14>>
      iex(4)>
  """

  import RF24.Util

  @derive {Inspect,
           only: [
             :channel,
             :crc,
             :crc_2_bit,
             :auto_retransmit_delay,
             :auto_retransmit_count,
             :data_rate
           ]}

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
            receiver_pid: nil,
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

  @doc """
  Start a radio connection. `args` is a list or map of configuration.
  See below for the available options.

  # Wiring configuration

    * `ce_pin` - GPIO pin number. (default=87)
    * `csn_pin` - GPIO pin number. (default=23)
    * `irq_pin` - GPIO pin number. (default=89)
    * `spi_bus_name` - SPI bus name. (default=spidev1.0)

  # Radio configuration

    * `channel` - Frequency for the radio to receive and transmit on. Must be between 0 and 125. (default=76)
    * `crc?` - Enable hardware level CRC checking. (default=true)
    * `crc_2_bit?` - Enable 2 bit CRC checking. (requires `crc?` to be true) (default: true)
    * `auto_retransmit_delay` - (uint8) milliseconds to wait before retransmitting a failed packet
    * `auto_retransmit_count` - (uint8) number of retries before considering a packet failed. 
    * `data_rate`  - `:RF24_250KBPS`, `:RF24_1MBPS`, or `:RF24_2MBPS`
  """
  def start_link(args \\ [], opts \\ []) do
    args = put_in(args, [:receiver_pid], self())
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  send a packet.
  Payload must be a binary with a size of no more than 32 bytes.
  Returns the contents of the status register
  """
  def send(pid, payload, ack?) when byte_size(payload) <= 32 and is_boolean(ack?) do
    GenServer.call(pid, {:send, payload, ack?})
  end

  @doc """
  Sets a reading address. 
    * `pipe` is the index of the pipe you want to change. 
    * `addr` is a 1, 3, 4, or 5 byte binary address.

  # Addressing Rules

  Only pipe 0 and pipe 1 will take the full address.
  Pipes 2-5 only take one single byte. The first part of the address will be the
  same as pipe 1. Examples:

  this works

      RF24.Set_rx_pipe_address(pid, 0, <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>)
      RF24.Set_rx_pipe_address(pid, 1, <<0xC2, 0xC2, 0xC2, 0xC2, 0xC2>>)

  this will throw an Argument error because address 2-5 only take suffix to
  whatever is in address 1

      RF24.Set_rx_pipe_address(pid, 2, <<0xC3, 0xC3, 0xC3, 0xC3, 0xC3>>)

  To set the address on pipe 2 do:

      RF24.Set_rx_pipe_address(pid, 1, <<0xC2, 0xC2, 0xC2, 0xC2, 0xC2>>)
      RF24.Set_rx_pipe_address(pid, 2, <<0xC3>>)

  The address of pipe 2 will now be: 

      <<0xC2, 0xC2, 0xC2, 0xC2, 0xC3>>

  # Width rules

  Pipes and addresses all share the same width. (3, 4, or 5 bytes wide). This includes the 
  tx address. This function will set the global width according to width of the address
  provided. This means that setting the `rx_pipe_address` for pipes 0 or 1 to a different
  width will change the address values of pipes 2-5 and will also change the address
  of the tx address. This library defaults to 5 bit address and it is suggested that
  users keep this width. 
  """
  def set_rx_pipe_address(pid, pipe, addr) when byte_size(addr) in [3, 4, 5] and pipe in [0, 1] do
    GenServer.call(pid, {:set_rx_pipe_address, pipe, addr})
  end

  def set_rx_pipe_address(pid, pipe, <<_::8>> = addr) when pipe in [2, 3, 4, 5] do
    GenServer.call(pid, {:set_rx_pipe_address, pipe, addr})
  end

  def set_rx_pipe_address(_pid, pipe, addr) when is_integer(pipe) and is_binary(addr) do
    raise ArgumentError, """
    Invalid address #{inspect(addr, base: :hex)} for pipe: #{pipe}.
    See the documentation for acceptable pipe and address combinations
    """
  end

  @doc """
  Returns the entire address. This means that pipes 2, 3, 4, and 5 will return 
  the comple address, including the base stored in address 1.

  If you only want the single byte of those registers, you can extract it like this:

      <<base::binary-4, address::binary-1>> = RF24.get_rx_pipe_address(pid, pipe)
  """
  def get_rx_pipe_address(pid, pipe) when pipe <= 5 do
    GenServer.call(pid, {:get_rx_pipe_address, pipe})
  end

  @doc """
  Sets the transmit address. The same rules apply as 
  set_rx_address on pipes 0 and 1.
  """
  def set_tx_address(pid, addr) when byte_size(addr) in [3, 4, 5] do
    GenServer.call(pid, {:set_tx_address, addr})
  end

  @doc """
  Returns the tx address
  """
  def get_tx_address(pid) do
    GenServer.call(pid, :get_tx_address)
  end

  @doc """
  Public, but discouraged function. Reads a register.
  Calling this function incorrectly will result in
  the GenServer crashing by design.
  """
  def read_register(pid, reg) do
    GenServer.call(pid, {:read_register, reg})
  end

  @doc """
  Public, but discouraged function. Writes a register.
  Calling this function incorrectly will result in
  the GenServer crashing by design.
  """
  def write_register(pid, reg, value) do
    GenServer.call(pid, {:write_register, reg, value})
  end

  @impl GenServer
  def init(args) do
    send(self(), :init)
    {:ok, struct(RF24, args)}
  end

  @impl GenServer
  def handle_call({:send, payload, ack?}, _, rf24) do
    status = send_payload(rf24, payload, ack?)
    {:reply, status, rf24}
  end

  def handle_call({:set_rx_pipe_address, pipe, addr}, _from, rf24) do
    rf24 = write_rx_pipe_addr(rf24, pipe, addr)
    {:reply, :ok, rf24}
  end

  def handle_call({:get_rx_pipe_address, pipe}, _from, rf24) do
    addr = read_rx_pipe_addr(rf24, pipe)
    {:reply, addr, rf24}
  end

  def handle_call({:set_tx_address, addr}, _from, rf24) do
    rf24 = write_tx_addr(rf24, addr)
    {:reply, :ok, rf24}
  end

  def handle_call(:get_tx_address, _from, rf24) do
    addr = read_tx_addr(rf24)
    {:reply, addr, rf24}
  end

  def handle_call({:read_register, addr}, _from, rf24) do
    value = read_reg_bin(rf24, addr)
    {:reply, value, rf24}
  end

  def handle_call({:write_register, addr, value}, _from, rf24) do
    rf24 = write_reg(rf24, addr, value)
    {:reply, :ok, rf24}
  end

  @impl GenServer
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
      |> write_reg(:TX_ADDR, <<0xCE, 0xCC, 0xCE, 0xCC, 0xCE>>)
      |> write_reg(:RX_ADDR_P0, <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>)
      |> write_reg(:TX_ADDR, <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>)
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
      |> write_crc()
      |> write_retries()
      |> write_data_rate()
      |> write_channel()
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
    handle_interupt(rf24)
  end

  # When an interupt happens, 
  # one of three possible bits will be set.
  # bit 6 = RX complete
  # bit 5 = TX complete
  # bit 4 = max retries (TX failed)
  def handle_interupt(rf24) do
    case read_reg_bin(rf24, :NRF_STATUS) do
      <<_::1, 1::1, _tx::1, _max_retry::1, pipe::3, tx_full::1>> ->
        handle_rx_interupt(rf24, pipe, tx_full)

      <<_::1, _::1, 1::1, _max_retry::1, pipe::3, tx_full::1>> ->
        handle_tx_interupt(rf24, pipe, tx_full)

      <<_::1, _::1, _::1, 1::1, pipe::3, tx_full::1>> ->
        handle_err_interupt(rf24, pipe, tx_full)
    end
  end

  def handle_rx_interupt(rf24, pipe, tx_full) do
    rf24 = write_reg(rf24, :NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)

    # check FEATURE.EN_DPL
    # if it's set, we can get the full packet
    # If FEATURE.EN_DPL is not set, the user will need to retrieve the packet
    case read_reg_bin(rf24, :FEATURE) do
      # EN_DPL is enabled
      <<_::5, 1::1, _en_ack_pay::1, _en_dyn_ack::1>> ->
        # retreive the packet
        length = read_payload_length(rf24)
        payload = read_payload(rf24, length)
        # IO.inspect(payload, label: "PAYLOAD from pipe: #{pipe}")
        send(rf24.receiver_pid, {__MODULE__, {:packet_received, pipe, payload}})
        # send_ack_payload(rf24, 1, payload)
        {:noreply, rf24}

      # EN_DPL is not enabled 
      # TODO implement this usecase?
      <<_::5, 0::1, _en_ack_pay::1, _en_dyn_ack::1>> ->
        {:noreply, rf24}
    end
  end

  def handle_tx_interupt(rf24, pipe, tx_full) do
    send(rf24.receiver_pid, {__MODULE__, {:packet_sent, pipe}})

    rf24 =
      rf24
      |> write_reg(:NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)
      |> enable_prx()

    {:noreply, rf24}
  end

  def handle_err_interupt(rf24, pipe, tx_full) do
    rf24 = write_reg(rf24, :NRF_STATUS, <<0::1, 1::1, 1::1, 1::1, pipe::3, tx_full::1>>)
    send(rf24.receiver_pid, {__MODULE__, {:packet_error, pipe}})
    {:noreply, rf24}
  end
end
