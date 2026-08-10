import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct LoLCalendarCommand {
    static func main() async {
        do {
            let options = try CLIOptions.parse(CommandLine.arguments)
            let apiKey = try Environment.required("CITO_API_KEY")
            guard let baseURL = URL(string: "https://api.citoapi.com/api/v1") else {
                throw CalendarCLIError.invalidURL
            }
            let client = CitoClient(baseURL: baseURL, apiKey: apiKey)
            let writtenURLs = try await generate(options: options, client: client)
            for url in writtenURLs {
                print("Generated \(url.path)")
            }
        } catch CalendarCLIError.help {
            print(CLIOptions.usage)
        } catch {
            writeToStandardError("Error: \(error.localizedDescription)\n")
            exit(EXIT_FAILURE)
        }
    }

    static func generate(
        options: CLIOptions,
        client: some CitoScheduleFetching
    ) async throws -> [URL] {
        let interval = YearInterval(year: options.year)
        var writtenURLs: [URL] = []

        for leagueSlug in options.leagueSlugs {
            guard let league = LeagueConfig.defaults[leagueSlug] else {
                throw CalendarCLIError.invalidArgument("unsupported league: \(leagueSlug)")
            }
            let rawEvents = try await client.fetchSchedule(
                leagueID: league.leagueID,
                from: interval.startDateString,
                to: interval.endDateString
            )
            let events = try ScheduleEventMapper.map(rawEvents)
            writtenURLs.append(
                contentsOf: try CalendarFileWriter.write(
                    events: events,
                    league: league,
                    options: options
                )
            )
        }
        return writtenURLs
    }

    private static func writeToStandardError(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}

enum Environment {
    static func required(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
            throw CalendarCLIError.missingEnvironment(key)
        }
        return value
    }
}
