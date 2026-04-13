# Auto Reframe Design

## Goal

Tek kişilik çekimlerde uygulamanın görüntüyü yazılımsal olarak daha düzgün kadrajlaması. İlk sürümde sistem, kişi kadrajda hafif kaymışsa önizlemede otomatik yeniden kadraj uygular, hareketleri yumuşatır ve kullanıcı isterse bu davranışı kapatabilir.

## Why

Mevcut kadraj koçu yalnızca sesli yönlendirme veriyor. Bu, erişilebilirlik açısından değerli olsa da küçük hizalama hatalarında kullanıcıya fazladan yük bindiriyor. Otomatik yeniden kadrajlama, kullanıcıyı yormadan daha düzenli bir görüntü üretmeyi hedefliyor.

## Scope

### In Scope

- Tek kişi algılandığında otomatik yeniden kadrajlama hedefi üretmek
- Yatay ve dikey mod için farklı hedef ölçek ve düşey yerleşim kullanmak
- Önizlemede yumuşak dijital pan/zoom uygulamak
- Özelliği açıp kapatmak için tek bir kontrol sunmak
- İki veya daha fazla kişi algılandığında tam kadraja yumuşak dönüş yapmak

### Out of Scope

- İki kişilik otomatik yeniden kadraj
- Arka plan değiştirme veya renk/ışık işleme
- Kayıt anında canlı frame-by-frame özel encode hattısı

## Constraints

- Uygulama şu anda canlı önizlemede `AVCaptureVideoPreviewLayer`, kayıt tarafında `AVCaptureMovieFileOutput` kullanıyor.
- `AVCaptureMovieFileOutput` hattısı, kare bazlı dinamik crop/position bilgisini doğrudan kayıt akışına uygulamak için uygun değil.
- Bu nedenle kayıt dosyası için güvenli yol, kayıt bittikten sonra mevcut `.mov` çıktısını zaman bazlı bir video composition ile yeniden dışa vermektir.

## User Experience

- Özellik adı: `Otomatik yeniden kadrajlama`
- Varsayılan: açık
- Tek kişi varken sistem yüzü doğal konuşma kadrajına yaklaştırır
- Kişi merkezden kaydığında görüntü zıplamaz; kadraj yumuşak hareket eder
- Kişi kısa süre kaybolursa son crop kısa süre korunur
- İki kişi görünürse sistem full frame'e geri döner
- Kayıt tamamlandıktan sonra oluşturulan MP4, toplanan crop zaman çizelgesine göre yeniden kadrajlanır

## Design

### AutoReframeEngine

Giriş olarak `FrameAnalysis` ve `RecordingMode` alır. Çıkış olarak 0...1 aralığında normalize edilmiş bir crop rect üretir.

- Tek kişi yoksa full-frame döner
- Güven düşükse full-frame döner
- Yüz genişliğini hedef konuşma kadrajına göre yorumlar
- Maksimum crop oranını düşük tutar
- Düşey yerleşimde yüzü tam merkeze değil, göz çizgisi üst bölgeye yakın olacak şekilde konumlandırır

### AutoReframeSmoother

Motorun ürettiği hedef crop'u yumuşatarak uygular.

- Exponential smoothing kullanır
- Crop değişimlerini frame-frame yumuşatır
- Geçici yüz kaybında son kararlı crop'u korur
- Uzun kayıpta full-frame'e geri yaklaşır

### Preview Integration

`VideoPreviewView`, oturumun görüntüsünü gösteren `AVCaptureVideoPreviewLayer` üstünde affine transform uygular.

- Ölçek: crop genişliğinin tersinden türetilir
- Konum: crop merkezine göre hesaplanır
- Uygulama `resizeAspectFill` ile çalışır

### View Model Integration

`RecorderViewModel`, preview frame analizini hem kadraj koçu hem otomatik yeniden kadraj için paylaşır.

- Yeni durum: `isAutoReframeEnabled`
- Yeni durum: `currentAutoReframeCrop`
- Preview frame akışı, koç veya auto-reframe açıkken aktif olur

### Recording Integration

Kayıt sırasında her analiz için zaman damgalı crop anahtar kareleri toplanır.

- Kayıt başında boş bir `AutoReframeTimeline` oluşturulur
- Her preview analizinde mevcut yumuşatılmış crop ve zaman bilgisi timeline'a yazılır
- Kayıt tamamlanınca export aşamasında timeline'dan `AVMutableVideoComposition` üretilir
- Export hattısı, uygun veri varsa composition ile MP4 üretir
- Yeterli veri yoksa normal export fallback çalışır

## Error Handling

- Analiz yoksa crop aniden sıfırlanmaz
- Düşük güvenli analizler crop üretmez
- Çok kişi algılanırsa full-frame'e kontrollü dönüş yapılır
- Timeline boşsa veya composition kurulamazsa kayıt akışı bozulmadan normal MP4 export yapılır

## Testing

- Tek kişi soldaysa crop merkezi sola kayar
- Tek kişi küçük görünüyorsa sınırlı zoom uygulanır
- Çok kişi görünüyorsa full-frame döner
- Yumuşatıcı ilk adımda tam hedefe sıçramaz
- View model auto-reframe açıkken crop günceller
- View model auto-reframe kapalıyken full-frame korur
- Timeline kayıt süresi boyunca anahtar kare toplar
- Export builder, anahtar karelerden composition instruction üretir
- Timeline yoksa export normal MP4 fallback ile tamamlanır
