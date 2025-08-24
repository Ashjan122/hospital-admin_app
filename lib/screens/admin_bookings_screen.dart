import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hospital_admin_app/services/sms_service.dart';
import 'package:hospital_admin_app/widgets/optimized_loading_widget.dart';

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
  String _selectedFilter = 'all'; // all, today, upcoming, past
  Set<String> _confirmingBookings = {}; // لتتبع الحجوزات التي يتم تأكيدها
  List<Map<String, dynamic>> _allBookings = [];
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  bool _isLoading = true; // متغير لتتبع حالة التحميل الأولي
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    fetchAllBookings();
  }

  Future<void> fetchAllBookings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // جلب جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get()
          .timeout(const Duration(seconds: 8));

      List<Map<String, dynamic>> allBookings = [];
      List<Future<void>> futures = [];
      
      // البحث في كل تخصص بشكل متوازي
      for (var specDoc in specializationsSnapshot.docs) {
        futures.add(_fetchBookingsFromSpecialization(specDoc, allBookings));
      }
      
      await Future.wait(futures);
      
      // ترتيب الحجوزات حسب التاريخ (الأحدث أولاً)
      allBookings.sort((a, b) {
        final dateA = DateTime.tryParse(a['date'] ?? '');
        final dateB = DateTime.tryParse(b['date'] ?? '');
        
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        
        return dateB.compareTo(dateA); // الأحدث أولاً
      });
      
      setState(() {
        _allBookings = allBookings;
        _currentPage = 0;
        _hasMoreData = allBookings.length > _pageSize;
        _isLoadingMore = false;
        _isLoading = false; // انتهاء التحميل الأولي
      });
    } catch (e) {
      print('Error loading bookings: $e');
      setState(() {
        _allBookings = [];
        _currentPage = 0;
        _hasMoreData = false;
        _isLoading = false; // انتهاء التحميل الأولي حتى في حالة الخطأ
      });
    }
  }

  Future<void> _fetchBookingsFromSpecialization(QueryDocumentSnapshot specDoc, List<Map<String, dynamic>> allBookings) async {
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
        doctorFutures.add(_fetchBookingsFromDoctor(doctorDoc, specDoc.id, specializationName, allBookings));
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
    List<Map<String, dynamic>> allBookings
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
    final filteredBookings = filterBookings();
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
      filteredBookings = filteredBookings.where((booking) {
        final doctorName = booking['doctorName']?.toString().toLowerCase() ?? '';
        final patientName = booking['patientName']?.toString().toLowerCase() ?? '';
        
        return doctorName.contains(searchLower) ||
               patientName.contains(searchLower);
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
    
    // إعادة ترتيب النتائج المصفاة حسب التاريخ (الأحدث أولاً)
    filteredBookings.sort((a, b) {
      final dateA = DateTime.tryParse(a['date'] ?? '');
      final dateB = DateTime.tryParse(b['date'] ?? '');
      
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      
      return dateB.compareTo(dateA); // الأحدث أولاً
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

  Future<void> _confirmBooking(Map<String, dynamic> booking) async {
    final appointmentId = booking['appointmentId'] as String;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحجز'),
        content: Text('هل تريد تأكيد حجز المريض ${booking['patientName']}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('تأكيد'),
            ),
          ],
        ),
    );

    if (confirmed == true) {
      // إضافة loading محلي للحجز المحدد
      setState(() {
        _confirmingBookings.add(appointmentId);
      });

      try {
        // Update booking status
        await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(booking['specializationId'])
            .collection('doctors')
            .doc(booking['doctorId'])
            .collection('appointments')
            .doc(appointmentId)
            .update({
          'isConfirmed': true,
          'confirmedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 5));

        // Send SMS notification to patient
        final patientPhone = booking['patientPhone'] ?? '';
        if (patientPhone.isNotEmpty) {
          final date = formatDate(booking['date']);
          final time = formatTime(booking['time']);
          final period = getPeriodText(booking['period']);
          
          final message = 'تم تأكيد حجزك في ${booking['specialization']} مع د. ${booking['doctorName']} في $date الساعة $time $period';
          
          await SMSService.sendSimpleSMS(patientPhone, message);
        }

        // تحديث الحجز في القائمة المحلية
                      setState(() {
          final index = _allBookings.indexWhere((b) => b['appointmentId'] == appointmentId);
          if (index != -1) {
            _allBookings[index]['isConfirmed'] = true;
            _allBookings[index]['confirmedAt'] = DateTime.now();
          }
          _confirmingBookings.remove(appointmentId);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تأكيد الحجز وإرسال رسالة للمريض'),
              backgroundColor: Colors.green,
                      ),
                    );
                  }
      } catch (e) {
        setState(() {
          _confirmingBookings.remove(appointmentId);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في تأكيد الحجز: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
                            _searchQuery.isEmpty ? Icons.calendar_today_outlined : Icons.search_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty 
                                ? 'لا توجد حجوزات في هذا المركز'
                                : 'لم يتم العثور على حجوزات تطابق البحث',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty 
                                ? 'لم يتم العثور على أي حجوزات مسجلة'
                                : 'جرب البحث بكلمات مختلفة',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
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
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
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
                      final doctorName = booking['doctorName'] ?? 'طبيب غير معروف';
                      final specialization = booking['specialization'] ?? 'تخصص غير معروف';
                      final patientName = booking['patientName'] ?? 'مريض غير معروف';
                      final date = booking['date'] ?? '';
                      final time = booking['time'] ?? '';
                      final period = booking['period'] ?? '';

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
                           child: Row(
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
                                     
                                     // Doctor name and specialization (subtitle)
                                     Row(
                                       children: [
                                         Icon(
                                           FontAwesomeIcons.userDoctor,
                                           size: 16,
                                           color: const Color(0xFF2FBDAF),
                                         ),
                                         const SizedBox(width: 8),
                                         Expanded(
                                           child: Text(
                                             '$doctorName - $specialization',
                                             style: TextStyle(
                                               fontSize: 14,
                                               color: Colors.grey[600],
                                             ),
                                           ),
                                         ),
                                       ],
                                     ),
                                     const SizedBox(height: 8),
                                     
                                     // Date and time (simple text)
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
                                             '${formatDate(date)} - ${formatTime(time)} ${getPeriodText(period)}',
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
                               
                // Status badge and confirm button
                Column(
                  children: [
                               Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                 decoration: BoxDecoration(
                        color: getStatusColor(date, isConfirmed: booking['isConfirmed'] ?? false).withOpacity(0.1),
                                   borderRadius: BorderRadius.circular(12),
                                   border: Border.all(
                          color: getStatusColor(date, isConfirmed: booking['isConfirmed'] ?? false).withOpacity(0.3),
                                   ),
                                 ),
                                 child: Text(
                        getStatusText(date, isConfirmed: booking['isConfirmed'] ?? false),
                                   style: TextStyle(
                                     fontSize: 10,
                          color: getStatusColor(date, isConfirmed: booking['isConfirmed'] ?? false),
                                     fontWeight: FontWeight.bold,
                                   ),
                                 ),
                    ),
                    if (!(booking['isConfirmed'] ?? false)) ...[
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _confirmingBookings.contains(booking['appointmentId'])
                            ? null
                            : () => _confirmBooking(booking),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 30),
                        ),
                        child: _confirmingBookings.contains(booking['appointmentId'])
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'تأكيد الحجز',
                                style: TextStyle(fontSize: 10),
                              ),
                      ),
                    ],
                  ],
                               ),
                             ],
                           ),
                         ),
                       );
                    },
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
        // إعادة تعيين الصفحة عند تغيير الفلتر
        _resetPagination();
      },
      selectedColor: const Color(0xFF2FBDAF).withOpacity(0.2),
      checkmarkColor: const Color(0xFF2FBDAF),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF2FBDAF) : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
            widget.centerName != null ? 'الحجوزات - ${widget.centerName}' : 'الحجوزات',
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
              icon: const Icon(Icons.refresh),
              onPressed: () {
                fetchAllBookings();
              },
            ),
          ],
        ),
        body: Column(
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
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: Color(0xFF2FBDAF),
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
    );
  }
}
