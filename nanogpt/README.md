# nanoGPT

Study notes, notebooks, and experiments for Andrej Karpathy's GPT-from-scratch / nanoGPT lesson.

## Goals

- Understand the full character-level language-modeling pipeline from data loading to text generation.
- Rebuild the core Transformer blocks step by step: token embeddings, positional embeddings, self-attention, multi-head attention, feed-forward layers, residual connections, and layer normalization.
- Keep the first pass small enough to reason about tensor shapes, loss, and sampling behavior.
- Record mistakes and debugging notes as concrete review rules.

## Structure

```text
nanogpt/
  data/       raw or downloaded datasets
  docs/       learning plans, summaries, and mistake notes
  notebooks/  Jupyter notebooks for lesson work
  src/        reusable Python code, if needed later
```

## Dataset

The first-pass dataset is Tiny Shakespeare:

```text
nanogpt/data/tinyshakespeare/input.txt
```

Source:

```text
https://raw.githubusercontent.com/karpathy/char-rnn/master/data/tinyshakespeare/input.txt
```

## Recommended First Pass

1. Load `input.txt`, inspect length, unique characters, and `stoi` / `itos`.
2. Implement `encode` / `decode`.
3. Split `train_data` and `val_data`.
4. Implement `get_batch`.
5. Build the simplest bigram baseline and verify the loss.
6. Add the Transformer pieces one at a time, checking tensor shapes after each step.
7. Generate text after each meaningful checkpoint.

## Workflow

1. Watch a small section.
2. Rebuild the code in a notebook without copying large blocks blindly.
3. Pause and explain the data flow in Chinese, while preserving code names like `idx`, `targets`, `logits`, and `loss`.
4. Record repeated mistakes in `docs/`.
5. Commit stable checkpoints to git.
