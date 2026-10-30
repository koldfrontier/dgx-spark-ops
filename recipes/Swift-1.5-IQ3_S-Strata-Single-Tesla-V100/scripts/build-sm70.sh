#!/usr/bin/env bash
# Build Strata's CUDA engine for a Tesla V100 (sm_70) from a Strata checkout, with the configure line Strata's own
# setup.py uses for an sm_70 card (Release, STRATA_EXPERIMENTAL_SM60, Q6_K experts, MMQ k-quants, the vendored
# llama.cpp), CUDA 12.8 and g++-14. Verified on Strata 0.1.52 (5e8a4cca), Ubuntu 26.04.1, CUDA 12.8.93, driver
# 580.178.04. Builds only.
#
# Usage: build-sm70.sh STRATA_CHECKOUT [BUILD_DIR]
#
# Before the first build:
#  - Run Strata's setup once (or its llama.cpp fetch): third_party/llama.cpp is not in Git; setup downloads the
#    commit pinned in setup.py (LLAMA_CPP_COMMIT).
#  - Ubuntu 26.04 (glibc 2.43): CUDA 12.8's crt/math_functions.h declares cospi/cospif/sinpi/sinpif/rsqrt/rsqrtf
#    without the noexcept glibc gives them, and nvcc stops with "exception specification is incompatible".
#    Strata's troubleshooting page names 12.9 only; 12.8.93 has it too. Patch those six declarations (append
#    `noexcept (true)` under `#ifdef __cplusplus`) and keep the original file.
set -eu
S=$(cd "$1" && pwd); B=${2:-$S/build-v100}
NVCC=/usr/local/cuda-12.8/bin/nvcc
[ -x "$NVCC" ] || { echo "no CUDA 12.8 at /usr/local/cuda-12.8 (CUDA 13 cannot compile sm_70)"; exit 1; }
[ -d "$S/third_party/llama.cpp/ggml" ] || { echo "no $S/third_party/llama.cpp: run Strata's setup once first"; exit 1; }
export PATH=/usr/local/cuda-12.8/bin:$PATH NVCC_CCBIN=g++-14 CUDAHOSTCXX=g++-14
cmake -G Ninja -S "$S" -B "$B" -DCMAKE_BUILD_TYPE=Release \
  -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_TESTS=OFF -DSTRATA_Q6K_EXPERTS=ON -DSTRATA_MMQ_KQUANTS=ON \
  -DCMAKE_CUDA_ARCHITECTURES=70 -DCMAKE_CUDA_COMPILER="$NVCC" -DCUDAToolkit_ROOT=/usr/local/cuda-12.8 \
  -DSTRATA_GGML_DIR="$S/third_party/llama.cpp" -DCMAKE_CUDA_HOST_COMPILER=g++-14 -DSTRATA_EXPERIMENTAL_SM60=ON
cmake --build "$B" --target strata -j "$(nproc)"
ls -la "$B/strata" && sha256sum "$B/strata"
