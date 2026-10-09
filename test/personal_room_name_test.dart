// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/personal_room_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'utils/personal_name_test_client.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await personalNameTestClient();
    room = client.getRoomById(personalNameRoomId)!;
  });

  tearDown(() => client.dispose());

  test(
    'personal name survives shared renames and reset uses the latest name',
    () async {
      await client.handleSync(personalNameSync({'name': sharedName}));
      await seedPersonalNameRoom(client, name: '67890 (WA)');
      expect(room.getEffectiveDisplayname(), sharedName);
      expect(room.getLocalizedDisplayname(), '67890 (WA)');
      await client.handleSync(personalNameSync({}));
      expect(room.getEffectiveDisplayname(), '67890 (WA)');
    },
  );

  test(
    'malformed names fall back and valid names preserve internal spaces',
    () async {
      for (final content in <Map<String, Object?>>[
        {},
        {'other': 'name'},
        {'name': null},
        {'name': 42},
        {'name': []},
        {'name': ' \n '},
      ]) {
        await client.handleSync(personalNameSync(content));
        expect(room.personalName, isNull);
        expect(room.getEffectiveDisplayname(), sharedName);
      }
      await client.handleSync(personalNameSync({'name': '  Mum  and Dad  '}));
      expect(room.personalName, 'Mum  and Dad');
    },
  );

  test(
    'local search matches both names and drops the reset personal name',
    () async {
      const locals = MatrixDefaultLocalizations();
      await client.handleSync(personalNameSync({'name': 'Mum'}));
      expect(room.matchesDisplayname('mum', locals), isTrue);
      expect(room.matchesDisplayname('12345', locals), isTrue);
      await client.handleSync(personalNameSync({}));
      expect(room.matchesDisplayname('mum', locals), isFalse);
      expect(room.matchesDisplayname('12345', locals), isTrue);
    },
  );

  test(
    'account-data-only sync passes the list filter and narrow subscription',
    () async {
      final updates = <SyncUpdate>[];
      final subscription = room.onPersonalNameChanged.listen(updates.add);
      addTearDown(subscription.cancel);
      final update = personalNameSync({'name': 'Mum'});
      expect(update.hasRoomUpdate, isTrue);
      expect(update.rooms!.join![room.id]!.state, isNull);
      expect(update.rooms!.join![room.id]!.timeline, isNull);
      await client.handleSync(personalNameSync({}, type: 'another.event'));
      await client.handleSync(
        personalNameSync({}, roomId: '!other:example.invalid'),
      );
      await client.handleSync(update);
      await Future<void>.delayed(Duration.zero);
      expect(updates, [update]);
      expect(room.personalName, 'Mum');
    },
  );

  test(
    'names are isolated by account and room, and loaded from the SDK database',
    () async {
      final other = await personalNameTestClient(
        userId: '@bob:example.invalid',
      );
      addTearDown(other.dispose);
      const otherRoomId = '!same-contact:example.invalid';
      await seedPersonalNameRoom(client, roomId: otherRoomId);
      await client.handleSync(personalNameSync({'name': 'Mum'}));
      expect(client.getRoomById(otherRoomId)!.personalName, isNull);
      expect(other.getRoomById(room.id)!.personalName, isNull);
      final restored = await client.database.getRoomList(client);
      expect(restored.singleWhere((r) => r.id == room.id).personalName, 'Mum');
      final fresh = await personalNameTestClient();
      addTearDown(fresh.dispose);
      await fresh.handleSync(personalNameSync({'name': 'Mum'}));
      expect(fresh.getRoomById(room.id)!.personalName, 'Mum');
    },
  );

  test(
    'set/reset only write dedicated account data without state permissions',
    () async {
      expect(room.canChangeStateEvent(EventTypes.RoomName), isFalse);
      expect(room.isDirectChat, isFalse);
      expect(room.canSetPersonalName, isTrue);
      final writes = <Map<String, Object?>>[];
      FakeMatrixApi.currentApi!.api['PUT']![personalNameEndpoint(
        client,
      )] = (body) {
        writes.add(jsonDecode(body as String) as Map<String, Object?>);
        return {};
      };
      await room.setPersonalName('  Mum  and Dad  ');
      expect(writes, [
        {'name': 'Mum  and Dad'},
      ]);
      expect(
        room.personalName,
        isNull,
        reason: 'PUT must wait for canonical sync',
      );
      await client.handleSync(personalNameSync(writes.single));
      await room.resetPersonalName();
      expect(writes.last, isEmpty);
      expect(room.personalName, 'Mum  and Dad');
      await client.handleSync(personalNameSync({}));
      expect(room.personalName, isNull);
      expect(room.isDirectChat, isFalse);
      expect(
        FakeMatrixApi.calledEndpoints.keys.where((e) => e.contains('/state/')),
        isEmpty,
      );
      expect(
        FakeMatrixApi.calledEndpoints.keys.where(
          (e) => e.contains('/account_data/'),
        ),
        [personalNameEndpoint(client)],
      );
    },
  );

  test(
    'empty input sends no request and failed PUT preserves the synced name',
    () async {
      await client.handleSync(personalNameSync({'name': 'Mum'}));
      expect(() => room.setPersonalName(' \n '), throwsArgumentError);
      FakeMatrixApi.currentApi!.api['PUT']![personalNameEndpoint(client)] =
          (_) => {'errcode': 'M_FORBIDDEN', 'error': 'offline or rejected'};
      await expectLater(
        room.setPersonalName('Dad'),
        throwsA(isA<MatrixException>()),
      );
      expect(room.personalName, 'Mum');
    },
  );

  test(
    'spaces and invites cannot be edited; archived rooms retain their label',
    () async {
      await seedPersonalNameRoom(
        client,
        roomId: '!space:example.invalid',
        space: true,
      );
      final space = client.getRoomById('!space:example.invalid')!;
      expect(space.canSetPersonalName, isFalse);
      expect(() => space.setPersonalName('Label'), throwsStateError);
      await client.handleSync(personalNameSync({'name': 'Mum'}));
      room.membership = Membership.invite;
      expect(room.canSetPersonalName, isFalse);
      expect(() => room.resetPersonalName(), throwsStateError);
      room.membership = Membership.leave;
      expect(room.canSetPersonalName, isFalse);
      expect(room.getEffectiveDisplayname(), 'Mum');
    },
  );

  test('outgoing message content and shared rename remain independent', () async {
    await client.handleSync(personalNameSync({'name': 'Private label'}));
    final messageEndpoint =
        '/client/v3/rooms/${Uri.encodeComponent(room.id)}/send/m.room.message/';
    FakeMatrixApi.currentApi!.api['PUT']!['${messageEndpoint}privacy-test'] =
        (_) => {'event_id': '\$sent'};
    await client.sendMessage(room.id, EventTypes.Message, 'privacy-test', {
      'msgtype': 'm.text',
      'body': 'Hello',
    });
    final body = jsonDecode(
      FakeMatrixApi.calledEndpoints['${messageEndpoint}privacy-test']!.single
          as String,
    );
    expect(body, {'msgtype': 'm.text', 'body': 'Hello'});
    expect(room.id, personalNameRoomId);
    expect(room.getLocalizedDisplayname(), sharedName);
  });
}
