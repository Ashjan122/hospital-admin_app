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
import 'package:hospital_admin_app/screens/admin_lab_results_screen.dart';
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
        title: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'لوحة التحكم',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              Text(
                displayCenterName ?? 'مركز طبي',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
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
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const AboutScreen()),
                  );
                },
                tooltip: 'حول التطبيق',
              ),
        actions: [
          IconButton(
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
                      // إظهار بطاقة نتيجة المختبر فقط في "مركز الرومي الطبي" وليس "مركز الرومي لطب الاسنان"
                      if (((displayCenterName ?? '').toLowerCase().contains('الرومي') ||
                              (displayCenterName ?? '').toLowerCase().contains('roomy') ||
                              (displayCenterName ?? '').toLowerCase().contains('alroomy')) &&
                          ((displayCenterName ?? '').toLowerCase().contains('طبي') ||
                              (displayCenterName ?? '').toLowerCase().contains('medical')) &&
                          !((displayCenterName ?? '').toLowerCase().contains('اسنان') ||
                              (displayCenterName ?? '').toLowerCase().contains('الاسنان') ||
                              (displayCenterName ?? '').toLowerCase().contains('أسنان') ||
                              (displayCenterName ?? '').toLowerCase().contains('الأسنان') ||
                              (displayCenterName ?? '').toLowerCase().contains('dental')))
                        _buildDashboardCard(
                          context,
                          'نتيجة المختبر',
                          Icons.science,
                          const Color(0xFF2FBDAF),
                          () {
                            if (displayCenterId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminLabResultsScreen(
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
          color: const Color(0xFF2FBDAF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2FBDAF)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(200),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                icon,
                size: 30,
                color: const Color(0xFF2FBDAF),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
