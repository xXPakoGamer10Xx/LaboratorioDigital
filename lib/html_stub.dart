// lib/html_stub.dart
library html_stub;

// Definiciones "falsas" (stubs) para satisfacer el análisis estático en Android/iOS.
// Este código NUNCA se ejecuta en Android/iOS porque el uso real
// en MathExpertPage.dart está protegido por `if (kIsWeb)`.

// Stub para la clase Blob
class Blob {
  // Constructor falso que coincide con cómo se usa en tu código
  Blob(List<Object?> blobParts, [String? type, String? endings]);
}

// Stub para la clase Url
class Url {
  // Métodos estáticos falsos que coinciden con cómo se usan
  static String createObjectUrlFromBlob(Blob blob) {
    // Devuelve algo, aunque no se usará
    print("Advertencia: createObjectUrlFromBlob llamado en plataforma no web (stub).");
    return '';
  }

  static void revokeObjectUrl(String url) {
    // No hace nada
    print("Advertencia: revokeObjectUrl llamado en plataforma no web (stub).");
  }
}

// Stub para la clase AnchorElement
class AnchorElement {
  // Constructor falso que coincide con cómo se usa (parámetro nombrado href)
  AnchorElement({String? href});

  // Métodos falsos que coinciden con cómo se usan
  void setAttribute(String name, String value) {
    // No hace nada
  }

  void click() {
    // No hace nada
    print("Advertencia: click de AnchorElement llamado en plataforma no web (stub).");
  }
}

// Si aparecieran más errores sobre otros elementos de 'html.',
// tendrías que añadir sus stubs aquí también.