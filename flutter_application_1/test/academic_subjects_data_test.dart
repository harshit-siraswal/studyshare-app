import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/data/academic_subjects_data.dart';

void main() {
  group('USAR academic catalog', () {
    test('resolves Delhi and GGSIPU aliases', () {
      expect(resolveCollegeCatalogKey(collegeName: 'USAR Delhi'), 'usar');
      expect(
        resolveCollegeCatalogKey(
          collegeName: 'University School of Automation and Robotics',
        ),
        'usar',
      );
      expect(resolveCollegeCatalogKey(collegeDomain: 'ipu.ac.in'), 'usar');
    });

    test('exposes USAR branches in official programme order', () {
      final branches = getBranchOptionsForCollege(collegeId: 'usar');

      expect(branches.map((branch) => branch.value), <String>[
        'ai_ml',
        'ai_ds',
        'iiot',
        'automation_robotics',
      ]);
      expect(branches.map((branch) => branch.shortLabel), contains('A&R'));
    });

    test('returns branch-specific semester subjects and electives', () {
      expect(
        getSubjectsForBranchAndSemester('ai_ds', '5', collegeId: 'usar'),
        containsAll(<String>[
          'Big Data Analytics',
          'Pattern Recognition',
          '3D-Printing Technologies',
        ]),
      );

      expect(
        getSubjectsForBranchAndSemester(
          'ai_ml',
          '7',
          collegeName: 'USAR GGSIPU',
        ),
        containsAll(<String>[
          'Introduction to Deep Learning',
          'Introduction to Large Language Models',
          'Web Development',
        ]),
      );

      expect(
        getSubjectsForBranchAndSemester(
          'iiot',
          '6',
          collegeDomain: 'ipu.ac.in',
        ),
        containsAll(<String>[
          'Electronic Design Automation for VLSI',
          'Cyber Security and Digital Forensics',
          'Operations Management',
        ]),
      );

      expect(
        getSubjectsForBranchAndSemester(
          'automation robotics',
          '4',
          collegeId: 'usar',
        ),
        containsAll(<String>[
          'Kinematics and Dynamics of Machines',
          'Production Technology Lab',
        ]),
      );
    });
  });
}
