import 'academic_subjects_data.dart';

enum Branch {
  cse,
  it,
  cseAi,
  aiml,
  ds,
  cseCs,
  me,
  amia,
  elce,
  eee,
  ece,
  eceVlsi,
  ce,
}

const Map<Branch, String> _branchCodeByEnum = <Branch, String>{
  Branch.cse: 'cse',
  Branch.it: 'it',
  Branch.cseAi: 'cse_ai',
  Branch.aiml: 'aiml',
  Branch.ds: 'ds',
  Branch.cseCs: 'cse_cs',
  Branch.me: 'me',
  Branch.amia: 'amia',
  Branch.elce: 'elce',
  Branch.eee: 'eee',
  Branch.ece: 'ece',
  Branch.eceVlsi: 'ece_vlsi',
  Branch.ce: 'ce',
};

/// Backward-compatible consolidated subjects by branch.
final Map<Branch, List<String>> syllabusSubjects = <Branch, List<String>>{
  for (final entry in _branchCodeByEnum.entries)
    entry.key: getSubjectsForBranchAndSemester(entry.value, null),
};

List<String> getSyllabusSubjectsForBranch(Branch branch, {String? semester}) {
  return getSubjectsForBranchAndSemester(_branchCodeByEnum[branch], semester);
}
