import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import 'success_overlay.dart';

class PaywallDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  
  const PaywallDialog({super.key, required this.onSuccess});

  @override
  State<PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<PaywallDialog> {
  final SubscriptionService _subService = SubscriptionService();
  final AuthService _auth = AuthService();
  bool _isLoading = false;
  String _selectedPlan = 'quarterly'; // monthly, quarterly

  Future<void> _startPayment() async {
    final email = _auth.userEmail;
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to continue.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    
    // Use user's phone if available, else usage existing placeholder
    final phone = _auth.currentUser?.phoneNumber ?? '9999999999';
    
    // In a real app we'd pass the amount based on plan
    final result = await _subService.buyPremium(context, email, phone, planId: _selectedPlan);

    if (mounted) {
      setState(() => _isLoading = false);
      if (result) {
        Navigator.pop(context); // Close paywall
        
        // Use a builder to ensure context is valid if dialog needs it
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => SuccessOverlay(
               message: 'Premium Activated! Welcome to the club.',
               onDismiss: () {
                 Navigator.pop(context); 
                 widget.onSuccess();
               },
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment failed. Please try again or contact support.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _restorePurchase() async {
     setState(() => _isLoading = true);
     // Simulate restore
     await Future.delayed(const Duration(seconds: 2));
     if (mounted) {
       setState(() => _isLoading = false);
       Navigator.pop(context);
       widget.onSuccess();
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Purchases restored successfully')),
       );
     }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final orangeColor = const Color(0xFFFF5722); // Gentler Streak Orange
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                   const Spacer(),
                   IconButton(
                     onPressed: () => Navigator.pop(context),
                     icon: const Icon(Icons.close_rounded, color: Colors.grey),
                     padding: EdgeInsets.zero,
                     constraints: const BoxConstraints(),
                   ),
                ],
              ),
              
              Text(
                'StudySpace Premium',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Streak, Unlimited Downloads, Offline Access, Insights, Profile Customization.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              
              // Monthly Plan
              _buildPlanCard(
                id: 'monthly',
                title: 'Monthly',
                price: '₹49/month',
                subtitle: 'Offline PDFs + 1-Year Rooms',
                orangeColor: orangeColor,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              
              // Quarterly Plan (Highlighted)
              _buildPlanCard(
                id: 'quarterly',
                title: 'Quarterly',
                price: '₹149',
                subtitle: '3 Months Access, All Premium Features',
                badgeText: 'BEST VALUE',
                isHighlighted: true,
                orangeColor: orangeColor,
                isDark: isDark,
              ),
              
              const SizedBox(height: 32),
              
              Center(
                 child: TextButton(
                   onPressed: _restorePurchase,
                   child: Text(
                     'Restore Purchase',
                     style: GoogleFonts.inter(
                       fontSize: 14,
                       fontWeight: FontWeight.w600,
                       color: Colors.grey,
                     ),
                   ),
                 ),
              ),
              const SizedBox(height: 20),
              
              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _startPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: orangeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                      ? const SizedBox(
                          width: 24, 
                          height: 24, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Continue',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            if (_selectedPlan == 'monthly')
                              Text(
                                'Cancel Anytime',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                              ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Back Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String id,
    required String title,
    required String price,
    String? subtitle,
    String? badgeText,
    bool isHighlighted = false,
    required Color orangeColor,
    required bool isDark,
  }) {
    final isSelected = _selectedPlan == id;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = id),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
        width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: isSelected && isHighlighted 
                  ? const Color(0xFFFFF7ED) // Light orange bg for highlighted
                  : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? orangeColor : (isDark ? Colors.white10 : Colors.grey.shade200),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                 if (!isDark)
                   BoxShadow(
                     color: Colors.black.withValues(alpha: 0.03),
                     blurRadius: 10,
                     offset: const Offset(0, 4),
                   ),
              ],
            ),
            child: Row(
              children: [
                // Radio Circle
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? orangeColor : Colors.transparent,
                    border: Border.all(
                       color: isSelected ? orangeColor : Colors.grey.shade400,
                       width: 2,
                    ),
                  ),
                  child: isSelected 
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 16),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Price
                Text(
                  price,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
          
          if (badgeText != null)
            Positioned(
              top: -12,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: orangeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
