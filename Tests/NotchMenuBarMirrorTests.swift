// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchMenuBarMirrorTests {
    static func run(expect: (Bool, String) -> Void) {
        let laptop = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let external = CGRect(x: 1470, y: -200, width: 2560, height: 1440)
        let screens = [laptop, external]
        let bar = CGRect(x: external.minX, y: external.maxY - 24, width: external.width, height: 24)
        func menu(_ x: CGFloat, _ width: CGFloat, on screen: CGRect, height: CGFloat = 32) -> CGRect {
            CGRect(x: screen.minX + x, y: screen.maxY - height, width: width, height: height)
        }
        func mirrored(_ menus: [CGRect], everyDisplay: Bool = true) -> [CGRect]? {
            NotchMenuBarLayout.menus(menus, in: bar, screens: screens, onEveryDisplay: everyDisplay)
        }

        let own = [menu(10, 40, on: external, height: 24), menu(50, 60, on: external, height: 24)]
        expect(mirrored(own) ?? [] == own && mirrored(own, everyDisplay: false) ?? [] == own,
               "menus reported on the island's own bar are used as they are")

        let elsewhere = [menu(50, 60, on: laptop), menu(10, 40, on: laptop), menu(110, 50, on: laptop)]
        expect(mirrored(elsewhere) ?? [] == [menu(10, 40, on: external, height: 24), menu(50, 60, on: external, height: 24),
                                           menu(110, 50, on: external, height: 24)],
               "another display's active menus are repeated from this bar's own left edge, at its height")
        let aroundNotch = [menu(10, 600, on: laptop), menu(830, 70, on: laptop)]
        expect(mirrored(aroundNotch) ?? [] == [menu(10, 600, on: external, height: 24), menu(610, 70, on: external, height: 24)],
               "a bar without a camera does not repeat the jump menus make around one")
        expect(mirrored(elsewhere, everyDisplay: false) == nil,
               "a display without a menu bar of its own has nothing to repeat")
        expect(mirrored([CGRect(x: -5000, y: 0, width: 40, height: 24)]) == nil && mirrored([]) == nil,
               "menus that belong to no known display stay unknown")

        let room = (mirrored(elsewhere)).flatMap {
            NotchMenuBarLayout.sideRoom(screen: external, cameraWidth: 135, barHeight: 24, occupied: $0)
        }
        expect(room == external.width / 2 - 135 / 2 - 160 - 8,
               "the island keeps its measured room while another display holds the active menu bar")
    }
}
