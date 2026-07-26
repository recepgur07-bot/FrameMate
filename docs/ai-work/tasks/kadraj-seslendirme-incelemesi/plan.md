# İnceleme Kapsamı (Uygulama Planı Yerine)

Bu görevde yeni bir uygulama planı yoktur. Bu dosya, üç bağımsız incelemenin
karşılaştıracağı "mevcut durum" kapsamını sabitler.

## Önerilen yaklaşım

Mevcut Frame Coach implementasyonunu erişilebilirlik, kod yapısı ve Apple'ın
güncel platform yeteneklerine göre denetlemek. Her inceleyen kaynağı
bağımsız okur, aşağıdaki sorulara kanıtla yanıt verir, kendi
`reviews/NN-arac-r1.md` dosyasına yazar.

## Etkilenen alanlar (salt-okunur inceleme kapsamı)

- `Sources/VideoRecorderApp/FrameCoach/CaptureCoachingEngine.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachingEngine.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachingProfile.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCue.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCueResolver.swift`
- `Sources/VideoRecorderApp/FrameCoach/SpatialCoachCuePlayer.swift`
- `Sources/VideoRecorderApp/FrameCoach/SpeechCuePlayer.swift`
- `Sources/VideoRecorderApp/FrameCoach/RecordingElapsedTimeAnnouncer.swift`
- `Sources/VideoRecorderApp/RecorderViewModel.swift` (Frame Coach bağlanma noktaları)
- `Sources/VideoRecorderApp/ContentView.swift` (VoiceOver anons/erişilebilirlik metinleri)
- `Sources/VideoRecorderApp/CameraOverlayRecorder.swift` (kişi tespiti/overlay ile bağlantı)
- İlgili testler: `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`

## Adımlar (inceleyen için)

1. Yukarıdaki dosyaları oku; kadraj/kişi-tespiti akışının uçtan uca veri
   akışını çıkar (kamera → tespit → spatial cue resolver → speech cue player
   → VoiceOver anonsu).
2. Tek kişi → çoklu kişi geçişinde durumu, önceliklendirmeyi ve olası çakışan
   anonsları izle.
3. Anons sıklığı/eşik/debounce mantığını bul; gereksiz tekrar riskini
   değerlendir.
4. Güncel Apple erişilebilirlik/algı API'leriyle (VoiceOver, Sistem Sesli
   Betimleme, Sound Recognition, Haptics, Personal Voice, Live Speech vb.)
   karşılaştır; kaçırılan fırsat varsa belirt.
5. Kod yapısını (sorumluluk ayrımı, test kapsamı, state machine netliği)
   değerlendir.
6. Simülatör/cihaz erişimi varsa gerçek anons davranışını doğrula; yoksa
   "doğrulanamadı" olarak işaretle.

## Riskler ve açık sorular

- Gerçek cihaz/VoiceOver deneyimi olmadan yalnız statik kod okumasıyla "anlaşılırlık"
  değerlendirmesi sınırlı kalabilir — bu durum incelemede açıkça belirtilmeli.
- Çoklu kişi senaryosunda kamera tespiti kaynaklı gürültü (ör. sık kişi
  sayısı değişimi) ile gerçek sahne değişikliği ayrımı kod okumasıyla tam
  doğrulanamayabilir.

## Kabul ölçütü eşlemesi

- brief.md kabul ölçütü 1-3 → her inceleyenin `reviews/NN-arac-r1.md`
  dosyasını zorunlu başlık şemasıyla doldurması ve `synthesis.md`nin üç
  görüşü birleştirmesiyle karşılanır.
