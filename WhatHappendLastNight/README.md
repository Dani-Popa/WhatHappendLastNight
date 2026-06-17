### 1. Adăugarea permisiunii pentru Cameră (Info.plist)
macOS cere o justificare text care va fi afișată utilizatorului atunci când aplicația cere acces la cameră:

1. Deschide proiectul în **Xcode**.
2. În bara din stânga (Project Navigator), dă click pe fișierul principal al proiectului (cel de sus, cu o pictogramă albastră de proiect).
3. Selectează tab-ul **Info** din bara de sus.
4. Mergi la secțiunea **Custom macOS Application Target Properties**, pune mouse-ul peste ultimul rând și dă click pe butonul mic de tip **`+`**.
5. Caută sau scrie cheia: **`Privacy - Camera Usage Description`**.
6. În coloana **Value**, folosește un mesaj specific și transparent, de exemplu: *"Camera access is used to capture a selfie for local face matching. Images and biometric embeddings are not uploaded or stored by the app."*

### 2. Privacy baseline

- Procesează selfie-ul, fotografiile selectate, detecțiile feței și embedding-urile doar local, în memorie.
- Nu trimite fotografii, selfie-uri, embedding-uri sau rezultate către servere externe.
- Nu loga nume de fișiere personale, vectori biometrici sau scoruri de similaritate în producție.
- Păstrează butonul **Clear Session** și acordul explicit înainte de scanare.
- Consultă `../PRIVACY.md` înainte să adaugi analytics, backend-uri sau procesare AI terță.

