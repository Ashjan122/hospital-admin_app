 import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:hospital_admin_app/screens/central_data_screen.dart';
import 'package:hospital_admin_app/screens/control_user_screen.dart';
import 'package:hospital_admin_app/screens/users_stats_screen.dart';
import 'package:hospital_admin_app/screens/sample_requests_screen.dart';
import 'package:hospital_admin_app/screens/support_numbers_screen.dart';
import 'package:hospital_admin_app/screens/control_notifications_screen.dart';
import 'package:hospital_admin_app/screens/home_clinic_centers_screen.dart';
import 'package:lottie/lottie.dart';

class ControlPanelScreen extends StatefulWidget {
  const ControlPanelScreen({super.key});

  @override
  State<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends State<ControlPanelScreen> {
  String? _controlUserId;
  String? _userName;
  final ImagePicker _picker = ImagePicker();
  String? _profileImageUrl;
  @override
  void initState() {
    super.initState();
    print('ControlPanelScreen initState');
    _checkLoginStatus();
     _loadUserName();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final role = prefs.getString('role');

    print('ControlPanel _checkLoginStatus - isLoggedIn: $isLoggedIn, role: $role');

    if (!isLoggedIn || role != 'control') {
      print('Redirecting to login screen');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } else {
      print('User is logged in as control, staying in ControlPanel');
      // حذف fromControlPanel عند الوصول للكنترول
      await prefs.remove('fromControlPanel');
      print('تم حذف fromControlPanel عند الوصول للكنترول');
      
      // إعادة الاشتراك في الإشعارات إذا كان مشترك سابقاً
      await _restoreNotificationSubscription();
    }
  }

  Future<void> _restoreNotificationSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSubscribed = prefs.getBool('subscribed_to_new_signup') ?? false;
      
      if (isSubscribed) {
        // استيراد Firebase Messaging
        final FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.subscribeToTopic('new_signup');
        print('تم إعادة الاشتراك في إشعارات الحسابات الجديدة');
      } else {
        // إذا لم يكن مشترك، اشترك تلقائياً
        final FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.subscribeToTopic('new_signup');
        await prefs.setBool('subscribed_to_new_signup', true);
        print('تم الاشتراك التلقائي في إشعارات الحسابات الجديدة');
      }
    } catch (e) {
      print('خطأ في إعادة الاشتراك في الإشعارات: $e');
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('userType');
    await prefs.remove('role');
    await prefs.remove('profileImageUrl');
    await prefs.remove('subscribed_to_new_signup');

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // عنصر بطاقة أيقونة في الشاشة الرئيسية
  Widget _buildHomeCard({
  required String lottieAsset,
    required String title,
    required VoidCallback onTap,
  double size = 60, // الحجم الافتراضي
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),

            SizedBox(
              height: size,
              width: size,
              child: Lottie.asset(
                lottieAsset,
                repeat: true,
                fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReceptionStaffList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ControlUsersScreen(),
      ),
    );
  }

  void _showSampleRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SampleRequestsScreen(),
          ),
        );
      }
  void _showEditProfileDialog() {
  final TextEditingController nameController = TextEditingController(text: _userName ?? '');
  final TextEditingController passwordController = TextEditingController();

      showDialog(
        context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('الملف الشخصي'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // حقل الاسم
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              ),
              const SizedBox(height: 10),

              // حقل تغيير كلمة المرور
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تغيير كلمة المرور',
                  hintText: 'اتركه فارغ إذا لا تريد التغيير',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newPassword = passwordController.text.trim();

              if (_controlUserId == null) return;

              final updates = <String, dynamic>{};

              if (newName.isNotEmpty) {
                updates['userName'] = newName;
              }

              if (newPassword.isNotEmpty) {
                updates['userPassword'] = newPassword;
              }

              if (updates.isNotEmpty) {
                try {
                  await FirebaseFirestore.instance
                      .collection('controlUsers')
                      .doc(_controlUserId)
                      .update(updates);

                  final prefs = await SharedPreferences.getInstance();
                  if (newName.isNotEmpty) {
                    await prefs.setString('userName', newName);
                  }

                  setState(() {
                    if (newName.isNotEmpty) _userName = newName;
                  });

        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ التعديلات بنجاح')),
        );
    } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل في التحديث: $e')),
                  );
                }
              } else {
                Navigator.of(context).pop(); // لم يتم تغيير شيء
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );
}
Future<void> _pickAndUploadProfileImage() async {
  if (_controlUserId == null) return;

  final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
  if (picked == null) return;

  final file = File(picked.path);
  try {
    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_images/$_controlUserId.jpg');

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

        await FirebaseFirestore.instance
        .collection('controlUsers')
        .doc(_controlUserId)
        .update({'profileImageUrl': url});

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profileImageUrl', url);

        setState(() {
      _profileImageUrl = url;
        });

          ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث الصورة')),
          );
      } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('فشل في رفع الصورة: $e')),
    );
  }
}
Future<void> _loadUserName() async {
  final prefs = await SharedPreferences.getInstance();
  String? name = prefs.getString('userName');
  String? img = prefs.getString('profileImageUrl');
  final controlUserId = prefs.getString('userId');

  if ((name == null || name.isEmpty) || (img == null || img.isEmpty)) {
    if (controlUserId != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('controlUsers')
            .doc(controlUserId)
            .get();
        if (snap.exists) {
          name ??= snap.data()?['userName']?.toString();
          img ??= snap.data()?['profileImageUrl']?.toString();

          if (name != null && name.isNotEmpty) {
            await prefs.setString('userName', name);
          }
          if (img != null && img.isNotEmpty) {
            await prefs.setString('profileImageUrl', img);
          }
        }
      } catch (_) {}
    }
  }

      if (!mounted) return;
      setState(() {
    _controlUserId = controlUserId;
    _userName = name;
    _profileImageUrl = img;
  });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text(
            'لوحة تحكم الكنترول',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          elevation: 0,
          centerTitle: true,
          
         
         
        ),
       drawer: Drawer(
  child: SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ✅ رأس الدروار بصورة واسم المستخدم
        Container(
          color: const Color(0xFF0D47A1),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickAndUploadProfileImage,
                child: CircleAvatar(
                  radius: 45, // حجم أكبر
                  backgroundColor: Colors.white,
                  backgroundImage: (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                      ? NetworkImage(_profileImageUrl!)
                      : null,
                  child: (_profileImageUrl == null || _profileImageUrl!.isEmpty)
                      ? const Icon(Icons.person, color: Color(0xFF0D47A1), size: 40)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _userName ?? 'المستخدم',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        ),
        // ✅ زر الملف الشخصي
ListTile(
  leading: const Icon(Icons.person, color: Color(0xFF0D47A1)),
  title: const Text('الملف الشخصي'),
  onTap: () {
    Navigator.pop(context); // يغلق الدروار
    _showEditProfileDialog(); // يظهر الديالوق
  },
),



            // 🟪 باقي العناصر يمكن إضافتها هنا
            const Spacer(),

        // ✅ زر تسجيل الخروج داخل إطار
        ListTile(
          leading: const Icon(Icons.logout, color: Color(0xFF0D47A1)),
          title: const Text('تسجيل الخروج'),
          onTap: () {
            Navigator.pop(context); // يغلق الدروار
            _logout(); // ينفذ تسجيل الخروج
          },
        ),
        const SizedBox(height: 24), // هامش سفلي بسيط
      ],
    ),
  ),
), 
        
        body: Padding(
          padding: const EdgeInsets.all(5),
                child: GridView.count(
            crossAxisCount: 1,
            childAspectRatio: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
                    children: [
                    _buildHomeCard(
                      title: 'البيانات المركزية',
  lottieAsset: 'assets/lottie/Red Network Globe.json',
  onTap: () {
    Navigator.push(
                          context,
      MaterialPageRoute(builder: (context) => const CentralDataScreen()),
    );
                          },
                    ),
                    _buildHomeCard(
                      lottieAsset: 'assets/lottie/Connect.json', 
                title: 'المستخدمين',
                
                
                      onTap: () {
                            _showReceptionStaffList();
                          },
                    ),
                    _buildHomeCard(
                      lottieAsset: 'assets/lottie/registro.json',
                      title: 'طلبات العيادة المنزلية',
                      onTap: () {
                            _showSampleRequests();
                          },
                    ),
                    _buildHomeCard(
                      lottieAsset: 'assets/lottie/Call Center Support Lottie Animation.json',
                      title: 'أرقام الدعم الفني',
                      onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SupportNumbersScreen(),
                              ),
                            );
                          },
                    ),
                    _buildHomeCard(
                      lottieAsset: 'assets/lottie/search users.json',
                      title: 'إحصائيات المستخدمين',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const UsersStatsScreen(),
                          ),
                        );
                      },
                      ),
                    _buildHomeCard(
                      lottieAsset: 'assets/lottie/Notifications.json',
                      title: 'الإشعارات',
                      
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ControlNotificationsScreen(),
                          ),
                        );
                      },
                      ),
                    _buildHomeCard(
                      lottieAsset: 'assets/lottie/Home Icon Loading.json',
                      title: 'مراكز العيادة المنزلية',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HomeClinicCentersScreen(),
                          ),
                        );
                      },
                      ),
            ],
          ),
        ),
      ),
    );
  }
}
