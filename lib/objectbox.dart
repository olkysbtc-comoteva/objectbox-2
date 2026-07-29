// lib/objectbox.dart
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Importa el archivo generado por ObjectBox
// ¡Este archivo se creará después de que añadas las anotaciones a tus modelos y ejecutes el `build_runner`!
import 'package:comoteva/objectbox.g.dart'; // Ajusta la ruta si es necesario

class ObjectBox {
  late final Store store;

  ObjectBox._create(this.store);

  /// Crea e inicializa la tienda de ObjectBox.
  static Future<ObjectBox> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    // Asegúrate de que el modelo haya sido generado antes de esta línea.
    // Ejecuta `flutter pub run build_runner build`
    final store = await openStore(directory: p.join(docsDir.path, "obx-db"));
    return ObjectBox._create(store);
  }

  /// Cierra la tienda de ObjectBox cuando ya no sea necesaria.
  void close() {
    store.close();
  }
}