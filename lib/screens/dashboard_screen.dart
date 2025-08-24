import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hospital_admin_app/screens/login_screen.dart';
import 'package:hospital_admin_app/screens/admin_doctors_screen.dart';
import 'package:hospital_admin_app/screens/admin_specialties_screen.dart';
import 'package:hospital_admin_app/screens/admin_doctors_schedule_screen.dart';
import 'package:hospital_admin_app/screens/admin_bookings_screen.dart';
import 'package:hospital_admin_app/screens/admin_users_screen.dart';
import 'package:hospital_admin_app/screens/admin_insurance_companies_screen.dart';
import 'package:hospital_admin_app/screens/admin_reports_screen.dart';
import 'package:hospital_admin_app/screens/about_screen.dart';


class DashboardScreen extends StatefulWidget {
  final String? centerId;
  final String? centerName;
  final bool fromControlPanel;

  const DashboardScreen({
    super.key,
    this.centerId,
    this.centerName,
    this.fromControlPanel = false,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? currentUserName;
  String? userType;
  String? displayCenterName;
  String? displayCenterId;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserName = prefs.getString('userName');
      userType = prefs.getString('userType');
      // استخدام widget.centerName أولاً، وإذا كان فارغاً استخدم القيمة المحفوظة
      displayCenterName = widget.centerName ?? prefs.getString('centerName') ?? 'مركز طبي';
      displayCenterId = widget.centerId ?? prefs.getString('centerId');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'لوحة تحكم $displayCenterName',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF2FBDAF),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // تعطيل الزر التلقائي
        leading: widget.fromControlPanel
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  // حذف متغير fromControlPanel
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('fromControlPanel');
                  Navigator.of(context).pop();
                },
                tooltip: 'رجوع إلى صفحة الكنترول',
              )
            : IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  // إذا جاء من تسجيل الدخول العادي، امسح البيانات واذهب لصفحة تسجيل الدخول
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
                tooltip: 'تسجيل الخروج',
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      
                      Text(
                        'مرحباً بك في $displayCenterName',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2FBDAF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'إدارة عمليات المستشفى',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Grid section
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      _buildDashboardCard(
                        context,
                        'الأطباء',
                        Icons.medical_services,
                        const Color(0xFF2FBDAF),
                        () {
                          if (displayCenterId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminDoctorsScreen(
                                  centerId: displayCenterId!,
                                  centerName: displayCenterName ?? 'مركز طبي',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى تسجيل الدخول أولاً'),
                                backgroundColor: Color(0xFF2FBDAF),
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'التخصصات',
                        Icons.medical_services,
                        const Color(0xFF2FBDAF),
                        () {
                          if (displayCenterId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminSpecialtiesScreen(
                                  centerId: displayCenterId!,
                                  centerName: displayCenterName ?? 'مركز طبي',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى تسجيل الدخول أولاً'),
                                backgroundColor: Color(0xFF2FBDAF),
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'شركات التأمين',
                        Icons.security,
                        const Color(0xFF2FBDAF),
                        () {
                          if (displayCenterId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminInsuranceCompaniesScreen(
                                  centerId: displayCenterId!,
                                  centerName: displayCenterName ?? 'مركز طبي',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى تسجيل الدخول أولاً'),
                                backgroundColor: Color(0xFF2FBDAF),
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'جدول الأطباء',
                        Icons.schedule,
                        const Color(0xFF2FBDAF),
                        () {
                          if (displayCenterId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminDoctorsScheduleScreen(
                                  centerId: displayCenterId!,
                                  centerName: displayCenterName ?? 'مركز طبي',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى تسجيل الدخول أولاً'),
                                backgroundColor: Color(0xFF2FBDAF),
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'المستخدمين',
                        Icons.people,
                        const Color(0xFF2FBDAF),
                        () {
                          if (displayCenterId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminUsersScreen(
                                  centerId: displayCenterId!,
                                  centerName: displayCenterName ?? 'مركز طبي',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى تسجيل الدخول أولاً'),
                                backgroundColor: Color(0xFF2FBDAF),
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'الحجوزات',
                        Icons.calendar_today,
                        const Color(0xFF2FBDAF),
                        () {
                          if (displayCenterId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminBookingsScreen(
                                  centerId: displayCenterId!,
                                  centerName: displayCenterName ?? 'مركز طبي',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى تسجيل الدخول أولاً'),
                                backgroundColor: Color(0xFF2FBDAF),
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'التقارير',
                        Icons.analytics,
                        const Color(0xFF2FBDAF),
                        () {
                          if (displayCenterId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminReportsScreen(
                                  centerId: displayCenterId!,
                                  centerName: displayCenterName ?? 'مركز طبي',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى تسجيل الدخول أولاً'),
                                backgroundColor: Color(0xFF2FBDAF),
                              ),
                            );
                          }
                        },
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

  Widget _buildDashboardCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withAlpha(26),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                icon,
                size: 30,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط للوصول',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
