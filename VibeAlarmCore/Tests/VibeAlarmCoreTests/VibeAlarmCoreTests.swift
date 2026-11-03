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
}
