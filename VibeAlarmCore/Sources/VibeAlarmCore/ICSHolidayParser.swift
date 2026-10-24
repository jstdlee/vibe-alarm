import Foundation

/// Zero-dependency RFC 5545 iCalendar (`.ics`) parser that extracts public holidays,
/// statutory makeup workdays (调休补班), and personal leave events into `HolidayCalendarEntry`.
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
                    let cleanCat = Self.unescapeICSText(categories ?? "")
                    let kind = Self.classifyEventKind(
                        summary: cleanTitle,
                        description: cleanDesc,
                        categories: cleanCat
                    )
                    let dates = expandEventDates(dtStartRaw: startRaw, dtEndRaw: dtEndRaw)
                    for dateStr in dates {
                        entries.append(
                            HolidayCalendarEntry(
                                date: dateStr,
                                title: cleanTitle,
                                kind: kind,
                                source: source
                            )
                        )
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

        let makeupKeywords = [
            "补班", "调休上班", "调休补班", "上班", "工作日", "make-up workday", "makeup workday", "working day"
        ]
        for kw in makeupKeywords where combined.contains(kw) {
            // Avoid misclassifying "不上班"
            if !combined.contains("不上班") {
                return .makeupWorkday
            }
        }

        let leaveKeywords = [
            "请假", "年假", "病假", "事假", "个人休假", "pto", "annual leave", "personal leave", "vacation", "out of office", "ooo"
        ]
        for kw in leaveKeywords where combined.contains(kw) {
            return .personalLeave
        }

        return .publicHoliday
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
}
