#!/bin/bash
#
# Runs two benchmarks against the project, one with JDK HotSpot and one with GraalVM native-image.
#
# Make sure to run the compile.sh script before running this script.

set -euo pipefail
IFS=$'\n\t'

declare memory_limit="800m"

# Hook to kill all background processes on exit. We have to use `wait` to wait for the processes to
# finish, otherwise the script will exit before the processes are killed and the background processes
# will be orphaned, potentially becoming zombies (e.g., inside a Docker container).
trap 'kill $(jobs -p); wait' EXIT

function wait_for_port() {
  local start_time
  start_time=$(date +%s)
  local port="$1"
  while ! curl -s "http://localhost:${port}/customers" > /dev/null; do
    sleep 0.1
    echo -n .
  done
  local end_time
  end_time=$(date +%s)
  echo -n " ($((end_time - start_time)) seconds)"
}

function indent() {
  local n="$1"
  # prefix is a string of n spaces
  local prefix
  prefix=$(printf "%${n}s")
  # Read each line from stdin and add the prefix, then print it
  while IFS= read -r line; do
    echo "${prefix}${line}"
  done
}

# Usage $0 --memory-limit <memory-limit>, Default memory limit is 800m
function usage() {
  echo "Usage: $0 [--memory-limit <memory-limit>] [--help]"
  echo "  --memory-limit <memory-limit>  Memory limit for the JVM and native-image processes"
  echo "                                  Default is 800m"
  echo "  --help                         Display this help message"
  exit 1
}

function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --memory-limit)
      shift
      memory_limit="$1"
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
    esac
  done
}

function main() {
  parse_args "$@"

  echo "Testing with memory limit: ${memory_limit}"
  echo -n "JVM HotSpot version: "; java -version
  echo -n "GraalVM native-image version: "; native-image --version
  echo "Starting GraalVM native-image process on port 8080"
  command time --format "[GraalVM native-image] max mem: %MkB, wall clock time: %es, user time: %Us, system time: %Ss" ./build/native/nativeCompile/jpa -Xmx${memory_limit} > /dev/null &
  echo -n "Waiting for port 8080 to be ready"
  wait_for_port 8080
  echo " done"

  echo "Starting JVM Hotspot VM process on port 8081"
  command time --format "[JVM Hotspot] max mem: %MkB, wall clock time: %es, user time: %Us, system time: %Ss" java -Xmx${memory_limit} -XX:+UseG1GC  -Dserver.port=8081 -jar ./build/libs/jpa-0.0.1-SNAPSHOT.jar > /dev/null &
  echo -n "Waiting for port 8081 to be ready"
  wait_for_port 8081
  echo " done"

  echo "Warmup"
  echo "  Warmup GraalVM native-image"
  wrk -t2 -c5 -d5s http://localhost:8080/customers > /dev/null
  echo "  Warmup JVM Hotspot"
  wrk -t2 -c5 -d5s http://localhost:8081/customers > /dev/null

  echo "Benchmarking..."
  echo "  Round 1"
  echo "    Benchmark GraalVM native-image"
  wrk -t12 -c400 -d30s --latency http://localhost:8080/customers | indent 6
  echo "    Benchmark JVM Hotspot"
  wrk -t12 -c400 -d30s --latency http://localhost:8081/customers | indent 6
  echo "  Cooldown: waiting for 30 seconds"
  sleep 30
  echo "  Round 2"
  echo "    Benchmark JVM Hotspot"
  wrk -t12 -c400 -d30s --latency http://localhost:8081/customers | indent 6
  echo "    Benchmark GraalVM native-image"
  wrk -t12 -c400 -d30s --latency http://localhost:8080/customers | indent 6

  echo "Shotdown JVM Hotspot and GraalVM native-image processes"
  kill %1
  wait %1
  kill %2
  wait %2
  echo "Done"
}

main "$@"
