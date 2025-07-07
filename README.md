# kv

KV is a modern, simple remote KVM solution. Minimal dependencies, easy to set up, and designed for performance.

## Features

* Stream video from the server's HDMI output
* Send keyboard and mouse events from a single-board computer (SBC) to the server
* Expose disk images to the server as if they were plugged via USB thumb drives

## Installation

For now you need to build from source. This is a work in progress, and we will provide
pre-built binaries and detailed instructions soon.

## Usage

To setup a KVM you need:

* A SBC with an OTG port (the *kvm*). I use a Radxa Zero.
* A system you want to control (the *server*)
* A USB dongle to capture HDMI (these are super cheap)
* Misc cables and adapters

Here's how my setup looks:



The white cable goes from the OTG port in the SBC to a regular USB port in the server.
Through this cable the server powers the SBC and the SBC sends keyboard and mouse events to the server.

The HDMI dongle is connected to a USB port in the SBC and captures the HDMI output from the server via
a normal HDMI cable.

You can ignore the black cable, that's monitor output for the SBC and you would normally not have it.

## Development

Details to be explained

## Contributing

1. Fork it (<https://github.com/ralsina/kv/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Roberto Alsina](https://github.com/ralsina) - creator and maintainer
