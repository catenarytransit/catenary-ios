#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
cp catenary-ios/PhotonAPI.swift "$tmpdir/PhotonAPI.swift"
cp scripts/photon-smoke-main.swift "$tmpdir/main.swift"
swiftc "$tmpdir/PhotonAPI.swift" "$tmpdir/main.swift" -o "$tmpdir/photon-tests"
"$tmpdir/photon-tests"
