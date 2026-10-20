// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TVCastStrings {
    let pageTitle: String
    let hubDescription: String
    let sendSection: String
    let videoLinkLabel: String
    let videoLinkPlaceholder: String
    let tvLabel: String
    let sendButton: String
    let playCopiedLinkButton: String
    let sendingFormat: String
    let sentFormat: String
    let invalidVideo: String
    let noCopiedLink: String
    let keepYouTubeOpenHint: String
    let noTVsHint: String
    let noTVsIslandHint: String
    let importCaption: String
    let importButton: String
    let tvsSection: String
    let pairedWithCodeCaption: String
    let lastUsedBadge: String
    let actionsFormat: String
    let renameButton: String
    let renameTitle: String
    let pairAgainButton: String
    let removeButton: String
    let removeConfirmFormat: String
    let removeConfirmMessage: String
    let cancelButton: String
    let saveButton: String
    let nameLabel: String
    let namePlaceholder: String
    let addSection: String
    let addInstructions: String
    let codeLabel: String
    let codePlaceholder: String
    let pairButton: String
    let pairingStatus: String
    let pairedFormat: String
    let failureHelperMissing: String
    let failureInvalidCode: String
    let failurePairingRejected: String
    let failureDeviceNotFound: String
    let failureUnreachable: String
    let failurePlaybackRejected: String
    let failureOffline: String
    let failureTimedOut: String
    let failureCacheUnreadable: String
    let failureExitedFormat: String
    let failureOtherFormat: String

    func message(for failure: TVCastFailure) -> String {
        switch failure {
        case .helperMissing: return failureHelperMissing
        case .invalidCode: return failureInvalidCode
        case .pairingRejected: return failurePairingRejected
        case .deviceNotFound: return failureDeviceNotFound
        case .unreachable: return failureUnreachable
        case .playbackRejected: return failurePlaybackRejected
        case .offline: return failureOffline
        case .timedOut: return failureTimedOut
        case .cacheUnreadable: return failureCacheUnreadable
        case .failed(let detail): return String(format: failureOtherFormat, detail)
        case .exited(let status): return String(format: failureExitedFormat, status)
        }
    }
}

extension FeatureStrings {
    static func tvCast(_ language: AppLanguage) -> TVCastStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}
