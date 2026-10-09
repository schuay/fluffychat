// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_details/chat_details_view.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/personal_room_name.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatDetails extends StatefulWidget {
  final String roomId;
  final Widget? embeddedCloseButton;

  const ChatDetails({
    super.key,
    required this.roomId,
    this.embeddedCloseButton,
  });

  @override
  ChatDetailsController createState() => ChatDetailsController();
}

class ChatDetailsController extends State<ChatDetails> {
  bool personalNameSaving = false;
  bool personalNamePending = false;
  String? _pendingPersonalName;
  Room? _personalNameRoom;
  StreamSubscription<SyncUpdate>? _personalNameSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final room = Matrix.of(context).client.getRoomById(widget.roomId);
    if (identical(room, _personalNameRoom)) return;
    _personalNameSubscription?.cancel();
    _personalNameRoom = room;
    personalNamePending = false;
    _personalNameSubscription = room?.onPersonalNameChanged.listen((_) {
      setState(() {
        if (personalNamePending && room.personalName == _pendingPersonalName) {
          personalNamePending = false;
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant ChatDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) didChangeDependencies();
  }

  @override
  void dispose() {
    _personalNameSubscription?.cancel();
    super.dispose();
  }

  Future<void> setPersonalNameAction() async {
    if (personalNameSaving || personalNamePending) return;
    final room = _personalNameRoom;
    if (room == null || !room.canSetPersonalName) return;
    final l10n = L10n.of(context);
    setState(() => personalNameSaving = true);
    try {
      final input = await showTextInputDialog(
        context: context,
        title: l10n.nameForYou,
        message: l10n.personalNameDescription,
        okLabel: l10n.save,
        cancelLabel: l10n.cancel,
        initialText: room.personalName ?? '',
        hintText: room.getLocalizedDisplayname(MatrixLocals(l10n)),
        validator: (input) =>
            input.trim().isEmpty ? l10n.personalNameEmpty : null,
      );
      if (input == null || !mounted) return;
      await _writePersonalName(room, input.trim());
    } finally {
      if (mounted) setState(() => personalNameSaving = false);
    }
  }

  Future<void> resetPersonalNameAction() async {
    if (personalNameSaving || personalNamePending) return;
    final room = _personalNameRoom;
    if (room == null || !room.canSetPersonalName) return;
    setState(() => personalNameSaving = true);
    try {
      await _writePersonalName(room, null);
    } finally {
      if (mounted) setState(() => personalNameSaving = false);
    }
  }

  Future<void> _writePersonalName(Room room, String? name) async {
    _pendingPersonalName = name;
    setState(() => personalNamePending = true);
    final result = await showFutureLoadingDialog(
      context: context,
      future: () =>
          name == null ? room.resetPersonalName() : room.setPersonalName(name),
    );
    if (!mounted) return;
    setState(() {
      personalNamePending = result.error == null && room.personalName != name;
    });
  }

  bool displaySettings = false;

  void toggleDisplaySettings() =>
      setState(() => displaySettings = !displaySettings);

  String? get roomId => widget.roomId;

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: l10n.changeTheNameOfTheGroup,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: room.getLocalizedDisplayname(MatrixLocals(l10n)),
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setName(input),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.displaynameHasBeenChanged)),
      );
    }
  }

  Future<void> setTopicAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: l10n.setChatDescription,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.noChatDescriptionYet,
      initialText: room.topic,
      minLines: 4,
      maxLines: 8,
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setDescription(input),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.chatDescriptionHasBeenChanged)),
      );
    }
  }

  Future<void> setAvatarAction(AvatarAction action) async {
    final room = Matrix.of(context).client.getRoomById(roomId!);
    if (action == AvatarAction.remove) {
      await showFutureLoadingDialog(
        context: context,
        future: () => room!.setAvatar(null),
      );
      return;
    }
    MatrixFile file;
    if (action == AvatarAction.camera) {
      final result = await ImagePicker().pickImage(source: ImageSource.camera);
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      if (!mounted) return;
      final picked = await selectFiles(
        context,
        allowMultiple: false,
        type: FileType.image,
      );
      final pickedFile = picked.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room!.setAvatar(file),
    );
  }

  static const fixedWidth = 360.0;

  @override
  Widget build(BuildContext context) => ChatDetailsView(this);
}
