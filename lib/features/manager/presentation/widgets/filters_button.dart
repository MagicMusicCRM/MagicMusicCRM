part of 'leads_widget.dart';

// «Фильтры» toolbar button with an active-filter count badge.

class _FiltersButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const _FiltersButton({required this.activeCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final hasActive = activeCount > 0;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: hasActive
          ? OutlinedButton.styleFrom(
              foregroundColor: AppColor.gold,
              side: const BorderSide(color: AppColor.goldLine),
            )
          : null,
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Фильтры'),
          if (hasActive) ...[
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColor.gold,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$activeCount',
                style: const TextStyle(
                  color: AppColor.onGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

