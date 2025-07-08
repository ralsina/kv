#!/bin/bash
set -e

docker run --rm --privileged \
  multiarch/qemu-user-static \
  --reset -p yes

shards install

# Build for AMD64
docker build . -f Dockerfile.static -t kv-builder
docker run -ti --rm -v "$PWD":/app --user="$UID" kv-builder /bin/sh -c "cd /app && shards build --static --release && strip bin/kv"
mv bin/kv bin/kv-static-linux-amd64

# Build for ARM64
docker build . -f Dockerfile.static --platform linux/arm64 -t kv-builder
docker run -ti --rm -v "$PWD":/app --platform linux/arm64 --user="$UID" kv-builder /bin/sh -c "cd /app && shards build --static --release && strip bin/kv"
mv bin/kv bin/kv-static-linux-arm64
