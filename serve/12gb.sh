#!/bin/bash
# 12GB cards: the full native 262K window resident, 11.7 GB on an RTX 3060 12GB.
llama-server -m "${1:-Ternary-Bonsai-2-27B-PTQ1_0.gguf}" -c 262144 -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20 --host 127.0.0.1 --port 8899
