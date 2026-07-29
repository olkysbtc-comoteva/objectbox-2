import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:comoteva/main.dart';
import 'package:comoteva/models/chat_message.dart';
import 'package:comoteva/models/chat_pinned_message.dart'; // Importación corregida
import 'package:comoteva/models/chat_room.dart'; // Importar ChatRoom
import 'package:comoteva/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:objectbox/objectbox.dart'; // Asegúrate de importar esto

class OutboxSyncService {
  static final OutboxSyncService _instance = OutboxSyncService._internal();
  factory OutboxSyncService() => _instance;
  OutboxSyncService._internal();

  bool _isSyncing = false;

  void listenToConnectionChanges() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      if (results.any((result) => result != ConnectivityResult.none)) {
        debugPrint('🌐 [Outbox] Conectividad física detectada. Esperando estabilización...');

        await Future.delayed(const Duration(seconds: 2));

        if (await _hasActualInternet()) {
          debugPrint('🚀 [Outbox] Internet real verificado. Iniciando sincronización...');
          syncAllPendingOperations(); // Cambiado a un método más general
        } else {
          debugPrint('⏳ [Outbox] Conectado a la red pero sin acceso real a internet aún.');
        }
      }
    });
  }

  Future<bool> _hasActualInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      // FIX: Acceder al primer elemento de la lista para obtener 'rawAddress'
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  /// Sincroniza todas las operaciones pendientes (mensajes, pines, ediciones, borrados, etc.)
  Future<void> syncAllPendingOperations() async {
    if (_isSyncing || objectbox == null) {
      debugPrint('🚫 [Outbox] Sincronización ya en curso o ObjectBox no inicializado. Abortando.');
      return;
    }
    _isSyncing = true;
    debugPrint('🚦 [Outbox] Iniciando ciclo completo de sincronización...');

    try {
      // Orden de prioridad: Mensajes nuevos > Actualizaciones > Recibos de lectura > Pines > Borrados
      // Los pines deben sincronizarse después de los mensajes a los que hacen referencia.
      // Las eliminaciones deben ser lo último para evitar referencias rotas temporalmente.
      await _syncPendingMessages();
      await _syncPendingMessageUpdates();
      await _syncPendingReactions(); // Las reacciones también son actualizaciones
      await _syncPendingReadReceipts();
      await _syncPendingRoomUpdates();
      await _syncPendingPins();
      await _syncPendingMessageDeletions();
      await _syncPendingRoomDeletions();

      debugPrint('✅ [Outbox] Ciclo completo de sincronización terminado.');
    } catch (generalError) {
      debugPrint('❌ [Outbox] Error general en el ciclo de sincronización: $generalError');
    } finally {
      _isSyncing = false;
    }
  }

  // Sincroniza la subida inicial de mensajes
  Future<void> _syncPendingMessages() async {
    final messageBox = objectbox!.store.box<ChatMessage>();
    final query = (messageBox.query(ChatMessage_.isSent.equals(false))).build();
    final pendingMessages = query.find();
    query.close();

    if (pendingMessages.isEmpty) {
      debugPrint('✨ [Outbox Msgs] No hay nuevos mensajes pendientes de envío.');
      return;
    }

    debugPrint('📦 [Outbox Msgs] Encontrados ${pendingMessages.length} mensajes pendientes de envío.');

    for (var message in pendingMessages) {
      try {
        await Supabase.instance.client
            .from('messages')
            .insert(message.toJson());

        messageBox.put(message.copyWith(isSent: true)); // Marcar como enviado
        debugPrint('✅ [Outbox Msgs] Mensaje enviado: ${message.supabaseId}');
      } catch (supabaseError) {
        debugPrint('❌ [Outbox Msgs] Error de red/servidor subiendo mensaje ${message.supabaseId}: $supabaseError');
        // Si hay un error de red, asumimos que los siguientes también fallarán y detenemos
        break;
      }
    }
  }

  // Sincroniza actualizaciones de contenido o reacciones de mensajes
  Future<void> _syncPendingMessageUpdates() async {
    final messageBox = objectbox!.store.box<ChatMessage>();
    // Buscamos mensajes con isUpdatePending a true
    final query = (messageBox.query(ChatMessage_.isUpdatePending.equals(true))).build();
    final pendingUpdates = query.find();
    query.close();

    if (pendingUpdates.isEmpty) {
      debugPrint('✨ [Outbox Msg Updates] No hay mensajes pendientes de actualización de contenido/reacción.');
      return;
    }

    debugPrint('🔄 [Outbox Msg Updates] Encontrados ${pendingUpdates.length} mensajes pendientes de actualización.');

    for (var message in pendingUpdates) {
      try {
        await Supabase.instance.client
            .from('messages')
            .update({
              'content': message.content, // Actualizar contenido
              'reaction': message.reaction, // Actualizar reacción
              'is_update_pending': false, // Se establece a false en la BD
            })
            .eq('id', message.supabaseId);

        messageBox.put(message.copyWith(isUpdatePending: false)); // Marcar como sincronizado localmente
        debugPrint('✅ [Outbox Msg Updates] Mensaje actualizado: ${message.supabaseId}');
      } catch (supabaseError) {
        debugPrint('❌ [Outbox Msg Updates] Error actualizando mensaje ${message.supabaseId}: $supabaseError');
        break;
      }
    }
  }

  // Sincroniza solo las reacciones pendientes (como parte de las actualizaciones)
  Future<void> _syncPendingReactions() async {
    final messageBox = objectbox!.store.box<ChatMessage>();
    // FIX PARA ERROR 1: Asumiendo que `reaction` es `String?` en el modelo y `objectbox.g.dart` está actualizado.
    // Si `reaction` es `String` (no nullable) en tu modelo `ChatMessage`, elimina `.isNotNull()`.
    final query = (messageBox.query(
      ChatMessage_.reaction.notNull() // `isNotNull()` debería funcionar si `reaction` es `String?`
          .and(ChatMessage_.reaction.notEquals(''))
          .and(ChatMessage_.isUpdatePending.equals(true)) // Reacciones pendientes se marcan con isUpdatePending
    )).build();
    final pendingReactions = query.find();
    query.close();

    if (pendingReactions.isEmpty) {
      debugPrint('✨ [Outbox Reactions] No hay reacciones pendientes de envío.');
      return;
    }

    debugPrint('👍 [Outbox Reactions] Encontradas ${pendingReactions.length} reacciones pendientes.');

    for (var message in pendingReactions) {
      try {
        // Asumimos que el message.reaction ya tiene el valor actualizado
        await Supabase.instance.client
            .from('messages')
            .update({
              'reaction': message.reaction,
              'is_update_pending': false, // Marcar como no pendiente en la BD
            })
            .eq('id', message.supabaseId);

        messageBox.put(message.copyWith(isUpdatePending: false)); // Marcar como sincronizado localmente
        debugPrint('✅ [Outbox Reactions] Reacción sincronizada: ${message.supabaseId}');
      } catch (supabaseError) {
        debugPrint('❌ [Outbox Reactions] Error sincronizando reacción de ${message.supabaseId}: $supabaseError');
        break;
      }
    }
  }


  // Sincroniza actualizaciones de estado de lectura
  Future<void> _syncPendingReadReceipts() async {
    final messageBox = objectbox!.store.box<ChatMessage>();
    // Buscamos mensajes que están marcados como leídos localmente Y tienen isReadPending
    final query = (messageBox.query(
      ChatMessage_.isRead.equals(true)
          .and(ChatMessage_.isReadPending.equals(true))
    )).build();
    final pendingReadReceipts = query.find();
    query.close();

    if (pendingReadReceipts.isEmpty) {
      debugPrint('✨ [Outbox ReadReceipts] No hay estados de lectura pendientes.');
      return;
    }

    debugPrint('👁️ [Outbox ReadReceipts] Encontrados ${pendingReadReceipts.length} recibos de lectura pendientes.');

    // Agrupar por room_id para una sola llamada si es posible o optimizar
    final Map<String, List<String>> roomMessagesToMark = {};
    for (var msg in pendingReadReceipts) {
      roomMessagesToMark.putIfAbsent(msg.roomId, () => []).add(msg.supabaseId);
    }

    for (var entry in roomMessagesToMark.entries) {
      final roomId = entry.key;
      final messageIds = entry.value;

      try {
        // FIX PARA ERROR 2: Usar `.filter('column', 'in', valueList)` para el operador IN
        await Supabase.instance.client
            .from('messages')
            .update({'is_read': true, 'is_read_pending': false}) // También actualizar is_read_pending en la BD
            .filter('id', 'in', messageIds);

        // Una vez actualizado en Supabase, marcamos localmente como no pendiente
        for (var id in messageIds) {
          final msg = pendingReadReceipts.firstWhere((m) => m.supabaseId == id);
          messageBox.put(msg.copyWith(isReadPending: false));
        }
        debugPrint('✅ [Outbox ReadReceipts] Marcados ${messageIds.length} mensajes como leídos en sala $roomId.');
      } catch (supabaseError) {
        debugPrint('❌ [Outbox ReadReceipts] Error marcando mensajes como leídos en sala $roomId: $supabaseError');
        break;
      }
    }
  }


  // Sincroniza eliminaciones de mensajes
  Future<void> _syncPendingMessageDeletions() async {
    final messageBox = objectbox!.store.box<ChatMessage>();
    final query = (messageBox.query(ChatMessage_.isDeletePending.equals(true))).build();
    final pendingDeletions = query.find();
    query.close();

    if (pendingDeletions.isEmpty) {
      debugPrint('✨ [Outbox Msg Deletions] No hay mensajes pendientes de eliminación.');
      return;
    }

    debugPrint('🗑️ [Outbox Msg Deletions] Encontrados ${pendingDeletions.length} mensajes pendientes de eliminación.');

    for (var message in pendingDeletions) {
      try {
        await Supabase.instance.client
            .from('messages')
            .delete()
            .eq('id', message.supabaseId);

        messageBox.remove(message.obxId); // Eliminar localmente después de borrar de Supabase
        debugPrint('✅ [Outbox Msg Deletions] Mensaje eliminado: ${message.supabaseId}');
      } catch (supabaseError) {
        debugPrint('❌ [Outbox Msg Deletions] Error eliminando mensaje ${message.supabaseId}: $supabaseError');
        // Si el error es de conexión, detenemos para no reintentar fallidamente
        break;
      }
    }
  }

  /// Proceso aislado para sincronizar los pines rezagados
  Future<void> _syncPendingPins() async {
    final pinBox = objectbox!.store.box<ChatPinnedMessage>();
    final pendingPinsQuery = (pinBox.query(ChatPinnedMessage_.isSynced.equals(false))).build();
    final pendingPins = pendingPinsQuery.find();
    pendingPinsQuery.close();

    if (pendingPins.isEmpty) {
      debugPrint('✨ [Outbox Pins] No hay pines pendientes de sincronización.');
      return;
    }
    debugPrint('📌 [Outbox Pins] Encontrados ${pendingPins.length} pines pendientes.');

    for (var pin in pendingPins) {
      try {
        // Validamos si el mensaje asociado ya se subió.
        // Si el messageId es 'null_unpin', es una operación de desfijar.
        if (pin.messageId != 'null_unpin') {
          final messageBox = objectbox!.store.box<ChatMessage>();
          final msgQuery = (messageBox.query(ChatMessage_.supabaseId.equals(pin.messageId))).build();
          final associatedMsg = msgQuery.findFirst();
          msgQuery.close();

          // Si el mensaje asociado aún existe localmente y *no está enviado*, postergar este pin.
          // Si el mensaje ya no existe localmente (porque se borró optimista y no se subió), el pin es inválido y se elimina de la cola.
          if (associatedMsg != null && !associatedMsg.isSent) {
            debugPrint('⏳ [Outbox Pin] Postergado: El mensaje asociado (${pin.messageId}) aún no se subió.');
            continue; // Pasa al siguiente pin
          } else if (associatedMsg == null || associatedMsg.isDeletePending) {
             debugPrint('⚠️ [Outbox Pin] El mensaje asociado (${pin.messageId}) no existe o está pendiente de eliminación. Eliminando pin localmente.');
             pinBox.remove(pin.obxId); // Eliminar este pin de la cola, ya no es válido
             continue; // Pasa al siguiente pin
          }
        }

        // Si el messageId es nulo o 'null_unpin', es una operación de desfijar
        if (pin.messageId == 'null_unpin') {
           await Supabase.instance.client
            .from('chat_pinned_messages')
            .delete()
            .eq('room_id', pin.roomId)
            .eq('user_id', pin.userId);
            pinBox.remove(pin.obxId); // Eliminar el pin de la cola local
            debugPrint('✅ [Outbox Pins] Pin desfijado sincronizado para sala: ${pin.roomId}');
        } else {
          // Es una operación de fijar/actualizar pin
          await Supabase.instance.client
              .from('chat_pinned_messages')
              .upsert({
                'room_id': pin.roomId,
                'user_id': pin.userId,
                'message_id': pin.messageId,
              }, onConflict: 'room_id,user_id'); // Agrega onConflict para que upsert funcione correctamente

          pinBox.put(pin.copyWith(isSynced: true));
          debugPrint('✅ [Outbox Pins] Pin fijado sincronizado para mensaje: ${pin.messageId}');
        }
      } catch (e) {
        debugPrint('❌ [Outbox Pins] Error en pin ${pin.messageId}: $e');
        break;
      }
    }
  }

  // Sincroniza actualizaciones de salas (ej. fondo de pantalla)
  Future<void> _syncPendingRoomUpdates() async {
    final roomBox = objectbox!.store.box<ChatRoom>();
    final query = (roomBox.query(ChatRoom_.isUpdatePending.equals(true))).build();
    final pendingRoomUpdates = query.find();
    query.close();

    if (pendingRoomUpdates.isEmpty) {
      debugPrint('✨ [Outbox Room Updates] No hay salas pendientes de actualización.');
      return;
    }

    debugPrint('🖼️ [Outbox Room Updates] Encontradas ${pendingRoomUpdates.length} salas pendientes de actualización.');

    for (var room in pendingRoomUpdates) {
      try {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId == null) {
          debugPrint('🚫 [Outbox Room Updates] No hay usuario autenticado para actualizar la sala.');
          break;
        }

        int? wallpaperIdToSend;
        if (room.backgroundImageUrl != null && room.backgroundImageUrl!.isNotEmpty) {
          // Intentamos obtener el wallpaperId de Supabase si tenemos la URL
          try {
            final wallpaperData = await Supabase.instance.client
                .from('chat_wallpapers')
                .select('id')
                .eq('url', room.backgroundImageUrl!)
                .maybeSingle();
            wallpaperIdToSend = wallpaperData?['id'] as int?;
          } catch (e) {
            debugPrint('Error buscando wallpaper ID para URL ${room.backgroundImageUrl}: $e');
          }
        }

        await Supabase.instance.client
            .from('room_members')
            .update({'wallpaper_id': wallpaperIdToSend, 'is_update_pending': false}) // wallpaperIdToSend puede ser nulo para borrar, y actualizar is_update_pending
            .eq('room_id', room.supabaseId)
            .eq('user_id', currentUserId);

        roomBox.put(room.copyWith(isUpdatePending: false));
        debugPrint('✅ [Outbox Room Updates] Sala actualizada (ej. fondo de pantalla): ${room.supabaseId}');
      } catch (supabaseError) {
        debugPrint('❌ [Outbox Room Updates] Error actualizando sala ${room.supabaseId}: $supabaseError');
        break;
      }
    }
  }

  // Sincroniza eliminaciones de salas
  Future<void> _syncPendingRoomDeletions() async {
    final roomBox = objectbox!.store.box<ChatRoom>();
    final messageBox = objectbox!.store.box<ChatMessage>();
    final pinBox = objectbox!.store.box<ChatPinnedMessage>();

    final query = (roomBox.query(ChatRoom_.isDeletePending.equals(true))).build();
    final pendingRoomDeletions = query.find();
    query.close();

    if (pendingRoomDeletions.isEmpty) {
      debugPrint('✨ [Outbox Room Deletions] No hay salas pendientes de eliminación.');
      return;
    }

    debugPrint('🔥 [Outbox Room Deletions] Encontradas ${pendingRoomDeletions.length} salas pendientes de eliminación.');

    for (var room in pendingRoomDeletions) {
      try {
        // Eliminar miembros de la sala
        await Supabase.instance.client.from('room_members').delete().eq('room_id', room.supabaseId);
        // Eliminar mensajes de la sala
        await Supabase.instance.client.from('messages').delete().eq('room_id', room.supabaseId);
        // Desfijar mensajes asociados (si existe la tabla)
        await Supabase.instance.client.from('chat_pinned_messages').delete().eq('room_id', room.supabaseId);
        // Finalmente, eliminar la sala
        await Supabase.instance.client.from('rooms').delete().eq('id', room.supabaseId);

        // Eliminar localmente después de borrar de Supabase
        roomBox.remove(room.obxId);
        messageBox.query(ChatMessage_.roomId.equals(room.supabaseId)).build().find().forEach((msg) => messageBox.remove(msg.obxId));
        pinBox.query(ChatPinnedMessage_.roomId.equals(room.supabaseId)).build().find().forEach((pin) => pinBox.remove(pin.obxId));

        debugPrint('✅ [Outbox Room Deletions] Sala eliminada: ${room.supabaseId}');
      } catch (supabaseError) {
        debugPrint('❌ [Outbox Room Deletions] Error eliminando sala ${room.supabaseId}: $supabaseError');
        break;
      }
    }
  }
}