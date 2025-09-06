# 🧪 دليل اختبار نظام الأطباء المفضلين

## 🎯 **الهدف من الاختبار**
التأكد من أن النظام يحفظ جميع الأطباء المفضلين بشكل صحيح في قاعدة البيانات Firebase.

## 📋 **خطوات الاختبار**

### **الخطوة 1: تسجيل الدخول**
1. افتح التطبيق
2. سجل دخول كموظف استقبال
3. تأكد من أن الشاشة تفتح بشكل صحيح

### **الخطوة 2: اختيار الأطباء المفضلين**
1. اضغط على أيقونة `+` (إضافة أطباء مفضلين)
2. اختر **4 أطباء** من القائمة
3. تأكد من أن جميع الخانات محددة
4. اضغط "حفظ"

### **الخطوة 3: مراقبة السجلات**
1. افتح Console/Logs
2. ابحث عن الرسائل التالية:
   ```
   === SAVING FROM DIALOG ===
   Temp selected doctors: [doctor1, doctor2, doctor3, doctor4]
   Temp selected count: 4
   Updated _selectedDoctorIds: [doctor1, doctor2, doctor3, doctor4]
   Updated count: 4
   ```

### **الخطوة 4: مراقبة عملية الحفظ**
1. ابحث عن الرسائل التالية:
   ```
   === _saveSelectedDoctors STARTED ===
   Selected doctor IDs: [doctor1, doctor2, doctor3, doctor4]
   Selected count: 4
   Calling FavoriteDoctorsService.saveFavoriteDoctors...
   ```

### **الخطوة 5: مراقبة حفظ قاعدة البيانات**
1. ابحث عن الرسائل التالية:
   ```
   === SAVING FAVORITE DOCTORS ===
   User ID: [user_id]
   Center ID: [center_id]
   Doctors to save: [doctor1, doctor2, doctor3, doctor4]
   Number of doctors: 4
   Document ID: [user_id]_[center_id]
   Saving data: {userId: ..., centerId: ..., doctorIds: [...], updatedAt: ..., totalDoctors: 4}
   ✅ Data saved successfully!
   Saved document ID: [user_id]_[center_id]
   Saved data: {userId: ..., centerId: ..., doctorIds: [...], updatedAt: ..., totalDoctors: 4}
   Verification - Saved doctors: [doctor1, doctor2, doctor3, doctor4]
   Verification - Count: 4
   ```

### **الخطوة 6: اختبار حفظ البيانات**
1. اضغط على زر "اختبار حفظ البيانات"
2. ابحث عن الرسائل التالية:
   ```
   === SAVED DATA CHECK STARTED ===
   Local selected doctors: [doctor1, doctor2, doctor3, doctor4]
   Local count: 4
   === DATABASE STATUS ===
   Exists: true
   Is Valid: true
   📊 Database Data:
   - Doctor IDs: [doctor1, doctor2, doctor3, doctor4]
   - Expected Count: 4
   - Actual Count: 4
   🔄 Comparison:
   - Local count: 4
   - Database count: 4
   - IDs match: true
   ```

### **الخطوة 7: تسجيل الخروج والعودة**
1. اضغط على أيقونة تسجيل الخروج
2. سجل دخول مرة أخرى
3. تأكد من أن الأطباء المفضلين لا يزالون محفوظين

## 🔍 **ما يجب البحث عنه**

### **✅ علامات النجاح:**
- عدد الأطباء المحفوظين = 4
- البيانات محفوظة في قاعدة البيانات
- لا توجد أخطاء في السجلات
- رسائل النجاح تظهر

### **❌ علامات الفشل:**
- عدد الأطباء المحفوظين ≠ 4
- أخطاء في السجلات
- رسائل خطأ تظهر
- البيانات لا تُحفظ في قاعدة البيانات

## 📊 **البيانات المتوقعة**

### **في قاعدة البيانات:**
```json
{
  "userId": "[user_id]",
  "centerId": "[center_id]",
  "doctorIds": ["doctor1", "doctor2", "doctor3", "doctor4"],
  "totalDoctors": 4,
  "updatedAt": "[timestamp]"
}
```

### **في التطبيق:**
- `_selectedDoctorIds.length = 4`
- جميع الأطباء المختارين يظهرون في القائمة
- زر الاختبار يعرض "قاعدة البيانات: 4 طبيب | المحلي: 4 طبيب"

## 🚨 **استكشاف الأخطاء**

### **إذا كان العدد = 1 بدلاً من 4:**

#### **التحقق من:**
1. **السجلات:** ابحث عن رسائل الخطأ
2. **عملية الحفظ:** تأكد من أن `tempSelected` يحتوي على 4 أطباء
3. **قاعدة البيانات:** تحقق من أن البيانات تُحفظ بشكل صحيح

#### **الأسباب المحتملة:**
1. **مشكلة في `setState`:** قد لا يتم تحديث `_selectedDoctorIds` بشكل صحيح
2. **مشكلة في الحفظ:** قد لا يتم حفظ جميع البيانات في قاعدة البيانات
3. **مشكلة في التحميل:** قد لا يتم تحميل جميع البيانات من قاعدة البيانات

### **إذا كانت البيانات لا تُحفظ:**

#### **التحقق من:**
1. **الاتصال بالإنترنت:** تأكد من وجود اتصال
2. **Firebase:** تحقق من إعدادات Firebase
3. **الصلاحيات:** تأكد من صلاحيات الكتابة في قاعدة البيانات

## 📝 **تقرير الاختبار**

### **بعد كل اختبار، سجل:**
- ✅ **عدد الأطباء المختارين:**
- ✅ **عدد الأطباء المحفوظين:**
- ✅ **هل البيانات محفوظة في قاعدة البيانات؟**
- ✅ **هل زر الاختبار يعمل؟**
- ✅ **هل البيانات تبقى بعد تسجيل الخروج؟**
- ❌ **أي أخطاء أو مشاكل:**

## 🎯 **النتيجة المتوقعة**

بعد الاختبار، يجب أن:
1. **4 أطباء** يتم حفظهم في قاعدة البيانات
2. **جميع البيانات** تبقى محفوظة بعد تسجيل الخروج
3. **زر الاختبار** يعرض العدد الصحيح
4. **لا توجد أخطاء** في السجلات
