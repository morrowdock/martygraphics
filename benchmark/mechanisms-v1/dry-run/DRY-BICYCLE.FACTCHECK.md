# DRY-BICYCLE first fact check

Status: first source check complete; independent second check PASS. Refreshed: 2026-11-13 UTC.
Source: [FACTCHECK-2](DRY-BICYCLE.FACTCHECK-2.md), checked 2026-11-12 at
`9bfa0746a4bdbee738361b5b8531741faa00da08`: 19 PASS, 0 FIX.

Checked: 2026-11-12 UTC. Base: `9e95ad3d69a54bce75b1a86d5b136734fb3ddb84`.

Sources: [source record](DRY-BICYCLE.SOURCES.md), [grader view](DRY-BICYCLE.grader.json),
[rubric](../RUBRIC.md), [protocol](../PROTOCOL.md), `../harness/score.py`,
`../harness/rubric_form.py`, and `../tools/grader_questions.py`.

This file remains the research author's first check. The independent second
check is now recorded separately in [FACTCHECK-2](DRY-BICYCLE.FACTCHECK-2.md).
The full two-arm dry run required by PROTOCOL section 2.4 has not been run by this task.

## Scope and isolation

- New question ID: `DRY-BICYCLE`. It is outside the registered set and must not enter the
  registered question list, hashes, lock, run statistics, or registered grader-view file.
- The JSON is one grader-view document: `kind` and a one-entry `questions` array. It has
  exactly the existing grader-view field names, types and nesting, with no research metadata.
- The registered grader file was read only to extract its schema, suppressing all scalar
  values. No registered question content was used, reported, or shared with another agent.
- The accepted configurations are `conventional`, `single-speed-freewheel`, `hub-gear`, and
  `fixed-gear`. Each has five applicable core facts. Conditional clauses remain conditional.
- There are five core facts and four non-core facts. Freewheeling, derailleur selection,
  chainline detail and the fixed-gear exception are not additional core-coverage requirements.

## Per-fact review

PASS means the final wording agrees with the cited evidence and the stated assumptions.
FIX -> PASS records a qualification applied during drafting, not a defect left unresolved.

| Fact | Core | Result | Check against sources and final restriction |
| --- | --- | --- | --- |
| K1 | Yes | PASS | S1 explicitly describes tooth contact, and S2 analyses chain load on the bicycle rear sprocket. The chain transmits drive through engagement, not smooth-pulley friction; the rear connection can be a clutch, internal hub drive, or fixed coupling. |
| K2 | Yes | FIX -> PASS | S2 puts chain tension at the top of the rear sprocket; S5 explicitly tensions the lower section. The final text says tighter upper run under forward drive, not zero lower tension, and excludes coasting and fixed-gear braking. |
| K3 | Yes | PASS | S3 gives C/S for the external speed ratio. Whole-turn tooth accounting in S1 gives rear sprocket revolutions per crank revolution, not the inverse. A clearly defined reciprocal convention is acceptable. No instantaneous constant chain speed is required. |
| K4 | Yes | FIX -> PASS | S3 gives circumference times front/rear teeth times internal ratio. The final text distinguishes rear sprocket from wheel, defines h as wheel/sprocket turns, and applies development only to engaged drive with rolling without tyre slip. |
| K5 | Yes | FIX -> PASS | From S3 and S4, equal ideal power gives torque gain 1/(R*h). Larger rear teeth increase this gain at fixed chainring and h, but reduce speed at fixed cadence. At fixed speed they require higher cadence. The final text states the ideal lossless steady-drive assumption and does not promise extra power. |
| K6 | No | FIX -> PASS | S6 describes one-way drive and coasting. The final text separates freewheel/freehub placement and excludes the fixed-gear configuration. The hub variant is explicitly a coasting internal hub, not every possible hub design. |
| K7 | No | PASS | S5 explicitly describes rear sprocket selection. The sprockets themselves do not grow or lose teeth. Applies only to conventional; S3 supports an internal ratio change without an external sprocket shift. |
| K8 | No | FIX -> PASS | S7 defines effective chainline and says perfect front/rear alignment is not universal. The final text allows ordinary lateral chain angles without endorsing arbitrary cross-chaining or assuming a numerical allowable angle. |
| K9 | No | PASS | S8 explicitly distinguishes a single-speed fixed gear from a freewheel-equipped bicycle. Coasting with stationary pedals is incompatible with the fixed-gear coupling. Applies only to fixed-gear. |

No contested efficiency percentage, universal “perfect chainline,” unlimited cross-chaining,
or universal coasting requirement is included. K5's comparison is per crank torque, not per
pedal force unless crank length is also held fixed. Fixed-gear gearing comparisons mean
alternative sprocket setups, not a nonexistent in-motion derailleur shift.

## Independent arithmetic within this first check

These are synthetic examples, not copied question content or measured bicycle performance.
Use a direct drive, 48 front teeth, wheel circumference 2.1 m, cadence 60 rpm, and ideal
crank torque 40 N m. Wheel speed means revolutions per minute, not road speed.

| Rear teeth | R | Wheel rpm | Distance/crank turn | Road speed | Ideal wheel torque |
| --- | --- | --- | --- | --- | --- |
| 16 | 3 | 180 | 6.3 m | 6.3 m/s | 40/3 N m |
| 24 | 2 | 120 | 4.2 m | 4.2 m/s | 20 N m |

The 24-tooth setup needs 90 rpm, not 60 rpm, to hold 6.3 m/s. With the 16-tooth setup
and an illustrative hub factor h = 0.5, wheel/crank ratio is 1.5, rollout is 3.15 m, and
ideal wheel torque is 80/3 N m. The factor 0.5 is an arithmetic example, not a claimed
available ratio of a particular manufacturer's hub. All cases preserve ideal input/output
power, and the direct-drive torque example must not be applied unchanged to the hub case.

## Mechanism-check review

| Check | Rubric meaning | First-review result |
| --- | --- | --- |
| M1 | Parts | PASS: names recognisable drive components; derailleur and internal hub requirements are configuration-specific. Does not require microscopic rollers or a cutaway clutch. |
| M2 | Connections | PASS: continuous toothed chain path and appropriate rear drive; accepts hidden hub connections and temporary engagement changes during a correctly shown shift. |
| M3 | Direction | PASS: same-sense sprocket rotation for the uncrossed layout; upper chain travels toward the front chainring, not toward the rear. Coasting and fixed-gear cases are distinguished. Applies the sampling rule before judging direction. |
| M4 | Ratio or timing | PASS: counts whole turns, includes h, and gives the sign/order rule where exact measurement is unresolved. Invisible torque is NOT SHOWN rather than inferred from decorative arrows. Visible clauses can still determine the check. |
| M5 | Geometry | PASS: constant link length, articulation, compatible resolved pitch, support and nonpenetration. Does not mistake lateral chain angle, hidden parts or a flat-image crossing for a physical failure. |

Static motion receives NOT SHOWN for M3/M4. Moving but unresolved or undersampled direction
or ratio receives CANNOT JUDGE, not FAIL. CANNOT JUDGE is not a valid state for M1/M2/M5.
The 10 percent measurement rule applies only when teeth, turns or time can actually be resolved.

## Validation

Validation uses only this new key and synthetic replies. It does not ask the harness to read
the registered question set. The results below are loader/form checks, not scores of real
rendered explainers and not evidence that either generation route has completed a dry run.

Executed from the repository root with Python 3 on 2026-11-12 UTC:

| Validation | Result |
| --- | --- |
| Exact allowed fields, scalar/list types, unique IDs, one-sentence question and M1-M5 kinds | PASS |
| Nine facts, five core; known applicability IDs; five applicable core facts in each of four configurations | PASS |
| `score.load_key` on a temporary copy containing only this new document | PASS: one question, `DRY-BICYCLE`, loaded with its raw grader view intact |
| `rubric_form.check_text` on one synthetic score reply for each accepted configuration | PASS: four accepted replies with configuration-specific N/A lists |
| `rubric_form.check_text` on static and undersampled synthetic replies | PASS: NOT SHOWN accepted for static M3/M4; CANNOT JUDGE with timed evidence accepted for moving but undersampled M3/M4 |
| Negative form checks | PASS: rejected unknown fact ID, non-core fact in coveredFacts, M1 CANNOT JUDGE, FAIL without evidence, and unknown configuration |
| Existing `tools/grader_questions.py` forbidden-word function, called on this key only | PASS: no forbidden words; its registered-file build functions were not called |
| Exact-fraction arithmetic for both direct-drive examples, fixed-speed cadence, illustrative hub factor and ideal power conservation | PASS |
| Exact source excerpt check against fetched HTML/PDF text, with whitespace normalisation | PASS: all prose excerpts matched; S4's mathematical markup was checked against the fetched chapter's equation 10.31 |
| Byte-only comparison of all pre-existing files except the required FILES.json refresh, and manifest-only integrity check | PASS: no other existing file changed; manifest digests match the explicit candidate file set |
| `git diff --cached --check` | PASS |

Minimal loader/form reproduction, from the repository root:

```sh
python3 - <<'PY'
import json
from pathlib import Path
import sys
sys.path.insert(0, 'benchmark/mechanisms-v1/harness')
import score
import rubric_form
path = Path('benchmark/mechanisms-v1/dry-run/DRY-BICYCLE.grader.json')
question = score.load_key(path)['DRY-BICYCLE']['raw']
for configuration in ['conventional'] + [item['id'] for item in question['acceptedVariants']]:
    reply = {
        'question': question['id'], 'output': 'synthetic-structure-only',
        'configuration': configuration,
        'mechanism': dict.fromkeys(rubric_form.CHECKS, 'PASS'),
        'errors': [], 'unsure': [], 'defects': [],
        'coveredFacts': [item['id'] for item in question['keyFacts'] if item['core']],
        'notApplicableFacts': [item['id'] for item in question['keyFacts']
                              if 'all' not in item['appliesTo']
                              and configuration not in item['appliesTo']],
        'clarity': 5, 'clarityReason': 'Synthetic form fixture, not a rendered grade.'
    }
    reply['mechanism']['evidence'] = {}
    parsed, problems = rubric_form.check_text('score', json.dumps(reply), question, reply['output'])
    assert not problems, problems
    assert parsed == reply
print('PASS: isolated loader and four configuration score forms')
PY
```

The full repository validator is deliberately not run here: its JSON-syntax loop would parse
the registered grader file for a purpose other than schema extraction. Instead, its manifest
digest rule is checked independently using byte hashes without parsing registered JSON.
The only changed existing file is FILES.json, refreshed to include these three new files.
No harness code, registered input, prompt, lock or hash list is changed.
