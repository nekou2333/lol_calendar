import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LoLCalendar

final class CLIOptionsTests: XCTestCase {
    func testDefaultsUseCurrentUTCYearAndDocs() throws {
        let date = ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z")!
        let options = try CLIOptions.parse(["LoLCalendar"], currentDate: date)

        XCTAssertEqual(options.year, 2026)
        XCTAssertEqual(options.outputDirectory.path, URL(fileURLWithPath: "docs").path)
        XCTAssertEqual(options.leagueSlugs, ["lpl"])
        XCTAssertFalse(options.splitTeams)
        XCTAssertNil(options.teamSlug)
    }

    func testParsesAllSupportedOptions() throws {
        let options = try CLIOptions.parse([
            "LoLCalendar", "--year", "2025", "--output", "/tmp/calendars",
            "--leagues", "LPL,lpl", "--split-teams", "--team", "EDG"
        ])

        XCTAssertEqual(options.year, 2025)
        XCTAssertEqual(options.outputDirectory.path, "/tmp/calendars")
        XCTAssertEqual(options.leagueSlugs, ["lpl"])
        XCTAssertTrue(options.splitTeams)
        XCTAssertEqual(options.teamSlug, "EDG")
    }

    func testTeamRequiresSplitTeams() {
        XCTAssertThrowsError(try CLIOptions.parse(["LoLCalendar", "--team", "EDG"])) { error in
            XCTAssertEqual(error as? CalendarCLIError, .invalidArgument("--team requires --split-teams"))
        }
    }

    func testRejectsUnsupportedLeagueAndMissingValues() {
        XCTAssertThrowsError(try CLIOptions.parse(["LoLCalendar", "--leagues", "worlds"]))
        XCTAssertThrowsError(try CLIOptions.parse(["LoLCalendar", "--year"]))
        XCTAssertThrowsError(try CLIOptions.parse(["LoLCalendar", "--year", "0"]))
        XCTAssertThrowsError(try CLIOptions.parse(["LoLCalendar", "--unknown"]))
    }
}

final class CitoResponseTests: XCTestCase {
    func testDecodesActualResponseShape() throws {
        let response = try JSONDecoder().decode(LeagueScheduleResponse.self, from: pageJSON(
            offset: 0,
            hasMore: false,
            nextOffset: nil,
            events: [eventJSON(matchID: "lol-match-1")]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?.events.first?.matchID, "lol-match-1")
        XCTAssertEqual(response.data?.events.first?.teams.first?.score, 0)
        XCTAssertEqual(response.data?.events.first?.strategy.count, 3)
        XCTAssertNil(response.data?.nextOffset)
    }

    func testReportsSuccessFalseWithoutRequiringData() async {
        let client = CitoClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            apiKey: "secret",
            loadData: { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(#"{"success":false}"#.utf8), response)
            }
        )

        do {
            _ = try await client.fetchSchedule(leagueID: "lol-lpl", from: "2026-01-01", to: "2026-12-31")
            XCTFail("Expected success=false error")
        } catch {
            XCTAssertEqual(error as? CalendarCLIError, .invalidResponse("success=false"))
        }
    }

    func testFetchesAllOffsetPagesAndBuildsCorrectRequest() async throws {
        let loader = PageLoader(pages: [
            pageJSON(offset: 0, hasMore: true, nextOffset: 1, events: [eventJSON(matchID: "one")]),
            pageJSON(offset: 1, hasMore: false, nextOffset: nil, events: [eventJSON(matchID: "two")])
        ])
        let client = CitoClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            apiKey: "secret",
            pageLimit: 1,
            loadData: { request in try await loader.load(request) }
        )

        let events = try await client.fetchSchedule(
            leagueID: "lol-lpl",
            from: "2026-01-01",
            to: "2026-12-31"
        )

        XCTAssertEqual(events.map(\.matchID), ["one", "two"])
        let requests = await loader.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/api/v1/lol/leagues/lol-lpl/schedule")
        XCTAssertEqual(queryValue("from", in: requests[0]), "2026-01-01")
        XCTAssertEqual(queryValue("to", in: requests[0]), "2026-12-31")
        XCTAssertEqual(queryValue("limit", in: requests[0]), "1")
        XCTAssertEqual(queryValue("offset", in: requests[1]), "1")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "x-api-key"), "secret")
    }

    func testRejectsHasMoreWithoutUsableNextOffset() async {
        let loader = PageLoader(pages: [
            pageJSON(offset: 0, hasMore: true, nextOffset: nil, events: [eventJSON(matchID: "one")])
        ])
        let client = CitoClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            apiKey: "secret",
            loadData: { request in try await loader.load(request) }
        )

        do {
            _ = try await client.fetchSchedule(leagueID: "lol-lpl", from: "2026-01-01", to: "2026-12-31")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(
                error as? CalendarCLIError,
                .invalidResponse("hasMore=true without a valid nextOffset")
            )
        }
    }

    func testRejectsEmptyIntermediatePage() async {
        let loader = PageLoader(pages: [
            pageJSON(offset: 0, hasMore: true, nextOffset: 1, events: [])
        ])
        let client = CitoClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            apiKey: "secret",
            loadData: { request in try await loader.load(request) }
        )

        do {
            _ = try await client.fetchSchedule(leagueID: "lol-lpl", from: "2026-01-01", to: "2026-12-31")
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(
                error as? CalendarCLIError,
                .invalidResponse("pagination returned an empty page with hasMore=true")
            )
        }
    }

    func testReportsHTTPAndDecodeErrors() async {
        let badStatusClient = CitoClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            apiKey: "secret",
            loadData: { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
        )
        do {
            _ = try await badStatusClient.fetchSchedule(leagueID: "lol-lpl", from: "2026-01-01", to: "2026-12-31")
            XCTFail("Expected HTTP error")
        } catch {
            XCTAssertEqual(error as? CalendarCLIError, .badHTTPSStatus(401))
        }

        let invalidJSONClient = CitoClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            apiKey: "secret",
            loadData: { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("not-json".utf8), response)
            }
        )
        do {
            _ = try await invalidJSONClient.fetchSchedule(leagueID: "lol-lpl", from: "2026-01-01", to: "2026-12-31")
            XCTFail("Expected decode error")
        } catch let error as CalendarCLIError {
            guard case .invalidResponse(let message) = error else {
                return XCTFail("Expected invalidResponse")
            }
            XCTAssertTrue(message.hasPrefix("JSON decoding failed:"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class CalendarGenerationTests: XCTestCase {
    func testMapsEventsSortsDeduplicatesAndOnlyShowsCompletedScores() throws {
        let future = makeRawEvent(matchID: "future", startTime: "2026-08-12T07:00:00.000Z", state: "unstarted")
        let completed = makeRawEvent(
            matchID: "completed",
            startTime: "2026-08-11T07:00:00.000Z",
            state: "completed",
            firstScore: 2,
            secondScore: 1
        )

        let events = try ScheduleEventMapper.map([future, completed, completed])

        XCTAssertEqual(events.map(\.id), ["completed", "future"])
        XCTAssertEqual(events[0].summary, "EDG vs AL · 2:1")
        XCTAssertEqual(events[1].summary, "EDG vs AL")
        XCTAssertEqual(events[0].details, "LPL · Week 4 · BO3")
    }

    func testRejectsMalformedMatch() {
        let malformed = RawScheduleEvent(
            startTime: "not-a-date",
            state: "unstarted",
            type: "match",
            blockName: "Week 4",
            matchID: "bad",
            tournamentID: "tournament",
            teams: [],
            strategy: RawMatchStrategy(type: "bestOf", count: 3),
            leagueID: "lol-lpl",
            leagueName: "LPL",
            coverage: nil
        )
        XCTAssertThrowsError(try ScheduleEventMapper.map([malformed]))
    }

    func testRendersUTCWithTwoHourDurationAndEscapesText() throws {
        let raw = makeRawEvent(matchID: "match-1", state: "completed", firstScore: 2, secondScore: 0)
        let event = try XCTUnwrap(ScheduleEventMapper.map([raw]).first)
        let adjusted = CalendarEvent(
            id: event.id,
            startDate: event.startDate,
            summary: "EDG, A vs AL; B",
            details: "LPL\nWeek 4",
            teams: event.teams
        )

        let output = ICalendarRenderer.render(events: [adjusted], calendarName: "LPL")

        XCTAssertTrue(output.contains("DTSTART:20260812T070000Z\r\n"))
        XCTAssertTrue(output.contains("DTEND:20260812T090000Z\r\n"))
        XCTAssertTrue(output.contains("SUMMARY:EDG\\, A vs AL\\; B\r\n"))
        XCTAssertTrue(output.contains("DESCRIPTION:LPL\\nWeek 4\r\n"))
        XCTAssertTrue(output.hasSuffix("END:VCALENDAR\r\n"))
    }

    func testFoldsUTF8LinesAt75Octets() {
        let lines = ICalendarRenderer.foldLine("DESCRIPTION:" + String(repeating: "赛", count: 40))
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.hasPrefix(" ") })
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 75 })
    }

    func testWritesMainAndSelectedTeamCalendars() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lol-calendar-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let events = try ScheduleEventMapper.map([makeRawEvent(matchID: "match-1")])
        let options = CLIOptions(
            year: 2026,
            outputDirectory: temporaryDirectory,
            leagueSlugs: ["lpl"],
            splitTeams: true,
            teamSlug: "edg"
        )

        let urls = try CalendarFileWriter.write(
            events: events,
            league: LeagueConfig.defaults["lpl"]!,
            options: options
        )

        XCTAssertEqual(urls.map(\.lastPathComponent), ["lpl.ics", "EDG.ics"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("lpl.ics").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("teams/EDG.ics").path))
    }

    func testEmptyScheduleStillWritesMainCalendarWhenSplittingTeams() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lol-calendar-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let options = CLIOptions(
            year: 2026,
            outputDirectory: temporaryDirectory,
            leagueSlugs: ["lpl"],
            splitTeams: true,
            teamSlug: nil
        )

        let urls = try CalendarFileWriter.write(
            events: [],
            league: LeagueConfig.defaults["lpl"]!,
            options: options
        )

        XCTAssertEqual(urls.map(\.lastPathComponent), ["lpl.ics"])
    }

    func testSafeFilenameCannotEscapeOutputDirectory() {
        XCTAssertEqual(CalendarFileWriter.safeFilename("../EDG / A"), "EDG-A")
    }
}

private actor PageLoader {
    private var pages: [Data]
    private(set) var requests: [URLRequest] = []

    init(pages: [Data]) {
        self.pages = pages
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !pages.isEmpty else {
            throw CalendarCLIError.invalidResponse("test loader ran out of pages")
        }
        let data = pages.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

private func queryValue(_ name: String, in request: URLRequest) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == name })?
        .value
}

private func pageJSON(offset: Int, hasMore: Bool, nextOffset: Int?, events: [String]) -> Data {
    let nextOffsetValue = nextOffset.map(String.init) ?? "null"
    return Data("""
    {
      "success": true,
      "data": {
        "leagueId": "lol-lpl",
        "leagueName": "LPL",
        "total": \(events.count),
        "count": \(events.count),
        "limit": 50,
        "offset": \(offset),
        "events": [\(events.joined(separator: ","))],
        "hasMore": \(hasMore),
        "nextOffset": \(nextOffsetValue),
        "meta": {"source": "db"},
        "pagination": {"mode": "offset"},
        "pages": {}
      }
    }
    """.utf8)
}

private func eventJSON(matchID: String) -> String {
    """
    {
      "startTime": "2026-08-12T07:00:00.000Z",
      "state": "unstarted",
      "type": "match",
      "blockName": "Week 4",
      "matchId": "\(matchID)",
      "tournamentId": "lol-lpl_split_3_2026",
      "teams": [
        {"slug":"edg","name":"EDWARD GAMING","code":"EDG","imageUrl":"https://example.com/edg.png","score":0},
        {"slug":"al","name":"Anyone's Legend","code":"AL","imageUrl":"https://example.com/al.png","score":0}
      ],
      "strategy": {"type":"bestOf","count":3},
      "leagueId": "lol-lpl",
      "leagueName": "LPL",
      "coverage": {"gamesCount":0,"expectedGames":3,"gamesReady":false,"playerStatsReady":false}
    }
    """
}

private func makeRawEvent(
    matchID: String,
    startTime: String = "2026-08-12T07:00:00.000Z",
    state: String = "unstarted",
    firstScore: Int = 0,
    secondScore: Int = 0
) -> RawScheduleEvent {
    RawScheduleEvent(
        startTime: startTime,
        state: state,
        type: "match",
        blockName: "Week 4",
        matchID: matchID,
        tournamentID: "lol-lpl_split_3_2026",
        teams: [
            RawScheduleTeam(slug: "edg", name: "EDWARD GAMING", code: "EDG", imageURL: nil, score: firstScore),
            RawScheduleTeam(slug: "al", name: "Anyone's Legend", code: "AL", imageURL: nil, score: secondScore)
        ],
        strategy: RawMatchStrategy(type: "bestOf", count: 3),
        leagueID: "lol-lpl",
        leagueName: "LPL",
        coverage: nil
    )
}
