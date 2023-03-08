class MapHelper {
  /// Merge two maps recursively. If the same key exists in both maps, the value
  /// from the second map will be used. If the value is a map, the merge will be
  /// recursive. Sub-maps also have to have their keys be of type [K].
  static Map<K, dynamic> merge<K>(Map<K, dynamic> a, Map<K, dynamic> b) {
    for (K key in b.keys) {
      if (a.containsKey(key)) {
        if (a[key] is Map && b[key] is Map) {
          a[key] = merge(a[key] as Map<K, dynamic>, b[key] as Map<K, dynamic>);
        } else {
          a[key] = b[key]!;
        }
      } else {
        a[key] = b[key]!;
      }
    }

    return a;
  }
}
