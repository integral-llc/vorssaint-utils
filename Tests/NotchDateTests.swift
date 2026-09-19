// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchDateTests {
    static func run(expect: (Bool, String) -> Void) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let english = Locale(identifier: "en_US")
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 14, _ minute: Int = 5) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        // 2 February 2022 was a Wednesday.
        let sample = date(2022, 2, 2)
        func text(_ pattern: String, on day: Date? = nil, locale: Locale? = nil) -> NotchDateText {
            NotchDatePattern(pattern).text(date: day ?? sample, calendar: calendar, locale: locale ?? english)
        }

        expect(text("DDDD DD/MM/YYYY") == NotchDateText(leading: "Wednesday", trailing: "02/02/2022"),
               "a weekday and a numeric date take one wing each")
        expect(text("DDDD, DD/MM/YYYY") == NotchDateText(leading: "Wednesday", trailing: "02/02/2022"),
               "punctuation is not left dangling beside the camera")
        expect(text("DD/MM/YYYY") == NotchDateText(leading: "", trailing: "02/02/2022"),
               "text that cannot be divided leaves the leading wing to the symbol")
        expect(text("DDD D | MMM YYYY") == NotchDateText(leading: "Wed 2", trailing: "Feb 2022"),
               "an explicit separator decides what each wing shows")
        expect(text("DDDD |") == NotchDateText(leading: "", trailing: "Wednesday")
               && text("| DDDD") == NotchDateText(leading: "", trailing: "Wednesday"),
               "a single filled half always sits opposite the symbol")
        expect(text("D/M/YY hh:mm A") == NotchDateText(leading: "2/2/22", trailing: "02:05 PM"),
               "the division falls at the space that balances the wings")
        expect(text("HH:mm | H h hh A", on: date(2022, 2, 2, 0, 5)) == NotchDateText(leading: "00:05", trailing: "0 12 12 AM"),
               "midnight is hour zero on a 24-hour clock and twelve on a 12-hour clock")
        expect(text("[DD] | DD [D|D] Q") == NotchDateText(leading: "DD", trailing: "02 D|D Q"),
               "bracketed text and unknown letters are shown as written")
        expect(text("DD | [open") == NotchDateText(leading: "02", trailing: "open"),
               "an unclosed bracket escapes the remainder instead of discarding it")
        expect(text("DDDD[, ]D MMMM") == NotchDateText(leading: "Wednesday, 2", trailing: "February")
               && text("[ DD ] | D[,]") == NotchDateText(leading: " DD ", trailing: "2,"),
               "bracketed spaces and punctuation are neither a place to divide nor trimmed away")
        expect(text("DDD | MM | YY") == NotchDateText(leading: "Wed", trailing: "02 | 22"),
               "only the first separator divides the wings")
        expect(text("DDDD | D MMMM", locale: Locale(identifier: "pt_BR"))
                == NotchDateText(leading: "quarta-feira", trailing: "2 fevereiro"),
               "weekday and month names follow the app language")

        let long = NotchDatePattern("DDDD D MMMM YYYY")
        let may = long.text(date: date(2022, 5, 2), calendar: calendar, locale: english)
        let september = long.text(date: date(2022, 9, 28), calendar: calendar, locale: english)
        expect(may == NotchDateText(leading: "Monday 2", trailing: "May 2022")
               && september == NotchDateText(leading: "Wednesday 28", trailing: "September 2022"),
               "the division belongs to the pattern, so it never moves from one day to the next")

        func widest(_ pattern: String) -> CGFloat {
            NotchDatePattern(pattern).widestHalf(calendar: calendar, locale: english) { CGFloat($0.count) }
        }
        expect(widest("DDDD | D") == 9 && widest("D | MMMM") == 9 && widest("DDD | MMM") == 3,
               "a wing is sized for the longest name it will ever show")
        expect(widest("D/M/YY") == 8 && widest("h:mm A | YYYY") == 8,
               "numbers reserve their widest form, so the island keeps its width as days pass")
        expect(widest("DDDD, DD/MM/YYYY") == 10, "the wider half decides both wings")

        expect(NotchDateFormat.sanitized(nil) == NotchDateFormat.defaultPattern
               && NotchDateFormat.sanitized("") == NotchDateFormat.defaultPattern
               && NotchDateFormat.sanitized("  | ,") == NotchDateFormat.defaultPattern
               && NotchDateFormat.sanitized("[]") == NotchDateFormat.defaultPattern,
               "a pattern that would show nothing falls back to the default")
        expect(NotchDateFormat.sanitized(" DD\n/MM\u{0} ") == "DD/MM",
               "line breaks and control characters cannot reach the island")
        expect(NotchDateFormat.sanitized(String(repeating: "D ", count: 60)).count <= NotchDateFormat.maximumLength,
               "a pasted essay is cut to what a wing could plausibly show")
        expect(NotchDateFormat.presets.contains(NotchDateFormat.defaultPattern)
               && Set(NotchDateFormat.presets).count == NotchDateFormat.presets.count
               && NotchDateFormat.presets.allSatisfy { NotchDateFormat.sanitized($0) == $0 },
               "every offered format is distinct and survives its own validation")
        expect(NotchDateFormat.appending(.day, to: "YYYY-MM-DD") == "YYYY-MM-DD D"
               && NotchDateFormat.appending(.month, to: "DDD | D MMM") == "DDD | D MMM M"
               && NotchDateFormat.appending(.yearShort, to: "DD/MM/YYYY") == "DD/MM/YYYY YY",
               "an added code never fuses with the one before it into a different code")
        expect(NotchDateFormat.appending(.monthPadded, to: "DD/") == "DD/MM"
               && NotchDateFormat.appending(.day, to: "") == "D"
               && NotchDateFormat.appending(.year, to: "DD ") == "DD YYYY",
               "punctuation and spaces already separate codes, so nothing is inserted after them")
        expect(NotchDateFormat.appending(.monthName, to: String(repeating: "D ", count: 19)) == nil
               && NotchDateFormat.appending(.month, to: String(repeating: "D ", count: 19)) != nil,
               "a code that does not fit is refused whole instead of being cut into another code")
        expect(NotchDatePattern("DDD | HH:mm").showsTime && NotchDatePattern("h A").showsTime
               && !NotchDatePattern("DDDD DD/MM/YYYY").showsTime && !NotchDatePattern("[HH:mm] D").showsTime,
               "only a format with clock codes needs refreshing every minute")
        expect(NotchDateFormat.sanitized("D \u{1F468}\u{200D}\u{1F4BB}") == "D \u{1F468}\u{200D}\u{1F4BB}",
               "joined emoji survive validation intact")
        expect(NotchDateToken.allCases.allSatisfy { token in
            !NotchDatePattern(token.rawValue).text(date: sample, calendar: calendar, locale: english).trailing.isEmpty
        }, "every documented token produces text")

        func whole(_ pattern: String) -> String {
            NotchDatePattern(pattern).wholeText(date: sample, calendar: calendar, locale: english)
        }
        expect(whole("DDDD, DD/MM/YYYY") == "Wednesday, 02/02/2022" && whole("DDD | D MMM") == "Wed 2 Feb"
               && whole("| DDDD") == "Wednesday" && whole(" DD/MM ;") == "02/02",
               "undivided, the date reads as typed, with one space where the wings were divided")
        expect(NotchDatePattern("DDDD, DD/MM/YYYY").widestWhole(calendar: calendar, locale: english) { CGFloat($0.count) } == 21
               && NotchDatePattern("DDD | D MMM").widestWhole(calendar: calendar, locale: english) { CGFloat($0.count) } == 10,
               "the undivided date also reserves its widest form")

        let suite = "com.vorssaint.tests.notch.date"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(!NotchSupport.showsIdleDate(in: defaults) && Defaults.registeredDefaults[DefaultsKey.notchIdleShowsDate] as? Bool == false,
               "the date is an opt-in addition to the resting island")
        for choice in NotchIdleContent.allCases {
            defaults.set(choice.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchIdleShowsDate)
            let alone = NotchSupport.idleContent(in: defaults)
            defaults.set(true, forKey: DefaultsKey.notchIdleShowsDate)
            expect(NotchSupport.showsIdleDate(in: defaults) && NotchSupport.idleContent(in: defaults) == alone,
                   "the date joins \(choice.rawValue) instead of replacing it")
        }
        expect(NotchDateFormat.pattern(in: defaults) == NotchDatePattern(NotchDateFormat.defaultPattern),
               "an unset format shows the default")
        defaults.set("YYYY | MM", forKey: DefaultsKey.notchIdleDateFormat)
        expect(NotchDateFormat.pattern(in: defaults) == NotchDatePattern("YYYY | MM"), "a typed format is honored")
        defaults.set(42, forKey: DefaultsKey.notchIdleDateFormat)
        expect(NotchDateFormat.pattern(in: defaults) == NotchDatePattern(NotchDateFormat.defaultPattern),
               "a format of the wrong type is ignored")
        expect(Defaults.registeredDefaults[DefaultsKey.notchIdleDateFormat] as? String == NotchDateFormat.defaultPattern
               && SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchIdleDateFormat, DefaultsKey.notchIdleShowsDate]),
               "the date preferences have registered defaults and travel in backup")

        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let insets = NotchLayout.restingTextOuterInset + NotchLayout.restingTextInnerInset
        var notched = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180, menuBarHeight: 32, compactSideRoom: 200)
        let bare = notched.restingSize(showsContent: false)
        expect(notched.restingWingWidth == 44 && notched.restingRowWidth == nil, "symbols keep the compact wing")
        notched.restingText = NotchRestingText(wing: 70, row: 120, date: 100)
        expect(notched.restingWingWidth == 70 + insets && notched.collapsed.width == 180 + (70 + insets) * 2
               && notched.restingRowWidth == nil,
               "beside a real camera, text widens both wings equally and the island stays centered")
        expect(notched.restingSize(showsContent: false) == notched.collapsed,
               "a date alone is resting content, even with nothing else chosen")
        notched.restingText = NotchRestingText(wing: 10, row: 10, date: 10)
        expect(notched.restingWingWidth == 44, "short text never shrinks the wing below a symbol's")
        notched.restingText = NotchRestingText(wing: 900, row: 900, date: 900)
        expect(notched.restingWingWidth == 0 && notched.restingSize(showsContent: true) == CGSize(width: 180, height: 32),
               "a long format yields to the menu bar instead of being cut short")
        notched.compactSideRoom = 1000
        expect(notched.restingWingWidth == 900 + insets, "with room to spare, the whole text is shown")
        notched.restingText = NotchRestingText(wing: 70, row: 120, date: 100)
        notched.compactSideRoom = 70 + insets - 1
        expect(notched.restingWingWidth == 0, "text that would cover a menu is hidden rather than clipped")
        for invalid in [CGFloat.nan, .infinity, -1] {
            notched.compactSideRoom = 200
            notched.restingText = NotchRestingText(wing: invalid, row: invalid, date: invalid)
            expect(notched.restingWingWidth == 44 && notched.restingSize(showsContent: false) == bare,
                   "an unusable measurement is no resting content at all")
        }

        var simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 32, compactSideRoom: 200)
        let cutout = simulated.cameraWidth
        simulated.restingText = NotchRestingText(wing: 40, row: 60, date: 60)
        expect(simulated.restingRowWidth == cutout && simulated.collapsed.width == cutout && simulated.restingWingWidth == 0,
               "without a camera to avoid, a short date sits inside the cutout and adds no wings")
        simulated.restingText = NotchRestingText(wing: 120, row: 260, date: 200)
        let row = 260 + NotchLayout.restingTextOuterInset * 2
        expect(simulated.restingRowWidth == row && simulated.collapsed.width == row,
               "a longer row grows the pill only as far as its content")
        simulated.compactSideRoom = (row - cutout) / 2 - 1
        expect(simulated.restingRowWidth == nil && simulated.collapsed.width == cutout,
               "a row that would cover a menu is hidden rather than clipped")
        simulated.compactSideRoom = 0
        simulated.restingText = NotchRestingText(wing: 40, row: 60, date: 60)
        expect(simulated.restingRowWidth == cutout, "a date inside the cutout needs no room beside it")
    }
}
