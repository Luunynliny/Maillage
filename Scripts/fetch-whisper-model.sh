#!/bin/bash
#
# Fetches the WhisperKit model this app embeds — the compressed `large-v3-turbo` variant
# (~632MB), quantized and multilingual. Chosen over the smaller `small_216MB` variant this app
# used previously because its accuracy is far closer to what earlier FluidAudio-based attempts
# delivered, and the size difference barely matters next to the ~600MB-1GB models this app has
# already shipped. Called by the "Fetch WhisperKit Model" build phase in maillage.xcodeproj, and
# safe to run standalone.
#
# Not committed to git: a model this size would permanently bloat the repo (and need Git LFS).
# Instead this is a plain HTTPS fetch from the model's public, ungated Hugging Face repo, cached
# at .whisperkit-model-cache/ so a normal repeat build costs a handful of filesystem checks, not a
# re-download. CI caches that same directory (see .github/workflows/ci.yml) for the same reason.
#
# python3 over jq for the JSON parsing, matching check-build-parity.sh: jq isn't guaranteed on a
# stock macOS runner.

set -euo pipefail
cd "$(dirname "$0")/.."

repo="argmaxinc/whisperkit-coreml"
variant="openai_whisper-large-v3-v20240930_turbo_632MB"
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

echo "==> Downloading $variant (this only happens once, then it's cached)"
while IFS= read -r path; do
    dest="$staging/$path"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "https://huggingface.co/$repo/resolve/main/$path" -o "$dest"
done <<<"$files"

# Atomic within the cache directory's own filesystem: the model directory either doesn't exist
# yet, or is a previous complete download — never a half-written one a concurrent build could
# see. The rm -rf is what makes that true: without it, an interrupted prior run that got past this
# mv but crashed before the manifest was written below would leave $model_dir populated but
# unmanifested, and mv into an *existing* directory nests the source inside it instead of
# replacing it. Renamed from the HF variant name to $bundled_name here (rather than at every call
# site) so the app-facing name stays short and stable even if the upstream variant folder is
# renamed on a future model bump.
rm -rf "$model_dir"
mv "$staging/$variant" "$model_dir"
echo "$files" >"$manifest"

echo "==> WhisperKit model ready at $model_dir"
