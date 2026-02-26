import 'package:flutter_application_1/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  try {
    final supabase = SupabaseService().client;
    final res = await supabase.from('notifications').select().limit(1);
    print("NOTIFICATIONS TABLE EXISTS: $res");
  } catch(e) {
    print("ERROR notifications: $e");
  }

  try {
    final supabase = SupabaseService().client;
    final res = await supabase.from('follow_requests').select().limit(1);
    print("FOLLOW REQUESTS TABLE EXISTS: $res");
  } catch(e) {
    print("ERROR follow_requests: $e");
  }
}
