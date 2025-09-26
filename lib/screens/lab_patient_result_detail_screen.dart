import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LabPatientResultDetailScreen extends StatelessWidget {
  final String labId;
  final String labName;
  final String patientDocId;
  const LabPatientResultDetailScreen({super.key, required this.labId, required this.labName, required this.patientDocId});

  Future<Map<String, dynamic>> _loadPatientAndTests() async {
    final patientRef = FirebaseFirestore.instance
        .collection('labToLap')
        .doc('global')
        .collection('patients')
        .doc(patientDocId);
    final pSnap = await patientRef.get();
    final pData = pSnap.data() ?? {};
    final idDyn = pData['id'];
    final intId = (idDyn is int) ? idDyn : int.tryParse('${idDyn ?? ''}') ?? 0;
    final testsSnap = await patientRef.collection('lab_request').get();
    final tests = testsSnap.docs.map((d) => d.data()).toList();
    return {
      'id': intId,
      'name': pData['name']?.toString() ?? '',
      'status': (pData['status']?.toString() ?? 'pending').toLowerCase(),
      'tests': tests,
    };
  }

  // removed old linear progress calculation, replaced by segmented bar

  Color _statusColor(String status) {
    switch (status) {
      case 'received':
        return Colors.blue;
      case 'inprocess':
        return Colors.orange;
      case 'comlated':
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatPrice(num price) {
    final str = price.toStringAsFixed(0);
    return str.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  num _calcTotal(List<Map<String, dynamic>> tests) {
    num total = 0;
    for (final t in tests) {
      final p = t['price'];
      if (p is num) {
        total += p;
      } else {
        final n = num.tryParse('$p');
        if (n != null) total += n;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('بيانات المريض', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _loadPatientAndTests(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snap.data ?? {'id': 0, 'name': '', 'status': 'pending', 'tests': <Map<String, dynamic>>[]};
            final intId = data['id'] as int? ?? 0;
            final name = data['name'] as String? ?? '';
            final status = (data['status']?.toString() ?? 'pending').toLowerCase();
            final tests = (data['tests'] as List).cast<Map<String, dynamic>>();
            final total = _calcTotal(tests);

            return Column(
              children: [
                // Status chip on top-left
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _statusColor(status), width: 1),
                        ),
                        child: Text(status == 'comlated' ? 'completed' : status, style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Centered ID and Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(intId > 0 ? '$intId' : patientDocId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87), textAlign: TextAlign.center),
                        const SizedBox(height: 6),
                        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 26)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Tests list within fixed area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: tests.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (context, i) {
                        final t = tests[i];
                        final tName = t['name']?.toString() ?? '';
                        final priceDyn = t['price'];
                        final price = (priceDyn is num) ? priceDyn : (num.tryParse('$priceDyn') ?? 0);
                        return Row(
                          children: [
                            Expanded(child: Text('${i + 1}- $tName', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Text(_formatPrice(price), style: const TextStyle(color: Colors.black87)),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // Bottom fixed area: total, PDF button, progress bar
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Text('المبلغ: ${_formatPrice(total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سيتم إضافة عرض النتائج PDF قريباً')));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                              ),
                            ),
                            child: const Text('عرض النتيجة PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Segmented progress bar (4 segments) LTR: pending starts at left
                        Builder(
                          builder: (context) {
                            final labels = ['pending', 'received', 'inprocess', 'completed'];
                            final colors = [Colors.grey, Colors.blue, Colors.orange, Colors.green];
                            int activeIndex = 0;
                            switch (status) {
                              case 'received':
                                activeIndex = 1;
                                break;
                              case 'inprocess':
                                activeIndex = 2;
                                break;
                              case 'comlated':
                              case 'completed':
                                activeIndex = 3;
                                break;
                              case 'pending':
                              default:
                                activeIndex = 0;
                            }
                            return Column(
                              children: [
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      height: 14,
                                      child: Row(
                                        children: List.generate(4, (i) {
                                          final bool isActive = i == activeIndex;
                                          return Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: isActive ? colors[i] : colors[i].withOpacity(0.25),
                                                border: isActive ? Border.all(color: colors[i], width: 2) : null,
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Status labels under the bar with active emphasis
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: List.generate(4, (i) {
                                      final bool isActive = i == activeIndex;
                                      return Text(
                                        labels[i],
                                        style: TextStyle(
                                          color: colors[i],
                                          fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                                          fontSize: 12,
                                          decoration: isActive ? TextDecoration.underline : TextDecoration.none,
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


