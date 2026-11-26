import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:para_mobile/core/api.dart';

void main() {
  test('Каталог читается из кэша до явного обновления', () async {
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://store.example/v1',
      client: MockClient((request) async {
        calls++;
        return http.Response('{"products":[],"brands":[],"models":[]}', 200);
      }),
    );
    await api.catalogue('City', '', '');
    await api.catalogue('City', '', '');
    expect(calls, 1);
    await api.catalogue('City', '', '', refresh: true);
    expect(calls, 2);
    await api.catalogue('Trail', '', '');
    expect(calls, 3);
    api.close();
  });
  test('Личные данные не используют кэш каталога', () async {
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://store.example/v1',
      client: MockClient((request) async {
        calls++;
        expect(request.headers['authorization'], 'Bearer example-token');
        return http.Response(
          '{"items":[],"subtotal":"0.00","max_points":0}',
          200,
        );
      }),
    ).token = 'example-token';
    await api.send('GET', '/cart');
    await api.send('GET', '/cart');
    expect(calls, 2);
    api.close();
  });
  test('Цена и роль не передаются клиентом при оформлении', () async {
    final api = ApiClient(
      baseUrl: 'https://store.example/v1',
      client: MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body.containsKey('total'), false);
        expect(body.containsKey('user_id'), false);
        expect(body['points'], 249);
        return http.Response('{"id":1}', 201);
      }),
    );
    await api.send(
      'POST',
      '/orders',
      data: {
        'token': 'a' * 32,
        'recipient': 'Анна',
        'address': 'Учебный адрес',
        'points': 249,
      },
    );
    api.close();
  });
  test('Ошибка сервера сохраняет код ответа для обработки', () async {
    final api = ApiClient(
      baseUrl: 'https://store.example/v1',
      client: MockClient(
        (request) async => http.Response('{"message":"Not enough stock"}', 400),
      ),
    );
    await expectLater(
      api.send('GET', '/cart'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
    );
    api.close();
  });
}
