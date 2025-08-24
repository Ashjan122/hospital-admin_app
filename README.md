# تطبيق إدارة المراكز الطبية

## 📋 وصف التطبيق
تطبيق إدارة شامل للمراكز الطبية يتيح إدارة الأطباء، الحجوزات، المستخدمين، التخصصات، وشركات التأمين.

## 🚀 المميزات

### 🏥 إدارة المراكز الطبية
- عرض قائمة المراكز الطبية
- تفاصيل كل مركز
- إدارة بيانات المراكز

### 👨‍⚕️ إدارة الأطباء
- قائمة الأطباء
- إضافة طبيب جديد
- تفاصيل الطبيب
- جدول عمل الأطباء
- إدارة التخصصات

### 📅 إدارة الحجوزات
- عرض جميع الحجوزات
- إدارة حجوزات الأطباء
- تتبع حالة الحجوزات

### 👥 إدارة المستخدمين
- قائمة المستخدمين
- إدارة صلاحيات المستخدمين

### 🏢 إدارة التخصصات
- إضافة وتعديل التخصصات الطبية
- ربط التخصصات بالمراكز

### 🛡️ إدارة شركات التأمين
- إدارة شركات التأمين
- ربط الشركات بالمراكز

## 📱 الصفحات المتاحة

### صفحات الإدارة:
1. **لوحة التحكم** - `control_panel_screen.dart`
2. **لوحة المعلومات** - `dashboard_screen.dart`
3. **المراكز الطبية** - `hospital_screen.dart`
4. **تفاصيل المركز** - `facility_details_screen.dart`

### إدارة الأطباء:
5. **قائمة الأطباء** - `admin_doctors_screen.dart`
6. **تفاصيل الطبيب** - `admin_doctor_details_screen.dart`
7. **إضافة طبيب** - `add_doctor_screen.dart`
8. **جدول عمل الأطباء** - `admin_doctors_schedule_screen.dart`

### إدارة الحجوزات:
9. **إدارة الحجوزات** - `admin_bookings_screen.dart`
10. **حجوزات الطبيب** - `doctor_bookings_screen.dart`

### إدارة النظام:
11. **إدارة المستخدمين** - `admin_users_screen.dart`
12. **إدارة التخصصات** - `admin_specialties_screen.dart`
13. **إدارة شركات التأمين** - `admin_insurance_companies_screen.dart`

### الصفحات المركزية:
14. **الأطباء المركزية** - `central_doctors_screen.dart`
15. **التخصصات المركزية** - `central_specialties_screen.dart`
16. **التأمين المركزي** - `central_insurance_screen.dart`

## 🔧 التثبيت والتشغيل

### المتطلبات:
- Flutter SDK 3.7.0 أو أحدث
- Dart SDK
- Firebase project

### خطوات التثبيت:
1. استنساخ المشروع
2. تثبيت التبعيات: `flutter pub get`
3. تكوين Firebase
4. تشغيل التطبيق: `flutter run`

## 🔗 Firebase Configuration
التطبيق يستخدم نفس إعدادات Firebase الخاصة بالتطبيق الرئيسي:
- Firestore Database
- Firebase Authentication
- Firebase Storage
- Firebase Messaging

## 📁 هيكل المشروع
```
lib/
├── main.dart
├── firebase_options.dart
├── screens/
│   ├── admin_*.dart (صفحات الإدارة)
│   ├── central_*.dart (الصفحات المركزية)
│   └── control_*.dart (صفحات الكنترول)
├── services/
│   ├── app_update_service.dart
│   ├── central_data_service.dart
│   └── sms_service.dart
└── widgets/
    ├── app_update_dialog.dart
    ├── app_update_wrapper.dart
    └── optimized_loading_widget.dart
```

## 🎨 الواجهة
- تصميم عربي بالكامل
- دعم RTL
- واجهة إدارية سهلة الاستخدام
- ألوان متناسقة

## 📞 الدعم
للحصول على الدعم أو الإبلاغ عن مشاكل، يرجى التواصل مع فريق التطوير.

---
**تم تطوير هذا التطبيق باستخدام Flutter و Firebase**
