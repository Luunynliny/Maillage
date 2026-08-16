#!/bin/bash
#
# Fetches the FluidAudio streaming diarizer model this app embeds — Sortformer, `fastV2_1`
# config (~1s inherent latency, the lowest of FluidAudio's streaming tiers, chosen per the
# meeting-recording-v2 design doc's reasoning for Sortformer over LS-EEND). Called by the
# "Fetch FluidAudio Diarizer Model" build phase in maillage.xcodeproj, and safe to run standalone.
#
# Not committed to git, same reasoning as fetch-fluidaudio-asr-model.sh: ships as a compiled
# .mlmodelc bundle (~240MB), cached at .fluidaudio-model-cache/ so a normal repeat build costs a
# handful of filesystem checks, not a re-download. CI caches the same directory.

set -euo pipefail
cd "$(dirname "$0")/.."

repo="FluidInference/diar-streaming-sortformer-coreml"
variant="v3/fp16/Sortformer_v2.1.mlmodelc"
cache_dir="$PWD/.fluidaudio-model-cache"
model_dir="$cache_dir/$variant"
manifest="$cache_dir/sortformer-fastv2.1-fp16.manifest"

# Fast path: a manifest only ever exists once every file it lists was downloaded successfully and
# the completed tree was moved into place atomically (see below) — so its presence is proof the
# model is complete, not a guess. This is the path every build after the first takes.
if [ -f "$manifest" ]; then
    if (cd "$cache_dir" 2>/dev/null && xargs -I{} test -f {} <"$manifest"); then
        echo "==> Sortformer (fastV2_1/fp16) already cached at $model_dir, skipping download"
        exit 0
    fi
    echo "==> Cached Sortformer model is incomplete, refetching" >&2
    rm -rf "$model_dir" "$manifest"
fi

echo "==> Fetching file list for $variant from $repo"
files=$(
    curl -fsSL "https://huggingface.co/api/models/$repo" | python3 -c "
import json, sys
data = json.load(sys.stdin)
prefix = '$variant/'
for sibling in data['siblings']:
    path = sibling['rfilename']
    if path.startswith(prefix):
        print(path)
"
)

if [ -z "$files" ]; then
    echo "error: no files found under $variant/ in $repo — check the variant name or repo layout" >&2
    exit 1
fi

mkdir -p "$cache_dir"
staging=$(mktemp -d "$cache_dir/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT

echo "==> Downloading $variant (~240MB, this only happens once, then it's cached)"
while IFS= read -r path; do
    dest="$staging/$path"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "https://huggingface.co/$repo/resolve/main/$path" -o "$dest"
done <<<"$files"

# Atomic within the cache directory's own filesystem: the model directory either doesn't exist
# yet, or is a previous complete download — never a half-written one a concurrent build could see.
mkdir -p "$(dirname "$model_dir")"
mv "$staging/$variant" "$model_dir"
echo "$files" >"$manifest"

echo "==> Sortformer (fastV2_1/fp16) ready at $model_dir"
