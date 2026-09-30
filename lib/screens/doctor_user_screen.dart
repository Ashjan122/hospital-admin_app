import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/presence_service.dart';
import '../services/sms_service.dart';
import 'doctor_bookings_screen.dart';
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
    // mark online when doctor screen opens
    _markOnline();
    _subscribeToDoctorTopic();
  }

  Future<void> _markOnline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? '';
      await PresenceService.setOnline(userId: userId, userType: 'doctor');
    } catch (_) {}
  }

  Future<void> _subscribeToDoctorTopic() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSubscribed =
          prefs.getBool('doctor_notifications_enabled') ?? true;

      if (isSubscribed) {
        final topic = 'doctor_${widget.doctorId}';
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        print('Doctor user subscribed to topic: $topic');
      }
    } catch (e) {
      print('Error subscribing doctor to topic: $e');
    }
  }

  Future<void> _unsubscribeFromDoctorTopic() async {
    try {
      final topic = 'doctor_${widget.doctorId}';
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      print('Doctor user unsubscribed from topic: $topic');
    } catch (e) {
      print('Error unsubscribing doctor from topic: $e');
    }
  }

  Future<void> _toggleNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isCurrentlyEnabled =
          prefs.getBool('doctor_notifications_enabled') ?? true;
      final newStatus = !isCurrentlyEnabled;

      await prefs.setBool('doctor_notifications_enabled', newStatus);

      // تحديث الواجهة فوراً
      if (mounted) {
        setState(() {});
      }

      if (newStatus) {
        await _subscribeToDoctorTopic();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تفعيل الإشعارات'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        await _unsubscribeFromDoctorTopic();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تعطيل الإشعارات'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Error toggling notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تغيير حالة الإشعارات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadTodayBookings() async {
    setState(() {
      _loading = true;
    });

    try {
      final specializationsSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .get();

      List<Map<String, dynamic>> allBookings = [];

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
          final specializationData = specDoc.data();
          final specializationName =
              specializationData['specName'] ?? specDoc.id;

          // جلب حجوزات الطبيب
          final appointmentsSnapshot =
              await FirebaseFirestore.instance
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

      final todayBookings =
          allBookings.where((booking) {
            final bookingDate = DateTime.tryParse(booking['date'] ?? '');
            return bookingDate != null &&
                DateTime(
                      bookingDate.year,
                      bookingDate.month,
                      bookingDate.day,
                    ) ==
                    today;
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
      final userId = prefs.getString('userId') ?? '';

      // إيقاف حالة الطبيب
      if (userId.isNotEmpty) {
        await PresenceService.setOffline(userId: userId);
      }

      // إلغاء الاشتراك من إشعارات الطبيب
      await _unsubscribeFromDoctorTopic();

      // تسجيل الخروج من Firebase Auth
      // مهم جداً حتى لا يرجع الحساب تلقائياً بعد إعادة فتح التطبيق
      await FirebaseAuth.instance.signOut();

      // مسح بيانات الجلسة المحلية
      await prefs.clear();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تسجيل الخروج: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'د. ${widget.doctorName}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            FutureBuilder<bool>(
              future: SharedPreferences.getInstance().then(
                (prefs) =>
                    prefs.getBool('doctor_notifications_enabled') ?? true,
              ),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data ?? true;
                return IconButton(
                  icon: Icon(
                    isEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    color: isEnabled ? Colors.white : Colors.orange[300],
                  ),
                  onPressed: _toggleNotifications,
                  tooltip: isEnabled ? 'تعطيل الإشعارات' : 'تفعيل الإشعارات',
                );
              },
            ),
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
          child:
              _loading
                  ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2FBDAF)),
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
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                intl.DateFormat(
                                  'EEEE، d MMMM yyyy',
                                  'ar',
                                ).format(DateTime.now()),
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          // GridView للبطاقات الأربع
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            children: [
                              // بطاقة حجوزات اليوم
                              _buildDashboardCard(
                                context,
                                'حجوزات اليوم',
                                Icons.today,
                                const Color(0xFF2FBDAF),
                                '',
                                () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder:
                                          (context) => DoctorBookingsScreen(
                                            doctorId: widget.doctorId,
                                            centerId: widget.centerId,
                                            centerName: widget.centerName,
                                            doctorName: widget.doctorName,
                                          ),
                                    ),
                                  );
                                },
                              ),

                              // بطاقة المواعيد المجدولة
                              _buildDashboardCard(
                                context,
                                'المواعيد المجدولة',
                                Icons.schedule,
                                Colors.orange,
                                '',
                                () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder:
                                          (context) =>
                                              _ScheduledAppointmentsScreen(
                                                doctorId: widget.doctorId,
                                                centerId: widget.centerId,
                                                doctorName: widget.doctorName,
                                              ),
                                    ),
                                  );
                                },
                              ),

                              // بطاقة المفضلون
                              _buildDashboardCard(
                                context,
                                'المفضلون',
                                Icons.favorite,
                                Colors.red,
                                '',
                                () {
                                  // يمكن إضافة صفحة المفضلون هنا
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('قريباً - صفحة المفضلون'),
                                    ),
                                  );
                                },
                              ),

                              // بطاقة الإحصائيات
                              _buildDashboardCard(
                                context,
                                'الإحصائيات',
                                Icons.analytics,
                                Colors.purple,
                                '',
                                () {
                                  // يمكن إضافة صفحة الإحصائيات هنا
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('قريباً - صفحة الإحصائيات'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String count,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              if (count.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    count,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
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
                    stream:
                        _notesCollection
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
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
                _infoTile(
                  label: 'الاسم',
                  value: patientName,
                  icon: Icons.person,
                ),
                const SizedBox(height: 12),
                _infoTile(
                  label: 'رقم الهاتف',
                  value: patientPhone,
                  icon: Icons.phone,
                ),
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

    print('📱 WhatsApp - رقم الهاتف الأصلي: $phone');
    print('💬 WhatsApp - نص الرسالة: ${_messageController.text}');

    setState(() {
      _sendingWhatsApp = true;
    });

    try {
      // استخدام الرقم كما هو محفوظ في Firestore بدون أي تعديل
      final formattedPhone = phone;
      print('📞 WhatsApp - رقم الهاتف كما هو محفوظ: $formattedPhone');

      var headers = {'Content-Type': 'application/x-www-form-urlencoded'};

      print('🌐 WhatsApp - إرسال طلب إلى API...');
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

      print('📡 WhatsApp - محتوى الطلب: ${request.bodyFields}');
      http.StreamedResponse response = await request.send();

      print('📊 WhatsApp - رمز الاستجابة: ${response.statusCode}');
      final responseBody = await response.stream.bytesToString();
      print('📄 WhatsApp - محتوى الاستجابة: $responseBody');

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
              content: Text(
                'خطأ في إرسال الرسالة: ${response.statusCode} - ${responseBody}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ WhatsApp - خطأ: $e');
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
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Title
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
                // Message text field
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

                // Send buttons
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
                          backgroundColor: const Color(0xFF2FBDAF),
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

  @override
  void dispose() {
    super.dispose();
  }

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
                primary: Color(0xFF2FBDAF),
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
        print('تم اختيار التاريخ: $_selectedDate');
      }
    } catch (e) {
      print('خطأ في اختيار التاريخ: $e');
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
      // إنشاء تاريخ الموعد (بدون وقت محدد)
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
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // اختيار التاريخ
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
                            color: const Color(0xFF2FBDAF),
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

                // نوع الموعد
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

                // زر الحفظ
                ElevatedButton(
                  onPressed: _saving ? null : _saveAppointment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2FBDAF),
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

class _ScheduledAppointmentsScreen extends StatefulWidget {
  final String doctorId;
  final String centerId;
  final String doctorName;

  const _ScheduledAppointmentsScreen({
    required this.doctorId,
    required this.centerId,
    required this.doctorName,
  });

  @override
  State<_ScheduledAppointmentsScreen> createState() =>
      _ScheduledAppointmentsScreenState();
}

class _ScheduledAppointmentsScreenState
    extends State<_ScheduledAppointmentsScreen> {
  int _refreshKey = 0;

  Future<List<Map<String, dynamic>>> _fetchScheduledAppointments() async {
    try {
      // البحث في جميع التخصصات للعثور على الطبيب
      final specializationsSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .get();

      List<Map<String, dynamic>> allScheduledAppointments = [];

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
          // جلب المواعيد المجدولة من هذا التخصص
          final scheduledAppointmentsSnapshot =
              await FirebaseFirestore.instance
                  .collection('medicalFacilities')
                  .doc(widget.centerId)
                  .collection('specializations')
                  .doc(specDoc.id)
                  .collection('doctors')
                  .doc(widget.doctorId)
                  .collection('scheduledAppointments')
                  .where('status', isEqualTo: 'scheduled')
                  .get();

          for (var appointmentDoc in scheduledAppointmentsSnapshot.docs) {
            final appointmentData = appointmentDoc.data();
            appointmentData['appointmentId'] = appointmentDoc.id;
            appointmentData['specializationId'] = specDoc.id;
            allScheduledAppointments.add(appointmentData);
          }
          break; // وجدنا الطبيب، لا نحتاج للبحث في تخصصات أخرى
        }
      }

      return allScheduledAppointments;
    } catch (e) {
      print('Error fetching scheduled appointments: $e');
      return [];
    }
  }

  Future<void> _cancelAppointment(
    String appointmentId,
    String patientName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('تأكيد الإلغاء'),
            content: Text('هل أنت متأكد من إلغاء موعد "$patientName"؟'),
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
                child: const Text('إلغاء الموعد'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        // البحث عن التخصص الذي يحتوي على الموعد
        final specializationsSnapshot =
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .collection('specializations')
                .get();

        bool appointmentFound = false;
        for (var specDoc in specializationsSnapshot.docs) {
          final appointmentDoc =
              await FirebaseFirestore.instance
                  .collection('medicalFacilities')
                  .doc(widget.centerId)
                  .collection('specializations')
                  .doc(specDoc.id)
                  .collection('doctors')
                  .doc(widget.doctorId)
                  .collection('scheduledAppointments')
                  .doc(appointmentId)
                  .get();

          if (appointmentDoc.exists) {
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(widget.doctorId)
                .collection('scheduledAppointments')
                .doc(appointmentId)
                .update({
                  'status': 'cancelled',
                  'cancelledAt': FieldValue.serverTimestamp(),
                });
            appointmentFound = true;
            break;
          }
        }

        if (!appointmentFound) {
          throw Exception('لم يتم العثور على الموعد');
        }

        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إلغاء موعد "$patientName"'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _refreshKey++;
          });
        }
      } catch (e) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في إلغاء الموعد: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatAppointmentDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return intl.DateFormat('EEEE، d MMMM yyyy', 'ar').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'scheduled':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'scheduled':
        return 'مجدول';
      case 'cancelled':
        return 'ملغي';
      case 'completed':
        return 'مكتمل';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('المواعيد المجدولة - د. ${widget.doctorName}'),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _refreshKey++;
                });
              },
            ),
          ],
        ),
        body: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(_refreshKey),
            future: _fetchScheduledAppointments(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2FBDAF)),
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
                        'حدث خطأ في تحميل المواعيد',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }

              final appointments = snapshot.data ?? [];

              if (appointments.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.schedule, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد مواعيد مجدولة',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ستظهر هنا المواعيد التي تم جدولتها',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: appointments.length,
                itemBuilder: (context, index) {
                  final appointment = appointments[index];
                  final patientName =
                      appointment['patientName'] ?? 'مريض غير معروف';
                  final patientPhone = appointment['patientPhone'] ?? '';
                  final appointmentDate = appointment['appointmentDate'] ?? '';
                  final appointmentType =
                      appointment['appointmentType'] ?? 'موعد';
                  final notes = appointment['notes'] ?? '';
                  final status = appointment['status'] ?? 'scheduled';
                  final reminderSent = appointment['reminderSent'] ?? false;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patientName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      patientPhone,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _getStatusText(status),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatAppointmentDate(appointmentDate),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.medical_services,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                appointmentType,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (reminderSent) ...[
                                const SizedBox(width: 16),
                                Icon(
                                  Icons.notifications_active,
                                  size: 16,
                                  color: Colors.green[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'تم التذكير',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'ملاحظات: $notes',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                          if (status == 'scheduled') ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton(
                                  onPressed:
                                      () => _cancelAppointment(
                                        appointment['appointmentId'],
                                        patientName,
                                      ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('إلغاء الموعد'),
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
      ),
    );
  }
}

class _ScheduledAppointmentsList extends StatelessWidget {
  final String doctorId;
  final String centerId;
  final int refreshKey;
  final VoidCallback onAppointmentChanged;

  const _ScheduledAppointmentsList({
    required this.doctorId,
    required this.centerId,
    required this.refreshKey,
    required this.onAppointmentChanged,
  });

  Future<List<Map<String, dynamic>>> _fetchScheduledAppointments() async {
    try {
      print(
        'Fetching scheduled appointments for doctor: $doctorId in center: $centerId',
      );

      // البحث في التخصصات أولاً
      final specializationsSnapshot =
          await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(centerId)
              .collection('specializations')
              .get();

      print('Found ${specializationsSnapshot.docs.length} specializations');

      List<Map<String, dynamic>> allScheduledAppointments = [];
      List<Map<String, dynamic>> allAppointments = []; // للتصحيح

      for (var specDoc in specializationsSnapshot.docs) {
        print('Checking specialization: ${specDoc.id}');

        final doctorDoc =
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(doctorId)
                .get();

        if (doctorDoc.exists) {
          print('Found doctor in specialization: ${specDoc.id}');

          // البحث في جميع المواعيد أولاً للتصحيح
          final allAppointmentsSnapshot =
              await FirebaseFirestore.instance
                  .collection('medicalFacilities')
                  .doc(centerId)
                  .collection('specializations')
                  .doc(specDoc.id)
                  .collection('doctors')
                  .doc(doctorId)
                  .collection('scheduledAppointments')
                  .get();

          print(
            'Found ${allAppointmentsSnapshot.docs.length} total appointments in specialization ${specDoc.id}',
          );

          for (var appointmentDoc in allAppointmentsSnapshot.docs) {
            final appointmentData = appointmentDoc.data();
            appointmentData['appointmentId'] = appointmentDoc.id;
            appointmentData['specializationId'] = specDoc.id;
            allAppointments.add(appointmentData);

            final status = appointmentData['status']?.toString() ?? '';
            print(
              'Appointment: ${appointmentData['patientName']} - Status: $status - Date: ${appointmentData['appointmentDate']}',
            );
          }

          // البحث في المواعيد المجدولة فقط
          final scheduledAppointmentsSnapshot =
              await FirebaseFirestore.instance
                  .collection('medicalFacilities')
                  .doc(centerId)
                  .collection('specializations')
                  .doc(specDoc.id)
                  .collection('doctors')
                  .doc(doctorId)
                  .collection('scheduledAppointments')
                  .where('status', isEqualTo: 'scheduled')
                  .get();

          print(
            'Found ${scheduledAppointmentsSnapshot.docs.length} scheduled appointments in specialization ${specDoc.id}',
          );

          for (var appointmentDoc in scheduledAppointmentsSnapshot.docs) {
            final appointmentData = appointmentDoc.data();
            appointmentData['appointmentId'] = appointmentDoc.id;
            appointmentData['specializationId'] = specDoc.id;
            allScheduledAppointments.add(appointmentData);
            print(
              'Added scheduled appointment: ${appointmentData['patientName']} on ${appointmentData['appointmentDate']}',
            );
          }
          break; // وجدنا الطبيب، لا نحتاج للبحث في تخصصات أخرى
        }
      }

      print('=== DEBUG INFO ===');
      print('Total appointments found: ${allAppointments.length}');
      print(
        'Total scheduled appointments found: ${allScheduledAppointments.length}',
      );

      // ترتيب المواعيد حسب التاريخ
      allScheduledAppointments.sort((a, b) {
        final dateA = DateTime.tryParse(a['appointmentDate'] ?? '');
        final dateB = DateTime.tryParse(b['appointmentDate'] ?? '');

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return dateA.compareTo(dateB); // ترتيب تصاعدي (الأقدم أولاً)
      });

      print(
        'Total scheduled appointments found: ${allScheduledAppointments.length}',
      );
      return allScheduledAppointments;
    } catch (e) {
      print('Error fetching scheduled appointments: $e');
      return [];
    }
  }

  Future<void> _cancelAppointment(
    BuildContext context,
    String appointmentId,
    String patientName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('تأكيد الإلغاء'),
            content: Text('هل أنت متأكد من إلغاء موعد "$patientName"؟'),
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
                child: const Text('إلغاء الموعد'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        // البحث عن الموعد في التخصصات
        final specializationsSnapshot =
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(centerId)
                .collection('specializations')
                .get();

        bool appointmentFound = false;
        for (var specDoc in specializationsSnapshot.docs) {
          final appointmentDoc =
              await FirebaseFirestore.instance
                  .collection('medicalFacilities')
                  .doc(centerId)
                  .collection('specializations')
                  .doc(specDoc.id)
                  .collection('doctors')
                  .doc(doctorId)
                  .collection('scheduledAppointments')
                  .doc(appointmentId)
                  .get();

          if (appointmentDoc.exists) {
            await FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(doctorId)
                .collection('scheduledAppointments')
                .doc(appointmentId)
                .update({
                  'status': 'cancelled',
                  'cancelledAt': FieldValue.serverTimestamp(),
                });
            appointmentFound = true;
            break;
          }
        }

        if (!appointmentFound) {
          throw Exception('لم يتم العثور على الموعد');
        }

        onAppointmentChanged();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في إلغاء الموعد: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatAppointmentDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return intl.DateFormat('EEEE، d MMMM yyyy', 'ar').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(refreshKey),
      future: _fetchScheduledAppointments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: Color(0xFF2FBDAF)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'حدث خطأ في تحميل المواعيد',
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final appointments = snapshot.data ?? [];

        if (appointments.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Text(
                'لا توجد مواعيد مجدولة',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final appointment = appointments[index];
              final patientName =
                  appointment['patientName'] ?? 'مريض غير معروف';
              final patientPhone = appointment['patientPhone'] ?? '';
              final appointmentDate = appointment['appointmentDate'] ?? '';
              final appointmentType = appointment['appointmentType'] ?? 'موعد';
              final reminderSent = appointment['reminderSent'] ?? false;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patientName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  patientPhone,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (reminderSent)
                            Icon(
                              Icons.notifications_active,
                              size: 16,
                              color: Colors.green[600],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _formatAppointmentDate(appointmentDate),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.medical_services,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            appointmentType,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed:
                                () => _cancelAppointment(
                                  context,
                                  appointment['appointmentId'],
                                  patientName,
                                ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: const Text(
                              'إلغاء',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
