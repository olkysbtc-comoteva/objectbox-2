import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    this.messageType = 'text',
    required this.createdAt,
    this.isRead = false,
    this.reaction, // Añadido para soportar los stickers flotantes de emojis
    this.replyToMessageId,    // NUEVO: ID del mensaje al que se responde
    this.replyToContent,      // NUEVO: Contenido del mensaje al que se responde
    this.replyToSenderId,     // NUEVO: ID del remitente del mensaje al que se responde
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      messageType: (json['message_type'] as String?) ?? 'text',
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: (json['is_read'] as bool?) ?? false,
      reaction: json['reaction'] as String?, // Mapea la reacción desde Supabase
      replyToMessageId: json['reply_to_message_id'] as String?, // NUEVO
      replyToContent: json['reply_to_content'] as String?,     // NUEVO
      replyToSenderId: json['reply_to_sender_id'] as String?,  // NUEVO
    );
  }

  final String id;

  final String roomId;

  final String senderId;

  final String content;

  final String messageType;

  final DateTime createdAt;

  final bool isRead;

  final String? reaction; // Propiedad de lectura para la interfaz de las burbujas

  final String? replyToMessageId;    // NUEVO
  final String? replyToContent;      // NUEVO
  final String? replyToSenderId;     // NUEVO

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'reaction': reaction, // Envía el emoji de vuelta si es necesario convertir a JSON
      'reply_to_message_id': replyToMessageId,    // NUEVO
      'reply_to_content': replyToContent,      // NUEVO
      'reply_to_sender_id': replyToSenderId,     // NUEVO
    };
  }
}
