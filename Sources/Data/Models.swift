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

    private enum CodingKeys: String, CodingKey { case id, username, displayName, email, role, avatar }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id, default: "")
        username = c.lenient(String.self, forKey: .username, default: "")
        displayName = c.lenient(String.self, forKey: .displayName)
        email = c.lenient(String.self, forKey: .email)
        role = c.lenient(String.self, forKey: .role)
        avatar = c.lenient(String.self, forKey: .avatar)
    }
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

    private enum CodingKeys: String, CodingKey { case id, name, displayPhoneNumber, isActive }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id, default: "")
        name = c.lenient(String.self, forKey: .name)
        displayPhoneNumber = c.lenient(String.self, forKey: .displayPhoneNumber)
        isActive = c.lenient(Bool.self, forKey: .isActive)
    }
}

struct InstancesResponse: Codable {
    var items: [Instance] = []
    var defaultInstanceId: String? = nil

    private enum CodingKeys: String, CodingKey { case items, defaultInstanceId }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(Instance.self, forKey: .items)
        defaultInstanceId = c.lenient(String.self, forKey: .defaultInstanceId)
    }
}

// MARK: - Conversations

// Conversation metadata is a free-form JSON blob on the server, so every
// field decodes leniently — a malformed value must never sink the whole
// conversations list.
struct ConvMetadata: Codable, Hashable {
    var lastMessage: String? = nil
    var unreadCount: Int? = nil
    var status: String? = nil
    var about: String? = nil
    var website: String? = nil
    var lastSeenAt: String? = nil
    var labels: [String]? = nil

    private enum CodingKeys: String, CodingKey {
        case lastMessage, unreadCount, status, about, website, lastSeenAt, labels
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastMessage = (try? c.decodeIfPresent(String.self, forKey: .lastMessage)) ?? nil
        unreadCount = (try? c.decodeIfPresent(Int.self, forKey: .unreadCount)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
        about = (try? c.decodeIfPresent(String.self, forKey: .about)) ?? nil
        website = (try? c.decodeIfPresent(String.self, forKey: .website)) ?? nil
        lastSeenAt = (try? c.decodeIfPresent(String.self, forKey: .lastSeenAt)) ?? nil
        labels = (try? c.decodeIfPresent([String].self, forKey: .labels)) ?? nil
    }
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

    private enum CodingKeys: String, CodingKey {
        case id, instanceId, phone, displayName, archived, pinned, lastAt, metadata, instance
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id, default: "")
        instanceId = c.lenient(String.self, forKey: .instanceId)
        phone = c.lenient(String.self, forKey: .phone)
        displayName = c.lenient(String.self, forKey: .displayName)
        archived = c.lenient(Bool.self, forKey: .archived, default: false)
        pinned = c.lenient(Bool.self, forKey: .pinned)
        lastAt = c.lenient(String.self, forKey: .lastAt)
        metadata = c.lenient(ConvMetadata.self, forKey: .metadata)
        instance = c.lenient(Instance.self, forKey: .instance)
    }
}

struct ConversationsResponse: Codable {
    var items: [Conversation] = []
    var total: Int = 0

    private enum CodingKeys: String, CodingKey { case items, total }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(Conversation.self, forKey: .items)
        total = c.lenient(Int.self, forKey: .total, default: 0)
    }
}

// MARK: - Messages

struct MessageMedia: Codable, Equatable {
    var url: String? = nil
    var mediaType: String? = nil
    var mimeType: String? = nil
}

// Quoted-reply summary attached to a message (server: ReplySummary).
struct ReplySummary: Codable, Equatable {
    var id: String? = nil
    var content: String? = nil
    var direction: String? = nil
    var senderLabel: String? = nil
    var createdAt: String? = nil
}

// Template message snapshot (server: TemplatePreviewSnapshot) — the resolved
// body and interactive buttons of a template message, for display in-thread.
struct TemplatePreviewButton: Codable, Equatable {
    var type: String? = nil            // quick_reply | url | unknown
    var text: String? = nil
    var resolvedUrl: String? = nil
}

struct TemplatePreviewSnapshot: Codable, Equatable {
    var resolvedBodyText: String? = nil
    var resolvedButtons: [TemplatePreviewButton]? = nil
}

// Shared-contact (vCard) payload embedded in the raw WhatsApp message.
struct RawContactName: Codable, Equatable {
    var formatted_name: String? = nil
    var first_name: String? = nil
    var last_name: String? = nil
}
struct RawContactPhone: Codable, Equatable {
    var phone: String? = nil
}
struct RawContact: Codable, Equatable {
    var name: RawContactName? = nil
    var phones: [RawContactPhone]? = nil
}
/// Lenient slice of the raw webhook payload — only what the UI renders.
struct RawPayload: Codable, Equatable {
    var contacts: [RawContact]? = nil

    private enum CodingKeys: String, CodingKey { case contacts }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        contacts = (try? c?.decodeIfPresent([RawContact].self, forKey: .contacts)) ?? nil
    }
}

/// A displayable shared contact extracted from `raw.contacts`.
struct SharedContact: Equatable {
    let name: String
    let phones: [String]
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
    var replyTo: ReplySummary? = nil
    var errorCode: String? = nil
    var errorTitle: String? = nil
    var errorDetails: String? = nil
    var templateName: String? = nil
    var templateLanguage: String? = nil
    var templatePreview: TemplatePreviewSnapshot? = nil
    var raw: RawPayload? = nil

    private enum CodingKeys: String, CodingKey {
        case id, conversationId, direction, body, status, createdAt, media, senderLabel
        case replyTo, errorCode, errorTitle, errorDetails
        case templateName, templateLanguage, templatePreview, raw
    }

    init() {}

    // Fully lenient decoding — `raw`/`templatePreview` are free-form JSON on
    // the server; a malformed field must never sink the whole thread.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil ?? ""
        conversationId = (try? c.decodeIfPresent(String.self, forKey: .conversationId)) ?? nil
        direction = (try? c.decodeIfPresent(String.self, forKey: .direction)) ?? nil
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil
        media = (try? c.decodeIfPresent(MessageMedia.self, forKey: .media)) ?? nil
        senderLabel = (try? c.decodeIfPresent(String.self, forKey: .senderLabel)) ?? nil
        replyTo = (try? c.decodeIfPresent(ReplySummary.self, forKey: .replyTo)) ?? nil
        errorCode = (try? c.decodeIfPresent(String.self, forKey: .errorCode)) ?? nil
        errorTitle = (try? c.decodeIfPresent(String.self, forKey: .errorTitle)) ?? nil
        errorDetails = (try? c.decodeIfPresent(String.self, forKey: .errorDetails)) ?? nil
        templateName = (try? c.decodeIfPresent(String.self, forKey: .templateName)) ?? nil
        templateLanguage = (try? c.decodeIfPresent(String.self, forKey: .templateLanguage)) ?? nil
        templatePreview = (try? c.decodeIfPresent(TemplatePreviewSnapshot.self, forKey: .templatePreview)) ?? nil
        raw = (try? c.decodeIfPresent(RawPayload.self, forKey: .raw)) ?? nil
    }

    var isOutbound: Bool { direction == "outbound" }
    var isTemplateMessage: Bool { templatePreview != nil || templateName?.isEmpty == false }

    /// Shared contacts (vCards), extracted like the web MessageBubble does.
    var sharedContacts: [SharedContact] {
        (raw?.contacts ?? []).compactMap { contact in
            let name = contact.name?.formatted_name?.trimmingCharacters(in: .whitespaces)
                ?? [contact.name?.first_name, contact.name?.last_name]
                    .compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let phones = (contact.phones ?? []).compactMap { $0.phone?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if name.isEmpty && phones.isEmpty { return nil }
            return SharedContact(name: name, phones: phones)
        }
    }

    /// Human-readable reason a send failed, best field first.
    var failureReason: String? {
        errorTitle?.isEmpty == false ? errorTitle
            : (errorDetails?.isEmpty == false ? errorDetails
                : (errorCode?.isEmpty == false ? errorCode : nil))
    }
}

struct MessagesResponse: Codable {
    var items: [Message] = []
    var total: Int = 0

    private enum CodingKeys: String, CodingKey { case items, total }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(Message.self, forKey: .items)
        total = c.lenient(Int.self, forKey: .total, default: 0)
    }
}

struct SendMessageRequest: Codable {
    var conversationId: String
    var body: String
    var replyToMessageId: String? = nil
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
    var replyToMessageId: String? = nil
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
struct PinsResponse: Codable {
    var pins: [PinnedConversation] = []

    private enum CodingKeys: String, CodingKey { case pins }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pins = c.lossy(PinnedConversation.self, forKey: .pins)
    }
}

struct CreateConversationRequest: Codable {
    var phone: String
    var displayName: String?   // server reads `displayName` (POST /api/conversations)
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

    private enum CodingKeys: String, CodingKey {
        case id, callId, phone, peer, displayName, direction, status, outcome
        case startedAt, durationSeconds, instance, recording, recordingUrl, initiatedByName
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id, default: "")
        callId = c.lenient(String.self, forKey: .callId, default: "")
        phone = c.lenient(String.self, forKey: .phone)
        peer = c.lenient(String.self, forKey: .peer)
        displayName = c.lenient(String.self, forKey: .displayName)
        direction = c.lenient(String.self, forKey: .direction)
        status = c.lenient(String.self, forKey: .status)
        outcome = c.lenient(String.self, forKey: .outcome)
        startedAt = c.lenient(String.self, forKey: .startedAt)
        durationSeconds = c.lenient(Int.self, forKey: .durationSeconds, default: 0)
        instance = c.lenient(VoiceInstance.self, forKey: .instance)
        recording = c.lenient(String.self, forKey: .recording)
        recordingUrl = c.lenient(String.self, forKey: .recordingUrl)
        initiatedByName = c.lenient(String.self, forKey: .initiatedByName)
    }

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

    private enum CodingKeys: String, CodingKey { case total, items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.lenient(Int.self, forKey: .total, default: 0)
        items = c.lossy(VoiceCall.self, forKey: .items)
    }
}

struct RejectCallRequest: Codable {
    var callId: String
    var action: String
}

struct CallPermissionRequest: Codable {
    var to: String
    var instanceId: String?
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

    private enum CodingKeys: String, CodingKey { case accounts, agents }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = c.lossy(CallFilterAccount.self, forKey: .accounts)
        agents = c.lossy(String.self, forKey: .agents)
    }
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

    private enum CodingKeys: String, CodingKey { case totals, series, instanceBreakdown, delivery, userStats }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totals = c.lenient(StatTotals.self, forKey: .totals)
        series = c.lossy(SeriesPoint.self, forKey: .series)
        instanceBreakdown = c.lossy(StatInstance.self, forKey: .instanceBreakdown)
        delivery = c.lenient(Delivery.self, forKey: .delivery)
        userStats = c.lossy(UserStat.self, forKey: .userStats)
    }
}

// MARK: - Users & roles

struct UsersResponse: Codable {
    var items: [AuthUser] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(AuthUser.self, forKey: .items)
    }
}

struct Role: Codable, Identifiable {
    var id: String = ""
    var name: String = ""
    var description: String? = nil
    var isSystem: Bool = false
    var permissions: [String] = []
}
struct RolesResponse: Codable {
    var items: [Role] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(Role.self, forKey: .items)
    }
}

struct UpdateRoleRequest: Codable {
    var name: String? = nil
    var description: String? = nil
    var permissions: [String]? = nil
}

// GET /api/permissions/catalog -> { items:[{id,label,group,groupLabel,action,description,isCritical}] }
struct PermissionCatalogItem: Codable, Identifiable {
    var id: String = ""
    var label: String? = nil
    var group: String? = nil
    var groupLabel: String? = nil
    var action: String? = nil
    var description: String? = nil
    var isCritical: Bool? = nil
    var title: String { label ?? id }
    var groupTitle: String { groupLabel ?? group ?? L("أخرى") }
}
struct PermissionCatalogResponse: Codable {
    var items: [PermissionCatalogItem] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(PermissionCatalogItem.self, forKey: .items)
    }
}

// GET /api/users/:id/permissions -> { rolePermissions:[id], overrides:[{permissionId,allowed}], effectivePermissions:[id] }
struct UserPermissionOverride: Codable { var permissionId: String; var allowed: Bool }
struct UserPermissions: Codable {
    var rolePermissions: [String] = []
    var overrides: [UserPermissionOverride] = []
    var effectivePermissions: [String] = []

    private enum CodingKeys: String, CodingKey { case rolePermissions, overrides, effectivePermissions }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rolePermissions = c.lossy(String.self, forKey: .rolePermissions)
        overrides = c.lossy(UserPermissionOverride.self, forKey: .overrides)
        effectivePermissions = c.lossy(String.self, forKey: .effectivePermissions)
    }
}
struct UpdateUserPermissionsRequest: Codable { var overrides: [UserPermissionOverride] }

// MARK: - Templates & ready messages

struct ReadyMessage: Codable, Identifiable {
    var id: String = ""
    var name: String = ""
    var body: String = ""
    var isActive: Bool = true
}
struct ReadyMessagesResponse: Codable {
    var items: [ReadyMessage] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(ReadyMessage.self, forKey: .items)
    }
}

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
struct TemplatesResponse: Codable {
    var items: [Template] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(Template.self, forKey: .items)
    }
}

// Admin template CRUD (POST /api/admin/templates, /sync).
struct CreateTemplateRequest: Codable {
    var name: String
    var language: String
    var category: String? = nil
    var components: [TemplateComponent]
    var submitToMeta: Bool = false
    var instanceId: String? = nil
}
struct SyncTemplatesResponse: Codable { var syncedCount: Int = 0; var lastSyncedAt: String? = nil }
struct InstanceIdBody: Codable { var instanceId: String? = nil }

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

    private enum CodingKeys: String, CodingKey { case summary, health }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = c.lenient(IntegrationsSummary.self, forKey: .summary)
        health = c.lenient(IntegrationsHealth.self, forKey: .health)
    }
}

// GET /api/admin/integrations/messages — template messages pushed by
// external systems through the integration API (snake_case payload).
struct IntegrationMonitorItem: Codable, Identifiable {
    var id: String = ""
    var requestId: String? = nil
    var conversationId: String? = nil
    var phone: String? = nil
    var name: String? = nil
    var instance: Instance? = nil
    var templateName: String? = nil
    var templateLanguage: String? = nil
    var status: String? = nil
    var resolvedUrl: String? = nil
    var createdAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, phone, name, instance, status
        case requestId = "request_id"
        case conversationId = "conversation_id"
        case templateName = "template_name"
        case templateLanguage = "template_language"
        case resolvedUrl = "resolved_url"
        case createdAt = "created_at"
    }
}

struct IntegrationMonitorResponse: Codable {
    var items: [IntegrationMonitorItem] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(IntegrationMonitorItem.self, forKey: .items)
    }
}
struct PublicIntegration: Codable, Identifiable {
    var id: String = ""
    var name: String = ""
    var type: String = ""
    var status: String = ""
    var health: String = ""          // healthy | warning | failed | disconnected | needs_configuration
    var baseUrl: String? = nil
    var endpoint: String? = nil
    var authType: String? = nil      // none | bearer | api_key
    var isEnabled: Bool = true
    var lastErrorMessage: String? = nil
}
struct IntegrationsListResponse: Codable {
    var items: [PublicIntegration] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(PublicIntegration.self, forKey: .items)
    }
}
struct IntegrationLog: Codable, Identifiable {
    var id: String = ""
    var timestamp: String? = nil
    var severity: String = "info"    // info | success | warning | error | critical
    var component: String = ""
    var summary: String = ""
    var correlationId: String? = nil
}
struct IntegrationLogsResponse: Codable {
    var items: [IntegrationLog] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(IntegrationLog.self, forKey: .items)
    }
}

// GET /api/integrations/message-flow -> { items:[event] }. Only scalar fields decoded
// (Codable ignores the variant-typed payloadSummary/requestPayload/headers/retryHistory).
struct MessageFlowEvent: Codable, Identifiable {
    var id: String = ""
    var timestamp: String? = nil
    var direction: String? = nil       // inbound | outbound
    var source: String? = nil
    var destination: String? = nil
    var eventType: String? = nil
    var status: String? = nil
    var responseCode: Int? = nil
    var latencyMs: Int? = nil
    var errorMessage: String? = nil
    var retryable: Bool? = nil
    var isRetryable: Bool { retryable ?? false }
}
struct MessageFlowResponse: Codable {
    var items: [MessageFlowEvent] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(MessageFlowEvent.self, forKey: .items)
    }
}
struct RetryResult: Codable { var ok: Bool = false; var retried: Bool = false; var status: String? = nil; var message: String? = nil }

// MARK: - WhatsApp accounts (health)

struct WhatsAppAccount: Codable, Identifiable {
    var id: String = ""
    var displayName: String = ""
    var phoneNumber: String? = nil
    var phoneNumberId: String? = nil
    var wabaId: String? = nil
    var businessName: String? = nil
    var status: String? = nil       // live Meta connection status
    var health: String? = nil       // healthy | failed | needs_configuration | ...
    var tokenStatus: String? = nil  // configured | missing
    var isActive: Bool = true
    var isDefault: Bool = false
    var webhookBehavior: String? = nil  // auto | accept | reject (call-permission requests)
}
struct WhatsAppAccountsResponse: Codable {
    var items: [WhatsAppAccount] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(WhatsAppAccount.self, forKey: .items)
    }
}
struct WhatsAppAccountResponse: Codable { var account: WhatsAppAccount? = nil }

// WhatsApp account CRUD + registration request bodies.
struct CreateWhatsappAccountRequest: Codable {
    var name: String
    var phoneNumberId: String
    var accessToken: String
    var displayPhoneNumber: String? = nil
    var wabaId: String? = nil
    var isActive: Bool = true
    var isDefault: Bool = false
}
struct UpdateWhatsappAccountRequest: Codable {
    var name: String? = nil
    var displayPhoneNumber: String? = nil
    var wabaId: String? = nil
    var accessToken: String? = nil
    var isActive: Bool? = nil
    var isDefault: Bool? = nil
    var webhookBehavior: String? = nil
}

// MARK: - Webhook center (GET /api/integrations/webhooks + admin config)

struct WebhookCenter: Codable {
    var sharedWebhookUrl: String? = nil
    var metaWebhookPath: String? = nil
    var metaVerifyToken: String? = nil
    var verificationStatus: String? = nil     // configured | needs_configuration
    var lastReceivedWebhook: String? = nil
    var failedWebhookCount: Int? = nil
    var retryCount: Int? = nil
}

struct WebhookConfig: Codable {
    var path: String? = nil
    var verifyToken: String? = nil
}
struct WebhookConfigResponse: Codable { var config: WebhookConfig? = nil }
struct UpdateWebhookConfigRequest: Codable {
    var path: String
    var verifyToken: String? = nil
}
struct RequestCodeRequest: Codable { var codeMethod: String; var language: String = "en_US" }
struct RegisterNumberRequest: Codable { var pin: String }

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
struct StatCustomersResponse: Codable {
    var items: [StatCustomer] = []

    private enum CodingKeys: String, CodingKey { case items }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.lossy(StatCustomer.self, forKey: .items)
    }
}

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

    private enum CodingKeys: String, CodingKey {
        case conversation, totals, statusBreakdown, agents, responseStats, timeline
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversation = c.lenient(CustomerReportConversation.self, forKey: .conversation)
        totals = c.lenient(CustomerReportTotals.self, forKey: .totals)
        statusBreakdown = c.lenient([String: Int].self, forKey: .statusBreakdown)
        agents = c.lossy(CustomerReportAgent.self, forKey: .agents)
        responseStats = c.lenient(CustomerReportResponseStats.self, forKey: .responseStats)
        timeline = c.lossy(CustomerReportTimelineItem.self, forKey: .timeline)
    }
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
