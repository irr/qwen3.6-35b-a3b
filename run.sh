#!/usr/bin/env bash
set -euo pipefail

# Qwen3.6-35B-A3B Q5_K_M on Strix Halo
# Context: 262144 | Vision via mmproj
# MTP is off by default: the unsloth GGUF has no MTP layers. Set MTP=1
# only with a GGUF that includes them.
# Runs llama-server from the official llama.cpp Vulkan Docker image.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$SCRIPT_DIR/models"
MODEL_FILE="Qwen3.6-35B-A3B-UD-Q5_K_M.gguf"
HF_REPO="unsloth/Qwen3.6-35B-A3B-GGUF"
HF_HUB_SPEC='huggingface_hub>=1.0,<2'
MMPROJ_FILE="mmproj-F16.gguf"
IMAGE="${IMAGE:-ghcr.io/ggml-org/llama.cpp:server-vulkan}"
CONTAINER_NAME="${CONTAINER_NAME:-qwen3.6-35b-a3b}"
PORT="${PORT:-8000}"
CTX=262144
MTP="${MTP:-0}"

if ! command -v docker &>/dev/null; then
  echo "Error: docker is not installed or not in PATH." >&2
  exit 1
fi

mkdir -p "$MODEL_DIR"

download() {
  local file="$1"
  [[ -f "$MODEL_DIR/$file" ]] && return 0
  local url="https://huggingface.co/$HF_REPO/resolve/main/$file"
  echo "Downloading $file to $MODEL_DIR..."
  if command -v hf &>/dev/null; then
    hf download "$HF_REPO" "$file" --local-dir "$MODEL_DIR"
  elif command -v uvx &>/dev/null; then
    uvx --from "$HF_HUB_SPEC" hf download "$HF_REPO" "$file" \
      --local-dir "$MODEL_DIR"
  elif command -v wget &>/dev/null; then
    wget -c -O "$MODEL_DIR/$file" "$url"
  elif command -v curl &>/dev/null; then
    curl -L -C - -o "$MODEL_DIR/$file" "$url"
  else
    echo "Error: need hf, uvx, wget, or curl to download the model." >&2
    exit 1
  fi
}

download "$MODEL_FILE"
download "$MMPROJ_FILE"

# Give the container the host's GPU device groups (by numeric GID,
# since group names like "render" don't exist inside the image)
GROUP_FLAGS=()
for gid in $(stat -c '%g' /dev/dri/* 2>/dev/null | sort -u); do
  [[ "$gid" != 0 ]] && GROUP_FLAGS+=(--group-add "$gid")
done

SPEC_FLAGS=()
MTP_INFO="disabled"
if [[ "$MTP" == 1 ]]; then
  SPEC_FLAGS=(--spec-type draft-mtp --spec-draft-n-max 3)
  MTP_INFO="enabled (draft-mtp, n-max 3)"
fi

# Only allocate a TTY when running interactively
TTY_FLAGS=()
[[ -t 0 && -t 1 ]] && TTY_FLAGS=(-it)

echo "Starting llama-server (Docker)"
echo "  Image:   $IMAGE"
echo "  Model:   $MODEL_DIR/$MODEL_FILE"
echo "  Vision:  $MODEL_DIR/$MMPROJ_FILE"
echo "  Context: $CTX"
echo "  MTP:     $MTP_INFO"
echo "  Port:    $PORT"

exec docker run --rm "${TTY_FLAGS[@]}" \
  --name "$CONTAINER_NAME" \
  --device /dev/dri \
  "${GROUP_FLAGS[@]}" \
  -v "$MODEL_DIR":/models:ro \
  -p "$PORT":8000 \
  "$IMAGE" \
  -m "/models/$MODEL_FILE" \
  --mmproj "/models/$MMPROJ_FILE" \
  -ngl 999 \
  -c "$CTX" \
  -fa on \
  -ub 1024 \
  -b 1024 \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  "${SPEC_FLAGS[@]}" \
  --host 0.0.0.0 \
  --port 8000
