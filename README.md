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
Playgrounds، أضِف هذه الحزمة كاعتمادية من رابط GitHub (يلتقط Playgrounds أحدث
**وسم إصدار** تلقائيًّا — 1.1.1 أو أحدث)، ثم:

The package holds the whole app and exposes a single root view `WhatsXRoot()`. In
Swift Playgrounds, create an **App**, add this repo as a **Swift Package** dependency
(Playgrounds resolves the latest **release tag** automatically — 1.1.1+), then:

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
- **تحديثات فورية** عبر WebSocket (`/ws`): رسائل واردة/صادرة وحالاتها، تثبيت/أرشفة، ومكالمات — بلا تحديث يدوي، مع إعادة اتصال تلقائية ونبضة حضور.
- **بحث داخل المحادثة** مع عدّاد نتائج وتنقّل سابق/تالٍ وتمييز الرسالة.
- **الرد الاقتباسي**: ضغطة مطوّلة ← «رد»، مع معاينة الاقتباس في الفقاعة والملحّن + «نسخ».
- **أحداث المكالمات داخل خط زمن المحادثة** (واردة/صادرة/فائتة مع المدة).
- **لوحة معلومات المحادثة**: حول (الحالة/النبذة/آخر ظهور/الموقع/التصنيفات) + معارض الوسائط والملفات والروابط المشتركة.
- **فلتر الحسابات المتعددة** في صندوق المحادثات (شرائح لكل حساب واتساب).
- **رسائل الموقع الجغرافي**: خريطة مصغّرة (MapKit) بالاسم/العنوان، تفتح في الخرائط.
- **فواصل التواريخ** (اليوم/أمس/التاريخ) داخل خط زمن المحادثة.
- **شارة غير المقروء** على تبويب المحادثات، تتحدث لحظيًا مع الأحداث الفورية.
- **إشعارات محلية** (صوت + لافتة نظام) للرسائل والمكالمات الواردة أثناء تشغيل التطبيق، مع مفتاح تحكم في الإعدادات — البديل الممكن داخل Playgrounds عن APNs.
- **لافتة المكالمة الواردة** أعلى الشاشة فور الرنين، مع **رفض المكالمة** فعليًا عبر Meta، وتختفي تلقائيًا إذا ردّ موظف آخر.
- **طلب إذن الاتصال** من شاشة المحادثة (زر الهاتف) — رسالة Meta تفاعلية للعميل.
- **سبب فشل الإرسال** يظهر تحت الرسالة الفاشلة (errorTitle/details من الخادم).

## لم يُنقل بعد — Not yet ported
**صوت المكالمات الحيّة (WebRTC)** و**إشعارات الخلفية (APNs/FCM)** فقط — يتطلبان
مكتبات ثنائية وصلاحيات native لا تتوفر لتطبيقات Swift Playgrounds، ويُنجزان على الماك.
(المتوفر بدلًا عنهما داخل الحزمة: لافتة المكالمة الواردة مع الرفض وطلب إذن الاتصال،
وإشعارات محلية أثناء عمل التطبيق.)
Only **live call audio (WebRTC)** and **background push (APNs/FCM)** remain — both
need binary libs/entitlements unavailable to Swift Playgrounds apps (in-package
stand-ins: the incoming-call banner with reject + call-permission request, and
local notifications while the app runs).

## ملاحظات — Notes
- **Liquid Glass**: الحزمة تشترط **iOS 16** فقط كي تُحمَّل في Swift Playgrounds؛ على **iOS 26** تُعرض البطاقات والشرائح وشريط التبويبات بزجاج Liquid Glass الأصلي تلقائيًّا، وعلى الأنظمة الأقدم تعود لأسطح Luxe الكلاسيكية (انظر `Sources/Design/Glass.swift`).
  The package only requires **iOS 16** so it loads in Swift Playgrounds; on **iOS 26** cards, chips and the tab bar render on native Liquid Glass automatically, falling back to classic Luxe surfaces on older systems (see `Sources/Design/Glass.swift`).
- **الأيقونات**: مجموعة أندرويد الخطّية المخصّصة مُطابَقة إلى **SF Symbols** (المكافئ الطبيعي في iOS).
- **الألوان**: تعكس ثيم Luxe Amber (Color.kt) وتتكيّف فاتح/داكن تلقائيًّا.
- **JSON**: أسماء الحقول تتبع نماذج أندرويد؛ إن رفض الخادم حقلًا snake_case أضف `CodingKeys`.
- **معرّف الحزمة**: `net.alnokhba.whatsx` (منفصل عن أندرويد؛ عدّله قبل النشر إن لزم).
