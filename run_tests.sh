#!/bin/sh

set -e

TEST_FILE=$1
TEST_NAME=$2

# ensure no bitcoind regtest processes are running before starting tests
pkill -f "bitcoind.*-regtest" || true

# remove any existing test directories from /tmp
rm -rf /tmp/dartcoin_test_*
rm -rf /tmp/dartcoin_node_*

# remove the port registry
rm -f /tmp/dartcoin_port_registry.txt
rm -f /tmp/dartcoin_core_process_lock

# run the test/s
if [ -n "$TEST_FILE" ] && [ -n "$TEST_NAME" ]; then
  dart test "$TEST_FILE" --plain-name "$TEST_NAME"
elif [ -n "$TEST_FILE" ]; then
  dart test "$TEST_FILE"
else
  dart test test/test_*.dart
fi
