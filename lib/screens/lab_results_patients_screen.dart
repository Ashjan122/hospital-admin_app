import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'lab_request_summary_screen.dart';

class LabResultsPatientsScreen extends StatefulWidget {
  final String labId;
  final String labName;
  const LabResultsPatientsScreen({super.key, required this.labId, required this.labName});

  @override
  State<LabResultsPatientsScreen> createState() => _LabResultsPatientsScreenState();
}

class _LabResultsPatientsScreenState extends State<LabResultsPatientsScreen> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(Timestamp? ts, DateTime day) {
    if (ts == null) return false;
    final dt = ts.toDate();
    return dt.year == day.year && dt.month == day.month && dt.day == day.day;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'اختر التاريخ',
      cancelText: 'إلغاء',
      confirmText: 'موافق',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('labToLap')
        .doc('global')
        .collection('patients');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('نتائج المرضى - ${widget.labName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'اختيار التاريخ',
              icon: const Icon(Icons.calendar_today, color: Colors.white),
              onPressed: _pickDate,
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: col.where('labId', isEqualTo: widget.labId).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            // فلترة حسب تاريخ اليوم المحدد
            final filtered = snap.data!.docs.where((doc) {
              final m = doc.data();
              final ts = m['createdAt'];
              final t = (ts is Timestamp) ? ts : null;
              return _isSameDay(t, _selectedDate);
            }).toList();

            // ترتيب تنازلي حسب createdAt
            filtered.sort((a, b) {
              final aTs = a.data()['createdAt'];
              final bTs = b.data()['createdAt'];
              final aT = (aTs is Timestamp) ? aTs : null;
              final bT = (bTs is Timestamp) ? bTs : null;
              if (aT == null && bT == null) return 0;
              if (aT == null) return 1;
              if (bT == null) return -1;
              return bT.compareTo(aT);
            });

            if (filtered.isEmpty) {
              return const Center(child: Text('لا توجد عينات لليوم المحدد'));
            }

            return ListView.separated(
              itemCount: filtered.length,
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = filtered[i];
                final data = d.data();
                final name = data['name']?.toString() ?? '';
                final dynamicId = data['id'];
                final intId = (dynamicId is int)
                    ? dynamicId
                    : int.tryParse('${dynamicId ?? ''}') ?? 0;
                final idLabel = intId > 0 ? '$intId-' : '${d.id}-';
                final labReqCol = col.doc(d.id).collection('lab_request');
                return Card(
                  child: ListTileTheme(
                    data: const ListTileThemeData(
                      horizontalTitleGap: 8,
                      minLeadingWidth: 0,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: ListTile(
                      minLeadingWidth: 0,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Text(
                        idLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        future: labReqCol.get(),
                        builder: (context, snapCount) {
                          final count = (snapCount.data?.docs.length ?? 0);
                          return Text(
                            'عدد الفحوصات: $count',
                            style: const TextStyle(color: Colors.black54),
                          );
                        },
                      ),
                      onTap: () async {
                        // جلب الفحوصات المحفوظة للمريض
                        final labReqSnapshot = await labReqCol.get();
                        final selectedTests = labReqSnapshot.docs.map((doc) {
                          final data = doc.data();
                          return {
                            'name': data['name'],
                            'price': data['price'],
                            'container_id': data['container_id'],
                          };
                        }).toList();
                        
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LabRequestSummaryScreen(
                                labId: widget.labId,
                                labName: widget.labName,
                                patientId: d.id,
                                selectedTests: selectedTests,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}


