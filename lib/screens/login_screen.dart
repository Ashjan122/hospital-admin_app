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

  Future<Map<String, dynamic>> _getUserData(String uid) async {
    try {
      // البحث مباشرة باستخدام UID كـ Document ID
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!doc.exists) {
        print("❌ No user document found: users/$uid");
        throw Exception('بيانات المستخدم غير موجودة');
      }

      final data = doc.data();

      if (data == null) {
        throw Exception('بيانات المستخدم فارغة');
      }

      return data;
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

    final centerId = data['facilityId'] ?? '';
    final centerName = data['facilityName'] ?? '';

    print("User role: $role");

    // =========================================================
    // Super Admin → الكنترول
    // =========================================================
    if (role == 'superadmin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ControlPanelScreen()),
      );
      return;
    }

    // =========================================================
    // مشرف مرفق
    // =========================================================
    if (data['userType'] == 'admin') {
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

    // =========================================================
    // كول سنتر
    // =========================================================
    if (data['userType'] == 'callcenter') {
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

    print("❌ Unknown user role: $role");
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
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Card(
                          color: const Color(0xFFFDFEFF),
                          elevation: 6,
                          shadowColor: const Color(
                            0xFF7AAFC4,
                          ).withOpacity(0.18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: const Color(0xFF2FBDAF).withOpacity(0.08),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(32, 30, 32, 30),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // =========================
                                  // Logo
                                  // =========================
                                  Center(
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      height: 120,
                                    ),
                                  ),

                                  const SizedBox(height: 18),

                                  const Text(
                                    'إدارة المراكز الطبية',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  Text(
                                    'تسجيل الدخول',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),

                                  const SizedBox(height: 28),

                                  // =========================
                                  // Email
                                  // =========================
                                  const Text(
                                    'البريد الإلكتروني',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText: 'أدخل البريد الإلكتروني',
                                      hintStyle: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 14,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.email_outlined,
                                        color: Color(0xFF2FBDAF),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF2FBDAF),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'أدخل البريد الإلكتروني';
                                      }

                                      if (!v.contains('@')) {
                                        return 'أدخل بريد إلكتروني صحيح';
                                      }

                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 20),

                                  // =========================
                                  // Password
                                  // =========================
                                  const Text(
                                    'كلمة المرور',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: !_isPasswordVisible,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) {
                                      if (!_isLoading) {
                                        _login();
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'أدخل كلمة المرور',
                                      hintStyle: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 14,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Color(0xFF2FBDAF),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: Colors.grey[500],
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isPasswordVisible =
                                                !_isPasswordVisible;
                                          });
                                        },
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF2FBDAF),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'أدخل كلمة المرور';
                                      }

                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 28),

                                  // =========================
                                  // Login Button
                                  // =========================
                                  SizedBox(
                                    height: 52,
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF2FBDAF,
                                        ),
                                        foregroundColor: Colors.white,
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      child:
                                          _isLoading
                                              ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Colors.white,
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
                ),

                if (_version.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _version,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
