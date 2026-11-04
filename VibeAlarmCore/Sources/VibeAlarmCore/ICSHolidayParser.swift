import Foundation

/// Zero-dependency RFC 5545 iCalendar (`.ics`) parser that extracts public holidays,
/// statutory makeup workdays, and personal leave events into `HolidayCalendarEntry`.
public struct ICSHolidayParser: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = AlarmScheduleEngine.defaultCalendar()) {
        self.calendar = calendar
    }

    public func parse(
        icsContent: String,
        source: HolidayEntrySource = .externalICS
    ) -> [HolidayCalendarEntry] {
        let unfolded = Self.unfoldLines(icsContent)
        let lines = unfolded.components(separatedBy: .newlines)

        var entries: [HolidayCalendarEntry] = []
        var inEvent = false
        var dtStartRaw: String?
        var dtEndRaw: String?
        var summary: String?
        var description: String?
        var categories: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.uppercased() == "BEGIN:VEVENT" {
                inEvent = true
                dtStartRaw = nil
                dtEndRaw = nil
                summary = nil
                description = nil
                categories = nil
                continue
            }

            if line.uppercased() == "END:VEVENT" {
                if inEvent, let startRaw = dtStartRaw, let title = summary, !title.isEmpty {
                    let cleanTitle = Self.unescapeICSText(title)
                    let cleanDesc = Self.unescapeICSText(description ?? "")
                    let descWithNewlines = Self.unescapeICSTextPreservingNewlines(description ?? "")
                    let cleanCat = Self.unescapeICSText(categories ?? "")
                    if let classified = Self.classifyEvent(
                        title: cleanTitle,
                        description: cleanDesc,
                        descriptionWithNewlines: descWithNewlines,
                        categories: cleanCat
                    ) {
                        let dates = expandEventDates(dtStartRaw: startRaw, dtEndRaw: dtEndRaw)
                        for dateStr in dates {
                            entries.append(
                                HolidayCalendarEntry(
                                    date: dateStr,
                                    title: classified.title,
                                    kind: classified.kind,
                                    source: source
                                )
                            )
                        }
                    }
                }
                inEvent = false
                continue
            }

            guard inEvent else { continue }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let propPart = String(line[..<colonIndex]).uppercased()
            let valuePart = String(line[line.index(after: colonIndex)...])
            let propName = propPart.split(separator: ";").first.map(String.init) ?? propPart

            switch propName {
            case "DTSTART":
                dtStartRaw = valuePart
            case "DTEND":
                dtEndRaw = valuePart
            case "SUMMARY":
                summary = valuePart
            case "DESCRIPTION":
                description = valuePart
            case "CATEGORIES":
                categories = valuePart
            default:
                break
            }
        }

        // Deduplicate preserving order
        var seen = Set<String>()
        var unique: [HolidayCalendarEntry] = []
        for entry in entries {
            let key = "\(entry.date)|\(entry.kind.rawValue)|\(entry.title)"
            if seen.insert(key).inserted {
                unique.append(entry)
            }
        }
        return unique.sorted { $0.date < $1.date }
    }

    // MARK: - Classification (Holiday vs Makeup Workday vs Personal Leave)

    public static func classifyEventKind(
        summary: String,
        description: String = "",
        categories: String = ""
    ) -> HolidayEntryKind {
        let combined = "\(summary) \(description) \(categories)".lowercased()

        let makeupKeywords = ["makeup", "make-up", "working weekend", "working saturday", "working sunday"]
        for kw in makeupKeywords where combined.contains(kw) {
            return .makeupWorkday
        }

        let leaveKeywords = [
            "pto", "annual leave", "personal leave", "sick leave", "day off",
            "vacation", "out of office", "ooo"
        ]
        for kw in leaveKeywords where combined.contains(kw) {
            return .personalLeave
        }

        return .publicHoliday
    }

    // MARK: - Per-Event Classification (Google feeds, China statutory feed, keyword fallback)

    /// Resolved classification of a single `VEVENT`: the holiday kind plus the
    /// display title to store. `classifyEvent` returns `nil` when the event must
    /// be excluded entirely (e.g. a Google regional holiday or observance).
    struct ClassifiedHoliday {
        let kind: HolidayEntryKind
        let title: String
    }

    /// Classifies one event using, in priority order: (1) the Google public
    /// holiday DESCRIPTION rule, (2) the China statutory SUMMARY rule, and
    /// (3) the existing keyword classification used by the SG/custom feeds.
    static func classifyEvent(
        title: String,
        description: String,
        descriptionWithNewlines: String,
        categories: String
    ) -> ClassifiedHoliday? {
        // 1. Google public-holiday feeds (English DESCRIPTION).
        switch classifyGoogleDescription(descriptionWithNewlines) {
        case .dayOff:
            return ClassifiedHoliday(kind: .publicHoliday, title: title)
        case .excluded:
            return nil
        case .unrecognized:
            break
        }

        // 2. China statutory feed (CJK SUMMARY, expressed only as Unicode scalars).
        if let china = classifyChineseSummary(title) {
            return china
        }

        // 3. Existing keyword classification (SG/custom/built-in feeds).
        let kind = classifyEventKind(summary: title, description: description, categories: categories)
        return ClassifiedHoliday(kind: kind, title: title)
    }

    // MARK: - Google Public Holiday Feed Rule

    /// Classification of a Google holiday feed event derived from its DESCRIPTION
    /// (after unescaping, with real newlines preserved).
    enum GoogleHolidayDescription {
        /// Nationwide day off: DESCRIPTION is exactly "Public holiday" or begins with "Public holiday" + newline.
        case dayOff
        /// Regional holiday ("Public holiday in <region>") or an observance: not a nationwide day off.
        case excluded
        /// Not a Google-style description; fall back to keyword classification.
        case unrecognized
    }

    /// Applies the Google feed rule. Google feeds mix genuine days off with
    /// regional holidays ("Public holiday in Queensland") and observances
    /// ("Observance ...") that are NOT days off. Only the former are kept.
    static func classifyGoogleDescription(_ description: String) -> GoogleHolidayDescription {
        if description == "Public holiday" || description.hasPrefix("Public holiday\n") {
            return .dayOff
        }
        if description.hasPrefix("Public holiday in ") {
            return .excluded
        }
        if description.hasPrefix("Observance") {
            return .excluded
        }
        return .unrecognized
    }

    // MARK: - China Statutory Feed Rule (NateScarlet holiday-cn)

    /// Chinese holiday names (expressed as Unicode scalars only, zero literal CJK
    /// characters in the repository) mapped to English display titles.
    static let chineseHolidayNames: [(scalars: String, english: String)] = [
        ("\u{5143}\u{65E6}", "New Year's Day"),
        ("\u{6625}\u{8282}", "Spring Festival"),
        ("\u{6E05}\u{660E}\u{8282}", "Qingming Festival"),
        ("\u{52B3}\u{52A8}\u{8282}", "Labour Day"),
        ("\u{7AEF}\u{5348}\u{8282}", "Dragon Boat Festival"),
        ("\u{4E2D}\u{79CB}\u{8282}", "Mid-Autumn Festival"),
        ("\u{56FD}\u{5E86}\u{8282}", "National Day")
    ]

    /// Classifies a China statutory feed SUMMARY. The runtime feed serves Chinese
    /// text; keywords are expressed only as Unicode scalars:
    /// - U+4E0A U+73ED ("work day") prefix -> makeup workday.
    /// - U+5047 U+671F ("holiday period") suffix -> public holiday.
    /// Titles are translated to English for display. Returns `nil` when the
    /// SUMMARY matches neither rule (so other feeds fall through).
    static func classifyChineseSummary(_ summary: String) -> ClassifiedHoliday? {
        let makeupPrefix = "\u{4E0A}\u{73ED}"   // U+4E0A U+73ED, "work day"
        let holidaySuffix = "\u{5047}\u{671F}"  // U+5047 U+671F, "holiday period"

        if summary.hasPrefix(makeupPrefix) {
            if let english = chineseHolidayEnglishName(in: summary) {
                return ClassifiedHoliday(kind: .makeupWorkday, title: "Makeup workday (\(english))")
            }
            return ClassifiedHoliday(kind: .makeupWorkday, title: "Makeup workday")
        }

        if summary.hasSuffix(holidaySuffix) {
            let english = chineseHolidayEnglishName(in: summary) ?? "China public holiday"
            return ClassifiedHoliday(kind: .publicHoliday, title: english)
        }

        return nil
    }

    /// Returns the English name of the first known Chinese holiday keyword found
    /// in `summary`, or `nil` if none is present.
    static func chineseHolidayEnglishName(in summary: String) -> String? {
        for entry in chineseHolidayNames where summary.contains(entry.scalars) {
            return entry.english
        }
        return nil
    }

    // MARK: - Date Parsing & Multi-Day Expansion

    private func expandEventDates(dtStartRaw: String, dtEndRaw: String?) -> [String] {
        guard let startDate = parseICSDate(dtStartRaw) else {
            return []
        }
        let engine = AlarmScheduleEngine(calendar: calendar)
        guard let dtEndRaw, let endDate = parseICSDate(dtEndRaw), endDate > startDate else {
            return [engine.dateString(from: startDate)]
        }

        // In RFC 5545, all-day DTEND is exclusive (e.g., 20261001 to 20261008 means Oct 1..Oct 7).
        var result: [String] = []
        var cursor = startDate
        var safety = 0
        while cursor < endDate && safety < 60 {
            result.append(engine.dateString(from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            safety += 1
        }
        if result.isEmpty {
            result.append(engine.dateString(from: startDate))
        }
        return result
    }

    public func parseICSDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Extract first 8 digits YYYYMMDD
        let digits = trimmed.prefix(8)
        guard digits.count == 8,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)) else {
            return nil
        }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        return calendar.date(from: comps)
    }

    private static func unfoldLines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
    }

    private static func unescapeICSText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like `unescapeICSText` but keeps `\n` / `\N` as real newline characters so
    /// callers (the Google DESCRIPTION rule) can distinguish "Public holiday\n..."
    /// (a day off) from "Public holiday in ..." (a regional holiday).
    private static func unescapeICSTextPreservingNewlines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
