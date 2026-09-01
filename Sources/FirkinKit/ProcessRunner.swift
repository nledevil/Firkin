import Foundation

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String
}

public enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(path: String, underlying: Error)
    case nonZeroExit(command: String, status: Int32)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(path, underlying):
            return "Could not launch \(path): \(underlying.localizedDescription)"
        case let .nonZeroExit(command, status):
            return "`\(command)` exited with status \(status)."
        }
    }
}

public enum ProcessRunner {
    /// Runs a command to completion, collecting stdout and stderr separately.
    /// Exit status is reported in the result, not thrown — callers decide.
    public static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = makeProcess(executable, arguments: arguments, environment: environment)
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(
                        path: executable.path, underlying: error))
                    return
                }

                // Drain stderr on its own thread so neither pipe can fill up
                // and deadlock the child.
                var stderrData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: ProcessOutput(
                    status: process.terminationStatus,
                    standardOutput: String(decoding: stdoutData, as: UTF8.self),
                    standardError: String(decoding: stderrData, as: UTF8.self)
                ))
            }
        }
    }

    /// Streams combined stdout/stderr chunks while a command runs.
    /// Finishes when the process exits; throws on a non-zero exit status.
    /// Cancelling the consuming task terminates the process.
    public static func stream(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = makeProcess(executable, arguments: arguments, environment: environment)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else { return }
                continuation.yield(String(decoding: data, as: UTF8.self))
            }

            let commandName = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            process.terminationHandler = { finished in
                handle.readabilityHandler = nil
                let remainder = handle.readDataToEndOfFile()
                if !remainder.isEmpty {
                    continuation.yield(String(decoding: remainder, as: UTF8.self))
                }
                if finished.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ProcessRunnerError.nonZeroExit(
                        command: commandName, status: finished.terminationStatus))
                }
            }

            continuation.onTermination = { termination in
                if case .cancelled = termination, process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                continuation.finish(throwing: ProcessRunnerError.launchFailed(
                    path: executable.path, underlying: error))
            }
        }
    }

    private static func makeProcess(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]
    ) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
        return process
    }
}
