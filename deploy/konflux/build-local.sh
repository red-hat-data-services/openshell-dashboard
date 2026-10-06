#!/usr/bin/env bash
# Build the dashboard with Hermeto-prefetched dependencies and no build network.
set -euo pipefail

if [[ $# -gt 1 || ${1:-} == --help ]]; then
    echo "Usage: $0 [image-tag]"
    echo "Requires a running Podman machine, git, and python3."
    echo "Optional: PODMAN (executable path), HERMETO_IMAGE (fetcher image), VERSION (image label)."
    if [[ $# -gt 1 ]]; then exit 1; fi
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PODMAN="${PODMAN:-podman}"
HERMETO_IMAGE="${HERMETO_IMAGE:-ghcr.io/hermetoproject/hermeto:latest}"
IMAGE_TAG="${1:-localhost/openshell-dashboard:konflux-local}"

command -v "$PODMAN" >/dev/null
command -v git >/dev/null
command -v python3 >/dev/null
"$PODMAN" info >/dev/null

mkdir -p "$REPO_ROOT/.cache/konflux-build"
BUILD_DIR="$(mktemp -d "$REPO_ROOT/.cache/konflux-build/run.XXXXXX")"
SOURCE_DIR="$BUILD_DIR/source"
OUTPUT_DIR="$BUILD_DIR/output"
echo "Build files and dependency cache: $BUILD_DIR"

# Retain Git history for Hermeto's Go module metadata, then overlay current
# tracked files. Hermeto may rewrite manifests only in this temporary copy.
git clone --quiet --local --no-hardlinks "$REPO_ROOT" "$SOURCE_DIR"
REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin)"
case "$REMOTE_URL" in
    git@github.com:*) REMOTE_URL="https://github.com/${REMOTE_URL#git@github.com:}" ;;
esac
git -C "$SOURCE_DIR" remote set-url origin "$REMOTE_URL"
python3 - "$REPO_ROOT" "$SOURCE_DIR" <<'PY'
import pathlib
import shutil
import subprocess
import sys

root, source = map(pathlib.Path, sys.argv[1:])
files = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
for name in files.decode().split("\0"):
    if not name:
        continue
    original, destination = root / name, source / name
    if original.is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, destination)
    elif not original.exists() and destination.is_file():
        destination.unlink()
PY

hermeto() {
    "$PODMAN" run --rm -v "$BUILD_DIR:/work:z" "$HERMETO_IMAGE" "$@"
}

echo "Prefetching npm and Go dependencies"
hermeto fetch-deps --source /work/source --output /work/output \
    '[{"type":"npm","path":"frontend"},{"type":"gomod","path":"backend"}]'
hermeto generate-env /work/output --format env \
    --output /work/output/cachi2.env --for-output-dir /cachi2/output
hermeto inject-files /work/output --for-output-dir /cachi2/output

# Match Konflux's environment injection without changing the checked-in file.
awk '/^[[:space:]]*RUN / {
    match($0, /RUN /)
    $0 = substr($0, 1, RSTART - 1) "RUN . /cachi2/cachi2.env && " substr($0, RSTART + RLENGTH)
} { print }' "$SOURCE_DIR/deploy/Dockerfile.konflux" > "$BUILD_DIR/Dockerfile.hermetic"

echo "Building $IMAGE_TAG with networking disabled"
BUILD_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$SOURCE_DIR/frontend/package.json")"
"$PODMAN" build --network none \
    --build-arg "VERSION=${VERSION:-$BUILD_VERSION}" \
    -v "$OUTPUT_DIR:/cachi2/output:z" \
    -v "$OUTPUT_DIR/cachi2.env:/cachi2/cachi2.env:z" \
    -f "$BUILD_DIR/Dockerfile.hermetic" -t "$IMAGE_TAG" "$SOURCE_DIR"

echo "Checking that the image executable runs"
"$PODMAN" run --rm "$IMAGE_TAG" --help
