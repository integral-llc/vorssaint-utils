// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the scorer may ask about this one user's words.
protocol LayoutPersonalVocabulary {
    /// The user took a correction of this word back. It is never offered again.
    func isRefused(_ word: String) -> Bool
    func typedCount(of word: String) -> Int
}

/// Words this user types and corrections they took back, kept across launches.
///
/// No word list carries a team's project names or somebody's surname, and a
/// correction that keeps coming back after being undone is the feature arguing
/// with its user. Both are learned from what stood and what did not.
///
/// This is typed text on disk, so it is held to a few rules: only ordinary
/// words are counted (nothing with a digit or a symbol in it, which is what a
/// password or a token looks like), both lists are capped, the key is never
/// registered and so never travels in a settings backup, and settings has a
/// button that forgets all of it.
final class LayoutVocabulary: LayoutPersonalVocabulary {
    private struct Stored: Codable {
        /// Oldest first, so the order that decides eviction survives a restart.
        let refused: [String]
        let counts: [String: Int]
    }

    static let shared = LayoutVocabulary(capacity: 5000, persistEvery: 20, defaults: .standard)

    private let lock = NSLock()
    private let capacity: Int
    private let persistEvery: Int
    private let defaults: UserDefaults?

    private var refusedSeen: [String: UInt64] = [:]
    private var counts: [String: Int] = [:]
    private var countSeen: [String: UInt64] = [:]
    private var tick: UInt64 = 0
    private var unsavedWords = 0

    /// `defaults` nil keeps everything in memory, for tests.
    init(capacity: Int, persistEvery: Int, defaults: UserDefaults?) {
        self.capacity = max(1, capacity)
        self.persistEvery = max(1, persistEvery)
        self.defaults = defaults
        load()
    }

    /// Room above the cap before anything is evicted. Pruning a batch at a
    /// time keeps an insert cheap; pruning on every insert past the cap would
    /// sort the whole store per word typed.
    static func slack(forCapacity capacity: Int) -> Int { max(64, capacity / 8) }

    var storedWordCount: Int { lock.withLock { counts.count } }

    func isRefused(_ word: String) -> Bool {
        lock.withLock { refusedSeen[word.lowercased()] != nil }
    }

    func typedCount(of word: String) -> Int {
        lock.withLock { counts[word.lowercased()] ?? 0 }
    }

    /// A word that was typed and left alone. Written out in batches: this runs
    /// once per word typed, and a defaults write per word is a lot of disk for
    /// a count that only matters in aggregate.
    func recordTyped(_ word: String) {
        let key = word.lowercased()
        guard Self.isOrdinaryWord(key) else { return }
        let snapshot = lock.withLock { () -> Stored? in
            tick += 1
            counts[key, default: 0] += 1
            countSeen[key] = tick
            if counts.count > capacity + Self.slack(forCapacity: capacity) {
                let kept = Self.mostRecent(countSeen, limit: capacity)
                counts = counts.filter { kept.contains($0.key) }
                countSeen = countSeen.filter { kept.contains($0.key) }
            }
            unsavedWords += 1
            guard unsavedWords >= persistEvery else { return nil }
            unsavedWords = 0
            return stored()
        }
        if let snapshot { write(snapshot) }
    }

    /// Rare and deliberate, so it is written at once.
    func refuse(_ word: String) {
        let key = word.lowercased()
        guard !key.isEmpty else { return }
        let snapshot = lock.withLock { () -> Stored in
            tick += 1
            refusedSeen[key] = tick
            if refusedSeen.count > capacity + Self.slack(forCapacity: capacity) {
                let kept = Self.mostRecent(refusedSeen, limit: capacity)
                refusedSeen = refusedSeen.filter { kept.contains($0.key) }
            }
            unsavedWords = 0
            return stored()
        }
        write(snapshot)
    }

    func flush() {
        let snapshot = lock.withLock { () -> Stored? in
            guard unsavedWords > 0 else { return nil }
            unsavedWords = 0
            return stored()
        }
        if let snapshot { write(snapshot) }
    }

    func clear() {
        lock.withLock {
            refusedSeen.removeAll()
            counts.removeAll()
            countSeen.removeAll()
            unsavedWords = 0
        }
        defaults?.removeObject(forKey: DefaultsKey.layoutSwitcherVocabulary)
    }

    private static func isOrdinaryWord(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
    }

    private static func mostRecent(_ seen: [String: UInt64], limit: Int) -> Set<String> {
        Set(seen.sorted { $0.value > $1.value }.prefix(limit).map(\.key))
    }

    /// Caller holds `lock`.
    private func stored() -> Stored {
        Stored(refused: refusedSeen.sorted { $0.value < $1.value }.map(\.key), counts: counts)
    }

    private func write(_ snapshot: Stored) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: DefaultsKey.layoutSwitcherVocabulary)
    }

    private func load() {
        // A copy that does not decode is a copy from some other version. What
        // it held is lost either way, and the next write replaces it.
        guard let data = defaults?.data(forKey: DefaultsKey.layoutSwitcherVocabulary),
              let snapshot = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }
        lock.withLock {
            for word in snapshot.refused {
                tick += 1
                refusedSeen[word] = tick
            }
            for (word, count) in snapshot.counts where count > 0 {
                tick += 1
                counts[word] = count
                countSeen[word] = tick
            }
        }
    }
}
