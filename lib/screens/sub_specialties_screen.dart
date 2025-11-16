import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SubSpecialtiesScreen extends StatefulWidget {
  final String parentId;
  final String parentName;

  const SubSpecialtiesScreen({
    super.key,
    required this.parentId,
    required this.parentName,
  });

  @override
  State<SubSpecialtiesScreen> createState() => _SubSpecialtiesScreenState();
}

class _SubSpecialtiesScreenState extends State<SubSpecialtiesScreen> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("تخصصات ${widget.parentName} الفرعية"),
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF0D47A1),
        ),

        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddSubSpecialtyDialog(),
          backgroundColor: const Color(0xFF0D47A1),
          child: const Icon(Icons.add),
        ),

        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('medicalSpecialties')
              .doc(widget.parentId)
              .collection('subSpecialties')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final docs = snapshot.data!.docs;

            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  "لا توجد تخصصات فرعية",
                  style: TextStyle(fontSize: 18),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;

                return Card(
                  child: ListTile(
                    title: Text(data['name']),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showAddSubSpecialtyDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("إضافة تخصص فرعي"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "اسم التخصص الفرعي",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await FirebaseFirestore.instance
                    .collection('medicalSpecialties')
                    .doc(widget.parentId)
                    .collection('subSpecialties')
                    .add({
                  'name': controller.text.trim(),
                });
              }
            },
            child: const Text("إضافة"),
          )
        ],
      ),
    );
  }
}
