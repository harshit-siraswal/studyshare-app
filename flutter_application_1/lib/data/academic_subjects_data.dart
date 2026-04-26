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

class CollegeAcademicCatalog {
  final String key;
  final List<String> branchCodes;
  final Map<String, Map<String, List<String>>> subjectsByBranchSemester;

  const CollegeAcademicCatalog({
    required this.key,
    required this.branchCodes,
    required this.subjectsByBranchSemester,
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
    value: 'computer',
    label: 'Computer Engineering',
    shortLabel: 'COE',
  ),
  BranchOption(
    value: 'csbs',
    label: 'Computer Science and Business Systems',
    shortLabel: 'CSBS',
  ),
  BranchOption(
    value: 'mnc',
    label: 'Mathematics and Computing',
    shortLabel: 'MnC',
  ),
  BranchOption(
    value: 'ai_ml',
    label: 'Artificial Intelligence and Machine Learning',
    shortLabel: 'AI-ML',
  ),
  BranchOption(
    value: 'ai_ds',
    label: 'Artificial Intelligence and Data Science',
    shortLabel: 'AI-DS',
  ),
  BranchOption(
    value: 'me',
    label: 'Mechanical Engineering (ME)',
    shortLabel: 'ME',
  ),
  BranchOption(
    value: 'mechatronics',
    label: 'Mechatronics Engineering',
    shortLabel: 'MTRX',
  ),
  BranchOption(
    value: 'amia',
    label: 'Advanced Mechatronics & Industrial Automation',
    shortLabel: 'AM&IA',
  ),
  BranchOption(
    value: 'automation_robotics',
    label: 'Automation and Robotics',
    shortLabel: 'A&R',
  ),
  BranchOption(
    value: 'robotics_ai',
    label: 'Robotics and Artificial Intelligence',
    shortLabel: 'RAI',
  ),
  BranchOption(value: 'ee', label: 'Electrical Engineering', shortLabel: 'EE'),
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
    value: 'eec',
    label: 'Electrical and Computer Engineering',
    shortLabel: 'EEC',
  ),
  BranchOption(
    value: 'eic',
    label: 'Electronics and Instrumentation Engineering',
    shortLabel: 'EIC',
  ),
  BranchOption(
    value: 'ece',
    label: 'Electronics & Communication Engineering (ECE)',
    shortLabel: 'ECE',
  ),
  BranchOption(
    value: 'ece_iot',
    label: 'Electronics and Communication Engineering (IoT)',
    shortLabel: 'ECE-IoT',
  ),
  BranchOption(
    value: 'ecm',
    label: 'Electronics and Computer Engineering',
    shortLabel: 'ECM',
  ),
  BranchOption(
    value: 'ece_vlsi',
    label: 'ECE (VLSI Design & Technology)',
    shortLabel: 'ECE-VLSI',
  ),
  BranchOption(
    value: 'entc',
    label: 'Electronics and Telecommunication Engineering',
    shortLabel: 'E&TC',
  ),
  BranchOption(
    value: 'iiot',
    label: 'Industrial Internet of Things',
    shortLabel: 'IIOT',
  ),
  BranchOption(
    value: 'instrumentation',
    label: 'Instrumentation and Control Engineering',
    shortLabel: 'I&C',
  ),
  BranchOption(
    value: 'biomedical',
    label: 'Biomedical Engineering',
    shortLabel: 'BME',
  ),
  BranchOption(value: 'biotech', label: 'Biotechnology', shortLabel: 'BT'),
  BranchOption(
    value: 'chemical',
    label: 'Chemical Engineering',
    shortLabel: 'CHE',
  ),
  BranchOption(value: 'ce', label: 'Civil Engineering', shortLabel: 'CE'),
  BranchOption(
    value: 'manufacturing',
    label: 'Manufacturing Science and Engineering',
    shortLabel: 'MFG',
  ),
  BranchOption(
    value: 'metallurgy',
    label: 'Metallurgy and Materials Engineering',
    shortLabel: 'META',
  ),
];

const Map<String, String> _branchAliases = <String, String>{
  'cs': 'cse',
  'cse/cs': 'cse',
  'cse-cs': 'cse_cs',
  'cse_cs': 'cse_cs',
  'cyber security': 'cse_cs',
  'cybersecurity': 'cse_cs',
  'csit': 'it',
  'it/csit': 'it',
  'cse(ai)': 'cse_ai',
  'cse-ai': 'cse_ai',
  'cse ai': 'cse_ai',
  'cse_ai': 'cse_ai',
  'ai': 'cse_ai',
  'cse-aiml': 'aiml',
  'cse_aiml': 'aiml',
  'cse aiml': 'aiml',
  'cse(ai&ml)': 'aiml',
  'cse(ai & ml)': 'aiml',
  'cse(ai ml)': 'aiml',
  'ai&ml': 'aiml',
  'ai/ml': 'aiml',
  'cse(ds)': 'ds',
  'cse-ds': 'ds',
  'data science': 'ds',
  'computer engineering': 'computer',
  'coe': 'computer',
  'computer science and business systems': 'csbs',
  'mathematics and computing': 'mnc',
  'mtrx': 'mechatronics',
  'rai': 'robotics_ai',
  'artificial intelligence machine learning': 'ai_ml',
  'artificial intelligence and machine learning': 'ai_ml',
  'artificial intelligence data science': 'ai_ds',
  'artificial intelligence and data science': 'ai_ds',
  'advanced mechatronics and industrial automation': 'amia',
  'am&ia': 'amia',
  'am ia': 'amia',
  'electrical engineering': 'ee',
  'electrical and computer engineering': 'eec',
  'electrical & computer engineering': 'eec',
  'electronics and instrumentation engineering': 'eic',
  'electronics & instrumentation engineering': 'eic',
  'electronics and communication engineering': 'ece',
  'electronics & communication engineering': 'ece',
  'ece(iot)': 'ece_iot',
  'ece-iot': 'ece_iot',
  'ece iot': 'ece_iot',
  'electronics and communication engineering iot': 'ece_iot',
  'electronics and computer engineering': 'ecm',
  'ece(vlsi)': 'ece_vlsi',
  'ece-vlsi': 'ece_vlsi',
  'ece vlsi': 'ece_vlsi',
  'vlsi': 'ece_vlsi',
  'electronics and telecommunication engineering': 'entc',
  'e&tc': 'entc',
  'industrial internet of things': 'iiot',
  'internet of things': 'iiot',
  'instrumentation and control engineering': 'instrumentation',
  'i&c': 'instrumentation',
  'biomedical engineering': 'biomedical',
  'bme': 'biomedical',
  'biotechnology': 'biotech',
  'bt': 'biotech',
  'chemical engineering': 'chemical',
  'che': 'chemical',
  'civil engineering': 'ce',
  'mechatronics and automation': 'mechatronics',
  'mechatronics engineering': 'mechatronics',
  'automation and robotics': 'automation_robotics',
  'automation robotics': 'automation_robotics',
  'a&r': 'automation_robotics',
  'robotics and ai': 'robotics_ai',
  'robotics and artificial intelligence': 'robotics_ai',
  'robotics ai': 'robotics_ai',
  'metallurgy and materials engineering': 'metallurgy',
  'meta': 'metallurgy',
  'manufacturing science and engineering': 'manufacturing',
  'mfg': 'manufacturing',
};

const Map<String, List<String>> _collegeAliases = <String, List<String>>{
  'kiet': <String>[
    'kiet',
    'kiet.edu',
    'kiet group of institutions',
    'krishna institute of engineering and technology',
  ],
  'iiitbh': <String>[
    'iiitbh',
    'iiitbhagalpur',
    'iiit bhagalpur',
    'iiitbh.ac.in',
  ],
  'thapar': <String>[
    'thapar',
    'thapar.edu',
    'thapar.edu.in',
    'thapar institute of engineering and technology',
    'thapar institute',
    'tiet',
  ],
  'coep': <String>[
    'coep',
    'coep pune',
    'coep technological university',
    'coeptech.ac.in',
    'college of engineering pune',
  ],
  'iiitn': <String>[
    'iiitn',
    'iiit nagpur',
    'iiitn.ac.in',
    'indian institute of information technology nagpur',
  ],
  'usar': <String>[
    'usar',
    'usar ggsipu',
    'ggsipu usar',
    'ipu.ac.in',
    'ggsipu',
    'guru gobind singh indraprastha university',
    'university school of automation and robotics',
  ],
};

const List<String> _kietBranchCodes = <String>[
  'cse',
  'it',
  'cse_ai',
  'aiml',
  'ds',
  'cse_cs',
  'me',
  'amia',
  'elce',
  'eee',
  'ece',
  'ece_vlsi',
  'ce',
];

const List<String> _iiitBhBranchCodes = <String>[
  'cse',
  'ece',
  'mechatronics',
  'mnc',
];

const List<String> _thaparBranchCodes = <String>[
  'computer',
  'cse',
  'csbs',
  'ee',
  'eec',
  'eic',
  'biomedical',
  'ece',
  'ecm',
  'chemical',
  'ce',
  'me',
  'mechatronics',
  'robotics_ai',
  'biotech',
];

const List<String> _coepBranchCodes = <String>[
  'ce',
  'computer',
  'ee',
  'entc',
  'instrumentation',
  'me',
  'metallurgy',
  'manufacturing',
  'robotics_ai',
];

const List<String> _iiitNagpurBranchCodes = <String>['cse', 'ece_iot'];

const List<String> _usarBranchCodes = <String>[
  'ai_ml',
  'ai_ds',
  'iiot',
  'automation_robotics',
];

const Map<String, List<String>> _iiitBhFirstYearSubjects =
    <String, List<String>>{
      '1': <String>[
        'Physics',
        'Chemistry',
        'Mathematics-I',
        'English',
        'Basic Electrical and Electronics Engineering',
        'Engineering Graphics',
      ],
      '2': <String>[
        'Computer Programming',
        'Engineering Mechanics',
        'Mathematics-II',
        'Environmental Studies',
        'Basic Electronics Engineering',
      ],
    };

const Map<String, List<String>> _thaparFirstYearSubjects =
    <String, List<String>>{
      '1': <String>[
        'Physics',
        'Engineering Drawing',
        'Professional Communication',
        'Manufacturing Process',
        'Mathematics-I',
      ],
      '2': <String>[
        'Chemistry',
        'Programming for Problem Solving',
        'Electrical and Electronics Engineering',
        'Energy and Environment',
        'Mathematics-II',
      ],
    };

const Map<String, List<String>> _coepFirstYearSubjects = <String, List<String>>{
  '1': <String>[
    'Calculus and Differential Equations',
    'Engineering Chemistry',
    'Engineering Mechanics',
    'Fundamental of Electrical and Electronics Engineering',
    'Semiconductor Physics and Devices',
    'Engineering Graphics and Design Lab',
    'Engineering Chemistry Lab',
    'Semiconductor Physics and Devices Lab',
  ],
  '2': <String>[
    'Linear Algebra and Complex Variables',
    'Environmental Science and Technology',
    'Programming for Problem Solving',
    'Basic Workshop Technology',
    'Basic Civil and Mechanical Engineering',
    'Programming for Problem Solving Lab',
    'Basic Workshop Technology Lab',
    'Basic Civil and Mechanical Engineering Lab',
  ],
};

const Map<String, List<String>> _iiitNagpurFirstYearSubjects =
    <String, List<String>>{
      '1': <String>[
        'Engineering Physics',
        'Engineering Chemistry',
        'Engineering Mathematics-I',
        'Basic Electrical Engineering',
        'Engineering Graphics and Design',
      ],
      '2': <String>[
        'Engineering Physics Lab',
        'Engineering Chemistry Lab',
        'Electrical Workshop',
        'Workshop Practice',
        'Engineering Mathematics-II',
        'Data Structures',
        'Basic Electronics Engineering',
        'Communicative English',
      ],
    };

const Map<String, List<String>> _usarFirstYearSubjects = <String, List<String>>{
  '1': <String>[
    'Mathematics-I',
    'Applied Physics-I',
    'Basic Electrical Engineering',
    'Workshop Technology',
    'Engineering Drawing and Visualization',
    'Communication Skills',
    'Applied Physics-I Lab',
    'Electrical Science Lab',
    'Engineering Graphics Lab',
    'Workshop Practice',
  ],
  '2': <String>[
    'Mathematics-II',
    'Applied Physics-II',
    'Applied Chemistry',
    'Programming in C',
    'Mechanics',
    'Environmental Studies',
    'Applied Physics-II Lab',
    'Applied Chemistry Lab',
    'Engineering Mechanics Lab',
    'C Programming Lab',
  ],
};

const Map<String, Map<String, List<String>>> _kietSubjectsByBranchSemester =
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

Map<String, Map<String, List<String>>> _cloneSemestersForBranches(
  List<String> branchCodes,
  Map<String, List<String>> semesterSubjects,
) {
  return <String, Map<String, List<String>>>{
    for (final branchCode in branchCodes)
      branchCode: <String, List<String>>{
        for (final entry in semesterSubjects.entries)
          entry.key: List<String>.from(entry.value),
      },
  };
}

final Map<String, CollegeAcademicCatalog> _collegeCatalogs =
    <String, CollegeAcademicCatalog>{
      'kiet': const CollegeAcademicCatalog(
        key: 'kiet',
        branchCodes: _kietBranchCodes,
        subjectsByBranchSemester: _kietSubjectsByBranchSemester,
      ),
      'iiitbh': CollegeAcademicCatalog(
        key: 'iiitbh',
        branchCodes: _iiitBhBranchCodes,
        subjectsByBranchSemester: _cloneSemestersForBranches(
          _iiitBhBranchCodes,
          _iiitBhFirstYearSubjects,
        ),
      ),
      'thapar': CollegeAcademicCatalog(
        key: 'thapar',
        branchCodes: _thaparBranchCodes,
        subjectsByBranchSemester: _cloneSemestersForBranches(
          _thaparBranchCodes,
          _thaparFirstYearSubjects,
        ),
      ),
      'coep': CollegeAcademicCatalog(
        key: 'coep',
        branchCodes: _coepBranchCodes,
        subjectsByBranchSemester: _cloneSemestersForBranches(
          _coepBranchCodes,
          _coepFirstYearSubjects,
        ),
      ),
      'iiitn': CollegeAcademicCatalog(
        key: 'iiitn',
        branchCodes: _iiitNagpurBranchCodes,
        subjectsByBranchSemester: _cloneSemestersForBranches(
          _iiitNagpurBranchCodes,
          _iiitNagpurFirstYearSubjects,
        ),
      ),
      'usar': CollegeAcademicCatalog(
        key: 'usar',
        branchCodes: _usarBranchCodes,
        subjectsByBranchSemester: _cloneSemestersForBranches(
          _usarBranchCodes,
          _usarFirstYearSubjects,
        ),
      ),
    };

String _normalizeCollegeProbe(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('@', '')
      .replaceAll(RegExp(r'[^a-z0-9. ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String? resolveCollegeCatalogKey({
  String? collegeId,
  String? collegeDomain,
  String? collegeName,
}) {
  final probes = <String>{
    _normalizeCollegeProbe(collegeId),
    _normalizeCollegeProbe(collegeDomain),
    _normalizeCollegeProbe(collegeName),
  }..removeWhere((value) => value.isEmpty);

  for (final entry in _collegeAliases.entries) {
    final aliases = entry.value.map(_normalizeCollegeProbe).toSet();
    for (final probe in probes) {
      if (aliases.contains(probe)) {
        return entry.key;
      }
      if (aliases.any((alias) => alias.isNotEmpty && probe.contains(alias))) {
        return entry.key;
      }
      if (aliases.any((alias) => alias.isNotEmpty && alias.contains(probe))) {
        return entry.key;
      }
    }
  }

  return null;
}

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

List<BranchOption> getBranchOptionsForCollege({
  String? collegeId,
  String? collegeDomain,
  String? collegeName,
}) {
  final catalogKey = resolveCollegeCatalogKey(
    collegeId: collegeId,
    collegeDomain: collegeDomain,
    collegeName: collegeName,
  );
  final catalog = catalogKey == null ? null : _collegeCatalogs[catalogKey];
  final desiredCodes = catalog?.branchCodes ?? _kietBranchCodes;

  return <BranchOption>[
    for (final code in desiredCodes)
      branchOptions.firstWhere(
        (option) => option.value == code,
        orElse: () => BranchOption(value: code, label: code, shortLabel: code),
      ),
  ];
}

List<String> _mergeUniqueSubjects(Iterable<List<String>> subjectGroups) {
  final merged = <String>[];
  final seen = <String>{};
  for (final subjects in subjectGroups) {
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

List<String> getSubjectsForBranchAndSemester(
  String? branch,
  String? semester, {
  String? collegeId,
  String? collegeDomain,
  String? collegeName,
}) {
  final normalizedBranch = normalizeBranchCode(branch);
  final normalizedSemester = (semester ?? '').trim();
  final catalogKey = resolveCollegeCatalogKey(
    collegeId: collegeId,
    collegeDomain: collegeDomain,
    collegeName: collegeName,
  );
  final catalog =
      (catalogKey != null ? _collegeCatalogs[catalogKey] : null) ??
      _collegeCatalogs['kiet']!;

  if (normalizedBranch.isEmpty) return const <String>[];

  final branchCatalog = catalog.subjectsByBranchSemester[normalizedBranch];
  if (branchCatalog == null) return const <String>[];

  if (normalizedSemester.isNotEmpty) {
    final scoped = branchCatalog[normalizedSemester];
    if (scoped != null && scoped.isNotEmpty) {
      return List<String>.from(scoped);
    }
  }

  return _mergeUniqueSubjects(branchCatalog.values);
}
