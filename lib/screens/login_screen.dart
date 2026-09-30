import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hospital_admin_app/screens/call_center_screen.dart';
import 'package:hospital_admin_app/screens/control_panel_screen.dart';
import 'package:hospital_admin_app/screens/dashboard_screen.dart';
import 'package:hospital_admin_app/screens/doctor_user_screen.dart';
import 'package:hospital_admin_app/screens/reception_staff_screen.dart';
import 'package:local_auth/local_auth.dart';
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
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _biometricUsersKey = 'biometric_users';
  bool _biometricAvailable = false;
  bool _isBiometricChecking = false;
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _getVersionInfo();
    _checkBiometric();
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

  Future<void> _checkBiometric() async {
    if (_isBiometricChecking) return;

    _isBiometricChecking = true;

    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!mounted) return;

      setState(() {
        _biometricAvailable = canCheckBiometrics && isDeviceSupported;
      });

      if (!_biometricAvailable) return;

      final biometricUsers = await _getBiometricUsers();
      await _secureStorage.delete(key: 'biometric_enabled');
      await _secureStorage.delete(key: 'biometric_email');
      await _secureStorage.delete(key: 'biometric_password');

      if (biometricUsers.isNotEmpty) {
        await _biometricLogin();
      }
    } catch (e) {
      print('Biometric check error: $e');

      if (!mounted) return;

      setState(() {
        _biometricAvailable = false;
      });
    } finally {
      _isBiometricChecking = false;
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
    // =========================================================
    // موظف الاستقبال
    // =========================================================
    if (data['userType'] == 'reception') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => ReceptionStaffScreen(
                centerId: centerId,
                centerName: centerName,
                userId: FirebaseAuth.instance.currentUser!.uid,
                userName: data['displayName'] ?? '',
              ),
        ),
      );
      return;
    }
    // =========================================================
    // الطبيب
    // =========================================================
    if (data['userType'] == 'doctor') {
      final doctorId = data['doctorId']?.toString() ?? '';
      final doctorName = data['doctorName']?.toString() ?? '';

      if (doctorId.isEmpty) {
        print("❌ Doctor ID is missing for this user");
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => DoctorUserScreen(
                doctorId: doctorId,
                centerId: centerId,
                centerName: centerName,
                doctorName: doctorName,
              ),
        ),
      );
      return;
    }

    print("❌ Unknown user role: $role");
  }

  Future<List<Map<String, dynamic>>> _getBiometricUsers() async {
    final data = await _secureStorage.read(key: _biometricUsersKey);

    if (data == null || data.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(data);

      if (decoded is! List) {
        return [];
      }

      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('Biometric users read error: $e');
      return [];
    }
  }

  Future<void> _saveBiometricUsers(List<Map<String, dynamic>> users) async {
    await _secureStorage.write(
      key: _biometricUsersKey,
      value: jsonEncode(users),
    );
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

      if (_biometricAvailable) {
        final enableBiometric = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: const Text(
                'تفعيل تسجيل الدخول بالبصمة',
                textAlign: TextAlign.right,
              ),
              content: const Text(
                'هل تريد تفعيل تسجيل الدخول بالبصمة في المرات القادمة؟',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.black),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  child: const Text(
                    'ليس الآن',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  child: const Text(
                    'تفعيل البصمة',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            );
          },
        );

        if (enableBiometric == true) {
          final authenticated = await _localAuth.authenticate(
            localizedReason: 'تحقق من بصمتك لتفعيل تسجيل الدخول بالبصمة',
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
              useErrorDialogs: true,
            ),
          );

          if (authenticated) {
            final biometricUsers = await _getBiometricUsers();

            // حذف الحساب إذا كان محفوظًا مسبقًا
            biometricUsers.removeWhere((item) => item['uid'] == user.uid);

            // إضافة الحساب الحالي
            biometricUsers.add({
              'uid': user.uid,
              'email': _emailController.text.trim(),
              'password': _passwordController.text.trim(),
              'name': data['displayName'] ?? '',
            });

            await _saveBiometricUsers(biometricUsers);
          }
        }
      }

      if (!mounted) return;

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

  Future<void> _biometricLogin() async {
    if (!_biometricAvailable) return;

    try {
      final biometricUsers = await _getBiometricUsers();

      if (biometricUsers.isEmpty) {
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'استخدم بصمتك لتسجيل الدخول',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!authenticated) return;

      Map<String, dynamic>? selectedUser;

      if (biometricUsers.length == 1) {
        selectedUser = biometricUsers.first;
      } else {
        selectedUser = await _showBiometricUsersDialog(biometricUsers);
      }

      if (selectedUser == null) {
        return;
      }

      final email = selectedUser['email']?.toString();
      final password = selectedUser['password']?.toString();

      if (email == null || password == null) {
        return;
      }
      setState(() => _isLoading = true);

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('فشل تسجيل الدخول');
      }

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
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'فشل تسجيل الدخول')));
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<Map<String, dynamic>?> _showBiometricUsersDialog(
    List<Map<String, dynamic>> users,
  ) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('اختر الحساب', textAlign: TextAlign.right),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final user = users[index];

                final name = user['name']?.toString() ?? '';
                final email = user['email']?.toString() ?? '';

                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(
                    name.isNotEmpty ? name : email,
                    textAlign: TextAlign.right,
                  ),
                  subtitle: Text(email, textAlign: TextAlign.right),
                  onTap: () {
                    Navigator.pop(context, user);
                  },
                );
              },
            ),
          ),
        );
      },
    );
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
                const Color.fromARGB(255, 71, 216, 185).withOpacity(0.1),
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
                              color: const Color.fromARGB(
                                255,
                                34,
                                96,
                                129,
                              ).withOpacity(0.08),
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
                                      'assets/images/icon.png',
                                      height: 120,
                                    ),
                                  ),

                                  const SizedBox(height: 18),

                                  const Text(
                                    'تطبيق الإدارة',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
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
                                        color: Color.fromARGB(255, 34, 96, 129),
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
                                          color: Color.fromARGB(
                                            255,
                                            34,
                                            96,
                                            129,
                                          ),
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
                                        color: Color.fromARGB(255, 34, 96, 129),
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
                                          color: Color.fromARGB(
                                            255,
                                            34,
                                            96,
                                            129,
                                          ),
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
