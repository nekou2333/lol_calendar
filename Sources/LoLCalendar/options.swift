import Foundation

struct CLIOptions: Equatable, Sendable {
    var year: Int
    var outputDirectory: URL
    var leagueSlugs: [String]
    var splitTeams: Bool
    var teamSlug: String?

    static let defaultLeagueSlugs = ["lpl"]
    static let usage = """
    Usage: swift run LoLCalendar [options]

    Options:
        --year YYYY          Calendar year in UTC (default: current year)
        --output PATH        Output directory (default: docs)
        --leagues LIST       Comma-separated leagues (currently: lpl)
        --split-teams        Also generate one calendar per team
        --team CODE          With --split-teams, only generate this team
        -h, --help           Show this help

    Environment:
        CITO_API_KEY         Required Cito API key
    """

    static func parse(_ arguments: [String], currentDate: Date = Date()) throws -> CLIOptions {
        var year = YearInterval.currentYear(at: currentDate)
        var output = URL(fileURLWithPath: "docs", isDirectory: true)
        var leagueSlugs = defaultLeagueSlugs
        var splitTeams = false
        var teamSlug: String?

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--year":
                let value = try requiredValue(after: argument, at: &index, in: arguments)
                guard let parsedYear = Int(value), (1 ... 9999).contains(parsedYear) else {
                    throw CalendarCLIError.invalidArgument("--year requires a value between 1 and 9999")
                }
                year = parsedYear
            case "--output":
                let value = try requiredValue(after: argument, at: &index, in: arguments)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else {
                    throw CalendarCLIError.invalidArgument("--output cannot be empty")
                }
                output = URL(fileURLWithPath: value, isDirectory: true)
            case "--leagues":
                let value = try requiredValue(after: argument, at: &index, in: arguments)
                leagueSlugs = value.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                guard !leagueSlugs.isEmpty else {
                    throw CalendarCLIError.invalidArgument("--leagues cannot be empty")
                }
                var seen = Set<String>()
                leagueSlugs = leagueSlugs.filter { seen.insert($0).inserted }
            case "--split-teams":
                splitTeams = true
            case "--team":
                let value = try requiredValue(after: argument, at: &index, in: arguments)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else {
                    throw CalendarCLIError.invalidArgument("--team cannot be empty")
                }
                teamSlug = value
            case "-h", "--help":
                throw CalendarCLIError.help
            default:
                throw CalendarCLIError.invalidArgument("unknown argument: \(argument)")
            }
            index += 1
        }

        let unsupported = leagueSlugs.filter { LeagueConfig.defaults[$0] == nil }
        guard unsupported.isEmpty else {
            throw CalendarCLIError.invalidArgument(
                "unsupported league(s): \(unsupported.joined(separator: ", ")); currently supported: lpl"
            )
        }
        if teamSlug != nil, !splitTeams {
            throw CalendarCLIError.invalidArgument("--team requires --split-teams")
        }

        return CLIOptions(
            year: year,
            outputDirectory: output,
            leagueSlugs: leagueSlugs,
            splitTeams: splitTeams,
            teamSlug: teamSlug
        )
    }

    private static func requiredValue(
        after option: String,
        at index: inout Int,
        in arguments: [String]
    ) throws -> String {
        index += 1
        guard index < arguments.count, !arguments[index].hasPrefix("--") else {
            throw CalendarCLIError.invalidArgument("\(option) requires a value")
        }
        return arguments[index]
    }
}
