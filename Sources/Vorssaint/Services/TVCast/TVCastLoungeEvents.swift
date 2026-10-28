// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// YouTube sends a session's events as frames: a length on a line of its
/// own, then a JSON array. The length counts UTF-16 units, not bytes, so a
/// frame is found by its brackets instead, which also holds when a read ends
/// halfway through one. The scan resumes where the last read stopped.
struct TVCastLoungeFrames {
    /// Far past any frame YouTube sends; a stream that runs this long without
    /// closing one is not the Lounge API's.
    static let maxPending = 256 * 1024

    private var buffer: [UInt8] = []
    private var cursor = 0
    private var start: Int?
    private var depth = 0
    private var inString = false
    private var escaped = false
    private(set) var overflowed = false

    mutating func append(_ data: Data) -> [Data] {
        guard !overflowed else { return [] }
        buffer.append(contentsOf: data)
        var frames: [Data] = []
        while cursor < buffer.count {
            let byte = buffer[cursor]
            cursor += 1
            guard let first = start else {
                if byte == UInt8(ascii: "[") {
                    start = cursor - 1
                    depth = 1
                }
                continue
            }
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "["): depth += 1
            case UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 {
                    frames.append(Data(buffer[first..<cursor]))
                    buffer.removeFirst(cursor)
                    cursor = 0
                    start = nil
                }
            default: break
            }
        }
        // Outside a frame only a length is left, which nothing reads.
        if start == nil {
            buffer.removeAll(keepingCapacity: true)
            cursor = 0
        } else if buffer.count > Self.maxPending {
            overflowed = true
            buffer = []
        }
        return frames
    }
}

/// What the TV reports about the video it shows.
struct TVCastPlayerReport: Equatable {
    /// Nil in a state change, which names no video.
    let videoID: String?
    let position: TimeInterval
    let duration: TimeInterval
    /// YouTube's player state: 1 playing, 2 paused, 3 buffering, 0 ended,
    /// -1 unstarted, 5 cued, 1081 an ad.
    let state: Int
}

/// The events a remote acts on; everything else YouTube sends is `other`.
enum TVCastLoungeEvent: Equatable {
    case sessionID(String)
    case gsessionID(String)
    /// Nil when the TV plays nothing.
    case nowPlaying(TVCastPlayerReport?)
    case stateChanged(TVCastPlayerReport)
    /// Whether the session lists the TV itself; nil when it lists no one.
    case loungeStatus(screenPresent: Bool?)
    case screenDisconnected
    case other
}

struct TVCastLoungeMessage: Equatable {
    let id: Int
    let event: TVCastLoungeEvent
}

extension TVCastLounge {
    /// Each frame holds `[[id, [name, argument...]], ...]`. An entry of any
    /// other shape is skipped, not the frame around it.
    static func messages(in frame: Data) -> [TVCastLoungeMessage] {
        guard let entries = (try? JSONSerialization.jsonObject(with: frame)) as? [Any] else { return [] }
        return entries.compactMap { entry in
            guard let entry = entry as? [Any], entry.count >= 2,
                  let id = (entry[0] as? NSNumber)?.intValue,
                  let payload = entry[1] as? [Any], let name = payload.first as? String else { return nil }
            return TVCastLoungeMessage(id: id, event: event(name, arguments: Array(payload.dropFirst())))
        }
    }

    /// Every message in a whole reply, such as the bind's.
    static func messages(inReply body: Data) -> [TVCastLoungeMessage] {
        var frames = TVCastLoungeFrames()
        return frames.append(body).flatMap(messages(in:))
    }

    private static func event(_ name: String, arguments: [Any]) -> TVCastLoungeEvent {
        let fields = arguments.first as? [String: Any]
        switch name {
        case "c":
            return (arguments.first as? String).map(TVCastLoungeEvent.sessionID) ?? .other
        case "S":
            return (arguments.first as? String).map(TVCastLoungeEvent.gsessionID) ?? .other
        case "nowPlaying":
            guard let fields, fields["videoId"] != nil else { return .nowPlaying(nil) }
            return .nowPlaying(report(fields))
        case "onStateChange":
            return fields.map { .stateChanged(report($0)) } ?? .other
        case "loungeStatus":
            return .loungeStatus(screenPresent: screenPresent(in: fields))
        case "loungeScreenDisconnected":
            return .screenDisconnected
        default:
            return .other
        }
    }

    /// YouTube sends every number as a string.
    private static func report(_ fields: [String: Any]) -> TVCastPlayerReport {
        func number(_ key: String) -> Double {
            if let text = fields[key] as? String, let value = Double(text), value.isFinite { return value }
            return (fields[key] as? NSNumber)?.doubleValue ?? 0
        }
        let state = (fields["state"] as? String).flatMap { Int($0) } ?? (fields["state"] as? NSNumber)?.intValue ?? -1
        return TVCastPlayerReport(videoID: fields["videoId"] as? String, position: max(0, number("currentTime")),
                                  duration: max(0, number("duration")), state: state)
    }

    /// `devices` is itself JSON, a string holding the list.
    private static func screenPresent(in fields: [String: Any]?) -> Bool? {
        guard let listed = fields?["devices"] as? String,
              let devices = (try? JSONSerialization.jsonObject(with: Data(listed.utf8))) as? [[String: Any]] else {
            return nil
        }
        return devices.contains { $0["type"] as? String == "LOUNGE_SCREEN" }
    }
}
