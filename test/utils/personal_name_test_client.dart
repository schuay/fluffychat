// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/personal_room_name.dart';
import 'package:matrix/matrix.dart';

import 'test_client.dart';

const personalNameRoomId = '!personal:example.invalid';
const sharedName = '12345 (WA)';

SyncUpdate personalNameSync(
  Map<String, Object?> content, {
  String roomId = personalNameRoomId,
  String type = PersonalRoomName.accountDataType,
}) => SyncUpdate(
  nextBatch: 'personal-name',
  rooms: RoomsUpdate(
    join: {
      roomId: JoinedRoomUpdate(
        accountData: [BasicEvent(type: type, content: content)],
      ),
    },
  ),
);

Future<void> seedPersonalNameRoom(
  Client client, {
  String roomId = personalNameRoomId,
  String name = sharedName,
  bool space = false,
}) => client.handleSync(
  SyncUpdate.fromJson({
    'next_batch': 'room-state',
    'rooms': {
      'join': {
        roomId: {
          'summary': {'m.joined_member_count': 2},
          'state': {
            'events': [
              {
                'type': EventTypes.RoomCreate,
                'state_key': '',
                'event_id': '\$create',
                'sender': '@owner:example.invalid',
                'origin_server_ts': 1,
                'content': {if (space) 'type': 'm.space'},
              },
              {
                'type': EventTypes.RoomName,
                'state_key': '',
                'event_id': '\$name-$name',
                'sender': '@owner:example.invalid',
                'origin_server_ts': DateTime.now().millisecondsSinceEpoch,
                'content': {'name': name},
              },
              for (final id in [client.userID!, '@owner:example.invalid'])
                {
                  'type': EventTypes.RoomMember,
                  'state_key': id,
                  'event_id': '\$member-$id',
                  'sender': id,
                  'origin_server_ts': 1,
                  'content': {'membership': 'join'},
                },
              {
                'type': EventTypes.RoomPowerLevels,
                'state_key': '',
                'event_id': '\$power',
                'sender': '@owner:example.invalid',
                'origin_server_ts': 1,
                'content': {
                  'users': {'@owner:example.invalid': 100},
                  'state_default': 50,
                },
              },
            ],
          },
        },
      },
    },
  }),
);

Future<Client> personalNameTestClient({
  String userId = '@alice:example.invalid',
}) async {
  final client = await prepareTestClient();
  client.importantStateEvents.addAll({
    EventTypes.RoomMember,
    EventTypes.RoomPowerLevels,
  });
  client.setUserId(userId);
  client.accessToken = 'test-token';
  await seedPersonalNameRoom(client);
  await client.fetchCurrentPresence(userId);
  await client.fetchCurrentPresence('@owner:example.invalid');
  return client;
}

String personalNameEndpoint(Client client) =>
    '/client/v3/user/${Uri.encodeComponent(client.userID!)}/rooms/'
    '${Uri.encodeComponent(personalNameRoomId)}/account_data/'
    '${PersonalRoomName.accountDataType}';
