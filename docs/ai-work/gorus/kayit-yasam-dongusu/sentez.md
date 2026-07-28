# Sentez — kayıt yaşam döngüsü ve zamanlama

Koordinatör: Claude · Girdiler: `01-claude.md`, `02-codex.md`, `03-antigravity.md` (üçü de tam)
Durum: tam görüşle sentez. Tek karar aşağıda; uygulama şartnamesi `handoff.md`.

## 1. Üç görüşün ortak paydası (yüksek güven)

Üç araç da bağımsız olarak aynı kök mekanizmaya vardı:

| # | Bulgu | Claude | Codex | Antigravity |
|---|---|---|---|---|
| A | Pause aralıkları `systemUptime` ile ölçülüp dosya-local t=0'a uygulanıyor | K1 | P0 | Q3 |
| B | `primaryCaptureStartUptime` yalnız ekran yolunda set ediliyor; kamera/ses modu "şimdi"ye düşüyor | K2 | Riskli varsayım 2 | Riskli varsayım 1 |
| C | Ses-only ve kamera export'unda hiç track offset'i yok | K3 | P0 ×2 | Bulgu 4 |
| D | macOS 15+'ta ekran sıfırı `SCRecordingOutput` dosyasından değil, gözlemci `SCStreamOutput`'tan okunuyor; frame status kontrolü yok | K4 | P1 | Bulgu 3 |
| E | Yaşam döngüsü `.stopping`de kilitlenebiliyor / `isStopping` mandalı açılmıyor | K5 | P1 | Bulgu 2 |
| F | Export sürerken yeni kayıt eski session state'ini eziyor | K6 | P1 | Q4 |

A–D aynı hastalığın dört yüzü: **tek bir oturum için üç ayrı saat kullanılıyor** —
main-actor `systemUptime`, her dosyanın kendi ilk-örnek PTS'i, ve macOS 15+'ta üçüncü
bir taraf olarak `SCRecordingOutput`'un kendi dosya sıfırı. E ve F bağımsız durum
makinesi kusurları.

## 2. Çözülen anlaşmazlıklar

**Anlaşmazlık 1 — Offset yönü.** Antigravity (Bulgu 1) mikrofon izini `offset` kadar
ileri itmenin *hatanın kendisi* olduğunu, videonun başını sessiz bıraktığını söylüyor.
**Reddedildi.** Mikrofon gerçekten 3 sn geç başladıysa videonun ilk 3 saniyesinde
mikrofon sesi fiziksel olarak yoktur; izi 0'a çekmek sesi *yanlış yere* koyar, kurtarmaz.
Claude (K4) ve Codex (P1) haklı: yön doğru, **referans noktası** şüpheli. Antigravity'nin
teşhisi yanlış ama gözlemi değerli — offset büyüdükçe baş sessizleşiyor, yani asıl iş
offset'i doğru hesaplamak *ve* bileşenlerin gerçek başlama gecikmesini küçültmek.

**Anlaşmazlık 2 — Ortak `startSession(atSourceTime:)` ankrajı.** Antigravity tüm
writer'ların tek bir `masterSessionZeroHostTime`'a bağlanmasını öneriyor.
**Kısmen kabul.** Fikir doğru ve export matematiğini tümüyle gereksizleştirir; ama
macOS 15+'ta ekran dosyasını `SCRecordingOutput` yazar, onun session start'ını
kontrol edemeyiz. Bu yüzden **hibrit** karar: dosya başına t=0 + export-time offset
mimarisi korunur (zaten %80'i yazılmış ve testli), fakat tek bir açık `RecordingSessionClock`
değeri üzerinden, üç modda da aynı biçimde uygulanır.

**Anlaşmazlık 3 — Durdurma hatasının tam yolu.** Üç aday: `isStopping` mandalı
(Claude K5), audio-only'de sıfır-kaynak kombinasyonunun hiç callback üretmemesi
(Codex P1), eksik bileşen sonucu yüzünden `maybeFinalize`'ın erken dönmesi
(Antigravity Bulgu 2). **Üçü de gerçek ve birbirinden bağımsız.** Hepsi düzeltilecek;
hangisinin kullanıcının gördüğü hata olduğunu tartışmak yerine üçünü de kapatmak
daha ucuz.

## 3. Karar

Tek karar: **kayıt oturumunun zamanı tek bir yerde tanımlanır, üç modda da aynı
mekanizmayla uygulanır; yaşam döngüsü her koşulda `.idle`'a döner; oturum durumu
durdurma anında dondurulur.**

Somut olarak, öncelik sırasıyla:

1. **Yaşam döngüsü kilitlerini kapat** (E). Deterministik, ölçüm gerektirmez, kullanıcının
   gördüğü hatayı doğrudan hedefler. İlk faz bu.
2. **Oturum saati** (`RecordingSessionClock`): sessionZero = primary bileşenin ilk örnek
   host-time PTS'i. Pause aralıkları host-time'dan türetilir, `systemUptime` kayıt
   zamanlamasında hiç kullanılmaz.
3. **Offset'i üç moda da yay** (B, C): kamera ve ses-only, ekran yolundaki
   `shiftedEarlier` + `outputPosition` mekaniğini aynen kullanır.
4. **Ekran referansını sağlamlaştır** (D): `SCStreamFrameInfoStatus` filtresi + finalize
   sonrası dosyadan okunan gerçek ilk kare PTS'i ile doğrulama/telemetri.
5. **Session generation** (F): export completion'ları yalnız kendi kuşaklarına yazar.
6. **Testler + ölçüm logu**: hatayı yakalayacak birim testleri ve kullanıcının cihazında
   kalan sapmayı ölçülebilir kılan log satırları.

Faz 4'ün "gerçek 10 saniye"yi tek başına açıklayıp açıklamadığı **ölçülmeden iddia
edilmiyor**; faz 6'nın logu bunu kesinleştirecek. Bu, şimdiye kadarki kısır döngünün
sebebini de açıklıyor: her seferinde ölçülmeden tek bir offset yamandı.

## 4. Kapsam dışı bırakılanlar

- Başlangıç ses efektlerinin (`playStartSoundBeforeCapture`, ~5 sn'ye kadar) yeniden
  tasarımı. Saatler düzeldikten sonra ayrı bir görevde ele alınacak (Claude K7).
- Tek muxed writer'a geçiş / mimari yeniden yazım. Üç araç da mevcut mimarinin doğru
  olduğunda hemfikir.
- `RecordingPauseTimeline`'ın kendi aritmetiği. Girdileri yanlış, kendisi değil.
