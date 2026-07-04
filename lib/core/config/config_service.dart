import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';

class ConfigService {
  final Dio _dio = ApiClient.instance;

  Future<Map<String, dynamic>?> fetchConfig() async {
    try {
      final response = await _dio.get('/config');
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      debugPrint('Config fetch failed: ${e.type}');
      return null;
    }
  }
}
