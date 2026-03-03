class DepartmentOption {
  final String id;
  final String name;

  const DepartmentOption({required this.id, required this.name});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DepartmentOption && other.id == id && other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

const List<DepartmentOption> departmentOptions = [
  DepartmentOption(id: 'general', name: 'General Notices'),
  DepartmentOption(id: 'cse', name: 'Computer Science and Engineering'),
  DepartmentOption(
    id: 'ece',
    name: 'Electronics and Communication Engineering',
  ),
  DepartmentOption(id: 'eee', name: 'Electrical and Electronics Engineering'),
  DepartmentOption(id: 'me', name: 'Mechanical Engineering'),
  DepartmentOption(id: 'ce', name: 'Civil Engineering'),
  DepartmentOption(id: 'it', name: 'Information Technology'),
];
