# Scanner (25/10/2026): ML Kit legge solo i caratteri latini. La libreria
# nomina anche i modelli cinese, giapponese, coreano e devanagari, che non
# sono inclusi: senza queste righe la compilazione release (R8) si ferma.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
