// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

/// Retypes a word that went in on the wrong keyboard layout.
///
/// The pairing comes from what each physical key produces on each of the
/// layouts the user actually enabled, so any pair works, not a list of the
/// ones somebody wrote a table for. Applying it twice returns the original.
final class LayoutSwitcherService: ObservableObject {
    static let shared = LayoutSwitcherService()

    @Published private(set) var isRunning = false

    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var buffer = ""
    /// The word the last boundary finished. Noticing the wrong layout usually
    /// happens a beat after the space, so the shortcut can still reach it.
    private var lastFinishedWord = ""
    private var config = LayoutSwitcherConfig()
    private var tableCache: [String: [UInt16: String]] = [:]
    private let hotkey = QuickToolHotkey(id: 59)

    /// Keycodes 0 through 50 are the block a word is typed on. Everything
    /// above is a modifier, a function key or the keypad, which no layout
    /// pairing has an opinion about.
    private static let typingKeyCodes: [UInt16] = Array(0...50)

    private init() {
        hotkey.onPress = { [weak self] in self?.correctWordAtCaret() }
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourcesChanged),
            name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
    }

    @objc private func inputSourcesChanged() {
        eventLock.withLock { tableCache.removeAll() }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let nextConfig = LayoutSwitcherConfig(
            enabled: AppFeature.layoutSwitcher.isAvailable
                && defaults.bool(forKey: DefaultsKey.layoutSwitcherEnabled),
            minimumWordLength: Defaults.sanitizedLayoutSwitcherWordLength(
                defaults.integer(forKey: DefaultsKey.layoutSwitcherMinimumWordLength)
            ),
            automatic: defaults.bool(forKey: DefaultsKey.layoutSwitcherAutomatic)
        )
        eventLock.withLock {
            config = nextConfig
            buffer = ""
            lastFinishedWord = ""
        }
        hotkey.sync(enabled: nextConfig.enabled,
                    shortcut: GlobalShortcutRole.layoutSwitcher.savedShortcut)

        if SessionActivitySupport.tapShouldRun(featureWanted: nextConfig.enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    // MARK: - Correcting

    /// The shortcut path. Retypes the word the caret sits behind, or the
    /// selection when there is one, without asking whether it looked wrong:
    /// pressing the shortcut is the answer to that question.
    @discardableResult
    func correctWordAtCaret() -> Bool {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { self.correctWordAtCaret() }
        }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return false }

        let selection = CommandBarSelectionReader.readSelectedText()
        let target = eventLock.withLock { () -> (word: String, deleteCount: Int, suffix: String)? in
            if !selection.isEmpty {
                // A selection is already highlighted; one Delete clears it.
                return (selection, 1, "")
            }
            let typing = LayoutSwitcherSupport.trailingWord(in: buffer)
            if !typing.isEmpty { return (typing, typing.count, "") }
            guard !lastFinishedWord.isEmpty else { return nil }
            // The boundary is past the word, so it goes and comes back with it.
            return (lastFinishedWord, lastFinishedWord.count + 1, " ")
        }
        guard let target, let corrected = retyped(target.word) else { return false }

        let replaced = TextSnippetService.postExpansion(
            deleteCount: target.deleteCount,
            text: corrected + target.suffix,
            trailingKeyCode: nil,
            trailingFlags: []
        )
        if replaced {
            eventLock.withLock {
                if buffer.hasSuffix(target.word) {
                    buffer.removeLast(target.word.count)
                    buffer.append(corrected)
                } else if lastFinishedWord == target.word {
                    // Pressing the shortcut again has to undo, not re-apply.
                    lastFinishedWord = corrected
                }
            }
        }
        return replaced
    }

    /// The other layout's spelling of `word`, or nil when no enabled layout
    /// maps every character of it.
    func retyped(_ word: String) -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let currentID = KeyboardLayoutGlyph.property(current, kTISPropertyInputSourceID),
              let currentGlyphs = glyphs(for: current, id: currentID)
        else { return nil }

        for candidate in Self.enabledLayouts() {
            guard let candidateID = KeyboardLayoutGlyph.property(candidate, kTISPropertyInputSourceID),
                  candidateID != currentID,
                  let candidateGlyphs = glyphs(for: candidate, id: candidateID)
            else { continue }
            // Reverse: the text carries the candidate layout's glyphs and the
            // user meant the one now selected. That is the common case, since
            // noticing the mistake is what makes them switch layouts first.
            let table = LayoutSwitcherSupport.table(from: candidateGlyphs, to: currentGlyphs)
            guard table.isUsable else { continue }
            if let corrected = table.mapForward(word) { return corrected }
            if let corrected = table.mapReverse(word) { return corrected }
        }
        return nil
    }

    private func glyphs(for source: TISInputSource, id: String) -> [UInt16: String]? {
        if let cached = eventLock.withLock({ tableCache[id] }) { return cached }
        guard let data = KeyboardLayoutGlyph.layoutData(for: source) else { return nil }
        var glyphs: [UInt16: String] = [:]
        for keyCode in Self.typingKeyCodes {
            guard let glyph = KeyboardLayoutGlyph.character(in: data, keyCode: keyCode),
                  LayoutSwitcherSupport.singleCharacter(glyph) != nil
            else { continue }
            glyphs[keyCode] = glyph
        }
        guard !glyphs.isEmpty else { return nil }
        eventLock.withLock { tableCache[id] = glyphs }
        return glyphs
    }

    private static func enabledLayouts() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String]
        guard let sources = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return sources
    }

    // MARK: - Lifecycle

    private func start() {
        eventLock.withLock { buffer = ""; lastFinishedWord = "" }

        let startState = lifecycleLock.withLock { () -> (thread: Thread?, publishRunning: Bool, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, false, lifecycleGeneration)
                }
                return (nil, true, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Layout Switcher"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, false, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if startState.publishRunning {
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        eventLock.withLock { buffer = ""; lastFinishedWord = "" }

        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        publishRunning(false, generation: snapshot.generation)
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock { shouldStopTapThread }
            guard !shouldStopBeforeCreatingTap else {
                if clearEventTapThread() {
                    start()
                } else {
                    publishRunning(false, generation: generation)
                }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<LayoutSwitcherService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                publishRunning(false, generation: generation)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            eventLock.withLock { buffer = ""; lastFinishedWord = "" }

            let shouldStop = lifecycleLock.withLock { shouldStopTapThread }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            eventLock.withLock { buffer = ""; lastFinishedWord = "" }
            if clearEventTapThread() {
                start()
            } else {
                publishRunning(false, generation: generation)
            }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func publishRunning(_ running: Bool, generation: UInt) {
        let update = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock { generation == self.lifecycleGeneration }
            guard isCurrent else { return }
            self.isRunning = running
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }

        // A click moves the caret somewhere the buffer knows nothing about.
        if type == .leftMouseDown || type == .rightMouseDown {
            if !AssistiveKeyboard.ownsPoint(event.location) { resetBuffer() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.eventSourceUserData) != TextSnippetService.syntheticMarker else {
            return Unmanaged.passUnretained(event)
        }
        // Secure input means a password field. Nothing typed there is kept,
        // read, or offered for correction.
        guard !IsSecureEventInputEnabled() else {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            eventLock.withLock { if !buffer.isEmpty { buffer.removeLast() } }
            return Unmanaged.passUnretained(event)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Tab:
            resetBuffer()
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4,
                                       actualStringLength: &length,
                                       unicodeString: &characters)
        guard length > 0 else { return Unmanaged.passUnretained(event) }
        let typed = String(utf16CodeUnits: characters, count: length)

        let finished = eventLock.withLock { () -> String? in
            guard config.enabled else { return nil }
            // The buffer only ever holds the word being typed. Anything the
            // user could have meant as a boundary ends it.
            if typed.allSatisfy({ $0.isWhitespace }) {
                let word = buffer
                buffer = ""
                lastFinishedWord = word
                // Only a space is put back after a correction. Return committed
                // the line somewhere, and retyping it would send it twice.
                guard config.automatic, typed == " " else { return nil }
                return word
            }
            buffer.append(typed)
            // Bounded so a session of typing cannot grow it without limit.
            if buffer.count > 128 { buffer.removeFirst(buffer.count - 128) }
            return nil
        }

        if let finished, !finished.isEmpty {
            let minimum = eventLock.withLock { config.minimumWordLength }
            if LayoutSwitcherSupport.isCorrectable(finished, minimumLength: minimum) {
                DispatchQueue.main.async { [weak self] in
                    self?.correctFinishedWord(finished)
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    /// Automatic mode. The word is already committed and the caret has moved
    /// past the space, so the space goes and comes back with it.
    private func correctFinishedWord(_ word: String) {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return }
        guard let corrected = retyped(word), corrected != word else { return }
        TextSnippetService.postExpansion(deleteCount: word.count + 1,
                                         text: corrected + " ",
                                         trailingKeyCode: nil,
                                         trailingFlags: [])
    }

    private func resetBuffer() {
        eventLock.withLock {
            buffer = ""
            // The caret moved somewhere unknown, so the finished word is no
            // longer sitting behind it and must not be rewritten.
            lastFinishedWord = ""
        }
    }
}
