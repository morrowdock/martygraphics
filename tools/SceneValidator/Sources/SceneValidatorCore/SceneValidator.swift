// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import MartyGraphics

/// Checks scene JSON files with the same `MGParser.scene(data:)` call an app uses before drawing.
/// It only reads regular files named on the command line: no stdin, directory walking, network or rendering.
public enum SceneValidator {
    public static let toolName = "marty-scene-validate"
    /// Identifies the `--json` report layout. Bump only for incompatible changes.
    public static let reportFormat = "marty-scene-validate/1"
    /// `MGParser.scene(data:)` rejects anything larger; reading one byte more proves a file is over the limit.
    public static let maximumInputBytes = MGLimits.sceneBytes * 2

    public enum Status: Int32, Sendable {
        /// Every file was read and accepted by the parser.
        case valid = 0
        /// Every file was read and at least one was rejected by the parser (or exceeds its byte limit).
        case invalid = 1
        /// The command line was not understood; no file was read.
        case usage = 2
        /// At least one file could not be read. Takes precedence over `invalid`.
        case unreadable = 3
    }

    public enum Outcome: Equatable, Sendable {
        case valid(dimension: String, items: Int, steps: Int, template: String?)
        /// `reason` is the parser's own reason code (or `input.too-large`); `detail` is optional extra text.
        case invalid(reason: String, detail: String?)
        /// `reason` is one of `not-found`, `permission-denied`, `not-a-regular-file`, `read-error`.
        case unreadable(reason: String, detail: String)
    }

    public struct Report: Equatable, Sendable {
        public let status: Status
        public let stdout: String
        public let stderr: String
    }

    public static let usage = """
    Usage: \(toolName) [--json] [--] FILE...
           \(toolName) --help

    Checks each MartyGraphics scene JSON file with MGParser.scene(data:), the
    same strict validation an app runs before drawing. Files are checked in the
    order given; the tool never renders, executes, downloads or writes anything.

    Options:
      --json    Print one machine-readable JSON report instead of text lines.
      -h, --help
                Print this help and exit 0; must be used alone.
      --        Treat every later argument as a file, even if it starts with '-'.

    Inputs:
      Each FILE must name a regular file of at most \(maximumInputBytes) raw bytes.
      The parser also limits canonical scene content to \(MGLimits.sceneBytes) bytes.
      Symbolic links are followed; the final target must be a regular
      file. Directories, FIFOs, sockets and devices are refused without reading.
      Standard input ('-') and recursive directory scans are not supported.

    Exit status:
      0  every file is a valid scene
      1  at least one file was rejected by the parser (all files were read)
      2  usage error; no file was read
      3  at least one file could not be read (takes precedence over 1)
      4  output could not be written (including a closed pipe)

    """

    // MARK: entry point

    public static func run(arguments: [String]) -> Report {
        if arguments == ["--help"] || arguments == ["-h"] {
            return Report(status: .valid, stdout: usage, stderr: "")
        }
        var json = false
        var files: [String] = []
        var operandsOnly = false
        for argument in arguments {
            if operandsOnly { files.append(argument); continue }
            switch argument {
            case "--": operandsOnly = true
            case "-h", "--help": return usageError("help must be used alone")
            case "--json": json = true
            case "-": return usageError("reading standard input is not supported; name a file")
            default:
                if argument.hasPrefix("-") {
                    return usageError("unknown option '\(terminalSafe(argument))'")
                }
                files.append(argument)
            }
        }
        guard !files.isEmpty else { return usageError("no scene files given") }

        let results = files.map { ($0, check(path: $0)) }
        let status = overallStatus(results.map(\.1))
        let stdout = json ? jsonReport(results, status: status) : textReport(results)
        return Report(status: status, stdout: stdout, stderr: "")
    }

    static func usageError(_ message: String) -> Report {
        Report(status: .usage, stdout: "",
               stderr: "\(toolName): \(message)\nTry '\(toolName) --help' for usage.\n")
    }

    public static func overallStatus(_ outcomes: [Outcome]) -> Status {
        var status = Status.valid
        for outcome in outcomes {
            switch outcome {
            case .valid: continue
            case .invalid: if status == .valid { status = .invalid }
            case .unreadable: status = .unreadable
            }
        }
        return status
    }

    // MARK: checking one file

    public static func check(path: String) -> Outcome {
        switch readBounded(path: path) {
        case .failure(let failure): return failure.outcome
        case .success(let data): return check(data: data)
        }
    }

    /// Validates bytes already in memory. The size rule matches `MGParser.scene(data:)`.
    public static func check(data: Data) -> Outcome {
        guard data.count <= maximumInputBytes else {
            return .invalid(reason: "input.too-large", detail: "larger than \(maximumInputBytes) bytes")
        }
        switch MGParser.scene(data: data) {
        case .success(let scene):
            return .valid(dimension: scene.is3D ? "3d" : "2d", items: scene.items.count,
                          steps: scene.steps.count, template: scene.template)
        case .failure(let error):
            return .invalid(reason: error.reason, detail: detail(for: error.reason, data: data))
        }
    }

    /// Extra wording only; the reason code always comes from the parser unchanged.
    static func detail(for reason: String, data: Data) -> String? {
        switch reason {
        case "json":
            if (try? JSONSerialization.jsonObject(with: data)) == nil {
                return "not valid JSON with an object or array at the top level"
            }
            return "JSON contains a value the scene format cannot hold"
        case "template.unknown":
            return "not a built-in template; app-registered packs are not loaded by this tool"
        default:
            return nil
        }
    }

    // MARK: bounded reading

    /// Follows symlinks, refuses non-regular files before opening them, re-checks the opened descriptor
    /// (so a swap between `stat` and `open` cannot substitute a FIFO or device) and reads at most one byte
    /// past the parser limit.
    struct ReadFailure: Error { let outcome: Outcome }

    static func readBounded(path: String) -> Result<Data, ReadFailure> {
        var before = stat()
        guard stat(path, &before) == 0 else { return .failure(ReadFailure(outcome: openFailure(errno))) }
        guard isRegular(before.st_mode) else { return .failure(ReadFailure(outcome: notRegular(before.st_mode))) }

        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
        guard fd >= 0 else { return .failure(ReadFailure(outcome: openFailure(errno))) }
        defer { close(fd) }

        var opened = stat()
        guard fstat(fd, &opened) == 0 else { return .failure(ReadFailure(outcome: readFailure(errno))) }
        guard isRegular(opened.st_mode) else { return .failure(ReadFailure(outcome: notRegular(opened.st_mode))) }
        guard opened.st_dev == before.st_dev, opened.st_ino == before.st_ino else {
            return .failure(ReadFailure(outcome: .unreadable(reason: "read-error", detail: "file changed while opening")))
        }

        let limit = maximumInputBytes + 1
        var buffer = [UInt8](repeating: 0, count: limit)
        var total = 0
        while total < limit {
            let count = buffer.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress! + total, limit - total)
            }
            if count > 0 { total += count; continue }
            if count == 0 { break }
            if errno == EINTR { continue }
            return .failure(ReadFailure(outcome: readFailure(errno)))
        }
        return .success(Data(buffer[0..<total]))
    }

    static func isRegular(_ mode: mode_t) -> Bool { mode & S_IFMT == S_IFREG }

    static func notRegular(_ mode: mode_t) -> Outcome {
        let kind: String
        switch mode & S_IFMT {
        case S_IFDIR: kind = "directory"
        case S_IFIFO: kind = "FIFO"
        case S_IFSOCK: kind = "socket"
        case S_IFCHR: kind = "character device"
        case S_IFBLK: kind = "block device"
        default: kind = "special file"
        }
        return .unreadable(reason: "not-a-regular-file", detail: kind)
    }

    static func openFailure(_ code: Int32) -> Outcome {
        switch code {
        case ENOENT, ENOTDIR: return .unreadable(reason: "not-found", detail: "no such file")
        case EACCES, EPERM: return .unreadable(reason: "permission-denied", detail: "permission denied")
        default: return readFailure(code)
        }
    }

    static func readFailure(_ code: Int32) -> Outcome {
        .unreadable(reason: "read-error", detail: String(cString: strerror(code)))
    }

    // MARK: reports

    static func textReport(_ results: [(String, Outcome)]) -> String {
        var lines: [String] = []
        var counts = (valid: 0, invalid: 0, unreadable: 0)
        for (path, outcome) in results {
            let name = terminalSafe(path)
            switch outcome {
            case .valid(let dimension, let items, let steps, let template):
                counts.valid += 1
                var facts = [dimension, plural(items, "item"), plural(steps, "step")]
                if let template { facts.append("template \(terminalSafe(template))") }
                lines.append("\(name): valid (\(facts.joined(separator: ", ")))")
            case .invalid(let reason, let detail):
                counts.invalid += 1
                lines.append("\(name): invalid: \(terminalSafe(reason))" + (detail.map { " (\($0))" } ?? ""))
            case .unreadable(let reason, let detail):
                counts.unreadable += 1
                lines.append("\(name): unreadable: \(reason) (\(detail))")
            }
        }
        lines.append("Checked \(plural(results.count, "file")): \(counts.valid) valid, "
                     + "\(counts.invalid) invalid, \(counts.unreadable) unreadable.")
        return lines.joined(separator: "\n") + "\n"
    }

    static func jsonReport(_ results: [(String, Outcome)], status: Status) -> String {
        var counts = ["valid": 0, "invalid": 0, "unreadable": 0]
        let files: [[String: Any]] = results.map { path, outcome in
            switch outcome {
            case .valid(let dimension, let items, let steps, let template):
                counts["valid", default: 0] += 1
                var entry: [String: Any] = ["path": path, "status": "valid", "dim": dimension,
                                            "items": items, "steps": steps]
                if let template { entry["template"] = template }
                return entry
            case .invalid(let reason, let detail):
                counts["invalid", default: 0] += 1
                var entry: [String: Any] = ["path": path, "status": "invalid", "reason": reason]
                if let detail { entry["detail"] = detail }
                return entry
            case .unreadable(let reason, let detail):
                counts["unreadable", default: 0] += 1
                return ["path": path, "status": "unreadable", "reason": reason, "detail": detail]
            }
        }
        let document: [String: Any] = ["format": reportFormat, "exitCode": Int(status.rawValue),
                                       "summary": counts, "files": files]
        // Every value above is a String, Int, array or dictionary, so serialisation cannot fail.
        let data = (try? JSONSerialization.data(withJSONObject: document,
                                                options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let encoded = String(decoding: data, as: UTF8.self).unicodeScalars.map { scalar in
            terminalSensitive(scalar.value) ? String(format: "\\u%04x", scalar.value) : String(scalar)
        }.joined()
        return encoded + "\n"
    }

    static func plural(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }

    static func terminalSensitive(_ value: UInt32) -> Bool {
        (0x7F...0x9F).contains(value) || value == 0x061C || value == 0x200E || value == 0x200F
            || (0x2028...0x202E).contains(value) || (0x2066...0x2069).contains(value)
    }

    /// Escapes control characters so a crafted file name or reason cannot rewrite terminal output.
    public static func terminalSafe(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x5C: out += "\\\\"
            case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E...0x200F, 0x2028...0x202E, 0x2066...0x2069:
                out += "\\u{" + String(scalar.value, radix: 16) + "}"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
