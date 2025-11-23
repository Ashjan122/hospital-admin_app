import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class PdfViewScreen extends StatefulWidget {
  final String pdfUrl;
  

  const PdfViewScreen({super.key, required this.pdfUrl, });

  @override
  State<PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<PdfViewScreen> {
  File? localPdf;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/lab_result_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final dio = Dio();

      // 👇 نحمل الملف بالرابط مع التوكن
      final response = await dio.get(
        widget.pdfUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            
            'Accept': 'application/pdf',
          },
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(response.data);
      setState(() {
        localPdf = file;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نتيجة التحاليل',style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),),
        backgroundColor: const Color(0xFF2FBDAF),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2FBDAF)))
          : error != null
              ? Center(child: Text('فشل تحميل الملف:\n$error'))
              : SfPdfViewer.file(localPdf!),
    );
  }
}
