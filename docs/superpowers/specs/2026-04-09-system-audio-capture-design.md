# System Audio Capture Design

**Date:** 2026-04-09

## Goal

Kayda isteğe bağlı `sistem sesi` eklemek:

- varsayılan kapalı
- tüm modlarda aynı kontrol yüzeyi
- ilk teknik teslimatta gerçek kayıt desteği ekran ve pencere modlarında
- kamera modlarında ise kontrol görünür, durum metniyle mevcut sınır açıkça anlatılır

## Product Decision

`Sistem sesini dahil et` seçeneği tüm modlarda görünecek. Bunun nedeni erişilebilirlik ve bağlam ihtiyacının yalnızca ekran anlatımıyla sınırlı olmaması.

Ancak bu turda güvenilir kayıt desteği önce `ScreenCaptureKit` tabanlı ekran/pencere akışına eklenecek. Kamera kayıt hattısında aynı özelliğin gerçek mixing desteği sonraki faza bırakılacak.

Bu sayede ürün yüzeyi doğru olur, ama teknik davranış konusunda kullanıcı yanıltılmaz.

## UX

- Yeni toggle: `Sistem sesini dahil et`
- Varsayılan: kapalı
- Açıklama: `Mac'te çalan uygulama ve sistem seslerini kayda ekler.`

### Screen Modes

Toggle açıksa:

- ekran/pencere kaydı sistem sesini de yakalar
- mikrofonla birlikte kullanılabilir
- durum metni bunu kısaca belirtir

### Camera Modes

Toggle açıksa:

- kontrol görünür kalır
- durum metni şu anki sınırı söyler:
  - sistem sesi seçildi
  - bu sürümde gerçek kayıt desteği ekran modlarında aktif

## Architecture

### Shared View Model State

`RecorderViewModel` içinde ortak bir `isSystemAudioEnabled` durumu tutulacak. Böylece kullanıcı modlar arasında geçse de tercih kaybolmayacak.

### Screen Recorder Integration

`ScreenRecordingProviding.startRecording(...)` imzası genişletilecek ve `includeSystemAudio` parametresi alacak.

`ScreenRecorder`, `SCStreamConfiguration.capturesAudio` özelliğini bu parametreye göre ayarlayacak.

### Status Messaging

Durum metni iki şeyi açıkça ayıracak:

- mikrofon
- sistem sesi

Böylece kullanıcı kayda hangi seslerin gireceğini önceden anlayacak.

## Risks

### Audio Mix Complexity

Ekran modlarında sistem sesi ve mikrofon aynı anda geldiğinde seviye dengesi ileride ayrı tuning isteyebilir. İlk sürüm bunu ek denge ayarı olmadan sunacak.

### Camera Mode Expectation

Kontrol tüm modlarda göründüğü için kamera modunda da çalışması beklenecek. Bu yüzden durum metninin sınırı açıkça söylemesi kritik.

## Success Criteria

- ekran/pencere modlarında sistem sesi toggle'ı gerçek kayda etki ediyor
- varsayılan kapalı
- kontrol tüm modlarda görünüyor
- kamera modunda yanıltıcı davranmıyor
- build ve testler temiz geçiyor
