import Foundation

// Codable mirrors of the backend JSON (same REST API the Android app consumes).
// Field names follow the Android data classes. If the backend emits snake_case
// for any field, add CodingKeys or enable `.convertFromSnakeCase` in Api.swift.

// MARK: - Auth

struct AuthUser: Codable, Identifiable, Equatable {
    var id: String = ""
    var username: String = ""
    var displayName: String? = nil
    var email: String? = nil
    var role: String? = nil
    var avatar: String? = nil

    var title: String { (displayName?.isEmpty == false ? displayName! : username) }
}

struct LoginRequest: Codable {
    var username: String
    var password: String
}

struct LoginResponse: Codable {
    var user: AuthUser? = nil
    var ok: Bool? = nil
}

// MARK: - WhatsApp instances (accounts)

struct Instance: Codable, Identifiable, Hashable {
    var id: String = ""
    var name: String? = nil
    var displayPhoneNumber: String? = nil
    var isActive: Bool? = nil

    var label: String { name ?? displayPhoneNumber ?? id }
}

struct InstancesResponse: Codable {
    var items: [Instance] = []
    var defaultInstanceId: String? = nil
}

// MARK: - Conversations

struct ConvMetadata: Codable, Hashable {
    var lastMessage: String? = nil
    var unreadCount: Int? = nil
}

struct Conversation: Codable, Identifiable, Hashable {
    var id: String = ""
    var instanceId: String? = nil
    var phone: String? = nil
    var displayName: String? = nil
    var archived: Bool = false
    var pinned: Bool? = nil
    var lastAt: String? = nil
    var metadata: ConvMetadata? = nil
    var instance: Instance? = nil

    var title: String { (displayName?.isEmpty == false ? displayName! : (phone ?? "—")) }
    var unread: Int { metadata?.unreadCount ?? 0 }
    var preview: String { metadata?.lastMessage ?? "" }
    var isPinned: Bool { pinned ?? false }
}

struct ConversationsResponse: Codable {
    var items: [Conversation] = []
    var total: Int = 0
}

// MARK: - Messages

struct MessageMedia: Codable, Equatable {
    var url: String? = nil
    var mediaType: String? = nil
    var mimeType: String? = nil
}

struct Message: Codable, Identifiable, Equatable {
    var id: String = ""
    var conversationId: String? = nil
    var direction: String? = nil        // "inbound" | "outbound"
    var body: String? = nil
    var status: String? = nil
    var createdAt: String? = nil
    var media: MessageMedia? = nil
    var senderLabel: String? = nil

    var isOutbound: Bool { direction == "outbound" }
}

struct MessagesResponse: Codable {
    var items: [Message] = []
    var total: Int = 0
}

struct SendMessageRequest: Codable {
    var conversationId: String
    var body: String
}

// Media upload response from POST /api/upload (signed path in `url`).
struct MediaUploadResponse: Codable {
    var url: String = ""
    var publicUrl: String? = nil
    var relativePath: String? = nil
    var unsignedUrl: String? = nil
}

// POST /api/message/send with a media attachment (field names match the server: snake_case media_url).
struct SendMediaRequest: Codable {
    var conversationId: String
    var media_url: String
    var body: String? = nil
}

// Template send: `template` accepts {name, language}; params fill the body variables.
struct TemplateRef: Codable {
    var name: String
    var language: String? = nil
}
struct SendTemplateRequest: Codable {
    var conversationId: String
    var messageType: String = "template"
    var template: TemplateRef
    var templateParams: [String]? = nil
}

// GET /api/conversations/pins -> { pins: [{ conversationId, pinnedAt }] }
struct PinnedConversation: Codable, Identifiable {
    var conversationId: String = ""
    var id: String { conversationId }
}
struct PinsResponse: Codable { var pins: [PinnedConversation] = [] }

struct CreateConversationRequest: Codable {
    var phone: String
    var name: String?
    var instanceId: String?
}

struct CreateConversationResponse: Codable {
    var conversation: Conversation? = nil
}

// MARK: - Voice calls

struct VoiceInstance: Codable, Equatable {
    var id: String = ""
    var name: String? = nil
    var displayPhoneNumber: String? = nil
}

struct VoiceCall: Codable, Identifiable, Equatable {
    var id: String = ""
    var callId: String = ""
    var phone: String? = nil
    var peer: String? = nil
    var displayName: String? = nil
    var direction: String? = nil        // inbound | outbound
    var status: String? = nil
    var outcome: String? = nil
    var startedAt: String? = nil
    var durationSeconds: Int = 0
    var instance: VoiceInstance? = nil
    var recording: String? = nil
    var recordingUrl: String? = nil
    var initiatedByName: String? = nil

    var title: String { displayName ?? phone ?? peer ?? "—" }
    var isInbound: Bool { direction == "inbound" }
    var isMissed: Bool { outcome == "missed" || status == "missed" || status == "rejected" }
    /// Path to the stored recording, if any (served by /api/voice/recordings/:name).
    var recordingPath: String? {
        if let r = recording, !r.isEmpty { return r }
        if let r = recordingUrl, !r.isEmpty { return r }
        return nil
    }
}

struct VoiceCallsResponse: Codable {
    var total: Int = 0
    var items: [VoiceCall] = []
}

// GET /api/voice/calls/filters -> { accounts:[{id,name,displayPhoneNumber}], agents:[username] }
struct CallFilterAccount: Codable, Identifiable {
    var id: String = ""
    var name: String? = nil
    var displayPhoneNumber: String? = nil
    var label: String { name ?? displayPhoneNumber ?? id }
}
struct VoiceCallFilters: Codable {
    var accounts: [CallFilterAccount] = []
    var agents: [String] = []
}

// MARK: - Statistics

struct StatTotals: Codable, Equatable {
    var conversations: Int = 0
    var messages: Int = 0
    var incoming: Int = 0
    var outgoing: Int = 0
    var users: Int = 0
}

struct SeriesPoint: Codable, Identifiable, Equatable {
    var id: String { bucket ?? UUID().uuidString }
    var bucket: String? = nil
    var incoming: Int = 0
    var outgoing: Int = 0
}

struct InstTotals: Codable, Equatable {
    var messages: Int = 0
    var conversations: Int = 0
}

struct StatInstance: Codable, Identifiable, Equatable {
    var id: String = ""
    var name: String? = nil
    var displayPhoneNumber: String? = nil
    var totals: InstTotals? = nil

    var label: String { name ?? displayPhoneNumber ?? id }
}

struct Delivery: Codable, Equatable {
    var sent: Int = 0
    var delivered: Int = 0
    var read: Int = 0
    var failed: Int = 0
}

struct UserStat: Codable, Identifiable, Equatable {
    var id: String = ""
    var username: String = ""
    var role: String? = nil
    var messagesSent: Int = 0
    var repliesSent: Int = 0
    var conversationsCreated: Int = 0
    var avgResponseSeconds: Double? = nil
    var responseCount: Int = 0
    var engagementRate: Double = 0
    var activityScore: Int = 0
    var lastActiveAt: String? = nil
}

struct StatsResponse: Codable, Equatable {
    var totals: StatTotals? = nil
    var series: [SeriesPoint] = []
    var instanceBreakdown: [StatInstance] = []
    var delivery: Delivery? = nil
    var userStats: [UserStat] = []
}

// MARK: - Users & roles

struct UsersResponse: Codable { var items: [AuthUser] = [] }

struct Role: Codable, Identifiable {
    var id: String = ""
    var name: String = ""
    var description: String? = nil
    var isSystem: Bool = false
    var permissions: [String] = []
}
struct RolesResponse: Codable { var items: [Role] = [] }

// MARK: - Templates & ready messages

struct ReadyMessage: Codable, Identifiable {
    var id: String = ""
    var name: String = ""
    var body: String = ""
    var isActive: Bool = true
}
struct ReadyMessagesResponse: Codable { var items: [ReadyMessage] = [] }

struct TemplateComponent: Codable { var type: String? = nil; var text: String? = nil }

struct Template: Codable {
    var id: String? = nil
    var name: String = ""
    var language: String? = nil
    var category: String? = nil
    var status: String? = nil
    var bodyParams: Int = 0
    var components: [TemplateComponent]? = nil

    var stableId: String { id ?? name }
    var bodyText: String? { components?.first { $0.type?.uppercased() == "BODY" }?.text }
}
struct TemplatesResponse: Codable { var items: [Template] = [] }

// MARK: - Integrations

struct LinkedAccount: Codable { var id: String = ""; var name: String = ""; var phoneNumber: String? = nil }

struct IntegrationsSummary: Codable {
    var totalIntegrations: Int = 0
    var activeIntegrations: Int = 0
    var failedIntegrations: Int = 0
    var whatsappAccountsConnected: Int = 0
    var externalSystemsConnected: Int = 0
    var webhookSuccessRate: Double? = nil
    var lastEventTime: String? = nil
    var lastErrorTime: String? = nil
}
struct IntegrationsHealth: Codable {
    var healthy: Int = 0
    var warning: Int = 0
    var failed: Int = 0
    var disconnected: Int = 0
    var needsConfiguration: Int = 0
}
struct IntegrationsOverview: Codable {
    var summary: IntegrationsSummary? = nil
    var health: IntegrationsHealth? = nil
}
struct PublicIntegration: Codable, Identifiable {
    var id: String = ""
    var name: String = ""
    var type: String = ""
    var status: String = ""
    var health: String = ""          // healthy | warning | failed | disconnected | needs_configuration
    var baseUrl: String? = nil
    var endpoint: String? = nil
    var isEnabled: Bool = true
    var lastErrorMessage: String? = nil
}
struct IntegrationsListResponse: Codable { var items: [PublicIntegration] = [] }
struct IntegrationLog: Codable, Identifiable {
    var id: String = ""
    var timestamp: String? = nil
    var severity: String = "info"    // info | success | warning | error | critical
    var component: String = ""
    var summary: String = ""
    var correlationId: String? = nil
}
struct IntegrationLogsResponse: Codable { var items: [IntegrationLog] = [] }

// MARK: - WhatsApp accounts (health)

struct WhatsAppAccount: Codable, Identifiable {
    var id: String = ""
    var displayName: String = ""
    var phoneNumber: String? = nil
    var businessName: String? = nil
    var status: String? = nil       // live Meta connection status
    var health: String? = nil       // healthy | failed | needs_configuration | ...
    var isActive: Bool = true
    var isDefault: Bool = false
}
struct WhatsAppAccountsResponse: Codable { var items: [WhatsAppAccount] = [] }

// MARK: - Action request bodies

struct UpdateProfileRequest: Codable { var displayName: String? = nil; var email: String? = nil }
struct ArchiveRequest: Codable { var archived: Bool }
struct PinRequest: Codable { var pinned: Bool }
struct CreateUserRequest: Codable { var username: String; var password: String; var role: String }
struct UpdateUserRequest: Codable { var role: String? = nil; var password: String? = nil }
struct CreateRoleRequest: Codable { var name: String; var description: String? = nil; var permissions: [String]? = nil }

// MARK: - Voice / SIP settings (read-only subset)

struct VoiceSettings: Codable {
    var enabled: Bool = false
    var sipEnabled: Bool = false
    var cloudflareHostname: String = ""
    var asteriskWebrtcWssUrl: String = ""
    var ucmPublicIp: String = ""
    var ucmDefaultExtension: String = ""
    var whatsappSipDomain: String = ""
}
struct VoiceSettingsResponse: Codable { var settings: VoiceSettings? = nil }

// MARK: - Customer reports

struct StatCustomer: Codable, Identifiable {
    var id: String { conversationId }
    var conversationId: String = ""
    var phone: String? = nil
    var displayName: String? = nil
    var instanceName: String? = nil
    var messageCount: Int = 0
    var title: String { (displayName?.isEmpty == false ? displayName! : (phone ?? "—")) }
}
struct StatCustomersResponse: Codable { var items: [StatCustomer] = [] }

// MARK: - Customer report (GET /api/statistics/customer-report?conversationId=&range=)

struct CustomerReportConversation: Codable {
    var id: String = ""
    var phone: String? = nil
    var displayName: String? = nil
    var instanceName: String? = nil
    var createdAt: String? = nil
    var title: String { (displayName?.isEmpty == false ? displayName! : (phone ?? "—")) }
}
struct CustomerReportTotals: Codable {
    var messages: Int = 0
    var incoming: Int = 0
    var outgoing: Int = 0
    var firstAt: String? = nil
    var lastAt: String? = nil
}
struct CustomerReportAgent: Codable, Identifiable {
    var userId: String? = nil
    var username: String = "—"
    var sent: Int = 0
    var replies: Int = 0
    var lastAt: String? = nil
    var id: String { userId ?? username }
}
struct CustomerReportResponseStats: Codable {
    var avgSeconds: Int? = nil
    var minSeconds: Int? = nil
    var maxSeconds: Int? = nil
    var count: Int = 0
}
struct CustomerReportTimelineItem: Codable, Identifiable {
    var id: String = ""
    var direction: String? = nil
    var body: String? = nil
    var status: String? = nil
    var sentByUsername: String? = nil
    var createdAt: String? = nil
    var isOutbound: Bool { direction == "outbound" }
}
struct CustomerReport: Codable {
    var conversation: CustomerReportConversation? = nil
    var totals: CustomerReportTotals? = nil
    var statusBreakdown: [String: Int]? = nil
    var agents: [CustomerReportAgent] = []
    var responseStats: CustomerReportResponseStats? = nil
    var timeline: [CustomerReportTimelineItem] = []
}

// MARK: - Change password (POST /api/user/password)

struct ChangePasswordRequest: Codable { var currentPassword: String; var newPassword: String }

// MARK: - Ready-message CRUD

struct CreateReadyMessageRequest: Codable { var name: String; var body: String; var isActive: Bool = true }
struct UpdateReadyMessageRequest: Codable { var name: String? = nil; var body: String? = nil; var isActive: Bool? = nil }

// MARK: - Integration CRUD

struct CreateIntegrationRequest: Codable {
    var name: String
    var type: String = "external_system"
    var baseUrl: String? = nil
    var endpoint: String? = nil
    var authType: String = "none"
    var linkedInstanceId: String? = nil
    var timeoutMs: Int? = nil
    var isEnabled: Bool? = nil
}
struct UpdateIntegrationRequest: Codable {
    var name: String? = nil
    var baseUrl: String? = nil
    var endpoint: String? = nil
    var authType: String? = nil
    var linkedInstanceId: String? = nil
    var timeoutMs: Int? = nil
    var isEnabled: Bool? = nil
}
