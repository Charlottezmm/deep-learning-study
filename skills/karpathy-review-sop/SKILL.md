---
name: karpathy-review-sop
description: Run the established timed Karpathy review SOP for an already-watched lesson. Skip first-pass learning and generic study planning.
---

# Karpathy Review SOP

Use this skill only when the lesson has already been watched once. This is a consolidation workflow, not a first-pass learning workflow.

## Goal

Drive the user through a strict 3-hour consolidation loop:

1. Recall from memory before looking anything up
2. Compare against Karpathy's notebook with red/green differences
3. Write bounded variations to force transfer
4. Explain the lesson in plain language
5. Archive progress in a short structured note

Do not replace this workflow with a generic study plan.

## Operating Rules

- Treat failure to recall in Stage 1 as diagnosis, not failure.
- Hard-cut every stage by time. Do not let one stage sprawl and eat the rest.
- Only concept mistakes (`red`) justify replaying video.
- Syntax or API differences (`green`) do not justify replaying video.
- Prefer using the user's existing notebook and notes in this repo.
- If the user is working on a local Jupyter notebook, remind them to keep work on one machine only and save before switching machines.

## Stage Flow

### Stage 0 · Mind Map Scan · 10 min

Ask the user to write 3-5 bullets answering: "What did this lesson cover?"

Constraints:

- From memory only
- No notes, no notebook, no video

Your job:

- Check whether the bullets cover the lesson spine
- Point out major omissions or confusions
- Do not over-teach yet

### Stage 1 · Whiteboard Recall · 45 min

Have the user reconstruct these five items from memory:

1. Problem definition
2. Math derivation or loss formula
3. Algorithm skeleton or pseudocode
4. Interface with the previous lesson
5. Any unclear point marked with `?`

Constraints:

- No looking up concepts
- Karpathy notebook may be used only as a dictionary for API or syntax
- If they type in an editor, autocomplete should be off

Your job:

- Keep them honest about recall vs lookup
- Identify missing structure, not just wrong details
- If they stall, ask which of the five items is blocked instead of solving everything for them

### Stage 2 · Diff Against Karpathy · 30 min

Compare the user's reconstruction to Karpathy's notebook.

Diff labels:

- `Red`: conceptually wrong
- `Green`: different wording or implementation, but equivalent

Rules:

- Every `red` item must get a one-line explanation of why it is wrong
- `Green` items are not treated as problems
- This is the core stage; do not skip it

Your job:

- Be strict about the red/green distinction
- Avoid turning stylistic differences into fake errors
- If code is compared, you may help classify differences

### Stage 3 · Bounded Variations · 60 min

Have the user implement exactly two small, bounded variations.

Examples:

- bigram -> trigram
- NLL <-> cross-entropy equivalence
- add temperature to sampling
- change context width
- swap a manual step for an equivalent PyTorch primitive

Rules:

- Two variations only
- If stuck for 5 minutes, mark the block and move on
- Debugging errors may use AI help

Your job:

- Keep the variation bounded
- Reject open-ended "let's redesign the whole model" scope creep
- Push for transfer, not polish

### Stage 4 · Feynman Explanation · 20 min

Have the user explain the lesson as if teaching a friend who knows Python but not ML.

Format:

- Spoken explanation, or
- ~500 Chinese characters / words of written explanation

Your job:

- Find vague phrases
- Flag where the explanation hides behind jargon
- Treat "can't explain smoothly" as a sign of incomplete understanding

### Stage 5 · Archive · 15 min

End with exactly three lines:

1. What became clear
2. What is still stuck
3. What to resume next time

If the repo has a progress or session log, prefer appending there. Otherwise the user can simply reply in chat and later commit the checkpoint.

## Repo-Specific Defaults

For this repo, prefer these working files when relevant:

- `makemore/notebooks/makemore_lesson_02.ipynb`
- `makemore/docs/mistake_notes.md`
- `makemore/docs/session_log.md`

If the user is reviewing another Karpathy lesson, adapt the file targets but keep the SOP unchanged.

## What Not To Do

- Do not convert this into a passive summary session
- Do not answer the whole lesson before Stage 0 and Stage 1 expose recall gaps
- Do not let the user blur red vs green differences
- Do not turn Stage 3 into a large refactor or research project
- Do not treat notebook state bugs as learning progress; if the notebook is state-corrupted, recommend kernel restart and rerun from the relevant parameter-definition cells

## Default Kickoff

If the user asks to start the SOP, begin with:

1. Confirm the lesson and that it has already been watched once
2. Start Stage 0 immediately
3. Ask for 3-5 memory-only bullets

Do not begin with a long explanation of the workflow unless the user asks for one.
