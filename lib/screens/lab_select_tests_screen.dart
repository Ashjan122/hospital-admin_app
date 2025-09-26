import 'lab_request_summary_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LabSelectTestsScreen extends StatefulWidget {
  final String labId;
  final String labName;
  final String patientId;
  const LabSelectTestsScreen({super.key, required this.labId, required this.labName, required this.patientId});

  @override
  State<LabSelectTestsScreen> createState() => _LabSelectTestsScreenState();
}

class _LabSelectTestsScreenState extends State<LabSelectTestsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedIds = <String>{};
  bool _saving = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _priceCol => FirebaseFirestore.instance
      .collection('labToLap')
      .doc(widget.labId)
      .collection('pricelist');

  Future<void> _saveSelection(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_selectedIds.isEmpty) return;
    setState(() => _saving = true);
    try {
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      final reqCol = FirebaseFirestore.instance
          .collection('labToLap')
          .doc('global')
          .collection('patients')
          .doc(widget.patientId)
          .collection('lab_request');

      final selectedDocs = docs.where((d) => _selectedIds.contains(d.id));
      for (final d in selectedDocs) {
        final data = d.data();
        final reqDocRef = reqCol.doc();
        batch.set(reqDocRef, {
          'testId': d.id,
          'name': data['name'],
          'price': data['price'],
          'container_id': data['container_id'] ?? data['containerId'],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الطلب'), backgroundColor: Colors.green),
      );
      Navigator.pop(context); // الرجوع إلى شاشة العينة
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('اختيار الفحوصات - ${widget.labName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D47A1),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: Text(_selectedIds.isEmpty ? '' : 'المحدد: ${_selectedIds.length}', style: const TextStyle(color: Colors.white)),
              ),
            ),
            IconButton(
              tooltip: 'حفظ',
              onPressed: _saving ? null : () {},
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : const Icon(Icons.save, color: Colors.white),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  labelText: 'بحث باسم الفحص',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _priceCol.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snap.data!.docs.where((d) {
                    final n = (d.data()['name']?.toString() ?? '').toLowerCase();
                    if (_searchQuery.isEmpty) return true;
                    return n.contains(_searchQuery);
                  }).toList();
                  // sort by numeric id ascending; items without valid id go last by doc id
                  docs.sort((a, b) {
                    final ida = a.data()['id'];
                    final idb = b.data()['id'];
                    final ia = (ida is num) ? ida.toInt() : int.tryParse('${ida ?? ''}');
                    final ib = (idb is num) ? idb.toInt() : int.tryParse('${idb ?? ''}');
                    if (ia != null && ib != null) return ia.compareTo(ib);
                    if (ia != null) return -1;
                    if (ib != null) return 1;
                    return a.id.compareTo(b.id);
                  });

                  return ListView.separated(
                    itemCount: docs.length,
                    padding: const EdgeInsets.all(16),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data();
                      final name = data['name']?.toString() ?? '';
                      final price = data['price'];
                      final selected = _selectedIds.contains(d.id);
                      return Card(
                        child: CheckboxListTile(
                          value: selected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.add(d.id);
                              } else {
                                _selectedIds.remove(d.id);
                              }
                            });
                          },
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('السعر: ${price ?? 0}'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final snap = await _priceCol.get();
                            final allDocs = snap.docs;
                            final selectedDocs = allDocs.where((d) => _selectedIds.contains(d.id)).toList();
                            // save to lab_request
                            await _saveSelection(allDocs);
                            if (!mounted) return;
                            // navigate to summary with selected items info (including containerId if present)
                            final items = selectedDocs.map((d) => {
                              'name': d.data()['name'],
                              'price': d.data()['price'],
                              'containerId': d.data()['containerId'] ?? d.data()['container_id'],
                            }).toList();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LabRequestSummaryScreen(
                                  labId: widget.labId,
                                  labName: widget.labName,
                                  patientId: widget.patientId,
                                  selectedTests: items,
                                ),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                        : const Text('حفظ '),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


