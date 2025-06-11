#!/usr/bin/env bash

VERTEX=$1
FRAGMENT=$2
OUTPUT=$3
ZIG="pub const vertex = \"${VERTEX}\";\n pub const fragment = \"${FRAGMENT}\";\n"
echo -e "${ZIG}" >"${OUTPUT}"
