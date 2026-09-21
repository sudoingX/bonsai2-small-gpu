# reasoning_effort: the template default (xhigh) against medium, measured on the RTX 3060 12GB

## What the template does (read from the GGUF, the template dump)

`tokenizer.chat_template` of `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (8,952 characters) contains, when thinking is enabled
(`enable_thinking` undefined or true):

```
{%- set resolved_reasoning_effort = reasoning_effort|default('xhigh') %}
{%- if resolved_reasoning_effort not in ('xhigh', 'medium', 'low') %} ... raise_exception ...
{%- if resolved_reasoning_effort == 'xhigh' %}
    {%- set reasoning_instructions = 'Reasoning effort is set to xhigh. Please think carefully through the task, validate key assumptions, consider plausible alternatives, and prioritize correctness, consistency, and clarity in the final answer.' %}
{%- elif resolved_reasoning_effort == 'low' %}
    {%- set reasoning_instructions = 'Reasoning effort is set to low. Keep your thinking brief and focused, moving directly to the conclusion without unnecessary elaboration.' %}
```

`medium` sets no instruction. The server's `/apply-template` confirms it : the default prompt for a one-line
user message starts with `<|im_start|>system\nReasoning effort is set to xhigh. Please think carefully ...<|im_end|>`, the `medium`
prompt has no system message and still opens `<think>`, `enable_thinking: false` opens and closes `<think>` at once.

## Every way to change it on this fork's server (common/arg.cpp, tools/server/server-common.cpp, tools/server/server-chat.cpp)

1. `--reasoning-effort LEVEL` server flag (env `LLAMA_ARG_REASONING_EFFORT`), `default` keeps the template default. Present on the
   prebuilt prism-b10685 `llama-server` and on the `bonsai2` bundle binary (both `--help` outputs checked).
2. `--chat-template-kwargs '{"reasoning_effort":"medium"}'` server flag.
3. Per request: the OpenAI field `"reasoning_effort": "medium"` on `/v1/chat/completions` (`none` disables reasoning), or
   `"chat_template_kwargs": {"reasoning_effort": "medium"}`; the Responses-style `reasoning: {effort}` is mapped to the same field.
4. `--chat-template-file` with an edited template.

Related: `--reasoning-budget N` caps thinking tokens server-side, `--reasoning-budget-message` injects a line before the forced
close. Neither was measured here.

## Measurement

Original file, the `bonsai2` bundle build (8971d7b) `llama-server`, `-ngl 99 -fa on -c 65536 -np 1 -ctk q4_0
-ctv q4_0 --jinja`, greedy (`temperature 0, top_k 1`), `/v1/chat/completions`, two runs per cell, two client caps (`max_tokens` 4096,
the common client default, and 16384). Thinking tokens = server `reasoning_content` counted with `/tokenize`; content tokens likewise;
generated = `usage.completion_tokens`. Complete = SVG contains `<svg` and `</svg>`; HTML contains `<html` and `</html>`; Python parses
with `ast` and has at least 100 non-empty lines. Runs 1 and 2 were identical in every cell (greedy).

Tasks: SVG = the prompt from professorpalmer's `bench/reason_ab.py` with the subject he lists first, "Draw a five-tier pagoda as a
single self-contained SVG. No markdown, no explanation, inline SVG only. Temperature-0 style: clean geometric shapes, white background.";
HTML = a single self-contained to-do list page with localStorage; Python = a key-value store CLI of at least 100 lines with a self-test.

| cap | effort | task | finish | generated tokens | thinking tokens | content tokens | complete | wall s (run 1, run 2) |
|---:|---|---|---|---:|---:|---:|---|---|
| 4096 | default (xhigh) | svg_pagoda | length | 4096 | 4096 | 0 | no, empty | 107.6, 107.6 |
| 4096 | default (xhigh) | html_todo | length | 4096 | 4096 | 0 | no, empty | 107.7, 107.6 |
| 4096 | default (xhigh) | python_kv | length | 4096 | 4096 | 0 | no, empty | 107.7, 107.6 |
| 4096 | medium | svg_pagoda | stop | 2238 | 1610 | 625 | yes | 57.7, 57.7 |
| 4096 | medium | html_todo | stop | 1758 | 22 | 1733 | yes | 45.2, 45.2 |
| 4096 | medium | python_kv | length | 4096 | 2381 | 1713 | no, cut inside the code | 107.6, 107.6 |
| 16384 | default (xhigh) | svg_pagoda | length | 16384 | 16384 | 0 | no, empty | 477.2, 476.9 |
| 16384 | default (xhigh) | html_todo | stop | 12988 | 7839 | 5145 | yes | 368.0, 367.7 |
| 16384 | default (xhigh) | python_kv | stop | 11936 | 9536 | 2397 | yes | 335.0, 335.2 |
| 16384 | medium | svg_pagoda | stop | 2238 | 1610 | 625 | yes | 57.7, 57.5 |
| 16384 | medium | html_todo | stop | 1758 | 22 | 1733 | yes | 45.2, 45.0 |
| 16384 | medium | python_kv | stop | 4679 | 2381 | 2295 | yes | 123.5, 123.4 |

## Reading

- At the 4,096-token client cap the template default returns nothing on all three tasks (6 of 6 runs spend the whole cap inside
  `<think>`). `medium` completes the SVG and the page inside the cap; the 100-line script needs about 4,700 tokens and is cut.
- At a 16,384-token cap the default completes the page and the script after 7,839 and 9,536 thinking tokens (6.1 and 5.6 minutes on
  this card) and never finishes thinking about the pagoda (16,384 tokens, 8 minutes, empty). `medium` completes all three in 45 to
  124 seconds with 22 to 2,381 thinking tokens; on the two tasks both settings complete, medium uses 7.4x and 2.6x fewer tokens.
- The empty-SVG and truncated-code reports are reproduced by the default, on this card, on the original file, with the bundle build.

Decision: `medium` measurably helps. The serve scripts in `serve/` and in the prebuilt bundle get `--reasoning-effort medium`; the README says what it does and what it costs. The tarball already on Hugging Face still carries the old scripts until it is re-uploaded. `--reasoning-budget` was not measured and is not set.
