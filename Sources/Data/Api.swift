import Foundation

// Networking client for the same WhatsX REST backend the Android app uses.
// Session auth is cookie-based (passport) — URLSession's shared cookie storage
// persists the login cookie across requests automatically.
//
// Real endpoint paths are taken verbatim from the Android ApiService.
// NOTE: most JSON is camelCase; a few request fields are snake_case on the
// server — add CodingKeys if the backend rejects a field.

enum AppConfig {
    private static let key = "whatsx.baseURL"
    /// Set this to your production server (a STABLE public https domain).
    static let defaultBaseURL = "https://your-server.example.com"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: key) ?? defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct ApiError: LocalizedError {
    let message: String
    let status: Int?
    var errorDescription: String? { message }
}

/// Type-erased Encodable so `request(body:)` can take any Encodable.
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

struct EmptyResponse: Decodable {}

final class Api {
    static let shared = Api()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    static func avatarURL(userId: String, avatar: String) -> URL? {
        let base = AppConfig.baseURL.trimmed()
        return URL(string: "\(base)/api/user/avatar/\(userId)?v=\(avatar.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? avatar)")
    }

    static func mediaURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: AppConfig.baseURL.trimmed() + (path.hasPrefix("/") ? path : "/" + path))
    }

    private func makeURL(_ path: String, query: [String: String?] = [:]) -> URL {
        var comps = URLComponents(string: AppConfig.baseURL.trimmed() + "/" + path)!
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { comps.queryItems = items }
        return comps.url!
    }

    @discardableResult
    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Encodable? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        var req = URLRequest(url: makeURL(path, query: query))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ApiError(message: "No HTTP response", status: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ApiError(message: "HTTP \(http.statusCode)", status: http.statusCode)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw ApiError(message: "Decode failed: \(error.localizedDescription)", status: http.statusCode) }
    }

    // MARK: - Auth
    func login(username: String, password: String) async throws -> AuthUser {
        let _: EmptyResponse = try await request(
            "api/login", method: "POST", body: LoginRequest(username: username, password: password))
        return try await me()
    }
    func logout() async throws { let _: EmptyResponse = try await request("api/logout", method: "POST") }
    func me() async throws -> AuthUser { try await request("api/user") }

    // MARK: - Instances
    func instances() async throws -> InstancesResponse { try await request("api/whatsapp/instances") }

    // MARK: - Conversations
    func conversations(archived: Bool, page: Int = 1, pageSize: Int = 50, instanceIds: String? = nil) async throws -> ConversationsResponse {
        try await request("api/conversations", query: [
            "archived": String(archived), "page": String(page),
            "page_size": String(pageSize), "instanceIds": instanceIds,
        ])
    }
    func createConversation(_ body: CreateConversationRequest) async throws -> CreateConversationResponse {
        try await request("api/conversations", method: "POST", body: body)
    }

    // MARK: - Messages
    func messages(conversationId: String, page: Int = 1) async throws -> MessagesResponse {
        try await request("api/conversations/\(conversationId)/messages", query: ["page": String(page)])
    }
    func sendMessage(conversationId: String, body: String, replyToMessageId: String? = nil) async throws {
        let _: EmptyResponse = try await request(
            "api/message/send", method: "POST",
            body: SendMessageRequest(conversationId: conversationId, body: body,
                                     replyToMessageId: replyToMessageId))
    }
    /// Upload a file to /api/upload (multipart field "file"); returns the signed media path in `url`.
    func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> MediaUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: makeURL("api/upload"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var b = Data()
        b.append("--\(boundary)\r\n".data(using: .utf8)!)
        b.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        b.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        b.append(data)
        b.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = b
        let (respData, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ApiError(message: "Upload failed", status: (resp as? HTTPURLResponse)?.statusCode)
        }
        return try decoder.decode(MediaUploadResponse.self, from: respData)
    }
    /// Send a previously-uploaded media URL as a message (optionally with a caption).
    func sendMedia(conversationId: String, mediaUrl: String, caption: String?, replyToMessageId: String? = nil) async throws {
        let _: EmptyResponse = try await request(
            "api/message/send", method: "POST",
            body: SendMediaRequest(conversationId: conversationId, media_url: mediaUrl,
                                   body: (caption?.isEmpty == false) ? caption : nil,
                                   replyToMessageId: replyToMessageId))
    }
    /// Send an approved Meta template with optional body parameters.
    func sendTemplate(conversationId: String, name: String, language: String?, params: [String]) async throws {
        let _: EmptyResponse = try await request(
            "api/message/send", method: "POST",
            body: SendTemplateRequest(conversationId: conversationId,
                                      template: TemplateRef(name: name, language: language),
                                      templateParams: params.isEmpty ? nil : params))
    }
    /// Fetch the set of pinned conversation ids.
    func pinnedConversationIds() async throws -> [String] {
        let resp: PinsResponse = try await request("api/conversations/pins")
        return resp.pins.map { $0.conversationId }
    }

    // MARK: - Voice calls
    /// Call history scoped to one conversation (inline call events in the chat timeline).
    func conversationCalls(conversationId: String, limit: Int = 100) async throws -> VoiceCallsResponse {
        try await request("api/conversations/\(conversationId)/calls", query: ["limit": String(limit)])
    }
    func voiceCalls(limit: Int = 200, search: String? = nil, direction: String? = nil, status: String? = nil,
                    instanceId: String? = nil, agent: String? = nil, hasRecording: Bool? = nil) async throws -> VoiceCallsResponse {
        try await request("api/voice/calls", query: [
            "limit": String(limit), "search": search, "direction": direction, "status": status,
            "instanceId": instanceId, "agent": agent,
            "hasRecording": hasRecording.map { $0 ? "true" : "false" },
        ])
    }
    func voiceCallFilters() async throws -> VoiceCallFilters {
        try await request("api/voice/calls/filters")
    }
    /// Reject a ringing call — or terminate an active one (action: "terminate").
    func rejectCall(callId: String, action: String = "reject") async throws {
        let _: EmptyResponse = try await request(
            "api/voice/whatsapp/reject", method: "POST",
            body: RejectCallRequest(callId: callId, action: action))
    }
    /// Ask the contact (Meta interactive message) to allow business-initiated calls.
    func requestCallPermission(to: String, instanceId: String?) async throws {
        let _: EmptyResponse = try await request(
            "api/voice/whatsapp/call-permission", method: "POST",
            body: CallPermissionRequest(to: to, instanceId: instanceId))
    }

    // MARK: - Statistics
    func statistics(range: String? = nil, instanceId: String? = nil) async throws -> StatsResponse {
        try await request("api/statistics", query: ["range": range, "instanceId": instanceId])
    }

    // MARK: - Admin & integrations
    func users() async throws -> UsersResponse { try await request("api/users") }
    func roles() async throws -> RolesResponse { try await request("api/roles") }
    func readyMessages() async throws -> ReadyMessagesResponse { try await request("api/ready-messages") }
    func templates() async throws -> TemplatesResponse { try await request("api/templates") }
    func createTemplate(_ body: CreateTemplateRequest) async throws {
        let _: EmptyResponse = try await request("api/admin/templates", method: "POST", body: body)
    }
    func deleteTemplate(_ id: String) async throws {
        let _: EmptyResponse = try await request("api/admin/templates/\(id)", method: "DELETE")
    }
    func syncTemplates(instanceId: String? = nil) async throws -> SyncTemplatesResponse {
        try await request("api/admin/templates/sync", method: "POST", body: InstanceIdBody(instanceId: instanceId))
    }
    func integrationsOverview() async throws -> IntegrationsOverview { try await request("api/integrations/overview") }
    func integrations() async throws -> IntegrationsListResponse { try await request("api/integrations") }
    func integrationLogs(severity: String? = nil) async throws -> IntegrationLogsResponse {
        try await request("api/integrations/logs", query: ["severity": severity])
    }
    func messageFlow() async throws -> MessageFlowResponse {
        try await request("api/integrations/message-flow")
    }
    @discardableResult
    func retryMessageFlow(_ id: String) async throws -> RetryResult {
        try await request("api/integrations/message-flow/\(id)/retry", method: "POST")
    }
    func whatsappAccounts() async throws -> WhatsAppAccountsResponse {
        try await request("api/integrations/whatsapp-accounts")
    }
    func createWhatsappAccount(_ body: CreateWhatsappAccountRequest) async throws -> WhatsAppAccount? {
        let resp: WhatsAppAccountResponse = try await request("api/integrations/whatsapp-accounts", method: "POST", body: body)
        return resp.account
    }
    func updateWhatsappAccount(_ id: String, _ body: UpdateWhatsappAccountRequest) async throws -> WhatsAppAccount? {
        let resp: WhatsAppAccountResponse = try await request("api/integrations/whatsapp-accounts/\(id)", method: "PATCH", body: body)
        return resp.account
    }
    func deleteWhatsappAccount(_ id: String) async throws {
        let _: EmptyResponse = try await request("api/integrations/whatsapp-accounts/\(id)", method: "DELETE")
    }
    /// Request a registration code by SMS or VOICE for a WhatsApp number.
    func requestWhatsappCode(_ id: String, method: String, language: String = "en_US") async throws {
        let _: EmptyResponse = try await request(
            "api/integrations/whatsapp-accounts/\(id)/request-code", method: "POST",
            body: RequestCodeRequest(codeMethod: method, language: language))
    }
    /// Complete registration with the 6-digit PIN.
    func registerWhatsappNumber(_ id: String, pin: String) async throws {
        let _: EmptyResponse = try await request(
            "api/integrations/whatsapp-accounts/\(id)/register", method: "POST",
            body: RegisterNumberRequest(pin: pin))
    }

    // MARK: - Presence
    /// Heartbeat that stamps the user's last-active time (web parity: use-activity-ping).
    func activityPing() async throws {
        let _: EmptyResponse = try await request("api/activity/ping", method: "POST")
    }

    // MARK: - Profile
    func updateProfile(displayName: String?, email: String?) async throws -> AuthUser {
        try await request("api/user/profile", method: "PATCH",
                          body: UpdateProfileRequest(displayName: displayName, email: email))
    }
    func uploadAvatar(imageData: Data) async throws -> AuthUser {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: makeURL("api/user/avatar"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ApiError(message: "Upload failed", status: (resp as? HTTPURLResponse)?.statusCode)
        }
        return try decoder.decode(AuthUser.self, from: data)
    }

    // MARK: - Integration actions
    func integrationTest(_ id: String) async throws { let _: EmptyResponse = try await request("api/integrations/\(id)/test", method: "POST") }
    func integrationEnable(_ id: String) async throws { let _: EmptyResponse = try await request("api/integrations/\(id)/enable", method: "POST") }
    func integrationDisable(_ id: String) async throws { let _: EmptyResponse = try await request("api/integrations/\(id)/disable", method: "POST") }

    // MARK: - Conversation actions
    func archiveConversation(_ id: String, archived: Bool) async throws {
        let _: EmptyResponse = try await request("api/conversations/\(id)/archive", method: "PATCH", body: ArchiveRequest(archived: archived))
    }
    func pinConversation(_ id: String, pinned: Bool) async throws {
        let _: EmptyResponse = try await request("api/conversations/\(id)/pin", method: "POST", body: PinRequest(pinned: pinned))
    }
    func deleteConversation(_ id: String) async throws {
        let _: EmptyResponse = try await request("api/conversations/\(id)", method: "DELETE")
    }

    // MARK: - Voice settings & user CRUD
    func voiceSettings() async throws -> VoiceSettingsResponse { try await request("api/voice/settings") }
    func createUser(username: String, password: String, role: String) async throws -> AuthUser {
        try await request("api/users", method: "POST", body: CreateUserRequest(username: username, password: password, role: role))
    }
    func deleteUser(_ id: String) async throws {
        let _: EmptyResponse = try await request("api/users/\(id)", method: "DELETE")
    }
    func updateUser(_ id: String, role: String?, password: String?) async throws -> AuthUser {
        let pw = (password?.isEmpty == false) ? password : nil
        return try await request("api/users/\(id)", method: "PATCH", body: UpdateUserRequest(role: role, password: pw))
    }
    func createRole(name: String, description: String?) async throws -> Role {
        try await request("api/roles", method: "POST", body: CreateRoleRequest(name: name, description: description))
    }
    func updateRole(_ id: String, name: String? = nil, description: String? = nil, permissions: [String]? = nil) async throws {
        let _: EmptyResponse = try await request(
            "api/roles/\(id)", method: "PATCH",
            body: UpdateRoleRequest(name: name, description: description, permissions: permissions))
    }
    func deleteRole(_ id: String) async throws {
        let _: EmptyResponse = try await request("api/roles/\(id)", method: "DELETE")
    }
    func permissionsCatalog() async throws -> [PermissionCatalogItem] {
        let resp: PermissionCatalogResponse = try await request("api/permissions/catalog")
        return resp.items
    }
    func userPermissions(_ id: String) async throws -> UserPermissions {
        try await request("api/users/\(id)/permissions")
    }
    func updateUserPermissions(_ id: String, overrides: [UserPermissionOverride]) async throws {
        let _: EmptyResponse = try await request(
            "api/users/\(id)/permissions", method: "PATCH",
            body: UpdateUserPermissionsRequest(overrides: overrides))
    }

    // MARK: - Customer reports
    func statisticsCustomers(search: String? = nil) async throws -> StatCustomersResponse {
        try await request("api/statistics/customers", query: ["search": search])
    }
    func customerReport(conversationId: String, range: String? = nil) async throws -> CustomerReport {
        try await request("api/statistics/customer-report", query: ["conversationId": conversationId, "range": range])
    }

    // MARK: - Account security
    func changePassword(currentPassword: String, newPassword: String) async throws {
        let _: EmptyResponse = try await request(
            "api/user/password", method: "POST",
            body: ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword))
    }

    // MARK: - Ready-message CRUD
    func createReadyMessage(name: String, body: String, isActive: Bool) async throws {
        let _: EmptyResponse = try await request("api/admin/ready-messages", method: "POST",
            body: CreateReadyMessageRequest(name: name, body: body, isActive: isActive))
    }
    func updateReadyMessage(_ id: String, name: String?, body: String?, isActive: Bool?) async throws {
        let _: EmptyResponse = try await request("api/admin/ready-messages/\(id)", method: "PATCH",
            body: UpdateReadyMessageRequest(name: name, body: body, isActive: isActive))
    }
    func deleteReadyMessage(_ id: String) async throws {
        let _: EmptyResponse = try await request("api/admin/ready-messages/\(id)", method: "DELETE")
    }

    // MARK: - Integration CRUD
    func createIntegration(_ body: CreateIntegrationRequest) async throws -> PublicIntegration {
        try await request("api/integrations", method: "POST", body: body)
    }
    func updateIntegration(_ id: String, _ body: UpdateIntegrationRequest) async throws -> PublicIntegration {
        try await request("api/integrations/\(id)", method: "PATCH", body: body)
    }
    func deleteIntegration(_ id: String) async throws {
        let _: EmptyResponse = try await request("api/integrations/\(id)", method: "DELETE")
    }
}

extension String {
    func trimmed() -> String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
