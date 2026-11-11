# marty-scene-validate

Check MartyGraphics scene JSON files from a terminal or a CI step, without
opening an app. Each file goes through `MGParser.scene(data:)`, the same strict
validation an app runs before drawing, so a file that passes here is one the
engine accepts. The exit status tells a script whether every file is valid.

## Requirements and platform limits

macOS 14 or later with a Swift 6 toolchain. The tool links the MartyGraphics
library, which needs Apple's SwiftUI, SceneKit, CoreGraphics and Combine. Linux
and Windows are **not** supported. The hosted `CI` workflow's Ubuntu `hygiene`
job does not build or run it; its `macos` job tests it. See [Verify on Mac](../../docs/VERIFY-ON-MAC.md).
There are no external package dependencies.

## Build and run

From the root of a MartyGraphics checkout:

```sh
swift build -c release --jobs 2 --package-path tools/SceneValidator
BIN_DIR="$(swift build -c release --package-path tools/SceneValidator --show-bin-path)"
"$BIN_DIR/marty-scene-validate" -- scenes/intro.json "scenes/second scene.json"
```

Example output:

```text
scenes/intro.json: valid (2d, 4 items, 3 steps)
scenes/second scene.json: invalid: id.duplicate.dot
Checked 2 files: 1 valid, 1 invalid, 0 unreadable.
```

For files passed to the parser, the value after `invalid:` is its reason code, reported unchanged
(see the [protocol](../../docs/PROTOCOL.md) for the format's rules). A short
explanation follows in parentheses where one helps, for example malformed JSON
or an unknown template. The tool itself emits `input.too-large` when its raw-input
read bound is exceeded, before invoking the parser.

## Usage

```text
marty-scene-validate [--json] [--] FILE...
marty-scene-validate --help
```

| Option | Meaning |
| --- | --- |
| `--json` | Print one JSON report (sorted keys, one line) instead of text lines. |
| `-h`, `--help` | Print help and exit 0; must be used alone. |
| `--` | Treat every later argument as a file, even one starting with `-`. Recommended in scripts. |

Any other argument starting with `-` is a usage error. Files are checked and
reported in the order given; repeated names are checked again.

## Exit status

| Code | Meaning |
| --- | --- |
| 0 | Every file is a valid scene. |
| 1 | Every file was read and at least one was rejected by the parser. |
| 2 | Usage error (unknown option, no files, `-`, or help combined with other arguments). No file was read. |
| 3 | At least one file could not be read. Takes precedence over 1. |
| 4 | Output could not be written, including a closed descriptor or broken pipe. Takes precedence over other results. |

Text results go to standard output. Usage errors go to standard error as text,
even with `--json`.
Output failures produce a best-effort diagnostic on standard error, never a
complete JSON report. Consumers must check the process exit status before trusting
the report: its `exitCode` describes validation, not successful delivery.

## Inputs

- Only the files named on the command line are read. There is no directory
  walking and no standard input. To check a tree, let the shell or `find`
  produce names, for example
  `find scenes -name '*.json' -type f -print0 | xargs -0 marty-scene-validate --`.
  `xargs` may split a long list across several runs and then exits 123 rather
  than passing the tool's code through.
- Each file must be a regular file of at most 16384 raw bytes. A larger file is
  reported as `invalid: input.too-large` after reading only one byte past the bound.
  Passing this bound does not imply validity: the parser also limits canonical
  scene content to 8192 bytes and may reject it with `scene.bytes`.
- Symbolic links are followed. The final target must be a regular file.
  Directories, FIFOs, sockets and devices are reported as
  `unreadable: not-a-regular-file` without being opened for reading, so a FIFO
  cannot make the tool wait.
- Scene content is only parsed. Nothing is rendered, executed, downloaded or
  written.
- Control and bidirectional-formatting characters in file names are escaped in
  text output. JSON also escapes bidirectional-formatting characters and C1 controls;
  decoding the JSON restores the original path, so consumers must escape it again
  before printing it to a terminal.

## JSON report

```json
{"exitCode":1,"files":[{"dim":"2d","items":4,"path":"scenes/intro.json","status":"valid","steps":3},{"path":"scenes/bad.json","reason":"scene.version","status":"invalid"}],"format":"marty-scene-validate/1","summary":{"invalid":1,"unreadable":0,"valid":1}}
```

`status` is `valid`, `invalid` or `unreadable`. Valid entries add `dim`,
`items`, `steps` and, for template scenes, `template`. Invalid entries add the
parser `reason` and sometimes `detail`. Unreadable entries add a `reason` (one
of `not-found`, `permission-denied`, `not-a-regular-file` or `read-error`) and
a `detail`. `format` changes only if the layout changes incompatibly.

## What it does not check

- Templates from packs an app registers at runtime with `MGPacks.register`
  are unknown here, so their scenes fail with `template.unknown`. Only built-in
  templates are available.
- Patches (`MGPatch`) and streamed scenes are out of scope.
- A valid scene can still look poor. The tool does not judge layout, legibility
  or visual quality on any device.

## Tests

```sh
swift test --package-path tools/SceneValidator
```

The tests build scenes in a temporary directory: valid scenes, malformed JSON,
parser reason codes, the byte limit, missing files, FIFOs, directories,
symlinks, permissions, unknown options, `--`, several files, paths with
spaces, help-argument ordering, bidirectional-character escaping and JSON path
roundtripping, the JSON report, and the built executable's exit codes including
closed stdout and stderr. Interrupted and partial output writes are handled in
the implementation but do not have injected-failure regression tests.
