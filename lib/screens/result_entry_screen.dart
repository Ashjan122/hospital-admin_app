import 'package:flutter/material.dart';
import 'package:dio/dio.dart';


class ResultEntryScreen extends StatefulWidget {
  final String labRequestId;
  final String mainTestName;
  final String mainTestId;
  

  const ResultEntryScreen({
    super.key,
    required this.labRequestId,
    required this.mainTestName,
    required this.mainTestId,
    
  });

  @override
  State<ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<ResultEntryScreen> {
  bool isLoading = true;
  String errorMessage = '';
  Map<String, dynamic>? resultData;

  @override
  void initState() {
    super.initState();
    fetchResults();
  }

  Future<void> fetchResults() async {
    try {
      final dio = Dio();

      final response = await dio.get(
        'https://alroomy.a.pinggy.link/jawda-medical/public/api/labrequests/${widget.labRequestId}/for-result-entry');
      

      if (response.statusCode == 200) {
        final data = response.data['data'];
        if (data != null) {
          setState(() {
            resultData = data;
            isLoading = false;
          });
          

        } else {
          setState(() {
            errorMessage = 'لا توجد بيانات لهذا الفحص.';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'فشل في تحميل البيانات (رمز: ${response.statusCode})';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء تحميل البيانات: $e';
        isLoading = false;
      });
    }
    
  }

  @override
  Widget build(BuildContext context) {
    final Color color1 = const Color.fromARGB(255, 215, 213, 219);
    final Color color2 = const Color.fromARGB(255, 156, 208, 235);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.mainTestName,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color.fromARGB(255, 156, 208, 235),
          centerTitle: true,
        ),
        body:SafeArea(child: SizedBox.expand(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color1,
                  Color.fromARGB(255, 156, 208, 235).withOpacity(0.2),
                  Color.fromARGB(255, 156, 208, 235).withOpacity(0.4),
                  Color.fromARGB(255, 156, 208, 235).withOpacity(0.6),
                ],
              ),
            ),
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                    ? Center(child: Text(errorMessage))
                    : _buildResultView(),
          ),
        ),),
      ),
    );
  }

  Widget _buildResultView() {
    final allChildTests = resultData?['child_tests_with_results'] ?? [];

    if (allChildTests.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد نتائج لهذا الفحص.',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      );
    }

    return SafeArea(child:  SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.vertical,
      child: Table(
        border: TableBorder.symmetric(
          inside: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
        columnWidths: const {
          0: FlexColumnWidth(1), // عمود اسم الفحص
          1: FlexColumnWidth(3), // عمود النتيجة يأخذ أكبر مساحة
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          // Header
          TableRow(
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Text(
                  'Test',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Text(
                  'Result',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          // Data rows
          ...allChildTests.map((test) {
            final resultValue = test['result_value']?.toString() ?? '-';
            final unitName = test['unit_name'] ?? '';
            final normalRange = test['normalRange'] ?? test['normal_range'] ?? '';

            Color valueColor = Colors.black87;
            if (resultValue != '-' && normalRange.isNotEmpty) {
              try {
                final reg = RegExp(r'(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)');
                final match = reg.firstMatch(normalRange);
                if (match != null) {
                  final low = double.tryParse(match.group(1) ?? '') ?? double.negativeInfinity;
                  final high = double.tryParse(match.group(2) ?? '') ?? double.infinity;
                  final val = double.tryParse(resultValue);
                  if (val != null) {
                    valueColor = (val < low || val > high) ? Colors.red : Colors.green;
                  }
                }
              } catch (_) {
                valueColor = Colors.black87;
              }
            }

            return TableRow(
              decoration: const BoxDecoration(color: Colors.white),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    test['child_test_name'] ?? '-',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: GestureDetector(
                    onLongPress: () {
                      if (normalRange.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('النطاق الطبيعي', textDirection: TextDirection.rtl,),
                            content: Text(normalRange, textDirection: TextDirection.rtl,),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('إغلاق'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$resultValue $unitName',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: valueColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    ),
    );
  }
}

