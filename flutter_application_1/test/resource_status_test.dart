import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/resource.dart';

void main() {
  test('Resource normalizes cross-platform approved variants', () {
    final resource = Resource.fromJson({
      'id': 'res-1',
      'title': 'Compiler Notes',
      'type': 'notes',
      'file_url': 'https://cdn.example.com/compiler.pdf',
      'uploaded_by_email': 'teacher@example.com',
      'college_id': 'college-1',
      'status': 'Published',
      'created_at': '2026-03-09T00:00:00Z',
    });

    expect(resource.status, Resource.approvedStatus);
    expect(resource.isApprovedStatus, isTrue);
    expect(resource.isApproved, isTrue);
  });

  test('Resource falls back to approved when legacy boolean is set', () {
    final resource = Resource.fromJson({
      'id': 'res-2',
      'title': 'DBMS Notes',
      'type': 'notes',
      'file_url': 'https://cdn.example.com/dbms.pdf',
      'uploaded_by_email': 'teacher@example.com',
      'college_id': 'college-1',
      'is_approved': true,
      'created_at': '2026-03-09T00:00:00Z',
    });

    expect(resource.status, Resource.approvedStatus);
    expect(resource.isApprovedStatus, isTrue);
    expect(resource.isApproved, isTrue);
  });

  test('Resource normalizes rejected and pending variants', () {
    expect(Resource.normalizeStatusValue('retracted'), Resource.rejectedStatus);
    expect(
      Resource.normalizeStatusValue('under_review'),
      Resource.pendingStatus,
    );
  });

  test('Resource builds approved filter with legacy boolean fallback', () {
    final filter = Resource.buildStatusOrFilter(const [
      Resource.approvedStatus,
    ], includeLegacyApprovalFlag: true);

    expect(filter, contains('status.eq.approved'));
    expect(filter, contains('status.eq.accepted'));
    expect(filter, contains('status.eq.published'));
    expect(filter, contains('is_approved.eq.true'));
  });

  test('Resource builds approved filter without legacy boolean fallback', () {
    final filter = Resource.buildStatusOrFilter(const [
      Resource.approvedStatus,
    ], includeLegacyApprovalFlag: false);

    expect(filter, contains('status.eq.approved'));
    expect(filter, isNot(contains('is_approved.eq.true')));
  });

  test('Resource builds rejected filter with all aliases', () {
    final filter = Resource.buildStatusOrFilter(const [
      Resource.rejectedStatus,
    ], includeLegacyApprovalFlag: false);

    expect(filter, contains('status.eq.rejected'));
    expect(filter, contains('status.eq.retracted'));
  });

  test('Resource builds pending filter with all aliases', () {
    final filter = Resource.buildStatusOrFilter(const [
      Resource.pendingStatus,
    ], includeLegacyApprovalFlag: false);

    expect(filter, contains('status.eq.pending'));
    expect(filter, contains('status.eq.under_review'));
  });

  test('normalizeStatusValue uses isRejected fallback when status is empty', () {
    final status = Resource.normalizeStatusValue(
      null,
      isRejected: true,
    );
    expect(status, Resource.rejectedStatus);
  });

  test('normalizeStatusValue returns pending when all inputs empty', () {
    final status = Resource.normalizeStatusValue(null);
    expect(status, Resource.pendingStatus);
  });
}
