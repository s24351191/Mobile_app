import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  const ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final http.Client client;
  final Uri base;
  String? token, staffToken;
  String language = 'ru';
  final _catalog = <String, (DateTime, Json)>{};
  ApiClient({required String baseUrl, http.Client? client})
      : base = Uri.parse(baseUrl.replaceFirst(RegExp(r'/$'), '')),
        client = client ?? http.Client();
  Uri url(String path) => Uri.parse('$base$path');
  Map<String, String> headers({bool staff = false}) => {
        'Content-Type': 'application/json',
        'Accept-Language': language,
        if ((staff ? staffToken : token) != null)
          'Authorization': 'Bearer ${staff ? staffToken : token}',
      };
  Future<dynamic> send(
    String method,
    String path, {
    Json? data,
    bool staff = false,
  }) async {
    final request = http.Request(method, url(path))
      ..headers.addAll(headers(staff: staff));
    if (data != null) request.body = jsonEncode(data);
    try {
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          value['message'] ?? 'HTTP ${response.statusCode}',
        );
      }
      return value;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(0, 'network');
    }
  }

  Future<Json> catalogue(
    String query,
    String brand,
    String model, {
    bool refresh = false,
  }) async {
    final path =
        '/catalog?${Uri(queryParameters: {'q': query, 'brand': brand, 'model': model}).query}';
    final key = '$language$path';
    final cached = _catalog[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.$1).inSeconds < 30) {
      return cached.$2;
    }
    final Json value = await send('GET', path);
    _catalog[key] = (DateTime.now(), value);
    return value;
  }

  void clearCatalogue() => _catalog.clear();
  String imageUrl(String path) {
    if (path.startsWith('https://')) return path;
    final prefix = base.path.replaceFirst(RegExp(r'/v1$'), '');
    return base.replace(path: '$prefix$path', query: null).toString();
  }

  Future<Json> saveProduct(
    Json fields,
    List<int>? photo,
    String? filename,
  ) async {
    final request = http.MultipartRequest('POST', url('/staff/products'))
      ..headers.addAll(headers(staff: true)..remove('Content-Type'))
      ..fields['payload'] = jsonEncode(fields);
    if (photo != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photo,
          filename: filename ?? 'photo.jpg',
        ),
      );
    }
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 30)),
    );
    final Json value = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400)
      throw ApiException(response.statusCode, value['message']);
    clearCatalogue();
    return value;
  }

  void close() => client.close();
}
