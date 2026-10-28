// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// The TV's YouTube session. Kept open while the island's Cast page shows
/// that TV, so the page can say what plays, and shared with the playback
/// controls, so YouTube and the TV see one remote however often they are
/// pressed. Everything here runs on one queue: the stream's callbacks are
/// delivered on it, and the requests that wait for an answer block it.
final class TVCastLoungeChannel: NSObject, URLSessionDataDelegate {
    static let shared = TVCastLoungeChannel()

    /// On the main queue, with the screen the state belongs to.
    var onChange: ((String, TVCastLiveState) -> Void)?

    /// This Mac as one TV's remote: the session it joined and how far it
    /// read. A reference, confined to the queue.
    private final class Remote {
        let screen: TVCastLoungeScreen
        /// Nil while the saved token has lapsed and none was renewed yet.
        var token: String?
        var session: TVCastLoungeSession?
        var commandsSent = 0
        var lastEventID = 0

        init(screen: TVCastLoungeScreen) {
            self.screen = screen
            token = screen.isExpired(at: Date()) ? nil : screen.loungeToken
        }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "tvcast")
    /// YouTube's keep-alives come well within this; a stream quiet for longer
    /// is opened again.
    private static let streamIdleTimeout: TimeInterval = 90
    private static let streamLifetime: TimeInterval = 600
    /// A stream that ends this soon with nothing in it counts as a failure,
    /// so a server that closes at once is not asked again in a tight loop.
    private static let shortestStream: TimeInterval = 1
    private static let longestRetryDelay: TimeInterval = 30

    private let queue = DispatchQueue(label: "com.vorssaint.utils.tvcast.lounge", qos: .userInitiated)
    private let exchange = TVCastLoungeExchange()
    private let lock = NSLock()
    /// Cancelled when the feature is switched off, from any thread, so a
    /// request the queue waits on stops at once.
    private var currentLifetime = BoundedProcessCancellation()
    private var lifetime: BoundedProcessCancellation { lock.withLock { currentLifetime } }

    // Confined to the queue.
    private var remote: Remote?
    private var watching = false
    private var state = TVCastLiveState()
    private var stream: URLSessionDataTask?
    private var streamStatus = 0
    private var streamStarted = Date.distantPast
    private var streamDelivered = false
    private var frames = TVCastLoungeFrames()
    private var failures = 0
    private var retry: DispatchWorkItem?

    private lazy var streamSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.streamIdleTimeout
        configuration.timeoutIntervalForResource = Self.streamLifetime
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }()

    private override init() {
        super.init()
    }

    /// Follows the TV until `unwatch`. A session from an earlier look at the
    /// same TV is taken up again, so reopening the page joins nothing new.
    func watch(_ screen: TVCastLoungeScreen) {
        queue.async { [self] in
            lock.withLock { if currentLifetime.isCancelled { currentLifetime = BoundedProcessCancellation() } }
            cancelRetry()
            if remote?.screen.screenID != screen.screenID {
                endStream()
                remote = Remote(screen: screen)
                state = TVCastLiveState()
            } else if stream == nil {
                state.link = .connecting
            }
            watching = true
            failures = 0
            publish()
            if stream == nil { refresh() }
        }
    }

    /// Stops following. The session is kept for the next look.
    func unwatch() {
        queue.async { [self] in
            watching = false
            cancelRetry()
            endStream()
        }
    }

    /// Forgets the session, for a feature switched off.
    func stop() {
        lifetime.cancel()
        queue.async { [self] in
            watching = false
            cancelRetry()
            endStream()
            remote = nil
            state = TVCastLiveState()
        }
    }

    /// Sends a control from the service's queue and waits for YouTube's
    /// answer. The TV in view shares its session; another TV gets one of its
    /// own, which the next look at that TV takes up when nothing is in view.
    func perform(_ playback: TVCastPlayback, on screen: TVCastLoungeScreen,
                 cancellation: BoundedProcessCancellation) -> Result<Void, TVCastFailure> {
        queue.sync {
            let target: Remote
            if let remote, remote.screen.screenID == screen.screenID {
                target = remote
            } else {
                target = Remote(screen: screen)
                if !watching {
                    remote = target
                    state = TVCastLiveState()
                }
            }
            let result = command(playback.command, on: target, cancellation: cancellation)
            if case .success = result, target === remote {
                state.expect(playback, at: Date())
                publish()
                // A command that had to join again ended the old stream.
                if stream == nil { startStream() }
            }
            return result
        }
    }

    // MARK: - Session

    /// Joins when needed, asks what plays and opens the stream the answer
    /// comes on.
    private func refresh() {
        guard watching, let remote else { return }
        switch command(TVCastLounge.nowPlayingCommand, on: remote, cancellation: lifetime) {
        case .success:
            if state.link != .away { state.link = .connected }
            publish()
            startStream()
        case .failure(let failure):
            guard watching, !lifetime.isCancelled else { return }
            Self.log.error("the TV's session could not be followed: \(String(describing: failure), privacy: .public)")
            failures += 1
            state.link = .failed(failure)
            publish()
            scheduleRetry()
        }
    }

    /// One command on the remote's session, joining first when it has none.
    /// A session YouTube ended, or a token it turned down, is joined again once.
    private func command(_ name: String, on remote: Remote,
                         cancellation: BoundedProcessCancellation) -> Result<Void, TVCastFailure> {
        var rejoined = false
        while true {
            if remote.session == nil, case .failure(let failure) = join(remote, cancellation: cancellation) {
                return .failure(failure)
            }
            guard let token = remote.token, let session = remote.session else { return .failure(.unreachable) }
            remote.commandsSent += 1
            let request = TVCastLounge.commandRequest(name, token: token, session: session, number: remote.commandsSent)
            let reply: TVCastLoungeExchange.Reply
            switch exchange.send(request, cancellation: cancellation) {
            case .failure(let failure): return .failure(failure)
            case .success(let answer): reply = answer
            }
            if reply.status == 200 { return .success(()) }
            let rejected = TVCastLounge.tokenRejected(status: reply.status)
            guard rejected || TVCastLounge.sessionLost(status: reply.status), !rejoined else {
                return .failure(.unreachable)
            }
            rejoined = true
            if rejected { remote.token = nil }
            remote.session = nil
            if remote === self.remote { endStream() }
        }
    }

    /// Renews a lapsed token first, and once more when YouTube turns down
    /// the one it has, as ytcast's Connect does after its own refresh fails.
    private func join(_ remote: Remote, cancellation: BoundedProcessCancellation) -> Result<Void, TVCastFailure> {
        var renewed = false
        while true {
            if remote.token == nil {
                guard !renewed, let fresh = renew(remote.screen, cancellation: cancellation) else {
                    return .failure(.unreachable)
                }
                remote.token = fresh
                renewed = true
            }
            guard let token = remote.token else { return .failure(.unreachable) }
            let reply: TVCastLoungeExchange.Reply
            switch exchange.send(TVCastLounge.bindRequest(token: token), cancellation: cancellation) {
            case .failure(let failure): return .failure(failure)
            case .success(let answer): reply = answer
            }
            if TVCastLounge.tokenRejected(status: reply.status), !renewed {
                remote.token = nil
                continue
            }
            let messages = reply.status == 200 ? TVCastLounge.messages(inReply: reply.body) : []
            guard let session = TVCastLounge.session(in: messages) else { return .failure(.unreachable) }
            remote.session = session
            remote.commandsSent = 0
            remote.lastEventID = messages.map(\.id).max() ?? 0
            if remote === self.remote { take(messages) }
            return .success(())
        }
    }

    /// The renewed token lives in memory only. The list is never written
    /// here: ytcast renews its own copy on the next send, and the list keeps
    /// one writer per run.
    private func renew(_ screen: TVCastLoungeScreen, cancellation: BoundedProcessCancellation) -> String? {
        guard case .success(let reply) = exchange.send(TVCastLounge.renewalRequest(screenID: screen.screenID),
                                                       cancellation: cancellation) else { return nil }
        return TVCastLounge.renewedToken(status: reply.status, body: reply.body)
    }

    /// True when an event asks for the video it does not name.
    @discardableResult
    private func take(_ messages: [TVCastLoungeMessage]) -> Bool {
        let now = Date()
        var asks = false
        for message in messages where state.apply(message.event, at: now) { asks = true }
        if !messages.isEmpty { publish() }
        return asks
    }

    private func publish() {
        guard let screenID = remote?.screen.screenID else { return }
        let state = state
        DispatchQueue.main.async { [weak self] in self?.onChange?(screenID, state) }
    }

    // MARK: - Stream

    private func startStream() {
        guard watching, stream == nil, let remote, let token = remote.token, let session = remote.session else { return }
        frames = TVCastLoungeFrames()
        streamStatus = 0
        streamStarted = Date()
        streamDelivered = false
        let task = streamSession.dataTask(with: TVCastLounge.subscribeRequest(token: token, session: session,
                                                                              lastEventID: remote.lastEventID))
        stream = task
        task.resume()
    }

    private func endStream() {
        stream?.cancel()
        stream = nil
    }

    private func cancelRetry() {
        retry?.cancel()
        retry = nil
    }

    /// 1, 2, 4... seconds after each failure in a row, up to half a minute.
    private func scheduleRetry() {
        cancelRetry()
        let delay = min(Self.longestRetryDelay, pow(2, Double(max(0, failures - 1))))
        let work = DispatchWorkItem { [weak self] in
            self?.retry = nil
            self?.refresh()
        }
        retry = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === stream else { return completionHandler(.cancel) }
        streamStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(streamStatus == 200 ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === stream, let remote else { return }
        let messages = frames.append(data).flatMap(TVCastLounge.messages(in:))
        if frames.overflowed {
            dataTask.cancel()
            return
        }
        guard !messages.isEmpty else { return }
        streamDelivered = true
        failures = 0
        remote.lastEventID = max(remote.lastEventID, messages.map(\.id).max() ?? 0)
        let asks = take(messages)
        // YouTube ends the session with the TV's: join again, which waits
        // for YouTube to be open on it.
        if messages.contains(where: { $0.event == .screenDisconnected }) {
            remote.session = nil
            endStream()
            failures += 1
            scheduleRetry()
        } else if asks, case .failure(let failure) = command(TVCastLounge.nowPlayingCommand, on: remote,
                                                              cancellation: lifetime) {
            Self.log.error("the TV did not say what it plays: \(String(describing: failure), privacy: .public)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === stream else { return }
        stream = nil
        guard watching, let remote, !lifetime.isCancelled else { return }
        let rejected = TVCastLounge.tokenRejected(status: streamStatus)
        if rejected || TVCastLounge.sessionLost(status: streamStatus) {
            if rejected { remote.token = nil }
            remote.session = nil
            failures += 1
            if failures == 1 { refresh() } else { scheduleRetry() }
            return
        }
        // YouTube closes every stream after a while; one that carried
        // events, or simply ran its course, opens again at once.
        let urlError = error as? URLError
        let ranItsCourse = urlError == nil || urlError?.code == .timedOut
        if streamStatus == 200, ranItsCourse,
           streamDelivered || Date().timeIntervalSince(streamStarted) >= Self.shortestStream {
            startStream()
            return
        }
        failures += 1
        if let urlError, streamStatus == 0 {
            state.link = .failed(TVCastLounge.failure(for: urlError.code))
            publish()
        }
        scheduleRetry()
    }
}

/// One request at a time over one ephemeral session: no cookies, no cache,
/// no redirect, each answer capped. The caller waits; a cancelled run stops
/// the request in flight.
final class TVCastLoungeExchange: NSObject, URLSessionDataDelegate {
    struct Reply {
        let status: Int
        let body: Data
    }

    /// ytcast's own limit for one request.
    private static let timeout: TimeInterval = 30
    /// A session's first answer is a few kilobytes.
    private static let maxReplyBytes = 64 * 1024
    private static let cancellationCheck: TimeInterval = 0.25

    private let finished = DispatchSemaphore(value: 0)
    private var session: URLSession?
    // Written on the session's delegate queue while a request is in flight,
    // read by the caller once `finished` is signalled.
    private var status = 0
    private var body = Data()
    private var error: URLError?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func send(_ request: URLRequest, cancellation: BoundedProcessCancellation) -> Result<Reply, TVCastFailure> {
        guard let session, !cancellation.isCancelled else { return .failure(.offline) }
        status = 0
        body = Data()
        error = nil
        let task = session.dataTask(with: request)
        task.resume()
        while finished.wait(timeout: .now() + Self.cancellationCheck) == .timedOut {
            if cancellation.isCancelled { task.cancel() }
        }
        // Cut off for its size, an answer is not one the Lounge API gives.
        if body.count > Self.maxReplyBytes { return .failure(.unreachable) }
        if let error { return .failure(TVCastLounge.failure(for: error.code)) }
        return .success(Reply(status: status, body: body))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        body.append(chunk)
        if body.count > Self.maxReplyBytes { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            self.error = error as? URLError ?? URLError(.unknown)
        }
        finished.signal()
    }
}
