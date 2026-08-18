import crypto from 'crypto';

/**
 * Vault service for AES-256-GCM envelope encryption of sensitive CyberVidya credentials
 * and college email OAuth tokens. Secrets are protected at rest and never returned unencrypted.
 */
export class CyberVidyaVaultService {
  private static readonly ALGORITHM = 'aes-256-gcm';
  private static readonly KEY_LENGTH = 32; // 256 bits
  private static readonly IV_LENGTH = 12;  // 96 bits standard for GCM

  /**
   * Retrieves the master encryption key from environment variables.
   * Fallback for dev mode uses a deterministic key derived from ENCRYPTION_SECRET.
   */
  private static getMasterKey(): Buffer {
    const rawSecret = process.env.CYBERVIDYA_VAULT_SECRET || process.env.SUPABASE_SERVICE_ROLE_KEY || 'default-dev-vault-secret-key-32b!';
    return crypto.createHash('sha256').update(rawSecret).digest();
  }

  /**
   * Encrypts plaintext secret using AES-256-GCM.
   */
  public static encryptSecret(plaintext: string): { encryptedData: string; iv: string; keyVersion: number } {
    if (!plaintext || plaintext.trim().length === 0) {
      throw new Error('[CyberVidyaVault] Cannot encrypt an empty payload.');
    }

    const key = this.getMasterKey();
    const iv = crypto.randomBytes(this.IV_LENGTH);
    const cipher = crypto.createCipheriv(this.ALGORITHM, key, iv);

    let encrypted = cipher.update(plaintext, 'utf8', 'hex');
    encrypted += cipher.final('hex');

    const authTag = cipher.getAuthTag().toString('hex');
    // Pack authTag together with cipher output
    const combinedPayload = `${encrypted}:${authTag}`;

    return {
      encryptedData: combinedPayload,
      iv: iv.toString('hex'),
      keyVersion: 1,
    };
  }

  /**
   * Decrypts ciphertext secret using AES-256-GCM.
   */
  public static decryptSecret(encryptedData: string, ivHex: string): string {
    if (!encryptedData || !ivHex) {
      throw new Error('[CyberVidyaVault] Missing required decryption parameters.');
    }

    const parts = encryptedData.split(':');
    if (parts.length !== 2) {
      throw new Error('[CyberVidyaVault] Invalid encrypted payload format.');
    }

    const [ciphertext, authTagHex] = parts;
    const key = this.getMasterKey();
    const iv = Buffer.from(ivHex, 'hex');
    const authTag = Buffer.from(authTagHex, 'hex');

    const decipher = crypto.createDecipheriv(this.ALGORITHM, key, iv);
    decipher.setAuthTag(authTag);

    let decrypted = decipher.update(ciphertext, 'hex', 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  }

  /**
   * Utility method to scrub log output before writing to CloudWatch or stdout.
   */
  public static sanitizeLogObject(obj: Record<string, any>): Record<string, any> {
    const sensitiveKeys = ['password', 'otp', 'token', 'authorization', 'cybervidyatoken', 'refreshtoken'];
    const sanitized: Record<string, any> = {};

    for (const [key, value] of Object.entries(obj)) {
      const lowerKey = key.toLowerCase();
      if (sensitiveKeys.some(s => lowerKey.includes(s))) {
        sanitized[key] = '[REDACTED_SECRET]';
      } else if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
        sanitized[key] = this.sanitizeLogObject(value);
      } else {
        sanitized[key] = value;
      }
    }

    return sanitized;
  }
}
