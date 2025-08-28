import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sms_service.dart';
import 'login_screen.dart';


class DoctorBookingsScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String? centerName;
  final String doctorName;

  const DoctorBookingsScreen({
    super.key,
    required this.doctorId,
    required this.centerId,
    this.centerName,
    required this.doctorName,
  });

  @override
  State<DoctorBookingsScreen> createState() => _DoctorBookingsScreenState();
}

class _DoctorBookingsScreenState extends State<DoctorBookingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'today'; // تغيير الافتراضي إلى اليوم
  DateTime? _selectedDate; // فلترة حسب تاريخ معين
  Set<String> _confirmingBookings = {}; // لتتبع الحجوزات التي يتم تأكيدها
  Set<String> _cancelingBookings = {}; // لتتبع الحجوزات التي يتم إلغاؤها

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
                  primary: const Color(0xFF2FBDAF),
                  secondary: const Color(0xFF2FBDAF),
                ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2FBDAF),
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
      // البحث عن الطبيب في جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      List<Map<String, dynamic>> allBookings = [];

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(widget.doctorId)
            .get();

        if (doctorDoc.exists) {
          final specializationData = specDoc.data();
          final specializationName = specializationData['specName'] ?? specDoc.id;

          // جلب حجوزات الطبيب
          final appointmentsSnapshot = await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .doc(widget.doctorId)
              .collection('appointments')
              .get();

          for (var appointmentDoc in appointmentsSnapshot.docs) {
            final appointmentData = appointmentDoc.data();
            appointmentData['specialization'] = specializationName;
            appointmentData['appointmentId'] = appointmentDoc.id;
            appointmentData['specializationId'] = specDoc.id;
            allBookings.add(appointmentData);
          }
          break; // وجدنا الطبيب، لا نحتاج للبحث في تخصصات أخرى
        }
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

  List<Map<String, dynamic>> filterBookings(List<Map<String, dynamic>> bookings) {
    List<Map<String, dynamic>> filteredBookings = bookings;
    
    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final searchLower = _searchQuery.toLowerCase().trim();
      filteredBookings = filteredBookings.where((booking) {
        final patientName = booking['patientName']?.toString().toLowerCase() ?? '';
        final patientPhone = booking['patientPhone']?.toString().toLowerCase() ?? '';
        
        return patientName.contains(searchLower) ||
               patientPhone.contains(searchLower);
      }).toList();
    }
    
    // Filter by date
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (_selectedFilter) {
      case 'today':
        filteredBookings = filteredBookings.where((booking) {
          final bookingDate = DateTime.tryParse(booking['date'] ?? '');
          return bookingDate != null && 
                 DateTime(bookingDate.year, bookingDate.month, bookingDate.day) == today;
        }).toList();
        break;
      case 'upcoming':
        filteredBookings = filteredBookings.where((booking) {
          final bookingDate = DateTime.tryParse(booking['date'] ?? '');
          return bookingDate != null && bookingDate.isAfter(today);
        }).toList();
        break;
      case 'past':
        filteredBookings = filteredBookings.where((booking) {
          final bookingDate = DateTime.tryParse(booking['date'] ?? '');
          return bookingDate != null && bookingDate.isBefore(today);
        }).toList();
        break;
    }

    // فلترة حسب التاريخ المحدد (إن وُجد)
    if (_selectedDate != null) {
      final target = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      filteredBookings = filteredBookings.where((booking) {
        final bookingDate = DateTime.tryParse(booking['date'] ?? '');
        if (bookingDate == null) return false;
        final day = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
        return day == target;
      }).toList();
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
      final bookingDay = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
      
      if (bookingDay.isBefore(today)) {
        return Colors.grey; // Past
      } else if (bookingDay == today) {
        return Colors.green; // Today
      } else {
        return const Color(0xFF2FBDAF); // Upcoming
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
      final bookingDay = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
      
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

  Future<void> _sendConfirmationSMS(Map<String, dynamic> booking) async {
    try {
      final patientPhone = booking['patientPhone'] ?? '';
      
      if (patientPhone.isEmpty) {
        print('No phone number available for SMS');
        return;
      }
      
      final date = formatDate(booking['date']);
      final time = formatTime(booking['time']);
      final period = getPeriodText(booking['period'] ?? '');
      
      final message = 'تم تأكيد حجزك في ${booking['specialization']} مع د. ${widget.doctorName} في $date الساعة $time $period';
      
      print('Sending confirmation SMS to: $patientPhone');
      print('Message: $message');
      
      final result = await SMSService.sendSimpleSMS(patientPhone, message);
      
      if (result['success'] == true) {
        print('SMS sent successfully');
      } else {
        print('Failed to send SMS: ${result['message']}');
      }
    } catch (e) {
      print('Error sending confirmation SMS: $e');
    }
  }

  Future<void> _confirmBooking(Map<String, dynamic> booking) async {
    final appointmentId = booking['appointmentId'];
    
    // إضافة loading محلي للحجز المحدد
    setState(() {
      _confirmingBookings.add(appointmentId);
    });

    try {
      final specializationId = booking['specializationId'];
      
      await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specializationId)
          .collection('doctors')
          .doc(widget.doctorId)
          .collection('appointments')
          .doc(appointmentId)
          .update({
        'isConfirmed': true,
        'confirmedAt': FieldValue.serverTimestamp(),
      });

      // إرسال رسالة تأكيد للمريض
      await _sendConfirmationSMS(booking);

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد الحجز وإرسال رسالة للمريض'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {}); // تحديث الواجهة
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تأكيد الحجز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // إزالة loading المحلي
      setState(() {
        _confirmingBookings.remove(appointmentId);
      });
    }
  }



  Future<void> _sendCancellationSMS(Map<String, dynamic> booking) async {
    try {
      final patientPhone = booking['patientPhone'] ?? '';
      
      if (patientPhone.isEmpty) {
        print('No phone number available for cancellation SMS');
        return;
      }
      
      final date = formatDate(booking['date']);
      final time = formatTime(booking['time']);
      final period = getPeriodText(booking['period'] ?? '');
      
      final message = 'تم إلغاء حجزك في ${booking['specialization']} مع د. ${widget.doctorName} في $date الساعة $time $period';
      
      print('Sending cancellation SMS to: $patientPhone');
      print('Message: $message');
      
      final result = await SMSService.sendSimpleSMS(patientPhone, message);
      
      if (result['success'] == true) {
        print('Cancellation SMS sent successfully');
      } else {
        print('Failed to send cancellation SMS: ${result['message']}');
      }
    } catch (e) {
      print('Error sending cancellation SMS: $e');
    }
  }

  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    final appointmentId = booking['appointmentId'];
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إلغاء الحجز'),
        content: Text('هل أنت متأكد من إلغاء حجز المريض "${booking['patientName']}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('إلغاء الحجز'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // إضافة loading محلي للحجز المحدد
      setState(() {
        _cancelingBookings.add(appointmentId);
      });

      try {
        final specializationId = booking['specializationId'];
        
        // إرسال رسالة إلغاء للمريض قبل حذف الحجز
        await _sendCancellationSMS(booking);
        
        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specializationId)
            .collection('doctors')
            .doc(widget.doctorId)
            .collection('appointments')
            .doc(appointmentId)
            .delete();

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إلغاء الحجز وإرسال رسالة للمريض'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {}); // تحديث الواجهة
        }
      } catch (e) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في إلغاء الحجز: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        // إزالة loading المحلي
        setState(() {
          _cancelingBookings.remove(appointmentId);
        });
      }
    }
  }



  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // مسح جميع البيانات المحفوظة
      
      if (mounted && context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
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
            'حجوزات د. ${widget.doctorName}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'تسجيل الخروج',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
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
                    const SizedBox(height: 12),
                    // Date picker row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              _selectedDate == null
                                  ? 'اختر تاريخاً لعرض الحجوزات'
                                  : _formatSelectedDate(_selectedDate!),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                              foregroundColor: const Color(0xFF2FBDAF),
                              side: const BorderSide(color: Color(0xFF2FBDAF)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_selectedDate != null)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedDate = null;
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF2FBDAF),
                            ),
                            child: const Text('مسح التاريخ'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Filter buttons
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('الكل', 'all'),
                          const SizedBox(width: 8),
                          _buildFilterChip('اليوم', 'today'),
                          const SizedBox(width: 8),
                          _buildFilterChip('القادمة', 'upcoming'),
                          const SizedBox(width: 8),
                          _buildFilterChip('السابقة', 'past'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Bookings list
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: fetchDoctorBookings(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF2FBDAF),
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
                              _searchQuery.isEmpty ? Icons.calendar_today : Icons.search_off,
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
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredBookings.length,
                      itemBuilder: (context, index) {
                        final booking = filteredBookings[index];
                        final patientName = booking['patientName'] ?? 'مريض غير معروف';
                        final specialization = booking['specialization'] ?? 'تخصص غير معروف';
                        final date = booking['date'] ?? '';
                        final time = booking['time'] ?? '';
                        final period = booking['period'] ?? '';
                        final isConfirmed = booking['isConfirmed'] ?? false;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 1,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    // Content
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Patient name (main title)
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: 18,
                                                color: const Color(0xFF2FBDAF),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  patientName,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          
                                          // Specialization
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.medical_services,
                                                size: 16,
                                                color: const Color(0xFF2FBDAF),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  specialization,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          
                                          // Date and time
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today,
                                                size: 16,
                                                color: const Color(0xFF2FBDAF),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '${formatDate(date)} - $time ${getPeriodText(period)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[500],
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
                                        if (booking['createdAt'] != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                                                                         child: Text(
                                               formatBookingTime(booking['createdAt']),
                                               style: TextStyle(
                                                 fontSize: 9,
                                                 color: Colors.grey[600],
                                                 fontWeight: FontWeight.w500,
                                               ),
                                             ),
                                          ),
                                          const SizedBox(height: 4),
                                        ],
                                        // Status badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: getStatusColor(date, isConfirmed: isConfirmed).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: getStatusColor(date, isConfirmed: isConfirmed).withOpacity(0.3),
                                            ),
                                          ),
                                          child: Text(
                                            getStatusText(date, isConfirmed: isConfirmed),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: getStatusColor(date, isConfirmed: isConfirmed),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                
                                // Action buttons (only for unconfirmed bookings)
                                if (!isConfirmed) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _confirmingBookings.contains(booking['appointmentId'])
                                              ? null
                                              : () => _confirmBooking(booking),
                                          icon: _confirmingBookings.contains(booking['appointmentId'])
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(Icons.check, size: 16),
                                          label: Text(
                                            _confirmingBookings.contains(booking['appointmentId'])
                                                ? 'جاري التأكيد...'
                                                : 'تأكيد الحجز',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _cancelingBookings.contains(booking['appointmentId'])
                                              ? null
                                              : () => _cancelBooking(booking),
                                          icon: _cancelingBookings.contains(booking['appointmentId'])
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(Icons.cancel, size: 16),
                                          label: Text(
                                            _cancelingBookings.contains(booking['appointmentId'])
                                                ? 'جاري الإلغاء...'
                                                : 'إلغاء الحجز',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
      selectedColor: const Color(0xFF2FBDAF).withOpacity(0.2),
      checkmarkColor: const Color(0xFF2FBDAF),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF2FBDAF) : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
