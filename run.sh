#!/bin/sh
#
# Run a test or benchmark with the appropriate environment variables set.
#
set -e

usage() {
    echo "Usage: $0 tests|benchmarks [test_file.dart] [test_name]"
    echo ""
    echo "  tests        Run the test suite"
    echo "  benchmarks   Run the benchmarks"
    echo "  example      Run the example application"
    echo ""
    echo "  test_file.dart   (optional) A specific test file to run"
    echo "  test_name        (optional) A specific test name to run (requires test_file.dart)"
    echo ""
    echo "  benchmark_file.dart (optional) A specific benchmark file to run"
    echo ""
    echo "  --profile       (optional) Run with profiler enabled"
    exit 1
}

TESTS="0"
TEST_FILE=""
TEST_NAME=""
BENCHMARKS="0"
BENCHMARK_FILE=""
EXAMPLE="0"
PROFILE="0"

# iterate through optional arguments and set variables accordingly
while [ "$#" -gt 0 ]; do
    case "$1" in
        tests)
            TESTS=1
            ;;
        benchmarks)
            BENCHMARKS=1
            ;;
        example)
            EXAMPLE=1
            ;;
        --profile)
            PROFILE=1
            ;;
        *)
            if [ "$TESTS" = "1" ]; then
                if [ -z "$TEST_FILE" ]; then
                    TEST_FILE="$1"
                elif [ -z "$TEST_NAME" ]; then
                    TEST_NAME="$1"
                else
                    usage
                fi
            elif [ "$BENCHMARKS" = "1" ]; then
                if [ -z "$BENCHMARK_FILE" ]; then
                    BENCHMARK_FILE="$1"
                else
                    usage
                fi
            elif [ "$EXAMPLE" = "1" ]; then
                # remaining args are passed through to the example application
                break
            else
                usage
            fi
            ;;
    esac
    shift
done

SELECTED_COUNT=0
if [ "$TESTS" = "1" ]; then
  SELECTED_COUNT=$((SELECTED_COUNT + 1))
fi
if [ "$BENCHMARKS" = "1" ]; then
  SELECTED_COUNT=$((SELECTED_COUNT + 1))
fi
if [ "$EXAMPLE" = "1" ]; then
  SELECTED_COUNT=$((SELECTED_COUNT + 1))
fi
if [ "$SELECTED_COUNT" -gt 1 ]; then
  echo "Error: Cannot specify more than one of 'tests', 'benchmarks', or 'example'."
  usage
fi

PROFILE_ARGS=""
if [ "$PROFILE" = "1" ]; then
  PROFILE_ARGS="--observe"
fi

if [ "$TESTS" = "1" ]; then
  # check for valid BITCOIN_CORE_BIN environment variable
  if [ -z "$BITCOIN_CORE_BIN" ]; then
    echo "Error: BITCOIN_CORE_BIN environment variable is not set."
    exit 1
  fi
  if [ ! -x "$BITCOIN_CORE_BIN" ]; then
    echo "Error: BITCOIN_CORE_BIN is not a valid executable: $BITCOIN_CORE_BIN"
    exit 1
  fi

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
    dart test $PROFILE_ARGS "$TEST_FILE" --plain-name "$TEST_NAME"
  elif [ -n "$TEST_FILE" ]; then
    dart test $PROFILE_ARGS "$TEST_FILE"
  else
    dart test $PROFILE_ARGS test/test_*.dart
  fi
elif [ "$BENCHMARKS" = "1" ]; then
  # run the benchmarks
  if [ -n "$BENCHMARK_FILE" ]; then
    dart run $PROFILE_ARGS benchmark_runner report "$BENCHMARK_FILE"
  else
    dart run $PROFILE_ARGS benchmark_runner report
  fi
elif [ "$EXAMPLE" = "1" ]; then
  # run the example application, passing through any extra arguments
  dart run $PROFILE_ARGS example/lib/main.dart "$@"
else
  usage
fi
