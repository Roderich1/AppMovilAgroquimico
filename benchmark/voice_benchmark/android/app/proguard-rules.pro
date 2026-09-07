# Reglas de R8 del banco de pruebas de voz.
#
# HERRAMIENTA DE SPIKE. No la usa la aplicación Agrocuentas ni su CI.
#
# ## Por qué existe este archivo
#
# El APK release de Vosk arrancaba y fallaba al cargar el modelo con:
#
#   java.lang.UnsatisfiedLinkError: Can't obtain peer field ID for class
#   com.sun.jna.Pointer
#
# JNA busca ese campo **por nombre desde código nativo**, con JNI. R8 no puede
# saberlo —no hay ninguna referencia en bytecode— así que lo renombra y la
# búsqueda falla. El fallo no aparece en debug, donde no hay R8: sólo en el APK
# release, que es justamente el que se usa para medir.
#
# Sin estas reglas, el candidato C1 y el híbrido C4 no cargan el modelo.

# --------------------------------------------------------------------- JNA
# Los nombres de clase y de campo los resuelve el puente nativo por reflexión.
-keep class com.sun.jna.** { *; }
-keepclassmembers class com.sun.jna.** { *; }
-keep class * extends com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }

# JNA compila contra AWT para escritorio; en Android esas clases no existen y
# no se usan. Sin esto R8 avisa de referencias que nunca se ejecutan.
-dontwarn java.awt.**
-dontwarn javax.swing.**

# -------------------------------------------------------------------- Vosk
# `LibVosk`, `Model` y `Recognizer` mapean funciones nativas por nombre.
-keep class org.vosk.** { *; }
-keepclassmembers class org.vosk.** { *; }

# ------------------------------------------------------- puente del banco
# Los metodos que JNI llama desde `whisper_jni.c` no tienen ninguna referencia
# en bytecode: para R8 son codigo muerto.
-keep class com.comunidad.agro.voicebench.whisper.WhisperLib { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
