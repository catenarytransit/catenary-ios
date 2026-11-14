#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_binary=$(mktemp -t catenary-departure-tests.XXXXXX)
trap 'rm -f "$test_binary"' EXIT
swiftc catenary-ios/Features/Stops/DepartureRouteFilters.swift \
  Tests/DepartureFilters/main.swift -o "$test_binary"
"$test_binary"
