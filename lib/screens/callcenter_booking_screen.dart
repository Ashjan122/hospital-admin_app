import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hospital_admin_app/screens/patient_info_screen.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' as intl;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class BookingScreen extends StatefulWidget {
  final String name;
  final Map<String, dynamic> workingSchedule;
  final String centerId;
  final String specializationId;
  final String doctorId;
  final bool isReschedule;
  final Map<String, dynamic>? oldBookingData;
  final bool showDoctorInfo; // جديد: لعرض معلومات الطبيب
  final String? doctorSpecialty; // جديد: تخصص الطبيب
  final String? centerName; // جديد: اسم المركز

  const BookingScreen({
    super.key,
    required this.name,
    required this.workingSchedule,
    required this.centerId,
    required this.specializationId,
    required this.doctorId,
    this.isReschedule = false,
    this.oldBookingData,
    this.showDoctorInfo = false, // افتراضياً false
    this.doctorSpecialty,
    this.centerName,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime? selectedDate;
  String? selectedShift;
  bool localeInitialized = false;
  Set<String> blockedDates = {}; // لتخزين الأيام المحظورة
  int? _queuePosition; // رقم الحجز الحالي (n+1)
  int? _dailyCapacity; // السعة المحددة لليوم/الفترة
  bool _loadingQueue = false;
  bool _isFull = false;
  Map<String, dynamic>? _doctorData;
  String? _loadedSpecialty; // التخصص المحمّل من قاعدة البيانات

  // ملاحظة: هذا الكلاس يتحقق من الوقت الحالي مقارنة بجدول الطبيب
  // أمثلة:
  // 1. إذا كان جدول الطبيب الصباحي ينتهي 12 ظهراً والوقت الحالي 1 ظهراً
  //    فلن تظهر الفترة الصباحية في القائمة
  // 2. إذا كان جدول الطبيب المسائي ينتهي 8 مساءً والوقت الحالي 9 مساءً
  //    فلن تظهر الفترة المسائية في القائمة
  // 3. إذا كان اليوم فيه فترة صباحية فقط وانتهت، أو فترة مسائية فقط وانتهت
  //    فلن يظهر اليوم في القائمة
  // 4. إذا كان الوقت 10 صباحاً والفترة الصباحية تنتهي 12 ظهراً
  //    ستظهر الفترتان (صباحية ومسائية) للمريض للاختيار

  String _toEnglishDigits(String input) {
    const arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const easternArabicIndic = [
      '۰',
      '۱',
      '۲',
      '۳',
      '۴',
      '۵',
      '۶',
      '۷',
      '۸',
      '۹',
    ];
    String out = input;
    for (int i = 0; i < 10; i++) {
      out = out.replaceAll(arabicIndic[i], i.toString());
      out = out.replaceAll(easternArabicIndic[i], i.toString());
    }
    return out;
  }

  bool _hasScheduleOn(DateTime day) {
    final dayName = intl.DateFormat('EEEE', 'ar').format(day).trim();
    final schedule = widget.workingSchedule[dayName];
    if (schedule == null || schedule is! Map<String, dynamic>) return false;
    final morning = schedule['morning'] as Map<String, dynamic>?;
    final evening = schedule['evening'] as Map<String, dynamic>?;

    // التحقق من وجود أي فترة (صباحية أو مسائية)
    final hasMorning = morning != null && morning.isNotEmpty;
    final hasEvening = evening != null && evening.isNotEmpty;

    return hasMorning || hasEvening;
  }

  Set<String> _computeBookableDateStrs() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final Set<String> allowed = {};

    // السماح بالحجز من اليوم الحالي حتى 7 أيام قادمة
    for (int i = 0; i <= 7; i++) {
      final day = today.add(Duration(days: i));
      final dayStr = intl.DateFormat('yyyy-MM-dd').format(day);
      
      if (blockedDates.contains(dayStr)) continue;
      
      if (_hasScheduleOn(day)) {
        final dayName = intl.DateFormat('EEEE', 'ar').format(day).trim();
      final schedule = widget.workingSchedule[dayName] as Map<String, dynamic>?;

      bool hasValidPeriod = false;

      final morning = schedule?['morning'] as Map<String, dynamic>?;
      if (morning != null && morning.isNotEmpty) {
        hasValidPeriod = true;
      }

      final evening = schedule?['evening'] as Map<String, dynamic>?;
      if (evening != null && evening.isNotEmpty) {
        hasValidPeriod = true;
      }

      if (hasValidPeriod) {
          allowed.add(dayStr);
        }
      }
    }

    return allowed;
  }

  int _extractCapacity(Map<String, dynamic>? periodData) {
    return _extractCapacityWithShift(periodData, selectedShift);
  }

  int _extractCapacityWithShift(
    Map<String, dynamic>? periodData,
    String? shift,
  ) {
    int parseCap(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    // 1) سعة من بيانات الفترة (morning/evening)
    if (periodData != null) {
      final dynamic cap =
          periodData['capacity'] ??
          periodData['maxPatients'] ??
          periodData['maxBookings'];
      final c1 = parseCap(cap);
      if (c1 > 0) return c1;
      final dynamic slots = periodData['slots'] ?? periodData['times'];
      if (slots is List && slots.isNotEmpty) return slots.length;
    }

    // 2) سعة على مستوى الطبيب (عام أو حسب الفترة)
    final d = _doctorData;
    if (d != null) {
      // مفاتيح صريحة كما في شاشة تفاصيل الطبيب
      if (shift == 'morning') {
        final cm0 = parseCap(d['morningPatientLimit']);
        if (cm0 > 0) return cm0;
      } else if (shift == 'evening') {
        final ce0 = parseCap(d['eveningPatientLimit']);
        if (ce0 > 0) return ce0;
      }
      // حسب الفترة أولاً
      if (shift == 'morning') {
        final c = parseCap(
          d['capacityMorning'] ??
              d['morningCapacity'] ??
              d['maxPatientsMorning'] ??
              d['morningMax'] ??
              d['morningLimit'],
        );
        if (c > 0) return c;
      } else if (shift == 'evening') {
        final c = parseCap(
          d['capacityEvening'] ??
              d['eveningCapacity'] ??
              d['maxPatientsEvening'] ??
              d['eveningMax'] ??
              d['eveningLimit'],
        );
        if (c > 0) return c;
      }
      // عام
      final cg = parseCap(
        d['dailyCapacity'] ??
            d['maxDailyPatients'] ??
            d['maxPatients'] ??
            d['maxBookings'] ??
            d['capacity'] ??
            d['limit'],
      );
      if (cg > 0) return cg;
    }

    return 0;
  }

  Future<void> _updateQueueInfo(DateTime date) async {
    final allowed = _computeBookableDateStrs();
    final dayStr = intl.DateFormat('yyyy-MM-dd').format(date);
    if (!allowed.contains(dayStr)) {
      setState(() {
        _queuePosition = null;
        _dailyCapacity = null;
        _isFull = false;
      });
      return;
    }

    final dayName = intl.DateFormat('EEEE', 'ar').format(date).trim();
    final schedule = widget.workingSchedule[dayName] as Map<String, dynamic>?;

    // لو الفترتين متاحتين ولم يحدد المستخدم الفترة بعد، ننتظر اختيار الفترة
    final hasMorning = schedule?['morning'] != null;
    final hasEvening = schedule?['evening'] != null;
    final String? effectiveShift =
        (hasMorning && hasEvening)
            ? selectedShift
            : (hasMorning ? 'morning' : (hasEvening ? 'evening' : null));

    if (effectiveShift == null) {
      setState(() {
        _queuePosition = null;
        _dailyCapacity = null;
        _isFull = false;
      });
      return;
    }

    setState(() {
      _loadingQueue = true;
    });

    try {
      // قراءة السعة من جدول الطبيب
      final periodData = (schedule?[effectiveShift]) as Map<String, dynamic>?;
      final capacity = _extractCapacity(periodData);

      // حساب عدد الحجوزات الحالية لهذا اليوم والفترة
      final qs =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(widget.specializationId)
              .collection('doctors')
              .doc(widget.doctorId)
              .collection('appointments')
              .where('date', isEqualTo: dayStr)
              .where('period', isEqualTo: effectiveShift)
              .get();

      final count = qs.docs.length;
      setState(() {
        _dailyCapacity =
            capacity > 0 ? capacity : null; // إن لم تكن معرفّة، نخليها null
        _queuePosition = count + 1; // موقعه إن حجز الآن
        _isFull = (_dailyCapacity != null) && (count >= _dailyCapacity!);
        _loadingQueue = false;
      });
    } catch (e) {
      setState(() {
        _queuePosition = null;
        _dailyCapacity = null;
        _isFull = false;
        _loadingQueue = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ar', null).then((_) {
      setState(() => localeInitialized = true);
    });
    // تحميل الأيام المحظورة وبيانات الطبيب
    _loadBlockedDates();
    _loadDoctorInfo();
  }

  Future<void> _loadBlockedDates() async {
    try {
      final blockedSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(widget.specializationId)
              .collection('doctors')
              .doc(widget.doctorId)
              .collection('blockedDates')
              .get();
      setState(() {
        blockedDates = blockedSnapshot.docs.map((doc) => doc.id).toSet();
      });
    } catch (e) {
      print('خطأ في تحميل الأيام المحظورة: $e');
    }
  }

  Future<void> _loadDoctorInfo() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(widget.specializationId)
              .collection('doctors')
              .doc(widget.doctorId)
              .get();
      if (doc.exists) {
        final data = doc.data();
        print('DEBUG: تم تحميل بيانات الطبيب: $data');
        setState(() {
          _doctorData = data;
        });
      } else {
        print('DEBUG: وثيقة الطبيب غير موجودة');
      }

      // جلب اسم التخصص من قاعدة البيانات إذا لم يتم تمريره
      if (widget.doctorSpecialty == null || widget.doctorSpecialty!.isEmpty) {
        try {
          final specDoc = await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(widget.specializationId)
              .get();
          if (specDoc.exists) {
            final specData = specDoc.data();
            final specName = specData?['specName']?.toString();
            if (specName != null && specName.isNotEmpty) {
              setState(() {
                _loadedSpecialty = specName;
              });
            }
          }
        } catch (e) {
          print('خطأ في جلب اسم التخصص: $e');
        }
      }
    } catch (e) {
      print('خطأ في تحميل بيانات الطبيب: $e');
    }
  }

  Future<bool> isDateBlocked(DateTime date) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0]; // YYYY-MM-DD
      final blockedDoc =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(widget.specializationId)
              .collection('doctors')
              .doc(widget.doctorId)
              .collection('blockedDates')
              .doc(dateStr)
              .get();
      if (blockedDoc.exists) {
        final blockedData = blockedDoc.data()!;
        final period = blockedData['period'] as String?;
        if (period == 'all' || period == selectedShift) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('خطأ في فحص اليوم المحظور: $e');
      return false;
    }
  }

  // دالة لتحويل الوقت من نص إلى ساعة
  // مثال: "14:30" -> 14, "09:00" -> 9
  int? _parseTimeToHour(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 1) {
        return int.tryParse(parts[0]);
      }
    } catch (e) {
      print('خطأ في تحويل الوقت: $timeStr');
    }
    return null;
  }

  // دالة للتحقق من صلاحية الفترة بناءً على الوقت الحالي
  bool _isPeriodValid(Map<String, dynamic>? periodData, String periodType) {
    if (periodData == null || periodData.isEmpty) return false;

    final now = DateTime.now();
    final currentHour = now.hour;

    if (periodType == 'morning') {
      final endTime = periodData['end'] as String?;
      final endHour = _parseTimeToHour(endTime);
      if (endHour != null) {
        // إذا انتهت الفترة الصباحية، لا تظهر
        return currentHour < endHour;
      }
    } else if (periodType == 'evening') {
      final endTime = periodData['end'] as String?;
      final endHour = _parseTimeToHour(endTime);
      if (endHour != null) {
        // إذا انتهت الفترة المسائية، لا تظهر
        return currentHour < endHour;
      }
    }

    // إذا لم نتمكن من تحديد الوقت، نعتبر الفترة صالحة
    return true;
  }

  // دالة لتحديد ما إذا كان اليوم متاح للحجز أم لا
  bool isDateBookable(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateStr = intl.DateFormat('yyyy-MM-dd').format(date);

    // السماح بالحجز من اليوم الحالي فصاعداً (وليس الأيام الماضية)
    if (date.isBefore(today)) {
      return false;
    }

    // التحقق من أن اليوم غير محظور
    if (blockedDates.contains(dateStr)) {
      return false;
    }

    final dayName = intl.DateFormat('EEEE', 'ar').format(date).trim();
    final schedule = widget.workingSchedule[dayName] as Map<String, dynamic>?;
    if (schedule == null) return false;

    final morning = schedule['morning'] as Map<String, dynamic>?;
    final evening = schedule['evening'] as Map<String, dynamic>?;
    final hasMorning = morning != null && morning.isNotEmpty;
    final hasEvening = evening != null && evening.isNotEmpty;
    return hasMorning || hasEvening;
  }

  // دالة جديدة لتحديد الفترة المناسبة بناءً على الوقت الحالي
  String? _getAppropriateShift(DateTime date) {
    final dayName = intl.DateFormat('EEEE', 'ar').format(date).trim();
    final schedule = widget.workingSchedule[dayName] as Map<String, dynamic>?;

    if (schedule == null) return null;

    final morning = schedule['morning'] as Map<String, dynamic>?;
    final evening = schedule['evening'] as Map<String, dynamic>?;

    final hasMorning = morning != null && morning.isNotEmpty;
    final hasEvening = evening != null && evening.isNotEmpty;

    // نطبق منطق الغد فقط: إن كانت فترة واحدة أعدها، وإن كانت فترتان اترك الاختيار للمستخدم
    if (hasMorning && !hasEvening) {
      return 'morning';
    } else if (!hasMorning && hasEvening) {
      return 'evening';
    } else if (hasMorning && hasEvening) {
      return null;
    }

    return null;
  }

  // دالة جديدة للحصول على رسالة الفترة المنتهية
  String? _getPeriodEndedMessage(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday =
        intl.DateFormat('yyyy-MM-dd').format(date) ==
        intl.DateFormat('yyyy-MM-dd').format(today);

    if (!isToday) return null; // لا توجد رسائل للغد

    final dayName = intl.DateFormat('EEEE', 'ar').format(date).trim();
    final schedule = widget.workingSchedule[dayName] as Map<String, dynamic>?;

    if (schedule == null) return null;

    final morning = schedule['morning'] as Map<String, dynamic>?;
    final evening = schedule['evening'] as Map<String, dynamic>?;

    final hasMorning = morning != null && morning.isNotEmpty;
    final hasEvening = evening != null && evening.isNotEmpty;

    // إذا كان يعمل فترة صباحية فقط
    if (hasMorning && !hasEvening) {
      return "الحجز متاح فقط للفترة المسائية في اليوم الحالي";
    }

    // إذا كان يعمل فترتين
    if (hasMorning && hasEvening) {
      final isEveningValid = _isPeriodValid(evening, 'evening');

      if (!isEveningValid) {
        return "الحجز متاح فقط للفترة المسائية في اليوم الحالي";
      }
    }

    return null;
  }

  // دالة لجلب جميع الأيام التي لها جدول عمل
  // الأيام المتاحة للحجز: اليوم الحالي (إذا كانت الفترات صالحة) والغد
  // باقي الأيام تظهر لكنها غير متاحة للحجز
  List<DateTime> getAvailableDates() {
    final now = DateTime.now();
    final List<DateTime> dates = [];
    if (widget.workingSchedule.isEmpty) {
      print('workingSchedule فارغ أو غير محدد أو غير موجود في قاعدة البيانات');
      return dates;
    }

    // عرض جميع الأيام التي لها جدول عمل خلال 7 أيام بدءاً من اليوم الحالي
    for (int i = 0; i <= 7; i++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final dateStr = day.toIso8601String().split('T')[0];
      if (blockedDates.contains(dateStr)) continue;

      final name = intl.DateFormat('EEEE', 'ar').format(day).trim();
      final schedule = widget.workingSchedule[name];
      if (schedule != null && schedule is Map<String, dynamic>) {
        final morning = schedule['morning'] as Map<String, dynamic>?;
        final evening = schedule['evening'] as Map<String, dynamic>?;
        final hasAnyPeriod =
            (morning != null && morning.isNotEmpty) ||
            (evening != null && evening.isNotEmpty);
        if (hasAnyPeriod) {
          dates.add(day);
        }
      }
    }

    return dates;
  }

  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Center(
              child: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            content: Text(message, textAlign: TextAlign.center),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("موافق"),
              ),
            ],
          ),
    );
  }

  // دالة للتحقق من توقف الحجز للطبيب
  bool _isDoctorBookingDisabled() {
    // التحقق من بيانات الطبيب
    if (_doctorData != null) {
      print('DEBUG: _doctorData = $_doctorData');

      // التحقق من وجود حقل يوضح توقف الحجز
      final bookingDisabled = _doctorData!['bookingDisabled'];
      final isBookingDisabled = _doctorData!['isBookingDisabled'];
      final bookingSuspended = _doctorData!['bookingSuspended'];
      final isBookingSuspended = _doctorData!['isBookingSuspended'];
      final bookingStatus = _doctorData!['bookingStatus'];
      final status = _doctorData!['status'];
      final isBookingEnabled = _doctorData!['isBookingEnabled'];

      print('DEBUG: bookingDisabled = $bookingDisabled');
      print('DEBUG: isBookingDisabled = $isBookingDisabled');
      print('DEBUG: bookingSuspended = $bookingSuspended');
      print('DEBUG: isBookingSuspended = $isBookingSuspended');
      print('DEBUG: bookingStatus = $bookingStatus');
      print('DEBUG: status = $status');
      print('DEBUG: isBookingEnabled = $isBookingEnabled');

      final isDisabled =
          bookingDisabled == true ||
          isBookingDisabled == true ||
          bookingSuspended == true ||
          isBookingSuspended == true ||
          bookingStatus == 'disabled' ||
          bookingStatus == 'suspended' ||
          status == 'disabled' ||
          status == 'suspended' ||
          isBookingEnabled == false;

      print('DEBUG: isDisabled = $isDisabled');
      return isDisabled;
    }

    print('DEBUG: _doctorData is null');
    return false;
  }

  // دالة لمشاركة الأيام المتاحة عبر واتساب
  Future<void> _shareAvailableDaysOnWhatsApp() async {
    try {
      // إنشاء نص الأيام المتاحة
      final availableDates = getAvailableDates();

      if (availableDates.isEmpty) {
        _showDialog("تنبيه", "لا توجد أيام متاحة للحجز حالياً");
        return;
      }

      String message = "📅 الأيام المتاحة للحجز مع د. ${widget.name}:\n\n";

      for (int i = 0; i < availableDates.length; i++) {
        final date = availableDates[i];
        final formatted = intl.DateFormat(
          'EEEE - yyyy/MM/dd',
          'ar',
        ).format(date);
        final formattedEnglish = _toEnglishDigits(formatted);

        // تحديد الفترات المتاحة
        final dayName = intl.DateFormat('EEEE', 'ar').format(date).trim();
        final schedule =
            widget.workingSchedule[dayName] as Map<String, dynamic>?;

        String periods = "";
        if (schedule != null) {
          final morning = schedule['morning'] as Map<String, dynamic>?;
          final evening = schedule['evening'] as Map<String, dynamic>?;

          List<String> availablePeriods = [];
          if (morning != null && morning.isNotEmpty) {
            availablePeriods.add("صباح");
          }
          if (evening != null && evening.isNotEmpty) {
            availablePeriods.add("مساء");
          }

          if (availablePeriods.isNotEmpty) {
            periods = " (${availablePeriods.join(' - ')})";
          }
        }

        message += "${i + 1}. $formattedEnglish$periods\n";
      }

      // محاولة فتح واتساب بطرق مختلفة
      final encodedMessage = Uri.encodeComponent(message);

      // الطريقة الأولى: wa.me مع النص
      final whatsappUrl = "https://wa.me/?text=$encodedMessage";

      try {
        await launchUrl(
          Uri.parse(whatsappUrl),
          mode: LaunchMode.externalApplication,
        );
        return;
      } catch (e) {
        print('فشل wa.me: $e');
      }

      // الطريقة الثانية: api.whatsapp.com
      final whatsappApiUrl =
          "https://api.whatsapp.com/send?text=$encodedMessage";

      try {
        await launchUrl(
          Uri.parse(whatsappApiUrl),
          mode: LaunchMode.externalApplication,
        );
        return;
      } catch (e) {
        print('فشل api.whatsapp.com: $e');
      }

      // الطريقة الثالثة: whatsapp://
      final whatsappScheme = "whatsapp://send?text=$encodedMessage";

      try {
        await launchUrl(
          Uri.parse(whatsappScheme),
          mode: LaunchMode.externalApplication,
        );
        return;
      } catch (e) {
        print('فشل whatsapp://: $e');
      }

      // الطريقة الرابعة: فتح واتساب بدون نص
      try {
        await launchUrl(
          Uri.parse("https://wa.me/"),
          mode: LaunchMode.externalApplication,
        );
        // عرض النص للنسخ
        _showCopyDialog(message);
        return;
      } catch (e) {
        print('فشل wa.me بدون نص: $e');
      }

      // إذا فشلت جميع المحاولات
      _showCopyDialog(message);
    } catch (e) {
      print('خطأ عام في فتح واتساب: $e');
      _showDialog("تنبيه", "حدث خطأ أثناء فتح واتساب");
    }
  }

  // دالة لعرض النص للنسخ
  void _showCopyDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text("مشاركة الأيام المتاحة"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "لا يمكن فتح واتساب مباشرة. يمكنك نسخ النص التالي ومشاركته:",
                ),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SelectableText(
                    message,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("موافق"),
              ),
            ],
          ),
    );
  }

  Widget _buildContinueButton(List<DateTime> availableDates) {
    if (availableDates.isNotEmpty &&
        selectedDate != null &&
        !_isDoctorBookingDisabled()) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          height: 60,
          child: OutlinedButton(
            onPressed: () {
              if (selectedDate == null) {
                _showDialog("تنبيه", "يرجى اختيار يوم أولاً");
                return;
              }

              // التحقق من الفترات المتاحة
              if (selectedShift == null) {
                final appropriateShift = _getAppropriateShift(selectedDate!);
                if (appropriateShift != null) {
                  selectedShift = appropriateShift;
                } else {
                  _showDialog("تنبيه", "لا توجد فترة متاحة للحجز في هذا اليوم");
                  return;
                }
              }

              if (!isDateBookable(selectedDate!)) {
                _showDialog(
                  "تنبيه",
                  "هذا اليوم غير متاح للحجز، يرجى اختيار يوم آخر",
                );
                return;
              }
              if (_isFull) {
                _showDialog(
                  "تنبيه",
                  "العدد اكتمل لهذا اليوم/الفترة، لا يمكن الحجز",
                );
                return;
              }
              Navigator.push(
                context,
               MaterialPageRoute(
                  builder:
                      (_) => PatientInfoScreen(
                        centerId: widget.centerId,
                        specializationId: widget.specializationId,
                        doctorId: widget.doctorId,
                        selectedDate: selectedDate!,
                        selectedShift: selectedShift,
                        workingSchedule: widget.workingSchedule,
                        isReschedule: widget.isReschedule,
                        oldBookingData: widget.oldBookingData,
                      ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: const Color(0xFF2FBDAF), width: 2),
              foregroundColor: const Color(0xFF2FBDAF),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              "متابعة لإدخال البيانات",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (!localeInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final availableDates = getAvailableDates();
    final schedule =
        selectedDate != null
            ? widget.workingSchedule[intl.DateFormat(
              'EEEE',
              'ar',
            ).format(selectedDate!).trim()]
            : null;

    // تحديد ما إذا كان اليوم المختار هو اليوم الحالي أم لا
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isSelectedToday =
        selectedDate != null &&
        intl.DateFormat('yyyy-MM-dd').format(selectedDate!) ==
            intl.DateFormat('yyyy-MM-dd').format(today);

    // نعرض جميع الفترات الموجودة بغض النظر عن الوقت الحالي
    final hasMorning = schedule?['morning'] != null;
    final hasEvening = schedule?['evening'] != null;

    // إضافة رسائل تصحيح
    if (selectedDate != null) {
      print(
        'DEBUG: selectedDate = ${intl.DateFormat('yyyy-MM-dd').format(selectedDate!)}',
      );
      print('DEBUG: isSelectedToday = $isSelectedToday');
      print('DEBUG: schedule = $schedule');
      print('DEBUG: hasMorning = $hasMorning, hasEvening = $hasEvening');
      print('DEBUG: schedule?[\'morning\'] = ${schedule?['morning']}');
      print('DEBUG: schedule?[\'evening\'] = ${schedule?['evening']}');

      // إضافة تصحيح للفترة الصباحية
      if (schedule?['morning'] != null) {
        final morningValid = _isPeriodValid(
          schedule?['morning'] as Map<String, dynamic>?,
          'morning',
        );
        print('DEBUG: _isPeriodValid for morning = $morningValid');
      }

      // إضافة تصحيح للفترة المسائية
      if (schedule?['evening'] != null) {
        final eveningValid = _isPeriodValid(
          schedule?['evening'] as Map<String, dynamic>?,
          'evening',
        );
        print('DEBUG: _isPeriodValid for evening = $eveningValid');
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:
              widget.showDoctorInfo
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2FBDAF),
                          fontSize: 20,
                        ),
                      ),
                      if (widget.doctorSpecialty != null ||
                          widget.centerName != null)
                        Text(
                          '${widget.doctorSpecialty ?? ''}${widget.doctorSpecialty != null && widget.centerName != null ? ' - ' : ''}${widget.centerName ?? ''}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                    ],
                  )
                  : Text(
                    "اختيار الموعد",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2FBDAF),
                      fontSize: 30,
                    ),
                  ),
          actions: [
            GestureDetector(
              onTap: _shareAvailableDaysOnWhatsApp,
              child: Container(
                padding: EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/whattsap.png',
                      width: 24,
                      height: 24,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
  FontAwesomeIcons.whatsapp,
  color: Colors.green,
                          size: 24,
                        );
                      },
                    ),
                    SizedBox(height: 2),
                    Text(
                      'مشاركة الجدول',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF2FBDAF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // معلومات الطبيب والتخصص
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // اسم الطبيب
                      Text(
                        widget.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:  Colors.black,
                        ),
                      ),
                      // التخصص (subtitle)
                      const SizedBox(height: 4),
                      Text(
                        widget.doctorSpecialty ?? _loadedSpecialty ?? 'غير محدد',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      // ملاحظة الحجز
                     /* const SizedBox(height: 12),
                       Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Color(0xFF2FBDAF),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getBookingAvailabilityMessage(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF2FBDAF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),*/
                      
                    ],
                  ),
                ),
                Text(
                  "اختر يوم من الأيام المتاحة:",
                  style: TextStyle(fontSize: 18),
                ),
                
               
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (availableDates.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(40),
                            margin: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'لا توجد أيام متاحة للحجز حالياً',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('العودة لاختيار طبيب آخر'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2FBDAF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ...availableDates.map((date) {
                            String formatted = intl.DateFormat(
                              'EEEE - yyyy/MM/dd',
                              'ar',
                            ).format(date);
                            formatted = _toEnglishDigits(formatted);
                            final isSelected =
                                selectedDate != null &&
                                intl.DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(selectedDate!) ==
                                    intl.DateFormat('yyyy-MM-dd').format(date);
                            final isBookable = isDateBookable(date);

                            return Column(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    if (!isBookable) return;

                                    setState(() {
                                      selectedDate = date;
                                      // تحديد الفترة المناسبة بناءً على الوقت الحالي
                                      selectedShift = _getAppropriateShift(
                                        date,
                                      );
                                    });

                                    _updateQueueInfo(date);
                                  },
                                  child: Container(
                                    margin: EdgeInsets.symmetric(vertical: 4),
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          isSelected
                                              ? Colors.blue[100]
                                              : (isBookable
                                                  ? Colors.grey[200]
                                                  : Colors.grey[100]),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            isSelected
                                                ? Colors.blue
                                                : (isBookable
                                                    ? Colors.transparent
                                                    : Colors.grey[300]!),
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isBookable
                                              ? (isSelected
                                                  ? Icons.check_circle
                                                  : Icons
                                                      .radio_button_unchecked)
                                              : Icons.block,
                                          color:
                                              isBookable
                                                  ? (isSelected
                                                      ? Colors.blue
                                                      : Colors.grey)
                                                  : Colors.grey,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            formatted,
                                            style: TextStyle(fontSize: 16),
                                          ),
                                        ),
                                        // شارات صباح/مساء دائماً، وتحتها العدد عند التحديد
                                        Builder(
                                          builder: (_) {
                                            final dName =
                                                intl.DateFormat(
                                                  'EEEE',
                                                  'ar',
                                                ).format(date).trim();
                                            final sch =
                                                widget.workingSchedule[dName]
                                                    as Map<String, dynamic>?;
                                            final morning =
                                                sch?['morning']
                                                    as Map<String, dynamic>?;
                                            final evening =
                                                sch?['evening']
                                                    as Map<String, dynamic>?;
                                            final hasMorning =
                                                morning != null &&
                                                morning.isNotEmpty;
                                            final hasEvening =
                                                evening != null &&
                                                evening.isNotEmpty;
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (hasMorning)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Colors.blue[50],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors
                                                                    .blue[200]!,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            const Icon(
                                                              Icons.wb_sunny,
                                                              size: 12,
                                                              color:
                                                                  Colors.orange,
                                                            ),
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Text(
                                                              'صباح',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    Colors
                                                                        .blue[600],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    if (hasMorning &&
                                                        hasEvening)
                                                      const SizedBox(width: 6),
                                                    if (hasEvening)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Colors.blue[50],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors
                                                                    .blue[200]!,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .nightlight_round,
                                                              size: 12,
                                                              color:
                                                                  Colors
                                                                      .blue[600],
                                                            ),
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Text(
                                                              'مساء',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    Colors
                                                                        .blue[600],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                if (isSelected &&
                                                    isBookable &&
                                                    !_loadingQueue)
                                                  const SizedBox(height: 4),
                                                if (isSelected &&
                                                    isBookable &&
                                                    !_loadingQueue)
                                                  Builder(
                                                    builder: (_) {
                                                      if (_isFull) {
                                                        return Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors.red[50],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  Colors
                                                                      .red[200]!,
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'مكتمل',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      if (_queuePosition !=
                                                          null) {
                                                        final capText =
                                                            _dailyCapacity !=
                                                                    null
                                                                ? _toEnglishDigits(
                                                                  _dailyCapacity!
                                                                      .toString(),
                                                                )
                                                                : '';
                                                        final text =
                                                            capText.isNotEmpty
                                                                ? '${_toEnglishDigits(_queuePosition!.toString())} من $capText'
                                                                : _toEnglishDigits(
                                                                  _queuePosition!
                                                                      .toString(),
                                                                );
                                                        return Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors.blue[50],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  Colors
                                                                      .blue[200]!,
                                                            ),
                                                          ),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              // إظهار العدد فقط تحت الشارات عند التحديد
                                                              Text(
                                                                text,
                                                                style: const TextStyle(
                                                                  color:
                                                                      Colors
                                                                          .blue,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 10,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      }
                                                      return const SizedBox.shrink();
                                                    },
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isSelected && isBookable)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      children: [
                                        // عرض رسالة الفترة المنتهية إذا وجدت
                                        if (_getPeriodEndedMessage(date) !=
                                            null)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            margin: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange[50],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.orange[200]!,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.info_outline,
                                                  color: Colors.orange[700],
                                                  size: 20,
                                                ),
                                                SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _getPeriodEndedMessage(
                                                      date,
                                                    )!,
                                                    style: TextStyle(
                                                      color: Colors.orange[700],
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // عرض اختيار الفترات إذا كان هناك فترتين
                                        if (hasMorning && hasEvening) ...[
                                          Builder(
                                            builder: (context) {
                                              final now = DateTime.now();
                                              final today = DateTime(
                                                now.year,
                                                now.month,
                                                now.day,
                                              );
                                              final isToday =
                                                  intl.DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(date) ==
                                                  intl.DateFormat(
                                                    'yyyy-MM-dd',
                                                  ).format(today);

                                              // نعرض جميع الفترات بغض النظر عن الوقت الحالي
                                              final showMorning = true;
                                              final showEvening = true;

                                              // إضافة رسائل تصحيح
                                              print(
                                                'DEBUG: isToday = $isToday',
                                              );
                                              print(
                                                'DEBUG: hasMorning = $hasMorning, hasEvening = $hasEvening',
                                              );
                                              print(
                                                'DEBUG: showMorning = $showMorning, showEvening = $showEvening',
                                              );
                                              print(
                                                'DEBUG: schedule = $schedule',
                                              );
                                              print(
                                                'DEBUG: About to show choice chips',
                                              );

                                              return Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  ChoiceChip(
                                                    label: Text(
                                                      "الفترة الصباحية",
                                                    ),
                                                    selected:
                                                        selectedShift ==
                                                        'morning',
                                                    onSelected: (_) {
                                                      setState(
                                                        () =>
                                                            selectedShift =
                                                                'morning',
                                                      );
                                                      if (selectedDate !=
                                                          null) {
                                                        _updateQueueInfo(
                                                          selectedDate!,
                                                        );
                                                      }
                                                    },
                                                  ),
                                                  SizedBox(width: 10),
                                                  ChoiceChip(
                                                    label: Text(
                                                      "الفترة المسائية",
                                                    ),
                                                    selected:
                                                        selectedShift ==
                                                        'evening',
                                                    onSelected: (_) {
                                                      setState(
                                                        () =>
                                                            selectedShift =
                                                                'evening',
                                                      );
                                                      if (selectedDate !=
                                                          null) {
                                                        _updateQueueInfo(
                                                          selectedDate!,
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }),
                        // رسالة توقف الحجز إذا كان الطبيب موقف الحجز
                        Builder(
                          builder: (context) {
                            final isDisabled = _isDoctorBookingDisabled();
                            print(
                              'DEBUG: availableDates.isNotEmpty = ${availableDates.isNotEmpty}',
                            );
                            print(
                              'DEBUG: _isDoctorBookingDisabled() = $isDisabled',
                            );
                            print(
                              'DEBUG: سيتم عرض الرسالة = ${availableDates.isNotEmpty && isDisabled}',
                            );

                            if (availableDates.isNotEmpty && isDisabled) {
                              return Column(
                                children: [
                                  SizedBox(height: 10),
                                  Center(
                                    child: Text(
                                      "للاستعلام فقط",
                                      style: TextStyle(
                                        color: Colors.red[700],
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // زر متابعة لإدخال البيانات - في نهاية الشاشة
                _buildContinueButton(getAvailableDates()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
