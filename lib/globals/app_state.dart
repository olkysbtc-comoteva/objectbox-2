import 'package:flutter/material.dart';
import 'package:comoteva/app_theme_mode.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:comoteva/app_theme.dart';
import 'package:provider/provider.dart';
// Importamos el main para poder leer la variable global sharedPrefs
import 'package:comoteva/main.dart'; 

@NowaGenerated()
class AppState extends ChangeNotifier {
  // CORRECCIÓN: Al instanciar el estado, leemos inmediatamente el string guardado
  AppState() {
    _cargarTemaPersistente();
  }

  factory AppState.of(BuildContext context, {bool listen = true}) {
    return Provider.of<AppState>(context, listen: listen);
  }

  AppThemeMode _currentThemeMode = AppThemeMode.amoled;

  AppThemeMode get currentThemeMode {
    return _currentThemeMode;
  }

  ThemeData get theme {
    switch (_currentThemeMode) {
      case AppThemeMode.light:
        return AppTheme.lightTheme;
      case AppThemeMode.amoled:
        return AppTheme.amoledTheme;
      case AppThemeMode.plus:
        return AppTheme.plusTheme;
    }
  }

  String? _currentChatWallpaper;

  String? get currentChatWallpaper {
    return _currentChatWallpaper;
  }

  // Método interno para recuperar la configuración física al arrancar
  void _cargarTemaPersistente() {
    try {
      final String? savedTheme = sharedPrefs.getString('tema_seleccionado');
      if (savedTheme != null) {
        _currentThemeMode = AppThemeMode.values.firstWhere(
          (e) => e.toString() == savedTheme,
          orElse: () => AppThemeMode.amoled,
        );
        // No es necesario llamar a notifyListeners() aquí porque se ejecuta 
        // en el constructor antes de que el árbol de widgets se dibuje.
      }
    } catch (e) {
      debugPrint('Error al leer el tema persistente: $e');
    }
  }

  // CORRECCIÓN: Ahora guarda en caliente cada cambio de tema
  void setTheme(AppThemeMode mode) {
    _currentThemeMode = mode;
    notifyListeners();

    try {
      sharedPrefs.setString('tema_seleccionado', mode.toString());
      debugPrint('Tema $mode guardado con éxito en disco duro.');
    } catch (e) {
      debugPrint('Error al persistir el cambio de tema: $e');
    }
  }

  void setChatWallpaper(String? assetPath) {
    _currentChatWallpaper = assetPath;
    notifyListeners();
  }
}
