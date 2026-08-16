#!/bin/bash
#
# Fetches the FluidAudio batch ASR model this app embeds — Parakeet TDT 0.6B v3, FluidAudio's
# CoreML port, int8 encoder. Handles French/English code-switching mid-meeting with no per-call
# fixed-language lock, unlike the alternative Cohere pipeline. Called by the "Fetch FluidAudio ASR
# Model" build phase in maillage.xcodeproj, and safe to run standalone.
#
# Not committed to git: this ships as compiled .mlmodelc bundles, and a binary that size would
# permanently bloat the repo (and need Git LFS). Same shape as fetch-whisper-model.sh: a plain
# HTTPS fetch from the model's public, ungated Hugging Face repo, cached at
# .fluidaudio-model-cache/ so a normal repeat build costs a handful of filesystem checks, not a
# re-download. CI caches that same directory (see .github/workflows/ci.yml) for the same reason.
#
# Unlike the streaming Nemotron model this replaces, the v3 repo ships its files at the repo
# root rather than under a `<variant>/` subfolder, and ships several encoder precisions and
# alternate window sizes side by side — so this only pulls the four .mlmodelc bundles + vocab
# file the int8, v3 batch path (`AsrModels.load(from:version:.v3,encoderPrecision:.int8)`) needs,
# not the whole repo.
#
# python3 over jq for the JSON parsing, matching check-build-parity.sh: jq isn't guaranteed on a
# stock macOS runner.

set -euo pipefail
cd "$(dirname "$0")/.."

repo="FluidInference/parakeet-tdt-0.6b-v3-coreml"
model_name="parakeet-tdt-0.6b-v3"
cache_dir="$PWD/.fluidaudio-model-cache"
model_dir="$cache_dir/$model_name"
manifest="$cache_dir/$model_name.manifest"

# The exact set AsrModels.load(from:version:.v3,encoderPrecision:.int8) reads: the shared
# preprocessor, the int8 encoder, the decoder, the v3 joint model (with top-K outputs), and the
# shared Parakeet vocabulary.
required_dirs=(Preprocessor.mlmodelc Encoder.mlmodelc Decoder.mlmodelc JointDecisionv3.mlmodelc)
required_files=(parakeet_vocab.json)

# Fast path: a manifest only ever exists once every file it lists was downloaded successfully and
# the completed tree was moved into place atomically (see below) — so its presence is proof the
# model is complete, not a guess. This is the path every build after the first takes.
if [ -f "$manifest" ]; then
    if (cd "$cache_dir" 2>/dev/null && xargs -I{} test -f {} <"$manifest"); then
        echo "==> Parakeet TDT v3 (int8) already cached at $model_dir, skipping download"
        exit 0
    fi
    echo "==> Cached Parakeet TDT v3 model is incomplete, refetching" >&2
    rm -rf "$model_dir" "$manifest"
fi

echo "==> Fetching file list for $repo"
files=$(
    curl -fsSL "https://huggingface.co/api/models/$repo" | python3 -c "
import json, sys
data = json.load(sys.stdin)
prefixes = tuple(d + '/' for d in '$(IFS=,; echo "${required_dirs[*]}")'.split(','))
wanted = set('$(IFS=,; echo "${required_files[*]}")'.split(','))
for sibling in data['siblings']:
    path = sibling['rfilename']
    if path.startswith(prefixes) or path in wanted:
        print(path)
"
)

if [ -z "$files" ]; then
    echo "error: none of the required model files were found in $repo — check the repo layout" >&2
    exit 1
fi

mkdir -p "$cache_dir"
staging=$(mktemp -d "$cache_dir/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT

echo "==> Downloading Parakeet TDT v3 (int8, ~600MB, this only happens once, then it's cached)"
while IFS= read -r path; do
    dest="$staging/$path"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "https://huggingface.co/$repo/resolve/main/$path" -o "$dest"
done <<<"$files"

# Atomic within the cache directory's own filesystem: the model directory either doesn't exist
# yet, or is a previous complete download — never a half-written one a concurrent build could see.
mkdir -p "$model_dir"
for entry in "${required_dirs[@]}" "${required_files[@]}"; do
    mv "$staging/$entry" "$model_dir/$entry"
done
echo "$files" | sed "s#^#$model_name/#" >"$manifest"

echo "==> Parakeet TDT v3 (int8) ready at $model_dir"
