# Mode-Based Recording Hub Design

**Date:** 2026-04-09

## Goal

Uygulamanın ana kullanım modelini "ayarlar ekranı" yaklaşımından çıkarıp "mod seç, ilgili kontrolleri gör, hemen kayda başla" deneyimine çevirmek.

Bu değişiklikle kullanıcı:

- `Cmd-1` ile yatay kamera kaydına
- `Cmd-2` ile dikey kamera kaydına
- `Cmd-3` ile yatay ekran kaydına
- `Cmd-4` ile dikey ekran kaydına

anında geçebilmeli. Her mod yalnızca kendi bağlamında gerekli kontrolleri göstermeli.

## Product Scope

### In Scope

Bu teslimatta:

- ana kayıt deneyimi 4 sabit moda bölünecek
- menü komutları bu 4 modu doğrudan seçecek
- `Cmd-1 ... Cmd-4` kısayolları eklenecek
- ana ekran seçili moda göre sadeleşecek
- her mod kendi ilgili ayarlarını gösterecek
- tek kayıt düğmesi korunacak: `Cmd-R`
- mevcut kamera ve ekran kayıt altyapısı bu yeni mod yapısına taşınacak

### Out of Scope

Bu teslimata dahil değil:

- dikey ekran kaydı için gelişmiş akıllı kompozisyon
- ekran + kamera overlay
- kamera kutusu konumu için 9 bölge desteği
- kamera kutusu boyut kontrolü
- sistem sesi
- mikrofon ve sistem sesi mix dengesi
- preset bazlı gelişmiş menü veya ayrı profil editörü

Bu kalemler sonraki fazlara bırakılacak.

## User Problem

Mevcut arayüzde kaynak, mod, cihaz ve izin kontrolleri aynı yüzeyde birikiyor. Bu şu sorunları doğuruyor:

- kullanıcı önce "ne kaydı alıyorum?" sorusuna değil "hangi kontrol ne işe yarıyor?" sorusuna maruz kalıyor
- ekran kaydı ve kamera kaydı ayarları aynı yerde bulununca kafa karışıyor
- klavye kısayolu ile hızlı mod değişimi yok
- hedef format odaklı iş akışı zayıf kalıyor

Kullanıcının zihinsel modeli teknik olmamalı. "Kamera mı ekran mı, yatay mı dikey mi?" seçimi en başta ve tek hamlede yapılmalı.

## Mode Model

Yeni ana model `RecordingPreset` benzeri tek bir mod olmalı. Kaynak ve yön bilgisi kullanıcıya ayrı ayrı gösterilmek yerine tek mod olarak sunulmalı.

Önerilen modlar:

- `horizontalCamera`
- `verticalCamera`
- `horizontalScreen`
- `verticalScreen`

Bu model UI'da birincil karar noktası olacak. Mevcut `RecordingSource` ve `RecordingMode` kavramları içeride yardımcı kalabilir, ama kullanıcı deneyimi bunları ayrı ayrı seçtirmemeli.

## Approach Options

### Option A: 4 Sabit Mod

Ana yüzeyde ve menüde 4 sabit kayıt modu bulunur. Kullanıcı doğrudan istediği sonuca gider.

Artıları:

- en sade akış
- erişilebilirlik açısından net
- kısayol kullanımı çok doğal
- kullanıcıyı teknik modellere boğmaz

Eksileri:

- ileride daha fazla varyant gelirse mod sayısı büyüyebilir

### Option B: Kaynak ve Yönü Ayrı Seçtirme

Kullanıcı önce kamera/ekran, sonra yatay/dikey seçer.

Artıları:

- veri modeli daha genel kalır

Eksileri:

- kullanıcı için daha fazla adım
- hızlı kayıt akışını zayıflatır
- erişilebilirlikte daha çok odak durağı üretir

### Option C: 4 Ana Mod + Gelişmiş Ayarlar

Ana ekranda 4 mod vardır; istenirse gelişmiş alan açılır.

Artıları:

- uzun vadede esnek
- ileri kullanıcılar için iyi temel

Eksileri:

- ilk teslimat için gereğinden büyük olabilir

## Recommended Approach

`Option A` seçilmeli.

İlk teslimatın amacı hız, sadelik ve güvenilirlik. Kullanıcı için en doğru model "hangi kayıt türünü istiyorum?" sorusuna tek adımda cevap vermek. Bu nedenle 4 sabit mod yaklaşımı ilk sürüm için en güçlü seçenek.

İç mimari ise ileride `Option C`ye evrilebilecek şekilde kurulmalı. Yani bugünden itibaren tek bir `recordingPreset` kullanılsın, ama modlara bağlı ek seçenekler sonradan genişletilebilsin.

## UX Design

### Main Surface

Ana ekran şu sırayla çalışmalı:

1. Kayıt modu seçimi
2. Seçili moda ait ilgili kontroller
3. İzin durumu
4. Tek kayıt düğmesi
5. Durum metni

Ana fark şu olacak: kullanıcı aynı ekranda her şeyi görmeyecek; yalnızca seçtiği moda ait kontrolleri görecek.

### Mode Shortcuts

Şu kısayollar eklenmeli:

- `Cmd-1`: Yatay Kamera
- `Cmd-2`: Dikey Kamera
- `Cmd-3`: Yatay Ekran
- `Cmd-4`: Dikey Ekran
- `Cmd-R`: Kaydı başlat / durdur

Bu kısayollar menüden de görünür olmalı.

### Mode-Specific Controls

#### Yatay Kamera

Gösterilecek alanlar:

- kamera seçimi
- mikrofon seçimi
- otomatik yeniden kadrajlama
- kadraj koçu

#### Dikey Kamera

Gösterilecek alanlar:

- kamera seçimi
- mikrofon seçimi
- otomatik yeniden kadrajlama
- kadraj koçu

Bu mod ile yatay kamera arasındaki ana fark iç kayıt modu olacak.

#### Yatay Ekran

Gösterilecek alanlar:

- ekran mı pencere mi alt seçimi
- seçili ekrana veya pencereye ait picker
- mikrofon seçimi

Bu mod ilk sürümde YouTube ve klasik ekran anlatımı amacıyla tanımlanacak.

#### Dikey Ekran

Gösterilecek alanlar:

- ekran mı pencere mi alt seçimi
- seçili ekrana veya pencereye ait picker
- mikrofon seçimi

İlk sürümde bu mod yalnızca "dikey hedefli ekran kaydı" niyetini temsil edecek. Daha gelişmiş 9:16 kompozisyon ikinci fazda geliştirilecek.

### Status Messaging

Durum metinleri seçili moda göre kısa ve bağlamsal kalmalı:

- `Yatay kamera kaydı hazır`
- `Dikey kamera kaydı hazır`
- `Yatay ekran kaydı hazır`
- `Dikey ekran kaydı hazır`
- `Kayıt için ekran kaydı izni gerekli`
- `Kayıt hazırlanıyor`
- `Kayıt yapılıyor`

## Architecture

### New Recording Preset Layer

View model seviyesinde yeni bir mod kavramı tanımlanmalı. Bu mod aşağıdaki alanları türetmeli:

- aktif kaynak türü
- aktif kayıt yönü
- ekran kaydında hedef sunum tipi
- hangi kontrollerin görünür olduğu
- hangi izinlerin zorunlu olduğu

Bu katman ana UI kararlarını tek yerden üretmeli.

### Backward-Compatible Integration

Mevcut sistem tamamen atılmamalı.

- kamera akışı mevcut `RecordingMode` ve kamera recorder hattısını kullanmaya devam eder
- ekran akışı mevcut screen recorder hattısını kullanmaya devam eder
- yeni preset katmanı bunların üstünde orkestrasyon yapar

Bu sayede değişiklik ürün davranışında büyük olur, ama altyapı riski sınırlı kalır.

### Screen Submode

Ekran modlarında ayrıca küçük bir alt seçim korunmalı:

- `Tam Ekran`
- `Pencere`

Yani üst seviye mod `yatay ekran / dikey ekran`, alt seviye kaynak ise `tam ekran / pencere` olacak.

Bu ayrım kullanıcı için mantıklı çünkü "ekran anlatımı" bağlamını korurken yine de kaynak esnekliği sağlıyor.

## Menu Design

`Kayıt` menüsü genişletilmeli.

Önerilen yapı:

- `Yatay Kamera Modu`
- `Dikey Kamera Modu`
- `Yatay Ekran Modu`
- `Dikey Ekran Modu`
- ayraç
- `Kaydı Başlat / Durdur`
- kamera modundaysa `Kadraj Koçunu Aç / Kapat`

Menü başlıkları seçili modu görünür şekilde yansıtmalı.

## Accessibility

Bu değişiklik erişilebilirlik açısından ürünün ana kazanımlarından biri olacak.

Hedefler:

- kullanıcı modunu tek kısayolla değiştirebilmeli
- odak sırası daha kısa olmalı
- seçili moda ait olmayan kontroller DOM/UI ağacında gereksiz yere kalmamalı
- durum metinleri mod bağlamını açıkça taşımalı

Özellikle VoiceOver kullanımında "önce modu seç, sonra o modun birkaç kontrolüne git" akışı mevcut yapıdan çok daha anlaşılır olacaktır.

## Risks

### Overloaded Mode Responsibilities

Yeni preset katmanı fazla iş yüklenirse view model karmaşıklaşabilir. Bu nedenle mod türetme mantığı yardımcı bir tipe ayrılmalı.

### Dikey Screen Expectations

`Dikey ekran kaydı` adı kullanıcıda daha akıllı kompozisyon beklentisi yaratabilir. İlk sürüm bu beklentiyi tam karşılamayabilir. Bu yüzden ilk teslimat metinleri "dikey hedefli kayıt modu" hissini verirken aşırı vaatkar olmamalı.

### Keyboard Shortcut Conflicts

`Cmd-1 ... Cmd-4` uygulama içi menü yapısıyla uyumlu tanımlanmalı. Menü komutları ve UI davranışı tek kaynaktan beslensin.

## Testing

Şu test yüzeyi eklenmeli:

- `Cmd-1 ... Cmd-4` ile doğru preset seçimi
- her preset için doğru görünür kontrol seti
- preset değişince kaynak ve mode türetme doğruluğu
- ekran presetlerinde kamera kontrollerinin gizlenmesi
- kamera presetlerinde ekran kontrollerinin gizlenmesi
- durum metninin preset bazlı değişmesi
- `Cmd-R` ile seçili preset üzerinde doğru start/stop yolu

## Success Criteria

Bu teslimat başarılı sayılacak if:

- kullanıcı 4 ana mod arasında tek kısayolla geçebiliyor
- her mod yalnızca ilgili kontrolleri gösteriyor
- kayıt başlatma mantığı bozulmadan devam ediyor
- kamera ve ekran kayıt akışları yeni mod modeline sorunsuz taşınıyor
- arayüz mevcut haline göre daha kısa ve daha anlaşılır hissediliyor
