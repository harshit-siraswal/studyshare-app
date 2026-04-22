class AttendanceStudent {
  final String fullName;
  final String registrationNumber;
  final String sectionName;
  final String branchShortName;
  final String degreeName;
  final String semesterName;
  final int? studentId;

  const AttendanceStudent({
    required this.fullName,
    required this.registrationNumber,
    required this.sectionName,
    required this.branchShortName,
    required this.degreeName,
    required this.semesterName,
    required this.studentId,
  });

  factory AttendanceStudent.fromJson(Map<String, dynamic> json) {
    return AttendanceStudent(
      fullName: json['fullName']?.toString() ?? '',
      registrationNumber: json['registrationNumber']?.toString() ?? '',
      sectionName: json['sectionName']?.toString() ?? '',
      branchShortName: json['branchShortName']?.toString() ?? '',
      degreeName: json['degreeName']?.toString() ?? '',
      semesterName: json['semesterName']?.toString() ?? '',
      studentId: _toNullableInt(json['studentId']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      'registrationNumber': registrationNumber,
      'sectionName': sectionName,
      'branchShortName': branchShortName,
      'degreeName': degreeName,
      'semesterName': semesterName,
      'studentId': studentId,
    };
  }
}

class AttendanceOverview {
  final int presentClasses;
  final int totalClasses;
  final double percentage;

  const AttendanceOverview({
    required this.presentClasses,
    required this.totalClasses,
    required this.percentage,
  });

  factory AttendanceOverview.fromJson(Map<String, dynamic> json) {
    return AttendanceOverview(
      presentClasses: _toInt(json['presentClasses']),
      totalClasses: _toInt(json['totalClasses']),
      percentage: _toDouble(json['percentage']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'presentClasses': presentClasses,
      'totalClasses': totalClasses,
      'percentage': percentage,
    };
  }
}

class AttendanceComponent {
  final int courseId;
  final String courseName;
  final String courseCode;
  final int courseComponentId;
  final String componentName;
  final int totalClasses;
  final int attendedClasses;
  final int extraAttendance;
  final double percentage;
  final String percentageLabel;
  final int threshold;
  final bool isLowAttendance;
  final int classesNeededForThreshold;
  final int bunkAllowance;

  const AttendanceComponent({
    required this.courseId,
    required this.courseName,
    required this.courseCode,
    required this.courseComponentId,
    required this.componentName,
    required this.totalClasses,
    required this.attendedClasses,
    required this.extraAttendance,
    required this.percentage,
    required this.percentageLabel,
    required this.threshold,
    required this.isLowAttendance,
    required this.classesNeededForThreshold,
    required this.bunkAllowance,
  });

  factory AttendanceComponent.fromJson(Map<String, dynamic> json) {
    return AttendanceComponent(
      courseId: _toInt(json['courseId']),
      courseName: json['courseName']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      courseComponentId: _toInt(json['courseComponentId']),
      componentName: json['componentName']?.toString() ?? '',
      totalClasses: _toInt(json['totalClasses']),
      attendedClasses: _toInt(json['attendedClasses']),
      extraAttendance: _toInt(json['extraAttendance']),
      percentage: _toDouble(json['percentage']),
      percentageLabel: json['percentageLabel']?.toString() ?? '',
      threshold: _toInt(json['threshold']),
      isLowAttendance: json['isLowAttendance'] == true,
      classesNeededForThreshold: _toInt(json['classesNeededForThreshold']),
      bunkAllowance: _toInt(json['bunkAllowance']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'courseId': courseId,
      'courseName': courseName,
      'courseCode': courseCode,
      'courseComponentId': courseComponentId,
      'componentName': componentName,
      'totalClasses': totalClasses,
      'attendedClasses': attendedClasses,
      'extraAttendance': extraAttendance,
      'percentage': percentage,
      'percentageLabel': percentageLabel,
      'threshold': threshold,
      'isLowAttendance': isLowAttendance,
      'classesNeededForThreshold': classesNeededForThreshold,
      'bunkAllowance': bunkAllowance,
    };
  }
}

class AttendanceCourse {
  final int courseId;
  final String courseName;
  final String courseCode;
  final List<AttendanceComponent> components;

  const AttendanceCourse({
    required this.courseId,
    required this.courseName,
    required this.courseCode,
    required this.components,
  });

  factory AttendanceCourse.fromJson(Map<String, dynamic> json) {
    final componentsRaw = (json['components'] as List?) ?? const [];
    return AttendanceCourse(
      courseId: _toInt(json['courseId']),
      courseName: json['courseName']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      components: componentsRaw
          .whereType<Map>()
          .map(
            (item) =>
                AttendanceComponent.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'courseId': courseId,
      'courseName': courseName,
      'courseCode': courseCode,
      'components': components.map((component) => component.toJson()).toList(),
    };
  }
}

class AttendanceScheduleEntry {
  final String title;
  final String courseName;
  final String courseCode;
  final String courseComponentName;
  final String facultyName;
  final String lectureDate;
  final String start;
  final String end;
  final String type;
  final String classRoom;

  const AttendanceScheduleEntry({
    required this.title,
    required this.courseName,
    required this.courseCode,
    required this.courseComponentName,
    required this.facultyName,
    required this.lectureDate,
    required this.start,
    required this.end,
    required this.type,
    required this.classRoom,
  });

  factory AttendanceScheduleEntry.fromJson(Map<String, dynamic> json) {
    return AttendanceScheduleEntry(
      title: json['title']?.toString() ?? '',
      courseName: json['courseName']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      courseComponentName: json['courseCompName']?.toString() ?? '',
      facultyName: json['facultyName']?.toString() ?? '',
      lectureDate: json['lectureDate']?.toString() ?? '',
      start: json['start']?.toString() ?? '',
      end: json['end']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      classRoom: json['classRoom']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'courseName': courseName,
      'courseCode': courseCode,
      'courseCompName': courseComponentName,
      'facultyName': facultyName,
      'lectureDate': lectureDate,
      'start': start,
      'end': end,
      'type': type,
      'classRoom': classRoom,
    };
  }
}

class AttendanceSchedule {
  final String weekStartDate;
  final String weekEndDate;
  final List<AttendanceScheduleEntry> entries;

  const AttendanceSchedule({
    required this.weekStartDate,
    required this.weekEndDate,
    required this.entries,
  });

  factory AttendanceSchedule.fromJson(Map<String, dynamic> json) {
    final entriesRaw = (json['entries'] as List?) ?? const [];
    return AttendanceSchedule(
      weekStartDate: json['weekStartDate']?.toString() ?? '',
      weekEndDate: json['weekEndDate']?.toString() ?? '',
      entries: entriesRaw
          .whereType<Map>()
          .map(
            (item) => AttendanceScheduleEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weekStartDate': weekStartDate,
      'weekEndDate': weekEndDate,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class AttendanceSnapshot {
  final AttendanceStudent student;
  final AttendanceOverview overall;
  final List<AttendanceCourse> courses;
  final List<AttendanceComponent> lowAttendance;
  final AttendanceSchedule schedule;
  final DateTime syncedAt;

  const AttendanceSnapshot({
    required this.student,
    required this.overall,
    required this.courses,
    required this.lowAttendance,
    required this.schedule,
    required this.syncedAt,
  });

  factory AttendanceSnapshot.fromJson(Map<String, dynamic> json) {
    final coursesRaw = (json['courses'] as List?) ?? const [];
    final lowRaw = (json['lowAttendance'] as List?) ?? const [];
    return AttendanceSnapshot(
      student: AttendanceStudent.fromJson(
        Map<String, dynamic>.from(json['student'] as Map? ?? const {}),
      ),
      overall: AttendanceOverview.fromJson(
        Map<String, dynamic>.from(json['overall'] as Map? ?? const {}),
      ),
      courses: coursesRaw
          .whereType<Map>()
          .map(
            (item) =>
                AttendanceCourse.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      lowAttendance: lowRaw
          .whereType<Map>()
          .map(
            (item) =>
                AttendanceComponent.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      schedule: AttendanceSchedule.fromJson(
        Map<String, dynamic>.from(json['schedule'] as Map? ?? const {}),
      ),
      syncedAt:
          DateTime.tryParse(json['syncedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student': student.toJson(),
      'overall': overall.toJson(),
      'courses': courses.map((course) => course.toJson()).toList(),
      'lowAttendance': lowAttendance
          .map((component) => component.toJson())
          .toList(),
      'schedule': schedule.toJson(),
      'syncedAt': syncedAt.toIso8601String(),
    };
  }

  List<AttendanceComponent> get allComponents =>
      courses.expand((course) => course.components).toList(growable: false);
}

class AttendanceLecture {
  final String lectureDate;
  final String dayName;
  final String timeSlot;
  final String attendanceStatus;
  final String facultyName;
  final String courseName;
  final String courseComponentName;

  const AttendanceLecture({
    required this.lectureDate,
    required this.dayName,
    required this.timeSlot,
    required this.attendanceStatus,
    required this.facultyName,
    required this.courseName,
    required this.courseComponentName,
  });

  factory AttendanceLecture.fromJson(Map<String, dynamic> json) {
    final normalizedStatus =
        json['attendanceStatus']?.toString().trim() ??
        json['attendance']?.toString().trim() ??
        '';
    return AttendanceLecture(
      lectureDate: json['planLecDate']?.toString() ?? '',
      dayName: json['dayName']?.toString() ?? '',
      timeSlot: json['timeSlot']?.toString() ?? '',
      attendanceStatus: normalizedStatus,
      facultyName: json['facultyName']?.toString() ?? '',
      courseName: json['courseName']?.toString() ?? '',
      courseComponentName: json['courseCompName']?.toString() ?? '',
    );
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _toNullableInt(Object? value) {
  if (value == null) return null;
  final parsed = _toInt(value);
  return parsed <= 0 ? null : parsed;
}

double _toDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
