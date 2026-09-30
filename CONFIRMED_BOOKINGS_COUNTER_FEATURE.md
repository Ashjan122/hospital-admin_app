# 📊 ميزة عداد الحجوزات المؤكدة

## 🎯 **الهدف**

إضافة نظام عداد للحجوزات المؤكدة لكل موظف استقبال، حيث يزيد العداد كلما أكد موظف الاستقبال حجزاً ويحفظ في قاعدة البيانات.

## ✅ **ما تم تنفيذه**

### **1. إضافة معامل `userId` في `DoctorBookingsScreen`:**
```dart
class DoctorBookingsScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String? centerName;
  final String doctorName;
  final DateTime? initialDate;
  final String? userId; // معرف المستخدم (موظف الاستقبال)

  const DoctorBookingsScreen({
    super.key,
    required this.doctorId,
    required this.centerId,
    this.centerName,
    required this.doctorName,
    this.initialDate,
    this.userId, // معرف المستخدم (موظف الاستقبال)
  });
}
```

### **2. دالة زيادة عداد الحجوزات المؤكدة:**
```dart
// دالة زيادة عداد الحجوزات المؤكدة لموظف الاستقبال
Future<void> _incrementConfirmedBookingsCount() async {
  if (widget.userId == null) {
    print('⚠️ No userId provided, skipping confirmed bookings count increment');
    return;
  }

  try {
    print('=== INCREMENTING CONFIRMED BOOKINGS COUNT ===');
    print('User ID: ${widget.userId}');
    print('Center ID: ${widget.centerId}');

    // زيادة عداد الحجوزات المؤكدة في قاعدة البيانات
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({
      'confirmedBookingsCount': FieldValue.increment(1),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    print('✅ Confirmed bookings count incremented successfully');
  } catch (e) {
    print('❌ Error incrementing confirmed bookings count: $e');
    // لا نريد إيقاف عملية تأكيد الحجز بسبب فشل تحديث العداد
  }
}
```

### **3. تعديل دالة تأكيد الحجز:**
```dart
Future<void> _confirmBooking(Map<String, dynamic> booking) async {
  // ... الكود الموجود ...
  
  // إرسال رسالة تأكيد للمريض
  await _sendConfirmationSMS(booking);

  // زيادة عداد الحجوزات المؤكدة لموظف الاستقبال
  await _incrementConfirmedBookingsCount();

  // ... باقي الكود ...
}
```

### **4. تمرير `userId` من شاشة موظف الاستقبال:**
```dart
void _viewDoctorBookings(String doctorId, String doctorName) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => DoctorBookingsScreen(
        doctorId: doctorId,
        centerId: widget.centerId,
        centerName: widget.centerName,
        doctorName: doctorName,
        userId: widget.userId, // تمرير معرف المستخدم
      ),
    ),
  );
}
```

### **5. إضافة متغير عداد الحجوزات المؤكدة:**
```dart
class _ReceptionStaffScreenState extends State<ReceptionStaffScreen> {
  // ... المتغيرات الموجودة ...
  int _confirmedBookingsCount = 0; // عداد الحجوزات المؤكدة
}
```

### **6. دالة تحميل عداد الحجوزات المؤكدة:**
```dart
// دالة تحميل عداد الحجوزات المؤكدة
Future<void> _loadConfirmedBookingsCount() async {
  try {
    print('=== LOADING CONFIRMED BOOKINGS COUNT ===');
    print('User ID: ${widget.userId}');
    
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();

    if (userDoc.exists) {
      final userData = userDoc.data();
      final count = userData?['confirmedBookingsCount'] ?? 0;
      
      print('Found confirmed bookings count: $count');
      
      if (mounted) {
        setState(() {
          _confirmedBookingsCount = count;
        });
      }
    } else {
      print('⚠️ User document not found');
    }
  } catch (e) {
    print('❌ Error loading confirmed bookings count: $e');
  }
}
```

### **7. تحميل العداد مع البيانات الأخرى:**
```dart
Future<void> _initializeData() async {
  print('Initializing data for user: ${widget.userId}');
  
  // تحميل البيانات بشكل متوازي
  await Future.wait([
    _loadSelectedDoctors(),
    _loadAvailableDoctors(),
    _loadUnreadNotifications(),
    _loadConfirmedBookingsCount(), // تحميل عداد الحجوزات المؤكدة
  ]);
  
  print('Data initialization completed for user: ${widget.userId}');
  print('Selected doctors count: ${_selectedDoctorIds.length}');
  print('Available doctors count: ${_availableDoctors.length}');
  print('Confirmed bookings count: $_confirmedBookingsCount');
}
```

### **8. عرض عداد الحجوزات المؤكدة في الواجهة:**
```dart
// عداد الحجوزات المؤكدة
Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: const Color.fromARGB(255, 34, 96, 129),
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: const Color.fromARGB(255, 34, 96, 129),.withOpacity(0.3),
        spreadRadius: 1,
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  ),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(
        Icons.check_circle,
        color: Colors.white,
        size: 24,
      ),
      const SizedBox(width: 8),
      Text(
        'الحجوزات المؤكدة: $_confirmedBookingsCount',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ],
  ),
),
```

## 🚀 **كيفية العمل**

### **عند تأكيد الحجز:**
1. **موظف الاستقبال** يضغط على زر تأكيد الحجز
2. **النظام يؤكد الحجز** في قاعدة البيانات
3. **إرسال رسالة SMS** للمريض
4. **زيادة عداد الحجوزات المؤكدة** في قاعدة البيانات
5. **تحديث الواجهة** لعرض العداد الجديد

### **عند فتح شاشة موظف الاستقبال:**
1. **تحميل البيانات** بشكل متوازي
2. **جلب عداد الحجوزات المؤكدة** من قاعدة البيانات
3. **عرض العداد** في الواجهة مع تصميم جميل

## 📊 **هيكل البيانات في قاعدة البيانات**

### **مجموعة `users`:**
```json
{
  "userId": "string",
  "centerId": "KyKrjLBHMBGHtLzU3RS3",
  "centerName": "مركز الرومي الطبي",
  "confirmedBookingsCount": 0, // عداد الحجوزات المؤكدة
  "createdAt": "timestamp",
  "favoriteDoctors": ["34", "229", "147"],
  "lastUpdated": "timestamp",
  "photoUrl": "",
  "totalFavoriteDoctors": 3,
  "updatedAt": "timestamp",
  "userName": "mohamed",
  "userPassword": "13579",
  "userPhone": "091254789",
  "userType": "reception"
}
```

### **حقل `confirmedBookingsCount`:**
- **النوع:** `number`
- **القيمة الافتراضية:** `0`
- **التحديث:** يزيد بـ `1` عند كل تأكيد حجز
- **الاستخدام:** `FieldValue.increment(1)`

## 🎨 **تصميم الواجهة**

### **عداد الحجوزات المؤكدة:**
- **الموقع:** في أعلى الشاشة تحت عنوان "الأطباء المفضلون"
- **التصميم:** خلفية خضراء مع ظل جميل
- **الأيقونة:** `Icons.check_circle` بلون أبيض
- **النص:** "الحجوزات المؤكدة: [العدد]"
- **الألوان:** أخضر (`#2FBDAF`) وخلفية بيضاء

## 📱 **مثال عملي**

### **سيناريو:**
- **موظف الاستقبال:** محمد
- **العداد الحالي:** 5 حجوزات مؤكدة
- **إجراء:** تأكيد حجز جديد

### **النتيجة:**
1. **تأكيد الحجز** في قاعدة البيانات
2. **إرسال SMS** للمريض
3. **زيادة العداد** من 5 إلى 6
4. **تحديث الواجهة** لعرض "الحجوزات المؤكدة: 6"

## 🔧 **استكشاف الأخطاء**

### **إذا لم يزد العداد:**

#### **التحقق من:**
1. **السجلات:** ابحث عن رسائل "INCREMENTING CONFIRMED BOOKINGS COUNT"
2. **userId:** تأكد من تمرير `userId` بشكل صحيح
3. **قاعدة البيانات:** تحقق من وجود مستخدم في مجموعة `users`

#### **الحلول:**
1. **تأكد من `userId`** في `DoctorBookingsScreen`
2. **تحقق من السجلات** للتشخيص
3. **راجع قاعدة البيانات** للتأكد من وجود المستخدم

### **إذا لم يظهر العداد في الواجهة:**
1. **تحقق من `_confirmedBookingsCount`**
2. **تأكد من استدعاء `_loadConfirmedBookingsCount`**
3. **راجع السجلات** للتشخيص

## 🚀 **المزايا**

1. **تتبع الأداء:** معرفة عدد الحجوزات المؤكدة لكل موظف
2. **تحفيز الموظفين:** عرض إنجازاتهم بوضوح
3. **إحصائيات دقيقة:** بيانات موثوقة من قاعدة البيانات
4. **تصميم جميل:** عرض واضح ومميز
5. **تحديث فوري:** العداد يتحدث مع كل تأكيد

## 📝 **ملاحظات مهمة**

- **العداد يزيد تلقائياً** مع كل تأكيد حجز
- **البيانات محفوظة** في قاعدة البيانات
- **لا يؤثر على** عملية تأكيد الحجز
- **يعمل مع جميع** أنواع الحجوزات
- **قابل للتوسيع** لإضافة إحصائيات أخرى

## 🔧 **الخطوات التالية**

1. **اختبار الميزة** مع تأكيد حجوزات جديدة
2. **مراقبة العداد** في قاعدة البيانات
3. **جمع التغذية الراجعة** من الموظفين
4. **إضافة إحصائيات أخرى** مثل الحجوزات الملغاة
