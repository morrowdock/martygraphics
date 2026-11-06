// SPDX-License-Identifier: Apache-2.0
import Foundation
import Darwin
import SceneValidatorCore

func writeOutput(_ text: String, descriptor: Int32) -> Bool {
    let bytes = Array(text.utf8)
    return bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            if written > 0 { offset += written }
            else if written < 0 && errno == EINTR { continue }
            else { return false }
        }
        return true
    }
}

signal(SIGPIPE, SIG_IGN)
let report = SceneValidator.run(arguments: Array(CommandLine.arguments.dropFirst()))
guard writeOutput(report.stdout, descriptor: STDOUT_FILENO),
      writeOutput(report.stderr, descriptor: STDERR_FILENO) else {
    _ = writeOutput("marty-scene-validate: output write failed\n", descriptor: STDERR_FILENO)
    exit(4)
}
exit(report.status.rawValue)
