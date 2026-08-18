import { CyberVidyaAuthClient } from '../services/cybervidya_auth_client';

export interface SyncJobPayload {
  userId: string;
  collegeId: string;
  registrationNumber: string;
  encryptedPassword: string;
  passwordIv: string;
  encryptedRefreshToken: string;
  emailIv: string;
  emailProvider: 'google' | 'microsoft';
  syncType: 'manual' | 'scheduled_background' | 'initial_setup';
}

export interface SyncJobResult {
  userId: string;
  success: boolean;
  cybervidyaToken?: string;
  errorCode?: string;
  durationMs: number;
}

/**
 * Background worker queue manager for attendance synchronization.
 * Controls concurrency, applies per-user idempotency locks, and logs audit trails.
 */
export class AttendanceSyncQueueWorker {
  private readonly authClient: CyberVidyaAuthClient;
  private readonly activeLocks: Set<string> = new Set();
  private static readonly MAX_TENANT_CONCURRENCY = 5;

  constructor() {
    this.authClient = new CyberVidyaAuthClient();
  }

  /**
   * Processes an incoming synchronization job with idempotency locking and jitter delay.
   */
  public async processSyncJob(payload: SyncJobPayload): Promise<SyncJobResult> {
    const startTime = Date.now();
    const lockKey = `sync:lock:${payload.userId}`;

    // 1. Idempotency Lock Check
    if (this.activeLocks.has(lockKey)) {
      console.log(`[SyncQueueWorker] Skipping job for user ${payload.userId} — sync already in progress.`);
      return {
        userId: payload.userId,
        success: false,
        errorCode: 'sync_already_in_progress',
        durationMs: Date.now() - startTime,
      };
    }

    this.activeLocks.add(lockKey);

    try {
      // 2. Add randomized jitter for background scheduled jobs (0 to 1500ms in dev/staging)
      if (payload.syncType === 'scheduled_background') {
        const jitterMs = Math.floor(Math.random() * 1500);
        await new Promise((resolve) => setTimeout(resolve, jitterMs));
      }

      // 3. Authenticate with CyberVidya & Retrieve Session Token
      const authResult = await this.authClient.authenticateStudent({
        userId: payload.userId,
        collegeId: payload.collegeId,
        registrationNumber: payload.registrationNumber,
        encryptedPassword: payload.encryptedPassword,
        passwordIv: payload.passwordIv,
        encryptedRefreshToken: payload.encryptedRefreshToken,
        emailIv: payload.emailIv,
        emailProvider: payload.emailProvider,
      });

      const durationMs = Date.now() - startTime;

      if (!authResult.success) {
        console.warn(`[SyncQueueWorker] Sync failed for user ${payload.userId}: ${authResult.errorMessage}`);
        await this.recordAuditLog({
          userId: payload.userId,
          collegeId: payload.collegeId,
          syncType: payload.syncType,
          status: 'failed',
          errorCode: authResult.errorCode,
          durationMs,
        });

        return {
          userId: payload.userId,
          success: false,
          errorCode: authResult.errorCode,
          durationMs,
        };
      }

      // 4. Record Successful Sync Audit Log
      await this.recordAuditLog({
        userId: payload.userId,
        collegeId: payload.collegeId,
        syncType: payload.syncType,
        status: 'success',
        durationMs,
      });

      return {
        userId: payload.userId,
        success: true,
        cybervidyaToken: authResult.cybervidyaToken,
        durationMs,
      };

    } finally {
      this.activeLocks.delete(lockKey);
    }
  }

  /**
   * Records execution audit record in database log table.
   */
  private async recordAuditLog(log: {
    userId: string;
    collegeId: string;
    syncType: string;
    status: string;
    errorCode?: string;
    durationMs: number;
  }): Promise<void> {
    try {
      // Simulated DB insertion (or call to Supabase / PG client)
      console.log(`[SyncAuditLog] user=${log.userId} status=${log.status} duration=${log.durationMs}ms error=${log.errorCode || 'none'}`);
    } catch (err) {
      console.error('[SyncQueueWorker] Failed to write audit log:', err);
    }
  }
}
