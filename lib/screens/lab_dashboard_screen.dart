import 'package:flutter/material.dart';
import 'lab_new_sample_screen.dart';
import 'lab_results_patients_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'lab_price_list_screen.dart';
import 'lab_users_screen.dart';

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

  //

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
                // تسجيل خروج كامل حتى لو كان الدخول من الكنترول
                await prefs.setBool('isLoggedIn', false);
                await prefs.remove('userType');
                await prefs.remove('centerId');
                await prefs.remove('centerName');
                await prefs.remove('fromControlPanel');
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
              _buildCard(
                icon: FontAwesomeIcons.syringe,
                title: 'عينة جديدة',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LabNewSampleScreen(labId: labId, labName: labName),
                    ),
                  );
                },
              ),
              _buildCard(
                icon: Icons.print,
                title: 'النتائج',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LabResultsPatientsScreen(labId: labId, labName: labName),
                    ),
                  );
                },
              ),
              _buildCard(
                icon: Icons.people,
                title: 'المستخدمين',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LabUsersScreen(labId: labId, labName: labName),
                    ),
                  );
                },
              ),
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


