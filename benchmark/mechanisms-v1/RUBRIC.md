# Grading rubric: mechanisms-v1

Status: registered with the merge of its pull request. Do not change this file after registration.

You are a grader of 3D explainers that answer a learner's question about a mechanism. You do not know how the
explainers were made. Do not try to guess. Grade only what a learner can see.

There are two kinds of grading call:

1. **Score call:** one explainer (folder `output/`). Grade items (a) to (d).
2. **Preference call:** two explainers for the same question (folders `A/` and `B/`). Give item (e) only.

For the question you get `question.json`: the question text, the **conventional** configuration and the
**accepted variants** (other physically correct configurations), the key facts (with `core` flags, `appliesTo` and
`acceptedWordings`) and the five mechanism checks (`M1` to `M5`).

## The evidence

Each explainer folder holds:

- **Five stills** (`still-1.png` to `still-5.png`, 1280 × 800) at 10, 30, 50, 70 and 90 % of the explainer's
  length. Read the text in these.
- **Contact sheets** (`sheets/sheet-NN.png`): every frame at 10 frames per second for the whole explainer, at 1/5 size,
  in reading order (left to right, then top to bottom), with the time under each frame. Judge motion from these.
- **TEXT.txt:** the visible text, read by optical character recognition (OCR). It is an aid. If it differs from the
  images, the images win.

How to judge motion from the sheets:

- Follow a feature that does not repeat around the part: a pin, a crank, a label, a marker, a single spoke or arm.
- Prefer a non-repeating feature to gear teeth or other repeating patterns.
- **The motion limit (one boundary for every feature).** Between two consecutive frames, the feature you follow may
  move at most **one quarter of its repeat period**. A single feature (one pin, one marker) repeats once per turn, so
  its limit is a quarter turn (90°). A feature that repeats k times around the part (k teeth, k arms) has the limit
  90°/k, a quarter of its spacing. **At or below the limit:** judge the direction or ratio. **Above the limit:** answer
  CANNOT JUDGE for that direction or ratio, even if a direction seems to show; such motion can look reversed between
  frames.
- Timing: use the times under the frames. A frame step is 0.1 s.

## General rules

1. **Visible content only.** Text that is too small or too faint to read in the stills does not count as a claim, but
   it counts as a visual defect (d).
2. **Grey patches.** Some branding words and file names are covered by plain patches, in any explainer. A patch is
   not a defect and not an error. Ignore it.
3. **One finding, one place.** Do not count one fault twice in the same item. A fault can count in two items only when
   the rules below say so.
4. **Text against motion.** If the text is true but the animation shows something else, that is a mechanism failure
   (a), not a text error (b). If the text is false, it is a text error (b), also when the animation matches it.
5. **Evidence.** For every FAIL, CANNOT JUDGE, error and defect, give the still or the frame time (seconds) and one
   sentence of evidence.
6. **Strict but fair.** Accept correct statements in other words. Accept what `acceptedWordings` lists. Do not reward
   length. A short explainer that is correct can get the best scores.

## Judging limits (apply to every item)

1. **Invisible quantities are NOT SHOWN.** Mass flow, torque, force magnitude, friction, noise, self-locking and a
   small speed fluctuation cannot be seen in pictures. A check clause about such a quantity is NOT SHOWN unless readable
   values or calibrated graphics (a plotted trace, a labelled scale) show it. A still alone cannot show rotation or
   phase.
2. **Undersampled motion cannot fail direction or ratio.** The sheets are 10 frames per second. If the motion is too
   fast to follow between frames (above "The motion limit"), the direction or ratio is CANNOT JUDGE, not FAIL.
3. **Measurements need resolved features.** "Within 10 %" applies only when turns, teeth, angles or seconds are
   actually resolved. Arrows and decorative tooth counts are not measurements of hidden geometry.
4. **Labels are not calibration.** Readable numbers can support an explained relation, but they do not prove that an
   uncalibrated fluid animation (arrow widths, particle counts) shows the stated mass flow.
5. **Hidden is not broken.** A connection hidden behind another part is not evidence of a disconnection. Two parts that
   cross in the 2-D picture are not a 3-D collision unless the overlap is clearly solid.
6. **One configuration, consistently.** Identify the configuration the explainer shows (below) and grade it against the
   facts and check clauses for that configuration. Accept any physically correct accepted variant.

**Clause rule.** A check can have several clauses. Grade the check on its visible, applicable clauses. A clause that is
NOT SHOWN under limit 1, or N/A (below), neither passes nor fails the check; give it in the evidence. The check is NOT
SHOWN only when none of its applicable clauses is visible.

## Configurations and N/A

`question.json` names the **conventional** configuration and the **accepted variants**. First decide which one the
explainer shows: `conventional`, an accepted variant's id, or `unclear` (then use `conventional`).

**N/A (not applicable).** A key fact whose `appliesTo` does not include the shown configuration, or a check clause
written for another configuration, is N/A when the explainer shows a correctly explained accepted variant. An N/A item
is not a FAIL and not NOT SHOWN: it leaves both the numerator and the denominator of every score. A whole check is N/A
only if all its clauses are for other configurations. An explainer that shows a configuration that is neither the
conventional one nor an accepted variant is graded against the conventional one.

## (a) Mechanism correctness: five checks

Give each check `M1` to `M5` one result:

| Result | Definition |
| --- | --- |
| **PASS** | The explainer shows what the check asks, and nothing visible contradicts it. When an exact value cannot be measured (for example a speed ratio), PASS needs the visible behaviour to have the right sign and order (for example "the larger gear turns slower") and no stated value that contradicts the check. "Within 10 %" applies only where you can count turns, teeth, degrees or seconds. |
| **FAIL** | Something visible or stated contradicts the check: a missing connection, a wrong direction, a wrong ratio or timing, a part passing through another part, a link that changes length, an impossible arrangement. |
| **NOT SHOWN** | The explainer does not show the thing the check asks about: the part is missing, or the motion does not happen at all, or (limit 1) only an invisible quantity is asked. |
| **N/A** | Every clause of the check is for a configuration other than the shown accepted variant (see "Configurations and N/A"). |
| **CANNOT JUDGE** | Only for `M3` (direction) and `M4` (ratio or timing). The motion is shown, but the evidence does not let you decide: for example the feature you follow moves more than the motion limit between frames (more than a quarter of its repeat period: 90° for a single feature, 90°/k for a pattern that repeats k times), or every moving feature is too small to resolve. A repeating pattern that moves at or below its limit is judged. Give the reason. Do not use CANNOT JUDGE when the motion is missing (that is NOT SHOWN) or when you can see that it is wrong (that is FAIL). |

Kinds of check:

- **M1 parts.** All named parts are present and recognisable. A part named in text but not drawn is NOT SHOWN.
  Extra parts are allowed.
- **M2 connections.** The parts are joined as in the real mechanism (meshes, pins, shafts, guides, fixed members).
- **M3 direction.** Every motion has the right direction or sense, and fixed parts stay fixed.
- **M4 ratio or timing.** Speed ratios, step sizes, stroke timing and phase follow the key facts.
- **M5 geometry.** Nothing is impossible: no part passes through another part (gear teeth in mesh may touch, not
  overlap visibly), links keep their length, nothing floats without support, sizes that must match do match.

Static explainer: if nothing moves in the sheets, `M3` and `M4` are NOT SHOWN (no question in this set can be answered
without motion).

## (b) Text accuracy: error count and key-fact coverage

**Claim.** A claim is a statement about the mechanism, its physics or its use in the visible text: titles, captions,
labels, tables, numbers and legends. A label that only names a part is a claim that the named thing is that part.

**Error.** Count one error for each distinct false claim:

1. **Key-fact error (`K`).** The claim contradicts a key fact. Give the key fact id.
2. **Number error (`N`).** A stated number is wrong, or stated numbers contradict each other (for example the tooth
   counts and the stated ratio do not agree). Example values that the explainer calls examples are not errors when
   they are possible.
3. **Label error (`L`).** A label names the wrong part, or points to the wrong part.
4. **Other error (`O`).** The claim is false by established engineering or physics that the key facts do not cover.
   Give the principle in one sentence. When you are not sure, do not count it: list it as "unsure" instead.

Rules for counting:

- The same false claim repeated in several frames counts once.
- A vague or simplified statement that is not false is not an error ("the gears slow it down" is not an error).
- Missing a key fact is not an error. It lowers coverage and clarity instead.
- Hedged statements ("about", "typically", "in this example") are errors only if false even with the hedge.
- Statements about how exact the explainer is ("schematic", "schematic motion", "not checked", "not to scale",
  "simplified") are limitation labels, not claims about the mechanism. They are never errors.

Check claims only against the key facts that apply to the shown configuration. A claim that is correct for the shown
accepted variant is not an error because a conventional-only fact says otherwise.

**Coverage.** List the **core** key facts (`"core": true`) that apply to the shown configuration and that the explainer
states or shows clearly and correctly, in text or unmistakably in the visuals (`coveredFacts`). List the facts that are
N/A (`notApplicableFacts`). A core fact stated wrongly is not covered (and is an error). The analysis divides the covered
core facts by the applicable core facts. Every configuration in this set has at least 2 applicable core facts; if
none applied, coverage would be N/A for that explainer, and clarity would be judged without the core-fact parts of the
anchors.

## (c) Teaching clarity: ordinal scale 1 to 5

Judge how well the explainer teaches a learner with no background, as if its claims were true. Do not lower (c) for
errors that you count in (b), or for defects that you count in (d), unless they also make the explanation hard to
follow.

| Score | Anchor |
| --- | --- |
| **5 Excellent** | A learner could answer the question in their own words after seeing it once. The whole mechanism is shown first, then the key idea, step by step. Motion makes the cause and effect obvious. Each text appears when the matching motion is on screen. All applicable core key facts are present. Nothing is confusing. |
| **4 Good** | Answers the question. One small gap: one applicable core fact is missing, or one moment is confusing, or text and motion are out of step once. |
| **3 Adequate** | The main idea is present but takes effort: the order is confusing, or two applicable core facts are missing, or the text and the visuals are only loosely linked. |
| **2 Poor** | A learner would probably not get the answer. The key mechanism is hard to see, or the text is mostly generic, or most applicable core facts are missing. |
| **1 Very poor** | Does not answer the question, or shows a different mechanism, or is mostly unreadable. |

## (d) Visual defects: counts by type and severity

Count each distinct defect once per explainer, even if it shows in many frames. Give type, time and severity.

| Type | Definition |
| --- | --- |
| **D1 frame cut** | The frame edge cuts a part that a mechanism check names, or cuts text, so that its shape, label or motion is lost in a still or for more than 2 s. |
| **D2 clipping** | Parts visibly pass through each other where they should not (beyond gear teeth in contact), the camera clips into a part, or surfaces flicker (z-fighting). |
| **D3 unreadable text** | Text in a still with capital letters less than about 10 px high, text over other text, text with too little contrast to read, text cut off without an ellipsis, or missing characters. |
| **D4 label pointer** | A label or leader line points to empty space or to a part it does not name, or a label hides the part it names. (Also count a label error in (b) only if the label text is false.) |
| **D5 jump or flicker** | Within one scene, a part or the camera jumps between consecutive frames, or a part disappears for at least 0.1 s (one frame step or more) and comes back within 0.5 s. A deliberate scene change (a clean cut or fade to a new view) is not a defect. |
| **D6 empty frame** | A still, or more than 2 s of frames, shows nothing useful: blank, black, or the mechanism covers less than about 2 % of the frame. |

Severity:

- **Major**: the defect hides or confuses something a learner needs (a part named in `M1`, a core key fact, or the
  answer's main motion).
- **Minor**: anything else.

## (e) Pairwise preference: A, B or tie (preference call only)

Question to answer: **"Which explainer would you rather show a learner who asked this question?"** Decide in this
order:

1. Mechanism correctness (a). A clear difference here decides, unless the other explainer is far better on 2 and 3.
2. Text accuracy (b): fewer and less serious errors.
3. Teaching clarity (c), then visual defects (d).

Answer **tie** only if you cannot honestly prefer one. Give one sentence of reason. The order of A and B is random and
has no meaning.

## Answer formats

**Score call.** Return one JSON object and nothing else:

```json
{
  "question": "MECH-01",
  "output": "<output id given to you>",
  "configuration": "conventional",
  "mechanism": {"M1": "PASS", "M2": "FAIL", "M3": "CANNOT JUDGE", "M4": "NOT SHOWN", "M5": "PASS",
                "evidence": {"M2": "t=6.0 s: the two gears of the compound pair are on different shafts",
                             "M3": "only the gear teeth move; no single feature to follow",
                             "M4": "no motion is shown"}},
  "errors": [{"type": "K", "keyFact": "K3", "time": "10.0 s", "text": "quoted text", "reason": "one sentence"}],
  "unsure": [],
  "coveredFacts": ["K1", "K2", "K4"],
  "notApplicableFacts": [],
  "clarity": 4,
  "clarityReason": "one sentence",
  "defects": [{"type": "D3", "severity": "minor", "time": "14.0 s", "evidence": "one sentence"}]
}
```

**Preference call.** Return one JSON object and nothing else:

```json
{"question": "MECH-01", "pair": "<pair id given to you>", "preference": "A", "preferenceReason": "one sentence"}
```

Each check result is one of `PASS`, `FAIL`, `NOT SHOWN`, `N/A` and (for `M3` and `M4` only) `CANNOT JUDGE`. Do not
add totals: the analysis counts the lists. A separate later call may ask you other questions. It never changes
a grade.
