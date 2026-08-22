# ملاحظات النشر على App Store — WhatsX

بيانات جاهزة للّصق في App Store Connect، والقرارات التي يجب حسمها قبل أول رفع.

---

## الهوية

- **الاسم:** WhatsX
- **Bundle ID:** `com.m-s-jaber.whatsx`
- **النسخة:** 1.25.0 (تطابق `MARKETING_VERSION` في `project.yml`)
- **التصنيف:** Business (ثانوي: Productivity)
- **الأجهزة:** iPhone + iPad (native)، iOS 16.0+
- **اللغات:** العربية (الأساسية، RTL)، الإنجليزية
- **نموذج النشر:** مجاني، بدفع خارج التطبيق وفق Guideline **3.1.3(b)**

---

## ⚠️ قرار الاستضافة — احسمه قبل أي رفع

هذا القرار يحدد **بطاقة الخصوصية** و**`PrivacyInfo.xcprivacy`** معاً، وتغييره
بعد النشر يستلزم تحديث الإعلان ومراجعة جديدة.

### الوضع الحالي المُعلَن: `Data Not Collected`

`Resources/PrivacyInfo.xcprivacy` يعلن حالياً **عدم جمع أي بيانات**. هذا صحيح
بشرط واحد: **أن يستضيف كل عميل خادم WhatsX الخاص به**، فلا تصل أنت — المطوّر —
إلى بيانات أي عميل. التطبيق عندها مجرد عميل يتصل بخادم يملكه المستخدم، تماماً
كتطبيقات Nextcloud و Home Assistant و Mastodon.

### إن كنت تستضيف خادماً مركزياً

البيانات تُعدّ **مجموعة منك**، ويجب:

1. تعديل `Resources/PrivacyInfo.xcprivacy` لإعلان الأنواع التالية بـ
   `Linked = true` و `Tracking = false`:

   | النوع | ما يقابله في التطبيق |
   |---|---|
   | `NSPrivacyCollectedDataTypeName` | اسم المستخدم واسم العرض |
   | `NSPrivacyCollectedDataTypePhoneNumber` | أرقام هواتف العملاء في المحادثات |
   | `NSPrivacyCollectedDataTypeMessages` | نصوص المحادثات |
   | `NSPrivacyCollectedDataTypePhotosorVideos` | الصور والفيديو المرسلة |
   | `NSPrivacyCollectedDataTypeAudioData` | الرسائل الصوتية |

2. الإجابة بما يطابقها في App Store Connect → App Privacy.
3. تحديث `docs/privacy/index.html` ليصف الاستضافة المركزية بدل الذاتية.

> **الأمان أولاً:** إن كنت تستضيف لبعض العملاء فقط، أعلن الجمع. Apple تقيّم
> أسوأ الحالات، والإعلان الناقص سبب معروف للرفض ولإزالة التطبيق لاحقاً.

---

## الخصوصية — ما جرى التحقق منه في الشيفرة

- **التتبّع:** لا شيء. `NSPrivacyTracking = false`، ولا نطاقات تتبّع.
- **SDK أطراف ثالثة:** **صفر**. `Package.swift` بلا أي تبعية خارجية.
- **تحليلات:** لا Firebase ولا Crashlytics ولا Sentry ولا أي معرّف إعلاني.
- **الإشعارات:** منذ 1.19.0 تصل إشعارات الرسائل عن بُعد عبر APNs، ورمز
  الجهاز يُرسل إلى **خادم العميل الذاتي فقط** (لا طرف ثالث). بقرار المالك،
  حمولة الإشعار تحمل **اسم المرسل فقط** — نص الرسالة لا يعبر خوادم Apple
  أبداً (انظر `MessagePush.swift` و `docs/VOIP_PUSH.md`).
- **واجهات السبب المصرَّح:** `UserDefaults` فقط، بالسبب `CA92.1`.
  `FileManager` مستخدم في `temporaryDirectory` و `removeItem` وهما خارج
  قائمة الواجهات التي تتطلب إفصاحاً.
- **النقل:** `AppConfig.normalized()` يفرض `https` ويرفّع أي `http` تلقائياً —
  بيانات العملاء لا تسافر بلا تشفير.

**رابط سياسة الخصوصية:** صفحة جاهزة ثنائية اللغة في `docs/privacy/index.html`.
أسهل استضافة: فعّل GitHub Pages من Settings → Pages → Deploy from branch →
`main` / مجلد `/docs`، فتُقدَّم على:
`https://m-s-jaber.github.io/WhatsX-iOS/privacy/`

---

## أوصاف الصلاحيات

معلنة في `Resources/Info.plist`، وكلها تُطلب عند أول استخدام للميزة:

| المفتاح | الميزة |
|---|---|
| `NSMicrophoneUsageDescription` | المكالمات الصوتية وتسجيل الرسائل الصوتية |
| `NSCameraUsageDescription` | التقاط صورة الملف الشخصي والوسائط |
| `NSPhotoLibraryUsageDescription` | إرسال الصور وتعيين صورة الملف الشخصي |
| `NSFaceIDUsageDescription` | قفل التطبيق لحماية محادثات العملاء |

**entitlement واحد فقط**: `aps-environment` (دفعات VoIP لرنين المكالمات
والتطبيق مغلق — أُضيف في 1.18.0 بقرار المالك). لا Apple Pay ولا Wallet ولا
Sign in with Apple ولا Network Extension.

> Note (1.16.0): live call audio adds `UIBackgroundModes: audio` — an
> Info.plist capability. Mention in-app WhatsApp calling in the review notes.

> Note (1.18.0): VoIP call push adds `UIBackgroundModes: voip` + the
> `aps-environment` entitlement (Push Notifications capability on the App
> ID). For a future **App Transfer**: push capability does not block a
> transfer, but APNs auth keys are per-account — the receiving account must
> create its own `.p8` and the server must switch to it after the transfer.

---

## 🔑 حساب المراجعة — سبب الرفض الأول الأكثر شيوعاً

WhatsX يُستضاف ذاتياً ولا يعمل بلا خادم. مراجع Apple سيفتح التطبيق ويجد شاشة
دخول تطلب عنوان خادم لا يملكه. **بدون تجهيز مسبق سيُرفض التطبيق حتماً** تحت
Guideline **2.1 (App Completeness)**.

في App Store Connect → App Review Information، املأ:

- **Sign-in required:** نعم
- **Username / Password:** حساب تجريبي فعّال على خادم يعمل
- **Notes:** نص يشرح الخطوة الإضافية، مثلاً:

```
This app connects to a self-hosted WhatsX server; there is no default server.

To sign in:
1. Open the app and expand "Server settings" on the login screen
   (it expands automatically on first launch).
2. Enter this server address:  https://demo.example.com
3. Sign in with the username and password provided above.

The demo server is kept online for the duration of the review.
The app is free; billing is handled outside the app for business
customers, in line with Guideline 3.1.3(b).
```

> ⚠️ استبدل `https://demo.example.com` بعنوان خادم تجريبي **يعمل فعلاً طوال
> فترة المراجعة**. هذا أهم سطر في هذا الملف.

---

## بيانات المتجر

### الاسم الفرعي (Subtitle، حتى 30 محرفاً)
```
إدارة محادثات واتساب للأعمال
```

### الكلمات المفتاحية (حتى 100 محرف، بفواصل بلا مسافات)
```
واتساب,محادثات,أعمال,عملاء,دعم,مبيعات,whatsapp,business,crm,inbox
```

### الوصف (مسوّدة — راجعها وعدّلها)

```
WhatsX منصة لإدارة محادثات واتساب لفرق الأعمال، بواجهة عربية كاملة
تدعم الكتابة من اليمين إلى اليسار.

الميزات:
• إدارة عدة حسابات واتساب من تطبيق واحد
• صندوق وارد موحّد لكل المحادثات مع بحث شامل
• إرسال واستقبال النصوص والصور والفيديو والمستندات والرسائل الصوتية
• تقارير وإحصاءات عن أداء الفريق مع تصدير PDF
• صلاحيات متعددة المستخدمين وأدوار للفريق
• قفل التطبيق ببصمة الوجه لحماية محادثات العملاء
• إشعارات فورية للرسائل والمكالمات الواردة
• مظهر فاتح وداكن، ودعم كامل لأحجام الخطوط والقارئ الصوتي

يتطلب WhatsX خادماً خاصاً بمؤسستك. أدخل عنوان الخادم عند أول تشغيل.

الاستخدام للأعمال؛ الاشتراك يُدار خارج التطبيق.
```

> ⚠️ لا تكتب في الوصف أي رابط شراء أو إشارة إلى سعر أو طريقة دفع — هذا يخالف
> Guideline 3.1.1 ويسبب رفضاً حتى مع نموذج 3.1.3(b).

### لقطات الشاشة المطلوبة

| المقاس | الجهاز | العدد |
|---|---|---|
| 6.9" (1320×2868) | iPhone Pro Max | 3–10 |
| 13" (2064×2752) | iPad Pro 13" — إلزامي لأن التطبيق iPad أصلي | 3–10 |

> مقاس 6.5" لم يعد إلزامياً — App Store Connect يشتق الأصغر من 6.9" تلقائياً.

**التوليد آلي بلا Mac** — workflow جاهز:

1. Actions → **ios-screenshots** → Run workflow (يدوي، بلا أي أسرار).
2. ينتظر ~15 دقيقة: يشغّل التطبيق في **وضع العرض التجريبي** (بيانات وهمية
   عربية عبر `-wx-demo`؛ انظر `Sources/Data/DemoMode.swift`) على محاكي
   iPhone Pro Max و iPad Pro 13"، بشريط حالة 9:41 مثالي.
3. نزّل artifact باسم `appstore-screenshots`: خمس لقطات لكل جهاز —
   الصندوق، محادثة مفتوحة (مع شريحة الرد الذكي)، المكالمات، التقارير،
   الإعدادات — بالمقاسات الرسمية جاهزة للرفع إلى App Store Connect.

---

## قائمة تحقق قبل الرفع

- [ ] حُسم **قرار الاستضافة** وضُبط `PrivacyInfo.xcprivacy` بما يطابقه
- [ ] فُعّلت GitHub Pages ونُسخ رابط سياسة الخصوصية
- [ ] جُهّز حساب مراجعة وخادم تجريبي يعمل، وكُتبت ملاحظات المراجع
- [ ] شُغّل ios-screenshots ورُفعت لقطات الشاشة بالمقاسين (iPhone + iPad)
- [ ] وُقّعت اتفاقية **Free Apps** (لا Paid Apps)
- [ ] صُنّف المحتوى عمرياً (Age Rating) — 4+ متوقّع
- [ ] رُفع أول بناء عبر `ios-release` وظهر في TestFlight
