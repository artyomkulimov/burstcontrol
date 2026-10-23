#!/bin/zsh
set -eu
cd "${0:A:h}"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/burst-control-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc Sources/BurstControl/HID.swift Sources/BurstControl/Settings.swift Tests/ProtocolChecks.swift -o "$test_dir/protocol-checks" -framework IOKit
"$test_dir/protocol-checks"
