# DRY-BICYCLE source record

Status: verified source excerpts; independent second check PASS. Refreshed: 2026-11-13 UTC.
Source: [FACTCHECK-2](DRY-BICYCLE.FACTCHECK-2.md), checked 2026-11-12 at
`9bfa0746a4bdbee738361b5b8531741faa00da08`: 19 PASS, 0 FIX. The full dry run remains pending.

Fetched: 2026-11-12 UTC. Base: `9e95ad3d69a54bce75b1a86d5b136734fb3ddb84`.

Scope: the bicycle question prescribed by PROTOCOL section 2.4, outside the registered set.
This file is evidence for [the new grader view](DRY-BICYCLE.grader.json), not part of that view.
No registered question content was used. The registered grader file was inspected for field names,
types and nesting only. The format identifier comes from `tools/grader_questions.py`.

There are eight sources, from six independent publishers or authors: Heriot-Watt University,
MIT, Rohloff, OpenStax, Park Tool, and Sheldon Brown/John Allen. The three Park Tool articles
are separate sources, not three independent organisations. All were fetched during this task.
Quotes below are exact short excerpts; PDF line wrapping and HTML whitespace are normalised.
Shared excerpts are listed once, with all supported fact IDs. Calculations are explicitly identified
as derivations, not quotations. No numerical efficiency or chainline tolerance is claimed.

## S1 — Chain engagement and pitch

- URL: https://www.ros.hw.ac.uk/server/api/core/bitstreams/4e19d021-5198-4e8b-9efb-5be77917287f/content
- Title: *Bicycle Chain Efficiency*.
- Author/publisher: Matthew Donald Kidd, mechanical-engineering PhD thesis, Heriot-Watt University, May 2000.
- Fetch date: 2026-11-12 UTC; PDF downloaded and text extracted with `pdftotext -layout`.
- Locator: section 2.2, printed page 10, introductory paragraph and assumption 2.
- Exact excerpts supporting K1 and the pitch clause in M5:

> the chain is in contact with a number of sprocket teeth

> chain pitch is exactly equal to sprocket pitch

Verified interpretation: a roller-chain drive engages teeth rather than relying on a smooth belt's
friction. Matching pitch is an ideal design relation, not a claim that worn parts have zero error.
The thesis describes the tight/return strands and articulated chain joints in the same section.
K1's crank-to-chain-to-rear-drive sequence is also supported by the bicycle drawing and chain
force analysis in S2. M2/M5 apply these physical relations only where a connection is visible.

## S2 — Loaded upper run

- URL: https://ocw.mit.edu/courses/2-007-design-and-manufacturing-i-spring-2009/559019a24f0c8a3729570785aa963939_MIT2_007s09_sol_exam01.pdf
- Title: *2.007 — Design and Manufacturing I, Exam 1 Solutions*.
- Author/publisher: MIT OpenCourseWare, Spring 2009.
- Fetch date: 2026-11-12 UTC; PDF downloaded and text extracted with `pdftotext -layout`.
- Locator: problem 7 solution, printed page 6 of 8.
- Exact excerpt supporting K2:

> the chain tension which is applied at the top of the rear sprocket and tangent to it.

Verified interpretation: under forward drive the chain pulls tangentially on the rear sprocket
through its loaded upper run. S1's tight/return-strand analysis and S5's lower-run tension support
the distinction between greater driving tension and a return run that need not be tension-free.
The scope excludes coasting and fixed-gear braking, when the drive-load premise does not hold.
M3's upper-run travel direction is a kinematic derivation: in the ordinary uncrossed layout,
forward rotation carries the top of the front chainring forward, drawing the upper run toward it.
It is not a statement that chain material travels rearward along that run.

## S3 — External ratio, development and internal hub factor

- URL: https://www.rohloff.de/en/service/handbook/speedhub/tables
- Title: *Tables — Rohloff AG*.
- Author/publisher: Rohloff AG, SPEEDHUB technical handbook.
- Fetch date: 2026-11-12 UTC; HTML fetched and read.
- Locator: “Inner gear ratio,” formula above the IGR table, and the comparison formula below it.
- Exact excerpts supporting K3, K4 and the speed/cadence part of K5:

> Distance travelled per crank revolution = W · C / S · IGR

> Ratio of the derailleur gear system = C / S

Verified notation: the source defines W as wheel circumference, C as chainring size, S as
sprocket size, and IGR as inner gear ratio. The key renames these W -> wheel circumference,
C -> Nf, S -> Nr, IGR -> h, so its chain ratio R is Nf/Nr, not its reciprocal.

Derivation for K3/K4: the direct-drive wheel and driven rear sprocket make the same turns;
therefore wheel turns per crank turn are R. An internal hub adds h, giving R*h wheel turns
and R*h times the rolling circumference per crank turn. Multiplying by cadence gives speed.
For fixed front teeth and h, increasing rear teeth decreases R, decreasing speed at fixed
cadence and increasing required cadence at fixed speed (K5). These statements assume
engaged drive and rolling without tyre slip; they do not constrain a freely coasting wheel.
The hub variant uses this additional internal ratio rather than pretending that a rear
derailleur or an external sprocket change is necessary for every shift.

## S4 — Torque is exchanged for speed, not extra power

- URL: https://openstax.org/books/university-physics-volume-1/pages/10-8-work-and-power-for-rotational-motion
- Title: *10.8 Work and Power for Rotational Motion — University Physics Volume 1*.
- Authors/publisher: William Moebs, Samuel J. Ling and Jeff Sanny; OpenStax, Rice University.
- Fetch date: 2026-11-12 UTC; chapter text and displayed equation fetched and read.
- Locator: “Power for Rotational Motion,” equation 10.31.
- Exact equation supporting K5 (source mathematical markup):

> `P=\tau \omega .`

Derivation for K5: in an ideal lossless steady drive, input and output power are equal.
Substituting wheel angular speed = R*h times crank angular speed gives wheel torque =
crank torque/(R*h). With unchanged h, a larger rear sprocket decreases R and increases
that ideal torque multiplier. Dissipation makes output power lower, not higher; at the
same positive speed ratio this lowers torque relative to the ideal prediction.
This is a stated ideal model, not a claim that a real drivetrain has 100 percent efficiency.
Cadence means crank revolutions per unit time here, not rear-wheel revolutions.

## S5 — Derailleur selection and return-run tension

- URL: https://www.parktool.com/en-us/blog/repair-help/how-a-rear-derailleur-works
- Title: *How A Rear Derailleur Works*.
- Author/publisher: Park Tool, 2017-07-29.
- Fetch date: 2026-11-12 UTC; HTML fetched and read.
- Locator: “Derailleur Mechanics,” first paragraph and pulley paragraph.
- Exact excerpts supporting K7 and the return-run qualification in K2:

> The rear derailleur is the mechanism that shifts the chain at the rear sprockets.

> tension to the lower section of chain.

Verified interpretation: the guide pulley selects the rear sprocket; the tension pulley tensions
the lower run. The key does not claim that a derailleur changes the geometry of a sprocket.
For a single-speed example, tooth-count comparisons can be separate setups, not an invented
on-bike shifting mechanism. A hub-gear example changes its internal ratio instead (S3).

## S6 — Freehub/freewheel and coasting

- URL: https://www.parktool.com/en-us/blog/repair-help/determining-cassette-freewheel-type
- Title: *Determining Cassette / Freewheel Type*.
- Author/publisher: Park Tool, repair-help technical article.
- Fetch date: 2026-11-12 UTC; HTML fetched and read.
- Locator: “Rear Cogs,” cassette-hub paragraph; following threaded-freewheel paragraph.
- Exact excerpt supporting K6:

> This cylindrical mechanism ratchets counter-clockwise for coasting, and locks clockwise for driving the bike when pedaled.

Verified interpretation: a freehub acts as a one-way drive; coasting does not require the
crank and chain to keep turning. The article distinguishes a cassette's hub-mounted ratchet
from a threaded freewheel's ratcheting body. Absolute clockwise wording is the source's
viewpoint, not a universal camera-direction requirement in the key. The accepted hub-gear
variant is explicitly a coasting hub; no particular hidden clutch layout is required.
K6 is N/A for fixed-gear, whose different constraint is sourced in S8.

## S7 — Chainline is not universal perfect coplanarity

- URL: https://www.parktool.com/en-us/blog/repair-help/chainline-concepts
- Title: *Chainline Concepts*.
- Author/publisher: Park Tool, 2015-08-07.
- Fetch date: 2026-11-12 UTC; HTML fetched and read.
- Locator: “Basics,” effective-chainline definition and manufacturer-alignment paragraph.
- Exact excerpts supporting K8 and M5's lateral-angle allowance:

> the relative position of the front and rear cogs to each other

> do not specify “perfect” or exact center-to-center alignment

Verified interpretation: the relative lateral positions are effective chainline. A derailleur
system's selected sprockets need not all share one plane. The article allows workable chain
angles and cautions about rubbing; the key does not endorse every extreme cross-chain
combination, require a numerical alignment tolerance, or claim that lateral bending is free
of losses. Straight alignment is a valid single-speed example, not a universal visual test.

## S8 — Fixed gear is not synonymous with single-speed freewheel

- URL: https://www.sheldonbrown.com/fixed.html
- Title: *Fixed Gear Bicycles for the Road*.
- Authors/publisher: Sheldon Brown; revisions by John Allen, author-maintained bicycle technical reference.
- Fetch date: 2026-11-12 UTC; HTML fetched and read.
- Locator: “What is a Fixed-Gear Bicycle, and Why Would You Want One?”, opening paragraph.
- Exact excerpts supporting K9 and the fixed-gear accepted variant:

> This is a single-speed bike without a freewheel

> You cannot coast on a fixed-gear machine.

Verified interpretation: the chain-connected crank and rear wheel remain coupled. A stationary
crank with a turning rear wheel is therefore inconsistent with this variant, but not with S6.
This source is used only for that mechanical distinction, not for its riding or health advice.

## Fact-to-source ledger

| Fact | Supporting excerpts and derivation |
| --- | --- |
| K1 | S1 engagement; S2 bicycle drive arrangement and rear sprocket load |
| K2 | S2 upper sprocket tension; S1 tight/return-strand analysis; S5 nonzero return tension |
| K3 | S3 C/S speed ratio; whole-turn tooth engagement follows S1 |
| K4 | S3 development formula; speed follows distance per turn times cadence |
| K5 | S3 inverse rear-tooth speed dependence; S4 power equation and explicit lossless derivation |
| K6 | S6 one-way coasting/drive action; S8 fixed-gear exception |
| K7 | S5 rear sprocket selection; S3 internal-ratio alternative |
| K8 | S7 effective chainline and non-perfect alignment |
| K9 | S8 absence of freewheel and inability to coast |

All nine facts have a source and an exact supporting excerpt above. M1-M5 use these same
physical relations, with the visibility, sampling, clause and N/A rules from RUBRIC.md.
No statement here substitutes for the coordinator's pending second-model review.
