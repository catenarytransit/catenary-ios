#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_binary=$(mktemp -t catenary-nearby-tests.XXXXXX)
trap 'rm -f "$test_binary"' EXIT
swiftc catenary-ios/Networking/Nearby/NearbyDepartureStream.swift \
  Tests/NearbyDepartures/main.swift -o "$test_binary"
"$test_binary"
