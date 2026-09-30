part of 'messenger_screen.dart';

extension _MessengerSearch on _MessengerScreenState {
  void _resetMessageSearch() {
    _messageSearchTimer?.cancel();
    _messageSearchGeneration++;
    _chatSearchController.clear();
    _searchResults = [];
    _searchContext = null;
    _currentMatchIndex = 0;
    _messageSearchLoading = false;
    _messageSearchHasMore = false;
    _messageSearchError = null;
  }

  void _onSearchInChat() => _emitState(() {
    _isSearchingInChat = !_isSearchingInChat;
    if (!_isSearchingInChat) _resetMessageSearch();
  });

  void _performSearch(String query, {bool jump = false}) {
    _messageSearchTimer?.cancel();
    final generation = ++_messageSearchGeneration;
    final text = query.trim();
    _emitState(() {
      _searchResults = [];
      _searchContext = null;
      _currentMatchIndex = 0;
      _messageSearchHasMore = false;
      _messageSearchLoading = text.isNotEmpty;
      _messageSearchError = null;
    });
    if (text.isEmpty) return;
    if (jump) {
      unawaited(_loadMessageSearch(text, generation));
    } else {
      _messageSearchTimer = Timer(
        const Duration(milliseconds: 350),
        () => _loadMessageSearch(text, generation),
      );
    }
  }

  Future<void> _loadMessageSearch(
    String query,
    int generation, {
    bool more = false,
  }) async {
    final chatId = _selectedChatId;
    if (chatId == null) return;
    _emitState(() {
      _messageSearchLoading = true;
      _messageSearchError = null;
    });
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      final cursor = more && _searchResults.isNotEmpty
          ? _searchResults.last['id'].toString()
          : null;
      final page = _selectedChatType == 'channel'
          ? await messenger.listChannelPosts(
              chatId,
              query: query,
              beforeId: cursor,
              limit: 50,
            )
          : await messenger.listMessages(
              chatId,
              query: query,
              beforeId: cursor,
              limit: 50,
            );
      if (!mounted ||
          generation != _messageSearchGeneration ||
          chatId != _selectedChatId) {
        return;
      }
      final nextIndex = more ? _searchResults.length : 0;
      _emitState(() {
        _searchResults = [
          ...(more ? _searchResults : <Map<String, dynamic>>[]),
          ...page.reversed,
        ];
        _messageSearchHasMore = page.length == 50;
      });
      if (nextIndex < _searchResults.length) {
        await _openSearchMatch(nextIndex, generation);
      }
    } catch (_) {
      if (mounted && generation == _messageSearchGeneration) {
        _emitState(
          () => _messageSearchError =
              'Не удалось выполнить поиск. Повторите запрос.',
        );
      }
    } finally {
      if (mounted && generation == _messageSearchGeneration) {
        _emitState(() => _messageSearchLoading = false);
      }
    }
  }

  Future<void> _openSearchMatch(int index, int generation) async {
    final chatId = _selectedChatId;
    if (chatId == null || index >= _searchResults.length) return;
    final id = _searchResults[index]['id'].toString();
    _emitState(() {
      _messageSearchLoading = true;
      _messageSearchError = null;
    });
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      final items = _selectedChatType == 'channel'
          ? await messenger.listChannelPosts(chatId, atId: id, limit: 30)
          : await messenger.listMessages(chatId, atId: id, limit: 30);
      if (!mounted ||
          generation != _messageSearchGeneration ||
          chatId != _selectedChatId) {
        return;
      }
      if (!items.any((message) => message['id'] == id)) {
        _emitState(
          () => _messageSearchError =
              'Сообщение больше недоступно. Обновите поиск.',
        );
        return;
      }
      _emitState(() {
        _currentMatchIndex = index;
        _searchContext = items;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _messageSearchGeneration) {
          _jumpToMessage(id);
        }
      });
    } catch (_) {
      if (mounted && generation == _messageSearchGeneration) {
        _emitState(
          () => _messageSearchError =
              'Не удалось открыть сообщение. Повторите запрос.',
        );
      }
    } finally {
      if (mounted && generation == _messageSearchGeneration) {
        _emitState(() => _messageSearchLoading = false);
      }
    }
  }

  void _nextSearchMatch() {
    if (_messageSearchLoading || _searchResults.isEmpty) return;
    if (_currentMatchIndex + 1 < _searchResults.length) {
      unawaited(
        _openSearchMatch(_currentMatchIndex + 1, _messageSearchGeneration),
      );
    } else if (_messageSearchHasMore) {
      unawaited(
        _loadMessageSearch(
          _chatSearchController.text.trim(),
          _messageSearchGeneration,
          more: true,
        ),
      );
    }
  }

  void _prevSearchMatch() {
    if (!_messageSearchLoading && _currentMatchIndex > 0) {
      unawaited(
        _openSearchMatch(_currentMatchIndex - 1, _messageSearchGeneration),
      );
    }
  }
}
