import 'dart:async'; // NUEVO: Importar para StreamSubscription
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
import 'package:cached_network_image/cached_network_image.dart';

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
  final TextEditingController _messageController = TextEditingController();
  static const Color amberPremium = Color(0xFFD4AF37);

  static const String _fontStorageKey = 'chat_bubble_font_size';
  double _fontSizeBurbuja = 16.0;
  double _scaleStartFontSize = 16.0;

  String? _contactName;
  bool _isLoadingName = false;

  ChatMessage? _replyingToMessage; // Mensaje al que se está respondiendo
  ChatMessage? _pinnedMessage;     // NUEVO: Mensaje fijado
  StreamSubscription? _pinnedMessageSubscription; // NUEVO: Suscripción para el mensaje fijado

  // NUEVO: Mapa para almacenar GlobalKeys por message.id para el scroll
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    _cargarPreferenciaTamano();

    if (widget.chatRoom != null) {
      _contactName = widget.chatRoom?.otherUser?.displayName;
    } else {
      _fetchContactDetails();
    }

    // NUEVO: Inicializar suscripción a mensajes fijados
    _pinnedMessageSubscription = SupabaseService()
        .getPinnedMessageStream(widget.roomId)
        .listen((message) {
      if (mounted) {
        setState(() {
          _pinnedMessage = message;
        });
      }
    }, onError: (error) {
      debugPrint('Error en el stream de mensajes fijados: $error');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final appState = AppState.of(context, listen: false);
        String? initialBackgroundUrl = widget.chatRoom?.backgroundImageUrl;

        if (initialBackgroundUrl != null && initialBackgroundUrl.isNotEmpty) {
          appState.setChatWallpaper(initialBackgroundUrl);
          debugPrint('Fondo inicial establecido desde ChatRoom: $initialBackgroundUrl');
        } else {
          final fondoActivo = await SupabaseService().getActiveChatBackground(widget.roomId);
          if (fondoActivo != null && mounted) {
            appState.setChatWallpaper(fondoActivo['url'] as String?);
            debugPrint('Fondo activo establecido desde Supabase: ${fondoActivo['url']}');
          } else {
            final fondos = await SupabaseService().getAvailableWallpapers();
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
    _pinnedMessageSubscription?.cancel(); // NUEVO: Cancelar suscripción del mensaje fijado
    super.dispose();
  }

  Future<void> _fetchContactDetails() async {
    if (!mounted) return;
    setState(() => _isLoadingName = true);

    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;

      if (currentUserId == null) throw Exception("Usuario no autenticado");

      final data = await supabase
          .from('room_members')
          .select('profiles:user_id(nombre)')
          .eq('room_id', widget.roomId)
          .neq('user_id', currentUserId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (data != null && data['profiles'] != null) {
            _contactName = data['profiles']['nombre'] ?? 'Usuario';
          } else {
            _contactName = "Chat";
          }
          _isLoadingName = false;
        });
      }
    } catch (e) {
      debugPrint('Error al traer datos del contacto de Supabase: $e');
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

      await Supabase.instance.client.storage
          .from('temporary_media')
          .uploadBinary(
            'gifs/$nombreArchivo',
            contenido.data!,
          );

      final String urlPublicaFinal = Supabase.instance.client.storage
          .from('temporary_media')
          .getPublicUrl('gifs/$nombreArchivo');

      // Modificado para incluir datos de respuesta si existe
      await SupabaseService().sendMessage(
        widget.roomId,
        urlPublicaFinal,
        type: 'gif',
        replyToMessageId: _replyingToMessage?.id,
        replyToContent: _replyingToMessage?.content,
        replyToSenderId: _replyingToMessage?.senderId,
      );
      _messageController.clear();
      setState(() {
        _replyingToMessage = null; // Limpiar estado de respuesta
      });
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
    final isMe = message.senderId == SupabaseService().currentUserId;
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
        title: const Text('Responder mensaje'), // Cambiado de "Reenviar mensaje"
        onTap: () {
          Navigator.pop(context);
          setState(() {
            _replyingToMessage = message; // Establecer el mensaje al que se responde
          });
          // Desplazarse al final para mostrar la barra de respuesta
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
      ),
    ];

    // NUEVO: Opciones de fijar/desfijar
    if (_pinnedMessage?.id == message.id) {
      options.add(
        ListTile(
          leading: const Icon(Icons.push_pin_outlined, color: Colors.red),
          title: const Text('Desfijar mensaje'),
          onTap: () async {
            Navigator.pop(context);
            await SupabaseService().unpinMessage(widget.roomId);
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
            await SupabaseService().pinMessage(widget.roomId, message.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mensaje fijado.')),
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
                  onDelete: (messageId) async {
                    await SupabaseService().deleteMessage(messageId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mensaje eliminado.')),
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
            await SupabaseService().deleteMessage(message.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mensaje eliminado para todos.')),
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
                await SupabaseService().updateMessageReaction(message.id, emoji);
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
                await SupabaseService().updateMessage(
                  message.id,
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
            if (message.replyToMessageId != null) ...[ // Mostrar info de respuesta
              const SizedBox(height: 8),
              const Text('Respondiendo a:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('  - Contenido: ${message.replyToContent ?? 'N/A'}'),
              Text('  - Remitente ID: ${message.replyToSenderId ?? 'N/A'}'),
            ],
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

  // NUEVO: Helper para mostrar el contenido del mensaje respondido/fijado
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

  // Widget para la previsualización del mensaje respondido en la barra de entrada
  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    String replySenderName;
    if (_replyingToMessage!.senderId == SupabaseService().currentUserId) {
      replySenderName = 'Tú';
    } else if (_replyingToMessage!.senderId == widget.chatRoom?.otherUser?.id) {
      replySenderName = _contactName ?? 'Usuario';
    } else {
      replySenderName = 'Usuario'; // Fallback para casos no esperados en 1-a-1
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
                  14.0, // Tamaño de fuente para la vista previa
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withOpacity(0.6)),
            onPressed: () {
              setState(() {
                _replyingToMessage = null; // Limpiar estado de respuesta
              });
            },
          ),
        ],
      ),
    );
  }

  // NUEVO: Widget para la barra de mensaje fijado
  Widget _buildPinnedMessageBanner() {
  if (_pinnedMessage == null) return const SizedBox.shrink();

  final theme = Theme.of(context);
  // Color de ámbar/oro premium unificado
  const Color premiumAmber = Color(0xFFD4AF37); 

  String pinnedSenderName;
  if (_pinnedMessage!.senderId == SupabaseService().currentUserId) {
    pinnedSenderName = 'Tú';
  } else if (_pinnedMessage!.senderId == widget.chatRoom?.otherUser?.id) {
    pinnedSenderName = _contactName ?? 'Usuario';
  } else {
    pinnedSenderName = 'Usuario';
  }

  return ClipRect(
    child: GestureDetector(
      onTap: () {
        final key = _messageKeys[_pinnedMessage!.id];
        if (key != null && key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            alignment: 0.5,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
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
                // Fondo oscuro translúcido para dar buen contraste
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
                      await SupabaseService().unpinMessage(widget.roomId);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Mensaje desfijado.')),
                        );
                      }
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

    return Scaffold(
      appBar: AppBar(
        title: _isLoadingName
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
              )
            : Text(
                _contactName ?? widget.chatRoom?.otherUser?.displayName ?? 'Chat',
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
                              future: SupabaseService().getAvailableWallpapers(),
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
                                        await SupabaseService().updateChatBackground(widget.roomId, wpId);
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
                // NUEVO: Banner de mensaje fijado, visible solo si hay un mensaje fijado
                if (_pinnedMessage != null) _buildPinnedMessageBanner(),

                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: SupabaseService().getMessagesStream(widget.roomId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final messages = snapshot.data;

                      return NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification notification) {
                          if (notification.metrics.pixels < -60 && notification is ScrollUpdateNotification) {
                            HapticFeedback.lightImpact();
                            SupabaseService().markMessagesAsRead(widget.roomId);
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
                          itemCount: messages?.length ?? 0,
                          itemBuilder: (context, index) {
                            final message = messages![index];
                            final isMe = message.senderId == SupabaseService().currentUserId;
                            final isVideo = message.messageType == 'video';
                            final isImage = message.messageType == 'image';
                            final isGif = message.messageType == 'gif';
                            final isMedia = isImage || isVideo || isGif;
                            final localTime = message.createdAt.toLocal();
                            final tieneReaccion = message.reaction != null && message.reaction!.isNotEmpty;
                            final esLeido = message.isRead ?? false;

                            // Almacenar la GlobalKey para este mensaje
                            _messageKeys[message.id] = GlobalKey();

                            // Lógica para el nombre del remitente del mensaje respondido
                            String? originalReplySenderName;
                            if (message.replyToSenderId != null) {
                              if (message.replyToSenderId == SupabaseService().currentUserId) {
                                originalReplySenderName = 'Tú';
                              } else if (message.replyToSenderId == widget.chatRoom?.otherUser?.id) {
                                originalReplySenderName = _contactName ?? 'Usuario';
                              } else {
                                originalReplySenderName = 'Usuario'; // Fallback
                              }
                            }

                                                        return Align(
                              key: _messageKeys[message.id], // Asignar la GlobalKey
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
                                        // 1. CAMBIO PREMIUM: Burbujas translúcidas adaptables al tema activo
                                        color: isMe 
                                            ? theme.primaryColor.withOpacity(0.75) // Tus mensajes (azul o coral Plus suave)
                                            : Colors.black.withOpacity(0.68),       // Mensajes del otro usuario (cristal oscuro neutro)
                                        borderRadius: BorderRadius.circular(18),
                                        // 2. BORDE ULTRA FINO: Evita que la burbuja se pierda en texturas complejas de fondo
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
                                          // Previsualización del mensaje respondido
                                          // Previsualización del mensaje respondido (Optimizado para legibilidad)
if (message.replyToMessageId != null && message.replyToContent != null)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      // MEJORA: Aumentamos el contraste del fondo de la cajita de respuesta
      color: isMe
          ? Colors.white.withOpacity(0.18) // Un poco más claro si es tu burbuja
          : Colors.black.withOpacity(0.35), // Un poco más oscuro si es la burbuja del otro
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
            // MEJORA: Blanco pleno para tus burbujas, o el color del tema bien nítido para el otro
            color: isMe ? Colors.white : (theme.brightness == Brightness.dark ? theme.primaryColor : theme.primaryColor.withRed(255)),
            fontSize: _fontSizeBurbuja * 0.85,
          ),
        ),
        const SizedBox(height: 4),
        // LLAMADO A LA VISTA PREVIA DEL CONTENIDO
        _buildContentPreview(
          message.replyToContent!,
          message.messageType, 
          // MEJORA CLAVE: Forzamos un blanco/gris muy claro para que el texto de fondo no se pierda jamás
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
                                                  height: 150, // Altura placeholder
                                                  width: 150,
                                                  color: Colors.grey[300],
                                                  child: const Center(child: CircularProgressIndicator()),
                                                ),
                                                errorWidget: (context, url, error) => Container(
                                                  height: 150, // Altura placeholder
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
                                                // Ajustamos el color para que siempre sea legible en tus burbujas o las del otro
                                                color: isMe ? Colors.white : theme.colorScheme.onSurface,
                                                fontSize: _fontSizeBurbuja,
                                              ),
                                              child: Text(message.content),
                                            ),
                                          const SizedBox(height: 4), // Un poquito más de aire antes de la hora
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                DateFormat('HH:mm').format(localTime),
                                                style: TextStyle(
                                                  // El texto de la hora se adapta al contraste translúcido
                                                  color: isMe ? Colors.white.withOpacity(0.65) : theme.colorScheme.onSurface.withOpacity(0.5),
                                                  fontSize: 10,
                                                ),
                                              ),
                                              if (isMe) ...[
                                                const SizedBox(width: 4),
                                                Icon(
                                                  esLeido ? Icons.done_all : Icons.done,
                                                  size: 14,
                                                  // Si es leído brilla en blanco puro, si no, se atenúa sutilmente
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
                                            // MEJORA PREMIUM: Reacción translúcida tipo píldora de cristal
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
                // Mostrar la previsualización de respuesta si hay un mensaje para responder
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
          final publicUrl = await SupabaseService().uploadMedia(
            bytes,
            file.name,
            roomId: widget.roomId,
          );

          if (publicUrl != null) {
            await SupabaseService().sendMessage(
              widget.roomId,
              publicUrl,
              type: type,
              replyToMessageId: _replyingToMessage?.id,
              replyToContent: _replyingToMessage?.content,
              replyToSenderId: _replyingToMessage?.senderId,
            );
            setState(() {
              _replyingToMessage = null; // Limpiar estado de respuesta
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
          // Si hay un mensaje para responder, envía los datos de respuesta
          SupabaseService().sendMessage(
            widget.roomId,
            texto,
            replyToMessageId: _replyingToMessage!.id,
            replyToContent: _replyingToMessage!.content,
            replyToSenderId: _replyingToMessage!.senderId,
          );
          setState(() {
            _replyingToMessage = null; // Limpiar el mensaje al que se responde
          });
        } else {
          // Si no, envía un mensaje normal
          SupabaseService().sendMessage(widget.roomId, texto);
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
                  onDelete(message.id);
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