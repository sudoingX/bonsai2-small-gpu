# serve lines, one per vram tier

All lines use the PrismML llama.cpp fork (release `prism-b10685-7dffb15` or newer, or the `bonsai2` branch of
github.com/sudoingX/llama.cpp for the faster PTQ1_0 decode; RTX 50 cards need v1.1 of that branch or the cuda12.8 sm_120
bundle, see the top README). Stock llama.cpp does not run these files. The scripts call `llama-server` from your `PATH`:
after a source build run `export PATH=$PWD/build/bin:$PATH` in the clone, or point `LLAMA_SERVER` at the binary.
Every line: `-np 1` (one slot; four slots cost 450 MiB for nothing), `--jinja` (tool calls), the thinking
defaults `--temp 1.0 --top-p 0.95 --top-k 20`, `--host 127.0.0.1 --port 8899`. Measured on the cards named in `../sweeps/`.

| tier | script | context | served VRAM | notes |
| --- | --- | --- | --- | --- |
| 8GB | `8gb.sh` | 65536 | 7.7 GB | the Hermes floor; measured on an RTX 3060 Ti 8GB, `../sweeps/rtx3060ti-8gb.md`: 40.3 tok/s at 64K with the kernel, 262K fits in 7.7 GB with q4_0 K/V, decode holds to a 96K window and drops past ~112K |
| 8GB + MTP head (lean) | `12gb-mtp.sh` with the lean file, `CTX=88064`, `--spec-draft-n-max 2` | 88064 | 7.9 GB | only the lean (no-embed) merged file fits; measured on an RTX 3000 Ada Laptop 8GB on AC (`../sweeps/rtx3000Ada-8gb.md`). On the `285542d` bundle use `CTX=65536` (31.6 median, +23% over 25.7 flag off). On `prism` ≥ `f13265492` (#221) **88064 costs nothing over 64K** and is lossless with `GGML_CUDA_BATCH_INVARIANT=1` (36.1 median, +33% over the 27.1 base; invariance costs ~12% there, without it ~41 but not byte-identical); cliff at 89088. On battery the numbers are ~15-20% lower but the 88064 window and 89088 cliff are unchanged. The fat shipped MTP file spills on 8 GB (14.3 tok/s) |
| 12GB | `12gb.sh` | 262144 | 11.7 GB | the full native window fits, 0.6 GB spare; measured on an RTX 3060 12GB (`../sweeps/rtx3060.md`) and on an RTX 4070 12GB (`../sweeps/RTX-4070-pr-ptq1-mmv.md`, `../sweeps/RTX-4070-prism.md`, llama-bench r=3, q4_0 K/V, flash attention on): tg128 57.1 tok/s fresh and 23.4 tok/s at 128K depth on the kernel branch (588318660) against 51.9 and 21.8 tok/s on the prism build (5d80cff0b), pp512 637 vs 607 tok/s |
| 12GB + MTP head | `12gb-mtp.sh` | 131072 | 10.6 GB | needs the merged file from `../graft/`; lossless with `GGML_CUDA_BATCH_INVARIANT=1` on the fork branch |
| 16GB + vision | `16gb-vision.sh` | 131072 | 9.6 GB | adds `--mmproj`; measured on an RTX 5060 Ti 16GB (`../sweeps/rtx5060ti-16gb.md`): 9,646 MiB at 131072 |
| 16GB + MTP head + vision | `16gb-mtp-vision.sh` | 262144 | 15.1 GB | needs the merged file from `../graft/`; measured on an RTX 5060 Ti 16GB (`../sweeps/rtx5060ti-16gb.md`): the full window with the head and the mmproj, 15,070 MiB after load, 15,332 MiB after an image request, 67.6 to 67.9 tok/s decode on the image answer; lossless with `GGML_CUDA_BATCH_INVARIANT=1`; on a card that also drives a display use `-c 131072` (11,486 MiB) |

Prebuilt Linux bundles (driver only, the `bonsai2` branch), on the Hugging Face repo next to the merged files: cuda12.4 sm_86 + sm_89 for RTX 30 and 40 cards (README copy in `prebuilt_README.md`) and, from v1.1, cuda12.8 sm_120 for RTX 50 cards (README copy in `prebuilt_README_sm120.md`). The #215 / #214 / #218 a/b on the 3060: `../kernel/ab/ab_215_214_rtx3060.md`.
