# Ternary Bonsai 2 27B PTQ1_0, NVIDIA GeForce RTX 4070

All numbers are from one NVIDIA GeForce RTX 4070, one session (Sep 20 2026),
the same node, direct `llama-bench`, q4_0 K/V cache, flash attention on,
`-p 512 -n 128`, and 3 repetitions per depth. Depths were run as
separate processes so `nvidia-smi --query-gpu=memory.used --format=csv,noheader`
could be sampled before, during, and after each run.

Binaries:

- pr-ptq1-mmv branch : `0.2.0-dev (build 10714, commit 588318660)`
- Executable: `D:\AI\Apps\llama.cpp-bonsai2\build-cuda\bin\Release\llama-bench.exe`

Files:

- `Ternary-Bonsai-2-27B-PTQ1_0.gguf`

Hardware:

- Card: NVIDIA GeForce RTX 4070
- VRAM: 12,282 MiB
- NVIDIA driver: `596.49`

## Depth ladder, original Bonsai 2 PTQ1_0 file, q4_0 K/V, flash attention on

| depth | pp512 tok/s | tg128 tok/s | served VRAM peak (nvidia-smi memory.used) |
|---:|---:|---:|---:|
| 0 | 637.24 ± 5.79 | 57.05 ± 0.61 | 6980 MiB |
| 16384 | 573.59 ± 4.25 | 49.21 ± 0.17 | 7268 MiB |
| 65536 | 426.63 ± 1.84 | 33.32 ± 0.11 | 8142 MiB |
| 131072 | 315.98 ± 0.58 | 23.41 ± 0.02 | 9502 MiB |

The served-VRAM values are the maximum `memory.used` sample observed while
each `llama-bench` process was alive; all runs exited with code 0.

## llama-bench lines verbatim

### Depth 0

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           pp512 |        637.24 ± 5.79 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |           tg128 |         57.05 ± 0.61 |

build: 588318660 (10714)
```

### Depth 16384

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d16384 |        573.59 ± 4.25 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d16384 |         49.21 ± 0.17 |

build: 588318660 (10714)
```

### Depth 65536

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  pp512 @ d65536 |        426.63 ± 1.84 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 |  tg128 @ d65536 |         33.32 ± 0.11 |

build: 588318660 (10714)
```

### Depth 131072

```text
| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | pp512 @ d131072 |        315.98 ± 0.58 |
| qwen35 27B PTQ1_0 - 1.75 bpw ternary (group 128) |   5.53 GiB |    26.90 B | CUDA       |  99 |   q4_0 |   q4_0 |   1 | tg128 @ d131072 |         23.41 ± 0.02 |

build: 588318660 (10714)
```

Odd: the workstation already had 694 MiB reported as used before the first benchmark, so served-VRAM figures include background GPU allocations.
