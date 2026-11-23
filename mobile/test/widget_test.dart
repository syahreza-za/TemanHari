import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temanhari/features/chat/widgets/mood_checkin_bar.dart';
import 'package:temanhari/features/today/widgets/agenda_card.dart';
import 'package:temanhari/models/agenda_item.dart';

void main() {
  testWidgets('MoodCheckinBar renders mood chips and invokes callback',
      (WidgetTester tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoodCheckinBar(
            selectedMood: null,
            onMoodSelected: (mood) => picked = mood.key,
          ),
        ),
      ),
    );

    expect(find.text('Gimana perasaanmu saat ini?'), findsOneWidget);
    await tester.tap(find.text('😊 Senang'));
    await tester.pump();
    expect(picked, 'senang');
  });

  testWidgets('AgendaCard displays source badge and schedule conflict warning',
      (WidgetTester tester) async {
    final conflictEvent = UnifiedAgendaItem(
      id: 'ev-outlook-1',
      kind: 'event',
      source: 'microsoft',
      sourceBadge: 'Microsoft Outlook',
      title: '1-on-1 Check-in dengan Lead',
      location: 'Microsoft Teams',
      startAt: DateTime(2026, 11, 23, 14, 0),
      endAt: DateTime(2026, 11, 23, 15, 0),
      hasConflict: true,
      conflictWithIds: const ['ev-google-1'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaCard(item: conflictEvent),
        ),
      ),
    );

    expect(find.text('Microsoft Outlook'), findsOneWidget);
    expect(find.text('Bentrok Jadwal'), findsOneWidget);
    expect(find.text('1-on-1 Check-in dengan Lead'), findsOneWidget);
  });
}
