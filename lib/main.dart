import 'package:shared_preferences/shared_preferences.dart';
import 'package:comoteva/integrations/supabase_service.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:comoteva/globals/app_state.dart';
import 'package:comoteva/globals/router.dart';
// --- Importaciones de Firebase y Notificaciones Locales ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart'; 

import 'package:comoteva/objectbox.dart';
import 'package:comoteva/integrations/outbox_sync_service.dart'; // Asegúrate de importar OutboxSyncService

// Quitamos la anotación de Nowa para asegurar persistencia real en la compilación externa
late final SharedPreferences sharedPrefs;

ObjectBox? objectbox;

// 🔥 CONFIGURACIÓN DEL CANAL DE EMERGENCIA
const AndroidNotificationChannel emergencyChannel = AndroidNotificationChannel(
  'high_importance_channel', 
  'Alertas de Emergencia',     
  description: 'Canal utilizado para notificaciones críticas y de alta prioridad.',
  importance: Importance.max,  
  playSound: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// FUNCIÓN GLOBAL PARA MANEJAR EL CLIC
void _handleNotificationClick(Map<String, dynamic> data) {
  final roomId = data['room_id'];
  if (roomId != null) {
    debugPrint('Redirigiendo automáticamente a la sala: $roomId');
    appRouter.go('/chat/$roomId'); 
  }
}

// CONTROLADOR DE SEGUNDO PLANO
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Notificación recibida en segundo plano: ${message.notification?.title}");
}


@NowaGenerated()
main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sharedPrefs = await SharedPreferences.getInstance();
  
  objectbox = await ObjectBox.create();
  
  // Inicialización de las bases de datos
  await SupabaseService().initialize();
  
  // Inicializa Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. REGISTRAR EL CANAL DE EMERGENCIA EN EL TELÉFONO
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(emergencyChannel);

  // Configuraciones del icono nativo
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher'); 
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
      
  // 🔥 FIRMA ESTABLE DE LA VERSIÓN 17.x: Recibe el objeto directo sin nombres caprichosos
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // VINCULAR EL CONTROLADOR DE SEGUNDO PLANO
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Solicitás los permisos para las notificaciones (FCM)
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  
  // 4. CONTROLAR PRIMER PLANO (Firma posicional clásica y estable)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Notificación recibida en primer plano: ${message.notification?.title}');
    
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            emergencyChannel.id,
            emergencyChannel.name,
            channelDescription: emergencyChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: android.smallIcon,
          ),
        ),
      );
    }
  });
  
  
    // 5. CONTROLAR CLIC CON APP EN SEGUNDO PLANO (ABIERTA RECIENTEMENTE)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationClick(message.data);
  });

  // 6. CONTROLAR CLIC CON APP TOTALMENTE CERRADA (TERMINATED STATE)
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationClick(initialMessage.data);
  }
  
  // En tu main.dart, al final del método main()
  
  // 🔥 ACTIVAR COLA DE SALIDA OFFLINE
  // FIX: No necesitas una variable local para el singleton, se accede directamente a la instancia.
  // final outboxService = OutboxSyncService(); // <--- ELIMINAR ESTA LÍNEA

  // Inicializamos el escucha de la cola de salida
  OutboxSyncService().listenToConnectionChanges(); // FIX: Acceso correcto al singleton

  // Forzar una sincronización inicial por si quedaron pendientes de la sesión anterior
  OutboxSyncService().syncAllPendingOperations(); // FIX: Método renombrado a syncAllPendingOperations

  // 🚀 LLEGAMOS AL RUNAPP
  runApp(const MyApp());
}

@NowaGenerated({'visibleInNowa': false})
class MyApp extends StatelessWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(create: (context) => AppState()),
      ],
      builder: (context, child) {
        final appState = AppState.of(context);
        return MaterialApp.router(
          theme: appState.theme,
          routerConfig: appRouter,
          builder: (context, child) => AnimatedTheme(
            data: appState.theme,
            duration: const Duration(milliseconds: 500),
            child: child!,
          ),
        );
      },
    );
  }
}