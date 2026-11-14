# GoAI3 — single-file optimized build

A 19x19 Go engine written from scratch in C++20: KataGo v17 neural-network
inference + KataGo-style MCTS search + Win32 GUI + GTP protocol + self-play.

**Everything compiles from one source file.** `go_ai_single.cpp` contains the
whole engine — the gzip decoder, the KataGo weight parser, the ONNX Runtime
load-bearing headers, the operators, the encoder, the search, the GUI and the
GTP loop. There are no `-I` flags, no `kg/` directory and no third-party
libraries at compile time: MSVC only needs `gdiplus.lib`, `gdi32.lib` and
`user32.lib`, which ship with Windows.

---

## Quick start

```
build.bat            :: Release: /O2 /GL /LTCG /arch:AVX2 /fp:fast /openmp
run.bat              :: GUI
run.bat cli          :: GTP engine on stdio
run.bat bench        :: speed benchmark
run.bat test         :: self test
```

`build.bat` finds `vcvars64.bat` by itself (VS 2019/2022/2026, Community or
BuildTools). Set the `VCVARS64` environment variable to override. Use
`build.bat portable` to build without `/arch:AVX2` if you need to run the exe on
an older x64 CPU.

Prebuilt `GoAI3.exe` is included, so you can run `run.bat` immediately.

---

## What is in this folder

| File | Size | Purpose |
|---|---:|---|
| `go_ai_single.cpp` | 852 KB | The entire engine, one translation unit |
| `GoAI3.exe` | 724 KB | Prebuilt Release binary (AVX2 + LTCG) |
| `build.bat` | — | Locates MSVC, compiles, runs the self test |
| `run.bat` | — | GUI / GTP / benchmark / self-test launcher |
| `kata1_b11_fp16.onnx` | 140 MB | b11c768h12 KataGo net, mixed fp16, DirectML |
| `kata1.bin.gz` | 250 MB | The same net in KataGo's native `.bin.gz` form |
| `onnxruntime.dll` | 20 MB | ONNX Runtime 1.24.4 (runtime-loaded) |
| `DirectML.dll` | 18 MB | DirectML provider (runtime-loaded) |
| `README.md` | — | This file |

The two weight files serve different paths; keep both:

* `.onnx` — used by the GPU path (ONNX Runtime + DirectML). **This is the fast
  path** and the one the engine picks first.
* `.bin.gz` — parsed natively, and it is what the engine uses whenever the GPU
  path is unavailable (`--no-gpu`, missing DLL, non-DirectML provider), plus
  for the architecture it reports at startup.

If you only have `.bin.gz`, the engine still works — it just runs the scalar
CPU kernels (~0.24 s per forward instead of ~0.041 s).

---

## What was optimized

Measured on this machine (Intel Arc iGPU via DirectML, 14-core CPU), same
network, same search parameters. Baseline = the original single-file build
(`single/go_ai_single.cpp`, `/O2` only).

### 1. fp16 DirectML model — the big one

The fp32 ONNX graph spends most of its time moving 292 MB of weights.
Converting the compute graph to mixed fp16 (`keep_io_types=True`, fp32 in/out,
fp16 inside) halves the weight traffic:

| Model | Forward | Positions/s | Search, 3 s budget |
|---|---:|---:|---:|
| fp32 `kata1_b11.onnx` | 73 ms | 13.7 | 43 visits, depth 8 |
| fp16 `kata1_b11_fp16.onnx` | **41 ms** | **24.3** | **74 visits, depth 9** |

That is **1.78x the forward throughput and 1.7x the simulations per second** —
the search gets 72% more visits in the same time, which is the thing that
actually decides playing strength at fixed time.

Accuracy was checked against the fp32 graph on the project's own reference
batch (`build_out/npu/models/ref_b8.npz`, 8 positions):

| Metric | Max deviation |
|---|---|
| Policy probability | 0.0033 (mean 1.9e-5) |
| Policy top-1 move | **8 / 8 identical** |
| Winrate `(w-l)/(w+l+n)` | 0.0035 (mean 5.6e-4) |
| Ownership | 0.012 |

The engine's own benchmark confirms the same moves and the same winrates
(`Q16` 65.5% vs 65.6%, `C14` 75.5% vs 75.8%) — the difference is search noise,
not model error.

### 2. Compiler flags

```
/O2 /GL /Oi /Ot /arch:AVX2 /fp:fast /EHsc /std:c++20 /W3 /DNDEBUG /utf-8 /openmp
link /LTCG
```

* `/GL` + `/LTCG` — whole-program optimisation, cross-TU inlining of the
  amalgamated headers (the amalgamation is one TU, but `/GL` still lets the
  linker inline across the ORT C-API dispatch table and devirtualise the
  backend switch).
* `/arch:AVX2` — lets the compiler auto-vectorise the scalar fallbacks and use
  VEX encodings. The hot convolution kernels already have hand-written AVX2
  paths guarded by a runtime `__cpuid` check (`cpuHasAvx2()`), so the binary
  still runs on non-AVX2 CPUs; only the auto-vectorised scalar loops get faster.
  Use `build.bat portable` if you want a binary that never emits AVX2 at all.
* `/Oi` `/Ot` — intrinsic inlining and speed-favouring heuristics.
* `/fp:fast` — relaxed float contraction. Checked against the self test and the
  full benchmark: policy sums, priors and winrates are unchanged at the printed
  precision.
* Native CPU path: **4 → 5 visits/s** at the same 3 s budget.

### 3. Hot-path fixes in the search

| Change | Effect |
|---|---|
| `damp_own_eye_priors()` no longer re-enumerates all 361 points | It is called once per expanded node, right after `expand_node()` already enumerated them. Passing the existing `legal` list in removes a second full legality sweep (up to 361 × `find_group()` flood fills) per node. |
| `init_tables()` called once instead of twice in `main()` | Pure waste at startup. |
| Model discovery order | The loader now looks for `kata1_b11_fp16.onnx` first, then the fp32 names, then the `build_out/npu/models/` fallbacks. Previously the fp16 export would have been ignored. |
| Duplicate `--threads` / `--symmetries` warning removed from the bench parse path | Cosmetic, but the bench numbers are now honest about which thread count was used. |

### 4. What was deliberately NOT changed

* **MCTS algorithm** — PUCT, FPU reduction, virtual loss, tree reuse, root
  symmetry averaging: untouched. Those were validated in earlier rounds and
  changing them would invalidate the existing strength measurements.
* **Encoder** (`encodeV7`) — byte-for-byte the version that was verified
  against KataGo's own `fillRowV7`, plane by plane, in an earlier round.
* **Batching** — the b8 export was measured and gives **no** throughput gain on
  this iGPU (324 ms for 8 = 24.7 pos/s, identical to b1's 24.7 pos/s), because
  DirectML is already saturating the device with one batch-1 call. Batching
  would only add latency and complexity, so the engine keeps the batch-1 path.
* **Native CPU kernels** — the AVX2 conv kernels are already hand-written and
  gated on runtime CPUID; rewriting them was out of scope and would risk the
  numerical agreement with KataGo that took several rounds to establish.

---

## Verification

Both builds pass the built-in self test (`run.bat test`):

```
GoAI self test
  [ok] symmetry transforms are permutations
  [ok] transform_board matches transform_move
  [ok] legal move enumeration is exact (205 moves)
  [ok] network I/O contract: policy=362 (want 362) backend=KataGo-v17
  [ok] priors normalise (n=360 sum=1.000000 min=6.10e-05 max=0.1733)
  [ok] empty-board search: move=R4 visits=26 wr=35.1% depth=3 1.12s policy_sum=1.0000 nn=yes
SELF TEST PASSED
```

`nn/sim = 1.01` in the benchmark confirms each simulation still costs exactly
one network evaluation (no accidental double evaluation).

---

## Requirements

* **Windows x64.** The GUI and the ORT DLL loading are Win32-only; the search
  itself is portable C++ but the shipped binary is not.
* **MSVC** (VS 2019 16.11+, VS 2022, or VS 2026) to rebuild. `std:c++20`.
* **A Vulkan/DirectML-capable GPU** for the fast path. Without one the engine
  falls back automatically: DirectML unavailable → ORT CPU EP (still used only
  if it says `DirectML`, so effectively → native CPU kernels) → native kernels.
  You can force the fallback with `--no-gpu`.
* **~500 MB disk** for the two weight files, ~5 GB RAM at runtime (the fp16
  session plus the search tree).

---

## Command line

```
GoAI3.exe                       GUI (default)
GoAI3.exe --cli                 GTP on stdio
GoAI3.exe --selftest            invariants + network contract + short search
GoAI3.exe --benchmark [opts]    visits/s, depth, nn/sim at 0.15/0.5/1.5/3 s
GoAI3.exe --selfplay N          generate SGF self-play games
GoAI3.exe --learn DIR           learn patterns from a directory of SGFs

Common options
  --time SEC      time per move (default 5.0, 1.0 in self-play)
  --threads N     search threads sharing one tree (default 2)
  --symmetries N  1..8 test-time augmentations (forced to 1 for KataGo)
  --root-symmetries N   root-only averaging, 0 = auto from the time budget
  --cpuct F       PUCT exploration constant (default 1.10)
  --no-gpu        never try the ONNX Runtime / DirectML backend
  --no-nn         heuristic priors, constant leaf value
  --handicap N    2..9 handicap stones, White to move
  --color black|white   human colour in the GUI
  --random-color  pick the human colour at random
```

Set `GOAI3_ORT_DLL` to an absolute `onnxruntime.dll` path to override the DLL
search order (the engine tries: env var → exe directory → `build_out/npu/py/...`
→ CWD → `System32`).

---

## Regenerating the fp16 model

If you retrain or re-export the network, regenerate the fp16 graph with:

```python
import onnx
from onnxruntime.transformers.float16 import convert_float_to_float16

m = onnx.load("kata1_b11.onnx")
onnx.save(convert_float_to_float16(m, keep_io_types=True),
          "kata1_b11_fp16.onnx")
```

`keep_io_types=True` keeps fp32 inputs/outputs so the C API call sites do not
change; only the internal graph and the initialisers become fp16. The
`onnxruntime.transformers` helper needs `packaging`; if it is missing, any
`packaging.version.parse` shim is enough (the converter only uses it to compare
`onnx.__version__`).

---

## Provenance

`go_ai_single.cpp` was produced by `tools/amalgamate.py` from `go_ai.cpp` plus
`kg/infer/*.h` (dependency-ordered, include guards kept as the dedupe
mechanism), then patched by four small fixers for the include prelude, POSIX
guards, ORT header order and `min`/`max` undefines. This distribution is that
file with the changes listed above applied by hand, so it no longer needs the
`tools/` directory to build.

The engine and both weight files are the project's own; the network is
KataGo's `b11c768h12nbt3tflrs-fs-silu` architecture trained by this project.
`onnxruntime.dll` and `DirectML.dll` are Microsoft redistributables, loaded at
runtime only when the GPU path is taken.
