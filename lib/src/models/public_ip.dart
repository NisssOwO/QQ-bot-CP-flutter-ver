class PublicIpResult {
  const PublicIpResult({this.ipv4, this.ipv6, required this.checkedAt, this.error});
  final String? ipv4;
  final String? ipv6;
  final DateTime checkedAt;
  final String? error;
}
