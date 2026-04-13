# Audio Mix Controls Design

**Date:** 2026-04-09

## Goal

Kullanicinin mikrofon ve sistem sesi dengesini daha rahat ayarlayabildigi, kayit oncesi daha anlasilir bir ses miks deneyimi saglamak.

## Scope

Ilk surumde:

- mikrofon seviyesi kontrolu
- sistem sesi seviyesi kontrolu
- kamera modunda gercek export mix uygulamasi
- ortak UI kontrolleri

Bu surumde ekran/pencere modlarinda ayri mikrofon ve sistem sesi seviyeleri ayri ayri uygulanmayacak. Bunun nedeni mevcut ScreenCaptureKit ekran kaydi yolunun sesi tek kayit akisinda toplamasidir. UI bu yuzeyin temelini kuracak; ekran modlarinda ayri kanal miksini sonraki turda ele alacagiz.

## Approach

1. `RecorderViewModel` icine iki yeni ayar eklenecek:
   - `microphoneVolume`
   - `systemAudioVolume`

2. Yeni bir `RecordingAudioMixBuilder` olusturulacak.
   - kamera export composition icindeki mikrofon ve sistem sesi track'lerine volume parametreleri uygulayacak
   - `AVMutableAudioMix` uretip export session'a verecek

3. Kamera export hattisi genisletilecek.
   - composition olusturulurken mikrofon ve sistem sesi track ID'leri ayrik tutulacak
   - export sirasinda `audioMix` da eklenecek

4. UI'ye iki slider eklenecek.
   - mikrofon mevcutsa mikrofon seviyesi gorunecek
   - sistem sesi seciliyse sistem sesi seviyesi gorunecek

## Defaults

- mikrofon seviyesi: `1.0`
- sistem sesi seviyesi: `1.0`

Bu ilk surumde surpriz yaratmayan, dogrudan anlasilir varsayimdir.

## Testing

- `RecordingAudioMixBuilderTests`
  - mikrofon track'ine dogru volume uygulanir
  - sistem sesi track'ine dogru volume uygulanir
  - track gruplari bos ise audio mix uretilmez
- mevcut recorder/view model testleri regresyon icin calisir
