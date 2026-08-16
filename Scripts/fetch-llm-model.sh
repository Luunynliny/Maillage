#!/bin/bash
#
# Fetches the local LLM this app embeds for transcript cleanup and meeting summarization —
# `Qwen2.5-1.5B-Instruct`, already converted to MLX format by the `mlx-community` org
# (~830MB, 4-bit quantized). Called by the "Fetch LLM Model" build phase in maillage.xcodeproj,
# and safe to run standalone.
#
# One repo, self-contained: unlike WhisperKit's split across a CoreML repo and a separate
# tokenizer repo, `mlx-community/Qwen2.5-1.5B-Instruct-4bit` ships its weights
# (`model.safetensors`) and its tokenizer (`tokenizer.json`, `tokenizer_config.json`, …) side by
# side, which is what `mlx-swift-lm`'s local-directory loading and `swift-transformers`'
# `AutoTokenizer.from(modelFolder:)` both expect: everything in one folder.
#
# Not committed to git: a model this size would permanently bloat the repo (and need Git LFS).
# Instead this is a plain HTTPS fetch from one public, ungated Hugging Face repo, cached at
# .llm-model-cache/ so a normal repeat build costs a handful of filesystem checks, not a
# re-download. CI caches that same directory (see .github/workflows/ci.yml) for the same reason.
#
# python3 over jq for the JSON parsing, matching check-build-parity.sh: jq isn't guaranteed on a
# stock macOS runner.

set -euo pipefail
cd "$(dirname "$0")/.."

repo="mlx-community/Qwen2.5-1.5B-Instruct-4bit"
bundled_name="qwen2.5-1.5b-instruct-4bit"
cache_dir="$PWD/.llm-model-cache"
model_dir="$cache_dir/$bundled_name"
manifest="$cache_dir/$bundled_name.manifest"

# Fast path: a manifest only ever exists once every file it lists was downloaded successfully and
# the completed tree was moved into place atomically (see below) — so its presence is proof the
# model is complete, not a guess. This is the path every build after the first takes.
if [ -f "$manifest" ]; then
    if (cd "$cache_dir" 2>/dev/null && xargs -I{} test -f {} <"$manifest"); then
        echo "==> LLM model already cached at $model_dir, skipping download"
        exit 0
    fi
    echo "==> Cached LLM model is incomplete, refetching" >&2
    rm -rf "$model_dir" "$manifest"
fi

echo "==> Fetching file list for $repo"
paths=$(
    curl -fsSL "https://huggingface.co/api/models/$repo" | python3 -c "
import json, sys
data = json.load(sys.stdin)
skip = {'.gitattributes', 'README.md'}
for sibling in data['siblings']:
    path = sibling['rfilename']
    if path not in skip:
        print(path)
"
)

if [ -z "$paths" ]; then
    echo "error: no files found in $repo — check the repo name or layout" >&2
    exit 1
fi

mkdir -p "$cache_dir"
staging=$(mktemp -d "$cache_dir/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT

echo "==> Downloading $repo (this only happens once, then it's cached)"
while IFS= read -r relpath; do
    dest="$staging/$relpath"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "https://huggingface.co/$repo/resolve/main/$relpath" -o "$dest"
done <<<"$paths"

# Every relative path bundled — manifest entries are recorded relative to $cache_dir (i.e.
# prefixed with $bundled_name), matching exactly where the atomic mv below places them, so the
# fast-path completeness check above actually checks the real files.
files=$(printf '%s\n' "$paths" | sed "s|^|$bundled_name/|")

# Atomic within the cache directory's own filesystem: the model directory either doesn't exist
# yet, or is a previous complete download — never a half-written one a concurrent build could
# see. The rm -rf is what makes that true: without it, an interrupted prior run that got past this
# mv but crashed before the manifest was written below would leave $model_dir populated but
# unmanifested, and mv into an *existing* directory nests the source inside it instead of
# replacing it.
rm -rf "$model_dir"
mv "$staging" "$model_dir"
echo "$files" >"$manifest"

echo "==> LLM model ready at $model_dir"
