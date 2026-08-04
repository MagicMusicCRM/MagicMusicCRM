import 'package:flutter/material.dart';

class Skeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const Skeleton({super.key, this.width, this.height, this.borderRadius = 8});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [
                0.0,
                (_animation.value - 0.5).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.5).clamp(0.0, 1.0),
                1.0,
              ],
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Skeleton(width: 50, height: 50, borderRadius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(width: 150, height: 16),
                const SizedBox(height: 8),
                const Skeleton(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ListSkeleton extends StatelessWidget {
  final int count;
  const ListSkeleton({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, index) => const CardSkeleton(),
    );
  }
}

class TimelineSkeleton extends StatelessWidget {
  final int count;

  const TimelineSkeleton({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Skeleton(width: 40, height: 40, borderRadius: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 160, height: 14),
                    SizedBox(height: 8),
                    Skeleton(height: 12),
                    SizedBox(height: 6),
                    Skeleton(width: 220, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScheduleSkeleton extends StatelessWidget {
  final int rows;
  final int columns;

  const ScheduleSkeleton({super.key, this.rows = 6, this.columns = 5});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Column(
        children: List.generate(
          rows,
          (row) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: row == rows - 1 ? 0 : 8),
              child: Row(
                children: List.generate(
                  columns,
                  (column) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: column == columns - 1 ? 0 : 8,
                      ),
                      child: const Skeleton(borderRadius: 6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KanbanSkeleton extends StatelessWidget {
  final int columns;
  final int cardsPerColumn;

  const KanbanSkeleton({super.key, this.columns = 4, this.cardsPerColumn = 4});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(
          columns,
          (column) => Container(
            width: 300,
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Skeleton(width: 10, height: 10, borderRadius: 5),
                      SizedBox(width: 8),
                      Skeleton(width: 120, height: 16),
                      Spacer(),
                      Skeleton(width: 28, height: 18, borderRadius: 9),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...List.generate(
                    cardsPerColumn,
                    (index) => const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: CardSkeleton(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardStatsSkeleton extends StatelessWidget {
  final int count;

  const DashboardStatsSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(width: 130, height: 26),
          const SizedBox(height: 8),
          const Skeleton(width: 280, height: 14),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 1100
                  ? 4
                  : width >= 720
                  ? 3
                  : 2;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: width >= 720 ? 2.6 : 2.15,
                children: List.generate(
                  count,
                  (_) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Skeleton(width: 34, height: 34, borderRadius: 8),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Skeleton(width: 70, height: 18),
                              SizedBox(height: 8),
                              Skeleton(width: 110, height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
