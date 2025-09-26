import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'lab_results_patients_screen.dart';

class LabRequestSummaryScreen extends StatelessWidget {
  final String labId;
  final String labName;
  final String patientId;
  final List<Map<String, dynamic>> selectedTests; // {name, price, containerId}
  final bool fromPatientsList;
  const LabRequestSummaryScreen({super.key, required this.labId, required this.labName, required this.patientId, required this.selectedTests, this.fromPatientsList = false});

  Future<Map<String, dynamic>> _getPatientInfo() async {
    final doc = await FirebaseFirestore.instance
        .collection('labToLap')
        .doc('global')
        .collection('patients')
        .doc(patientId)
        .get();
    final data = doc.data() ?? {};
    final dynamicId = data['id'];
    final intId = (dynamicId is int) ? dynamicId : int.tryParse('${dynamicId ?? ''}') ?? 0;
    return {
      'id': intId,
      'name': data['name']?.toString() ?? '',
    };
  }

  Future<String?> _getContainerUrl(String containerId) async {
    try {
      final ref = FirebaseStorage.instance.ref('containers/$containerId.png');
      return await ref.getDownloadURL();
    } catch (_) {
      try {
        final ref = FirebaseStorage.instance.ref('containers/$containerId.jpg');
        return await ref.getDownloadURL();
      } catch (e) {
        return null;
      }
    }
  }

  num _totalPrice() {
    num sum = 0;
    for (final t in selectedTests) {
      final p = t['price'];
      if (p is num) sum += p; else { final n = num.tryParse('$p'); if (n != null) sum += n; }
    }
    return sum;
  }

  String _formatPrice(num price) {
    final str = price.toStringAsFixed(0);
    return str.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ملخص الطلب ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    'المبلغ: ${_formatPrice(_totalPrice())}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: fromPatientsList
                        ? null
                        : () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LabResultsPatientsScreen(labId: labId, labName: labName),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                      ),
                    ),
                    child: Text(fromPatientsList ? 'عرض النتيجة' : 'متابعة', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _getPatientInfo(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final info = snap.data ?? {'id': 0, 'name': ''};
            final patientIdNum = info['id'] as int? ?? 0;
            final patientName = info['name'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          patientIdNum > 0 ? '$patientIdNum' : '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 25, color: Colors.black87),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          patientName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 26),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final Map<String, List<String>> containerToNames = {};
                      for (final t in selectedTests) {
                        final containerId = (t['containerId'] ?? t['container_id'])?.toString() ?? '';
                        final name = t['name']?.toString() ?? '';
                        if (containerId.isEmpty && name.isEmpty) continue;
                        containerToNames.putIfAbsent(containerId, () => []);
                        if (name.isNotEmpty) containerToNames[containerId]!.add(name);
                      }
                      final entries = containerToNames.entries.toList();
                      return SizedBox(
                        height: 360,
                        child: ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            final cid = e.key;
                            final names = e.value;
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 64,
                                      height: 64,
                                      child: FutureBuilder<String?>(
                                        future: cid.isEmpty ? Future.value(null) : _getContainerUrl(cid),
                                        builder: (context, snapImg) {
                                          if (snapImg.connectionState == ConnectionState.waiting) {
                                            return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
                                          }
                                          final url = snapImg.data;
                                          if (url == null) {
                                            return const Center(child: Icon(Icons.image_not_supported, color: Colors.grey, size: 28));
                                          }
                                          return Image.network(url, fit: BoxFit.contain);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        names.join(' , '),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const SizedBox.shrink(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}


