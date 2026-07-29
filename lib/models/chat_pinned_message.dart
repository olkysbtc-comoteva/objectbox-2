import 'package:objectbox/objectbox.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
@Entity()
class ChatPinnedMessage {
  @Id()
  int obxId = 0;

  @Index()
  final String messageId; // El supabaseId del mensaje fijado

  @Index()
  final String roomId;    // La sala donde se fijó

  @Index()
  final String userId;    // El usuario que lo fijó

  final bool isSynced;    // Bandera crítica para saber si ya se subió a Supabase

  ChatPinnedMessage({
    this.obxId = 0,
    required this.messageId,
    required this.roomId,
    required this.userId,
    this.isSynced = false, // Nace en false si se crea sin conexión
  });

  // Método copyWith para actualizar la sincronización más adelante
  ChatPinnedMessage copyWith({
    int? obxId,
    String? messageId,
    String? roomId,
    String? userId,
    bool? isSynced,
  }) {
    return ChatPinnedMessage(
      obxId: obxId ?? this.obxId,
      messageId: messageId ?? this.messageId,
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
