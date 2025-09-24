import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'lab_price_list_screen.dart';

class LabDashboardScreen extends StatelessWidget {
  final String labId;
  final String labName;
  const LabDashboardScreen({super.key, required this.labId, required this.labName});

  Widget _buildCard({required IconData icon, required String title, required VoidCallback onTap, Color color = const Color(0xFF0D47A1)}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('لوحة $labName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('lab_id');
                await prefs.remove('labName');
                // إذا كان المستخدمType مسجل كـ lab، أعد ضبط تسجيل الدخول للمختبر فقط
                final userType = prefs.getString('userType');
                if (userType == 'lab') {
                  await prefs.setBool('isLoggedIn', false);
                  await prefs.remove('userType');
                }
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 0.9,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _buildCard(icon: FontAwesomeIcons.syringe, title: 'عينة جديدة', onTap: () {}),
              _buildCard(icon: Icons.print, title: 'النتائج', onTap: () {}),
              _buildCard(icon: Icons.people, title: 'المستخدمون', onTap: () {}),
              _buildCard(
                icon: Icons.price_change,
                title: 'قائمة الأسعار',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LabPriceListScreen(labId: labId, labName: labName),
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


