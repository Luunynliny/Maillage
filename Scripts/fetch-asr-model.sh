#!/bin/bash
#
# Fetches the two models this app embeds for local ASR — Qwen3-ASR (0.6B, 4-bit MLX) for
# transcription and Silero VAD (MLX) for voice-activity chunking, both via `speech-swift`'s
# `StreamingASR`. Called by the "Fetch ASR Model" build phase in maillage.xcodeproj, and safe to
# run standalone.
#
# Two repos, like WhisperKit's coreml+tokenizer split before it — but here because
# `StreamingASR` composes two independently-loaded models, not because one model's files are
# split across repos. Each repo's *entire* file list is fetched (minus the two files every HF
# repo carries that aren't model data), the same as `fetch-llm-model.sh`: `speech-swift`'s own
# `WeightLoader`/`SileroWeightLoader` (read directly from source) expect `config.json` plus
# `*.safetensors` sitting directly in the folder passed as `cacheDir:`, and the ASR repo also
# needs its `vocab.json`/`merges.txt`/`tokenizer_config.json` alongside them for
# `Qwen3ASRModel.fromPretrained` to build a tokenizer — hand-picking a subset risked silently
# missing one of those and getting a model that "loads" but returns raw token IDs instead of text.
#
# Not committed to git: these are large binary MLX weights, regenerated from a plain HTTPS fetch
# on first build and cached at .asr-model-cache/ for every build after, on a developer machine and
# in CI alike (see .github/workflows/ci.yml for the CI-side cache).
#
# python3 over jq for the JSON parsing, matching check-build-parity.sh: jq isn't guaranteed on a
# stock macOS runner.

set -euo pipefail
cd "$(dirname "$0")/.."

asr_repo="aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
asr_name="qwen3-asr-0.6b-mlx-4bit"
vad_repo="aufklarer/Silero-VAD-v6.2.1-MLX"
vad_name="silero-vad-mlx"
bundled_name="asr-model"
cache_dir="$PWD/.asr-model-cache"
model_dir="$cache_dir/$bundled_name"
manifest="$cache_dir/$bundled_name.manifest"

# Fast path: a manifest only ever exists once every file it lists was downloaded successfully and
# the completed tree was moved into place atomically (see below) — so its presence is proof both
# models are complete, not a guess. This is the path every build after the first takes.
if [ -f "$manifest" ]; then
    if (cd "$cache_dir" 2>/dev/null && xargs -I{} test -f {} <"$manifest"); then
        echo "==> ASR models already cached at $model_dir, skipping download"
        exit 0
    fi
    echo "==> Cached ASR models are incomplete, refetching" >&2
    rm -rf "$model_dir" "$manifest"
fi

fetch_repo_paths() {
    local repo="$1"
    curl -fsSL "https://huggingface.co/api/models/$repo" | python3 -c "
import json, sys
data = json.load(sys.stdin)
skip = {'.gitattributes', 'README.md'}
for sibling in data['siblings']:
    path = sibling['rfilename']
    if path not in skip:
        print(path)
"
}

mkdir -p "$cache_dir"
staging=$(mktemp -d "$cache_dir/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT

fetch_into() {
    local repo="$1" name="$2"
    # Status lines go to stderr, not stdout: this function's stdout is captured whole by the
    # caller's `$(...)` to get the manifest's file list, and an echo left on stdout here would
    # land in that list as a bogus "path" — corrupting the manifest xargs reads back on the fast
    # path above.
    echo "==> Fetching file list for $repo" >&2
    local paths
    paths=$(fetch_repo_paths "$repo")
    if [ -z "$paths" ]; then
        echo "error: no files found in $repo — check the repo name or layout" >&2
        exit 1
    fi

    echo "==> Downloading $repo (this only happens once, then it's cached)" >&2
    while IFS= read -r relpath; do
        local dest="$staging/$name/$relpath"
        mkdir -p "$(dirname "$dest")"
        curl -fsSL "https://huggingface.co/$repo/resolve/main/$relpath" -o "$dest"
    done <<<"$paths"

    printf '%s\n' "$paths" | sed "s|^|$bundled_name/$name/|"
}

asr_files=$(fetch_into "$asr_repo" "$asr_name")
vad_files=$(fetch_into "$vad_repo" "$vad_name")

# Every relative path bundled, both models alike — manifest entries are recorded relative to
# $cache_dir (i.e. prefixed with $bundled_name), matching exactly where the atomic mv below places
# them, so the fast-path completeness check above actually checks the real files.
files=$(
    echo "$asr_files"
    echo "$vad_files"
)

# Atomic within the cache directory's own filesystem: the model directory either doesn't exist
# yet, or is a previous complete download — never a half-written one a concurrent build could
# see. The rm -rf is what makes that true: without it, an interrupted prior run that got past this
# mv but crashed before the manifest was written below would leave $model_dir populated but
# unmanifested, and mv into an *existing* directory nests the source inside it instead of
# replacing it.
rm -rf "$model_dir"
mv "$staging" "$model_dir"
echo "$files" >"$manifest"

echo "==> ASR models ready at $model_dir"
