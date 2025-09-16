import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SupportNumbersScreen extends StatefulWidget {
  const SupportNumbersScreen({super.key});

  @override
  State<SupportNumbersScreen> createState() => _SupportNumbersScreenState();
}

class _SupportNumbersScreenState extends State<SupportNumbersScreen> {
  bool _saving = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _promptAddNumber() async {
    final TextEditingController ctrl = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة رقم دعم فني'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('إضافة')),
        ],
      ),
    );
    if (confirmed == null || confirmed.isEmpty) return;
    setState(() => _saving = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('support').doc('phones');
      final doc = await docRef.get();
      final List<dynamic> numbers = (doc.data()?['numbers'] as List<dynamic>? ?? []).toList();
      numbers.add(confirmed);
      await docRef.set({'numbers': numbers}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إضافة الرقم: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editNumber(List<dynamic> currentNumbers, int index) async {
    final TextEditingController editCtrl = TextEditingController(text: currentNumbers[index].toString());
    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الرقم'),
        content: TextField(
          controller: editCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, editCtrl.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (newValue == null || newValue.isEmpty) return;
    try {
      final docRef = FirebaseFirestore.instance.collection('support').doc('phones');
      final updated = currentNumbers.toList();
      updated[index] = newValue;
      await docRef.set({'numbers': updated}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تعديل الرقم: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteNumber(List<dynamic> currentNumbers, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الرقم: ${currentNumbers[index]}؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final docRef = FirebaseFirestore.instance.collection('support').doc('phones');
      final updated = currentNumbers.toList();
      updated.removeAt(index);
      await docRef.set({'numbers': updated}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حذف الرقم: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF2FBDAF)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'أرقام الدعم الفني',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2FBDAF),
              fontSize: 24,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'إضافة رقم',
              onPressed: _saving ? null : _promptAddNumber,
              icon: const Icon(Icons.add, color: Color(0xFF2FBDAF)),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('support').doc('phones').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('خطأ: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = snapshot.data!.data() ?? {};
                      final List<dynamic> numbers = (data['numbers'] as List<dynamic>? ?? []);
                      if (numbers.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.support_agent, color: Colors.grey[400], size: 64),
                              const SizedBox(height: 12),
                              Text('لا توجد أرقام مسجلة', style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: numbers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final value = numbers[index].toString();
                          return Card(
                            elevation: 2,
                            child: ListTile(
                              title: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${index + 1} -',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2FBDAF),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    value,
                                    textDirection: TextDirection.ltr,
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'تعديل',
                                    onPressed: () => _editNumber(numbers, index),
                                    icon: const Icon(Icons.edit, color: Color(0xFF2FBDAF)),
                                  ),
                                  IconButton(
                                    tooltip: 'حذف',
                                    onPressed: () => _deleteNumber(numbers, index),
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


