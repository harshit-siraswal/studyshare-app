import { CyberVidyaVaultService } from './cybervidya_vault_service';
import { CollegeEmailOtpService } from './college_email_otp_service';

export interface CyberVidyaAuthResult {
  success: boolean;
  cybervidyaToken?: string;
  statusCode?: number;
  errorCode?: 'invalid_credentials' | 'otp_timeout' | 'captcha_required' | 'rate_limited' | 'server_error';
  errorMessage?: string;
}

export interface CyberVidyaClientConfig {
  baseUrl?: string;
  tenantDomain?: string;
  maxRetries?: number;
}

/**
 * Isolated backend client for authenticating with CyberVidya ERP servers.
 * Executes credential submission, OTP retrieval from college mailbox, and session token capture.
 */
export class CyberVidyaAuthClient {
  private readonly baseUrl: string;
  private readonly otpService: CollegeEmailOtpService;

  constructor(config?: CyberVidyaClientConfig) {
    this.baseUrl = config?.baseUrl || 'https://kiet.cybervidya.net';
    this.otpService = new CollegeEmailOtpService();
  }

  /**
   * Authenticates student with CyberVidya using encrypted credentials and college email OAuth tokens.
   */
  public async authenticateStudent(params: {
    userId: string;
    collegeId: string;
    registrationNumber: string;
    encryptedPassword: string;
    passwordIv: string;
    encryptedRefreshToken: string;
    emailIv: string;
    emailProvider: 'google' | 'microsoft';
  }): Promise<CyberVidyaAuthResult> {
    const password = CyberVidyaVaultService.decryptSecret(params.encryptedPassword, params.passwordIv);

    try {
      // Step 1: Submit Username & Password to CyberVidya ERP
      const initResponse = await this.executeWithRetry(async () => {
        return fetch(`${this.baseUrl}/api/v1/auth/student-login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            username: params.registrationNumber,
            password: password,
          }),
        });
      });

      if (!initResponse.ok) {
        if (initResponse.status === 401 || initResponse.status === 403) {
          return {
            success: false,
            errorCode: 'invalid_credentials',
            errorMessage: 'CyberVidya rejected the registration number or password.',
          };
        }
        if (initResponse.status === 429) {
          return {
            success: false,
            errorCode: 'rate_limited',
            errorMessage: 'CyberVidya rate limit exceeded. Retrying later.',
          };
        }
        // Check if reCAPTCHA is required
        const bodyText = await initResponse.text();
        if (bodyText.toLowerCase().includes('captcha') || bodyText.toLowerCase().includes('recaptcha')) {
          return {
            success: false,
            errorCode: 'captcha_required',
            errorMessage: 'CyberVidya requested interactive reCAPTCHA verification.',
          };
        }
      }

      const initData = await initResponse.json() as any;
      const sessionId = initData.sessionId || initData.txnId;

      // Step 2: Retrieve OTP automatically from connected college mailbox
      let otpCode: string;
      try {
        otpCode = await this.otpService.retrieveCyberVidyaOtp({
          userId: params.userId,
          encryptedRefreshToken: params.encryptedRefreshToken,
          iv: params.emailIv,
          provider: params.emailProvider,
          maxWaitMs: 45000,
        });
      } catch (error) {
        return {
          success: false,
          errorCode: 'otp_timeout',
          errorMessage: 'Failed to retrieve OTP from college email within timeout period.',
        };
      }

      // Step 3: Submit OTP to finalize CyberVidya authentication
      const verifyResponse = await fetch(`${this.baseUrl}/api/v1/auth/verify-otp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sessionId: sessionId,
          otp: otpCode,
          username: params.registrationNumber,
        }),
      });

      if (!verifyResponse.ok) {
        return {
          success: false,
          errorCode: 'otp_timeout',
          errorMessage: 'CyberVidya rejected the submitted OTP code.',
        };
      }

      const verifyData = await verifyResponse.json() as any;
      const cybervidyaToken = verifyData.token || verifyData.authenticationtoken;

      if (!cybervidyaToken || cybervidyaToken.length < 8) {
        return {
          success: false,
          errorCode: 'server_error',
          errorMessage: 'CyberVidya did not return a valid session token.',
        };
      }

      return {
        success: true,
        cybervidyaToken: cybervidyaToken,
      };

    } catch (error: any) {
      console.error('[CyberVidyaAuthClient] Unexpected authentication exception:', error);
      return {
        success: false,
        errorCode: 'server_error',
        errorMessage: error.message || 'Network or internal server exception during authentication.',
      };
    }
  }

  /**
   * Helper executing fetch with exponential backoff and randomized jitter.
   */
  private async executeWithRetry(fn: () => Promise<Response>, maxAttempts: number = 3): Promise<Response> {
    let attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        const res = await fn();
        if (res.status !== 429 && res.status < 500) {
          return res;
        }
        if (attempt === maxAttempts) return res;
      } catch (err) {
        if (attempt === maxAttempts) throw err;
      }

      // Exponential backoff with jitter: 500ms * 2^(attempt-1) + jitter(0-250ms)
      const baseDelay = 500 * Math.pow(2, attempt - 1);
      const jitter = Math.floor(Math.random() * 250);
      await new Promise((resolve) => setTimeout(resolve, baseDelay + jitter));
    }
    throw new Error('[CyberVidyaAuthClient] Max retry attempts reached.');
  }
}
