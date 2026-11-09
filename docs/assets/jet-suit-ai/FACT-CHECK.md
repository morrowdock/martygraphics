# Independent fact check of the AI jet-suit lesson (`r2j-opus-1`)

Date: 2026-11-09. Two AI models with web access checked the AI-written lesson after it was graded:

- **GPT-6.1 Sol** (web; 61 claims). It saw the lesson, the follow-up answer, the stills and the model's research reply.
- **Gemini 4 Argon** (web; 19 claims). Blind: it saw only the lesson, its summary, the follow-up answer and the stills.

Neither checker saw the grader's fact key, the grading or earlier checks. A coordinator model (Claude Opus 5.5) merged
the two reports. **Rule: where the checkers disagree, the stricter label wins.** These are AI model checks with web
access, not a review by a jet-suit engineer.

**Verdict (both checkers): public with fixes.** The core of the lesson is not wrong: the engine layout, the hover
balance, steering with the arms, the gas-turbine path and the one shaft. It has **1 wrong sentence** (C1), several "not
found in this search" gaps where good public sources exist, a version-scope problem in the table, and weak wording.
In all: **1 wrong sentence and 12 corrections.**

**The lesson is shown unedited.** These corrections are not applied to the AI output by hand. They go back to Marty and
the engine for later rounds.

## Corrections

| # | Where | AI lesson says | Correction | Label (merged) | Sources |
| --- | --- | --- | --- | --- | --- |
| C1 | Beat 7 | "The hot gas spins the turbine at 1 turn per input turn" (marked solved) | **WRONG.** The engine solves only the animation ratio: compressor and turbine turn together on one shaft (1:1). It does not calculate gas flow or engine speed. The hot gas expands through the turbine and turns it; the turbine drives the compressor. | WRONG (both) | The lesson's own limits; JetCat P220 catalogue; NASA Glenn |
| C2 | Beat 2, label "Total thrust" | "not found in this search" | A public figure exists: about 144 kgf (317 lbf) total for the five-engine suit, reported by AOPA, 8 Oct 2020. Reported, not measured independently. Not calculated by the lesson. | WRONG as a gap (Gemini) / misleading (Sol) | AOPA 2020-10-08 |
| C3 | Beat 5, label "thrust split" | "not found in this search" | ASME (12 Jul 2019) reports a tripod of thrust: roughly one third on each arm and one third on the back, for the older suit. Approximate; changes with throttle and arm angle. Mk4 split not confirmed. | WRONG as a gap (Gemini) / misleading (Sol) | ASME "Iron Man Lives" 2019-07-12 |
| C4 | Title, label "Daedalus suit 2018" | "Daedalus layout", "claimed" | Name the layout by what is documented: "five-engine layout reported in 2018 (two per arm, one on the back)". The layout is VERIFIED (not only "claimed"). "Daedalus" is a press codename (The Manual, 2018), not a confirmed model name; do not use "Mk2/Mk3" either (no primary source). | VERIFIED layout; name CLAIM | WIRED 2018-11-09; TIME 2018-11-15; AOPA 2020; The Manual 2018-08-02 |
| C5 | Board table | "Dry wt kg 27 · F11 IntEng"; "Flight min 3 · F12 IntEng"; beat 3 calls them figures "for the current suit" | Source cells must be readable: "About 27 kg before fuel — Interesting Engineering, 28 Oct 2026" and "About 3 min — Gravity, Defence page (accessed 9 Nov 2026)". The sources do not state the suit version; do not call them "current suit" figures. | CLAIM (both); scope misleading | Interesting Engineering 2026-10-28; gravity.co Defence page |
| C6 | Beat 4, arrow text, follow-up answer | Steering "claimed, not checked"; "the body moves that way" | Arm steering is VERIFIED. Say: moving the arms aims the arm-engine thrust; this changes the total force and the turning moment; the lesson does not calculate the resulting motion. Do not state a direction. | VERIFIED method; direction not calculated (Sol, stricter) | Gravity Defence page; WIRED 2018; NASA Glenn |
| C7 | Beat 6 | Diffuser "squeezes" the air | The compressor wheel speeds the air outward and raises its pressure; the diffuser slows it and raises its static pressure. | Imprecise (Sol) | FAA-H-8083-32B glossary; JetCat |
| C8 | Label | "Engines likely micro gas turbines" | Gravity uses small gas-turbine jet engines (VERIFIED). The cutaway is a generic single-shaft turbojet, not a verified drawing of a Gravity engine; show that on every cutaway beat. | VERIFIED class; geometry schematic | Browning interviews; JetCat |
| C9 | Label "Fuel" | "Jet A-1 or diesel in a back bladder", shown beside the arm-engine cutaway | Fuel: Jet A-1 or diesel (reported). The older suit carries fuel in bladders beside the back engine; not shown in the model. Not an engine-internal store. | VERIFIED fuel; location scoped | WIRED 2018; ASME 2019 |
| C10 | Label "Mk4 per arm" | "not found in this search" | Gravity's page says Mk4 has "micro jet arm engines" and "three additional micro turbines in the back". It does not state a per-arm count. Two per arm is PLAUSIBLE from secondary coverage only. | PLAUSIBLE (stricter: Sol) | gravity.co/innovation |
| C11 | Summary text (Marty's run summary; not in the stills) | Mentions power and the 2019 speed record | Neither appears in the lesson. Remove. (If added: Guinness 85.06 mph / 136.891 km/h, 14 Nov 2019, a measured record.) | WRONG for this document (Gemini) | Guinness |
| C12 | Legend line | "Solved 19 · Given 1 · Not checked 16" | Can read as 19 verified facts. Solved items are animation ratios only; no flight force is calculated. | Misleading framing (Sol) | — |
| C13 | Beat 2 still | Weight arrow drawn beside the arm | Weight acts at the combined centre of mass; the arrow shows direction only. | Visual (both) | NASA Glenn |

## Where the checkers disagreed

- **Mk4 engines per arm.** Gemini: two per arm (maker page plus secondary coverage). Sol: the maker page gives no
  per-arm count, and sources conflict. Merged: PLAUSIBLE, not stated by the maker (C10).
- **"Mk2/Mk3" names.** Gemini only, with no primary source. Not used.
- **Flight time "3–4 min, max 8–10".** Gemini only. Merged: "about 3 min" (Gravity Defence page).
- **Steering direction ("pushes to the pilot's right").** Gemini only. Merged: direction not calculated (Sol, stricter).
- **The 2017 six-engine rig.** The checkers and earlier sources give different layouts. This lesson does not need it,
  so it is not in the panel. A later check is pending.
