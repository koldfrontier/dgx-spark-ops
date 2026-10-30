# Swift 1.5 IQ3_S · Strata · one Tesla V100-PCIE-32GB

**Not a DGX Spark recipe.** This is the estate's V100 workstation: one 32 GB Volta card in a dual-Xeon box with
192 GB of RAM. It runs a 47 GiB-of-experts MoE at 262K context with [Strata](https://github.com/Niko1221/Strata).
Strata keeps the experts in pinned host RAM, caches the hot ones in VRAM, and computes the rest on the CPU. It lives
here because the method and the honesty rules are the same as for the Spark recipes.

| | |
|---|---|
| Engine | Strata 0.1.52 (`5e8a4cca`), CUDA 12.8 source build for sm_70 (`STRATA_EXPERIMENTAL_SM60`) |
| Checkpoint | [`ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF`](https://huggingface.co/ukisai/Swift-1.5-Qwen3.8-Flash-Next-GSQ-RCO-GGUF) IQ3_S (2 shards, 83.7 GB; 46.8 GiB of experts) |
| Context | 262,144 tokens, 8-bit KV, KV streaming (`--kv-resident 32768`) |
| Slots | **1** (`serve-s1`, measured fastest) or 2 (`serve-s2`) |
| Decode, one request | S1: 88-93 tok/s code, 62-66 prose (4K-128K); S2: 74-77 code, 52-60 prose |
| Throughput, 1/2/4 clients | S1 58 / 60 / 63 tok/s aggregate; S2 42 / 39 / 42 |
| Sanity | Strata's twelve standard-v1 checks: 12/12 |
| Last verified | 2026-10-30 on the reference box (see **Status**) |

Raw data for every number here (rows, configs, logs, the profile, the harness) is in Strata
[PR #4717](https://github.com/Niko1221/Strata/pull/4717)
(`bench/results/2026-10-30-community-v100-pcie-32gb-swift15-iq3s/`).

## What this recipe changes, and what each part is worth

Start from the config Strata's setup writes. Measured gains, against a 2-slot 262K config with none of these:

| Setting | Why | Measured |
|---|---|---|
| PR [#3411](https://github.com/Niko1221/Strata/pull/3411)'s 13 Volta environment switches (`STRATA_SIDE_MIXER=2` + 12 x `=1`) | Volta-tuned decode kernels. All are in 0.1.52 but opt-in: no sm_70 row in `nv_defaults.cpp` | **+8.6-10.5%** decode at 32K x 1; output byte-identical to the default path in 12/12 requests |
| `--kv-resident 32768` | The 262K KV cache lives in 3.1 GiB of pinned RAM; only 32K cells per attention layer stay in VRAM. The two 262K sessions shrink from 3.65 to 0.95 GiB each, and the expert cache grows from 7,478 to 11,877 slots | **+20-36%** decode, 128K included |
| one slot (`"parallel": 1`) | Frees the second session's VRAM for experts (12,845 slots) and stops two requests sharing one decode | with the two above: **+50-82%** over the reference, against +25-46% for two slots |
| `--vram-reserve-mib 768` | Every start left ~490 MiB free, under the engine's own 512 MiB paging warning (#2065) | 554 MiB free at start; the warning still shows at some request starts |

**Setup already writes `--kv-resident 32768`** when the context is 64K or more and the RAM holds the cache. Ours was
missing because the 262K config had been made by editing setup's 32K config. Re-run setup with the context you want,
or use `scripts/apply-v100-stack.py`, which adds it when missing.

**One slot or two.** On this card a second slot adds no throughput:
- ladder aggregate at 2 clients: 38.8 tok/s with two slots, 60.1 with one;
- two 128K requests sent together finish in 239 s on two slots and 211 s on one;
- with two slots, a request decodes at ~7 tok/s while the other's 128K prompt is read.

What one slot costs you is head-of-line blocking: a short request waits behind a long generation in progress. If your
clients include long agent turns and an interactive user, that is the trade to decide.

What did **not** help:
- `STRATA_ADAPT_NOWAIT=1 STRATA_ADAPT_LAG=2`, and the sm_60/sm_86 tables' extra switches;
- `--pool-cores 1-19`: 19 workers on the GPU's socket instead of 32 on both, inside the noise.
- `--prefill auto:32768` gave +4-9% prompt speed at 16K and above. It was the only setting that hit the card's 250 W
  power limit, and its output is not bit-exact on CUDA.

## Prerequisites

- **Driver 580**: the last branch with Volta (590+ dropped it). `nvidia-driver-580-server`, never the `-open` one.
- **CUDA 12.x toolkit** from the runfile, toolkit only (CUDA 13 cannot compile sm_70). Never add NVIDIA's CUDA apt
  repo: its metapackages pull a 590+ driver.
- **g++-14**: Ubuntu 26.04's default GCC is newer than CUDA 12.x accepts.
- **Ubuntu 26.04 / glibc 2.43 only:** patch six declarations in CUDA 12.8's `crt/math_functions.h` (see
  `scripts/build-sm70.sh`).
- **RAM:** the expert arena (47 GiB), the n-gram table kept in RAM with `--ple-io ram` (29 GB), and the streamed KV
  (3 GB at 262K) all sit in RAM beside the OS. This box has 192 GB; 128 GB is about the floor for this config.

## Setup

1. Clone Strata and run its setup once for this model; that fetches the pinned llama.cpp and writes
   `strata-<model>.json`. Give it `--context 262144`, so it writes `--kv-resident` itself.
2. `scripts/build-sm70.sh <strata checkout>` if you build yourself; setup's own build uses the same flags.
3. `python3 scripts/apply-v100-stack.py strata-swift-iq3_s-serve.json strata-swift-iq3_s-serve.json --slots 1`
   (or write to a new file). The result should match `config/strata-swift-iq3_s-serve-s1.json` apart from your paths.
4. Serve: `serve/server.py --engine strata --config <that file> --port 8080`.

## Finding your own values

- **`--kv-resident`** is cells per attention layer kept in VRAM. 32768 is what setup writes. The VRAM it frees is
  printed at start: `--batch: N slot sessions on CUDA0 (X GiB each)` and `expert cache N slots`. Compare those two
  lines with and without it.
- **Slots:** measure your own mix. `tools/conc2.py` and the ladder in the Strata PR folder send concurrent long
  requests and show whether a second slot buys anything on your card.
- **`--vram-reserve-mib`:** read `VRAM free with everything loaded` and the `WARNING: only N MiB of VRAM free`
  lines; raise it until the warning stops, and accept the few expert slots it costs.
- **Where the time goes:** `STRATA_VERIFY_PROFILE=1 STRATA_DECODE_TIMING=1` print a per-window breakdown.
  - On this box at 262K x 2 without KV streaming, a 61 ms window was 25 ms GPU work and 23 ms waiting for the CPU's
    experts.
  - At 32K x 1 it was 25 ms GPU and 6 ms CPU.
  - If CPU waits dominate, more experts in VRAM (the settings above) is the lever.
- **The CPU path.** On a CPU without AVX-512 VNNI (Skylake-SP and older) Strata's expert kernels run AVX2. perf showed
  the pool waiting most of the time, and PCM showed 3.5-7.5 GB/s of DRAM traffic against STREAM's 36 GB/s per
  socket: here it is not memory-bound.

## Verifying

- `bench/sanity12.py`: Strata's twelve standard-v1 sanity fixtures, scored as Strata's protocol says (temperature 0
  here). Expect 12/12.
- `bench/decode-bench.py`: two fixed prompts at 4K and 16K (and 128K). Compare its decode tok/s with the table above;
  every repeat should be a fresh engine start.
- Paths in both are placeholders; edit them.

## Trust notes

- **Strata** (`Niko1221/Strata`, MIT; sm_70 is an experimental build target, community-tested). The 13 switches
  come from an open, unmerged PR (#3411). We checked their effect on output ourselves (byte-identical in 12/12; one
  near-tie wording flip in 8 under the reproducible recipe, of the kind the reference itself shows across restarts).
- **Swift 1.5** is UkisAI's fine-tune of Qwen3.8-Flash-Next, licence "other" on its model card. We measured speed and
  the twelve functional checks, not quality.

## Security posture

- Strata's server binds `127.0.0.1:8080` with **no API key**. We publish it on the tailnet with `tailscale serve`,
  so anyone on the tailnet can use it.
- Strata answers 403 to a Host header it does not know (DNS-rebinding guard). Clients use the IP, or you add the name
  to `allowed_hosts` / `STRATA_ALLOWED_HOSTS`. Setting an `api_key` turns the check off: prefer a key if you expose
  it wider.

## Hardware notes (the reference box: HP Z6 G4)

- 2x Xeon Gold 6138, 192 GB DDR4-2666 with 3 of 6 channels per socket, Tesla V100-PCIE-32GB (passive, own blower) on
  PCIe Gen3 x16 (12.3 GB/s measured), NUMA on.
- **It froze twice under sustained full CPU and GPU load**: a hard hang with nothing in the logs, which panic-on-lockup
  did not catch.
  - Workaround in place: BIOS fan floors raised to 50%, and the CPU capped at 2.7 GHz (`scaling_max_freq`).
  - Cause not established; HP forum reports describe the same freeze on dual high-TDP Xeons in this chassis.
  - **Every number in this recipe is under that cap.**
- The V100 stayed at or below 77 C in these runs, with no thermal-violation samples.

## Files

- `config/strata-swift-iq3_s-serve-s1.json`, `-s2.json`: the serving configs as they run here (paths are
  placeholders).
- `scripts/apply-v100-stack.py`: setup's config -> this form.
- `scripts/build-sm70.sh`: the sm_70 build.
- `bench/sanity12.py`, `bench/decode-bench.py`: the checks above.

## Status

Serving on the reference box since 2026-10-30: S1, with Qwen3.8-Flash-Next IQ3_S's config in the same S1 form kept as
the fallback. That model gave 57.7 -> 92.9 tok/s (4K code) with the same change, sanity 12/12. Measured on 0.1.52;
newer Strata versions may change these numbers.

## License

Apache-2.0, as the rest of this repository.
