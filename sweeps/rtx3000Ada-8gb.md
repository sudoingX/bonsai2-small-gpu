# Ternary Bonsai 2 27B, RTX 3000 Ada Generation Laptop GPU 8GB

All numbers from one NVIDIA RTX 3000 Ada Generation Laptop GPU (8 GB, sm_89) on Windows 11 +
WSL2 (Ubuntu 22.04.5, kernel 5.15.167.4-microsoft-standard-WSL2, i9-13900H, 20 threads),
driver 595.95, CUDA UMD 13.2. **Measured on AC**, GPU memory clock 7001 MHz (on battery it
drops to 5471 MHz; see Power below). The GPU drives no display (`nvidia-smi` idle: 0 MiB
used). Numbers only from runs done on this machine.

This card is **not** the RTX 3060 12GB and not the 3060 Ti 8GB. It is an Ada (sm_89)
laptop part: 8 GB on a 128-bit bus (about 256 GB/s at the AC memory clock), a 50 W power cap
(`nvidia-smi power.max_limit = 50.00 W`) and no display attached. Same VRAM as the 3060 Ti
row (`rtx3060ti-8gb.md`), but its stock decode already sits near the card's practical
bandwidth, which changes what the PTQ1_0 mat-vec kernel is worth here.

## Binaries

- **stock**: the source build at `/home/randon_m/bonsai/llama.cpp`, branch `prism` at
  `bdc23b56b` (build 10728) — the base, **without** the kernel
  (`ggml/src/ggml-cuda/mmvq-ptq1_0.cuh` is absent).
- **bundle**: `bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-285542d` (the `bonsai2`
  branch of `sudoingX/llama.cpp`, `285542d98`, build 10738): `bdc23b56b` + the ten
  `pr-ptq1-mmv` commits including the PTQ1_0 mat-vec kernel and `GGML_CUDA_BATCH_INVARIANT`.
  Confirmed by the `mul_mat_vec_ptq1_0_pt` SASS and the sm_86 **and** sm_89 cubins in
  `lib/libggml-cuda.so.0`. cuda12.4 runtime.
- **prism `f13265492`** (build 10752): a second source build of the official
  `PrismML-Eng/llama.cpp` `prism` branch at `f13265492`, which includes the merged #221
  integration checkpoint (`5244ceade`): the `pr-ptq1-mmv` kernel (the bundle's own series),
  the hybrid PTQ1_0 dispatch (mat-vec to 4 columns, MMQ from 5), the Ampere+ 4-column GDN
  warp layout (#216, +6% prefill on Ada), and in-place q4_0/q8_0 K/V flash attention (no F16
  scratch). `cmake -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89`. The bundle predates all of
  it.

## Files

- `Ternary-Bonsai-2-27B-PTQ1_0.gguf`, 5,946,648,928 bytes — base, no MTP.
- `Ternary-Bonsai-2-27B-PTQ1_0-MTP.gguf`, 6,297,658,656 bytes, sha256
  `09bce6c2eb6f862a5ac8b654c3b4d53f7600e915a4030986af09647a275a1514` — the **lean** MTP
  graft (`blk.64.*` only, no duplicate embedding; the fork reads the trunk's own table via
  the Hadamard fix). Built from the unsloth Qwen3.8-27B donor.
- `Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf`, 7,012,820,512 bytes, sha256
  `83a396ee218c36e5ed88205eccb940a71549d9a72a3d020cc2713f94a78f70f0` — the **fat** MTP file
  shipped by `bonsai2-small-gpu`; carries a second, Q4_K `blk.64.nextn.embed_tokens.weight`
  (682 MiB) for forks without the Hadamard fix.

## A/B on the same card (llama-bench), AC

Same model (base file), same flags, same session, only the binary differs.

```
llama-bench -m Ternary-Bonsai-2-27B-PTQ1_0.gguf -ngl 99 -fa 1 -ctk q4_0 -ctv q4_0 -p 512 -n 128 -r 3 -d 0,16384,65536
```

| test | stock `bdc23b56b` | bundle `285542d` | prism `f13265492` |
| --- | ---: | ---: | ---: |
| pp512 | 497.95 ± 13.16 | 488.19 ± 9.48 | **523.80 ± 8.88** |
| tg128 | 24.01 ± 0.66 | 25.78 ± 0.06 | **27.81 ± 2.03** |
| pp512 @ d16384 | 439.37 ± 22.84 | 425.28 ± 27.79 | **494.19 ± 32.57** |
| tg128 @ d16384 | 20.87 ± 1.12 | 21.16 ± 0.54 | **22.93 ± 1.45** |
| pp512 @ d65536 | 277.16 ± 5.51 | 264.90 ± 6.36 | **311.55 ± 13.03** |
| tg128 @ d65536 | 13.80 ± 0.28 | 14.17 ± 0.58 | **14.46 ± 0.40** |

The PTQ1_0 mat-vec kernel is worth about **+7% decode** here (stock 24.0 to bundle 25.8
tok/s), not the +53% it gives an RTX 3060 12GB. This is expected: stock decode is already at
about 153 GB/s of a ~256 GB/s card, so the kernel removes a bottleneck this card does not
have. The current `prism` build adds the prefill work (#216, in-place FA, hybrid dispatch):
**+5.8% pp512 and +14.5% pp512 at d65536 over the bundle**.

## MTP on the bundle: a 64K window with holes

Same bundle binary, `-ngl 99 -fa on -np 1 -ctk q4_0 -ctv q4_0`, `graft/probe.py` client
tok/s (thinking off, 400 max tokens, TTFT excluded, 3 prompts x 3 runs; mean / median of the
nine runs). `GGML_CUDA_BATCH_INVARIANT=1` unless noted; `draft-mtp` n-max as listed.

### 65536 full probe

| arm | file | spec | inv | mean | median | code / prose / bash |
| --- | --- | --- | --- | ---: | ---: | --- |
| base | base | off | on | 25.7 | 25.7 | 25.7 / 25.8 / 25.8 |
| lean | lean | n-max 1 | on | 32.4 | 33.6 | 34.6 / 28.7 / 33.9 |
| lean | lean | n-max 2 | on | 32.1 | 31.6 | 38.4 / 25.9 / 31.6 |
| lean | lean | n-max 2 | off | 32.6 | 31.9 | 40.2 / 26.7 / 31.9 |
| fat | fat | n-max 2 | on | — | 14.3 (short) | — |

The lean MTP head is worth **+23% median and lossless** at 64K on the bundle. The acceptance
is high (mean accepted length 2.3), so the head matches this ternary trunk well.

### Context scan on the bundle (short probe)

| ctx | short median |
| ---: | ---: |
| 65536 | 37.1 |
| 73728 | 37.3 (full: 30.0) |
| 77824 | **12.5** |
| 81920 | 35.2 |
| 86016 | **20.2** |
| 90112 | 18.3 |
| 98304 | 14.0 |

The bundle's window curve is **not monotonic**: 77824 and 86016 are holes. The same holes
appear on battery (77824 12.5, 86016 20.2), so they are an **allocation/build artifact on
this driver, not a power effect**.

### 98304: MTP collapses on the bundle

| arm | mean | median | code / prose / bash |
| --- | ---: | ---: | --- |
| base, no spec | 25.6 | 25.9 | 25.4 / 25.9 / 25.9 |
| lean, n-max 2, inv | 13.0 | 12.7 | 15.9 / 10.4 / 12.7 |

Base decode is unchanged at 98304, but MTP is **less than half** speed even with high
acceptance. On the bundle, 64K with the head (31.6) beats 96K with it (12.7); 96K without it
is 25.9. **Bundle rule: serve 64K with the lean MTP head, or a higher window without it.**

## Current prism (`f13265492`, #221): the MTP window reaches 88064

The 64K cap is a property of the **bundle**, not of the card. The same 8 GB card on the
current `prism` branch runs MTP to **88064**, at no loss against 64K.

Short-probe scan (lean, n-max 2, invariant):

| ctx | bundle | prism `f13265492` |
| ---: | ---: | ---: |
| 65536 | 37.1 | 42.9 |
| 73728 | 37.3 | 41.1 |
| 77824 | 12.5 | 39.9 |
| 81920 | 35.2 | 40.3 |
| 86016 | 20.2 | 40.1 |
| 87040 | — | 40.5 |
| 88064 | — | **41.4** |
| 89088 | — | **10.0** |
| 90112 | 18.3 | 10.3 |
| 94208 | — | 9.8 |
| 98304 | 14.0 | 9.5 |
| 114688 | — | 8.0 |
| 131072 | — | 7.8 |

The bundle's holes are gone; the cliff is a single step at **89088**. Full 3x3 probe:

| window | arm | mean | median | code / prose / bash |
| ---: | --- | ---: | ---: | --- |
| 65536 | lean MTP n2 inv | 36.0 | 35.8 | 42.2 / 29.0 / 35.8 |
| 88064 | base, no MTP | 27.1 | 27.1 | 27.0 / 27.2 / 27.1 |
| 88064 | lean MTP n1 inv | 35.6 | 36.2 | 39.6 / 31.5 / 36.2 |
| 88064 | lean MTP n2 inv | 35.8 | 36.1 | 41.3 / 30.4 / 36.1 |
| 88064 | lean MTP n2, no inv | 41.0 | 40.9 | 51.4 / 30.8 / 40.9 |

88064 costs nothing over 65536 (36.1 vs 35.8) for 34% more window. Identity at 88064
(`verify_identity.py`, greedy, invariant): all three prompts byte-identical, and a
1,500-token generation completed with no OOM (7,939 MiB peak). Server `print_timing` at
88064: off 26.49 / 26.31 / 26.25; on 41.66 / 31.73 / 34.83 (+36% mean).

**`GGML_CUDA_BATCH_INVARIANT=1` is not free on this build**: the hybrid dispatch forces the
one-column decode onto the PT layout, so invariance costs about 12% here (36.1 with against
40.9 without, at 88064). Keep it for a lossless speedup; drop it only if byte-identical
output does not matter.

**Prism rule: serve 88064 with the lean MTP head, `--spec-draft-n-max 1 or 2`, and
`GGML_CUDA_BATCH_INVARIANT=1` for a lossless ~36 tok/s median (+33% over base); without
invariance the same window runs ~41 but the greedy text is not byte-identical. The cliff is
89088; 98304 falls to ~9.5.**

## The fat MTP file does not fit an 8 GB card

The `bonsai2-small-gpu` MTP file carries a duplicate Q4_K embedding table
(`blk.64.nextn.embed_tokens.weight`, 682 MiB) that only exists for forks without the
Hadamard fix. At 65536 the CUDA0 model buffer is 6,412 MiB against the lean file's 5,730 MiB,
and the same-session probe drops to **14.3 tok/s** (short) from 37-42. The extra 682 MiB
pushes the 8 GB card past capacity and decode spills. The lean graft is both smaller and
about 2.7x faster here.

## Served VRAM

`nvidia-smi --query-gpu=memory.used`, after load and during the probe:

| file | 65536 | 88064 | 98304 |
| --- | ---: | ---: | ---: |
| base | 7,273 / 7,293 MiB | 7,477 / 7,497 MiB | 7,917 / 7,937 MiB |
| lean MTP | 7,899 / 7,921 MiB | 7,929 / 7,939 MiB | 7,919 / 7,939 MiB |
| fat MTP | 7,931 / 7,939 MiB | — | — |

## Power (AC vs battery)

The GPU memory clock is 7001 MHz on AC and drops to 5471 MHz on battery (nothing else
changes). Every AC number above was re-run on battery.

| arm (window) | AC | battery (63%) | delta |
| --- | ---: | ---: | ---: |
| bundle, base, 65536 | 25.7 | 20.7 | -19% |
| bundle, lean MTP n-max 2 inv, 65536 | 31.6 | 28.1 | -11% |
| prism, base, 88064 | 27.1 | 21.9 | -19% |
| prism, lean MTP n-max 2 inv, 88064 | 36.1 | 29.9 | -17% |

- **The maximum stable MTP window does not change with power.** The fast/slow cliff sits at
  **89088** on both AC and battery; 88064 is the largest window that runs full speed either
  way, and 98304 / 114688 / 131072 run at ~9 / 8 / 7.8 on AC and a proportionally lower
  ~5-6 on battery.
- Decode tracks the memory clock: about **15-20% lower on battery**, base and MTP alike. The
  MTP gain over base is preserved or slightly larger (prism +37% on battery against +33% on
  AC, because the base path is the more bandwidth-bound one).
- Losslessness is unchanged: `verify_identity.py` at 88064 is byte-identical on battery too.
- Battery throughput varies with charge and power state: one sample taken near 15% charge
  read the bundle MTP at 21.5 median where it reads 28.1 at 63%. Read the battery column as
  "about 15-20% down", not a fixed figure.
- The bundle's non-monotonic holes (77824, 86016) are identical on AC and battery, confirming
  they are not a power effect.
- The card's 50 W cap is the laptop's; no power-limit change, no overclock, no `--no-mmap`.

## Reproducibility

- The A/B and the probe tables were each run once in this session. This card is noisy across
  sessions: the bundle `tg128` alone has read 25.8, 27.8 and 25.8 tok/s on different days,
  so read the A/B as +5 to +8% decode, not a single figure.
- The 89088 cliff and the bundle holes were each reproduced more than once.
- The identity check is exact (three byte-identical greedy completions).

## Notes

- **WSL2 run.** Ubuntu 22.04.5 under `microsoft-standard-WSL2`, driver 595.95 exposed from
  Windows, CUDA UMD 13.2. The bundle is the cuda12.4 build and needs no toolkit; the two
  source builds were made with CUDA 12.4 and `-DCMAKE_CUDA_ARCHITECTURES=89`.
- Use `GGML_CUDA_BATCH_INVARIANT=1` with the head on `prism` for a lossless speedup; on the
  bundle it was free, on `prism` it costs ~12%.
- The current `prism` branch contains this repo's own PTQ1_0 kernel series (via #221), so a
  build from it does not need the `kernel/patches` applied by hand.
