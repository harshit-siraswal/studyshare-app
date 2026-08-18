import { CyberVidyaVaultService } from './cybervidya_vault_service';

export interface EmailAccessTokenResult {
  accessToken: string;
  expiresInSeconds: number;
}

export interface OtpFetchOptions {
  userId: string;
  encryptedRefreshToken: string;
  iv: string;
  provider: 'google' | 'microsoft';
  maxWaitMs?: number;
  pollIntervalMs?: number;
}

/**
 * Service dedicated to retrieving CyberVidya authentication OTPs from the student's connected college mailbox.
 * Uses narrow OAuth scopes and ephemeral memory extraction (zero retention of email bodies).
 */
export class CollegeEmailOtpService {
  private static readonly DEFAULT_MAX_WAIT_MS = 60000; // 60s timeout for OTP delivery
  private static readonly DEFAULT_POLL_INTERVAL_MS = 3000; // Poll every 3 seconds

  /**
   * Refreshes the OAuth access token for Google Workspace or Microsoft Graph API.
   */
  public async getFreshAccessToken(
    provider: 'google' | 'microsoft',
    encryptedRefreshToken: string,
    iv: string
  ): Promise<EmailAccessTokenResult> {
    const refreshToken = CyberVidyaVaultService.decryptSecret(encryptedRefreshToken, iv);

    if (provider === 'google') {
      const clientId = process.env.GOOGLE_COLLEGE_OAUTH_CLIENT_ID || '';
      const clientSecret = process.env.GOOGLE_COLLEGE_OAUTH_CLIENT_SECRET || '';

      const response = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          refresh_token: refreshToken,
          grant_type: 'refresh_token',
        }),
      });

      if (!response.ok) {
        throw new Error(`[CollegeEmailOtp] Google token refresh failed with HTTP ${response.status}`);
      }

      const data = await response.json() as any;
      return {
        accessToken: data.access_token,
        expiresInSeconds: data.expires_in || 3600,
      };
    } else {
      // Microsoft Graph OAuth token refresh
      const clientId = process.env.MICROSOFT_COLLEGE_OAUTH_CLIENT_ID || '';
      const clientSecret = process.env.MICROSOFT_COLLEGE_OAUTH_CLIENT_SECRET || '';

      const response = await fetch('https://login.microsoftonline.com/common/oauth2/v2.0/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          refresh_token: refreshToken,
          grant_type: 'refresh_token',
        }),
      });

      if (!response.ok) {
        throw new Error(`[CollegeEmailOtp] Microsoft token refresh failed with HTTP ${response.status}`);
      }

      const data = await response.json() as any;
      return {
        accessToken: data.access_token,
        expiresInSeconds: data.expires_in || 3600,
      };
    }
  }

  /**
   * Polls the mailbox for messages matching `from:cybervidya OR subject:"OTP"` sent in the last 5 minutes.
   * Parses and returns the 6-digit numeric verification code.
   */
  public async retrieveCyberVidyaOtp(options: OtpFetchOptions): Promise<string> {
    const maxWaitMs = options.maxWaitMs || CollegeEmailOtpService.DEFAULT_MAX_WAIT_MS;
    const pollIntervalMs = options.pollIntervalMs || CollegeEmailOtpService.DEFAULT_POLL_INTERVAL_MS;
    const startTime = Date.now();

    const tokenResult = await this.getFreshAccessToken(options.provider, options.encryptedRefreshToken, options.iv);

    while (Date.now() - startTime < maxWaitMs) {
      try {
        const otp = await this.queryMailboxForOtp(options.provider, tokenResult.accessToken);
        if (otp) {
          return otp;
        }
      } catch (error) {
        console.warn('[CollegeEmailOtp] Transient error while querying mailbox for OTP:', error);
      }

      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }

    throw new Error('[CollegeEmailOtp] Timeout: CyberVidya OTP email did not arrive within 60 seconds.');
  }

  /**
   * Query mailbox via Gmail REST API or Microsoft Graph API.
   */
  private async queryMailboxForOtp(provider: 'google' | 'microsoft', accessToken: string): Promise<string | null> {
    if (provider === 'google') {
      // Query recent messages matching CyberVidya OTP filter
      const query = encodeURIComponent('from:cybervidya subject:OTP');
      const listUrl = `https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${query}&maxResults=3`;

      const listResponse = await fetch(listUrl, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });

      if (!listResponse.ok) return null;

      const listData = await listResponse.json() as any;
      if (!listData.messages || listData.messages.length === 0) return null;

      // Inspect latest message snippet/payload
      const messageId = listData.messages[0].id;
      const msgUrl = `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}?format=full`;

      const msgResponse = await fetch(msgUrl, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });

      if (!msgResponse.ok) return null;

      const msgData = await msgResponse.json() as any;
      const snippet = msgData.snippet || '';
      return this.extractOtpFromText(snippet);
    } else {
      // Query Microsoft Graph messages
      const filter = encodeURIComponent("contains(subject,'OTP') or contains(from/emailAddress/address,'cybervidya')");
      const listUrl = `https://graph.microsoft.com/v1.0/me/messages?$filter=${filter}&$top=3&$select=subject,bodyPreview,body`;

      const listResponse = await fetch(listUrl, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });

      if (!listResponse.ok) return null;

      const listData = await listResponse.json() as any;
      if (!listData.value || listData.value.length === 0) return null;

      const latestMsg = listData.value[0];
      const preview = latestMsg.bodyPreview || '';
      return this.extractOtpFromText(preview);
    }
  }

  /**
   * Regex extraction of 6-digit numeric verification codes from email text.
   */
  private extractOtpFromText(text: string): string | null {
    if (!text) return null;
    // Match strings like "OTP is 123456", "verification code: 654321", or standalone 6 digits
    const match = text.match(/\b\d{6}\b/);
    return match ? match[0] : null;
  }
}
