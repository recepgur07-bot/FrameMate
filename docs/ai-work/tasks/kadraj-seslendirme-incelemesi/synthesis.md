# Görüş Sentezi

Girdiler: üç tamamlanmış tur-1 görüş — `reviews/01-codex-r1.md` (Codex),
`reviews/02-claude-r1.md` (claude), `reviews/03-antigravity-r1.md`
(Antigravity). Bu görev bir uygulama planı değil, mevcut Frame Coach
implementasyonunun salt-okunur incelemesidir; bu nedenle "kabul/ret" burada
kod değişikliğine değil, **bulgunun doğruluğuna ve önceliğine** karar verir.

Sentez sırasında koordinatör, üç görüş arasındaki iki somut çelişkiyi (test
kapsamı iddiası ve yön-sesi anlamı iddiası) kaynak koda ve gerçek
lokalizasyon kataloğuna bakarak bağımsız doğruladı — aşağıda hangi görüşün
doğrulandığı, hangisinin düzeltildiği açıkça belirtilmiştir.

## Kabul edilenler

Üç görüşün de bağımsız olarak vardığı veya koordinatörün kaynak koddan
doğruladığı bulgular:

1. **Tutarsız "yüz algılanamıyor" metni (üçü de aynı üç konumu buldu).**
   `CaptureCoachingEngine.swift` ve `FrameCoachingEngine.swift` aynı uzun
   metni (`"Yüz algılanamıyor, kameraya bak"`) iki ayrı literal olarak
   taşırken, `RecorderViewModel.swift`'teki 3-kare debounce sonrası yalnız
   kısa `"Yüz algılanamıyor"` söyleniyor — eylem talimatı olmadan. Gerçek
   dünyada en sık karşılaşılan yol (kısa yüz kaybı) tam olarak eksik talimatlı
   metni söylüyor. **Öncelik: yüksek.**

2. **"Kadraj iyi/dengeli" durumu üç ayrı dosyada localize string eşitliğiyle
   tespit ediliyor**, tip güvenli bir sinyal yerine
   (`RecorderViewModel.swift`: `guidance == String(localized: "kadraj uygun")
   ...`; `FrameCoachSpatialCueResolver.swift`: aynı karşılaştırma). Üçü de
   bunu mimari kırılganlık olarak işaretledi. Metin ileride değişirse "iyi
   duruma kilitleme" penceresi, periyodik onay tekrarı ve spatial cue'nun
   "ortalandı" onayı sessizce bozulur. **Öncelik: yüksek.**

3. **`FrameAnalysisService.confidence` sabit `0.9`** — hem claude hem
   Antigravity bunu `FrameCoachingEngine`'in düşük-güven korumasını (`analysis.confidence
   > 0.3`) fiilen ölü koda çevirdiğini not etti. Gerçek Vision güven değeri
   hiç kullanılmıyor.

4. **Kişi sayısı 3 ile sınırlanıyor (`FrameAnalysisService.swift`,
   `.prefix(3)`); 4. ve sonraki kişi sessizce düşüyor**, sistem yine de "Üç
   kişi görünüyor" diyor. Antigravity ve Codex bunu açıkça, claude dolaylı
   olarak (riskli varsayımlar) işaretledi. Kör kullanıcı gözle göremediği bir
   yanlış bilgi alıyor. **Öncelik: yüksek — erişilebilirlik/doğruluk riski.**

5. **Kişi-sayısı anonsu için hysteresis/debounce yok.** Yüz kaybı (3 kare
   toleranslı) ve "iyi duruma kilitleme" (3 saniyelik pencere) için özenli
   debounce mekanizmaları varken, `lastAnnouncedSubjectCount` değişikliği tek
   kare üzerinden anında anons tetikliyor — gürültülü tespitte "Bir kişi
   görünüyor" ↔ "İki kişi görünüyor" çırpınması mümkün. Codex (P1) ve
   Antigravity (#2) bunu bağımsız olarak buldu; claude'un görüşü bunu yalnız
   "riskli varsayım" olarak zayıf değindi — koordinatör olarak bunu şimdi
   **kritik bulgu** seviyesine çıkarıyorum çünkü kodun kendi debounce
   deseniyle (aynı dosyada, aynı yazar) tutarsız. **Öncelik: yüksek.**

6. **3 kişilik sahnede `overlapInstruction` ve `scaleImbalanceInstruction`
   hiç çalışmıyor** — her ikisi de `FrameCoachingEngine.swift`'te
   `analysis.subjectCount == .two` ile korumalı, `.three` için karşılığı yok.
   Antigravity bunu #1 olarak işaretledi; koordinatör kodu tekrar okuyarak
   doğruladı: bu gerçek bir kural boşluğu, test eksikliği değil (bkz. aşağıki
   düzeltme). 3 kişilik bir sahnede biri diğerinin arkasında kalsa veya çok
   yakın dursa, hiçbir uyarı verilmiyor.

7. **VoiceOver anonsu her zaman `NSAccessibilityPriorityLevel.high`
   kullanıyor** (`SpeechCuePlayer.swift`, `SystemAccessibilityAnnouncer`),
   koşulsuz — rutin "kadraj uygun" onay tekrarları dahil. `Sık` (frequent)
   geri bildirim sıklığı ayarında minimum aralık `0` saniye. Bu ikisinin
   birleşimi, sıradan pozisyon düzeltmelerinin VoiceOver'ın başka önemli bir
   anonsunu (veya sistem anonsunu) gereksiz yere kesebileceği anlamına gelir.
   Bu Codex'in P1 bulgusuydu; koordinatör kaynak kodda `NSAccessibilityPriorityLevel.high`
   kullanımının koşulsuz olduğunu doğruladı. Claude ve Antigravity bunu bu
   netlikte işaretlememişti. **Öncelik: yüksek — kullanıcının "yönlendirme
   anlaşılır mı" sorusuyla doğrudan ilgili.**

8. **Yön sesi (spatial audio) kulaklık yönü ile UI'daki erişilebilirlik
   açıklaması arasında gerçek bir anlam çelişkisi var — koordinatör bunu
   kodda ve gerçek UI metninde doğruladı, bu sentezin en önemli bulgusu.**
   `ContentView.swift:1231` erişilebilirlik ipucu şöyle diyor: *"Uzamsal
   modda ses, yüzünün bulunduğu tarafa göre sağ veya sol kulaktan gelir."*
   Ancak `FrameCoachSpatialCueResolver.horizontalCue` (satır 44, 51):
   ```swift
   let delta = analysis.groupCenterX - 0.5
   let direction: FrameCoachSpatialDirection = delta < 0 ? .right : .left
   ```
   Yüz **solda** ise (`groupCenterX < 0.5` → `delta < 0`) üretilen yön
   `.right`. `SpatialCoachCuePlayer.channelGains` (satır 222‑227) `.right`
   yönü için sesi **sağ kulaktan** çalıyor. Yani yüz soldayken ses sağ
   kulaktan geliyor — yani ses "yüzün bulunduğu taraftan" değil, **"kameranın
   hareket etmesi gereken taraftan"** geliyor (bu, konuşma talimatlarıyla
   tutarlı: yüz solda → "biraz sağa geç"). Bu, Codex'in ham gözleminin tam
   olarak doğrulanmış, kesinleşmiş halidir; claude ve Antigravity bunu
   yakalamadı. **Bu, kör bir kullanıcının erişilebilirlik ayarları
   ekranındaki açıklamayı okuyup tam tersi bir zihinsel modelle sesi
   yorumlamasına yol açabilecek, doğrulanmış bir kullanıcı-yanıltıcı metin
   hatasıdır — öncelik: en yüksek.**

## Reddedilenler

- **Claude'un kendi görüşündeki Kritik bulgu 5 ("no dedicated unit test
  files... no test exercises the 3-person path... overlapInstruction veya
  scaleImbalanceInstruction'ı doğrudan test eden yok") — koordinatör olarak
  bunu yanlış buluyorum ve reddediyorum.** `Tests/VideoRecorderAppTests/`
  altında `FrameCoachingEngineTests.swift` (807 satır),
  `CaptureCoachingEngineTests.swift`, `FrameCoachSpatialCueResolverTests.swift`,
  `SpeechCuePlayerTests.swift`, `SpatialCoachCuePlayerTests.swift` mevcut ve
  şunları doğrudan test ediyor: `testThreePeopleTooWideRequestsTighterGroup`,
  `testThreePeopleGoodFramingReportsBalancedGroup`,
  `testTwoPeopleWithScaleImbalanceAskCloserPersonToMoveBack`,
  `testTwoPeopleWhenOnePersonIsHiddenBehindTheOtherAskThemToSeparate`
  (overlap), `testUsesAccessibilityAnnouncementWhenVoiceOverIsRunning`,
  `testAutomaticModeFallsBackToAppVoiceWhenVoiceOverIsNotRunning`,
  `testFeedbackFrequencySuppressesDifferentAnnouncementsUntilMinimumIntervalPasses`.
  Codex'in görüşü bu dosyaları doğru şekilde tespit etmişti; claude ve
  Antigravity'nin görüşleri bu dosyaları kaçırdı (muhtemelen dosya
  taramasının `Tests/VideoRecorderAppTests/` dizinini tam listelememesi
  nedeniyle). **Düzeltilmiş gerçek: 3-kişi genel çerçeveleme ve 2-kişi
  overlap/scale-imbalance kuralları test ediliyor; test edilmeyen asıl şey
  3-kişilik overlap/scale-imbalance'tır — çünkü bu kural zaten kodda 3 kişi
  için hiç yazılmamış (bkz. Kabul edilenler #6), test eksikliği değil.**
- Codex'in "plan.md eksik dosya listeledi, revizyon gerekli" sonucu —
  plan.md zaten `FrameAnalysis.swift`/`FrameAnalysisService.swift`'i
  "Etkilenen alanlar" listesinde taşıyordu (bkz. `plan.md`), yalnız Codex'in
  görüşünün ilk cümlesi bunu gözden kaçırmış olabilir; kapsam listesi zaten
  yeterliydi, plan revizyonu gerekmiyor.

## Doğrulama gerekli

- **VoiceOver anons önceliği/kesintisi gerçek cihaz davranışı** —
  `.high` önceliğin gerçekte VoiceOver'ın başka anonslarını nasıl kestiği
  veya kuyruğa aldığı, `RecordingElapsedTimeAnnouncer` (30s, `.medium`
  öncelik) ile çakışma dahil, yalnız kaynak okumasıyla kesin olarak
  doğrulanamaz. Üçü de bunu doğrulanamadı olarak işaretledi.
- **`isHardFrameCoachInstruction`'ın İngilizce anahtar kelimeleri —
  koordinatör bunu `Localizable.xcstrings` dosyasından kısmen doğruladı, kısmen
  çürüttü.** Gerçek İngilizce çeviriler kontrol edildi:
  - `"too close"` → `"Too close, move back"` içeriyor ✓ eşleşiyor.
  - `"too far"` → `"Too far, move closer"` / `"Too far away, ..."` içeriyor ✓ eşleşiyor.
  - `"closer to the camera"` → `"%@ is closer to the camera, move slightly back"` ✓ eşleşiyor.
  - `"not fully in frame"` → gerçek çeviri `"You are partly out of frame, move slightly right"` / `"%@ is partly out of frame, ..."` — **eşleşmiyor.**
  - `"further back"` → gerçek çeviri (overlap için) `"%@ is blocked, move slightly to the side"` — **eşleşmiyor, "further back" hiçbir çeviride yok.**
  Yani `isHardFrameCoachInstruction`'ın 5 İngilizce anahtar kelimesinden 3'ü
  çalışıyor, 2'si (`"not fully in frame"`, `"further back"`) hiçbir zaman
  eşleşmiyor — bu, İngilizce dil ayarında kırpılmış-özne ve overlap
  düzeltmelerinin "sert talimat" olarak tanınmayıp "iyi duruma kilitleme"
  penceresi tarafından yanlışlıkla susturulabileceği anlamına gelir. Bu artık
  doğrulanamadı değil, **kısmen doğrulanmış bir kod hatasıdır** (statik
  kanıtla kesinleşti); yalnız gerçek İngilizce VoiceOver oturumunda kaç kez
  tetiklendiği hâlâ doğrulama gerektirir.
- **4+ kişi sahnesinde gerçek Vision davranışı, kesişen/örtüşen kişiler,
  ayna/yönlendirme (mirroring) etkisi** — üçü de statik okumayla kesin
  doğrulanamayacağını belirtti; gerçek cihaz/simülatör oturumu gerekli.
- **Yön sesi bulgusunun (Kabul edilenler #8) kullanıcı algısı üzerindeki
  gerçek etkisi** — kod ve UI metni arasındaki çelişki kesinleşmiş bir
  gerçek, ama bunun kör bir VoiceOver kullanıcısını pratikte ne kadar
  yanılttığı yalnız kullanıcı testiyle doğrulanabilir.

## Kullanıcı kararı gerekenler

Erişilebilirlik riski taşıyan bulgular için PROTOCOL.md'nin temkinli-sonuç
kuralı gereği, aşağıdakiler doğrudan uygulamaya geçilmeden önce kullanıcıya
sunulur:

1. **Yön sesi açıklaması/davranışı çelişkisi (Kabul edilenler #8)** en
   yüksek öncelikli olarak değerlendirilmeli mi, yoksa mevcut App Store
   resubmission görevinin (`tasks/app-store-yeniden-gonderim`) önüne mi
   geçmemeli? Bu, kör kullanıcının kafasında yanlış bir zihinsel model
   oluşturabilecek, doğrulanmış bir hata.
2. Ayrı bir uygulama görevi açılacaksa, kapsamı şu 6 maddeden hangilerini
   içermeli: (a) tek "yüz algılanamıyor" metni, (b) tip güvenli
   "isBalanced" sinyali, (c) gerçek Vision confidence kablolaması, (d) 3
   kişilik overlap/scale-imbalance kuralı, (e) kişi-sayısı anonsuna
   hysteresis, (f) VoiceOver anons önceliği/sıklığı politikasının gözden
   geçirilmesi, (g) yön-sesi UI metni veya davranışının düzeltilmesi.
3. Apple'ın güncel erişilebilirlik/algı API'lerinin (Personal Voice, Sound
   Recognition, `VNDetectHumanBodyPoseRequest`, macOS Haptics) bu özelliğe
   eklenmesi — Codex'in de belirttiği gibi bunlar mevcut bir ürün gereksinimi
   olmadan otomatik olarak "eksiklik" sayılmaz; kullanıcı bunu ayrı bir
   keşif/ürün kararı olarak mı ele almak istiyor?

## Onaya sunulan kapsam

Bu görev salt-okunur inceleme olarak tamamlandı; herhangi bir kod
değiştirilmedi. Kullanıcı onayı, yukarıdaki "Kullanıcı kararı gerekenler"
sorularına yanıt ve hangi bulguların ayrı bir uygulama görevine (`brief` →
`plan` → ... → `handoff`) dönüşeceğine dair kapsam seçimi için isteniyor.
Onay olmadan `handoff.md` açılmayacak, kod değiştirilmeyecek.
