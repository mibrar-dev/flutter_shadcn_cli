import 'package:flutter_shadcn_cli/src/registry.dart';

class InstallerRegistryFileOwner {
  final String id;
  final bool isShared;
  final RegistryFile file;

  const InstallerRegistryFileOwner({
    required this.id,
    required this.isShared,
    required this.file,
  });

  factory InstallerRegistryFileOwner.shared(String id, RegistryFile file) {
    return InstallerRegistryFileOwner(id: id, isShared: true, file: file);
  }

  factory InstallerRegistryFileOwner.component(String id, RegistryFile file) {
    return InstallerRegistryFileOwner(id: id, isShared: false, file: file);
  }

  bool get isComponent => !isShared;
}
