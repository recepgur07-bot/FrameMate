# Light-Aware Capture Coach Design

## Goal

Kadraj koçunu görme engelli kullanıcılar için daha güvenilir bir çekim koçuna doğru genişletmek. İlk dilimde koç, kamera görüntüsü çok karanlıksa kullanıcıyı kayıt öncesinde veya canlı önizlemede uyarır.

## Scope

- Kareden basit bir ışık analizi üret.
- Işık çok düşükse kadraj önerisinin önüne ışık önerisini koy.
- Işık yeterliyse mevcut kadraj koçu davranışını koru.
- Yüz algılanamasa bile görüntü karanlıksa önce ışığı açmayı öner.

## Non-Goals

- Renk düzeltme, LUT, retouch veya gerçek görüntü işleme.
- macOS Edge Light veya Studio Light ayarını programatik açmak.
- Detaylı pozlama histogramı veya yüz bazlı parlaklık ölçümü.

## Experience

Koç açıkken kullanıcı düşük ışıkta şu tür kısa bir yönlendirme duyar ve ekranda görür:

> Işık düşük, lambayı aç veya ekran parlaklığını artır

Bu öneri yüz algılanamadı mesajından daha önce gelir, çünkü karanlık ortam yüz algılamayı da bozabilir.

## Technical Approach

- `FrameLightingAnalysis` düşük maliyetli bir ortalama parlaklık sinyali taşır.
- `CaptureCoachingEngine` ışık ve kadraj önerileri arasında öncelik seçer.
- `FrameAnalysisService` yüz analizinden bağımsız olarak pixel buffer parlaklığını hesaplar.
- `RecorderViewModel` eski kadraj akışını korur, ama koç mesajını yeni capture coach üzerinden üretir.

## Testing

- Düşük ışık varsa kadraj uygun olsa bile ışık önerisi döner.
- Işık yeterliyse mevcut kadraj önerisi korunur.
- Yüz algılanamayıp ışık düşükse yüz yerine ışık önerisi döner.
