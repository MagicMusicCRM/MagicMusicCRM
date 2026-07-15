part of 'user_roles_widget.dart';

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? accent;

  const _MiniBadge({required this.icon, required this.text, this.accent});

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkSection extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> items;
  final ValueChanged<String> onTap;

  const _LinkSection({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            emptyText,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          )
        else
          ...items.map((item) {
            final first = item['first_name']?.toString() ?? '';
            final last = item['last_name']?.toString() ?? '';
            final name = '$last $first'.trim();
            final phone = item['phone']?.toString() ?? '';
            final status = item['status']?.toString() ?? '';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                name.isEmpty ? 'Без имени' : name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                [phone, status].where((v) => v.isNotEmpty).join(' · '),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: IconButton(
                tooltip: 'Связать',
                icon: const Icon(Icons.link, color: AppColor.gold),
                onPressed: () => onTap(item['id'].toString()),
              ),
            );
          }),
      ],
    );
  }
}
