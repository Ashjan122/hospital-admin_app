import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class LabRequestSummaryScreen extends StatelessWidget {
  final String labId;
  final String labName;
  final String patientId;
  final List<Map<String, dynamic>> selectedTests; // {name, price, containerId}
  const LabRequestSummaryScreen({super.key, required this.labId, required this.labName, required this.patientId, required this.selectedTests});

  Future<String> _getPatientName() async {
    final doc = await FirebaseFirestore.instance
        .collection('labToLap')
        .doc('global')
        .collection('patients')
        .doc(patientId)
        .get();
    return doc.data()?['name']?.toString() ?? '';
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ملخص الطلب - $labName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
        ),
        body: FutureBuilder<String>(
          future: _getPatientName(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final patientName = snap.data ?? '';
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF0D47A1)),
                      const SizedBox(width: 8),
                      Text('المريض: $patientName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Blood Container', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.9,
                      ),
                      itemCount: selectedTests.length,
                      itemBuilder: (context, index) {
                        final t = selectedTests[index];
                        final containerId = (t['containerId'] ?? t['container_id'])?.toString() ?? '';
                        final name = t['name']?.toString() ?? '';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                Expanded(
                                  child: FutureBuilder<String?>(
                                    future: containerId.isEmpty ? Future.value(null) : _getContainerUrl(containerId),
                                    builder: (context, snapImg) {
                                      if (snapImg.connectionState == ConnectionState.waiting) {
                                        return const Center(child: CircularProgressIndicator());
                                      }
                                      final url = snapImg.data;
                                      if (url == null) {
                                        return const Center(child: Icon(Icons.image_not_supported, color: Colors.grey, size: 48));
                                      }
                                      return Image.network(url, fit: BoxFit.contain);
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text('الإجمالي: ${_totalPrice()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0D47A1))),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}


