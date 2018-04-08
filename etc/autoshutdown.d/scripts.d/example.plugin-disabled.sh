#!/bin/bash

echo "--------------------------------------------------"
echo "This is an example plugin"
echo "It won't be prevent your system from shutting down"
echo "This script is disabled by default. To enabled it rename it to 'example.plugin.sh'"

echo "The autoshutdown configuration will be automatically loaded by the plugin system"
echo "All variables from /etc/autoshutdown.conf are available, see 'declare -p'"

echo "Output of 'declare -p'"
declare -p

echo "At the end, we will exit with exitcode 0"
echo "--------------------------------------------------"

exit 0
