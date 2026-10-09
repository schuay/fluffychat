// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/personal_room_name.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class PersonalRoomNameBuilder extends StatelessWidget {
  final Room room;
  final WidgetBuilder builder;

  const PersonalRoomNameBuilder({
    required this.room,
    required this.builder,
    super.key,
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<SyncUpdate>(
    stream: room.onPersonalNameChanged,
    builder: (context, _) => builder(context),
  );
}
