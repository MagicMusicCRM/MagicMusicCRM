import 'dart:collection';

import 'package:magic_music_crm/core/navigation/entity_link.dart';

class ContextViewState {
  ContextViewState({
    Map<String, dynamic> filters = const {},
    this.date,
    this.scrollOffset = 0,
    this.selectedColumn,
  }) : filters = UnmodifiableMapView(Map<String, dynamic>.from(filters));

  factory ContextViewState.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt() ?? schemaVersion;
    if (version != schemaVersion) {
      throw const FormatException('Unsupported context view-state version.');
    }
    final rawFilters = json['filters'];
    return ContextViewState(
      filters: rawFilters is Map
          ? rawFilters.map((key, value) => MapEntry(key.toString(), value))
          : const {},
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
      selectedColumn: json['selectedColumn']?.toString(),
    );
  }

  final Map<String, dynamic> filters;
  static const schemaVersion = 1;
  final DateTime? date;
  final double scrollOffset;
  final String? selectedColumn;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    if (filters.isNotEmpty) 'filters': filters,
    if (date != null) 'date': date!.toUtc().toIso8601String(),
    if (scrollOffset != 0) 'scrollOffset': scrollOffset,
    if (selectedColumn != null) 'selectedColumn': selectedColumn,
  };
}

class ContextRouteState {
  const ContextRouteState({required this.link, required this.viewState});

  factory ContextRouteState.fromJson(Map<String, dynamic> json) {
    final rawLink = json['link'];
    final rawViewState = json['viewState'];
    if (rawLink is! Map) {
      throw const FormatException('Context route link is missing.');
    }
    return ContextRouteState(
      link: EntityLink.fromJson(
        rawLink.map((key, value) => MapEntry(key.toString(), value)),
      ),
      viewState: rawViewState is Map
          ? ContextViewState.fromJson(
              rawViewState.map((key, value) => MapEntry(key.toString(), value)),
            )
          : ContextViewState(),
    );
  }

  final EntityLink link;
  final ContextViewState viewState;

  ContextRouteState copyWith({EntityLink? link, ContextViewState? viewState}) {
    return ContextRouteState(
      link: link ?? this.link,
      viewState: viewState ?? this.viewState,
    );
  }

  Map<String, dynamic> toJson() => {
    'link': link.toJson(),
    'viewState': viewState.toJson(),
  };
}
