### 1. Adăugarea permisiunii pentru Cameră (Info.plist)
macOS cere o justificare text care va fi afișată utilizatorului atunci când aplicația cere acces la cameră:

1. Deschide proiectul în **Xcode**.
2. În bara din stânga (Project Navigator), dă click pe fișierul principal al proiectului (cel de sus, cu o pictogramă albastră de proiect).
3. Selectează tab-ul **Info** din bara de sus.
4. Mergi la secțiunea **Custom macOS Application Target Properties**, pune mouse-ul peste ultimul rând și dă click pe butonul mic de tip **`+`**.
5. Caută sau scrie cheia: **`Privacy - Camera Usage Description`**.
6. În coloana **Value**, adaugă mesajul tău (ex: *„Sistemul are nevoie de acces la cameră pentru a-ți face un selfie de analizat biometric.”*).

