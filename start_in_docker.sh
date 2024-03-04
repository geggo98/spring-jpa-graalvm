#!/bin/bash
#
# Start the application inside a Docker container.

set -Eeuo pipefail
IFS=$'\n\t'

declare platform

function usage() {
  echo "Usage: $0 [--platform <platform>] [--help]"
  echo
  echo "Options:"
  echo "  --platform <platform>  The platform to run the container on."
  echo "  --help                 Show this help message."
  echo
  echo "Example:"
  echo "  $0 --platform linux/arm64"
  exit 1
}


function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform)
        platform="$2"
        shift 2
        ;;
      --help)
        usage
        ;;
      *)
        echo "Unknown argument: $1"
        exit 1
        ;;
    esac
  done
}


function main() {
  parse_args "$@"

  local common_args
common_args="--rm -ti --init -v \"$(pwd):/code\" --workdir /code jetpackio/devbox:latest devbox shell"

  if [[ -z "${platform}" ]]; then
    eval "docker run ${common_args}"
  else
    eval "docker run --platform \"${platform}\" ${common_args}"
  fi
}

main "$@"
