import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/dashboard_screen.dart';
import 'package:hospital_admin_app/screens/control_panel_screen.dart';
import 'package:hospital_admin_app/screens/reception_staff_screen.dart';
import 'package:hospital_admin_app/screens/lab_dashboard_screen.dart';
// import 'package:hospital_admin_app/screens/doctor_bookings_screen.dart';
import 'package:hospital_admin_app/screens/doctor_user_screen.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
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
          // Control user is logged in
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const ControlPanelScreen(),
            ),
          );
        } else if (userType == 'admin' && centerId != null && centerName != null) {
          // Admin is logged in
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
          // Reception staff is logged in
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
          // Doctor is logged in
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
        }
    }
  }

  Future<void> _saveLoginData(String userType, {
    String? centerId, 
    String? centerName, 
    String? userEmail, 
    String? userName, 
    String? userId,
    String? doctorId,
    String? doctorName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userType', userType);
    
    if (centerId != null) await prefs.setString('centerId', centerId);
    if (centerName != null) await prefs.setString('centerName', centerName);
    if (userEmail != null) await prefs.setString('userEmail', userEmail);
    if (userName != null) await prefs.setString('userName', userName);
    if (userId != null) await prefs.setString('userId', userId);
    if (doctorId != null) await prefs.setString('doctorId', doctorId);
    if (doctorName != null) await prefs.setString('doctorName', doctorName);
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Check if control credentials (super admin) from database
        final controlQuery = await FirebaseFirestore.instance
            .collection('controlUsers')
            .where('userName', isEqualTo: _usernameController.text.trim())
            .get();

        if (controlQuery.docs.isNotEmpty) {
          final controlDoc = controlQuery.docs.first;
          final controlData = controlDoc.data();
          final controlPassword = controlData['userPassword'] ?? '';

          if (controlPassword == _passwordController.text) {
            // Control login successful
            final controlUserName = controlData['userName'] ?? _usernameController.text.trim();
            await _saveLoginData('control', userName: controlUserName);
            
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const ControlPanelScreen(),
                ),
              );
            }
            return;
          }
        }
        
        // First, check if it's a user login
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('userName', isEqualTo: _usernameController.text.trim())
            .get();

        if (userQuery.docs.isNotEmpty) {
          // Found a user with this username
          final userDoc = userQuery.docs.first;
          final userData = userDoc.data();
          final userPassword = userData['userPassword'] ?? '';

          if (userPassword == _passwordController.text) {
            // User login successful
            final userId = userDoc.id;
            final userName = userData['userName'] ?? '';
            final centerId = userData['centerId'] ?? '';
            final centerName = userData['centerName'] ?? '';
            final userType = userData['userType'] ?? 'user';
            final doctorId = userData['doctorId'] ?? '';
            final doctorName = userData['doctorName'] ?? '';

            // Update user's last login/seen timestamps for stats
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .set({
                'lastLoginAt': FieldValue.serverTimestamp(),
                'lastSeenAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e) {
              // Non-fatal
            }

            // Save user login data
            await _saveLoginData(userType, 
              centerId: centerId, 
              centerName: centerName,
              userEmail: userName,
              userName: userName,
              userId: userId,
              doctorId: doctorId,
              doctorName: doctorName,
            );

            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              
              // Redirect based on user type
              if (userType == 'admin') {
                final prefs = await SharedPreferences.getInstance();
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
              } else if (userType == 'reception') {
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
              } else if (userType == 'doctor') {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => DoctorUserScreen(
                      doctorId: doctorId,
                      centerId: centerId,
                      centerName: centerName,
                      doctorName: doctorName.isNotEmpty ? doctorName : userName,
                    ),
                  ),
                );
              } else {
                // Default to dashboard for other user types
                final prefs = await SharedPreferences.getInstance();
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
              }
            }
            return; // Exit the function after successful user login
          } else {
            // Invalid user password
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('كلمة المرور غير صحيحة'),
                backgroundColor: Colors.red,
              ),
            );
            return; // Exit the function
          }
        }

        // If not a user login, check if admin credentials (center ID or name)
        // Check if username is a center ID or name
        final centerQuery = await FirebaseFirestore.instance
            .collection('medicalFacilities')
            .where('available', isEqualTo: true)
            .get();

        bool isAdminLogin = false;
        String centerId = '';
        String centerName = '';
        String centerPassword = '';

        for (var doc in centerQuery.docs) {
          final centerData = doc.data();
          final centerDocId = doc.id;
          final centerDocName = centerData['name'] ?? '';

          // Check if username matches center ID or name (case insensitive)
          if (_usernameController.text.trim() == centerDocId || 
              _usernameController.text.trim().toLowerCase() == centerDocName.toLowerCase() ||
              _usernameController.text.trim().toLowerCase().contains(centerDocName.toLowerCase()) ||
              centerDocName.toLowerCase().contains(_usernameController.text.trim().toLowerCase())) {
            isAdminLogin = true;
            centerId = centerDocId;
            centerName = centerDocName;
            centerPassword = centerData['adminPassword'] ?? '12345678'; // Default password if not set
            break;
          }
        }

        if (isAdminLogin) {
          // Check if password matches
          if (_passwordController.text == centerPassword) {
            // Save admin login data
            await _saveLoginData('admin', centerId: centerId, centerName: centerName);
            
            // Admin login - redirect to dashboard with center info
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              final prefs = await SharedPreferences.getInstance();
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
            }
          } else {
            // Invalid password for center
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('كلمة المرور غير صحيحة'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          // Try lab login: by lab name and password (default 123456)
          final labQuery = await FirebaseFirestore.instance
              .collection('labToLap')
              .where('name', isEqualTo: _usernameController.text.trim())
              .limit(1)
              .get();

          if (labQuery.docs.isNotEmpty) {
            final labDoc = labQuery.docs.first;
            final labData = labDoc.data();
            final labPassword = labData['password']?.toString() ?? '123456';

            if (_passwordController.text == labPassword) {
              // Save session as lab
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isLoggedIn', true);
              await prefs.setString('userType', 'lab');
              await prefs.setString('labId', labDoc.id);
              await prefs.setString('labName', labData['name']?.toString() ?? '');

              if (mounted) {
                setState(() { _isLoading = false; });
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => LabDashboardScreen(
                      labId: labDoc.id,
                      labName: labData['name']?.toString() ?? '',
                    ),
                  ),
                );
              }
              return;
            } else {
              setState(() { _isLoading = false; });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('كلمة المرور غير صحيحة'), backgroundColor: Colors.red),
              );
              return;
            }
          } else {
            // Not a valid center or lab, show error
            setState(() { _isLoading = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('الاسم غير موجود'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2FBDAF).withOpacity(0.1), // لون أزرق أخضر فاتح
              Colors.grey[50]!, // رمادي فاتح جداً
            ],
          ),
        ),
        child: SafeArea(
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo
                        Container(
                          width: 120,
                          height: 120,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Title
                        const Text(
                          'إدارة المراكز الطبية',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        
                        const Text(
                          'تسجيل دخول الإدارة',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        
                        // Username field
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'اسم المركز أو اسم المستخدم',
                            hintText: 'أدخل اسم المركز أو اسم المستخدم',
                            prefixIcon: const Icon(Icons.business, color: Color(0xFF2FBDAF)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF2FBDAF),
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال اسم المركز أو اسم المستخدم';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // Password field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            hintText: 'أدخل كلمة المرور',
                            prefixIcon: const Icon(Icons.lock, color: Color(0xFF2FBDAF)),
                                                          suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  color: const Color(0xFF2FBDAF),
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
                                color: Color(0xFF2FBDAF),
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
                        
                        // Login button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF2FBDAF),
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
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
    );
  }
}


