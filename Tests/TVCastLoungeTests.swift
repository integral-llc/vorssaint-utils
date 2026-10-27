// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The playback controls speak YouTube's Lounge API themselves, in ytcast
/// v1.4.1's own requests, and only read the TV list.
enum TVCastLoungeTests {
    static func run(_ suite: TestSuite) {
        commandRules(suite)
        screenRules(suite)
        expiryRules(suite)
        bindRequestRules(suite)
        commandRequestRules(suite)
        renewalRules(suite)
        sessionRules(suite)
        failureRules(suite)
        stringRules(suite)
        sourceRules(suite)
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private static func body(_ request: URLRequest) -> String {
        request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private static func cache(_ remote: String, device: String = "null") -> Data {
        Data("[{\"Device\": \(device), \"Remote\": \(remote), \"LastUsed\": true}]".utf8)
    }

    private static let session = TVCastLoungeSession(sid: "sid-1", gsessionID: "gs-1")

    private static func commandRules(_ suite: TestSuite) {
        suite.expect(TVCastPlayback.allCases.map(\.command) == ["play", "pause", "stopVideo"],
                     "the controls send YouTube's own play, pause and stopVideo")
        suite.expect(TVCastPlayback.allCases.map(\.symbol) == ["play.fill", "pause.fill", "stop.fill"],
                     "each control wears its transport glyph")
    }

    private static func screenRules(_ suite: TestSuite) {
        let paired = cache("{\"ScreenId\": \"scr\", \"DeviceId\": \"dev\", \"LoungeToken\": \"tok\", "
            + "\"Expiration\": 1767225600000, \"ScreenName\": \"Living room\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: paired)
                     == TVCastLoungeScreen(screenID: "scr", loungeToken: "tok", expiration: 1_767_225_600_000),
                     "a TV paired with a code gives its screen, token and expiry")
        suite.expect(TVCastSupport.loungeScreen(for: "other", inCache: paired) == nil,
                     "a TV the list lacks has no screen")
        let discovered = cache("{\"ScreenId\": \"scr\", \"LoungeToken\": \"tok\"}",
                               device: "{\"UniqueServiceName\": \"dev\", \"FriendlyName\": \"TV\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: discovered) == nil,
                     "a discovered TV is never controlled, as it is never cast to")
        let tokenless = cache("{\"ScreenId\": \"scr\", \"DeviceId\": \"dev\", \"LoungeToken\": \"\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: tokenless) == nil,
                     "a pairing without a token has nothing to send with")
        let timeless = cache("{\"ScreenId\": \"scr\", \"DeviceId\": \"dev\", \"LoungeToken\": \"tok\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: timeless)?.expiration == 0,
                     "a pairing without an expiry counts as lapsed, so the token is renewed first")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: nil) == nil
                     && TVCastSupport.loungeScreen(for: "dev", inCache: Data("null".utf8)) == nil,
                     "no list, or ytcast's empty one, has no screen")
    }

    private static func expiryRules(_ suite: TestSuite) {
        let screen = TVCastLoungeScreen(screenID: "s", loungeToken: "t", expiration: 2_000_000)
        suite.expect(!screen.isExpired(at: Date(timeIntervalSince1970: 1_999))
                     && !screen.isExpired(at: Date(timeIntervalSince1970: 2_000))
                     && screen.isExpired(at: Date(timeIntervalSince1970: 2_000.001)),
                     "a token lapses past its expiry in milliseconds, not at it, as ytcast's Expired")
    }

    private static func bindRequestRules(_ suite: TestSuite) {
        let request = TVCastLounge.bindRequest(token: "tok")
        suite.expect(request.httpMethod == "POST"
                     && request.url?.absoluteString.hasPrefix("https://www.youtube.com/api/lounge/bc/bind?") == true
                     && request.httpBody == nil
                     && request.value(forHTTPHeaderField: "Content-Type") == nil,
                     "joining the session is ytcast's empty POST to bind")
        suite.expect(query(request) == ["CVER": "1", "RID": "1", "VER": "8", "app": "youtube-desktop",
                                        "device": "REMOTE_CONTROL", "id": "remote", "loungeIdToken": "tok",
                                        "name": "ytcast"],
                     "the bind names the remote as ytcast does, so the TV sees one remote: \(query(request))")
        suite.expect(request.value(forHTTPHeaderField: "Origin") == "https://www.youtube.com"
                     && request.value(forHTTPHeaderField: "User-Agent")?.contains("Chrome/96.0.4664.45") == true,
                     "every request carries ytcast's Origin and browser user agent")
        let escaped = TVCastLounge.bindRequest(token: "a+b/c=d e")
        let encoded = escaped.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.percentEncodedQuery
        suite.expect(encoded?.contains("loungeIdToken=a%2Bb%2Fc%3Dd%20e") == true
                     && query(escaped)["loungeIdToken"] == "a+b/c=d e",
                     "a token's + and / reach YouTube escaped, never as a space or a path")
    }

    private static func commandRequestRules(_ suite: TestSuite) {
        for playback in TVCastPlayback.allCases {
            let request = TVCastLounge.commandRequest(playback, token: "tok", session: session)
            suite.expect(request.httpMethod == "POST"
                         && request.url?.path == "/api/lounge/bc/bind"
                         && query(request) == ["CVER": "1", "RID": "2", "SID": "sid-1", "VER": "8",
                                               "gsessionid": "gs-1", "loungeIdToken": "tok"]
                         && body(request) == "count=1&req0__sc=\(playback.command)"
                         && request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded",
                         "\(playback.command) goes in the shape of ytcast's Play, after the bind")
        }
    }

    private static func renewalRules(_ suite: TestSuite) {
        let request = TVCastLounge.renewalRequest(screenID: "scr/1")
        suite.expect(request.httpMethod == "POST"
                     && request.url?.absoluteString == "https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch"
                     && body(request) == "screen_ids=scr%2F1",
                     "a lapsed token is renewed for the TV's screen, as ytcast's RefreshToken")
        let reply = Data("{\"screens\": [{\"screenId\": \"scr\", \"loungeToken\": \"fresh\", \"expiration\": 1}]}".utf8)
        suite.expect(TVCastLounge.renewedToken(status: 200, body: reply) == "fresh",
                     "the renewed token is the first screen's")
        suite.expect(TVCastLounge.renewedToken(status: 500, body: reply) == nil
                     && TVCastLounge.renewedToken(status: 200, body: Data("{\"screens\": []}".utf8)) == nil
                     && TVCastLounge.renewedToken(status: 200, body: Data("{\"screens\": [{\"loungeToken\": \"\"}]}".utf8)) == nil
                     && TVCastLounge.renewedToken(status: 200, body: Data("<html>".utf8)) == nil,
                     "an error, no screen, an empty token or no JSON renews nothing")
        suite.expect(TVCastLounge.tokenRejected(status: 401) && !TVCastLounge.tokenRejected(status: 400)
                     && !TVCastLounge.tokenRejected(status: 200),
                     "only YouTube's 401 calls for one renewal")
    }

    private static func sessionRules(_ suite: TestSuite) {
        // ytcast's own TestExtractSessionIds reply.
        let reply = Data("""

            270
            [[0,["c","sid-foo-bar-baz","",8]]
            ,[1,["S","gsessionid-foo-bar-baz"]]
            ,[2,["loungeStatus",{}]]
            ,[3,["playlistModified",{}]]
            ,[4,["onAutoplayModeChanged",{"autoplayMode":"UNSUPPORTED"}]]
            ,[5,["onPlaylistModeChanged",{"shuffleEnabled":"false","loopEnabled":"false"}]]
            ]
            """.utf8)
        suite.expect(TVCastLounge.session(status: 200, body: reply)
                     == TVCastLoungeSession(sid: "sid-foo-bar-baz", gsessionID: "gsessionid-foo-bar-baz"),
                     "the session ids come out of the bind's events past its length")
        let noGsession = Data("10\n[[0,[\"c\",\"sid\",\"\",8]]]".utf8)
        suite.expect(TVCastLounge.session(status: 200, body: noGsession) == nil
                     && TVCastLounge.session(status: 400, body: reply) == nil
                     && TVCastLounge.session(status: 200, body: Data("no events".utf8)) == nil
                     && TVCastLounge.session(status: 200, body: Data("[[0,[\"c\",7]],[1]]".utf8)) == nil,
                     "a reply without both ids, an error status or no events joins nothing")
    }

    private static func failureRules(_ suite: TestSuite) {
        suite.expect(TVCastLounge.failure(for: .timedOut) == .timedOut
                     && TVCastLounge.failure(for: .notConnectedToInternet) == .offline
                     && TVCastLounge.failure(for: .cannotFindHost) == .offline
                     && TVCastLounge.failure(for: .secureConnectionFailed) == .offline,
                     "a request that never got an answer is a timeout or no connection")
    }

    private static func stringRules(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.tvCast(language)
            let titles = TVCastPlayback.allCases.map(text.title(for:))
            suite.expect(Set(titles).count == 3 && titles.allSatisfy { !$0.isEmpty } && !text.playbackLabel.isEmpty,
                         "each control has its own name, under a named row (\(language.rawValue))")
            suite.expect([text.pausedFormat, text.stoppedFormat].allSatisfy { $0.components(separatedBy: "%@").count == 2 }
                         && text.controlledMessage(.pause, on: "TV") != text.controlledMessage(.stop, on: "TV")
                         && text.controlledMessage(.play, on: "TV") == String(format: text.sentFormat, "TV"),
                         "pause and stop each name the TV once, and play says what a send says (\(language.rawValue))")
        }
    }

    private static func source(_ path: String) -> String {
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return source.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The controls only read the list, and reach YouTube through the
    /// requests checked above and nothing else.
    private static func sourceRules(_ suite: TestSuite) {
        let service = source("Sources/Vorssaint/Services/TVCast/TVCastService.swift")
        let control = service.components(separatedBy: "private static func performControl(").dropFirst().first?
            .components(separatedBy: "private static func run(").first ?? ""
        let guardsFirst: Bool = {
            guard let check = control.range(of: "TVCastSupport.loungeScreen(for: id, inCache: readCache())"),
                  let send = control.range(of: "TVCastLoungeClient.perform(") else { return false }
            return check.upperBound <= send.lowerBound
        }()
        suite.expect(guardsFirst && control.contains(".failed(.deviceNotFound, during: .control)")
                     && !control.contains("writeCache") && !control.contains("run("),
                     "a control finds the TV paired with a code first, runs no ytcast and writes no list")
        let client = source("Sources/Vorssaint/Services/TVCast/TVCastLoungeClient.swift")
        suite.expect(!client.isEmpty && !client.contains("URLRequest(") && !client.contains("URL(")
                     && !client.contains("PrivateFileStore") && !client.contains("write(")
                     && client.contains("URLSessionConfiguration.ephemeral")
                     && client.contains("configuration.httpCookieStorage = nil")
                     && client.contains("completionHandler(nil)"),
                     "the client builds no request of its own, writes nothing, and keeps no cookies or redirects")
    }
}
