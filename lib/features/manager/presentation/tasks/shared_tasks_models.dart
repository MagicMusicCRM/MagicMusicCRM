class SharedTaskAudienceOption {
  const SharedTaskAudienceOption({
    required this.type,
    required this.id,
    required this.label,
  });

  final String type;
  final String id;
  final String label;
}

typedef SharedTaskAudiencePreviewLoader =
    Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> audiences);
