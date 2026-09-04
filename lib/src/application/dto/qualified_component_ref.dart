class QualifiedComponentRef {
  final String namespace;
  final String componentId;
  final String? version;

  const QualifiedComponentRef({
    required this.namespace,
    required this.componentId,
    this.version,
  });

  String get canonical =>
      '@$namespace/$componentId${version == null ? '' : '@$version'}';

  @override
  String toString() => canonical;
}
