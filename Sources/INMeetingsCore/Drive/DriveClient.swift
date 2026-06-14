import Foundation

public enum DriveError: Error, Sendable { case http(status: Int, body: String) }

/// Minimal Google Drive v3 client, **Shared-Drive-aware** (all calls pass `supportsAllDrives`). Request
/// construction (the folder-search `q`, the multipart body) is factored into pure static helpers that
/// are unit-tested; execution goes through an injected access-token provider + `URLSession`.
public final class DriveClient: @unchecked Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String

    private let token: TokenProvider
    private let session: URLSession

    public init(token: @escaping TokenProvider, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    static let apiBase = URL(string: "https://www.googleapis.com/drive/v3")!
    static let uploadBase = URL(string: "https://www.googleapis.com/upload/drive/v3")!
    static let folderMIME = "application/vnd.google-apps.folder"

    // MARK: - Pure request building (unit-tested)

    /// The `q` to find a non-trashed folder by exact name under a parent. Escapes `\` then `'`.
    static func folderQuery(name: String, parentID: String) -> String {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "name = '\(escaped)' and '\(parentID)' in parents "
            + "and mimeType = '\(folderMIME)' and trashed = false"
    }

    /// A `multipart/related` body (JSON metadata + media) for a simple upload.
    static func multipartBody(metadata: [String: Any], media: Data, mediaType: String,
                              boundary: String) throws -> Data {
        var body = Data()
        func add(_ string: String) { body.append(Data(string.utf8)) }
        add("--\(boundary)\r\n")
        add("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        add("\r\n--\(boundary)\r\n")
        add("Content-Type: \(mediaType)\r\n\r\n")
        body.append(media)
        add("\r\n--\(boundary)--\r\n")
        return body
    }

    // MARK: - API (verified live)

    public struct DriveItem: Decodable, Sendable {
        public let id: String
        public let name: String
    }

    private struct IDOnly: Decodable { let id: String }
    private struct FileListResponse: Decodable { let files: [DriveItem] }
    private struct DriveListResponse: Decodable { let drives: [DriveItem] }

    /// Shared Drives the user can access — feeds the location picker.
    public func listSharedDrives() async throws -> [DriveItem] {
        var components = URLComponents(url: Self.apiBase.appendingPathComponent("drives"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "fields", value: "drives(id,name)"),
        ]
        let (data, _) = try await send(components.url!, method: "GET")
        return try JSONDecoder().decode(DriveListResponse.self, from: data).drives
    }

    /// The connected account's email — names the connection in the UI (works with just the drive scope).
    public func accountEmail() async throws -> String {
        var components = URLComponents(url: Self.apiBase.appendingPathComponent("about"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: "user(emailAddress)")]
        let (data, _) = try await send(components.url!, method: "GET")
        struct About: Decodable { struct User: Decodable { let emailAddress: String }; let user: User }
        return try JSONDecoder().decode(About.self, from: data).user.emailAddress
    }

    /// Find a folder by name under `parentID`, or create it. `driveId` scopes the search to a Shared Drive.
    public func findOrCreateFolder(name: String, parentID: String, driveId: String?) async throws -> String {
        var search = URLComponents(url: Self.apiBase.appendingPathComponent("files"),
                                   resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "q", value: Self.folderQuery(name: name, parentID: parentID)),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
        ]
        if let driveId {
            query.append(URLQueryItem(name: "corpora", value: "drive"))
            query.append(URLQueryItem(name: "driveId", value: driveId))
        }
        search.queryItems = query
        let (data, _) = try await send(search.url!, method: "GET")
        if let existing = try JSONDecoder().decode(FileListResponse.self, from: data).files.first {
            return existing.id
        }

        var create = URLComponents(url: Self.apiBase.appendingPathComponent("files"),
                                   resolvingAgainstBaseURL: false)!
        create.queryItems = [
            URLQueryItem(name: "fields", value: "id"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
        ]
        let metadata: [String: Any] = ["name": name, "mimeType": Self.folderMIME, "parents": [parentID]]
        let body = try JSONSerialization.data(withJSONObject: metadata)
        let (created, _) = try await send(create.url!, method: "POST",
                                          contentType: "application/json", body: body)
        return try JSONDecoder().decode(IDOnly.self, from: created).id
    }

    /// Upload `data` as a file named `name` under `parentID` (multipart simple upload); returns its id.
    @discardableResult
    public func uploadFile(name: String, mimeType: String, data: Data,
                           parentID: String, driveId: String?) async throws -> String {
        let boundary = "inmeetings-\(UUID().uuidString)"
        let metadata: [String: Any] = ["name": name, "parents": [parentID]]
        let body = try Self.multipartBody(metadata: metadata, media: data, mediaType: mimeType, boundary: boundary)

        var components = URLComponents(url: Self.uploadBase.appendingPathComponent("files"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
        ]
        let (response, _) = try await send(components.url!, method: "POST",
                                           contentType: "multipart/related; boundary=\(boundary)", body: body)
        return try JSONDecoder().decode(IDOnly.self, from: response).id
    }

    /// Upload a (potentially large) file by streaming it from disk through a resumable session — used for
    /// the audio/video recordings so hundreds of MB never load into memory. Returns the new file id.
    @discardableResult
    public func uploadFileResumable(name: String, mimeType: String, fileURL: URL,
                                    parentID: String, driveId: String?) async throws -> String {
        // 1. Initiate a resumable session (metadata only); Google returns the session URI in `Location`.
        var initiate = URLComponents(url: Self.uploadBase.appendingPathComponent("files"),
                                     resolvingAgainstBaseURL: false)!
        initiate.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: "id"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
        ]
        var initRequest = URLRequest(url: initiate.url!)
        initRequest.httpMethod = "POST"
        initRequest.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        initRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initRequest.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        initRequest.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parentID]])

        let (initData, initResponse) = try await session.data(for: initRequest)
        guard let http = initResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let sessionURI = URL(string: location) else {
            let status = (initResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw DriveError.http(status: status, body: String(decoding: initData, as: UTF8.self))
        }

        // 2. Stream the file to the session URI (which carries its own authorization).
        var put = URLRequest(url: sessionURI)
        put.httpMethod = "PUT"
        put.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: put, fromFile: fileURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DriveError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(IDOnly.self, from: data).id
    }

    // MARK: - HTTP

    private func send(_ url: URL, method: String, contentType: String? = nil,
                      body: Data? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DriveError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return (data, response)
    }
}
