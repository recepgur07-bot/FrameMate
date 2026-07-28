## Sonuç

Revizyon gerekli. Q1’in mekanik kökü, `RecordingPauseTimeline`ın `ProcessInfo.systemUptime` farkından üretilip (`RecorderViewModel.swift:1661-1665`, `RecorderViewModel.swift:1702-1717`) dışa aktarımda dosyaların yerel t=0’ına doğrudan uygulanmasıdır. Screen yolunda bileşen PTS ofsetleri hesaplanıp dönüştürülüyor (`ScreenCameraOverlayCompositionBuilder.swift:34-57`, `ScreenCameraOverlayCompositionBuilder.swift:329-340`); fakat ekran ana dosyasının t=0’ı da `startCapture()` dönüşü değil ilk screen sample PTS’sidir (`ScreenRecorder.swift:185-188`, `ScreenRecorder.swift:266-282`). Kamera ve audio-only yollarında aynı dönüşüm hiç yoktur (`RecorderViewModel.swift:128-139`, `RecorderViewModel.swift:2990-3035`). Bu nedenle bir erken pause (özellikle start cue / aygıt hazırlığı nedeniyle gözlenen yaklaşık 10 saniyelik gecikme) kesimi gerçek dosya zamanından kaydırır; kesilen aralık dosyanın başına veya baştan sonraki yanlış bölüme düşer.

Q2 için “Start → Stop → ekranda hata”nın kesin hata kodu log/çalışan uygulama olmadan doğrulanamadı. Ancak hemen stopta örnek gelmemiş recorder’ın `emptyRecording` üretme yolu açıktır: `stopRecording()` → recorder stop → sample yoksa failure (`MicrophoneAudioRecorder.swift:187-224`, `SystemAudioRecorder.swift:104-143`, `ScreenRecorder.swift:228-249`) → completion handler → `report` (`RecorderViewModel.swift:2696-2711`, `RecorderViewModel.swift:3482-3492`). Bu hata yolu ViewModel’i takılı bırakmaz; `report` lifecycle’ı idle’a çeker. Ayrı ve deterministik takılma ise audio-only’de hem mikrofon hem sistem sesi kapalıyken oluşur: başlangıç iki pending sonucu `.success(nil)` yapar (`RecorderViewModel.swift:2341-2347`), stop hiçbir recorder’ı durdurmaz (`RecorderViewModel.swift:2120-2126`), completion/finalize hiç gelmez ve `recordingLifecycle.phase` `.stopping` kalır (`RecorderViewModel.swift:2313-2317`, `RecordingLifecycleState.swift:31-39`).

Q3: pause aralıkları hiçbir modda kanıtlanabilir biçimde her kesilen dosyanın yerel t=0 zamanında üretilmiyor. Screen’de ana ekran için start-capture-return ile first-frame PTS ayrıdır; secondary dosyalar için offset dönüşümü var. Kamera ana movie ve ayrı system-audio dosyasına ham timeline uygulanır. Audio-only’de mikrofon ve sistem-audio dosyalarına da ham timeline uygulanır. Q4: ViewModel, capture completion’da lifecycle’ı export başlamadan idle yapıyor (`RecorderViewModel.swift:2622-2628`, `RecorderViewModel.swift:2725-2728`, `RecorderViewModel.swift:2806-2828`); yeni kayıt başlatılabilirken eski export closure’ı `lastSavedURL`, `completedRecording`, `statusText` ya da hata durumunu koşulsuz değiştirebilir (`RecorderViewModel.swift:2642-2663`, `RecorderViewModel.swift:2749-2763`, `RecorderViewModel.swift:2849-2858`).

## Kritik bulgular

- P0 — Pause clock dosya clock’u değildir. `recordingStartUptime`, screen için `SCStream.startCapture()` döndükten sonra alınır (`RecorderViewModel.swift:2458-2470`) ve pause ofsetleri uptime ile hesaplanır (`RecorderViewModel.swift:1702-1717`); oysa screen dosyasının gerçek sıfırı ilk sample PTS’dir (`ScreenRecorder.swift:34-56`, `ScreenRecorder.swift:266-282`). İlk frame gecikmesi D ise tüm pause kesimleri screen dosyasında D saniye yanlış konumdadır. Bu, “ilk ~10 s yok” semptomunu bir pause/start gecikmesi ile mekanik olarak açıklar.

- P0 — Audio-only’nin iki ayrı dosyası kendi ilk sample PTS’lerinde writer session başlatır (`MicrophoneAudioRecorder.swift:240-252`, `SystemAudioRecorder.swift:159-171`), fakat exporter her ikisine aynı, çevrilmemiş `pauseTimeline.segments(for:)` uygulayıp ikisini t=0’a yerleştirir (`RecorderViewModel.swift:77-89`, `RecorderViewModel.swift:121-139`). Başlatma sıralı olduğundan mikrofon/system-audio başlangıç gecikmeleri farklıysa, aynı pause aralığı iki farklı gerçek konuşma/ses bölümünü keser.

- P0 — Camera modunda ana movie dosyasına ve ayrı system-audio dosyasına aynı ham pause segmentleri uygulanır (`RecorderViewModel.swift:2996-3017`, `RecorderViewModel.swift:3021-3035`). `systemAudioRecorder` önce başlatılıyor, kamera sonra başlıyor (`RecorderViewModel.swift:2084-2098`); dolayısıyla dosya t=0’ları eşit değildir. Camera yolunda `firstSamplePresentationTime` veya `RecordingTrackOffsets` kullanılmıyor.

- P1 — Screen export only has a partial correction. `RecordingTrackOffsets.make` ortak host-clock PTS’lerini kullanarak secondary track’leri screen’e göre kaydırıyor (`RecorderViewModel.swift:2794-2805`, `ScreenCameraOverlayCompositionBuilder.swift:34-57`) ve `shiftedEarlier` bu offset ile secondary pause kesimini yerel dosya zamanına taşıyor (`RecordingPauseTimeline.swift:102-119`, `ScreenCameraOverlayCompositionBuilder.swift:329-340`). Ancak ana screen pause başlangıcı hâlâ start-capture-return tabanlıdır; PTS-first-frame farkı için dönüşüm yoktur.

- P1 — Audio-only “kaynak yok” kombinasyonu stopta callback üretmez ve lifecycle `.stopping`de kalır. İki pending sonuç başlangıçta hazır sayılır (`RecorderViewModel.swift:2341-2347`), stop çağrısı ise yalnız `nil` pending sonucu olan gerçek recorder’lara gider (`RecorderViewModel.swift:2120-2126`); `maybeFinalizeAudioRecordingExport` çağrısı sadece completion handlerlardan gelir (`RecorderViewModel.swift:2696-2715`). Sonuç: `isRecording` false görünür fakat state machine idle değildir.

- P1 — Önceki export tamamlanmadan yeni kayıt başlatma korunmuyor. Completion handler’lar pending state’i resetleyip lifecycle’ı idle’a indiriyor (`RecorderViewModel.swift:2606-2628`, `RecorderViewModel.swift:2723-2728`, `RecorderViewModel.swift:2806-2808`); export Task’ları session/generation kimliği kontrol etmeden UI durumunu yazıyor (`RecorderViewModel.swift:2642-2663`, `RecorderViewModel.swift:2749-2763`, `RecorderViewModel.swift:2849-2858`). `ScreenRecorder` kendi geç callback’lerini generation ile filtreliyor (`ScreenRecorder.swift:28-33`, `ScreenRecorder.swift:357-371`), fakat ViewModel/export katmanında eşdeğer koruma yok.

- P2 — Çift stop güvenli bir state transition değil. `toggleRecording` yalnız `isRecording`e bakar (`RecorderViewModel.swift:1614-1619`), fakat doğrudan `stopRecording()` her çağrıda component stop ve `markRecordingStopping()` çalıştırır (`RecorderViewModel.swift:2116-2153`). `beginStopping()` yalnız recording fazından geçer, dönüş değeri yok sayılır (`RecorderViewModel.swift:2313-2317`, `RecordingLifecycleState.swift:31-35`). Recorder’ların çoğu kendi `isStopping` korumasına sahiptir (`ScreenRecorder.swift:195-198`, `MicrophoneAudioRecorder.swift:187-189`, `SystemAudioRecorder.swift:104-106`), ancak ViewModel’de idempotence/session sahipliği yoktur.

## Onaylanan kararlar

- Screen’de komponent dosyalarının bağımsız t=0’a sahip olduğu ve bunların first-sample host-clock PTS’leriyle hizalanması gerektiği doğru karardır (`ScreenCameraOverlayCompositionBuilder.swift:13-26`, `ScreenCameraOverlayCompositionBuilder.swift:34-57`).

- Screen secondary track’leri için pause range’i `offset` kadar yerel dosya zamanına çevirme yaklaşımı doğru yönlüdür (`RecordingPauseTimeline.swift:102-119`, `ScreenCameraOverlayCompositionBuilder.swift:257-340`). Aynı kural kamera system-audio ve audio-only dosyalarına da uygulanmalıdır.

- Capture seviyesinde gerçek pause yerine exportta aralık çıkarma tasarımı, tek bir doğru session-zamanı ve her asset için açık dönüşüm sağlanırsa uygulanabilir durumdadır (`RecorderViewModel.swift:1646-1655`, `RecorderViewModel.swift:1702-1717`, `ScreenCameraOverlayCompositionBuilder.swift:98-104`).

- `ScreenRecorder`ın geç callback’i generation ile düşürmesi doğru korumadır; bu koruma ViewModel export completion’larına genişletilmelidir (`ScreenRecorder.swift:28-33`, `ScreenRecorder.swift:357-371`).

## Riskli varsayımlar

- `RecordingTrackOffsets` PTS’lerin ortak host clock’ta doğrudan karşılaştırılabilir olduğunu varsayıyor (`ScreenCameraOverlayCompositionBuilder.swift:34-37`). ScreenCaptureKit ile AVCapture PTS eşlemesi gerçek cihazda, uyku/uyandırma ve farklı aygıtlarda ölçülmeden kesin kabul edilmemeli.

- `primaryCaptureStartUptime`ın “capture began” olduğu varsayılıyor (`RecorderViewModel.swift:1133-1136`, `RecorderViewModel.swift:2468-2470`), ama kod yalnız API’nin `startCapture()` dönüş anını kaydediyor; ilk dosya sample’ını değil (`ScreenRecorder.swift:185-188`, `ScreenRecorder.swift:266-282`).

- Testler state temizliğini denetliyor (`RecorderViewModelTests.swift:3890-3895`) ama fake recorder’ların gerçek asenkron startup, first-sample PTS, export sürmesi ve geç callback davranışını temsil ettiğine dair kanıt yok. Bu nedenle mevcut start/pause/stop testleri clock hatasını yakalayamaz.

- Q2’de kullanıcıya görünen spesifik hata metni/error domain paylaşılmadığı için `emptyRecording` yolunun bildirilen hatanın tek sebebi olduğu ileri sürülemez. Bu yol koddan kanıtlıdır; gerçek semptomun eşleşmesi runtime log ile doğrulanmalıdır (`RecorderViewModel.swift:3482-3490`).

## Doğrulama listesi

- Screen: start cue etkin, secondary mikrofon geç başlıyor, ilk screen PTS / `startCapture()` dönüş uptime’ı / mikrofon ilk PTS kaydedilsin; pause begin/end hem session PTS hem dosya-local PTS olarak loglansın (`RecorderViewModel.swift:2434-2470`, `RecorderViewModel.swift:2797-2805`). Export edilen video/audio’da kesilen örnek aralığı beklenen konuşma aralığıyla karşılaştırılsın.

- Camera: system audio etkin iken camera ve system-audio first sample PTS’leri ve ayrı dosya t=0’ları ölçülsün; tek pause aralığının iki dosyada aynı gerçek duvar-zamanını çıkarıp çıkarmadığı doğrulansın (`RecorderViewModel.swift:2084-2098`, `RecorderViewModel.swift:2990-3035`).

- Audio-only: mikrofon + sistem sesi sıralı başlangıçta iki first PTS farkı kontrollü fake ile verilsin; pause segmentlerinin her assette offset dönüştürülerek kesildiği assert edilsin (`RecorderViewModel.swift:77-89`, `RecorderViewModel.swift:121-139`).

- Üç modun her biri için start → pause → resume → stop ve pause → doğrudan stop senaryosu, cue gecikmesi ve first-sample gecikmesi en az 5–10 s enjekte edilerek çalıştırılsın; çıktı süresi ve baştaki referans sesi/frame’i kontrol edilsin (`RecorderViewModel.swift:1639-1717`, `RecorderViewModel.swift:2116-2153`).

- Audio-only’de mic yok + system audio kapalı kombinasyonunun ya başlangıçta reddedildiği ya da stop sonrası lifecycle’ın idle olduğu test edilsin (`RecorderViewModel.swift:2341-2347`, `RecorderViewModel.swift:2714-2728`, `RecordingLifecycleState.swift:31-39`).

- Yeni session, eski export sürerken başlatılsın; eski başarı ve hata completion’larının yeni session’ın `lastSavedURL`, `completedRecording`, `statusText`, `errorText` değerlerini değiştirmediği assert edilsin (`RecorderViewModel.swift:2642-2663`, `RecorderViewModel.swift:2749-2763`, `RecorderViewModel.swift:2849-2858`).

## Önerilen plan düzeltmeleri

1. Tek oturum zaman tabanı tanımlayın: ilk kabul edilen primary sample PTS (screen için first screen PTS; camera/audio-only için seçilen primary recorder’ın first PTS) ve buna bağlı monoton session-seconds. `startCapture()` dönüş uptime’ını dosya kesim zamanı olarak kullanmayın (`ScreenRecorder.swift:185-188`, `ScreenRecorder.swift:266-282`). UI süresi gerekirse ayrı uptime sayacı olarak kalabilir.

2. Her recorder için `firstSamplePresentationTime`ı zorunlu, test edilebilir metadata yapın ve exporta `RecordingTrackOffsets` benzeri ortak `RecordingAssetTiming` verin. Pause range önce primary session zamanında üretilsin, sonra her dosya için `localRange = sessionRange - assetOffset` ile dönüştürülsün. Screen’deki mevcut `shiftedEarlier` mantığını camera system-audio ve audio-only microphone/system-audio için ortaklaştırın (`RecordingPauseTimeline.swift:102-119`, `ScreenCameraOverlayCompositionBuilder.swift:329-340`, `RecorderViewModel.swift:121-139`, `RecorderViewModel.swift:3021-3035`).

3. Başlatma aşamasını “ilk sample hazır” sınırına kadar açıkça modelleyin veya pause’u first-primary-sample gelene dek engelleyin. Bu, start cue / aygıt setup süresinin clock origin’e sızmasını önler (`RecorderViewModel.swift:2038-2057`, `RecorderViewModel.swift:2297-2301`, `RecorderViewModel.swift:2452-2549`).

4. ViewModel’e monoton `recordingGeneration` ekleyin. Pending sonuçlar, finalize ve export Task’ları generation taşısın; yalnız aktif generation UI/pending state yazabilsin. Export sürerken yeni startı engelleyin veya eski exportun sonucu ayrı immutable result deposuna yazılsın; `isRecording == false` tek başına yeniden başlatma izni olmamalı (`RecorderViewModel.swift:2622-2665`, `RecorderViewModel.swift:2714-2764`, `RecorderViewModel.swift:2768-2860`).

5. Stop transition’ını lifecycle tarafından koruyun: `beginStopping()` başarısızsa component stop/finalize tekrarını yapmayın; “kaynak yok” audio-only konfigürasyonunu start öncesinde reddedin ya da explicit zero-source finalize edin (`RecordingLifecycleState.swift:31-39`, `RecorderViewModel.swift:2116-2153`, `RecorderViewModel.swift:2341-2347`).

6. En küçük yakalayıcı unit test: fake primary first PTS = 100 s, secondary = 110 s; session pause = [20, 25]. Secondary local kesimin [10, 15] ve output yerleşiminin 10 s olduğu assert edilsin. Aynı fixture camera system-audio ve audio-only için çalışsın; start-return uptime ile first sample arasındaki 10 s farkı özellikle enjekte edilsin (`ScreenCameraOverlayCompositionBuilder.swift:34-57`, `RecordingPauseTimeline.swift:102-119`). Ayrı testte eski export completion’ı generation N, yeni kayıt N+1 iken UI state’i değiştirememelidir (`ScreenRecorder.swift:357-371`, `RecorderViewModel.swift:2642-2663`).
