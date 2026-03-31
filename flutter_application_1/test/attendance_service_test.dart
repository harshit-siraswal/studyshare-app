import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/attendance_models.dart';
import 'package:flutter_application_1/services/attendance_service.dart';

AttendanceSnapshot _buildSnapshot({
  required String fullName,
  required String registrationNumber,
  required int studentId,
  required double overallPercentage,
  required String courseName,
  required String classroom,
}) {
  final lowAttendanceComponent = AttendanceComponent(
    courseId: 101,
    courseName: courseName,
    courseCode: 'CSE101',
    courseComponentId: 501,
    componentName: 'Theory',
    totalClasses: 40,
    attendedClasses: 26,
    extraAttendance: 0,
    percentage: 65,
    percentageLabel: '65%',
    threshold: 75,
    isLowAttendance: true,
    classesNeededForThreshold: 4,
    bunkAllowance: 0,
  );

  return AttendanceSnapshot(
    student: AttendanceStudent(
      fullName: fullName,
      registrationNumber: registrationNumber,
      sectionName: 'A',
      branchShortName: 'CSE',
      degreeName: 'B.Tech',
      semesterName: 'Semester 4',
      studentId: studentId,
    ),
    overall: AttendanceOverview(
      presentClasses: 52,
      totalClasses: 60,
      percentage: overallPercentage,
    ),
    courses: <AttendanceCourse>[
      AttendanceCourse(
        courseId: 101,
        courseName: courseName,
        courseCode: 'CSE101',
        components: <AttendanceComponent>[lowAttendanceComponent],
      ),
    ],
    lowAttendance: <AttendanceComponent>[lowAttendanceComponent],
    schedule: AttendanceSchedule(
      weekStartDate: '2026-03-30',
      weekEndDate: '2026-04-05',
      entries: <AttendanceScheduleEntry>[
        AttendanceScheduleEntry(
          title: 'DSA Theory',
          courseName: courseName,
          courseCode: 'CSE101',
          courseComponentName: 'Theory',
          facultyName: 'Prof. Sharma',
          lectureDate: '2026-03-31',
          start: '10:00',
          end: '10:50',
          type: 'lecture',
          classRoom: classroom,
        ),
        AttendanceScheduleEntry(
          title: 'OS Lab',
          courseName: 'Operating Systems',
          courseCode: 'CSE202',
          courseComponentName: 'Lab',
          facultyName: 'Prof. Mehta',
          lectureDate: '2026-03-31',
          start: '12:00',
          end: '12:50',
          type: 'lab',
          classRoom: 'LAB-3',
        ),
      ],
    ),
    syncedAt: DateTime.parse('2026-03-31T08:15:00.000'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttendanceService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = AttendanceService();
  });

  test('detects attendance and schedule prompts', () {
    expect(
      service.isAttendanceOrSchedulePrompt('What is my attendance today?'),
      isTrue,
    );
    expect(
      service.isAttendanceOrSchedulePrompt(
        'Tell me my next class and room number',
      ),
      isTrue,
    );
    expect(
      service.isAttendanceOrSchedulePrompt('Summarize this PDF chapter'),
      isFalse,
    );
  });

  test(
    'buildLocalAiResponse reads only the scoped cache for the signed-in user',
    () async {
      final firstUserSnapshot = _buildSnapshot(
        fullName: 'Aman Verma',
        registrationNumber: '22001',
        studentId: 1001,
        overallPercentage: 80.5,
        courseName: 'Data Structures',
        classroom: 'B-204',
      );
      final secondUserSnapshot = _buildSnapshot(
        fullName: 'Riya Singh',
        registrationNumber: '22002',
        studentId: 1002,
        overallPercentage: 91.2,
        courseName: 'Database Systems',
        classroom: 'C-112',
      );

      SharedPreferences.setMockInitialValues(<String, Object>{
        'attendance_snapshot_kiet_aman_example_com': jsonEncode(
          firstUserSnapshot.toJson(),
        ),
        'attendance_snapshot_kiet_riya_example_com': jsonEncode(
          secondUserSnapshot.toJson(),
        ),
      });

      final answer = await service.buildLocalAiResponse(
        collegeId: 'kiet',
        collegeName: 'KIET Group of Institutions',
        prompt: 'What is my attendance and low attendance risk?',
        userEmail: 'riya@example.com',
      );

      expect(answer, isNotNull);
      expect(answer!, contains('Riya Singh'));
      expect(answer, contains('Student ID 1002'));
      expect(answer, contains('Database Systems'));
      expect(answer, isNot(contains('Aman Verma')));
      expect(answer, isNot(contains('Student ID 1001')));
      expect(answer, isNot(contains('Data Structures')));
    },
  );

  test(
    'buildLocalAiResponseForSnapshot answers from the offline snapshot with schedule details',
    () {
      final snapshot = _buildSnapshot(
        fullName: 'Harshit Pal',
        registrationNumber: '22999',
        studentId: 4242,
        overallPercentage: 86.67,
        courseName: 'Artificial Intelligence',
        classroom: 'A-301',
      );

      final answer = service.buildLocalAiResponseForSnapshot(
        snapshot: snapshot,
        prompt: 'Tell me my attendance, low attendance risk, and next class',
        now: DateTime.parse('2026-03-31T09:30:00.000'),
      );

      expect(answer, contains('private KIET ERP cache'));
      expect(answer, contains('Harshit Pal'));
      expect(answer, contains('Student ID 4242'));
      expect(answer, contains('Overall attendance: 86.67%'));
      expect(answer, contains('Low attendance summary'));
      expect(answer, contains('Artificial Intelligence'));
      expect(answer, contains('Upcoming classes'));
      expect(answer, contains('Room A-301'));
    },
  );

  test(
    'clearSavedSession removes both legacy and user-scoped attendance keys',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'attendance_snapshot_kiet': '{}',
        'attendance_token_kiet': 'legacy-token',
        'attendance_snapshot_kiet_student_example_com': '{}',
        'attendance_token_kiet_student_example_com': 'scoped-token',
      });

      await service.clearSavedSession('kiet', userEmail: 'student@example.com');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('attendance_snapshot_kiet'), isNull);
      expect(prefs.getString('attendance_token_kiet'), isNull);
      expect(
        prefs.getString('attendance_snapshot_kiet_student_example_com'),
        isNull,
      );
      expect(
        prefs.getString('attendance_token_kiet_student_example_com'),
        isNull,
      );
    },
  );
}
