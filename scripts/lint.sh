#!/bin/bash
set -euo pipefail

echo "Running SwiftLint..."
if command -v swiftlint &> /dev/null; then
    swiftlint lint --strict
else
    echo "SwiftLint not installed. Run: brew install swiftlint"
    echo "Skipping lint check."
fi

echo ""
echo "Building..."
swift build

echo ""
echo "Running tests..."
swift test

echo ""
echo "All checks passed."
