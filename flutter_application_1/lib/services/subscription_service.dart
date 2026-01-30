import 'dart:async';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import 'backend_api_service.dart';

class SubscriptionService {
  final BackendApiService _api = BackendApiService();
  final SupabaseClient _supabase = Supabase.instance.client;
  late Razorpay _razorpay;
  Completer<bool>? _paymentCompleter;

  SubscriptionService() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void dispose() {
    _razorpay.clear();
  }

  /// Checks if the user is currently premium
  Future<bool> isPremium() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

      debugPrint('Checking premium status for user: ${user.id}');
      final res = await _supabase
          .from('premium_users')
          .select('premium_until')
          .eq('id', user.id)
          .maybeSingle(); 
      
      debugPrint('Premium check result: $res');

      if (res == null) {
        debugPrint('User has no entry in premium_users table.');
        return false;
      }
      
      final premiumUntilStr = res['premium_until'];
      if (premiumUntilStr == null) return false;

      final premiumUntil = DateTime.parse(premiumUntilStr);
      final isActive = premiumUntil.isAfter(DateTime.now());
      debugPrint('Premium until: $premiumUntil, Is active: $isActive');
      return isActive;
    } catch (e) {
      debugPrint('Error checking premium status: $e');
      return false;
    }
  }

  /// Starts the payment flow for Premium (₹49)
  Future<bool> buyPremium(String email, String phone) async {
    _paymentCompleter = Completer<bool>();
    debugPrint('Step 1: buyPremium called');

    try {
      // 1. Create Order on Backend
      debugPrint('Step 2: Creating order on backend...');
      final orderData = await _api.createPaymentOrder();
      debugPrint('Step 3: Order created: $orderData');
      
      if (orderData == null) {
         debugPrint('Step 3.1: Order data is null');
         return false;
      }

      final orderId = orderData['id']; // Razorpay Order ID
      debugPrint('Step 4: Order ID: $orderId');

      // 2. Open Checkout
      var options = {
        'key': AppConfig.razorpayKeyId,
        'amount': 4900, // in paise
        'name': 'MyStudySpace Premium',
        'description': 'Offline Downloads Subscription',
        'order_id': orderId,
        'prefill': {
          'contact': phone,
          'email': email,
        },
        'external': {
          'wallets': ['paytm']
        }
      };
      
      debugPrint('Step 5: Opening Razorpay with options: $options');
      _razorpay.open(options);
      debugPrint('Step 6: Razorpay open called');

      return _paymentCompleter!.future;
    } catch (e, stack) {
      debugPrint('Payment Init Error: $e');
      debugPrint('Stack trace: $stack');
      return false;
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      // 3. Verify on Backend (Critical for security)
      await _api.verifyPayment(
        orderId: response.orderId!,
        paymentId: response.paymentId!,
        signature: response.signature!,
      );
      
      // 4. Update Client-side State (Immediate feedback)
      // Ideally backend does this via webhook, but for now we do it here 
      // ensuring the RLS policy "Users can insert own premium status" allows it.
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final now = DateTime.now();
        final expiresAt = now.add(const Duration(days: 30)); // 30 days subscription
        
        await _supabase.from('premium_users').upsert({
          'id': user.id,
          'email': user.email,
          'plan_type': 'monthly',
          'premium_until': expiresAt.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }

      _paymentCompleter?.complete(true);
    } catch (e) {
      debugPrint('Payment Verify/Update Error: $e');
      // Even if update fails, we might want to return true if payment was verified? 
      // But for now, let's play safe and fail if we can't record it.
      _paymentCompleter?.complete(false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('Payment Error: ${response.code} - ${response.message}');
    _paymentCompleter?.complete(false);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('External Wallet: ${response.walletName}');
    // Usually treated as success pending verification, strictly we should probably fail or wait
    // For standard flow, we might not need this if not using external wallets extensively
    _paymentCompleter?.complete(false); 
  }
}
