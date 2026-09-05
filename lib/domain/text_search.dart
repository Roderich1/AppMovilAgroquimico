/// Comparación de texto para las búsquedas de la interfaz.
///
/// Vive en `domain/` y no en una pantalla porque la regla debe ser **una sola**:
/// antes cada lista y cada selector hacía su propio `toLowerCase().contains()`.
library;

/// Normaliza [text] para comparar búsquedas: minúsculas y **sin diacríticos**.
///
/// En un teclado móvil español lo normal es escribir sin tildes, así que buscar
/// `maria` debe encontrar *María* y `anez` debe encontrar *Áñez* (UIBUG-019).
/// Antes cada pantalla hacía `toLowerCase().contains(...)` por su cuenta —siete
/// sitios— y ninguna normalizaba, de modo que el usuario concluía que el
/// registro no existía y lo creaba duplicado.
///
/// La `ñ` **se conserva**: es una letra propia del español, no una `n` con
/// diacrítico, y quien la escribe la escribe a propósito.
String normalizeForSearch(String text) {
  const withDiacritics = 'áàäâãéèëêíìïîóòöôõúùüûçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÇ';
  const without = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = withDiacritics.indexOf(char);
    buffer.write(index < 0 ? char : without[index].toLowerCase());
  }
  return buffer.toString();
}

/// `true` si [haystack] contiene [needle] ignorando mayúsculas y tildes.
bool matchesSearch(String haystack, String needle) =>
    normalizeForSearch(haystack).contains(normalizeForSearch(needle));
