import Foundation

/// Ajustes de compatibilidad para sitios concretos, como los "quirks" que traen Safari y Chrome.
/// Cada uno explica el problema que corrige; si el sitio cambia, el ajuste deja de aplicar sin romper nada.
enum SiteQuirks {
    static let source = """
    (() => {
      // Gmail: el fondo del tema es una imagen de tamaño fijo (p. ej. 1920 × 1200) elegida al cargar
      // según el ancho visible. Si la zona crece después (al ocultar la barra lateral), no la cambia y
      // queda una franja sin fondo a la derecha. Se hace que cubra siempre toda la zona.
      if (location.hostname === 'mail.google.com') {
        const style = document.createElement('style');
        style.textContent = 'img.ao0 { min-width: 100% !important; min-height: 100% !important; object-fit: cover !important; }';
        (document.head || document.documentElement).appendChild(style);
      }
    })();
    """
}
