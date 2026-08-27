class ProviderFlowState {
  final _scopes = <Map<String, ProviderBinding>>[{}];
  final _values = <int, ProviderFlowValue>{};
  var _nextBindingId = 0;

  ProviderBinding declare(String name, ProviderFlowValue value) {
    final binding = ProviderBinding(_nextBindingId++);
    _scopes.last[name] = binding;
    _values[binding.id] = value;
    return binding;
  }

  ProviderFlowValue read(String name) {
    final binding = _lookup(name);
    return binding == null
        ? ProviderFlowValue.symbol(name)
        : _values[binding.id]!;
  }

  void assign(String name, ProviderFlowValue value) {
    final binding = _lookup(name);
    if (binding != null) _values[binding.id] = value;
  }

  void assignOuter(String name, ProviderFlowValue value) {
    final binding = _lookup(name, skipCurrent: true);
    if (binding != null) _values[binding.id] = value;
  }

  ProviderFlowSnapshot snapshot() => Map<int, ProviderFlowValue>.from(_values);

  ProviderFlowSnapshot capture(Iterable<ProviderBinding> bindings) => {
    for (final binding in bindings) binding.id: _values[binding.id]!,
  };

  ProviderFlowSnapshot join(Iterable<ProviderFlowSnapshot> states) {
    final result = <int, ProviderFlowValue>{};
    for (final state in states) {
      for (final entry in state.entries) {
        result.update(
          entry.key,
          (value) => value.mergedWith(entry.value),
          ifAbsent: () => entry.value,
        );
      }
    }
    return result;
  }

  void restore(ProviderFlowSnapshot state) {
    for (final entry in state.entries) {
      if (_values.containsKey(entry.key)) _values[entry.key] = entry.value;
    }
  }

  void pushScope() => _scopes.add({});

  void popScope() {
    final removed = _scopes.removeLast();
    for (final binding in removed.values) {
      _values.remove(binding.id);
    }
  }

  ProviderBinding? _lookup(String name, {bool skipCurrent = false}) {
    final start = _scopes.length - (skipCurrent ? 2 : 1);
    for (var index = start; index >= 0; index--) {
      final binding = _scopes[index][name];
      if (binding != null) return binding;
    }
    return null;
  }
}

typedef ProviderFlowSnapshot = Map<int, ProviderFlowValue>;

class ProviderBinding {
  const ProviderBinding(this.id);

  final int id;
}

class ProviderFlowValue {
  const ProviderFlowValue({
    this.symbols = const {},
    this.readReceivers = const {},
    this.services = const [],
  });

  factory ProviderFlowValue.symbol(String name) =>
      ProviderFlowValue(symbols: {name});

  static const empty = ProviderFlowValue();

  final Set<String> symbols;
  final Set<String> readReceivers;
  final List<ProviderOrigin> services;

  ProviderFlowValue mergedWith(ProviderFlowValue other) => ProviderFlowValue(
    symbols: {...symbols, ...other.symbols},
    readReceivers: {...readReceivers, ...other.readReceivers},
    services: {...services, ...other.services}.toList(),
  );
}

class ProviderOrigin {
  const ProviderOrigin({
    required this.providerSymbols,
    required this.receiverSymbols,
  });

  final Set<String> providerSymbols;
  final Set<String> receiverSymbols;
}
