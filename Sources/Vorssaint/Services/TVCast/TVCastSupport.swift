// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A TV that ytcast knows, as its cache file lists it.
///
/// ytcast keeps no per-device commands beyond pairing and casting, so the
/// cache file is the list: Vorssaint reads it, and renames or forgets a TV by
/// editing that one entry. The file layout is ytcast v1.4.1's; a new ytcast
/// version has to be checked against it before the pin in build.sh moves.
struct TVCastDevice: Equatable, Identifiable {
    /// What ytcast selects the TV by: the pairing's device id for a TV paired
    /// with a code, the DIAL service name for one it discovered.
    let id: String
    /// The name the list shows: the one the person gave it, else the one
    /// YouTube or the TV reported (numbered when another TV has it), else a
    /// default such as "Apple TV"; the id when the cache holds no name.
    let name: String
    /// True for a TV paired with a code: only those can be renamed, and only
    /// those reach the TV through YouTube alone, without the local network.
    let pairedWithCode: Bool
    /// The TV ytcast sent to last, offered first.
    let lastUsed: Bool
}

/// Why a pairing or a send stopped, as a case rather than a sentence. The
/// wording lives in `TVCastStrings`, keyed off these cases, so every language
/// gets it.
enum TVCastFailure: Error, Equatable {
    case helperMissing
    case invalidCode
    /// YouTube refused the TV code: mistyped, or no longer shown on the TV.
    case pairingRejected
    /// ytcast no longer lists the TV.
    case deviceNotFound
    /// The pairing could not be renewed: YouTube is closed on the TV, or the
    /// link expired and the TV needs a new code.
    case unreachable
    /// The TV answered but did not start the video.
    case playbackRejected
    case offline
    case timedOut
    /// The list of TVs could not be read or written.
    case cacheUnreadable
    /// Anything else ytcast reported, in its own words.
    case failed(String)
    /// ytcast ended with this status and printed nothing to explain it.
    case exited(Int32)
}

enum TVCastSupport {
    /// ytcast's cache file, relative to the `XDG_CACHE_HOME` it is given.
    static let cacheSubpath = "ytcast/ytcast.json"

    private static let watchURL = "https://www.youtube.com/watch?v="
    private static let youtubeHosts: Set<String> = [
        "youtube.com", "music.youtube.com", "youtube-nocookie.com", "youtu.be",
    ]
    /// Path segments that carry the video id in the next segment.
    private static let idPathMarkers: Set<String> = ["shorts", "live", "embed", "v"]
    private static let errorPrefix = "ytcast: "
    /// A product name, so it reads the same in every language.
    private static let defaultTVName = "Apple TV"
    /// Go's HTTP client giving up on one request after ytcast's 30 s: YouTube
    /// answering too slowly rather than this Mac being offline.
    private static let timeoutNeedles = ["client.timeout exceeded", "context deadline exceeded"]
    private static let networkNeedles = [
        "no such host", "network is unreachable", "i/o timeout", "connection refused",
        "tls handshake timeout", "connection reset", "no route to host", "operation timed out",
        "network is down", "server misbehaving", "tls:", "x509:",
    ]
    /// The line ytcast v1.4.1 prints for the TV a pairing saved, `%.8s %-15s
    /// %-30q %s`: at most eight characters of the id, the host padded to 15,
    /// which is "unknown" for a code-paired TV, a space, then the quoted name.
    private static let printedPairingPattern = "^[^\\s]{1,8} unknown {9}\""
    private static let printedIDLength = 8

    /// The canonical watch URL to hand ytcast for a YouTube link or a bare
    /// 11-character video id, keeping a `t` start time; nil for anything that
    /// is not one video on YouTube.
    static func videoArgument(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isVideoID(trimmed) { return watchURL + trimmed }
        guard let components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              youtubeHosts.contains(strippingSubdomain(host)),
              let id = videoID(in: components, host: strippingSubdomain(host)),
              isVideoID(id) else { return nil }
        let start = components.queryItems?.first { $0.name == "t" }?.value
        if let start, isStartTime(start) { return watchURL + id + "&t=" + start }
        return watchURL + id
    }

    /// The digits of a TV code as the TV shows it, spaces and dashes removed;
    /// nil when it is not a plausible code.
    static func pairingCode(from input: String) -> String? {
        let digits = input.filter { !$0.isWhitespace && $0 != "-" }
        guard (8...16).contains(digits.count),
              digits.unicodeScalars.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) else { return nil }
        return digits
    }

    static func pairArguments(code: String) -> [String] {
        ["-pair=" + code]
    }

    /// The `=` form and `--` keep a device id or video id that starts with a
    /// dash from being read as a flag by Go's flag package.
    static func castArguments(deviceID: String, video: String) -> [String] {
        ["-d=" + deviceID, "--", video]
    }

    /// The name a TV gets when neither the person nor YouTube named it:
    /// "Apple TV", else the first free "Apple TV 2", "Apple TV 3"... so the
    /// list never shows two TVs alike. Case and surrounding spaces are ignored
    /// when comparing.
    static func defaultName(avoiding takenNames: [String]) -> String {
        uniqueName(defaultTVName, avoiding: takenNames)
    }

    /// The name a pairing saves the TV under: the one typed, else the one
    /// YouTube reported for the screen, numbered like `defaultName` when
    /// another TV has it, else `defaultName`. ytcast stores the id as the
    /// name when YouTube reports none, so a name equal to the id is none.
    static func pairedName(typed: String, for id: String, inCache data: Data?) -> String {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let listed = devices(fromCache: data)
        let others = listed.filter { $0.id != id }.map(\.name)
        let reported = listed.first { $0.id == id && $0.pairedWithCode }?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reported.isEmpty, reported != id else { return defaultName(avoiding: others) }
        return uniqueName(reported, avoiding: others)
    }

    /// The TV the send picker shows: the person's pick while it is still
    /// listed, else the last used one, else the first.
    static func selectedDeviceID(_ picked: String?, in devices: [TVCastDevice]) -> String? {
        if let picked, devices.contains(where: { $0.id == picked }) { return picked }
        return (devices.first(where: \.lastUsed) ?? devices.first)?.id
    }

    /// The TVs in ytcast's cache, the last used first, then by name.
    static func devices(fromCache data: Data?) -> [TVCastDevice] {
        guard let entries = cacheEntries(data) else { return [] }
        return entries.compactMap(device(from:)).sorted { a, b in
            if a.lastUsed != b.lastUsed { return a.lastUsed }
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame { return order == .orderedAscending }
            return a.id < b.id
        }
    }

    /// The TV a pairing added or replaced, found by comparing the cache
    /// before and after it. LastUsed is ignored: every send rewrites it, and
    /// it says nothing about a pairing.
    static func changedDeviceID(before: Data?, after: Data?) -> String? {
        let previous = keyedByID(cacheEntries(before) ?? [])
        let current = keyedByID(cacheEntries(after) ?? [])
        let changed = current.filter { id, entry in
            guard let old = previous[id] else { return true }
            return !NSDictionary(dictionary: withoutLastUsed(old)).isEqual(to: withoutLastUsed(entry))
        }
        return changed.count == 1 ? changed.keys.first : nil
    }

    /// The cache with one code-paired TV renamed, every other field kept.
    static func renaming(_ id: String, to name: String, inCache data: Data) -> Data? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var entries = cacheEntries(data),
              let index = entries.firstIndex(where: { isCodePaired($0) && entryID($0) == id }),
              var remote = entries[index]["Remote"] as? [String: Any] else { return nil }
        remote["ScreenName"] = name
        entries[index]["Remote"] = remote
        return serialized(entries)
    }

    /// The cache without one TV, every other entry kept as it was.
    static func removing(_ id: String, fromCache data: Data) -> Data? {
        guard let entries = cacheEntries(data) else { return nil }
        let kept = entries.filter { entryID($0) != id }
        return kept.count == entries.count ? nil : serialized(kept)
    }

    /// The cache without the other code-paired entries on the same screen as
    /// `id`. When YouTube reports no device id, ytcast gives a pairing a fresh
    /// time-based one, so pairing a TV again would leave its old entry behind:
    /// dead, and still the last used. Nil when `id` is not a code-paired entry.
    static func droppingDuplicates(of id: String, inCache data: Data) -> Data? {
        guard let entries = cacheEntries(data),
              let paired = entries.first(where: { isCodePaired($0) && entryID($0) == id }) else { return nil }
        guard let screen = screenID(paired) else { return data }
        let kept = entries.filter { !isCodePaired($0) || entryID($0) == id || screenID($0) != screen }
        return kept.count == entries.count ? data : serialized(kept)
    }

    /// The cache a pairing leaves once its stale duplicates are gone and the
    /// TV carries its name, and that name. The duplicates go first, so the
    /// old entry's name does not push the TV's own to " 2". Nil when the TV
    /// is not a code-paired entry in the cache.
    static func settledPairing(of id: String, typedName: String,
                               inCache data: Data) -> (cache: Data, name: String)? {
        guard let deduplicated = droppingDuplicates(of: id, inCache: data) else { return nil }
        let name = pairedName(typed: typedName, for: id, inCache: deduplicated)
        guard let renamed = renaming(id, to: name, inCache: deduplicated) else { return nil }
        return (renamed, name)
    }

    /// The start of the id ytcast printed for the TV a pairing saved. It
    /// names the TV when the file cannot: a pairing that changed nothing in
    /// it, or a file cut off mid-write.
    static func printedPairingID(in output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .last { $0.range(of: printedPairingPattern, options: .regularExpression) != nil }
            .map { String($0.prefix { !$0.isWhitespace }) }
    }

    /// The one code-paired TV in the cache whose id ytcast would print the
    /// way the pairing printed it; nil when none or several match.
    static func pairedDeviceID(printedIn output: String, cache data: Data?) -> String? {
        guard let printed = printedPairingID(in: output) else { return nil }
        let matches = codePairedEntries(printedAs: printed, in: cacheEntries(data) ?? []).compactMap(entryID)
        return matches.count == 1 ? matches.first : nil
    }

    /// What to write back after a ytcast run, or nil to leave the file as
    /// ytcast left it. `pairingOutput` is a pairing's output, nil for a send.
    ///
    /// ytcast rewrites the file in place as it exits, with no temporary file,
    /// and when it could not read the file it started from it writes back
    /// only what that run added, or `null`. A file that no longer reads as a
    /// list, where the snapshot did, gets the snapshot back, with the printed
    /// pairing if it survived whole; a pairing that lost TVs gets them back.
    static func repairedCache(snapshot: Data?, after: Data?, pairingOutput: String?) -> Data? {
        guard let saved = cacheEntries(snapshot) else { return nil }
        guard let current = cacheEntries(after) else {
            return serialized(restoring(saved, pairingFrom: after, output: pairingOutput))
        }
        guard pairingOutput != nil else { return nil }
        let present = Set(current.compactMap(entryID))
        let missing = saved.filter { entry in entryID(entry).map { !present.contains($0) } ?? false }
        return missing.isEmpty ? nil : serialized(current + missing)
    }

    /// Nil when the run succeeded.
    static func failure(fromOutput output: String, status: Int32, timedOut: Bool) -> TVCastFailure? {
        if timedOut { return .timedOut }
        if status == 0 { return nil }
        guard let message = errorMessage(in: output) else { return .exited(status) }
        let lowered = message.lowercased()
        if message.contains("invalid pairing code") { return .invalidCode }
        if message.contains("no device matches") || message.contains("no device found") {
            return .deviceNotFound
        }
        // Ahead of the prefixes: every step can fail on the network, and
        // "ConnectWithCode" alone would blame the code for a dropped line.
        if timeoutNeedles.contains(where: lowered.contains) { return .timedOut }
        if isNetworkFailure(lowered) { return .offline }
        if message.hasPrefix("ConnectWithCode") { return .pairingRejected }
        if message.hasPrefix("Connect:") || message.contains("RefreshToken") { return .unreachable }
        if message.hasPrefix("Play:") || message.hasPrefix("Add:") { return .playbackRejected }
        return .failed(message)
    }

    private static func comparableName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `base`, else the first free "base 2", "base 3"... so the list never
    /// shows two TVs alike.
    private static func uniqueName(_ base: String, avoiding takenNames: [String]) -> String {
        let taken = Set(takenNames.map(comparableName))
        guard taken.contains(comparableName(base)) else { return base }
        var number = 2
        while taken.contains(comparableName("\(base) \(number)")) { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: Video parsing

    private static func isVideoID(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }

    /// Digits only, or an `h`/`m`/`s` duration; ytcast hands it to YouTube as is.
    private static func isStartTime(_ text: String) -> Bool {
        !text.isEmpty
            && text.range(of: "^([0-9]+|([0-9]+h)?([0-9]+m)?([0-9]+s)?)$", options: .regularExpression) != nil
    }

    private static func strippingSubdomain(_ host: String) -> String {
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }

    private static func videoID(in components: URLComponents, host: String) -> String? {
        if let id = components.queryItems?.first(where: { $0.name == "v" })?.value { return id }
        let path = components.path.split(separator: "/").map(String.init)
        if host == "youtu.be" { return path.first }
        guard let marker = path.firstIndex(where: idPathMarkers.contains), marker + 1 < path.count else {
            return nil
        }
        return path[marker + 1]
    }

    // MARK: Cache entries

    private static func cacheEntries(_ data: Data?) -> [[String: Any]]? {
        guard let data, !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    /// Slashes stay unescaped so the file keeps reading like ytcast's own.
    private static func serialized(_ entries: [[String: Any]]) -> Data? {
        try? JSONSerialization.data(withJSONObject: entries, options: [.withoutEscapingSlashes])
    }

    /// ytcast's `wasManuallyPaired`: no discovered Device, so Remote holds the TV.
    private static func isCodePaired(_ entry: [String: Any]) -> Bool {
        !(entry["Device"] is [String: Any]) && entry["Remote"] is [String: Any]
    }

    private static func entryID(_ entry: [String: Any]) -> String? {
        let id: String?
        if let device = entry["Device"] as? [String: Any] {
            id = device["UniqueServiceName"] as? String
        } else {
            id = (entry["Remote"] as? [String: Any])?["DeviceId"] as? String
        }
        guard let id, !id.isEmpty else { return nil }
        return id
    }

    private static func device(from entry: [String: Any]) -> TVCastDevice? {
        guard let id = entryID(entry) else { return nil }
        let pairedWithCode = isCodePaired(entry)
        let source = (pairedWithCode ? entry["Remote"] : entry["Device"]) as? [String: Any]
        let name = (source?[pairedWithCode ? "ScreenName" : "FriendlyName"] as? String) ?? ""
        return TVCastDevice(id: id, name: name.isEmpty ? id : name, pairedWithCode: pairedWithCode,
                            lastUsed: entry["LastUsed"] as? Bool ?? false)
    }

    private static func keyedByID(_ entries: [[String: Any]]) -> [String: [String: Any]] {
        entries.reduce(into: [:]) { result, entry in
            if let id = entryID(entry) { result[id] = entry }
        }
    }

    private static func withoutLastUsed(_ entry: [String: Any]) -> [String: Any] {
        entry.filter { $0.key != "LastUsed" }
    }

    private static func screenID(_ entry: [String: Any]) -> String? {
        guard let id = (entry["Remote"] as? [String: Any])?["ScreenId"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// The code-paired entries ytcast would print with this id: its
    /// `%.8s` of the id after dropping a `uuid:` prefix.
    private static func codePairedEntries(printedAs printed: String,
                                          in entries: [[String: Any]]) -> [[String: Any]] {
        entries.filter { entry in
            guard isCodePaired(entry), let id = entryID(entry) else { return false }
            let printable = id.hasPrefix("uuid:") ? id.dropFirst("uuid:".count) : Substring(id)
            return String(printable.prefix(printedIDLength)) == printed
        }
    }

    /// The snapshot, plus the entry a pairing printed when it survived whole
    /// in the file ytcast left unreadable.
    private static func restoring(_ saved: [[String: Any]], pairingFrom after: Data?,
                                  output: String?) -> [[String: Any]] {
        guard let output, let after, let printed = printedPairingID(in: output) else { return saved }
        let survivors = codePairedEntries(printedAs: printed, in: leadingEntries(of: after))
        guard survivors.count == 1, let paired = survivors.first, let id = entryID(paired) else { return saved }
        return saved.filter { entryID($0) != id } + [paired]
    }

    /// The whole entries at the start of a list cut off mid-write. Brackets
    /// inside strings are skipped, so a name holding one cannot end an entry.
    private static func leadingEntries(of data: Data) -> [[String: Any]] {
        let bytes = [UInt8](data)
        guard bytes.first == UInt8(ascii: "[") else { return [] }
        var depth = 0
        var inString = false
        var escaped = false
        var lastEntryEnd: Int?
        for (index, byte) in bytes.enumerated() {
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
            case UInt8(ascii: "["), UInt8(ascii: "{"): depth += 1
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
                if depth == 1 { lastEntryEnd = index }
            default: break
            }
        }
        guard let lastEntryEnd else { return [] }
        return cacheEntries(Data(bytes[...lastEntryEnd]) + Data("]".utf8)) ?? []
    }

    // MARK: Failure parsing

    /// Go reports a connection closed mid-request as a bare `EOF` at the end.
    private static func isNetworkFailure(_ lowered: String) -> Bool {
        networkNeedles.contains(where: lowered.contains) || lowered == "eof" || lowered.hasSuffix(": eof")
    }

    /// ytcast's own last `ytcast: ` line, else the last line of anything.
    private static func errorMessage(in output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let line = lines.last(where: { $0.hasPrefix(errorPrefix) }) {
            return String(line.dropFirst(errorPrefix.count))
        }
        return lines.last
    }
}
