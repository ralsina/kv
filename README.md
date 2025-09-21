# kv

KV is a modern, simple remote KVM solution. Minimal dependencies, easy to set up, and designed for performance.

## Features

* Stream video and audio from the server's HDMI output
* Send keyboard and mouse events from a single-board computer (SBC) to the server
* Expose disk images to the server as if they were plugged via USB thumb drives

You can see a short demo video [here](https://youtu.be/_NCVytMPW18?si=67kIt7nWbrda1uy8)

Some more information in [the website](https://kv.ralsina.me)

There is a [tutorial in Reddit](https://www.reddit.com/r/homelab/comments/1nld478/building_a_cheap_kvm_using_an_sbc_and_kv/) by [VeryLargeCucumber](https://www.reddit.com/user/VeryLargeCucumber/)

## Known Bugs

* Framerate detection is broken. You can use `-f` as a workaround. 

## TODO

* ✅ Audio streaming
* ✅ Basic Auth
* ✅ Change resolution
* Use ttyd to access the kvm itself
* ✅ Performance improvements
* ✅ Better UX for mass storage
* SSL support
* Video/Audio demuxing
* Other pixel formats support

## Installation

You can build from source or get the static binaries from the [releases page](https://github.com/ralsina/kv/releases)

Put it somewhere, run it, look at the options.

## Usage

To setup a KVM you need:

* A SBC with an OTG port (the *kvm*). I use a Radxa Zero.
* A system you want to control (the *server*)
* A USB dongle to capture HDMI (these are super cheap)
* Misc cables and adapters

Here's how my setup looks:

![image](https://github.com/user-attachments/assets/9b67d7a3-ea71-4f2e-936f-6c4c42b25125)


The white cable goes from the OTG port in the SBC to a regular USB port in the server.
Through this cable the server powers the SBC and the SBC sends keyboard and mouse events to the server.

The HDMI dongle is connected to a USB port in the SBC and captures the HDMI output from the server via
a normal HDMI cable.

You can ignore the black cable, that's monitor output for the SBC and you would normally not have it.

More details in [docs/handbook.md](docs/handbook.md).

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
