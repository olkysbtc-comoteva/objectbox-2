import 'dart:async'; // NUEVO: Importar para StreamSubscription
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:comoteva/globals/app_constants.dart';
import 'package:comoteva/models/user_profile.dart';
import 'package:comoteva/models/chat_room.dart';
import 'package:comoteva/models/chat_message.dart';
import 'dart:typed_data';
import 'package:comoteva/models/app_config.dart';
import 'package:flutter/material.dart';

@NowaGenerated()
class SupabaseService {
  SupabaseService._();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseClient get client {
    return Supabase.instance.client;
  }

  String? get currentUserId {
    return client.auth.currentUser?.id;
  }

  static final SupabaseService _instance = SupabaseService._();

  Future initialize() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  }

  Future<AuthResponse> signIn(String email, String password) async {
    return Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp(String email, String password) async {
    return Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  // ===================================================
  // MÉTODOS DE FIREBASE CLOUD MESSAGING (FCM)
  // ===================================================

  Future<void> updateFcmToken(String token) async {
    try {
      final userId = currentUserId;
      if (userId == null) return;

      await client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);

      debugPrint('FCM Token guardado con éxito en Supabase.');
    } catch (e) {
      debugPrint('Error al guardar el FCM Token: $e');
    }
  }

  // ===================================================
  // MÉTODOS DE PERFIL Y EMISIONES EN TIEMPO REAL
  // ===================================================

  Future<UserProfile?> getMyProfile() async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }
    final response = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    return UserProfile.fromJson(response);
  }
  
  Stream<List<ChatRoom>> getMyRoomsStream() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value([]);
    }

    // Comprobamos el estado del token usando Future nativo dentro del constructor de Stream
    return Stream.fromFuture(Future(() async {
      try {
        final currentSession = client.auth.currentSession;
        if (currentSession != null && currentSession.isExpired) {
          debugPrint('JWT Expirado detectado en tiempo real. Solicitando refresh...');
          await client.auth.refreshSession();
        }
      } catch (e) {
        debugPrint('Error intentando refrescar sesión para Realtime: $e');
      }
      return true;
    })).asyncExpand((_) {
      // Una vez asegurado el token, abrimos la suscripción de Supabase
      return client
          .from('room_members')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .asyncMap((members) async {
            try {
              if (members.isEmpty) return <ChatRoom>[];

              final roomsFutures = members.map((member) async {
                try {
                  final roomId = member['room_id'] as String;
                  
                  // Ejecutamos las consultas concurrentes en paralelo
                  final List<dynamic> dataFetch = await Future.wait([
                    client.from('rooms').select().eq('id', roomId).single(),
                    client.from('room_members').select('profiles(*)').eq('room_id', roomId).neq('user_id', userId).maybeSingle(),
                    client.from('messages').select().eq('room_id', roomId).order('created_at', ascending: false).limit(1).maybeSingle(),
                  ]);

                  final roomData = dataFetch[0] as Map<String, dynamic>;
                  final otherMemberData = dataFetch[1] as Map<String, dynamic>?;
                  final lastMsgData = dataFetch[2] as Map<String, dynamic>?;

                  final otherProfile = (otherMemberData != null && otherMemberData['profiles'] != null)
                      ? UserProfile.fromJson(otherMemberData['profiles'] as Map<String, dynamic>)
                      : null;

                  final lastMsg = lastMsgData != null
                      ? ChatMessage.fromJson(lastMsgData)
                      : null;

                  return ChatRoom.fromJson(
                    roomData,
                    otherUser: otherProfile,
                    lastMessage: lastMsg,
                  );
                } catch (e) {
                  debugPrint('Error procesando sala individual: $e');
                  return null; 
                }
              });

              final resolvedRooms = await Future.wait(roomsFutures);
              return resolvedRooms.whereType<ChatRoom>().toList();
              
            } catch (e) {
              debugPrint('Error crítico en getMyRoomsStream asyncMap: $e');
              return <ChatRoom>[];
            }
          });
    });
  }
  
  
  Stream<List<ChatMessage>> getMessagesStream(String roomId) {
    // CORRECCIÓN: Envolvemos correctamente en una instancia de Future pura
    return Stream.fromFuture(Future(() async {
      try {
        final currentSession = client.auth.currentSession;
        if (currentSession != null && currentSession.isExpired) {
          debugPrint('JWT Expirado detectado en stream de mensajes. Solicitando refresh...');
          await client.auth.refreshSession();
        }
      } catch (e) {
        debugPrint('Error intentando refrescar sesión para mensajes Realtime: $e');
      }
      return true;
    })).asyncExpand((_) {
      // Una vez validada la sesión, iniciamos el stream de escucha de mensajes
      return client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('room_id', roomId)
          .order('created_at', ascending: false)
          .map((data) => data.map((json) => ChatMessage.fromJson(json)).toList());
    });
  }

  // ===================================================
  // GESTIÓN DE MENSAJES Y ACCIONES DE CHAT
  // ===================================================

  Future<void> sendMessage(
    String roomId,
    String content, {
    String type = 'text',
    String? replyToMessageId,    // Parámetro para el ID del mensaje respondido
    String? replyToContent,      // Parámetro para el contenido del mensaje respondido
    String? replyToSenderId,     // Parámetro para el ID del remitente del mensaje respondido
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return;
    }
    await client.from('messages').insert({
      'room_id': roomId,
      'sender_id': userId,
      'content': content,
      'message_type': type,
      'reply_to_message_id': replyToMessageId,
      'reply_to_content': replyToContent,
      'reply_to_sender_id': replyToSenderId,
    });
  }

  Future<void> updateMessageReaction(String messageId, String emoji) async {
    await client
        .from('messages')
        .update({'reaction': emoji})
        .eq('id', messageId);
  }

  Future<void> markMessagesAsRead(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await client
        .from('messages')
        .update({'is_read': true})
        .eq('room_id', roomId)
        .neq('sender_id', userId)
        .eq('is_read', false);
  }

  // ===================================================
  // GESTIÓN DE MENSAJES FIJADOS (PINNED MESSAGES)
  // ===================================================

  // Obtener el mensaje fijado para una sala
Stream<ChatMessage?> getPinnedMessageStream(String roomId) {
  final userId = currentUserId;
  if (userId == null) return Stream<ChatMessage?>.value(null);
  
  return client
      .from('chat_pinned_messages')
      .stream(primaryKey: ['id']) 
      .eq('room_id', roomId)
      .limit(1) 
      .asyncMap<ChatMessage?>((data) async {
        if (data.isEmpty) return null; 
        
        final pinnedMessageData = data.first;
        final messageId = pinnedMessageData['message_id'] as String?;

        if (messageId == null) return null;

        try {
          final messageResponse = await client
              .from('messages')
              .select()
              .eq('id', messageId)
              .maybeSingle();

          if (messageResponse != null) {
            return ChatMessage.fromJson(messageResponse);
          }
          return null;
        } catch (e) {
          debugPrint('Error asíncrono en mensaje fijado: $e');
          return null;
        }
      });
}





  // Fijar un mensaje en una sala
  Future<void> pinMessage(String roomId, String messageId) async {
  final userId = currentUserId;
  if (userId == null) return;

  try {
    // Al usar upsert con onConflict, Supabase pisa el registro viejo en un solo paso
    await client.from('chat_pinned_messages').upsert({
      'room_id': roomId,
      'message_id': messageId,
      'user_id': userId,
    }, onConflict: 'room_id,user_id'); 

    debugPrint('✅ Mensaje privado fijado/reemplazado con éxito en la sala $roomId');
  } catch (e) {
    debugPrint('Error al fijar mensaje privado: $e');
    throw Exception('No se pudo fijar el mensaje.');
  }
}


  // Desfijar un mensaje en una sala
  Future<void> unpinMessage(String roomId) async {
    try {
      await client
          .from('chat_pinned_messages')
          .delete()
          .eq('room_id', roomId);
      debugPrint('Mensaje desfijado correctamente en la sala $roomId');
    } catch (e) {
      debugPrint('Error al desfijar el mensaje: $e');
      throw Exception('No se pudo desfijar el mensaje.');
    }
  }

  Future<String?> generateDynamicToken() async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }
    await client.from('temporary_tokens').delete().eq('user_id', userId);
    final response = await client
        .from('temporary_tokens')
        .insert({
          'user_id': userId,
          'expires_at': DateTime.now()
              .add(const Duration(seconds: 120))
              .toIso8601String(),
        })
        .select()
        .single();
    return response['token'] as String?;
  }
  
  Future<ChatRoom?> startChatWithDynamicToken(String token) async {
    final myId = currentUserId;
    if (myId == null) {
      return null;
    }
    final tokenData = await client
        .from('temporary_tokens')
        .select()
        .eq('token', token)
        .gt('expires_at', DateTime.now().toIso8601String())
        .maybeSingle();
    if (tokenData == null) {
      throw Exception('El código QR es inválido o ha expirado.');
    }
    final targetUserId = tokenData['user_id'] as String;
    if (targetUserId == myId) {
      throw Exception('No puedes chatear contigo mismo.');
    }
    await client.from('temporary_tokens').delete().eq('token', token);
    final existingRoomData = await client.rpc(
      'get_private_room_between_users',
      params: {'user1': myId, 'user2': targetUserId},
    );
    if (existingRoomData != null) {
      final roomData = await client
          .from('rooms')
          .select()
          .eq('id', existingRoomData as String)
          .single();
      final otherProfileData = await client
          .from('profiles')
          .select()
          .eq('id', targetUserId)
          .single();
      return ChatRoom.fromJson(
        roomData,
        otherUser: UserProfile.fromJson(otherProfileData),
      );
    }
    final newRoomData = await client.from('rooms').insert({}).select().single();
    final roomId = newRoomData['id'] as String;
    await client.from('room_members').insert([
      {'room_id': roomId, 'user_id': myId},
      {'room_id': roomId, 'user_id': targetUserId},
    ]);
    final otherProfileData = await client
        .from('profiles')
        .select()
        .eq('id', targetUserId)
        .single();
    return ChatRoom.fromJson(
      newRoomData,
      otherUser: UserProfile.fromJson(otherProfileData),
    );
  }
  
  Future<void> deleteRoom(String roomId) async {
    try {
      await client.from('room_members').delete().eq('room_id', roomId);
      await client.from('rooms').delete().eq('id', roomId);
      // Opcional: Desfijar mensajes al eliminar la sala
      await unpinMessage(roomId); 
      debugPrint('Sala $roomId eliminada correctamente de Supabase.');
    } catch (e) {
      debugPrint('Error al eliminar la sala de chat: $e');
      throw Exception('No se pudo eliminar el chat.');
    }
  }
  
  Future<void> updateMessage(String messageId, String newContent) async {
    await client
        .from('messages')
        .update({'content': newContent})
        .eq('id', messageId);
  }

  Future<void> deleteMessage(String messageId) async {
    await client.from('messages').delete().eq('id', messageId);
    // Opcional: Si el mensaje eliminado es el fijado, desfijarlo automáticamente
    // Esto podría ser un trigger en Supabase o una lógica aquí.
    // Para simplificar, asumimos que Supabase handles CASCADE DELETE or similar.
    // Si no, necesitaríamos comprobar si `messageId` es el `pinnedMessageId`
    // y llamar a `unpinMessage(roomId)` si lo es.
  }
  
  
    // ===================================================
  // ALMACENAMIENTO Y AUTENTICACIÓN AVANZADA
  // ===================================================

  Future<String?> uploadMedia(
    Uint8List bytes,
    String fileName, {
    required String roomId,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }
    
    // Verificación preventiva del token antes de subir archivos pesados
    try {
      final currentSession = client.auth.currentSession;
      if (currentSession != null && currentSession.isExpired) {
        await client.auth.refreshSession();
      }
    } catch (e) {
      debugPrint('Error refrescando sesión previo a Storage upload: $e');
    }

    final path =
        '${roomId}/${userId}/${DateTime.now().millisecondsSinceEpoch}_${fileName}';
    await client.storage.from('temporary_media').uploadBinary(path, bytes);
    return client.storage.from('temporary_media').getPublicUrl(path);
  }
  
  Future<AuthResponse> signUpWithProfile(
    String email,
    String password, {
    String? nombre,
  }) async {
    final response = await client.auth.signUp(email: email, password: password);
    if (response.user != null) {
      await client.from('profiles').insert({
        'id': response.user?.id,
        'nombre': nombre ?? email.split('@')[0],
        'preferencia_canal': 1,
      });
    }
    return response;
  }

  Future<AuthResponse> signInAndSyncProfile(
    String email,
    String password,
  ) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    
    if (response.user != null) {
      final existingProfile = await client
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .maybeSingle();
      if (existingProfile == null) {
        await client.from('profiles').insert({
          'id': response.user?.id,
          'nombre': email.split('@')[0],
          'preferencia_canal': 1,
        });
      }

      // Sincronización del FCM Token tras inicio de sesión exitoso
      try {
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await updateFcmToken(token);
        }
      } catch (e) {
        debugPrint('Error obteniendo FCM Token tras Login: $e');
      }
    }
    return response;
  }

  Future<void> updateAvatar(Uint8List bytes, String fileName) async {
    final userId = currentUserId;
    if (userId == null) {
      return;
    }

    // Verificación preventiva del token antes de cambiar el avatar
    try {
      final currentSession = client.auth.currentSession;
      if (currentSession != null && currentSession.isExpired) {
        await client.auth.refreshSession();
      }
    } catch (e) {
      debugPrint('Error refrescando sesión previo a Avatar upload: $e');
    }

    final path =
        'avatars/${userId}/${DateTime.now().millisecondsSinceEpoch}_${fileName}';
    await client.storage.from('temporary_media').uploadBinary(path, bytes);
    final publicUrl = client.storage.from('temporary_media').getPublicUrl(path);
    await client
        .from('profiles')
        .update({'avatar_url': publicUrl})
        .eq('id', userId);
  }

  Future<AppConfig?> getAppConfig() async {
    try {
      final response = await client.from('app_config2').select().maybeSingle();
      if (response != null) {
        return AppConfig.fromJson(response);
      }
    } catch (e) {
      debugPrint('Error fetching app config: $e');
    }
    return null;
  }

  // ===================================================
  // MÉTODOS DE PERSISTENCIA PARA FONDOS DE CHAT
  // ===================================================

  Future<List<Map<String, dynamic>>> getAvailableWallpapers() async {
    try {
      final response = await client
          .from('chat_wallpapers')
          .select()
          .order('id', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error al leer chat_wallpapers: $e');
      return [];
    }
  }

  Future<void> updateChatBackground(String roomId, int wallpaperId) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await client
          .from('room_members')
          .update({'wallpaper_id': wallpaperId})
          .eq('room_id', roomId)
          .eq('user_id', userId);
      debugPrint('Fondo $wallpaperId guardado con éxito para la sala $roomId');
    } catch (e) {
      debugPrint('Error al guardar fondo en room_members: $e');
    }
  }

  Future<Map<String, dynamic>?> getActiveChatBackground(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final memberData = await client
          .from('room_members')
          .select('wallpaper_id')
          .eq('room_id', roomId)
          .eq('user_id', userId)
          .maybeSingle();

      if (memberData == null || memberData['wallpaper_id'] == null) return null;

      final int wallpaperId = memberData['wallpaper_id'];

      final wallpaperData = await client
          .from('chat_wallpapers')
          .select()
          .eq('id', wallpaperId)
          .single();

      return wallpaperData;
    } catch (e) {
      debugPrint('Error al recuperar fondo activo: $e');
      return null;
    }
  }
}