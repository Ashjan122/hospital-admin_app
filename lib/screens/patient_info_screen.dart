import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

class PatientInfoScreen extends StatefulWidget {
  final String centerId;
  final String specializationId;
  final String doctorId;
  final DateTime selectedDate;
  final String? selectedShift;
  final Map<String, dynamic> workingSchedule;
  final bool isReschedule;
  final Map<String, dynamic>? oldBookingData;

  const PatientInfoScreen({
    super.key,
    required this.centerId,
    required this.specializationId,
    required this.doctorId,
    required this.selectedDate,
    required this.selectedShift,
    required this.workingSchedule,
    this.isReschedule = false,
    this.oldBookingData,
  });

  @override
  State<PatientInfoScreen> createState() => _PatientInfoScreenState();
}

class _PatientInfoScreenState extends State<PatientInfoScreen> {
  String? patientName;
  String? patientPhone;
  bool isLoading = false;
  String? selectedTime;
  
  // Controllers for text fields
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  
  // Data for display
  String? facilityName;
  String? specializationName;
  String? doctorName;


  @override
  void initState() {
    super.initState();
    
    // Initialize controllers
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    
    // إذا كان هذا تأجيل حجز، استخدم البيانات القديمة
    if (widget.isReschedule && widget.oldBookingData != null) {
      patientName = widget.oldBookingData!['patientName'];
      patientPhone = widget.oldBookingData!['patientPhone'];
      _nameController.text = patientName ?? '';
      _phoneController.text = patientPhone ?? '';
    }
    
    // جلب بيانات المركز والتخصص والطبيب
    _loadFacilityData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }



  Future<void> _loadFacilityData() async {
    try {
      // جلب اسم المركز
      final facilityDoc = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .get();
      
      if (facilityDoc.exists) {
        facilityName = facilityDoc.data()?['name'] ?? 'مركز طبي';
      }
      
      // جلب اسم التخصص
      final specializationDoc = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(widget.specializationId)
          .get();
      
      if (specializationDoc.exists) {
        specializationName = specializationDoc.data()?['specName'] ?? 'تخصص طبي';
      }
      
      // جلب اسم الطبيب
      final doctorDoc = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(widget.specializationId)
          .collection('doctors')
          .doc(widget.doctorId)
          .get();
      
      if (doctorDoc.exists) {
        final d = doctorDoc.data();
        // محاولة جلب اسم الطبيب من عدة مفاتيح محتملة بما فيها docName
        doctorName = (d?['docName']
                ?? d?['name']
                ?? d?['doctorName']
                ?? d?['displayName']
                ?? d?['fullName']
                ?? d?['nameAr']
                ?? d?['arabicName'])
            ?.toString()
            .trim();
        if (doctorName == null || doctorName!.isEmpty) {
          doctorName = 'طبيب';
        }
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('خطأ في جلب بيانات المركز: $e');
    }
  }

  Future<Set<String>> getBookedTimes(DateTime date) async {
    final dateStr = intl.DateFormat('yyyy-MM-dd').format(date);
    final snapshot =
        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(widget.specializationId)
            .collection('doctors')
            .doc(widget.doctorId)
            .collection('appointments')
            .where('date', isEqualTo: dateStr)
            .get();

    return snapshot.docs.map((doc) => doc['time'] as String).toSet();
  }

  Future<Map<String, String>?> getAvailableTime(DateTime date) async {
    final bookedTimes = await getBookedTimes(date);
    final now = DateTime.now();
    final dayName = intl.DateFormat('EEEE', 'ar').format(date).trim();
    final schedule = widget.workingSchedule[dayName];
    final shiftKey = widget.selectedShift ?? 'morning';
    final shiftData = schedule[shiftKey];
    
    if (shiftData == null) return null;

    // فحص عدد المرضى المحجوزين في هذا اليوم والفترة
    final dateStr = intl.DateFormat('yyyy-MM-dd').format(date);
    final shiftBookings = await FirebaseFirestore.instance
        .collection('medicalFacilities')
        .doc(widget.centerId)
        .collection('specializations')
        .doc(widget.specializationId)
        .collection('doctors')
        .doc(widget.doctorId)
        .collection('appointments')
        .where('date', isEqualTo: dateStr)
        .where('period', isEqualTo: shiftKey)
        .get();

    // الحصول على حد المرضى للطبيب
    final doctorDoc = await FirebaseFirestore.instance
        .collection('medicalFacilities')
        .doc(widget.centerId)
        .collection('specializations')
        .doc(widget.specializationId)
        .collection('doctors')
        .doc(widget.doctorId)
        .get();

    final doctorData = doctorDoc.data();
    final patientLimit = shiftKey == 'morning' 
        ? (doctorData?['morningPatientLimit'] ?? 20)
        : (doctorData?['eveningPatientLimit'] ?? 20);

    // فحص إذا كان العدد قد اكتمل
    if (shiftBookings.docs.length >= patientLimit) {
      return null; // لا توجد مواعيد متاحة
    }

    // تحويل الوقت من 12 ساعة إلى 24 ساعة
    int startHour = int.parse(shiftData['start'].split(":")[0]);
    int endHour = int.parse(shiftData['end'].split(":")[0]);
    
    // إذا كان وقت النهاية أقل من وقت البداية، فهذا يعني أنه بعد الظهر
    if (endHour < startHour) {
      endHour += 12; // تحويل إلى 24 ساعة
    }

    for (int hour = startHour; hour <= endHour; hour++) {
      for (String suffix in [":00", ":30"]) {
        final timeStr = '${hour.toString().padLeft(2, '0')}$suffix';
        final timeObj = DateTime(
          date.year,
          date.month,
          date.day,
          hour,
          suffix == ":30" ? 30 : 0,
        );
        if (date.day == now.day && timeObj.isBefore(now)) continue;
        if (!bookedTimes.contains(timeStr)) {
          return {'time': timeStr, 'period': shiftKey};
        }
      }
    }
    return null;
  }

  Future<void> confirmBooking() async {
    print('TEST: بدء تأكيد الحجز');
    print('=== بدء تأكيد الحجز ===');
    print('اسم المريض: $patientName');
    print('رقم الهاتف: $patientPhone');
    print('التاريخ المحدد: ${widget.selectedDate}');
    print('الفترة المحددة: ${widget.selectedShift}');
    
    if (patientName == null ||
        patientName!.isEmpty ||
        patientPhone == null ||
        patientPhone!.isEmpty) {
      _showDialog("تنبيه", "يرجى إدخال الاسم ورقم الهاتف");
      return;
    }

    // التحقق من الاسم (اسمين على الأقل)
    List<String> nameParts = patientName!.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.length < 2) {
      _showDialog("تنبيه", "يرجى إدخال الاسم (اسمين على الأقل)");
      return;
    }
    
    // التحقق من رقم الهاتف (يجب أن يحتوي على أرقام فقط)
    String phoneDigits = patientPhone!.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.isEmpty) {
      _showDialog("تنبيه", "يرجى إدخال رقم هاتف صحيح");
      return;
    }

    // التحقق من عدم وجود حجز سابق لنفس الشخص في نفس اليوم (بالاسم الثلاثي فقط)
    final checkDateStr = intl.DateFormat('yyyy-MM-dd').format(widget.selectedDate);
    final existingBooking = await FirebaseFirestore.instance
        .collection('medicalFacilities')
        .doc(widget.centerId)
        .collection('specializations')
        .doc(widget.specializationId)
        .collection('doctors')
        .doc(widget.doctorId)
        .collection('appointments')
        .where('date', isEqualTo: checkDateStr)
        .where('patientName', isEqualTo: patientName)
        .get();

    if (existingBooking.docs.isNotEmpty) {
      _showDialog("حجز موجود", "يوجد حجز سابق لنفس الاسم في نفس اليوم لهذا الطبيب. لا يمكن الحجز مرة اخرى");
      return;
    }
    


    if (!mounted) return;
    setState(() => isLoading = true);

    final result = await getAvailableTime(widget.selectedDate);
    if (!mounted) return;
    
    if (result == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      
      // فحص إذا كان السبب هو اكتمال العدد
      final dateStr = intl.DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      final shiftKey = widget.selectedShift ?? 'morning';
      final shiftBookings = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(widget.specializationId)
          .collection('doctors')
          .doc(widget.doctorId)
          .collection('appointments')
          .where('date', isEqualTo: dateStr)
          .where('period', isEqualTo: shiftKey)
          .get();

      final doctorDoc = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(widget.specializationId)
          .collection('doctors')
          .doc(widget.doctorId)
          .get();

      final doctorData = doctorDoc.data();
      final patientLimit = shiftKey == 'morning' 
          ? (doctorData?['morningPatientLimit'] ?? 20)
          : (doctorData?['eveningPatientLimit'] ?? 20);

      if (shiftBookings.docs.length >= patientLimit) {
        final periodText = shiftKey == 'morning' ? 'الصباحية' : 'المسائية';
        _showDialog(
          "اكتمل العدد", 
          "عذراً، اكتمل العدد المحدد للمرضى في الفترة $periodText لهذا اليوم (${patientLimit} مريض).\nيرجى اختيار يوم آخر أو فترة أخرى."
        );
      } else {
        _showDialog("لا يوجد موعد", "لا توجد مواعيد متاحة في هذا اليوم");
      }
      return;
    }

    final availableTime = result['time']!;
    final period = result['period']!;
    final dateStr = intl.DateFormat('yyyy-MM-dd').format(widget.selectedDate);

    // Get current patient ID from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString('userId');

    if (widget.isReschedule && widget.oldBookingData != null) {
      // حذف الحجز القديم أولاً
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.oldBookingData!['facilityId'])
          .collection('specializations')
          .doc(widget.oldBookingData!['specializationId'])
          .collection('doctors')
          .doc(widget.oldBookingData!['doctorId'])
          .collection('appointments')
          .doc(widget.oldBookingData!['id'])
          .delete();
    }

    // إضافة الحجز الجديد
    await FirebaseFirestore.instance
        .collection('medicalFacilities')
        .doc(widget.centerId)
        .collection('specializations')
        .doc(widget.specializationId)
        .collection('doctors')
        .doc(widget.doctorId)
        .collection('appointments')
        .add({
          'patientName': patientName,
          'patientPhone': patientPhone,
          'patientId': patientId, // Save patient ID instead of phone

          'date': dateStr,
          'time': availableTime,
          'period': period,
          'createdAt': FieldValue.serverTimestamp(),
          'isConfirmed': false, // الحجز الجديد يحتاج تأكيد
        });

    if (!mounted) return;

    setState(() {
      isLoading = false;
      selectedTime = availableTime;
    });

    // عرض dialog نجاح الحجز
    if (mounted) {
      _showBookingSuccessDialog(dateStr, availableTime);
    }
  }

  void _showBookingSuccessDialog(String dateStr, String time) {
    final formattedDate = intl.DateFormat('EEEE - yyyy/MM/dd', 'ar').format(widget.selectedDate);
    final periodText = widget.selectedShift == 'morning' ? 'صباحية' : 'مسائية';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تم الحجز بنجاح',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
           
            const SizedBox(height: 16),
            _buildInfoRow('الاسم', patientName ?? ''),
            const SizedBox(height: 8),
            _buildInfoRow('رقم الهاتف', patientPhone ?? ''),
            const SizedBox(height: 8),
            _buildInfoRow('التاريخ', formattedDate),
            const SizedBox(height: 8),
            _buildInfoRow('الوقت', time),
            const SizedBox(height: 8),
            _buildInfoRow('الفترة', periodText),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // إغلاق dialog
              Navigator.of(context).pop(); // العودة للشاشة السابقة
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2FBDAF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }




  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Center(
          child: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        content: Text(message, textAlign: TextAlign.center),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("موافق", style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isReschedule ? "تأجيل الحجز" : "إدخال البيانات",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF2FBDAF),
              fontSize: 30,
            ),
          ),
        ),
        body: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                        // حقل الاسم
                        TextFormField(
                          decoration: InputDecoration(
                            labelText: 'الاسم *',
                            hintText: 'أدخل الاسم (اسمين على الأقل)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person, color: const Color(0xFF2FBDAF)),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: const Color(0xFF2FBDAF), width: 2),
                            ),
                            labelStyle: TextStyle(color: const Color(0xFF2FBDAF)),
                          ),
                          onChanged: (val) => patientName = val,
                          textDirection: TextDirection.rtl,
                          controller: _nameController,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال الاسم';
                            }
                            
                            List<String> nameParts = value.trim().split(' ').where((part) => part.isNotEmpty).toList();
                            
                            if (nameParts.length < 2) {
                              return 'يرجى إدخال الاسم (اسمين على الأقل)';
                            }
                            
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // حقل رقم الهاتف
                        TextFormField(
                          decoration: InputDecoration(
                            labelText: 'رقم الهاتف *',
                            hintText: 'أدخل رقم الهاتف',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone, color: const Color(0xFF2FBDAF)),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: const Color(0xFF2FBDAF), width: 2),
                            ),
                            labelStyle: TextStyle(color: const Color(0xFF2FBDAF)),
                          ),
                          onChanged: (val) => patientPhone = val,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.rtl,
                          controller: _phoneController,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال رقم الهاتف';
                            }
                            
                            String phoneDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
                            if (phoneDigits.isEmpty) {
                              return 'يرجى إدخال رقم هاتف صحيح';
                            }
                            
                            return null;
                          },
                        ),
                        
                        // مساحة فارغة لدفع الزر لأسفل
                        const Spacer(),
                        
                        // زر حجز الآن - في نهاية الشاشة
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: OutlinedButton(
                        onPressed: confirmBooking,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: const Color(0xFF2FBDAF),
                                width: 2,
                              ),
                              foregroundColor: const Color(0xFF2FBDAF),
                              backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.isReschedule ? "تأكيد التأجيل" : "حجز الآن",
                          style: const TextStyle(
                                fontSize: 20,
                            fontWeight: FontWeight.bold,
                              ),
                          ),
                        ),
                      ),
                      
                        const SizedBox(height: 20),

                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
