import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

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
  String _selectedFilter = 'all'; // all, today, upcoming, past

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

      // ترتيب الحجوزات حسب التاريخ (الأحدث أولاً)
      allBookings.sort((a, b) {
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
