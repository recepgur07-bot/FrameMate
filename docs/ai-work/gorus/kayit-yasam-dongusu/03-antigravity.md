# Kayıt Yaşam Döngüsü ve Zamanlama Analizi — Antigravity Görüşü

Oturum: `kayit-yasam-dongusu` · Hedef: Antigravity · Tür: Bağımsız Salt-Okunur İnceleme

## Sonuç

Kayıt başlangıcındaki ~10 saniyelik kayıp ve durdurma sonrası ekranın kilitlenmesi, sistem seviyesindeki üç temel mimari çelişkiden kaynaklanmaktadır:

1. **Ekran/Ses Offset ve Saat Uyuşmazlığı (Q1):** Ekran kaydı (`ScreenRecorder.swift:145-157`) macOS 15+ üzerinde `SCRecordingOutput` kullanırken, ilk örnek zamanı `SCStreamOutput` delegate'ine düşen ilk ham `CMSampleBuffer` zamanından (`ScreenRecorder.swift:271`) alınmaktadır. Bu tampon henüz `SCStreamFrameInfoStatus.frameComplete` içermeyen akış başlatma karelerine denk gelebilmekte veya ses bileşenleri (`MicrophoneAudioRecorder.swift:147`, `CameraOverlayRecorder.swift:114`) `AVCaptureSession` / `SCStream` başlatma gecikmeleri yüzünden saniyeler sonra ilk örneği üretebilmektedir. `RecordingTrackOffsets.make` (`ScreenCameraOverlayCompositionBuilder.swift:38-57`) ile hesaplanan pozitif offset (`delta = componentStart - screenStart`), ses dosyasının (`.m4a`) kendi t=0 noktasından başlayan sesini kompozisyonda 2-10 saniye ileriye ötelemektedir (`ScreenCameraOverlayCompositionBuilder.swift:313-326`). Sonuç olarak videonun başı sessiz kalmakta ve ses akışı kaymaktadır.
2. **Durdurma Hatası ve Kilitlenen Yaşam Döngüsü Durumu (Q2):** Kullanıcı kaydı hızlıca durdurduğunda veya bir alt bileşen (örneğin mikrofon/sistem sesi) ses üretemeden `emptyRecording` hatası döndürdüğünde (`MicrophoneAudioRecorder.swift:208`, `SystemAudioRecorder.swift:126`), `maybeFinalizeScreenRecordingExport` (`RecorderViewModel.swift:2768-2784`) beklenen sonuçlardan biri `nil` kaldığı için erken döner. Bu durumda `finishRecordingLifecycle()` (`RecorderViewModel.swift:2808`) çağrılamaz. `recordingLifecycle.phase` (`RecordingLifecycleState.swift:31`) kalıcı olarak `.stopping` aşamasında takılır ve `RecordingLifecycleState.swift:18` gereği sonraki kayıt başlatma istekleri reddedilir.
3. **Parçalı Zaman Tabanı ve Dışarı Aktarım Kırılganlığı (Q3, Q4, Q5):** Duraklatma aralıkları (`RecordingPauseTimeline.swift:108-119`) ile dışarı aktarım ötelemeleri (`RecordingTrackOffsets`) bileşen bazında farklı uygulanmakta; kamera-sadece ve ses-sadece modlarında ise offset hiç hesaba katılmamaktadır (`RecorderViewModel.swift:2937-3048`, `RecorderViewModel.swift:47-144`). İki kez Başlat/Durdur basıldığında veya dışarı aktarma sürerken yeni kayıt başlatıldığında `RecorderViewModel.swift` üzerindeki geçici dosya URL'leri ezilmekte ve `ScreenRecorder` tekil örneği çakışmaktadır.

Çözüm; her bileşenin bağımsız t=0 sürelerini dışarı aktarımda offset ile kaydırmaya çalışmak yerine, tüm kaydedicilerin tek bir ortak konak saati (`sessionZeroHostTime`) ile senkronize edilmesini ve `maybeFinalizeScreenRecordingExport` içindeki durum makinesi tamamlanmasının `defer` / `finally` garantisine alınmasını gerektirmektedir.

---

## Kritik bulgular

### 1. [Kritik] Ses Dosyasının İleri İtilmesi ve Baştaki ~10 Saniyelik Kesinti
- **Konum:** `Sources/VideoRecorderApp/ScreenRecorder.swift:145-157`, `Sources/VideoRecorderApp/ScreenRecorder.swift:271`, `Sources/VideoRecorderApp/ScreenCameraOverlayCompositionBuilder.swift:38-57`, `Sources/VideoRecorderApp/ScreenCameraOverlayCompositionBuilder.swift:313-326`, `Sources/VideoRecorderApp/RecorderViewModel.swift:2458-2542`
- **Mekanizma:** `RecorderViewModel.swift:2458` üzerinde `screenRecordingProvider.startRecording` çağrılır ve `primaryCaptureStartUptime` kaydedilir. Ardından `withThrowingTaskGroup` (`RecorderViewModel.swift:2492`) ile kamera overlay, mikrofon ve sistem sesi eşzamanlı başlatılır. `AVCaptureSession` yapılandırması ve başlatılması (`MicrophoneAudioRecorder.swift:147`, `CameraOverlayRecorder.swift:115`) 1 ila 3+ saniye sürebilmektedir.
- `ScreenRecorder.swift:271` içindeki `recordFirstSampleTimeIfNeeded` metodu `SCStreamOutput` üzerinden akış başlar başlamaz gelen ilk kare zamanını (`screenStart`) yakalar. Mikrofon ise ilk ses verisini aldığında (`MicrophoneAudioRecorder.swift:246`) kendi `firstSampleTime` değerini (`microphoneStart`) kaydeder.
- `RecordingTrackOffsets.make` (`ScreenCameraOverlayCompositionBuilder.swift:38-57`) bu iki konak saati timestamp'i arasındaki farkı `offset = microphoneStart - screenStart` (ör. +3.5s veya başlatma ses efektleri bekletildiyse daha uzun) olarak hesaplar.
- Mikrofon `.m4a` dosyası kendi içerisinde t=0'dan itibaren kaydedilmiş sesi içerir. Ancak `ScreenCameraOverlayCompositionBuilder.swift:313-326` içinde `insertComponentSegments` metodu, mikrofondan gelen ses izini kompozisyona `at: CMTimeAdd(segment.destinationStart, base)` (burada `base = offset`) ile yerleştirir.
- **Sonuç:** Mikrofon dosyasındaki ses kompozisyonda 3.5 saniye (veya daha fazla) ileri ötelenir. Ekran videosunun ilk 3.5 saniyesi sessiz kalır, kullanıcının konuştuğu ilk kelimeler ötelendiği için kayar veya video süresini aştığı için sonda kesilir.

### 2. [Kritik] Durdurma Esnasında Kilitlenen Durum Makinesi (`.stopping` Kapanı)
- **Konum:** `Sources/VideoRecorderApp/RecordingLifecycleState.swift:18-39`, `Sources/VideoRecorderApp/RecorderViewModel.swift:2146`, `Sources/VideoRecorderApp/RecorderViewModel.swift:2768-2784`, `Sources/VideoRecorderApp/RecorderViewModel.swift:2808`
- **Mekanizma:** Kullanıcı "Durdur" düğmesine bastığında `RecorderViewModel.swift:2116` `stopRecording()` çağrılır. `markRecordingStopping()` (`RecorderViewModel.swift:2313`) `recordingLifecycle.beginStopping()` çağırarak `phase` değerini `.stopping` yapar (`RecordingLifecycleState.swift:31`).
- Ekran kaydı ve alt bileşenlerin durdurulması tetiklenir. Ancak eğer bir alt bileşen (ör. mikrofon veya sistem sesi) henüz hiçbir örnek yazamadıysa (`MicrophoneAudioRecorder.swift:208`, `SystemAudioRecorder.swift:126`), completion closure'ı `.failure(emptyRecording)` döner veya durdurma süreci zaman aşımına uğrar.
- `maybeFinalizeScreenRecordingExport()` (`RecorderViewModel.swift:2768-2784`) guard şartlarını kontrol eder:
  ```swift
  guard let screenResult = pendingScreenCaptureResult, ...
        let microphoneResult = pendingScreenMicrophoneCaptureResult,
        let systemAudioResult = pendingScreenSystemAudioCaptureResult else { return }
  ```
  Eğer bileşenlerden birinin sonucu henüz gelmediyse veya aksadıysa, fonksiyon `return` ile erken çıkar.
- `finishRecordingLifecycle()` çağrısı (`RecorderViewModel.swift:2808`) `maybeFinalizeScreenRecordingExport` fonksiyonunun guard şartlarının *altında* yer aldığı için çalıştırılamaz.
- **Sonuç:** `recordingLifecycle.phase` sürekli `.stopping` durumunda kalır. Kullanıcı tekrar "Başlat" düğmesine bastığında `startRecordingAsync()` -> `beginRecordingPreparation()` (`RecorderViewModel.swift:2291`) çalışır, ancak `RecordingLifecycleState.swift:18` gereği `phase == .idle` şartı sağlanmadığı için kayıt başlatılamaz. Kullanıcı arayüzde hata görür ve uygulama yeniden başlatılana kadar kayıt yapamaz.

### 3. [Yüksek] macOS 15+ SCRecordingOutput ve SCStreamOutput Zaman Çakışması
- **Konum:** `Sources/VideoRecorderApp/ScreenRecorder.swift:145-157`, `Sources/VideoRecorderApp/ScreenRecorder.swift:271`, `Sources/VideoRecorderApp/ScreenRecorder.swift:467-488`
- **Mekanizma:** macOS 15+ üzerinde `ScreenRecorder.swift:145` `stream.addRecordingOutput(recordingOutput)` kullanarak ekran videosunu doğrudan ScreenCaptureKit'in kendi yazıcısına teslim eder. Aynı zamanda ilk kare zamanını ölçmek için `stream.addStreamOutput(self, type: .screen, ...)` eklenir.
- `SCStreamOutput` delegate'ine gelen ilk `CMSampleBuffer` (`ScreenRecorder.swift:271`) akış başlatıldığı anda teslim edilir; bu örnek `SCStreamFrameInfoStatus.started` veya `.idle` durumunda olabilir ve henüz gerçek ekran içeriği içermeyebilir.
- `SCRecordingOutput` ise dosyaya yazmaya ilk geçerli görüntü karesi (`SCStreamFrameInfoStatus.frameComplete`) ile başlar.
- **Sonuç:** `firstSamplePresentationTime` olarak kaydedilen `screenStart` zamanı, `SCRecordingOutput` dosyasındaki gerçek t=0 video karesinden daha erken bir zamanı gösterebilir. Bu durum `RecordingTrackOffsets` hesabını saptırarak ses ve video arasındaki senkronizasyonu bozar.

### 4. [Orta] Modlar Arası Offset Mantığı Tutarsızlığı (Kamera ve Ses Modları)
- **Konum:** `Sources/VideoRecorderApp/RecorderViewModel.swift:2937-3048` (`makeCameraExportAsset`), `Sources/VideoRecorderApp/RecorderViewModel.swift:47-144` (`AudioRecordingExporter`)
- **Mekanizma:** Ekran kaydı modunda `RecordingTrackOffsets` hesaplanıp `ScreenCameraOverlayCompositionBuilder` üzerinden uygulanırken, Kamera-Sadece (`makeCameraExportAsset`) ve Ses-Sadece (`AudioRecordingExporter`) modlarında alt bileşenler (mikrofon ve sistem sesi) için herhangi bir track offset hesaplaması yapılmaz.
- Ses-Sadece modunda mikrofon ve sistem sesi farklı zamanlarda başlasa dahi `addAudioTracks` (`RecorderViewModel.swift:121`) her iki dosyayı da t=0'dan itibaren yerleştirir.
- Kamera modunda `systemAudioRecorder` (`RecorderViewModel.swift:2085`) kamera kaydından (`RecorderViewModel.swift:2094`) önce başlatılır ancak `makeCameraExportAsset` (`RecorderViewModel.swift:3025`) iki izi aynı sıfır noktasına hizalar.
- **Sonuç:** Farklı kayıt modlarında zamanlama ve senkronizasyon davranışı tutarsızlaşır.

---

## Onaylanan kararlar

1. **Tekil Dosya Yapısının Muhafazası:** Ekran, kamera, mikrofon ve sistem sesinin ayrı dosyalara kaydedilip dışarı aktarım esnasında `AVMutableComposition` ile birleştirilmesi mimarisi korunacaktır; ancak bileşenlerin t=0 noktaları dışarı aktarımda rastgele offset ile düzeltilmek yerine kayıt anında ortak zaman tabanına oturtulacaktır.
2. **Duraklatma Zaman Çizelgesi (`RecordingPauseTimeline`):** Duraklatma aralıklarının kaydedilmeye devam eden fiziksel akışlardan dışarı aktarım esnasında dilimlenerek çıkarılması (`RecordingPauseTimeline.swift:31-78`) doğru ve işlevsel bir yaklaşımdır.
3. **Güvenlik Durum Kontrolleri:** Disk alanı yetersizliği veya süre sınırı aşımlarında kaydın otomatik durdurulması (`RecorderViewModel.swift:2201`, `RecorderViewModel.swift:2159`) onaylanmıştır.

---

## Riskli varsayımlar

1. **`primaryCaptureStartUptime` Bağlantısı Varsayımı:** `RecorderViewModel.swift:1664` üzerinde `recordingStartUptime = primaryCaptureStartUptime ?? ProcessInfo.processInfo.systemUptime` denilerek duraklatma çizelgesinin ekran kaydı başlama zamanına bağlandığı varsayılmaktadır. Ancak `primaryCaptureStartUptime` yalnızca `startScreenRecording` (`RecorderViewModel.swift:2469`) içinde set edilmektedir. Kamera ve Ses modlarında bu değer `nil` kalmakta ve `ProcessInfo.processInfo.systemUptime` değerine düşmektedir.
2. **Eşzamanlı Başlatmanın Zaman Farkını Yok Ettiği Varsayımı:** `RecorderViewModel.swift:2472` yorum satırında ikincil bileşenlerin `withThrowingTaskGroup` ile paralel başlatılmasının gecikmeyi önleyeceği varsayılmıştır. Ancak paralel başlatma bileşenlerin donanım hazırlık sürelerindeki farklılıkları (örn. `AVCaptureSession.startRunning()` vs `SCStream.startCapture()`) ortadan kaldırmaz; bileşenlerin ilk örnek zamanları hala farklı konak zamanlarına düşmektedir.
3. **Asenkron Tamamlanmanın Garantili Olduğu Varsayımı:** `maybeFinalizeScreenRecordingExport` fonksiyonunun 4 bileşen sonucunu da her koşulda eksiksiz alacağı varsayılmıştır. İptal, zaman aşımı veya cihaz hatasında bu callback'lerden biri gelmediğinde yaşam döngüsünün sıfırlanacağı mekanizma eksiktir.

---

## Doğrulama listesi

- [ ] **Kök Neden Doğrulaması:** Ekran kaydı başlatılıp 5 saniye konuşulduğunda kaydedilen `.m4a` mikrofon dosyası ile ekran `.mov` dosyasının ilk örnek `CMSampleBuffer` zaman damgaları (`CMClockGetTime(CMClockGetHostTimeClock())`) karşılaştırılmalı ve `RecordingTrackOffsets` çıktısı loglanmalıdır.
- [ ] **Yaşam Döngüsü Kilitlenme Testi:** Kayıt başlatıldıktan hemen sonra (100 ms içinde) "Durdur" düğmesine basılmalı; `recordingLifecycle.phase` durumunun `.idle` konumuna dönüp dönmediği ve hemen ardından yeni kayıt başlatılabildiği doğrulanmalıdır.
- [ ] **Hızlı Çift Tıklama Testi:** "Başlat" ve "Durdur" düğmelerine ardı ardına hızlıca basıldığında `ScreenRecorder` ve `RecorderViewModel` durumunun tutarlı kaldığı test edilmelidir.
- [ ] **Bileşen Eksikliği Testi:** Mikrofon izni kapalı veya mikrofon yokken ekran kaydı yapıldığında kısmi kaydın sorunsuz tamamlandığı ve yaşam döngüsünün takılmadığı doğrulanmalıdır.

---

## Önerilen plan düzeltmeleri

### Q1, Q2, Q3, Q4 ve Q5 Yanıtları ve Somut Çözüm Planı:

1. **Q1 — Baştaki Kayıp Sesin Kesin Nedeni:**
   `RecorderViewModel.swift:2469` konumunda ekran kaydı başladıktan sonra ikincil bileşenler (`MicrophoneAudioRecorder.swift:147`) başlatılmakta, mikrofon ilk veriyi alana kadar gecikmektedir. `ScreenCameraOverlayCompositionBuilder.swift:45` `RecordingTrackOffsets.make` ile bu fark hesaplanıp `ScreenCameraOverlayCompositionBuilder.swift:319` içinde `insertTimeRange(..., at: CMTimeAdd(segment.destinationStart, base))` ile ses izi kompozisyonda ileri itilmektedir. Oysa `.m4a` ses dosyası zaten mikrofondan ilk sesin alındığı andan itibaren başlamaktadır. Sesi ileri itmek, videonun ilk 3-10 saniyesini sessiz bırakmakta ve ses çizelgesini bozmaktadır.

2. **Q2 — Durdurma Hatası ve Takılan Durum Flag'i:**
   `RecorderViewModel.swift:2146` `markRecordingStopping()` çağrısı `recordingLifecycle.phase` değerini `.stopping` durumuna getirir. Ancak `RecorderViewModel.swift:2768-2784` `maybeFinalizeScreenRecordingExport()` içindeki guard ifadeleri bileşenlerden biri eksik kaldığında fonksiyonu sonlandırır ve `finishRecordingLifecycle()` (`RecorderViewModel.swift:2808`) çalıştırılamaz. Takılı kalan durum flag'i `recordingLifecycle.phase` (`.stopping`) ve `isPreparingRecording` / `isStopping` bayraklarıdır.

3. **Q3 — Duraklatma Aralıkları ve Zaman Tabanı Tutarlılığı:**
   Duraklatma aralıkları `ProcessInfo.processInfo.systemUptime` (konak saati) cinsinden ölçülür. Ekran kaydında `shiftedEarlier(by: offset)` ile bileşen zamanına kaydırılırken, Kamera ve Ses modlarında offset hesabı yapılmadan doğrudan uygulanır. Zaman tabanı teorik olarak konak saatidir ancak her bileşenin dosya başı (t=0) farklı konak zamanına denk geldiği için offset hataları duraklatma kesimlerini de saptırır.

4. **Q4 — Çift Tıklama ve Eşzamanlı Kayıt/Aktarım Riskleri:**
   Dışarı aktarım (`exportMP4`) arka planda çalışırken `finishRecordingLifecycle()` çalıştığı için `recordingLifecycle.phase` `.idle` durumuna döner. Kullanıcı bu esnada yeni bir kayıt başlatırsa `RecorderViewModel` üzerindeki `pendingScreenCaptureURL` vb. geçici dosya yolları ezilir ve yürütülen `AVAssetExportSession` dosyası silindiği için hata vererek çöker.

5. **Q5 — En Küçük, Test Edilebilir Çözüm ve Birim Testi:**
   - **Ortak Referans Zamanı (Master Session Zero):**
     Tüm kayıt bileşenlerine ilk örnek zaman damgalarını bağımsız toplattırmak yerine, kaydın gerçekten başladığı an konak saatinden tek bir `masterSessionZeroHostTime: CMTime` alınmalı ve `AVAssetWriter.startSession(atSourceTime:)` tüm yazıcılarda aynı master zamana anchored edilmelidir.
   - **Garantili Durum Temizliği (Lifecycle State Safety):**
     `RecorderViewModel.swift` içindeki dışarı aktarım ve tamamlama mantığı `defer` bloğuna alınmalı veya bir `finally` mekanizması ile `finishRecordingLifecycle()` çağrısının her durumda (hata, zaman aşımı, eksik bileşen) çalışması garanti edilmelidir.
   - **Örnek Birim Testi (Unit Test):**
     `Tests/VideoRecorderAppTests` altında `RecordingLifecycleStateTests.swift` dosyası eklenerek:
     1. Hazırlık ve durdurma esnasında bir bileşen hata verdiğinde `phase` değerinin `.idle` durumuna döndüğü,
     2. Gecikmeli mikrofon başlangıç senaryosunda `RecordingTrackOffsets` ve kompozisyon iz başlangıç zamanlarının (`destinationStart`) doğruluğu test edilmelidir.
