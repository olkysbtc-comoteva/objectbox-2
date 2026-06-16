import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class AppConfig {
  AppConfig({
    required this.appName,
    required this.version,
    this.email,
    this.website,
    this.logo,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      appName: json['nombre_app2'] as String,
      version: json['version'] as String,
      email: json['correo'] as String?,
      website: json['sitio_web'] as String?,
      logo: json['logo'] as String?,
    );
  }

  final String appName;

  final String version;

  final String? email;

  final String? website;

  final String? logo;

  Map<String, dynamic> toJson() {
    return {
      'nombre_app2': appName,
      'version': version,
      'correo': email,
      'sitio_web': website,
      'logo': logo,
    };
  }
}
