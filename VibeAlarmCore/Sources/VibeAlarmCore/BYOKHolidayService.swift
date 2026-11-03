import Foundation

// MARK: - BYOK Provider & Configuration

public enum BYOKProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI Compatible (OpenAI / DeepSeek / OpenRouter / Ollama)"
        case .anthropic:
            return "Anthropic Claude (/v1/messages)"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .openAICompatible:
            return "https://api.openai.com/v1/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAICompatible:
            return "gpt-4o-mini"
        case .anthropic:
            return "claude-3-5-haiku-latest"
        }
    }
}

public struct BYOKConfiguration: Codable, Equatable, Sendable {
    public var provider: BYOKProviderKind
    public var endpointURL: String
    public var model: String

    public init(
        provider: BYOKProviderKind = .openAICompatible,
        endpointURL: String = BYOKProviderKind.openAICompatible.defaultEndpoint,
        model: String = BYOKProviderKind.openAICompatible.defaultModel
    ) {
        self.provider = provider
        self.endpointURL = endpointURL
        self.model = model
    }
}

public struct BYOKExtractionResult: Codable, Equatable, Sendable {
    public var entries: [HolidayCalendarEntry]
    public var discoveredCalendarURLs: [String]
    public var summaryNote: String

    public init(
        entries: [HolidayCalendarEntry],
        discoveredCalendarURLs: [String] = [],
        summaryNote: String = ""
    ) {
        self.entries = entries
        self.discoveredCalendarURLs = discoveredCalendarURLs
        self.summaryNote = summaryNote
    }
}

public enum BYOKServiceError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidEndpointURL
    case httpError(statusCode: Int, message: String)
    case emptyModelResponse
    case malformedJSON(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured yet (set one in Settings, or use the on-device offline parser)."
        case .invalidEndpointURL:
            return "The API endpoint URL is not valid."
        case .httpError(let code, let msg):
            return "The LLM endpoint returned HTTP \(code): \(msg)"
        case .emptyModelResponse:
            return "The LLM response was empty."
        case .malformedJSON(let detail):
            return "Could not parse the holiday JSON returned by the LLM: \(detail)"
        }
    }
}

// MARK: - BYOK Holiday Extraction Service (100% Direct On-Device -> User's LLM Endpoint)

public struct BYOKHolidayService: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = AlarmScheduleEngine.defaultCalendar()) {
        self.calendar = calendar
    }

    public static func systemPrompt(referenceDateString: String) -> String {
        """
        You are a holiday and makeup-workday extraction assistant running entirely on the user's iPhone. The current reference date is \(referenceDateString).
        Extract every date mentioned in the pasted email, HR notice, government holiday announcement, or spoken instruction, along with any calendar subscription links (.ics/webcal) found in the text.
        Respond with ONLY the following JSON object (no extra commentary):
        {
          "entries": [
            {
              "date": "YYYY-MM-DD",
              "title": "Short name, e.g. National Day / Annual Leave / Makeup Workday",
              "kind": "publicHoliday | makeupWorkday | personalLeave"
            }
          ],
          "discoveredCalendarURLs": ["https://example.com/holidays.ics"],
          "summaryNote": "One-sentence summary of what was extracted"
        }
        Rules:
        1. If a continuous date range is mentioned (e.g. "October 26 to October 28, 2026 annual leave"), expand it into one entry per day.
        2. Statutory public holidays use "publicHoliday"; a weekend makeup workday use "makeupWorkday"; personal leave, annual leave, or sick leave use "personalLeave".
        3. If the text contains a webcal:// or .ics link, include it in discoveredCalendarURLs (replace webcal:// with https://).
        """
    }

    public func buildURLRequest(
        userText: String,
        config: BYOKConfiguration,
        apiKey: String,
        referenceDate: Date = Date()
    ) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw BYOKServiceError.missingAPIKey
        }
        guard let url = URL(string: config.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            throw BYOKServiceError.invalidEndpointURL
        }

        let engine = AlarmScheduleEngine(calendar: calendar)
        let refDateStr = engine.dateString(from: referenceDate)
        let sysPrompt = Self.systemPrompt(referenceDateString: refDateStr)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch config.provider {
        case .openAICompatible:
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": config.model,
                "temperature": 0.1,
                "messages": [
                    ["role": "system", "content": sysPrompt],
                    ["role": "user", "content": userText]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

        case .anthropic:
            request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": config.model,
                "max_tokens": 1024,
                "system": sysPrompt,
                "messages": [
                    ["role": "user", "content": userText]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    public func extractHolidaysViaLLM(
        userText: String,
        config: BYOKConfiguration,
        apiKey: String,
        referenceDate: Date = Date(),
        session: URLSession = .shared
    ) async throws -> BYOKExtractionResult {
        let request = try buildURLRequest(
            userText: userText,
            config: config,
            apiKey: apiKey,
            referenceDate: referenceDate
        )
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw BYOKServiceError.httpError(statusCode: http.statusCode, message: String(bodyText.prefix(240)))
        }
        return try parseLLMResponseData(data, provider: config.provider, fallbackText: userText)
    }

    public func parseLLMResponseData(
        _ data: Data,
        provider: BYOKProviderKind,
        fallbackText: String = ""
    ) throws -> BYOKExtractionResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BYOKServiceError.malformedJSON("Response is not a JSON object")
        }

        var contentText: String?
        switch provider {
        case .openAICompatible:
            if let choices = root["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                contentText = content
            }
        case .anthropic:
            if let contentArr = root["content"] as? [[String: Any]],
               let first = contentArr.first,
               let text = first["text"] as? String {
                contentText = text
            }
        }

        guard let rawContent = contentText, !rawContent.isEmpty else {
            throw BYOKServiceError.emptyModelResponse
        }

        return try parseStructuredJSONContent(rawContent, sourceTextForURLs: fallbackText)
    }

    public func parseStructuredJSONContent(
        _ rawContent: String,
        sourceTextForURLs: String = ""
    ) throws -> BYOKExtractionResult {
        let cleaned = Self.extractJSONBlock(from: rawContent)
        guard let jsonData = cleaned.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw BYOKServiceError.malformedJSON("Failed to decode inner JSON payload")
        }

        var entries: [HolidayCalendarEntry] = []
        if let rawEntries = obj["entries"] as? [[String: Any]] {
            for item in rawEntries {
                guard let date = item["date"] as? String,
                      Self.isValidDateString(date) else { continue }
                let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "AI Holiday"
                let kindRaw = (item["kind"] as? String) ?? "publicHoliday"
                let kind = HolidayEntryKind(rawValue: kindRaw)
                    ?? ICSHolidayParser.classifyEventKind(summary: title)
                entries.append(
                    HolidayCalendarEntry(
                        date: date,
                        title: title.isEmpty ? "AI Holiday" : title,
                        kind: kind,
                        source: .byokLLM
                    )
                )
            }
        }

        var urls: [String] = (obj["discoveredCalendarURLs"] as? [String]) ?? []
        let regexURLs = Self.extractCalendarURLs(from: sourceTextForURLs)
        for u in regexURLs where !urls.contains(u) {
            urls.append(u)
        }

        let summaryNote = (obj["summaryNote"] as? String) ?? "Extracted \(entries.count) holiday/workday entries"
        return BYOKExtractionResult(
            entries: entries.sorted { $0.date < $1.date },
            discoveredCalendarURLs: urls,
            summaryNote: summaryNote
        )
    }

    // MARK: - Deterministic Offline Natural-Language & Link Parser (Zero-Network Fallback)

    public func parseLocally(
        text: String,
        referenceDate: Date = Date()
    ) -> BYOKExtractionResult {
        let engine = AlarmScheduleEngine(calendar: calendar)
        let refYear = calendar.component(.year, from: referenceDate)
        let discoveredURLs = Self.extractCalendarURLs(from: text)

        var entries: [HolidayCalendarEntry] = []
        // Split on sentence/line boundaries only (not ".") so URLs like ".ics" stay intact.
        let clauses = text.components(separatedBy: CharacterSet(charactersIn: ";\n"))

        for rawClause in clauses {
            let clause = rawClause.trimmingCharacters(in: .whitespacesAndNewlines)
            if clause.isEmpty { continue }

            let lowerClause = clause.lowercased()
            let kind = ICSHolidayParser.classifyEventKind(summary: clause)
            let title = Self.inferShortTitle(from: lowerClause, kind: kind)

            // 1. Check relative dates ("today", "tomorrow", "day after tomorrow")
            if lowerClause.contains("day after tomorrow") {
                if let d = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: referenceDate)) {
                    entries.append(HolidayCalendarEntry(date: engine.dateString(from: d), title: title, kind: kind, source: .byokLLM))
                }
            } else if lowerClause.contains("tomorrow") {
                if let d = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) {
                    entries.append(HolidayCalendarEntry(date: engine.dateString(from: d), title: title, kind: kind, source: .byokLLM))
                }
            }

            // 2. Check ISO range: YYYY-MM-DD to/through/~/- YYYY-MM-DD
            let isoRangeDates = expandISODateRanges(in: clause)
            for dStr in isoRangeDates {
                entries.append(HolidayCalendarEntry(date: dStr, title: title, kind: kind, source: .byokLLM))
            }

            // 3. Check English month/day mentions: "October 26 to 28, 2026" or "October 31, 2026"
            let monthDayDates = expandEnglishMonthDayMentions(in: clause, defaultYear: refYear)
            for dStr in monthDayDates {
                entries.append(HolidayCalendarEntry(date: dStr, title: title, kind: kind, source: .byokLLM))
            }
        }

        // Deduplicate by (date, kind)
        var seen = Set<String>()
        var unique: [HolidayCalendarEntry] = []
        for entry in entries {
            let key = "\(entry.date)|\(entry.kind.rawValue)"
            if seen.insert(key).inserted {
                unique.append(entry)
            }
        }

        let summary = unique.isEmpty && discoveredURLs.isEmpty
            ? "No clear dates recognized. Try input like \"Annual leave Oct 26 to 28, makeup Saturday Oct 31.\""
            : "Parsed \(unique.count) local date entries" + (discoveredURLs.isEmpty ? "" : " and \(discoveredURLs.count) calendar link(s)")

        return BYOKExtractionResult(
            entries: unique.sorted { $0.date < $1.date },
            discoveredCalendarURLs: discoveredURLs,
            summaryNote: summary
        )
    }

    // MARK: - Helpers

    public static func extractCalendarURLs(from text: String) -> [String] {
        let pattern = #"(?:https?|webcal)://[^\s"'<>]+(?:\.ics|/ical[^\s"'<>]*|/calendar[^\s"'<>]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var urls: [String] = []
        for m in matches {
            guard let r = Range(m.range, in: text) else { continue }
            var urlStr = String(text[r])
            if urlStr.lowercased().hasPrefix("webcal://") {
                urlStr = "https://" + urlStr.dropFirst("webcal://".count)
            }
            if !urls.contains(urlStr) {
                urls.append(urlStr)
            }
        }
        return urls
    }

    private func expandISODateRanges(in text: String) -> [String] {
        let engine = AlarmScheduleEngine(calendar: calendar)
        var results: [String] = []

        // Range pattern: YYYY-MM-DD (to|through|~|–|-) YYYY-MM-DD
        let rangePattern = #"(\d{4}-\d{2}-\d{2})\s*(?:to|through|~|–|-)\s*(\d{4}-\d{2}-\d{2})"#
        if let regex = try? NSRegularExpression(pattern: rangePattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                if let r1 = Range(match.range(at: 1), in: text),
                   let r2 = Range(match.range(at: 2), in: text),
                   let start = engine.date(from: String(text[r1])),
                   let end = engine.date(from: String(text[r2])),
                   start <= end {
                    var cur = start
                    var count = 0
                    while cur <= end && count < 45 {
                        results.append(engine.dateString(from: cur))
                        guard let next = calendar.date(byAdding: .day, value: 1, to: cur) else { break }
                        cur = next
                        count += 1
                    }
                }
            }
        }

        // Single ISO dates
        let singlePattern = #"\b(\d{4}-\d{2}-\d{2})\b"#
        if let regex = try? NSRegularExpression(pattern: singlePattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                if let r = Range(match.range(at: 1), in: text) {
                    let s = String(text[r])
                    if Self.isValidDateString(s) && !results.contains(s) {
                        results.append(s)
                    }
                }
            }
        }
        return results
    }

    private static let monthPattern = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    private static func monthNumber(from matchedName: String) -> Int? {
        monthNumbers[String(matchedName.lowercased().prefix(3))]
    }

    private func expandEnglishMonthDayMentions(in text: String, defaultYear: Int) -> [String] {
        let engine = AlarmScheduleEngine(calendar: calendar)
        var results: [String] = []

        // Pattern A: <Month> <Day>[, <Year>] (to|through|-|–) [<Month>] <Day>[, <Year>]
        let rangePattern = #"(?i)(\#(Self.monthPattern))\s+(\d{1,2})(?:,?\s+(\d{4}))?\s*(?:to|through|-|–)\s*(?:(\#(Self.monthPattern))\s+)?(\d{1,2})(?:,?\s+(\d{4}))?"#
        if let regex = try? NSRegularExpression(pattern: rangePattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                guard let rMonth1 = Range(match.range(at: 1), in: text),
                      let rDay1 = Range(match.range(at: 2), in: text),
                      let month1 = Self.monthNumber(from: String(text[rMonth1])),
                      let day1 = Int(text[rDay1]) else { continue }
                let month2: Int
                if let rMonth2 = Range(match.range(at: 4), in: text), let m2 = Self.monthNumber(from: String(text[rMonth2])) {
                    month2 = m2
                } else {
                    month2 = month1
                }
                guard let rDay2 = Range(match.range(at: 5), in: text), let day2 = Int(text[rDay2]) else { continue }
                let year1 = Range(match.range(at: 3), in: text).flatMap { Int(text[$0]) }
                let year2 = Range(match.range(at: 6), in: text).flatMap { Int(text[$0]) }
                let year = year1 ?? year2 ?? defaultYear

                let s1 = String(format: "%04d-%02d-%02d", year, month1, day1)
                let s2 = String(format: "%04d-%02d-%02d", year, month2, day2)
                if let start = engine.date(from: s1), let end = engine.date(from: s2), start <= end {
                    var cur = start
                    var count = 0
                    while cur <= end && count < 45 {
                        results.append(engine.dateString(from: cur))
                        guard let next = calendar.date(byAdding: .day, value: 1, to: cur) else { break }
                        cur = next
                        count += 1
                    }
                }
            }
        }

        // Pattern B: Single <Month> <Day>[, <Year>]
        let singlePattern = #"(?i)(\#(Self.monthPattern))\s+(\d{1,2})(?:,?\s+(\d{4}))?"#
        if let regex = try? NSRegularExpression(pattern: singlePattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                guard let rMonth = Range(match.range(at: 1), in: text),
                      let rDay = Range(match.range(at: 2), in: text),
                      let month = Self.monthNumber(from: String(text[rMonth])),
                      let day = Int(text[rDay]) else { continue }
                let year = Range(match.range(at: 3), in: text).flatMap { Int(text[$0]) } ?? defaultYear
                let s = String(format: "%04d-%02d-%02d", year, month, day)
                if Self.isValidDateString(s) && !results.contains(s) {
                    results.append(s)
                }
            }
        }

        return results
    }

    private static func inferShortTitle(from lowerClause: String, kind: HolidayEntryKind) -> String {
        switch kind {
        case .makeupWorkday:
            return "Makeup Workday"
        case .personalLeave:
            if lowerClause.contains("annual leave") { return "Annual Leave" }
            if lowerClause.contains("sick leave") { return "Sick Leave" }
            return "Personal Leave"
        case .publicHoliday:
            let knownNames = [
                "new year", "lunar new year", "qingming", "labor day", "dragon boat",
                "mid-autumn", "national day", "deepavali", "christmas", "public holiday"
            ]
            for name in knownNames where lowerClause.contains(name) {
                return name.capitalized
            }
            return "Public Holiday"
        }
    }

    public static func extractJSONBlock(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            return String(trimmed[firstBrace...lastBrace])
        }
        return trimmed
    }

    public static func isValidDateString(_ str: String) -> Bool {
        let parts = str.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              let y = Int(parts[0]), (2020...2100).contains(y),
              let m = Int(parts[1]), (1...12).contains(m),
              let d = Int(parts[2]), (1...31).contains(d) else {
            return false
        }
        return true
    }
}
