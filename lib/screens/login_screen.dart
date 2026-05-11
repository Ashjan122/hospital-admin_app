import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/call_center_screen.dart';
import 'package:hospital_admin_app/screens/control_panel_screen.dart';
import 'package:hospital_admin_app/screens/dashboard_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
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
      print("Version error: $e");
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ✅ البحث بـ uid field داخل الدوكيومنت
  Future<Map<String, dynamic>> _getUserData(String uid) async {
    try {
      final query =
          await FirebaseFirestore.instance
              .collection('users')
              .where('uid', isEqualTo: uid)
              .limit(1)
              .get();

      if (query.docs.isEmpty) {
        print("❌ No user found with uid field: $uid");
        throw Exception('بيانات المستخدم غير موجودة');
      }

      return query.docs.first.data();
    } catch (e) {
      print("🔥 Firestore error: $e");
      rethrow;
    }
  }

  // ✅ التحقق من تسجيل الدخول
  Future<void> _checkLoginStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final data = await _getUserData(user.uid);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userId', user.uid);
      await prefs.setString('userName', data['displayName'] ?? '');
      await prefs.setString('userType', data['userType'] ?? '');
      await prefs.setString('role', data['role'] ?? '');
      await prefs.setString('centerId', data['facilityId'] ?? '');
      await prefs.setString('centerName', data['displayName'] ?? '');

      _navigateUser(data);
    } catch (e) {
      print("Check login error: $e");
    }
  }

  // ✅ التنقل حسب الدور
  void _navigateUser(Map<String, dynamic> data) {
    final role = data['role'];
    final userType = data['userType'];

    final centerId = data['facilityId'] ?? '';
    final centerName = data['displayName'] ?? '';

    print("User role: $role | userType: $userType");

    if (role == 'control') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ControlPanelScreen()),
      );
      return;
    }

    if (userType == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => DashboardScreen(
                centerId: centerId,
                centerName: centerName,
                fromControlPanel: false,
              ),
        ),
      );
      return;
    }

    if (userType == 'callcenter') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => CallCenterScreen(
                centerId: centerId,
                centerName: centerName,
                userId: FirebaseAuth.instance.currentUser!.uid,
                userName: data['displayName'] ?? '',
              ),
        ),
      );
      return;
    }

    print("❌ Unknown user type");
  }

  // ✅ تسجيل الدخول
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = credential.user;
      if (user == null) throw Exception('فشل تسجيل الدخول');

      print("Firebase UID: ${user.uid}");

      final data = await _getUserData(user.uid);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userId', user.uid);
      await prefs.setString('userName', data['displayName'] ?? '');
      await prefs.setString('userType', data['userType'] ?? '');
      await prefs.setString('role', data['role'] ?? '');
      await prefs.setString('centerId', data['facilityId'] ?? '');
      await prefs.setString('centerName', data['displayName'] ?? '');

      if (!mounted) return;
      setState(() => _isLoading = false);

      _navigateUser(data);
    } on FirebaseAuthException catch (e) {
      print("Auth error: ${e.code}");

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'خطأ')));
    } catch (e) {
      print("General error: $e");

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
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
                const Color.fromARGB(255, 156, 208, 235).withOpacity(0.1),
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
                          padding: const EdgeInsets.all(32.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                Image.asset(
                                  'assets/images/logo.png',
                                  height: 120,
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'إدارة المراكز الطبية',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                TextFormField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.email),
                                  ),
                                  validator:
                                      (v) =>
                                          v!.isEmpty
                                              ? 'أدخل البريد الإلكتروني'
                                              : null,
                                ),

                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: !_isPasswordVisible,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _isPasswordVisible
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isPasswordVisible =
                                              !_isPasswordVisible;
                                        });
                                      },
                                    ),
                                  ),
                                  validator:
                                      (v) =>
                                          v!.isEmpty
                                              ? 'أدخل كلمة المرور'
                                              : null,
                                ),

                                const SizedBox(height: 24),

                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2FBDAF),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child:
                                        _isLoading
                                            ? const CircularProgressIndicator(
                                              color: Colors.white,
                                            )
                                            : const Text(
                                                'تسجيل الدخول',
                                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    padding: const EdgeInsets.all(16),
                    child: Text(_version),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
