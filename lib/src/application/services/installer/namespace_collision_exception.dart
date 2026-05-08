import 'package:flutter_shadcn_cli/src/application/services/installer/namespace_collision.dart';

class NamespaceCollisionException implements Exception {
  final List<NamespaceCollision> collisions;

  const NamespaceCollisionException(this.collisions);

  @override
  String toString() {
    final details = collisions.map((collision) {
      return '${collision.kind} "${collision.identifier}" is owned by '
          '${collision.existingOwner} and cannot be claimed by '
          '${collision.pendingOwner}';
    }).join('; ');
    return 'Namespace collision: $details';
  }
}
