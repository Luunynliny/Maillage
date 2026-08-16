#!/bin/bash
#
# Fetches the WhisperKit model this app embeds — the compressed `large-v3-turbo` variant
# (~632MB), quantized and multilingual. Chosen over the smaller `small_216MB` variant this app
# used previously because its accuracy is far closer to what earlier FluidAudio-based attempts
# delivered, and the size difference barely matters next to the ~600MB-1GB models this app has
# already shipped. Called by the "Fetch WhisperKit Model" build phase in maillage.xcodeproj, and
# safe to run standalone.
#
# Two repos, not one: the CoreML weights live in `argmaxinc/whisperkit-coreml`, but WhisperKit's
# tokenizer loading (`Hub.swift`, local-folder path) requires `tokenizer.json` and
# `tokenizer_config.json` sitting in the SAME folder as the model — and those aren't in the CoreML
# repo at all. They're the original HF tokenizer files from `openai/whisper-large-v3`, the PyTorch
# release this CoreML conversion came from. Without them bundled locally, WhisperKit falls through
# to fetching the tokenizer from Hugging Face Hub at runtime — a real network call this app's
# offline-only model loading can't make, which is what an "incomplete" tokenizer error means.
#
# Not committed to git: a model this size would permanently bloat the repo (and need Git LFS).
# Instead this is a plain HTTPS fetch from two public, ungated Hugging Face repos, cached at
# .whisperkit-model-cache/ so a normal repeat build costs a handful of filesystem checks, not a
# re-download. CI caches that same directory (see .github/workflows/ci.yml) for the same reason.
#
# python3 over jq for the JSON parsing, matching check-build-parity.sh: jq isn't guaranteed on a
# stock macOS runner.

set -euo pipefail
cd "$(dirname "$0")/.."

coreml_repo="argmaxinc/whisperkit-coreml"
variant="openai_whisper-large-v3-v20240930_turbo_632MB"
tokenizer_repo="openai/whisper-large-v3"
tokenizer_files=(tokenizer.json tokenizer_config.json)
bundled_name="large-v3-turbo"
cache_dir="$PWD/.whisperkit-model-cache"
model_dir="$cache_dir/$bundled_name"
manifest="$cache_dir/$bundled_name.manifest"

# Fast path: a manifest only ever exists once every file it lists was downloaded successfully and
# the completed tree was moved into place atomically (see below) — so its presence is proof the
# model is complete, not a guess. This is the path every build after the first takes.
if [ -f "$manifest" ]; then
    if (cd "$cache_dir" 2>/dev/null && xargs -I{} test -f {} <"$manifest"); then
        echo "==> WhisperKit model already cached at $model_dir, skipping download"
        exit 0
    fi
    echo "==> Cached WhisperKit model is incomplete, refetching" >&2
    rm -rf "$model_dir" "$manifest"
fi

echo "==> Fetching file list for $variant from $coreml_repo"
coreml_paths=$(
    curl -fsSL "https://huggingface.co/api/models/$coreml_repo" | python3 -c "
import json, sys
data = json.load(sys.stdin)
prefix = '$variant/'
for sibling in data['siblings']:
    path = sibling['rfilename']
    if path.startswith(prefix):
        print(path[len(prefix):])
"
)

if [ -z "$coreml_paths" ]; then
    echo "error: no files found under $variant/ in $coreml_repo — check the variant name or repo layout" >&2
    exit 1
fi

mkdir -p "$cache_dir"
staging=$(mktemp -d "$cache_dir/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT

echo "==> Downloading $variant (this only happens once, then it's cached)"
while IFS= read -r relpath; do
    dest="$staging/$relpath"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "https://huggingface.co/$coreml_repo/resolve/main/$variant/$relpath" -o "$dest"
done <<<"$coreml_paths"

echo "==> Downloading tokenizer files from $tokenizer_repo"
for relpath in "${tokenizer_files[@]}"; do
    curl -fsSL "https://huggingface.co/$tokenizer_repo/resolve/main/$relpath" -o "$staging/$relpath"
done

# Every relative path bundled, CoreML weights and tokenizer files alike — manifest entries are
# recorded relative to $cache_dir (i.e. prefixed with $bundled_name), matching exactly where the
# atomic mv below places them, so the fast-path completeness check above actually checks the real
# files.
files=$(
    { echo "$coreml_paths"
      printf '%s\n' "${tokenizer_files[@]}"
    } | sed "s|^|$bundled_name/|"
)

# Atomic within the cache directory's own filesystem: the model directory either doesn't exist
# yet, or is a previous complete download — never a half-written one a concurrent build could
# see. The rm -rf is what makes that true: without it, an interrupted prior run that got past this
# mv but crashed before the manifest was written below would leave $model_dir populated but
# unmanifested, and mv into an *existing* directory nests the source inside it instead of
# replacing it. $staging is moved (and renamed to $bundled_name) directly — no extra nesting from
# the upstream variant name, so it stays short and stable even if that name changes on a future
# model bump, and every file inside it lands exactly where the manifest above expects it.
rm -rf "$model_dir"
mv "$staging" "$model_dir"
echo "$files" >"$manifest"

echo "==> WhisperKit model ready at $model_dir"
