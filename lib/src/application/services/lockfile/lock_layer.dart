/// The three implicit layers that live next to `components/` in an install.
///
/// Layers are never addressed as components: they are pulled in by the
/// dependency closure and tracked separately in `shadcn.lock` so `remove` can
/// drop a unit once no installed component references it.
enum LockLayer {
  foundation('foundation'),
  theme('theme'),
  primitives('primitives');

  const LockLayer(this.key);

  /// Directory name under the install root, and the key used in the lock.
  final String key;

  /// Resolves a lock key, or `null` when [key] is not a v2 layer.
  static LockLayer? fromKey(String key) {
    final normalized = key.trim();
    for (final layer in LockLayer.values) {
      if (layer.key == normalized) {
        return layer;
      }
    }
    return null;
  }
}
