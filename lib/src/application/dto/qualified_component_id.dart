class QualifiedComponentId {
  final String namespace;
  final String componentId;

  const QualifiedComponentId({
    required this.namespace,
    required this.componentId,
  });

  String get canonical => '@$namespace/$componentId';

  Map<String, String> toStorageFields() {
    return {
      'namespace': namespace,
      'componentId': componentId,
      'qualifiedId': canonical,
    };
  }

  static QualifiedComponentId fromLegacy({
    required String defaultNamespace,
    required String componentId,
  }) {
    return QualifiedComponentId(
      namespace: defaultNamespace,
      componentId: componentId,
    );
  }
}
