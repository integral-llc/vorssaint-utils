// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Renders one island section's page, the way Settings previews it, to a PNG.
/// Compiling and unit tests say nothing about what a page looks like; this
/// lets a change to a page be looked at without clicking through the app.
/// Development builds only, like the presentation probe.
enum NotchPageRenderProbe {
    static let flag = "--render-notch-page"

    static func isRequested(by arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    static func runAndExit() -> Never {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 2),
              let module = NotchModule(rawValue: arguments[index + 1]) else {
            let sections = NotchModule.allCases.map(\.rawValue).joined(separator: ", ")
            print("RENDER FAILED: \(flag) <section> <file.png>; sections: \(sections)")
            exit(2)
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: arguments[index + 2])
        guard let png = render(module) else {
            print("RENDER FAILED: \(module.rawValue) drew nothing")
            exit(1)
        }
        do {
            try png.write(to: output)
        } catch {
            print("RENDER FAILED: \(error.localizedDescription)")
            exit(1)
        }
        print("RENDERED \(module.rawValue) -> \(output.path)")
        exit(0)
    }

    /// The page body only: the Settings pane draws its island just while its
    /// window is on screen, so controls a page puts in the island's top row
    /// (through `notchBand`) are not in this picture.
    private static func render(_ module: NotchModule) -> Data? {
        let service = NotchService.shared
        let content = service.previewGeometry(for: module).contentSize(for: service.previewSize(for: module))
        let page = NotchPagePreview(module: module, size: content)
            .frame(width: content.width, height: content.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: page)
        hosting.frame = CGRect(origin: .zero, size: content)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        // Pages load on appear (a list read, a service reload) and publish on
        // the main queue; give that a moment before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.close()
        return bitmap.representation(using: .png, properties: [:])
    }
}
