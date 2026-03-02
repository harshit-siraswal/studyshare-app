/// Lightweight stand-in for `dart:io`'s `File` on platforms without `dart:io`.
///
/// This stub only stores a path string so shared viewer code can compile on web;
/// use real `dart:io` `File` for actual filesystem operations.
class File {
  final String path;

  const File(this.path);
}
