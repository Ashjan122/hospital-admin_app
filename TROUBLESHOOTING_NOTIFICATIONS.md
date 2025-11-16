# استكشاف أخطاء إشعارات المعامل

## المشكلة: عدم وصول إشعارات المعامل

### الخطوات المطلوبة لحل المشكلة:

## 1. نشر Cloud Function
```bash
# في مجلد functions
firebase deploy --only functions:notifyNewLabSample
```

## 2. التحقق من الاشتراك في التوبك
- اذهب إلى شاشة "إشعارات الكنترول"
- تأكد من أنك مشترك في "إشعارات المعامل"
- إذا لم تكن مشتركاً، اضغط على "الاشتراك في الإشعارات"

## 3. التحقق من صلاحيات الإشعارات
- تأكد من أن التطبيق لديه صلاحيات إرسال الإشعارات
- في Android: Settings > Apps > Hospital Admin > Notifications
- في iOS: Settings > Notifications > Hospital Admin

## 4. اختبار الإشعار
- أضف عينة جديدة
- اختر فحص واحد على الأقل
- احفظ الطلب
- يجب أن تصل الإشعار خلال 5-10 ثوان

## 5. التحقق من Logs
- اذهب إلى Firebase Console > Functions > Logs
- ابحث عن "notifyNewLabSample"
- تحقق من وجود أخطاء

## 6. اختبار يدوي
يمكنك اختبار الإشعار يدوياً من Firebase Console:
- اذهب إلى Firebase Console > Cloud Messaging
- اضغط "Send your first message"
- في "Target" اختر "Topic" واكتب "lab_to_lab"
- أرسل رسالة تجريبية

## معلومات إضافية:
- التوبك المستخدم: `lab_to_lab`
- المسار المراقب: `labToLap/global/patients/{patientId}/lab_request/{requestId}`
- نوع الإشعار: `new_lab_sample`
