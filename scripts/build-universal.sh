#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/.build/universal/LocalDesk}"
ARM_SCRATCH="$ROOT_DIR/.build/arm64-release"
INTEL_SCRATCH="$ROOT_DIR/.build/x86_64-release"

cd "$ROOT_DIR"
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM_SCRATCH"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$INTEL_SCRATCH"

mkdir -p "$(dirname "$OUTPUT_PATH")"
lipo -create \
    "$ARM_SCRATCH/arm64-apple-macosx/release/LocalDesk" \
    "$INTEL_SCRATCH/x86_64-apple-macosx/release/LocalDesk" \
    -output "$OUTPUT_PATH"
lipo "$OUTPUT_PATH" -verify_arch arm64 x86_64
file "$OUTPUT_PATH"
