# Permission Hub Design — FrameMate

**Date:** 2026-04-16  
**Status:** Proposed

---

## Overview

Mevcut izin deneyimi iki farklı yüzeye dağılmış durumda:

- ilk açılıştaki onboarding sheet
- ana ekrandaki ayrı ayrı permission banner'ları

Bu ikili yapı aynı izinleri farklı dille ve farklı davranışlarla anlattığı için özellikle macOS ekran kaydı izninde karışıklık yaratıyor. Kamera ve mikrofon uygulama içinden doğrudan istenirken, ekran kaydı ve sistem sesi aynı akışta fakat farklı beklentilerle ilerliyor. Kullanıcı onboarding'i hiç görmese bile asıl çalışma durumu ana ekranda çözülmek zorunda.

Bu tasarımın amacı izinleri tek bir merkezden yöneten, macOS gerçek davranışını doğru yansıtan ve onboarding gösterilmese bile uygulamayı anlaşılır kılan bir model kurmaktır.

---

## Goals

- Kamera, mikrofon ve ekran kaydı izinlerini tek bir durum modeliyle temsil etmek
- Sistem sesi davranışını ayrı bir izin gibi değil, ekran kaydı izninin uzantısı olarak açıklamak
- Onboarding'i zorunlu kilit olmaktan çıkarıp rehber rolüne indirmek
- Ana ekranda kalıcı ve güvenilir bir `Permission Hub` göstermek
- Ekran kaydı izni sonrası gereken yeniden başlatma davranışını açıkça göstermek
- Uygulama yeniden aktif olduğunda izin durumlarını tekrar senkronize etmek

---

## Non-Goals

- Bu turda yeni macOS izin türleri eklemek
- Ayarlar penceresinde ayrı bir permission yönetim ekranı tasarlamak
- Kayıt motorlarını yeniden yazmak
- Satın alma/onboarding/paywall akışını yeniden tasarlamak

---

## Current Problems

### 1. Aynı izin için iki farklı UI dili var

`OnboardingView` ve `ContentView` aynı izinleri farklı satırlar ve farklı CTA'larla gösteriyor. Kullanıcı onboarding'i atlasa ya da hiç görmese, ana ekran kendi başına başka bir model sunuyor.

### 2. Ekran kaydı izni diğerlerinden farklı ama bu fark sistematik değil

macOS ekran kaydı izni:

- bazen uygulama içi isteme yerine sistem yönlendirmesi ister
- izin verildikten sonra uygulamanın yeniden açılmasını gerektirebilir
- sistem sesi kaydını da etkiler

Mevcut yapıda bu durum `screenPermissionNeedsRestart` ile kısmen temsil ediliyor, ancak yalnızca bazı yüzeylerde anlaşılır.

### 3. Sistem sesi ayrı bir kavram gibi davranıyor

Kullanıcı için "sistem sesi neden çalışmıyor?" sorusunun cevabı aslında ekran kaydı iznidir. Bu bağı UI seviyesinde açık ve kalıcı anlatmıyoruz.

### 4. Onboarding görünürlüğü güvenilir değil

`onboarding.completed` daha önce set edilmişse kullanıcı onboarding'i tekrar görmez. Bu yüzden onboarding içine koyulan kritik izin eğitimi tek başına güvenilir başlangıç noktası olamaz.

---

## Recommended Approach

Önerilen yaklaşım: **hafif onboarding + kalıcı Permission Hub**

Bu modelde:

- onboarding kısa bir rehberdir
- gerçek izin durumu ana ekrandaki tek bir izin merkezi tarafından gösterilir
- kullanıcı onboarding'i görmese bile ana ekran neyin eksik olduğunu açıkça söyler

Bu yaklaşım Loom, CleanShot X ve benzeri macOS araçlarındaki davranışa daha yakındır: ilk kullanımda rehberlik eder, ama asıl kaynak gerçekliği ana ekranda saklamaz.

---

## Architecture

### 1. Yeni merkezi izin modeli

`RecorderViewModel` içinde doğrudan dağılmış izin banner kararları yerine tek bir merkezden türetilen bir model kullanılacak.

Yeni yapı:

- `PermissionKind`
- `PermissionAction`
- `PermissionHubItem`
- `PermissionHubState`

Önerilen alanlar:

```swift
enum PermissionKind {
    case camera
    case microphone
    case screenRecording
}

enum PermissionAction {
    case request
    case openSettings
    case restartApp
    case none
}

struct PermissionHubItem: Identifiable, Equatable {
    let id: PermissionKind
    let title: String
    let detail: String
    let statusLabel: String
    let isRequired: Bool
    let isSatisfied: Bool
    let primaryAction: PermissionAction
    let secondaryAction: PermissionAction?
}
```

`RecorderViewModel` bu item'ları hesaplayacak ve hem onboarding hem ana ekran aynı kaynağı kullanacak.

### 2. Tek source of truth

Bu hesaplama aşağıdaki girdilerden türeyecek:

- `cameraPermissionStatus`
- `microphonePermissionStatus`
- `screenRecordingPermissionStatus`
- `screenPermissionNeedsRestart`
- aktif modlar (`selectedPreset`, `isSystemAudioEnabled`, `isScreenCameraOverlayEnabled`)

Yani permission satırları view içinde koşullu if-else kümeleriyle ayrı ayrı kurulmayacak; view sadece modellenmiş state'i render edecek.

---

## UI Design

### Onboarding

Onboarding kalacak, ama rolü değişecek:

- kullanıcıya neden izin gerektiğini anlatır
- aynı `PermissionHubItem` satırlarını daha sade biçimde gösterir
- "Başla" butonunu sert bir product gate gibi değil, rehber sonu gibi kullanır

Onboarding tamamlanma kuralı:

- kullanıcı sheet'i bitirebilir
- eksik izinler varsa ana ekranda Permission Hub görünmeye devam eder

Bu yüzden onboarding artık tek başına kritik operasyonel ekran değildir.

### Main Screen Permission Hub

`ContentView` içine, header altında veya scroll içeriğinin üst kısmında tek bir `Permission Hub` kartı eklenecek.

Davranış:

- tüm gerekli izinler sağlanmışsa kompakt bir "Hazır" durumu gösterir veya sadeleşir
- eksik ya da yarım kalan izinler varsa ilgili satırlar görünür
- satırların her biri ortak bileşenle çizilir

Örnek satırlar:

- `Kamera` → `İzin Ver` veya `Ayarları Aç`
- `Mikrofon` → `İzin Ver` veya `Ayarları Aç`
- `Ekran Kaydı` → `İzin İste`, `Ayarları Aç`, gerekirse `Yeniden Aç`

### Sistem Sesi Mesajı

Sistem sesi ayrı bir izin satırı olmayacak. Bunun yerine:

- sistem sesi toggle'ı açıkken
- ekran kaydı izni eksikse

ekran kaydı satırının açıklaması genişletilecek:

`Ekran ve sistem sesi kaydı için gerekli`

Böylece kullanıcı iki ayrı sebep arasında kaybolmaz.

---

## Behavior Rules

### Camera

- `notDetermined` → `İzin Ver`
- `authorized` → tamam
- `denied/restricted` → `Ayarları Aç`

Kamera yalnızca ekran+kamera veya kamera modunda zorunlu hissedilir; diğer senaryolarda `opsiyonel` olarak işaretlenebilir.

### Microphone

- `notDetermined` → `İzin Ver`
- `authorized` → tamam
- `denied/restricted` → `Ayarları Aç`

Mikrofon sesli kayıt akışları için gerekli izin olarak kalır.

### Screen Recording

- `notDetermined` → `İzin İste`
- `authorized` → tamam
- `denied` → `Ayarları Aç`
- `screenPermissionNeedsRestart == true` → `Yeniden Aç`

Buradaki temel fark: ekran kaydı için "izin verildi ama henüz aktif değil" durumu birinci sınıf durum olarak temsil edilir.

### Restart semantics

`screenPermissionNeedsRestart` true olduğunda:

- satır başarısız gibi değil, "bir adım kaldı" gibi görünür
- status etiketi örneği: `Yeniden açılmalı`
- birincil CTA: `Yeniden Aç`
- ikincil CTA: `Ayarları Gör`

Bu davranış kullanıcıya sistemin gerçekten ne istediğini dürüstçe anlatır.

---

## Onboarding Completion Policy

Yeni yaklaşımda onboarding'in bitişi ile izinlerin tamlığı ayrılacaktır.

Yani:

- onboarding `completed = true` olabilir
- ama Permission Hub hâlâ eksik izin gösterebilir

Bu özellikle TestFlight ve tekrar kurulum senaryolarında daha güvenlidir. Kullanıcı onboarding'i kaçırsa bile uygulama ana ekranda toparlanır.

İsteğe bağlı iyileştirme:

- ileride ayarlardan `Onboarding'i Tekrar Göster` eklenebilir

Bu turda zorunlu değildir.

---

## ViewModel Changes

`RecorderViewModel` içinde:

- permission CTA üretimi merkezileştirilecek
- onboarding ve content view aynı merkezi state'i kullanacak
- `permissionStatusText` gibi birleşik metinler gerekiyorsa bu yeni merkezden türetilecek

Yeni önerilen yardımcı alanlar:

- `permissionHubItems`
- `requiredPermissionItems`
- `hasBlockingPermissionIssue`
- `canProceedPastOnboarding`

Eski dağınık banner koşulları mümkün olduğunca kaldırılacak.

---

## App Relaunch Handling

Ekran kaydı için en güvenilir deneyim, kullanıcıya sadece sistem ayarını açmak değil, uygulamanın yeniden açılması gerektiğini de doğrudan sunmaktır.

Bu turda minimum davranış:

- `restartApp` aksiyonu `NSApp.terminate(nil)` + kullanıcıya yeniden açma yönlendirmesi yapabilir
- ya da daha güvenli ilk adım olarak yalnızca kullanıcıya yeniden açması gerektiğini net söyler

Önerim:

- ilk iterasyonda "yeniden başlat" değil "uygulamayı yeniden aç" metni kullanalım
- otomatik relaunch denemesi yapmayalım

Bu daha düşük risklidir.

---

## Testing

### Unit tests

Yeni testler:

- permission state mapping for camera
- permission state mapping for microphone
- permission state mapping for screen recording
- `screenPermissionNeedsRestart` durumunda doğru action mapping
- sistem sesi aktifken ekran kaydı satır detayının genişlemesi
- onboarding proceed kararının merkezi state'e dayanması

### Regression coverage

Korunacak davranışlar:

- izin verildikten sonra cihaz listelerinin yenilenmesi
- app active olduğunda permission refresh
- denied durumunda settings deep-link
- screen recording source list refresh davranışı

---

## File Changes

Beklenen değişiklikler:

| Dosya | Değişiklik |
|---|---|
| `Sources/VideoRecorderApp/RecorderViewModel.swift` | merkezi permission state üretimi |
| `Sources/VideoRecorderApp/ContentView.swift` | Permission Hub kartı ve ortak satır render'ı |
| `Sources/VideoRecorderApp/OnboardingView.swift` | onboarding izin sayfasını merkezi modele bağlama |
| `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift` | permission mapping testleri |
| Gerekirse yeni küçük view dosyası | ortak permission row / hub component |

---

## Risks

### 1. Çok fazla state duplication

Eski banner koşulları bırakılıp üstüne yeni merkez eklenirse iki source of truth oluşur. Bu yüzden view tarafındaki eski koşullar temizlenmelidir.

### 2. Ekran kaydı izin tespiti gecikmeli olabilir

`ScreenCaptureKit` tarafındaki gerçek izin aktivasyonu sistem davranışına bağlıdır. Bu yüzden `needsRestart` durumu yalın ve dürüst modellenmelidir; sahte "authorized" gösterilmemelidir.

### 3. Onboarding artık sert gate olmadığı için bazı kullanıcılar izin vermeden içeri geçebilir

Bu kabul edilen bir trade-off'tur. Çünkü ana ekran artık eksik izinleri görünür ve eyleme geçirilebilir şekilde taşıyacaktır.

---

## Success Criteria

- Kullanıcı onboarding'i görmese bile uygulama ana ekranda hangi iznin eksik olduğunu açıkça anlar
- Kamera, mikrofon ve ekran kaydı aynı tasarım diliyle görünür
- Sistem sesi neden çalışmadığı açık şekilde ekran kaydı iznine bağlanır
- Ekran kaydı sonrası yeniden açma ihtiyacı kullanıcı için sürpriz olmaz
- İzinlerle ilgili karar mantığı view katmanından büyük ölçüde çıkarılmış olur
