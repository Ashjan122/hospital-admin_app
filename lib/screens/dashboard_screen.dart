import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/medical_centers_screen.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hospital_admin_app/services/presence_service.dart';
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
import 'package:hospital_admin_app/screens/control_panel_screen.dart';


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
    final savedUserId = prefs.getString('userId') ?? '';
    final savedUserType = prefs.getString('userType') ?? '';
    setState(() {
      currentUserName = prefs.getString('userName');
      userType = savedUserType;
      // استخدام widget.centerName أولاً، وإذا كان فارغاً استخدم القيمة المحفوظة
      displayCenterName = widget.centerName ?? prefs.getString('centerName') ?? 'مركز طبي';
      displayCenterId = widget.centerId ?? prefs.getString('centerId');
    });
    // Mark online when main dashboard opens
    await PresenceService.setOnline(userId: savedUserId, userType: savedUserType);
  }

  @override
  Widget build(BuildContext context) {
    print('Dashboard build - fromControlPanel: ${widget.fromControlPanel}');
    return WillPopScope(
  onWillPop: () async {
    if (widget.fromControlPanel) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userType', 'control');
      await prefs.setBool('isLoggedIn', true);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MedicalCentersScreen()),
        (route) => false,
      );
      return false; // منع الخروج من التطبيق
    }

    return true; // يسمح بالخروج في الحالات العادية
  },
  child:  Scaffold(
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
        backgroundColor: Color.fromARGB(255, 156, 208, 235),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // تعطيل الزر التلقائي
       leading: widget.fromControlPanel
    ? IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('userType', 'control');
          await prefs.setBool('isLoggedIn', true);

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MedicalCentersScreen()),
            (route) => false,
          );
        },
        tooltip: 'رجوع إلى صفحة الكنترول',
      )
    : const SizedBox(),

        actions: [
  Builder(
    builder: (context) => IconButton(
      icon: const Icon(Icons.menu),
      onPressed: () {
        Scaffold.of(context).openEndDrawer(); // فتح الدروار
      },
    ),
  ),
],

      ),
      endDrawer: Drawer(
  child: SafeArea(
    child: Column(
      children: [
        // الجزء العلوي الملون
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          color: const Color.fromARGB(255, 156, 208, 235),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.person,
                  size: 50,
                  color: Color.fromARGB(255, 156, 208, 235),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                currentUserName ?? "مستخدم",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        

        const Divider(),
        ListTile(
  leading: const Icon(Icons.info, color: Colors.blueGrey),
  title: const Text(
    "حول التطبيق",
    style: TextStyle(color: Colors.black),
  ),
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const AboutScreen()),
    );
  },
),


        const Spacer(),

        ListTile(
          leading: const Icon(Icons.logout, color: Colors.blueGrey),
          title: const Text(
            "تسجيل الخروج",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
         onTap: () async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedUserId = prefs.getString('userId') ?? '';

    // 1. إيقاف الـ presence (لو موجود)
    await PresenceService.setOffline(userId: savedUserId);

    // 2. تسجيل خروج Firebase (مهم جداً للاستقرار)
    await FirebaseAuth.instance.signOut();

    // 3. مسح بيانات الجلسة فقط (مش كل حاجة)
    await prefs.remove('isLoggedIn');
    await prefs.remove('userId');
    await prefs.remove('userType');
    await prefs.remove('userName');
    await prefs.remove('centerId');
    await prefs.remove('centerName');

    if (!context.mounted) return;

    // 4. الرجوع لصفحة تسجيل الدخول
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  } catch (e) {
    debugPrint('Logout error: $e');

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('حدث خطأ أثناء تسجيل الخروج'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
         
        ),

        const SizedBox(height: 24),
      ],
    ),
  ),
),

      
      body: Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
         Color.fromARGB(255, 156, 208, 235).withOpacity(0.25),
        Colors.grey[200]!, 
      ],
    ),
  ),
  

        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [


                // Grid section
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 1,
                    childAspectRatio: 5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: [
                      _buildDashboardCard(
                        context,
                        'الحجوزات',
                        'assets/lottie/Calendar Event.json',
                        40,
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
                                backgroundColor: Colors.blueGrey,
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'الأطباء',
                        'assets/lottie/doctors.json',
                        40,
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
                                backgroundColor: Colors.blueGrey,
                              ),
                            );
                          }
                        },
                      ),
                       _buildDashboardCard(
                        context,
                        'جدول الأطباء',
                        'assets/lottie/take an appointment.json',
                        40,
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
                                backgroundColor: Colors.blueGrey,
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'التخصصات',
                        'assets/lottie/document.json',
                        40,
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
                                backgroundColor: Colors.blueGrey,
                              ),
                            );
                          }
                        },
                      ),
                      _buildDashboardCard(
                        context,
                        'شركات التأمين',
                        'assets/lottie/Insurance Protection.json',
                        40,
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
                                backgroundColor: Colors.blueGrey,
                              ),
                            );
                          }
                        },
                      ),
                     
                      _buildDashboardCard(
                        context,
                        'المستخدمين',
                        'assets/lottie/Connect.json',
                        40,
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
                                backgroundColor: Colors.blueGrey,
                              ),
                            );
                          }
                        },
                      ),
                      
                      _buildDashboardCard(
                        context,
                        'التقارير',
                       'assets/lottie/Financial Reports.json',
                        40,
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
                                backgroundColor: Colors.blueGrey,
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
                          'assets/lottie/Erlenmeyer flask.json',
                          40,
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
                                  backgroundColor: Colors.blueGrey,
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
      ),),
    );
  }

  Widget _buildDashboardCard(
  BuildContext context,
  String title,
  String lottieAsset,   // ← بدل Icon
  double lottieSize,
  VoidCallback onTap,
) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
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

            // النص
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
            ),

            // لوتي
            Container(
              height: lottieSize,
              width: lottieSize,
              alignment: Alignment.center,
              child: Lottie.asset(
                lottieAsset,
                fit: BoxFit.contain,
                repeat: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
