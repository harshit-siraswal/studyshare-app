import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import 'backend_api_service.dart';
import 'supabase_service.dart';

class SubscriptionService {
  final BackendApiService _api = BackendApiService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final SupabaseService _supabaseService = SupabaseService();
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  late Razorpay _razorpay;
  Completer<bool>? _paymentCompleter;
  String _pendingPurchaseType = 'premium';
  String? _pendingPlanId;
  static const Duration _premiumStatusCacheTtl = Duration(seconds: 45);
  static String? _cachedPremiumEmail;
  static bool? _cachedPremiumStatus;
  static DateTime? _cachedPremiumStatusAt;

  SubscriptionService() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  Future<void> _clearPremiumCache(SharedPreferences prefs) async {
    await prefs.remove('premium_until');
    await prefs.remove('premium_tier');
    await prefs.remove('premium_email');
    _cachedPremiumEmail = null;
    _cachedPremiumStatus = null;
    _cachedPremiumStatusAt = null;
  }

  bool _hasFreshPremiumCache(String email) {
    final cachedAt = _cachedPremiumStatusAt;
    if (cachedAt == null) return false;
    if (_cachedPremiumEmail != email) return false;
    return DateTime.now().difference(cachedAt) < _premiumStatusCacheTtl;
  }

  void _cachePremiumStatus(String email, bool isPremium) {
    _cachedPremiumEmail = email;
    _cachedPremiumStatus = isPremium;
    _cachedPremiumStatusAt = DateTime.now();
  }

  void dispose() {
    _razorpay.clear();
  }

  String _resolveRazorpayKey(Map<String, dynamic> orderData) {
    final keyFromOrder = (orderData['key_id'] ?? orderData['key'])?.toString();
    final normalizedOrderKey = keyFromOrder?.trim() ?? '';
    if (normalizedOrderKey.isNotEmpty) {
      return normalizedOrderKey;
    }
    return AppConfig.razorpayKeyId.trim();
  }

  bool _isValidRazorpayKey(String key) {
    return key.isNotEmpty &&
        (key.startsWith('rzp_live_') || key.startsWith('rzp_test_'));
  }

  /// Checks if the user is currently premium
  Future<bool> isPremium() async {
    final email = _firebaseAuth.currentUser?.email;
    if (email == null) return false;
    final normalizedEmail = email.trim().toLowerCase();

    // 1. Check local cache first for immediate responsiveness
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString('premium_email');
    if (cachedEmail != email) {
      await _clearPremiumCache(prefs);
    }
    if (_hasFreshPremiumCache(normalizedEmail) && _cachedPremiumStatus != null) {
      return _cachedPremiumStatus!;
    }
    final localPremiumUntilStr = prefs.getString('premium_until');

    if (localPremiumUntilStr != null) {
      try {
        final localUntil = DateTime.parse(localPremiumUntilStr);
        final localUntilUtc = localUntil.isUtc
            ? localUntil
            : localUntil.toUtc();
        if (localUntilUtc.isAfter(DateTime.now().toUtc())) {
          _cachePremiumStatus(normalizedEmail, true);
          return true;
        }
      } catch (e) {
        debugPrint('Failed to parse cached premium_until: $e');
        // Fall through to Supabase check
      }
    }

    // 2. Fallback to Supabase (Source of Truth)
    final isPremium = await _checkPremiumStatus();
    _cachePremiumStatus(normalizedEmail, isPremium);
    return isPremium;
  }

  Future<bool> _checkPremiumStatus() async {
    try {
      // Use Firebase Auth email instead of Supabase Auth user ID
      final email = _firebaseAuth.currentUser?.email;
      if (email == null) return false;

      final res = await _supabase
          .from('users')
          .select('subscription_end_date, subscription_tier')
          .eq('email', email)
          .maybeSingle();

      bool isPaidPremium = false;
      String? paidTier;
      String? premiumUntilStr;

      if (res != null) {
        premiumUntilStr = res['subscription_end_date'];
        paidTier = res['subscription_tier'] as String?;
        if (premiumUntilStr != null) {
          final premiumUntil = DateTime.parse(premiumUntilStr);
          final now = DateTime.now();
          final premiumUntilUtc = premiumUntil.isUtc
              ? premiumUntil
              : premiumUntil.toUtc();
          final nowUtc = now.isUtc ? now : now.toUtc();
          isPaidPremium = premiumUntilUtc.isAfter(nowUtc);
        }
      }

      // Auto-unlock Premium for active contributors (>= 10 approved uploads)
      if (!isPaidPremium) {
        try {
          final response = await _supabase
              .from('resources')
              .select('id')
              .eq('uploaded_by_email', email)
              .eq('status', 'approved')
              .count(CountOption.exact);

          final uploadCount = response.count;

          if (uploadCount >= 10) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('premium_email', email);
            await prefs.setString('premium_tier', 'pro');
            await prefs.setString(
              'premium_until',
              DateTime.now()
                  .add(const Duration(days: 30))
                  .toUtc()
                  .toIso8601String(),
            );
            _cachePremiumStatus(email.trim().toLowerCase(), true);
            return true;
          }
        } catch (e) {
          debugPrint('Failed to check upload count for auto-premium: $e');
        }
        _cachePremiumStatus(email.trim().toLowerCase(), false);
        return false;
      }

      // Sync tier to local cache
      final prefs = await SharedPreferences.getInstance();
      if (paidTier != null) {
        await prefs.setString('premium_tier', paidTier);
      }
      await prefs.setString('premium_email', email);

      // Sync expiry to local cache
      await prefs.setString('premium_until', premiumUntilStr!);
      _cachePremiumStatus(email.trim().toLowerCase(), true);

      return true;
    } catch (e) {
      debugPrint('Check Premium Critical Error: $e');
      final email = _firebaseAuth.currentUser?.email?.trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        _cachePremiumStatus(email, false);
      }
      return false;
    }
  }

  /// Checks if the user is on the Max (Tier 2) plan
  Future<bool> isTier2() async {
    // Ensure we have latest data
    final isPrem = await isPremium();
    if (!isPrem) return false;

    // Check local cache
    final prefs = await SharedPreferences.getInstance();
    final tier = prefs.getString('premium_tier');

    return tier == 'max';
  }

  /// Starts the payment flow
  /// [planId]: 'monthly' (₹49) or 'quarterly' (₹149)
  Future<bool> buyPremium(
    BuildContext context,
    String email,
    String phone, {
    required String planId,
  }) async {
    if (_paymentCompleter != null && !_paymentCompleter!.isCompleted) {
      debugPrint('Payment already in progress');
      return _paymentCompleter!.future;
    }

    _paymentCompleter = Completer<bool>();
    _pendingPurchaseType = 'premium';
    _pendingPlanId = planId;

    // Explicit Amount Logic
    int amount;
    String description;

    if (planId == 'quarterly') {
      amount = 14900; // ₹149.00
      description = '3 Months Subscription';
    } else {
      amount = 4900; // ₹49.00
      description = 'Monthly Subscription';
    }

    debugPrint('Initiating Payment: Plan=$planId, Amount=$amount');

    try {
      // 2. Create Order on Backend
      final orderData = await _api.createPaymentOrder(
        purchaseType: 'premium',
        planId: planId,
        amount: amount,
        context: context.mounted ? context : null,
      );

      if (orderData['error'] != null) {
        throw Exception(orderData['error']);
      }

      final orderId = orderData['id'];

      final authorizedAmount = orderData['amount'] ?? amount;

      if (authorizedAmount != amount) {
        debugPrint(
          'ERROR: Backend returned different amount: $authorizedAmount vs expected $amount',
        );
        throw Exception('Price mismatch. Please try again or contact support.');
      }

      final razorpayKey = _resolveRazorpayKey(orderData);
      if (!_isValidRazorpayKey(razorpayKey)) {
        throw Exception(
          'Razorpay key is missing or invalid. Configure backend key_id or RAZORPAY_KEY_ID.',
        );
      }

      // 3. Open Checkout
      var options = {
        'key': razorpayKey,
        'amount': authorizedAmount,
        'name': 'StudyShare Premium',
        'description': description,
        'order_id': orderId,
        'prefill': {'contact': phone, 'email': email},
        'external': {
          'wallets': ['paytm'],
        },
      };

      _razorpay.open(options);
      return _paymentCompleter!.future;
    } catch (e) {
      debugPrint('Payment Init Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initiate payment: $e')),
        );
      }
      _resetPaymentState();
      _paymentCompleter?.complete(false);
      return false;
    }
  }

  Future<bool> buyAiTokenRecharge(
    BuildContext context,
    String email,
    String phone, {
    required int rechargeRupees,
  }) async {
    if (_paymentCompleter != null && !_paymentCompleter!.isCompleted) {
      debugPrint('Payment already in progress');
      return _paymentCompleter!.future;
    }

    if (rechargeRupees <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid recharge amount.')),
        );
      }
      return false;
    }

    _paymentCompleter = Completer<bool>();
    _pendingPurchaseType = 'ai_token_recharge';
    _pendingPlanId = null;

    final amount = rechargeRupees * 100;
    final description = 'AI Tokens Recharge';

    try {
      final orderData = await _api.createPaymentOrder(
        purchaseType: 'ai_token_recharge',
        rechargeRupees: rechargeRupees,
        amount: amount,
        context: context.mounted ? context : null,
      );

      if (orderData['error'] != null) {
        throw Exception(orderData['error']);
      }

      final orderId = orderData['id'];
      final authorizedAmount = orderData['amount'] ?? amount;

      if (authorizedAmount != amount) {
        throw Exception('Price mismatch. Please try again or contact support.');
      }

      final razorpayKey = _resolveRazorpayKey(orderData);
      if (!_isValidRazorpayKey(razorpayKey)) {
        throw Exception(
          'Razorpay key is missing or invalid. Configure backend key_id or RAZORPAY_KEY_ID.',
        );
      }

      final options = {
        'key': razorpayKey,
        'amount': authorizedAmount,
        'name': 'StudyShare AI Tokens',
        'description': '$description (\u20b9$rechargeRupees)',
        'order_id': orderId,
        'prefill': {'contact': phone, 'email': email},
        'external': {
          'wallets': ['paytm'],
        },
      };

      _razorpay.open(options);
      return _paymentCompleter!.future;
    } catch (e) {
      debugPrint('AI Recharge Init Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initiate AI token recharge: $e')),
        );
      }
      _resetPaymentState();
      _paymentCompleter?.complete(false);
      return false;
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (response.orderId == null ||
        response.paymentId == null ||
        response.signature == null) {
      debugPrint('Payment response missing required fields');
      _resetPaymentState();
      _paymentCompleter?.complete(false);
      return;
    }

    try {
      debugPrint('Payment Success Callback: ${response.paymentId}');

      // 4. Verify on Backend
      final result = await _api.verifyPayment(
        orderId: response.orderId!,
        paymentId: response.paymentId!,
        signature: response.signature!,
      );

      final purchaseType =
          (result['purchase_type']?.toString() ?? _pendingPurchaseType)
              .trim()
              .toLowerCase();

      if (purchaseType == 'ai_token_recharge') {
        _supabaseService.markAiTokenBalanceStale();
        _resetPaymentState();
        _paymentCompleter?.complete(true);
        return;
      }

      // 5. Update Local Cache IMMEDIATELY from intent (Optimistic Update)
      // Executed ONLY after successful verification as requested.

      final prefs = await SharedPreferences.getInstance();

      // Set Plan
      String newTier = 'pro';
      final planFromResponse =
          result['plan_id']?.toString() ?? result['plan']?.toString();
      if (_pendingPlanId != null) {
        newTier = (_pendingPlanId == 'quarterly' || _pendingPlanId == 'max')
            ? 'max'
            : 'pro';
      } else if (planFromResponse != null) {
        newTier = (planFromResponse == 'quarterly' || planFromResponse == 'max')
            ? 'max'
            : 'pro';
      }
      await prefs.setString('premium_tier', newTier);

      final email = _firebaseAuth.currentUser?.email;
      if (email != null) {
        await prefs.setString('premium_email', email);
      }

      // Calculate new expiry date locally to allow immediate access
      final now = DateTime.now().toUtc();
      final newExpiry = (newTier == 'max')
          ? now.add(const Duration(days: 90))
          : now.add(const Duration(days: 30));

      await prefs.setString('premium_until', newExpiry.toIso8601String());
      debugPrint('Success: Subscription activated locally until $newExpiry');
      _supabaseService.markAiTokenBalanceStale();

      _resetPaymentState();
      _paymentCompleter?.complete(true);
    } catch (e) {
      debugPrint('Payment Verify Error: $e');
      // If verification fails, we do NOT apply optimistic updates.
      // We ensure the state is reset and return false.
      _resetPaymentState();
      _paymentCompleter?.complete(false);
    }
  }

  void _resetPaymentState() {
    _pendingPurchaseType = 'premium';
    _pendingPlanId = null;
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('Payment Error: ${response.code} - ${response.message}');
    _resetPaymentState();
    _paymentCompleter?.complete(false);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('External Wallet: ${response.walletName}');
    _resetPaymentState();
    _paymentCompleter?.complete(false);
  }
}
