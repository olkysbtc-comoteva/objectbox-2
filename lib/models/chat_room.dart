import 'package:comoteva/models/user_profile.dart';
import 'package:comoteva/models/chat_message.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class ChatRoom {
  ChatRoom({
    required this.id,
    required this.createdAt,
    this.isGroup = false,
    this.otherUser,
    this.lastMessage,
  });

  factory ChatRoom.fromJson(
    Map<String, dynamic> json, {
    UserProfile? otherUser,
    ChatMessage? lastMessage,
  }) {
    return ChatRoom(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      isGroup: (json['is_group'] as bool?) ?? false,
      otherUser: otherUser,
      lastMessage: lastMessage,
    );
  }

  final String id;

  final DateTime createdAt;

  final bool isGroup;

  final UserProfile? otherUser;

  final ChatMessage? lastMessage;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'is_group': isGroup,
    };
  }
}
