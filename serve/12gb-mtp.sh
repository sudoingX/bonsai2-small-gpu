#!/bin/bash
# 12GB cards with the MTP head (merged file from ../graft/): 131K context, 10.6 GB, n-max 1 = the lossless speed pick.
GGML_CUDA_BATCH_INVARIANT=1 llama-server -m "${1:-Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf}" -c 131072 --spec-type draft-mtp --spec-draft-n-max 1 -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20 --host 127.0.0.1 --port 8899
