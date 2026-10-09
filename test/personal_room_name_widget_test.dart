// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/utils/personal_room_name.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'utils/personal_name_test_client.dart';

class _TestMatrixState extends MatrixState {
  @override
  final Client client;

  _TestMatrixState(this.client);
}

class _HeaderController extends ChatController {
  @override
  final Room room;

  _HeaderController(this.room);
}

Widget _app(Client client, Widget child) => Provider<MatrixState>.value(
  value: _TestMatrixState(client),
  child: MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: child,
  ),
);

Future<void> _sync(
  WidgetTester tester,
  Client client,
  Map<String, Object?> content,
) async {
  await tester.runAsync(() => client.handleSync(personalNameSync(content)));
  await tester.pumpAndSettle();
}

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await personalNameTestClient();
    room = client.getRoomById(personalNameRoomId)!;
  });

  tearDown(() => client.dispose());

  testWidgets(
    'open header refreshes from account data alone, including avatar initials',
    (tester) async {
      final controller = _HeaderController(room);
      addTearDown(controller.scrollController.dispose);
      await tester.pumpWidget(
        _app(
          client,
          Scaffold(appBar: AppBar(title: ChatAppBarTitle(controller))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(sharedName), findsOneWidget);
      await _sync(tester, client, {'name': 'Mum'});
      expect(find.text('Mum'), findsOneWidget);
      expect(tester.widget<Avatar>(find.byType(Avatar)).name, 'Mum');
      expect(find.text(sharedName), findsNothing);
      await _sync(tester, client, {});
      expect(find.text(sharedName), findsOneWidget);
    },
  );

  testWidgets('list label, initials, and filter use both names', (
    tester,
  ) async {
    await tester.runAsync(
      () => client.handleSync(personalNameSync({'name': 'Mum'})),
    );
    for (final filter in ['mum', '12345']) {
      await tester.pumpWidget(
        _app(
          client,
          Scaffold(
            body: ChatListItem(room, onTap: () {}, filter: filter),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mum'), findsOneWidget);
      expect(tester.widget<Avatar>(find.byType(Avatar)).name, 'Mum');
    }
    await tester.runAsync(() => client.handleSync(personalNameSync({})));
    await tester.pumpWidget(
      _app(
        client,
        Scaffold(
          body: ChatListItem(room, onTap: () {}, filter: 'mum'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Avatar), findsNothing);
  });

  testWidgets(
    'details retain shared name and participant identity after remote edit',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(client, const ChatDetails(roomId: personalNameRoomId)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Name for you'), findsOneWidget);
      await _sync(tester, client, {'name': 'Mum'});
      expect(find.text('Mum'), findsNWidgets(2));
      expect(find.text(sharedName), findsOneWidget);
      expect(find.text('@owner:example.invalid'), findsOneWidget);
      expect(find.byTooltip('Reset name'), findsOneWidget);
      await _sync(tester, client, {});
      expect(find.byTooltip('Reset name'), findsNothing);
      expect(find.text('Not set'), findsOneWidget);
    },
  );

  testWidgets(
    'saving validates input, waits for sync, and reset waits for sync',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final writes = <Map<String, Object?>>[];
      FakeMatrixApi.currentApi!.api['PUT']![personalNameEndpoint(
        client,
      )] = (body) {
        writes.add(jsonDecode(body as String) as Map<String, Object?>);
        return {};
      };
      await tester.pumpWidget(
        _app(client, const ChatDetails(roomId: personalNameRoomId)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name for you'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), '  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(writes, isEmpty);
      await tester.enterText(find.byType(TextField), '  Mum  ');
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await tester.pump(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(writes, [
        {'name': 'Mum'},
      ]);
      expect(room.personalName, isNull);
      expect(find.text('Waiting for the name to sync...'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await _sync(tester, client, writes.single);
      expect(find.text('Waiting for the name to sync...'), findsNothing);
      expect(find.text('Mum'), findsNWidgets(2));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Reset name'));
        await tester.pump(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(writes.last, isEmpty);
      expect(room.personalName, 'Mum');
      expect(find.text('Waiting for the name to sync...'), findsOneWidget);
      await _sync(tester, client, {});
      expect(find.text('Not set'), findsOneWidget);
    },
  );
}
