import 'package:dio/dio.dart';

class ApiClient {
  // Siguraduhin na walang extra spaces o hidden characters dito
  static const String baseUrl = "https://indigo-bear-885857.hostingersite.com/backend/";

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
    // Force direct connection to avoid any accidental proxy issues
    followRedirects: true,
  ));

  static Dio get instance => _dio;
}
