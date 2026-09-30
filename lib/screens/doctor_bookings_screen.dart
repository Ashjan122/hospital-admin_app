import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/sms_service.dart';
import 'login_screen.dart';

class DoctorBookingsScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String? centerName;
  final String doctorName;
  final DateTime? initialDate; // التاريخ المحدد لفتح الشاشة عليه
  final String? userId; // معرف المستخدم (موظف الاستقبال)

  const DoctorBookingsScreen({
    super.key,
    required this.doctorId,
    required this.centerId,
    this.centerName,
    required this.doctorName,
    this.initialDate, // التاريخ المحدد للحجز الجديد
    this.userId, // معرف المستخدم (موظف الاستقبال)
  });

  @override
  State<DoctorBookingsScreen> createState() => _DoctorBookingsScreenState();
}

class _DoctorBookingsScreenState extends State<DoctorBookingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newPatientNameController =
      TextEditingController();
  final TextEditingController _newPatientPhoneController =
      TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'today'; // تغيير الافتراضي إلى اليوم
  DateTime? _selectedDate; // فلترة حسب تاريخ معين
  // Set<String> _confirmingBookings = {}; // لتتبع الحجوزات التي يتم تأكيدها - معطل مؤقتاً
  // Set<String> _cancelingBookings = {}; // لتتبع الحجوزات التي يتم إلغاؤها - معطل مؤقتاً
  String? _userType; // نوع المستخدم (admin, doctor, etc.)
  List<Map<String, dynamic>> _allBookings = []; // جميع الحجوزات
  bool _isCreatingBooking = false; // حالة إنشاء الحجز الجديد

  // متغيرات لتحسين الأداء
  // bool _isLoading = true; // معطل مؤقتاً
  bool _isInitializing = true;
  // String _loadingMessage = 'جاري تحميل البيانات...'; // معطل مؤقتاً

  bool _isAlroomyMedicalCenter(String? name) {
    if (name == null) return false;
    final normalized =
        name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized == 'مركز الرومي الطبي';
  }

  @override
  void initState() {
    super.initState();

    print('=== DOCTOR BOOKINGS SCREEN INIT ===');
    print('Doctor ID: ${widget.doctorId}');
    print('Center ID: ${widget.centerId}');
    print('Doctor Name: ${widget.doctorName}');
    print('User ID: ${widget.userId}');
    print('User ID is null: ${widget.userId == null}');
    print('User ID is empty: ${widget.userId?.isEmpty ?? true}');

    // إذا كان هناك تاريخ محدد، استخدمه
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate;
      _selectedFilter = 'custom'; // تغيير الفلتر إلى تاريخ مخصص
      print('=== INITIALIZING WITH SPECIFIC DATE ===');
      print('Initial Date: ${widget.initialDate}');
      print('Selected Filter: $_selectedFilter');
    }

    // تحميل البيانات بشكل متوازي لتحسين السرعة
    _initializeDataParallel();
  }

  // دالة تحميل البيانات بشكل متوازي
  Future<void> _initializeDataParallel() async {
    print('=== INITIALIZING DATA IN PARALLEL ===');
    // _updateLoadingState('جاري تهيئة البيانات...'); // معطل مؤقتاً

    try {
      // تحميل نوع المستخدم والحجوزات في نفس الوقت
      await Future.wait([_loadUserType(), _loadBookings()]);

      print('✅ All data loaded successfully in parallel');

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print('❌ Error loading data in parallel: $e');
      // في حالة الخطأ، حاول التحميل بشكل منفصل
      await _loadUserType();
      await _loadBookings();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _loadUserType() async {
    print('=== LOADING USER TYPE ===');
    // _updateLoadingState('جاري تحميل نوع المستخدم...'); // معطل مؤقتاً

    try {
      final prefs = await SharedPreferences.getInstance();
      final userType = prefs.getString('userType');

      print('✅ User type loaded: $userType');

      if (mounted) {
        setState(() {
          _userType = userType;
        });
      }
    } catch (e) {
      print('❌ Error loading user type: $e');
    }
  }

  Future<void> _loadBookings() async {
    print('=== LOADING BOOKINGS ===');
    // _updateLoadingState('جاري تحميل الحجوزات...'); // معطل مؤقتاً

    try {
      // تحميل الحجوزات مع timeout لتحسين الأداء
      final bookings = await fetchDoctorBookings().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⚠️ Bookings loading timed out');
          throw TimeoutException('Bookings loading timed out');
        },
      );

      print('✅ Bookings loaded successfully: ${bookings.length} bookings');

      if (mounted) {
        setState(() {
          _allBookings = bookings;
        });
      }
    } catch (e) {
      print('❌ Error loading bookings: $e');
    }
  }

  // دالة تحديث حالة التحميل - معطلة مؤقتاً
  // void _updateLoadingState(String message) {
  //   if (mounted) {
  //     setState(() {
  //       _loadingMessage = message;
  //     });
  //   }
  // }

  // دالة زيادة عداد الحجوزات المؤكدة لموظف الاستقبال - معطلة مؤقتاً
  // Future<void> _incrementConfirmedBookingsCount() async {
  //   print('=== ENTERING _incrementConfirmedBookingsCount ===');
  //   print('User ID: ${widget.userId}');
  //   print('User ID is null: ${widget.userId == null}');
  //   print('User ID is empty: ${widget.userId?.isEmpty ?? true}');
  //
  //   if (widget.userId == null) {
  //     print('⚠️ No userId provided, skipping confirmed bookings count increment');
  //     return;
  //   }

  //   if (widget.userId!.isEmpty) {
  //     print('⚠️ User ID is empty, skipping confirmed bookings count increment');
  //     return;
  //   }

  //   try {
  //     print('=== INCREMENTING CONFIRMED BOOKINGS COUNT ===');
  //     print('User ID: ${widget.userId}');
  //     print('Center ID: ${widget.centerId}');

  //     // التحقق من وجود المستخدم وإنشاء حقل confirmedBookingsCount إذا لم يكن موجوداً
  //     print('🔍 Fetching user document...');
  //     final userDoc = await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(widget.userId)
  //         .get();

  //     print('📄 User document exists: ${userDoc.exists}');

  //     if (!userDoc.exists) {
  //       print('❌ User document not found, creating new user document');
  //       // إنشاء مستخدم جديد مع عداد الحجوزات المؤكدة
  //       await FirebaseFirestore.instance
  //           .collection('users')
  //           .doc(widget.userId)
  //           .set({
  //         'confirmedBookingsCount': 1,
  //         'lastUpdated': FieldValue.serverTimestamp(),
  //         'createdAt': FieldValue.serverTimestamp(),
  //       });
  //       print('✅ New user document created with confirmedBookingsCount: 1');
  //       return;
  //     }

  //     // التحقق من وجود حقل confirmedBookingsCount
  //     final userData = userDoc.data();
  //     print('📊 User data: $userData');
  //     print('🔢 Current confirmedBookingsCount: ${userData?['confirmedBookingsCount']}');
  //
  //     if (userData == null || userData['confirmedBookingsCount'] == null) {
  //       print('⚠️ confirmedBookingsCount field not found, initializing to 1');
  //       // إنشاء حقل confirmedBookingsCount إذا لم يكن موجوداً
  //       await FirebaseFirestore.instance
  //           .collection('users')
  //           .doc(widget.userId)
  //           .update({
  //         'confirmedBookingsCount': 1,
  //         'lastUpdated': FieldValue.serverTimestamp(),
  //       });
  //       print('✅ confirmedBookingsCount field initialized to 1');
  //       return;
  //     }

  //     // زيادة عداد الحجوزات المؤكدة في قاعدة البيانات
  //     print('🔄 Updating confirmedBookingsCount with increment...');
  //     await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(widget.userId)
  //         .update({
  //       'confirmedBookingsCount': FieldValue.increment(1),
  //       'lastUpdated': FieldValue.serverTimestamp(),
  //     });

  //     print('✅ Confirmed bookings count incremented successfully');
  //
  //     // التحقق من التحديث
  //     print('🔍 Verifying update...');
  //     final updatedDoc = await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(widget.userId)
  //         .get();
  //
  //     if (updatedDoc.exists) {
  //       final updatedData = updatedDoc.data();
  //       print('📊 Updated user data: $updatedData');
  //       print('🔢 New confirmedBookingsCount: ${updatedData?['confirmedBookingsCount']}');
  //     }
  //
  //   } catch (e) {
  //     print('❌ Error incrementing confirmed bookings count: $e');
  //     print('Error details: ${e.toString()}');
  //     print('Stack trace: ${StackTrace.current}');
  //     // لا نريد إيقاف عملية تأكيد الحجز بسبب فشل تحديث العداد
  //   }
  // }

  // دالة بناء شاشة التحميل الأولية
  Widget _buildInitialLoadingScreen() {
    return const Center(
      child: SizedBox(
        width: 80,
        height: 80,
        child: CircularProgressIndicator(
          strokeWidth: 6,
          valueColor: AlwaysStoppedAnimation<Color>(
            Color.fromARGB(255, 34, 96, 129),
          ),
        ),
      ),
    );
  }

  Future<void> _onAddBookingPressed() async {
    try {
      if (_userType != 'reception') {
        return; // حماية إضافية: الخاصية لموظف الاستقبال فقط
      }
      final bool isWorkingToday = await _isDoctorWorkingToday();
      if (!isWorkingToday) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ليس متاح اليوم'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      _newPatientNameController.clear();
      _newPatientPhoneController.clear();

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true, // السماح بالإغلاق بالضغط خارج الديالوق
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('إضافة حجز اليوم'),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _newPatientNameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المريض',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newPatientPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                      ),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed:
                        _isCreatingBooking
                            ? null
                            : () async {
                              final name =
                                  _newPatientNameController.text.trim();
                              final phone =
                                  _newPatientPhoneController.text.trim();

                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('يرجى إدخال اسم المريض'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              setState(() {
                                _isCreatingBooking = true;
                              });

                              try {
                                await _createTodayBooking(
                                  name: name,
                                  phone: phone,
                                );

                                // رسالة نجاح
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم إضافة الحجز بنجاح'),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }

                                // لا نغلق الحوار: نفرغ الحقول للسماح بحجز آخر
                                _newPatientNameController.clear();
                                _newPatientPhoneController.clear();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('خطأ في إنشاء الحجز: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isCreatingBooking = false;
                                  });
                                }
                              }
                            },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 34, 96, 129),
                      foregroundColor: Colors.white,
                    ),
                    child:
                        _isCreatingBooking
                            ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('جاري الحجز...'),
                              ],
                            )
                            : const Text('حجز الآن'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      print('Error in _onAddBookingPressed: $e');
    }
  }

  Future<bool> _isDoctorWorkingToday() async {
    try {
      final today = DateTime.now();
      final arabicDays = [
        'الاثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
        'الأحد',
      ];
      final todayName = arabicDays[today.weekday - 1];

      final specializationsSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .get();

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc =
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(widget.doctorId)
                .get();

        if (!doctorDoc.exists) continue;
        final data = doctorDoc.data();
        final workingSchedule =
            data?['workingSchedule'] as Map<String, dynamic>?;
        if (workingSchedule == null) return false;

        final daySchedule = workingSchedule[todayName];
        if (daySchedule == null) return false;

        final hasMorning = daySchedule['morning'] != null;
        final hasEvening = daySchedule['evening'] != null;
        return hasMorning || hasEvening;
      }
      return false;
    } catch (e) {
      print('Error checking doctor working today: $e');
      return false;
    }
  }

  Future<void> _createTodayBooking({
    required String name,
    required String phone,
  }) async {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final dateStr = intl.DateFormat('yyyy-MM-dd').format(todayDate);

    final specializationsSnapshot =
        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .get();

    for (var specDoc in specializationsSnapshot.docs) {
      final doctorRef = FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specDoc.id)
          .collection('doctors')
          .doc(widget.doctorId);

      final doctorDoc = await doctorRef.get();
      if (!doctorDoc.exists) continue;

      // تحقق من عدم تكرار الحجز لنفس المريض (نفس الرقم) في نفس اليوم
      final duplicateSnapshot =
          await doctorRef
              .collection('appointments')
              .where('date', isEqualTo: dateStr)
              .where('patientName', isEqualTo: name)
              .limit(1)
              .get();

      if (duplicateSnapshot.docs.isNotEmpty) {
        throw Exception('هذا المريض لديه حجز بالفعل اليوم');
      }

      // اجلب حجوزات اليوم للتحقق من التعارض الزمني
      final todayAppointmentsSnapshot =
          await doctorRef
              .collection('appointments')
              .where('date', isEqualTo: dateStr)
              .get();

      // ابنِ مجموعة أوقات اليوم المحجوزة بالدقائق منذ منتصف الليل
      final Set<int> usedMinutesFromMidnight = {};
      for (var d in todayAppointmentsSnapshot.docs) {
        final timeRaw = d.data()['time'];
        if (timeRaw == null) continue;
        final timeStr = timeRaw.toString().trim();
        if (timeStr.isEmpty) continue;
        final parts = timeStr.split(':');
        if (parts.length != 2) continue;
        final hh = int.tryParse(parts[0]);
        final mm = int.tryParse(parts[1]);
        if (hh == null || mm == null) continue;
        usedMinutesFromMidnight.add(hh * 60 + mm);
      }

      // احسب آخر وقت محجوز اليوم (إن وُجد) من خلال الدقائق
      DateTime? lastBookedDateTime;
      if (usedMinutesFromMidnight.isNotEmpty) {
        final lastMinutes = usedMinutesFromMidnight.reduce(
          (a, b) => a > b ? a : b,
        );
        final hh = lastMinutes ~/ 60;
        final mm = lastMinutes % 60;
        lastBookedDateTime = DateTime(
          todayDate.year,
          todayDate.month,
          todayDate.day,
          hh,
          mm,
        );
      }

      // المرشح الأول: إن وجِد آخر حجز فابدأ من (آخر وقت + 30 دقيقة)، وإلا من أقرب نصف ساعة قادمة من الآن
      DateTime candidate;
      if (lastBookedDateTime != null) {
        candidate = lastBookedDateTime.add(const Duration(minutes: 30));
      } else {
        DateTime roundedNow = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute,
        );
        if (roundedNow.minute % 30 != 0) {
          final int addMinutes = 30 - (roundedNow.minute % 30);
          roundedNow = roundedNow.add(Duration(minutes: addMinutes));
        }
        candidate = roundedNow;
      }

      String selectedTime = intl.DateFormat('HH:mm').format(candidate);
      int attempts = 0;
      while (usedMinutesFromMidnight.contains(
        candidate.hour * 60 + candidate.minute,
      )) {
        candidate = candidate.add(const Duration(minutes: 30));
        if (DateTime(candidate.year, candidate.month, candidate.day) !=
            todayDate) {
          break; // خرجنا من اليوم
        }
        selectedTime = intl.DateFormat('HH:mm').format(candidate);
        attempts++;
        if (attempts > 48) break; // حد أمان
      }

      if (usedMinutesFromMidnight.contains(
        candidate.hour * 60 + candidate.minute,
      )) {
        throw Exception('لا يوجد وقت متاح اليوم بدون تعارض');
      }

      final String computedPeriod = candidate.hour < 15 ? 'morning' : 'evening';

      // الحصول على اسم التخصص واسم الطبيب
      final doctorData = doctorDoc.data();
      final specializationData = specDoc.data();
      final specializationName =
          (specializationData is Map<String, dynamic>)
              ? (specializationData['specName'] as String? ?? specDoc.id)
              : specDoc.id;
      final doctorName =
          (doctorData is Map<String, dynamic>)
              ? (doctorData['doctorName'] as String? ?? widget.doctorName)
              : widget.doctorName;

      // حفظ الحجز في كولكشن appointments داخل المركز مباشرة
      final appointmentRef =
          FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('appointments')
              .doc();

      await appointmentRef.set({
        'patientName': name,
        'patientPhone': phone,
        'facilityId': widget.centerId,
        'centralSpecialtyId': specDoc.id,
        'doctorId': widget.doctorId,
        'doctorName': doctorName,
        'specializationName': specializationName,
        'date': dateStr,
        'time': selectedTime,
        'period': computedPeriod,
        'isConfirmed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': widget.userId ?? 'reception',
        'createdByType': 'reception',
      });

      await _loadBookings();
      if (mounted) setState(() {});
      return;
    }

    throw Exception('تعذر العثور على الطبيب لإضافة الحجز');
  }

  // دالة لحساب عدد الحجوزات حسب الفلتر
  int _getBookingsCount() {
    final filteredBookings = filterBookings(_allBookings);
    return filteredBookings.length;
  }

  // دالة لحساب رقم الحجز للمريض
  int _getBookingNumber(Map<String, dynamic> booking) {
    // تحديد التاريخ المستهدف
    DateTime targetDate;
    if (_selectedDate != null) {
      targetDate = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );
    } else {
      final now = DateTime.now();
      targetDate = DateTime(now.year, now.month, now.day);
    }

    final targetDateBookings =
        _allBookings.where((b) {
          final bookingDate = DateTime.tryParse(b['date'] ?? '');
          if (bookingDate == null) return false;
          final bookingDay = DateTime(
            bookingDate.year,
            bookingDate.month,
            bookingDate.day,
          );
          return bookingDay == targetDate;
        }).toList();

    // ترتيب الحجوزات حسب وقت الإنشاء
    targetDateBookings.sort((a, b) {
      final createdAtA = a['createdAt'];
      final createdAtB = b['createdAt'];

      if (createdAtA == null && createdAtB == null) return 0;
      if (createdAtA == null) return 1;
      if (createdAtB == null) return -1;

      DateTime dateA, dateB;
      if (createdAtA is Timestamp) {
        dateA = createdAtA.toDate();
      } else if (createdAtA is String) {
        dateA = DateTime.parse(createdAtA);
      } else {
        return 1;
      }

      if (createdAtB is Timestamp) {
        dateB = createdAtB.toDate();
      } else if (createdAtB is String) {
        dateB = DateTime.parse(createdAtB);
      } else {
        return -1;
      }

      return dateA.compareTo(dateB);
    });

    // البحث عن رقم الحجز للمريض الحالي
    for (int i = 0; i < targetDateBookings.length; i++) {
      if (targetDateBookings[i]['appointmentId'] == booking['appointmentId']) {
        return i + 1;
      }
    }
    return 0;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Color.fromARGB(255, 34, 96, 129),
              secondary: Color.fromARGB(255, 34, 96, 129),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Color.fromARGB(255, 34, 96, 129),
              ),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  String _formatSelectedDate(DateTime date) {
    try {
      return intl.DateFormat('yyyy/MM/dd', 'ar').format(date);
    } catch (_) {
      return '${date.year}/${date.month}/${date.day}';
    }
  }

  Future<List<Map<String, dynamic>>> fetchDoctorBookings() async {
    try {
      // جلب الحجوزات من كولكشن appointments داخل المركز مباشرة مع فلترة حسب doctorId
      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('appointments')
          .where('doctorId', isEqualTo: widget.doctorId)
          .get()
          .timeout(const Duration(seconds: 10));

      List<Map<String, dynamic>> allBookings = [];

      // إضافة الحجوزات إلى القائمة
      for (var appointmentDoc in appointmentsSnapshot.docs) {
        final appointmentData = Map<String, dynamic>.from(
          appointmentDoc.data(),
        );
        appointmentData['appointmentId'] = appointmentDoc.id;
        // إضافة اسم التخصص إذا كان متوفراً
        final specializationName = appointmentData['specializationName'];
        if (specializationName != null) {
          appointmentData['specialization'] = specializationName;
        }
        allBookings.add(appointmentData);
      }

      // ترتيب الحجوزات حسب وقت الحجز (آخر حجز يظهر أولاً)
      allBookings.sort((a, b) {
        final createdAtA = a['createdAt'];
        final createdAtB = b['createdAt'];

        // إذا كان وقت الحجز متوفر، نرتب حسبه
        if (createdAtA != null && createdAtB != null) {
          try {
            DateTime timeA, timeB;

            if (createdAtA is Timestamp) {
              timeA = createdAtA.toDate();
            } else if (createdAtA is String) {
              timeA = DateTime.parse(createdAtA);
            } else {
              throw Exception('Invalid createdAt type');
            }

            if (createdAtB is Timestamp) {
              timeB = createdAtB.toDate();
            } else if (createdAtB is String) {
              timeB = DateTime.parse(createdAtB);
            } else {
              throw Exception('Invalid createdAt type');
            }

            return timeB.compareTo(timeA); // آخر حجز أولاً
          } catch (e) {
            // في حالة خطأ في تحليل التاريخ، نرتب حسب تاريخ الحجز
          }
        }

        // إذا لم يكن وقت الحجز متوفر، نرتب حسب تاريخ الحجز
        final dateA = DateTime.tryParse(a['date'] ?? '');
        final dateB = DateTime.tryParse(b['date'] ?? '');

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return dateB.compareTo(dateA); // الأحدث أولاً
      });

      return allBookings;
    } catch (e) {
      print('Error fetching doctor bookings: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> filterBookings(
    List<Map<String, dynamic>> bookings,
  ) {
    List<Map<String, dynamic>> filteredBookings = bookings;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final searchLower = _searchQuery.toLowerCase().trim();
      filteredBookings =
          filteredBookings.where((booking) {
            final patientName =
                booking['patientName']?.toString().toLowerCase() ?? '';
            final patientPhone =
                booking['patientPhone']?.toString().toLowerCase() ?? '';

            return patientName.contains(searchLower) ||
                patientPhone.contains(searchLower);
          }).toList();
    }

    // تحديد التاريخ المستهدف
    DateTime targetDate;
    if (_selectedDate != null) {
      targetDate = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );
    } else {
      final now = DateTime.now();
      targetDate = DateTime(now.year, now.month, now.day);
    }

    // فلترة حسب التاريخ المستهدف أولاً
    filteredBookings =
        filteredBookings.where((booking) {
          final bookingDate = DateTime.tryParse(booking['date'] ?? '');
          return bookingDate != null &&
              DateTime(bookingDate.year, bookingDate.month, bookingDate.day) ==
                  targetDate;
        }).toList();

    // فلترة حسب الفترة (صباح/مساء)
    switch (_selectedFilter) {
      case 'morning':
        filteredBookings =
            filteredBookings.where((booking) {
              final period = booking['period']?.toString().toLowerCase() ?? '';
              return period == 'morning';
            }).toList();
        break;
      case 'evening':
        filteredBookings =
            filteredBookings.where((booking) {
              final period = booking['period']?.toString().toLowerCase() ?? '';
              return period == 'evening';
            }).toList();
        break;
      case 'all':
      default:
        // لا تفلتر حسب الفترة، اعرض كل الحجوزات في التاريخ المحدد
        break;
    }

    return filteredBookings;
  }

  String formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return intl.DateFormat('EEEE, yyyy/MM/dd', 'ar').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String formatTime(String timeStr) {
    try {
      final date = DateTime.parse(timeStr);
      return intl.DateFormat('HH:mm', 'ar').format(date);
    } catch (e) {
      return timeStr;
    }
  }

  String getPeriodText(String period) {
    switch (period) {
      case 'morning':
        return 'صباحاً';
      case 'evening':
        return 'مساءً';
      default:
        return period;
    }
  }

  Color getStatusColor(String dateStr, {bool isConfirmed = false}) {
    // If not confirmed, show orange
    if (!isConfirmed) {
      return Colors.orange;
    }

    try {
      final bookingDate = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final bookingDay = DateTime(
        bookingDate.year,
        bookingDate.month,
        bookingDate.day,
      );

      if (bookingDay.isBefore(today)) {
        return Colors.grey; // Past
      } else if (bookingDay == today) {
        return Colors.green; // Today
      } else {
        return Color.fromARGB(255, 34, 96, 129); // Upcoming
      }
    } catch (e) {
      return Colors.grey;
    }
  }

  String getStatusText(String dateStr, {bool isConfirmed = false}) {
    if (!isConfirmed) {
      return 'في انتظار التأكيد';
    }

    try {
      final bookingDate = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final bookingDay = DateTime(
        bookingDate.year,
        bookingDate.month,
        bookingDate.day,
      );

      if (bookingDay.isBefore(today)) {
        return 'سابقة';
      } else if (bookingDay == today) {
        return 'اليوم';
      } else {
        return 'قادمة';
      }
    } catch (e) {
      return 'غير محدد';
    }
  }

  String formatBookingTime(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      DateTime date;
      if (createdAt is Timestamp) {
        date = createdAt.toDate();
      } else if (createdAt is String) {
        date = DateTime.parse(createdAt);
      } else {
        return '';
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final bookingDay = DateTime(date.year, date.month, date.day);

      String timeText = intl.DateFormat('HH:mm', 'en').format(date);

      if (bookingDay == today) {
        return 'اليوم $timeText';
      } else if (bookingDay == yesterday) {
        return 'أمس $timeText';
      } else {
        // إذا كان قديماً، نعرض التاريخ الكامل
        String dateText = intl.DateFormat('yyyy/MM/dd', 'en').format(date);
        return '$dateText $timeText';
      }
    } catch (e) {
      return '';
    }
  }

  // دالة إرسال رسالة تأكيد - معطلة مؤقتاً
  // Future<void> _sendConfirmationSMS(Map<String, dynamic> booking) async {
  //   try {
  //     final patientPhone = booking['patientPhone'] ?? '';
  //
  //     if (patientPhone.isEmpty) {
  //       print('No phone number available for SMS');
  //       return;
  //     }
  //
  //     final date = formatDate(booking['date']);
  //     final time = formatTime(booking['time']);
  //     final period = getPeriodText(booking['period'] ?? '');
  //
  //     final message = 'تم تأكيد حجزك في ${booking['specialization']} مع د. ${widget.doctorName} في $date الساعة $time $period';
  //
  //     print('Sending confirmation SMS to: $patientPhone');
  //     print('Message: $message');
  //
  //     final result = await SMSService.sendSimpleSMS(patientPhone, message);
  //
  //     if (result['success'] == true) {
  //       print('SMS sent successfully');
  //     } else {
  //       print('Failed to send SMS: ${result['message']}');
  //     }
  //   } catch (e) {
  //     print('Error sending confirmation SMS: $e');
  //   }
  // }

  // دالة تأكيد الحجز - معطلة مؤقتاً
  // Future<void> _confirmBooking(Map<String, dynamic> booking) async {
  //   final appointmentId = booking['appointmentId'];
  //
  //   // إضافة loading محلي للحجز المحدد
  //   setState(() {
  //     _confirmingBookings.add(appointmentId);
  //   });

  //   try {
  //     print('=== CONFIRMING BOOKING ===');
  //     print('Appointment ID: $appointmentId');
  //     print('Center ID: ${widget.centerId}');
  //     print('Doctor ID: ${widget.doctorId}');
  //     print('User ID: ${widget.userId}'); // تسجيل معرف المستخدم
  //     print('User ID is null: ${widget.userId == null}'); // التحقق من null
  //
  //     final specializationId = booking['specializationId'];
  //
  //     await FirebaseFirestore.instance
  //         .collection('medicalFacilities')
  //         .doc(widget.centerId)
  //         .collection('specializations')
  //         .doc(specializationId)
  //         .collection('doctors')
  //         .doc(widget.doctorId)
  //         .collection('appointments')
  //         .doc(appointmentId)
  //         .update({
  //       'isConfirmed': true,
  //       'confirmedAt': FieldValue.serverTimestamp(),
  //     });

  //     print('✅ Booking confirmed successfully in database');

  //     // إرسال رسالة تأكيد للمريض
  //     await _sendConfirmationSMS(booking);

  //     // زيادة عداد الحجوزات المؤكدة لموظف الاستقبال
  //     print('🔄 Calling _incrementConfirmedBookingsCount...');
  //     print('🔄 User ID when calling: ${widget.userId}');
  //     print('🔄 User ID is null when calling: ${widget.userId == null}');
  //
  //     if (widget.userId != null && widget.userId!.isNotEmpty) {
  //       await _incrementConfirmedBookingsCount();
  //       print('✅ _incrementConfirmedBookingsCount completed successfully');
  //     } else {
  //       print('❌ Cannot call _incrementConfirmedBookingsCount - userId is null or empty');
  //     }

  //     if (mounted && context.mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('تم تأكيد الحجز وإرسال رسالة للمريض'),
  //           backgroundColor: Colors.green,
  //         ),
  //       );
  //       setState(() {}); // تحديث الواجهة
  //     }
  //   } catch (e) {
  //     if (mounted && context.mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('خطأ في تأكيد الحجز: $e'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   } finally {
  //     // إزالة loading المحلي
  //     setState(() {
  //       _confirmingBookings.remove(appointmentId);
  //     });
  //   }
  // }

  // دالة إرسال رسالة إلغاء - معطلة مؤقتاً
  // Future<void> _sendCancellationSMS(Map<String, dynamic> booking) async {
  //   try {
  //     final patientPhone = booking['patientPhone'] ?? '';
  //
  //     if (patientPhone.isEmpty) {
  //       print('No phone number available for cancellation SMS');
  //       return;
  //     }
  //
  //     final date = formatDate(booking['date']);
  //     final time = formatTime(booking['time']);
  //     final period = getPeriodText(booking['period'] ?? '');
  //
  //     final message = 'تم إلغاء حجزك في ${booking['specialization']} مع د. ${widget.doctorName} في $date الساعة $time $period';
  //
  //     print('Sending cancellation SMS to: $patientPhone');
  //     print('Message: $message');
  //
  //     final result = await SMSService.sendSimpleSMS(patientPhone, message);
  //
  //     if (result['success'] == true) {
  //       print('Cancellation SMS sent successfully');
  //     } else {
  //       print('Failed to send cancellation SMS: ${result['message']}');
  //     }
  //   } catch (e) {
  //     print('Error sending cancellation SMS: $e');
  //   }
  // }

  // دالة إلغاء الحجز - معطلة مؤقتاً
  // Future<void> _cancelBooking(Map<String, dynamic> booking) async {
  //   final appointmentId = booking['appointmentId'];
  //
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       title: const Text('تأكيد إلغاء الحجز'),
  //       content: Text('هل أنت متأكد من إلغاء حجز المريض "${booking['patientName']}"؟'),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, false),
  //           child: const Text('إلغاء'),
  //         ),
  //         ElevatedButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.red,
  //             foregroundColor: Colors.white,
  //           ),
  //           child: const Text('إلغاء الحجز'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed == true) {
  //     // إضافة loading محلي للحجز المحدد
  //     setState(() {
  //       _cancelingBookings.add(appointmentId);
  //     });

  //     try {
  //       final specializationId = booking['specializationId'];
  //
  //       // إرسال رسالة إلغاء للمريض قبل حذف الحجز
  //       await _sendCancellationSMS(booking);
  //
  //       await FirebaseFirestore.instance
  //           .collection('medicalFacilities')
  //           .doc(widget.centerId)
  //           .collection('specializations')
  //           .doc(specializationId)
  //           .collection('doctors')
  //           .doc(widget.doctorId)
  //           .collection('appointments')
  //           .doc(appointmentId)
  //           .delete();

  //       if (mounted && context.mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(
  //             content: Text('تم إلغاء الحجز وإرسال رسالة للمريض'),
  //             backgroundColor: Colors.orange,
  //           ),
  //         );
  //         setState(() {}); // تحديث الواجهة
  //       }
  //     } catch (e) {
  //       if (mounted && context.mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //             content: Text('خطأ في إلغاء الحجز: $e'),
  //             backgroundColor: Colors.red,
  //           ),
  //         );
  //       }
  //     } finally {
  //       // إزالة loading المحلي
  //       setState(() {
  //         _cancelingBookings.remove(appointmentId);
  //       });
  //     }
  //   }
  // }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // مسح جميع البيانات المحفوظة

      if (mounted && context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false, // إزالة جميع الصفحات السابقة
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تسجيل الخروج: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.doctorName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
          // centerTitle: true,
          elevation: 0,
          actions: [
            if (_userType == 'reception')
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _onAddBookingPressed,
                tooltip: 'إضافة حجز جديد',
              ),

            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: _pickDate,
              tooltip: 'اختر تاريخاً لعرض الحجوزات',
            ),

            if (_userType == 'doctor')
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _logout,
                tooltip: 'تسجيل الخروج',
              ),
          ],
        ),
        body: SafeArea(
          child:
              _isInitializing
                  ? _buildInitialLoadingScreen()
                  : Column(
                    children: [
                      // Search and filter section
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.grey[50],
                        child: Column(
                          children: [
                            // Search bar
                            TextField(
                              controller: _searchController,
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'البحث باسم المريض أو رقم الهاتف...',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Filter buttons
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildFilterChip('الكل', 'all'),
                                  const SizedBox(width: 8),
                                  _buildFilterChip('صباح', 'morning'),
                                  const SizedBox(width: 8),
                                  _buildFilterChip('مساء', 'evening'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Bookings counter
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'عدد الحجوزات: ${_getBookingsCount()}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                if (_selectedDate != null)
                                  Text(
                                    'التاريخ: ${_formatSelectedDate(_selectedDate!)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Bookings list
                      Expanded(
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: fetchDoctorBookings(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Color.fromARGB(255, 34, 96, 129),
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 64,
                                      color: Colors.red[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'حدث خطأ في تحميل الحجوزات',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final bookings = snapshot.data ?? [];
                            final filteredBookings = filterBookings(bookings);

                            if (filteredBookings.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _searchQuery.isEmpty
                                          ? Icons.calendar_today
                                          : Icons.search_off,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'لا توجد حجوزات للطبيب'
                                          : 'لم يتم العثور على حجوزات تطابق البحث',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: filteredBookings.length,
                              itemBuilder: (context, index) {
                                final booking = filteredBookings[index];
                                final patientName =
                                    booking['patientName'] ?? 'مريض غير معروف';
                                final patientPhone =
                                    booking['patientPhone'] ?? '';
                                final date = booking['date'] ?? '';
                                final time = booking['time'] ?? '';
                                final period = booking['period'] ?? '';
                                final isConfirmed =
                                    booking['isConfirmed'] ?? false;

                                final bookingNumber = _getBookingNumber(
                                  booking,
                                );
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.08),
                                        spreadRadius: 1,
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            // Content
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // Patient name (main title) - قابل للضغط
                                                  InkWell(
                                                    onTap: () {
                                                      print(
                                                        'DEBUG: تم الضغط على اسم المريض: $patientName',
                                                      );
                                                      Navigator.of(
                                                        context,
                                                      ).push(
                                                        MaterialPageRoute(
                                                          builder:
                                                              (
                                                                context,
                                                              ) => Directionality(
                                                                textDirection:
                                                                    TextDirection
                                                                        .rtl,
                                                                child: Scaffold(
                                                                  appBar: AppBar(
                                                                    title: Text(
                                                                      patientName,
                                                                    ),
                                                                    backgroundColor:
                                                                        Color.fromARGB(
                                                                          255,
                                                                          34,
                                                                          96,
                                                                          129,
                                                                        ),
                                                                    foregroundColor:
                                                                        Colors
                                                                            .white,
                                                                    elevation:
                                                                        0,
                                                                  ),
                                                                  body: SafeArea(
                                                                    child: Padding(
                                                                      padding:
                                                                          const EdgeInsets.all(
                                                                            16,
                                                                          ),
                                                                      child: GridView.count(
                                                                        crossAxisCount:
                                                                            2,
                                                                        crossAxisSpacing:
                                                                            16,
                                                                        mainAxisSpacing:
                                                                            16,
                                                                        children: [
                                                                          _buildGridItem(
                                                                            icon:
                                                                                Icons.message,
                                                                            title:
                                                                                'رسالة الاعتذار',
                                                                            color:
                                                                                Colors.red,
                                                                            onTap: () {
                                                                              Navigator.of(
                                                                                context,
                                                                              ).push(
                                                                                MaterialPageRoute(
                                                                                  builder:
                                                                                      (
                                                                                        context,
                                                                                      ) => _MessageScreen(
                                                                                        booking:
                                                                                            booking,
                                                                                      ),
                                                                                ),
                                                                              );
                                                                            },
                                                                          ),
                                                                          _buildGridItem(
                                                                            icon:
                                                                                Icons.schedule,
                                                                            title:
                                                                                'الموعد',
                                                                            color:
                                                                                Colors.blue,
                                                                            onTap: () {
                                                                              Navigator.of(
                                                                                context,
                                                                              ).push(
                                                                                MaterialPageRoute(
                                                                                  builder:
                                                                                      (
                                                                                        context,
                                                                                      ) => _ScheduleAppointmentScreen(
                                                                                        doctorId:
                                                                                            widget.doctorId,
                                                                                        centerId:
                                                                                            widget.centerId,
                                                                                        doctorName:
                                                                                            widget.doctorName,
                                                                                        patientName:
                                                                                            patientName,
                                                                                        patientPhone:
                                                                                            booking['patientPhone'] ??
                                                                                            '',
                                                                                      ),
                                                                                ),
                                                                              );
                                                                            },
                                                                          ),
                                                                          _buildGridItem(
                                                                            icon:
                                                                                Icons.note,
                                                                            title:
                                                                                'الملاحظات',
                                                                            color:
                                                                                Colors.orange,
                                                                            onTap: () {
                                                                              final patientPhone =
                                                                                  booking['patientPhone'] ??
                                                                                  '';
                                                                              Navigator.of(
                                                                                context,
                                                                              ).push(
                                                                                MaterialPageRoute(
                                                                                  builder:
                                                                                      (
                                                                                        context,
                                                                                      ) => _PatientNotesScreen(
                                                                                        doctorId:
                                                                                            widget.doctorId,
                                                                                        centerId:
                                                                                            widget.centerId,
                                                                                        patientName:
                                                                                            patientName,
                                                                                        patientPhone:
                                                                                            patientPhone,
                                                                                      ),
                                                                                ),
                                                                              );
                                                                            },
                                                                          ),
                                                                          _buildGridItem(
                                                                            icon:
                                                                                Icons.person,
                                                                            title:
                                                                                'معلومات المريض',
                                                                            color:
                                                                                Colors.green,
                                                                            onTap: () {
                                                                              Navigator.of(
                                                                                context,
                                                                              ).push(
                                                                                MaterialPageRoute(
                                                                                  builder:
                                                                                      (
                                                                                        context,
                                                                                      ) => _PatientDetailsScreen(
                                                                                        booking:
                                                                                            booking,
                                                                                      ),
                                                                                ),
                                                                              );
                                                                            },
                                                                          ),
                                                                          // إظهار نتيجة المختبر فقط إذا كان المركز هو "مركز الرومي الطبي" تحديداً
                                                                          if (_isAlroomyMedicalCenter(
                                                                            widget.centerName,
                                                                          ))
                                                                            _buildGridItem(
                                                                              icon:
                                                                                  Icons.science,
                                                                              title:
                                                                                  'نتيجة المختبر',
                                                                              color:
                                                                                  Colors.purple,
                                                                              onTap: () {
                                                                                final patientPhone =
                                                                                    booking['patientPhone'] ??
                                                                                    '';
                                                                                print(
                                                                                  '=== NAVIGATING TO LAB RESULTS ===',
                                                                                );
                                                                                print(
                                                                                  'Patient Phone from booking: $patientPhone',
                                                                                );
                                                                                print(
                                                                                  'Patient Name: $patientName',
                                                                                );
                                                                                Navigator.of(
                                                                                  context,
                                                                                ).push(
                                                                                  MaterialPageRoute(
                                                                                    builder:
                                                                                        (
                                                                                          context,
                                                                                        ) => _LabResultsScreen(
                                                                                          patientPhone:
                                                                                              patientPhone,
                                                                                          patientName:
                                                                                              patientName,
                                                                                        ),
                                                                                  ),
                                                                                );
                                                                              },
                                                                            ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                        ),
                                                      );
                                                    },
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            4,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.person,
                                                            size: 18,
                                                            color:
                                                                Color.fromARGB(
                                                                  255,
                                                                  34,
                                                                  96,
                                                                  129,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              patientName,
                                                              style: const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    Colors
                                                                        .black87,
                                                              ),
                                                            ),
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .arrow_forward_ios,
                                                            size: 16,
                                                            color:
                                                                Colors
                                                                    .grey[400],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),

                                                  // Patient phone
                                                  if (patientPhone
                                                      .toString()
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.phone,
                                                          size: 16,
                                                          color: Color.fromARGB(
                                                            255,
                                                            34,
                                                            96,
                                                            129,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            patientPhone
                                                                .toString(),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color:
                                                                  Colors
                                                                      .grey[600],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],

                                                  // Date and time
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.calendar_today,
                                                        size: 16,
                                                        color: Color.fromARGB(
                                                          255,
                                                          34,
                                                          96,
                                                          129,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          '${formatDate(date)} -  ${getPeriodText(period)}',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                Colors
                                                                    .grey[500],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Status badge
                                            Column(
                                              children: [
                                                // Booking time
                                                if (booking['createdAt'] !=
                                                    null) ...[
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[200],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      formatBookingTime(
                                                        booking['createdAt'],
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.grey[600],
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                ],
                                                // Status badge
                                                // Status badge - معطل مؤقتاً
                                                // Container(
                                                //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                //   decoration: BoxDecoration(
                                                //     color: getStatusColor(date, isConfirmed: isConfirmed).withOpacity(0.1),
                                                //     borderRadius: BorderRadius.circular(12),
                                                //     border: Border.all(
                                                //       color: getStatusColor(date, isConfirmed: isConfirmed).withOpacity(0.3),
                                                //     ),
                                                //   ),
                                                //   child: Text(
                                                //     getStatusText(date, isConfirmed: isConfirmed),
                                                //     style: TextStyle(
                                                //       fontSize: 10,
                                                //       color: getStatusColor(date, isConfirmed: isConfirmed),
                                                //       fontWeight: FontWeight.bold,
                                                //     ),
                                                //   ),
                                                // ),
                                                // Booking number
                                                const SizedBox(height: 4),
                                                Text(
                                                  '$bookingNumber من ${_getBookingsCount()}',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.grey[600],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),

                                        // Action buttons (only for unconfirmed bookings and admin/reception users)
                                        if (!isConfirmed &&
                                            (_userType == 'admin' ||
                                                _userType == 'reception')) ...[
                                          const SizedBox(height: 6),
                                          // أزرار التأكيد والإلغاء معطلة مؤقتاً
                                          // Row(
                                          //   children: [
                                          //     Expanded(
                                          //       child: ElevatedButton.icon(
                                          //         onPressed: _confirmingBookings.contains(booking['appointmentId'])
                                          //             ? null
                                          //             : () => _confirmBooking(booking),
                                          //         icon: _confirmingBookings.contains(booking['appointmentId'])
                                          //             ? const SizedBox(
                                          //                 width: 16,
                                          //                 height: 16,
                                          //                 child: CircularProgressIndicator(
                                          //                   strokeWidth: 2,
                                          //                   color: Colors.white,
                                          //                 ),
                                          //               )
                                          //             : const Icon(Icons.check, size: 16),
                                          //         label: Text(
                                          //           _confirmingBookings.contains(booking['appointmentId'])
                                          //               ? 'جاري التأكيد...'
                                          //               : 'تأكيد الحجز',
                                          //         ),
                                          //         style: ElevatedButton.styleFrom(
                                          //           backgroundColor: Colors.green,
                                          //           foregroundColor: Colors.white,
                                          //           padding: const EdgeInsets.symmetric(vertical: 8),
                                          //         ),
                                          //       ),
                                          //     ),
                                          //     const SizedBox(width: 8),
                                          //     Expanded(
                                          //       child: ElevatedButton.icon(
                                          //         onPressed: _cancelingBookings.contains(booking['appointmentId'])
                                          //             ? null
                                          //             : () => _cancelBooking(booking),
                                          //         icon: _cancelingBookings.contains(booking['appointmentId'])
                                          //             ? const SizedBox(
                                          //                 width: 16,
                                          //                 height: 16,
                                          //                 child: CircularProgressIndicator(
                                          //                   strokeWidth: 2,
                                          //                   color: Colors.white,
                                          //                 ),
                                          //               )
                                          //             : const Icon(Icons.cancel, size: 16),
                                          //         label: Text(
                                          //           _cancelingBookings.contains(booking['appointmentId'])
                                          //               ? 'جاري الإلغاء...'
                                          //               : 'إلغاء الحجز',
                                          //         ),
                                          //         style: ElevatedButton.styleFrom(
                                          //           backgroundColor: Colors.red,
                                          //           foregroundColor: Colors.white,
                                          //           padding: const EdgeInsets.symmetric(vertical: 8),
                                          //         ),
                                          //       ),
                                          //     ),
                                          //   ],
                                          // ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: Color.fromARGB(255, 34, 96, 129).withOpacity(0.2),
      checkmarkColor: Color.fromARGB(255, 34, 96, 129),
      labelStyle: TextStyle(
        color: isSelected ? Color.fromARGB(255, 34, 96, 129) : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

// إضافة الكلاسات المطلوبة للبطاقات
Widget _buildGridItem({
  required IconData icon,
  required String title,
  required Color color,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.grey[300]!),
    ),
    elevation: 1,
    shadowColor: Colors.black.withOpacity(0.08),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _MessageScreen extends StatefulWidget {
  final Map<String, dynamic> booking;

  const _MessageScreen({required this.booking});

  @override
  State<_MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<_MessageScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _sendingWhatsApp = false;
  bool _sendingSMS = false;
  final String _apologyTemplate =
      'عذراً، تم إلغاء موعد اليوم. يرجى الحجز في يوم آخر.';

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendWhatsAppMessage() async {
    final phone = widget.booking['patientPhone']?.toString() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('رقم الهاتف غير متوفر')));
      return;
    }

    setState(() {
      _sendingWhatsApp = true;
    });

    try {
      final formattedPhone = phone;
      var headers = {'Content-Type': 'application/x-www-form-urlencoded'};

      var request = http.Request(
        'POST',
        Uri.parse('https://api.ultramsg.com/instance140877/messages/chat'),
      );
      request.bodyFields = {
        'token': 'df2r46jz82otkegg',
        'to': formattedPhone,
        'body': _messageController.text,
      };
      request.headers.addAll(headers);

      http.StreamedResponse response = await request.send();

      if (response.statusCode == 200) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال الرسالة عبر واتساب')),
          );
        }
      } else {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في إرسال الرسالة: ${response.statusCode}'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingWhatsApp = false;
        });
      }
    }
  }

  Future<void> _sendSMS() async {
    final phone = widget.booking['patientPhone']?.toString() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('رقم الهاتف غير متوفر')));
      return;
    }

    setState(() {
      _sendingSMS = true;
    });

    try {
      final result = await SMSService.sendSimpleSMS(
        phone,
        _messageController.text,
      );

      if (result['success'] == true) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال الرسالة النصية')),
          );
        }
      } else {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل في إرسال الرسالة: ${result['message']}'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingSMS = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('رسالة للمريض'),
          backgroundColor: Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'رسالة اعتذار',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageController,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  onTap: () {
                    if (_messageController.text.trim().isEmpty) {
                      _messageController.text = _apologyTemplate;
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _messageController.text.length),
                      );
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'اكتب الرسالة هنا...',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.black,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _sendingWhatsApp ? null : _sendWhatsAppMessage,
                        icon: const Icon(Icons.chat, color: Colors.white),
                        label: Text(
                          _sendingWhatsApp ? 'جاري الإرسال...' : 'واتساب',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _sendingSMS ? null : _sendSMS,
                        icon: const Icon(Icons.sms, color: Colors.white),
                        label: Text(
                          _sendingSMS ? 'جاري الإرسال...' : 'رسالة نصية',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color.fromARGB(255, 34, 96, 129),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleAppointmentScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String doctorName;
  final String patientName;
  final String patientPhone;

  const _ScheduleAppointmentScreen({
    required this.doctorId,
    required this.centerId,
    required this.doctorName,
    required this.patientName,
    required this.patientPhone,
  });

  @override
  State<_ScheduleAppointmentScreen> createState() =>
      _ScheduleAppointmentScreenState();
}

class _ScheduleAppointmentScreenState
    extends State<_ScheduleAppointmentScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _appointmentType = 'مقابلة';
  bool _saving = false;

  final List<String> _appointmentTypes = ['مقابلة', 'عملية صغيرة'];

  Future<void> _selectDate() async {
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime.now().add(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        locale: const Locale('ar', 'SA'),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color.fromARGB(255, 34, 96, 129),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        setState(() {
          _selectedDate = DateTime(picked.year, picked.month, picked.day);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في اختيار التاريخ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveAppointment() async {
    if (_selectedDate.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن تحديد موعد في الماضي')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final appointmentDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      // البحث عن التخصص الذي ينتمي إليه الطبيب
      final specializationsSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .get();

      String? specializationId;
      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc =
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(widget.doctorId)
                .get();

        if (doctorDoc.exists) {
          specializationId = specDoc.id;
          break;
        }
      }

      if (specializationId == null) {
        throw Exception('لم يتم العثور على تخصص الطبيب');
      }

      // حفظ الموعد في التخصص الصحيح
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specializationId)
          .collection('doctors')
          .doc(widget.doctorId)
          .collection('scheduledAppointments')
          .add({
            'patientName': widget.patientName,
            'patientPhone': widget.patientPhone,
            'doctorId': widget.doctorId,
            'doctorName': widget.doctorName,
            'centerId': widget.centerId,
            'appointmentDate': appointmentDateTime.toIso8601String(),
            'appointmentType': _appointmentType,
            'scheduledAt': FieldValue.serverTimestamp(),
            'reminderSent': false,
            'status': 'scheduled',
          });

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الموعد بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ الموعد: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('تحديد موعد - ${widget.patientName}'),
          backgroundColor: Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSection(
                  title: 'تاريخ الموعد',
                  child: InkWell(
                    onTap: _selectDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: const Color.fromARGB(255, 34, 96, 129),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatDate(_selectedDate),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title: 'نوع الموعد',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _appointmentType,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      items:
                          _appointmentTypes.map((String type) {
                            return DropdownMenuItem<String>(
                              value: type,
                              child: Text(type),
                            );
                          }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _appointmentType = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saving ? null : _saveAppointment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(255, 34, 96, 129),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _saving ? 'جاري الحفظ...' : 'حفظ الموعد',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final days = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    final months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _PatientNotesScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String patientName;
  final String patientPhone;

  const _PatientNotesScreen({
    required this.doctorId,
    required this.centerId,
    required this.patientName,
    required this.patientPhone,
  });

  @override
  State<_PatientNotesScreen> createState() => _PatientNotesScreenState();
}

class _PatientNotesScreenState extends State<_PatientNotesScreen> {
  final TextEditingController _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _patientKey {
    final keySource =
        (widget.patientPhone.isNotEmpty)
            ? widget.patientPhone
            : widget.patientName;
    return keySource.replaceAll('/', '_');
  }

  CollectionReference<Map<String, dynamic>> get _notesCollection =>
      FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc('general')
          .collection('doctors')
          .doc(widget.doctorId)
          .collection('appointments')
          .doc(_patientKey)
          .collection('notes');

  Future<void> _saveNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _saving = true;
    });
    try {
      await _notesCollection.add({
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'patientName': widget.patientName,
        'patientPhone': widget.patientPhone,
        'doctorId': widget.doctorId,
      });
      _noteController.clear();
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ الملاحظة')));
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ملاحظات - ${widget.patientName}'),
          backgroundColor: Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: TextField(
                    controller: _noteController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: 'اكتب الملاحظة هنا...',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveNote,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 34, 96, 129),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_saving ? 'جاري الحفظ...' : 'حفظ'),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'الملاحظات السابقة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream:
                        _notesCollection
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color.fromARGB(255, 34, 96, 129),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('حدث خطأ في تحميل الملاحظات'),
                        );
                      }
                      final notes = snapshot.data?.docs ?? [];
                      if (notes.isEmpty) {
                        return Center(
                          child: Text(
                            'لا توجد ملاحظات بعد',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: notes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final data = notes[index].data();
                          final text = data['text'] ?? '';
                          final createdAt = data['createdAt'];
                          String dateStr = '';
                          if (createdAt is Timestamp) {
                            dateStr = intl.DateFormat(
                              'yyyy/MM/dd HH:mm',
                              'ar',
                            ).format(createdAt.toDate());
                          }
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (dateStr.isNotEmpty)
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    text,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> booking;

  const _PatientDetailsScreen({required this.booking});

  @override
  Widget build(BuildContext context) {
    final patientName = booking['patientName'] ?? 'مريض غير معروف';
    final patientPhone = booking['patientPhone'] ?? 'غير محدد';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('تفاصيل المريض'),
          backgroundColor: Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _infoTile(
                  label: 'الاسم',
                  value: patientName,
                  icon: Icons.person,
                ),
                const SizedBox(height: 12),
                _phoneTile(context: context, phone: patientPhone),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: const Color.fromARGB(255, 34, 96, 129)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneTile({required BuildContext context, required String phone}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.phone, color: const Color.fromARGB(255, 34, 96, 129)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'رقم الهاتف',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (phone != 'غير محدد' && phone.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _makePhoneCall(context, phone);
                      },
                      onLongPress: () {
                        _copyPhoneNumber(context, phone);
                      },
                      child: Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.blue,
                        ),
                      ),
                    )
                  else
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makePhoneCall(BuildContext context, String phone) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phone);

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('لا يمكن الاتصال برقم $phone'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الاتصال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copyPhoneNumber(BuildContext context, String phone) {
    Clipboard.setData(ClipboardData(text: phone)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم نسخ الرقم: $phone'),
          backgroundColor: Color.fromARGB(255, 34, 96, 129),
          action: SnackBarAction(
            label: 'إلغاء',
            textColor: Colors.white,
            onPressed: () {
              // يمكن إضافة كود لإلغاء النسخ إذا لزم الأمر
            },
          ),
        ),
      );
    });
  }
}

// شاشة نتائج المختبر
class _LabResultsScreen extends StatefulWidget {
  final String patientPhone;
  final String patientName;

  const _LabResultsScreen({
    required this.patientPhone,
    required this.patientName,
  });

  @override
  State<_LabResultsScreen> createState() => _LabResultsScreenState();
}

class _LabResultsScreenState extends State<_LabResultsScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _patients = [];
  String? _errorMessage;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    print('=== LAB RESULTS SCREEN INIT ===');
    print('Patient Phone: ${widget.patientPhone}');
    print('Patient Name: ${widget.patientName}');
    // لا يتم البحث تلقائياً، فقط عند الضغط على الزر
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _searchPatients() async {
    final phone = widget.patientPhone.trim();

    print('=== LAB RESULTS SEARCH ===');
    print('Patient Phone: $phone');
    print('Patient Name: ${widget.patientName}');

    if (phone.isEmpty) {
      print('Phone number is empty');
      setState(() {
        _errorMessage = 'رقم الهاتف غير متوفر';
        _patients = [];
      });
      return;
    }

    // تنظيف رقم الهاتف (إزالة المسافات والرموز)
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    print('Clean Phone: $cleanPhone');

    // التأكد من أن الرقم يحتوي على 10 أرقام
    if (cleanPhone.length != 10) {
      print('Phone number length is not 10: ${cleanPhone.length}');
      setState(() {
        _errorMessage = 'رقم الهاتف يجب أن يكون 10 أرقام';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _patients = [];
    });

    try {
      final url =
          'https://alroomy.a.pinggy.link/projects/bootstraped/new/patients_api.php?phone=$cleanPhone';
      print('API URL: $url');

      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              print('Request timeout');
              throw Exception('انتهت مهلة الاتصال');
            },
          );

      print('Response Status Code: ${response.statusCode}');
      print('Response Body Length: ${response.body.length}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          print('Parsed Data: $data');

          if (data['success'] == true && data['data'] != null) {
            final List<dynamic> patientsData = data['data'];
            print('Patients Data Length: ${patientsData.length}');

            setState(() {
              _patients =
                  patientsData
                      .map((patient) => patient as Map<String, dynamic>)
                      .toList();
              _isLoading = false;
            });
            print('Final Patients List Length: ${_patients.length}');
          } else {
            print('API returned success: false or no data');
            print('API Message: ${data['message']}');
            setState(() {
              _errorMessage = data['message'] ?? 'لا توجد نتائج';
              _isLoading = false;
            });
          }
        } catch (jsonError) {
          print('JSON Parse Error: $jsonError');
          setState(() {
            _errorMessage = 'خطأ في تحليل البيانات: $jsonError';
            _isLoading = false;
          });
        }
      } else {
        print('HTTP Error: ${response.statusCode}');
        setState(() {
          _errorMessage = 'خطأ في الاتصال بالخادم (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Exception caught: $e');
      setState(() {
        _errorMessage = 'خطأ: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _viewResults(Map<String, dynamic> patient) async {
    final patientId = patient['patient_id']?.toString();

    if (patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خطأ: معرف المريض غير متوفر'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('Viewing results for Patient ID: $patientId');
    print('Patient Name: ${patient['patient_name']}');

    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Color.fromARGB(255, 34, 96, 129),
            ),
          ),
        );
      },
    );

    try {
      final url =
          'https://alroomy.a.pinggy.link/projects/bootstraped/new/lab_results_api.php?patient_id=$patientId';
      print('Lab Results API URL: $url');

      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('انتهت مهلة الاتصال');
            },
          );

      // إخفاء مؤشر التحميل
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      print('Lab Results Response Status: ${response.statusCode}');
      print('Lab Results Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          // تحميل وعرض PDF
          await _downloadAndOpenPDF(
            patient['patient_name'] ?? 'نتائج_المختبر',
            data,
          );
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'خطأ في تحميل النتائج'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خطأ في الاتصال بالخادم'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // إخفاء مؤشر التحميل في حالة الخطأ
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      print('Error viewing results: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الاتصال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndOpenPDF(
    String patientName,
    Map<String, dynamic> apiData,
  ) async {
    try {
      print('Downloading PDF for: $patientName');
      print('API Data: $apiData');

      // إنشاء اسم الملف
      final fileName =
          'نتائج_${patientName}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // الحصول على مجلد التطبيق
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      // التحقق من وجود بيانات PDF في الاستجابة
      final pdfData = apiData['data'];

      if (pdfData != null && pdfData['pdf_base64'] != null) {
        // إذا كان هناك PDF base64، استخدمه
        try {
          final Uint8List pdfBytes = base64Decode(pdfData['pdf_base64']);
          final file = File(filePath);
          await file.writeAsBytes(pdfBytes);

          // فتح الملف
          await OpenFilex.open(filePath);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم فتح نتائج المختبر'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          print('Error decoding PDF: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('خطأ في فتح الملف: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد نتائج مختبر متاحة'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error downloading PDF: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل النتائج: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndOpenPdf(String pdfUrl, String fileName) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final response = await http.get(Uri.parse(pdfUrl));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        // حفظ الملف في مجلد التطبيق
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);

        // فتح الملف
        await OpenFilex.open(file.path);

        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في تحميل الملف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'نتيجة المختبر - ${widget.patientName}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _searchPatients,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // زر الاستعلام
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _searchPatients,
                  icon:
                      _isLoading
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.search),
                  label: Text(
                    _isLoading ? 'جاري البحث...' : 'الاستعلام عن النتيجة',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(255, 34, 96, 129),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // عرض النتائج
                Expanded(
                  child:
                      _isLoading
                          ? const Center(
                            child: CircularProgressIndicator(
                              color: Color.fromARGB(255, 34, 96, 129),
                            ),
                          )
                          : _errorMessage != null
                          ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                          : _patients.isEmpty
                          ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.science_outlined,
                                  size: 40,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'اضغط على زر الاستعلام للبحث عن النتائج',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                          : ListView.builder(
                            itemCount: _patients.length,
                            itemBuilder: (context, index) {
                              final patient = _patients[index];
                              final patientName =
                                  patient['patient_name'] ?? 'غير محدد';
                              final patientDate =
                                  patient['patient_date'] ?? 'غير محدد';
                              final patientId =
                                  patient['patient_id']?.toString() ?? '';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  title: Text(
                                    patientName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    patientDate,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () {
                                      _viewResults(patient);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color.fromARGB(
                                        255,
                                        34,
                                        96,
                                        129,
                                      ),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: const Text(
                                      'عرض النتيجة',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
