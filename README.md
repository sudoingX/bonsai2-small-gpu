# bonsai2-small-gpu

Run Ternary Bonsai 2 27B well on the cards people actually own. Serve lines per VRAM tier with the
measured flags, a 1.5x faster decode kernel for the PrismML fork, the Qwen 3.8 MTP head grafted back
onto the ternary file for lossless speculative decoding, and a sweep table that grows by PR.

The core numbers were measured on one RTX 3060 12GB, the most owned desktop GPU on Steam (3.92% of
every surveyed system, August 2026), and the RTX 50 numbers on an RTX 5060 Ti 16GB. Other cards land as
rows in `sweeps/` from their owners.

## Run it on your card

Prebuilt Linux bundles on the [Hugging Face repo](https://huggingface.co/sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF),
driver only, no compiler. Find your card, take its bundle and script:

| your card | VRAM | bundle | script | what you get |
| --- | --- | --- | --- | --- |
| RTX 3050 8GB, 3060 8GB, 3060 Ti, 3070, 3070 Ti, 3080 10GB, 4060, 4060 Ti 8GB | 8 to 10 GB | cuda12.4 sm86-sm89 | `serve-8gb.sh` | 98K context; 64K if the card also drives your display |
| RTX 3060 12GB, 3080 12GB, 3080 Ti, 4070, 4070 Super, 4070 Ti | 12 GB | cuda12.4 sm86-sm89 | `serve-12gb-mtp.sh` | the MTP head, 131K context |
| RTX 4060 Ti 16GB, 4070 Ti Super, 4080, 4080 Super, 3090, 3090 Ti, 4090 | 16 to 24 GB | cuda12.4 sm86-sm89 | `serve-12gb-mtp.sh` with `CTX=262144` | the MTP head, the full 262K |
| RTX 5050, 5060, 5060 Ti 8GB | 8 GB | cuda12.8 sm120 | `serve-8gb.sh` | 98K context; 64K with a display |
| RTX 5070 | 12 GB | cuda12.8 sm120 | `serve-12gb-mtp.sh` | the MTP head, 131K context |
| RTX 5060 Ti 16GB, 5070 Ti, 5080, 5090 | 16 to 32 GB | cuda12.8 sm120 | `serve-16gb-mtp-vision.sh` | the MTP head, vision and the full 262K |

Laptop GPUs: the same series, go by your VRAM. Measured so far: RTX 3060 12GB, RTX 3060 Ti 8GB, RTX 4070 12GB (a
contributor), RTX 5060 Ti 16GB and the RTX 3000 Ada Laptop 8GB (a contributor); the other rows follow from the same VRAM
numbers. The Ada Laptop is the case to read before expecting the kernel's gains: on a bandwidth-bound laptop part the
PTQ1_0 mat-vec is worth about +7% decode on `bdc23b56b`, while the current PrismML `prism` branch (post-#221) adds +6 to
+15% prefill and, with the lean (no-embed) MTP file, moves the lossless MTP window from 64K to 88064
(`sweeps/rtx3000Ada-8gb.md`, measured on AC; ~15-20% slower on battery, same window). Run it on yours and open a PR with your row.

RTX 5060 Ti 16GB (any 16GB or bigger RTX 50), four commands:

```
hf download sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf bonsai2-small-gpu-linux-x64-cuda12.8-sm120-ff41412.tar.gz --local-dir ~/models/bonsai2-27b
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf --local-dir ~/models/bonsai2-27b
cd ~/models/bonsai2-27b && tar xzf bonsai2-small-gpu-linux-x64-cuda12.8-sm120-ff41412.tar.gz
./bonsai2-small-gpu-linux-x64-cuda12.8-sm120-ff41412/serve-16gb-mtp-vision.sh
```

RTX 30 or 40 with 12GB or more, three:

```
hf download sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d.tar.gz --local-dir ~/models/bonsai2-27b
cd ~/models/bonsai2-27b && tar xzf bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d.tar.gz
./bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d/serve-12gb-mtp.sh
```

On 8GB cards take `Ternary-Bonsai-2-27B-PTQ1_0.gguf` from `prism-ml/Ternary-Bonsai-2-27B-gguf` instead and run
`serve-8gb.sh`. Then open `http://localhost:8899`: the llama.cpp chat UI, and an OpenAI-compatible API at `/v1`.

What you need: Linux x86-64 (on Windows, WSL2, see below) and `hf` (`pip install -U huggingface_hub`). The RTX 50
bundle wants NVIDIA driver 570 or newer and Ubuntu 24.04 or newer (glibc 2.38); the RTX 30 and 40 bundle wants driver
525 or newer and Ubuntu 22.04 or newer. On a card that also drives your display, start with a smaller window:
`CTX=131072 ./serve-16gb-mtp-vision.sh`. Every script takes `MODEL`, `CTX`, `HOST` and `PORT` from the environment.

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

## RTX 50 series (Blackwell), v1.1

v1.1 makes the branch correct and fast on RTX 50 cards. Two fixes, both in `kernel/blackwell.md`: the PTQ1_0 mat-vec
kernel now waits for its input under programmatic dependent launch (before v1.1 a source build decoded a run of `!` on
RTX 50 cards with the head off), and llama.cpp's flash-attention q4_0 V dequant no longer sits on the stack on sm_120
(long-context decode with a q4_0 K/V cache ran at less than half speed). The branch also moved onto PrismML's latest
release, `prism-b10743-adfffbe`, so if you built it before v1.1, clone it again.

Measured on an RTX 5060 Ti 16GB with the v1.1 bundle (`sweeps/rtx5060ti-16gb.md`): fresh decode 42.0 tok/s on PrismML's
prism-b10743, 53.4 with v1.1 and 67.3 with the MTP head (probe median, the 16GB line: fat file, mmproj, 262144); 39.5
tok/s with the head at 38,774 tokens of context and 21.0 at 119,489; the head, the vision tower and the full 262,144
window together in 15,070 MiB; four requests at once 127.1 tok/s in aggregate with the head, where prism-b10743 does 58.3
without it. At 261,000 tokens, the full window, v1.1 decodes at 12.35 tok/s with the head off and 12.07 with it, where
prism-b10743 does 3.73 (3.3x, head off to head off); past about 120K tokens the head stops adding speed. Up to 8 requests
at once, four agents with 60K of context each and board power are in the same file.

No compiler: the Hugging Face repo carries a cuda12.8 sm_120 bundle next to the cuda12.4 one (driver 570 or newer),
with a `serve-16gb-mtp-vision.sh` for 16GB cards; its README is `serve/prebuilt_README_sm120.md`.

## What is here

- `serve/` one script per tier: 8GB at 64K, 12GB at the full 262K, 12GB with the MTP head, 16GB with the
  vision tower, 16GB with the head and the vision tower at the full 262K. Read `serve/README.md` first.
- `kernel/` the changes to the PrismML fork as patch series and ready-to-read PR bodies: the PTQ1_0
  mat-vec kernel (fast, batch-invariant small batches) and the Hadamard fix for the MTP draft graph,
  plus `blackwell.md`, the two RTX 50 fixes of v1.1. Branches on github.com/sudoingX/llama.cpp:
  `pr-ptq1-mmv` (the kernel series, PrismML-Eng/llama.cpp#218) and `bonsai2`, the one to build: the
  kernel series and the v1.1 fixes on PrismML's latest release, which already carries the Hadamard fix
  (#205, which our #217 closed in favour of) and the PTQ1_0 MMQ tile loader (#214).
- `graft/` the tools that put the Qwen 3.8 27B MTP head back into the Bonsai 2 GGUF: a byte-range
  GGUF reader and writer that handles PrismML's custom quant types, head extraction, merge with a
  byte-exact `--strip`, the identity and batch-numerics probes, tests, and `recipe.txt`.
- `sweeps/` the measured rows and the PR template for new cards.
- `prompts/` the one-paragraph build prompt used for the on-camera test.
- `results/` the two run reports and the greedy identity transcripts.

## Run it in three lines

```
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-PTQ1_0.gguf --local-dir .
# PrismML fork, release prism-b10685-7dffb15 or newer (stock llama.cpp does not load this file):
# https://github.com/PrismML-Eng/llama.cpp/releases
bash serve/12gb.sh Ternary-Bonsai-2-27B-PTQ1_0.gguf
```

For the faster decode, build the `bonsai2` branch of github.com/sudoingX/llama.cpp:

```
git clone -b bonsai2 https://github.com/sudoingX/llama.cpp && cd llama.cpp
cmake -B build -DGGML_CUDA=ON && cmake --build build -j $(nproc)
export PATH=$PWD/build/bin:$PATH
```

then run the same serve line. RTX 50 cards need CUDA 12.8 or newer (`nvcc --version`); cmake picks the card's
architecture itself (sm_120 builds as `120a`). The build also builds the server's web UI, which needs npm or network
access; `-DLLAMA_BUILD_UI=OFF` skips it. The serve scripts listen on `127.0.0.1:8899`.

## Traps

Stock llama.cpp loads the Q2_0 variant and outputs gibberish, and rejects PTQ1_0 outright; use the fork.
The file skips 6GB cards, the weights alone are 5.95 GB; on 8GB the 64K line is the one to try.

The GGUF chat template defaults `reasoning_effort` to `xhigh`, which adds a "think carefully" system line; on the 3060 at a 4,096-token client cap that returned nothing on an SVG, an HTML page and a 100-line Python script (6 of 6 greedy runs spent the whole cap inside `<think>`), and the SVG never finished thinking even at 16,384. The serve lines therefore pass `--reasoning-effort medium` (thinking on, no extra line): the same tasks complete in 45 to 124 s with 22 to 2,381 thinking tokens; keep the client `max_tokens` at 8,192 or more for code, since thinking counts against it. Measurement: `kernel/reasoning_effort.md`.

## Windows

No native Windows build ships yet; run it in WSL2. Update the NVIDIA driver on Windows (570 or newer for RTX 50 cards)
and do not install a Linux driver inside WSL. `wsl --install -d Ubuntu-24.04`, check that `nvidia-smi` inside WSL shows
the card, keep the model files in the Linux filesystem (`~/`, not `/mnt/c`, which is much slower for multi-GB files),
then use the Linux bundle for your card or the source build above. `http://localhost:8899` opens from Windows. On a
card that is tight on VRAM, set NVIDIA Control Panel, Manage 3D settings, CUDA - Sysmem Fallback Policy to Prefer No
Sysmem Fallback, so an overflow fails instead of silently spilling into system RAM. PrismML's own Windows CUDA release
runs the same files at stock speed.

## Changelog

- **v1.1** (Sep 2026): RTX 50 series. The PTQ1_0 mat-vec PDL wait and the flash-attention q4_0 V dequant fix
  (`kernel/blackwell.md`); `bonsai2` rebased onto `prism-b10743-adfffbe`; a cuda12.8 sm_120 bundle; the 16GB serve line
  with the head and the vision tower at 262K; the RTX 5060 Ti 16GB sweep; the serve scripts take `LLAMA_SERVER`; the
  install notes (the full stock tag, CUDA 12.8 for RTX 50, `build/bin` on `PATH`, port 8899); this Windows section.
- **v1.0** (Sep 2026): the PTQ1_0 mat-vec kernel, the MTP graft, the serve lines, the cuda12.4 sm_86 + sm_89 bundle.

## Licence

Apache 2.0. Ternary Bonsai 2 27B is PrismML's, Apache 2.0; the MTP head comes from Qwen3.8-27B, Apache 2.0.
