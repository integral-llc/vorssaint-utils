// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Sends audio to a whisper.cpp server the user runs and reads the transcript
/// back.
///
/// There is no vendor here and no key: the endpoint is whatever host the user
/// typed, which is why the scheme defaults to https rather than to plaintext.
enum RemoteTranscriber {
    private static let timeout: TimeInterval = 3600

    static func transcribe(audioPath: String,
                           endpoint: URL,
                           onProgress: @escaping (Double) -> Void)
        -> Result<String, TranscriptionFailure> {
        guard let body = MultipartBody(filePath: audioPath, fieldName: "file") else {
            return .failure(.notMedia)
        }
        defer { body.discard() }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout

        let observer = UploadObserver(onProgress: onProgress)
        let session = URLSession(configuration: configuration,
                                 delegate: observer,
                                 delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let outcome = Synchronous<Result<String, TranscriptionFailure>>()
        let task = session.uploadTask(with: request, fromFile: body.fileURL) { data, response, error in
            if error != nil {
                outcome.resolve(.failure(.remoteUnreachable))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                outcome.resolve(.failure(.remoteRejected(status: status)))
                return
            }
            guard let data, let text = transcriptText(from: data) else {
                outcome.resolve(.failure(.remoteRejected(status: status)))
                return
            }
            outcome.resolve(.success(text))
        }
        task.resume()
        return outcome.wait(timeout: timeout) ?? .failure(.remoteUnreachable)
    }

    /// whisper.cpp answers with `{"text": "..."}`, and some builds answer with
    /// segments instead. Both are read rather than assuming one shape.
    private static func transcriptText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return String(data: data, encoding: .utf8) }
        if let text = object["text"] as? String { return text }
        if let segments = object["segments"] as? [[String: Any]] {
            return segments.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return nil
    }
}

/// Blocks the pipeline's own queue until the upload answers. The pipeline
/// already runs off the main thread and has nothing else to do meanwhile.
private final class Synchronous<Value>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value: Value?

    func resolve(_ newValue: Value) {
        lock.withLock { value = newValue }
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> Value? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return lock.withLock { value }
    }
}

private final class UploadObserver: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 1))
    }
}

/// A multipart body written to a file rather than built in memory, because the
/// audio can be hours long.
private final class MultipartBody {
    let boundary = "vorssaint.\(UUID().uuidString)"
    let fileURL: URL

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    init?(filePath: String, fieldName: String) {
        let name = URL(fileURLWithPath: filePath).lastPathComponent
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-upload-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: staged.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: staged),
              let source = try? FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        else { return nil }
        fileURL = staged
        defer {
            try? handle.close()
            try? source.close()
        }

        let header = """
        --\(boundary)\r
        Content-Disposition: form-data; name="\(fieldName)"; filename="\(name)"\r
        Content-Type: application/octet-stream\r
        \r

        """
        guard (try? handle.write(contentsOf: Data(header.utf8))) != nil else { return nil }
        while let chunk = try? source.read(upToCount: 1 << 20), !chunk.isEmpty {
            guard (try? handle.write(contentsOf: chunk)) != nil else { return nil }
        }
        let footer = "\r\n--\(boundary)--\r\n"
        guard (try? handle.write(contentsOf: Data(footer.utf8))) != nil else { return nil }
    }

    func discard() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
