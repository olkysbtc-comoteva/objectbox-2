// lib/models/chat_room.dart
import 'package:comoteva/objectbox.g.dart'; // CORREGIDO: Importar para UserProfile_ y ChatMessage_

import 'package:comoteva/models/user_profile.dart';
import 'package:comoteva/models/chat_message.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:objectbox/objectbox.dart';

@NowaGenerated()
@Entity()
class ChatRoom {
  @Id()
  int obxId = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  @Index()
  final String supabaseId;

  final DateTime createdAt;
  final bool isGroup;
  String? backgroundImageUrl; // Hacemos que sea mutable para actualizarlo
  String? pinnedMessageId;

  // NUEVAS PROPIEDADES PARA OFFLINE SYNC
  bool isUpdatePending; // true: El fondo de pantalla de esta sala fue modificado localmente y espera sync.
  bool isDeletePending; // true: Esta sala fue marcada para eliminar localmente y espera sync.

  // 🔹 RELACIONES NATIVAS
  final otherUser = ToOne<UserProfile>();
  final lastMessage = ToOne<ChatMessage>();

  ChatRoom({
    this.obxId = 0,
    required this.supabaseId,
    required this.createdAt,
    this.isGroup = false,
    this.backgroundImageUrl,
    this.pinnedMessageId,
    this.isUpdatePending = false, // Por defecto no hay actualizaciones pendientes
    this.isDeletePending = false, // Por defecto no hay eliminaciones pendientes
  });

  factory ChatRoom.fromJson(
    Map<String, dynamic> json, {
    UserProfile? otherUser,
    ChatMessage? lastMessage,
  }) {
    final room = ChatRoom(
      supabaseId: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      isGroup: (json['is_group'] as bool?) ?? false,
      backgroundImageUrl: json['background_image_url'] as String?,
      // Cuando viene de Supabase, asumimos que no hay nada pendiente
      isUpdatePending: false,
      isDeletePending: false,
    );

    // Asignamos los objetos directamente a las relaciones nativas de ObjectBox
    if (otherUser != null) room.otherUser.target = otherUser;
    if (lastMessage != null) room.lastMessage.target = lastMessage;

    return room;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': supabaseId,
      'created_at': createdAt.toIso8601String(),
      'is_group': isGroup,
      'background_image_url': backgroundImageUrl,
    };
  }

  ChatRoom copyWith({
    int? obxId,
    String? supabaseId,
    DateTime? createdAt,
    bool? isGroup,
    String? backgroundImageUrl,
    UserProfile? otherUser,
    ChatMessage? lastMessage,
    String? pinnedMessageId,
    bool? isUpdatePending,
    bool? isDeletePending,
  }) {
    final newRoom = ChatRoom(
      obxId: obxId ?? this.obxId,
      supabaseId: supabaseId ?? this.supabaseId,
      createdAt: createdAt ?? this.createdAt,
      isGroup: isGroup ?? this.isGroup,
      backgroundImageUrl: backgroundImageUrl ?? this.backgroundImageUrl,
      pinnedMessageId: pinnedMessageId ?? this.pinnedMessageId,
      isUpdatePending: isUpdatePending ?? this.isUpdatePending,
      isDeletePending: isDeletePending ?? this.isDeletePending,
    );

    // Mantenemos o actualizamos las relaciones nativas
    newRoom.otherUser.target = otherUser ?? this.otherUser.target;
    newRoom.lastMessage.target = lastMessage ?? this.lastMessage.target;

    return newRoom;
  }
}