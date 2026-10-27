// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Sends one playback command to a TV through YouTube, the way ytcast casts:
/// renew the token when it lapsed, join the session, send the command. It
/// runs on the service's queue and blocks it, as a ytcast run does, so a
/// control never overlaps a pairing, a send or an edit of the list.
enum TVCastLoungeClient {
    static func perform(_ playback: TVCastPlayback, on screen: TVCastLoungeScreen,
                        cancellation: BoundedProcessCancellation) -> Result<Void, TVCastFailure> {
        let exchange = TVCastLoungeExchange(cancellation: cancellation)
        defer { exchange.close() }
        var token = screen.loungeToken
        var renewed = false
        if screen.isExpired(at: Date()) {
            guard let fresh = renew(screen, through: exchange) else { return .failure(.unreachable) }
            token = fresh
            renewed = true
        }
        var bound = exchange.send(TVCastLounge.bindRequest(token: token))
        // A token can lapse before the expiry YouTube stated; one renewal is
        // worth trying, as ytcast's Connect does after its own refresh fails.
        if case .success(let reply) = bound, TVCastLounge.tokenRejected(status: reply.status), !renewed {
            guard let fresh = renew(screen, through: exchange) else { return .failure(.unreachable) }
            token = fresh
            bound = exchange.send(TVCastLounge.bindRequest(token: token))
        }
        let session: TVCastLoungeSession
        switch bound {
        case .failure(let failure): return .failure(failure)
        case .success(let reply):
            guard let joined = TVCastLounge.session(status: reply.status, body: reply.body) else {
                return .failure(.unreachable)
            }
            session = joined
        }
        switch exchange.send(TVCastLounge.commandRequest(playback, token: token, session: session)) {
        case .failure(let failure): return .failure(failure)
        case .success(let reply): return reply.status == 200 ? .success(()) : .failure(.unreachable)
        }
    }

    /// The renewed token lives for this control only. The list is never
    /// written here: ytcast renews its own copy on the next send, and the
    /// list keeps one writer per run.
    private static func renew(_ screen: TVCastLoungeScreen, through exchange: TVCastLoungeExchange) -> String? {
        guard case .success(let reply) = exchange.send(TVCastLounge.renewalRequest(screenID: screen.screenID)) else {
            return nil
        }
        return TVCastLounge.renewedToken(status: reply.status, body: reply.body)
    }
}

/// One control's requests over one ephemeral session: no cookies, no cache,
/// no redirect, each answer capped. Requests go one at a time and the caller
/// waits; a cancelled run stops the request in flight.
private final class TVCastLoungeExchange: NSObject, URLSessionDataDelegate {
    struct Reply {
        let status: Int
        let body: Data
    }

    /// ytcast's own limit for one request.
    private static let timeout: TimeInterval = 30
    /// A session's first answer is a few kilobytes.
    private static let maxReplyBytes = 64 * 1024
    private static let cancellationCheck: TimeInterval = 0.25

    private let cancellation: BoundedProcessCancellation
    private let finished = DispatchSemaphore(value: 0)
    private var session: URLSession?
    // Written on the session's delegate queue while a request is in flight,
    // read by the caller once `finished` is signalled.
    private var status = 0
    private var body = Data()
    private var error: URLError?

    init(cancellation: BoundedProcessCancellation) {
        self.cancellation = cancellation
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Ends the session, which also lets go of this delegate.
    func close() {
        session?.invalidateAndCancel()
        session = nil
    }

    func send(_ request: URLRequest) -> Result<Reply, TVCastFailure> {
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
