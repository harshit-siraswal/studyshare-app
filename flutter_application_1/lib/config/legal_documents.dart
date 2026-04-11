/// Centralized legal copy shown inside app settings.
class LegalDocuments {
  static const String privacyPolicyUrl =
      'https://studyshare.in/privacy-policy';
  static const String termsOfUseUrl = 'https://studyshare.in/terms-of-use';
  static const String communityGuidelinesUrl =
      'https://studyshare.in/community-guidelines';
  static const String accountDeletionUrl =
      'https://studyshare.in/account-deletion';

  static String privacyPolicy({required String supportEmail}) => '''
Last updated: April 11, 2026

StudyShare ("we", "us", "our") provides campus-focused learning services.
This Privacy Policy explains what personal data we collect, why we collect it,
and how you can control your information.

1. Data we collect
- Account data: email, display name, profile photo, and college metadata.
- Learning activity: resources viewed, downloads, interactions, and engagement.
- User-generated content: posts, comments, room messages, and uploaded files.
- Device and diagnostics: app version, crash logs, and abuse-prevention signals.
- Payment metadata: subscription or recharge status from trusted payment flows.

2. How we use data
- Provide and improve app features and moderation.
- Personalize campus-specific feeds and access control.
- Protect users, prevent abuse, and enforce platform safety.
- Process support requests and account recovery.

3. Legal basis and consent
By using StudyShare, you consent to processing required for product operation,
security, compliance, and user support.

4. Data sharing
We do not sell personal data. We may share limited data with:
- Infrastructure and analytics providers for service delivery.
- Payment processors for subscription/recharge workflows.
- Authorities when legally required or to prevent harm/fraud.

5. Data retention
We retain data only as long as needed for product operation, legal compliance,
audit obligations, and abuse prevention.

6. Security
We apply access controls, transport security, and operational safeguards.
No system is fully risk free, but we continuously improve controls.

7. Your rights
You can request account updates, export, correction, or deletion. Some data may
be retained where required for legal/security reasons.

8. Children and eligibility
StudyShare is intended for users eligible under applicable laws and campus
policy. If you believe a minor used the service in violation of policy, contact
support immediately.

9. Contact
For privacy questions or data requests, contact: $supportEmail
''';

  static String termsOfUse({required String supportEmail}) => '''
Last updated: April 11, 2026

These Terms of Use govern your use of StudyShare. By using the app, you agree
to these terms.

1. Eligibility and account responsibility
- You are responsible for account activity and credential safety.
- You must provide accurate profile and institutional information.

2. Acceptable use
You agree not to:
- Upload illegal, infringing, hateful, harassing, or harmful content.
- Abuse messaging, notices, or collaboration features.
- Attempt unauthorized access, scraping, reverse engineering, or automation
  that harms reliability.

3. User content
You retain ownership of your content, but grant StudyShare a limited license to
host, display, process, and distribute content needed to operate the service.

4. Moderation and enforcement
We may remove content, limit access, or suspend accounts to enforce safety,
compliance, and community standards.

5. Paid features
Premium and AI recharge purchases are processed through supported payment
channels. Access is granted per active entitlement state.

6. Availability and changes
We may update features, pricing, terms, and policies over time. Continued use
means acceptance of updated terms.

7. Disclaimer and limitation
Service is provided "as is" and "as available". To the extent permitted by law,
StudyShare is not liable for indirect, incidental, or consequential damages.

8. Termination
You may stop using the app anytime. We may suspend/terminate access for policy
violations, abuse, or legal obligations.

9. Contact
For legal questions, reach us at: $supportEmail
''';

  static String communityGuidelines({required String supportEmail}) => '''
Last updated: April 11, 2026

StudyShare is a campus learning network. Keep it useful and safe.

- Be respectful in rooms, comments, and direct interactions.
- Share authentic academic resources with correct categorization.
- Do not post harassment, hate speech, explicit content, or threats.
- Do not impersonate faculty/students or spread false institutional notices.
- Do not share private data without consent.
- Report abuse through support so moderators can act quickly.

Repeated or severe violations can lead to content removal, temporary limits, or
permanent suspension.

Support contact: $supportEmail
''';

  static String accountDeletionPolicy({required String supportEmail}) => '''
Last updated: April 11, 2026

You can request account deletion from app settings.

What happens after deletion request:
- Access is revoked from active sessions.
- Profile and user-generated content may be removed or anonymized.
- Some audit/security/payment records may be retained when legally required.
- Recovery may not be possible after deletion is finalized.

If your request fails in-app, contact $supportEmail with your account email and
college details for manual verification.
''';
}
