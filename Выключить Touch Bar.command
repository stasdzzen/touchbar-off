#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
./touchbarctl off
printf '\nКоманда гашения отправлена. Это окно можно закрыть.\n'
