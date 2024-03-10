#!/bin/bash
#
# Compiles the project as a Spring boot JAR and as a GraalVM native image.

set -Eeuo pipefail
IFS=$'\n\t'

function main() {
./gradlew --no-daemon clean bootJar nativeCompile test nativeTest
}

main "$@"
