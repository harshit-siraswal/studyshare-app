import 'package:flutter/foundation.dart';

import '../models/resource.dart';
import 'backend_api_service.dart';
import 'supabase_service.dart';

class ResourceStateRepository {
  factory ResourceStateRepository({SupabaseService? supabaseService}) {
    if (supabaseService != null) {
      return ResourceStateRepository._(supabaseService);
    }
    return _instance;
  }

  ResourceStateRepository._(this._supabaseService);

  static final ResourceStateRepository _instance =
      ResourceStateRepository._(SupabaseService());

  final SupabaseService _supabaseService;

  Future<void> prefetchBookmarkStateForResources({
    required String userEmail,
    required Iterable<Resource> resources,
  }) async {
    await prefetchBookmarkStateForResourceIds(
      userEmail: userEmail,
      resourceIds: resources.map((resource) => resource.id),
    );
  }

  Future<void> prefetchBookmarkStateForResourceIds({
    required String userEmail,
    required Iterable<String> resourceIds,
  }) async {
    final ids = resourceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    await _supabaseService.prefetchBookmarksForResources(
      userEmail: userEmail,
      resourceIds: ids,
    );
  }

  Future<void> prefetchResourceStateForResourceIds({
    required String userEmail,
    required Iterable<String> resourceIds,
    bool includeVotes = true,
  }) async {
    final ids = resourceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    try {
      await _supabaseService.prefetchResourceStatesFromBulkEndpoint(
        userEmail: userEmail,
        resourceIds: ids,
      );
      return;
    } catch (e) {
      if (!isBackendCompatibilityFallbackError(e)) {
        debugPrint(
          'Bulk resource-state prefetch failed; skipping legacy fallback: $e',
        );
        return;
      }
      debugPrint(
        'Bulk resource-state endpoint unavailable, using legacy prefetch fallback: $e',
      );
    }

    final tasks = <Future<void>>[
      _supabaseService.prefetchBookmarksForResources(
        userEmail: userEmail,
        resourceIds: ids,
      ),
      if (includeVotes)
        _supabaseService.prefetchVotesForResources(
          userEmail: userEmail,
          resourceIds: ids,
        ),
    ];

    await Future.wait(tasks);
  }

  Future<void> prefetchResourceStateForResources({
    required String userEmail,
    required Iterable<Resource> resources,
    bool includeVotes = true,
  }) async {
    await prefetchResourceStateForResourceIds(
      userEmail: userEmail,
      resourceIds: resources.map((resource) => resource.id),
      includeVotes: includeVotes,
    );
  }

  bool? getCachedBookmarkState({
    required String userEmail,
    required String resourceId,
  }) {
    return _supabaseService.getCachedBookmarkState(userEmail, resourceId);
  }

  ({int? userVote, int upvotes, int downvotes})? getCachedVoteState({
    required String userEmail,
    required String resourceId,
  }) {
    return _supabaseService.getCachedVoteState(resourceId, userEmail: userEmail);
  }
}
