import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'doctor_bookings_screen.dart';
import '../services/sms_service.dart';
import 'notifications_screen.dart'; // Added import for NotificationsScreen

class ReceptionStaffScreen extends StatefulWidget {
  final String centerId;
  final String centerName;
  final String userId;
  final String userName;

  const ReceptionStaffScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.userId,
    required this.userName,
  });

  @override
  State<ReceptionStaffScreen> createState() => _ReceptionStaffScreenState();
}

class _ReceptionStaffScreenState extends State<ReceptionStaffScreen> {
  static const String _defaultDoctorPhotoUrl = 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQupVHd_oeqnkds0k3EjT1SX4ctwwblwYP2Uw&s';

  List<String> _selectedDoctorIds = [];
  List<Map<String, dynamic>> _availableDoctors = [];
  bool _loading = true;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    
    print('ReceptionStaffScreen initState for user: ${widget.userId}');
    print('Center ID: ${widget.centerId}');
    print('User Name: ${widget.userName}');
    
    // تحميل البيانات بشكل متوازي لتحسين الأداء
    _initializeData();
    
    // تحديث عدد الإشعارات كل 30 ثانية
    _startNotificationTimer();
    
    // بدء مراقبة الحجوزات الجديدة
    _startMonitoringNewBookings();
  }

  void _startMonitoringNewBookings() {
    // مراقبة الحجوزات الجديدة كل دقيقة
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        _checkForNewBookings();
        _startMonitoringNewBookings(); // إعادة تشغيل المراقبة
      }
    });
  }

  Future<void> _checkForNewBookings() async {
    try {
      // التحقق من الحجوزات الجديدة للأطباء المفضلين
      for (String doctorId in _selectedDoctorIds) {
        await _checkDoctorNewBookings(doctorId);
      }
    } catch (e) {
      print('Error checking for new bookings: $e');
    }
  }

  Future<void> _checkDoctorNewBookings(String doctorId) async {
    try {
      // البحث عن الطبيب في جميع التخصصات
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      for (var specDoc in specializationsSnapshot.docs) {
        final doctorDoc = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .doc(widget.centerId)
            .collection('specializations')
            .doc(specDoc.id)
            .collection('doctors')
            .doc(doctorId)
            .get();

        if (doctorDoc.exists) {
          final specializationData = specDoc.data();
          final specializationName = specializationData['specName'] ?? specDoc.id;
          final doctorData = doctorDoc.data();
          final doctorName = doctorData?['docName'] ?? 'طبيب غير معروف';

          // جلب الحجوزات الجديدة (التي تم إنشاؤها في آخر 5 دقائق)
          final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
          
          final appointmentsSnapshot = await FirebaseFirestore.instance
              .collection('medicalFacilities')
              .doc(widget.centerId)
              .collection('specializations')
              .doc(specDoc.id)
              .collection('doctors')
              .doc(doctorId)
              .collection('appointments')
              .where('createdAt', isGreaterThan: fiveMinutesAgo)
              .get();

          for (var appointmentDoc in appointmentsSnapshot.docs) {
            final appointmentData = appointmentDoc.data();
            
            // التحقق من أن هذا الحجز لم يتم إشعاره من قبل
            final notificationKey = 'notification_${appointmentDoc.id}';
            final prefs = await SharedPreferences.getInstance();
            final isNotified = prefs.getBool(notificationKey) ?? false;
            
            if (!isNotified) {
              // حفظ الإشعار
              await NotificationService.saveNotification(
                userId: widget.userId,
                doctorId: doctorId,
                doctorName: doctorName,
                patientName: appointmentData['patientName'] ?? 'مريض غير معروف',
                appointmentDate: appointmentData['date'] ?? '',
                appointmentTime: appointmentData['time'] ?? '',
                appointmentId: appointmentDoc.id,
                centerId: widget.centerId,
              );
              
              // تحديد أن هذا الحجز تم إشعاره
              await prefs.setBool(notificationKey, true);
              
              // تحديث عدد الإشعارات
              _loadUnreadNotifications();
              
              print('New booking notification sent for doctor: $doctorName');
            }
          }
          break; // وجدنا الطبيب، لا نحتاج للبحث في تخصصات أخرى
        }
      }
    } catch (e) {
      print('Error checking new bookings for doctor $doctorId: $e');
    }
  }



  // دالة فحص حالة البيانات المحفوظة (للتطوير فقط)
  Future<void> _checkSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoriteKey = 'selectedDoctors_${widget.userId}';
      final savedFavorites = prefs.getStringList(favoriteKey) ?? [];
      
      print('=== Saved Data Check ===');
      print('User ID: ${widget.userId}');
      print('Favorite Key: $favoriteKey');
      print('Saved Favorites Count: ${savedFavorites.length}');
      print('Saved Favorites: $savedFavorites');
      print('Current Selected Doctors: $_selectedDoctorIds');
      print('=======================');
      
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('البيانات المحفوظة: ${savedFavorites.length} طبيب'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('Error checking saved data: $e');
    }
  }

  void _startNotificationTimer() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _loadUnreadNotifications();
        _startNotificationTimer(); // إعادة تشغيل المؤقت
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initializeData() async {
    print('Initializing data for user: ${widget.userId}');
    
    // تحميل الأطباء المفضلين والأطباء المتاحين في نفس الوقت
    await Future.wait([
      _loadSelectedDoctors(),
      _loadAvailableDoctors(),
      _loadUnreadNotifications(),
    ]);
    
    print('Data initialization completed for user: ${widget.userId}');
    print('Selected doctors count: ${_selectedDoctorIds.length}');
    print('Available doctors count: ${_availableDoctors.length}');
  }

  Future<void> _loadSelectedDoctors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'selectedDoctors_${widget.userId}';
      final selectedDoctors = prefs.getStringList(key) ?? [];
      
      print('Loading selected doctors for user: ${widget.userId}');
      print('Using key: $key');
      print('Found ${selectedDoctors.length} doctors: $selectedDoctors');
      
      setState(() {
        _selectedDoctorIds = selectedDoctors;
      });
      
      // التحقق من أن البيانات تم تحميلها بشكل صحيح
      print('Loaded selected doctors in setState: $_selectedDoctorIds');
      
      // التحقق من أن البيانات تم تحميلها بشكل صحيح
      final verification = prefs.getStringList(key) ?? [];
      print('Verification after loading: ${verification.length} doctors');
      
    } catch (e) {
      print('Error loading selected doctors: $e');
      print('User ID when error occurred: ${widget.userId}');
    }
  }

  Future<void> _saveSelectedDoctors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'selectedDoctors_${widget.userId}';
      
      print('Saving selected doctors for user: ${widget.userId}');
      print('Using key: $key');
      print('Doctors to save: $_selectedDoctorIds');
      
      final success = await prefs.setStringList(key, _selectedDoctorIds);
      print('Save success: $success');
      
      // التحقق من أن البيانات تم حفظها بشكل صحيح
      final savedDoctors = prefs.getStringList(key) ?? [];
      print('Verification after save: ${savedDoctors.length} doctors saved');
      print('Saved doctors: $savedDoctors');
      
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ ${_selectedDoctorIds.length} طبيب مفضل'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error saving selected doctors: $e');
      print('User ID when save error occurred: ${widget.userId}');
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ الأطباء المفضلين: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadAvailableDoctors() async {
    try {
      print('Loading doctors for center: ${widget.centerId}');
      
      final specializationsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .get();

      print('Found ${specializationsSnapshot.docs.length} specializations');

      final Set<String> addedDoctorIds = {};
      List<Map<String, dynamic>> doctors = [];

      // تحميل الأطباء بشكل متوازي بدلاً من متسلسل
      final List<Future<void>> futures = [];

      for (var specDoc in specializationsSnapshot.docs) {
        futures.add(_loadDoctorsFromSpecialization(specDoc, addedDoctorIds, doctors));
      }

      // انتظار اكتمال جميع الطلبات
      await Future.wait(futures);

      // Sort doctors by name
      doctors.sort((a, b) => (a['doctorName'] ?? '').toString().toLowerCase().compareTo((b['doctorName'] ?? '').toString().toLowerCase()));

      print('Total active doctors loaded: ${doctors.length}');

      setState(() {
        _availableDoctors = doctors;
        _loading = false;
      });
    } catch (e) {
      print('Error loading doctors: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadDoctorsFromSpecialization(
    DocumentSnapshot specDoc,
    Set<String> addedDoctorIds,
    List<Map<String, dynamic>> doctors,
  ) async {
    try {
      print('Loading doctors from specialization: ${specDoc.id}');
      
      final doctorsSnapshot = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .doc(widget.centerId)
          .collection('specializations')
          .doc(specDoc.id)
          .collection('doctors')
          .where('isActive', isEqualTo: true)
          .get();

      print('Found ${doctorsSnapshot.docs.length} active doctors in specialization ${specDoc.id}');

      final specializationData = specDoc.data() as Map<String, dynamic>? ?? {};

      for (var doctorDoc in doctorsSnapshot.docs) {
        if (addedDoctorIds.contains(doctorDoc.id)) {
          print('Doctor ${doctorDoc.id} already added, skipping');
          continue;
        }

        final doctorData = doctorDoc.data();
        
        // استخدام البيانات المحلية مباشرة بدلاً من البحث في allDoctors
        final name = doctorData['docName'] ?? 'طبيب غير معروف';
        final photo = (doctorData['photoUrl'] ?? '').toString();

        doctors.add({
          'doctorId': doctorDoc.id,
          'doctorName': name,
          'specialization': specializationData['specName'] ?? specDoc.id,
          'photoUrl': photo.isNotEmpty ? photo : _defaultDoctorPhotoUrl,
          'specializationId': specDoc.id,
        });
        addedDoctorIds.add(doctorDoc.id);
        print('Added active doctor: $name');
      }
    } catch (e) {
      print('Error loading doctors from specialization ${specDoc.id}: $e');
    }
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      print('Loading unread notifications for user: ${widget.userId}');
      final count = await NotificationService.getUnreadCount(widget.userId);
      print('Unread notifications count: $count');
      
      if (mounted) {
        setState(() {
          _unreadNotifications = count;
        });
        print('Updated unread notifications in UI: $_unreadNotifications');
        
        // التحقق من أن البيانات تم تحديثها بشكل صحيح
        final verification = await NotificationService.getUnreadCount(widget.userId);
        print('Verification unread count: $verification');
      }
    } catch (e) {
      print('Error loading unread notifications: $e');
    }
  }

  void _viewDoctorBookings(String doctorId, String doctorName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorBookingsScreen(
          doctorId: doctorId,
          centerId: widget.centerId,
          centerName: widget.centerName,
          doctorName: doctorName,
        ),
      ),
    );
  }

  void _openNotificationsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationsScreen(
          userId: widget.userId,
          centerName: widget.centerName,
          onNotificationsChanged: _loadUnreadNotifications,
        ),
      ),
    ).then((_) {
      // تحديث عدد الإشعارات عند العودة
      _loadUnreadNotifications();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    print('didChangeDependencies called for user: ${widget.userId}');
    
    // تحديث عدد الإشعارات عند تغيير التبعيات
    _loadUnreadNotifications();
    
    // إعادة تحميل الأطباء المفضلين عند العودة للشاشة
    _loadSelectedDoctors();
  }

  Future<void> _openSelectFavorites() async {
    if (_loading) return;

    print('Opening select favorites dialog');
    print('Available doctors count: ${_availableDoctors.length}');
    print('Center ID: ${widget.centerId}');

    final Set<String> tempSelected = {..._selectedDoctorIds};
    String searchQuery = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Row(
                    children: [
                      const Text(
                        'اختر الأطباء المفضلين',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Search bar
                  TextField(
                    onChanged: (value) {
                      setLocalState(() {
                        searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'البحث في الأطباء...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Doctors list
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final filteredDoctors = _availableDoctors.where((doctor) {
                          if (searchQuery.isEmpty) return true;
                          final name = doctor['doctorName'].toString().toLowerCase();
                          final specialization = doctor['specialization'].toString().toLowerCase();
                          final query = searchQuery.toLowerCase();
                          return name.contains(query) || specialization.contains(query);
                        }).toList();
                        
                        if (filteredDoctors.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  searchQuery.isEmpty ? Icons.people_outline : Icons.search_off,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  searchQuery.isEmpty 
                                      ? 'لا يوجد أطباء متاحين'
                                      : 'لم يتم العثور على أطباء يطابقون البحث',
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
                          itemCount: filteredDoctors.length,
                          itemBuilder: (context, index) {
                            final doctor = filteredDoctors[index];
                            final isSelected = tempSelected.contains(doctor['doctorId']);
                            final photoUrl = ((doctor['photoUrl'] ?? '') as String).isNotEmpty
                                ? doctor['photoUrl'] as String
                                : _defaultDoctorPhotoUrl;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (val) {
                                  setLocalState(() {
                                    if (isSelected) {
                                      tempSelected.remove(doctor['doctorId']);
                                    } else {
                                      tempSelected.add(doctor['doctorId']);
                                    }
                                  });
                                },
                                activeColor: const Color(0xFF2FBDAF),
                                title: Text(
                                  doctor['doctorName'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(doctor['specialization']),
                                secondary: CircleAvatar(
                                  radius: 25,
                                  backgroundColor: Colors.grey[200],
                                  child: ClipOval(
                                    child: Image.network(
                                      photoUrl,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      cacheWidth: 100,
                                      cacheHeight: 100,
                                      errorBuilder: (c, e, s) => Image.network(
                                        _defaultDoctorPhotoUrl,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        cacheWidth: 100,
                                        cacheHeight: 100,
                                        errorBuilder: (c2, e2, s2) => const Icon(Icons.person, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  
                  // Actions
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إلغاء'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedDoctorIds = tempSelected.toList();
                          });
                          
                          print('Saving selected doctors from dialog');
                          print('Selected doctors: $_selectedDoctorIds');
                          
                          _saveSelectedDoctors();
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2FBDAF),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('حفظ'),
                      ),
                    ],
                  ),
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
    final favoriteDoctors = _availableDoctors
        .where((d) => _selectedDoctorIds.contains(d['doctorId']))
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          
          title: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const Text(
                  'موظف الاستقبال',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          foregroundColor: Colors.white,
          elevation: 0,
                    actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'إضافة أطباء مفضلين',
              onPressed: _openSelectFavorites,
            ),
            IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.notifications),
                  if (_unreadNotifications > 0)
                    Positioned(
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        child: Text(
                          _unreadNotifications.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: _openNotificationsScreen,
              tooltip: 'الإشعارات',
            ),
          ],
          leading: IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              
              // حفظ معرف المستخدم قبل مسح البيانات
              final currentUserId = widget.userId;
              
              print('Logout: Starting logout for user: $currentUserId');
              print('Logout: Current favorite doctors: $_selectedDoctorIds');
              
              // مسح بيانات تسجيل الدخول فقط، وليس الأطباء المفضلين
              await prefs.remove('userId');
              await prefs.remove('userName');
              await prefs.remove('centerId');
              await prefs.remove('centerName');
              await prefs.remove('userType');
              await prefs.remove('isLoggedIn');
              

              
              // تأكيد أن الأطباء المفضلين محفوظة
              final favoriteKey = 'selectedDoctors_$currentUserId';
              final savedFavorites = prefs.getStringList(favoriteKey) ?? [];
              print('Logout: Favorite doctors preserved: ${savedFavorites.length} doctors');
              print('Logout: Preserved doctors: $savedFavorites');
              
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
            tooltip: 'تسجيل الخروج',
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2FBDAF),
                  ),
                )
              : Column(
                  children: [
                    // Header section
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[50],
                      child: Column(
                        children: const [
                          Text(
                            'الأطباء المفضلون',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2FBDAF),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Favorites list
                    Expanded(
                      child: favoriteDoctors.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.star_border,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'لا يوجد أطباء مفضلين',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: _openSelectFavorites,
                                    icon: const Icon(Icons.add),
                                    label: const Text('إضافة أطباء'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2FBDAF),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: favoriteDoctors.length,
                              itemBuilder: (context, index) {
                                final doctor = favoriteDoctors[index];
                                final photoUrl = ((doctor['photoUrl'] ?? '') as String).isNotEmpty
                                    ? doctor['photoUrl'] as String
                                    : _defaultDoctorPhotoUrl;
                                return InkWell(
                                  onTap: () => _viewDoctorBookings(
                                    doctor['doctorId'],
                                    doctor['doctorName'],
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.08),
                                          spreadRadius: 1,
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      leading: CircleAvatar(
                                        radius: 30,
                                        backgroundColor: Colors.grey[200],
                                        child: ClipOval(
                                          child: Image.network(
                                            photoUrl,
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                            cacheWidth: 120, // تحسين الأداء
                                            cacheHeight: 120,
                                            errorBuilder: (c, e, s) => Image.network(
                                              _defaultDoctorPhotoUrl,
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                              cacheWidth: 120,
                                              cacheHeight: 120,
                                              errorBuilder: (c2, e2, s2) => const Icon(Icons.person, size: 30, color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        doctor['doctorName'],
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        doctor['specialization'],
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      trailing: const Icon(Icons.chevron_left, color: Color(0xFF2FBDAF)),
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
    );
  }
}
