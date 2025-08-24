import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;

class AdminReportsScreen extends StatefulWidget {
  final String centerId;
  final String centerName;

  const AdminReportsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
  });

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _statistics = {};
  String _selectedPeriod = 'today'; // today, week, month, all
  String _loadingMessage = 'جاري تحميل الإحصائيات...';
  
  // متغيرات لتتبع حالة تحميل كل إحصائية
  Map<String, bool> _loadingStates = {
    'specializations': true,
    'doctors': true,
    'insuranceCompanies': true,
    'users': true,
    'patients': true,
    'bookings': true,
  };

  @override
  void initState() {
    super.initState();
    // تهيئة القيم الافتراضية
    _statistics = {
      'specializations': 0,
      'doctors': 0,
      'insuranceCompanies': 0,
      'todayBookings': 0,
      'weekBookings': 0,
      'monthBookings': 0,
      'patients': 0,
      'users': 0,
      'confirmedBookings': 0,
      'totalBookings': 0,
    };
    // تعيين _isLoading إلى false ليعرض الكروت فوراً
    _isLoading = false;
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    if (_isLoading) return; // منع التحميل المتكرر
    
    setState(() {
      // إعادة تعيين جميع حالات التحميل
      _loadingStates.forEach((key, value) {
        _loadingStates[key] = true;
      });
    });

    try {
      // تحميل جميع البيانات بالتوازي - كل كرت يتم تحميله بشكل مستقل
      await Future.wait([
        _loadSpecializationsCount(),
        _loadInsuranceCompaniesCount(),
        _loadUsersCount(),
        _loadDoctorsAndBookings(),
        _loadPatientsCount(),
      ]);
    } catch (e) {
      print('Error loading statistics: $e');
    }
  }

  // تحميل عدد التخصصات
  Future<void> _loadSpecializationsCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();
      
      if (mounted) {
        setState(() {
          _statistics['specializations'] = snapshot.docs.length;
          _loadingStates['specializations'] = false;
        });
      }
    } catch (e) {
      print('Error loading specializations: $e');
      if (mounted) {
        setState(() {
          _loadingStates['specializations'] = false;
        });
      }
    }
  }

  // تحميل عدد شركات التأمين
  Future<void> _loadInsuranceCompaniesCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('insuranceCompanies')
          .get();
      
      if (mounted) {
        setState(() {
          _statistics['insuranceCompanies'] = snapshot.docs.length;
          _loadingStates['insuranceCompanies'] = false;
        });
      }
    } catch (e) {
      print('Error loading insurance companies: $e');
      if (mounted) {
        setState(() {
          _loadingStates['insuranceCompanies'] = false;
        });
      }
    }
  }

  // تحميل عدد المستخدمين
  Future<void> _loadUsersCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('centerId', isEqualTo: widget.centerId)
          .get();
      
      if (mounted) {
        setState(() {
          _statistics['users'] = snapshot.docs.length;
          _loadingStates['users'] = false;
        });
      }
    } catch (e) {
      print('Error loading users: $e');
      if (mounted) {
        setState(() {
          _loadingStates['users'] = false;
        });
      }
    }
  }

  // تحميل الأطباء والحجوزات
  Future<void> _loadDoctorsAndBookings() async {
    try {
      // جلب التخصصات أولاً
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      int totalDoctors = 0;
      int todayBookings = 0;
      int weekBookings = 0;
      int monthBookings = 0;
      int confirmedBookings = 0;
      int totalBookings = 0;

      // تحديد الفترات الزمنية
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekAgo = today.subtract(const Duration(days: 7));
      final monthAgo = DateTime(now.year, now.month - 1, now.day);

      // جلب الأطباء أولاً (سريع)
      List<Future<QuerySnapshot>> doctorFutures = [];
      for (var specDoc in specializationsSnapshot.docs) {
        doctorFutures.add(
          FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .get()
        );
      }

      final doctorSnapshots = await Future.wait(doctorFutures);
      
      // حساب عدد الأطباء
      for (var doctorsSnapshot in doctorSnapshots) {
        totalDoctors += doctorsSnapshot.docs.length;
      }

      // تحديث عدد الأطباء فوراً
      if (mounted) {
        setState(() {
          _statistics['doctors'] = totalDoctors;
          _loadingStates['doctors'] = false;
        });
      }

      // جلب الحجوزات بالتوازي (بطيء)
      List<Future<QuerySnapshot>> appointmentFutures = [];
      for (int i = 0; i < specializationsSnapshot.docs.length; i++) {
        final specDoc = specializationsSnapshot.docs[i];
        final doctorsSnapshot = doctorSnapshots[i];

        for (var doctorDoc in doctorsSnapshot.docs) {
          appointmentFutures.add(
            FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(doctorDoc.id)
                .collection('appointments')
                .where('date', isGreaterThanOrEqualTo: monthAgo.toIso8601String())
                .get()
          );
        }
      }

      final appointmentSnapshots = await Future.wait(appointmentFutures);

      // معالجة الحجوزات
      for (var appointmentsSnapshot in appointmentSnapshots) {
        for (var appointmentDoc in appointmentsSnapshot.docs) {
          final appointmentData = appointmentDoc.data() as Map<String, dynamic>?;
          final date = appointmentData?['date'] ?? '';
          final status = appointmentData?['status'] ?? 'pending';

          totalBookings++;
          if (status == 'confirmed') {
            confirmedBookings++;
          }

          if (date.isNotEmpty) {
            try {
              final appointmentDate = DateTime.parse(date);
              
              if (appointmentDate.year == today.year &&
                  appointmentDate.month == today.month &&
                  appointmentDate.day == today.day) {
                todayBookings++;
              }
              
              if (appointmentDate.isAfter(weekAgo) && appointmentDate.isBefore(today.add(const Duration(days: 1)))) {
                weekBookings++;
              }
              
              if (appointmentDate.isAfter(monthAgo) && appointmentDate.isBefore(today.add(const Duration(days: 1)))) {
                monthBookings++;
              }
            } catch (e) {
              // تجاهل التواريخ غير الصحيحة
            }
          }
        }
      }

      // تحديث إحصائيات الحجوزات
      if (mounted) {
        setState(() {
          _statistics['todayBookings'] = todayBookings;
          _statistics['weekBookings'] = weekBookings;
          _statistics['monthBookings'] = monthBookings;
          _statistics['confirmedBookings'] = confirmedBookings;
          _statistics['totalBookings'] = totalBookings;
          _loadingStates['bookings'] = false;
        });
      }
    } catch (e) {
      print('Error loading doctors and bookings: $e');
      if (mounted) {
        setState(() {
          _loadingStates['doctors'] = false;
          _loadingStates['bookings'] = false;
        });
      }
    }
  }

  // تحميل عدد المرضى
  Future<void> _loadPatientsCount() async {
    try {
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      Set<String> uniquePatients = {};

      // جلب جميع الحجوزات بالتوازي
      List<Future<QuerySnapshot>> appointmentFutures = [];
      
      for (var specDoc in specializationsSnapshot.docs) {
        final doctorsSnapshot = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .get();

        for (var doctorDoc in doctorsSnapshot.docs) {
          appointmentFutures.add(
            FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(doctorDoc.id)
                .collection('appointments')
                .get()
          );
        }
      }

      final appointmentSnapshots = await Future.wait(appointmentFutures);

      // معالجة الحجوزات
      for (var appointmentsSnapshot in appointmentSnapshots) {
        for (var appointmentDoc in appointmentsSnapshot.docs) {
          final appointmentData = appointmentDoc.data() as Map<String, dynamic>?;
          final patientName = appointmentData?['patientName'] ?? '';
          
          if (patientName.isNotEmpty) {
            uniquePatients.add(patientName);
          }
        }
      }

      if (mounted) {
        setState(() {
          _statistics['patients'] = uniquePatients.length;
          _loadingStates['patients'] = false;
        });
      }
    } catch (e) {
      print('Error loading patients: $e');
      if (mounted) {
        setState(() {
          _loadingStates['patients'] = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _calculateStatistics() async {
    Map<String, dynamic> stats = {
      'specializations': 0,
      'doctors': 0,
      'insuranceCompanies': 0,
      'todayBookings': 0,
      'weekBookings': 0,
      'monthBookings': 0,
      'patients': 0,
      'users': 0,
      'confirmedBookings': 0,
      'totalBookings': 0,
    };

    try {
      // جلب البيانات الأساسية بالتوازي
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();
      
      final insuranceSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('insuranceCompanies')
          .get();
      
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('centerId', isEqualTo: widget.centerId)
          .get();

      stats['specializations'] = specializationsSnapshot.docs.length;
      stats['insuranceCompanies'] = insuranceSnapshot.docs.length;
      stats['users'] = usersSnapshot.docs.length;

      // جلب الأطباء والحجوزات مع تحسين الأداء
      int totalDoctors = 0;
      int todayBookings = 0;
      int weekBookings = 0;
      int monthBookings = 0;
      int confirmedBookings = 0;
      int totalBookings = 0;
      Set<String> uniquePatients = {};

      // تحديد الفترات الزمنية
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final weekAgo = today.subtract(const Duration(days: 7));
      final monthAgo = DateTime(now.year, now.month - 1, now.day);

      // جلب الأطباء بالتوازي (بدلاً من حلقة متسلسلة)
      List<Future<QuerySnapshot>> doctorFutures = [];
      for (var specDoc in specializationsSnapshot.docs) {
        doctorFutures.add(
          FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .get()
        );
      }

      final doctorSnapshots = await Future.wait(doctorFutures);
      
      // جلب الحجوزات بالتوازي مع تحديد الفترات الزمنية
      List<Future<QuerySnapshot>> appointmentFutures = [];
      Map<String, String> doctorToSpecialization = {};

      for (int i = 0; i < specializationsSnapshot.docs.length; i++) {
        final specDoc = specializationsSnapshot.docs[i];
        final doctorsSnapshot = doctorSnapshots[i];
        totalDoctors += doctorsSnapshot.docs.length;

        for (var doctorDoc in doctorsSnapshot.docs) {
          doctorToSpecialization[doctorDoc.id] = specDoc.id;
          
          // جلب الحجوزات مع فلتر التاريخ لتحسين الأداء
          appointmentFutures.add(
            FirebaseFirestore.instance
                .collection('medicalFacilities')
                .doc(widget.centerId)
                .collection('specializations')
                .doc(specDoc.id)
                .collection('doctors')
                .doc(doctorDoc.id)
                .collection('appointments')
                .where('date', isGreaterThanOrEqualTo: monthAgo.toIso8601String())
                .get()
          );
        }
      }

      stats['doctors'] = totalDoctors;

      // معالجة الحجوزات بالتوازي
      final appointmentSnapshots = await Future.wait(appointmentFutures);

      for (var appointmentsSnapshot in appointmentSnapshots) {
        for (var appointmentDoc in appointmentsSnapshot.docs) {
          final appointmentData = appointmentDoc.data() as Map<String, dynamic>?;
          final patientName = appointmentData?['patientName'] ?? '';
          final date = appointmentData?['date'] ?? '';
          final status = appointmentData?['status'] ?? 'pending';

          // إضافة المريض للمجموعة الفريدة
          if (patientName.isNotEmpty) {
            uniquePatients.add(patientName);
          }

          // إجمالي الحجوزات
          totalBookings++;

          // الحجوزات المؤكدة
          if (status == 'confirmed') {
            confirmedBookings++;
          }

          // حجوزات حسب الفترة الزمنية
          if (date.isNotEmpty) {
            try {
              final appointmentDate = DateTime.parse(date);
              
              // حجوزات اليوم
              if (appointmentDate.year == today.year &&
                  appointmentDate.month == today.month &&
                  appointmentDate.day == today.day) {
                todayBookings++;
              }
              
              // حجوزات الأسبوع
              if (appointmentDate.isAfter(weekAgo) && appointmentDate.isBefore(today.add(const Duration(days: 1)))) {
                weekBookings++;
              }
              
              // حجوزات الشهر
              if (appointmentDate.isAfter(monthAgo) && appointmentDate.isBefore(today.add(const Duration(days: 1)))) {
                monthBookings++;
              }
            } catch (e) {
              // تجاهل التواريخ غير الصحيحة
            }
          }
        }
      }

      stats['todayBookings'] = todayBookings;
      stats['weekBookings'] = weekBookings;
      stats['monthBookings'] = monthBookings;
      stats['confirmedBookings'] = confirmedBookings;
      stats['totalBookings'] = totalBookings;
      stats['patients'] = uniquePatients.length;

    } catch (e) {
      print('Error calculating statistics: $e');
    }

    return stats;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'التقارير والإحصائيات - ${widget.centerName}',
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
              onPressed: _loadStatistics,
            ),
          ],
        ),
                 body: SafeArea(
           child: _statistics.isEmpty
               ? Center(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       const CircularProgressIndicator(
                         color: Color(0xFF2FBDAF),
                       ),
                       const SizedBox(height: 16),
                       Text(
                         _loadingMessage,
                         style: TextStyle(
                           fontSize: 16,
                           color: Colors.grey,
                         ),
                       ),
                     ],
                   ),
                 )
               : _statistics.isEmpty
                   ? Center(
                       child: Column(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: [
                           Icon(
                             Icons.analytics_outlined,
                             size: 64,
                             color: Colors.grey[400],
                           ),
                           const SizedBox(height: 16),
                           Text(
                             'لا توجد بيانات متاحة',
                             style: TextStyle(
                               fontSize: 18,
                               color: Colors.grey[600],
                             ),
                           ),
                           const SizedBox(height: 8),
                           Text(
                             'لم يتم العثور على أي إحصائيات لهذا المركز',
                             style: TextStyle(
                               fontSize: 14,
                               color: Colors.grey[500],
                             ),
                           ),
                           const SizedBox(height: 16),
                           ElevatedButton.icon(
                             onPressed: _loadStatistics,
                             icon: const Icon(Icons.refresh),
                             label: const Text('إعادة المحاولة'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: const Color(0xFF2FBDAF),
                               foregroundColor: Colors.white,
                             ),
                           ),
                         ],
                       ),
                     )
                   : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2FBDAF), Color(0xFF1FA8A0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2FBDAF).withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.analytics,
                              size: 48,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'إحصائيات ${widget.centerName}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'آخر تحديث: ${intl.DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),

                                             const SizedBox(height: 24),

                       // Period Selection
                       Container(
                         width: double.infinity,
                         padding: const EdgeInsets.all(16),
                         decoration: BoxDecoration(
                           color: Colors.white,
                           borderRadius: BorderRadius.circular(16),
                           boxShadow: [
                             BoxShadow(
                               color: Colors.grey.withOpacity(0.1),
                               blurRadius: 10,
                               offset: const Offset(0, 4),
                             ),
                           ],
                           border: Border.all(color: Colors.grey[200]!),
                         ),
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             const Text(
                               'اختر الفترة الزمنية',
                               style: TextStyle(
                                 fontSize: 16,
                                 fontWeight: FontWeight.bold,
                                 color: Color(0xFF2FBDAF),
                               ),
                             ),
                             const SizedBox(height: 12),
                             Row(
                               children: [
                                 Expanded(
                                   child: _buildPeriodButton('اليوم', 'today', Icons.today),
                                 ),
                                 const SizedBox(width: 8),
                                 Expanded(
                                   child: _buildPeriodButton('الأسبوع', 'week', Icons.view_week),
                                 ),
                                 const SizedBox(width: 8),
                                 Expanded(
                                   child: _buildPeriodButton('الشهر', 'month', Icons.calendar_month),
                                 ),
                               ],
                             ),
                           ],
                         ),
                       ),

                       const SizedBox(height: 24),

                       // Statistics Grid
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.2,
                        children: [
                          _buildStatCard(
                            'التخصصات الطبية',
                            _statistics['specializations']?.toString() ?? '0',
                            Icons.medical_services,
                            Colors.blue,
                            loadingKey: 'specializations',
                          ),
                          _buildStatCard(
                            'الأطباء',
                            _statistics['doctors']?.toString() ?? '0',
                            Icons.person,
                            Colors.green,
                            loadingKey: 'doctors',
                          ),
                          _buildStatCard(
                            'شركات التأمين',
                            _statistics['insuranceCompanies']?.toString() ?? '0',
                            Icons.security,
                            Colors.orange,
                            loadingKey: 'insuranceCompanies',
                          ),
                          _buildStatCard(
                            'المستخدمين',
                            _statistics['users']?.toString() ?? '0',
                            Icons.people,
                            Colors.purple,
                            loadingKey: 'users',
                          ),
                          _buildStatCard(
                            'المرضى',
                            _statistics['patients']?.toString() ?? '0',
                            Icons.people_outline,
                            Colors.teal,
                            loadingKey: 'patients',
                          ),
                          _buildStatCard(
                            _getPeriodTitle(),
                            _getPeriodBookings(),
                            Icons.calendar_today,
                            Colors.red,
                            loadingKey: 'bookings',
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Booking Statistics
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إحصائيات الحجوزات',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2FBDAF),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildBookingStat(
                                    'إجمالي الحجوزات',
                                    _statistics['totalBookings']?.toString() ?? '0',
                                    Icons.calendar_today,
                                    Colors.blue,
                                    loadingKey: 'bookings',
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildBookingStat(
                                    'الحجوزات المؤكدة',
                                    _statistics['confirmedBookings']?.toString() ?? '0',
                                    Icons.check_circle,
                                    Colors.green,
                                    loadingKey: 'bookings',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildBookingStat(
                                    'نسبة التأكيد',
                                    _calculateConfirmationRate(),
                                    Icons.percent,
                                    Colors.orange,
                                    loadingKey: 'bookings',
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildBookingStat(
                                    'حجوزات اليوم',
                                    _statistics['todayBookings']?.toString() ?? '0',
                                    Icons.today,
                                    Colors.red,
                                    loadingKey: 'bookings',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Summary Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2FBDAF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF2FBDAF).withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ملخص المركز',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2FBDAF),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'يحتوي المركز على ${_statistics['specializations'] ?? 0} تخصص طبي، '
                              'ويعمل فيه ${_statistics['doctors'] ?? 0} طبيب، '
                              'ويخدم ${_statistics['patients'] ?? 0} مريض، '
                              'ويتعامل مع ${_statistics['insuranceCompanies'] ?? 0} شركات تأمين.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                height: 1.5,
                              ),
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
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? loadingKey}) {
    final isLoading = loadingKey != null && (_loadingStates[loadingKey] ?? true);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBookingStat(String title, String value, IconData icon, Color color, {String? loadingKey}) {
    final isLoading = loadingKey != null && (_loadingStates[loadingKey] ?? true);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _calculateConfirmationRate() {
    final total = _statistics['totalBookings'] ?? 0;
    final confirmed = _statistics['confirmedBookings'] ?? 0;
    
    if (total == 0) return '0%';
    
    final rate = (confirmed / total * 100).round();
    return '$rate%';
  }

  Widget _buildPeriodButton(String title, String period, IconData icon) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPeriod = period;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2FBDAF) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2FBDAF) : Colors.grey[300]!,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPeriodTitle() {
    switch (_selectedPeriod) {
      case 'today':
        return 'حجوزات اليوم';
      case 'week':
        return 'حجوزات الأسبوع';
      case 'month':
        return 'حجوزات الشهر';
      default:
        return 'حجوزات اليوم';
    }
  }

  String _getPeriodBookings() {
    switch (_selectedPeriod) {
      case 'today':
        return _statistics['todayBookings']?.toString() ?? '0';
      case 'week':
        return _statistics['weekBookings']?.toString() ?? '0';
      case 'month':
        return _statistics['monthBookings']?.toString() ?? '0';
      default:
        return _statistics['todayBookings']?.toString() ?? '0';
    }
  }
}
