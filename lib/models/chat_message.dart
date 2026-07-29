// lib/models/chat_message.dart
import 'package:objectbox/objectbox.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
@Entity()
class ChatMessage {
  @Id()
  int obxId = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  @Index()
  final String supabaseId;

  @Index()
  final String roomId;

  @Index()
  final String senderId;

  String content; 
  final String messageType;
  
  @Property(type: PropertyType.date)
  final DateTime createdAt;
  
  bool isRead; 
  String? reaction; 
  String? replyToMessageId;
  String? replyToContent;
  String? replyToSenderId;

  bool isSent; 
  bool isUpdatePending; 
  bool isDeletePending; 
  bool isReadPending; 

  ChatMessage({
    this.obxId = 0,
    required this.supabaseId,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.createdAt,
    this.isRead = false,
    this.reaction,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderId,
    this.isSent = true, 
    this.isUpdatePending = false,
    this.isDeletePending = false,
    this.isReadPending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      supabaseId: json['id'] as String,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      messageType: json['message_type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      isRead: (json['is_read'] as bool?) ?? false,
      reaction: json['reaction'] as String?,
      replyToMessageId: json['reply_to_message_id'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      replyToSenderId: json['reply_to_sender_id'] as String?,
      isSent: true, 
      isUpdatePending: false, //  Corregido de '=' a ':'
      isDeletePending: false, //  Corregido de '=' a ':'
      isReadPending: false,    //  Corregido de '=' a ':'
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': supabaseId,
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'reaction': reaction,
      'reply_to_message_id': replyToMessageId,
      'reply_to_content': replyToContent,
      'reply_to_sender_id': replyToSenderId,
    };
  }

  ChatMessage copyWith({
    int? obxId,
    String? supabaseId,
    String? roomId,
    String? senderId,
    String? content,
    String? messageType,
    DateTime? createdAt,
    bool? isRead,
    String? Function()? reaction, // Soporte funcional para anulables
    String? Function()? replyToMessageId,
    String? Function()? replyToContent,
    String? Function()? replyToSenderId,
    bool? isSent,
    bool? isUpdatePending,
    bool? isDeletePending,
    bool? isReadPending,
  }) {
    return ChatMessage(
      obxId: obxId ?? this.obxId,
      supabaseId: supabaseId ?? this.supabaseId,
      roomId: roomId ?? this.roomId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      reaction: reaction != null ? reaction() : this.reaction,
      replyToMessageId: replyToMessageId != null ? replyToMessageId() : this.replyToMessageId,
      replyToContent: replyToContent != null ? replyToContent() : this.replyToContent,
      replyToSenderId: replyToSenderId != null ? replyToSenderId() : this.replyToSenderId,
      isSent: isSent ?? this.isSent,
      isUpdatePending: isUpdatePending ?? this.isUpdatePending,
      isDeletePending: isDeletePending ?? this.isDeletePending,
      isReadPending: isReadPending ?? this.isReadPending,
    );
  }
}
