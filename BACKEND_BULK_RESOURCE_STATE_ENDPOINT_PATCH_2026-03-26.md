# Backend Patch: Bulk Resource State Endpoint
Date: 2026-03-26

Goal:
- Add a true bulk endpoint for resource state at POST /api/resources/state
- Return bookmark + vote status in one call for a list of resource IDs
- Match Flutter client contract already integrated in this workspace

## 1) API Contract

Request:
- Method: POST
- Path: /api/resources/state
- Body:
  {
    "resourceIds": ["resource-id-1", "resource-id-2"]
  }

Response:
- Status: 200
- Body:
  {
    "states": [
      {
        "resourceId": "resource-id-1",
        "isBookmarked": true,
        "userVote": "upvote",
        "upvotes": 12,
        "downvotes": 2
      },
      {
        "resourceId": "resource-id-2",
        "isBookmarked": false,
        "userVote": null,
        "upvotes": 3,
        "downvotes": 0
      }
    ]
  }

Notes:
- userVote may be "upvote" | "downvote" | null
- If a resource has no rows in votes/bookmarks, still return default state with zero counts and false bookmark.

## 2) Route

File (example): src/routes/resource.routes.ts

Add route:

import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { requireAuth } from '../middleware/auth';
import { getBulkResourceStateController } from '../controllers/resourceState.controller';
import { validateBulkStateRequest } from '../middleware/validateBulkStateRequest';

const router = Router();

const bulkResourceStateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) =>
    ((req as any)?.user?.email?.toString()?.trim()?.toLowerCase() ||
      req.ip ||
      'anonymous'),
});

router.post(
  '/state',
  requireAuth,
  bulkResourceStateLimiter,
  validateBulkStateRequest,
  getBulkResourceStateController,
);

export default router;

If your resources router is mounted under /api/resources, this creates:
- POST /api/resources/state

## 3) Controller

File: src/controllers/resourceState.controller.ts

import type { Request, Response } from 'express';
import { getBulkResourceStates } from '../services/resourceState.service';

const MAX_RESOURCE_IDS = 200;

function normalizeResourceIds(input: unknown): string[] {
  if (!Array.isArray(input)) return [];
  const ids = input
    .map((v) => (typeof v === 'string' ? v.trim() : ''))
    .filter((v) => v.length > 0);
  return Array.from(new Set(ids)).slice(0, MAX_RESOURCE_IDS);
}

const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function getBulkResourceStateController(req: Request, res: Response) {
  try {
    const resourceIds = normalizeResourceIds(req.body?.resourceIds);
    if (resourceIds.length === 0) {
      return res.status(200).json({ states: [] });
    }

    const userEmail =
      (req as any)?.user?.email?.toString()?.trim()?.toLowerCase() || '';

    if (!userEmail) {
      return res.status(401).json({ message: 'Authentication required' });
    }
    if (!emailRegex.test(userEmail)) {
      return res.status(400).json({ message: 'Invalid email format' });
    }

    const states = await getBulkResourceStates({ userEmail, resourceIds });
    return res.status(200).json({ states });
  } catch (error) {
    console.error('getBulkResourceStateController failed:', error);
    return res.status(500).json({
      message: 'Failed to load resource states',
    });
  }
}

## 4) Service

File: src/services/resourceState.service.ts

import { db } from '../db';

type BulkResourceStateInput = {
  userEmail: string;
  resourceIds: string[];
};

type ResourceState = {
  resourceId: string;
  isBookmarked: boolean;
  userVote: 'upvote' | 'downvote' | null;
  upvotes: number;
  downvotes: number;
};

type VoteCountRow = {
  resource_id: string | null;
  upvotes: number | string | null;
  downvotes: number | string | null;
};

type UserVoteRow = {
  resource_id: string | null;
  vote_type: 'upvote' | 'downvote' | string | null;
};

type BookmarkRow = {
  item_id: string | null;
};

function safeString(value: unknown): string {
  return String(value ?? '').trim();
}

export async function getBulkResourceStates(
  input: BulkResourceStateInput,
): Promise<ResourceState[]> {
  const { userEmail, resourceIds } = input;

  if (resourceIds.length === 0) return [];

  const { voteCountsRows, userVotesRows, bookmarksRows } = await db.transaction(
    async (trx) => {
      const voteCountsRows = (await trx('votes')
        .select('resource_id')
        .sum({ upvotes: trx.raw("CASE WHEN vote_type = 'upvote' THEN 1 ELSE 0 END") })
        .sum({ downvotes: trx.raw("CASE WHEN vote_type = 'downvote' THEN 1 ELSE 0 END") })
        .whereIn('resource_id', resourceIds)
        .groupBy('resource_id')) as VoteCountRow[];

      const userVotesRows = (await trx('votes')
        .select('resource_id', 'vote_type')
        .where('user_email', userEmail)
        .whereIn('resource_id', resourceIds)) as UserVoteRow[];

      const bookmarksRows = (await trx('bookmarks')
        .select('item_id')
        .where('user_email', userEmail)
        .where('type', 'resource')
        .whereIn('item_id', resourceIds)) as BookmarkRow[];

      return { voteCountsRows, userVotesRows, bookmarksRows };
    },
  );

  const voteCountsById = new Map<string, { upvotes: number; downvotes: number }>();
  for (const row of voteCountsRows) {
    const id = safeString(row.resource_id);
    if (!id) continue;
    voteCountsById.set(id, {
      upvotes: Number(row.upvotes || 0),
      downvotes: Number(row.downvotes || 0),
    });
  }

  const userVoteById = new Map<string, 'upvote' | 'downvote'>();
  for (const row of userVotesRows) {
    const id = safeString(row.resource_id);
    const vote = row.vote_type === 'upvote' || row.vote_type === 'downvote'
      ? row.vote_type
      : null;
    if (!id || !vote) continue;
    userVoteById.set(id, vote);
  }

  const bookmarkedIds = new Set<string>();
  for (const row of bookmarksRows) {
    const id = safeString(row.item_id);
    if (!id) continue;
    bookmarkedIds.add(id);
  }

  return resourceIds.map((resourceId) => {
    const counts = voteCountsById.get(resourceId) || { upvotes: 0, downvotes: 0 };
    return {
      resourceId,
      isBookmarked: bookmarkedIds.has(resourceId),
      userVote: userVoteById.get(resourceId) || null,
      upvotes: counts.upvotes,
      downvotes: counts.downvotes,
    };
  });
}

## 5) Optional Single SQL (PostgreSQL)

If you prefer a single query path:

SELECT
  input_ids.id AS resource_id,
  EXISTS (
    SELECT 1
    FROM bookmarks b
    WHERE b.user_email = :user_email
      AND b.type = 'resource'
      AND b.item_id = input_ids.id
  ) AS is_bookmarked,
  (
    SELECT v.vote_type
    FROM votes v
    WHERE v.user_email = :user_email
      AND v.resource_id = input_ids.id
    ORDER BY v.created_at DESC
    LIMIT 1
  ) AS user_vote,
  COALESCE(SUM(CASE WHEN v2.vote_type = 'upvote' THEN 1 ELSE 0 END), 0) AS upvotes,
  COALESCE(SUM(CASE WHEN v2.vote_type = 'downvote' THEN 1 ELSE 0 END), 0) AS downvotes
FROM unnest(:resource_ids::text[]) AS input_ids(id)
LEFT JOIN resources r ON r.id = input_ids.id
LEFT JOIN votes v2 ON v2.resource_id = input_ids.id
GROUP BY input_ids.id;

## 6) Suggested indexes

CREATE INDEX IF NOT EXISTS idx_votes_resource_id ON votes(resource_id);
CREATE INDEX IF NOT EXISTS idx_votes_user_resource ON votes(user_email, resource_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_votes_unique_user_resource ON votes(user_email, resource_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_type_item ON bookmarks(user_email, type, item_id);

## 7) Compatibility and rollout

- Flutter client is already bulk-first and will call POST /api/resources/state.
- If backend returns 404, 405, 406, 415, or 501, client automatically falls back to legacy prefetch path.
- Recommended rollout:
  1. Deploy endpoint.
  2. Hit endpoint with one internal user and verify states shape.
  3. Confirm client logs no compatibility fallback for active sessions.

## 8) Backend test cases

1. Empty list input returns states: []
2. Unknown resource IDs still return defaults when included in input
3. Mixed set with bookmarked/unbookmarked resources returns correct boolean
4. Mixed vote data returns correct userVote and aggregate counts
5. Unauthorized request returns 401
6. Large input is deduped and capped to 200 IDs
