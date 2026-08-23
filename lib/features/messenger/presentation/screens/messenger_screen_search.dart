part of 'messenger_screen.dart';

extension _MessengerSearch on _MessengerScreenState {
  void _onSearchInChat() {
    _emitState(() {
      _isSearchingInChat = !_isSearchingInChat;
      if (!_isSearchingInChat) {
        _chatSearchController.clear();
        _searchResults.clear();
        _currentMatchIndex = 0;
      }
    });
  }

  void _performSearch(String query, {bool jump = false}) {
    if (query.isEmpty) {
      _emitState(() {
        _searchResults.clear();
        _currentMatchIndex = 0;
      });
      return;
    }

    final results = _messages
        .where(
          (m) => (m['content']?.toString() ?? '').toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();

    _emitState(() {
      _searchResults = results;
      if (results.isNotEmpty) {
        if (jump) {
          _currentMatchIndex = 0;
          _jumpToMessage(results.first['id']);
        }
      } else {
        _currentMatchIndex = 0;
      }
    });
  }

  void _nextSearchMatch() {
    if (_searchResults.isEmpty) return;
    _emitState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchResults.length;
      _jumpToMessage(_searchResults[_currentMatchIndex]['id']);
    });
  }

  void _prevSearchMatch() {
    if (_searchResults.isEmpty) return;
    _emitState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _searchResults.length) %
          _searchResults.length;
      _jumpToMessage(_searchResults[_currentMatchIndex]['id']);
    });
  }
}
