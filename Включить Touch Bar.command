#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
./touchbarctl on
printf '\nКоманда включения отправлена. Это окно можно закрыть.\n'
