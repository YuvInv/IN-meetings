import Foundation

/// Executes Google's token-endpoint POSTs (code exchange + refresh) over `URLSession`. The request
/// *bodies* are built (and tested) by `GoogleOAuth`; this just sends them. Used both by the app's
/// sign-in and by `DriveTokenManager`'s refresher.
public struct GoogleTokenService: Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func post(_ formBody: Data) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: GoogleOAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DriveError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }
}
