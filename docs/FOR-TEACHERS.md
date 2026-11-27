# For teachers

This page is for teachers who want to know what MartyGraphics can do in a classroom today, and what it cannot.

## What it is, in one paragraph

MartyGraphics turns a short text description of a diagram into a clean, animated board. You describe the board in
JSON: "a ball here, a label there, then in step 2 show this arrow and say this sentence." The engine checks the
description before it draws anything. If something is wrong, for example a point off the board or a typo in a key, it
refuses and names the problem instead of drawing a broken picture. For 3D mechanisms such as gear trains, it also
works out how the parts move and checks that the gears can actually mesh.

## What you need today

MartyGraphics is a **developer tool**, not a classroom app. To see your own boards you need:

- a Mac with macOS 14 or later, and
- a Swift 6 toolchain (for example, from Xcode), and
- the ability to run a few commands in Terminal, or a colleague who can.

There is no web version and no Windows, Chromebook or iPad app in this repository. Nothing needs an account, a key
or an internet connection once the code is downloaded.

## Your first board

1. Follow step 1 of the [quick start](../README.md#quick-start) to open the example window.
2. Open one of the seven example files in `Examples/Showcase/Sources/MartyShowcase/Scenes`, for example `counts.json`,
   in any text editor.
3. Change a value, a label or a sentence. Save the file.
4. Run the same command again (or use `--verify` to check without opening a window). Your change appears. If the
   file breaks a rule, the command stops and prints a reason such as `bars.bars` instead of opening the window.

The [showcase instructions](../Examples/Showcase/README.md#make-a-first-change) walk through this. When you want a
new board instead of an edited one, start from a [cookbook recipe](COOKBOOK.md): a labelled triangle built in steps,
a water-cycle diagram, a distance-time plot, a class poll, forces on a ramp, a times table and more.

## What the engine checks, and what you check

| The engine checks | You check |
| --- | --- |
| The description is well formed and uses only known keys | That every sentence is true |
| Every item has a unique name, and references point to real items | That typed numbers are right (a plot draws the points you give it; it does not compute them) |
| Points are on the board; text, items and steps are within limits | That arrow lengths and positions mean what you intend |
| Text has no links, markup or hidden characters | That the board is readable at the size your class will see it |
| 3D gear meshes, gear ratios and joint motion (3D documents only) | Strength, friction, airflow and anything else the engine lists as not checked |

The engine checks motion and layout. It does not know your subject. A board that passes the check can still teach
something wrong if its words are wrong.

## Writing good boards

- **One idea per step.** A scene can have up to 8 steps. Each step's narration can be up to 200 characters; two
  short sentences read better than one long one.
- **Reveal, don't dump.** Use a step's `show` list so items appear when the narration reaches them
  ([recipe 2](COOKBOOK.md#2-reveal-a-diagram-step-by-step)).
- **Point at what you mean.** Use `focus`, or a `highlight` that moves between steps
  ([recipe 3](COOKBOOK.md#3-move-a-highlight-through-a-flow)).
- **Say when data is invented.** The examples here label invented numbers as invented.
- **Keep the words in sync.** If you change a value, change the sentence that quotes it. The engine will not.
- **Give the words as text too.** Some learners cannot see the board. Provide the narration in your own materials.
  For explainer documents, `marty-solid transcript` prints every caption and label as plain text
  ([transcript](EXPLAINER.md#transcript)).

## AI-written boards

MartyGraphics does not include an AI model. A separate app can ask a model to write the JSON, and the engine then
checks it like any other description. This catches broken descriptions, not wrong ideas. In the project's own
50-question development test, a model's answers were all accepted within three repairs, but only 29 of 40 in-scope
answers were fully correct in their mechanics. An unedited AI-written jet-suit lesson, shown with its fact check,
had 1 wrong sentence and 12 corrections ([gallery](GALLERY.md#from-a-prompt-ai-written)). Review every AI-written
board before you use it.

## Accessibility and classroom use

- The board gives VoiceOver its title and the current narration. Keyboard use and VoiceOver behaviour have not yet
  been checked by hand, so test with your own learners' tools.
- Animation stops when the system's Reduce Motion setting is on.
- The engine makes no network calls and saves nothing on its own. What a host app stores is up to that app.
- Colour choices have not been reviewed for colour-vision deficiency. Do not rely on colour alone: say it in words too.

## Using the examples in class

The code, the example JSON and the images made from them are under the [Apache-2.0 license](../LICENSE), which allows
classroom use. The [gallery](GALLERY.md) says what each example teaches and who wrote it. The fact-checked explainers
list their sources (for example the [jet-suit sources](assets/jet-suit/SOURCES.md) and the
[drone and aviation facts](assets/drone-aviation/FACTS.md)). Those checks were made by AI models, not by subject
experts, so read them as a starting point.

## Where to go next

- [Gallery](GALLERY.md): every example, with what it teaches.
- [Cookbook](COOKBOOK.md): ten short boards to copy and change.
- [Concepts](CONCEPTS.md): the parts of a scene, and the limits.
- [FAQ](FAQ.md): platforms, releases, refusals and exports.
