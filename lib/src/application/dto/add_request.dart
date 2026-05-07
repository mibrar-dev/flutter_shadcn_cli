class AddRequest {
  final String namespace;
  final String componentId;
  final String? version;

  const AddRequest({
    required this.namespace,
    required this.componentId,
    this.version,
  });
}
