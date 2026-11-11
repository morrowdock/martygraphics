// SPDX-License-Identifier: Apache-2.0
// marty-solid export-gltf: the strict check, then the scene and its loop motion as glTF 2.0 binary (docs/GLTF-EXPORT.md).
import Foundation
import MartyGraphics
import MartySolidGLTF

/// Writes `<name>.glb` and `<name>.manifest.json` into a NEW directory, only after the strict check passes. A refused
/// document prints its strict report (exit 1) and creates no directory. Explainer and lesson documents are
/// `kind.unsupported` (the exporter takes assemblies).
func exportGLTF(_ path: String, _ outPath: String, fps: Int, width: Int, height: Int, engineCommit: String,
                library lib: MGSolidLibrary) throws -> Int32 {
    let document = try loadDocument(path)
    if document.kind == "explainer" || document.kind == "lesson" { return unsupportedKind() }
    let src: Loaded
    do { src = try load(path) } catch let big as TooLarge {
        print(json(MGSolidReport.refused(MGSolidIssue("assembly.bytes", limit: big.detail(limit: MGSolidLimits.bytes)), engine: engine).json)); return 1
    }
    let checked: MGSolidGLTF.Checked
    switch MGSolidGLTF.check(data: src.data, library: lib, engine: engine) {
    case .failure(let refused): print(refused.report.text); return 1
    case .success(let c): checked = c
    }
    let file = URL(fileURLWithPath: path).lastPathComponent
    let stem = file.hasSuffix(".json") ? String(file.dropLast(5)) : file
    let output: MGSolidGLTF.Output
    do {
        let timeline = try MGSolidGLTF.renderLoop(checked, fps: fps, width: width, height: height)
        output = try MGSolidGLTF.export(checked, timeline: timeline, sourceID: stem, glbName: stem + ".glb", engineCommit: engineCommit,
                                        engine: engine)
    } catch let r as MGSolidGLTF.Refusal {
        print(json(stamped(["ok": .bool(false), "reason": .string(r.reason), "part": opt(r.part)]))); return 1
    }
    let out = URL(fileURLWithPath: outPath, isDirectory: true)
    // Atomic "must not exist", as for `render`; never leave a half-written result.
    do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false) }
    catch { throw CLIError.invalid("Cannot create a NEW output directory at \(out.path) (it exists, or its parent is missing)") }
    var finished = false
    defer { if !finished { try? FileManager.default.removeItem(at: out) } }
    let glbURL = out.appendingPathComponent(stem + ".glb"), manifestURL = out.appendingPathComponent(stem + ".manifest.json")
    try output.glb.write(to: glbURL, options: .withoutOverwriting)
    try Data(output.manifestText.utf8).write(to: manifestURL, options: .withoutOverwriting)
    finished = true
    print(json(stamped(["ok": .bool(true), "glb": .string(glbURL.lastPathComponent), "bytes": .number(Double(output.glb.count)),
                        "sha256": .string(output.sha256), "manifest": .string(manifestURL.lastPathComponent),
                        "fps": output.manifest["fps"] ?? .null, "frameCount": output.manifest["frameCount"] ?? .null])))
    return 0
}
