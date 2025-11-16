import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/admin_bookings_screen.dart';
import 'package:hospital_admin_app/screens/admin_doctors_schedule_screen.dart';
import 'package:hospital_admin_app/screens/callcenter_specialties_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hospital_admin_app/screens/login_screen.dart';
import 'package:hospital_admin_app/screens/today_samples_screen.dart';

class CallCenterScreen extends StatelessWidget {
  final String centerId;
  final String centerName;
  final String userId;
  final String userName;

  const CallCenterScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.userId,
    required this.userName,
  });

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // حذف جميع بيانات الجلسة

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
  Widget _buildHomeCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = const Color(0xFF2FBDAF),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: null,
          boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.07),
          blurRadius: 10,
          spreadRadius: 1,
          offset: const Offset(0, 3),
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
                style: const TextStyle(
                  fontSize: 18,
                  
                ),
              ),
              Icon(icon, size: 25, color: color),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2FBDAF),
        centerTitle: true,
        title: Column(
          children: [
            const Text('Call Center', style: TextStyle(color: Colors.white)),
            Text(centerName, style: const TextStyle(fontSize: 14, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'تسجيل الخروج',
            onPressed: () => _logout(context), // خروج مباشر
          ),
        ],
      ),
      body:  Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.count(
            crossAxisCount: 1,
            childAspectRatio: 4.5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildHomeCard(icon: Icons.calendar_today, title: 'الحجوزات', onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) =>  AdminBookingsScreen(centerId: centerId, centerName: centerName,)));
              }),
              _buildHomeCard(icon: Icons.add_alarm_rounded, title: 'حجز جديد', onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => CallcenterSpecialtiesScreen(centerId: centerId, centerName: centerName)));
              },),
              _buildHomeCard(icon: Icons.schedule, title: 'جدول الاطباء', onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) =>  AdminDoctorsScheduleScreen(centerId: centerId, centerName: centerName,)));
              }),
              _buildHomeCard(icon: Icons.science, title: 'النتائج', onTap: (){
                Navigator.push(context, MaterialPageRoute(builder: (context) => TodaySamplesScreen()));
              }),
              _buildHomeCard(icon: Icons.price_change, title: 'قائمة الاسعار', onTap: (){}),
            ]))
     );
  }
}
