#!/bin/bash
#
# Runs two benchmarks against the project, one with JDK HotSpot and one with GraalVM native-image.
#
# Make sure to run the compile.sh script before running this script.

set -Eeuo pipefail
IFS=$'\n\t'

declare memory_limit=""
declare latency_limit=""
declare -a jvm_args
declare -a native_image_args
declare -a hotspot_args


declare timing_file_graal
timing_file_graal=$(mktemp)
declare timing_file_hotspot
timing_file_hotspot=$(mktemp)

function shutdown() {
  set +e
  trap - SIGINT SIGQUIT EXIT

  # Check for "pgrep java" or "pgrep jpa"
  if pgrep "java" >/dev/null || pgrep "jpa" > /dev/null; then
    echo "Shutdown..."
    curl -s -XPOST "http://localhost:8080/shutdown" > /dev/null
    sleep 5
    curl -s -XPOST "http://localhost:8081/shutdown" > /dev/null
    sleep 5
  fi
  if [[ -s "${timing_file_graal}" || -s "${timing_file_hotspot}" ]]; then
    echo "Timing information:"
    cat "${timing_file_graal}" "${timing_file_hotspot}"
    rm "${timing_file_graal}" "${timing_file_hotspot}" 2>/dev/null
  fi
  # Kill all background processes
  # shellcheck disable=SC2046 # We want to actually need the process IDs as separate arguments.
  kill $(jobs -p) 2>/dev/null
  # Wait for all background processes to finish
  # shellcheck disable=SC2046 # We want to actually need the process IDs as separate arguments.
  wait $(jobs -p)
  if [[ -f "${timing_file_graal}" || -f "${timing_file_hotspot}" ]]; then
    cat "${timing_file_graal}" "${timing_file_hotspot}"
    rm "${timing_file_graal}" "${timing_file_hotspot}" 2>/dev/null
  fi
  exit
}

# Hook to kill all background processes on exit. We have to use `wait` to wait for the processes to
# finish, otherwise the script will exit before the processes are killed and the background processes
# will be orphaned, potentially becoming zombies (e.g., inside a Docker container).
trap 'shutdown' SIGINT SIGQUIT EXIT

function wait_for_port() {
  declare start_time
  start_time=$(date +%s)
  declare port="$1"
  while ! curl -s "http://localhost:${port}/customers" > /dev/null; do
    sleep 0.5
    echo -n .
  done
  declare end_time
  end_time=$(date +%s)
  echo -n " ($((end_time - start_time)) seconds)"
}

function indent() {
  declare n="$1"
  # prefix is a string of n spaces
  declare prefix
  prefix=$(printf "%${n}s")
  # Read each line from stdin and add the prefix, then print it
  declare line
  while IFS= read -r line; do
    echo "${prefix}${line}"
  done
}

# Usage $0 --memory-limit <memory-limit>, Default memory limit is 800m
function usage() {
  echo "Usage: $0 [--memory-limit <memory-limit>] [--help]"
  echo "  --memory-limit <memory-limit>   Memory limit for the JVM and native-image processes"
  echo "                                     Default is unlimited"
  echo "  --latency-limit <latency-limit> Latency limit for the garbage collector in milliseconds."
  echo "                                     Default is none."
  echo "                                     Applies only to HotSpot JVM."
  echo "  --gc [ZGC|G1]                   Garbage collector to use."
  echo "                                     Default is G1GC."
  echo "                                     Applies only to HotSpot JVM."
  echo "  --help                          Display this help message"
  exit 1
}

function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --memory-limit)
      shift
      memory_limit="$1"
      jvm_args+=("-Xmx${memory_limit}")
      shift
      ;;
    --latency-limit)
      shift
      latency_limit="$1"
      hotspot_args+=("-XX:MaxGCPauseMillis=$latency_limit")
      shift
      ;;
    --gc)
      shift
      case "$1" in
      ZGC)
        hotspot_args+=("-XX:+UseZGC")
        ;;
      G1)
        hotspot_args+=("-XX:+UseG1GC")
        ;;
      *)
        echo "Unknown garbage collector: $1"
        usage
        ;;
      esac
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

  jvm_args+=("-Dlogging.level.root=ERROR")
  jvm_args+=("-Dspring.main.banner-mode=off")
  native_image_args+=("${jvm_args[@]}")
  declare native_image_param_string
  native_image_param_string=$(IFS=$'\t'; echo "${native_image_args[*]}")

  hotspot_args+=("${jvm_args[@]}")
  hotspot_args+=("-Dserver.port=8081")
  declare hotspot_param_string
  hotspot_param_string=$(IFS=$'\t'; echo "${hotspot_args[*]}")

  echo "Testing with memory limit: ${memory_limit:-unlimited} and latency limit: ${latency_limit:-unlimited} ms"
  echo "JVM HotSpot parameters: ${hotspot_param_string}"
  echo "GraalVM native-image parameters: ${native_image_param_string}"
  echo -n "JVM HotSpot version: "
  java -version
  echo -n "GraalVM native-image version: "
  native-image --version

  echo "Starting GraalVM native-image process on port 8080"
  # shellcheck disable=SC2086
  (command time --out=${timing_file_graal} --append --format="[GraalVM native-image] max mem: %MkB, wall clock time: %es, user time: %Us, system time: %Ss" ./build/native/nativeCompile/jpa ${native_image_param_string}) &
  echo -n "Waiting for port 8080 to be ready"
  wait_for_port 8080
  echo " done"
  echo "Example request: curl -s http://localhost:8080/customers"
  curl -s http://localhost:8080/customers
  echo

  echo "Starting JVM Hotspot VM process on port 8081"
  # shellcheck disable=SC2086
  (command time --out=${timing_file_hotspot} --append --format="[JVM Hotspot] max mem: %MkB, wall clock time: %es, user time: %Us, system time: %Ss" java ${hotspot_param_string} -jar ./build/libs/jpa-0.0.1-SNAPSHOT.jar) &
  echo -n "Waiting for port 8081 to be ready"
  wait_for_port 8081
  echo " done"
  echo "Example request: curl -s http://localhost:8081/customers"
  curl -s http://localhost:8081/customers
  echo

  echo "Warmup"
  echo "  Warmup GraalVM native-image"
  wrk -t2 -c5 -d5s http://localhost:8080/customers >/dev/null
  echo "  Warmup JVM Hotspot"
  wrk -t2 -c5 -d5s http://localhost:8081/customers >/dev/null

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

  echo "Done"
}

main "$@"
