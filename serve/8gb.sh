#!/bin/bash
# 8GB cards: 64K context, the Hermes Agent floor. Measured footprint about 7.3 GB (on a 12GB card; 8GB row pending).
llama-server -m "${1:-Ternary-Bonsai-2-27B-PTQ1_0.gguf}" -c 65536 -ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0 --jinja --reasoning-effort medium --temp 1.0 --top-p 0.95 --top-k 20 --host 127.0.0.1 --port 8899
