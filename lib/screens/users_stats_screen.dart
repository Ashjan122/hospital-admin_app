import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UsersStatsScreen extends StatefulWidget {
  const UsersStatsScreen({super.key});

  @override
  State<UsersStatsScreen> createState() => _UsersStatsScreenState();
}

class _UsersStatsScreenState extends State<UsersStatsScreen> {
  bool _loading = false;
  // All users
  int _onlineAll = 0;
  int _loginsAll = 0;
  // Per role
  int _onlinePatient = 0, _loginsPatient = 0;
  int _onlineReception = 0, _loginsReception = 0;
  int _onlineDoctor = 0, _loginsDoctor = 0;
  int _onlineAdmin = 0, _loginsAdmin = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
    });

    try {
      final DateTime now = DateTime.now();
      final DateTime fiveMinutesAgo = now.subtract(const Duration(minutes: 5));
      final DateTime startOfToday = DateTime(now.year, now.month, now.day);

      // Fetch non-patient users once (users collection)
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      final List<Map<String, dynamic>> users = usersSnap.docs.map((d) => d.data()).toList();

      // Fetch patients from patients collection
      final patientsSnap = await FirebaseFirestore.instance.collection('patients').get();
      final List<Map<String, dynamic>> patients = patientsSnap.docs.map((d) => d.data()).toList();

      bool isOnlineFor(Map<String, dynamic> u) {
        if (u.containsKey('isOnline')) {
          return u['isOnline'] == true;
        }
        final lastSeen = u['lastSeenAt'];
        if (lastSeen is Timestamp) {
          final dt = lastSeen.toDate();
          return dt.isAfter(fiveMinutesAgo) || dt.isAtSameMomentAs(fiveMinutesAgo);
        }
        return false;
      }

      bool loginTodayFor(Map<String, dynamic> u) {
        final lastLogin = u['lastLoginAt'];
        if (lastLogin is Timestamp) {
          final dt = lastLogin.toDate();
          return dt.isAfter(startOfToday) || dt.isAtSameMomentAs(startOfToday);
        }
        return false;
      }

      // Non-patient roles are in users collection with userType field
      int countOnlineUsersType(String type) => users
          .where((u) => (u['userType']?.toString() ?? '') == type)
          .where(isOnlineFor)
          .length;

      int countLoginsUsersType(String type) => users
          .where((u) => (u['userType']?.toString() ?? '') == type)
          .where(loginTodayFor)
          .length;

      // Patients are in patients collection (no userType filter)
      int countOnlinePatients() => patients.where(isOnlineFor).length;
      int countLoginsPatients() => patients.where(loginTodayFor).length;

      final onlineReception = countOnlineUsersType('reception');
      final loginsReception = countLoginsUsersType('reception');
      final onlineDoctor = countOnlineUsersType('doctor');
      final loginsDoctor = countLoginsUsersType('doctor');
      final onlineAdmin = countOnlineUsersType('admin');
      final loginsAdmin = countLoginsUsersType('admin');
      final onlinePatient = countOnlinePatients();
      final loginsPatient = countLoginsPatients();
      final onlineAll = onlineReception + onlineDoctor + onlineAdmin + onlinePatient;
      final loginsAll = loginsReception + loginsDoctor + loginsAdmin + loginsPatient;

      if (mounted) {
        setState(() {
          _onlineAll = onlineAll;
          _loginsAll = loginsAll;
          _onlinePatient = onlinePatient;
          _loginsPatient = loginsPatient;
          _onlineReception = onlineReception;
          _loginsReception = loginsReception;
          _onlineDoctor = onlineDoctor;
          _loginsDoctor = loginsDoctor;
          _onlineAdmin = onlineAdmin;
          _loginsAdmin = loginsAdmin;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل الإحصائيات: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _showRoleDetails({required String title, required String roleKey}) async {
    // roleKey: 'all' | 'patient' | 'reception' | 'doctor' | 'admin'
    Future<_RoleDetailData> loadDetails() async {
      final DateTime now = DateTime.now();
      final DateTime fiveMinutesAgo = now.subtract(const Duration(minutes: 5));
      final DateTime startOfToday = DateTime(now.year, now.month, now.day);

      bool isOnlineFor(Map<String, dynamic> u) {
        if (u.containsKey('isOnline')) {
          return u['isOnline'] == true;
        }
        final lastSeen = u['lastSeenAt'];
        if (lastSeen is Timestamp) {
          final dt = lastSeen.toDate();
          return dt.isAfter(fiveMinutesAgo) || dt.isAtSameMomentAs(fiveMinutesAgo);
        }
        return false;
      }

      bool loginTodayFor(Map<String, dynamic> u) {
        final lastLogin = u['lastLoginAt'];
        if (lastLogin is Timestamp) {
          final dt = lastLogin.toDate();
          return dt.isAfter(startOfToday) || dt.isAtSameMomentAs(startOfToday);
        }
        return false;
      }

      List<Map<String, dynamic>> fetched = [];
      if (roleKey == 'patient' || roleKey == 'all') {
        final patientsSnap = await FirebaseFirestore.instance.collection('patients').get();
        final patients = patientsSnap.docs.map((d) => d.data()).toList();
        if (roleKey == 'patient') {
          fetched = patients;
        } else {
          fetched.addAll(patients);
        }
      }

      if (roleKey != 'patient') {
        // Fetch non-patient users and optionally filter by role
        final usersSnap = await FirebaseFirestore.instance.collection('users').get();
        final users = usersSnap.docs.map((d) => d.data()).toList();
        final List<Map<String, dynamic>> filteredUsers = roleKey == 'all'
            ? users
            : users.where((u) => (u['userType']?.toString() ?? '') == roleKey).toList();
        fetched.addAll(filteredUsers);
      }

      final online = fetched.where(isOnlineFor).toList();
      final logins = fetched.where(loginTodayFor).toList();
      return _RoleDetailData(online: online, logins: logins);
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 16),
              child: FutureBuilder<_RoleDetailData>(
                future: loadDetails(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 260,
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF2FBDAF))),
                    );
                  }
                  if (snapshot.hasError) {
                    return SizedBox(
                      height: 200,
                      child: Center(child: Text('حدث خطأ: ${snapshot.error}')),
                    );
                  }
                  final data = snapshot.data ?? _RoleDetailData.empty();
                  return DefaultTabController(
                    length: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'قائمة $title',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const TabBar(
                          labelColor: Color(0xFF2FBDAF),
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Color(0xFF2FBDAF),
                          tabs: [
                            Tab(text: 'المتصلون الآن'),
                            Tab(text: 'تسجيلات اليوم'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 420,
                          child: TabBarView(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SectionHeader(title: 'المتصلون الآن (${data.online.length})', color: Colors.green),
                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Expanded(child: _UsersList(items: data.online)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SectionHeader(title: 'تسجيلات اليوم (${data.logins.length})', color: Color(0xFF2FBDAF)),
                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Expanded(child: _UsersList(items: data.logins)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إحصائيات المستخدمين',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF2FBDAF),
          elevation: 0,
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadStats,
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF2FBDAF)))
              : GridView.count(
                  padding: const EdgeInsets.all(16),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _RoleCard(
                      title: 'الكل',
                      color: const Color(0xFF2FBDAF),
                      online: _onlineAll,
                      logins: _loginsAll,
                      onTap: () => _showRoleDetails(title: 'الكل', roleKey: 'all'),
                    ),
                    _RoleCard(
                      title: 'المرضى',
                      color: const Color(0xFF2FBDAF),
                      online: _onlinePatient,
                      logins: _loginsPatient,
                      onTap: () => _showRoleDetails(title: 'المرضى', roleKey: 'patient'),
                    ),
                    _RoleCard(
                      title: 'موظف الاستقبال',
                      color: const Color(0xFF2FBDAF),
                      online: _onlineReception,
                      logins: _loginsReception,
                      onTap: () => _showRoleDetails(title: 'موظف الاستقبال', roleKey: 'reception'),
                    ),
                    _RoleCard(
                      title: 'الأطباء',
                      color: const Color(0xFF2FBDAF),
                      online: _onlineDoctor,
                      logins: _loginsDoctor,
                      onTap: () => _showRoleDetails(title: 'الأطباء', roleKey: 'doctor'),
                    ),
                    _RoleCard(
                      title: 'الادمن',
                      color: const Color(0xFF2FBDAF),
                      online: _onlineAdmin,
                      logins: _loginsAdmin,
                      onTap: () => _showRoleDetails(title: 'الادمن', roleKey: 'admin'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
class _RoleCard extends StatelessWidget {
  final String title;
  final Color color;
  final int online;
  final int logins;
  final VoidCallback? onTap;

  const _RoleCard({
    required this.title,
    required this.color,
    required this.online,
    required this.logins,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Card(
        elevation: 2,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              _StatLine(label: 'المتصلون الآن', value: online.toString(), color: Colors.green),
              const SizedBox(height: 6),
              _StatLine(label: 'تسجيلات اليوم', value: logins.toString(), color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleDetailData {
  final List<Map<String, dynamic>> online;
  final List<Map<String, dynamic>> logins;

  _RoleDetailData({required this.online, required this.logins});

  factory _RoleDetailData.empty() => _RoleDetailData(online: const [], logins: const []);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 6, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey[800]),
          ),
        ),
      ],
    );
  }
}

class _UsersList extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _UsersList({required this.items});

  String _bestDisplayName(Map<String, dynamic> u) {
    // Prefer proper names across different roles (admin/doctor/reception/patient)
    final String? fullNameLike = _asNonEmptyString(
      u['name'] ??
          u['fullName'] ??
          u['full_name'] ??
          u['displayName'] ??
          u['display_name'] ??
          u['patientName'] ??
          u['doctorName'] ??
          u['receptionName'] ??
          u['adminName'] ??
          u['username'] ??
          u['userName'] ??
          u['nameAr'] ??
          u['name_ar'] ??
          u['arabicName'] ??
          u['arabic_name'] ??
          u['nameEn'] ??
          u['name_en'],
    );
    if (fullNameLike != null) return fullNameLike;

    // Try combining first/last names
    final String? first = _asNonEmptyString(u['firstName'] ?? u['first_name'] ?? u['fName'] ?? u['first']);
    final String? last = _asNonEmptyString(u['lastName'] ?? u['last_name'] ?? u['lName'] ?? u['last']);
    if (first != null && last != null) return '$first $last';
    if (first != null) return first;
    if (last != null) return last;

    // As a last resort, fall back to email (avoid phone or role)
    final String? email = _asNonEmptyString(u['email']);
    if (email != null) {
      final int atIndex = email.indexOf('@');
      final String local = atIndex > 0 ? email.substring(0, atIndex) : email;
      final String beautified = local
          .replaceAll(RegExp(r'[._-]+'), ' ')
          .split(' ')
          .where((p) => p.trim().isNotEmpty)
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
          .join(' ')
          .trim();
      if (beautified.isNotEmpty) return beautified;
      return email;
    }
    return 'بدون اسم';
  }

  String? _asNonEmptyString(dynamic value) {
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('لا توجد عناصر'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final u = items[index];
        return ListTile(
          dense: true,
          title: Text(_bestDisplayName(u)),
          leading: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
        );
      },
    );
  }
}


