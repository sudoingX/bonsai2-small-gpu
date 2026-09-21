# Ternary Bonsai 2 27B PTQ1_0, NVIDIA GeForce RTX 4070

All numbers are from one NVIDIA GeForce RTX 4070, one session (Sep 20 2026),
the same node, direct `llama-bench`, q4_0 K/V cache, flash attention on,
`-p 512 -n 128`, and 3 repetitions per depth. Depths were run as
separate processes so `nvidia-smi --query-gpu=memory.used --format=csv,noheader`
could be sampled before, during, and after each run.

Binaries:

- Bonsai 2 build: `0.2.0-dev (build 10687, commit 5d80cff0b)`
- Executable: `D:\AI\Apps\llama.cpp-prism\build-cuda-migrated-backup\bin\Release\llama-bench.exe`

Files:

- `Ternary-Bonsai-2-27B-PTQ1_0.gguf`

Hardware:

- Card: NVIDIA GeForce RTX 4070
- VRAM: 12,282 MiB
- NVIDIA driver: `596.49`

## Depth ladder, original Bonsai 2 PTQ1_0 file, q4_0 K/V, flash attention on

| depth | pp512 tok/s | tg128 tok/s | served VRAM peak (nvidia-smi memory.used) |
|---:|---:|---:|---:|
| 0 | 606.80 ± 4.71 | 51.93 ± 0.24 | 7561 MiB |
| 16384 | 551.74 ± 3.64 | 44.54 ± 0.26 | 7721 MiB |
| 65536 | 409.69 ± 2.12 | 30.69 ± 0.02 | 8586 MiB |
| 131072 | 304.26 ± 1.16 | 21.77 ± 0.03 | 9918 MiB |

The served-VRAM values are the maximum `memory.used` sample observed while
each `llama-bench` process was alive; all runs exited with code 0.

## llama-bench lines verbatim

### Depth 0

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |        606.80 ± 4.71 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         51.93 ± 0.24 |

build: 5d80cff0b (10687)
```

### Depth 16384

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d16384 |        551.74 ± 3.64 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d16384 |         44.54 ± 0.26 |

build: 5d80cff0b (10687)
```

### Depth 65536

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d65536 |        409.69 ± 2.12 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d65536 |         30.69 ± 0.02 |

build: 5d80cff0b (10687)
```

### Depth 131072

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | pp512 @ d131072 |        304.26 ± 1.16 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | tg128 @ d131072 |         21.77 ± 0.03 |

build: 5d80cff0b (10687)
```

Odd: the workstation already had 1249 MiB reported as used before the first benchmark, so served-VRAM figures include background GPU allocations.
