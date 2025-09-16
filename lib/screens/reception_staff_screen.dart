import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'doctor_bookings_screen.dart';
import '../services/sms_service.dart';
import '../services/favorite_doctors_service.dart';
import 'notifications_screen.dart'; // Added import for NotificationsScreen
import '../services/presence_service.dart';
import '../services/sms_service.dart' show NotificationService;

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
  int _confirmedBookingsCount = 0; // عداد الحجوزات المؤكدة
  bool _listenersActive = false; // لمنع الازدواجية مع المؤقت
  bool _internalNotificationsEnabled = false; // إيقاف/تشغيل الإشعارات الداخلية مؤقتاً
  bool _savingFavorites = false; // حالة حفظ الأطباء المفضلين

  // تتبع الإشعارات التي تم معالجتها لتجنب التكرار
  final Set<String> _notifiedAppointmentIds = <String>{};

  // مستمعو الحجوزات للأطباء المفضلين (doctorId -> قائمة مستمعين)
  final Map<String, List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>> _doctorAppointmentSubscriptions = {};

  @override
  void initState() {
    super.initState();
    
    print('=== RECEPTION STAFF SCREEN INIT ===');
    print('User ID: ${widget.userId}');
    print('User ID type: ${widget.userId.runtimeType}');
    print('User ID is null: ${widget.userId == null}');
    print('User ID is empty: ${widget.userId?.isEmpty ?? true}');
    print('Center ID: ${widget.centerId}');
    print('User Name: ${widget.userName}');
    
    // فحص SharedPreferences للتأكد من البيانات
    _checkSharedPreferences();
    
    // تحميل البيانات بشكل متوازي لتحسين الأداء
    _initializeData();
    
    // تحديث عدد الإشعارات كل 30 ثانية
    _startNotificationTimer();
    
    // بدء مراقبة الحجوزات الجديدة
    _startMonitoringNewBookings();

    // presence online on open
    PresenceService.setOnline(userId: widget.userId, userType: 'reception');

    // تأكد من تعطيل الإشعارات الداخلية من الخدمة أيضاً
    NotificationService.setInternalEnabled(false);
  }

  // دالة فحص SharedPreferences
  Future<void> _checkSharedPreferences() async {
    try {
      print('=== CHECKING SHARED PREFERENCES ===');
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('userId');
      final savedCenterId = prefs.getString('centerId');
      final savedUserName = prefs.getString('userName');
      final savedUserType = prefs.getString('userType');
      
      print('SharedPreferences Data:');
      print('- userId: $savedUserId');
      print('- centerId: $savedCenterId');
      print('- userName: $savedUserName');
      print('- userType: $savedUserType');
      
      // مقارنة مع widget data
      print('Widget vs SharedPreferences:');
      print('- widget.userId: ${widget.userId}');
      print('- savedUserId: $savedUserId');
      print('- Match: ${widget.userId == savedUserId}');
      
    } catch (e) {
      print('❌ Error checking SharedPreferences: $e');
    }
  }

  void _startMonitoringNewBookings() {
    if (!_internalNotificationsEnabled) return; // موقوفة مؤقتاً
    // مراقبة الحجوزات الجديدة كل دقيقة
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        // إذا كانت هناك مستمعات فورية مفعلة، لا داعي للفحص الدوري لتجنب التكرار
        if (!_listenersActive) {
          _checkForNewBookings();
        }
        _startMonitoringNewBookings(); // إعادة تشغيل المراقبة
      }
    });
  }

  Future<void> _checkForNewBookings() async {
    try {
      if (!_internalNotificationsEnabled) return; // موقوفة مؤقتاً
      if (_listenersActive) return; // حماية إضافية
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
      if (!_internalNotificationsEnabled) return; // موقوفة مؤقتاً
      if (_listenersActive) return; // إذا المراقبة الفورية فعالة نتجنب الازدواجية
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

            // تجاهل الحجوزات التي أنشأها موظف الاستقبال
            final createdBy = (appointmentData['createdBy'] ?? '').toString();
            final createdByType = (appointmentData['createdByType'] ?? '').toString();
            if (createdBy == 'reception' || createdByType == 'reception') {
              continue;
            }
            
            // التحقق من أن هذا الحجز لم يتم إشعاره من قبل
            final notificationKey = 'notification_${widget.userId}_${appointmentDoc.id}';
            final prefs = await SharedPreferences.getInstance();
            final isNotified = prefs.getBool(notificationKey) ?? false;
            
            if (!isNotified) {
              if (!_internalNotificationsEnabled) { continue; }
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

  // إلغاء كل المستمعين الحاليين
  void _detachAllAppointmentListeners() {
    for (final subs in _doctorAppointmentSubscriptions.values) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _doctorAppointmentSubscriptions.clear();
  }

  // إعادة بناء المستمعين لكل طبيب مفضل لمراقبة الحجوزات الجديدة
  Future<void> _refreshAppointmentListeners() async {
    try {
      if (!_internalNotificationsEnabled) {
        _detachAllAppointmentListeners();
        _listenersActive = false;
        return; // موقوفة مؤقتاً
      }
      _detachAllAppointmentListeners();
      // فعّل العلم مبكراً لتوقيف الفحص الدوري فوراً وتجنب الازدواجية
      _listenersActive = true;
      for (final doctorId in _selectedDoctorIds) {
        final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

        // إيجاد تخصص الطبيب ثم الاشتراك على appointments
        final specializationsSnapshot = await FirebaseFirestore.instance
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
              .doc(doctorId);

          final doctorDoc = await doctorRef.get();
          if (!doctorDoc.exists) continue;
          final doctorData = doctorDoc.data() as Map<String, dynamic>?;
          final fixedDoctorName = (doctorData?['docName'] ?? doctorData?['doctorName'] ?? 'طبيب غير معروف').toString();

          // استمع للحجوزات الجديدة فقط (createdAt أكبر من الآن - 2 دقيقة كنافذة صغيرة)
          final twoMinutesAgo = DateTime.now().subtract(const Duration(minutes: 2));
          final sub = doctorRef
              .collection('appointments')
              .where('createdAt', isGreaterThan: Timestamp.fromDate(twoMinutesAgo))
              .snapshots()
              .listen((snapshot) async {
            for (final doc in snapshot.docChanges) {
              if (doc.type != DocumentChangeType.added) continue;
              final data = doc.doc.data();
              if (data == null) continue;

              // تجاهل حجوزات موظف الاستقبال
              final byType = (data['createdByType'] ?? '').toString();
              final by = (data['createdBy'] ?? '').toString();
              if (byType == 'reception' || by == 'reception') continue;

              // منع التكرار: افحص مجموعة الذاكرة و SharedPreferences
              final String appointmentId = doc.doc.id;
              if (_notifiedAppointmentIds.contains(appointmentId)) continue;
              final prefs = await SharedPreferences.getInstance();
              final String spKey = 'notification_${widget.userId}_${appointmentId}';
              final bool already = prefs.getBool(spKey) ?? false;
              if (already) {
                _notifiedAppointmentIds.add(appointmentId);
                continue;
              }

              if (!_internalNotificationsEnabled) continue; // موقوفة مؤقتاً
              final patientName = data['patientName'] ?? 'مريض غير معروف';
              final appointmentDate = data['date'] ?? '';
              final appointmentTime = data['time'] ?? '';

              // حفظ الإشعار محلياً وزيادة العداد
              await NotificationService.saveNotification(
                userId: widget.userId,
                doctorId: doctorId,
                doctorName: fixedDoctorName,
                patientName: patientName,
                appointmentDate: appointmentDate,
                appointmentTime: appointmentTime,
                appointmentId: doc.doc.id,
                centerId: widget.centerId,
              );

              // علّم بأنه تم إشعاره
              _notifiedAppointmentIds.add(appointmentId);
              await prefs.setBool(spKey, true);

              // تحديث عداد الإشعارات في الواجهة
              _loadUnreadNotifications();
            }
          });
          subs.add(sub);
          break; // وجدنا الطبيب
        }
        _doctorAppointmentSubscriptions[doctorId] = subs;
      }
      // ثبّت العلم بناءً على وجود مستمعين فعليين
      _listenersActive = _doctorAppointmentSubscriptions.isNotEmpty;
    } catch (e) {
      print('❌ Error refreshing appointment listeners: $e');
    }
  }



  // دالة عرض رسالة تأكيد الحذف
  void _showDeleteConfirmation(String doctorId, String doctorName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل أنت متأكد من حذف الدكتور $doctorName من المفضلة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // إضافة تأخير صغير لمنع التعليق
                await Future.delayed(const Duration(milliseconds: 100));
                if (mounted) {
                  try {
                    await _removeDoctorFromFavorites(doctorId, doctorName);
                  } catch (e) {
                    print('❌ Error in delete confirmation: $e');
                    // لا حاجة لعرض رسالة خطأ إضافية هنا
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );
  }

  // دالة حذف طبيب من المفضلة
  Future<void> _removeDoctorFromFavorites(String doctorId, String doctorName) async {
    try {
      print('=== REMOVING DOCTOR FROM FAVORITES ===');
      print('Doctor ID: $doctorId');
      print('Doctor Name: $doctorName');
      print('Current favorites: $_selectedDoctorIds');
      print('Current count: ${_selectedDoctorIds.length}');
      
      // إزالة الطبيب من القائمة المحلية أولاً
      setState(() {
        _selectedDoctorIds.remove(doctorId);
      });
      
      print('Updated favorites: $_selectedDoctorIds');
      print('Updated count: ${_selectedDoctorIds.length}');
      
      // حفظ التغييرات في قاعدة البيانات
      try {
        await _saveSelectedDoctors();
        print('✅ Doctor removed successfully!');
        // تم إزالة رسالة النجاح بناءً على طلب المستخدم
      } catch (saveError) {
        print('❌ Error saving to database: $saveError');
        // إعادة الطبيب للقائمة في حالة فشل الحفظ
        setState(() {
          if (!_selectedDoctorIds.contains(doctorId)) {
            _selectedDoctorIds.add(doctorId);
          }
        });
        throw saveError;
      }
      
      print('=== REMOVE COMPLETED ===');
    } catch (e) {
      print('❌ Error removing doctor: $e');
      print('Error details: ${e.toString()}');
      
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في حذف الطبيب: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
    // mark offline on dispose
    PresenceService.setOffline(userId: widget.userId);
    _detachAllAppointmentListeners();
    super.dispose();
  }

  Future<void> _initializeData() async {
    print('Initializing data for user: ${widget.userId}');
    
    // تحميل الأطباء المفضلين والأطباء المتاحين في نفس الوقت
    await Future.wait([
      _loadSelectedDoctors(),
      _loadAvailableDoctors(),
      _loadUnreadNotifications(),
      _loadConfirmedBookingsCount(), // تحميل عداد الحجوزات المؤكدة
    ]);
    
    print('Data initialization completed for user: ${widget.userId}');
    print('Selected doctors count: ${_selectedDoctorIds.length}');
    print('Available doctors count: ${_availableDoctors.length}');
    print('Confirmed bookings count: $_confirmedBookingsCount');
  }

  Future<void> _loadSelectedDoctors() async {
    try {
      print('=== LOADING SELECTED DOCTORS ===');
      print('User ID: ${widget.userId}');
      print('Center ID: ${widget.centerId}');
      
      final selectedDoctors = await FavoriteDoctorsService.getFavoriteDoctors(
        userId: widget.userId,
        centerId: widget.centerId,
      );
      
      print('Found ${selectedDoctors.length} favorite doctors from database: $selectedDoctors');
      print('Selected doctors: $selectedDoctors');
      
      setState(() {
        _selectedDoctorIds = selectedDoctors;
      });
      
      print('Updated _selectedDoctorIds: $_selectedDoctorIds');
      print('Updated count: ${_selectedDoctorIds.length}');
      
      // التحقق من أن البيانات تم تحميلها بشكل صحيح
      if (_selectedDoctorIds.length != selectedDoctors.length) {
        print('⚠️ WARNING: Count mismatch after setState!');
        print('Expected: ${selectedDoctors.length}, Actual: ${_selectedDoctorIds.length}');
      }
      
      print('=== LOAD COMPLETED ===');
      // بعد تحميل الأطباء المفضلين، حدّث المستمعين للحجوزات
      await _refreshAppointmentListeners();
      
    } catch (e) {
      print('❌ Error loading selected doctors: $e');
      print('Error details: ${e.toString()}');
      print('User ID when error occurred: ${widget.userId}');
    }
  }

  Future<void> _saveSelectedDoctors() async {
    try {
      print('=== _saveSelectedDoctors STARTED ===');
      print('User ID: ${widget.userId}');
      print('Center ID: ${widget.centerId}');
      print('Selected doctor IDs: $_selectedDoctorIds');
      print('Selected count: ${_selectedDoctorIds.length}');
      print('Selected types: ${_selectedDoctorIds.map((id) => '${id.runtimeType}: $id').toList()}');
      
      // احتفظ بالقائمة السابقة للاشتراك/إلغاء الاشتراك في التوبيكات لاحقاً
      final Set<String> previousDoctorIds = {..._selectedDoctorIds};

      // التحقق من أن القائمة ليست فارغة
      if (_selectedDoctorIds.isEmpty) {
        print('⚠️ WARNING: No doctors selected!');
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم اختيار أي أطباء للحفظ'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // التحقق من صحة البيانات
      final validIds = _selectedDoctorIds.where((id) => id != null && id.toString().isNotEmpty).toList();
      print('Valid doctor IDs: $validIds');
      print('Valid count: ${validIds.length}');
      
      if (validIds.isEmpty) {
        print('❌ ERROR: No valid doctor IDs found!');
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خطأ: لا توجد معرفات صحيحة للأطباء'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      print('Calling FavoriteDoctorsService.saveFavoriteDoctors...');
      final success = await FavoriteDoctorsService.saveFavoriteDoctors(
        userId: widget.userId,
        centerId: widget.centerId,
        doctorIds: validIds,
      );
      
      print('Save result: $success');
      
      if (mounted && context.mounted) {
        if (success) {
          // تم إزالة رسالة النجاح بناءً على طلب المستخدم
          
          // تحديث القائمة المحلية
          setState(() {
            _selectedDoctorIds = validIds;
          });
          
          print('✅ Local state updated with: $_selectedDoctorIds');

          // إدارة الاشتراك في مواضيع التنبيهات لكل طبيب
          try {
            final FirebaseMessaging messaging = FirebaseMessaging.instance;
            final Set<String> newDoctorIds = {...validIds.map((e) => e.toString())};
            final Set<String> toSubscribe = newDoctorIds.difference(previousDoctorIds);
            final Set<String> toUnsubscribe = previousDoctorIds.difference(newDoctorIds);

            // الاشتراك في الأطباء الجدد
            for (final docId in toSubscribe) {
              final topic = 'doctor_${docId}';
              print('🔔 Subscribing to topic: $topic');
              await messaging.subscribeToTopic(topic);
            }

            // في حالة عدم وجود تغيير فعلي، أعد الاشتراك في جميع المواضيع للتأكيد
            if (toSubscribe.isEmpty && toUnsubscribe.isEmpty) {
              for (final docId in newDoctorIds) {
                final topic = 'doctor_${docId}';
                print('🔁 Re-subscribing to topic (no changes detected): $topic');
                await messaging.subscribeToTopic(topic);
              }
            }

            // إلغاء الاشتراك من الأطباء المحذوفين
            for (final docId in toUnsubscribe) {
              final topic = 'doctor_${docId}';
              print('🔕 Unsubscribing from topic: $topic');
              await messaging.unsubscribeFromTopic(topic);
            }
          } catch (e) {
            print('❌ Error managing FCM topic subscriptions: $e');
          }

          // إعادة بناء مستمعي الحجوزات بعد التحديث
          await _refreshAppointmentListeners();
        } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ خطأ في حفظ الأطباء المفضلين'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
          ),
        );
      }
      }
      
      print('=== _saveSelectedDoctors COMPLETED ===');
    } catch (e) {
      print('❌ Error in _saveSelectedDoctors: $e');
      print('Error details: ${e.toString()}');
      print('Stack trace: ${StackTrace.current}');
      
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في حفظ الأطباء المفضلين: $e'),
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

  // دالة تحميل عداد الحجوزات المؤكدة
  Future<void> _loadConfirmedBookingsCount() async {
    try {
      print('=== LOADING CONFIRMED BOOKINGS COUNT ===');
      print('User ID: ${widget.userId}');
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        final count = userData?['confirmedBookingsCount'] ?? 0;
        
        print('Found confirmed bookings count: $count');
        
        if (mounted) {
          setState(() {
            _confirmedBookingsCount = count;
          });
        }
      } else {
        print('⚠️ User document not found');
      }
    } catch (e) {
      print('❌ Error loading confirmed bookings count: $e');
    }
  }

  // دالة اختبار زيادة العداد مباشرة للتشخيص
  Future<void> _testIncrementConfirmedBookingsCount() async {
    try {
      print('=== TESTING DIRECT INCREMENT ===');
      print('User ID: ${widget.userId}');
      print('User ID is null: ${widget.userId == null}');
      
      if (widget.userId == null || widget.userId!.isEmpty) {
        print('❌ User ID is null or empty, cannot test increment');
        return;
      }

      // محاولة زيادة العداد مباشرة
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({
        'confirmedBookingsCount': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      print('✅ Direct increment successful, now reloading count...');
      
      // إعادة تحميل العداد
      await _loadConfirmedBookingsCount();
      
    } catch (e) {
      print('❌ Error in direct increment test: $e');
      print('Error details: ${e.toString()}');
    }
  }

  // دالة فحص البيانات المحفوظة للتشخيص
  Future<void> _checkSavedData() async {
    try {
      print('=== CHECKING SAVED DATA ===');
      print('User ID: ${widget.userId}');
      print('Center ID: ${widget.centerId}');
      print('User Name: ${widget.userName}');
      
      // فحص SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('userId');
      final savedCenterId = prefs.getString('centerId');
      final savedUserName = prefs.getString('userName');
      final savedUserType = prefs.getString('userType');
      
      print('SharedPreferences Data:');
      print('- userId: $savedUserId');
      print('- centerId: $savedCenterId');
      print('- userName: $savedUserName');
      print('- userType: $savedUserName');
      
      // فحص قاعدة البيانات
      if (widget.userId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data();
          print('Firebase User Data:');
          print('- confirmedBookingsCount: ${userData?['confirmedBookingsCount']}');
          print('- lastUpdated: ${userData?['lastUpdated']}');
          print('- createdAt: ${userData?['createdAt']}');
          print('- userType: ${userData?['userType']}');
        } else {
          print('❌ User document not found in Firebase');
        }
      } else {
        print('❌ Widget userId is null');
      }
      
    } catch (e) {
      print('❌ Error checking saved data: $e');
    }
  }

  void _viewDoctorBookings(String doctorId, String doctorName) {
    print('=== NAVIGATING TO DOCTOR BOOKINGS ===');
    print('Doctor ID: $doctorId');
    print('Doctor Name: $doctorName');
    print('Center ID: ${widget.centerId}');
    print('Center Name: ${widget.centerName}');
    print('User ID: ${widget.userId}');
    print('User ID is null: ${widget.userId == null}');
    print('User ID is empty: ${widget.userId?.isEmpty ?? true}');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorBookingsScreen(
          doctorId: doctorId,
          centerId: widget.centerId,
          centerName: widget.centerName,
          doctorName: doctorName,
          userId: widget.userId, // تمرير معرف المستخدم
        ),
      ),
    ).then((_) {
      // تحديث عداد الحجوزات المؤكدة عند العودة
      print('🔄 Returning from DoctorBookingsScreen, updating confirmed bookings count...');
      _loadConfirmedBookingsCount();
    });
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
                        onPressed: _savingFavorites ? null : () async {
                          print('=== SAVING FROM DIALOG ===');
                          print('Temp selected doctors: $tempSelected');
                          print('Temp selected count: ${tempSelected.length}');
                          
                          setLocalState(() {
                            _savingFavorites = true;
                          });
                          
                          try {
                            // تحديث القائمة الرئيسية
                            setState(() {
                              _selectedDoctorIds = tempSelected.toList();
                            });
                            
                            print('Updated _selectedDoctorIds: $_selectedDoctorIds');
                            print('Updated count: ${_selectedDoctorIds.length}');
                            
                            // حفظ البيانات في قاعدة البيانات
                            await _saveSelectedDoctors();
                            
                            Navigator.pop(ctx);
                          } catch (e) {
                            print('Error saving favorites: $e');
                            if (mounted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('خطأ في حفظ الأطباء المفضلين: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setLocalState(() {
                                _savingFavorites = false;
                              });
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2FBDAF),
                          foregroundColor: Colors.white,
                        ),
                        child: _savingFavorites
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('جاري الحفظ...'),
                                ],
                              )
                            : const Text('حفظ'),
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
              print('Logout: Center ID: ${widget.centerId}');
              
              // مسح بيانات تسجيل الدخول فقط، وليس الأطباء المفضلين
              await prefs.remove('userId');
              await prefs.remove('userName');
              await prefs.remove('centerId');
              await prefs.remove('centerName');
              await prefs.remove('userType');
              await prefs.remove('isLoggedIn');
              
              // تأكيد أن الأطباء المفضلين محفوظة في قاعدة البيانات
              final savedFavorites = await FavoriteDoctorsService.getFavoriteDoctors(
                userId: currentUserId,
                centerId: widget.centerId,
              );
              print('Logout: Favorite doctors preserved in database: ${savedFavorites.length} doctors');
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
                        children: [
                          const Text(
                            'الأطباء المفضلون',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2FBDAF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          
                          // تم حذف عداد الحجوزات المؤكدة من الشاشة
                          // العداد لا يزال يعمل في الخلفية ويتم تحديثه في قاعدة البيانات
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
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // زر حذف الطبيب
                                          IconButton(
                                            onPressed: () => _showDeleteConfirmation(
                                              doctor['doctorId'],
                                              doctor['doctorName'],
                                            ),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                              size: 24,
                                            ),
                                            tooltip: 'حذف من المفضلة',
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.chevron_left, color: Color(0xFF2FBDAF)),
                                        ],
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
    );
  }
}
