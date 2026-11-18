// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import MartyGraphicsMLKit
import SceneValidatorCore

let usage = """
Usage: marty-ml-render --ml-kit [--size 1920x1080|1080x1080|1080x1920] [--png-sequence] FILE NEW_OUTPUT
"""

func run(_ arguments: [String]) -> Int32 {
    if arguments == ["--help"] {
        print(usage)
        return 0
    }
    var optedIn = false
    var size: MGMLSize = .landscape
    var format: MGMLExportFormat = .mp4
    var files: [String] = []
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--ml-kit": optedIn = true
        case "--png-sequence": format = .pngSequence
        case "--size":
            index += 1
            guard index < arguments.count, let value = MGMLSize(rawValue: arguments[index]) else {
                return fail(usage, status: 2)
            }
            size = value
        default:
            guard !argument.hasPrefix("-") else { return fail(usage, status: 2) }
            files.append(argument)
        }
        index += 1
    }
    guard files.count == 2 else { return fail(usage, status: 2) }
    guard optedIn else { return fail(MGMLReason.optIn.rawValue, status: 2) }
    let input = SceneValidator.readMLKit(path: files[0])
    switch input {
    case .unreadable(let reason):
        return fail(reason, status: 3)
    case .checked(.failure(let issue)):
        print(MGMLKit.report(.failure(issue)), terminator: "")
        return 1
    case .checked(.success(let document)):
        do {
            let receipt = try document.export(to: URL(fileURLWithPath: files[1]), size: size, format: format)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            print(String(decoding: try encoder.encode(receipt), as: UTF8.self))
            return 0
        } catch let reason as MGMLReason {
            return fail(reason.rawValue, status: 3)
        } catch {
            return fail("Export failed.", status: 3)
        }
    }
}

func fail(_ message: String, status: Int32) -> Int32 {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return status
}

exit(run(Array(CommandLine.arguments.dropFirst())))
