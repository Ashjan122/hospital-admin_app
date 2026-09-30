import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsersStatsScreen extends StatefulWidget {
  const UsersStatsScreen({super.key});

  @override
  State<UsersStatsScreen> createState() => _UsersStatsScreenState();
}

class _UsersStatsScreenState extends State<UsersStatsScreen> {
  bool _loading = false;

  // ============================================================
  // All users
  // ============================================================

  int _onlineAll = 0;
  int _loginsAll = 0;

  // ============================================================
  // Per role
  // ============================================================

  int _onlinePatient = 0;
  int _loginsPatient = 0;

  int _onlineReception = 0;
  int _loginsReception = 0;

  int _onlineDoctor = 0;
  int _loginsDoctor = 0;

  int _onlineAdmin = 0;
  int _loginsAdmin = 0;

  // ============================================================
  // New patients for THIS DEVICE only
  // ============================================================

  int _newPatients = 0;

  static const String _lastPatientsReadKey = 'lastPatientsReadAt';

  // ============================================================
  // Init
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  // ============================================================
  // Get last time patient list was read on THIS DEVICE
  // ============================================================

  Future<DateTime?> _getLastPatientsReadAt() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_lastPatientsReadKey);

    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  // ============================================================
  // Save patient list read time on THIS DEVICE
  // ============================================================

  Future<void> _savePatientsReadAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lastPatientsReadKey, time.toIso8601String());
  }

  // ============================================================
  // IMPORTANT:
  // Online status is determined ONLY by lastSeenAt.
  //
  // isOnline is intentionally NOT trusted because it can remain
  // true after the user closes the application.
  // ============================================================

  bool _isOnline(Map<String, dynamic> user, DateTime now) {
    final lastSeen = user['lastSeenAt'];

    if (lastSeen is! Timestamp) {
      return false;
    }

    final DateTime lastSeenDate = lastSeen.toDate();

    final DateTime fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

    return lastSeenDate.isAfter(fiveMinutesAgo) ||
        lastSeenDate.isAtSameMomentAs(fiveMinutesAgo);
  }

  // ============================================================
  // Login today
  // ============================================================

  bool _loggedInToday(Map<String, dynamic> user, DateTime now) {
    final lastLogin = user['lastLoginAt'];

    if (lastLogin is! Timestamp) {
      return false;
    }

    final DateTime loginDate = lastLogin.toDate();

    final DateTime startOfToday = DateTime(now.year, now.month, now.day);

    return loginDate.isAfter(startOfToday) ||
        loginDate.isAtSameMomentAs(startOfToday);
  }

  // ============================================================
  // Count new patients
  // ============================================================

  int _countNewPatients(
    List<Map<String, dynamic>> patients,
    DateTime? lastReadAt,
  ) {
    // First time opening:
    // Do not consider old patients as new.
    if (lastReadAt == null) {
      return 0;
    }

    return patients.where((patient) {
      final createdAt = patient['createdAt'];

      if (createdAt is Timestamp) {
        return createdAt.toDate().isAfter(lastReadAt);
      }

      return false;
    }).length;
  }

  // ============================================================
  // Load statistics
  // ============================================================

  Future<void> _loadStats() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final DateTime now = DateTime.now();

      final DateTime? lastPatientsReadAt = await _getLastPatientsReadAt();

      // ========================================================
      // Users
      // ========================================================

      final usersSnap =
          await FirebaseFirestore.instance.collection('users').get();

      final List<Map<String, dynamic>> users =
          usersSnap.docs.map((doc) => doc.data()).toList();

      // ========================================================
      // Patients
      // ========================================================

      final patientsSnap =
          await FirebaseFirestore.instance.collection('patients').get();

      final List<Map<String, dynamic>> patients =
          patientsSnap.docs.map((doc) => doc.data()).toList();

      // ========================================================
      // Users by role
      // ========================================================

      int countOnlineUsersType(String type) {
        return users
            .where((u) => (u['userType']?.toString() ?? '') == type)
            .where((u) => _isOnline(u, now))
            .length;
      }

      int countLoginsUsersType(String type) {
        return users
            .where((u) => (u['userType']?.toString() ?? '') == type)
            .where((u) => _loggedInToday(u, now))
            .length;
      }

      // ========================================================
      // Patients
      // ========================================================

      final int onlinePatient = patients.where((u) => _isOnline(u, now)).length;

      final int loginsPatient =
          patients.where((u) => _loggedInToday(u, now)).length;

      // ========================================================
      // New patients
      // ========================================================

      final int newPatients = _countNewPatients(patients, lastPatientsReadAt);

      // ========================================================
      // Reception
      // ========================================================

      final int onlineReception = countOnlineUsersType('reception');

      final int loginsReception = countLoginsUsersType('reception');

      // ========================================================
      // Doctors
      // ========================================================

      final int onlineDoctor = countOnlineUsersType('doctor');

      final int loginsDoctor = countLoginsUsersType('doctor');

      // ========================================================
      // Admin
      // ========================================================

      final int onlineAdmin = countOnlineUsersType('admin');

      final int loginsAdmin = countLoginsUsersType('admin');

      // ========================================================
      // All
      // ========================================================

      final int onlineAll =
          onlineReception + onlineDoctor + onlineAdmin + onlinePatient;

      final int loginsAll =
          loginsReception + loginsDoctor + loginsAdmin + loginsPatient;

      // ========================================================
      // Update UI
      // ========================================================

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

          _newPatients = newPatients;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تحميل الإحصائيات: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // Patient details
  // ============================================================

  Future<void> _showPatientDetails() async {
    if (!mounted) return;
    final patientDetailsFuture = _loadPatientDetails();
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
              padding: const EdgeInsets.only(
                top: 8,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: FutureBuilder<_PatientDetailData>(
                future: patientDetailsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 400,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return SizedBox(
                      height: 200,
                      child: Center(child: Text('حدث خطأ: ${snapshot.error}')),
                    );
                  }

                  final data = snapshot.data ?? _PatientDetailData.empty();

                  return DefaultTabController(
                    length: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'قائمة المرضى',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
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
                          isScrollable: true,
                          labelColor: Color(0xFF0D47A1),
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Color(0xFF0D47A1),
                          tabs: [
                            Tab(text: 'كل المرضى'),
                            Tab(text: 'الجدد'),
                            Tab(text: 'المتصلون الآن'),
                          ],
                        ),

                        const SizedBox(height: 8),

                        SizedBox(
                          height: 480,
                          child: TabBarView(
                            children: [
                              _PatientsFullList(items: data.allPatients),
                              _PatientsFullList(
                                items: data.newPatients,
                                showNewBadge: true,
                              ),
                              _PatientsFullList(items: data.onlinePatients),
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

  // ============================================================
  // Load patient details
  // ============================================================

  Future<_PatientDetailData> _loadPatientDetails() async {
    final DateTime? lastReadAt = await _getLastPatientsReadAt();

    final DateTime now = DateTime.now();

    final patientsSnap =
        await FirebaseFirestore.instance.collection('patients').get();

    final List<Map<String, dynamic>> patients =
        patientsSnap.docs.map((doc) {
          return {...doc.data(), '_docId': doc.id};
        }).toList();

    // ==========================================================
    // New patients
    // ==========================================================

    List<Map<String, dynamic>> newPatients = [];

    if (lastReadAt != null) {
      newPatients =
          patients.where((patient) {
            final createdAt = patient['createdAt'];

            if (createdAt is Timestamp) {
              return createdAt.toDate().isAfter(lastReadAt);
            }

            return false;
          }).toList();
    }

    // ==========================================================
    // Sort all patients
    // ==========================================================

    patients.sort((a, b) {
      final aCreated = a['createdAt'];
      final bCreated = b['createdAt'];

      if (aCreated is Timestamp && bCreated is Timestamp) {
        return bCreated.compareTo(aCreated);
      }

      return 0;
    });

    // ==========================================================
    // Sort new patients
    // ==========================================================

    newPatients.sort((a, b) {
      final aCreated = a['createdAt'];
      final bCreated = b['createdAt'];

      if (aCreated is Timestamp && bCreated is Timestamp) {
        return bCreated.compareTo(aCreated);
      }

      return 0;
    });

    // ==========================================================
    // Online patients
    // IMPORTANT:
    // lastSeenAt only
    // ==========================================================

    final List<Map<String, dynamic>> onlinePatients =
        patients.where((patient) => _isOnline(patient, now)).toList();

    // ==========================================================
    // Mark as read after successful loading
    // ==========================================================

    await _savePatientsReadAt(now);

    if (mounted) {
      setState(() {
        _newPatients = 0;
      });
    }

    return _PatientDetailData(
      allPatients: patients,
      newPatients: newPatients,
      onlinePatients: onlinePatients,
    );
  }

  // ============================================================
  // Role details
  // ============================================================

  Future<void> _showRoleDetails({
    required String title,
    required String roleKey,
  }) async {
    if (roleKey == 'patient') {
      await _showPatientDetails();
      return;
    }

    Future<_RoleDetailData> loadDetails() async {
      final DateTime now = DateTime.now();

      // ========================================================
      // Users
      // ========================================================

      final usersSnap =
          await FirebaseFirestore.instance.collection('users').get();

      final List<Map<String, dynamic>> users =
          usersSnap.docs.map((doc) => doc.data()).toList();

      // ========================================================
      // لو "الكل" → نضيف المرضى أيضاً
      // ========================================================

      List<Map<String, dynamic>> fetched;

      if (roleKey == 'all') {
        final patientsSnap =
            await FirebaseFirestore.instance.collection('patients').get();

        final List<Map<String, dynamic>> patients =
            patientsSnap.docs.map((doc) => doc.data()).toList();

        fetched = [...users, ...patients];
      } else {
        fetched =
            users
                .where((u) => (u['userType']?.toString() ?? '') == roleKey)
                .toList();
      }

      // ========================================================
      // المتصلون الآن
      // ========================================================

      final List<Map<String, dynamic>> online =
          fetched.where((u) => _isOnline(u, now)).toList();

      // ========================================================
      // تسجيلات اليوم
      // ========================================================

      final List<Map<String, dynamic>> logins =
          fetched.where((u) => _loggedInToday(u, now)).toList();

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
              padding: const EdgeInsets.only(
                top: 8,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: FutureBuilder<_RoleDetailData>(
                future: loadDetails(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 260,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0D47A1),
                        ),
                      ),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
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
                          labelColor: Color(0xFF0D47A1),
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Color(0xFF0D47A1),
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
                                  _SectionHeader(
                                    title:
                                        'المتصلون الآن (${data.online.length})',
                                    color: Colors.green,
                                  ),
                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: _UsersList(items: data.online),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SectionHeader(
                                    title:
                                        'تسجيلات اليوم (${data.logins.length})',
                                    color: Color(0xFF0D47A1),
                                  ),
                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: _UsersList(items: data.logins),
                                  ),
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

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إحصائيات المستخدمين',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF0D47A1),
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
          child:
              _loading
                  ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
                  )
                  : GridView.count(
                    padding: const EdgeInsets.all(16),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      _RoleCard(
                        title: 'الكل',
                        color: const Color(0xFF0D47A1),
                        online: _onlineAll,
                        logins: _loginsAll,
                        onTap:
                            () =>
                                _showRoleDetails(title: 'الكل', roleKey: 'all'),
                      ),

                      _RoleCard(
                        title: 'المرضى',
                        color: const Color(0xFF0D47A1),
                        online: _onlinePatient,
                        logins: _loginsPatient,
                        newPatients: _newPatients,
                        onTap: _showPatientDetails,
                      ),

                      _RoleCard(
                        title: 'موظف الاستقبال',
                        color: const Color(0xFF0D47A1),
                        online: _onlineReception,
                        logins: _loginsReception,
                        onTap:
                            () => _showRoleDetails(
                              title: 'موظف الاستقبال',
                              roleKey: 'reception',
                            ),
                      ),

                      _RoleCard(
                        title: 'الأطباء',
                        color: const Color(0xFF0D47A1),
                        online: _onlineDoctor,
                        logins: _loginsDoctor,
                        onTap:
                            () => _showRoleDetails(
                              title: 'الأطباء',
                              roleKey: 'doctor',
                            ),
                      ),

                      _RoleCard(
                        title: 'الادمن',
                        color: const Color(0xFF0D47A1),
                        online: _onlineAdmin,
                        logins: _loginsAdmin,
                        onTap:
                            () => _showRoleDetails(
                              title: 'الادمن',
                              roleKey: 'admin',
                            ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}

// ================================================================
// ROLE CARD
// ================================================================

class _RoleCard extends StatelessWidget {
  final String title;
  final Color color;
  final int online;
  final int logins;
  final int newPatients;
  final VoidCallback? onTap;

  const _RoleCard({
    required this.title,
    required this.color,
    required this.online,
    required this.logins,
    this.newPatients = 0,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (newPatients > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$newPatients',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),

              const Spacer(),

              _StatLine(
                label: 'المتصلون الآن',
                value: online.toString(),
                color: Colors.green,
              ),

              const SizedBox(height: 6),

              _StatLine(
                label: 'تسجيلات اليوم',
                value: logins.toString(),
                color: color,
              ),

              if (title == 'المرضى' && newPatients > 0) ...[
                const SizedBox(height: 6),
                _StatLine(
                  label: 'مرضى جدد',
                  value: newPatients.toString(),
                  color: Colors.red,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// STAT LINE
// ================================================================

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

// ================================================================
// ROLE DETAIL DATA
// ================================================================

class _RoleDetailData {
  final List<Map<String, dynamic>> online;
  final List<Map<String, dynamic>> logins;

  _RoleDetailData({required this.online, required this.logins});

  factory _RoleDetailData.empty() {
    return _RoleDetailData(online: const [], logins: const []);
  }
}

// ================================================================
// PATIENT DETAIL DATA
// ================================================================

class _PatientDetailData {
  final List<Map<String, dynamic>> allPatients;
  final List<Map<String, dynamic>> newPatients;
  final List<Map<String, dynamic>> onlinePatients;

  _PatientDetailData({
    required this.allPatients,
    required this.newPatients,
    required this.onlinePatients,
  });

  factory _PatientDetailData.empty() {
    return _PatientDetailData(
      allPatients: const [],
      newPatients: const [],
      onlinePatients: const [],
    );
  }
}

// ================================================================
// SECTION HEADER
// ================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================
// PATIENT LIST
// ================================================================

class _PatientsFullList extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final bool showNewBadge;

  const _PatientsFullList({required this.items, this.showNewBadge = false});
  @override
  State<_PatientsFullList> createState() => _PatientsFullListState();
}

class _PatientsFullListState extends State<_PatientsFullList> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _asNonEmptyString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();

      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return null;
  }

  String _bestDisplayName(Map<String, dynamic> u) {
    final String? fullNameLike = _asNonEmptyString(
      u['name'] ??
          u['fullName'] ??
          u['full_name'] ??
          u['displayName'] ??
          u['display_name'] ??
          u['patientName'] ??
          u['nameAr'] ??
          u['name_ar'] ??
          u['arabicName'] ??
          u['arabic_name'] ??
          u['nameEn'] ??
          u['name_en'],
    );

    if (fullNameLike != null) {
      return fullNameLike;
    }

    final String? first = _asNonEmptyString(
      u['firstName'] ?? u['first_name'] ?? u['fName'] ?? u['first'],
    );

    final String? last = _asNonEmptyString(
      u['lastName'] ?? u['last_name'] ?? u['lName'] ?? u['last'],
    );

    if (first != null && last != null) {
      return '$first $last';
    }

    if (first != null) return first;
    if (last != null) return last;

    final String? email = _asNonEmptyString(u['email']);

    if (email != null) {
      final int atIndex = email.indexOf('@');

      final String local = atIndex > 0 ? email.substring(0, atIndex) : email;

      final String beautified =
          local
              .replaceAll(RegExp(r'[._-]+'), ' ')
              .split(' ')
              .where((p) => p.trim().isNotEmpty)
              .map(
                (w) =>
                    w.isEmpty
                        ? w
                        : w[0].toUpperCase() +
                            (w.length > 1 ? w.substring(1) : ''),
              )
              .join(' ')
              .trim();

      if (beautified.isNotEmpty) {
        return beautified;
      }

      return email;
    }

    return 'بدون اسم';
  }

  String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();

      final day = date.day.toString().padLeft(2, '0');

      final month = date.month.toString().padLeft(2, '0');

      final year = date.year.toString();

      final hour = date.hour.toString().padLeft(2, '0');

      final minute = date.minute.toString().padLeft(2, '0');

      return '$day/$month/$year  $hour:$minute';
    }

    return 'غير متوفر';
  }

  // ============================================================
  // Same online logic used by the statistics:
  // lastSeenAt within 5 minutes.
  // ============================================================

  bool _isOnline(Map<String, dynamic> u) {
    final lastSeen = u['lastSeenAt'];

    if (lastSeen is! Timestamp) {
      return false;
    }

    final DateTime now = DateTime.now();

    final DateTime fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

    final DateTime lastSeenDate = lastSeen.toDate();

    return lastSeenDate.isAfter(fiveMinutesAgo) ||
        lastSeenDate.isAtSameMomentAs(fiveMinutesAgo);
  }

  Future<void> _togglePatientStatus(
    BuildContext context,
    Map<String, dynamic> patient,
  ) async {
    final String? patientId = patient['_docId']?.toString();

    if (patientId == null || patientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديد حساب المريض'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final bool isActive = patient['isActive'] != false;

    try {
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientId)
          .update({'isActive': !isActive});

      if (!mounted) return;

      setState(() {
        patient['isActive'] = !isActive;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !isActive ? 'تم تفعيل حساب المريض' : 'تم تعطيل حساب المريض',
          ),
          backgroundColor: !isActive ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث حالة الحساب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showPatientDetails(
    BuildContext context,
    Map<String, dynamic> patient,
  ) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        bool isActive = patient['isActive'] != false;
        final bool isOnline = _isOnline(patient);

        return StatefulBuilder(
          builder: (context, setState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ==================================================
                        // Handle
                        // ==================================================
                        Center(
                          child: Container(
                            width: 45,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // ==================================================
                        // Header
                        // ==================================================
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    _bestDisplayName(patient),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 9,
                                        height: 9,
                                        decoration: BoxDecoration(
                                          color:
                                              isOnline
                                                  ? Colors.green
                                                  : Colors.grey,
                                          shape: BoxShape.circle,
                                        ),
                                      ),

                                      const SizedBox(width: 6),

                                      Text(
                                        isOnline ? 'متصل الآن' : 'غير متصل',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              isOnline
                                                  ? Colors.green
                                                  : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            IconButton(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ==================================================
                        // Account Status
                        // ==================================================
                        InkWell(
                          onTap: () async {
                            final String? patientId =
                                patient['_docId']?.toString();

                            if (patientId == null || patientId.isEmpty) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('تعذر تحديد حساب المريض'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            final bool newStatus = !isActive;

                            try {
                              await FirebaseFirestore.instance
                                  .collection('patients')
                                  .doc(patientId)
                                  .update({'isActive': newStatus});

                              // تحديث البيانات
                              patient['isActive'] = newStatus;
                              isActive = newStatus;

                              // تحديث شكل الشاشة
                              setState(() {});

                              if (!mounted) return;

                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    newStatus
                                        ? 'تم تفعيل حساب المريض'
                                        : 'تم تعطيل حساب المريض',
                                  ),
                                  backgroundColor:
                                      newStatus ? Colors.green : Colors.red,
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;

                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text('تعذر تحديث حالة الحساب: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isActive
                                      ? Colors.green.withOpacity(0.08)
                                      : Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    isActive
                                        ? Colors.green.withOpacity(0.25)
                                        : Colors.red.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isActive
                                      ? Icons.check_circle_outline
                                      : Icons.block_outlined,
                                  color: isActive ? Colors.green : Colors.red,
                                  size: 20,
                                ),

                                const SizedBox(width: 8),

                                Text(
                                  'حالة الحساب',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),

                                const Spacer(),

                                Text(
                                  isActive ? 'مفعل' : 'معطل',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isActive ? Colors.green : Colors.red,
                                  ),
                                ),

                                const SizedBox(width: 6),

                                Icon(
                                  Icons.chevron_left,
                                  size: 18,
                                  color: isActive ? Colors.green : Colors.red,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // ==================================================
                        // Patient Information
                        // ==================================================
                        const Text(
                          'بيانات المريض',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              _PatientInfoRow(
                                icon: Icons.person_outline,
                                label: 'الاسم',
                                value: _bestDisplayName(patient),
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.phone_outlined,
                                label: 'رقم الهاتف',
                                value:
                                    patient['phone']?.toString() ?? 'غير متوفر',
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.email_outlined,
                                label: 'البريد الإلكتروني',
                                value:
                                    patient['email']?.toString() ?? 'غير متوفر',
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.calendar_today_outlined,
                                label: 'تاريخ التسجيل',
                                value: _formatTimestamp(patient['createdAt']),
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.login_outlined,
                                label: 'آخر تسجيل دخول',
                                value: _formatTimestamp(patient['lastLoginAt']),
                              ),

                              const SizedBox(height: 12),

                              _PatientInfoRow(
                                icon: Icons.access_time,
                                label: 'آخر ظهور',
                                value: _formatTimestamp(patient['lastSeenAt']),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return widget.items;
    }

    return widget.items.where((patient) {
      final name = _bestDisplayName(patient).toLowerCase();
      final phone = patient['phone']?.toString().toLowerCase() ?? '';
      final email = patient['email']?.toString().toLowerCase() ?? '';

      return name.contains(query) ||
          phone.contains(query) ||
          email.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Center(
        child: Text('لا توجد عناصر', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو رقم الهاتف',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _searchQuery.isNotEmpty
                      ? IconButton(
                        onPressed: () {
                          _searchController.clear();

                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      )
                      : null,
              isDense: true,
              filled: true,
              fillColor: Colors.grey.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child:
              _filteredItems.isEmpty
                  ? const Center(
                    child: Text(
                      'لا توجد نتائج',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                  : ListView.separated(
                    itemCount: _filteredItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final u = _filteredItems[index];

                      final bool online = _isOnline(u);

                      return InkWell(
                        onTap: () => _showPatientDetails(context, u),
                        borderRadius: BorderRadius.circular(8),
                        child: Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF0D47A1,
                                        ).withOpacity(0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${_filteredItems.length - index}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0D47A1),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 10),

                                    Expanded(
                                      child: Text(
                                        _bestDisplayName(u),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    TextButton.icon(
                                      onPressed:
                                          () => _showPatientDetails(context, u),
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                        size: 17,
                                        color: Color(0xFF0D47A1),
                                      ),
                                      label: const Text(
                                        'عرض',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF0D47A1),
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),

                                    if (widget.showNewBadge)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Text(
                                          'جديد',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),

                                    const SizedBox(width: 6),

                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color:
                                            online ? Colors.green : Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                _PatientInfoRow(
                                  icon:
                                      online
                                          ? Icons.circle
                                          : Icons.circle_outlined,
                                  label: 'الحالة',
                                  value: online ? 'متصل الآن' : 'غير متصل',
                                  valueColor:
                                      online ? Colors.green : Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

// ================================================================
// PATIENT INFO ROW
// ================================================================

class _PatientInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _PatientInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey[600]),

        const SizedBox(width: 6),

        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),

        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.grey[800],
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================
// USERS LIST
// ================================================================

class _UsersList extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _UsersList({required this.items});

  String? _asNonEmptyString(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();

      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return null;
  }

  String _bestDisplayName(Map<String, dynamic> u) {
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

    if (fullNameLike != null) {
      return fullNameLike;
    }

    final String? first = _asNonEmptyString(
      u['firstName'] ?? u['first_name'] ?? u['fName'] ?? u['first'],
    );

    final String? last = _asNonEmptyString(
      u['lastName'] ?? u['last_name'] ?? u['lName'] ?? u['last'],
    );

    if (first != null && last != null) {
      return '$first $last';
    }

    if (first != null) {
      return first;
    }

    if (last != null) {
      return last;
    }

    final String? email = _asNonEmptyString(u['email']);

    if (email != null) {
      final int atIndex = email.indexOf('@');

      final String local = atIndex > 0 ? email.substring(0, atIndex) : email;

      final String beautified =
          local
              .replaceAll(RegExp(r'[._-]+'), ' ')
              .split(' ')
              .where((p) => p.trim().isNotEmpty)
              .map(
                (w) =>
                    w.isEmpty
                        ? w
                        : w[0].toUpperCase() +
                            (w.length > 1 ? w.substring(1) : ''),
              )
              .join(' ')
              .trim();

      if (beautified.isNotEmpty) {
        return beautified;
      }

      return email;
    }

    return 'بدون اسم';
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
          leading: Text(
            '${items.length - index}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}
