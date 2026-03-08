class BranchOption {
  final String value;
  final String label;
  final String shortLabel;

  const BranchOption({
    required this.value,
    required this.label,
    required this.shortLabel,
  });
}

const List<String> semesterOptions = <String>[
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
];

const List<BranchOption> branchOptions = <BranchOption>[
  BranchOption(
    value: 'cse',
    label: 'Computer Science & Engineering (CSE/CS)',
    shortLabel: 'CSE/CS',
  ),
  BranchOption(
    value: 'it',
    label: 'Information Technology (IT/CSIT)',
    shortLabel: 'IT/CSIT',
  ),
  BranchOption(
    value: 'cse_ai',
    label: 'Computer Science (AI)',
    shortLabel: 'CSE-AI',
  ),
  BranchOption(
    value: 'aiml',
    label: 'Computer Science (AI & ML)',
    shortLabel: 'CSE-AIML',
  ),
  BranchOption(
    value: 'ds',
    label: 'Computer Science (Data Science)',
    shortLabel: 'CSE-DS',
  ),
  BranchOption(
    value: 'cse_cs',
    label: 'Computer Science (Cyber Security)',
    shortLabel: 'CSE-CS',
  ),
  BranchOption(
    value: 'me',
    label: 'Mechanical Engineering (ME)',
    shortLabel: 'ME',
  ),
  BranchOption(
    value: 'amia',
    label: 'Advanced Mechatronics & Industrial Automation',
    shortLabel: 'AM&IA',
  ),
  BranchOption(
    value: 'elce',
    label: 'Electrical & Computer Engineering (ELCE)',
    shortLabel: 'ELCE',
  ),
  BranchOption(
    value: 'eee',
    label: 'Electrical & Electronics Engineering (EEE)',
    shortLabel: 'EEE',
  ),
  BranchOption(
    value: 'ece',
    label: 'Electronics & Communication Engineering (ECE)',
    shortLabel: 'ECE',
  ),
  BranchOption(
    value: 'ece_vlsi',
    label: 'ECE (VLSI Design & Technology)',
    shortLabel: 'ECE-VLSI',
  ),
  BranchOption(value: 'ce', label: 'Civil Engineering', shortLabel: 'CE'),
];

const Map<String, String> _branchAliases = <String, String>{
  'cs': 'cse',
  'cse_cs': 'cse_cs',
  'cse-cs': 'cse_cs',
  'cse/cs': 'cse',
  'cyber security': 'cse_cs',
  'cybersecurity': 'cse_cs',
  'csit': 'it',
  'it/csit': 'it',
  'cse(ai)': 'cse_ai',
  'cse-ai': 'cse_ai',
  'cse ai': 'cse_ai',
  'cse_ai': 'cse_ai',
  'cse-aiml': 'aiml',
  'cse_aiml': 'aiml',
  'cse aiml': 'aiml',
  'cse(ai&ml)': 'aiml',
  'cse(ai & ml)': 'aiml',
  'cse(ai ml)': 'aiml',
  'ai': 'cse_ai',
  'ai&ml': 'aiml',
  'cse(ds)': 'ds',
  'cse-ds': 'ds',
  'data science': 'ds',
  'am&ia': 'amia',
  'am ia': 'amia',
  'amia': 'amia',
  'ece(vlsi)': 'ece_vlsi',
  'ece-vlsi': 'ece_vlsi',
  'vlsi': 'ece_vlsi',
  'ece vlsi': 'ece_vlsi',
};

const Map<String, Map<String, List<String>>> kietBranchSemSubjects =
    <String, Map<String, List<String>>>{
      'cse': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Discrete Structures & Theory of Logic',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Web Designing',
          'Communication Skills',
          'Indian Knowledge System',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Environmental Chemistry',
          'Computer Organization & Logic Design',
          'Data Structure',
          'Design and Realization',
          'Computer Organization & Logic Design Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
        ],
      },
      'it': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Discrete Structures & Theory of Logic',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Web Designing',
          'Communication Skills',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Environmental Chemistry',
          'Computer Organization & Logic Design',
          'Data Structure',
          'Design and Realization',
          'Computer Organization & Logic Design Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
          'Indian Knowledge System',
        ],
      },
      'cse_ai': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Discrete Structures & Theory of Logic',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Web Designing',
          'Communication Skills',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Environmental Chemistry',
          'Computer Organization & Logic Design',
          'Data Structure',
          'Introduction to AI',
          'Computer Organization & Logic Design Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
          'Indian Knowledge System',
        ],
      },
      'aiml': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Discrete Structures & Theory of Logic',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Web Designing',
          'Communication Skills',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Environmental Chemistry',
          'Computer Organization & Logic Design',
          'Data Structure',
          'Introduction to AI',
          'Computer Organization & Logic Design Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
          'Indian Knowledge System',
        ],
      },
      'ds': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Discrete Structures & Theory of Logic',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Web Designing',
          'Communication Skills',
          'Indian Knowledge System',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Computer Organization & Logic Design',
          'Data Structure',
          'Design and Realization',
          'Introduction to Data Science',
          'Computer Organization & Logic Design Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
        ],
      },
      'cse_cs': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Discrete Structures & Theory of Logic',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Web Designing',
          'Communication Skills',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Environmental Chemistry',
          'Computer Organization & Logic Design',
          'Data Structure',
          'Introduction to Cyber Security',
          'Computer Organization & Logic Design Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
          'Indian Knowledge System',
        ],
      },
      'me': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Explorations in Electrical Engineering',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Explorations in Electrical Engineering Lab',
          'Communication Skills',
          'Indian Knowledge System',
        ],
        '2': <String>[
          'Differential Equations & Complex Integration',
          'Environmental Chemistry',
          'Engineering Mechanics',
          'Data Structure',
          'Design and Realization',
          'Emerging Technologies for Engineers',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
        ],
      },
      'amia': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Environmental Chemistry',
          'Fundamentals of Mechatronics and Industrial Automation',
          'Programming For Problem Solving',
          'Explorations in Electrical Engineering',
          'Design Thinking',
          'Introduction to IoT',
          'Programming For Problem Solving Lab',
          'Explorations in Electrical Engineering Lab',
          'Communication Skills',
          'Indian Knowledge System',
        ],
        '2': <String>[
          'Differential Equations & Complex Integration',
          'Semiconductor Physics and Devices',
          'Data Structure',
          'Design and Realization',
          'Emerging Technologies for Engineers',
          'Semiconductor Physics and Devices Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
        ],
      },
      'elce': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Explorations in Electrical Engineering',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Explorations in Electrical Engineering Lab',
          'Communication Skills',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Environmental Chemistry',
          'Computer Organization & Logic Design',
          'Data Structure',
          'Design and Realization',
          'Computer Organization & Logic Design Lab',
          'Python for Engineers',
          'Computer Aided Electrical Design',
          'Foreign Language',
          'Innovation and Entrepreneurship',
          'Indian Knowledge System',
        ],
      },
      'eee': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Semiconductor Physics and Devices',
          'Programming For Problem Solving',
          'Explorations in Electrical Engineering',
          'Design Thinking',
          'Introduction to IoT',
          'Semiconductor Physics and Devices Lab',
          'Programming For Problem Solving Lab',
          'Explorations in Electrical Engineering Lab',
          'Communication Skills',
          'Indian Knowledge System',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Environmental Chemistry',
          'Digital Logic Design',
          'Data Structure',
          'Design and Realization',
          'Emerging Technologies for Engineers',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
        ],
      },
      'ece': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Environmental Chemistry',
          'Programming For Problem Solving',
          'Computer Organization & Logic Design',
          'Intelligent Health Care Systems',
          'Design Thinking',
          'Introduction to IoT',
          'Computer Organization & Logic Design Lab',
          'Programming For Problem Solving Lab',
          'Intelligent Health Care Systems Lab',
          'Communication Skills',
          'Indian Knowledge System',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Semiconductor Physics and Devices',
          'Explorations in Electrical Engineering',
          'Data Structure',
          'Design and Realization',
          'Semiconductor Physics and Devices Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
        ],
      },
      'ece_vlsi': <String, List<String>>{
        '1': <String>[
          'Calculus for Engineers',
          'Environmental Chemistry',
          'Explorations in Electrical Engineering',
          'Programming For Problem Solving',
          'Computer Organization & Logic Design',
          'Design Thinking',
          'Design and Realization',
          'Computer Organization & Logic Design Lab',
          'Programming For Problem Solving Lab',
          'Communication Skills',
          'Indian Knowledge System',
        ],
        '2': <String>[
          'Linear Algebra for Engineers',
          'Semiconductor Physics and Devices',
          'Digital Logic Design using HDL',
          'Data Structure',
          'Basic Electronics Engineering',
          'Semiconductor Physics and Devices Lab',
          'Digital Logic Design using HDL Lab',
          'Python for Engineers',
          'Foreign Language',
          'Innovation and Entrepreneurship',
        ],
      },
      'ce': <String, List<String>>{
        '1': <String>[
          'Engineering Mathematics',
          'Engineering Physics',
          'Engineering Chemistry',
        ],
        '2': <String>[
          'Engineering Mechanics',
          'Data Structure',
          'Communication Skills',
        ],
      },
    };

String normalizeBranchCode(String? branch) {
  final normalized = (branch ?? '').toLowerCase().trim().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  if (normalized.isEmpty) return '';

  final aliased = _branchAliases[normalized];
  if (aliased != null) return aliased;

  return normalized.replaceAll(RegExp(r'[^\w]'), '_');
}

String getBranchLabel(String? branch) {
  final normalized = normalizeBranchCode(branch);
  for (final option in branchOptions) {
    if (option.value == normalized) return option.label;
  }
  return branch ?? '';
}

String getBranchShortLabel(String? branch) {
  final normalized = normalizeBranchCode(branch);
  for (final option in branchOptions) {
    if (option.value == normalized) return option.shortLabel;
  }
  return branch ?? '';
}

List<String> getSubjectsForBranchAndSemester(String? branch, String? semester) {
  final normalizedBranch = normalizeBranchCode(branch);
  final normalizedSemester = (semester ?? '').trim();

  if (normalizedBranch.isEmpty) return const <String>[];
  final branchCatalog = kietBranchSemSubjects[normalizedBranch];
  if (branchCatalog == null) return const <String>[];

  if (normalizedSemester.isNotEmpty) {
    final scoped = branchCatalog[normalizedSemester];
    if (scoped != null && scoped.isNotEmpty) {
      return List<String>.from(scoped);
    }
  }

  final merged = <String>[];
  final seen = <String>{};
  for (final subjects in branchCatalog.values) {
    for (final subject in subjects) {
      final normalizedSubject = subject.trim();
      if (normalizedSubject.isEmpty) continue;
      if (seen.add(normalizedSubject)) {
        merged.add(normalizedSubject);
      }
    }
  }
  return merged;
}
