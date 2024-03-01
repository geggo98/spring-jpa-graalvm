#!/bin/bash
#
# Compiles the project as a Spring boot JAR and as a GraalVM native image.

set -e -u -o pipefail
IFS=$'\n\t'

function main() {
  ./gradlew --no-daemon clean bootJar nativeCompile
}

main "$@"
