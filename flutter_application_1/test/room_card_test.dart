import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/widgets/room_card.dart';

void main() {
  testWidgets('RoomCard tolerates non-list tags and non-string values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 220,
            child: RoomCard(
              room: <String, dynamic>{
                'id': 'room-1',
                'name': 123,
                'description': null,
                'tags': '#alpha, #beta',
                'member_count': '7',
              },
              userEmail: 'user@example.edu',
              collegeDomain: 'example.edu',
            ),
          ),
        ),
      ),
    );

    expect(find.text('123'), findsOneWidget);
    expect(find.text('#alpha'), findsOneWidget);
    expect(find.text('#beta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
