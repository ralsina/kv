# KV: A Modern Remote KVM

## Intro

KV is my attempt at writing a remote KVM implementation that:

1. Works
2. Doesn't require specific special hardware
3. Is easy to use and set up

I hope to achieve those things. This document describes what it can currently do,
how to set it up to do those things, and some of the quirks and peculiarities
of its implementation. In some cases I have sacrificed performance or generality
for convenience. This is intentional.

I am trying to make it as fully-featured as I can. There are still missing pieces
but those can surely be added if there is interest.

## Installation

You can just get static binaries from <https://github.com/ralsina/kv/releases>

## Remote Video

KV requires a video capture device that supports the V4L2 API. Further it needs
one that produces MJPEG video. Most cheap "MacroSilicon" USB HDMI capture dongles
will fulfill this.

Once you have connected a compatible video capture device, and you have plugged
your video source to it, starting `kv` will show a message such as this:

```
2025-07-13T22:26:16.750129Z   INFO - main: 📹 Video device: /dev/video1
2025-07-13T22:26:16.750143Z   INFO - main: 📐 Resolution: 1280x720@30fps
```

It will *refuse to start* if it cannot find a video capture device that
supports MJPEG. Support for devices that don't produce MJPEG is possible
but not urgent. If you need it, [file an issue.](https://github.com/ralsina/kv/issues)

Once kv is running, you can access using a web browser and you will see
the video. It will have controls to make the video fullscreen, to take
screenshots and to change its resolution.

Usually 1280x720@30fps is a good resolution, but you can change it to
something else if you want. The available resolutions are detected from the
video capture device.

Additionally, there is a menu to set "JPEG Quality". You probably don't want
to change it. To set JPEG quality to anything other than 100% `kv` needs to
decode each frame and reencode it, and the current implementation is not
performant.

If the FPS are too low, it's better to lower the resolution instead.

## Remote Mouse/Keyboard

If your KVM hardware is a SBC that supports OTG on one of its USB ports,
you can plug that to the server and `kv` will act as a mouse and keyboard.

When you click on the video, it will capture your pointer and keyboard and
send them to the KVM. The KVM will then send them to the USB port of the
server, which will treat them like normal mouse and keyboard input.

## Mass Storage

You can upload disk images to the KVM, and they can then in turn be exposed
to the server as USB mass storage devices. The server can then access the
contents of those images. You could even use this as installation media
for the server's operating system.

## Ethernet Gadget

Your KVM can also act as an Ethernet gadget, allowing you to connect to
the server over a network connection. If the server has lost connectivity
you can even provide it with a new network connection by configuring the
KVM as a gateway (But kv provides no UI for this).

If `dnsmasq` is installed in the KVM, then `kv` will automatically assign
an IP address to the KVM and the server, and will provide a DHCP service
so the server configures its network automatically.

## Power Control

Currently `kv` doesn't have any mechanism for controlling the power of the
server. I am not planning on doing this because I don't need it, but I can
help others to do it.

Me, I have the server plugged into a IoT outlet I can turn on/off using my phone.

## Providing Power to the KVM

The KVM needs power to operate, and often this power is provided via the
same port that has OTG capabilities, which means the power is provided by
the server we are controlling.

The bad news is that when most computers cycle power they turn off all USB
ports, which means the KVM will reboot and not be able to control the server
while it's booting.

The easiest solution is: a powered USB hub. Since usually OTG ports are USB2
these are super cheap and easy to find.

## Supported Hardware

I have no idea what this works on because I have only tested it using *my*
hardware:

* Radxa Zero as KVM
* A UGreen "MacroSilicon" USB dongle as video capture device

Would it work using a Raspberry Pi as a KVM?

* Does it have a OTG port? This is true for Pi Zero, Zero 2W and Pi 4 only
* Is it 64-bit? Only Pi Zero 2W and Pi 4
* Does it have *some* way to capture the video?

  * The Pi 4 does, using a USB port
  * The Zero 2W probably needs some unusual hardware, like a CSI/HDMI adapter because it only has one usable USB port

Honestly, the cheapest Radxa Zero is probably cheaper than a Pi Zero 2W, is much faster and has 2 ports.

Let me know if you make it work on other hardware!

## Security and Remote Access

First of all: `kv` does not currently nor will it ever "call home". Why? Because I don't care what you do
with it. It's open source code, so you can look at it, it literally has no code in it to do anything other
than what it says it does.

On the other hand, you want two things from a remote KVM solution:

1) You want to connect to it securely and not let others access it.
2) You want to connect to it remotely, not just from the local network.

For 1:

* `kv` supports basic authentication, so you can set a user and password
* **IMPORTANT** `kv` has no secure transport. If you don't want someone
  to sniff your password, you should use a HTTPS terminating proxy in
  front of it.

For 2:

Your KVM is a freaking computer, setup a VPN. I use tailscale.