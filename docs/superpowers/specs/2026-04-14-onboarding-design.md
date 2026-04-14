# Onboarding Design — FrameMate

**Date:** 2026-04-14  
**Status:** Approved

---

## Overview

İlk açılışta kullanıcıya uygulamayı tanıtan 3 adımlı bir onboarding sheet'i. `UserDefaults`'a `onboarding.completed = true` kaydedilince bir daha gösterilmez. Ayarlardan erişim yoktur.

---

## Architecture

### Yeni dosya: `OnboardingView.swift`

Tek bir `View` dosyası, tüm onboarding mantığını içerir. İçinde üç alt view:

- `OnboardingWelcomePage` — Adım 1
- `OnboardingModesPage` — Adım 2
- `OnboardingPermissionsPage` — Adım 3

### Mevcut dosya değişiklikleri

**`VideoRecorderApp.swift`** — `VideoRecorderApp.body` içinde `ContentView`'e `.sheet(isPresented:)` eklenir. Gösterme kararı `@AppStorage("onboarding.completed")` ile alınır.

**`RecorderViewModel.swift`** — `requestScreenRecordingPermission()`, `requestCameraPermission()`, `requestMicrophonePermission()` zaten mevcut; onboarding bunları doğrudan çağırır.

---

## Sheet Özellikleri

- Boyut: 560 × 420 pt, sabit (`frame(width:height:)` + `fixedSize()` değil, `.frame` ile kilitli)
- Yeniden boyutlandırılamaz (`resizable: false` eşdeğeri — SwiftUI sheet macOS'ta otomatik)
- Arka plan: `regularMaterial` + `fmAccent.opacity(0.08)` gradyan (ContentView ile tutarlı)

---

## Adım Göstergesi

Sheet'in üstünde 3 nokta. Aktif adım `fmAccent` rengi ile dolu daire, pasifler küçük ve soluk. Geçiş animasyonu: `.easeInOut(duration: 0.25)`.

---

## Adım 1 — Hoş Geldin

```
[Uygulama İkonu — 80 pt]
FrameMate'e Hoş Geldin
Ekranını, sesini ve kameranı kolayca kaydet.
                              [İleri →]
```

- İkon: `NSApp.applicationIconImage` → `Image(nsImage:)`
- Başlık: `.title` font weight bold
- Açıklama: `.body` secondary foreground
- "İleri" butonu sağ alt köşe, `fmAccent` rengi

VoiceOver: sayfa başlığı "Adım 1 / 3, FrameMate'e Hoş Geldin" olarak duyurulur.

---

## Adım 2 — Kayıt Modları

```
Nasıl Kayıt Yapabilirsin?

[ekran.ikon]  Ekran Kaydı          Tüm ekranı veya bir pencereyi yakala.
[kamera.ikon] Ekran + Kamera       Kendi görüntünle birlikte kaydet.
[mic.ikon]    Sadece Ses           Toplantı ve podcast için saf ses kaydı.

                              [İleri →]
```

- Her satır: SF Symbol ikonu (24 pt) + başlık + açıklama, `Label` + `VStack` yapısı
- İkonlar: `rectangle.on.rectangle`, `rectangle.badge.person.crop`, `waveform`
- Satırlar arası boşluk: 16 pt

VoiceOver: "Adım 2 / 3, Kayıt Modları".

---

## Adım 3 — İzinler

```
Birkaç İzne İhtiyacımız Var

[lock.rectangle] Ekran Kaydı    [İzin Ver / ✓ Verildi]
[mic]            Mikrofon       [İzin Ver / ✓ Verildi]
[camera]         Kamera         [İzin Ver / ✓ Verildi]  (opsiyonel etiketi)

Kamera izni yalnızca Ekran + Kamera modunda gereklidir.

                              [Başla]  ← ekran + mikrofon olmadan disabled
```

### İzin Satırı Mantığı

Her satır bağımsız. Buton tıklanınca `RecorderViewModel` üzerindeki mevcut `requestXPermission()` metodları çağrılır. İzin verildikten sonra buton yerine yeşil tik + "Verildi" etiketi gösterilir.

### "Başla" Butonu Koşulu

`screenRecordingPermissionStatus == .authorized && microphonePermissionStatus == .authorized`

Bu koşul sağlanmadan buton `.disabled(true)` olarak kalır.

### Kamera "Opsiyonel"

Kamera satırının yanında küçük `(opsiyonel)` etiketi. Kullanıcı vermeden de Başla butonuna basabilir.

VoiceOver: "Adım 3 / 3, İzinler. Ekran kaydı izni gerekli. Mikrofon izni gerekli. Kamera izni opsiyonel."

---

## Geçiş Animasyonu

`withAnimation(.easeInOut(duration: 0.25))` ile `currentStep` state değişkeni artırılır. Adımlar arası geçiş `.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))` ile sağa-sola kayar.

---

## UserDefaults Kaydı

"Başla" butonuna tıklanınca:
```swift
UserDefaults.standard.set(true, forKey: "onboarding.completed")
isOnboardingPresented = false
```

`VideoRecorderApp.swift`'te:
```swift
@AppStorage("onboarding.completed") private var onboardingCompleted = false
// sheet isPresented: !onboardingCompleted
```

---

## Erişilebilirlik

- Her sayfa `accessibilityElement(children: .contain)` + `accessibilityLabel("Adım X / 3, [başlık]")`
- Butonlar anlamlı etiket taşır: "Ekran kaydı izni ver", "Mikrofona izin ver", "Kameraya izin ver", "Onboarding'i tamamla"
- Tik işareti: `Image(systemName: "checkmark.circle.fill").accessibilityLabel("Verildi")`

---

## Dosya Değişiklikleri Özeti

| Dosya | Değişiklik |
|---|---|
| `OnboardingView.swift` | YENİ — tüm onboarding view'leri |
| `VideoRecorderApp.swift` | `.sheet` ekleme, `@AppStorage` |
| Değişmeyen | `RecorderViewModel`, `ContentView`, diğerleri |
