import 'package:flutter_shadcn_cli/src/application/services/lockfile/shadcn_lock_repository.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/namespace_collision.dart';
import 'package:flutter_shadcn_cli/src/application/services/installer/namespace_collision_exception.dart';

class NamespaceCollisionPolicy {
  const NamespaceCollisionPolicy();

  void checkPendingInstall({
    required ShadcnLock lock,
    required ShadcnLockComponent pending,
    required String defaultNamespace,
  }) {
    final collisions = <NamespaceCollision>[];
    final pendingOwner = _qualifiedOwner(pending, defaultNamespace);

    for (final existing in lock.components) {
      final existingOwner = _qualifiedOwner(existing, defaultNamespace);
      if (existingOwner == pendingOwner) {
        continue;
      }

      _collectPathCollisions(
        collisions: collisions,
        kind: 'generated target',
        existingOwner: existingOwner,
        pendingOwner: pendingOwner,
        existingValues: existing.installedFiles,
        pendingValues: pending.installedFiles,
        existingSharedValues: existing.sharedFiles,
        pendingSharedValues: pending.sharedFiles,
      );
      _collectCollisions(
        collisions: collisions,
        kind: 'asset path',
        existingOwner: existingOwner,
        pendingOwner: pendingOwner,
        existingValues: existing.assetPaths,
        pendingValues: pending.assetPaths,
      );
      _collectCollisions(
        collisions: collisions,
        kind: 'manifest key',
        existingOwner: existingOwner,
        pendingOwner: pendingOwner,
        existingValues: existing.manifestKeys,
        pendingValues: pending.manifestKeys,
      );
      _collectCollisions(
        collisions: collisions,
        kind: 'post-install namespace',
        existingOwner: existingOwner,
        pendingOwner: pendingOwner,
        existingValues: existing.postInstallNamespaces,
        pendingValues: pending.postInstallNamespaces,
      );
      _collectCollisions(
        collisions: collisions,
        kind: 'locale namespace',
        existingOwner: existingOwner,
        pendingOwner: pendingOwner,
        existingValues: existing.localeNamespaces,
        pendingValues: pending.localeNamespaces,
      );
      _collectCollisions(
        collisions: collisions,
        kind: 'locale key',
        existingOwner: existingOwner,
        pendingOwner: pendingOwner,
        existingValues: existing.localeKeys,
        pendingValues: pending.localeKeys,
      );
    }

    if (collisions.isNotEmpty) {
      throw NamespaceCollisionException(collisions);
    }
  }

  void _collectPathCollisions({
    required List<NamespaceCollision> collisions,
    required String kind,
    required String existingOwner,
    required String pendingOwner,
    required List<String> existingValues,
    required List<String> pendingValues,
    required List<String> existingSharedValues,
    required List<String> pendingSharedValues,
  }) {
    final existingShared = _normalizedSet(existingSharedValues);
    final pendingShared = _normalizedSet(pendingSharedValues);
    for (final identifier in _normalizedSet(existingValues)
        .intersection(_normalizedSet(pendingValues))) {
      if (existingShared.contains(identifier) &&
          pendingShared.contains(identifier)) {
        continue;
      }
      collisions.add(
        NamespaceCollision(
          kind: kind,
          identifier: identifier,
          existingOwner: existingOwner,
          pendingOwner: pendingOwner,
        ),
      );
    }
  }

  void _collectCollisions({
    required List<NamespaceCollision> collisions,
    required String kind,
    required String existingOwner,
    required String pendingOwner,
    required List<String> existingValues,
    required List<String> pendingValues,
  }) {
    for (final identifier in _normalizedSet(existingValues)
        .intersection(_normalizedSet(pendingValues))) {
      collisions.add(
        NamespaceCollision(
          kind: kind,
          identifier: identifier,
          existingOwner: existingOwner,
          pendingOwner: pendingOwner,
        ),
      );
    }
  }

  Set<String> _normalizedSet(List<String> values) {
    return values
        .map((value) => value.trim().replaceAll('\\', '/'))
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String _qualifiedOwner(
    ShadcnLockComponent component,
    String defaultNamespace,
  ) {
    final namespace = component.namespace.trim().isNotEmpty
        ? component.namespace.trim()
        : defaultNamespace;
    if (component.qualifiedId.trim().isNotEmpty &&
        component.qualifiedId.startsWith('@')) {
      return component.qualifiedId.trim();
    }
    return '@$namespace/${component.componentId}';
  }
}
