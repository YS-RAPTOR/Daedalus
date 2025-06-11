#!/usr/bin/env bash

COMPUTE=$1
OUTPUT=$2
ZIG="pub const compute= \"${COMPUTE}\";\n"
echo -e "${ZIG}" >"${OUTPUT}"
