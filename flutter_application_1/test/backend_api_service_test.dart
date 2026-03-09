import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/services/backend_api_service.dart';

void main() {
  test(
    'compatibility fallback helper only accepts unsupported-route errors',
    () {
      expect(
        isBackendCompatibilityFallbackError(
          const BackendApiHttpException(statusCode: 404, message: 'Not found'),
        ),
        isTrue,
      );
      expect(
        isBackendCompatibilityFallbackError(
          const BackendApiHttpException(
            statusCode: 405,
            message: 'Method not allowed',
          ),
        ),
        isTrue,
      );
      expect(
        isBackendCompatibilityFallbackError(
          const BackendApiHttpException(
            statusCode: 500,
            message: 'Server error',
          ),
        ),
        isFalse,
      );
    },
  );

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

    final service = BackendApiService(httpClient: client);

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

    final service = BackendApiService(httpClient: client);

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

  testWidgets('deleteOwnedResource sends cleanup metadata to backend', (
    tester,
  ) async {
    http.BaseRequest? capturedRequest;

    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('{"success":true}', 200);
    });

    final service = BackendApiService(httpClient: client);

    await service.deleteOwnedResource(
      resourceId: '95aeade0-2eb7-4b5c-b776-39352479ef1f',
      bearerToken: 'test-token',
      fileUrl: 'https://cdn.example.com/resources/note.pdf',
      thumbnailUrl: 'https://cdn.example.com/resources/note-thumb.png',
      uploadedByEmail: 'Teacher@College.edu ',
    );

    expect(capturedRequest, isA<http.Request>());
    expect(capturedRequest!.method, 'DELETE');
    expect(
      capturedRequest!.url.path,
      '/api/resources/95aeade0-2eb7-4b5c-b776-39352479ef1f',
    );
    expect(capturedRequest!.headers['authorization'], 'Bearer test-token');

    final body = (capturedRequest as http.Request).body;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(decoded['fileUrl'], 'https://cdn.example.com/resources/note.pdf');
    expect(decoded['file_url'], 'https://cdn.example.com/resources/note.pdf');
    expect(
      decoded['thumbnailUrl'],
      'https://cdn.example.com/resources/note-thumb.png',
    );
    expect(
      decoded['thumbnail_url'],
      'https://cdn.example.com/resources/note-thumb.png',
    );
    expect(decoded['uploadedByEmail'], 'teacher@college.edu');
    expect(decoded['uploaded_by_email'], 'teacher@college.edu');
  });

  testWidgets('deleteOwnedResource falls back to legacy POST on 404', (
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

    final service = BackendApiService(httpClient: client);

    await service.deleteOwnedResource(
      resourceId: '95aeade0-2eb7-4b5c-b776-39352479ef1f',
      bearerToken: 'test-token',
      fileUrl: 'https://cdn.example.com/resources/note.pdf',
      uploadedByEmail: 'owner@example.com',
    );

    expect(requests, hasLength(2));
    expect(requests.first.method, 'DELETE');
    expect(
      requests.first.url.path,
      '/api/resources/95aeade0-2eb7-4b5c-b776-39352479ef1f',
    );

    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/admin');
    expect(requests.last.headers['authorization'], 'Bearer test-token');

    final body = (requests.last as http.Request).body;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(decoded['action'], 'delete_resource');
    expect(decoded['resourceId'], '95aeade0-2eb7-4b5c-b776-39352479ef1f');
    expect(decoded['keyHash'], 'test-token');
    expect(decoded['fileUrl'], 'https://cdn.example.com/resources/note.pdf');
    expect(decoded['file_url'], 'https://cdn.example.com/resources/note.pdf');
    expect(decoded['uploadedByEmail'], 'owner@example.com');
    expect(decoded['uploaded_by_email'], 'owner@example.com');
  });

  testWidgets('createNotice mirrors PDF attachment URL to both notice fields', (
    tester,
  ) async {
    http.BaseRequest? capturedRequest;

    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('{"success":true}', 200);
    });

    final service = BackendApiService(httpClient: client);

    await service.createNotice(
      collegeId: 'college-1',
      title: 'Exam timetable',
      content: 'Please review the attached PDF.',
      department: 'cse',
      fileUrl: 'https://cdn.example.com/notices/exam.pdf',
    );

    expect(capturedRequest, isA<http.Request>());
    expect(capturedRequest!.method, 'POST');
    expect(capturedRequest!.url.path, '/api/notices');

    final body = (capturedRequest as http.Request).body;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    expect(decoded['collegeId'], 'college-1');
    expect(decoded['department'], 'cse');
    expect(decoded['imageUrl'], 'https://cdn.example.com/notices/exam.pdf');
    expect(decoded['fileUrl'], 'https://cdn.example.com/notices/exam.pdf');
  });
}
