# WhatsX — iOS (SwiftUI)

نسخة **iOS بلغة Swift/SwiftUI** من تطبيق WhatsX، تتحدّث إلى **نفس خادم REST** الذي
يستخدمه تطبيق أندرويد (مصادقة عبر الكوكيز). هذه **نسخة أولى (v1)**: الأساس + الشاشات
الرئيسية. باقي الميزات تُنقل تباعًا.

A **Swift/SwiftUI iOS port** of WhatsX, talking to the **same REST backend** as the
Android app (cookie session auth). This is a **v1 scaffold** — foundation + core
screens; remaining features are ported incrementally.

> ⚠️ يتطلّب **macOS + Xcode 15+** للبناء والتشغيل (لا يُبنى على Windows).

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

## البنية — Structure

```
Sources/
  App/       WhatsXApp (entry) · RootView · MainTabView (floating bottom nav + FAB)
  Design/    Theme (amber Luxe colors) · WIcon (→ SF Symbols) · Avatar
  Data/      Models (Codable) · Api (URLSession) · Session (auth state)
  Features/  Login · Inbox (+NewConversation) · Chat · Calls · Stats · Settings
Resources/   Info.plist
project.yml  XcodeGen spec
```

## المُنجز — Implemented (v1)
- تسجيل الدخول (هيرو كهرماني + إعداد الخادم).
- الصندوق: أقسام (النشطة/غير المقروءة/المؤرشفة) + بحث + صفوف المحادثات + تنقّل للمحادثة.
- المحادثة: فقاعات (وارد/صادر) + ملحّن + إرسال.
- المكالمات: شرائح تصفية + صفوف المكالمات (أيقونة اتجاه ملوّنة).
- الإحصائيات: شرائح المدى + بطاقات KPI + بلاطات الحالات.
- الإعدادات: بطاقة الملف + أقسام بنمط التصميم + تسجيل خروج.
- محادثة جديدة (نافذة سفلية).
- الهوية الكهرمانية + RTL + أيقونات SF Symbols.

## لم يُنقل بعد — Not yet ported
التكاملات (التفصيل)، المكالمات الصوتية الحيّة (WebRTC)، إشعارات FCM في الخلفية،
القوالب والردود، المستخدمون والأدوار، مركز الإشعارات، رفع صورة الملف، تقارير العملاء،
تشغيل التسجيلات، والوسائط (صور/صوت/مستندات) داخل المحادثة.

## ملاحظات — Notes
- **الأيقونات**: مجموعة أندرويد الخطّية المخصّصة مُطابَقة إلى **SF Symbols** (المكافئ الطبيعي في iOS).
- **الألوان**: تعكس ثيم Luxe Amber (Color.kt) وتتكيّف فاتح/داكن تلقائيًّا.
- **JSON**: أسماء الحقول تتبع نماذج أندرويد؛ إن رفض الخادم حقلًا snake_case أضف `CodingKeys`.
- **معرّف الحزمة**: `net.alnokhba.whatsx` (منفصل عن أندرويد؛ عدّله قبل النشر إن لزم).
