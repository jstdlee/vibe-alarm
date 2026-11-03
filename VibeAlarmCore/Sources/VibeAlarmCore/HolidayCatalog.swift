import Foundation

// MARK: - Built-in Holiday Calendar Catalog

/// Kind of calendar feed a catalog item points at.
public enum HolidayCatalogKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Google public holiday ICS feed (`en.<slug>#holiday@group.v.calendar.google.com`).
    case google
    /// Dedicated non-Google statutory source that also includes makeup workdays.
    case chinaStatutory
}

/// A single selectable entry in the built-in holiday calendar catalog.
public struct HolidayCatalogItem: Codable, Hashable, Identifiable, Sendable {
    /// ISO 3166-1 alpha-2 country code (uppercase), e.g. "SG", "US", "CN".
    public let isoCode: String
    /// Human-readable country name shown in the UI.
    public let countryName: String
    /// Google calendar slug. Note: these are NOT ISO codes (Japan is `japanese`,
    /// Thailand is `th`). For non-Google items this is a synthetic, unique slug.
    public let googleSlug: String
    /// Which kind of feed this item resolves to.
    public let kind: HolidayCatalogKind

    /// Stable identifier used to remember which catalog item a subscription came from.
    public var id: String { "\(isoCode)-\(googleSlug)" }

    public init(isoCode: String, countryName: String, googleSlug: String, kind: HolidayCatalogKind) {
        self.isoCode = isoCode
        self.countryName = countryName
        self.googleSlug = googleSlug
        self.kind = kind
    }

    /// The ICS feed URL for this catalog item.
    public var icsURL: String {
        switch kind {
        case .chinaStatutory:
            return HolidayCatalog.chinaStatutoryURL
        case .google:
            return "https://calendar.google.com/calendar/ical/en.\(googleSlug)%23holiday%40group.v.calendar.google.com/public/basic.ics"
        }
    }
}

public enum HolidayCatalog {
    /// Dedicated China statutory source (also carries makeup workdays). This is the same
    /// feed already used by `ExternalCalendarSubscription.defaultPresets`.
    public static let chinaStatutoryURL = "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.ics"

    /// Full catalog. The dedicated China statutory source is listed first for CN, and the
    /// plain Google China feed follows as "China (Google)". All Google slugs are verified
    /// (HTTP 200) and must be used exactly as written; the percent-encoding in `icsURL`
    /// (`%23` for `#`, `%40` for `@`) is intentional.
    public static let all: [HolidayCatalogItem] = [
        // Dedicated non-Google source for China: includes statutory makeup workdays.
        HolidayCatalogItem(isoCode: "CN", countryName: "China (Statutory holidays and makeup workdays)", googleSlug: "cn-statutory", kind: .chinaStatutory),
        // Google public holiday feeds (slugs verified HTTP 200).
        HolidayCatalogItem(isoCode: "SG", countryName: "Singapore", googleSlug: "singapore", kind: .google),
        HolidayCatalogItem(isoCode: "US", countryName: "United States", googleSlug: "usa", kind: .google),
        HolidayCatalogItem(isoCode: "GB", countryName: "United Kingdom", googleSlug: "uk", kind: .google),
        HolidayCatalogItem(isoCode: "JP", countryName: "Japan", googleSlug: "japanese", kind: .google),
        HolidayCatalogItem(isoCode: "DE", countryName: "Germany", googleSlug: "german", kind: .google),
        HolidayCatalogItem(isoCode: "FR", countryName: "France", googleSlug: "french", kind: .google),
        HolidayCatalogItem(isoCode: "IN", countryName: "India", googleSlug: "indian", kind: .google),
        HolidayCatalogItem(isoCode: "AU", countryName: "Australia", googleSlug: "australian", kind: .google),
        HolidayCatalogItem(isoCode: "CN", countryName: "China (Google)", googleSlug: "china", kind: .google),
        HolidayCatalogItem(isoCode: "CA", countryName: "Canada", googleSlug: "canadian", kind: .google),
        HolidayCatalogItem(isoCode: "MY", countryName: "Malaysia", googleSlug: "malaysia", kind: .google),
        HolidayCatalogItem(isoCode: "ID", countryName: "Indonesia", googleSlug: "indonesian", kind: .google),
        HolidayCatalogItem(isoCode: "PH", countryName: "Philippines", googleSlug: "philippines", kind: .google),
        HolidayCatalogItem(isoCode: "TH", countryName: "Thailand", googleSlug: "th", kind: .google),
        HolidayCatalogItem(isoCode: "VN", countryName: "Vietnam", googleSlug: "vietnamese", kind: .google),
        HolidayCatalogItem(isoCode: "KR", countryName: "South Korea", googleSlug: "south_korea", kind: .google),
        HolidayCatalogItem(isoCode: "TW", countryName: "Taiwan", googleSlug: "taiwan", kind: .google),
        HolidayCatalogItem(isoCode: "HK", countryName: "Hong Kong", googleSlug: "hong_kong", kind: .google),
        HolidayCatalogItem(isoCode: "NZ", countryName: "New Zealand", googleSlug: "new_zealand", kind: .google),
        HolidayCatalogItem(isoCode: "IE", countryName: "Ireland", googleSlug: "irish", kind: .google),
        HolidayCatalogItem(isoCode: "IT", countryName: "Italy", googleSlug: "italian", kind: .google),
        HolidayCatalogItem(isoCode: "ES", countryName: "Spain", googleSlug: "spain", kind: .google),
        HolidayCatalogItem(isoCode: "NL", countryName: "Netherlands", googleSlug: "dutch", kind: .google),
        HolidayCatalogItem(isoCode: "BE", countryName: "Belgium", googleSlug: "be", kind: .google),
        HolidayCatalogItem(isoCode: "CH", countryName: "Switzerland", googleSlug: "ch", kind: .google),
        HolidayCatalogItem(isoCode: "AT", countryName: "Austria", googleSlug: "austrian", kind: .google),
        HolidayCatalogItem(isoCode: "SE", countryName: "Sweden", googleSlug: "swedish", kind: .google),
        HolidayCatalogItem(isoCode: "NO", countryName: "Norway", googleSlug: "norwegian", kind: .google),
        HolidayCatalogItem(isoCode: "DK", countryName: "Denmark", googleSlug: "danish", kind: .google),
        HolidayCatalogItem(isoCode: "FI", countryName: "Finland", googleSlug: "finnish", kind: .google),
        HolidayCatalogItem(isoCode: "PL", countryName: "Poland", googleSlug: "polish", kind: .google),
        HolidayCatalogItem(isoCode: "CZ", countryName: "Czechia", googleSlug: "czech", kind: .google),
        HolidayCatalogItem(isoCode: "PT", countryName: "Portugal", googleSlug: "portuguese", kind: .google),
        HolidayCatalogItem(isoCode: "GR", countryName: "Greece", googleSlug: "greek", kind: .google),
        HolidayCatalogItem(isoCode: "TR", countryName: "Turkey", googleSlug: "turkish", kind: .google),
        HolidayCatalogItem(isoCode: "RU", countryName: "Russia", googleSlug: "russian", kind: .google),
        HolidayCatalogItem(isoCode: "UA", countryName: "Ukraine", googleSlug: "ukrainian", kind: .google),
        HolidayCatalogItem(isoCode: "BR", countryName: "Brazil", googleSlug: "brazilian", kind: .google),
        HolidayCatalogItem(isoCode: "MX", countryName: "Mexico", googleSlug: "mexican", kind: .google),
        HolidayCatalogItem(isoCode: "AR", countryName: "Argentina", googleSlug: "ar", kind: .google),
        HolidayCatalogItem(isoCode: "CL", countryName: "Chile", googleSlug: "cl", kind: .google),
        HolidayCatalogItem(isoCode: "CO", countryName: "Colombia", googleSlug: "co", kind: .google),
        HolidayCatalogItem(isoCode: "PE", countryName: "Peru", googleSlug: "pe", kind: .google),
        HolidayCatalogItem(isoCode: "SA", countryName: "Saudi Arabia", googleSlug: "saudiarabian", kind: .google),
        HolidayCatalogItem(isoCode: "AE", countryName: "United Arab Emirates", googleSlug: "ae", kind: .google),
        HolidayCatalogItem(isoCode: "IL", countryName: "Israel", googleSlug: "jewish", kind: .google),
        HolidayCatalogItem(isoCode: "ZA", countryName: "South Africa", googleSlug: "sa", kind: .google),
        HolidayCatalogItem(isoCode: "EG", countryName: "Egypt", googleSlug: "eg", kind: .google),
        HolidayCatalogItem(isoCode: "NG", countryName: "Nigeria", googleSlug: "ng", kind: .google),
        HolidayCatalogItem(isoCode: "KE", countryName: "Kenya", googleSlug: "ke", kind: .google),
        HolidayCatalogItem(isoCode: "PK", countryName: "Pakistan", googleSlug: "pk", kind: .google),
        HolidayCatalogItem(isoCode: "BD", countryName: "Bangladesh", googleSlug: "bd", kind: .google),
        HolidayCatalogItem(isoCode: "LK", countryName: "Sri Lanka", googleSlug: "lk", kind: .google)
    ]

    /// Case- and diacritic-insensitive match on country name (prefix or substring) or an
    /// exact ISO code match. An empty query returns the full list sorted by country name.
    public static func search(_ query: String) -> [HolidayCatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sorted(all) }
        let needle = foldedKey(trimmed)
        let matches = all.filter { item in
            if foldedKey(item.isoCode) == needle { return true }
            return foldedKey(item.countryName).contains(needle)
        }
        return sorted(matches)
    }

    /// Maps a catalog item to the closest existing region hint used by the ICS parser.
    public static func regionHint(for item: HolidayCatalogItem) -> HolidayRegionHint {
        switch item.kind {
        case .chinaStatutory: return .cn
        case .google: return .custom
        }
    }

    // MARK: - Helpers

    /// Lowercased, diacritic-insensitive folding for stable comparisons.
    private static func foldedKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
    }

    /// Sorts by country name, keeping the dedicated China statutory source ahead of the
    /// plain Google China feed so CN always presents the makeup-aware source first.
    private static func sorted(_ items: [HolidayCatalogItem]) -> [HolidayCatalogItem] {
        items.sorted { lhs, rhs in
            if lhs.isoCode == rhs.isoCode, lhs.kind != rhs.kind {
                return lhs.kind == .chinaStatutory
            }
            let l = foldedKey(lhs.countryName)
            let r = foldedKey(rhs.countryName)
            if l != r { return l < r }
            return lhs.googleSlug < rhs.googleSlug
        }
    }
}
