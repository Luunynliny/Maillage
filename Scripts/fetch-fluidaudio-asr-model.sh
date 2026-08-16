#!/bin/bash
#
# Fetches the FluidAudio ASR model this app embeds — Nemotron Speech Streaming Multilingual,
# "latin" ship (shared vocabulary across en/es/fr/it/pt/de, so a French sentence with an English
# technical term decodes as one language instead of the whole-chunk English drift Parakeet TDT v3
# showed on clean French audio), 2240ms chunk tier (FluidAudio's documented recommended default).
# Called one-shot/batch after Stop, not live streaming — see Transcription/Transcriber.swift.
# Called by the "Fetch FluidAudio ASR Model" build phase in maillage.xcodeproj, and safe to run
# standalone.
#
# Not committed to git: this ships as compiled .mlmodelc bundles (~600MB), and a binary that size
# would permanently bloat the repo (and need Git LFS). Same shape as fetch-whisper-model.sh: a
# plain HTTPS fetch from the model's public, ungated Hugging Face repo, cached at
# .fluidaudio-model-cache/ so a normal repeat build costs a handful of filesystem checks, not a
# re-download. CI caches that same directory (see .github/workflows/ci.yml) for the same reason.
#
# python3 over jq for the JSON parsing, matching check-build-parity.sh: jq isn't guaranteed on a
# stock macOS runner.

set -euo pipefail
cd "$(dirname "$0")/.."

repo="FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML"
variant="latin/2240ms"
cache_dir="$PWD/.fluidaudio-model-cache"
model_dir="$cache_dir/$variant"
manifest="$cache_dir/nemotron-multilingual-latin-2240ms.manifest"

# Fast path: a manifest only ever exists once every file it lists was downloaded successfully and
# the completed tree was moved into place atomically (see below) — so its presence is proof the
# model is complete, not a guess. This is the path every build after the first takes.
if [ -f "$manifest" ]; then
    if (cd "$cache_dir" 2>/dev/null && xargs -I{} test -f {} <"$manifest"); then
        echo "==> Nemotron multilingual (latin/2240ms) already cached at $model_dir, skipping download"
        exit 0
    fi
    echo "==> Cached Nemotron multilingual model is incomplete, refetching" >&2
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

echo "==> Downloading Nemotron multilingual (latin/2240ms, ~600MB, this only happens once, then it's cached)"
while IFS= read -r path; do
    dest="$staging/$path"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "https://huggingface.co/$repo/resolve/main/$path" -o "$dest"
done <<<"$files"

# Atomic within the cache directory's own filesystem: `rm -rf` first because `mv` of a directory
# onto an existing directory nests it inside instead of replacing it, which an interrupted prior
# run (model dir created, manifest never written) would otherwise turn into a staging directory
# nested inside the old one rather than a clean replacement. Then one `mv` swaps the
# fully-populated staging directory in for good, so `$model_dir` either doesn't exist yet, or is a
# previous complete download, or is this one — never a half-written one a concurrent build could
# see.
rm -rf "$model_dir"
mkdir -p "$(dirname "$model_dir")"
mv "$staging/$variant" "$model_dir"
echo "$files" >"$manifest"

echo "==> Nemotron multilingual (latin/2240ms) ready at $model_dir"
