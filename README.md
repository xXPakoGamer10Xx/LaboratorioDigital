# Laboratorio Digital

![Logo](assets/Logo.jpg) Una aplicación móvil Flutter que funciona como un conjunto de herramientas interactivas y asistentes educativos impulsados por IA (Gemini), enfocados en áreas como matemáticas, física y normativas de ingeniería.

## Descripción

El Laboratorio Digital ofrece una interfaz unificada para acceder a diversas funcionalidades útiles para estudiantes y profesionales. Desde resolver problemas matemáticos y físicos con ayuda de IA hasta analizar documentos técnicos y visualizar conceptos complejos como áreas bajo curvas o movimientos físicos. La aplicación integra autenticación de usuarios y persistencia de datos en la nube para una experiencia personalizada.

## ✨ Características Principales

* **Autenticación Segura:** Registro, inicio de sesión y recuperación de contraseña mediante Firebase Authentication.
* **Dashboard Central:** Pantalla de inicio (`HomeScreen`) que actúa como punto de entrada a todas las herramientas.
* **Asistentes Expertos con IA (Gemini):**
    * **Experto en Matemáticas (`MathExpertPage`):** Chat interactivo para resolver problemas, explicar conceptos y analizar imágenes de problemas matemáticos.
    * **Experto en Física (`PhysicsExpertPage`):** Chat interactivo para resolver problemas, explicar conceptos y analizar imágenes de situaciones físicas.
    * **Experto en Normas IEEE (`IeeeGeneratorPage`):** Analiza documentos PDF subidos por el usuario y responde preguntas específicas sobre normativas IEEE.
    * **Análisis de Figuras (`ShapesPage`):** Identifica figuras geométricas (seleccionadas, descritas o en imágenes) y calcula/explica sus propiedades.
* **Herramientas de Visualización:**
    * **Visualizador de Áreas (`AreaVisualizerPage`):** Permite ingresar funciones matemáticas (`f(x)`), visualizarlas en una gráfica y calcular el área bajo la curva (integral definida aproximada).
    * **Gráficas de Movimiento (`MotionGraphPage`):** Simula y grafica la posición vs. tiempo para Movimiento Rectilíneo Uniforme (MRU), Movimiento Rectilíneo Uniformemente Acelerado (MRUA) y Caída Libre, mostrando también una animación del objeto.
* **Historial Persistente:** Guarda el historial de conversaciones con los asistentes de IA en Firebase Firestore para usuarios autenticados.
* **Manejo de Ciclo de Vida:** Implementadas correcciones para evitar problemas visuales al reanudar la app desde segundo plano.

## 🚀 Tecnologías Utilizadas

* **Framework:** Flutter
* **Lenguaje:** Dart
* **Backend & Base de Datos:** Firebase (Authentication, Firestore)
* **IA Generativa:** Google Generative AI (Gemini API via `google_generative_ai`)
* **Visualización (Gráficas):** `CustomPaint` (para `MotionGraphPage`), `fl_chart` (usado previamente en `AreaVisualizerPage`)
* **Matemáticas:** `math_expressions`, `flutter_math_fork` (para renderizar LaTeX)
* **Manejo de Archivos:** `file_picker`, `permission_handler`, `device_info_plus`
* **Otros:** `flutter_dotenv` (para claves API), `intl` (para formato de fechas), `flutter_markdown` (para renderizar respuestas de IA)

## 셋업 Configuración del Proyecto

Sigue estos pasos para configurar y ejecutar el proyecto localmente:

1.  **Prerrequisitos:**
    * Tener instalado el [Flutter SDK](https://docs.flutter.dev/get-started/install).
    * Un editor de código como [VS Code](https://code.visualstudio.com/) o [Android Studio](https://developer.android.com/studio).
    * Un emulador/simulador o dispositivo físico Android/iOS configurado.

2.  **Clonar el Repositorio:**
    ```bash
    git clone <URL_DEL_REPOSITORIO>
    cd <NOMBRE_DEL_DIRECTORIO>
    ```

3.  **Configurar Firebase:**
    * Crea un proyecto en [Firebase Console](https://console.firebase.google.com/).
    * Registra tu aplicación Flutter (Android, iOS, Web según necesites).
    * Sigue las instrucciones para añadir Firebase a tu app, lo cual generalmente implica descargar un archivo de configuración:
        * **Android:** `google-services.json` (colocar en `android/app/`).
        * **iOS:** `GoogleService-Info.plist` (colocar en `ios/Runner/` usando Xcode).
        * **Web:** Configuración en el `index.html` o usar `firebase_options.dart`.
    * El archivo `lib/firebase_options.dart` parece estar configurado principalmente para **Android** y **Web**. Asegúrate de que coincida con tu proyecto Firebase o reemplázalo con el generado por FlutterFire CLI (`flutterfire configure`).
    * Habilita los servicios que usarás en la consola de Firebase:
        * **Authentication:** Habilita el proveedor "Correo electrónico/Contraseña".
        * **Firestore:** Crea una base de datos Firestore en modo de prueba o producción (ajusta las reglas de seguridad según sea necesario).

4.  **Configurar Clave API de Gemini:**
    * Obtén una clave API para la API de Gemini desde [Google AI Studio](https://aistudio.google.com/app/apikey).
    * Crea un archivo llamado `.env` en la **raíz** de tu proyecto Flutter (al mismo nivel que `pubspec.yaml`).
    * Añade la siguiente línea al archivo `.env`, reemplazando `TU_API_KEY_AQUI` con tu clave real:
        ```env
        GEMINI_API_KEY=TU_API_KEY_AQUI
        ```
    * **Importante:** Asegúrate de que el archivo `.env` esté listado en tu `.gitignore` para no subir tu clave API a repositorios públicos.

5.  **Instalar Dependencias:**
    ```bash
    flutter pub get
    ```

6.  **Ejecutar la Aplicación:**
    ```bash
    flutter run
    ```
    Selecciona el dispositivo/emulador donde deseas ejecutarla.

## 📁 Estructura de Carpetas (Simplificada)

laboratorio_digital/├── android/              # Código específico de Android├── assets/               # Archivos estáticos (imágenes, fuentes)│   └── Logo.jpg├── ios/                  # Código específico de iOS├── lib/                  # Código fuente principal de Dart│   ├── *.dart            # Archivos principales (main, pages, widgets, etc.)│   └── firebase_options.dart # Configuración de Firebase (generada)├── test/                 # Pruebas unitarias y de widgets├── web/                  # Código específico de Web (si está habilitado)├── .env                  # Clave API (¡No subir a Git!)├── pubspec.yaml          # Dependencias y metadatos del proyecto└── README.md             # Este archivo
## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor, abre un issue o un pull request para discutir cambios.

## 📜 Licencia

<<<<<<< HEAD
(Opcional) Especifica la licencia de tu proyecto aquí (ej. MIT, Apache 2.0). Si no estás seguro, puedes omitirlo por ahora.
=======
(Opcional) Especifica la licencia de tu proyecto aquí (ej. MIT, Apache 2.0). Si no estás seguro, puedes omitirlo por ahora.
>>>>>>> b5064fc004544de9cdf120832a8e0e0794cb9dac
