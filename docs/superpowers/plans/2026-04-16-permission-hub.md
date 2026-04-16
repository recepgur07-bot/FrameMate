# Permission Hub Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** FrameMate içinde onboarding ve ana ekranın aynı izin kaynağını kullanacağı, ekran kaydı restart durumunu açıkça yöneten, gerçek çalışan bir Permission Hub sistemi kurmak.

**Architecture:** İzin kararı `RecorderViewModel` içinde merkezi bir `PermissionHubItem` listesine taşınacak; `ContentView` ve `OnboardingView` bu listeyi render eden ince UI katmanları olacak. Eski dağınık permission banner koşulları kademeli olarak kaldırılacak; önce state mapping testlerle güvence altına alınacak, sonra UI ortaklaştırılacak.

**Tech Stack:** SwiftUI, Observation `@Observable`, AVFoundation `AVAuthorizationStatus`, mevcut `ScreenRecordingAuthorizationStatus`, XCTest, xcodebuild

---

## File Map

- `Sources/VideoRecorderApp/RecorderViewModel.swift`
  Yeni permission model tipleri, state mapping helper'ları, onboarding proceed kararı ve merkezi aksiyon yönlendirmeleri burada olacak.

- `Sources/VideoRecorderApp/ContentView.swift`
  Dağınık permission banner yapısı yerine ortak Permission Hub kartı ve satırları kullanılacak.

- `Sources/VideoRecorderApp/OnboardingView.swift`
  İzin sayfası, aynı merkezi `permissionHubItems` datasını daha sade görünümle kullanacak.

- `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`
  Yeni permission mapping ve onboarding proceed testleri burada eklenecek.

- `Tests/VideoRecorderAppTests/TestSupport.swift`
  Gerekirse permission-state senaryolarını daha okunur kurmak için küçük test helper'ları burada genişletilecek.

---

## Chunk 1: Permission State Modeli ve ViewModel Mapping

### Task 1: Permission model tipleri için failing testleri yaz

**Files:**
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`
- Reference: `Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] **Step 1: Kamera, mikrofon ve ekran kaydı için mapping testlerini ekle**

```swift
func testPermissionHubShowsRequestActionForUndeterminedMicrophone() async
func testPermissionHubShowsSettingsActionForDeniedCamera() async
func testPermissionHubShowsRestartActionWhenScreenPermissionNeedsRestart() async
func testPermissionHubScreenDetailMentionsSystemAudioWhenEnabled() async
func testCanProceedPastOnboardingAllowsMissingOptionalCamera() async
```

- [ ] **Step 2: Testleri çalıştırıp doğru sebeple fail ettiğini doğrula**

Run:

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelTests 2>&1 | tail -40
```

Expected: `RecorderViewModel` içinde `permissionHubItems` / `canProceedPastOnboarding` benzeri üyeler eksik olduğu için derleme veya assertion failure.

- [ ] **Step 3: Commit yapma**

Bu task sonunda henüz commit yok; önce implementation ile green'e dön.

### Task 2: RecorderViewModel içinde merkezi permission state'i ekle

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Minimal permission model tiplerini ekle**

Eklenmesi beklenen yapılar:

```swift
enum PermissionKind: String, Identifiable, CaseIterable
enum PermissionAction: Equatable
struct PermissionHubItem: Identifiable, Equatable
```

Alanlar:

```swift
let id: PermissionKind
let title: String
let detail: String
let statusLabel: String
let isRequired: Bool
let isSatisfied: Bool
let primaryAction: PermissionAction
let secondaryAction: PermissionAction?
```

- [ ] **Step 2: `permissionHubItems` computed var'ını ekle**

İçermesi gereken kurallar:

- kamera: `notDetermined -> request`, `denied/restricted -> openSettings`, `authorized -> none`
- mikrofon: aynı desen
- ekran kaydı: `screenPermissionNeedsRestart -> restartApp/openSettings`, `authorized -> none`, `denied -> openSettings`, `notDetermined -> request`
- sistem sesi açıksa ekran kaydı `detail` metni genişlesin
- kamera `isRequired` yalnızca aktif mod gerçekten kamera gerektiriyorsa `true` olsun

- [ ] **Step 3: `canProceedPastOnboarding` ve `hasBlockingPermissionIssue` ekle**

Kurallar:

- onboarding için ekran kaydı veya restart-bekleyen durum kabul edilsin
- mikrofon gerekli
- kamera opsiyonel kalsın
- blocking kararını `requiredPermissionItems.contains(where: !isSatisfied)` ile türet

- [ ] **Step 4: Permission action dispatcher ekle**

Tek merkezden çağrılacak fonksiyonlar:

```swift
func performPrimaryPermissionAction(for kind: PermissionKind)
func performSecondaryPermissionAction(for kind: PermissionKind)
```

Bu fonksiyonlar mevcut:

- `requestCameraPermission()`
- `requestMicrophonePermission()`
- `requestScreenRecordingPermission()`
- `openPrivacySettings(for:)`
- `openScreenRecordingSettings()`

metotlarına delegasyon yapsın.

- [ ] **Step 5: Testleri çalıştırıp green olduğunu doğrula**

Run:

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelTests 2>&1 | tail -40
```

Expected: Yeni testler PASS.

- [ ] **Step 6: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/RecorderViewModel.swift Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "feat: add centralized permission hub state"
```

---

## Chunk 2: Main Screen Permission Hub UI

### Task 3: ContentView için failing UI davranış testini ekle veya mevcut test sınırını netleştir

**Files:**
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`
- Reference: `Sources/VideoRecorderApp/ContentView.swift`

- [ ] **Step 1: Test seviyesini ViewModel sınırında tut**

Yeni saf SwiftUI snapshot altyapısı ekleme. Bunun yerine `ContentView`'un kullanacağı state'i zaten ViewModel testleriyle doğruladığını plan notu olarak koru.

- [ ] **Step 2: Bu task için ayrı otomatik test yazma**

Beklenen yaklaşım: UI değişimi derleme ve manuel smoke check ile doğrulanacak.

### Task 4: ContentView içine ortak Permission Hub kartını ekle

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Test via build: whole target

- [ ] **Step 1: Ortak render helper'larını ekle**

`ContentView` içine veya dosya sonunda küçük private view/helper'lar ekle:

```swift
private var permissionHubCard: some View
private func permissionRow(_ item: PermissionHubItem) -> some View
```

Görünüm gereksinimleri:

- Header altı veya scroll içeriğinin en üstü
- tek kart içinde 0..n satır
- tüm izinler tamamsa kompakt hazır mesajı
- eksik durumlarda title + detail + status + CTA

- [ ] **Step 2: Scroll içeriğine Permission Hub kartını yerleştir**

`previewCard` öncesine yerleştir:

```swift
if viewModel.shouldShowPermissionHub { permissionHubCard }
```

veya kartı her zaman gösterip hazır durumda sadeleştir.

- [ ] **Step 3: Eski dağınık permission banner kullanımını azalt**

Kaldırılacak/azaltılacak parçalar:

- `cameraPermissionBanner`
- `microphonePermissionBanner`
- `screenPermissionBanner`

Not:

- Bu helper'lar tamamen silinebilir ya da geçici olarak yalnızca kart içinden kullanılabilir
- Aynı izin iki ayrı yerde aynı anda görünmemeli

- [ ] **Step 4: Derlemeyi çalıştır**

Run:

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Manuel smoke check notu**

Elle doğrulanacak:

- mikrofon `notDetermined` iken tek CTA görünmesi
- denied durumda `Ayarları Aç`
- ekran izni restart beklerken `Yeniden Aç`
- sistem sesi açıkken ekran satırı açıklamasının değişmesi

- [ ] **Step 6: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/ContentView.swift
git commit -m "feat: add main screen permission hub"
```

---

## Chunk 3: Onboarding İzin Sayfasını Merkezi State'e Bağlama

### Task 5: Onboarding proceed kuralı için failing test ekle

**Files:**
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`
- Reference: `Sources/VideoRecorderApp/OnboardingView.swift`

- [ ] **Step 1: Merkezi onboarding proceed testini ekle**

```swift
func testCanProceedPastOnboardingWhenScreenNeedsRestartAndMicrophoneAuthorized() async
```

Bu test onboarding mantığının artık doğrudan ham permission statülerine değil merkezi computed property'ye dayanmasını doğrular.

- [ ] **Step 2: Testi çalıştır ve gerekiyorsa red durumunu doğrula**

Run:

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelTests 2>&1 | tail -30
```

Expected: fail only if proceed logic still old behavior uses raw checks.

### Task 6: Onboarding izin sayfasını `permissionHubItems` ile render et

**Files:**
- Modify: `Sources/VideoRecorderApp/OnboardingView.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: `canProceed` kullanımını `viewModel.canProceedPastOnboarding` ile değiştir**

- [ ] **Step 2: İzin sayfasını merkezi item listesinden çiz**

Önerilen yaklaşım:

- onboarding için `viewModel.permissionHubItems`
- sadece kullanıcıya ilgili izinleri gösteren sade görünüm
- kamera satırı opsiyonel etiketini `item.isRequired` üzerinden üret
- CTA action'ları `performPrimaryPermissionAction` / `performSecondaryPermissionAction` üstünden çağrılsın

- [ ] **Step 3: Restart durumunu onboarding içinde net göster**

Ekran kaydı satırında:

- durum etiketi `Yeniden açılmalı`
- ana CTA `Yeniden Aç`
- ikincil CTA varsa `Ayarları Aç`

- [ ] **Step 4: Testleri çalıştır**

Run:

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelTests 2>&1 | tail -40
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/OnboardingView.swift Sources/VideoRecorderApp/RecorderViewModel.swift Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "feat: wire onboarding to permission hub state"
```

---

## Chunk 4: Cleanup ve Final Verification

### Task 7: Eski permission metinleri ve akışlarını temizle

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] **Step 1: Kullanılmayan eski permission helper'ları kaldır**

Hedef:

- duplicate banner helper'ları
- artık tek kaynaktan üretilmeyen eski if blokları

- [ ] **Step 2: `permissionStatusText` kullanımını gözden geçir**

Eğer hala gerekliysa yeni merkezi modelden türet. Kullanılmıyorsa teknik borç oluşturmadan sadeleştir.

- [ ] **Step 3: Full test suite çalıştır**

Run:

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -60
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 4: Full build çalıştır**

Run:

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Final manual checklist**

Elle doğrula:

- onboarding ilk açılışta yeni permission state'leri gösteriyor
- onboarding geçildikten sonra ana ekranda aynı izin dili kullanılıyor
- kamera izni opsiyonel kalıyor
- mikrofon izni yoksa kullanıcı net CTA görüyor
- ekran kaydı izni sonrası restart durumu açıkça görünüyor
- sistem sesi açıkken ekran izniyle bağlantı net

- [ ] **Step 6: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/ContentView.swift Sources/VideoRecorderApp/RecorderViewModel.swift Sources/VideoRecorderApp/OnboardingView.swift Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "refactor: unify permission flows across onboarding and main screen"
```
