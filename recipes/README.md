# Recipes

Reproducible serving configs for specific model checkpoints on **dual DGX
Spark / ASUS Ascent GX10** clusters. Each recipe is a standalone directory:
launch scripts, what's genericized vs. what you need to fill in for your own
hardware, trust notes on any third-party image or toolkit involved, and
honest tuning/benchmark data from the hardware it was developed on — not
vendor claims taken at face value.

| Recipe | Checkpoint | Notes |
|---|---|---|
| [`SuperDeepseek-V4-Flash-abliterated-MQ-Dual-DGX-Sparks`](SuperDeepseek-V4-Flash-abliterated-MQ-Dual-DGX-Sparks) | [`Jiunsong/SuperDeepseek-V4-Flash-abliterated-MQ-2xDGX`](https://huggingface.co/Jiunsong/SuperDeepseek-V4-Flash-abliterated-MQ-2xDGX) | 304B-class MoE, 1M context, checkpoint author's forked vLLM runtime |
| [`Qwen3.8-Flash-Next-FP8-Dual-DGX-Sparks`](Qwen3.8-Flash-Next-FP8-Dual-DGX-Sparks) | [`Qwen/Qwen3.8-Flash-Next-FP8`](https://huggingface.co/Qwen/Qwen3.8-Flash-Next-FP8) | Native FP8, MTP speculative decoding, vision, 262K context |

## Conventions across recipes

- **Nothing in a recipe's example values (IPs, hostnames, NIC names) should
  be copied verbatim.** They describe the hardware a recipe was developed
  and measured on. Each recipe's own "Finding your own values" section
  explains what to check on your hardware instead, and why.
- **Benchmarks are from the hardware they were run on, not vendor
  marketing.** Where a recipe cites a throughput number, it says whether
  that number is a vendor claim, a reproduction of one, or an independent
  measurement — and includes enough method (concurrency levels, prompt
  sizes, what `/metrics` showed) to judge whether it transfers to your
  setup.
- **Third-party images and toolkits are trust-checked, not just used.**
  Each recipe that depends on one says what was checked (stars, account
  age, layer history, documented-vs-actual behavior) and where that trust
  bar is thin.
- **Security tradeoffs are stated, not silently made for you.** If a recipe
  binds an API to something broader than a private network by default, it
  says so and tells you how to tighten it.
