import Foundation

enum ICalendarRenderer {
    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    static func render(events: [CalendarEvent], calendarName: String) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//lol-calendar//LoL Calendar//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escapeText(calendarName))"
        ]

        for event in events {
            let start = utcFormatter.string(from: event.startDate)
            let end = utcFormatter.string(from: event.startDate.addingTimeInterval(2 * 60 * 60))
            lines.append(contentsOf: [
                "BEGIN:VEVENT",
                "UID:\(event.id)@lol-calendar",
                "DTSTAMP:\(start)",
                "DTSTART:\(start)",
                "DTEND:\(end)",
                "SUMMARY:\(escapeText(event.summary))",
                "DESCRIPTION:\(escapeText(event.details))",
                "END:VEVENT"
            ])
        }
        lines.append("END:VCALENDAR")

        return lines.flatMap(foldLine).joined(separator: "\r\n") + "\r\n"
    }

    static func escapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    static func foldLine(_ line: String) -> [String] {
        guard line.utf8.count > 75 else { return [line] }

        var result: [String] = []
        var current = ""
        var currentByteCount = 0
        var byteLimit = 75

        for character in line {
            let characterString = String(character)
            let characterByteCount = characterString.utf8.count
            if currentByteCount + characterByteCount > byteLimit, !current.isEmpty {
                result.append(result.isEmpty ? current : " " + current)
                current = ""
                currentByteCount = 0
                byteLimit = 74
            }
            current.append(character)
            currentByteCount += characterByteCount
        }
        if !current.isEmpty {
            result.append(result.isEmpty ? current : " " + current)
        }
        return result
    }
}

enum CalendarFileWriter {
    static func write(
        events: [CalendarEvent],
        league: LeagueConfig,
        options: CLIOptions,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        do {
            try fileManager.createDirectory(
                at: options.outputDirectory,
                withIntermediateDirectories: true
            )

            var writtenURLs: [URL] = []
            let leagueURL = options.outputDirectory.appendingPathComponent("\(league.slug).ics")
            try writeCalendar(events: events, name: league.displayName, to: leagueURL)
            writtenURLs.append(leagueURL)

            guard options.splitTeams else { return writtenURLs }
            let teamGroups = try groupedByTeam(events: events, selector: options.teamSlug)
            if teamGroups.isEmpty, let requestedTeam = options.teamSlug {
                throw CalendarCLIError.invalidArgument(
                    "team not found: \(requestedTeam)"
                )
            }
            guard !teamGroups.isEmpty else { return writtenURLs }

            let teamsDirectory = options.outputDirectory.appendingPathComponent("teams", isDirectory: true)
            try fileManager.createDirectory(at: teamsDirectory, withIntermediateDirectories: true)
            for group in teamGroups.sorted(by: { $0.filename < $1.filename }) {
                let url = teamsDirectory.appendingPathComponent("\(group.filename).ics")
                try writeCalendar(events: group.events, name: group.team.displayName, to: url)
                writtenURLs.append(url)
            }
            return writtenURLs
        } catch let error as CalendarCLIError {
            throw error
        } catch {
            throw CalendarCLIError.outputFailure(error.localizedDescription)
        }
    }

    private struct TeamGroup {
        let team: CalendarTeam
        let filename: String
        var events: [CalendarEvent]
    }

    private static func groupedByTeam(events: [CalendarEvent], selector: String?) throws -> [TeamGroup] {
        var groups: [String: TeamGroup] = [:]
        var owners: [String: String] = [:]

        for event in events {
            for team in event.teams where selector == nil || team.matches(selector!) {
                let filename = safeFilename(team.displayName)
                guard !filename.isEmpty else {
                    throw CalendarCLIError.invalidResponse("team \(team.slug) has no safe filename")
                }
                if let existingSlug = owners[filename], existingSlug != team.slug.lowercased() {
                    throw CalendarCLIError.invalidResponse(
                        "multiple teams map to the calendar filename \(filename)"
                    )
                }
                owners[filename] = team.slug.lowercased()
                if groups[team.slug.lowercased()] == nil {
                    groups[team.slug.lowercased()] = TeamGroup(team: team, filename: filename, events: [])
                }
                groups[team.slug.lowercased()]?.events.append(event)
            }
        }
        return Array(groups.values)
    }

    static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var output = ""
        var previousWasSeparator = false
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !output.isEmpty {
                output.append("-")
                previousWasSeparator = true
            }
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func writeCalendar(events: [CalendarEvent], name: String, to url: URL) throws {
        let content = ICalendarRenderer.render(events: events, calendarName: name)
        guard let data = content.data(using: .utf8) else {
            throw CalendarCLIError.outputFailure("could not encode UTF-8 calendar")
        }
        try data.write(to: url, options: .atomic)
    }
}
