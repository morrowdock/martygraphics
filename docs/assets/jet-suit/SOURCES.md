# Jet suit explainer: sources

These are the sources for every fact in [`jet-suit.json`](jet-suit.json), the hand-built jet-suit explainer.
A Claude agent wrote the JSON by hand from fact-checked research. It is not the output of the engine's AI loop
answering a prompt. The facts come from a merged fact key with rows F1 to F20 (2026-11-08).

**How the facts were checked.** Two independent AI model fact-checks (GPT-6.1 Sol and Gemini 3.8 Flash) checked
the claims against public web sources on 2026-11-08, and where they disagreed the stricter label was kept. They
caused these corrections to an earlier draft: name the version (the classic five-engine suit, with a Mk4 note);
say that the upward components of thrust balance the weight, not that "thrust equals weight"; give the back
engine's share as "the equipment plus about one third of body weight"; keep 144 kgf and 155 kgf as two separate
reports, not one range; remove a claimed 31 % thrust loss at altitude; label the cutaway as a JetCat-style example,
not confirmed Gravity hardware; say "moving the arms", not a "lean one arm to turn" recipe; and mark 1,050 bhp as a
claim. These are model checks with web access, not a review by a jet-suit engineer.

## Labels

| Label | Meaning |
| --- | --- |
| VERIFIED | A primary source, or two or more good independent sources. For a published figure, "as a report" means that the publication is verified, not that the figure was measured independently. |
| CLAIM | The company or a person published it. Nobody measured it independently. |
| PLAUSIBLE | One source, or an inference from the engine class. Not a measured suit specification. |
| UNKNOWN | Not established. The lesson does not state it. |

All URLs were accessed on 2026-11-08. "Undated" means that the page gives no publication date.

## Facts in the lesson

| Key | Fact as the lesson says it | Label | Sources |
| --- | --- | --- | --- |
| F1 | The classic suit (as described 2020–2022) has five micro gas turbines: two on each forearm, one on the back. | VERIFIED (classic layout) | [Great North Air Ambulance](https://www.greatnorthairambulance.co.uk/jet-suit-paramedic/) (undated) · [BBC](https://www.bbc.com/news/uk-england-54331994) (2020-09-29) · [AOPA](https://www.aopa.org/news-and-media/all-news/2020/october/08/jet-suit-rescue-demonstrated) (2020-10-08) · [Browning interview, The Student Pocket Guide](https://www.thestudentpocketguide.com/2021/01/entertainment/technology/richard-browning-interview-iron-man/) (2021-01-26) |
| F2 | The Mk4 (not shown) has three back turbines; its total engine count is not published. | VERIFIED (company page); total UNKNOWN | [Gravity Industries, innovation](https://gravity.co/innovation/) (undated) |
| F4 | About 144 kgf (317 lbf) total thrust, AOPA 2020. | VERIFIED as a report | [AOPA](https://www.aopa.org/news-and-media/all-news/2020/october/08/jet-suit-rescue-demonstrated) (2020-10-08) · [BBC](https://www.bbc.com/news/uk-england-cumbria-60863725) (2022-03-26) |
| F5 | About 155 kgf total thrust for an earlier rig, Browning 2017. A separate report, not a range with F4. | VERIFIED as a report | [Guinness World Records, Q&A with Richard Browning](https://www.guinnessworldrecords.com/news/2017/11/qa-with-real-life-iron-man-richard-browning-as-discusses-his-jet-engine-suit-501862) (2017-11-09) |
| F7 | Claimed about 1,050 bhp. | CLAIM | [Great North Air Ambulance](https://www.greatnorthairambulance.co.uk/jet-suit-paramedic/) (undated) · [AOPA](https://www.aopa.org/news-and-media/all-news/2020/october/08/jet-suit-rescue-demonstrated) (2020-10-08) |
| F8 | Speed record 136.891 km/h (85.06 mph), Guinness, 2019-11-14. | VERIFIED | [Guinness World Records, fastest speed in a body-controlled jet engine powered suit](https://www.guinnessworldrecords.com/world-records/494369-fastest-speed-in-a-body-controlled-jet-engine-powered-suit) (record set 2019-11-14) |
| F9 | In Browning's 2021 description of the classic suit, the back engine carries the equipment plus about one third of his body weight; the arms about two thirds. | VERIFIED (Browning quote) | [Browning interview, The Student Pocket Guide](https://www.thestudentpocketguide.com/2021/01/entertainment/technology/richard-browning-interview-iron-man/) (2021-01-26) |
| F10 | The pilot steers by moving the arms to aim the thrust. If the exhaust is aimed back, a forward component of thrust results. | VERIFIED | [Guinness World Records, Q&A with Richard Browning](https://www.guinnessworldrecords.com/news/2017/11/qa-with-real-life-iron-man-richard-browning-as-discusses-his-jet-engine-suit-501862) (2017-11-09) · [BBC](https://www.bbc.com/news/uk-england-54331994) (2020-09-29) |
| F11 | The engines are micro gas turbines with a centrifugal compressor. | VERIFIED (compressor type) | [Browning interview, The Student Pocket Guide](https://www.thestudentpocketguide.com/2021/01/entertainment/technology/richard-browning-interview-iron-man/) (2021-01-26) |
| F12 | The cutaway is a JetCat-style micro turbojet with a compressor, combustion chamber, turbine and nozzle. The turbine and compressor share a shaft. A schematic example, not confirmed Gravity hardware. | PLAUSIBLE (true for this engine class; the installed engine is not confirmed) | [JetCat catalogue 2022](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Katalog%202022.pdf) (2022) |
| F13 | Shaft: about 120,000 rpm (reported). | PLAUSIBLE | [Great North Air Ambulance](https://www.greatnorthairambulance.co.uk/jet-suit-paramedic/) (undated; gives about 120,000) · [JetCat engines catalogue](https://jetcat.de/jetcat/Kataloge/JetCat%20ENGINES.pdf) (undated; P220-RXi maximum 117,000) |
| F14 | To hover, the upward components of all thrusts balance the weight of pilot, suit and fuel; the sideways forces and turning moments balance too. | VERIFIED (physics) | [NASA Glenn, equilibrium](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/equilibrium/) (undated; accessed 2026-11-08) |
| F15 | The compressor squeezes the air. Fuel burns with oxygen in the compressed air. Hot gas drives the turbine, which turns the compressor. The gas speeds up out of the nozzle, and the reaction is thrust. | VERIFIED (physics) | [JetCat catalogue 2022](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Katalog%202022.pdf) (2022) · [NASA Glenn, thrust force](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) (undated) |
| F19 | Browning's analogy: the grouped pushes are "a teepee of thrust, like the poles of a tent". | VERIFIED (quote) | [WIRED](https://www.wired.com/story/gravity-jetpacks/) (2020-10-13) |
| F20 | The chest box is a "schematic chest pack". The lesson names no function for it. | UNKNOWN (so the lesson makes no claim) | No source gives its function. |

## Left out on purpose

F3 (earlier-rig history), F6 (per-engine thrust), F16 (all-up mass), F17 (altitude effects), and F18 (flight time) are omitted.

## What the engine checks

The legend line in each step still reads **Solved 17 · Not checked 20**
([check output](check-strict.json)).

- **Solved 17:** the engine computed these. They are the motion of 15 rotating parts (the impeller, turbine
  wheel and shaft of each of the 5 engines), the direction of the weight arrow (straight down), and the sense of
  the shaft-turn arrow in step 7.
- **Not checked 20:** 8 labels and 4 captions that give a reported number, a quote or a version, each marked with
  its fact-key row, and 8 arrows whose direction and length are as authored. The engine shows them but does not
  check them. Their facts come from the table above. Labels that only name a part, and the other 3 captions, are
  not counted in the legend; the engine does not check their words either.
- The engine does not compute thrust, rpm, the load split or the hover balance. "Arrow lengths are not to scale"
  is printed in each step still. Engine sizes, the pack and the arm pose are schematic, not measured Gravity hardware.
