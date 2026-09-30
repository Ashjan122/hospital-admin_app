import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/sms_service.dart';
import '../services/whatsapp_service.dart';

class AdminBookingsScreen extends StatefulWidget {
  final String centerId;
  final String? centerName;

  const AdminBookingsScreen({
    super.key,
    required this.centerId,
    this.centerName,
  });

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, morning, evening
  DateTime? _selectedDate; // فلترة حسب تاريخ معين
  // Set<String> _confirmingBookings = {}; // لتتبع الحجوزات التي يتم تأكيدها - معطل مؤقتاً
  Set<String> _cancelingBookings = {};
  Set<String> _confirmingBookings = {};
  List<Map<String, dynamic>> _allBookings = [];
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  bool _isLoading = true; // متغير لتتبع حالة التحميل الأولي
  int _currentPage = 0;
  static const int _pageSize = 10;
  bool _canConfirmBooking = false;
  bool _canCancelBooking = false;
  bool _loadingPermissions = true;

  Future<void> _loadPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');

      if (userId == null || userId.isEmpty) {
        return;
      }

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();

      final data = userDoc.data();

      if (data == null) {
        return;
      }

      final permissions = data['permissions'];

      if (permissions is Map) {
        setState(() {
          _canConfirmBooking = permissions['confirmBooking'] == true;
          _canCancelBooking = permissions['cancelBooking'] == true;
        });
      }
    } catch (e) {
      debugPrint('Error loading permissions: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingPermissions = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    fetchAllBookings();
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
              primary: const Color.fromARGB(255, 34, 96, 129),
              secondary: const Color.fromARGB(255, 34, 96, 129),
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
  }

  String _formatSelectedDate(DateTime date) {
    try {
      final dayName = intl.DateFormat('EEEE', 'ar').format(date);
      final dateText = intl.DateFormat('yyyy/MM/dd', 'ar').format(date);

      return '$dayName $dateText';
    } catch (_) {
      return '${date.year}/${date.month}/${date.day}';
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

  Future<void> fetchAllBookings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final appointmentsSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('appointments')
              .get();

      List<Map<String, dynamic>> allBookings = [];

      for (var doc in appointmentsSnapshot.docs) {
        final data = doc.data();
        data['appointmentId'] = doc.id;
        allBookings.add(data);
      }

      // ترتيب الحجوزات حسب createdAt (الأحدث أولاً)
      allBookings.sort((a, b) {
        final createdAtA = a['createdAt'];
        final createdAtB = b['createdAt'];

        if (createdAtA != null && createdAtB != null) {
          DateTime aTime, bTime;

          if (createdAtA is Timestamp) {
            aTime = createdAtA.toDate();
          } else {
            aTime = DateTime.tryParse(createdAtA.toString()) ?? DateTime(2000);
          }

          if (createdAtB is Timestamp) {
            bTime = createdAtB.toDate();
          } else {
            bTime = DateTime.tryParse(createdAtB.toString()) ?? DateTime(2000);
          }

          return bTime.compareTo(aTime);
        }

        return 0;
      });

      setState(() {
        _allBookings = allBookings;
        _currentPage = 0;
        _hasMoreData = allBookings.length > _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching bookings: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchBookingsFromSpecialization(
    QueryDocumentSnapshot specDoc,
    List<Map<String, dynamic>> allBookings,
  ) async {
    try {
      final specializationData = specDoc.data() as Map<String, dynamic>?;
      final specializationName = specializationData?['specName'] ?? specDoc.id;

      final doctorsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specDoc.id)
          .collection('doctors')
          .get()
          .timeout(const Duration(seconds: 5));

      List<Future<void>> doctorFutures = [];

      // البحث في كل طبيب بشكل متوازي
      for (var doctorDoc in doctorsSnapshot.docs) {
        doctorFutures.add(
          _fetchBookingsFromDoctor(
            doctorDoc,
            specDoc.id,
            specializationName,
            allBookings,
          ),
        );
      }

      await Future.wait(doctorFutures);
    } catch (e) {
      // Error loading bookings from specialization
    }
  }

  Future<void> _fetchBookingsFromDoctor(
    QueryDocumentSnapshot doctorDoc,
    String specializationId,
    String specializationName,
    List<Map<String, dynamic>> allBookings,
  ) async {
    try {
      final doctorData = doctorDoc.data() as Map<String, dynamic>?;
      final doctorName = doctorData?['docName'] ?? 'طبيب غير معروف';

      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specializationId)
          .collection('doctors')
          .doc(doctorDoc.id)
          .collection('appointments')
          .get()
          .timeout(const Duration(seconds: 5));

      for (var appointmentDoc in appointmentsSnapshot.docs) {
        final appointmentData = appointmentDoc.data();

        // إضافة معلومات إضافية لكل حجز
        appointmentData['doctorName'] = doctorName;
        appointmentData['specialization'] = specializationName;
        appointmentData['doctorId'] = doctorDoc.id;
        appointmentData['specializationId'] = specializationId;
        appointmentData['appointmentId'] = appointmentDoc.id;
        allBookings.add(appointmentData);
      }
    } catch (e) {
      // Error loading bookings from doctor
    }
  }

  // دالة جلب الحجوزات على دفعات (10 حجوزات في كل مرة)
  List<Map<String, dynamic>> getPaginatedBookings() {
    final filteredBookings =
        filterBookings().reversed.toList(); // عكس ترتيب الحجوزات
    final startIndex = 0;
    final endIndex = (_currentPage + 1) * _pageSize;

    // إذا وصلنا لنهاية القائمة، نرجع جميع الحجوزات
    if (endIndex >= filteredBookings.length) {
      return filteredBookings;
    }

    // نرجع الحجوزات من البداية حتى النقطة الحالية
    return filteredBookings.sublist(startIndex, endIndex);
  }

  // دالة إعادة تعيين الصفحة عند تغيير الفلتر أو البحث
  void _resetPagination() {
    setState(() {
      _currentPage = 0;
      final filteredBookings = filterBookings();
      _hasMoreData = filteredBookings.length > _pageSize;
      _isLoadingMore = false;
    });
  }

  // دالة تحميل المزيد من الحجوزات (10 حجوزات إضافية)
  Future<void> loadMoreBookings() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() {
      _isLoadingMore = true;
    });

    // محاكاة تأخير للعرض (800 مللي ثانية)
    await Future.delayed(const Duration(milliseconds: 800));

    setState(() {
      _currentPage++; // زيادة رقم الصفحة
      final filteredBookings = filterBookings();
      // التحقق من وجود المزيد من الحجوزات
      final nextPageEnd = (_currentPage + 1) * _pageSize;
      _hasMoreData = nextPageEnd < filteredBookings.length;
      _isLoadingMore = false;
    });

    final filteredBookings = filterBookings();
    // Loaded page $_currentPage, displayed bookings: ${getPaginatedBookings().length} of ${filteredBookings.length}
  }

  List<Map<String, dynamic>> filterBookings() {
    List<Map<String, dynamic>> filteredBookings = List.from(_allBookings);

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final searchLower = _searchQuery.toLowerCase().trim();
      filteredBookings =
          filteredBookings.where((booking) {
            final doctorName =
                booking['doctorName']?.toString().toLowerCase() ?? '';
            final patientName =
                booking['patientName']?.toString().toLowerCase() ?? '';

            return doctorName.contains(searchLower) ||
                patientName.contains(searchLower);
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
      print('DEBUG: Selected date: $_selectedDate, Target date: $targetDate');
    } else {
      final now = DateTime.now();
      targetDate = DateTime(now.year, now.month, now.day);
      print('DEBUG: Using today: $targetDate');
    }

    // فلترة حسب التاريخ المستهدف أولاً
    filteredBookings =
        filteredBookings.where((booking) {
          final bookingDateStr = booking['date'] ?? '';
          final bookingDate = DateTime.tryParse(bookingDateStr);

          if (bookingDate == null) {
            print('DEBUG: Invalid date format: $bookingDateStr');
            return false;
          }

          final bookingDay = DateTime(
            bookingDate.year,
            bookingDate.month,
            bookingDate.day,
          );
          final targetDay = DateTime(
            targetDate.year,
            targetDate.month,
            targetDate.day,
          );

          print(
            'DEBUG: Booking date: $bookingDay, Target date: $targetDay, Match: ${bookingDay == targetDay}',
          );

          return bookingDay == targetDay;
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
      // 'all' لا يحتاج فلترة إضافية
    }

    // إعادة ترتيب النتائج المصفاة حسب وقت إنشاء الحجز (أول حجز في الأسفل)
    filteredBookings.sort((a, b) {
      final createdAtA = a['createdAt'];
      final createdAtB = b['createdAt'];

      // إذا كان وقت إنشاء الحجز متوفر، نرتب حسبه
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

          return timeA.compareTo(timeB); // أول حجز (أقدم وقت) أولاً
        } catch (e) {
          // في حالة خطأ في تحليل التاريخ، نرتب حسب وقت الحجز الفعلي
        }
      }

      // إذا لم يكن وقت إنشاء الحجز متوفر، نرتب حسب وقت الحجز الفعلي
      final timeA = a['time'] ?? '';
      final timeB = b['time'] ?? '';

      return timeA.compareTo(timeB);
    });

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
    return timeStr;
  }

  int _getBookingsCount() {
    return filterBookings().length;
  }

  int _getTotalBookingsForDate() {
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

    // فلترة الحجوزات حسب التاريخ المستهدف
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

    return targetDateBookings.length;
  }

  String _getEmptyStateMessage() {
    if (_searchQuery.isNotEmpty) {
      return 'لم يتم العثور على حجوزات تطابق البحث';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_selectedDate != null) {
      final selectedDate = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );
      if (selectedDate == today) {
        return 'لا توجد حجوزات اليوم بعد';
      } else {
        return 'لا توجد حجوزات في هذا اليوم';
      }
    } else {
      return 'لا توجد حجوزات اليوم بعد';
    }
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

    // فلترة الحجوزات حسب التاريخ المستهدف
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

    // ترتيب الحجوزات حسب وقت إنشاء الحجز (أول حجز أولاً)
    targetDateBookings.sort((a, b) {
      final createdAtA = a['createdAt'];
      final createdAtB = b['createdAt'];

      // إذا كان وقت إنشاء الحجز متوفر، نرتب حسبه
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

          return timeA.compareTo(timeB); // أول حجز (أقدم وقت) أولاً
        } catch (e) {
          // في حالة خطأ في تحليل التاريخ، نرتب حسب وقت الحجز الفعلي
        }
      }

      // إذا لم يكن وقت إنشاء الحجز متوفر، نرتب حسب وقت الحجز الفعلي
      final timeA = a['time'] ?? '';
      final timeB = b['time'] ?? '';

      return timeA.compareTo(timeB);
    });

    // البحث عن رقم الحجز للمريض الحالي (ترتيب طبيعي)
    for (int i = 0; i < targetDateBookings.length; i++) {
      if (targetDateBookings[i]['appointmentId'] == booking['appointmentId']) {
        return i + 1; // رقم طبيعي (1, 2, 3...)
      }
    }

    return 0; // إذا لم يتم العثور على الحجز
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
        // إعادة تعيين الصفحة عند تغيير الفلتر
        _resetPagination();
      },
      selectedColor: const Color.fromARGB(255, 34, 96, 129).withOpacity(0.2),
      checkmarkColor: const Color.fromARGB(255, 34, 96, 129),
      labelStyle: TextStyle(
        color:
            isSelected
                ? const Color.fromARGB(255, 34, 96, 129)
                : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
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
        return const Color.fromARGB(255, 34, 96, 129); // Upcoming
      }
    } catch (e) {
      return Colors.grey;
    }
  }

  Widget _bookingInfoItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 34, 96, 129).withOpacity(0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 14,
              color: const Color.fromARGB(255, 34, 96, 129),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // دالة حالة الحجز - معطلة مؤقتاً
  // String getStatusText(String dateStr, {bool isConfirmed = false}) {
  //   if (!isConfirmed) {
  //     return 'في انتظار التأكيد';
  //   }
  //
  //   try {
  //     final bookingDate = DateTime.parse(dateStr);
  //     final now = DateTime.now();
  //     final today = DateTime(now.year, now.month, now.day);
  //     final bookingDay = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
  //
  //     if (bookingDay.isBefore(today)) {
  //       return 'سابقة';
  //     } else if (bookingDay == today) {
  //       return 'اليوم';
  //     } else {
  //       return 'قادمة';
  //     }
  //   } catch (e) {
  //     return 'غير محدد';
  //   }
  // }

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

  void _updateBookingInLocalList(
    String appointmentId,
    Map<String, dynamic> updates,
  ) {
    setState(() {
      final index = _allBookings.indexWhere(
        (b) => b['appointmentId'] == appointmentId,
      );
      if (index != -1) {
        _allBookings[index].addAll(updates);
      }
    });
  }

  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    if (!_canCancelBooking) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ليس لديك صلاحية إلغاء الحجوزات'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final appointmentId = booking['appointmentId'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('تأكيد إلغاء الحجز'),
            content: Text(
              'هل تريد إلغاء حجز المريض ${booking['patientName']}؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('رجوع'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('إلغاء الحجز'),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    setState(() {
      _cancelingBookings.add(appointmentId);
    });

    // عرض ديالوق تحميل أثناء تنفيذ الإلغاء وإرسال الرسالة
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const Center(
              child: CircularProgressIndicator(
                color: Color.fromARGB(255, 34, 96, 129),
              ),
            ),
      );
    }

    bool smsSent = false;
    String? smsFailureReason;
    bool whatsappSent = false;
    String? whatsappFailureReason;

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? '';
      final userName = prefs.getString('userName') ?? 'مستخدم غير معروف';
      // تحديث الحجز فقط بدون حذفه
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('appointments')
          .doc(appointmentId)
          .update({
            'status': 'canceled',
            'canceledAt': FieldValue.serverTimestamp(),
            'canceledByName': userName,
            'canceledById': userId,
          })
          .timeout(const Duration(seconds: 8));

      // تحديث الشاشة مباشرة
      _updateBookingInLocalList(appointmentId, {
        'status': 'canceled',
        'canceledAt': Timestamp.now(),
        'canceledByName': userName,
        'canceledById': userId,
      });

      // إرسال رسالة SMS للمريض بإلغاء الحجز
      final patientPhone = booking['patientPhone']?.toString() ?? '';
      if (patientPhone.isNotEmpty) {
        try {
          final patientName = booking['patientName'] ?? '';
          final doctorName = booking['doctorName'] ?? '';
          final date = booking['date'] ?? '';
          final period = getPeriodText(booking['period'] ?? '');
          final centerName = widget.centerName ?? '';

          final message =
              'عذرا $patientName، تم الغاء حجزك مع دكتور $doctorName بتاريخ $date $period لظروف طارئة .\n\n$centerName';

          final smsResult = await SMSService.sendSimpleSMS(
            patientPhone,
            message,
          );
          smsSent = smsResult['success'] == true;
          if (!smsSent) {
            smsFailureReason =
                (smsResult['message'] ?? smsResult['response'] ?? '')
                    .toString();
            print('فشل إرسال رسالة إلغاء الحجز: $smsResult');
          }
        } catch (e) {
          // فشل إرسال SMS لا يجب أن يوقف عملية الإلغاء
          smsFailureReason = e.toString();
          print('خطأ أثناء إرسال رسالة إلغاء الحجز: $e');
        }
      }
      // إرسال رسالة WhatsApp للمريض بإلغاء الحجز
      if (patientPhone.isNotEmpty) {
        try {
          final patientName = booking['patientName']?.toString() ?? '';
          final doctorName = booking['doctorName']?.toString() ?? '';
          final date = booking['date']?.toString() ?? '';
          final period = getPeriodText(booking['period'] ?? '');

          // جلب رقم هاتف المركز من medicalFacilities/{centerId}
          String centerPhone = '';

          final centerDoc =
              await FirebaseFirestore.instance
                  .collection('medicalFacilities')
                  .doc(widget.centerId)
                  .get();

          if (centerDoc.exists) {
            centerPhone = centerDoc.data()?['phone']?.toString() ?? '';
          }

          await WhatsAppService.sendCancelBookingTemplate(
            phoneNumber: patientPhone,
            patientName: patientName,
            doctorName: doctorName,
            date: date,
            period: period,
            centerPhone: centerPhone,
          );

          whatsappSent = true;
        } catch (e) {
          whatsappFailureReason = e.toString();
          debugPrint('خطأ أثناء إرسال رسالة إلغاء WhatsApp: $e');
        }
      }
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // إغلاق ديالوق التحميل
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              smsSent
                  ? 'تم إلغاء الحجز وإرسال رسالة للمريض'
                  : 'تم إلغاء الحجز، لكن تعذر إرسال رسالة للمريض'
                      '${smsFailureReason != null && smsFailureReason.isNotEmpty ? ' ($smsFailureReason)' : ''}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // إغلاق ديالوق التحميل
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إلغاء الحجز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _cancelingBookings.remove(appointmentId);
        });
      }
    }
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  String _buildConfirmationMessage(
    Map<String, dynamic> booking,
    String centerPhone,
  ) {
    final bookingDate =
        DateTime.tryParse(booking['date']?.toString() ?? '') ?? DateTime.now();

    final dayName = intl.DateFormat('EEEE', 'ar').format(bookingDate);

    final formattedDate = intl.DateFormat('yyyy-MM-dd').format(bookingDate);

    final periodText =
        booking['period']?.toString().toLowerCase() == 'morning'
            ? 'صباحاً'
            : 'مساءً';

    final centerName = widget.centerName ?? 'غير محدد';
    final patientName = booking['patientName']?.toString() ?? 'غير محدد';
    final patientPhone = booking['patientPhone']?.toString() ?? 'غير محدد';
    final doctorName = booking['doctorName']?.toString() ?? 'غير محدد';
    final specialization =
        booking['specializationName']?.toString() ?? 'غير محدد';

    return 'تطبيق جودة الطبي\n\n'
        'تم حجز موعد بنجاح\n\n'
        'اسم المركز: $centerName\n'
        'اسم المريض: $patientName\n'
        'رقم الهاتف: $patientPhone\n'
        'الطبيب: $doctorName ($specialization)\n'
        'وقت الحجز: $dayName - $formattedDate - $periodText\n\n'
        ' للإستفسار يمكنك التواصل مع المركز على الرقم: $centerPhone\n\n'
        'شكراً لاختياركم تطبيق جودة الطبي';
  }

  Future<void> _confirmBooking(Map<String, dynamic> booking) async {
    if (!_canConfirmBooking) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ليس لديك صلاحية تأكيد الحجوزات'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final appointmentId = booking['appointmentId']?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('تأكيد الحجز'),
            content: const Text('هل تريد تأكيد هذا الحجز؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تأكيد'),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    setState(() {
      _confirmingBookings.add(appointmentId);
    });

    try {
      final specializationId =
          booking['centralSpecialtyId']?.toString() ??
          booking['specializationId']?.toString();

      final doctorId = booking['doctorId']?.toString();

      if (specializationId == null || specializationId.isEmpty) {
        throw Exception('معرف التخصص غير موجود');
      }

      if (doctorId == null || doctorId.isEmpty) {
        throw Exception('معرف الطبيب غير موجود');
      }

      final firestore = FirebaseFirestore.instance;
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? '';
      final userName = prefs.getString('userName') ?? 'مستخدم غير معروف';

      final facilityBookingRef = firestore
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('appointments')
          .doc(appointmentId);

      final doctorBookingRef = firestore
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specializationId)
          .collection('doctors')
          .doc(doctorId)
          .collection('appointments')
          .doc(appointmentId);

      final batch = firestore.batch();

      final updateData = {
        'isConfirmed': true,
        'status': 'confirmed',
        'confirmedAt': FieldValue.serverTimestamp(),
        'confirmedByName': userName,
        'confirmedById': userId,
      };

      // تحديث حجز المركز
      batch.update(facilityBookingRef, updateData);

      // تحديث نسخة حجز الطبيب
      batch.update(doctorBookingRef, updateData);

      await batch.commit();
      // جلب رقم هاتف المركز
      String centerPhone = '';

      try {
        final centerDoc =
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .get();

        if (centerDoc.exists) {
          centerPhone = centerDoc.data()?['phone']?.toString() ?? '';
        }
      } catch (e) {
        debugPrint('فشل جلب رقم هاتف المركز: $e');
      }
      // إرسال رسالة SMS للمريض بعد تأكيد الحجز
      try {
        final message = _buildConfirmationMessage(booking, centerPhone);

        await SMSService.sendSimpleSMS(
          booking['patientPhone']?.toString() ?? '',
          message,
        );
      } catch (e) {
        debugPrint('فشل إرسال رسالة تأكيد الحجز: $e');
      }
      // إرسال رسالة WhatsApp للمريض بعد تأكيد الحجز
      try {
        final bookingDate =
            DateTime.tryParse(booking['date']?.toString() ?? '') ??
            DateTime.now();

        final dayName = intl.DateFormat('EEEE', 'ar').format(bookingDate);

        final formattedDate = intl.DateFormat('yyyy-MM-dd').format(bookingDate);

        final periodText =
            booking['period']?.toString().toLowerCase() == 'morning'
                ? 'صباحاً'
                : 'مساءً';

        await WhatsAppService.sendBookingTemplate(
          phoneNumber: booking['patientPhone']?.toString() ?? '',
          facilityName: widget.centerName ?? 'غير محدد',
          patientName: booking['patientName']?.toString() ?? 'غير محدد',
          doctorName: booking['doctorName']?.toString() ?? 'غير محدد',
          specializationName:
              booking['specializationName']?.toString() ?? 'غير محدد',
          dayName: dayName,
          date: formattedDate,
          period: periodText,
          patientPhone: booking['patientPhone']?.toString() ?? '',
          centerPhone: centerPhone,
        );
      } catch (e) {
        debugPrint('فشل إرسال رسالة WhatsApp: $e');
      }

      // تحديث القائمة مباشرة بدون إعادة تحميل
      if (mounted) {
        setState(() {
          final index = _allBookings.indexWhere(
            (b) => b['appointmentId']?.toString() == appointmentId,
          );

          if (index != -1) {
            _allBookings[index] = {
              ..._allBookings[index],
              'isConfirmed': true,
              'status': 'confirmed',
              'confirmedByName': userName,
              'confirmedById': userId,
            };
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد الحجز'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تأكيد الحجز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _confirmingBookings.remove(appointmentId);
        });
      }
    }
  }

  void _showBookingDetailsDialog(Map<String, dynamic> booking) {
    final isCanceled = booking['status'] == 'canceled';
    final isConfirmed =
        booking['isConfirmed'] == true || booking['status'] == 'confirmed';

    final confirmedByName = booking['confirmedByName']?.toString().trim() ?? '';
    final canceledByName = booking['canceledByName']?.toString().trim() ?? '';

    String formatActionTime(dynamic value) {
      if (value == null) return '';

      try {
        DateTime date;

        if (value is Timestamp) {
          date = value.toDate();
        } else if (value is String) {
          date = DateTime.parse(value);
        } else {
          return '';
        }

        return intl.DateFormat('yyyy/MM/dd - HH:mm', 'en').format(date);
      } catch (_) {
        return '';
      }
    }

    final confirmedAt = formatActionTime(booking['confirmedAt']);
    final canceledAt = formatActionTime(booking['canceledAt']);

    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text(
              'تفاصيل الحجز',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isConfirmed) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'تم تأكيد الحجز',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  if (confirmedByName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('تم التأكيد بواسطة: $confirmedByName'),
                  ],
                  if (confirmedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('وقت التأكيد: $confirmedAt'),
                  ],
                ],

                if (isCanceled) ...[
                  Row(
                    children: [
                      const Icon(Icons.cancel, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'تم إلغاء الحجز',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  if (canceledByName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('تم الإلغاء بواسطة: $canceledByName'),
                  ],
                  if (canceledAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('وقت الإلغاء: $canceledAt'),
                  ],
                ],

                if (!isConfirmed && !isCanceled)
                  const Text(
                    'الحجز بانتظار التأكيد.',
                    style: TextStyle(color: Colors.orange),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPatientDetails(Map<String, dynamic> booking) async {
    final patientId = booking['patientId']?.toString();

    if (patientId == null || patientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديد حساب المريض'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('patients')
              .doc(patientId)
              .get();

      if (!doc.exists) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('بيانات المريض غير موجودة'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final patient = {...doc.data()!, '_docId': doc.id};

      if (!mounted) return;

      _showPatientDetailsDialog(patient);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحميل بيانات المريض: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showPatientDetailsDialog(Map<String, dynamic> patient) {
    bool isActive = patient['isActive'] != false;

    String formatTimestamp(dynamic value) {
      if (value is Timestamp) {
        final date = value.toDate();

        final day = date.day.toString().padLeft(2, '0');
        final month = date.month.toString().padLeft(2, '0');
        final year = date.year.toString();

        final hour = date.hour.toString().padLeft(2, '0');
        final minute = date.minute.toString().padLeft(2, '0');

        return '$day/$month/$year  $hour:$minute';
      }

      return 'غير متوفر';
    }

    String displayName() {
      final name =
          patient['name'] ??
          patient['fullName'] ??
          patient['displayName'] ??
          patient['patientName'];

      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }

      return 'بدون اسم';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // المقبض العلوي
                        Center(
                          child: Container(
                            width: 45,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // اسم المريض
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // حالة الحساب
                        InkWell(
                          onTap: () async {
                            final patientId = patient['_docId']?.toString();

                            if (patientId == null || patientId.isEmpty) {
                              return;
                            }

                            final newStatus = !isActive;

                            try {
                              await FirebaseFirestore.instance
                                  .collection('patients')
                                  .doc(patientId)
                                  .update({'isActive': newStatus});

                              patient['isActive'] = newStatus;
                              isActive = newStatus;

                              setState(() {});

                              if (!mounted) return;

                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    newStatus
                                        ? 'تم تفعيل حساب المريض'
                                        : 'تم تعطيل حساب المريض',
                                  ),
                                  backgroundColor:
                                      newStatus ? Colors.green : Colors.red,
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;

                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text('تعذر تحديث حالة الحساب: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isActive
                                      ? Colors.green.withOpacity(0.08)
                                      : Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    isActive
                                        ? Colors.green.withOpacity(0.25)
                                        : Colors.red.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isActive
                                      ? Icons.check_circle_outline
                                      : Icons.block_outlined,
                                  color: isActive ? Colors.green : Colors.red,
                                ),

                                const SizedBox(width: 8),

                                const Text(
                                  'حالة الحساب',
                                  style: TextStyle(fontSize: 12),
                                ),

                                const Spacer(),

                                Text(
                                  isActive ? 'مفعل' : 'معطل',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.green : Colors.red,
                                  ),
                                ),

                                const SizedBox(width: 6),

                                Icon(
                                  Icons.chevron_left,
                                  color: isActive ? Colors.green : Colors.red,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        const Text(
                          'بيانات المريض',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              _PatientInfoRow(
                                icon: Icons.person_outline,
                                label: 'الاسم',
                                value: displayName(),
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.phone_outlined,
                                label: 'رقم الهاتف',
                                value:
                                    patient['phone']?.toString() ?? 'غير متوفر',
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.email_outlined,
                                label: 'البريد الإلكتروني',
                                value:
                                    patient['email']?.toString() ?? 'غير متوفر',
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.calendar_today_outlined,
                                label: 'تاريخ التسجيل',
                                value: formatTimestamp(patient['createdAt']),
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.login_outlined,
                                label: 'آخر تسجيل دخول',
                                value: formatTimestamp(patient['lastLoginAt']),
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.access_time,
                                label: 'آخر ظهور',
                                value: formatTimestamp(patient['lastSeenAt']),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBookingsList() {
    final filteredBookings = filterBookings();
    // DEBUG: Total bookings: ${filteredBookings.length}, page: $_currentPage, hasMoreData: $_hasMoreData

    if (filteredBookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isEmpty
                  ? Icons.calendar_today_outlined
                  : Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _getEmptyStateMessage(),
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final paginatedBookings = getPaginatedBookings();

    // DEBUG: Total bookings: ${filteredBookings.length}, displayed: ${paginatedBookings.length}, page: $_currentPage, hasMoreData: $_hasMoreData

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: paginatedBookings.length + (_hasMoreData ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == paginatedBookings.length) {
          // Loading more indicator
          if (_isLoadingMore) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              child: const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text(
                      'جاري تحميل المزيد من الحجوزات...',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          } else if (_hasMoreData) {
            // Load more automatically when reaching the end
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadMoreBookings();
            });
            return const SizedBox.shrink();
          }
          return const SizedBox.shrink();
        }

        final booking = paginatedBookings[index];
        final doctorName =
            booking['doctorName']?.toString().trim().isNotEmpty == true
                ? booking['doctorName'].toString().trim()
                : 'غير محدد';

        final specialization =
            booking['specializationName']?.toString().trim().isNotEmpty == true
                ? booking['specializationName'].toString().trim()
                : 'غير محدد';

        final patientName =
            booking['patientName']?.toString().trim().isNotEmpty == true
                ? booking['patientName'].toString().trim()
                : 'غير محدد';

        final accountOwnerName =
            booking['accountOwnerName']?.toString().trim().isNotEmpty == true
                ? booking['accountOwnerName'].toString().trim()
                : booking['createdByName']?.toString().trim().isNotEmpty == true
                ? booking['createdByName'].toString().trim()
                : 'غير محدد';

        final date = booking['date']?.toString() ?? '';
        final time = booking['time']?.toString() ?? '';
        final period = booking['period']?.toString() ?? '';

        final bookingNumber =
            booking['bookingNumber']?.toString().trim().isNotEmpty == true
                ? booking['bookingNumber'].toString()
                : 'غير محدد';

        final isCanceled = booking['status'] == 'canceled';
        final isPending = booking['status'] == 'pending';
        return Opacity(
          opacity: isCanceled ? 0.55 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showBookingDetailsDialog(booking),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      isCanceled
                          ? Colors.red.withOpacity(0.35)
                          : const Color.fromARGB(
                            255,
                            34,
                            96,
                            129,
                          ).withOpacity(0.35),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // اسم المريض + رقم الحجز
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showPatientDetails(booking),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.settings_outlined,
                                  size: 17,
                                  color: Color.fromARGB(255, 34, 96, 129),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    patientName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(
                            255,
                            5,
                            50,
                            75,
                          ).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          'كود الحجز: $bookingNumber',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 4, 35, 53),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  // صاحب الحساب
                  Text(
                    'تم الحجز بواسطة: $accountOwnerName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.black),
                  ),

                  const SizedBox(height: 8),

                  // الطبيب + التخصص
                  Row(
                    children: [
                      const Icon(
                        FontAwesomeIcons.userDoctor,
                        size: 13,
                        color: Color.fromARGB(255, 34, 96, 129),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$doctorName - $specialization',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      // التاريخ
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 13,
                        color: Color.fromARGB(255, 34, 96, 129),
                      ),
                      const SizedBox(width: 6),

                      Text(
                        formatDate(date),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black,
                        ),
                      ),

                      const SizedBox(width: 8),

                      // الفترة
                      if (period.toLowerCase() == 'morning')
                        const Icon(
                          Icons.wb_sunny_outlined,
                          size: 15,
                          color: Colors.orange,
                        )
                      else if (period.toLowerCase() == 'evening')
                        const Icon(
                          Icons.nightlight_round,
                          size: 15,
                          color: Color.fromARGB(255, 34, 96, 129),
                        ),

                      const SizedBox(width: 4),

                      Text(
                        getPeriodText(period),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      // المسافة بين الفترة والحالة
                      const Spacer(),

                      // الحالة
                      if (isCanceled)
                        _statusBadge('ملغي', Colors.red)
                      else if (isPending)
                        _statusBadge('بانتظار التأكيد', Colors.orange)
                      else
                        _statusBadge('مؤكد', Colors.green),
                    ],
                  ),

                  // الأزرار
                  if (isPending || !isCanceled) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (isPending)
                          Expanded(
                            child: SizedBox(
                              height: 30,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _confirmingBookings.contains(
                                          booking['appointmentId'],
                                        )
                                        ? null
                                        : () => _confirmBooking(booking),
                                icon:
                                    _confirmingBookings.contains(
                                          booking['appointmentId'],
                                        )
                                        ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.green,
                                          ),
                                        )
                                        : const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.green,
                                        ),
                                label: const Text(
                                  'تأكيد',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.green.withOpacity(0.4),
                                  ),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (isPending) const SizedBox(width: 6),

                        Expanded(
                          child: SizedBox(
                            height: 30,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _cancelingBookings.contains(
                                        booking['appointmentId'],
                                      )
                                      ? null
                                      : () => _cancelBooking(booking),
                              icon:
                                  _cancelingBookings.contains(
                                        booking['appointmentId'],
                                      )
                                      ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.red,
                                        ),
                                      )
                                      : const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.red,
                                      ),
                              label: const Text(
                                'إلغاء',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.red.withOpacity(0.35),
                                ),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            children: [
              Text(
                widget.centerName != null ? 'الحجوزات ' : 'الحجوزات',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '${widget.centerName}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color.fromARGB(255, 34, 96, 129),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: _pickDate,
              tooltip: 'اختر تاريخاً لعرض الحجوزات',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                fetchAllBookings();
              },
            ),
          ],
        ),
        body: Container(
          color: const Color(0xFFF7F9FA),
          child: Column(
            children: [
              // Search and filter section
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.transparent,
                child: Column(
                  children: [
                    // Search bar
                    TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                        // إعادة تعيين الصفحة عند البحث
                        _resetPagination();
                      },
                      decoration: InputDecoration(
                        hintText: 'البحث باسم الطبيب أو المريض...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                        Text(
                          _formatSelectedDate(_selectedDate ?? DateTime.now()),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
                child:
                    _isLoading
                        ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: Color.fromARGB(255, 34, 96, 129),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'جاري تحميل الحجوزات...',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                        : _allBookings.isEmpty
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'لا توجد حجوزات في هذا المركز',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'لم يتم العثور على أي حجوزات مسجلة',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                        : _buildBookingsList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _PatientInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey[600]),

        const SizedBox(width: 6),

        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),

        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.grey[800],
            ),
          ),
        ),
      ],
    );
  }
}
