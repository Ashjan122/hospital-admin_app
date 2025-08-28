import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';

class DoctorUserScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String? centerName;
  final String doctorName;

  const DoctorUserScreen({
    super.key,
    required this.doctorId,
    required this.centerId,
    this.centerName,
    required this.doctorName,
  });

  @override
  State<DoctorUserScreen> createState() => _DoctorUserScreenState();
}

class _DoctorUserScreenState extends State<DoctorUserScreen> {
  List<Map<String, dynamic>> _todayBookings = [];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadTodayBookings();
  }

  Future<void> _loadTodayBookings() async {
    setState(() {
      _loading = true;
    });

    try {
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

      // فلترة حجوزات اليوم فقط
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final todayBookings = allBookings.where((booking) {
        final bookingDate = DateTime.tryParse(booking['date'] ?? '');
        return bookingDate != null && 
               DateTime(bookingDate.year, bookingDate.month, bookingDate.day) == today;
      }).toList();

      // ترتيب الحجوزات حسب وقت الإنشاء (آخر حجز يظهر أولاً)
      todayBookings.sort((a, b) {
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
        
        return dateB.compareTo(dateA); // ترتيب تنازلي
      });

      setState(() {
        _todayBookings = todayBookings;
        _loading = false;
      });
    } catch (e) {
      print('Error loading today bookings: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _refreshBookings() async {
    setState(() {
      _refreshing = true;
    });
    await _loadTodayBookings();
    setState(() {
      _refreshing = false;
    });
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

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      if (mounted && context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
          (route) => false,
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
            'حجوزات اليوم - د. ${widget.doctorName}',
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
              onPressed: _refreshing ? null : _refreshBookings,
              tooltip: 'تحديث',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'تسجيل الخروج',
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2FBDAF),
                  ),
                )
              : _todayBookings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'لا توجد حجوزات اليوم',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ستظهر هنا الحجوزات الجديدة',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                                     : RefreshIndicator(
                       onRefresh: _refreshBookings,
                       color: const Color(0xFF2FBDAF),
                       child: SingleChildScrollView(
                         padding: const EdgeInsets.all(16),
                         child: Column(
                           children: [
                             // تاريخ اليوم أعلى الصفحة
                             Padding(
                               padding: const EdgeInsets.only(bottom: 12),
                               child: Align(
                                 alignment: Alignment.centerRight,
                                 child: Text(
                                   intl.DateFormat('EEEE، d MMMM yyyy', 'ar').format(DateTime.now()),
                                   style: TextStyle(
                                     fontSize: 16,
                                     color: Colors.grey[700],
                                     fontWeight: FontWeight.w600,
                                   ),
                                 ),
                               ),
                             ),
                                                           // رأس الجدول
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2FBDAF),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    topRight: Radius.circular(12),
                                  ),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 1,
                                        child: Text(
                                          'رقم',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          'اسم المريض',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          '',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                             
                                                           // صفوف الجدول
                              ...List.generate(_todayBookings.length, (index) {
                                final booking = _todayBookings[index];
                                final patientName = booking['patientName'] ?? 'مريض غير معروف';
                                final time = booking['time'] ?? '';
                                final period = booking['period'] ?? '';
                                
                                return Container(
                                  decoration: BoxDecoration(
                                    color: index.isEven ? Colors.grey[50] : Colors.white,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: Text(
                                            '${_todayBookings.length - index}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          flex: 7,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                patientName,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${formatTime(time)} • ${getPeriodText(period)}',
                                            style: TextStyle(
                                                  fontSize: 12,
                                              color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                            ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          flex: 2,
                                          child: ElevatedButton(
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) => Directionality(
                                                    textDirection: TextDirection.rtl,
                                                    child: Scaffold(
                                                      appBar: AppBar(
                                                        title: Text(patientName),
                                                        backgroundColor: const Color(0xFF2FBDAF),
                                                        foregroundColor: Colors.white,
                                                        elevation: 0,
                                                      ),
                                                      body: SafeArea(
                                                        child: Padding(
                                                          padding: const EdgeInsets.all(16),
                                                          child: GridView.count(
                                                            crossAxisCount: 2,
                                                            crossAxisSpacing: 16,
                                                            mainAxisSpacing: 16,
                                                            children: [
                                                              _buildGridItem(
                                                                icon: Icons.note,
                                                                title: 'ملاحظات',
                                                                color: Colors.blue,
                                                                onTap: () {
                                                                  final patientPhone = booking['patientPhone'] ?? '';
                                                                  Navigator.of(context).push(
                                                                    MaterialPageRoute(
                                                                      builder: (context) => _PatientNotesScreen(
                                                                        doctorId: widget.doctorId,
                                                                        centerId: widget.centerId,
                                                                        patientName: patientName,
                                                                        patientPhone: patientPhone,
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                              _buildGridItem(
                                                                icon: Icons.person,
                                                                title: 'تفاصيل المريض',
                                                                color: Colors.green,
                                                                onTap: () {
                                                                  Navigator.of(context).push(
                                                                    MaterialPageRoute(
                                                                      builder: (context) => _PatientDetailsScreen(
                                                                        booking: booking,
                                                                      ),
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                              _buildGridItem(
                                                                icon: Icons.message,
                                                                title: 'رسالة للمريض',
                                                                color: Colors.orange,
                                                                onTap: () {
                                                                  // TODO: Navigate to message page
                                                                },
                                                              ),
                                                              _buildGridItem(
                                                                icon: Icons.schedule,
                                                                title: 'تحديد موعد',
                                                                color: Colors.purple,
                                                                onTap: () {
                                                                  // TODO: Navigate to schedule page
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
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF2FBDAF),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                            ),
                                            child: const Text(
                                              'عرض',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              
                           ],
                         ),
                       ),
                     ),
        ),
      ),
    );
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
      
      return intl.DateFormat('HH:mm', 'ar').format(date);
    } catch (e) {
      return '';
    }
  }

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
              Icon(
                icon,
                size: 48,
                color: color,
              ),
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
    final keySource = (widget.patientPhone.isNotEmpty)
        ? widget.patientPhone
        : widget.patientName;
    return keySource.replaceAll('/', '_');
  }

  CollectionReference<Map<String, dynamic>> get _notesCollection => FirebaseFirestore.instance
      .collection('medicalFacilities')
      .doc(widget.centerId)
      .collection('specializations')
      .doc('general') // You may need to adjust this based on your structure
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الملاحظة')),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
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
          title: Text('ملاحظات - ${widget.patientName}'),
          backgroundColor: const Color(0xFF2FBDAF),
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
                        borderSide: const BorderSide(color: Colors.black, width: 2),
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
                      backgroundColor: const Color(0xFF2FBDAF),
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
                    stream: _notesCollection.orderBy('createdAt', descending: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF2FBDAF)),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('حدث خطأ في تحميل الملاحظات'));
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
                            dateStr = intl.DateFormat('yyyy/MM/dd HH:mm', 'ar').format(createdAt.toDate());
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
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final date = DateTime.parse(timeStr);
      return intl.DateFormat('yyyy/MM/dd • HH:mm', 'ar').format(date);
    } catch (_) {
      return timeStr;
    }
  }

  String _periodText(String? period) {
    switch (period) {
      case 'morning':
        return 'صباحاً';
      case 'evening':
        return 'مساءً';
      default:
        return period ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = booking['patientName'] ?? 'مريض غير معروف';
    final patientPhone = booking['patientPhone'] ?? 'غير محدد';
    // Removed other fields per request (only name and phone)

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('تفاصيل المريض'),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _infoTile(label: 'الاسم', value: patientName, icon: Icons.person),
                const SizedBox(height: 12),
                _infoTile(label: 'رقم الهاتف', value: patientPhone, icon: Icons.phone),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile({required String label, required String value, required IconData icon}) {
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
            Icon(icon, color: const Color(0xFF2FBDAF)),
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
}
