# bonsai2-small-gpu

Run Ternary Bonsai 2 27B well on the cards people actually own. Serve lines per VRAM tier with the
measured flags, a 1.5x faster decode kernel for the PrismML fork, the Qwen 3.8 MTP head grafted back
onto the ternary file for lossless speculative decoding, and a sweep table that grows by PR.

Everything here was measured on one RTX 3060 12GB, the most owned desktop GPU on Steam (3.92% of
every surveyed system, August 2026). Other cards land as rows in `sweeps/` from their owners.

## The numbers, RTX 3060 12GB, llama-bench r=3, flag off, original file

| build | tg128 | pp512 |
| --- | ---: | ---: |
| PrismML fork, prebuilt prism-b10685 | 26.32 tok/s | 269.6 tok/s |
| `pr-ptq1-mmv` branch (this repo's kernel) | 40.47 tok/s | 267.8 tok/s |

Decode by filled context, same two builds: fresh 26.4 to 40.5 tok/s (1.53x), 16K 21.7 to 30.9 (1.42x),
64K 14.3 to 17.9 (1.25x), 131K 9.8 to 11.4 (1.16x). Prefill unchanged, served VRAM unchanged (7.3 GB at
64K, 11.7 GB at 262K).

With the MTP head grafted on and `GGML_CUDA_BATCH_INVARIANT=1`, `--spec-type draft-mtp --spec-draft-n-max 1`
runs at 50.1 tok/s median over code, prose and bash (code 53.2), and greedy output equals greedy output
without the flag on all three prompts. Details and every run: `results/KERNEL_REPORT.md`.

## What is here

- `serve/` one script per tier: 8GB at 64K, 12GB at the full 262K, 12GB with the MTP head, 16GB with the
  vision tower. Read `serve/README.md` first.
- `kernel/` the two changes to the PrismML fork as patch series and ready-to-read PR bodies:
  the PTQ1_0 mat-vec kernel (fast, batch-invariant small batches) and the Hadamard fix for the MTP
  draft graph. Branches: `pr-ptq1-mmv` and `pr-hadamard-mtp` on github.com/sudoingX/llama.cpp,
  and `bonsai2` which stacks both. Upstream pull requests: PrismML-Eng/llama.cpp#217 (Hadamard fix)
  and PrismML-Eng/llama.cpp#218 (kernel).
- `graft/` the tools that put the Qwen 3.8 27B MTP head back into the Bonsai 2 GGUF: a byte-range
  GGUF reader and writer that handles PrismML's custom quant types, head extraction, merge with a
  byte-exact `--strip`, the identity and batch-numerics probes, tests, and `recipe.txt`.
- `sweeps/` the measured rows and the PR template for new cards.
- `prompts/` the one-paragraph build prompt used for the on-camera test.
- `results/` the two run reports and the greedy identity transcripts.

## Run it in three lines

```
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-PTQ1_0.gguf --local-dir .
# PrismML fork, release prism-b10685 or newer (stock llama.cpp does not load this file):
# https://github.com/PrismML-Eng/llama.cpp/releases
bash serve/12gb.sh Ternary-Bonsai-2-27B-PTQ1_0.gguf
```

For the faster decode, build the `pr-ptq1-mmv` branch of github.com/sudoingX/llama.cpp with
`cmake -B build -DGGML_CUDA=ON && cmake --build build -j`, then run the same serve line with that binary.
Builds for sm_86 through sm_120 (the sm_90 and sm_120 host-stub failure at `5883186` is fixed in `2578fdf`).

## Traps

Stock llama.cpp loads the Q2_0 variant and outputs gibberish, and rejects PTQ1_0 outright; use the fork.
The file skips 6GB cards, the weights alone are 5.95 GB; on 8GB the 64K line is the one to try.

The GGUF chat template defaults `reasoning_effort` to `xhigh`, which adds a "think carefully" system line; on the 3060 at a 4,096-token client cap that returned nothing on an SVG, an HTML page and a 100-line Python script (6 of 6 greedy runs spent the whole cap inside `<think>`), and the SVG never finished thinking even at 16,384. The serve lines therefore pass `--reasoning-effort medium` (thinking on, no extra line): the same tasks complete in 45 to 124 s with 22 to 2,381 thinking tokens; keep the client `max_tokens` at 8,192 or more for code, since thinking counts against it. Measurement: `kernel/reasoning_effort.md`.

## Licence

Apache 2.0. Ternary Bonsai 2 27B is PrismML's, Apache 2.0; the MTP head comes from Qwen3.8-27B, Apache 2.0.
