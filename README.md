# RestartServiceByM - CodeByM

## Türkçe

**Gelişmiş Windows Servis İzleme ve Otomatik Kurtarma Aracı**  
**Yaratıcı / Üretici: CodeByM**  
**Platform: .NET 8 Worker Service | Windows Service Control Manager (SCM)**

### Proje hakkında

RestartServiceByM - CodeByM, yapılandırmada belirtilen kritik Windows servislerini arka planda izler. Bir servis durduğunda, ilgili seçenek etkinse yeniden başlatmayı dener; ayrıca pozitif bir planlı restart aralığı tanımlanmış servisleri bu aralıklarla yeniden başlatabilir. Hizmet, Windows Services listesinde **RestartService**, SCM sistem adında **`RestartService`** olarak görünür.

### Özellikler ve güvenlik mimarisi

- **Hata izolasyonu:** Bir servisin durum sorgusu veya restart işlemi başarısız olsa bile diğer geçerli servislerin izlenmesi sürer. Aynı servis ve hata türü için yinelenen loglar azaltılır; servis toparlandığında bilgilendirme logu yazılır.
- **Restart sonucu logu:** Planlı restart ancak stop/start durum geçişleri başarıyla tamamlandıktan sonra `"<servis adı> servisi başarıyla yeniden başlatıldı."` mesajıyla kaydedilir. Başarısız denemede başarı mesajı yazılmaz.
- **SCM test seam'i:** Dar kapsamlı `IServiceControllerAccess` adaptörü üretimde `ServiceController` kullanır; otomatik testlerde sahte adaptörlerle çalışır. Testler gerçek Windows servislerini başlatmaz veya durdurmaz.
- **Konfigürasyon doğrulama:** Servis adlarının başı ve sonu kırpılır; boş adlar, yinelenen (büyük/küçük harf duyarsız) adlar ve negatif `RestartIntervalMinutes` içeren kayıtlar izleme dışı bırakılır ve loglanır. `CheckIntervalSeconds` en az 5 olmalıdır. `RestartIntervalMinutes: 0`, planlı restartı kapatır; `RestartWhenStopped` davranışı bundan bağımsızdır.
- **ACL ve dizin güvenliği:** Installer, kurulum hedefini `%ProgramFiles%\RestartServiceByM` altında tutar ve dizinin yazma/değiştirme izinlerini denetler. Uygulama dosyaları ve konfigürasyon yetkisiz kullanıcılarca değiştirilebilir durumdaysa kurulum reddedilir.
- **Servis hesabı ve yetki kapsamı:** SCM kaydı ekran görüntüsündeki seçimle uyumlu olarak `LocalSystem` hesabıyla oluşturulur. Bu hesap makine genelinde çok geniş yetkilere sahiptir; uygulama veya yapılandırma güvenliği ihlal edilirse etki alanı büyür. Yalnızca güvenilir ve ACL'leri korunan kurulumlarda kullanın. Daha düşük ayrıcalık tercih ediliyorsa `LocalService` kullanıp izlenen her servise gereken en dar servis kontrol izinlerini ayrıca tanımlayın.
- **Loglama güvenliği:** Günlük dosyası yazımları süreç içi statik kilitle korunur. Dosya sistemi ve eski log temizleme hataları aynı logger'a geri gönderilmez; `System.Diagnostics.Trace`, gerektiğinde `Console.Error` fallback'i kullanılır. Fallback bildirimleri rate-limit edilir. Saklama politikası yedi günden eski `.log` dosyalarını temizler; bu, toplam log boyutu için bir kota değildir.
- **Zaman aşımı ve kapanış:** Servis durum geçişleri sınırlı süreyle beklenir. Host kapanışında bekleme işlemlerine `CancellationToken` aktarılır ve normal kapanış hata gibi raporlanmaz.
- **Güvenli kurulum betikleri:** BAT/PowerShell installer ve uninstaller yönetici izni ister; UAC akışı kullanılır, `sc.exe` çıkış kodları denetlenir. `install.bat` sonuç mesajını gösterip pencereyi açık tutar.

### Konfigürasyon

Kaynak örneği [`src/ServiceRestart/appsettings.json`](src/ServiceRestart/appsettings.json) dosyasındadır. İzlenecek adlar Windows SCM'deki servis adlarıdır; görünen adlar değildir.

```json
{
  "ServiceMonitor": {
    "CheckIntervalSeconds": 30,
    "Services": [
      {
        "Name": "W32Time",
        "Enabled": true,
        "RestartWhenStopped": true,
        "RestartIntervalMinutes": 0
      }
    ]
  }
}
```

- `CheckIntervalSeconds`: kontrol turları arasındaki süre; minimum 5 saniye.
- `Services[].Name`: Windows SCM servis adı.
- `Enabled`: bu kaydı izlemeye dahil eder veya dışarıda bırakır.
- `RestartWhenStopped`: servis durmuşsa başlatmayı dener.
- `RestartIntervalMinutes`: pozitif değerde planlı restart aralığı; `0` planlı restartı kapatır.

Uygulama önce çalıştırılabilir dosyanın dizininde `appsettings.json` arar, bulamazsa üst dizine bakar. Düz pakette EXE `runtime\` altında ve konfigürasyon kök dizinde bulunduğundan, ayar dosyası üst dizinden yüklenir. Loglar seçilen konfigürasyon dizininin `logs\` altına yazılır. Mevcut kurulum konfigürasyonu güncelleme esnasında korunur; yeni ayarlar operatör tarafından incelenip uygulanmalıdır.

### Düz dağıtım paketi (flat layout)

Kullanıcıya verilecek paket aşağıdaki düz yapıyı izler:

```text
RestartServiceByM_Release/
├── runtime/                         # EXE, DLL'ler ve yayın çalışma zamanı dosyaları
│   ├── ServiceRestart.exe
│   └── *.dll / diğer bağımlılıklar
├── appsettings.json
├── appsettings.Development.json     # Geliştirme ayarı; üretimde ayrıca gözden geçirin
├── install.bat
├── install.ps1
├── uninstall.bat
├── uninstall.ps1
└── README.md
```

Kurulum paketi bu dağıtım kökünden çalıştırılır. `install.ps1`, ikilileri `%ProgramFiles%\RestartServiceByM\runtime` konumuna, ayarları kurulum köküne alır ve `RestartService` SCM kaydını ayarlar. `appsettings.json` mevcutsa üzerine yazmaz. Bu nedenle güncellemede konfigürasyon farklarını elle inceleyin. Üretim ortamında `appsettings.Development.json` dosyasının bulunması gerekliliğini ve içeriğini ayrıca değerlendirin.

### Kurulum, publish ve kullanım

Komutları çözüm kökünde, PowerShell'de çalıştırın. Staging veya release klasörüne publish ederken çalışan servisin dosyalarının üzerine doğrudan yazmayın. Aşağıdaki örnek `staging\runtime` publish çıktısı oluşturur:

```powershell
$stage = Join-Path $PWD "staging"
New-Item -ItemType Directory -Force (Join-Path $stage "runtime") | Out-Null
dotnet publish ".\src\ServiceRestart\RestartServiceByM.CodeByM.csproj" `
  -c Release -o (Join-Path $stage "runtime")
```

Publish sonrasında publish'in runtime dizinine koyduğu konfigürasyonları runtime dışına, dağıtım köküne taşıyın. Bu adım önemlidir: uygulama EXE dizininde ayar dosyası bulursa üst dizini aramaz. Ardından kurulum dosyalarını ve README'yi paketin köküne alın:

```powershell
Move-Item (Join-Path $stage "runtime\appsettings.json") $stage
Move-Item (Join-Path $stage "runtime\appsettings.Development.json") $stage
Copy-Item ".\install.bat", ".\uninstall.bat", ".\README.md" $stage
Copy-Item ".\scripts\install.ps1", ".\scripts\uninstall.ps1" $stage
Test-Path (Join-Path $stage "runtime\ServiceRestart.exe")
Get-FileHash (Join-Path $stage "runtime\ServiceRestart.exe") -Algorithm SHA256
```

Staging içeriğini doğrulayıp düz pakete dönüştürürken dosyaları `runtime\` altında tutun; iki ayar dosyasını ve dört kurulum betiğini paketin köküne koyun. Paket içeriğini, hash değerlerini ve üretim konfigürasyonunu yönetici yetkisiyle çalıştırmadan önce kontrol edin.

1. Dağıtım klasörünü güvenilir kaynaktan alın ve dosyaları/konfigürasyonu inceleyin.
2. Kök dizindeki **`install.bat`** dosyasını çalıştırın. Gerekirse UAC yönetici onayı verin. Installer ACL'leri denetler, dosyaları korumalı Program Files dizinine kurar ve servisi `LocalSystem` hesabıyla kaydeder/başlatır.
3. Windows Services içinde **RestartService** durumunu doğrulayın. İzlenecek hedef servisler için gerekli izinleri ayrıca kontrol edin.
4. Kaldırmak için **`uninstall.bat`** dosyasını çalıştırıp UAC onayı verin. Betik yalnızca `RestartService` adlı SCM kaydını durdurup kaldırır.

Önceki sürüm `MeyerRestartService` veya `ServisRestart` SCM adıyla kuruluysa `RestartService` ayrı bir servis kaydı oluşturur. Kurulum/kaldırma betikleri eski kayıtları otomatik değiştirmez veya kaldırmaz; geçişi yönetici kontrollü ayrı bir bakım işlemi olarak planlayın. Servis kurulum betiklerini gerçek ortamda çalıştırmak mevcut hizmeti etkileyebilir.

### Build ve birim testleri

```powershell
dotnet restore ".\RestartServiceByM - CodeByM.sln"
dotnet build ".\RestartServiceByM - CodeByM.sln" -c Release
dotnet test ".\RestartServiceByM - CodeByM.sln" -c Release
```

MSTest tabanlı toplam **18 birim testi** bulunur:

- **10 Worker testi:** hata izolasyonu, durmuş servisi başlatma, başarısız/başarılı restart sonrası zaman bilgisi, `RestartIntervalMinutes: 0`, durum bekleme timeout'u, cancellation, eşzamanlı restart engeli, tekrarlanan hata loglarının azaltılması ve toparlanma logu.
- **8 FileLogger testi:** günlük dosyası biçimi/yazımı, yedi günlük temizleme, dosya/dizin/silme hatalarının bildirilmesi, eşzamanlı yazım ve logger'a geri dönmeyen fallback.

Testler sahte servis adaptörü ve geçici dosya sistemleri kullanır; gerçek Windows SCM davranışını, gerçek servis izinlerini veya dağıtım makinesindeki ACL'leri doğrulamaz.

### Bilinen kapsam sınırları

- Yedi günlük saklama, log dosyalarının toplam boyutuna kota koymaz.
- `LocalSystem` makine üzerinde yüksek ayrıcalıklıdır. Güvenlik gereksinimi daha düşük yetkili hesap talep ediyorsa, LocalService'e izlenen her servis için dar kapsamlı kontrol ACL'leri verilmesi gerekir.
- Installer mevcut `appsettings.json` dosyasını kasıtlı olarak korur; paket ayarları otomatik birleştirilmez.
- SCM adı `RestartService` olarak ayarlanmıştır. `MeyerRestartService` veya `ServisRestart` adlı eski bir SCM kaydı varsa geçiş ayrıca yönetilmelidir.

---

## English

**Advanced Windows Service Monitoring and Automatic Recovery Tool**  
**Creator / Publisher: CodeByM**  
**Platform: .NET 8 Worker Service | Windows Service Control Manager (SCM)**

### About

RestartServiceByM - CodeByM monitors configured critical Windows services in the background. When a service stops, the worker attempts to start it if that option is enabled. Services with a positive scheduled restart interval can also be restarted periodically. The service appears in Windows Services as **RestartService** and uses **`RestartService`** as its SCM service name.

### Features and security hardening

- **Fault isolation:** A status-query or restart failure for one service does not stop monitoring of other valid services. Repeated logs for the same service and exception type are suppressed; recovery is logged when monitoring succeeds again.
- **Restart result logging:** A scheduled restart is logged as successful only after stop/start state transitions complete: `"<service name> servisi başarıyla yeniden başlatıldı."` (the service was restarted successfully). Failed attempts do not emit the success message.
- **SCM test seam:** The narrow `IServiceControllerAccess` adapter uses `ServiceController` in production and fakes in automated tests. Tests do not start or stop real Windows services.
- **Configuration validation:** Service names are trimmed. Empty names, duplicate names (case-insensitive), and entries with a negative `RestartIntervalMinutes` are excluded and logged. `CheckIntervalSeconds` must be at least 5. A value of `0` disables scheduled restarts; `RestartWhenStopped` remains independent.
- **ACL and directory security:** The installer restricts the installation target to `%ProgramFiles%\RestartServiceByM` and checks directory write/modify access. Installation is rejected if application files or configuration can be modified by untrusted users.
- **Service identity and privilege scope:** The SCM entry is configured to run as `LocalSystem`, matching the account selected in the provided screenshot. This identity has extensive machine-wide privileges and increases impact if the application or its configuration is compromised. Use it only with trusted binaries and protected ACLs. For a lower-privilege deployment, use `LocalService` and explicitly grant only the required service-control permissions on each monitored service.
- **Logging security:** File writes are protected by a process-wide static lock. File-system and old-log cleanup errors are not sent back through the same logger; `System.Diagnostics.Trace` and, if needed, `Console.Error` are used as fallbacks. Fallback reports are rate-limited. Retention removes `.log` files older than seven days; it does not impose a total disk-usage quota.
- **Timeouts and shutdown:** Service state transitions are polled with a timeout. Host shutdown cancellation is passed to waits, and normal cancellation is not reported as an error.
- **Safe installer scripts:** The BAT/PowerShell installers and uninstallers require administrative rights, use UAC elevation, and check `sc.exe` exit codes. `install.bat` displays the result and keeps its window open.

### Configuration

The sample configuration is [`src/ServiceRestart/appsettings.json`](src/ServiceRestart/appsettings.json). Use actual Windows SCM service names, not display names.

```json
{
  "ServiceMonitor": {
    "CheckIntervalSeconds": 30,
    "Services": [
      {
        "Name": "W32Time",
        "Enabled": true,
        "RestartWhenStopped": true,
        "RestartIntervalMinutes": 0
      }
    ]
  }
}
```

- `CheckIntervalSeconds`: delay between monitoring cycles; minimum 5 seconds.
- `Services[].Name`: Windows SCM service name.
- `Enabled`: includes or excludes this entry from monitoring.
- `RestartWhenStopped`: attempts to start the service when stopped.
- `RestartIntervalMinutes`: scheduled restart interval when positive; `0` disables scheduled restarts.

The application looks for `appsettings.json` next to the executable first, then in its parent directory. In the flat package, the executable is under `runtime\` and configuration is in the package root, so the parent-directory lookup is used. Logs are written under `logs\` in the selected configuration directory. An existing installed configuration is preserved during upgrades; operators should review and apply configuration changes deliberately.

### Flat distribution package

The end-user package follows this layout:

```text
RestartServiceByM_Release/
├── runtime/                         # EXE, DLLs, and published runtime files
│   ├── ServiceRestart.exe
│   └── *.dll / other dependencies
├── appsettings.json
├── appsettings.Development.json     # Development settings; review before production use
├── install.bat
├── install.ps1
├── uninstall.bat
├── uninstall.ps1
└── README.md
```

Run the installer from this package root. `install.ps1` copies binaries to `%ProgramFiles%\RestartServiceByM\runtime`, places settings in the installation root, and configures the `RestartService` SCM entry. It does not overwrite an existing `appsettings.json`; review configuration changes manually during upgrades. Assess whether `appsettings.Development.json` should be present in production.

### Installation, publish, and usage

Run these commands from the solution root in PowerShell. Do not publish directly over files used by a running service. The example below publishes into `staging\runtime`:

```powershell
$stage = Join-Path $PWD "staging"
New-Item -ItemType Directory -Force (Join-Path $stage "runtime") | Out-Null
dotnet publish ".\src\ServiceRestart\RestartServiceByM.CodeByM.csproj" `
  -c Release -o (Join-Path $stage "runtime")
```

Verify the published executable and settings, then stage the settings and scripts that belong at the package root:

```powershell
Move-Item (Join-Path $stage "runtime\appsettings.json") $stage
Move-Item (Join-Path $stage "runtime\appsettings.Development.json") $stage
Copy-Item ".\install.bat", ".\uninstall.bat", ".\README.md" $stage
Copy-Item ".\scripts\install.ps1", ".\scripts\uninstall.ps1" $stage
Test-Path (Join-Path $stage "runtime\ServiceRestart.exe")
Get-FileHash (Join-Path $stage "runtime\ServiceRestart.exe") -Algorithm SHA256
```

After validating staging, assemble the flat package: keep binaries under `runtime\` and place both settings files and all four installer/uninstaller scripts at the package root. Review package contents, hashes, and production configuration before running with administrative rights.

1. Obtain the distribution directory from a trusted source and review its files and configuration.
2. Run **`install.bat`** from the package root and approve the UAC prompt if required. The installer checks ACLs, installs files under the protected Program Files directory, and registers/starts the service as `LocalSystem`.
3. Verify **RestartService** in Windows Services. Separately confirm that the account has the permissions required for the monitored services.
4. To uninstall, run **`uninstall.bat`** and approve UAC. It stops and removes only the SCM entry named `RestartService`.

If an older version is installed as `MeyerRestartService` or `ServisRestart`, installing `RestartService` creates a separate service entry. The scripts do not automatically modify or remove old entries; plan migration as a separate administrator-controlled maintenance action. Running service installation scripts in production may affect an existing service.

### Build and unit tests

```powershell
dotnet restore ".\RestartServiceByM - CodeByM.sln"
dotnet build ".\RestartServiceByM - CodeByM.sln" -c Release
dotnet test ".\RestartServiceByM - CodeByM.sln" -c Release
```

The MSTest suite contains **18 unit tests**:

- **10 Worker tests:** fault isolation, starting a stopped service, restart timestamp behavior on success/failure, `RestartIntervalMinutes: 0`, status-wait timeout, cancellation, preventing concurrent restarts, repeated-error log suppression, and recovery logging.
- **8 FileLogger tests:** daily file format/writes, seven-day cleanup, reporting directory/write/delete failures, concurrent writes, and fallback without recursive logger calls.

Tests use a fake service adapter and temporary file-system fixtures. They do not validate real Windows SCM behavior, real service permissions, or ACLs on the target deployment machine.

### Known limitations

- Seven-day retention does not cap total log size.
- `LocalSystem` has extensive machine-wide privileges. If a lower-privilege identity is required, grant `LocalService` only the narrowly scoped control ACLs needed on each monitored service.
- The installer deliberately preserves an existing `appsettings.json`; package settings are not merged automatically.
- The SCM name is `RestartService`. Existing `MeyerRestartService` or `ServisRestart` entries require a separately planned migration.
