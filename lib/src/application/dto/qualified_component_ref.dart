class QualifiedComponentRef {
  final String namespace;
  final String componentId;

  const QualifiedComponentRef({
    required this.namespace,
    required this.componentId,
  });

  String get canonical => '@$namespace/$componentId';

  @override
  String toString() => canonical;
}
