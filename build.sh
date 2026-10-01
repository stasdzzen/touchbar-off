#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation touchbarctl.m -o touchbarctl
