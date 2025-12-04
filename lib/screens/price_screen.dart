import 'package:flutter/material.dart';
import 'package:dio/dio.dart';


class PricesScreen extends StatefulWidget {
  final String centerId;
  const PricesScreen({super.key, required this.centerId});

  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> {
  List<dynamic> prices = [];
  bool isLoading = true;
  String errorMessage = '';
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final Color _color1 = const Color.fromARGB(255, 215, 213, 219);
  final Color _color2 = const Color.fromARGB(255, 156, 208, 235);

  @override
  void initState() {
    super.initState();
    fetchPrices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _extractErrorMessage(dynamic e) {
    if (e is DioException) {
      if (e.response != null && e.response!.data != null) {
        final data = e.response!.data;
        
        // محاولة استخراج الرسالة من حقول مختلفة
        if (data is Map) {
          // محاولة الحصول على message
          if (data['message'] != null) {
            return data['message'].toString();
          }
          // محاولة الحصول على error
          if (data['error'] != null) {
            if (data['error'] is String) {
              return data['error'];
            } else if (data['error'] is Map && data['error']['message'] != null) {
              return data['error']['message'].toString();
            }
          }
          // محاولة الحصول على errors (قائمة)
          if (data['errors'] != null) {
            if (data['errors'] is Map) {
              final errors = data['errors'] as Map;
              if (errors.isNotEmpty) {
                final firstError = errors.values.first;
                if (firstError is List && firstError.isNotEmpty) {
                  return firstError.first.toString();
                } else if (firstError is String) {
                  return firstError;
                }
              }
            }
          }
        }
        
        // إذا لم نجد رسالة واضحة، نعيد status code
        return 'خطأ ${e.response!.statusCode}: ${e.response!.statusMessage ?? 'حدث خطأ'}';
      }
      
      // إذا لم يكن هناك response، نعيد رسالة الاتصال
      return 'خطأ في الاتصال بالسيرفر: ${e.message ?? 'يرجى التحقق من الاتصال بالإنترنت'}';
    }
    
    return 'حدث خطأ غير متوقع: $e';
  }

  Future<void> fetchPrices() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final dio = Dio();
     
      dio.options.headers['Accept'] = 'application/json';

      final url = 'https://alroomy.a.pinggy.link/jawda-medical/public/api/main-tests';
      final response = await dio.get(
        url,
        queryParameters: {'page': 1, 'search': searchQuery, 'per_page': 1000},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data.containsKey('data')) {
          setState(() {
            prices = data['data'];
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'لم يتم العثور على بيانات.';
            isLoading = false;
          });
        }
      } else {
        // محاولة استخراج رسالة الخطأ من response
        String errorMsg = 'خطأ في الاتصال (${response.statusCode})';
        if (response.data != null && response.data is Map) {
          final responseData = response.data as Map;
          if (responseData['message'] != null) {
            errorMsg = responseData['message'].toString();
          } else if (responseData['error'] != null) {
            if (responseData['error'] is String) {
              errorMsg = responseData['error'];
            } else if (responseData['error'] is Map && responseData['error']['message'] != null) {
              errorMsg = responseData['error']['message'].toString();
            }
          } else if (responseData['errors'] != null && responseData['errors'] is Map) {
            final errors = responseData['errors'] as Map;
            if (errors.isNotEmpty) {
              final firstError = errors.values.first;
              if (firstError is List && firstError.isNotEmpty) {
                errorMsg = firstError.first.toString();
              } else if (firstError is String) {
                errorMsg = firstError;
              }
            }
          }
        }
        
        setState(() {
          errorMessage = errorMsg;
          isLoading = false;
        });
      }
    } on DioException catch (e) {
      setState(() {
        errorMessage = _extractErrorMessage(e);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ غير متوقع: $e';
        isLoading = false;
      });
    }
  }

  Widget _buildPriceItem(Map<String, dynamic> item) {
    final name = item['name'] ?? 'غير معروف';
    final price = item['price'] ?? 0;

    return Card(
      color: Colors.white,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        trailing: Text(
          '$price',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'قائمة الأسعار',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color.fromARGB(255, 156, 208, 235),
          centerTitle: true,
        ),
        body:  Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: TextField(
                  controller: _searchController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'البحث باسم الفحص...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() => searchQuery = value);
                    fetchPrices();
                  },
                ),
              ),

              Expanded(
                child:
                    isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage.isNotEmpty
                        ? Center(
                          child: Text(
                            errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                        : RefreshIndicator(
                          onRefresh: fetchPrices,
                          child: ListView.builder(
                            itemCount: prices.length,
                            itemBuilder: (context, index) {
                              final item = prices[index];
                              return _buildPriceItem(
                                item as Map<String, dynamic>,
                              );
                            },
                          ),
                        ),
              ),
            ],
          ),
        ),
      
    );
  }
}
