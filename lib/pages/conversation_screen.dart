import 'dart:async';
// Importa tu archivo main para que las pantallas reconozcan la variable global
import 'package:comoteva/main.dart';

import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:comoteva/integrations/supabase_service.dart';
import 'package:comoteva/models/chat_room.dart';
import 'package:comoteva/models/chat_message.dart';
import 'package:comoteva/globals/app_state.dart';
import 'package:cached_network_image/cached_network_image.dart'; // CORREGIDO: Importación correcta

import 'package:comoteva/objectbox.g.dart'; // Asegúrate de importar esto
import 'package:objectbox/objectbox.dart'; // Importa esto para usar Order, etc.


class ConversationScreen extends StatefulWidget {
  final String roomId;
  final ChatRoom? chatRoom;

  const ConversationScreen({
    super.key,
    required this.roomId,
    this.chatRoom,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<ChatMessage?> _pinnedMessageNotifier = ValueNotifier<ChatMessage?>(null);
  final TextEditingController _messageController = TextEditingController();
  static const Color amberPremium = Color(0xFFD4AF37);


  static const String _fontStorageKey = 'chat_bubble_font_size';
  double _fontSizeBurbuja = 16.0;
  double _scaleStartFontSize = 16.0;

  String? _contactName;
  bool _isLoadingName = false;

  ChatMessage? _replyingToMessage;
  ChatMessage? _pinnedMessage; // Actualizado directamente por el stream
  StreamSubscription? _pinnedMessageSubscription;

  final Map<String, GlobalKey> _messageKeys = {};

  final SupabaseService _supabaseService = SupabaseService(); // Usar instancia del singleton

  void _inicializarStreamFijado() {
    _pinnedMessageSubscription?.cancel();

    if (objectbox == null) return;

    final roomBox = objectbox!.store.box<ChatRoom>();
    final messageBox = objectbox!.store.box<ChatMessage>();

    // SOLUCIÓN: Eliminamos el .build() para mantener el QueryBuilder y poder usar .watch()
    final roomQueryBuilder = roomBox.query(ChatRoom_.supabaseId.equals(widget.roomId));

    // .watch() se invoca sobre el QueryBuilder, construye la consulta internamente y emite el stream
    _pinnedMessageSubscription = roomQueryBuilder
    .watch(triggerImmediately: true)
    .map((query) => query.find()) // Transforma la Query en List<ChatRoom> ejecutando .find()
    .listen((List<ChatRoom> roomsList) {
      ChatRoom? room;
      if (roomsList.isNotEmpty) {
        room = roomsList.first;
      }
      ChatMessage? localPinnedMessage;

      if (room?.pinnedMessageId != null) {
        final msgQuery = (messageBox.query(ChatMessage_.supabaseId.equals(room!.pinnedMessageId!))).build();
        localPinnedMessage = msgQuery.findFirst();
        msgQuery.close();
      }

      if (!mounted) return;

      setState(() {
        _pinnedMessage = localPinnedMessage;
        _pinnedMessageNotifier.value = localPinnedMessage;
      });
    }, onError: (error) {
      debugPrint('Error en el stream local de mensajes fijados: $error');
    });
  }



  @override
  void initState() {
    super.initState();
    _cargarPreferenciaTamano();

    _inicializarStreamFijado();

    // Iniciar la escucha de mensajes para esta sala a través de SupabaseService
    _supabaseService.startListeningToRoomMessages(widget.roomId);

    if (widget.chatRoom != null) {
      _contactName = widget.chatRoom?.otherUser.target?.displayName; // Acceso a ToOne
    } else {
      _fetchContactDetails();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final appState = AppState.of(context, listen: false);
        String? initialBackgroundUrl = widget.chatRoom?.backgroundImageUrl;

        if (initialBackgroundUrl != null && initialBackgroundUrl.isNotEmpty) {
          appState.setChatWallpaper(initialBackgroundUrl);
          debugPrint('Fondo inicial establecido desde ChatRoom: $initialBackgroundUrl');
        } else {
          final fondoActivo = await _supabaseService.getActiveChatBackground(widget.roomId); // Usar _supabaseService
          if (fondoActivo != null && mounted) {
            appState.setChatWallpaper(fondoActivo['url'] as String?);
            debugPrint('Fondo activo establecido desde Supabase/ObjectBox: ${fondoActivo['url']}');
          } else {
            final fondos = await _supabaseService.getAvailableWallpapers(); // Usar _supabaseService
            if (fondos.isNotEmpty && mounted && appState.currentChatWallpaper == null) {
              appState.setChatWallpaper(fondos.first['url'] as String?);
              debugPrint('Fondo por defecto establecido: ${fondos.first['url']}');
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _pinnedMessageSubscription?.cancel();
    _pinnedMessageNotifier.dispose();
    _supabaseService.stopListeningToRoomMessages(widget.roomId); // Detener la escucha al salir
    super.dispose();
  }

  Future<void> _fetchContactDetails() async {
    if (!mounted) return;
    setState(() => _isLoadingName = true);

    try {
      final currentUserId = _supabaseService.currentUserId; // Usar _supabaseService

      if (currentUserId == null) throw Exception("Usuario no autenticado");

      // Intenta obtener la sala desde el stream de ObjectBox (que es actualizado por Supabase)
      final roomFromService = await _supabaseService.getMyRoomsStream()
          .firstWhere((rooms) => rooms.any((r) => r.supabaseId == widget.roomId)) // Usar supabaseId
          .then((rooms) => rooms.firstWhere((r) => r.supabaseId == widget.roomId, orElse: () => throw Exception('Room not found'))); // Usar supabaseId

      if (mounted) {
        setState(() {
          _contactName = roomFromService.otherUser.target?.displayName ?? "Chat"; // Acceso a ToOne
          _isLoadingName = false;
        });
      }
    } catch (e) {
      debugPrint('Error al traer datos del contacto de Supabase/ObjectBox: $e');
      if (mounted) {
        setState(() {
          _contactName = "Chat";
          _isLoadingName = false;
        });
      }
    }
  }

  Future<void> _cargarPreferenciaTamano() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getDouble(_fontStorageKey);
      if (guardado != null && mounted) {
        setState(() {
          _fontSizeBurbuja = guardado;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar tamaño de letra: $e');
    }
  }

  Future<void> _guardarPreferenciaTamano(double nuevoTamano) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_fontStorageKey, nuevoTamano);
    } catch (e) {
      debugPrint('Error al guardar tamaño de letra: $e');
    }
  }

  Future<void> _sendKeyboardGif(KeyboardInsertedContent contenido) async {
    if (!mounted) return;

    try {
      final String nombreArchivo = 'gif_${DateTime.now().millisecondsSinceEpoch}.gif';

      final String? publicUrlFinal = await _supabaseService.uploadMedia( // Usar _supabaseService
        contenido.data!,
        nombreArchivo,
        roomId: widget.roomId,
      );

      if (publicUrlFinal != null) {
        await _supabaseService.sendMessage( // Usar _supabaseService
          widget.roomId,
          publicUrlFinal,
          type: 'gif',
          replyToMessageId: _replyingToMessage?.supabaseId, // Usar supabaseId
          replyToContent: _replyingToMessage?.content,
          replyToSenderId: _replyingToMessage?.senderId,
        );
        _messageController.clear();
        setState(() {
          _replyingToMessage = null;
        });
      } else {
        throw Exception("Fallo al obtener URL pública para el GIF");
      }
    } catch (error) {
      debugPrint("Error al procesar o subir el GIF del teclado: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo enviar el GIF del teclado")),
        );
      }
    }
  }

  Future<void> _downloadMediaFile(String url, String type) async {
    HapticFeedback.lightImpact();

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      double progresoActual = 0.0;
      final theme = Theme.of(context);

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        value: progresoActual,
                        strokeWidth: 5,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Guardando $type...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text('${(progresoActual * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final extension = type.toLowerCase() == 'video' ? 'mp4' : (type.toLowerCase() == 'gif' ? 'gif' : 'jpg');
      final tempPath = '${tempDir.path}/comoteva_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await dio.download(
        url,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            final double calculo = received / total;
            try {
              (context as Element).visitChildren((Element child) {
                if (child is StatefulElement && child.state is Object) {
                  child.state.setState(() {
                    progresoActual = calculo;
                  });
                }
              });
            } catch (_) {}
          }
        },
      );

      if (type.toLowerCase() == 'video') {
        await Gal.putVideo(tempPath);
      } else {
        await Gal.putImage(tempPath);
      }

      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$type guardado en la galería con éxito'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo completar la descarga'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      debugPrint('Error en la descarga real: $e');
    }
  }

  void _onMessageTap(ChatMessage message) {
    // Aquí recuperas el ID del usuario actual de tu servicio
    final currentUserId = _supabaseService.currentUserId;
    final isMe = message.senderId == currentUserId;
    final isVideo = message.messageType == 'video';
    final isImage = message.messageType == 'image';
    final isGif = message.messageType == 'gif';
    final isMedia = isImage || isVideo || isGif;
    final theme = Theme.of(context);

    List<Widget> options = [
      ListTile(
        leading: const Icon(Icons.info_outline, color: Colors.blue),
        title: const Text('Información del mensaje'),
        onTap: () {
          Navigator.pop(context);
          _showMsgInfo(message);
        },
      ),
      ListTile(
        leading: const Icon(Icons.reply, color: Colors.green),
        title: const Text('Responder mensaje'),
        onTap: () {
          Navigator.pop(context);
          setState(() {
            _replyingToMessage = message;
          });
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
      ),
    ];

    if (_pinnedMessage?.supabaseId == message.supabaseId) {
      options.add(
        ListTile(
          leading: const Icon(Icons.push_pin_outlined, color: Colors.red),
          title: const Text('Desfijar mensaje'),
          onTap: () async {
            Navigator.pop(context);

            // 1. Limpieza visual inmediata en pantalla (UI Optimista)
            setState(() {
              _pinnedMessage = null;
              _pinnedMessageNotifier.value = null;
            });

            // 2. Ejecución offline-first enviando messageId como null para remover el pin
            if (currentUserId != null) {
              await _supabaseService.fijarMensajeOffline(
  roomId: widget.roomId,
  userId: currentUserId,
  messageId: null, // Indicar desfijar
);

            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mensaje desfijado.')),
              );
            }
          },
        ),
      );
    } else {
      options.add(
        ListTile(
          leading: const Icon(Icons.push_pin, color: Colors.amber),
          title: const Text('Fijar mensaje'),
          onTap: () async {
            Navigator.pop(context);

            // 1. UI OPTIMISTIC: Mostramos el mensaje fijado al instante en la app
            if (mounted) {
              setState(() {
                _pinnedMessage = message;
                _pinnedMessageNotifier.value = message;
              });
              debugPrint('🎨 UI OPTIMISTIC: Mostrando nuevo mensaje fijado al instante');
            }

            // 2. Persistencia local garantizada. Si está offline o el mensaje aún no se subió,
            // se almacena en ObjectBox de forma segura sin disparar errores en la interfaz.
            if (currentUserId != null) {
              await _supabaseService.fijarMensajeOffline(
  roomId: widget.roomId,
  userId: currentUserId,
  messageId: message.supabaseId,
);
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mensaje fijado con éxito.')),
              );
            }
          },
        ),
      );
    }


    if (isMedia) {
      options.add(
        ListTile(
          leading: Icon(Icons.fullscreen, color: theme.primaryColor),
          title: Text(isVideo ? 'Ver Video' : (isGif ? 'Ver GIF' : 'Ver Imagen')),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MediaPreviewScreen(
                  message: message,
                  onDownload: _downloadMediaFile,
                  onDelete: (messageSupabaseId) async {
                    await _supabaseService.deleteMessage(messageSupabaseId); // Usar _supabaseService
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mensaje marcado para eliminación.')),
                      );
                    }
                  },
                ),
              ),
            );
          },
        ),
      );
      options.add(
        ListTile(
          leading: const Icon(Icons.download, color: Colors.purple),
          title: const Text('Descargar a la galería'),
          onTap: () {
            Navigator.pop(context);
            _downloadMediaFile(message.content, isVideo ? 'Video' : (isGif ? 'GIF' : 'Imagen'));
          },
        ),
      );
    } else if (isMe && message.messageType == 'text') {
      options.add(
        ListTile(
          leading: const Icon(Icons.edit, color: Colors.orange),
          title: const Text('Editar mensaje'),
          onTap: () {
            Navigator.pop(context);
            _showEditDialog(message);
          },
        ),
      );
    }

    if (isMe) {
      options.add(
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('Eliminar para todos'),
          onTap: () async {
            Navigator.pop(context);
            await _supabaseService.deleteMessage(message.supabaseId); // CORREGIDO: Usar supabaseId
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mensaje marcado para eliminación.')),
              );
            }
          },
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => SafeArea(
        child: Wrap(
          children: options,
        ),
      ),
    );
  }

  void _onMessageLongPress(ChatMessage message) {
    HapticFeedback.mediumImpact();
    final listaEmojis = ['👍', '🧉', '😂', '🤔', '😎', '🤭'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Reaccionar', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: listaEmojis.map((emoji) {
            return GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                await _supabaseService.updateMessageReaction(message.supabaseId, emoji); // CORREGIDO: Usar supabaseId
              },
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showEditDialog(ChatMessage message) {
    final editController = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar mensaje'),
        content: TextField(controller: editController, maxLines: null),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              if (editController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _supabaseService.updateMessage( // Usar _supabaseService
                  message.supabaseId, // CORREGIDO: Usar supabaseId
                  editController.text.trim(),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showMsgInfo(ChatMessage message) {
    final localTime = message.createdAt.toLocal();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalles'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enviado: ${DateFormat('dd/MM/yyyy HH:mm').format(localTime)}'),
            const SizedBox(height: 8),
            Text('Tipo: ${message.messageType}'),
            const SizedBox(height: 8),
            Text('Estado: ${message.isRead == true ? "Leído" : "Entregado"}'),
            if (message.replyToMessageId != null) ...[
              const SizedBox(height: 8),
              const Text('Respondiendo a:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('  - Contenido: ${message.replyToContent ?? 'N/A'}'),
              Text('  - Remitente ID: ${message.replyToSenderId ?? 'N/A'}'),
            ],
            // Mostrar los estados de sincronización pendientes
            Text('Sincronizado: ${message.isSent ? "Sí" : "No (pendiente)"}'),
            if (message.isUpdatePending) Text('Actualización Pendiente: Sí'),
            if (message.isDeletePending) Text('Eliminación Pendiente: Sí'),
            if (message.isReadPending) Text('Lectura Pendiente: Sí'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildContentPreview(String content, String messageType, Color textColor, double fontSize) {
    if (content.startsWith('http')) {
      if (messageType == 'image') {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image, size: fontSize * 0.9, color: textColor),
            const SizedBox(width: 4),
            Text('Imagen', style: TextStyle(fontSize: fontSize * 0.9, color: textColor)),
          ],
        );
      } else if (messageType == 'video') {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library, size: fontSize * 0.9, color: textColor),
            const SizedBox(width: 4),
            Text('Video', style: TextStyle(fontSize: fontSize * 0.9, color: textColor)),
          ],
        );
      } else if (messageType == 'gif') {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gif_box, size: fontSize * 0.9, color: textColor),
            const SizedBox(width: 4),
            Text('GIF', style: TextStyle(fontSize: fontSize * 0.9, color: textColor)),
          ],
        );
      }
    }
    return Text(
      content,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: fontSize, color: textColor),
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    String replySenderName;
    if (_replyingToMessage!.senderId == _supabaseService.currentUserId) { // Usar _supabaseService
      replySenderName = 'Tú';
    } else if (widget.chatRoom?.otherUser.target?.supabaseId != null && _replyingToMessage!.senderId == widget.chatRoom?.otherUser.target?.supabaseId) { // CORREGIDO: Usar supabaseId y verificación de nulo
      replySenderName = _contactName ?? 'Usuario';
    } else {
      replySenderName = 'Usuario';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.9),
        border: Border(left: BorderSide(color: theme.primaryColor, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respondiendo a ${replySenderName}',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                _buildContentPreview(
                  _replyingToMessage!.content,
                  _replyingToMessage!.messageType,
                  theme.colorScheme.onSurface.withOpacity(0.8),
                  14.0,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withOpacity(0.6)),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedMessageBanner() {
    if (_pinnedMessage == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    const Color premiumAmber = Color(0xFFD4AF37);

    String pinnedSenderName;
    if (_pinnedMessage!.senderId == _supabaseService.currentUserId) { // Usar _supabaseService
      pinnedSenderName = 'Tú';
    } else if (widget.chatRoom?.otherUser.target?.supabaseId != null && _pinnedMessage!.senderId == widget.chatRoom?.otherUser.target?.supabaseId) { // CORREGIDO: Usar supabaseId y verificación de nulo
      pinnedSenderName = _contactName ?? 'Usuario';
    } else {
      pinnedSenderName = 'Usuario';
    }

    return ClipRect(
      child: GestureDetector(
        onTap: () {
          final key = _messageKeys[_pinnedMessage!.supabaseId]; // CORREGIDO: Usar supabaseId
          if (key != null && key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              alignment: 0.5,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          } else {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mensaje fijado no visible, desplazando...')),
              );
            }
          }
        },
        child: Container(
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8, top: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: premiumAmber.withOpacity(0.8),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.push_pin, color: premiumAmber, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Mensaje fijado',
                            style: const TextStyle(
                              color: premiumAmber,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _buildContentPreview(
                            _pinnedMessage!.content,
                            _pinnedMessage!.messageType,
                            Colors.white.withOpacity(0.85),
                            13.0,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white.withOpacity(0.6), size: 18),
                      onPressed: () async {
                        HapticFeedback.lightImpact();

                        // 1. Limpieza visual inmediata
                        setState(() {
                          _pinnedMessageNotifier.value = null;
                          _pinnedMessage = null;
                        });

                        // 2. Persistencia local garantizada + intento remoto silencioso
                        await _supabaseService.fijarMensajeOffline(
                          roomId: widget.roomId,
                          userId: _supabaseService.currentUserId ?? '', // Acceso directo al getter global del servicio
                          messageId: null, // Indicar desfijar
                        );

                      },
                    ),

                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.of(context);
    final theme = Theme.of(context);

    // 🔥 VALIDACIÓN ANTICRASH DINÁMICA: Evita la pantalla blanca si entran antes de cargar ObjectBox
    if (objectbox == null) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface, // Usa el fondo exacto de tu app
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary), // Tu color principal
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _isLoadingName
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
              )
            : Text(
                _contactName ?? widget.chatRoom?.otherUser.target?.displayName ?? 'Chat', // Acceso a ToOne
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.8),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
            onSelected: (value) {
              if (value == 'wallpaper') {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: theme.colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (context) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'Seleccionar Fondo Dinámico',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Divider(),
                          SizedBox(
                            height: 160,
                            child: FutureBuilder<List<Map<String, dynamic>>>(
                              future: _supabaseService.getAvailableWallpapers(), // Usar _supabaseService
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                final wallpapers = snapshot.data ?? [];
                                if (wallpapers.isEmpty) {
                                  return const Center(child: Text('No hay fondos disponibles'));
                                }
                                return ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: wallpapers.length,
                                  itemBuilder: (context, index) {
                                    final wallpaper = wallpapers[index];
                                    final wpUrl = wallpaper['url'] as String? ?? '';
                                    final wpId = wallpaper['id'] as int;

                                    return GestureDetector(
                                      onTap: () async {
                                        appState.setChatWallpaper(wpUrl);
                                        await _supabaseService.updateChatBackground(widget.roomId, wpId); // Usar _supabaseService
                                        if (context.mounted) Navigator.pop(context);
                                      },
                                      child: Container(
                                        width: 100,
                                        margin: const EdgeInsets.only(right: 12, bottom: 20),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: theme.dividerColor),
                                          image: wpUrl.isNotEmpty
                                              ? DecorationImage(
                                                  image: NetworkImage(wpUrl),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                          color: Colors.grey,
                                        ),
                                        child: wpUrl.isEmpty
                                            ? const Center(child: Icon(Icons.image_not_supported, color: Colors.white24))
                                            : null,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'wallpaper',
                child: Row(
                  children: [
                    Icon(Icons.wallpaper, size: 20),
                    SizedBox(width: 12),
                    Text('Fondo dinámico'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      body: GestureDetector(
        onScaleStart: (details) {
          _scaleStartFontSize = _fontSizeBurbuja;
        },
        onScaleUpdate: (details) {
          setState(() {
            double calculado = _scaleStartFontSize * details.scale;
            _fontSizeBurbuja = calculado.clamp(13.0, 26.0);
          });
        },
        onScaleEnd: (details) {
          _guardarPreferenciaTamano(_fontSizeBurbuja);
        },
        child: Stack(
          children: [
            if (appState.currentChatWallpaper != null && appState.currentChatWallpaper!.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(appState.currentChatWallpaper!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            Column(
              children: [
                ValueListenableBuilder<ChatMessage?>(
  valueListenable: _pinnedMessageNotifier,
  builder: (context, pinnedMessage, child) {
    if (pinnedMessage == null) return const SizedBox.shrink();
    return _buildPinnedMessageBanner();
  },
),
Expanded(
  child: StreamBuilder<List<ChatMessage>>(
    // SOLUCIÓN: Eliminamos .build() y llamamos directamente a .watch() desde el query builder
    stream: objectbox!.store
        .box<ChatMessage>()
        .query(ChatMessage_.roomId.equals(widget.roomId))
        .order(ChatMessage_.createdAt, flags: Order.descending)
        .watch(triggerImmediately: true) // .watch() va directo aquí sin .build()
        .map((queryResult) => queryResult.find()), // Mapea el flujo para extraer List<ChatMessage>
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final messages = snapshot.data ?? [];

      return NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.metrics.pixels < -60 && notification is ScrollUpdateNotification) {
            HapticFeedback.lightImpact();
            _supabaseService.markMessagesAsRead(widget.roomId); 
          }
          return false;
        },
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMe = message.senderId == _supabaseService.currentUserId;
                            final isVideo = message.messageType == 'video';
                            final isImage = message.messageType == 'image';
                            final isGif = message.messageType == 'gif';
                            final isMedia = isImage || isVideo || isGif;
                            final localTime = message.createdAt.toLocal();
                            final tieneReaccion = message.reaction != null && message.reaction!.isNotEmpty;
                            final esLeido = message.isRead ?? false;

                            _messageKeys[message.supabaseId] = GlobalKey();

                            String? originalReplySenderName;
                            if (message.replyToSenderId != null) {
                              if (message.replyToSenderId == _supabaseService.currentUserId) {
                                originalReplySenderName = 'Tú';
                              } else if (widget.chatRoom?.otherUser.target?.supabaseId != null && message.replyToSenderId == widget.chatRoom?.otherUser.target?.supabaseId) {
                                originalReplySenderName = _contactName ?? 'Usuario';
                              } else {
                                originalReplySenderName = 'Usuario';
                              }
                            }

                            // No mostrar mensajes marcados para eliminación
                            if (message.isDeletePending) return const SizedBox.shrink();

                            return Align(
                              key: _messageKeys[message.supabaseId],
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () {
                                  _onMessageTap(message);
                                },
                                onLongPress: () => _onMessageLongPress(message),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      margin: EdgeInsets.only(bottom: tieneReaccion ? 16 : 8),
                                      padding: isMedia ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(14, 8, 10, 6),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? theme.primaryColor.withOpacity(0.75)
                                            : Colors.black.withOpacity(0.68),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: isMe
                                              ? theme.primaryColor.withOpacity(0.6)
                                              : Colors.white.withOpacity(0.15),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (message.replyToMessageId != null && message.replyToContent != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              margin: const EdgeInsets.only(bottom: 6),
                                              decoration: BoxDecoration(
                                                color: isMe
                                                    ? Colors.white.withOpacity(0.18)
                                                    : Colors.black.withOpacity(0.35),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border(
                                                  left: BorderSide(
                                                    color: isMe ? Colors.white70 : theme.primaryColor,
                                                    width: 3,
                                                  ),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    originalReplySenderName ?? 'Usuario',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: isMe ? Colors.white : (theme.brightness == Brightness.dark ? theme.primaryColor : theme.primaryColor.withRed(255)),
                                                      fontSize: _fontSizeBurbuja * 0.85,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  _buildContentPreview(
                                                    message.replyToContent!,
                                                    message.messageType,
                                                    isMe ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.8),
                                                    _fontSizeBurbuja * 0.9,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (isImage || isGif)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(14),
                                              child: CachedNetworkImage(
                                                imageUrl: message.content,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Container(
                                                  height: 150,
                                                  width: 150,
                                                  color: Colors.grey[300],
                                                  child: const Center(child: CircularProgressIndicator()),
                                                ),
                                                errorWidget: (context, url, error) => Container(
                                                  height: 150,
                                                  width: 150,
                                                  color: Colors.grey[300],
                                                  child: const Center(child: Icon(Icons.error)),
                                                ),
                                              ),
                                            ),
                                          if (isVideo)
                                            Container(
                                              height: 180,
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: const Center(
                                                child: Icon(Icons.video_library, color: Colors.white, size: 50),
                                              ),
                                            ),
                                          if (!isMedia)
                                            AnimatedDefaultTextStyle(
                                              duration: const Duration(milliseconds: 100),
                                              curve: Curves.easeOutCubic,
                                              style: TextStyle(
                                                color: isMe ? Colors.white : theme.colorScheme.onSurface,
                                                fontSize: _fontSizeBurbuja,
                                              ),
                                              child: Text(message.content),
                                            ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isMe && !message.isSent) ...[
                                                const Icon(Icons.access_time, size: 14, color: Colors.white54),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                DateFormat('HH:mm').format(localTime),
                                                style: TextStyle(
                                                  color: isMe ? Colors.white.withOpacity(0.65) : theme.colorScheme.onSurface.withOpacity(0.5),
                                                  fontSize: 10,
                                                ),
                                              ),
                                              if (isMe && message.isSent) ...[
                                                const SizedBox(width: 4),
                                                Icon(
                                                  esLeido ? Icons.done_all : Icons.done,
                                                  size: 14,
                                                  color: esLeido ? Colors.white : Colors.white.withOpacity(0.5),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (tieneReaccion)
                                      Positioned(
                                        bottom: -(_fontSizeBurbuja * 0.4),
                                        right: isMe ? null : 12,
                                        left: isMe ? 12 : null,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: _fontSizeBurbuja * 0.45,
                                            vertical: _fontSizeBurbuja * 0.15,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(_fontSizeBurbuja * 0.7),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.12),
                                              width: 0.8,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black38,
                                                blurRadius: 4,
                                                offset: Offset(0, 2),
                                              )
                                            ],
                                          ),
                                          child: Text(
                                            message.reaction!,
                                            style: TextStyle(
                                              fontSize: _fontSizeBurbuja + 2.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                if (_replyingToMessage != null) _buildReplyPreview(),
                _buildChatBar(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBar() {
    final theme = Theme.of(context);
    final picker = ImagePicker();

    Future<void> _adjuntarMultimedia(ImageSource source, String type) async {
      try {
        final XFile? file = type == 'video'
            ? await picker.pickVideo(source: source)
            : await picker.pickImage(source: source, imageQuality: 75);

        if (file != null) {
          final bytes = await file.readAsBytes();
          final publicUrl = await _supabaseService.uploadMedia( // Usar _supabaseService
            bytes,
            file.name,
            roomId: widget.roomId,
          );

          if (publicUrl != null) {
            await _supabaseService.sendMessage( // Usar _supabaseService
              widget.roomId,
              publicUrl,
              type: type,
              replyToMessageId: _replyingToMessage?.supabaseId, // Usar supabaseId
              replyToContent: _replyingToMessage?.content,
              replyToSenderId: _replyingToMessage?.senderId,
            );
            setState(() {
              _replyingToMessage = null;
            });
          }
        }
      } catch (e) {
        debugPrint('Error al adjuntar archivo: $e');
      }
    }

    void _procesarEnvio() {
      final texto = _messageController.text.trim();
      if (texto.isNotEmpty) {
        if (_replyingToMessage != null) {
          _supabaseService.sendMessage( // Usar _supabaseService
            widget.roomId,
            texto,
            replyToMessageId: _replyingToMessage!.supabaseId, // Usar supabaseId
            replyToContent: _replyingToMessage!.content,
            replyToSenderId: _replyingToMessage!.senderId,
          );
          setState(() {
            _replyingToMessage = null;
          });
        } else {
          _supabaseService.sendMessage(widget.roomId, texto); // Usar _supabaseService
        }
        _messageController.clear();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.add, color: theme.primaryColor, size: 26),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: theme.colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (context) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.image, color: Colors.blue),
                          title: const Text('Enviar Imagen (Galería)'),
                          onTap: () {
                            Navigator.pop(context);
                            _adjuntarMultimedia(ImageSource.gallery, 'image');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.camera_alt, color: Colors.green),
                          title: const Text('Tomar Foto (Cámara)'),
                          onTap: () {
                            Navigator.pop(context);
                            _adjuntarMultimedia(ImageSource.camera, 'image');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.video_library, color: Colors.red),
                          title: const Text('Enviar Video'),
                          onTap: () {
                            Navigator.pop(context);
                            _adjuntarMultimedia(ImageSource.gallery, 'video');
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _procesarEnvio(),
                  decoration: const InputDecoration(
                    hintText: 'Mensaje',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  contentInsertionConfiguration: ContentInsertionConfiguration(
                    allowedMimeTypes: const <String>['image/gif'],
                    onContentInserted: (KeyboardInsertedContent content) {
                      _sendKeyboardGif(content);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.send, color: theme.primaryColor),
              onPressed: _procesarEnvio,
            ),
          ],
        ),
      ),
    );
  }
}

class MediaPreviewScreen extends StatelessWidget {
  final ChatMessage message;
  final Future<void> Function(String, String) onDownload;
  final Future<void> Function(String) onDelete;

  const MediaPreviewScreen({
    super.key,
    required this.message,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = message.messageType.toLowerCase() == 'video';
    final isGif = message.messageType.toLowerCase() == 'gif';
    final isMe = message.senderId == SupabaseService().currentUserId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          isVideo ? 'Video' : (isGif ? 'GIF' : 'Imagen'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, size: 26),
            onPressed: () => onDownload(message.content, isVideo ? 'Video' : (isGif ? 'GIF' : 'Imagen')),
            tooltip: 'Descargar a la galería',
          ),
          if (isMe)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 26, color: Colors.redAccent),
              onPressed: () async {
                final confirmDelete = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar mensaje'),
                    content: const Text('¿Estás seguro de que quieres eliminar este mensaje para todos?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );
                if (confirmDelete == true) {
                  onDelete(message.supabaseId); // Usar supabaseId
                  Navigator.of(context).pop();
                }
              },
              tooltip: 'Eliminar para todos',
            ),
        ],
      ),
      body: Center(
        child: isVideo
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.video_library, color: Colors.white60, size: 80),
                  const SizedBox(height: 20),
                  const Text(
                    'Previsualización de Video',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.download, color: Colors.white),
                    label: const Text(
                      'Descargar para reproducir',
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () => onDownload(message.content, 'Video'),
                  ),
                ],
              )
            : InteractiveViewer(
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: message.content,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) {
                    return const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white38, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No se pudo cargar el medio',
                          style: TextStyle(color: Colors.white38),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}