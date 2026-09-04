class NamespaceCollision {
  final String kind;
  final String identifier;
  final String existingOwner;
  final String pendingOwner;

  const NamespaceCollision({
    required this.kind,
    required this.identifier,
    required this.existingOwner,
    required this.pendingOwner,
  });
}
