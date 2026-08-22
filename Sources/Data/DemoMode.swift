import Foundation

/// Screenshot/demo sessions: launched with the `-wx-demo` argument, the app
/// answers every API call from the canned fixtures below — no server, no
/// cookies, no sockets, no push registrations, nothing leaves the device.
/// Used by the WhatsXScreenshots UI tests (App Store screenshots on CI) and
/// handy for local demos. The fixture people and results are fictional.
enum DemoMode {
    static let active = ProcessInfo.processInfo.arguments.contains("-wx-demo")
}

enum DemoFixtures {

    /// JSON for the given API path; unknown paths decode as `{}`, which the
    /// lenient model decoders turn into harmless empty responses.
    static func payload(for path: String) -> Data {
        Data(json(for: path).utf8)
    }

    private static func json(for path: String) -> String {
        if path == "api/user" { return user }
        if path == "api/whatsapp/instances" { return instances }
        if path == "api/conversations/pins" { return #"{"pins":[]}"# }
        if path.hasPrefix("api/conversations/") && path.hasSuffix("/messages") { return messages }
        if path.hasPrefix("api/conversations/") && path.hasSuffix("/ai-draft") { return aiDraft }
        if path.hasPrefix("api/conversations/") && path.hasSuffix("/calls") { return #"{"total":0,"items":[]}"# }
        if path == "api/conversations" { return conversations }
        if path == "api/voice/calls/filters" { return callFilters }
        if path == "api/voice/calls" { return calls }
        if path == "api/statistics/customers" { return #"{"items":[]}"# }
        if path == "api/statistics" { return stats }
        if path == "api/ready-messages" { return readyMessages }
        if path == "api/integrations" { return integrations }
        if path == "api/users" { return users }
        if path == "api/roles" { return roles }
        return "{}"
    }

    /// ISO timestamp at a local wall-clock time, `dayOffset` days from today.
    private static func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: Date())) ?? Date()
        let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        return ISO8601DateFormatter().string(from: date)
    }

    /// Date-only bucket (yyyy-MM-dd) `dayOffset` days from today.
    private static func day(_ dayOffset: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: Date())) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static let user = """
    {"id":"u1","username":"mustafa","displayName":"مصطفى جابر","role":"مدير النظام",
     "effectivePermissions":["aiDrafts.view","aiDrafts.use","aiDrafts.regenerate"]}
    """

    private static let instances = """
    {"items":[
      {"id":"i1","name":"مختبر النور الرئيسي","displayPhoneNumber":"+964 771 000 1111","isActive":true},
      {"id":"i2","name":"فرع الكرادة","displayPhoneNumber":"+964 782 555 6677","isActive":true}
     ],"defaultInstanceId":"i1"}
    """

    private static var conversations: String {
        """
        {"total":8,"items":[
          {"id":"c1","instanceId":"i1","phone":"+9647712223344","displayName":"أم محمد",
           "lastAt":"\(at(0, 9, 41))","instance":{"id":"i1","name":"مختبر النور الرئيسي"},
           "metadata":{"lastMessage":"شكرًا جزيلًا لكم 🙏","unreadCount":2}},
          {"id":"c2","instanceId":"i2","phone":"+9647801112233","displayName":"أبو علي التميمي","pinned":true,
           "lastAt":"\(at(0, 9, 15))","instance":{"id":"i2","name":"فرع الكرادة"},
           "metadata":{"lastMessage":"متى يفتح الفرع يوم الجمعة؟","unreadCount":1}},
          {"id":"c3","instanceId":"i1","phone":"+9647705556677","displayName":"د. سارة الحسن",
           "lastAt":"\(at(0, 8, 50))","instance":{"id":"i1","name":"مختبر النور الرئيسي"},
           "metadata":{"lastMessage":"وصلتني النتائج، شكرًا للسرعة"}},
          {"id":"c4","instanceId":"i2","phone":"+9647709998877","displayName":"صيدلية النور",
           "lastAt":"\(at(-1, 18, 22))","instance":{"id":"i2","name":"فرع الكرادة"},
           "metadata":{"lastMessage":"نحتاج قائمة الأسعار المحدثة"}},
          {"id":"c5","instanceId":"i1","phone":"+9647714445566","displayName":"حسين كريم",
           "lastAt":"\(at(-1, 16, 5))","instance":{"id":"i1","name":"مختبر النور الرئيسي"},
           "metadata":{"lastMessage":"موعد السحب باچر الساعة 8 صباحًا؟"}},
          {"id":"c6","instanceId":"i1","phone":"+9647812223399","displayName":"شركة الرافدين للأدوية",
           "lastAt":"\(at(-1, 12, 40))","instance":{"id":"i1","name":"مختبر النور الرئيسي"},
           "metadata":{"lastMessage":"تم تحويل المبلغ، تجدون الإيصال مرفقًا"}},
          {"id":"c7","instanceId":"i2","phone":"+9647717778899","displayName":"نور الهدى",
           "lastAt":"\(at(-2, 19, 10))","instance":{"id":"i2","name":"فرع الكرادة"},
           "metadata":{"lastMessage":"التقرير وصل، الله يحفظكم"}},
          {"id":"c8","instanceId":"i1","phone":"+9647803334455","displayName":"مصطفى الأنصاري",
           "lastAt":"\(at(-2, 10, 30))","instance":{"id":"i1","name":"مختبر النور الرئيسي"},
           "metadata":{"lastMessage":"أحتاج فحص فيتامين د"}}
        ]}
        """
    }

    private static var messages: String {
        """
        {"total":7,"items":[
          {"id":"m1","conversationId":"c1","direction":"inbound","createdAt":"\(at(0, 9, 2))",
           "body":"السلام عليكم، حاب أستفسر عن نتيجة تحليل السكر التراكمي"},
          {"id":"m2","conversationId":"c1","direction":"outbound","status":"read","createdAt":"\(at(0, 9, 4))",
           "body":"وعليكم السلام، أهلًا بك 🌸 لحظة من فضلك أتحقق من النتيجة"},
          {"id":"m3","conversationId":"c1","direction":"inbound","createdAt":"\(at(0, 9, 5))",
           "body":"تفضل، الاسم أم محمد والعينة من يوم أمس"},
          {"id":"m4","conversationId":"c1","direction":"outbound","status":"read","createdAt":"\(at(0, 9, 7))",
           "body":"النتيجة جاهزة ✅ السكر التراكمي 5.4% — ضمن المعدل الطبيعي والحمد لله"},
          {"id":"m5","conversationId":"c1","direction":"inbound","createdAt":"\(at(0, 9, 8))",
           "body":"الحمد لله 🙏 ممكن ترسلون التقرير هنا؟"},
          {"id":"m6","conversationId":"c1","direction":"outbound","status":"delivered","createdAt":"\(at(0, 9, 9))",
           "body":"أكيد، جاري إرسال نسخة PDF من التقرير الكامل"},
          {"id":"m7","conversationId":"c1","direction":"inbound","createdAt":"\(at(0, 9, 41))",
           "body":"شكرًا جزيلًا لكم 🙏"}
        ]}
        """
    }

    private static var aiDraft: String {
        """
        {"draft":{"id":"d1","conversationId":"c1","status":"ready","channel":"lis",
          "draftText":"أهلًا بك 🌸 تم إرسال التقرير كاملًا. إذا احتجت شرح أي فقرة من النتائج فأنا بالخدمة.",
          "sources":["HbA1c"],"escalate":false,"createdAt":"\(at(0, 9, 42))","readyAt":"\(at(0, 9, 42))"}}
        """
    }

    private static let readyMessages = """
    {"items":[
      {"id":"r1","name":"مواعيد الدوام","body":"دوامنا يوميًا من 8 صباحًا حتى 10 مساءً، والجمعة من 2 ظهرًا.","isActive":true},
      {"id":"r2","name":"العنوان","body":"العنوان: شارع الكرادة الرئيسي، مقابل الجسر المعلق.","isActive":true},
      {"id":"r3","name":"استلام النتائج","body":"النتائج تصدر خلال 24 ساعة وترسل لكم هنا مباشرة.","isActive":true}
    ]}
    """

    private static var calls: String {
        """
        {"total":6,"items":[
          {"id":"v1","callId":"v1","phone":"+9647712223344","displayName":"أم محمد","direction":"inbound",
           "status":"answered","startedAt":"\(at(0, 9, 32))","durationSeconds":190,
           "instance":{"id":"i1","name":"مختبر النور الرئيسي"},"recording":"rec-v1.mp3"},
          {"id":"v2","callId":"v2","phone":"+9647801112233","displayName":"أبو علي التميمي","direction":"outbound",
           "status":"answered","startedAt":"\(at(0, 9, 20))","durationSeconds":84,
           "instance":{"id":"i2","name":"فرع الكرادة"},"recording":"rec-v2.mp3"},
          {"id":"v3","callId":"v3","phone":"+9647714445566","displayName":"حسين كريم","direction":"inbound",
           "status":"missed","outcome":"missed","startedAt":"\(at(0, 8, 12))","durationSeconds":0,
           "instance":{"id":"i1","name":"مختبر النور الرئيسي"}},
          {"id":"v4","callId":"v4","phone":"+9647705556677","displayName":"د. سارة الحسن","direction":"outbound",
           "status":"answered","startedAt":"\(at(-1, 17, 45))","durationSeconds":132,
           "instance":{"id":"i1","name":"مختبر النور الرئيسي"}},
          {"id":"v5","callId":"v5","phone":"+9647709998877","displayName":"صيدلية النور","direction":"inbound",
           "status":"rejected","outcome":"rejected","startedAt":"\(at(-1, 13, 5))","durationSeconds":0,
           "instance":{"id":"i2","name":"فرع الكرادة"}},
          {"id":"v6","callId":"v6","phone":"+9647812223399","displayName":"شركة الرافدين للأدوية","direction":"inbound",
           "status":"answered","startedAt":"\(at(-2, 11, 22))","durationSeconds":322,
           "instance":{"id":"i1","name":"مختبر النور الرئيسي"}}
        ]}
        """
    }

    private static let callFilters = """
    {"accounts":[
      {"id":"i1","name":"مختبر النور الرئيسي","displayPhoneNumber":"+964 771 000 1111"},
      {"id":"i2","name":"فرع الكرادة","displayPhoneNumber":"+964 782 555 6677"}
     ],"agents":["mustafa"]}
    """

    private static var stats: String {
        let series = (0..<7).map { i -> String in
            let values = [(210, 160), (180, 120), (260, 190), (320, 240), (410, 300), (280, 210), (300, 220)][i]
            return #"{"bucket":"\#(day(i - 6))","incoming":\#(values.0),"outgoing":\#(values.1)}"#
        }.joined(separator: ",")
        return """
        {"totals":{"conversations":128,"messages":3420,"incoming":1980,"outgoing":1440,"users":4},
         "series":[\(series)],
         "instanceBreakdown":[
           {"id":"i1","name":"مختبر النور الرئيسي","totals":{"messages":2100,"conversations":80}},
           {"id":"i2","name":"فرع الكرادة","totals":{"messages":1320,"conversations":48}}],
         "delivery":{"sent":410,"delivered":1280,"read":1620,"failed":12},
         "userStats":[]}
        """
    }

    private static let integrations = """
    {"items":[
      {"id":"g1","name":"نظام المختبر (LIS)","type":"lis","status":"active","health":"healthy",
       "baseUrl":"https://lis.example.iq","isEnabled":true},
      {"id":"g2","name":"بوابة المواعيد","type":"webhook","status":"active","health":"healthy",
       "baseUrl":"https://booking.example.iq","isEnabled":true}
    ]}
    """

    private static let users = """
    {"items":[
      {"id":"u1","username":"mustafa","displayName":"مصطفى جابر","role":"مدير النظام"},
      {"id":"u2","username":"zahraa","displayName":"زهراء","role":"موظف"},
      {"id":"u3","username":"hussein","displayName":"حسين","role":"موظف"}
    ]}
    """

    private static let roles = """
    {"items":[
      {"id":"ro1","name":"مدير النظام","isSystem":true,"permissions":[]},
      {"id":"ro2","name":"مشرف","isSystem":false,"permissions":[]},
      {"id":"ro3","name":"موظف","isSystem":false,"permissions":[]}
    ]}
    """
}
