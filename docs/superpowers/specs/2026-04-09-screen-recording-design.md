# Screen Recording Design

**Date:** 2026-04-09

## Goal

Uygulamaya kamera kaydının yanına ekran kaydı ailesini eklemek:

- tam ekran kaydı
- pencere kaydı
- ekran kaydı + mikrofon
- ileride ekran + kamera overlay
- ileride sistem sesi

İlk teslimat, güvenilir ve sade bir ekran kayıt akışı olmalı. Daha büyük "stüdyo kayıt" deneyimi bunun üstüne kurulacak.

## Product Scope

### Phase 1

İlk uygulanacak kapsam:

- kayıt kaynağı seçimi: `Kamera`, `Tam Ekran`, `Pencere`
- tüm ekranları listeleme
- paylaşılabilir pencereleri listeleme
- seçilen ekranı veya pencereyi kaydetme
- mikrofon sesi ekleme
- kayıt sonrası MP4 export
- temel ekran kayıt izni yönlendirmesi

### Later Phases

Sonraki fazlara bırakılanlar:

- ekran + kamera picture-in-picture
- overlay konumu ve boyutu
- sistem sesi
- mikrofon + sistem sesi mix dengesi
- ekran alanı seçimi
- gelişmiş stüdyo layout'ları

## Approach Options

### Option A: ScreenCaptureKit tabanlı ayrı ekran kayıt motoru

Yeni bir ekran kayıt motoru `ScreenCaptureKit` ile ekran veya pencere görüntüsünü alır, ses ve video örneklerini dosyaya yazar.

Artıları:

- modern macOS capture yolu
- ekran, pencere ve sistem sesi için doğru temel
- ileride kamera overlay için uygun

Eksileri:

- mevcut `AVCaptureMovieFileOutput` hattısından farklı olduğu için ayrı kayıt yolu gerekir

### Option B: Baştan birleşik stüdyo pipeline

Kamera, ekran, mikrofon ve sistem sesini ilk günden tek bir özel recording pipeline içinde birleştirmek.

Artıları:

- uzun vadede tek motor olur

Eksileri:

- ilk teslimat gereğinden büyük olur
- hata yüzeyi yükselir

### Option C: Sadece tam ekran için minimal geçici çözüm

İlk sürümde yalnızca tam ekran kaydı eklemek.

Artıları:

- hızlı çıkar

Eksileri:

- pencere kaydı ve sonraki fazlar için yeniden mimari gerekir

## Recommended Approach

`Option A` seçilmeli.

Mevcut kamera kayıt hattısı korunacak. Bunun yanına ayrı bir `ScreenCaptureKit` tabanlı ekran kayıt motoru eklenecek. `RecorderViewModel`, seçilen kayıt kaynağına göre ya mevcut `CaptureRecorder` hattısını ya da yeni ekran kayıt hattısını kullanacak.

Bu yaklaşım ilk sürümü teslim etmeyi kolaylaştırır ve sonradan overlay ile sistem sesi için temiz genişleme noktaları bırakır.

## Architecture

### Recording Source Model

Yeni bir kayıt kaynağı modeli eklenecek:

- `camera`
- `screen`
- `window`

UI önce kayıt kaynağını seçecek. Kaynağa göre ilgili seçim kontrolleri görünecek.

### Screen Capture Service

Yeni `ScreenRecorder` tipi şu sorumlulukları alacak:

- paylaşılabilir ekranları yüklemek
- paylaşılabilir pencereleri yüklemek
- ScreenCaptureKit stream kurmak
- video örneklerini toplamak
- mikrofon sesini stream'e eklemek
- geçici `.mov` dosyası üretmek

### Unified View Model Flow

`RecorderViewModel` şu soyut akışı yönetecek:

- kaynak seçimi
- izin durumu
- hazır cihaz veya ekran listesi
- kayıt başlat/durdur
- export

Kamera için mevcut davranış korunacak. Ekran kayıtları için kaynak ve seçim doğrulaması ayrıca eklenecek.

### Export Strategy

İlk fazda ekran kaydı için de geçici kayıt dosyası üretilecek ve mevcut MP4 export akışına benzer final dosya üretimi yapılacak. Kamera auto-reframe ekran kaydına uygulanmayacak.

## Permissions

macOS ekran kaydı için sistem seviyesinde Screen Recording izni gerekir. İlk fazda:

- uygulama izni ön kontrol eder
- izin yoksa kullanıcıya açık durum metni verir
- gerekirse sistem yönlendirmesi sağlar

Kamera ve mikrofon izin akışı korunur.

## UX

### Source Selection

Ana akış:

- `Kayıt kaynağı`
- `Kamera` seçiliyse mevcut kamera/mikrofon kontrolleri
- `Tam ekran` seçiliyse ekran listesi
- `Pencere` seçiliyse pencere listesi

### Status

Durum metinleri sade olmalı:

- `Ekran kaydı için izin gerekli`
- `Ekran seçildi, kayıt hazır`
- `Pencere seçildi, kayıt hazır`
- `Kayıt yapılıyor`
- `Kaydedildi: ...`

## Testing

İlk faz için şu test yüzeyi eklenecek:

- kaynak seçim davranışı
- ekran/pencere seçim doğrulaması
- ekran kayıt izni durumu metni
- ekran kaydı modunda kamera bağımlılıklarının zorunlu olmaması
- source bazlı start/stop yönlendirmesi

Gerçek ScreenCaptureKit akışı bir protokol arkasına alınacak; testlerde stub kullanılacak.

## Risks

### Permission Friction

Ekran kaydı izni kullanıcı tarafında karışık olabilir. Bu yüzden metinler ve yönlendirme net olmalı.

### App Window Capture Edge Cases

Bazı pencereler paylaşılabilir listede değişken davranabilir. İlk sürümde seçili pencerenin sonradan kapanması veya değişmesi güvenli hata mesajına düşmeli.

### Audio Complexity

Mikrofon ilk fazda desteklenecek ama sistem sesi ikinci faza bırakılacak. Böylece ilk teslimat güvenilir kalır.

## Success Criteria

İlk teslimat başarılı sayılacak if:

- kullanıcı `Tam ekran` seçip kayıt alabiliyor
- kullanıcı `Pencere` seçip kayıt alabiliyor
- mikrofon sesi eklenebiliyor
- çıktı MP4 olarak kaydediliyor
- izin eksikse çökmeden, açık yönlendirmeyle kullanıcıyı durduruyor
