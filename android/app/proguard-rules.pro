# Scanner (25/10/2026): ML Kit legge solo i caratteri latini. La libreria
# nomina anche i modelli cinese, giapponese, coreano e devanagari, che non
# sono inclusi: senza queste righe la compilazione release (R8) si ferma.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Le classi di ML Kit che il sistema trova per nome mentre l'app gira: R8 non
# deve rinominarle ne' toglierle (1.0.108: lo scanner non leggeva niente).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

# Codici a barre (28/10/2026): stesse regole per il lettore di ML Kit.
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google_mlkit_barcode_scanning.** { *; }
