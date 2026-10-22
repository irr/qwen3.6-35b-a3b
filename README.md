# Qwen3.6-35B-A3B on Strix Halo

One script to run [Qwen3.6-35B-A3B](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF) locally with `llama-server`, using the official llama.cpp **Vulkan** Docker image. Built for AMD Strix Halo (Ryzen AI Max) but it should work on any Linux machine with a Vulkan-capable GPU and enough memory.

- **Model:** Unsloth Dynamic `UD-Q5_K_M` GGUF (~26.5 GB)
- **Vision:** image input through `mmproj-F16.gguf` (~0.9 GB)
- **Context:** 262,144 tokens
- **Concurrency:** 4 parallel requests sharing the full context
- **API:** OpenAI-compatible, plus the llama.cpp web UI

## Requirements

- Linux with a GPU exposed at `/dev/dri` (Vulkan)
- Docker
- About 30 GB of free disk for the model files, and enough GPU-accessible memory for the weights plus the KV cache at full context (Strix Halo's unified memory is the target)
- One of `hf`, `uvx`, `wget` or `curl` to download the model (tried in that order)

## Quick start

```bash
./run.sh
```

On the first run the script downloads both GGUF files into `models/`. After that it starts `llama-server` on port 8000 with every layer offloaded to the GPU.

Open <http://localhost:8000> for the web UI, or call the API:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Explain mixture-of-experts in two sentences."}]
  }'
```

### Image input

```bash
IMG=$(base64 -w0 photo.jpg)
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "What is in this picture?"},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,'"$IMG"'"}}
      ]
    }]
  }'
```

## Configuration

Set these environment variables to change the defaults:

| Variable         | Default                                     | Description                                    |
| ---------------- | ------------------------------------------- | ---------------------------------------------- |
| `PORT`           | `8000`                                      | Host port the server listens on                |
| `IMAGE`          | `ghcr.io/ggml-org/llama.cpp:server-vulkan`  | llama.cpp Docker image                         |
| `CONTAINER_NAME` | `qwen3.6-35b-a3b`                           | Docker container name                          |
| `MTP`            | `0`                                         | Set to `1` for multi-token-prediction speculative decoding (see below) |

Example:

```bash
PORT=9000 ./run.sh
```

### Server settings

| Setting          | Value                                  |
| ---------------- | -------------------------------------- |
| GPU layers       | all (`-ngl 999`)                       |
| Context          | 262144                                 |
| Parallel slots   | 4 (`-np 4`), unified KV cache (`--kv-unified`) |
| Flash attention  | on                                     |
| Batch / ubatch   | 1024 / 1024                            |
| Sampling         | temp 0.6, top-p 0.95, top-k 20, min-p 0 |

The sampling values follow Qwen's recommendations for thinking mode. Change them in `run.sh` if you need different behaviour, or override them per request in the API call.

### Parallel requests

The server handles up to 4 requests at once. The slots share one 262,144-token KV cache, so a single request can use the full context, but all active requests together can't go past it. A 5th request waits until a slot frees up. To change the number of slots, edit `-np` in `run.sh`. Keep `--kv-unified`, or each slot gets only `262144 / N` tokens.

### MTP (multi-token prediction)

MTP is off by default because the Unsloth GGUF has no MTP layers. Set `MTP=1` only when you switch to a GGUF that includes them. It then runs with `--spec-type draft-mtp --spec-draft-n-max 3`.

## How it works

- `models/` is mounted read-only into the container at `/models`.
- `/dev/dri` is passed through, and the container joins the host's GPU device groups by numeric GID (group names such as `render` don't exist inside the image).
- A TTY is only allocated when you run the script interactively, so it also works from systemd or other scripts.
- The container is started with `--rm`, so stopping it (Ctrl+C or `docker stop qwen3.6-35b-a3b`) removes it. The model files stay in `models/`.

## Security note

The server binds to `0.0.0.0` and has no API key, so anyone who can reach the port can use it. To keep it local only, change the port mapping in `run.sh` to `-p 127.0.0.1:"$PORT":8000`, or add `--api-key <key>` to the server arguments.

## Project layout

```
.
├── run.sh        # downloads the model and starts llama-server
├── models/       # GGUF files (git-ignored)
└── README.md
```

## Credits

- [Qwen](https://huggingface.co/Qwen) for the model
- [Unsloth](https://huggingface.co/unsloth) for the GGUF quantization
- [llama.cpp](https://github.com/ggml-org/llama.cpp) for the server and Docker image
