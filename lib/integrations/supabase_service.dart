import 'dart:async';
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

import 'package:objectbox/objectbox.dart';
import 'package:comoteva/objectbox.dart';
import 'package:comoteva/objectbox.g.dart';
import 'package:comoteva/main.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:comoteva/models/chat_pinned_message.dart';
import 'package:comoteva/integrations/outbox_sync_service.dart'; // Importar OutboxSyncService

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

  late final Box<UserProfile> _userProfileBox;
  late final Box<ChatRoom> _chatRoomBox;
  late final Box<ChatMessage> _chatMessageBox;
  late final Box<ChatPinnedMessage> _chatPinnedMessageBox; // Nueva box para pines

  StreamSubscription? _roomMembersSubscription;
  final Map<String, StreamSubscription> _activeMessageStreams = {};
  final OutboxSyncService _outboxSyncService = OutboxSyncService(); // Instancia del Outbox

  Future initialize() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
    _userProfileBox = objectbox!.store.box<UserProfile>();
    _chatRoomBox = objectbox!.store.box<ChatRoom>();
    _chatMessageBox = objectbox!.store.box<ChatMessage>();
    _chatPinnedMessageBox = objectbox!.store.box<ChatPinnedMessage>(); // Inicializar box

    _ensureSupabaseSyncListeners();
    _outboxSyncService.listenToConnectionChanges(); // Iniciar el servicio de sincronización
  }

  void _saveUserProfile(UserProfile profile) {
    _userProfileBox.put(profile);
    debugPrint('ObjectBox: Guardado/Actualizado UserProfile con Supabase ID: ${profile.supabaseId}');
  }

  void _saveChatRoom(ChatRoom room) {
    _chatRoomBox.put(room);
    debugPrint('ObjectBox: Guardado/Actualizado ChatRoom con Supabase ID: ${room.supabaseId}');
  }

  void _saveChatMessage(ChatMessage message) {
    _chatMessageBox.put(message);
    debugPrint('ObjectBox: Guardado/Actualizado ChatMessage con Supabase ID: ${message.supabaseId}');
  }

  UserProfile? _getUserProfileFromObjectBox(String supabaseId) {
    return _userProfileBox.query(UserProfile_.supabaseId.equals(supabaseId)).build().findFirst();
  }

  ChatMessage? _getChatMessageFromObjectBox(String supabaseId) {
    return _chatMessageBox.query(ChatMessage_.supabaseId.equals(supabaseId)).build().findFirst();
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    _ensureSupabaseSyncListeners();
    _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar tras login
    return response;
  }

  Future<AuthResponse> signUp(String email, String password) async {
    final response = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );
    _ensureSupabaseSyncListeners();
    _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar tras signup
    return response;
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    _userProfileBox.removeAll();
    _chatRoomBox.removeAll();
    _chatMessageBox.removeAll();
    _chatPinnedMessageBox.removeAll(); // Limpiar también los pines
    debugPrint('ObjectBox: Todos los datos locales se han borrado al cerrar sesión.');
    _cancelAllSupabaseStreams();
  }

  Future<void> _ensureSupabaseSyncListeners() async {
    if (currentUserId != null) {
      await _startSupabaseRoomSync();
    } else {
      _cancelAllSupabaseStreams();
    }
  }

  void _cancelAllSupabaseStreams() {
    _roomMembersSubscription?.cancel();
    _roomMembersSubscription = null;
    _activeMessageStreams.values.forEach((sub) => sub.cancel());
    _activeMessageStreams.clear();
    debugPrint('Supabase: Todas las suscripciones en tiempo real canceladas.');
  }

  Future<void> updateFcmToken(String token) async {
    try {
      final userId = currentUserId;
      if (userId == null) return;

      // Esto es una operación crítica que requiere red para notificaciones
      await client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);

      debugPrint('FCM Token guardado con éxito en Supabase.');
    } catch (e) {
      debugPrint('Error al guardar el FCM Token: $e');
      // No se encola para Outbox, ya que el token FCM es sensible al tiempo y la conectividad.
    }
  }

  /// Agrega este método para fijar mensajes con soporte Offline
  Future<void> fijarMensajeOffline({
    required String roomId,
    required String userId,
    String? messageId, // Si es nulo, significa que el usuario presionó "Desfijar"
  }) async {
    if (objectbox == null) return;

    final pinBox = objectbox!.store.box<ChatPinnedMessage>();

    // 1. Buscamos si ya existía un pin previo en esta sala para este usuario
    final query = (pinBox.query(
      ChatPinnedMessage_.roomId.equals(roomId).and(ChatPinnedMessage_.userId.equals(userId))
    )).build();
    final existingPin = query.findFirst();
    query.close();

    // Actualizar el `pinnedMessageId` de la sala en ObjectBox
    final localRoom = _chatRoomBox.query(ChatRoom_.supabaseId.equals(roomId)).build().findFirst();
    if (localRoom != null) {
        _saveChatRoom(localRoom.copyWith(pinnedMessageId: messageId));
    }


    // Caso A: Acción de DESFIJAR
    if (messageId == null) {
      if (existingPin != null) {
        // Marcamos el pin existente para eliminación y lo actualizamos como no sincronizado
        // En `_syncPendingPins` de Outbox, buscaremos un messageId especial para desfijar.
        pinBox.put(existingPin.copyWith(messageId: 'null_unpin', isSynced: false)); // Usamos una convención
      }
      debugPrint('📡 [Offline] Desfijado localmente. Pendiente de sincronización remota.');
    } else {
      // Caso B: Acción de FIJAR
      final nuevoPin = ChatPinnedMessage(
        obxId: existingPin?.obxId ?? 0,
        messageId: messageId,
        roomId: roomId,
        userId: userId,
        isSynced: false, // Siempre nace como no sincronizado para que Outbox lo procese
      );
      pinBox.put(nuevoPin);
      debugPrint('📡 [Pin] Guardado localmente. Pendiente de sincronización remota.');
    }
    _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar inmediatamente
  }

  Future<UserProfile?> getMyProfile() async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }

    final localProfile = _getUserProfileFromObjectBox(userId);
    // Siempre intentamos refrescar desde Supabase en segundo plano si hay conectividad
    // y la caché local está disponible, pero devolvemos lo local de inmediato.
    _fetchProfileFromSupabaseAndUpdateObjectBox(userId);
    return localProfile;
  }

  Future<UserProfile?> _fetchProfileFromSupabaseAndUpdateObjectBox(String userId) async {
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      final profile = UserProfile.fromJson(response);
      _saveUserProfile(profile);
      debugPrint('Supabase: Perfil recuperado y ObjectBox actualizado.');
      return profile;
    } catch (e) {
      debugPrint('Error al obtener perfil de Supabase: $e');
      return null;
    }
  }

  Future<void> _startSupabaseRoomSync() async {
    final userId = currentUserId;
    if (userId == null || _roomMembersSubscription != null) return;

    try {
      final currentSession = client.auth.currentSession;
      if (currentSession != null && currentSession.isExpired) {
        await client.auth.refreshSession();
      }
    } catch (e) {
      debugPrint('Error refrescando sesión para Supabase room sync: $e');
      return;
    }

    _roomMembersSubscription = client
        .from('room_members')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((members) async {
          debugPrint('Supabase: Actualización en tiempo real de miembros de sala recibida.');

          final allLocalRooms = _chatRoomBox.getAll();
          final localRoomSupabaseIds = allLocalRooms.map((r) => r.supabaseId).toSet();
          final remoteRoomSupabaseIds = members.map<String>((m) => m['room_id'] as String).toSet();

          final roomsToDeleteLocally = localRoomSupabaseIds.where((localId) => !remoteRoomSupabaseIds.contains(localId));

          for (final localId in roomsToDeleteLocally) {
            final roomToDelete = _chatRoomBox.query(ChatRoom_.supabaseId.equals(localId)).build().findFirst();
            if (roomToDelete != null) {
              // Si la sala está marcada como pendiente de eliminación localmente, no la eliminamos forzosamente.
              // Dejamos que el outbox la elimine de Supabase, y luego de ObjectBox.
              if (!roomToDelete.isDeletePending) {
                _chatRoomBox.remove(roomToDelete.obxId);
                _chatMessageBox.query(ChatMessage_.roomId.equals(localId)).build().find().forEach((msg) => _chatMessageBox.remove(msg.obxId));
                _chatPinnedMessageBox.query(ChatPinnedMessage_.roomId.equals(localId)).build().find().forEach((pin) => _chatPinnedMessageBox.remove(pin.obxId)); // Eliminar pines asociados
                debugPrint('ObjectBox: Eliminada sala local $localId y sus mensajes/pines, ya no presente en Supabase.');
              } else {
                debugPrint('ObjectBox: Sala $localId marcada para eliminar, evitando eliminación forzada desde real-time.');
              }
            }
          }

          if (members.isEmpty) {
            return;
          }

          for (var member in members) {
            final roomId = member['room_id'] as String;
            try {
              final List<dynamic> dataFetch = await Future.wait([
                client.from('rooms').select().eq('id', roomId).single(),
                client.from('room_members').select('profiles(*)').eq('room_id', roomId).neq('user_id', userId).maybeSingle(),
                client.from('messages').select().eq('room_id', roomId).order('created_at', ascending: false).limit(1).maybeSingle(),
              ]);

              final roomData = dataFetch[0] as Map<String, dynamic>;
              final otherMemberData = dataFetch[1] as Map<String, dynamic>?;
              final lastMsgData = dataFetch[2] as Map<String, dynamic>?;

              UserProfile? otherProfile;
              if (otherMemberData != null && otherMemberData['profiles'] != null) {
                  otherProfile = UserProfile.fromJson(otherMemberData['profiles'] as Map<String, dynamic>);
                  _saveUserProfile(otherProfile);
              }

              ChatMessage? lastMsg;
              if (lastMsgData != null) {
                  lastMsg = ChatMessage.fromJson(lastMsgData);
                  // Solo guardamos si no hay un mensaje local pendiente de alguna operación
                  final existingLocalMsg = _getChatMessageFromObjectBox(lastMsg.supabaseId);
                  if (existingLocalMsg == null ||
                      (!existingLocalMsg.isSent && !existingLocalMsg.isUpdatePending && !existingLocalMsg.isDeletePending && !existingLocalMsg.isReadPending)) {
                    _saveChatMessage(lastMsg);
                  } else {
                    debugPrint('ObjectBox: Ignorando mensaje remoto ${lastMsg.supabaseId} por tener operaciones locales pendientes.');
                  }
              }

              // Buscar el pinnedMessageId en la tabla `chat_pinned_messages`
              String? pinnedMessageId;
              try {
                final pinnedMessageEntry = await client.from('chat_pinned_messages')
                    .select('message_id')
                    .eq('room_id', roomId)
                    .eq('user_id', userId)
                    .maybeSingle();
                pinnedMessageId = pinnedMessageEntry?['message_id'] as String?;
              } catch (pinError) {
                debugPrint('Error obteniendo pinnedMessageId para room $roomId: $pinError');
              }


              final chatRoom = ChatRoom.fromJson(
                roomData,
                otherUser: otherProfile,
                lastMessage: lastMsg,
              );

              // Intentar preservar el estado local de isUpdatePending/isDeletePending si existe
              final existingLocalRoom = _chatRoomBox.query(ChatRoom_.supabaseId.equals(chatRoom.supabaseId)).build().findFirst();
              final isUpdatePending = existingLocalRoom?.isUpdatePending ?? false;
              final isDeletePending = existingLocalRoom?.isDeletePending ?? false;

              _saveChatRoom(chatRoom.copyWith(
                isUpdatePending: isUpdatePending,
                isDeletePending: isDeletePending,
                pinnedMessageId: pinnedMessageId, // Actualizar el pinnedMessageId
              ));
              debugPrint('ObjectBox: Sala ${chatRoom.supabaseId} actualizada desde Supabase real-time.');
            } catch (e) {
              debugPrint('Error procesando actualización de sala desde Supabase real-time para room $roomId: $e');
            }
          }
        }, onError: (error) {
          debugPrint('Error en el stream de Supabase real-time de miembros de sala: $error');
        });
  }

  Stream<List<ChatRoom>> getMyRoomsStream() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value([]);
    }

    return _chatRoomBox.query(ChatRoom_.supabaseId.notNull()).watch(triggerImmediately: true).asyncMap((query) async {
      final rooms = query.find().where((room) => !room.isDeletePending).toList(); // Filtrar salas pendientes de eliminación
      List<ChatRoom> fullRooms = [];
      for (var room in rooms) {
        // Las relaciones ToOne ya manejan la carga automática del otherUser y lastMessage
        fullRooms.add(room);
      }
      // Ordenar por la fecha del último mensaje
      fullRooms.sort((a, b) {
        final aTime = a.lastMessage.target?.createdAt ?? a.createdAt;
        final bTime = b.lastMessage.target?.createdAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });
      debugPrint('ObjectBox: Emitiendo ${fullRooms.length} salas de chat desde el almacén local.');
      return fullRooms;
    });
  }

  void startListeningToRoomMessages(String roomId) async {
    if (_activeMessageStreams.containsKey(roomId)) return;

    try {
      final currentSession = client.auth.currentSession;
      if (currentSession != null && currentSession.isExpired) {
        await client.auth.refreshSession();
      }
    } catch (e) {
      debugPrint('Error refrescando sesión para Supabase message sync ($roomId): $e');
    }

    // Solo iniciar el stream real-time si hay conectividad
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((result) => result == ConnectivityResult.none)) {
      debugPrint('Supabase: Offline, no se inició el stream de mensajes para sala $roomId.');
      return;
    }

    final subscription = client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .listen((data) {
          debugPrint('Supabase: Actualización en tiempo real de mensajes en sala $roomId recibida.');
          for (var json in data) {
            if (json['id'] == null) {
              debugPrint('Supabase Real-time: Posible evento de eliminación sin ID.');
              continue;
            }
            final message = ChatMessage.fromJson(json);

            // Verificar si hay un mensaje local pendiente de alguna operación para evitar sobrescribir
            final existingLocalMsg = _getChatMessageFromObjectBox(message.supabaseId);
            if (existingLocalMsg != null &&
                (existingLocalMsg.isSent == false || // Mensaje pendiente de envío inicial
                 existingLocalMsg.isUpdatePending == true || // Mensaje con edición/reacción pendiente
                 existingLocalMsg.isDeletePending == true || // Mensaje pendiente de eliminación
                 existingLocalMsg.isReadPending == true // Mensaje pendiente de lectura
                )) {
              debugPrint('ObjectBox: Ignorando mensaje remoto ${message.supabaseId} por tener operaciones locales pendientes.');
              continue; // No sobrescribir si hay una operación local en curso
            }
            _saveChatMessage(message); // Guarda/Actualiza el mensaje en ObjectBox
          }
        }, onError: (error) {
          debugPrint('Error en el stream de Supabase real-time de mensajes para sala $roomId: $error');
        });
    _activeMessageStreams[roomId] = subscription;
    debugPrint('Supabase: Iniciada sincronización de mensajes para sala $roomId.');
  }

  void stopListeningToRoomMessages(String roomId) {
    _activeMessageStreams[roomId]?.cancel();
    _activeMessageStreams.remove(roomId);
    debugPrint('Supabase: Detenida sincronización de mensajes para sala $roomId.');
  }

  Stream<List<ChatMessage>> getMessagesStream(String roomId) {
    return _chatMessageBox.query(ChatMessage_.roomId.equals(roomId))
        .watch(triggerImmediately: true)
        .map((query) {
          final messages = query.find().where((msg) => !msg.isDeletePending).toList(); // Filtrar mensajes pendientes de eliminación
          messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          debugPrint('ObjectBox: Emitiendo ${messages.length} mensajes para la sala $roomId desde el almacén local.');
          return messages;
        });
  }

  Future<void> sendMessage(
    String roomId,
    String content, {
    String type = 'text',
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderId,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('Usuario no autenticado para enviar mensaje.');
    }

    final tempSupabaseId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$userId';
    final optimisticMessage = ChatMessage(
      supabaseId: tempSupabaseId,
      roomId: roomId,
      senderId: userId,
      content: content,
      messageType: type,
      createdAt: DateTime.now(),
      isRead: false,
      replyToMessageId: replyToMessageId,
      replyToContent: replyToContent,
      replyToSenderId: replyToSenderId,
      isSent: false, // ¡Marcado como no enviado para el Outbox!
    );
    _saveChatMessage(optimisticMessage);
    debugPrint('ObjectBox: Mensaje añadido optimista con ID temporal: $tempSupabaseId (pendiente de envío)');

    // El OutboxSyncService se encargará de enviarlo cuando haya red
    _outboxSyncService.syncAllPendingOperations();
  }

  Future<void> updateMessageReaction(String messageSupabaseId, String emoji) async {
    final localMessage = _getChatMessageFromObjectBox(messageSupabaseId);
    if (localMessage != null) {
      _saveChatMessage(localMessage.copyWith(reaction: () => emoji, isUpdatePending: true)); // Marcar como pendiente
      debugPrint('ObjectBox: Reacción actualizada optimista para mensaje $messageSupabaseId (pendiente de sync).');
      _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar
    } else {
      debugPrint('ObjectBox: Mensaje $messageSupabaseId no encontrado para actualizar reacción.');
    }
  }

  Future<void> markMessagesAsRead(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return;

    final unreadMessages = _chatMessageBox.query(
      ChatMessage_.roomId.equals(roomId)
      .and(ChatMessage_.senderId.notEquals(userId))
      .and(ChatMessage_.isRead.equals(false))
      .and(ChatMessage_.isReadPending.equals(false)) // No marcar si ya está pendiente
    ).build().find();

    for (var msg in unreadMessages) {
      // Marcar como leído y pendiente de sincronización
      _saveChatMessage(msg.copyWith(isRead: true, isReadPending: true));
    }
    debugPrint('ObjectBox: Marcados ${unreadMessages.length} mensajes como leídos optimista en sala $roomId (pendientes de sync).');
    _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar
  }


  // Deprecado. Usar fijarMensajeOffline
  @deprecated
  Future<void> pinMessage(String roomId, String messageSupabaseId) async {
    final userId = currentUserId;
    if (userId == null) return;
    await fijarMensajeOffline(roomId: roomId, userId: userId, messageId: messageSupabaseId);
  }

  // Deprecado. Usar fijarMensajeOffline con messageId = null
  @deprecated
  Future<void> unpinMessage(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return;
    await fijarMensajeOffline(roomId: roomId, userId: userId, messageId: null);
  }

  Future<void> deleteRoom(String roomId) async {
    // 1. Marcar la sala y sus contenidos como pendientes de eliminación en ObjectBox
    final localRoom = _chatRoomBox.query(ChatRoom_.supabaseId.equals(roomId)).build().findFirst();
    if (localRoom != null) {
      _saveChatRoom(localRoom.copyWith(isDeletePending: true)); // Marcar sala para eliminación
      debugPrint('ObjectBox: Sala $roomId marcada para eliminación (pendiente de sync).');
    }

    final messagesInRoom = _chatMessageBox.query(ChatMessage_.roomId.equals(roomId)).build().find();
    for (var msg in messagesInRoom) {
      _saveChatMessage(msg.copyWith(isDeletePending: true)); // Marcar mensajes para eliminación
    }
    debugPrint('ObjectBox: Mensajes en sala $roomId marcados para eliminación (pendiente de sync).');

    final pinsInRoom = _chatPinnedMessageBox.query(ChatPinnedMessage_.roomId.equals(roomId)).build().find();
    for (var pin in pinsInRoom) {
      // Para unpin, usamos la convención 'null_unpin' y se marcará como no sincronizado
      _chatPinnedMessageBox.put(pin.copyWith(messageId: 'null_unpin', isSynced: false));
      debugPrint('ObjectBox: Pin local para sala $roomId marcado para desfijar.');
    }

    _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar
  }


  Future<void> updateMessage(String messageSupabaseId, String newContent) async {
    final localMessage = _getChatMessageFromObjectBox(messageSupabaseId);
    if (localMessage != null) {
      _saveChatMessage(localMessage.copyWith(content: newContent, isUpdatePending: true)); // Marcar como pendiente
      debugPrint('ObjectBox: Contenido de mensaje $messageSupabaseId actualizado optimista (pendiente de sync).');
      _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar
    } else {
      debugPrint('ObjectBox: Mensaje $messageSupabaseId no encontrado para actualizar contenido.');
    }
  }

  Future<void> deleteMessage(String messageSupabaseId) async {
    final localMessage = _getChatMessageFromObjectBox(messageSupabaseId);
    if (localMessage != null) {
      _saveChatMessage(localMessage.copyWith(isDeletePending: true)); // Marcar como pendiente de eliminación
      debugPrint('ObjectBox: Mensaje $messageSupabaseId marcado para eliminación (pendiente de sync).');
      _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar
    } else {
      debugPrint('ObjectBox: Mensaje $messageSupabaseId no encontrado para eliminación.');
    }
  }

  Future<String?> uploadMedia(
    Uint8List bytes,
    String fileName, {
    required String roomId,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }

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
    final response = await client.storage.from('temporary_media').uploadBinary(path, bytes);
    
    // Supabase returns the path, then you get public URL
    final publicUrl = client.storage.from('temporary_media').getPublicUrl(path);
    debugPrint('Media uploaded to: $publicUrl');
    return publicUrl;
  }

  Future<AuthResponse> signUpWithProfile(
    String email,
    String password, {
    String? nombre,
  }) async {
    final response = await client.auth.signUp(email: email, password: password);
    if (response.user != null) {
      final profileData = {
        'id': response.user?.id,
        'nombre': nombre ?? email.split('@')[0],
        'preferencia_canal': 1,
      };
      await client.from('profiles').insert(profileData);
      _saveUserProfile(UserProfile.fromJson(profileData));
    }
    _ensureSupabaseSyncListeners();
    _outboxSyncService.syncAllPendingOperations();
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
      final userId = response.user!.id;
      final existingProfile = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (existingProfile == null) {
        final newProfileData = {
          'id': userId,
          'nombre': email.split('@')[0],
          'preferencia_canal': 1,
        };
        await client.from('profiles').insert(newProfileData);
        _saveUserProfile(UserProfile.fromJson(newProfileData));
      } else {
        _saveUserProfile(UserProfile.fromJson(existingProfile));
      }

      try {
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await updateFcmToken(token);
        }
      } catch (e) {
        debugPrint('Error obteniendo FCM Token tras Login: $e');
      }
    }
    _ensureSupabaseSyncListeners();
    _outboxSyncService.syncAllPendingOperations();
    return response;
  }

  Future<void> updateAvatar(Uint8List bytes, String fileName) async {
    final userId = currentUserId;
    if (userId == null) {
      return;
    }

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

    final localProfile = _getUserProfileFromObjectBox(userId);
    if (localProfile != null) {
      _saveUserProfile(localProfile.copyWith(avatarUrl: publicUrl));
      debugPrint('ObjectBox: Avatar_url actualizado para perfil $userId.');
    }
    // No se considera una operación Outbox ya que es una subida de archivo y actualización de perfil,
    // que generalmente requiere conectividad y se completa inmediatamente.
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

    // Actualizar ObjectBox primero y marcar como pendiente
    final localRoom = _chatRoomBox.query(ChatRoom_.supabaseId.equals(roomId)).build().findFirst();
    if (localRoom != null) {
      // Obtener la URL del wallpaper para actualizar localmente
      String? wallpaperUrl;
      try {
        final wallpaperData = await client
            .from('chat_wallpapers')
            .select('url')
            .eq('id', wallpaperId)
            .single();
        wallpaperUrl = wallpaperData['url'] as String?;
      } catch (e) {
        debugPrint('Error al obtener URL del wallpaper para ObjectBox: $e');
      }

      _saveChatRoom(localRoom.copyWith(
        backgroundImageUrl: wallpaperUrl,
        isUpdatePending: true, // Marcar como pendiente de sincronización
      ));
      debugPrint('ObjectBox: Fondo de chat actualizado para la sala $roomId localmente (pendiente de sync).');
    }

    _outboxSyncService.syncAllPendingOperations(); // Intentar sincronizar
  }

  Future<Map<String, dynamic>?> getActiveChatBackground(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final localRoom = _chatRoomBox.query(ChatRoom_.supabaseId.equals(roomId)).build().findFirst();
    if (localRoom != null && localRoom.backgroundImageUrl != null) {
      debugPrint('ObjectBox: Fondo de chat recuperado de la caché local.');
      return {'url': localRoom.backgroundImageUrl};
    }

    // Si no está en ObjectBox o está vacío, intentar de Supabase
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

      final wallpaperUrl = wallpaperData['url'] as String?;
      if (localRoom != null && wallpaperUrl != null) {
        _saveChatRoom(localRoom.copyWith(backgroundImageUrl: wallpaperUrl));
      }
      return wallpaperData;
    } catch (e) {
      debugPrint('Error al recuperar fondo activo de Supabase: $e');
      return null;
    }
  }

  Future<String?> generateDynamicToken() async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }
    // Requiere conexión para generar tokens seguros
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
    // Requiere conexión para validar tokens y crear salas
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
      final otherUser = UserProfile.fromJson(otherProfileData);
      final chatRoom = ChatRoom.fromJson(
        roomData,
        otherUser: otherUser,
      );
      _saveUserProfile(otherUser);
      _saveChatRoom(chatRoom);
      return chatRoom;
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
    final otherUser = UserProfile.fromJson(otherProfileData);
    final chatRoom = ChatRoom.fromJson(
      newRoomData,
      otherUser: otherUser,
    );
    _saveUserProfile(otherUser);
    _saveChatRoom(chatRoom);
    return chatRoom;
  }
}

extension Let<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}