import Foundation

struct YearInterval: Equatable, Sendable {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    let year: Int

    var startDateString: String { "\(year)-01-01" }
    var endDateString: String { "\(year)-12-31" }

    static func currentYear(at date: Date) -> Int {
        utcCalendar.component(.year, from: date)
    }
}

enum CalendarCLIError: LocalizedError, Equatable {
    case help
    case invalidArgument(String)
    case missingEnvironment(String)
    case invalidURL
    case badHTTPSStatus(Int)
    case invalidResponse(String)
    case outputFailure(String)

    var errorDescription: String? {
        switch self {
        case .help:
            return CLIOptions.usage
        case .invalidArgument(let message):
            return message
        case .missingEnvironment(let key):
            return "missing required environment variable: \(key)"
        case .invalidURL:
            return "failed to build Cito API URL"
        case .badHTTPSStatus(let status):
            return "Cito API returned HTTP \(status)"
        case .invalidResponse(let message):
            return "invalid Cito API response: \(message)"
        case .outputFailure(let message):
            return "failed to write calendar output: \(message)"
        }
    }
}

struct LeagueConfig: Equatable, Sendable {
    let slug: String
    let leagueID: String
    let displayName: String

    static let defaults: [String: LeagueConfig] = [
        "lpl": LeagueConfig(slug: "lpl", leagueID: "lol-lpl", displayName: "LPL")
    ]
}

struct LeagueScheduleResponse: Decodable, Equatable, Sendable {
    let success: Bool
    let data: LeagueScheduleData?
}

struct LeagueScheduleData: Decodable, Equatable, Sendable {
    let leagueID: String
    let leagueName: String
    let total: Int
    let count: Int
    let limit: Int
    let offset: Int
    let events: [RawScheduleEvent]
    let hasMore: Bool
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case leagueID = "leagueId"
        case leagueName
        case total
        case count
        case limit
        case offset
        case events
        case hasMore
        case nextOffset
    }
}

struct RawScheduleEvent: Decodable, Equatable, Sendable {
    let startTime: String
    let state: String
    let type: String
    let blockName: String
    let matchID: String
    let tournamentID: String
    let teams: [RawScheduleTeam]
    let strategy: RawMatchStrategy
    let leagueID: String
    let leagueName: String
    let coverage: RawCoverage?

    enum CodingKeys: String, CodingKey {
        case startTime
        case state
        case type
        case blockName
        case matchID = "matchId"
        case tournamentID = "tournamentId"
        case teams
        case strategy
        case leagueID = "leagueId"
        case leagueName
        case coverage
    }
}

struct RawScheduleTeam: Decodable, Equatable, Sendable {
    let slug: String
    let name: String
    let code: String
    let imageURL: String?
    let score: Int

    enum CodingKeys: String, CodingKey {
        case slug
        case name
        case code
        case imageURL = "imageUrl"
        case score
    }
}

struct RawMatchStrategy: Decodable, Equatable, Sendable {
    let type: String
    let count: Int
}

struct RawCoverage: Decodable, Equatable, Sendable {
    let gamesCount: Int
    let expectedGames: Int
    let gamesReady: Bool
    let playerStatsReady: Bool
}

struct CalendarTeam: Equatable, Hashable, Sendable {
    let slug: String
    let code: String
    let name: String

    var displayName: String {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCode.isEmpty ? name.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedCode
    }

    func matches(_ selector: String) -> Bool {
        let normalized = selector.lowercased()
        return slug.lowercased() == normalized || code.lowercased() == normalized
    }
}

struct CalendarEvent: Equatable, Sendable {
    let id: String
    let startDate: Date
    let summary: String
    let details: String
    let teams: [CalendarTeam]
}

enum ScheduleEventMapper {
    static func map(_ rawEvents: [RawScheduleEvent]) throws -> [CalendarEvent] {
        let parserWithFractionalSeconds = ISO8601DateFormatter()
        parserWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]

        var mapped: [CalendarEvent] = []
        for rawEvent in rawEvents where rawEvent.type.lowercased() == "match" {
            let matchID = rawEvent.matchID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !matchID.isEmpty else {
                throw CalendarCLIError.invalidResponse("match event is missing matchId")
            }
            guard rawEvent.teams.count == 2 else {
                throw CalendarCLIError.invalidResponse("match \(matchID) must contain exactly two teams")
            }
            guard let startDate = parserWithFractionalSeconds.date(from: rawEvent.startTime)
                    ?? parser.date(from: rawEvent.startTime) else {
                throw CalendarCLIError.invalidResponse("match \(matchID) has invalid startTime")
            }

            let teams = try rawEvent.teams.map { rawTeam -> CalendarTeam in
                let name = rawTeam.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let code = rawTeam.code.trimmingCharacters(in: .whitespacesAndNewlines)
                let slug = rawTeam.slug.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !slug.isEmpty, !(code.isEmpty && name.isEmpty) else {
                    throw CalendarCLIError.invalidResponse("match \(matchID) contains an invalid team")
                }
                return CalendarTeam(slug: slug, code: code, name: name)
            }

            var summary = "\(teams[0].displayName) vs \(teams[1].displayName)"
            if rawEvent.state.lowercased() == "completed" {
                summary += " · \(rawEvent.teams[0].score):\(rawEvent.teams[1].score)"
            }

            let leagueName = rawEvent.leagueName.trimmingCharacters(in: .whitespacesAndNewlines)
            let blockName = rawEvent.blockName.trimmingCharacters(in: .whitespacesAndNewlines)
            let details = [leagueName.isEmpty ? "LPL" : leagueName, blockName, "BO\(rawEvent.strategy.count)"]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            mapped.append(
                CalendarEvent(id: matchID, startDate: startDate, summary: summary, details: details, teams: teams)
            )
        }

        let sorted = mapped.sorted {
            if $0.startDate == $1.startDate { return $0.id < $1.id }
            return $0.startDate < $1.startDate
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.id).inserted }
    }
}
