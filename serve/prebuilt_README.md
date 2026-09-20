# bonsai2-small-gpu, Linux x86-64, CUDA 12.4, sm_86 + sm_89

A self-contained build of the PrismML llama.cpp fork with two changes for Ternary Bonsai 2 27B on consumer cards:

- the PTQ1_0 mat-vec kernel for small batches (PrismML-Eng/llama.cpp pull request 218): 1.5x single-token decode
  on an RTX 3060 12GB, 2 to 8 token verification batches at 1.2x to 1.8x the cost of one token instead of 1.5x to
  2.9x, and the `GGML_CUDA_BATCH_INVARIANT=1` switch that makes a token's logits bit-identical whether it is decoded
  alone or inside a batch of up to 4, so speculative decoding is lossless;
- the Hadamard fix for the qwen35 MTP draft graph (pull request 217), which lets the Qwen 3.8 MTP head grafted onto
  the ternary file draft from the trunk's own embedding table.

Source: branch `bonsai2` of github.com/sudoingX/llama.cpp, commit 8971d7b, which is PrismML-Eng/llama.cpp `prism`
at 9a9394a89 plus the two pull requests. Build: `cmake -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="86;89"
-DGGML_CUDA_FA=ON -DGGML_CUDA_GRAPHS=ON -DLLAMA_CURL=OFF -DGGML_NATIVE=OFF -DGGML_AVX2=ON -DGGML_FMA=ON
-DGGML_F16C=ON -DCMAKE_BUILD_TYPE=Release`, CUDA 12.4, GCC 11, Ubuntu 22.04.

## Runs on

- NVIDIA GPUs of compute capability 8.6 (RTX 3050, 3060, 3070, 3080, 3090, A2000 to A6000) and 8.9 (RTX 4060 to
  4090, RTX 6000 Ada). RTX 50 series (sm_120) is not included: CUDA 12.4 cannot target it; build the branch yourself
  with CUDA 12.8 or newer for those cards.
- NVIDIA driver 525 or newer. No CUDA toolkit needed: `lib/` carries the CUDA 12.4 runtime and cuBLAS.
- Linux x86-64 with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36 or newer) and a CPU with AVX2.

## Three lines

```
hf download prism-ml/Ternary-Bonsai-2-27B-gguf Ternary-Bonsai-2-27B-PTQ1_0.gguf --local-dir ~/models/bonsai2-27b
tar xzf bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-8971d7b.tar.gz && cd bonsai2-small-gpu-linux-x64-cuda12.4-sm86-sm89-8971d7b
./serve-12gb.sh
```

Then talk to `http://127.0.0.1:8899` (OpenAI-compatible, `/v1/chat/completions`, tools work with `--jinja`).

| script | file | context | VRAM after load (nvidia-smi, RTX 3060 12GB) | measured on the RTX 3060 12GB |
| --- | --- | --- | --- | --- |
| `serve-12gb.sh` | `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (original) | 262144 | 11,682 MiB | llama-bench tg128 40.4 tok/s fresh, 30.8 at 16K depth, 17.8 at 64K, 11.4 at 128K; pp512 267 |
| `serve-12gb-mtp.sh` | `Ternary-Bonsai-2-27B-PTQ1_0-mtp.gguf` (merged, with the MTP head) | 131072 | 10,622 MiB | 49.1 tok/s median over a code, a prose and a bash prompt (52.5 / 43.4 / 49.1), greedy output byte-identical to the same build without the head |
| `serve-8gb.sh` | `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (original) | 98304 | 8,002 MiB | needs the whole card; on an 8 GB card that also drives a display run it with `CTX=65536` (7,266 MiB) |

The lean merged file (`Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf`, no duplicate embedding table) runs with `serve-12gb-mtp.sh`
too: `MODEL=... ./serve-12gb-mtp.sh` loads at 9,940 MiB at 131072 and at 11,732 MiB with `CTX=196608`, same identical output.

Every script takes `MODEL`, `HOST`, `PORT` and `CTX` from the environment and passes extra arguments through to
`llama-server`. Set `MODEL=/path/to/file.gguf` if your models live elsewhere.

The merged file is the original PTQ1_0 file with the `blk.64` MTP tensors of Qwen3.8-27B appended (byte-exact,
reversible); the tools that make it are in github.com/sudoingX/bonsai2-small-gpu (`graft/`).

## Files

- `bin/llama-server`, `bin/llama-bench`, `bin/llama-cli`: the fork's binaries, RPATH set to `lib/`.
- `lib/`: libggml*, libllama, libmtmd and the CUDA 12.4 runtime (libcudart, libcublas, libcublasLt).
- `LICENSES/`: llama.cpp MIT (also the PrismML fork's license), NVIDIA CUDA EULA for the redistributed runtime.
- `SHA256SUMS`: `sha256sum -c SHA256SUMS` from this directory.

## Licenses

llama.cpp and the PrismML fork are MIT licensed (LICENSES/llama.cpp-LICENSE.txt). The CUDA runtime and cuBLAS
libraries in `lib/` are NVIDIA's, redistributed under the CUDA Toolkit EULA, Attachment A
(LICENSES/NVIDIA-CUDA-EULA.txt). Ternary Bonsai 2 27B is PrismML's, Apache 2.0; the MTP head is from Qwen3.8-27B,
Apache 2.0. Neither model file is in this archive.
