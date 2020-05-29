defmodule RF24Registers do
  def reg(:NRF_CONFIG), do: 0x00
  def reg(:EN_AA), do: 0x01
  def reg(:EN_RXADDR), do: 0x02
  def reg(:SETUP_AW), do: 0x03
  def reg(:SETUP_RETR), do: 0x04
  def reg(:RF_CH), do: 0x05
  def reg(:RF_SETUP), do: 0x06
  def reg(:NRF_STATUS), do: 0x07
  def reg(:OBSERVE_TX), do: 0x08
  def reg(:CD), do: 0x09
  def reg(:RX_ADDR_P0), do: 0x0A
  def reg(:RX_ADDR_P1), do: 0x0B
  def reg(:RX_ADDR_P2), do: 0x0C
  def reg(:RX_ADDR_P3), do: 0x0D
  def reg(:RX_ADDR_P4), do: 0x0E
  def reg(:RX_ADDR_P5), do: 0x0F
  def reg(:TX_ADDR), do: 0x10
  def reg(:RX_PW_P0), do: 0x11
  def reg(:RX_PW_P1), do: 0x12
  def reg(:RX_PW_P2), do: 0x13
  def reg(:RX_PW_P3), do: 0x14
  def reg(:RX_PW_P4), do: 0x15
  def reg(:RX_PW_P5), do: 0x16
  def reg(:FIFO_STATUS), do: 0x17
  def reg(:DYNPD), do: 0x1C
  def reg(:FEATURE), do: 0x1D

  def reg(unknown) do
    raise ArgumentError, "Unknown register #{unknown}"
  end

  def instr(:R_REGISTER), do: 0x00
  def instr(:W_REGISTER), do: 0x20
  def instr(:REGISTER_MASK), do: 0x1F
  def instr(:ACTIVATE), do: 0x50
  def instr(:R_RX_PL_WID), do: 0x60
  def instr(:R_RX_PAYLOAD), do: 0x61
  def instr(:W_TX_PAYLOAD), do: 0xA0
  def instr(:W_ACK_PAYLOAD), do: 0xA8
  def instr(:FLUSH_TX), do: 0xE1
  def instr(:FLUSH_RX), do: 0xE2
  def instr(:REUSE_TX_PL), do: 0xE3
  def instr(:RF24_NOP), do: 0xFF

  def instr(unknown) do
    raise ArgumentError, "Unknown instruction #{unknown}"
  end
end
