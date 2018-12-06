#!/bin/bash
resize -s 50 150
stty rows 50
stty cols 150

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

$SCRIPT_DIR/bin/elixium_node foreground
