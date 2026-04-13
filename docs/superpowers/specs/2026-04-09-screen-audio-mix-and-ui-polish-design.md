# Screen Audio Mix And UI Polish Design

**Date:** 2026-04-09

## Goal

Ekran ve pencere kayitlarinda mikrofon ile sistem sesini gercekten ayri kontrol edebilmek ve ekran kaydi ayarlarini VoiceOver ile daha sade kullanilabilir hale getirmek.

## Scope

Bu turda:

- ekran/pencere kaydinda mikrofonu ayri ses dosyasi olarak toplamak
- export sirasinda ekran videosu icindeki sistem sesi ile bu mikrofon dosyasini birlikte mixlemek
- mevcut `mikrofon seviyesi` ve `sistem sesi seviyesi` slider'larini ekran modlarinda da gercekten uygulamak
- ekran modu ayarlarini `Kaynak`, `Ses`, `Kamera Kutusu` bloklari halinde sadeleştirmek
- gereksiz veya etkisiz kontrolleri gizlemek

Bu turda olmayacaklar:

- otomatik ducking
- canli kayit sirasinda anlik ses seviyesi metering
- ekran kaydinda sistem sesi icin ayri cihaz secimi

## Approach

1. `ScreenRecorder` ekran videosunu ve ScreenCaptureKit sistem sesini toplamaya devam edecek.
   - Ancak mikrofon artik bu akis icine gomulmeyecek.

2. Yeni bir `MicrophoneAudioRecorder` eklenecek.
   - secilen mikrofonu `m4a` olarak ayri kaydedecek
   - ekran modlarinda gerekiyorsa paralel calisacak

3. Ekran export hatti genisletilecek.
   - ekran videosunun audio track'leri `system audio` olarak kabul edilecek
   - harici mikrofon dosyasi composition'a ayri audio track olarak eklenecek
   - `RecordingAudioMixBuilder` ile iki ses grubuna ayri volume uygulanacak

4. UI sadeleştirilecek.
   - ekran modlarinda ayarlar mantikli gruplara ayrilacak
   - mikrofon secimi yoksa mikrofon slider'i gosterilmeyecek
   - sadece aktif olan kontroller ekranda kalacak

## Defaults

- mikrofon secimi bos ise ekran kaydi mikrofonsuz devam eder
- sistem sesi toggle'i kapaliysa yalnizca mikrofon kaydi yapilabilir
- iki ses seviyesi de varsayilan olarak `1.0`

## Testing

- ekran kaydinda mikrofon recorder'i ayrik baslatilir
- ekran kaydi provider'a mikrofon ID gonderilmez
- ekran export audio mix'i mikrofon ve sistem sesi track'lerine ayri volume uygular
- ekran modu UI durum bayraklari gereksiz kontrolleri gizler
