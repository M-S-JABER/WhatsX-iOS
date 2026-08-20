# دليل الإعداد — WhatsX iOS

بناء ونشر التطبيق **بلا جهاز Mac**. كل ما يحتاج macOS يجري داخل runner على
GitHub Actions. أوامر جهازك بـ PowerShell، وهناك مسار كامل عبر المتصفح
للعمل من الآيباد.

---

## 1. كيف يعمل هذا الخط

```
project.yml  ──XcodeGen──▶  WhatsX.xcodeproj  ──gym──▶  .ipa  ──▶  TestFlight
   (نص)         داخل الرنر      (لا يُرفع للمستودع)              عبر API Key
```

`WhatsX.xcodeproj` **لا يوجد في المستودع ولن يوجد**. يولَّد من `project.yml`
في كل بناء داخل الـ runner. هذا ما يغنيك عن Xcode وعن Mac تماماً.

### الـ workflows الثلاثة

| Workflow | متى يعمل | يحتاج أسراراً؟ | الناتج |
|---|---|---|---|
| `ios-build` | كل push و PR | ❌ لا | `.ipa` غير موقّع للتنزيل |
| `ios-certificates` | يدوياً | ✅ نعم | توليد/تحقق الشهادات |
| `ios-release` | يدوياً أو وسم `v*` | ✅ نعم | رفع إلى TestFlight |

> **ابدأ الآن:** `ios-build` يعمل **فوراً** بلا حساب مطوّر ولا أسرار. اذهب إلى
> Actions → ios-build → Run workflow، ونزّل الـ IPA من قسم Artifacts. أعد
> توقيعه بـ AltStore أو Sideloadly لتجربته على جهاز حقيقي. هذه طريقتك
> الوحيدة للتجربة قبل تفعيل الحساب.

---

## 2. القيم المعلّقة — من أين تُستخرج كل واحدة

جدول المصادر. لا تملأ شيئاً منها قبل أن تتحول البوابة من `(Pending)` إلى مفعّلة.

### `TEAM_ID`
سلسلة من 10 محارف مثل `A1B2C3D4E5`.
> developer.apple.com → تسجيل الدخول → **Account** → **Membership details** → حقل **Team ID**

### `APP_STORE_CONNECT_KEY_ID` و `APP_STORE_CONNECT_ISSUER_ID` و `APP_STORE_CONNECT_KEY_P8`
الثلاثة من مكان واحد:
> appstoreconnect.apple.com → **Users and Access** → تبويب **Integrations** → **App Store Connect API** → **Team Keys**

1. اضغط **+** لإنشاء مفتاح جديد.
2. الاسم: `GitHub Actions CI` (أي اسم).
3. **الصلاحية: `Admin`.** لا تختر `Developer` — لن يستطيع توليد الشهادات ولا تسجيل التطبيق، وسيفشل `bootstrap` برسالة صلاحيات غامضة.
4. بعد الإنشاء:
   - **`KEY_ID`** = العمود المسمّى Key ID (10 محارف).
   - **`ISSUER_ID`** = معروض أعلى الجدول بصيغة UUID، ومشترك لكل المفاتيح.
   - **`KEY_P8`** = زر **Download API Key**. ⚠️ **التنزيل متاح مرة واحدة فقط ولا يتكرر.** احفظه فوراً في مكان آمن.

**محتوى الـ `.p8`:** افتحه بمحرر نصوص والصق **محتواه كاملاً** بما فيه سطرا
`-----BEGIN PRIVATE KEY-----` و `-----END PRIVATE KEY-----`. الـ Fastfile
يكتشف الصيغة تلقائياً، فلا حاجة لترميز base64 — وهذا مقصود ليسهل اللصق من
الآيباد.

### `MATCH_PASSWORD`
عبارة التشفير التي اخترتها لمستودع الشهادات. **ليست** كلمة مرور Apple.
اختر عبارة قوية واحفظها في مدير كلمات مرور — فقدانها يعني أن الشهادات
المخزّنة تصبح غير قابلة لفك التشفير وتضطر لتوليدها من جديد.

### `MATCH_GIT_TOKEN`
> github.com → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → Generate new token

الصلاحية المطلوبة: **`repo`** فقط. الصلاحية تكفي للقراءة والكتابة على
مستودع `certificates` الخاص.

### `MATCH_GIT_URL` (اختياري)
`https://github.com/M-S-JABER/certificates` — إن تركته فارغاً يُستخدم هذا
العنوان افتراضياً من `fastlane/Matchfile`.

---

## 3. إضافة الأسرار

### من الآيباد أو أي متصفح (الأسهل)
> المستودع → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

أضف واحداً واحداً. للـ `.p8` الصق النص متعدد الأسطر كما هو — واجهة GitHub
تقبله بلا مشاكل.

### من PowerShell على Windows Server
يتطلب [GitHub CLI](https://cli.github.com/):

```powershell
# مرة واحدة: تسجيل الدخول
gh auth login

Set-Location C:\Projects\WhatsX-iOS

# القيم النصية القصيرة
gh secret set TEAM_ID --body "A1B2C3D4E5"
gh secret set APP_STORE_CONNECT_KEY_ID --body "XXXXXXXXXX"
gh secret set APP_STORE_CONNECT_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set MATCH_PASSWORD --body "عبارة-التشفير-التي-اخترتها"
gh secret set MATCH_GIT_TOKEN --body "ghp_xxxxxxxxxxxxxxxxxxxx"
gh secret set MATCH_GIT_URL --body "https://github.com/M-S-JABER/certificates"

# ملف الـ .p8 — يُقرأ من الملف مباشرة، أدق من اللصق اليدوي
gh secret set APP_STORE_CONNECT_KEY_P8 `
  --body (Get-Content "C:\Projects\keys\AuthKey_XXXXXXXXXX.p8" -Raw)

# تأكد من أن الستة موجودة
gh secret list
```

---

## 4. الترتيب الدقيق للخطوات عند تفعيل الحساب

نفّذها بهذا الترتيب حصراً. كل خطوة تعتمد على ما قبلها.

### الخطوة 0 — قبل التفعيل (يمكنك فعلها الآن)
- [ ] شغّل `ios-build` وتأكد أنه أخضر ✅
- [ ] نزّل الـ IPA غير الموقّع وجرّبه عبر AltStore على جهازك
- [ ] تأكد أن مستودع `certificates` خاص وفيه فرع `main`

### الخطوة 1 — تأكيد التفعيل
افتح developer.apple.com. اختفاء بانر `Purchase your membership` وظهور
**Certificates, Identifiers & Profiles** في القائمة = الحساب مفعّل.

> ⚠️ لا تضغط `complete your purchase now` مهما طال الانتظار. الدفع تم
> ومؤكد. الأمر مزامنة بين نظام اشتراكات App Store والبوابة، ومدتها حتى
> 48 ساعة. الضغط قد يُنشئ اشتراكاً ثانياً مدفوعاً.

### الخطوة 2 — توقيع اتفاقية Free Apps
> appstoreconnect.apple.com → **Business** (أو Agreements, Tax, and Banking)
> → اتفاقية **Free Apps** → وافق عليها

كافية تماماً لنموذجك B2B. **لا توقّع Paid Apps Agreement** — هي وحدها التي
تستلزم حساباً بنكياً ونماذج ضريبية أمريكية.

> ⚠️ بدون توقيع هذه الاتفاقية سيفشل `bootstrap` عند خطوة إنشاء التطبيق
> برسالة عن اتفاقيات غير مكتملة.

### الخطوة 3 — إنشاء مفتاح API
راجع القسم 2 أعلاه. **الصلاحية `Admin`.**

### الخطوة 4 — إضافة الأسرار الستة
راجع القسم 3.

### الخطوة 5 — توليد الشهادات (مرة واحدة في العمر)
> Actions → **ios-certificates** → Run workflow
> - `mode` = **`bootstrap`**
> - `confirm` = **`CREATE`**

هذا هو الـ workflow الذي يحل مشكلة عدم امتلاكك Mac. ينفّذ داخل الرنر:
1. تسجيل `com.m-s-jaber.whatsx` في بوابة المطورين
2. إنشاء سجل التطبيق في App Store Connect
3. توليد شهادة التوزيع وملف التزويد
4. تشفيرهما ورفعهما إلى مستودع `certificates`

بعد نجاحه، افتح مستودع `certificates` — ستجد مجلدات `certs/` و `profiles/`
فيها ملفات مشفّرة. **لا تشغّل `bootstrap` مرة أخرى بعد ذلك.**

### الخطوة 6 — التحقق
> Actions → **ios-certificates** → Run workflow → `mode` = **`verify`**

أخضر = خط التوقيع سليم.

### الخطوة 7 — أول رفع إلى TestFlight
> Actions → **ios-release** → Run workflow → اكتب ملاحظات البناء

بعد اكتمال معالجة Apple (10–30 دقيقة عادةً) سيظهر البناء في
App Store Connect → TestFlight.

---

## 5. الاستخدام اليومي

### إصدار جديد إلى TestFlight
**من المتصفح/الآيباد:** Actions → ios-release → Run workflow.

**من PowerShell:**
```powershell
Set-Location C:\Projects\WhatsX-iOS
gh workflow run ios-release.yml -f changelog="إصلاح تسجيل الدخول"

# متابعة التنفيذ
gh run watch
```

### إصدار عبر وسم
```powershell
git tag v1.9.1
git push origin v1.9.1     # يُطلق ios-release تلقائياً
```

### رفع رقم النسخة
عدّل `MARKETING_VERSION` في `project.yml`. رقم البناء
(`CURRENT_PROJECT_VERSION`) يُضبط آلياً برقم تشغيل الـ workflow، فلا تلمسه.

---

## 6. قرارات مؤجّلة تخصّك

### عنوان الخادم
`Sources/Data/Api.swift` فيه `https://your-server.example.com` كقيمة
افتراضية، ويمكن تغييره من داخل التطبيق. قبل توزيع TestFlight على عملاء
حقيقيين، غيّر القيمة الافتراضية إلى خادمك الفعلي.

### iPad support — ENABLED
`TARGETED_DEVICE_FAMILY` is `"1,2"` (native iPhone + iPad) as of 1.15.0.
The inbox shows a two-pane split on iPads at least 700pt wide, and iPads
support all four orientations (a multitasking requirement); iPhones stay
portrait-only. TestFlight needs nothing extra. Reminder for a future App
Store submission: iPad screenshots become mandatory in App Store Connect.

### نموذج النشر
مجاني + دفع خارج التطبيق وفق Guideline **3.1.3(b)**. عملياً هذا يعني:
- لا `StoreKit` ولا أي شراء داخلي — لا تضفها لاحقاً بلا مراجعة الإرشاد
- التطبيق **خالٍ حالياً من أي entitlement** يعقّد **App Transfer** مستقبلاً:
  لا Apple Pay، لا Wallet، لا Sign in with Apple، لا Push Notifications
  (الإشعارات محلية عبر `UNUserNotificationCenter` فقط)
- حافظ على هذا الوضع حتى يتم النقل إلى حساب "مختبرات النخبة"

---

## 7. حل المشاكل

| العطل | السبب والحل |
|---|---|
| `أسرار ناقصة: ...` | لم تُضف الأسرار بعد. راجع القسم 3. |
| `Your account does not have permission` | مفتاح API بصلاحية `Developer`. أنشئ مفتاحاً بصلاحية `Admin`. |
| `The request expects other terms to be agreed` | اتفاقية Free Apps غير موقّعة. راجع الخطوة 2. |
| `Could not decrypt` في match | `MATCH_PASSWORD` خاطئة أو تغيّرت. يجب أن تطابق ما استُخدم وقت `bootstrap`. |
| `Authentication failed` لمستودع الشهادات | `MATCH_GIT_TOKEN` منتهٍ أو بلا صلاحية `repo`. |
| `No profiles for 'com.m-s-jaber.whatsx'` | لم تشغّل `bootstrap` بعد، أو معرّف الحزمة في `project.yml` لا يطابق `Matchfile`. |
| `bundle version must be higher` | رقم بناء مكرر. أعد التشغيل — رقم التشغيل الجديد يحلّها تلقائياً. |
| فشل `ios-build` بعد تحديث runner | ثبّت إصدار Xcode بإضافة خطوة `maxim-lobanov/setup-xcode` في الـ workflow. |

**للاطلاع على السجلات:** Actions → التشغيل الفاشل → افتح الخطوة الحمراء.
عند الفشل تُرفع السجلات التفصيلية كـ artifact باسم `build-logs` أو
`release-logs`.

---

## 8. ملاحظة على العمل من الآيباد

المستودع يحوي `Package.swift` يجعله حزمة Swift قابلة للفتح في **Swift
Playgrounds** على الآيباد. الشيفرة تعمل في الحالتين بفضل الشيم في
`Sources/Design/WXFont.swift`:

```swift
#if SWIFT_PACKAGE
return Bundle.module        // داخل Swift Playgrounds
#else
return Bundle.main          // داخل تطبيق XcodeGen
#endif
```

فلا تحذف هذا الشرط — بدونه ينكسر أحد المسارين.

كل عمليات البناء والنشر تُدار من متصفح الآيباد عبر تبويب **Actions**. لا
تحتاج أي أداة سطر أوامر على الآيباد إطلاقاً.
