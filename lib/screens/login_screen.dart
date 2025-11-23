import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/dashboard_screen.dart';
import 'package:hospital_admin_app/screens/control_panel_screen.dart';
import 'package:hospital_admin_app/screens/reception_staff_screen.dart';
import 'package:hospital_admin_app/screens/doctor_user_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hospital_admin_app/screens/call_center_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _getVersionInfo();
  }

  Future<void> _getVersionInfo() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = 'رقم الإصدار ${packageInfo.version}';
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _version = '';
    });
  }
}


  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final userType = prefs.getString('userType');
    final centerId = prefs.getString('centerId');
    final centerName = prefs.getString('centerName');

    if (isLoggedIn) {
      if (userType == 'control') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ControlPanelScreen()),
        );
      } else if (userType == 'admin' && centerId != null && centerName != null) {
        final fromControlPanel = prefs.getBool('fromControlPanel') ?? false;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => DashboardScreen(
              centerId: centerId,
              centerName: centerName,
              fromControlPanel: fromControlPanel,
            ),
          ),
        );
      } else if (userType == 'reception' && centerId != null && centerName != null) {
        final userId = prefs.getString('userId') ?? '';
        final userName = prefs.getString('userName') ?? '';
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ReceptionStaffScreen(
              centerId: centerId,
              centerName: centerName,
              userId: userId,
              userName: userName,
            ),
          ),
        );
      } else if (userType == 'doctor' && centerId != null && centerName != null) {
        final userName = prefs.getString('userName') ?? '';
        final doctorId = prefs.getString('doctorId') ?? '';
        final doctorName = prefs.getString('doctorName') ?? userName;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => DoctorUserScreen(
              doctorId: doctorId,
              centerId: centerId,
              centerName: centerName,
              doctorName: doctorName,
            ),
          ),
        );
      } else if (userType == 'callCenter' && centerId != null && centerName != null) {
        final userId = prefs.getString('userId') ?? '';
        final userName = prefs.getString('userName') ?? '';
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CallCenterScreen(
              centerId: centerId,
              centerName: centerName,
              userId: userId,
              userName: userName,
            ),
          ),
        );
      }
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // ================================================================
      // 🔥 1️⃣ تسجيل دخول مستخدم CONTROL – بعد التعديل
      // ================================================================
      final controlQuery = await FirebaseFirestore.instance
          .collection('controlUsers')
          .where('userName', isEqualTo: _usernameController.text.trim())
          .get();

      if (controlQuery.docs.isNotEmpty) {
        final controlDoc = controlQuery.docs.first;
        final controlData = controlDoc.data();
        final controlPassword = controlData['userPassword'] ?? '';

        if (controlPassword == _passwordController.text) {
          final controlUserName =
              controlData['userName'] ?? _usernameController.text.trim();

          final controlUserId = controlDoc.id;
          final controlImage = controlData['profileImageUrl'] ?? '';

          final prefs = await SharedPreferences.getInstance();

          await prefs.setBool('isLoggedIn', true);
          await prefs.setString('userType', 'control');
          await prefs.setString('userName', controlUserName);
          await prefs.setString('control_user_id', controlUserId);

          if (controlImage.isNotEmpty) {
            await prefs.setString('profileImageUrl', controlImage);
          }

          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const ControlPanelScreen()),
            );
          }
          return;
        }
      }

      // ================================================================
      // 2️⃣ باقي المستخدمين كما هو بدون تعديل
      // ================================================================

      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('userName', isEqualTo: _usernameController.text.trim())
          .get();

      if (userQuery.docs.isNotEmpty) {
        final userDoc = userQuery.docs.first;
        final userData = userDoc.data();
        final userPassword = userData['userPassword'] ?? '';

        if (userPassword == _passwordController.text) {
          final userId = userDoc.id;
          final userName = userData['userName'] ?? '';
          final centerId = userData['centerId'] ?? '';
          final centerName = userData['centerName'] ?? '';
          final userType = userData['userType'] ?? 'user';
          final doctorId = userData['doctorId'] ?? '';
          final doctorName = userData['doctorName'] ?? '';

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .set({
            'lastLoginAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setString('userType', userType);
          await prefs.setString('userName', userName);
          await prefs.setString('userId', userId);
          await prefs.setString('centerId', centerId);
          await prefs.setString('centerName', centerName);
          await prefs.setString('doctorId', doctorId);
          await prefs.setString('doctorName', doctorName);

          if (!mounted) return;
          setState(() => _isLoading = false);

          if (userType == 'admin') {
            final fromControlPanel =
                prefs.getBool('fromControlPanel') ?? false;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DashboardScreen(
                  centerId: centerId,
                  centerName: centerName,
                  fromControlPanel: fromControlPanel,
                ),
              ),
            );
          } else if (userType == 'reception') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ReceptionStaffScreen(
                  centerId: centerId,
                  centerName: centerName,
                  userId: userId,
                  userName: userName,
                ),
              ),
            );
          } else if (userType == 'doctor') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DoctorUserScreen(
                  doctorId: doctorId,
                  centerId: centerId,
                  centerName: centerName,
                  doctorName: doctorName.isNotEmpty ? doctorName : userName,
                ),
              ),
            );
          } else if (userType == 'callCenter') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CallCenterScreen(
                  centerId: centerId,
                  centerName: centerName,
                  userId: userId,
                  userName: userName,
                ),
              ),
            );
          }
          return;
        }
      }

      // ================================================================
      // 3️⃣ دخول أدمن المراكز
      // ================================================================
      final centerQuery = await FirebaseFirestore.instance
          .collection('medicalFacilities')
          .where('available', isEqualTo: true)
          .get();

      bool isAdminLogin = false;
      String centerId = '';
      String centerName = '';
      String centerPassword = '';

      for (var doc in centerQuery.docs) {
        final data = doc.data();
        final id = doc.id;
        final name = data['name'] ?? '';

        if (_usernameController.text.trim() == id ||
            _usernameController.text.trim().toLowerCase() == name.toLowerCase() ||
            _usernameController.text.trim().toLowerCase().contains(name.toLowerCase()) ||
            name.toLowerCase().contains(_usernameController.text.trim().toLowerCase())) {
          isAdminLogin = true;
          centerId = id;
          centerName = name;
          centerPassword = data['adminPassword'] ?? '12345678';
          break;
        }
      }

      if (isAdminLogin) {
        if (_passwordController.text == centerPassword) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setString('userType', 'admin');
          await prefs.setString('centerId', centerId);
          await prefs.setString('centerName', centerName);

          final fromControlPanel =
              prefs.getBool('fromControlPanel') ?? false;

          if (!mounted) return;
          setState(() => _isLoading = false);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardScreen(
                centerId: centerId,
                centerName: centerName,
                fromControlPanel: fromControlPanel,
              ),
            ),
          );
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('كلمة المرور غير صحيحة'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الاسم غير موجود'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromARGB(255, 156, 208, 235).withOpacity(0.1),
                Colors.grey[50]!,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding:  EdgeInsets.all(32.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'إدارة المراكز الطبية',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'اسم المستخدم',
                              hintText: 'أدخل اسم المستخدم',
                              prefixIcon: const Icon(Icons.person, color: Color.fromARGB(255, 156, 208, 235)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color.fromARGB(255, 156, 208, 235),
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'يرجى إدخال اسم المستخدم';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              hintText: 'أدخل كلمة المرور',
                              prefixIcon: const Icon(Icons.lock, color: Color.fromARGB(255, 156, 208, 235)),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: const Color.fromARGB(255, 156, 208, 235),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color.fromARGB(255, 156, 208, 235),
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'يرجى إدخال كلمة المرور';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromARGB(255, 156, 208, 235),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'تسجيل الدخول',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
                ),
                if (_version.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _version,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
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
}
