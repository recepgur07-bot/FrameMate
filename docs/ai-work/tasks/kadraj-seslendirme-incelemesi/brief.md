# Görev Özeti

## Kullanıcı isteği

"Görüş alınacak araçlar: Codex, Claude, Antigravity. Konu: uygulamadaki kadraj
seslendirme özelliği nasıl, körleri nasıl yönlendiriyor, son Apple özellikleri
vb. açısından geliştirilecek alanlar var mı, bir kişi iki kişi olunca gerekli
tüm tedbirler alınmış mı, yönlendirme anlaşılır mı, gereksiz rastgele tekrarlar
var mı vb. code yapısı ve genel tüm yönleriyle ele al."

Bu bir uygulama görevi değildir — mevcut "Frame Coach" (kadraj/kompozisyon
seslendirme) özelliğinin bağımsız, salt-okunur kod ve erişilebilirlik
incelemesidir. Değiştirilecek yeni bir `plan.md` yoktur; `plan.md` yalnız
incelenecek kapsamı ve inceleme sorularını taşır.

## Hedef

Üç aracın (Codex, Claude, Antigravity) mevcut Frame Coach implementasyonunu
bağımsız olarak incelemesi ve şu sorulara kanıtla desteklenmiş görüş
oluşturması:

1. Kadraj seslendirme (spatial/frame coaching) VoiceOver kullanıcısını nasıl
   yönlendiriyor — yön/mesafe/pozisyon geri bildirimi ne kadar anlaşılır?
2. Son Apple erişilebilirlik özellikleri (VoiceOver, Sistem Sesli Betimleme,
   Canlı Metin/Point-and-Speak benzeri API'ler, Haptics, Sound Recognition,
   Personal Voice vb.) açısından kaçırılan geliştirme alanı var mı?
3. Sahnede bir kişiden ikiye (veya çoklu kişiye) geçildiğinde kod bunu doğru
   ayırt edip güvenli/anlaşılır şekilde seslendiriyor mu; gerekli tüm
   durum/kenar durumları (ör. kişi sayısı değişimi, kimin öncelikli olduğu,
   çakışan sesler) ele alınmış mı?
4. Sesli yönlendirme mesajları anlaşılır mı; gereksiz, rastgele veya aşırı
   tekrar eden anonslar var mı (debounce/rate-limit/eşik mantığı yeterli mi)?
5. `Sources/VideoRecorderApp/FrameCoach/` altındaki kod yapısı (sorumluluk
   ayrımı, test edilebilirlik, state machine netliği) genel olarak nasıl?

İncelenecek başlıca dosyalar: `Sources/VideoRecorderApp/FrameCoach/*.swift`
(CaptureCoachingEngine, FrameCoachingEngine, FrameCoachingProfile,
FrameCoachSpatialCue, FrameCoachSpatialCueResolver, SpatialCoachCuePlayer,
SpeechCuePlayer, RecordingElapsedTimeAnnouncer) ve bunlara bağlanan
`RecorderViewModel.swift`, `ContentView.swift`, `CameraOverlayRecorder.swift`.

## Kapsam dışı

- Yeni kod yazma veya mevcut davranışı değiştirme (bu aşamada yok).
- App Store resubmission görevi (`tasks/app-store-yeniden-gonderim`) — ayrı
  görev, burada ele alınmaz.
- Ses/video kayıt pipeline'ının kadraj dışı kısımları (mikrofon, ekran kaydı).

## Kısıtlar

- İncelemeler salt-okunur olacak; kod/plan/ortak durum dosyaları
  değiştirilmeyecek.
- Gerçek cihaz/simülatör erişimi yoksa bu açıkça "doğrulanamadı" yazılacak.
- Erişilebilirlik riski taşıyan bulgularda temkinli sonuç seçilecek (bkz.
  PROTOCOL.md "Görüş çelişkisi ve karar kuralı").

## Kabul ölçütleri
- [ ] Üç aracın da `reviews/NN-arac-r1.md` dosyaları zorunlu başlık şemasıyla
      tamamlanmış olacak.
- [ ] Her görüş, incelenen kaynak dosyaları ve varsa çalışır arayüz kanıtını
      açıkça belirtecek.
- [ ] `synthesis.md`, üç görüşün uzlaşma/ayrışma noktalarını ve önerilen somut
      geliştirme alanlarını (varsa önceliklendirilmiş) özetleyecek.

## Roller
- Koordinatör: claude
- Planlayıcı: claude
- İnceleyenler: codex, claude, antigravity (üçü de bağımsız inceleyen; claude
  hem koordinatör hem inceleyenlerden biri olarak kendi görüşünü ayrı dosyaya
  yazar)
- Sentezleyici: claude
- Uygulayıcı: Bu görev uygulama içermiyor; yalnız kullanıcı ayrı bir uygulama
  görevi açarsa atanacak
- Doğrulayıcı: Uygulama yok, bu aşamada atanmayacak
