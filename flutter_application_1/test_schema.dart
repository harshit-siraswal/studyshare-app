import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/config/app_config.dart';

void main() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  final supabase = Supabase.instance.client;

  try {
    final res = await supabase.from('notifications').select().limit(1);
    debugPrint("NOTIFICATIONS TABLE EXISTS: $res");
  } on Exception catch(e) {
    debugPrint("ERROR notifications: $e");
  }

  try {
    final res = await supabase.from('follow_requests').select().limit(1);
    debugPrint("FOLLOW REQUESTS TABLE EXISTS: $res");
  } on Exception catch(e) {
    debugPrint("ERROR follow_requests: $e");
  }
}
