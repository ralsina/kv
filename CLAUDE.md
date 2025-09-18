# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KV is a modern remote KVM (Keyboard, Video, Mouse) solution built in Crystal that streams video/audio from a server's HDMI output and sends keyboard/mouse events from a single-board computer to the server. It can also expose disk images as virtual USB drives to the server.

## Development Commands

### Building
```bash
# Install dependencies
shards install

# Development build
crystal build --release src/main.cr -o bin/kv

# Build static binaries for distribution (AMD64 and ARM64)
./build_static.sh
```

### Testing
```bash
# Run tests (currently has issues with libcomposite kernel module loading)
crystal spec
```

### Linting
```bash
# Run linter
ameba src/ spec/

# Auto-fix linting issues
ameba --fix src/ spec/
```

## Architecture

The application is a single binary (`kv`) with these key components:

- **Web Interface**: Kemal-based HTTP server with WebSocket support
- **Video Capture**: Uses V4L2 via `v4cr` library for HDMI capture
- **Audio Streaming**: Opus-encoded audio via ALSA
- **Input Handling**: Keyboard and mouse events sent via USB gadget framework
- **Mass Storage**: USB gadget functionality to expose disk images

### Key Source Files

- `src/main.cr` - Entry point with docopt CLI parsing
- `src/kvm_manager.cr` - Core KVM orchestration
- `src/video_capture.cr` - Video streaming from HDMI devices
- `src/audio_streamer.cr` - Audio capture and streaming
- `src/keyboard.cr` & `src/mouse.cr` - Input device handling
- `src/composite.cr` - USB gadget setup and management
- `src/endpoints/` - HTTP API endpoints for web interface

## Important Notes

- **Single Binary**: The project produces one main binary (`kv`)
- **Static Builds**: Use `./build_static.sh` for distribution binaries
- **Test Issue**: Tests currently fail due to libcomposite kernel module loading at module level (line 215 in main.cr)
- **Linting**: All files currently pass ameba linting
- **CLI**: Uses docopt as preferred (avoid not_nil!, use descriptive parameter names)
- **Dependencies**: Managed via shards.yml, lib/ contains external libraries (don't modify)

## Build Verification

Always verify builds by:
1. Building the main binary: `crystal build --release src/main.cr -o bin/kv`
2. Checking the binary runs and shows help: `./bin/kv --help`
3. Running linter: `ameba --fix src/ spec/`
- Do not build, user builds manually