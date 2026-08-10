import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol CitoScheduleFetching: Sendable {
    func fetchSchedule(leagueID: String, from: String, to: String) async throws -> [RawScheduleEvent]
}

final class CitoClient: CitoScheduleFetching, Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let baseURL: URL
    let apiKey: String
    let pageLimit: Int
    private let loadData: DataLoader

    init(baseURL: URL, apiKey: String, session: URLSession = .shared, pageLimit: Int = 100) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.pageLimit = pageLimit
        self.loadData = { request in
            try await session.data(for: request)
        }
    }

    init(baseURL: URL, apiKey: String, pageLimit: Int = 100, loadData: @escaping DataLoader) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.pageLimit = pageLimit
        self.loadData = loadData
    }

    func fetchSchedule(leagueID: String, from: String, to: String) async throws -> [RawScheduleEvent] {
        guard pageLimit > 0 else {
            throw CalendarCLIError.invalidArgument("page limit must be greater than zero")
        }

        var events: [RawScheduleEvent] = []
        var offset = 0
        var visitedOffsets = Set<Int>()

        while true {
            guard visitedOffsets.insert(offset).inserted else {
                throw CalendarCLIError.invalidResponse("pagination repeated offset \(offset)")
            }

            let page = try await fetchSchedulePage(
                leagueID: leagueID,
                from: from,
                to: to,
                limit: pageLimit,
                offset: offset
            )
            guard page.offset == offset else {
                throw CalendarCLIError.invalidResponse(
                    "requested offset \(offset), received offset \(page.offset)"
                )
            }
            events.append(contentsOf: page.events)

            guard page.hasMore else { return events }
            guard !page.events.isEmpty else {
                throw CalendarCLIError.invalidResponse("pagination returned an empty page with hasMore=true")
            }
            guard let nextOffset = page.nextOffset, nextOffset > offset else {
                throw CalendarCLIError.invalidResponse("hasMore=true without a valid nextOffset")
            }
            offset = nextOffset
        }
    }

    private func fetchSchedulePage(
        leagueID: String,
        from: String,
        to: String,
        limit: Int,
        offset: Int
    ) async throws -> LeagueScheduleData {
        let endpoint = baseURL.appendingPathComponent("lol")
            .appendingPathComponent("leagues")
            .appendingPathComponent(leagueID)
            .appendingPathComponent("schedule")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw CalendarCLIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components.url else {
            throw CalendarCLIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (data, response) = try await loadData(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarCLIError.invalidResponse("response was not HTTP")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw CalendarCLIError.badHTTPSStatus(httpResponse.statusCode)
        }

        let decoded: LeagueScheduleResponse
        do {
            decoded = try JSONDecoder().decode(LeagueScheduleResponse.self, from: data)
        } catch {
            throw CalendarCLIError.invalidResponse("JSON decoding failed: \(error.localizedDescription)")
        }
        guard decoded.success else {
            throw CalendarCLIError.invalidResponse("success=false")
        }
        guard let responseData = decoded.data else {
            throw CalendarCLIError.invalidResponse("success=true without data")
        }
        return responseData
    }
}
