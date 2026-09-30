import 'package:flutter/material.dart';
import 'package:hospital_admin_app/screens/admin_doctors_screen.dart';
import 'package:hospital_admin_app/screens/admin_insurance_companies_screen.dart';
import 'package:hospital_admin_app/screens/admin_reports_screen.dart';
import 'package:hospital_admin_app/screens/admin_specialties_screen.dart';
import 'package:hospital_admin_app/screens/admin_users_screen.dart';
import 'package:lottie/lottie.dart';

class SettingsScreen extends StatelessWidget {
  final String centerId;
  final String centerName;

  const SettingsScreen({
    super.key,
    required this.centerId,
    required this.centerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الإعدادات',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 34, 96, 129),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color.fromARGB(255, 34, 96, 129).withOpacity(0.25),
              Colors.grey[200]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: GridView.count(
              crossAxisCount: 1,
              childAspectRatio: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _buildSettingCard(
                  context,
                  ' إدارة الأطباء ',
                  'assets/lottie/doctors.json',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => AdminDoctorsScreen(
                              centerId: centerId,
                              centerName: centerName,
                            ),
                      ),
                    );
                  },
                ),

                _buildSettingCard(
                  context,
                  ' إدارة التخصصات',
                  'assets/lottie/document.json',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => AdminSpecialtiesScreen(
                              centerId: centerId,
                              centerName: centerName,
                            ),
                      ),
                    );
                  },
                ),

                _buildSettingCard(
                  context,
                  ' إدارة شركات التأمين',
                  'assets/lottie/Insurance Protection.json',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => AdminInsuranceCompaniesScreen(
                              centerId: centerId,
                              centerName: centerName,
                            ),
                      ),
                    );
                  },
                ),

                _buildSettingCard(
                  context,
                  ' إدارة المستخدمين',
                  'assets/lottie/Connect.json',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => AdminUsersScreen(
                              centerId: centerId,
                              centerName: centerName,
                            ),
                      ),
                    );
                  },
                ),

                _buildSettingCard(
                  context,
                  'التقارير',
                  'assets/lottie/Financial Reports.json',
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => AdminReportsScreen(
                              centerId: centerId,
                              centerName: centerName,
                            ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingCard(
    BuildContext context,
    String title,
    String lottieAsset,
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
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  textAlign: TextAlign.start,
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                ),
              ),

              SizedBox(
                height: 40,
                width: 40,
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
