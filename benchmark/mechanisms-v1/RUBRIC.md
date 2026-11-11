# Grading rubric: mechanisms-v1

Status: pre-registered on 2026-11-11, before any benchmark run. Do not change this file after run 1
([PROTOCOL.md, Amendments](PROTOCOL.md#13-amendments)).

You are a grader. You see two outputs for one question: **Output A** and **Output B**. Each output is an artifact set:
five stills (at 2, 6, 10, 14 and 18 s), a 20-second video (or 20 frames from it at 1 s steps), and a text transcript of the
visible text (made by optical character recognition, OCR). You do not know how the outputs were made. Do not try to
guess. Grade only what a learner can see.

You also get, for this question, its entry in [QUESTIONS.json](QUESTIONS.json): the question text, the key facts
(`keyFacts`) and the five mechanism checks (`mechanismChecks`).

Grade each output on items (a) to (d) on its own. Then give the preference (e) for the pair.

## General rules

1. **Visible content only.** Grade the stills, the video and the visible text. The OCR transcript is an aid: if it
   differs from the images, the images win. Text that is too small or too faint to read in the images does not count
   as a claim, but it counts as a visual defect (d).
2. **Grey or blurred patches.** The harness covers some fixed words in both arms (file names and tool names). A covered
   patch is not a defect and not an error. Ignore it.
3. **One finding, one place.** Do not count one fault twice in the same item. A fault can count in two items only when
   the rules below say so.
4. **Text against motion.** If the text is true but the animation shows something else, that is a mechanism failure
   (a), not a text error (b). If the text is false, it is a text error (b), also when the animation matches it.
5. **Evidence.** For every FAIL, every error and every defect, give the still time or video time (seconds) and one
   sentence of evidence.
6. **Strict but fair.** Accept correct statements in other words. Accept the variants that a key fact's `note` lists.
   Do not reward length. A short output that is correct can score the maximum.

## (a) Mechanism correctness: five checks, score 0 to 5

Use the five checks of the question (`M1` to `M5`). Give each check one result:

| Result | Definition | Points |
| --- | --- | --- |
| **PASS** | The output shows what the check asks, and nothing visible contradicts it. When an exact value cannot be measured (for example a speed ratio), PASS needs the visible behaviour to have the right sign and order (for example "the larger gear turns slower") and no stated value that contradicts the check. "Within 10 %" applies only where you can count turns, teeth or degrees. | 1 |
| **FAIL** | Something visible or stated contradicts the check: a missing connection, a wrong direction, a wrong ratio, a part passing through another part, a link that changes length, an impossible arrangement. | 0 |
| **NOT SHOWN** | The output does not show the thing the check asks about (for example no motion at all, or the part is missing). | 0 |

Kinds of check:

- **M1 parts.** All named parts are present and recognisable. A part named in text but not drawn is NOT SHOWN.
  Extra parts are allowed.
- **M2 connections.** The parts are joined as in the real mechanism (meshes, pins, shafts, guides, fixed members).
- **M3 direction.** Every motion has the right direction or sense, and fixed parts stay fixed.
- **M4 ratio or timing.** Speed ratios, step sizes, stroke timing and phase follow the key facts.
- **M5 geometry.** Nothing is impossible: no part passes through another part (gear teeth in mesh may touch, not
  overlap visibly), links keep their length, nothing floats without support, sizes that must match do match.

**Score (a)** = number of PASS results (0 to 5).

Static output: if nothing in the video moves, M3 and M4 are NOT SHOWN unless the question can be answered without
motion (no question in this set can).

## (b) Text accuracy: error count, and key-fact coverage

**Claim.** A claim is a statement about the mechanism, its physics or its use in the visible text: titles, captions,
labels, tables, numbers and legends. A label that only names a part is a claim that the named thing is that part.

**Error.** Count one error for each distinct false claim:

1. **Key-fact error (`K`).** The claim contradicts a key fact of the question. Give the key fact id.
2. **Number error (`N`).** A stated number is wrong, or stated numbers contradict each other (for example the tooth
   counts and the stated ratio do not agree). Example values that the output calls examples are not errors when they
   are possible.
3. **Label error (`L`).** A label names the wrong part, or points to the wrong part.
4. **Other error (`O`).** The claim is false by established engineering or physics that the key facts do not cover.
   Give the principle in one sentence. When you are not sure, do not count it: list it as "unsure" instead.

Rules for counting:

- The same false claim repeated in several frames counts once.
- A vague or simplified statement that is not false is not an error ("the gears slow it down" is not an error).
- Missing a key fact is not an error. It lowers coverage and clarity instead.
- Hedged statements ("about", "typically", "in this example") are errors only if false even with the hedge.
- Words that only describe how the output was made, or how exact it is ("schematic", "not to scale", "simplified"),
  are not claims.

**Score (b)**: `errors` = the count (0 or more), with the list of errors (type, time, quoted text, reason).

**Coverage.** Also count `coverage`: the number of the question's **core** key facts (`"core": true`) that the output
states or shows clearly and correctly, in text or unmistakably in the visuals. A core fact stated wrongly is not
covered (and is an error).

## (c) Teaching clarity: ordinal scale 1 to 5

Judge how well the output teaches a learner with no background, as if its claims were true. Do not lower (c) for
errors that you count in (b), and do not lower it for defects that you count in (d), unless they also make the
explanation hard to follow.

| Score | Anchor |
| --- | --- |
| **5 Excellent** | A learner could answer the question in their own words after watching once. The whole mechanism is shown first, then the key idea, step by step. Motion makes the cause and effect obvious. Each text appears when the matching motion is on screen. All core key facts are present. Nothing is confusing. |
| **4 Good** | Answers the question. One small gap: one core fact is missing, or one moment is confusing, or text and motion are out of step once. |
| **3 Adequate** | The main idea is present but takes effort: the order is confusing, or two core facts are missing, or the text and the visuals are only loosely linked. |
| **2 Poor** | A learner would probably not get the answer. The key mechanism is hard to see, or the text is mostly generic, or most core facts are missing. |
| **1 Very poor** | Does not answer the question, or shows a different mechanism, or is mostly unreadable. |

A failed run (no artifact set) has clarity 0. You will not see failed runs; the analysis fills them in.

## (d) Visual defects: counts by type and severity

Count each distinct defect once per output, even if it shows in many frames. Give type, time and severity.

| Type | Definition |
| --- | --- |
| **D1 frame cut** | The frame edge cuts a part that a mechanism check names, or cuts text, so that its shape, label or motion is lost for a still or for more than 2 s of video. |
| **D2 clipping** | Parts visibly pass through each other where they should not (beyond gear teeth in contact), the camera clips into a part, or surfaces flicker (z-fighting). |
| **D3 unreadable text** | Text with capital letters less than about 10 px high at 1280 x 800, text over other text, text with too little contrast to read, text cut off without an ellipsis, or missing characters. |
| **D4 label pointer** | A label or leader line points to empty space or to a part it does not name, or a label hides the part it names. (Also count a label error in (b) only if the label text is false.) |
| **D5 jump or flicker** | Within one scene, a part or the camera jumps between consecutive frames, or a part disappears for less than 0.5 s and comes back. A deliberate scene change (a clean cut or fade to a new view) is not a defect. |
| **D6 empty frame** | A still or more than 2 s of video shows nothing useful: blank, black, or the mechanism covers less than about 2 % of the frame. |

Severity:

- **Major**: the defect hides or confuses something a learner needs (a part named in M1, a core key fact, or the
  answer's main motion).
- **Minor**: anything else.

**Score (d)**: `defectsMajor` and `defectsMinor` (counts), with the list.

## (e) Pairwise preference: A, B or tie

Question to answer: **"Which output would you rather show a learner who asked this question?"** Decide in this order:

1. Mechanism correctness (a). A clear difference here decides, unless the other output is far better on 2 and 3.
2. Text accuracy (b): fewer and less serious errors.
3. Teaching clarity (c), then visual defects (d).

Answer **tie** only if you cannot honestly prefer one. Give one sentence of reason. The order in which you saw the
outputs is random and has no meaning.

## Answer format

Return one JSON object and nothing else:

```json
{
  "question": "MECH-01",
  "pair": "<pair id given to you>",
  "outputs": {
    "A": {
      "mechanism": {"M1": "PASS", "M2": "FAIL", "M3": "PASS", "M4": "NOT SHOWN", "M5": "PASS",
                    "evidence": {"M2": "t=6 s: the compound gears are on different shafts", "M4": "no motion is shown"}},
      "errors": [{"type": "K", "keyFact": "K3", "time": "10 s", "text": "quoted text", "reason": "one sentence"}],
      "unsure": [],
      "coverage": 3,
      "clarity": 4,
      "clarityReason": "one sentence",
      "defects": [{"type": "D3", "severity": "minor", "time": "14 s", "evidence": "one sentence"}]
    },
    "B": {"...": "same fields as A"}
  },
  "preference": "A",
  "preferenceReason": "one sentence"
}
```

The scores follow from the lists: (a) is the number of PASS results; (b) is the length of `errors`; (d) counts
`defects` by severity. The analysis computes them; do not add totals.

## After the grade (blinding check, a separate call)

After your grade is stored, a new call shows you the same pair again and asks only: "Do you think A and B came from
different tools? If yes, which one used a dedicated 3D engine: A, B or cannot tell? Give one sentence." This answer
never changes a score ([PROTOCOL.md, Blinding](PROTOCOL.md#8-blinding)).
