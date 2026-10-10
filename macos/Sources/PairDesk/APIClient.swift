import Foundation

struct APIClient {
    let baseURL: URL
    let token: String?
    var session: URLSession = .shared

    init(server: String, token: String? = nil, session: URLSession = .shared) throws {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw APIError(status: 0, message: "Enter an HTTPS server address. HTTP is allowed only for a local development server.")
        }
        baseURL = url
        self.token = token
        self.session = session
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, _) = try await perform(path, method: method, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError(status: 0, message: "The server returned an incompatible response. Update the app or check the server version.") }
    }

    func send<B: Encodable>(_ path: String, body: B) async throws {
        _ = try await perform(path, method: "POST", body: JSONEncoder().encode(body))
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await request(path, method: "POST", body: JSONEncoder().encode(body))
    }

    private func perform(_ path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: 0, message: "No response from the server.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error) ?? "Request failed (\(http.statusCode))."
            throw APIError(status: http.statusCode, message: message)
        }
        return (data, http)
    }
}
