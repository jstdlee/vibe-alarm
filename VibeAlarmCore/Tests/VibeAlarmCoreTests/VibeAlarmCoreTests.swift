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
            label: "早起上班",
            hour: 7,
            minute: 30,
            isEnabled: true,
            repeatMode: .weekdays,
            skipPublicHolidays: true,
            skipPersonalLeave: true
        )

        let entries: [HolidayCalendarEntry] = [
            HolidayCalendarEntry(date: "2026-10-07", title: "国庆节假期", kind: .publicHoliday, source: .builtin),
            HolidayCalendarEntry(date: "2026-10-10", title: "国庆节调休补班", kind: .makeupWorkday, source: .builtin)
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
        XCTAssertEqual(scheduleFromOct7[0].status, .skippedByHoliday(reason: "国庆节假期"))
        XCTAssertNil(scheduleFromOct7[0].effectiveTime)

        // Day 1: Thu Oct 8 -> Normal workday -> Scheduled 07:30
        XCTAssertEqual(scheduleFromOct7[1].date, "2026-10-08")
        XCTAssertEqual(scheduleFromOct7[1].status, .scheduled)
        XCTAssertEqual(scheduleFromOct7[1].effectiveTime, "07:30")

        // Day 3: Sat Oct 10 -> Statutory makeup workday on Saturday -> Scheduled 07:30!
        XCTAssertEqual(scheduleFromOct7[3].date, "2026-10-10")
        XCTAssertEqual(scheduleFromOct7[3].status, .scheduled)
        XCTAssertEqual(scheduleFromOct7[3].effectiveTime, "07:30")
        XCTAssertTrue(scheduleFromOct7[3].reasonBadge.contains("调休"))
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
            HolidayCalendarEntry(date: "2026-10-27", title: "个人年假", kind: .personalLeave, source: .localEventKit)
        ]
        let monday = try XCTUnwrap(engine.date(from: "2026-10-26"))

        let (_, tomorrowSkipped) = engine.resolveTwoDayDashboard(
            rule: rule,
            entries: entries,
            override: nil,
            referenceDate: monday
        )
        XCTAssertEqual(tomorrowSkipped.status, .skippedByPersonalLeave(reason: "个人年假"))
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

    // MARK: - ICS Parser Tests

    func testICSHolidayParserMultiDayAndMakeupWorkday() {
        let sampleICS = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//VibeAlarm//CN Holidays//ZH
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261001
        DTEND;VALUE=DATE:20261004
        SUMMARY:国庆节放假
        DESCRIPTION:法定节假日
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261010
        DTEND;VALUE=DATE:20261011
        SUMMARY:国庆节调休补班
        DESCRIPTION:周六补班
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
        XCTAssertEqual(makeups.first?.title, "国庆节调休补班")
    }

    // MARK: - BYOK Service & Offline Parser Tests

    func testBYOKOfflineParserAndCalendarLinkDiscovery() throws {
        let service = BYOKHolidayService(calendar: calendar)
        let refDate = try XCTUnwrap(engine.date(from: "2026-10-24"))
        let text = """
        HR通知：我将在 2026年10月26日到10月28日休年假，10月31日周六调休补班。
        另外附公司公共日历订阅：webcal://calendar.example.com/company-holidays.ics
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
                "content": "```json\\n{\\"entries\\":[{\\"date\\":\\"2026-11-09\\",\\"title\\":\\"屠妖节补休\\",\\"kind\\":\\"publicHoliday\\"}],\\"discoveredCalendarURLs\\":[],\\"summaryNote\\":\\"已提取新加坡屠妖节补休\\"}\\n```"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let parsed = try service.parseLLMResponseData(mockOpenAIJSON, provider: .openAICompatible)
        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries.first?.date, "2026-11-09")
        XCTAssertEqual(parsed.entries.first?.title, "屠妖节补休")
        XCTAssertEqual(parsed.entries.first?.kind, .publicHoliday)
        XCTAssertEqual(parsed.summaryNote, "已提取新加坡屠妖节补休")
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
}
