---
license: apache-2.0
base_model:
- prism-ml/Ternary-Bonsai-2-27B-gguf
- Qwen/Qwen3.8-27B
library_name: llama.cpp
pipeline_tag: text-generation
tags:
- gguf
- qwen3_5
- ternary
- ptq1_0
- mtp
- speculative-decoding
- bonsai
- rtx-3060
---

# Ternary Bonsai 2 27B PTQ1_0 with the MTP head

The 1.75 bpw PTQ1_0 build of Ternary Bonsai 2 27B (PrismML's ternary compression of Qwen 3.8 27B, 5.95 GB, the file that fits 8GB and 12GB cards) with the Qwen 3.8 27B multi-token-prediction head grafted back on as block 64, so the PrismML llama.cpp fork can run `--spec-type draft-mtp` on it.

Three Bonsai 2 MTP grafts already exist, all on the PQ2_0 file (7.21 GB): [ProCreations](https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP), [decent-jawfish](https://huggingface.co/decent-jawfish/bonsai-2-27b-mtp), [BoldingBuilds](https://huggingface.co/BoldingBuilds/Ternary-Bonsai-2-27B-Abliterated-PQ2_0-MTP-GGUF). BoldingBuilds also tried PTQ1_0 and measured +1.6%: the head drafts fine, the verification does not pay, because on the 1.75 bpw kernels a 3-token batch cost about 3x a single token. This repo is that graft, and [PrismML-Eng/llama.cpp#218](https://github.com/PrismML-Eng/llama.cpp/pull/218) is the kernel that removes the wall: on an RTX 3060 12GB a 3-token verify now costs 1.55x a single token instead of 2.28x, and single-token decode itself goes from 26 to 40 tok/s.

## Download and run

One file: `Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf` (7.0 GB). It runs on the PrismML fork release binary as shipped, no patch, and it runs faster on the kernel branch. Every number below is this file.

```
hf download sudoingx/Ternary-Bonsai-2-27B-PTQ1_0-MTP-GGUF Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf --local-dir .
git clone -b bonsai2 https://github.com/sudoingX/llama.cpp && cmake -S llama.cpp -B build -DGGML_CUDA=ON && cmake --build build -j
GGML_CUDA_BATCH_INVARIANT=1 build/bin/llama-server -m Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf \
  -ngl 99 -fa on -c 131072 -np 1 -ctk q4_0 -ctv q4_0 --jinja \
  --reasoning-effort medium --spec-type draft-mtp --spec-draft-n-max 1
```

No compiler: extract the prebuilt tarball from this repo (Ampere and Ada, driver only) and run `serve-12gb-mtp.sh`, adding `--reasoning-effort medium`: the scripts inside the published tarball predate that measurement, the ones in the repo do not. On the stock PrismML release binary the same serve line works without the env var, at the +8% row below.

## Numbers

RTX 3060 12GB, one slot, thinking off, 131072 context, q4_0 K/V, client-measured tok/s (`probe.py` in the [repo](https://github.com/sudoingX/bonsai2-small-gpu), 3 prompts x 3 runs, medians), this fat file:

| build | flag | tok/s |
| --- | --- | ---: |
| PrismML release prism-b10685 | off | 25.0 |
| PrismML release prism-b10685 | draft-mtp, n-max 1 | 27.1 (+8%, the wall) |
| #218 kernel branch | off | 39.8 |
| #218 kernel branch, `GGML_CUDA_BATCH_INVARIANT=1` | draft-mtp, n-max 1 | **50.1** (code 53.2, bash 50.1, prose 41.8) |
| #218 kernel branch, `GGML_CUDA_BATCH_INVARIANT=1` | draft-mtp, n-max 2 | 45.4 |
| #218 kernel branch, 41.8K tokens filled | head off / n-max 1 / n-max 2 | 22.23 / 26.86 / 21.08 (release binary, head off: 16.85) |
| #218 kernel branch, 18K / 39K / 77K / 115K filled | head off → n-max 1 | 29.6 → 33.9 / 22.9 → 27.5 / 16.1 → 18.3 / 12.4 → 13.9 (+12% to +20%; n-max 2 below head off at every one of these depths) |

Draft acceptance on this card: 0.85 to 0.95 on Python, 0.73 to 0.81 on bash, 0.45 to 0.68 on prose, 0.65 to 0.73 on a long document at 18K to 120K tokens of context, 0.88 on an image prompt with the vision tower loaded. The head was trained by Qwen against fp16 hidden states and here it reads a ternary trunk; acceptance is lower than on stock Qwen 3.8 (about 0.70) and still well above break-even.

`llama-bench` on the same card, original PTQ1_0 file, `-fa 1 -ctk q4_0 -ctv q4_0 -r 3`: tg128 26.32 → 40.54 tok/s, pp512 269.6 → 268.7 tok/s (prefill untouched). Other owners' rows, 8GB through 5070 Ti, are in the repo's `sweeps/` and on the PR threads.

## Losslessness

With `GGML_CUDA_BATCH_INVARIANT=1` on the kernel branch, greedy output (temperature 0, top_k 1, 300 tokens, 3 prompts) with the head on is byte-identical to greedy output with the head off; the transcripts are in the repo under `results/identity/`. Without the knob, on any build, batched verification changes the floating-point reduction order and the text can differ at near-ties, which is what the other grafts report too. Sampling at the model card's `temperature 1.0, top_p 0.95, top_k 20` is unaffected either way; speculative decoding verifies every draft token against the target.

## Files

| file | bytes | needs |
| --- | ---: | --- |
| `Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf`, **the file** | 7,012,820,512 | the PrismML fork, prism-b10685 or later, as released. Carries its own unrotated copy of the token embedding for the head, so `--spec-type draft-mtp` starts without any patch. For the speed above, the kernel branch. |
| `bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-8971d7b.tar.gz` | 515,425,982 | nothing but the NVIDIA driver. `llama-server`, `llama-bench`, `llama-cli` built from the `bonsai2` branch (kernel + Hadamard fix), CUDA runtime bundled, serve scripts for 8GB, 12GB and 12GB with the head. Ampere and Ada; Blackwell builds from source. |

Smaller variant, optional: `Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf`, 6,297,658,848 bytes, the same graft without the embedding copy, 715 MB smaller (on a 12GB card that is 196K of context instead of 163K). Same output. It needs the 15-line qwen35 MTP Hadamard fix in the build (PrismML-Eng/llama.cpp#217 or #205, or the `bonsai2` branch above); the release binary refuses to start the draft graph on it. Once that fix ships in a PrismML release this becomes the default file.

`SHA256SUMS` in the repo covers all four files; the tarball carries its own `SHA256SUMS` for its 25 files. Tarball facts: NVIDIA driver 525 or newer, glibc 2.35 or newer, AVX2; extracted and run from a clean directory with no toolchain in the environment, identity byte-identical, 49.3 tok/s median; the lean file on the same binaries loads at 9,940 MiB at 131072 and 11,732 MiB at 196608, the fat file does not fit 196608 on 12 GB (the MTP compute buffer needs 1,040 MiB more).

Parents:

- PrismML `Ternary-Bonsai-2-27B-PTQ1_0.gguf`, 5,946,648,928 bytes, sha256 `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`. Every one of its 851 tensors is present with identical bytes and offsets; `tools/merge.py --strip` on the merged file reproduces this sha256.
- unsloth `Qwen3.8-27B-UD-Q4_K_M.gguf`, 16,464,440,224 bytes, sha256 `322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482`. Source of the 15 `blk.64.*` tensors (Q6_K, Q8_0, F32, 335 MiB) and, in the fat file, of `blk.64.nextn.embed_tokens.weight` (a Q4_K copy of its token_embd, 682 MiB).

Header changes versus Bonsai 2: `qwen35.block_count` 64 → 65, `qwen35.nextn_predict_layers = 1`, plus `graft.donor.name`, `graft.head_blocks`, `graft.head_tensor_count`, `graft.tool` for provenance. Everything else, the `prism.hadamard.*` keys and the tokenizer included, is byte-identical. Without `--spec-type draft-mtp` the file behaves exactly like Bonsai 2, the head is skipped.

## Serving notes

**Set `--reasoning-effort medium`.** The GGUF chat template defaults it to `xhigh`, which injects a "think carefully through the task" system line, and on an RTX 3060 at a 4,096-token client cap that returned **nothing at all** on all three build tasks tested: an SVG, a single-file HTML page and a 100-line Python CLI each spent the whole 4,096 tokens thinking and emitted no answer, in 108 seconds. At `medium` the same three completed in 45 to 58 seconds. Raising the cap does not fix it on its own, the SVG was still empty after 16,384 thinking tokens and 477 seconds. Three tasks, two caps, two runs each, every pair identical; the table is in [`kernel/reasoning_effort.md`](https://github.com/sudoingX/bonsai2-small-gpu/blob/main/kernel/reasoning_effort.md). Credit to professorpalmer for flagging the default. Per request it is the OpenAI `reasoning_effort` field; the serve scripts in the repo already pass it.

VRAM on an RTX 3060 12GB: fat file 10,638 MiB at 131072, 11,726 MiB at 163840 (with `-ctkd q4_0 -ctvd q4_0`); lean file 9,956 MiB at 131072, 11,990 MiB at 196608. Stock ggml-org llama.cpp cannot read PTQ1_0 and produces gibberish on any Bonsai 2 file; use the PrismML fork or the branch above.

Sampling per the base card: thinking `temperature 1.0, top_p 0.95, top_k 20`; instruct `temperature 0.7, top_p 0.8, top_k 20, presence_penalty 1.5`. `--spec-draft-n-max 1` was best on this card at every depth measured, fresh to 120K tokens; n-max 2 only pays on a fresh context and loses to head-off past ~16K. Sweep it on yours.

## How it was made

15 `blk.64.*` tensors, a full transformer block plus the `nextn` projections, copied verbatim from the unsloth GGUF into the Bonsai GGUF with the two header keys above; the fat file also copies the donor's token embedding for the head's own lookup. The residual stream of Bonsai 2 is in the original basis (its RMSNorm weights match stock Qwen 3.8 elementwise), so the head receives the activations it was trained on; only the embedding table is Hadamard-latent, which is what the lean file's 15-line fix inverts. Merge tool, byte-exact strip, identity and batch-numerics probes, 15 tests and `recipe.txt`: `graft/` in the [repo](https://github.com/sudoingX/bonsai2-small-gpu). The kernel: `kernel/` there, and #218.

## Credit

PrismML for Bonsai 2 and the fork; Qwen for the head; unsloth for the donor GGUF. decent-jawfish, ProCreations and BoldingBuilds for the PQ2_0 grafts and the Hadamard patch, and BoldingBuilds for publishing the PTQ1_0 negative result this file answers. professorpalmer's [#221](https://github.com/PrismML-Eng/llama.cpp/pull/221) stacks this kernel with his own and reaches 103 tok/s with the head at 262K on a 4070 12GB. The graft recipe traces back to [sudoingX/qwen38-mtp](https://github.com/sudoingX/qwen38-mtp).

## Licence

All parents are Apache 2.0 (Qwen/Qwen3.8-27B by Alibaba Cloud, Ternary Bonsai 2 27B by PrismML, unsloth's GGUF export of the former). This repo redistributes their weights unchanged under the same licence. The tarball carries llama.cpp's MIT licence and the NVIDIA CUDA runtime redistribution notice. Not affiliated with PrismML, Qwen or unsloth.
