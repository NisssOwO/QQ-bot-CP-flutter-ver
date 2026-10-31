String generateRoleId(String displayName, Iterable<String> existingIds) {
  final source = displayName.trim().toLowerCase();
  var slug = source
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) slug = 'role';
  slug = slug.substring(0, slug.length > 36 ? 36 : slug.length);

  final existing = existingIds.map((id) => id.trim().toLowerCase()).toSet();
  var candidate = 'custom.$slug';
  var suffix = 2;
  while (existing.contains(candidate)) {
    candidate = 'custom.$slug-$suffix';
    suffix += 1;
  }
  return candidate;
}
