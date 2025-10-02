# BLE Fake App

Simulación BLE con desaparición/aparición, notificaciones locales y trazabilidad A→B. Punto inicial fijo en Viña del Mar.

## Estructura
- lib/
  - main.dart
  - ble_fake_maps.dart
  - clases.dart
  - services/local_notifications.dart
  - screens/nearby_witnesses_page.dart
- pubspec.yaml

## Cómo correr localmente
1. Instala Flutter (3.22+)
2. En una carpeta local, coloca este proyecto (`ble_fake_app/`).
3. Dentro de `ble_fake_app/` ejecuta:
```bash
flutter create .
flutter pub get
flutter run -d <ID_DISPOSITIVO>
```

## Android (opcional) sonido personalizado
- Coloca `pii.wav` en `android/app/src/main/res/raw/` y usa un canal con ese sonido.

## Notas
- Si tu build pide NDK 27, en `android/app/build.gradle(.kts)` usa:
```
android {
  ndkVersion = "27.0.12077973"
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    coreLibraryDesugaringEnabled true
  }
}

dependencies {
  coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.2"
}
```