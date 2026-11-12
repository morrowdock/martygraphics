# Studio image refresh

Status: verified render outputs; review pending.

Date: 2026-11-12 UTC.

Engine commit: `fb60455674808362c64b5600687d77b9f9b77c2c`.

Sources: the unchanged example exporters and documents at that commit, and the adjacent `provenance.json` files.

This refresh replaces 98 stills and 3 GIF loops that used the old default look. Every image is a MartyGraphics
render, not Blender output or hand-made artwork. PNG and GIF files are copied from the exporters without edits.
JPEG files use the same dimensions and quality setting as before; `sips` performs only the format conversion.
Every image keeps its path and subject. Source documents, engine code, benchmark files, historical checks,
and authoring and fact-check records are unchanged. The old hashes below identify the replaced images.

The current engine can also differ from the much older capture engines in framing, labels and legends.
In particular, the winch motion arrow is shorter, and the AI jet-suit beat 4 omits two hidden thrust arrows.
The lesson text and its documented errors remain unchanged. The historical reviews do not review these new pixels.

The MP4 files and website videos are not refreshed. Their linked posters and GIF previews now use `studio`,
but the videos retain their recorded look and capture commit. Do not treat them as the same render run.

The word “classic” in the jet-suit lesson names the five-engine suit, not the renderer look. Its images are refreshed.
The four visual-quality comparison sheets are historical evidence, including classic-by-design panels, and stay unchanged.

## Verification

- Release builds passed for `marty-solid`, `marty-solid3d` and `marty-turbofan`.
- All 13 render/export commands passed. All 101 image hashes match their published files and provenance entries.
- All 101 dimensions are unchanged. Each GIF still has 120 frames with a 0.10-second delay per frame (12 seconds).
- Source document bytes match the engine commit. The 37 excluded media files are unchanged.
- `python3 -m unittest discover -s tools/tests`: 22 tests passed, 0 failures.
- `swift test --package-path Examples/Solid3D --jobs 2 --filter MartySolidCLITests.testCheckOutputIsByteIdenticalToTheGoldenFiles`: 1 test passed, 0 failures; the complete shipped-input golden set was checked.
- The 18 changed golden records differ only in `file.lines` and `file.sha256`. No test logic or engine report field changed.
- All 11 `marty-solid check --strict` commands passed. Eight documents had no warnings. Three had 17 warnings in all:

| Document | Current warnings (not errors) |
| --- | --- |
| Robot-joint gearbox | `framing.subject.small.step.3`, part `planet11` (1). |
| Hand-built jet suit | `framing.subject.small.step.1`, `.2`, `.3`, `.5` for `pilot.skull`; `.6` for `back.turbineWheel`; `.7` for `back.impeller` (6). |
| AI jet-suit lesson | `annotation.arrow.weight.aW`; `annotation.arrow.dropped.aL1`; `annotation.arrow.dropped.aR2`; `framing.subject.small.beat.1`, `.2`, `.4`, `.6`, `.7`, `.8`, `.9` (10). |

These checks do not validate the words or real-world mechanics. The historical check JSON files are not replaced.
The warnings are not repaired in this image-only task. The image paths, source documents and engine stay unchanged.

## Re-rendered images

Build the existing tools with `swift build -c release --package-path Examples/Solid3D` and
`swift build -c release --package-path Examples/Turbofan --product marty-turbofan`.
Run from the repository root. Put the built binaries on PATH. Create `OUT` first; each child output directory must be new.
Each command below applies to every row in its table. All rows use look `studio`.

### robot-joint

Command: `marty-solid render docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json OUT/robot-joint --size 1280x800 --look studio --no-story`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/from-a-prompt/robot-joint/exploded.png` | `exploded.png` | `271415abcd5eeafecfd3db61ea2d1d7a28179aa69c27d51f0fb6d7c58a6c07c5` → `fe4f44deab447e056c4f50550669de809eb0a52c1f4db32d2cb3be671df51e8e` | 975497 → 939731 |
| `docs/assets/from-a-prompt/robot-joint/hero.png` | `hero.png` | `adcdf503bfd406c85752d0fbaf9f2615a147d376a5cd41982c82e048ce269f6d` → `1d43417d6b380f623bbbd1366c9e211fcc465fd666691989f249939b9cf8d9a2` | 977242 → 929882 |
| `docs/assets/from-a-prompt/robot-joint/loop.gif` | `loop.gif` | `4ac7f1ebed15ea8bfa8dc8c32938c5af0ff850ea7988d2dad8a86a979bbed698` → `0813d27895c8933fc5403fc43b270bbbce74e9e6b92647688bf8852fb837f968` | 3662895 → 4162214 |
| `docs/assets/from-a-prompt/robot-joint/step-3.png` | `step-3.png` | `0c4feee9a48e6c72347e245d3432d7a752e460f883e51641ae4d5df11f94f542` → `56ed1b3a7a3faa29453ce0cc3cff0c0475800c47a1dd4c606f4c659a2a5c4360` | 867008 → 899657 |
| `docs/assets/from-a-prompt/robot-joint/step-5.png` | `step-5.png` | `a99f4f3c535b332670358f53846cc58e88e45174e390ac7770ccfbba8cdaf978` → `d8e5cdbd19bbd04683382ab63351734837c4c1fc79eea41043e17d92e2f10898` | 866315 → 885848 |


### cutaway

Command: `marty-solid render Examples/Solid3D/Sources/MartySolid3D/Models/idler-gearbox.json OUT/cutaway --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/cutaway/closed.png` | `step-1.png` | `7b4bec33e31a6512290c0d9ca5852cf962901b9805232bf8cdd7b8324bf894c5` → `1f7f82f50b6c56b4f1c9590d270fd65328901f8706d9b8f178fcf630d6685e6e` | 1064758 → 876342 |
| `docs/assets/cutaway/cut.png` | `step-2.png` | `96dabfcb37877242b3330344375c086c36b52afe2d575f212fd8a22d59dd6a26` → `fd683db425339f55b557c0fc7c7e4dad2b7dc11ace78efc08f67ea79a36cee95` | 1090443 → 959375 |
| `docs/assets/cutaway/ghost.png` | `step-6.png` | `c15d924592e38a30ffaebe42e7ba8eaf518a3f7b90430e51399f9d4b38d5ceab` → `82bb7a5d23f6484c2439bac8a42259ec005bbb4d8424465543683d1763dc5881` | 947217 → 912616 |


### annotations

Command: `marty-solid render Examples/Solid3D/Sources/MartySolid3D/Models/annotated-winch.json OUT/annotations --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/annotations/winch-dimension.png` | `step-3.png` | `c268f068cb84568032e0e855610a58bf2601ec1b54b6ff8c1308d18d6e83f8aa` → `ee4dc881ae939def98a67e7dc5b8ff3e85dfc5f67b4c2eb8c164c85eb2129845` | 818595 → 851647 |
| `docs/assets/annotations/winch-lift.png` | `step-5.png` | `d3a2181ef34927b247879c135fcf319e6227e5a02939c9fed815dc0887fb411c` → `232f4c22463bf94d09e93160718b7059060cdd5cbb01dc4f47b67164e6085af4` | 994486 → 892139 |


### explainer

Command: `marty-solid render Examples/Explainers/gears-mixed.explainer.json OUT/explainer --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/explainer/gears-mixed-beat-1.png` | `beat-1.png` | `719994caa0d4ff42e938f76ea57e1626e0fc3dac62728340dddfeac40a1a2076` → `24e965599ac234283221caeb241a9c09752d6ae53ae4503d48d4c3d6093959c6` | 499800 → 572822 |


### jet-suit

Command: `marty-solid render docs/assets/jet-suit/jet-suit.json OUT/jet-suit --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/jet-suit/hero.png` | `hero.png` | `526756cbe98d7f33c5b2abf6e0e3bf2f4388c889aa810a2478756d13db4f53f7` → `59c60a8c792a3aec7678918b934327e9284b4bbb9b3e38e514553ef3c2d6c20e` | 802528 → 917776 |
| `docs/assets/jet-suit/poster.jpg` | `step-2.png` | `206800feb81e1e623ae40381cab55f632a7ed5dfa4d47866d13c9d057d8f4f8e` → `dcdc72d7c9361027d1b69ab1e6a105c78d3192b4b2d995e32f5f136ce1e76618` | 93154 → 95902 |
| `docs/assets/jet-suit/step-1.png` | `step-1.png` | `ce203eb673be94e8688f8ffba048dd892deb07485970b72364db6f7dfa882049` → `28d6421123ba67531f312f3d07e54256cbe4aae3862f537c415bedfb47883c92` | 687224 → 904936 |
| `docs/assets/jet-suit/step-2.png` | `step-2.png` | `a827b6f6c46469ce18b3edb2cb7784e58f6167a781890c0c7afb57aa1fc3e76c` → `44c361228671c146dbe44e8d46ee78eff985f92f432664c7f7f9d3b7cb8a2d8f` | 707631 → 919096 |
| `docs/assets/jet-suit/step-3.png` | `step-3.png` | `3acc2dde40c5499e6fcce23b3dd6f1b399d78c7a7080dc6400363466cd29896b` → `91ddfaa767dff4d1b360bf89d9ec5238934ad5795a56b97bc6fc7be064392578` | 684494 → 899775 |
| `docs/assets/jet-suit/step-4.png` | `step-4.png` | `9e952baf5335d903596ed409fce5917685edb5f9308e6926520fbdd9e27a1f31` → `9f46f62fbc144e9299e0dbd0a1e011b927122d024938a38cf47a10052f994fa6` | 691287 → 916586 |
| `docs/assets/jet-suit/step-5.png` | `step-5.png` | `73a8a6e01b0f6dda0958b83ddc22661ffd9b7e2ede0b74dab291710e71fd6d97` → `941686ba282b1eaab43ff994956a85103188289dc177cc50323b58bebb333590` | 671872 → 888314 |
| `docs/assets/jet-suit/step-6.png` | `step-6.png` | `e8222f33787ad5888420d058a75dc8e89b2012dd7b3f68fdcd6c769218aaf767` → `3f68b279e58a96a64b4bbb8b0a419f89bdf1f5d9c8f26cfab2b4f1fff54db01a` | 720872 → 882949 |
| `docs/assets/jet-suit/step-7.png` | `step-7.png` | `29b44f44f2ba08052cc09befeea88c74cb13d22fcf8f99b0a32be9f39b5d58d0` → `9618176479e08f959efae896484253c00be25def443f443427b056e401db8684` | 681777 → 874237 |

- Conversion: `sips -s format jpeg -s formatOptions 82 OUT/jet-suit/step-2.png --out docs/assets/jet-suit/poster.jpg`.

### jet-suit-ai

Command: `marty-solid render docs/assets/jet-suit-ai/lesson.json OUT/jet-suit-ai --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/jet-suit-ai/beat-1.png` | `beat-1.png` | `44cdca04833a119dd76b54558418f52bb62e50f0699d3e47300063388df17e69` → `52e888160fbdf0ba9961868e58b29cd5cb3f06b5d890387062033e0daecb4ff8` | 535923 → 644927 |
| `docs/assets/jet-suit-ai/beat-2.png` | `beat-2.png` | `c9c1e671f6510966c234e708a4e4ffcfe7c280572d51e67890c6dd530fa26272` → `fd9b239d5f65a6a6da430aa78783209409a5ec423c9f6f53b39661a2477b8967` | 549286 → 667099 |
| `docs/assets/jet-suit-ai/beat-3.png` | `beat-3.png` | `d00a72a1e14a4ed72d05e6245b2992f2c44641e7a6e6c6d5aa1caec695889eeb` → `63d02e0d7ffc553cf978c650ef39898aab4f401bfcebfa9ac595eeedf9e8143d` | 587393 → 588196 |
| `docs/assets/jet-suit-ai/beat-4.png` | `beat-4.png` | `e255ab9d0e1ffa50a9aecb83995d85225ab99ade93820606d47e01711e522911` → `1d36ec82a64e00fc9c51e7e2700cb8d0fc49cdaf5d17c25b1bfb12c9540de4e5` | 547538 → 554400 |
| `docs/assets/jet-suit-ai/beat-5.png` | `beat-5.png` | `e898400b95d357b299272ae72433e438b4d4010b5d8692a8fd506bbf46d3e8cf` → `600d9d1be19a8b123753049c59b1dc5736e06b493989a668fb8822451ad2a5b6` | 538829 → 550503 |
| `docs/assets/jet-suit-ai/beat-6.png` | `beat-6.png` | `4c85c841ef39eb40084a6fbf0f7f7f2b1f75bd09caad0c0946e58bdaa5ec468e` → `307375f6ece2ecc3a0a136ff5ab8c4107b0ae46396d14dee7a7616afea720a64` | 549955 → 544214 |
| `docs/assets/jet-suit-ai/beat-7.png` | `beat-7.png` | `5f3cdde1b93e0c34bd210b420505e2ef7a7b93a9f1d7df0c4014daf3f82f5d54` → `bf3c496bbd84440385c784876eac5d530fbc123b01dc5fa35c20bde78871aefd` | 566293 → 554240 |
| `docs/assets/jet-suit-ai/beat-8.png` | `beat-8.png` | `2f041c0fd695db738efbd28638eab0ca740a1f5f1bf96158a3e4de955dc3115a` → `22608f684840722eb954cd847c7b54d4091800a52d57108de7556f3b93d24113` | 548201 → 512725 |
| `docs/assets/jet-suit-ai/beat-9.png` | `beat-9.png` | `aade8c7972c6c82eeb60ac9d51ffb487346cca1585147bceec8519c7c7d197a1` → `ab5ead49e9c01c53bbbf28bdcc25bd945de77e195182c8bf98def1c78bbc82d9` | 541933 → 554292 |
| `docs/assets/jet-suit-ai/poster.png` | `beat-2.png` | `c9c1e671f6510966c234e708a4e4ffcfe7c280572d51e67890c6dd530fa26272` → `fd9b239d5f65a6a6da430aa78783209409a5ec423c9f6f53b39661a2477b8967` | 549286 → 667099 |


### quadcopter

Command: `marty-solid render docs/assets/drone-aviation/quadcopter/quadcopter.json OUT/quadcopter --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/drone-aviation/quadcopter/exploded.jpg` | `exploded.png` | `9a5e156c17b5926ef91c0acbb9d9d887fb79ce63465347a218332c264a8dcb94` → `626c482f1b1d2bd4ec3ed4d2824f6842d102ca76af46b3b46f5af5179a637c6d` | 116695 → 118227 |
| `docs/assets/drone-aviation/quadcopter/hero.jpg` | `hero.png` | `c1a431584482ee6f05a6911c21c3e6d89c5366ebff12e1d48ff07644cb65895a` → `eb238decf161440ab3d7cb67d04ed2027425382cdd81fd3a93c26ecb818883ce` | 116249 → 117694 |
| `docs/assets/drone-aviation/quadcopter/poster.jpg` | `step-1.png` | `92bc99163997a84abd4f66b07567a480df0b6c94b9058ae11db81c1c985a5662` → `2ad9a627c19d52dd0555ca08e470f7d513c16c196e76ec79eb897769af1b30fd` | 115721 → 121061 |
| `docs/assets/drone-aviation/quadcopter/step-1.jpg` | `step-1.png` | `92bc99163997a84abd4f66b07567a480df0b6c94b9058ae11db81c1c985a5662` → `2ad9a627c19d52dd0555ca08e470f7d513c16c196e76ec79eb897769af1b30fd` | 115721 → 121061 |
| `docs/assets/drone-aviation/quadcopter/step-10.jpg` | `step-10.png` | `88d35eecf140b125f4ddf22db4816235bc22eb14a122f65894539223325e8d99` → `a1758f608b1314ffb78482d5df6f520bf133655797b0f1ded54f79e24236b5e5` | 134706 → 138028 |
| `docs/assets/drone-aviation/quadcopter/step-2.jpg` | `step-2.png` | `2047ae56d1d21c625973228faff67b4ae930e2959c9667bbc6230ef02bdf98db` → `8b870c81efa6b76080f24d55398962a2e76df7d266f51aec83d60dc673d06062` | 159398 → 150268 |
| `docs/assets/drone-aviation/quadcopter/step-3.jpg` | `step-3.png` | `c22956f254873428f8fc9e444077653ad0d78c634ca3b46ef1fec64717d72253` → `13c71746ffc4204bfbc2a11a250c82286819883f87558a87e6d4ea23b120e506` | 146028 → 147227 |
| `docs/assets/drone-aviation/quadcopter/step-4.jpg` | `step-4.png` | `29fa9e9b597310d72cc29266186a81b9889626a3c677cfbf2917ca3c023316e3` → `c209eee84c1a84ffcc1a702938dd4e0a9e4a51208a256f0a9949e9d3ee6b39e7` | 173604 → 160386 |
| `docs/assets/drone-aviation/quadcopter/step-5.jpg` | `step-5.png` | `f34b02801e78591e9f1a8c81d4723d54f0e35b8bfbca8b0caf35b797fc1dd187` → `e9a9dbc2f0d34ceb0902a162401ca0e3d18bc9a3f06aefd90eb58199c1f656d4` | 139633 → 139014 |
| `docs/assets/drone-aviation/quadcopter/step-6.jpg` | `step-6.png` | `aad87dcfdb194192f0033b8f307fb7ea9a498d50f68fedf0393c47acab1c0b89` → `ae58b20d42f2b755f43b60b8c218272819c7ef6837e10656d557c447eecbe053` | 127475 → 133637 |
| `docs/assets/drone-aviation/quadcopter/step-7.jpg` | `step-7.png` | `2b39c3f54824aa06418a2518a81fa4ee3f7dadaeb2336a39a8b1a3575bb7a253` → `a817589c59f4458b91d419f750d2f37efde507c9a0d10811b860eaeb90f0dd85` | 129910 → 135298 |
| `docs/assets/drone-aviation/quadcopter/step-8.jpg` | `step-8.png` | `cb09fb2ae4938cc18fa7ce0c86d234e3ebe45f5d4c0380b665f393256d8c7e54` → `112085cf1dc2bf8da2c94b3b167350268d70d9e33daea7bcc5a5707752c8b206` | 134372 → 140224 |
| `docs/assets/drone-aviation/quadcopter/step-9.jpg` | `step-9.png` | `14d34da6df3c86d6099bde1796f991d34449b9098a739ed8c2c53929e60d62fb` → `eb7bd1fd4ca978644fa82a2720abf622ce98d399442dde9675da0d0c90ecd63d` | 143342 → 146159 |

- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/exploded.png --out docs/assets/drone-aviation/quadcopter/exploded.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/hero.png --out docs/assets/drone-aviation/quadcopter/hero.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-1.png --out docs/assets/drone-aviation/quadcopter/poster.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-1.png --out docs/assets/drone-aviation/quadcopter/step-1.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-10.png --out docs/assets/drone-aviation/quadcopter/step-10.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-2.png --out docs/assets/drone-aviation/quadcopter/step-2.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-3.png --out docs/assets/drone-aviation/quadcopter/step-3.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-4.png --out docs/assets/drone-aviation/quadcopter/step-4.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-5.png --out docs/assets/drone-aviation/quadcopter/step-5.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-6.png --out docs/assets/drone-aviation/quadcopter/step-6.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-7.png --out docs/assets/drone-aviation/quadcopter/step-7.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-8.png --out docs/assets/drone-aviation/quadcopter/step-8.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/quadcopter/step-9.png --out docs/assets/drone-aviation/quadcopter/step-9.jpg`.

### brushless-motor

Command: `marty-solid render docs/assets/drone-aviation/brushless-motor/motor.json OUT/brushless-motor --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/drone-aviation/brushless-motor/exploded.jpg` | `exploded.png` | `f90743e313b60268bde013a52074712d2cfc778e259fbfd86f230293a32bd37b` → `bed7fbecc8b7698a45b8546cf37b67e438a34884bff8865d6bb597c742702740` | 100905 → 93329 |
| `docs/assets/drone-aviation/brushless-motor/hero.jpg` | `hero.png` | `5cf3483b67ce0903c3f4ae96b94dc77c75aa15bb8fb172a157ed557c673aafa5` → `52708c586aaf0ab3c0d6babff27bea6a53fabbb2c9520347a8d58db236acc6dd` | 101098 → 98893 |
| `docs/assets/drone-aviation/brushless-motor/poster.jpg` | `step-2.png` | `91b2b99423d8738d2c24948276b7c238c68d26b57daa99ece3f49428c864c919` → `ce6fdb24f3138fdb3d6d06f1eeabaac09f84beff86ece4f3a03a19227abd85b6` | 134205 → 139851 |
| `docs/assets/drone-aviation/brushless-motor/step-1.jpg` | `step-1.png` | `874a4ca5f034b7914b6fb94ebae2ef101bb56f03d67bba45bcf75444876de434` → `a2353c7ef5085c7d0b26a6d9fbed4988a5a4f455e54a15454de90201d6a3d380` | 131422 → 130966 |
| `docs/assets/drone-aviation/brushless-motor/step-10.jpg` | `step-10.png` | `66d219d37e8649944a385638120cf9b6bfd4a888c98585eea846dc9a3948c798` → `506234b9e8a768ea75de1329f20d07da49fcca2c3745e8eb4e81690697bb0b7f` | 117289 → 126096 |
| `docs/assets/drone-aviation/brushless-motor/step-11.jpg` | `step-11.png` | `3440b0809fda6073f6b2b167bec5b03d5ac0c9650dd49268014c3d7895ffef71` → `174071b9eb3bea95c7ab16c1acf4a9f8fb9a7fd820145d819371d40e264749c4` | 121536 → 126429 |
| `docs/assets/drone-aviation/brushless-motor/step-2.jpg` | `step-2.png` | `91b2b99423d8738d2c24948276b7c238c68d26b57daa99ece3f49428c864c919` → `ce6fdb24f3138fdb3d6d06f1eeabaac09f84beff86ece4f3a03a19227abd85b6` | 134205 → 139851 |
| `docs/assets/drone-aviation/brushless-motor/step-3.jpg` | `step-3.png` | `244324d9c6d548c1493cf48c60a37fe1df5547a4cbfb1a0b4b0060266502e39a` → `ef801726c2f72fc407e6e20b9dcce80e820fae9ab9f2c1840f4a6f8de9c1a60a` | 124274 → 128596 |
| `docs/assets/drone-aviation/brushless-motor/step-4.jpg` | `step-4.png` | `705ab426487ddc5d1cfe440bc979edbb9d17c6d37b7a2abb3886b86c2a4312a5` → `8fd57dd5a1bd7990564de6166146c8bcf902937936d542af3dc89625a9fb45a1` | 134683 → 139729 |
| `docs/assets/drone-aviation/brushless-motor/step-5.jpg` | `step-5.png` | `bf47d005f5123b693e6dac3f2e43082912b899f55867502807cb745e307252a7` → `7510af4cf3b198fbaa00953fdd833cb28e612e3df3ef02054422a997240a1d9e` | 121890 → 135394 |
| `docs/assets/drone-aviation/brushless-motor/step-6.jpg` | `step-6.png` | `d8163e35cc3da7ae7c5753d1b63511124de7c9ac0eea75ab46504c06f51aa2bf` → `b53598a39f0276b3d7e8df0ad75ad5c1f896ca802a8fd2a1223f86e56834c698` | 99984 → 116241 |
| `docs/assets/drone-aviation/brushless-motor/step-7.jpg` | `step-7.png` | `c6bb5dff76b217cf516d62479689a86dbec8334e0d6fb24c66a4124ff6f38ddf` → `58fdbec6c99263bf56108fdf15e3c37310b65a81f56df5b3e993f570ceb6de1b` | 121953 → 135795 |
| `docs/assets/drone-aviation/brushless-motor/step-8.jpg` | `step-8.png` | `2657cfb65d038b24e41afe141f12788fdfeb88b910e35ae454e1a806457f0ae9` → `aca859c12d73670a404e2f3f74a269e6e41399a3e19634c74fb3fed39cd152d9` | 135373 → 138547 |
| `docs/assets/drone-aviation/brushless-motor/step-9.jpg` | `step-9.png` | `df09975b3610fc82fc9295854bcb994a61b1724ad3592777b15e1452f592ea44` → `e3b1cda42458ea22355c40980b249ecdfca1c27be7be6ca46320513c0cff8506` | 133926 → 138996 |

- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/exploded.png --out docs/assets/drone-aviation/brushless-motor/exploded.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/hero.png --out docs/assets/drone-aviation/brushless-motor/hero.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-2.png --out docs/assets/drone-aviation/brushless-motor/poster.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-1.png --out docs/assets/drone-aviation/brushless-motor/step-1.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-10.png --out docs/assets/drone-aviation/brushless-motor/step-10.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-11.png --out docs/assets/drone-aviation/brushless-motor/step-11.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-2.png --out docs/assets/drone-aviation/brushless-motor/step-2.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-3.png --out docs/assets/drone-aviation/brushless-motor/step-3.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-4.png --out docs/assets/drone-aviation/brushless-motor/step-4.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-5.png --out docs/assets/drone-aviation/brushless-motor/step-5.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-6.png --out docs/assets/drone-aviation/brushless-motor/step-6.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-7.png --out docs/assets/drone-aviation/brushless-motor/step-7.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-8.png --out docs/assets/drone-aviation/brushless-motor/step-8.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/brushless-motor/step-9.png --out docs/assets/drone-aviation/brushless-motor/step-9.jpg`.

### gimbal

Command: `marty-solid render docs/assets/drone-aviation/gimbal/gimbal.json OUT/gimbal --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/drone-aviation/gimbal/exploded.jpg` | `exploded.png` | `d420c9e7d06aec3d8c0ec16001e6b07e2dc26e048ca5feab8185572c057f7564` → `291aed765fe1dac36cc68d13f6c8ed6d29887f65525c48dc76b21ed0919d6734` | 96386 → 99129 |
| `docs/assets/drone-aviation/gimbal/hero.jpg` | `hero.png` | `132b38816d92d984f55fa6e6f2ba3a1b8347aeb245786e39eea8052a3956b0b7` → `4cde946b12de0dc343712707354698678086547d86324454b58390a877b03eac` | 93898 → 96954 |
| `docs/assets/drone-aviation/gimbal/poster.jpg` | `step-6.png` | `d5f29e2479e835fdb9694b17f608d256ee8a29ecace4e1e2af774406402f1000` → `549be824eb627cb7b0473b50bb37983b9c3e5f030f5015a2d1a59d5076bf5ef9` | 147154 → 139074 |
| `docs/assets/drone-aviation/gimbal/step-1.jpg` | `step-1.png` | `fa7da533e1ae07c3bc1936f17ee83ae485d069502b1dc7f9fa0845a7bb087441` → `39025aa0af39246f1d0a2f22bdcd5aaf4eb500206a16f0e9f08f5de32563ca98` | 115999 → 112760 |
| `docs/assets/drone-aviation/gimbal/step-2.jpg` | `step-2.png` | `aacf0c419431036f02b48d644c899b48bd21210cb4c397d108b7af0f1507da9b` → `e9d5cf4f24503ba8a8f5b67f859f5f7cc5c940752da6cfa07e9e330747e3482d` | 120609 → 115644 |
| `docs/assets/drone-aviation/gimbal/step-3.jpg` | `step-3.png` | `da243d8390fd0c4c9c7a80f8e5ba7d28cc9c970f07a541c7b2cfa42ceb7eee98` → `2852feb8c4d54a135a2a62559d24d6e67df57c6da52c94fb32d7b48665047a10` | 119307 → 113619 |
| `docs/assets/drone-aviation/gimbal/step-4.jpg` | `step-4.png` | `d9e1775c69d6ecf0f8d825981d20b2b8da705500f16052709d47c40443e969d1` → `4be2936f288b912cff7e0b6f6e1c1cf349f5d8f8ae6f3182fef380ae0d0cf655` | 126516 → 120727 |
| `docs/assets/drone-aviation/gimbal/step-5.jpg` | `step-5.png` | `b46295a6d25e85fe819dfbb4700688f7f0c4aa32a4309b041748b3192e7c8e63` → `dc6986792743a35bc6f873a7fd86deff97db48dfc9f07f55c2eef946ee3ec14e` | 126034 → 119343 |
| `docs/assets/drone-aviation/gimbal/step-6.jpg` | `step-6.png` | `d5f29e2479e835fdb9694b17f608d256ee8a29ecace4e1e2af774406402f1000` → `549be824eb627cb7b0473b50bb37983b9c3e5f030f5015a2d1a59d5076bf5ef9` | 147154 → 139074 |
| `docs/assets/drone-aviation/gimbal/step-7.jpg` | `step-7.png` | `5243cc05c05b379a1a35a5d86c9e27855f6047707d01d44e258b84a58f5269d0` → `3b06bd6934b18c2125fedabbee22b1eb32ddcce2a89a974a0eabb0d4f019c6b9` | 105577 → 106840 |
| `docs/assets/drone-aviation/gimbal/step-8.jpg` | `step-8.png` | `c753fba6fc09bcb57050d77680b5dc41aba5442ffe8e969cda04da7a64ac409f` → `6eece406ba9db4cc9c487152b32f48e7c5794e9ad01f6575592337a40fe53b97` | 130261 → 125497 |

- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/exploded.png --out docs/assets/drone-aviation/gimbal/exploded.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/hero.png --out docs/assets/drone-aviation/gimbal/hero.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-6.png --out docs/assets/drone-aviation/gimbal/poster.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-1.png --out docs/assets/drone-aviation/gimbal/step-1.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-2.png --out docs/assets/drone-aviation/gimbal/step-2.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-3.png --out docs/assets/drone-aviation/gimbal/step-3.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-4.png --out docs/assets/drone-aviation/gimbal/step-4.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-5.png --out docs/assets/drone-aviation/gimbal/step-5.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-6.png --out docs/assets/drone-aviation/gimbal/step-6.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-7.png --out docs/assets/drone-aviation/gimbal/step-7.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/gimbal/step-8.png --out docs/assets/drone-aviation/gimbal/step-8.jpg`.

### landing-gear

Command: `marty-solid render docs/assets/drone-aviation/landing-gear/landing-gear.json OUT/landing-gear --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/drone-aviation/landing-gear/exploded.jpg` | `exploded.png` | `ca98518d2409044bbf68951a15afbe4c7ee0081d324deace7759e11a67889cee` → `9d547d422782071df31f0e4c8b4af838237f6bbd6647e887bf87681de2c9bdd5` | 78760 → 86276 |
| `docs/assets/drone-aviation/landing-gear/hero.jpg` | `hero.png` | `44157518ae2639f1c9d6a5996c5443dd896ec649fa94fae40e33b4b1b7840dbd` → `9a285bf663c26960b6ba410d0871da8bb9645ae0f36ed45d5badd3a368958b34` | 76303 → 83938 |
| `docs/assets/drone-aviation/landing-gear/poster.jpg` | `step-3.png` | `0a60e9474615322a5c887dec4b8cb400a8ea374265b00dcc584aa4311a6ae980` → `45b466cc29df9b5c3acafc4814e73a02d6ee7378076d558f5aa0faf5131b09d1` | 111695 → 122590 |
| `docs/assets/drone-aviation/landing-gear/step-1.jpg` | `step-1.png` | `351366e2ad0a31580e57def51d4998b162606c12ec47120a7f4e0d53e1558135` → `fb9057fbe9087adbe2ad00da94291e83df71a4619dcc45a77aeeeb6dbe12c05b` | 113440 → 122020 |
| `docs/assets/drone-aviation/landing-gear/step-10.jpg` | `step-10.png` | `bfd3869f608481a96660e43082d9213ba4bab16933b5888702342cd1dc449dc9` → `cac439fcd2f2f4ecb971629530c9944f5f9847ae04a2773541f89b988261a16e` | 76998 → 88028 |
| `docs/assets/drone-aviation/landing-gear/step-11.jpg` | `step-11.png` | `9c1fb489cda0f17c15811fb87ce9ec579ae9b3ace83ccc1a78f063560eb62ba1` → `5290db6564bd0b3a28ba6322234e68773c960e88fa0d699d88c021449ffbf1c5` | 104514 → 112580 |
| `docs/assets/drone-aviation/landing-gear/step-2.jpg` | `step-2.png` | `e0d2248745ebc9e11c084613a9e8c8cc426ad483e7d55b4e2b6dafa3aecb74bb` → `07938af3ac5edfae55f622df4a15504e9ea28f3ad1e5d16f378e9e30d8f2119d` | 110070 → 110250 |
| `docs/assets/drone-aviation/landing-gear/step-3.jpg` | `step-3.png` | `0a60e9474615322a5c887dec4b8cb400a8ea374265b00dcc584aa4311a6ae980` → `45b466cc29df9b5c3acafc4814e73a02d6ee7378076d558f5aa0faf5131b09d1` | 111695 → 122590 |
| `docs/assets/drone-aviation/landing-gear/step-4.jpg` | `step-4.png` | `2174a9e16aceef64540af2dd4989e0fd1969e3e5e76f624f323ebc5af6a0218d` → `cea89ce1e1d0dd26819f531c90c646d1e9a4aa775ce37f107e833f5d5ec38533` | 103146 → 110217 |
| `docs/assets/drone-aviation/landing-gear/step-5.jpg` | `step-5.png` | `d0ad4003baf54803fe53afaf14daa72dfa993e31151fb6c8e50baaa0b5941bcc` → `425c9fd7e0d896b0781d712416adaa028cc083758047f0814d4cc4eaaeaab467` | 107023 → 106727 |
| `docs/assets/drone-aviation/landing-gear/step-6.jpg` | `step-6.png` | `1839292336dccd733bc3fbb2b8f3d70b40205b303cf2c0d96ef6c933c526abeb` → `83b0a8f5b7d8a2732f8f6bc650f174309c0cec1eef5e8ca95ffd7e105619fd37` | 81707 → 92069 |
| `docs/assets/drone-aviation/landing-gear/step-7.jpg` | `step-7.png` | `8cab57d431280271582f9a47816fcf6d7039569230481bbaba150f266b2cfc4e` → `09b7921637afadf353d8aebb3eeae2f16e7f58c27226e0566fa6cbd8ef01fef7` | 81380 → 92084 |
| `docs/assets/drone-aviation/landing-gear/step-8.jpg` | `step-8.png` | `655f6cf75ce5f0317a4779753b5efdc5a0062c4749eeba10cc038621d5490e0f` → `6041360c9696604e1b0510793cf9d6ae1692c890a762a5030ba5162e15bf4f5c` | 76715 → 88071 |
| `docs/assets/drone-aviation/landing-gear/step-9.jpg` | `step-9.png` | `5f51dd7086eeb6a7f8d8129cf14476fb07dc8773b84b77792b45278ea7626faa` → `c0c9a246e57a8cd83dcaade500f9f7caf626d1a38e36176d457b2d3c4b19c1ab` | 75587 → 87106 |

- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/exploded.png --out docs/assets/drone-aviation/landing-gear/exploded.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/hero.png --out docs/assets/drone-aviation/landing-gear/hero.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-3.png --out docs/assets/drone-aviation/landing-gear/poster.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-1.png --out docs/assets/drone-aviation/landing-gear/step-1.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-10.png --out docs/assets/drone-aviation/landing-gear/step-10.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-11.png --out docs/assets/drone-aviation/landing-gear/step-11.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-2.png --out docs/assets/drone-aviation/landing-gear/step-2.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-3.png --out docs/assets/drone-aviation/landing-gear/step-3.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-4.png --out docs/assets/drone-aviation/landing-gear/step-4.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-5.png --out docs/assets/drone-aviation/landing-gear/step-5.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-6.png --out docs/assets/drone-aviation/landing-gear/step-6.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-7.png --out docs/assets/drone-aviation/landing-gear/step-7.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-8.png --out docs/assets/drone-aviation/landing-gear/step-8.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/landing-gear/step-9.png --out docs/assets/drone-aviation/landing-gear/step-9.jpg`.

### payload-cg

Command: `marty-solid render docs/assets/drone-aviation/payload-cg/payload-cg.json OUT/payload-cg --size 1280x800 --look studio --no-story --no-loop`.

Look: `studio` (explicit).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/drone-aviation/payload-cg/exploded.jpg` | `exploded.png` | `a3c42c3a01914e2f223411a142b963727a58faaf791aff207271dd20d1a76dd3` → `54af7cb08654036bf52c757040c6e0712a1daa2a6a97415f2c4cd577616f715a` | 115921 → 117432 |
| `docs/assets/drone-aviation/payload-cg/hero.jpg` | `hero.png` | `c6b4016f719cedba1a9a58b0ae6b2359028052a3efc9ed743c82b885bc2be3b7` → `3ede961196bbef7863407ffc0e640086cfd041e5347948dbf7384f1e61df3f5e` | 116386 → 117364 |
| `docs/assets/drone-aviation/payload-cg/poster.jpg` | `step-5.png` | `818a7f492b0d94ce624286b1838d2b3ff363f4d6f00c4be2e02c942663496132` → `9932097996efd6b94233832378c8664226430364cb0a7409a7a2984c5f6884b1` | 147401 → 147475 |
| `docs/assets/drone-aviation/payload-cg/step-1.jpg` | `step-1.png` | `ff3a5753ce319b02148e319bc1b8bc1f6721d5a510c138700b8d3fb05265b1c9` → `fe7256e34b479f83d330c602601424c41db0d31d857e3cb0c54cfbf630e932b0` | 173064 → 155239 |
| `docs/assets/drone-aviation/payload-cg/step-2.jpg` | `step-2.png` | `73dcfd7d04b3f939feb15a8b8cce6c6aaca485df0adf663f8798849b1bf4e79e` → `9b366bbb7777a5477e4e82e68437da70a69fc311f019d1da94242adc1d2e9e0c` | 149337 → 148369 |
| `docs/assets/drone-aviation/payload-cg/step-3.jpg` | `step-3.png` | `03416a33e1e3b25807f0311339dc0fde83f0b26523addbe476011ab3e1f5a576` → `031280d0d0bfa00285af4ef96ccf4f92bcf8bd4f79700ad68dcec6dc651ac7f3` | 119745 → 123998 |
| `docs/assets/drone-aviation/payload-cg/step-4.jpg` | `step-4.png` | `e9e47492150fc608970d07e39733e67add4d7ac04aa9eac623b6f06d21e69340` → `db60507c925c6aa383bd9a41637dd7cd25ad32962a304d8a3fa6660bbc6adf23` | 117740 → 123401 |
| `docs/assets/drone-aviation/payload-cg/step-5.jpg` | `step-5.png` | `818a7f492b0d94ce624286b1838d2b3ff363f4d6f00c4be2e02c942663496132` → `9932097996efd6b94233832378c8664226430364cb0a7409a7a2984c5f6884b1` | 147401 → 147475 |
| `docs/assets/drone-aviation/payload-cg/step-6.jpg` | `step-6.png` | `5fa0d89c53c2f06e45378e6969cafc38a888cc41abfc4c2c7ba9635b4ac2742a` → `62dee78003d3d117ff3b33bfa8403cf31348074ccb82eace7b600b02c6acb40e` | 136208 → 138533 |
| `docs/assets/drone-aviation/payload-cg/step-7.jpg` | `step-7.png` | `67ff813184685b7afea7e05063d68f81c82ec71ba9e993a62a3da5bb5b2bab92` → `e1729817c99d22822dbd86fb75db9e39079c37304937203d28478484ece1514e` | 134001 → 136817 |
| `docs/assets/drone-aviation/payload-cg/step-8.jpg` | `step-8.png` | `72c745c70982f9603ad128074908b2ada872d46532d6ae9a354712b00ca60e90` → `78e25fd9736d79551c89139140f86ae75301106a3c79fae3bedbd2aa1bbc616c` | 153975 → 154267 |
| `docs/assets/drone-aviation/payload-cg/step-9.jpg` | `step-9.png` | `ee6ffb186083895ec2ef2ca0a8786504d5b4a1eab7a456505a64d5c0df81b26f` → `25775cb21045a8e470b59d35e9b4cbeca539eb9ce699f981b91364708e2212f1` | 133986 → 138721 |

- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/exploded.png --out docs/assets/drone-aviation/payload-cg/exploded.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/hero.png --out docs/assets/drone-aviation/payload-cg/hero.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-5.png --out docs/assets/drone-aviation/payload-cg/poster.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-1.png --out docs/assets/drone-aviation/payload-cg/step-1.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-2.png --out docs/assets/drone-aviation/payload-cg/step-2.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-3.png --out docs/assets/drone-aviation/payload-cg/step-3.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-4.png --out docs/assets/drone-aviation/payload-cg/step-4.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-5.png --out docs/assets/drone-aviation/payload-cg/step-5.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-6.png --out docs/assets/drone-aviation/payload-cg/step-6.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-7.png --out docs/assets/drone-aviation/payload-cg/step-7.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-8.png --out docs/assets/drone-aviation/payload-cg/step-8.jpg`.
- Conversion: `sips -s format jpeg -s formatOptions 85 OUT/payload-cg/step-9.png --out docs/assets/drone-aviation/payload-cg/step-9.jpg`.

### solid

Command: `marty-solid3d --export OUT/solid`.

Look: `studio` (renderer default; the example keeps its own overlay and camera).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/solid/exploded-labelled.png` | `exploded-labelled.png` | `a3f02275fa20512ccc3f592666670287fda8dddf52c9c4d1627010bfced44109` → `eef1803d4721c589976afc93cc3994aacfabefd073ef20472bbcf9fa8435900e` | 917596 → 947867 |
| `docs/assets/solid/hero.png` | `hero.png` | `fd521558fd1825038249a76ebfed7044e5d752e2f9c3d873557bc69f1eb64467` → `17543f41bbb486bf4339a91a2d5ceebfc63118def73c603510221756ccdd5913` | 946810 → 919466 |
| `docs/assets/solid/planetary-loop.gif` | `planetary-loop.gif` | `89eeab02e5cb0cdaa4ded8cafcd7010ae3d780b0fd497d3e67d78b8b6a0a6a96` → `5a2c09d6592899530dafe03d09a6e138ed72c71609a2c219c50d2dc4f5e47939` | 2625137 → 3496183 |
| `docs/assets/solid/slider-crank-section.png` | `slider-crank-section.png` | `87926b2fa7bbcea44343a72143c1ac061ff623ef870204dd7f2d8913d079f7d8` → `9c13720bb13f7905497b1f7ffce38bb50b8739fc4ebb9e19623a731c895d59ee` | 801523 → 897383 |


### turbofan

Command: `marty-turbofan --export OUT/turbofan`.

Look: `studio` (renderer default; the example keeps its own overlay and camera).

| File | Exported frame | Old SHA-256 → new SHA-256 | Old → new bytes |
| --- | --- | --- | --- |
| `docs/assets/turbofan/exploded.png` | `step-8.png` | `8d4d8fbb78198e2d69696390ae0c7e5a3ba41eb09f9cc2cb19a8af65c9be4506` → `7fa610b379d5c2c7b47cc71cc38d57d9acc2b22b2217cd7430db293c355e7421` | 953242 → 1021356 |
| `docs/assets/turbofan/labelled.png` | `labelled.png` | `c12d119f2ed6165eee636ceaf642143bd01ed6c390a38c0c6b911e40fbd13b9e` → `c3a0bbcdd027808fc17f41b38496a199da258378365144e47e2d3a10df2b5573` | 993843 → 993830 |
| `docs/assets/turbofan/turbofan-loop.gif` | `turbofan-loop.gif` | `12d9f93fec8cd20a950ff3a5e4b91b9a81a82ca60fe7de45914d28674aa7c994` → `e68bee482a1d07b3a23022a0e86b1bb366ad2beead0062c373c7f2d2bd2c7d92` | 5422629 → 6500104 |


## Files left unchanged

| File | Reason |
| --- | --- |
| `docs/assets/drone-aviation/brushless-motor/loop.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/drone-aviation/brushless-motor/story.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/drone-aviation/gimbal/story.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/drone-aviation/landing-gear/story.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/drone-aviation/payload-cg/story.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/drone-aviation/quadcopter/loop.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/drone-aviation/quadcopter/story.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/jet-suit/story.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/jet-suit-ai/story.mp4` | Video is outside this image refresh; original capture and look retained. |
| `docs/assets/lessons/beat-1.png` | 2D capture, not an old-default solid render. |
| `docs/assets/lessons/beat-2-turning.png` | 2D capture, not an old-default solid render. |
| `docs/assets/lessons/beat-3.png` | 2D capture, not an old-default solid render. |
| `docs/assets/lessons/beat-4.png` | 2D capture, not an old-default solid render. |
| `docs/assets/lessons/beat-5.png` | 2D capture, not an old-default solid render. |
| `docs/assets/lessons/learner-slider-45.png` | 2D capture, not an old-default solid render. |
| `docs/assets/lessons/rotation-loop.gif` | 2D capture, not an old-default solid render. |
| `docs/assets/native/counts.png` | 2D capture, not an old-default solid render. |
| `docs/assets/native/function.png` | 2D capture, not an old-default solid render. |
| `docs/assets/native/handoff.png` | 2D capture, not an old-default solid render. |
| `docs/assets/native/motion.gif` | 2D capture, not an old-default solid render. |
| `docs/assets/native/motion.png` | 2D capture, not an old-default solid render. |
| `docs/assets/native/overview.png` | 2D capture, not an old-default solid render. |
| `docs/assets/native/shortest-path.gif` | 2D capture, not an old-default solid render. |
| `docs/assets/native/shortest-path.png` | 2D capture, not an old-default solid render. |
| `docs/assets/native/tree.png` | 2D capture, not an old-default solid render. |
| `docs/assets/native/two-pointers.gif` | 2D capture, not an old-default solid render. |
| `docs/assets/native/two-pointers.png` | 2D capture, not an old-default solid render. |
| `docs/assets/pathtrace/exploded.png` | MartyGraphicsPathTracer output; independent of the solid renderer look. |
| `docs/assets/pathtrace/gearbox-loop-640.gif` | MartyGraphicsPathTracer output; independent of the solid renderer look. |
| `docs/assets/pathtrace/gearbox-loop.gif` | MartyGraphicsPathTracer output; independent of the solid renderer look. |
| `docs/assets/pathtrace/hero.png` | MartyGraphicsPathTracer output; independent of the solid renderer look. |
| `docs/assets/pathtrace/side-by-side.png` | MartyGraphicsPathTracer output; independent of the solid renderer look. |
| `docs/assets/turbofan/pathtraced-hero.png` | MartyGraphicsPathTracer output; independent of the solid renderer look. |
| `docs/assets/visual-quality/looks-contact-sheet.jpg` | Historical classic/studio/paper or before/after comparison; replacing it would erase its evidence. |
| `docs/assets/visual-quality/materials-contact-sheet.jpg` | Historical classic/studio/paper or before/after comparison; replacing it would erase its evidence. |
| `docs/assets/visual-quality/round-0-contact-sheet.jpg` | Historical classic/studio/paper or before/after comparison; replacing it would erase its evidence. |
| `docs/assets/visual-quality/type-contact-sheet.jpg` | Historical classic/studio/paper or before/after comparison; replacing it would erase its evidence. |

The external website MP4 files linked by README and SHOWCASE are also unchanged.
All images under `benchmark/` are excluded and byte-identical; that directory is outside this task.
