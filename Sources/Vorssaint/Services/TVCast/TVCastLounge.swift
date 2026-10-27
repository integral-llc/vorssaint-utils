// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the playback controls ask YouTube on the TV to do.
enum TVCastPlayback: CaseIterable, Equatable {
    case play, pause, stop

    /// The Lounge command. `stopVideo` is what YouTube's own remotes send to
    /// end the video, as plaincast, a TV-side implementation, handles it.
    var command: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .stop: return "stopVideo"
        }
    }

    var symbol: String {
        switch self {
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .stop: return "stop.fill"
        }
    }
}

/// What a control needs from a TV paired with a code, as ytcast's cache
/// file holds it.
struct TVCastLoungeScreen: Equatable {
    let screenID: String
    let loungeToken: String
    /// Milliseconds since 1970, as ytcast stores it; 0 when the file has none.
    let expiration: Int64

    /// ytcast's `Expired`: past the moment, not at it.
    func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince1970 * 1000 > Double(expiration)
    }
}

/// The ids YouTube gives a remote when it joins a TV's session.
struct TVCastLoungeSession: Equatable {
    let sid: String
    let gsessionID: String
}

/// YouTube's Lounge API, which ytcast speaks for pairing and casting but
/// offers no pause or stop for. Every request is the one ytcast v1.4.1 makes,
/// parameter for parameter, so YouTube and the TV see the same remote they
/// already accept; only the command differs. The API is not public: a new
/// ytcast that changes these requests has to be checked against them.
enum TVCastLounge {
    private static let base = "https://www.youtube.com/api/lounge"
    private static let renewalURL = base + "/pairing/get_lounge_token_batch"
    private static let bindURL = base + "/bc/bind"
    private static let origin = "https://www.youtube.com"
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36"
    /// The name ytcast gets under Vorssaint, which passes it no account
    /// name: the TV keeps seeing one remote, not a second one for controls.
    static let remoteName = "ytcast"
    /// Go's `url.Values` escapes all but these; a token's `+` or `/` must
    /// not reach YouTube as a space or a path.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// A new token for a screen whose token has lapsed. Answers JSON.
    static func renewalRequest(screenID: String) -> URLRequest {
        request(renewalURL, query: [], body: [("screen_ids", screenID)])
    }

    static func renewedToken(status: Int, body: Data) -> String? {
        guard status == 200,
              let reply = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let screens = reply["screens"] as? [[String: Any]],
              let token = screens.first?["loungeToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// Joins the TV's session, as ytcast does before every Play.
    static func bindRequest(token: String) -> URLRequest {
        request(bindURL, query: [
            ("CVER", "1"), ("RID", "1"), ("VER", "8"), ("app", "youtube-desktop"),
            ("device", "REMOTE_CONTROL"), ("id", "remote"), ("loungeIdToken", token), ("name", remoteName),
        ], body: [])
    }

    /// YouTube's word that the token lapsed before the expiry it stated,
    /// which one renewal can fix.
    static func tokenRejected(status: Int) -> Bool { status == 401 }

    /// ytcast's `extractSessionIds`: a length, then arrays of `[index,
    /// [key, value, ...]]`, where `c` carries the SID and `S` the gsessionid.
    static func session(status: Int, body: Data) -> TVCastLoungeSession? {
        guard status == 200, let start = body.firstIndex(of: UInt8(ascii: "[")),
              let events = try? JSONSerialization.jsonObject(with: body[start...]) as? [[Any]] else { return nil }
        var sid: String?, gsessionID: String?
        for event in events {
            guard event.count >= 2, let payload = event[1] as? [Any], payload.count >= 2,
                  let key = payload[0] as? String, let value = payload[1] as? String else { continue }
            if key == "c" { sid = value }
            if key == "S" { gsessionID = value }
        }
        guard let sid, let gsessionID, !sid.isEmpty, !gsessionID.isEmpty else { return nil }
        return TVCastLoungeSession(sid: sid, gsessionID: gsessionID)
    }

    /// The command in the shape of ytcast's Play: one request, numbered after the bind.
    static func commandRequest(_ playback: TVCastPlayback, token: String,
                               session: TVCastLoungeSession) -> URLRequest {
        request(bindURL, query: [
            ("CVER", "1"), ("RID", "2"), ("SID", session.sid), ("VER", "8"),
            ("gsessionid", session.gsessionID), ("loungeIdToken", token),
        ], body: [("count", "1"), ("req0__sc", playback.command)])
    }

    /// A request that never reached an answer. Only a timeout says something
    /// else than a connection that is not there.
    static func failure(for code: URLError.Code) -> TVCastFailure {
        code == .timedOut ? .timedOut : .offline
    }

    static func formEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { escaped($0.0) + "=" + escaped($0.1) }.joined(separator: "&")
    }

    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static func request(_ address: String, query: [(String, String)],
                                body: [(String, String)]) -> URLRequest {
        var components = URLComponents(string: address)
        if !query.isEmpty { components?.percentEncodedQuery = formEncoded(query) }
        // Both addresses are constants, so the fallback is never taken.
        var request = URLRequest(url: components?.url ?? URL(fileURLWithPath: "/"))
        request.httpMethod = "POST"
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if !body.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(formEncoded(body).utf8)
        }
        return request
    }
}
