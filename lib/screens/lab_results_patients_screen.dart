import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'lab_patient_result_detail_screen.dart';

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
          title: Text('نتائج ${widget.labName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

            final perDayTotal = filtered.length;
            return ListView.separated(
              itemCount: filtered.length,
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = filtered[i];
                final data = d.data();
                final name = data['name']?.toString() ?? '';
                final dayNumber = perDayTotal - i; // رقم اليوم يبدأ من 1 لكل يوم
                // final labReqCol = col.doc(d.id).collection('lab_request');
                final status = (data['status']?.toString() ?? 'pending').toLowerCase();
                Color chipColor;
                switch (status) {
                  case 'received':
                    chipColor = Colors.blue;
                    break;
                  case 'inprocess':
                    chipColor = Colors.orange;
                    break;
                  case 'comlated':
                  case 'completed':
                    chipColor = Colors.green;
                    break;
                  default:
                    chipColor = Colors.grey;
                }
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
                      leading: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFF0D47A1), width: 2),
                        ),
                        child: Text(
                          '$dayNumber',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: chipColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: chipColor, width: 1),
                            ),
                            child: Text(
                              status == 'comlated' ? 'completed' : status,
                              style: TextStyle(color: chipColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ((data['id'] is int) ? data['id'] as int : (int.tryParse('${data['id'] ?? ''}') ?? 0)) > 0
                                ? '${(data['id'] is int) ? data['id'] as int : (int.tryParse('${data['id'] ?? ''}') ?? 0)}'
                                : d.id,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LabPatientResultDetailScreen(
                              labId: widget.labId,
                              labName: widget.labName,
                              patientDocId: d.id,
                            ),
                          ),
                        );
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


