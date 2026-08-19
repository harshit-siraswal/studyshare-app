import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';
import { CyberVidyaVaultService } from '../services/cybervidya_vault_service';

// ---------------------------------------------------------------------------
// Supabase admin client (service-role key bypasses RLS — required for upsert)
// ---------------------------------------------------------------------------
function getSupabaseAdmin() {
  const supabaseUrl = process.env.SUPABASE_URL || '';
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('[AttendanceEmail] SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set.');
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

// ---------------------------------------------------------------------------
// JWT helper — extracts userId from the Firebase/Supabase Bearer token
// ---------------------------------------------------------------------------
function extractUserIdFromBearerToken(authHeader: string | undefined): string | null {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  const token = authHeader.slice(7).trim();
  if (!token) return null;

  // Decode the JWT payload without verifying (Supabase middleware already verified it).
  // The `sub` claim holds the Supabase/Firebase user UUID.
  try {
    const payloadBase64 = token.split('.')[1];
    if (!payloadBase64) return null;
    const payload = JSON.parse(Buffer.from(payloadBase64, 'base64url').toString('utf8'));
    return (payload.sub as string) || null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

/**
 * POST /api/attendance/email/connect
 *
 * 1. Validates the user's Firebase/Supabase Bearer token.
 * 2. Exchanges the Google serverAuthCode for an access + refresh token.
 * 3. Encrypts the refresh token with CyberVidyaVaultService (AES-256-GCM).
 * 4. Upserts the record into `user_college_email_tokens` (migration 061).
 */
export async function connectCollegeEmailHandler(req: any, res: any): Promise<void> {
  // --- Auth ---
  const userId = req.user?.id || req.userId || extractUserIdFromBearerToken(req.headers?.authorization);
  if (!userId) {
    res.status(401).json({ success: false, error: 'Unauthorized.' });
    return;
  }

  // --- Validate body ---
  const { emailAddress, serverAuthCode, provider = 'google' } = (req.body || {}) as {
    emailAddress?: string;
    serverAuthCode?: string;
    provider?: string;
  };

  if (!emailAddress || !emailAddress.includes('@')) {
    res.status(400).json({ success: false, error: 'Invalid emailAddress.' });
    return;
  }
  if (!['google', 'microsoft'].includes(provider)) {
    res.status(400).json({ success: false, error: 'Unsupported provider.' });
    return;
  }

  // --- Email-only mode (no serverAuthCode) ---
  if (!serverAuthCode || serverAuthCode.trim().length === 0) {
    console.warn(`[ConnectEmail] user=${userId} email-only mode (no serverAuthCode) — skipping token exchange.`);
    res.status(200).json({ success: true, emailAddress, mode: 'email_only' });
    return;
  }

  // --- Exchange serverAuthCode for refresh token ---
  let refreshToken: string;
  try {
    refreshToken = await exchangeGoogleAuthCode(serverAuthCode.trim());
  } catch (err: any) {
    console.error('[ConnectEmail] Token exchange failed:', err.message);
    res.status(502).json({
      success: false,
      error: 'Failed to exchange Google auth code. The code may have expired — please try reconnecting.',
    });
    return;
  }

  // --- Encrypt refresh token ---
  const { encryptedData, iv } = CyberVidyaVaultService.encryptSecret(refreshToken);

  // --- Persist to Supabase ---
  try {
    const supabase = getSupabaseAdmin();
    const { error } = await supabase
      .from('user_college_email_tokens')
      .upsert(
        {
          user_id: userId,
          email_address: emailAddress,
          provider,
          encrypted_refresh_token: encryptedData,
          encryption_iv: iv,
          scope: 'https://www.googleapis.com/auth/gmail.readonly',
          token_status: 'active',
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id' }
      );

    if (error) {
      console.error('[ConnectEmail] Supabase upsert error:', error.message);
      res.status(500).json({ success: false, error: 'Database error while saving token.' });
      return;
    }

    console.log(`[ConnectEmail] Stored encrypted refresh token — user=${userId} email=${emailAddress} provider=${provider}`);
    res.status(200).json({ success: true, emailAddress });
  } catch (err: any) {
    console.error('[ConnectEmail] Unexpected error:', err.message);
    res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

/**
 * DELETE /api/attendance/email/disconnect
 *
 * 1. Validates the Bearer token.
 * 2. Fetches and decrypts the stored refresh token.
 * 3. Attempts to revoke it with Google's revocation endpoint.
 * 4. Deletes the row from `user_college_email_tokens`.
 */
export async function disconnectCollegeEmailHandler(req: any, res: any): Promise<void> {
  // --- Auth ---
  const userId = req.user?.id || req.userId || extractUserIdFromBearerToken(req.headers?.authorization);
  if (!userId) {
    res.status(401).json({ success: false, error: 'Unauthorized.' });
    return;
  }

  try {
    const supabase = getSupabaseAdmin();

    // Fetch the existing token row so we can revoke it
    const { data: row, error: fetchError } = await supabase
      .from('user_college_email_tokens')
      .select('encrypted_refresh_token, encryption_iv, provider')
      .eq('user_id', userId)
      .single();

    if (fetchError && fetchError.code !== 'PGRST116') {
      // PGRST116 = row not found — that's fine, nothing to revoke
      console.error('[DisconnectEmail] Supabase fetch error:', fetchError.message);
    }

    // Best-effort token revocation (don't block deletion on failure)
    if (row?.encrypted_refresh_token && row?.encryption_iv) {
      try {
        const refreshToken = CyberVidyaVaultService.decryptSecret(
          row.encrypted_refresh_token,
          row.encryption_iv
        );
        if (row.provider === 'google') {
          await revokeGoogleToken(refreshToken);
        }
      } catch (revokeErr: any) {
        console.warn('[DisconnectEmail] Token revocation failed (continuing):', revokeErr.message);
      }
    }

    // Delete the row
    const { error: deleteError } = await supabase
      .from('user_college_email_tokens')
      .delete()
      .eq('user_id', userId);

    if (deleteError) {
      console.error('[DisconnectEmail] Supabase delete error:', deleteError.message);
      res.status(500).json({ success: false, error: 'Database error while removing token.' });
      return;
    }

    console.log(`[DisconnectEmail] Removed college email token — user=${userId}`);
    res.status(200).json({ success: true });
  } catch (err: any) {
    console.error('[DisconnectEmail] Unexpected error:', err.message);
    res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Exchanges a Google serverAuthCode (from mobile GoogleSignIn) for a refresh token.
 * Uses GOOGLE_COLLEGE_OAUTH_CLIENT_ID and GOOGLE_COLLEGE_OAUTH_CLIENT_SECRET env vars.
 * The redirect_uri must be "postmessage" for the mobile server-auth-code flow.
 */
async function exchangeGoogleAuthCode(authCode: string): Promise<string> {
  const clientId = process.env.GOOGLE_COLLEGE_OAUTH_CLIENT_ID || '';
  const clientSecret = process.env.GOOGLE_COLLEGE_OAUTH_CLIENT_SECRET || '';
  const redirectUri = process.env.GOOGLE_COLLEGE_OAUTH_REDIRECT_URI || 'postmessage';

  if (!clientId || !clientSecret) {
    throw new Error(
      'GOOGLE_COLLEGE_OAUTH_CLIENT_ID and GOOGLE_COLLEGE_OAUTH_CLIENT_SECRET must be set in environment.'
    );
  }

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code: authCode,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Google token endpoint returned HTTP ${response.status}: ${body}`);
  }

  const data = await response.json() as any;
  const refreshToken: string | undefined = data.refresh_token;

  if (!refreshToken) {
    throw new Error(
      'Google did not return a refresh_token. ' +
      'Ensure the OAuth client has "offline" access type and the user granted consent for the first time.'
    );
  }

  return refreshToken;
}

/**
 * Best-effort revocation of a Google OAuth refresh token.
 */
async function revokeGoogleToken(refreshToken: string): Promise<void> {
  await fetch(
    `https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(refreshToken)}`,
    { method: 'POST' }
  );
}
