# WhatsX — iOS (SwiftUI)

نسخة **iOS بلغة Swift/SwiftUI** من تطبيق WhatsX، تتحدّث إلى **نفس خادم REST** الذي
يستخدمه تطبيق أندرويد (مصادقة عبر الكوكيز). هذه **نسخة أولى (v1)**: الأساس + الشاشات
الرئيسية. باقي الميزات تُنقل تباعًا.

A **Swift/SwiftUI iOS port** of WhatsX, talking to the **same REST backend** as the
Android app (cookie session auth). This is a **v1 scaffold** — foundation + core
screens; remaining features are ported incrementally.

> ⚠️ للبناء الكامل: **macOS + Xcode 15+** (لا يُبنى على Windows).
> 📱 المشروع أيضًا **Swift Package** (`Package.swift` بالجذر) يمكن استيراده على **iPad عبر Swift Playgrounds** — انظر قسم «على الآيباد».
>
> ⚠️ Full build needs **macOS + Xcode 15+** (not buildable on Windows).
> 📱 It's also a **Swift Package** (`Package.swift` at the root) importable on **iPad via Swift Playgrounds** — see "On iPad".

---

## التشغيل — Getting started

على جهاز Mac / On a Mac:

```bash
brew install xcodegen        # once
cd WhatsX-iOS
xcodegen generate            # creates WhatsX.xcodeproj
open WhatsX.xcodeproj         # then set Signing Team, Run on a simulator/device
```

اضبط رابط الخادم من **شاشة تسجيل الدخول ← إعدادات الخادم**، أو غيّر `AppConfig.defaultBaseURL`
في `Sources/Data/Api.swift`. يجب أن يكون **نطاقًا ثابتًا عامًّا (https)**.
Set the server URL from **Login → Server settings**, or edit `AppConfig.defaultBaseURL`
in `Sources/Data/Api.swift`. It must be a **stable public https domain**.

## على الآيباد — On iPad (Swift Playgrounds)

الحزمة تحتوي كامل التطبيق وتكشف واجهة جذر واحدة `WhatsXRoot()`. أنشئ تطبيقًا في Swift
Playgrounds، أضِف هذه الحزمة كاعتمادية من رابط GitHub مربوطة بالفرع `main`، ثم:

The package holds the whole app and exposes a single root view `WhatsXRoot()`. In
Swift Playgrounds, create an **App**, add this repo as a **Swift Package** dependency
pinned to the **`main`** branch, then:

```swift
import SwiftUI
import WhatsX          // the package/library module

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { WhatsXRoot() }   // wires session + RTL + bootstrap
    }
}
```

> الأذونات (ميكروفون للرسائل الصوتية، صور للإرفاق) تُضاف في **إعدادات تطبيق الآيباد**، لا في الحزمة.
> Permissions (microphone for voice notes, photos for attachments) go on the **iPad app**, not the package.

## البنية — Structure

```
Package.swift  Swift Package manifest (library "WhatsX", iOS 16)
Sources/
  App/       WhatsXRoot (public entry) · RootView · MainTabView · WhatsXApp (@main, macOS-only, excluded from package)
  Design/    Theme (amber Luxe colors) · WIcon (→ SF Symbols) · Avatar · AudioMessage
  Data/      Models (Codable) · Api (URLSession) · Session (auth state)
  Features/  Login · Inbox (+NewConversation) · Chat · Calls · Stats · Settings · Integrations · Admin
Resources/   Info.plist
project.yml  XcodeGen spec (Mac build)
```

## المُنجز — Implemented
- تسجيل الدخول (هيرو كهرماني + إعداد الخادم).
- الصندوق: أقسام (النشطة/غير المقروءة/المؤرشفة) + بحث + أرشفة/حذف/**تثبيت** (المثبّتة تُجلب وتطفو للأعلى).
- المحادثة: فقاعات + ملحّن + نصّ + **وسائط (صورة/مستند)** + **رسالة صوتية** (تسجيل) + **ردود جاهزة** + **إرسال قالب** (بمتغيّرات) + **إعادة إرسال** الفاشلة.
- المكالمات: شرائح تصفية + صفوف بأيقونة اتجاه ملوّنة.
- الإحصائيات: شرائح المدى + KPI + بلاطات الحالات + **تقارير العملاء**.
- الإعدادات: الملف + رفع الصورة (PhotosPicker) + أقسام + خروج.
- الإدارة: المستخدمون (إنشاء/**تعديل الدور والكلمة**/حذف) + **الأدوار (إنشاء/حذف)** + القوالب والردود (CRUD) + صحّة حسابات واتساب.
- التكاملات: نظرة عامة/خارجية/سجلّات + اختبار/تفعيل/تعطيل + CRUD.
- الهوية الكهرمانية + RTL + أيقونات SF Symbols.

## لم يُنقل بعد — Not yet ported
المكالمات الصوتية الحيّة (WebRTC)، إشعارات APNs في الخلفية، ومركز الإشعارات —
جميعها تتطلّب مكتبات/صلاحيات native ويُفضَّل إنجازها على الماك.
Live WebRTC calling, background APNs push, and a notification center — all need
native libs/entitlements, best done on the Mac.

## ملاحظات — Notes
- **الأيقونات**: مجموعة أندرويد الخطّية المخصّصة مُطابَقة إلى **SF Symbols** (المكافئ الطبيعي في iOS).
- **الألوان**: تعكس ثيم Luxe Amber (Color.kt) وتتكيّف فاتح/داكن تلقائيًّا.
- **JSON**: أسماء الحقول تتبع نماذج أندرويد؛ إن رفض الخادم حقلًا snake_case أضف `CodingKeys`.
- **معرّف الحزمة**: `net.alnokhba.whatsx` (منفصل عن أندرويد؛ عدّله قبل النشر إن لزم).
