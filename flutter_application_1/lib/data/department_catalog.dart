import 'dart:ui';

import '../models/department_account.dart';

class DepartmentCatalogEntry {
  final String code;
  final String name;
  final String shortName;
  final String handle;
  final String avatarLetter;
  final Color color;

  const DepartmentCatalogEntry({
    required this.code,
    required this.name,
    required this.shortName,
    required this.handle,
    required this.avatarLetter,
    required this.color,
  });
}

const List<DepartmentCatalogEntry> departmentCatalogEntries = [
  DepartmentCatalogEntry(
    code: 'general',
    name: 'General',
    shortName: 'General',
    handle: '@general',
    avatarLetter: 'G',
    color: Color(0xFF3B82F6),
  ),
  DepartmentCatalogEntry(
    code: 'hackathons',
    name: 'Hackathons and Competitions',
    shortName: 'Hackathons',
    handle: '@hackathons',
    avatarLetter: 'HC',
    color: Color(0xFF8B5CF6),
  ),
  DepartmentCatalogEntry(
    code: 'ir',
    name: 'International Relations',
    shortName: 'IR',
    handle: '@ir_cell',
    avatarLetter: 'IR',
    color: Color(0xFF0EA5E9),
  ),
  DepartmentCatalogEntry(
    code: 'pr',
    name: 'Public Relations',
    shortName: 'PR',
    handle: '@pr_cell',
    avatarLetter: 'PR',
    color: Color(0xFFEC4899),
  ),
  DepartmentCatalogEntry(
    code: 'placements',
    name: 'Placements and Career',
    shortName: 'Placements',
    handle: '@placements',
    avatarLetter: 'PC',
    color: Color(0xFFF59E0B),
  ),
  DepartmentCatalogEntry(
    code: 'internships',
    name: 'Internships',
    shortName: 'Internships',
    handle: '@internships',
    avatarLetter: 'IN',
    color: Color(0xFF14B8A6),
  ),
  DepartmentCatalogEntry(
    code: 'workshops',
    name: 'Workshops and Seminars',
    shortName: 'Workshops',
    handle: '@workshops',
    avatarLetter: 'WS',
    color: Color(0xFF6366F1),
  ),
  DepartmentCatalogEntry(
    code: 'events',
    name: 'Events and Activities',
    shortName: 'Events',
    handle: '@events',
    avatarLetter: 'EV',
    color: Color(0xFFEF4444),
  ),
  DepartmentCatalogEntry(
    code: 'scholarships',
    name: 'Scholarships and Financial Aid',
    shortName: 'Scholarships',
    handle: '@scholarships',
    avatarLetter: 'SF',
    color: Color(0xFF22C55E),
  ),
  DepartmentCatalogEntry(
    code: 'admissions',
    name: 'Admissions and Enrollment',
    shortName: 'Admissions',
    handle: '@admissions',
    avatarLetter: 'AD',
    color: Color(0xFF06B6D4),
  ),
  DepartmentCatalogEntry(
    code: 'examinations',
    name: 'Examinations and Assessment',
    shortName: 'Examinations',
    handle: '@examinations',
    avatarLetter: 'EX',
    color: Color(0xFFF97316),
  ),
  DepartmentCatalogEntry(
    code: 'academics',
    name: 'Academic Notices',
    shortName: 'Academics',
    handle: '@academics',
    avatarLetter: 'AC',
    color: Color(0xFF475569),
  ),
  DepartmentCatalogEntry(
    code: 'training',
    name: 'Training and Certifications',
    shortName: 'Training',
    handle: '@training',
    avatarLetter: 'TR',
    color: Color(0xFF10B981),
  ),
  DepartmentCatalogEntry(
    code: 'clubs',
    name: 'Clubs and Societies',
    shortName: 'Clubs',
    handle: '@clubs',
    avatarLetter: 'CL',
    color: Color(0xFF7C3AED),
  ),
  DepartmentCatalogEntry(
    code: 'nss_ncc',
    name: 'NSS / NCC',
    shortName: 'NSS / NCC',
    handle: '@nss_ncc',
    avatarLetter: 'NN',
    color: Color(0xFF84CC16),
  ),
  DepartmentCatalogEntry(
    code: 'cse',
    name: 'Computer Science and Engineering',
    shortName: 'CSE',
    handle: '@cse_dept',
    avatarLetter: 'CS',
    color: Color(0xFF8B5CF6),
  ),
  DepartmentCatalogEntry(
    code: 'aiml',
    name: 'Artificial Intelligence and Machine Learning',
    shortName: 'AI/ML',
    handle: '@aiml_dept',
    avatarLetter: 'AI',
    color: Color(0xFF7C3AED),
  ),
  DepartmentCatalogEntry(
    code: 'cse_ai',
    name: 'Computer Science and Engineering (AI)',
    shortName: 'CSE AI',
    handle: '@cse_ai_dept',
    avatarLetter: 'CA',
    color: Color(0xFF6366F1),
  ),
  DepartmentCatalogEntry(
    code: 'it',
    name: 'Information Technology',
    shortName: 'IT',
    handle: '@it_dept',
    avatarLetter: 'IT',
    color: Color(0xFF14B8A6),
  ),
  DepartmentCatalogEntry(
    code: 'ds',
    name: 'Data Science',
    shortName: 'DS',
    handle: '@ds_dept',
    avatarLetter: 'DS',
    color: Color(0xFF0EA5E9),
  ),
  DepartmentCatalogEntry(
    code: 'cse_cs',
    name: 'Cyber Security',
    shortName: 'Cyber Security',
    handle: '@cse_cs_dept',
    avatarLetter: 'CY',
    color: Color(0xFF2563EB),
  ),
  DepartmentCatalogEntry(
    code: 'ece',
    name: 'Electronics and Communication Engineering',
    shortName: 'ECE',
    handle: '@ece_dept',
    avatarLetter: 'EC',
    color: Color(0xFF10B981),
  ),
  DepartmentCatalogEntry(
    code: 'ece_vlsi',
    name: 'ECE - VLSI',
    shortName: 'ECE VLSI',
    handle: '@ece_vlsi_dept',
    avatarLetter: 'EV',
    color: Color(0xFF0F766E),
  ),
  DepartmentCatalogEntry(
    code: 'elce',
    name: 'Electrical and Computer Engineering',
    shortName: 'ELCE',
    handle: '@elce_dept',
    avatarLetter: 'EL',
    color: Color(0xFF0284C7),
  ),
  DepartmentCatalogEntry(
    code: 'eee',
    name: 'Electrical and Electronics Engineering',
    shortName: 'EEE',
    handle: '@eee_dept',
    avatarLetter: 'EE',
    color: Color(0xFFF59E0B),
  ),
  DepartmentCatalogEntry(
    code: 'ce',
    name: 'Civil Engineering',
    shortName: 'CE',
    handle: '@ce_dept',
    avatarLetter: 'CE',
    color: Color(0xFF6366F1),
  ),
  DepartmentCatalogEntry(
    code: 'me',
    name: 'Mechanical Engineering',
    shortName: 'ME',
    handle: '@me_dept',
    avatarLetter: 'ME',
    color: Color(0xFFEF4444),
  ),
  DepartmentCatalogEntry(
    code: 'amia',
    name: 'Advanced Mechatronics and Industrial Automation',
    shortName: 'AMIA',
    handle: '@amia_dept',
    avatarLetter: 'AM',
    color: Color(0xFFDC2626),
  ),
];

String normalizeDepartmentCode(String? rawCode) {
  return rawCode?.trim().toLowerCase() ?? '';
}

DepartmentCatalogEntry? departmentCatalogEntryForCode(String? rawCode) {
  final code = normalizeDepartmentCode(rawCode);
  if (code.isEmpty) return null;
  for (final entry in departmentCatalogEntries) {
    if (entry.code == code) return entry;
  }
  return null;
}

String _titleCaseDepartmentCode(String code) {
  final parts = code
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Unknown Department';
  return parts
      .map(
        (part) => part.length <= 3
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _departmentAvatarLetter(String code, String name) {
  final words = name
      .split(RegExp(r'[\s/&()_-]+'))
      .where((word) => word.trim().isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return code.isEmpty ? '?' : code.substring(0, 1).toUpperCase();
  }
  if (words.length == 1) {
    final word = words.first;
    return word.length >= 2
        ? word.substring(0, 2).toUpperCase()
        : word.toUpperCase();
  }
  return '${words.first[0]}${words[1][0]}'.toUpperCase();
}

Color _departmentColorFromCode(String code) {
  const palette = <Color>[
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF6366F1),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
  ];
  if (code.isEmpty) return const Color(0xFF64748B);
  final bucket = code.codeUnits.fold<int>(0, (sum, char) => sum + char);
  return palette[bucket % palette.length];
}

DepartmentAccount departmentAccountFromCode(
  String? rawCode, {
  String? fallbackName,
}) {
  final entry = departmentCatalogEntryForCode(rawCode);
  if (entry != null) {
    return DepartmentAccount(
      id: entry.code,
      name: entry.name,
      handle: entry.handle,
      avatarLetter: entry.avatarLetter,
      color: entry.color,
    );
  }

  final code = normalizeDepartmentCode(rawCode);
  if (code.isEmpty) {
    return DepartmentAccount.unknown();
  }

  final resolvedName = fallbackName?.trim().isNotEmpty == true
      ? fallbackName!.trim()
      : _titleCaseDepartmentCode(code);

  return DepartmentAccount(
    id: code,
    name: resolvedName,
    handle: '@${code.replaceAll('_', '')}',
    avatarLetter: _departmentAvatarLetter(code, resolvedName),
    color: _departmentColorFromCode(code),
  );
}

List<DepartmentAccount> buildDepartmentAccountsFromCodes(
  Iterable<String> rawCodes, {
  bool includeGeneral = true,
}) {
  final orderedCodes = <String>[
    if (includeGeneral) 'general',
    ...rawCodes.map(normalizeDepartmentCode),
  ];
  final seen = <String>{};
  final accounts = <DepartmentAccount>[];
  for (final code in orderedCodes) {
    if (code.isEmpty || !seen.add(code)) continue;
    accounts.add(departmentAccountFromCode(code));
  }
  return accounts;
}
