// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

extension PersonalRoomName on Room {
  static const accountDataType = 'im.fluffychat.custom_name';

  String? get personalName {
    final name = roomAccountData[accountDataType]?.content['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return name.trim();
  }

  String getEffectiveDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => personalName ?? getLocalizedDisplayname(i18n);

  bool matchesDisplayname(String filter, MatrixLocalizations i18n) =>
      getEffectiveDisplayname(i18n).toLowerCase().contains(filter) ||
      getLocalizedDisplayname(i18n).toLowerCase().contains(filter);

  bool get canSetPersonalName => membership == Membership.join && !isSpace;

  Stream<SyncUpdate> get onPersonalNameChanged => client.onSync.stream.where(
    (sync) =>
        sync.rooms?.join?[id]?.accountData?.any(
          (event) => event.type == accountDataType,
        ) ??
        false,
  );

  Future<void> setPersonalName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    return _writePersonalName({'name': trimmed});
  }

  Future<void> resetPersonalName() => _writePersonalName({});

  Future<void> _writePersonalName(Map<String, Object?> content) {
    if (!canSetPersonalName) {
      throw StateError('Personal names require a joined non-space room');
    }
    return client.setAccountDataPerRoom(
      client.userID!,
      id,
      accountDataType,
      content,
    );
  }
}
