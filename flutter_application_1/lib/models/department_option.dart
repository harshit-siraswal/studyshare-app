import '../data/department_catalog.dart';

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

final List<DepartmentOption> departmentOptions = departmentCatalogEntries
    .map((entry) => DepartmentOption(id: entry.code, name: entry.name))
    .toList(growable: false);
