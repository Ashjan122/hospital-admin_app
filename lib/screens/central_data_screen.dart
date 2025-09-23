import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/central_specialties_screen.dart';
import 'package:hospital_admin_app/screens/central_doctors_screen.dart';
import 'package:hospital_admin_app/screens/central_insurance_screen.dart';

class CentralDataScreen extends StatelessWidget {
  const CentralDataScreen({super.key});

  Widget _buildHomeCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = const Color(0xFF0D47A1),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
          title: const Text(
            'البيانات المركزية',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF0D47A1),
          elevation: 0,
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 0.9,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _buildHomeCard(
                icon: Icons.business,
                title: 'المراكز الطبية',
                onTap: () {
                  Navigator.pop(context, 'centers');
                },
              ),
              _buildHomeCard(
                icon: Icons.storage,
                title: 'التخصصات',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CentralSpecialtiesScreen(),
                    ),
                  );
                },
              ),
              _buildHomeCard(
                icon: Icons.medical_services,
                title: 'الأطباء',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CentralDoctorsScreen(),
                    ),
                  );
                },
              ),
              _buildHomeCard(
                icon: Icons.verified_user,
                title: 'التأمين',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CentralInsuranceScreen(),
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


