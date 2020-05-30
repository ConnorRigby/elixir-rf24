# RF24

Elixir Interface for nordic NRF24 radios

[datasheet](https://www.nordicsemi.com/-/media/DocLib/Other/Product_Spec/nRF24L01PPSv10.pdf)

[Arduino compatible library](https://github.com/nRF24/RF24/)

## Current Features / Known Issues / wants

* [x] Read/write pipe address
* [X] Read/write tx address
* [x] Send packets
* [x] Receive packets
* [x] Auto Ack packets
* [ ] Sane defaults
* [ ] Basic Usage documentation
* [ ] Processing packet data outside of the library

# WARNINGS

Be sure to check your local laws for legal radio bands.
2.4 ghz is a free band in most places, but be sure to 
check.

## Compatability

There is no common library for encoding/decoding packet
data, so i decided to leave that up to the developer.
So far i've tested this library with the following 
Arduino compatible libraries.

* [My Sensors](https://www.mysensors.org/)
* [nRF24](https://github.com/nRF24/RF24)

## Wiring

Currently i've only tested on Raspberry Pi, but it should work
on any device that [ElixirCircuits](https://elixir-circuits.github.io/) supports.

## Usage

Below is an example of the most basic usage from the Elixir console

```elixir
iex(1)> {:ok, pid} = RF24.start_link()
{:ok, #PID<0.1933.0>}
# cause a remote device to send a few packets..
iex(2)> flush()
{RF24, {:packet_received, 1, "Hello, world! x1"}}
{RF24, {:packet_received, 1, "Hello, world! x2"}}
{RF24, {:packet_received, 1, "Hello, world! x3"}}
iex(3)> RF24.send(pid, "Welcome to the world of radio!", true)
<<14>>
iex(4)> flush()
{RF24, {:packet_sent, 7}}
```

## Examples

There is a complement to [this arduino example](https://github.com/nRF24/RF24/blob/master/examples/pingpair_irq_simple/pingpair_irq_simple.ino)
in this project: [lib/rf24/simple_ping_pair.ex]

[There is a repo here](https://github.com/ConnorRigby/elixir-radio-examples) with some more examples

## Encryption

The NRF24 radios do not support hardware encryption. It
is up to the developer to implement this if so desired.

## RSSI

The NRF24 radios do not support hardware based
Received Signal Strength Indication. There is a single 
register that indicates if the last received packet was
greater than or less than -24 dbm. 