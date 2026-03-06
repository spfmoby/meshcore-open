import 'package:flutter/foundation.dart';
import '../models/contact.dart';
import '../models/path_history.dart';
import '../models/path_selection.dart';
import 'storage_service.dart';

class PathHistoryService extends ChangeNotifier {
  final StorageService _storage;
  final Map<String, ContactPathHistory> _cache = {};
  final Map<String, int> _autoRotationIndex = {};
  final Map<String, _FloodStats> _floodStats = {};

  // LRU cache eviction tracking
  static const int _maxCachedContacts = 50;
  final List<String> _cacheAccessOrder = [];

  static const int _maxHistoryEntries = 100;

  int _version = 0;
  int get version => _version;
  static const int _autoRotationTopCount = 3;

  PathHistoryService(this._storage);

  Future<void> initialize() async {
    // Load cached path histories on startup if needed
  }

  void handlePathUpdated(Contact contact) {
    if (contact.pathLength < 0) return;

    _addPathRecord(
      contactPubKeyHex: contact.publicKeyHex,
      hopCount: contact.pathLength,
      tripTimeMs: 0,
      wasFloodDiscovery: true,
      pathBytes: contact.path,
      successCount: 0,
      failureCount: 0,
    );
  }

  void recordPathAttempt(String contactPubKeyHex, PathSelection selection) {
    if (selection.useFlood) {
      _updateFloodStats(contactPubKeyHex);
      return;
    }

    _addPathRecord(
      contactPubKeyHex: contactPubKeyHex,
      hopCount: selection.hopCount,
      tripTimeMs: 0,
      wasFloodDiscovery: false,
      pathBytes: selection.pathBytes,
      successCount: 0,
      failureCount: 0,
    );
  }

  void recordPathResult(
    String contactPubKeyHex,
    PathSelection selection, {
    required bool success,
    int? tripTimeMs,
  }) {
    if (selection.useFlood) {
      final stats = _floodStats.putIfAbsent(
        contactPubKeyHex,
        () => _FloodStats(),
      );
      if (success) {
        stats.successCount += 1;
        if (tripTimeMs != null) stats.lastTripTimeMs = tripTimeMs;
      } else {
        stats.failureCount += 1;
      }
      stats.lastUsed = DateTime.now();
      return;
    }

    final existing = _findPathRecord(contactPubKeyHex, selection.pathBytes);
    final successCount = (existing?.successCount ?? 0) + (success ? 1 : 0);
    final failureCount = (existing?.failureCount ?? 0) + (success ? 0 : 1);

    _addPathRecord(
      contactPubKeyHex: contactPubKeyHex,
      hopCount: selection.hopCount,
      tripTimeMs: success ? (tripTimeMs ?? 0) : (existing?.tripTimeMs ?? 0),
      wasFloodDiscovery: existing?.wasFloodDiscovery ?? false,
      pathBytes: selection.pathBytes,
      successCount: successCount,
      failureCount: failureCount,
    );
  }

  PathSelection getNextAutoPathSelection(String contactPubKeyHex) {
    final ranked = _getRankedPaths(
      contactPubKeyHex,
    ).take(_autoRotationTopCount).toList();
    if (ranked.isEmpty) {
      return const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
    }

    _trackAccess(contactPubKeyHex);

    final selections =
        ranked
            .map(
              (path) => PathSelection(
                pathBytes: path.pathBytes,
                hopCount: path.hopCount,
                useFlood: false,
              ),
            )
            .toList()
          ..add(
            const PathSelection(pathBytes: [], hopCount: -1, useFlood: true),
          );

    final currentIndex = _autoRotationIndex[contactPubKeyHex] ?? 0;
    final selection = selections[currentIndex % selections.length];
    _autoRotationIndex[contactPubKeyHex] = currentIndex + 1;
    return selection;
  }

  void _addPathRecord({
    required String contactPubKeyHex,
    required int hopCount,
    required int tripTimeMs,
    required bool wasFloodDiscovery,
    required List<int> pathBytes,
    required int successCount,
    required int failureCount,
  }) {
    var history = _cache[contactPubKeyHex];

    if (history == null) {
      _loadHistoryFromStorage(contactPubKeyHex).then((loaded) {
        if (loaded != null) {
          _cache[contactPubKeyHex] = loaded;
          _addPathRecordInternal(
            contactPubKeyHex,
            hopCount,
            tripTimeMs,
            wasFloodDiscovery,
            pathBytes,
            successCount,
            failureCount,
          );
        } else {
          _cache[contactPubKeyHex] = ContactPathHistory(
            contactPubKeyHex: contactPubKeyHex,
            recentPaths: [],
          );
          _addPathRecordInternal(
            contactPubKeyHex,
            hopCount,
            tripTimeMs,
            wasFloodDiscovery,
            pathBytes,
            successCount,
            failureCount,
          );
        }
      });
      return;
    }

    _addPathRecordInternal(
      contactPubKeyHex,
      hopCount,
      tripTimeMs,
      wasFloodDiscovery,
      pathBytes,
      successCount,
      failureCount,
    );
  }

  void _addPathRecordInternal(
    String contactPubKeyHex,
    int hopCount,
    int tripTimeMs,
    bool wasFloodDiscovery,
    List<int> pathBytes,
    int successCount,
    int failureCount,
  ) {
    var history = _cache[contactPubKeyHex];
    if (history == null) return;
    _version++;

    final existing = _findPathRecord(contactPubKeyHex, pathBytes);
    if (existing != null) {
      successCount = successCount == 0 ? existing.successCount : successCount;
      failureCount = failureCount == 0 ? existing.failureCount : failureCount;
      if (tripTimeMs == 0) {
        tripTimeMs = existing.tripTimeMs;
      }
      wasFloodDiscovery = existing.wasFloodDiscovery || wasFloodDiscovery;
    }

    final newRecord = PathRecord(
      hopCount: hopCount,
      tripTimeMs: tripTimeMs,
      timestamp: DateTime.now(),
      wasFloodDiscovery: wasFloodDiscovery,
      pathBytes: pathBytes,
      successCount: successCount,
      failureCount: failureCount,
    );

    final updatedPaths = List<PathRecord>.from(history.recentPaths);

    updatedPaths.removeWhere((p) => _pathsEqual(p.pathBytes, pathBytes));

    if (existing == null && updatedPaths.length >= _maxHistoryEntries) {
      return;
    }

    updatedPaths.insert(0, newRecord);

    final updatedHistory = ContactPathHistory(
      contactPubKeyHex: contactPubKeyHex,
      recentPaths: updatedPaths,
    );

    _cache[contactPubKeyHex] = updatedHistory;
    _trackAccess(contactPubKeyHex);
    _evictIfNeeded();
    _storage.savePathHistory(contactPubKeyHex, updatedHistory);

    notifyListeners();
  }

  List<PathRecord> getRecentPaths(String contactPubKeyHex) {
    final history = _cache[contactPubKeyHex];
    if (history != null) {
      _trackAccess(contactPubKeyHex);
      return history.recentPaths;
    }

    _loadHistoryFromStorage(contactPubKeyHex).then((loaded) {
      if (loaded != null) {
        _cache[contactPubKeyHex] = loaded;
        _trackAccess(contactPubKeyHex);
        _evictIfNeeded();
        _version++;
        notifyListeners();
      }
    });

    return [];
  }

  Future<ContactPathHistory?> _loadHistoryFromStorage(
    String contactPubKeyHex,
  ) async {
    return await _storage.loadPathHistory(contactPubKeyHex);
  }

  PathRecord? getFastestPath(String contactPubKeyHex) {
    final history = _cache[contactPubKeyHex];
    if (history != null) {
      _trackAccess(contactPubKeyHex);
    }
    return history?.fastest;
  }

  PathRecord? getMostRecentPath(String contactPubKeyHex) {
    final history = _cache[contactPubKeyHex];
    if (history != null) {
      _trackAccess(contactPubKeyHex);
    }
    return history?.mostRecent;
  }

  Future<void> clearPathHistory(String contactPubKeyHex) async {
    _cache.remove(contactPubKeyHex);
    _cacheAccessOrder.remove(contactPubKeyHex);
    _autoRotationIndex.remove(contactPubKeyHex);
    _floodStats.remove(contactPubKeyHex);
    await _storage.clearPathHistory(contactPubKeyHex);
    notifyListeners();
  }

  Future<void> removePathRecord(
    String contactPubKeyHex,
    List<int> pathBytes,
  ) async {
    final history = _cache[contactPubKeyHex];
    if (history == null) return;

    final updatedPaths = List<PathRecord>.from(history.recentPaths)
      ..removeWhere((p) => _pathsEqual(p.pathBytes, pathBytes));

    _cache[contactPubKeyHex] = ContactPathHistory(
      contactPubKeyHex: contactPubKeyHex,
      recentPaths: updatedPaths,
    );

    await _storage.savePathHistory(contactPubKeyHex, _cache[contactPubKeyHex]!);
    notifyListeners();
  }

  PathRecord? _findPathRecord(String contactPubKeyHex, List<int> pathBytes) {
    final history = _cache[contactPubKeyHex];
    if (history == null) return null;
    for (final record in history.recentPaths) {
      if (_pathsEqual(record.pathBytes, pathBytes)) {
        return record;
      }
    }
    return null;
  }

  List<PathRecord> _getRankedPaths(String contactPubKeyHex) {
    final history = _cache[contactPubKeyHex];
    if (history == null) return [];

    final ranked = List<PathRecord>.from(history.recentPaths)
      ..removeWhere((p) => p.pathBytes.isEmpty);

    ranked.sort((a, b) {
      final aRate =
          (a.successCount + 1) / (a.successCount + a.failureCount + 2);
      final bRate =
          (b.successCount + 1) / (b.successCount + b.failureCount + 2);
      if (aRate != bRate) return bRate.compareTo(aRate);
      if (a.successCount != b.successCount) {
        return b.successCount.compareTo(a.successCount);
      }

      final aTrip = a.tripTimeMs == 0 ? 999999 : a.tripTimeMs;
      final bTrip = b.tripTimeMs == 0 ? 999999 : b.tripTimeMs;
      if (aTrip != bTrip) return aTrip.compareTo(bTrip);
      return b.timestamp.compareTo(a.timestamp);
    });

    return ranked;
  }

  bool _pathsEqual(List<int> a, List<int> b) {
    return listEquals(a, b);
  }

  void _updateFloodStats(String contactPubKeyHex) {
    final stats = _floodStats.putIfAbsent(
      contactPubKeyHex,
      () => _FloodStats(),
    );
    stats.lastUsed = DateTime.now();
  }

  void _trackAccess(String contactPubKeyHex) {
    _cacheAccessOrder.remove(contactPubKeyHex);
    _cacheAccessOrder.add(contactPubKeyHex);
  }

  void _evictIfNeeded() {
    while (_cache.length > _maxCachedContacts && _cacheAccessOrder.isNotEmpty) {
      final oldest = _cacheAccessOrder.removeAt(0);
      _cache.remove(oldest);
      _autoRotationIndex.remove(oldest);
      _floodStats.remove(oldest);
    }
  }
}

class _FloodStats {
  int successCount = 0;
  int failureCount = 0;
  int lastTripTimeMs = 0;
  DateTime? lastUsed;
}
