import Foundation

// MARK: - BYOK Provider & Configuration

public enum BYOKProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI 兼容 (OpenAI / DeepSeek / OpenRouter / Ollama)"
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
            return "尚未配置 API Key（可在设置页填入 Keychain，或直接使用本地规则解析）。"
        case .invalidEndpointURL:
            return "API Endpoint URL 格式无效。"
        case .httpError(let code, let msg):
            return "LLM 接口返回 HTTP \(code): \(msg)"
        case .emptyModelResponse:
            return "LLM 返回内容为空。"
        case .malformedJSON(let detail):
            return "无法解析 LLM 返回的假期 JSON: \(detail)"
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
        你是一个运行在用户 iPhone 本地的智能假期与调休提取助手。当前参考日期是 \(referenceDateString)。
        请从用户粘贴的邮件、HR通知、政府放假公告或口语指令中提取所有涉及的日期条目，以及文中出现的任何日历订阅链接(.ics/webcal)。
        严格且仅输出如下 JSON 对象（不要输出任何额外解释）：
        {
          "entries": [
            {
              "date": "YYYY-MM-DD",
              "title": "简短名称，如 国庆节 / 年假 / 春节调休补班",
              "kind": "publicHoliday | makeupWorkday | personalLeave"
            }
          ],
          "discoveredCalendarURLs": ["https://example.com/holidays.ics"],
          "summaryNote": "一句话总结提取结果"
        }
        规则：
        1. 如果是一段连续日期（例如 2026年10月26日至10月28日请年假），请展开成每一天独立的 YYYY-MM-DD 条目。
        2. 法定节假日或公共放假用 "publicHoliday"；周末调休上班/补班用 "makeupWorkday"；个人请假/年假/病假/休假用 "personalLeave"。
        3. 如果文中包含 webcal:// 或 .ics 链接，将其放入 discoveredCalendarURLs（webcal:// 自动替换为 https://）。
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
                let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "AI 假期"
                let kindRaw = (item["kind"] as? String) ?? "publicHoliday"
                let kind = HolidayEntryKind(rawValue: kindRaw)
                    ?? ICSHolidayParser.classifyEventKind(summary: title)
                entries.append(
                    HolidayCalendarEntry(
                        date: date,
                        title: title.isEmpty ? "AI 假期" : title,
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

        let summaryNote = (obj["summaryNote"] as? String) ?? "已提取 \(entries.count) 条假期/调休记录"
        return BYOKExtractionResult(
            entries: entries.sorted { $0.date < $1.date },
            discoveredCalendarURLs: urls,
            summaryNote: summaryNote
        )
    }

    // MARK: - Deterministic Offline Natural-Language & Link Parser (零网络兜底解析)

    public func parseLocally(
        text: String,
        referenceDate: Date = Date()
    ) -> BYOKExtractionResult {
        let engine = AlarmScheduleEngine(calendar: calendar)
        let refYear = calendar.component(.year, from: referenceDate)
        let discoveredURLs = Self.extractCalendarURLs(from: text)

        var entries: [HolidayCalendarEntry] = []
        let clauses = text.components(separatedBy: CharacterSet(charactersIn: "，,。；;\n"))

        for rawClause in clauses {
            let clause = rawClause.trimmingCharacters(in: .whitespacesAndNewlines)
            if clause.isEmpty { continue }

            let kind = ICSHolidayParser.classifyEventKind(summary: clause)
            let title = Self.inferShortTitle(from: clause, kind: kind)

            // 1. Check relative dates ("今天", "明天", "后天")
            if clause.contains("明天") || clause.contains("明日") {
                if let d = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) {
                    entries.append(HolidayCalendarEntry(date: engine.dateString(from: d), title: title, kind: kind, source: .byokLLM))
                }
            }
            if clause.contains("后天") {
                if let d = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: referenceDate)) {
                    entries.append(HolidayCalendarEntry(date: engine.dateString(from: d), title: title, kind: kind, source: .byokLLM))
                }
            }

            // 2. Check ISO range: YYYY-MM-DD 到/至/~ YYYY-MM-DD
            let isoRangeDates = expandISODateRanges(in: clause)
            for dStr in isoRangeDates {
                entries.append(HolidayCalendarEntry(date: dStr, title: title, kind: kind, source: .byokLLM))
            }

            // 3. Check Chinese month/day range: M月D日-M月D日 or M月D日到D日
            let cnDates = expandChineseMonthDayMentions(in: clause, defaultYear: refYear)
            for dStr in cnDates {
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
            ? "未识别到明确的日期，请尝试输入如“10月26日到28日休年假，10月31日补班”"
            : "本地识别出 \(unique.count) 个日期条目" + (discoveredURLs.isEmpty ? "" : " 及 \(discoveredURLs.count) 个日历链接")

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

        // Range pattern: YYYY-MM-DD (到|至|-|~|to) YYYY-MM-DD
        let rangePattern = #"(\d{4}-\d{2}-\d{2})\s*(?:到|至|~|—|-|to)\s*(\d{4}-\d{2}-\d{2})"#
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

    private func expandChineseMonthDayMentions(in text: String, defaultYear: Int) -> [String] {
        let engine = AlarmScheduleEngine(calendar: calendar)
        var results: [String] = []

        // Pattern A: (YYYY年)?M月D日(到|至|-|~)(M月)?D日
        let rangePattern = #"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})[日号]\s*(?:到|至|~|—|-)\s*(?:(\d{1,2})月)?(\d{1,2})[日号]"#
        if let regex = try? NSRegularExpression(pattern: rangePattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                let year = Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? defaultYear
                guard let rM1 = Range(match.range(at: 2), in: text),
                      let rD1 = Range(match.range(at: 3), in: text),
                      let rD2 = Range(match.range(at: 5), in: text),
                      let m1 = Int(text[rM1]),
                      let d1 = Int(text[rD1]),
                      let d2 = Int(text[rD2]) else { continue }
                let m2 = Range(match.range(at: 4), in: text).flatMap { Int(text[$0]) } ?? m1

                let s1 = String(format: "%04d-%02d-%02d", year, m1, d1)
                let s2 = String(format: "%04d-%02d-%02d", year, m2, d2)
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

        // Pattern B: Single (YYYY年)?M月D日
        let singlePattern = #"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})[日号]"#
        if let regex = try? NSRegularExpression(pattern: singlePattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                let year = Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? defaultYear
                guard let rM = Range(match.range(at: 2), in: text),
                      let rD = Range(match.range(at: 3), in: text),
                      let m = Int(text[rM]),
                      let d = Int(text[rD]) else { continue }
                let s = String(format: "%04d-%02d-%02d", year, m, d)
                if Self.isValidDateString(s) && !results.contains(s) {
                    results.append(s)
                }
            }
        }

        return results
    }

    private static func inferShortTitle(from clause: String, kind: HolidayEntryKind) -> String {
        switch kind {
        case .makeupWorkday:
            return "调休补班"
        case .personalLeave:
            if clause.contains("年假") { return "个人年假" }
            if clause.contains("病假") { return "病假休息" }
            return "个人休假"
        case .publicHoliday:
            let knownNames = ["元旦", "春节", "清明", "劳动节", "端午", "中秋", "国庆", "屠妖节", "Deepavali", "圣诞", "公共假期"]
            for name in knownNames where clause.contains(name) {
                return name
            }
            return "公共假期"
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
