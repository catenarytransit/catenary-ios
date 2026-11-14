#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_binary=$(mktemp -t catenary-planner-tests.XXXXXX)
trap 'rm -f "$test_binary"' EXIT
swiftc catenary-ios/Features/TripPlanner/DirectionsModels.swift \
  catenary-ios/Features/TripPlanner/DirectionsGeometry.swift \
  catenary-ios/Features/TripPlanner/DirectionsPresentation.swift \
  catenary-ios/Features/TripPlanner/DirectionsStreaming.swift \
  Tests/TripPlanner/main.swift -o "$test_binary"
"$test_binary"
