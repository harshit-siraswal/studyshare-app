import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/services/backend_api_service.dart';

void main() {
  testWidgets('updateResourceStatus sends PATCH instead of GET', (
    tester,
  ) async {
    late BuildContext testContext;
    http.BaseRequest? capturedRequest;

    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            testContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final service = BackendApiService(
      httpClient: client,
      startMaintenanceTimer: false,
    );

    await service.updateResourceStatus(
      resourceId: '95aeade0-2eb7-4b5c-b776-39352479ef1f',
      status: 'approved',
      bearerToken: 'test-token',
      context: testContext,
    );

    expect(capturedRequest, isNotNull, reason: 'HTTP request was never made');

    expect(capturedRequest!.method, 'PATCH');
    expect(
      capturedRequest!.url.path,
      '/api/admin/resources/95aeade0-2eb7-4b5c-b776-39352479ef1f/status',
    );
    expect(capturedRequest!.headers['authorization'], 'Bearer test-token');

    final body = (capturedRequest as http.Request).body;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(decoded['status'], 'approved');
  });

  testWidgets('deleteResourceAsAdmin falls back to legacy POST on 404', (
    tester,
  ) async {
    final requests = <http.BaseRequest>[];

    final client = MockClient((request) async {
      requests.add(request);
      if (requests.length == 1) {
        return http.Response('{"error":"Not found"}', 404);
      }
      return http.Response('{"success":true}', 200);
    });

    final service = BackendApiService(
      httpClient: client,
      startMaintenanceTimer: false,
    );

    await service.deleteResourceAsAdmin(
      resourceId: '95aeade0-2eb7-4b5c-b776-39352479ef1f',
      bearerToken: 'test-token',
    );

    expect(requests, hasLength(2));
    expect(requests.first.method, 'DELETE');
    expect(
      requests.first.url.path,
      '/api/admin/resources/95aeade0-2eb7-4b5c-b776-39352479ef1f',
    );

    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/admin');
    expect(requests.last.headers['authorization'], 'Bearer test-token');

    final body = (requests.last as http.Request).body;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(decoded['action'], 'delete_resource');
    expect(decoded['resourceId'], '95aeade0-2eb7-4b5c-b776-39352479ef1f');
    expect(decoded['keyHash'], 'test-token');
  });

  test(
    'queryRag sends explicit local retrieval flags when web is off',
    () async {
      http.BaseRequest? capturedRequest;

      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('{"answer":"ok"}', 200);
      });

      final service = BackendApiService(
        httpClient: client,
        startMaintenanceTimer: false,
      );

      final response = await service.queryRag(
        question: 'Explain this topic from my notes',
        allowWeb: false,
        fileId: 'file-123',
      );

      expect(response['answer'], 'ok');
      expect(capturedRequest, isA<http.Request>());

      final body =
          jsonDecode((capturedRequest as http.Request).body)
              as Map<String, dynamic>;
      expect(body['allow_web'], isFalse);
      expect(body['retrieval_mode'], 'local');
      expect(body['strict_notes_mode'], isTrue);
      expect(body['file_id'], 'file-123');
    },
  );

  test('queryRag sends explicit web retrieval flags when web is on', () async {
    http.BaseRequest? capturedRequest;

    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('{"answer":"ok"}', 200);
    });

    final service = BackendApiService(
      httpClient: client,
      startMaintenanceTimer: false,
    );

    await service.queryRag(
      question: 'Search the web for this topic',
      allowWeb: true,
    );

    expect(capturedRequest, isA<http.Request>());

    final body =
        jsonDecode((capturedRequest as http.Request).body)
            as Map<String, dynamic>;
    expect(body['allow_web'], isTrue);
    expect(body['retrieval_mode'], 'web');
    expect(body['strict_notes_mode'], isFalse);
  });

  test('queryRag retries once after a transient connection reset', () async {
    var requestCount = 0;

    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        throw http.ClientException('Connection reset by peer');
      }
      return http.Response('{"answer":"retry ok"}', 200);
    });

    final service = BackendApiService(
      httpClient: client,
      startMaintenanceTimer: false,
    );

    final response = await service.queryRag(
      question: 'Explain this topic from my notes',
      allowWeb: false,
    );

    expect(response['answer'], 'retry ok');
    expect(requestCount, 2);
  });

  test('checkFollowStatus uses the singular follow status endpoint', () async {
    http.BaseRequest? capturedRequest;

    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('{"status":"following"}', 200);
    });

    final service = BackendApiService(
      httpClient: client,
      startMaintenanceTimer: false,
    );

    final response = await service.checkFollowStatus('test.user@example.com');

    expect(response['status'], 'following');
    expect(capturedRequest, isA<http.Request>());
    expect(
      capturedRequest!.url.path,
      '/api/follow/status/test.user%40example.com',
    );
  });
}
