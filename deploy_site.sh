#!/bin/bash
set -e

rsync -rav site/* root@rocky:/data/stacks/web/websites/kv.ralsina.me/
