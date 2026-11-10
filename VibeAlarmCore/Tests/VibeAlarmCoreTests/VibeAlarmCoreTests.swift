import Foundation
import XCTest
@testable import VibeAlarmCore

final class VibeAlarmCoreTests: XCTestCase {
    private var calendar: Calendar!
    private var engine: AlarmScheduleEngine!

    override func setUp() {
        super.setUp()
        let tz = TimeZone(identifier: "Asia/Singapore") ?? .current
        calendar = AlarmScheduleEngine.defaultCalendar(timeZone: tz)
        engine = AlarmScheduleEngine(calendar: calendar)
    }

    // MARK: - Schedule Engine Tests

    func testPublicHolidaySkipsWeekdayAlarmAndMakeupWorkdayActivatesWeekendAlarm() throws {
        let rule = AlarmRule(
            label: "Morning Commute",
            hour: 7,
            minute: 30,
            isEnabled: true,
            repeatMode: .weekdays,
            skipPublicHolidays: true,
            skipPersonalLeave: true
        )

        let entries: [HolidayCalendarEntry] = [
            HolidayCalendarEntry(date: "2026-10-07", title: "National Day Holiday", kind: .publicHoliday, source: .builtin),
            HolidayCalendarEntry(date: "2026-10-10", title: "National Day Makeup Workday", kind: .makeupWorkday, source: .builtin)
        ]

        // 2026-10-07 is a Wednesday (Public Holiday -> should skip)
        let oct7 = try XCTUnwrap(engine.date(from: "2026-10-07"))
        let scheduleFromOct7 = engine.resolveSchedule(
            rule: rule,
            entries: entries,
            override: nil,
            referenceDate: oct7,
            daysCount: 4
        )

        XCTAssertEqual(scheduleFromOct7.count, 4)
        // Day 0: Wed Oct 7 -> Skipped by public holiday
        XCTAssertEqual(scheduleFromOct7[0].date, "2026-10-07")
        XCTAssertEqual(scheduleFromOct7[0].status, .skippedByHoliday(reason: "National Day Holiday"))
        XCTAssertNil(scheduleFromOct7[0].effectiveTime)

        // Day 1: Thu Oct 8 -> Normal workday -> Scheduled 07:30
        XCTAssertEqual(scheduleFromOct7[1].date, "2026-10-08")
        XCTAssertEqual(scheduleFromOct7[1].status, .scheduled)
        XCTAssertEqual(scheduleFromOct7[1].effectiveTime, "07:30")

        // Day 3: Sat Oct 10 -> Statutory makeup workday on Saturday -> Scheduled 07:30!
        XCTAssertEqual(scheduleFromOct7[3].date, "2026-10-10")
        XCTAssertEqual(scheduleFromOct7[3].status, .scheduled)
        XCTAssertEqual(scheduleFromOct7[3].effectiveTime, "07:30")
        XCTAssertTrue(scheduleFromOct7[3].reasonBadge.contains("Makeup"))
    }

    func testOneClickDelayAndSkipTomorrowAutoRestoresDayAfterTomorrow() throws {
        let rule = AlarmRule(hour: 7, minute: 15, repeatMode: .weekdays, autoRestoreNextDay: true)
        // Monday 2026-10-26
        let monday = try XCTUnwrap(engine.date(from: "2026-10-26"))
        // Override targets Tuesday 2026-10-27 with +45m delay
        let override = NextDayOverride(
            action: .delayTomorrow(minutes: 45),
            targetDate: "2026-10-27",
            createdAt: monday
        )

        let days = engine.resolveSchedule(
            rule: rule,
            entries: [],
            override: override,
            referenceDate: monday,
            daysCount: 3
        )

        // Monday (Today): normal 07:15
        XCTAssertEqual(days[0].date, "2026-10-26")
        XCTAssertEqual(days[0].effectiveTime, "07:15")
        XCTAssertFalse(days[0].hasManualOverride)

        // Tuesday (Tomorrow): delayed by +45m -> 08:00
        XCTAssertEqual(days[1].date, "2026-10-27")
        XCTAssertEqual(days[1].status, .delayed(minutes: 45))
        XCTAssertEqual(days[1].effectiveTime, "08:00")
        XCTAssertTrue(days[1].hasManualOverride)

        // Wednesday (Day after tomorrow): automatically restored to 07:15!
        XCTAssertEqual(days[2].date, "2026-10-28")
        XCTAssertEqual(days[2].status, .scheduled)
        XCTAssertEqual(days[2].effectiveTime, "07:15")
        XCTAssertFalse(days[2].hasManualOverride)
    }

    func testPersonalLeaveSkipsWorkdayAlarmUnlessForceKept() throws {
        let rule = AlarmRule(hour: 8, minute: 0, repeatMode: .weekdays, skipPersonalLeave: true)
        let entries = [
            HolidayCalendarEntry(date: "2026-10-27", title: "Annual Leave", kind: .personalLeave, source: .localEventKit)
        ]
        let monday = try XCTUnwrap(engine.date(from: "2026-10-26"))

        let (_, tomorrowSkipped) = engine.resolveTwoDayDashboard(
            rule: rule,
            entries: entries,
            override: nil,
            referenceDate: monday
        )
        XCTAssertEqual(tomorrowSkipped.status, .skippedByPersonalLeave(reason: "Annual Leave"))
        XCTAssertNil(tomorrowSkipped.effectiveTime)

        // Force keep tomorrow overrides personal leave
        let keepOverride = NextDayOverride(action: .forceKeepTomorrow, targetDate: "2026-10-27", createdAt: monday)
        let (_, tomorrowKept) = engine.resolveTwoDayDashboard(
            rule: rule,
            entries: entries,
            override: keepOverride,
            referenceDate: monday
        )
        XCTAssertEqual(tomorrowKept.status, .scheduled)
        XCTAssertEqual(tomorrowKept.effectiveTime, "08:00")
        XCTAssertTrue(tomorrowKept.hasManualOverride)
    }

    func testNeitherSkipFlagRingsOnHolidayAndPersonalLeave() throws {
        let rule = AlarmRule(
            hour: 7,
            minute: 30,
            repeatMode: .weekdays,
            skipPublicHolidays: false,
            skipPersonalLeave: false
        )
        let entries = [
            HolidayCalendarEntry(date: "2026-10-27", title: "Annual Leave", kind: .personalLeave, source: .localEventKit),
            HolidayCalendarEntry(date: "2026-10-28", title: "Public Holiday", kind: .publicHoliday, source: .builtin)
        ]
        let monday = try XCTUnwrap(engine.date(from: "2026-10-26"))
        let days = engine.resolveSchedule(
            rule: rule,
            entries: entries,
            override: nil,
            referenceDate: monday,
            daysCount: 3
        )
        XCTAssertEqual(days[1].date, "2026-10-27")
        XCTAssertEqual(days[1].status, .scheduled)
        XCTAssertEqual(days[1].effectiveTime, "07:30")
        XCTAssertEqual(days[2].date, "2026-10-28")
        XCTAssertEqual(days[2].status, .scheduled)
        XCTAssertEqual(days[2].effectiveTime, "07:30")
    }

    func testWeeklySelectionUsesTheNamedRepeatCases() {
        XCTAssertEqual(AlarmRepeatMode.matching(weekdays: Weekday.standardWeekdays), .weekdays)
        XCTAssertEqual(AlarmRepeatMode.matching(weekdays: Set(Weekday.allCases)), .everyday)
        XCTAssertEqual(AlarmRepeatMode.matching(weekdays: [.saturday, .sunday]), .weekends)
        XCTAssertEqual(
            AlarmRepeatMode.matching(weekdays: [.monday, .wednesday]),
            .customDays([.monday, .wednesday])
        )
        XCTAssertEqual(AlarmRepeatMode.matching(weekdays: []), .customDays([]))
        XCTAssertEqual(AlarmRepeatMode.weekdays.weekdays, Weekday.standardWeekdays)
        XCTAssertEqual(AlarmRepeatMode.everyday.weekdays, Set(Weekday.allCases))
        XCTAssertTrue(AlarmRepeatMode.specificDates(["2026-11-09"]).weekdays.isEmpty)
    }

    func testWeekendsRepeatModeOnlyRingsOnSaturdayAndSunday() throws {
        let rule = AlarmRule(hour: 9, minute: 0, repeatMode: .weekends, skipPublicHolidays: true)
        // 2026-10-26 is a Monday
        let monday = try XCTUnwrap(engine.date(from: "2026-10-26"))

        let days = engine.resolveSchedule(
            rule: rule,
            entries: [],
            override: nil,
            referenceDate: monday,
            daysCount: 6
        )

        // Monday..Friday: no alarm
        for weekday in days.prefix(5) {
            XCTAssertEqual(weekday.status, .noAlarm)
        }

        // Saturday 2026-10-31: rings at 09:00
        XCTAssertEqual(days[5].date, "2026-10-31")
        XCTAssertEqual(days[5].status, .scheduled)
        XCTAssertEqual(days[5].effectiveTime, "09:00")
    }

    // MARK: - ICS Parser Tests

    func testICSHolidayParserMultiDayAndMakeupWorkday() {
        let sampleICS = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//VibeAlarm//Holidays//EN
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261001
        DTEND;VALUE=DATE:20261004
        SUMMARY:National Day Holiday
        DESCRIPTION:Statutory Holiday
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261010
        DTEND;VALUE=DATE:20261011
        SUMMARY:National Day Makeup Workday
        DESCRIPTION:Saturday Makeup Workday
        END:VEVENT
        END:VCALENDAR
        """

        let parser = ICSHolidayParser(calendar: calendar)
        let entries = parser.parse(icsContent: sampleICS)
        XCTAssertEqual(entries.count, 4)

        let holidays = entries.filter { $0.kind == .publicHoliday }
        let makeups = entries.filter { $0.kind == .makeupWorkday }

        XCTAssertEqual(holidays.map(\.date), ["2026-10-01", "2026-10-02", "2026-10-03"])
        XCTAssertEqual(makeups.map(\.date), ["2026-10-10"])
        XCTAssertEqual(makeups.first?.title, "National Day Makeup Workday")
    }

    func testICSHolidayParserGoogleFeedClassification() {
        // Full sanitized ASCII sample from google_holidays_sample.ics, embedded line
        // by line and joined with CRLF to preserve RFC 5545 folding semantics. The
        // "\\n" / "\\," sequences are literal ICS escapes inside DESCRIPTION values.
        let icsLines = [
            "BEGIN:VCALENDAR",
            "PRODID:-//Google Inc//Google Calendar 70.9054//EN",
            "VERSION:2.0",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:Holidays in Singapore",
            "X-WR-TIMEZONE:UTC",
            "X-WR-CALDESC:Holidays and Observances in Singapore",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20260501",
            "DTEND;VALUE=DATE:20260502",
            "DTSTAMP:20261103T232404Z",
            "UID:20260501_iir73seq4bmhp7ad0dn1kkf7lk@google.com",
            "CLASS:PUBLIC",
            "CREATED:20240530T145217Z",
            "DESCRIPTION:Public holiday",
            "LAST-MODIFIED:20240530T145217Z",
            "SEQUENCE:0",
            "STATUS:CONFIRMED",
            "SUMMARY:Labour Day",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20260810",
            "DTEND;VALUE=DATE:20260811",
            "DTSTAMP:20261103T232404Z",
            "UID:20260810_vf99rr6t2mcumr2g358u896rnk@google.com",
            "CLASS:PUBLIC",
            "CREATED:20240530T145217Z",
            "DESCRIPTION:Public holiday",
            "LAST-MODIFIED:20240530T145217Z",
            "SEQUENCE:0",
            "STATUS:CONFIRMED",
            "SUMMARY:National Day observed",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20261108",
            "DTEND;VALUE=DATE:20261109",
            "DTSTAMP:20261103T232404Z",
            "UID:20261108_q60kgpfcdpllnrlv5bfdk3lahg@google.com",
            "CLASS:PUBLIC",
            "CREATED:20240530T145217Z",
            "DESCRIPTION:Public holiday",
            "LAST-MODIFIED:20240530T145217Z",
            "SEQUENCE:0",
            "STATUS:CONFIRMED",
            "SUMMARY:Diwali/Deepavali",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20260404",
            "DTEND;VALUE=DATE:20260405",
            "DTSTAMP:20261103T232404Z",
            "UID:20260404_7r96it48gek5pljm8789akaiq4@google.com",
            "CLASS:PUBLIC",
            "CREATED:20240530T145236Z",
            "DESCRIPTION:Observance\\nTo hide observances\\, go to Google Calendar Setting",
            " s > Holidays in Singapore",
            "LAST-MODIFIED:20240530T145236Z",
            "SEQUENCE:0",
            "STATUS:CONFIRMED",
            "SUMMARY:Easter Saturday",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20261224",
            "DTEND;VALUE=DATE:20261225",
            "DTSTAMP:20261103T232404Z",
            "UID:20261224_ldgdc27q3t9jlj41f39bo6psbs@google.com",
            "CLASS:PUBLIC",
            "CREATED:20240530T145256Z",
            "DESCRIPTION:Observance\\nTo hide observances\\, go to Google Calendar Setting",
            " s > Holidays in Singapore",
            "LAST-MODIFIED:20240530T145256Z",
            "SEQUENCE:0",
            "STATUS:CONFIRMED",
            "SUMMARY:Christmas Eve",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20260406",
            "DTEND;VALUE=DATE:20260407",
            "DTSTAMP:20261103T232406Z",
            "UID:20260406_gglful72diqo4tgctk1rq4qi1k@google.com",
            "CLASS:PUBLIC",
            "CREATED:20241024T090957Z",
            "DESCRIPTION:Public holiday in Australian Capital Territory\\, New South Wale",
            " s\\, Northern Territory\\, Queensland\\, South Australia\\, Tasmania\\, Victoria",
            " \\, Western Australia\\, Cocos and Keeling Islands\\, Heard and McDonald Islan",
            " ds",
            "LAST-MODIFIED:20241024T090957Z",
            "SEQUENCE:0",
            "STATUS:CONFIRMED",
            "SUMMARY:Easter Monday (regional holiday)",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20260101",
            "DTEND;VALUE=DATE:20260102",
            "DTSTAMP:20261103T232406Z",
            "UID:20260101_ohkboet8blbfrvg0kpilr92gf0@google.com",
            "CLASS:PUBLIC",
            "CREATED:20240517T092521Z",
            "DESCRIPTION:Public holiday",
            "LAST-MODIFIED:20240517T092521Z",
            "SEQUENCE:0",
            "STATUS:CONFIRMED",
            "SUMMARY:New Year's Day",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
            "END:VCALENDAR"
        ]
        let sampleICS = icsLines.joined(separator: "\r\n")

        let parser = ICSHolidayParser(calendar: calendar)
        let entries = parser.parse(icsContent: sampleICS)

        // Only the four genuine nationwide days off survive; the two observances
        // and the one regional holiday are excluded.
        XCTAssertEqual(entries.count, 4)
        XCTAssertTrue(entries.allSatisfy { $0.kind == .publicHoliday })

        let titlesByDate = Dictionary(uniqueKeysWithValues: entries.map { ($0.date, $0.title) })
        XCTAssertEqual(titlesByDate["2026-05-01"], "Labour Day")
        XCTAssertEqual(titlesByDate["2026-08-10"], "National Day observed")
        XCTAssertEqual(titlesByDate["2026-11-08"], "Diwali/Deepavali")
        XCTAssertEqual(titlesByDate["2026-01-01"], "New Year's Day")

        // Excluded events must not produce entries.
        XCTAssertNil(titlesByDate["2026-04-04"]) // Easter Saturday (observance)
        XCTAssertNil(titlesByDate["2026-12-24"]) // Christmas Eve (observance)
        XCTAssertNil(titlesByDate["2026-04-06"]) // Easter Monday (regional holiday)
    }

    func testICSHolidayParserChinaStatutoryFeedMakeupAndTranslation() {
        // China statutory feed (NateScarlet holiday-cn) serves Chinese SUMMARY text.
        // The repository stays free of literal CJK characters: every Chinese keyword
        // is expressed only as Swift Unicode scalar escapes.
        // Holiday SUMMARY "New Year's Day holiday period": U+5143 U+65E6 U+5047 U+671F.
        let holidaySummary = "\u{5143}\u{65E6}\u{5047}\u{671F}"
        // Makeup SUMMARY "work day (makeup New Year's Day holiday period)":
        // U+4E0A U+73ED U+FF08 U+8865 U+5143 U+65E6 U+5047 U+671F U+FF09.
        let makeupSummary = "\u{4E0A}\u{73ED}\u{FF08}\u{8865}\u{5143}\u{65E6}\u{5047}\u{671F}\u{FF09}"

        let icsLines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//NateScarlet/holiday-cn//EN",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20260101",
            "DTEND;VALUE=DATE:20260104",
            "SUMMARY:\(holidaySummary)",
            "END:VEVENT",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:20260104",
            "DTEND;VALUE=DATE:20260105",
            "SUMMARY:\(makeupSummary)",
            "END:VEVENT",
            "END:VCALENDAR"
        ]
        let sampleICS = icsLines.joined(separator: "\r\n")

        let parser = ICSHolidayParser(calendar: calendar)
        let entries = parser.parse(icsContent: sampleICS)

        // One 3-day holiday (DTEND exclusive) plus one makeup workday.
        XCTAssertEqual(entries.count, 4)

        let holidays = entries.filter { $0.kind == .publicHoliday }
        let makeups = entries.filter { $0.kind == .makeupWorkday }

        XCTAssertEqual(holidays.map(\.date), ["2026-01-01", "2026-01-02", "2026-01-03"])
        XCTAssertTrue(holidays.allSatisfy { $0.title == "New Year's Day" })

        XCTAssertEqual(makeups.map(\.date), ["2026-01-04"])
        XCTAssertEqual(makeups.first?.title, "Makeup workday (New Year's Day)")
    }

    // MARK: - BYOK Service & Offline Parser Tests

    func testBYOKOfflineParserAndCalendarLinkDiscovery() throws {
        let service = BYOKHolidayService(calendar: calendar)
        let refDate = try XCTUnwrap(engine.date(from: "2026-10-24"))
        let text = """
        HR Notice: I will take annual leave from October 26 to 28, 2026.
        I will work a makeup shift on Saturday, October 31, 2026.
        Company calendar subscription: webcal://calendar.example.com/company-holidays.ics
        """

        let result = service.parseLocally(text: text, referenceDate: refDate)
        XCTAssertEqual(result.discoveredCalendarURLs, ["https://calendar.example.com/company-holidays.ics"])

        let leaveDates = result.entries.filter { $0.kind == .personalLeave }.map(\.date)
        let makeupDates = result.entries.filter { $0.kind == .makeupWorkday }.map(\.date)

        XCTAssertEqual(leaveDates, ["2026-10-26", "2026-10-27", "2026-10-28"])
        XCTAssertEqual(makeupDates, ["2026-10-31"])
    }

    func testBYOKOpenAIResponseParsing() throws {
        let service = BYOKHolidayService(calendar: calendar)
        let mockOpenAIJSON = """
        {
          "choices": [
            {
              "message": {
                "content": "```json\\n{\\"entries\\":[{\\"date\\":\\"2026-11-09\\",\\"title\\":\\"Deepavali Observed\\",\\"kind\\":\\"publicHoliday\\"}],\\"discoveredCalendarURLs\\":[],\\"summaryNote\\":\\"Extracted Singapore Deepavali Observed holiday\\"}\\n```"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let parsed = try service.parseLLMResponseData(mockOpenAIJSON, provider: .openAICompatible)
        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries.first?.date, "2026-11-09")
        XCTAssertEqual(parsed.entries.first?.title, "Deepavali Observed")
        XCTAssertEqual(parsed.entries.first?.kind, .publicHoliday)
        XCTAssertEqual(parsed.summaryNote, "Extracted Singapore Deepavali Observed holiday")
    }

    // MARK: - SharedAlarmStore Tests

    func testSharedAlarmStoreExpiresStaleNextDayOverride() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vibe-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = SharedAlarmStore(fileURL: tempURL)
        let monday = try XCTUnwrap(engine.date(from: "2026-10-26"))
        _ = try store.setTomorrowOverride(action: .skipTomorrow, referenceDate: monday, calendar: calendar)

        // On Tuesday (2026-10-27), override is still active for 2026-10-27
        let tuesday = try XCTUnwrap(engine.date(from: "2026-10-27"))
        let loadedTuesday = store.load(referenceDate: tuesday, calendar: calendar)
        XCTAssertEqual(loadedTuesday.nextDayOverride?.targetDate, "2026-10-27")
        XCTAssertEqual(loadedTuesday.nextDayOverride?.action, .skipTomorrow)

        // On Wednesday (2026-10-28), override for 2026-10-27 automatically expires!
        let wednesday = try XCTUnwrap(engine.date(from: "2026-10-28"))
        let loadedWednesday = store.load(referenceDate: wednesday, calendar: calendar)
        XCTAssertNil(loadedWednesday.nextDayOverride)
    }

    // MARK: - Snooze Interval Tests

    func testDefaultSnoozeMinutesIsEight() {
        XCTAssertEqual(AlarmRule().snoozeMinutes, 8)
        XCTAssertEqual(AlarmRule.snoozeIntervalOptions, [5, 8, 10, 15, 20])
    }

    func testAlarmRuleDecodesMissingSnoozeMinutesAsEight() throws {
        // Encode a rule, strip the new key, and ensure legacy JSON still decodes.
        let rule = AlarmRule(hour: 6, minute: 0, repeatMode: .weekdays)
        let data = try JSONEncoder().encode(rule)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "snoozeMinutes")
        XCTAssertNil(dict["snoozeMinutes"])
        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(AlarmRule.self, from: strippedData)
        XCTAssertEqual(decoded.snoozeMinutes, 8)
    }

    func testSnoozeMinutesNormalizationSnapsToNearestOption() {
        XCTAssertEqual(AlarmRule.normalizedSnoozeMinutes(7), 8)
        XCTAssertEqual(AlarmRule.normalizedSnoozeMinutes(100), 20)
        XCTAssertEqual(AlarmRule.normalizedSnoozeMinutes(0), 8)
        XCTAssertEqual(AlarmRule.normalizedSnoozeMinutes(-5), 8)
        XCTAssertEqual(AlarmRule.normalizedSnoozeMinutes(5), 5)
        XCTAssertEqual(AlarmRule.normalizedSnoozeMinutes(15), 15)
        // The initializer also normalizes out-of-list values.
        XCTAssertEqual(AlarmRule(snoozeMinutes: 7).snoozeMinutes, 8)
        XCTAssertEqual(AlarmRule(snoozeMinutes: 0).snoozeMinutes, 8)
    }

    func testSharedAlarmStoreSnoozeMinutesRoundTrip() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vibe-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = SharedAlarmStore(fileURL: tempURL)
        _ = try store.setSnoozeMinutes(15)
        XCTAssertEqual(store.load().alarmRule.snoozeMinutes, 15)

        // A non-option value is normalized to the nearest option through the setter.
        _ = try store.setSnoozeMinutes(7)
        XCTAssertEqual(store.load().alarmRule.snoozeMinutes, 8)
    }

    func testSnoozeFireDateAddsExactlyConfiguredMinutes() throws {
        let base = try XCTUnwrap(engine.date(from: "2026-10-26"))

        let fire = engine.snoozeFireDate(after: base, rule: AlarmRule(snoozeMinutes: 10))
        XCTAssertEqual(fire.timeIntervalSince(base), 10 * 60, accuracy: 0.5)

        let defaultFire = engine.snoozeFireDate(after: base, rule: AlarmRule())
        XCTAssertEqual(defaultFire.timeIntervalSince(base), 8 * 60, accuracy: 0.5)
    }

    // MARK: - Holiday Catalog Tests

    func testHolidayCatalogHasAtLeastFiftyItems() {
        XCTAssertGreaterThanOrEqual(HolidayCatalog.all.count, 50)
    }

    func testHolidayCatalogISOAndSlugPairsAreUnique() {
        var seen = Set<String>()
        for item in HolidayCatalog.all {
            let key = "\(item.isoCode)|\(item.googleSlug)"
            XCTAssertFalse(seen.contains(key), "Duplicate ISO+slug pair: \(key)")
            seen.insert(key)
        }
        XCTAssertEqual(seen.count, HolidayCatalog.all.count)
    }

    func testHolidayCatalogURLsAreValidHTTPS() {
        for item in HolidayCatalog.all {
            let url = URL(string: item.icsURL)
            XCTAssertNotNil(url, "Invalid URL for \(item.countryName): \(item.icsURL)")
            XCTAssertEqual(url?.scheme, "https", "Non-HTTPS URL for \(item.countryName)")
        }
    }

    func testHolidayCatalogSearchMatchesISOCaseInsensitivelyAndByName() {
        XCTAssertTrue(HolidayCatalog.search("sg").contains { $0.isoCode == "SG" })
        XCTAssertTrue(HolidayCatalog.search("SG").contains { $0.isoCode == "SG" })
        XCTAssertTrue(HolidayCatalog.search("sing").contains { $0.countryName.contains("Singapore") })

        let united = HolidayCatalog.search("united")
        XCTAssertTrue(united.contains { $0.isoCode == "US" })
        XCTAssertTrue(united.contains { $0.isoCode == "GB" })
        XCTAssertTrue(united.contains { $0.isoCode == "AE" })

        XCTAssertTrue(HolidayCatalog.search("does-not-exist").isEmpty)

        // Empty query returns the full list sorted by country name.
        let everything = HolidayCatalog.search("")
        XCTAssertEqual(everything.count, HolidayCatalog.all.count)
    }

    func testHolidayCatalogHasDedicatedChinaMakeupSourcePresentedFirst() {
        let statutory = HolidayCatalog.all.first { $0.kind == .chinaStatutory }
        XCTAssertNotNil(statutory)
        XCTAssertEqual(statutory?.isoCode, "CN")
        XCTAssertEqual(
            statutory?.icsURL,
            "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.ics"
        )

        // Searching CN returns both the dedicated statutory source and the plain Google feed,
        // with the makeup-aware statutory source presented first.
        let cn = HolidayCatalog.search("cn")
        XCTAssertEqual(cn.first?.kind, .chinaStatutory)
        XCTAssertTrue(cn.contains { $0.kind == .google && $0.isoCode == "CN" })
    }

    func testHolidayCatalogGoogleURLEncodingIsPreserved() throws {
        let sg = try XCTUnwrap(HolidayCatalog.all.first { $0.isoCode == "SG" })
        XCTAssertEqual(
            sg.icsURL,
            "https://calendar.google.com/calendar/ical/en.singapore%23holiday%40group.v.calendar.google.com/public/basic.ics"
        )
    }

    func testExternalCalendarSubscriptionDecodesMissingCatalogIDAsNil() throws {
        let sub = ExternalCalendarSubscription(name: "Legacy", url: "https://example.com/a.ics")
        let data = try JSONEncoder().encode(sub)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "catalogID")
        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(ExternalCalendarSubscription.self, from: strippedData)
        XCTAssertNil(decoded.catalogID)
        XCTAssertEqual(decoded.url, "https://example.com/a.ics")
    }
}
