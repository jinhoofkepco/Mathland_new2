# MathLand Android Integration and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the Godot child app, versioned content, Supabase services, and guardian web app into a verified Android 1.0.0 release, then publish a signed ARM64 APK and its evidence bundle from `jinhoofkepco/Mathland_new2`.

**Architecture:** Subproject D adds a narrow Android Keystore bridge, deterministic cross-system harnesses, Android export and emulator gates, artifact/privacy audits, and a two-stage draft-then-publish release workflow. It consumes Subprojects A–C through their public contracts; it does not duplicate game, content, or cloud logic. Offline/local gates run without production credentials, while a separately authorized live gate is required before the GitHub Release can become public.

**Tech Stack:** Godot 4.7.1/GDScript, Godot Android plugin v2, Kotlin 2.1.21, Android Gradle Plugin 8.6.1, Gradle 8.11.1, OpenJDK 17, Android SDK 35/build-tools 35.0.1, TypeScript/Node.js, Vitest, Playwright, Supabase CLI/PostgreSQL, Bash, ADB, `apkanalyzer`, `apksigner`, GitHub Actions, GitHub CLI.

## Global Constraints

- Child platform: Android APK built with Godot 4.7.1 and GDScript.
- Package identity: `com.jinhoofkepco.mathland`, version `1.0.0`, version code `1`.
- Rendering: Godot Compatibility renderer for broad Android support.
- Screen: Phone portrait first; portrait tablet expansion must not require an architectural rewrite.
- Profiles: Multiple child profiles with separate progress, settings, and rewards.
- Connectivity: Offline-first; cloud availability never blocks play.
- Assets: New cohesive assets; no legacy raster assets are required in the release.
- Release: Source, documentation, signed APK, checksum, screenshots, and release notes on GitHub.
- Godot 4.7.1, OpenJDK 17, Android platform 35, and build-tools 35.0.1 are the initial Android toolchain.
- Android minimum SDK is 24 and target SDK is 35.
- The `v1.0.0` release APK uses the Compatibility renderer and ARM64. Other ABIs are outside the first release.
- Input feedback begins within 100 milliseconds of accepted input.
- The reference performance profile is a Pixel 6-class Android API 35 ARM64 device/emulator at 1080×2400 with 4 GB RAM.
- Target 60 frames per second during normal play; effect-heavy scenes keep 95th-percentile frame time below 25 ms after warm-up.
- Cold launch reaches profile selection within 5 seconds on the reference profile.
- The release APK is at most 200 MB unless an explicit, reviewed exception is committed before release.
- Core flows must render without clipped controls at 360×800 phone portrait, 1080×2400 reference portrait, and 800×1280 tablet portrait.
- Do not request broad external-storage, location, contacts, camera, microphone, or advertising-identifier permissions.
- Android cloud backup and device transfer must exclude refresh credentials and learning logs.
- No keystore, signing password, Supabase secret/service key, AI key, child event fixture containing real data, or personal credential may enter source, artifacts, logs, or repository history.
- CI produces only unsigned/debug artifacts until repository secrets and the protected `production-release` environment are configured.
- A real child-app event must appear in the authorized guardian dashboard before the release is declared complete.
- If live Supabase authorization is unavailable, remote monitoring remains explicitly unverified and the public `v1.0.0` release is blocked.

---

## File and Contract Map

| Path | Responsibility |
|---|---|
| `scripts/ci/verify_toolchain.mjs` | Validate exact Godot/JDK/Android tools without changing the machine. |
| `android/plugins/secure_credentials/` | Kotlin Android library that encrypts only the Supabase refresh credential with Android Keystore. |
| `addons/mathland_secure_credentials/` | Godot plugin v2 export metadata and generated AAR destination. |
| `src/platform/secure_credential_store.gd` | GDScript boundary used by `SyncService`; it never falls back to plaintext persistence. |
| `export_presets.cfg` | Reproducible ARM64 debug, smoke, and signed-release Android presets with no embedded secrets. |
| `scripts/android/` | Plugin build, Godot export, emulator smoke, lifecycle, responsive screenshot, and performance commands. |
| `packages/integration-tests/` | TypeScript cross-system harness for offline journal → ingest → aggregate → dashboard flows. |
| `tests/integration/` | Repository-owned Godot integration suites and release fixtures. |
| `tests/android/` | Debug-only on-device smoke probe and ADB log fixtures; excluded from release export. |
| `scripts/release/` | Artifact audit, signing, checksum, manifest validation, draft release, and download verification. |
| `.github/workflows/integration.yml` | Credential-free integration, Android debug, local Supabase, and emulator gates. |
| `.github/workflows/release.yml` | Protected signed build, draft Release upload, verification, and publication. |
| `release/` | Machine-readable non-secret release manifest, certificate fingerprint, and verification evidence. |
| `docs/operations/` | Android setup, signing, live integration, release, rollback, deletion, and recovery runbooks. |
| `docs/releases/v1.0.0.md` | Final user-facing release notes, install steps, and known limitations. |
| `docs/screenshots/v1.0.0/` | Reviewed child-game, dashboard, and Content Studio screenshots shipped with the release. |

### Consumed interfaces

- Godot test runner: `tests/run_all.gd`; accepted suites are `unit`, `scene`, `integration`, and `all`, and D invokes the exact `--suite integration` and `--suite all` commands shown below; no external Godot test plugin.
- App shell: `scenes/app/app_shell.tscn` and `project.godot`.
- Game/persistence contracts: `src/game/run_controller.gd`, `src/game/run_session.gd`, `src/persistence/event_journal.gd`, and `src/events/learning_event_v1.gd`.
- Content contracts: `@mathland/contracts` in `packages/contracts/`, plus `npm run test:contracts`, `npm run test:content-tools`, `npm run validate:content`, and `npm run build:content`.
- Cloud/web contracts: Supabase functions under `supabase/functions/`, migrations/tests under `supabase/`, and the React application under `web/`.

### Produced interfaces

- `SecureCredentialStore.is_available() -> bool`
- `SecureCredentialStore.save_refresh_token(token: String) -> bool`
- `SecureCredentialStore.load_refresh_token() -> String`
- `SecureCredentialStore.clear_refresh_token() -> bool`
- `runOfflineSyncScenario(options: OfflineSyncOptions) -> Promise<OfflineSyncEvidence>` in `packages/integration-tests/src/offline-sync-scenario.ts`.
- `analyzeFrameStats(text: string) -> FrameStatsResult` and `evaluatePerformance(result, thresholds) -> string[]` in `scripts/android/analyze-framestats.mjs`.
- `auditRelease(input: ReleaseAuditInput) -> Promise<ReleaseAuditFinding[]>` in `scripts/release/audit-release.mjs`.
- `release/v1.0.0-manifest.json` as the single source for expected artifact names and immutable release facts.

### Authoritative platform references

- Godot 4.7 Android plugin v2: `https://docs.godotengine.org/en/4.7/tutorials/platform/android/android_plugin.html`
- Godot 4.7 Gradle Android builds: `https://docs.godotengine.org/en/4.7/tutorials/export/android_gradle_build.html`
- Godot Android export/signing variables: `https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html`
- Android Keystore: `https://developer.android.com/privacy-and-security/keystore`
- APK signing verification: `https://developer.android.com/tools/apksigner`

---

### Task 1: Pin and Test the Release Toolchain Preflight

**Files:**
- Create: `scripts/ci/verify_toolchain.mjs`
- Create: `tests/release/verify_toolchain.test.mjs`
- Modify: `package.json`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: executables selected by `GODOT_BIN`, `JAVA_HOME`, and `ANDROID_HOME`/`ANDROID_SDK_ROOT`.
- Produces: `validateProbe(probe: ToolchainProbe) -> string[]`; CLI exits `0` only for Godot 4.7.1, JDK 17, platform 35, build-tools 35.0.1, and required Android executables.

- [ ] **Step 1: Write the failing validator tests**

```javascript
// tests/release/verify_toolchain.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { validateProbe } from "../../scripts/ci/verify_toolchain.mjs";

const valid = {
  godotVersion: "4.7.1.stable.official.a13da4feb",
  javaVersion: "17.0.19",
  platforms: ["android-35"],
  buildTools: ["35.0.1"],
  executables: { adb: true, apksigner: true, zipalign: true, aapt2: true },
};

test("accepts the exact release toolchain", () => {
  assert.deepEqual(validateProbe(valid), []);
});

test("reports every release-blocking mismatch", () => {
  const findings = validateProbe({
    ...valid,
    godotVersion: "4.7.0.stable.official",
    javaVersion: "21.0.2",
    platforms: ["android-36"],
    buildTools: ["36.0.0"],
    executables: { adb: true, apksigner: false, zipalign: false, aapt2: true },
  });
  assert.deepEqual(findings, [
    "Godot must be 4.7.1; found 4.7.0.stable.official",
    "Java major version must be 17; found 21.0.2",
    "Android platform android-35 is missing",
    "Android build-tools 35.0.1 is missing",
    "Android executable apksigner is missing",
    "Android executable zipalign is missing",
  ]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/release/verify_toolchain.test.mjs`

Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `scripts/ci/verify_toolchain.mjs`.

- [ ] **Step 3: Implement the validator and read-only probes**

```javascript
// scripts/ci/verify_toolchain.mjs
import { access, readdir } from "node:fs/promises";
import { constants } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

export function validateProbe(probe) {
  const findings = [];
  if (!probe.godotVersion.startsWith("4.7.1.")) findings.push(`Godot must be 4.7.1; found ${probe.godotVersion}`);
  if (probe.javaVersion.split(".")[0] !== "17") findings.push(`Java major version must be 17; found ${probe.javaVersion}`);
  if (!probe.platforms.includes("android-35")) findings.push("Android platform android-35 is missing");
  if (!probe.buildTools.includes("35.0.1")) findings.push("Android build-tools 35.0.1 is missing");
  for (const name of ["adb", "apksigner", "zipalign", "aapt2"]) {
    if (!probe.executables[name]) findings.push(`Android executable ${name} is missing`);
  }
  return findings;
}

function capture(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}`);
  return `${result.stdout}${result.stderr}`.trim();
}

async function exists(file) {
  try { await access(file, constants.X_OK); return true; } catch { return false; }
}

export async function probeToolchain(env = process.env) {
  const sdk = env.ANDROID_SDK_ROOT || env.ANDROID_HOME;
  if (!sdk) throw new Error("ANDROID_SDK_ROOT or ANDROID_HOME must be set");
  if (!env.JAVA_HOME) throw new Error("JAVA_HOME must be set");
  const godot = env.GODOT_BIN || "/opt/homebrew/bin/godot";
  const java = path.join(env.JAVA_HOME, "bin", "java");
  const javaText = capture(java, ["-version"]);
  const javaVersion = /version \"([^\"]+)\"/.exec(javaText)?.[1] || "unknown";
  const toolDir = path.join(sdk, "build-tools", "35.0.1");
  return {
    godotVersion: capture(godot, ["--version"]),
    javaVersion,
    platforms: await readdir(path.join(sdk, "platforms")),
    buildTools: await readdir(path.join(sdk, "build-tools")),
    executables: {
      adb: await exists(path.join(sdk, "platform-tools", "adb")),
      apksigner: await exists(path.join(toolDir, "apksigner")),
      zipalign: await exists(path.join(toolDir, "zipalign")),
      aapt2: await exists(path.join(toolDir, "aapt2")),
    },
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const findings = validateProbe(await probeToolchain());
  if (findings.length) {
    for (const finding of findings) console.error(`BLOCKED: ${finding}`);
    process.exitCode = 1;
  } else {
    console.log("PASS: Godot 4.7.1 / JDK 17 / Android 35 / build-tools 35.0.1");
  }
}
```

Add `"verify:toolchain": "node scripts/ci/verify_toolchain.mjs"` to the root `scripts` object. Ignore only generated locations: `.godot/`, `android/build/`, `addons/mathland_secure_credentials/bin/`, `dist/`, `reports/`, `*.jks`, `*.keystore`, and `*.p12`.

- [ ] **Step 4: Run the focused and real preflight checks**

Run: `node --test tests/release/verify_toolchain.test.mjs && npm run verify:toolchain`

Expected: two Node tests pass, followed by `PASS: Godot 4.7.1 / JDK 17 / Android 35 / build-tools 35.0.1`.

- [ ] **Step 5: Commit**

```bash
git add package.json .gitignore scripts/ci/verify_toolchain.mjs tests/release/verify_toolchain.test.mjs
git commit -m "build: pin Android release toolchain"
```

---

### Task 2: Build the Android Keystore Encryption Core

**Files:**
- Create: `android/plugins/secure_credentials/settings.gradle.kts`
- Create: `android/plugins/secure_credentials/build.gradle.kts`
- Create: `android/plugins/secure_credentials/gradle.properties`
- Create: `android/plugins/secure_credentials/gradle/wrapper/gradle-wrapper.properties`
- Create: `android/plugins/secure_credentials/secure_credentials/build.gradle.kts`
- Create: `android/plugins/secure_credentials/secure_credentials/src/main/java/com/jinhoofkepco/mathland/securecredentials/EncryptedValue.kt`
- Create: `android/plugins/secure_credentials/secure_credentials/src/main/java/com/jinhoofkepco/mathland/securecredentials/SecretCipher.kt`
- Create: `android/plugins/secure_credentials/secure_credentials/src/main/java/com/jinhoofkepco/mathland/securecredentials/AndroidKeystoreCipher.kt`
- Create: `android/plugins/secure_credentials/secure_credentials/src/main/java/com/jinhoofkepco/mathland/securecredentials/RefreshTokenStore.kt`
- Create: `android/plugins/secure_credentials/secure_credentials/src/test/java/com/jinhoofkepco/mathland/securecredentials/RefreshTokenStoreTest.kt`

**Interfaces:**
- Consumes: Android API 24+ `AndroidKeyStore` and private `SharedPreferences`.
- Produces: `RefreshTokenStore.save(token: String)`, `load(): String?`, `clear()`, and `contains(): Boolean`; `SecretCipher.encrypt/decrypt` keeps cipher behavior injectable for unit tests.

- [ ] **Step 1: Add the Gradle wrapper and module with pinned versions**

Use Gradle `8.11.1`, AGP `8.6.1`, Kotlin `2.1.21`, `compileSdk = 35`, `minSdk = 24`, and `compileOnly("org.godotengine:godot:4.7.1.stable")`. Add JUnit `4.13.2`, Robolectric `4.14.1`, and AndroidX Test Core `1.6.1` as test dependencies. The module namespace is `com.jinhoofkepco.mathland.securecredentials`; release minification remains disabled because this AAR is internal and the app release owns shrinking.

```kotlin
// android/plugins/secure_credentials/secure_credentials/build.gradle.kts
plugins { id("com.android.library"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.jinhoofkepco.mathland.securecredentials"
    compileSdk = 35
    defaultConfig { minSdk = 24; testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
    buildTypes { release { isMinifyEnabled = false } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isIncludeAndroidResources = true }
}
dependencies {
    compileOnly("org.godotengine:godot:4.7.1.stable")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
```

- [ ] **Step 2: Write the failing token-store tests**

```kotlin
@RunWith(RobolectricTestRunner::class)
class RefreshTokenStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val prefs = context.getSharedPreferences("credentials-test", Context.MODE_PRIVATE)
    private val cipher = FakeCipher()
    private val store = RefreshTokenStore(prefs, cipher)

    @Before fun reset() { prefs.edit().clear().commit() }

    @Test fun roundTripNeverStoresPlaintext() {
        store.save("refresh-secret-123")
        assertEquals("refresh-secret-123", store.load())
        assertFalse(prefs.all.values.any { it.toString().contains("refresh-secret-123") })
        assertTrue(store.contains())
    }

    @Test fun corruptedCiphertextIsClearedAndReturnsMissing() {
        store.save("refresh-secret-123")
        prefs.edit().putString(RefreshTokenStore.CIPHERTEXT_KEY, "broken").commit()
        assertNull(store.load())
        assertFalse(store.contains())
    }

    @Test fun clearRemovesAllStoredMaterial() {
        store.save("refresh-secret-123")
        store.clear()
        assertNull(store.load())
        assertTrue(prefs.all.isEmpty())
    }
}
```

The test-only `FakeCipher` reverses UTF-8 bytes and rejects malformed Base64; it lives beside the test and is never packaged.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd android/plugins/secure_credentials && ./gradlew :secure_credentials:testDebugUnitTest`

Expected: Kotlin compilation fails because `RefreshTokenStore`, `SecretCipher`, and `EncryptedValue` are unresolved.

- [ ] **Step 4: Implement AES-256-GCM and the minimal store**

```kotlin
data class EncryptedValue(val iv: ByteArray, val ciphertext: ByteArray)

interface SecretCipher {
    fun encrypt(plaintext: ByteArray): EncryptedValue
    fun decrypt(value: EncryptedValue): ByteArray
    fun deleteKey()
}

class AndroidKeystoreCipher(
    private val alias: String = "mathland.supabase.refresh.v1",
) : SecretCipher {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun key(): SecretKey {
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    override fun encrypt(plaintext: ByteArray): EncryptedValue {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return EncryptedValue(cipher.iv, cipher.doFinal(plaintext))
    }

    override fun decrypt(value: EncryptedValue): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, value.iv))
        return cipher.doFinal(value.ciphertext)
    }

    override fun deleteKey() { if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias) }
}
```

`RefreshTokenStore` uses preference file `mathland_secure_credentials`, keys `refresh_iv_v1` and `refresh_ciphertext_v1`, Android `Base64.NO_WRAP`, UTF-8, and synchronous `commit()` so success is not reported before durable persistence. `load()` catches malformed Base64, `GeneralSecurityException`, and key invalidation, clears both values, deletes the unusable key, and returns `null`. It never logs the token, IV, ciphertext, exception message, or preference contents.

- [ ] **Step 5: Run unit tests and inspect the packaged API**

Run: `cd android/plugins/secure_credentials && ./gradlew :secure_credentials:testDebugUnitTest :secure_credentials:assembleRelease`

Expected: `BUILD SUCCESSFUL`; three unit tests pass; `secure_credentials-release.aar` exists under `secure_credentials/build/outputs/aar/`.

- [ ] **Step 6: Commit**

```bash
git add android/plugins/secure_credentials
git commit -m "feat(android): encrypt refresh credentials with Android Keystore"
```

---

### Task 3: Expose and Package the Godot Android Plugin v2 Bridge

**Files:**
- Create: `android/plugins/secure_credentials/secure_credentials/src/main/AndroidManifest.xml`
- Create: `android/plugins/secure_credentials/secure_credentials/src/main/java/com/jinhoofkepco/mathland/securecredentials/SecureCredentialsPlugin.kt`
- Create: `android/plugins/secure_credentials/secure_credentials/src/androidTest/java/com/jinhoofkepco/mathland/securecredentials/SecureCredentialsInstrumentedTest.kt`
- Create: `addons/mathland_secure_credentials/plugin.cfg`
- Create: `addons/mathland_secure_credentials/export_plugin.gd`
- Create: `scripts/android/build_secure_credentials_plugin.sh`
- Create: `src/platform/secure_credential_store.gd`
- Create: `tests/integration/fakes/fake_secure_credentials_plugin.gd`
- Create: `tests/integration/test_secure_credential_store.gd`
- Modify: `tests/run_all.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `RefreshTokenStore` from Task 2 and `SyncService` credential-store injection from Subproject C.
- Produces: Android singleton `MathLandSecureCredentials` with exact camelCase methods `saveRefreshToken`, `loadRefreshToken`, `clearRefreshToken`, and `hasRefreshToken`, wrapped by the snake_case GDScript interface in the file map.

- [ ] **Step 1: Write failing GDScript wrapper tests**

```gdscript
# tests/integration/test_secure_credential_store.gd
extends RefCounted

func test_round_trip_delegates_to_plugin() -> void:
    var plugin := FakeSecureCredentialsPlugin.new()
    var store := SecureCredentialStore.new(plugin)
    assert_true(store.is_available())
    assert_true(store.save_refresh_token("refresh-token"))
    assert_eq(store.load_refresh_token(), "refresh-token")
    assert_true(store.clear_refresh_token())
    assert_eq(store.load_refresh_token(), "")

func test_missing_android_plugin_never_falls_back_to_file() -> void:
    var store := SecureCredentialStore.new(null, false)
    assert_false(store.is_available())
    assert_false(store.save_refresh_token("refresh-token"))
    assert_eq(store.load_refresh_token(), "")
```

Register an `integration` suite in `tests/run_all.gd` and include this test file.

- [ ] **Step 2: Run the focused suite to verify it fails**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration`

Expected: FAIL because `SecureCredentialStore` and `FakeSecureCredentialsPlugin` do not exist.

- [ ] **Step 3: Implement the Kotlin singleton and manifest registration**

```kotlin
class SecureCredentialsPlugin(godot: Godot) : GodotPlugin(godot) {
    private val store by lazy {
        val context = requireNotNull(activity).applicationContext
        RefreshTokenStore(
            context.getSharedPreferences("mathland_secure_credentials", Context.MODE_PRIVATE),
            AndroidKeystoreCipher(),
        )
    }

    override fun getPluginName() = "MathLandSecureCredentials"

    @UsedByGodot fun saveRefreshToken(token: String): Boolean = runCatching { store.save(token); true }.getOrDefault(false)
    @UsedByGodot fun loadRefreshToken(): String = runCatching { store.load().orEmpty() }.getOrDefault("")
    @UsedByGodot fun clearRefreshToken(): Boolean = runCatching { store.clear(); true }.getOrDefault(false)
    @UsedByGodot fun hasRefreshToken(): Boolean = runCatching { store.contains() }.getOrDefault(false)
}
```

```xml
<!-- android/plugins/secure_credentials/secure_credentials/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <meta-data
            android:name="org.godotengine.plugin.v2.MathLandSecureCredentials"
            android:value="com.jinhoofkepco.mathland.securecredentials.SecureCredentialsPlugin" />
    </application>
</manifest>
```

- [ ] **Step 4: Implement the fail-closed GDScript wrapper**

```gdscript
# src/platform/secure_credential_store.gd
class_name SecureCredentialStore
extends RefCounted

const SINGLETON_NAME := "MathLandSecureCredentials"
var _plugin: Object

func _init(plugin_override: Object = null, discover_plugin: bool = true) -> void:
    _plugin = plugin_override
    if _plugin == null and discover_plugin and Engine.has_singleton(SINGLETON_NAME):
        _plugin = Engine.get_singleton(SINGLETON_NAME)

func is_available() -> bool:
    return _plugin != null

func save_refresh_token(token: String) -> bool:
    return false if _plugin == null or token.is_empty() else bool(_plugin.saveRefreshToken(token))

func load_refresh_token() -> String:
    return "" if _plugin == null else String(_plugin.loadRefreshToken())

func clear_refresh_token() -> bool:
    return false if _plugin == null else bool(_plugin.clearRefreshToken())
```

The fake implements the same four camelCase methods in memory. It is reachable only from `tests/` and is excluded from every release preset.

- [ ] **Step 5: Package debug/release AARs as a Godot v2 editor plugin**

```gdscript
# addons/mathland_secure_credentials/export_plugin.gd
@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
    _export_plugin = AndroidExportPlugin.new()
    add_export_plugin(_export_plugin)

func _exit_tree() -> void:
    remove_export_plugin(_export_plugin)
    _export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
    func _supports_platform(platform: EditorExportPlatform) -> bool:
        return platform is EditorExportPlatformAndroid

    func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
        var variant := "debug" if debug else "release"
        return PackedStringArray(["mathland_secure_credentials/bin/%s/secure_credentials-%s.aar" % [variant, variant]])

    func _get_name() -> String:
        return "MathLandSecureCredentials"
```

`plugin.cfg` names the plugin `MathLandSecureCredentials`, version `1.0.0`, author `jinhoofkepco`, and script `export_plugin.gd`. `build_secure_credentials_plugin.sh` runs both AAR assemblies and copies each artifact to its exact `addons/mathland_secure_credentials/bin/{debug,release}/` destination. Enable `res://addons/mathland_secure_credentials/plugin.cfg` in `project.godot`.

- [ ] **Step 6: Add the on-device no-plaintext instrumentation test**

The instrumented test saves `device-refresh-token`, loads it, reads the private preferences XML through the app test context, asserts that neither the file nor its values contain the plaintext, clears the token, and asserts `hasRefreshToken()` is false. It also corrupts the stored ciphertext and asserts the plugin returns an empty string and clears both preference entries.

Run: `cd android/plugins/secure_credentials && ./gradlew :secure_credentials:connectedDebugAndroidTest`

Expected: `SecureCredentialsInstrumentedTest` passes on an API 35 emulator and Gradle reports `BUILD SUCCESSFUL`.

- [ ] **Step 7: Run both bridge suites**

Run: `./scripts/android/build_secure_credentials_plugin.sh && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration`

Expected: both AARs are copied, the editor detects `MathLandSecureCredentials`, and all integration tests pass without creating a credential file under the Godot project or `user://`.

- [ ] **Step 8: Commit**

```bash
git add android/plugins/secure_credentials addons/mathland_secure_credentials scripts/android/build_secure_credentials_plugin.sh src/platform/secure_credential_store.gd tests/integration tests/run_all.gd project.godot .gitignore
git commit -m "feat(android): bridge secure credentials into Godot"
```

---

### Task 4: Define Reproducible Android Export Presets and Privacy Defaults

**Files:**
- Create: `export_presets.cfg`
- Create: `scripts/android/export_debug.sh`
- Create: `scripts/android/inspect_manifest.sh`
- Create: `tests/integration/test_android_export_config.gd`
- Modify: `project.godot`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: Task 3 plugin output and final B-owned launcher/splash assets.
- Produces: `Android Debug`, `Android Smoke`, and `Android Release` presets; debug command writes `dist/MathLand-debug-arm64.apk` and the release preset receives signing only through Godot environment variables.

- [ ] **Step 1: Write the failing export-policy test**

The test reads `res://export_presets.cfg` and asserts all three presets use package `com.jinhoofkepco.mathland`, version `1.0.0`, code `1`, Gradle build, min SDK `24`, target SDK `35`, ARM64 only, backup disabled, Compatibility rendering, portrait project orientation, and blank keystore fields. It asserts release excludes `tests/**`, `.env*`, `reports/**`, `supabase/**`, `web/**`, `packages/**`, `scripts/**`, and Android plugin source while retaining the packaged AAR under `addons/`.

```gdscript
func test_release_export_policy() -> void:
    var text := FileAccess.get_file_as_string("res://export_presets.cfg")
    for required in [
        'name="Android Release"',
        'gradle_build/use_gradle_build=true',
        'gradle_build/min_sdk="24"',
        'gradle_build/target_sdk="35"',
        'architectures/arm64-v8a=true',
        'architectures/armeabi-v7a=false',
        'package/unique_name="com.jinhoofkepco.mathland"',
        'version/name="1.0.0"',
        'version/code=1',
        'user_data_backup/allow=false',
        'keystore/release=""',
        'keystore/release_password=""',
    ]:
        assert_true(text.contains(required), required)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration`

Expected: FAIL because `export_presets.cfg` is missing.

- [ ] **Step 3: Add exact Android preset values**

Each preset sets `gradle_build/use_gradle_build=true`, `gradle_build/gradle_build_directory="res://android"`, `gradle_build/export_format=0`, min/target `24`/`35`, `arm64-v8a=true`, all other ABIs false, `package/signed=true`, `package/retain_data_on_uninstall=false`, `screen/immersive_mode=true`, `user_data_backup/allow=false`, `graphics/opengl_debug=false`, and only `permissions/internet=true` plus `permissions/vibrate=true`. Release keystore path, user, and password remain empty in the file and are supplied as `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`.

```ini
[preset.2]
name="Android Release"
platform="Android"
runnable=false
custom_features="release"
export_filter="all_resources"
exclude_filter="tests/**,docs/**,reports/**,web/**,supabase/**,packages/**,scripts/**,android/plugins/**,.env,.env.*,dist/**"
export_path="dist/MathLand-v1.0.0-arm64.apk"

[preset.2.options]
gradle_build/use_gradle_build=true
gradle_build/gradle_build_directory="res://android"
gradle_build/export_format=0
gradle_build/min_sdk="24"
gradle_build/target_sdk="35"
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
keystore/release=""
keystore/release_user=""
keystore/release_password=""
version/code=1
version/name="1.0.0"
package/unique_name="com.jinhoofkepco.mathland"
package/name="MathLand"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
graphics/opengl_debug=false
screen/immersive_mode=true
screen/edge_to_edge=false
user_data_backup/allow=false
permissions/internet=true
permissions/vibrate=true
permissions/custom_permissions=PackedStringArray()
```

Keep `rendering/renderer/rendering_method="gl_compatibility"`, `rendering/renderer/rendering_method.mobile="gl_compatibility"`, `display/window/handheld/orientation=1`, and portrait stretch settings in `project.godot`.

- [ ] **Step 4: Implement debug export and final-manifest inspection scripts**

```bash
#!/usr/bin/env bash
# scripts/android/export_debug.sh
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
mkdir -p dist
./scripts/android/build_secure_credentials_plugin.sh
"$GODOT_BIN" --headless --path . --install-android-build-template --export-debug "Android Debug" "dist/MathLand-debug-arm64.apk"
./scripts/android/inspect_manifest.sh "dist/MathLand-debug-arm64.apk"
```

`inspect_manifest.sh` uses SDK 35 `apkanalyzer manifest print`; it requires package/version/min/target/`arm64-v8a`, `android:allowBackup="false"`, and rejects storage, camera, microphone, location, contacts, and advertising-ID permissions. It prints `PASS: Android manifest and ABI policy` only when every assertion succeeds.

- [ ] **Step 5: Run the complete debug export gate**

Run: `npm run verify:toolchain && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration && ./scripts/android/export_debug.sh`

Expected: integration tests pass, Godot reports a successful Android debug export, and manifest inspection ends with `PASS: Android manifest and ABI policy`.

- [ ] **Step 6: Commit**

```bash
git add export_presets.cfg project.godot .gitignore scripts/android/export_debug.sh scripts/android/inspect_manifest.sh tests/integration/test_android_export_config.gd
git commit -m "build(android): add private ARM64 export presets"
```

---
### Task 5: Exercise Android Install, Input, Lifecycle, Offline Restart, and Debug Upgrade

**Files:**
- Create: `tests/android/smoke_probe.gd`
- Create: `tests/android/smoke_log_fixture.txt`
- Create: `tests/release/android_smoke_log.test.mjs`
- Create: `scripts/android/emulator_smoke.sh`
- Modify: `tests/integration/test_offline_vertical_slice.gd`
- Modify: `tests/integration/test_lifecycle_resume.gd`
- Modify: `export_presets.cfg`
- Modify: `project.godot`

**Interfaces:**
- Consumes: unique scene controls `%CreateProfileButton`, `%ContinueButton`, `%AnswerButton`, `%ReturnToIslandButton`; `AppRouter`, `RunController`, `EventJournal`, and `SyncService` autoloads.
- Produces: newline-delimited `MATHLAND_SMOKE` JSON records and a final `{"status":"pass","scenario":"offline-lifecycle-upgrade"}` record.

- [ ] **Step 1: Write the failing smoke-log test**

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import { parseSmokeLog } from "../../scripts/android/parse-smoke-log.mjs";

test("requires every Android lifecycle checkpoint in order", () => {
  const result = parseSmokeLog(`MATHLAND_SMOKE {"step":"profile_select"}\nMATHLAND_SMOKE {"step":"offline_run_complete","pending":4}\nMATHLAND_SMOKE {"step":"foreground_resumed","duplicate_question":false}\nMATHLAND_SMOKE {"step":"force_stop_replayed","pending":4}\nMATHLAND_SMOKE {"step":"same_version_upgrade","pending":4}\nMATHLAND_SMOKE {"status":"pass","scenario":"offline-lifecycle-upgrade"}`);
  assert.equal(result.status, "pass");
  assert.equal(result.pendingAfterUpgrade, 4);
});
```

Run: `node --test tests/release/android_smoke_log.test.mjs`

Expected: FAIL because `parse-smoke-log.mjs` is missing.

- [ ] **Step 2: Implement the parser and debug-only Godot probe**

`parseSmokeLog(text)` parses only lines beginning `MATHLAND_SMOKE `, requires the six ordered records shown above, requires `pending > 0` while offline, and rejects `duplicate_question=true`.

`tests/android/smoke_probe.gd` runs only when both `OS.is_debug_build()` and `OS.has_feature("integration_test")` are true. It waits for `scenes/app/app_shell.tscn`, sends down/up `InputEventScreenTouch` pairs to the four named controls, completes a deterministic offline run, verifies the event journal before visual advancement, records the current question seed before pause, and asserts the same seed after resume. Release startup never loads this file.

Add an `Android Smoke` preset with `custom_features="integration_test"`, debug signing, `tests/android/**` included, and all Task 4 package/SDK/ABI/privacy values unchanged.

- [ ] **Step 3: Implement the ADB lifecycle script**

```bash
#!/usr/bin/env bash
set -euo pipefail
ADB="${ANDROID_SDK_ROOT:-$ANDROID_HOME}/platform-tools/adb"
APK="dist/MathLand-smoke-arm64.apk"
PACKAGE="com.jinhoofkepco.mathland"
trap '"$ADB" shell svc wifi enable >/dev/null 2>&1 || true; "$ADB" shell svc data enable >/dev/null 2>&1 || true' EXIT
./scripts/android/build_secure_credentials_plugin.sh
"${GODOT_BIN:-/opt/homebrew/bin/godot}" --headless --path . --install-android-build-template --export-debug "Android Smoke" "$APK"
"$ADB" install -r "$APK"
"$ADB" logcat -c
"$ADB" shell svc wifi disable
"$ADB" shell svc data disable
"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
sleep 2
"$ADB" shell input keyevent KEYCODE_HOME
"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
"$ADB" shell am force-stop "$PACKAGE"
"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
"$ADB" install -r "$APK"
"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1
"$ADB" logcat -d | node scripts/android/parse-smoke-log.mjs
```

- [ ] **Step 4: Run the emulator test and commit**

Run: `./scripts/android/emulator_smoke.sh`

Expected: APK install/update commands succeed and parser prints `PASS: offline lifecycle and same-version upgrade`.

```bash
git add export_presets.cfg project.godot scripts/android tests/android tests/release/android_smoke_log.test.mjs
git commit -m "test(android): cover offline lifecycle and upgrade smoke flow"
```

---

### Task 6: Implement Device Authentication, Durable Sync, Remote Content, and Dashboard Proof

**Files:**
- Create: `resources/config/cloud_public.example.json`
- Create: `scripts/android/write_public_cloud_config.sh`
- Create: `src/sync/http_json_transport.gd`
- Create: `src/sync/supabase_device_auth.gd`
- Create: `src/sync/sync_retry_policy.gd`
- Create: `src/sync/sync_cursor_store.gd`
- Create: `src/sync/cloud_sync_service.gd`
- Create: `src/content/remote_content_updater.gd`
- Create: `tests/support/fake_http_json_transport.gd`
- Create: `tests/support/fake_secure_credential_store.gd`
- Create: `tests/unit/test_supabase_device_auth.gd`
- Create: `tests/unit/test_sync_retry_policy.gd`
- Create: `tests/unit/test_cloud_sync_service.gd`
- Create: `tests/content/remote_content_updater_test.gd`
- Create: `packages/integration-tests/package.json`
- Create: `packages/integration-tests/tsconfig.json`
- Create: `packages/integration-tests/src/offline-sync-scenario.ts`
- Create: `packages/integration-tests/tests/offline-sync-dashboard.test.ts`
- Create: `tests/fixtures/integration/offline-run-events.jsonl`
- Create: `scripts/integration/run_local_e2e.sh`
- Modify: `package.json`
- Modify: `.gitignore`
- Modify: `src/persistence/event_journal.gd`
- Modify: `src/content/content_repository.gd`
- Modify: `src/ui/island/settings.gd`
- Modify: `tests/integration/test_offline_vertical_slice.gd`
- Modify: `tests/run_all.gd`

**Interfaces:**
- Consumes: `LearningEventV1`, `EventJournal.unacknowledged`, `ProgressService.snapshot`, Task 3's `SecureCredentialStore`, Supabase anonymous Auth/pairing/ingest/publication endpoints, B's `ContentRepository`, guardian aggregate view, and web dashboard route from A–C.
- Produces: `SupabaseDeviceAuth.ensure_session()`, `pair(code, profile_id)`, `CloudSyncService.request_sync()`, `SyncRetryPolicy.next_delay_ms(attempt)`, `RemoteContentUpdater.check_and_install()`, `EventJournal.compact_through(sequence)`, and `OfflineSyncEvidence { eventIds, acceptedIds, duplicateIds, pendingAfterAck, aggregateCorrect, aggregateAttempts, staleState }`.

- [ ] **Step 1: Write failing Godot auth, retry, synchronization, and content-update tests**

Use `FakeHttpJsonTransport`, a fake clock, and `FakeSecureCredentialStore`. Assert anonymous sign-in saves only the refresh token through the secure store; pairing sends the six-digit code plus selected profile and retains local progress on 401/403. Append 205 events and assert three ordered batches of `100,100,5`; replay the first response and assert duplicate IDs are treated as acknowledged. Assert transient delays begin at 2000 ms, use deterministic injected jitter, cap at 300000 ms, and reset after success. Assert authentication, schema, and permission diagnostics suspend retries while network/5xx retry. Assert acknowledged events are compacted only after `ProgressService.snapshot()` succeeds.

For content, serve a newer publication manifest and packages; assert schema/checksum/allowlist validation occurs before an atomic active-manifest switch, a running repository lookup pinned to the prior version remains unchanged, and an invalid download leaves the last valid cache active.

- [ ] **Step 2: Run the focused Godot tests and verify red**

Run:

```bash
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content
```

Expected: FAIL naming missing `SupabaseDeviceAuth`, `CloudSyncService`, `SyncRetryPolicy`, and `RemoteContentUpdater`.

- [ ] **Step 3: Add strict public cloud configuration and device authentication**

`cloud_public.example.json` contains only `{ "supabase_url": "https://example.supabase.co", "publishable_key": "sb_publishable_example" }`. Add `resources/config/cloud_public.json` to `.gitignore`. `write_public_cloud_config.sh` validates HTTPS, rejects localhost for release, rejects any key containing `service_role`, and writes the runtime file from `MATHLAND_SUPABASE_URL` and `MATHLAND_SUPABASE_PUBLISHABLE_KEY` immediately before export; these values are public client configuration, not privileged secrets.

`SupabaseDeviceAuth` calls `/auth/v1/signup` with anonymous Auth enabled, refreshes once through `/auth/v1/token?grant_type=refresh_token`, stores the refresh token only through `SecureCredentialStore`, keeps the access token in memory, and exposes a pairing call to `/functions/v1/pair-device`. The settings screen accepts a six-digit pairing code, never stores it, announces success/failure, and leaves the profile playable on every failure.

- [ ] **Step 4: Implement batching, retry classification, acknowledgement, and safe compaction**

`CloudSyncService.request_sync()` returns immediately when another request is active, loads at most 100 events after the stored acknowledged sequence, posts them in sequence order to `/functions/v1/ingest-events`, verifies that every returned ID came from the batch, advances the cursor across both `accepted_event_ids` and `already_present_event_ids`, flushes a fresh progress snapshot, then calls `EventJournal.compact_through(acknowledged_sequence)`. `compact_through` atomically rewrites only later events and never mutates `_next_sequence`. Network timeouts and 5xx responses schedule injected-jitter delays between 2 seconds and 5 minutes; 401 attempts one refresh, while persistent auth, 400 schema, and 403 permission responses retain events and suspend the batch with a diagnostic code. Runs never await this service.

- [ ] **Step 5: Implement verified remote-content installation**

`RemoteContentUpdater.check_and_install()` reads the public immutable publication manifest, downloads into `user://content/downloads/<manifest-version>.tmp/`, delegates schema/checksum/resource/generator validation to `ContentRepository`, flushes every file, atomically renames the verified directory, and atomically replaces the cache publication pointer. It reports `up_to_date`, `installed`, or a stable diagnostic; it never deletes the bundled package or current valid cache. Activity runs continue to pass their starting `content_version` explicitly.

- [ ] **Step 6: Run the Godot synchronization and content suites**

Run:

```bash
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content
```

Expected: auth/token-storage, `100,100,5` batching, duplicate acknowledgement, retry classification/cap, snapshot-before-compaction, pinned-run version, atomic install, invalid-download fallback, and offline nonblocking cases pass.

- [ ] **Step 7: Write the failing cross-system test**

```typescript
it("retries one offline run exactly once and renders its aggregate", async () => {
  const evidence = await runOfflineSyncScenario({ seed: 41017, answers: [true, false, true] });
  expect(evidence.acceptedIds).toEqual(evidence.eventIds);
  expect(evidence.duplicateIds).toEqual(evidence.eventIds);
  expect(evidence.pendingAfterAck).toBe(0);
  expect(evidence.aggregateAttempts).toBe(3);
  expect(evidence.aggregateCorrect).toBe(2);
  expect(evidence.staleState).toBe(false);
});
```

Run: `npm --workspace @mathland/integration-tests test`

Expected: FAIL because `runOfflineSyncScenario` is missing.

- [ ] **Step 8: Implement the deterministic harness**

The harness creates one synthetic nickname `Release Check`, authenticates a local anonymous device, consumes a local one-use pairing code, loads the JSONL emitted by the real Godot `EventJournal`, submits the same batch twice, snapshots/compacts only after acknowledgement, queries the guardian aggregate view, and passes the aggregate to the actual web dashboard loader. It rejects any fixture containing an email, real name, location, contact, camera, microphone, or advertising ID.

`run_local_e2e.sh` runs, in order: `npx supabase start`, `npx supabase db reset`, local Edge Functions, `npm run test:contracts`, `npm run test:content-tools`, `npm run validate:content`, the real Godot sync/content tests against a loopback test transport, the integration package test, and Playwright against the local web app. A trap stops local services.

- [ ] **Step 9: Run the full local flow**

Run: `./scripts/integration/run_local_e2e.sh`

Expected: duplicate ingestion is acknowledged, three attempts/two correct appear in the dashboard, and the script ends `PASS: offline journal -> idempotent ingest -> guardian dashboard`.

- [ ] **Step 10: Commit**

```bash
git add package.json .gitignore resources/config/cloud_public.example.json scripts/android/write_public_cloud_config.sh src/sync src/content/remote_content_updater.gd src/content/content_repository.gd src/persistence/event_journal.gd src/ui/island/settings.gd tests packages/integration-tests scripts/integration/run_local_e2e.sh
git commit -m "feat(integration): synchronize offline events and remote content"
```

---

### Task 7: Enforce Performance, Responsiveness, and Accessibility Gates

**Files:**
- Create: `scripts/android/analyze-framestats.mjs`
- Create: `scripts/android/measure_performance.sh`
- Create: `scripts/android/capture_viewports.sh`
- Create: `tests/release/analyze_framestats.test.mjs`
- Create: `tests/fixtures/android/gfxinfo-framestats.txt`
- Modify: `tests/integration/test_accessibility_and_performance_contract.gd`
- Create: `docs/quality/v1.0.0-performance.md`

**Interfaces:**
- Consumes: A/B effect quality tiers, reduced-motion setting, responsive scenes, and structured `MATHLAND_PERF` input-feedback records.
- Produces: frame p95, FPS, cold-launch milliseconds, input-feedback p95, APK bytes, viewport screenshots, and a release-blocking findings list.

- [ ] **Step 1: Write failing parser and scene-gate tests**

```javascript
test("passes the approved thresholds", () => {
  const result = analyzeFrameStats(fixture);
  assert.deepEqual(evaluatePerformance(result, {
    frameP95Ms: 25, launchMs: 5000, feedbackMs: 100, apkBytes: 200 * 1024 * 1024,
  }), []);
});
```

The Godot test instantiates profile select, island, run, reward, inventory, settings, dashboard-empty-state preview, and every manipulative at `360×800`, `1080×2400`, and `800×1280`; it asserts every visible control remains inside the viewport, every interactive minimum size maps to at least 48dp, and correctness is not color-only.

Run: `node --test tests/release/analyze_framestats.test.mjs && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration`

Expected: FAIL because the analyzer and accessibility gate do not exist.

- [ ] **Step 2: Implement measurement and analysis**

`analyzeFrameStats` parses `dumpsys gfxinfo ... framestats`, discards warm-up frames, computes sorted p95 without averaging percentiles, and requires strict frame p95 `<25ms`. `measure_performance.sh` resolves the launcher component, records `am start -W`, captures normal and effect-heavy frame stats after warm-up, records `MATHLAND_PERF` feedback deltas, and checks `stat` bytes. `capture_viewports.sh` applies each exact viewport with `adb shell wm size`, captures reviewed PNGs, and restores the original size in a trap.

- [ ] **Step 3: Run on the reference API 35 ARM64 emulator**

Run: `./scripts/android/measure_performance.sh dist/MathLand-release-candidate-arm64.apk && ./scripts/android/capture_viewports.sh`

Expected: 60 FPS normal play, frame p95 below 25 ms, launch at most 5000 ms, feedback at most 100 ms, APK at most 209715200 bytes, and three viewport captures without clipping. Record actual device image, warm-up, samples, measurements, and quality tier in `docs/quality/v1.0.0-performance.md`.

- [ ] **Step 4: Commit**

```bash
git add scripts/android tests/release/analyze_framestats.test.mjs tests/fixtures/android tests/integration/test_accessibility_and_performance_contract.gd docs/quality/v1.0.0-performance.md
git commit -m "test(quality): enforce Android performance and viewport gates"
```

---

### Task 8: Audit Privacy, Secrets, Permissions, Assets, and Release Bundles

**Files:**
- Create: `scripts/release/audit-release.mjs`
- Create: `tests/release/audit_release.test.mjs`
- Create: `tests/fixtures/release-audit/clean.txt`
- Create: `tests/fixtures/release-audit/contaminated.txt`
- Create: `PRIVACY.md`
- Create: `SECURITY.md`
- Modify: `ASSET_LICENSES.md`

**Interfaces:**
- Consumes: APK, web bundle, repository tree, final manifest, and B-owned asset ledger.
- Produces: `auditRelease(input) -> ReleaseAuditFinding[]`; zero findings is mandatory.

- [ ] **Step 1: Write a failing contamination test**

The dirty fixture contains `SUPABASE_SERVICE_ROLE_KEY`, `sk-` provider-key syntax, `yourserver.com`, `localhost`, a private-key header, and a `.jks` name. Assert one typed finding per forbidden value; assert the clean fixture and configured Supabase publishable key pass.

Run: `node --test tests/release/audit_release.test.mjs`

Expected: FAIL because `audit-release.mjs` is missing.

- [ ] **Step 2: Implement the audit**

The script scans tracked files, `git log -p --all`, uncompressed APK entries/strings, and `web/dist`; rejects signing files, service-role/AI/private keys, sample/dev hosts, real child data, debug test probes, and unlisted assets; verifies only `INTERNET` and `VIBRATE` permissions, `allowBackup=false`, package/version/SDK/ABI, no debuggable flag, and every bundled art/audio/font/voice row in `ASSET_LICENSES.md` has `original`, `generated`, or `third-party`, permitted redistribution, creator/source, and review status. `PRIVACY.md` documents nickname-only profiles, learning data, retention/deletion/export, offline queueing, no ads/tracking, no AI child logs, and guardian contact. `SECURITY.md` documents reporting, credential boundaries, RLS, local PIN limitations, and supported release.

- [ ] **Step 3: Run and commit the audit**

Run: `node --test tests/release/audit_release.test.mjs && node scripts/release/audit-release.mjs --apk dist/MathLand-release-candidate-arm64.apk --web web/dist --assets ASSET_LICENSES.md`

Expected: tests pass and audit prints `PASS: 0 release privacy/security/license findings`.

```bash
git add scripts/release tests/release tests/fixtures/release-audit PRIVACY.md SECURITY.md ASSET_LICENSES.md
git commit -m "chore(release): audit privacy secrets and asset rights"
```

---

### Task 9: Add Credential-Free Integration and Android CI

**Files:**
- Create: `.github/workflows/integration.yml`
- Create: `scripts/ci/godot-downloads.sha256`
- Modify: `package.json`

**Interfaces:**
- Consumes: Tasks 1–8 and all A–C test commands.
- Produces: required checks `godot`, `content-web-db`, `android-plugin-export`, `local-e2e`, and `artifact-audit`; no job reads production secrets.

- [ ] **Step 1: Add a failing workflow contract test**

Extend `tests/release/audit_release.test.mjs` to parse the workflow and require exact Godot `4.7.1`, JDK `17`, Android platform `35`, build-tools `35.0.1`, no `pull_request_target`, explicit least-privilege `permissions`, and the five required job IDs.

Run: `node --test tests/release/audit_release.test.mjs`

Expected: FAIL because `.github/workflows/integration.yml` is absent.

- [ ] **Step 2: Implement the workflow**

Use `ubuntu-24.04`; `contents: read`; Node install via lockfile; JDK 17; SDK 35/build-tools 35.0.1. Download official Linux Godot and templates and verify:

```text
c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba  Godot_v4.7.1-stable_linux.x86_64.zip
86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72  Godot_v4.7.1-stable_export_templates.tpz
```

Run `npm ci`, contract/content/web tests, Godot `unit`, `scene`, `integration`, and `all`, Supabase SQL/function/RLS tests locally, plugin unit tests, debug export, release audit against the debug artifact, and local E2E. Upload only debug APK, screenshots, and test reports with seven-day retention.

- [ ] **Step 3: Validate locally and commit**

Run: `node --test tests/release/audit_release.test.mjs && actionlint .github/workflows/integration.yml`

Expected: all workflow policy tests pass and `actionlint` emits no diagnostics.

```bash
git add .github/workflows/integration.yml scripts/ci/godot-downloads.sha256 package.json tests/release/audit_release.test.mjs
git commit -m "ci: gate integration and Android debug artifacts"
```

---

### Task 10: Create External Signing Operations and a Verified Release Build

**Files:**
- Create: `scripts/release/build_signed_apk.sh`
- Create: `scripts/release/verify_signed_apk.sh`
- Create: `tests/release/signing_output.test.mjs`
- Create: `docs/operations/android-signing.md`
- Create: `release/android-signing-cert.sha256`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: external keystore alias `mathland-release`, macOS Keychain service `MathLand Android Release Keystore Password`, and Godot signing environment variables.
- Produces: `dist/MathLand-v1.0.0-arm64.apk`, `dist/MathLand-v1.0.0-arm64.apk.sha256`, and a certificate digest matching the committed fingerprint.

- [ ] **Step 1: Write the failing verifier-output test**

Test parsers require `Verified`, package `com.jinhoofkepco.mathland`, version `1.0.0`/`1`, ARM64 only, SHA-256 checksum format, and exact signer certificate digest; mismatch must fail.

Run: `node --test tests/release/signing_output.test.mjs`

Expected: FAIL because the verifier does not exist.

- [ ] **Step 2: Document one-time external key generation**

```bash
SIGNING_DIR="$HOME/Library/Application Support/MathLand/signing"
mkdir -p "$SIGNING_DIR"
keytool -genkeypair -v -keystore "$SIGNING_DIR/mathland-release.jks" -alias mathland-release -keyalg RSA -keysize 4096 -validity 9125 -dname "CN=MathLand Android Release,OU=MathLand,O=jinhoofkepco,L=Seoul,ST=Seoul,C=KR"
security add-generic-password -U -a "$USER" -s "MathLand Android Release Keystore Password" -w
keytool -list -v -keystore "$SIGNING_DIR/mathland-release.jks" -alias mathland-release
```

Record the actual SHA-256 certificate fingerprint, creation date, expiry, alias, storage/backup owners, and recovery drill in `docs/operations/android-signing.md`; put only the normalized digest in `release/android-signing-cert.sha256`. The keystore and password remain outside Git and chat.

- [ ] **Step 3: Implement signed build and verification scripts**

`build_signed_apk.sh` resolves the external path, reads the password from Keychain without printing it, calls `scripts/android/write_public_cloud_config.sh` from the two publishable repository/environment variables, exports the three Godot signing variables, builds the plugin, exports `Android Release`, removes the generated public-config source file after export, unsets the password, and writes `shasum -a 256`. CI accepts signing values only through protected environment secrets, reconstructs the keystore under `$RUNNER_TEMP`, and supplies the non-secret Supabase URL/publishable key through repository variables.

`verify_signed_apk.sh` runs `apksigner verify --verbose --print-certs`, `apkanalyzer`, the Task 8 audit, size/performance evidence checks, checksum verification, and compares the normalized signer digest with `release/android-signing-cert.sha256`.

- [ ] **Step 4: Build, verify, and commit non-secret signing metadata**

Run: `./scripts/release/build_signed_apk.sh && ./scripts/release/verify_signed_apk.sh dist/MathLand-v1.0.0-arm64.apk`

Expected: `PASS: signed MathLand 1.0.0 ARM64 APK verified`; no secret appears in stdout, process arguments, Git status, or artifact contents.

```bash
git add .gitignore scripts/release docs/operations/android-signing.md release/android-signing-cert.sha256 tests/release/signing_output.test.mjs
git commit -m "build(release): add external signing and APK verification"
```

---

### Task 11: Complete Release Documentation, Screenshots, and Recovery Evidence

**Files:**
- Create: `release/v1.0.0-manifest.json`
- Create: `docs/releases/v1.0.0.md`
- Create: `docs/operations/android-build.md`
- Create: `docs/operations/live-integration.md`
- Create: `docs/operations/release.md`
- Create: `docs/operations/rollback-and-recovery.md`
- Create: `docs/screenshots/v1.0.0/profile-select.png`
- Create: `docs/screenshots/v1.0.0/exploration-island.png`
- Create: `docs/screenshots/v1.0.0/ten-rod-run.png`
- Create: `docs/screenshots/v1.0.0/run-reward.png`
- Create: `docs/screenshots/v1.0.0/guardian-dashboard.png`
- Create: `docs/screenshots/v1.0.0/content-studio.png`
- Create: `scripts/release/check_manifest.mjs`
- Modify: `README.md`

**Interfaces:**
- Consumes: actual verified APK/checksum, performance report, privacy/security docs, and asset ledger.
- Produces: complete install/operate/recover documentation and exact release asset inventory.

- [ ] **Step 1: Write a failing manifest check**

Require manifest values `v1.0.0`, `com.jinhoofkepco.mathland`, code `1`, min/target `24`/`35`, `arm64-v8a`, Compatibility renderer, APK/checksum names, six screenshot names, `ASSET_LICENSES.md`, release notes, source tag, certificate fingerprint file, and live-gate evidence.

Run: `node scripts/release/check_manifest.mjs release/v1.0.0-manifest.json`

Expected: non-zero exit with a precise missing-file list.

- [ ] **Step 2: Write and capture the release collateral**

Document clean install from GitHub, unknown-source warning, minimum Android version, offline behavior, guardian pairing, checksum verification, uninstall/data deletion, Supabase deployment/recovery, content rollback, device disconnect, key recovery, draft-release recovery, and the known limitation that distribution is APK/GitHub only. Capture the six named screenshots from release-candidate builds with synthetic data; strip EXIF/location metadata and review child nicknames before commit.

- [ ] **Step 3: Validate and commit**

Run: `node scripts/release/check_manifest.mjs release/v1.0.0-manifest.json && node scripts/release/audit-release.mjs --apk dist/MathLand-v1.0.0-arm64.apk --web web/dist --assets ASSET_LICENSES.md`

Expected: `PASS: v1.0.0 release manifest complete` and zero audit findings.

```bash
git add README.md release/v1.0.0-manifest.json docs/releases/v1.0.0.md docs/operations/android-build.md docs/operations/live-integration.md docs/operations/release.md docs/operations/rollback-and-recovery.md docs/screenshots/v1.0.0 scripts/release/check_manifest.mjs
git commit -m "docs: complete v1.0.0 release operations"
```

---

### Task 12: Pass the Authorized Live Gate and Publish a Verified Draft Release

**Files:**
- Create: `packages/integration-tests/src/live-release-gate.ts`
- Create: `packages/integration-tests/tests/live-release-gate.test.ts`
- Create: `scripts/integration/run_live_release_gate.sh`
- Create: `release/evidence/live-e2e-v1.0.0.json`
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: trusted Supabase browser/CLI authorization, protected GitHub `production-release` environment, signed build secrets, actual release APK, and synthetic `Release Check` profile.
- Produces: scrubbed live evidence, annotated `v1.0.0` tag, draft GitHub Release, independently downloaded/verified assets, then public release.

- [ ] **Step 1: Write failing live-gate state-machine tests**

Test states `awaiting_authorization → paired → offline_event_created → synchronized → dashboard_confirmed → cleanup_confirmed`; publication must reject skipped/out-of-order states, missing RLS negative-test evidence, or evidence older than 24 hours.

Run: `npm --workspace @mathland/integration-tests test -- live-release-gate`

Expected: FAIL because `live-release-gate.ts` is missing.

- [ ] **Step 2: Implement the authorized live gate**

`run_live_release_gate.sh` first runs every local/CI/release check. It then opens the trusted guardian magic-link flow, creates only the synthetic `Release Check` profile through normal owner/guardian APIs, pairs the signed APK on the API 35 emulator, disables network, completes one real activity, force-stops/restarts, reconnects, waits for exactly-once ingestion, opens the dashboard, asserts the new aggregate and sync timestamp, runs cross-family denial tests, exports then deletes the synthetic profile, disconnects the device, and writes scrubbed evidence containing timestamps, version, event ID hash, result booleans, and no tokens or personal data.

Run: `./scripts/integration/run_live_release_gate.sh dist/MathLand-v1.0.0-arm64.apk`

Expected: `PASS: signed child event synchronized exactly once and appeared in authorized dashboard`; the synthetic cloud/local profile is deleted.

- [ ] **Step 3: Implement protected draft-release automation**

The workflow triggers only by manual dispatch for an existing `v1.0.0` annotated tag at the reviewed commit; sets `contents: write`; uses environment `production-release`; reconstructs the keystore only in `$RUNNER_TEMP`; builds from source; verifies signer/checksum/audit/manifest/live evidence; uploads the APK, checksum, release notes, screenshots, `ASSET_LICENSES.md`, and source tag to a draft Release. A separate verification job downloads every draft asset, rechecks checksum/signature/install/launch, then publishes the draft. Failure leaves it non-public.

- [ ] **Step 4: Run the final clean-room gate**

```bash
npm ci
npm run test:contracts
npm run test:content-tools
npm run validate:content
npm run build:content
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite all
./scripts/integration/run_local_e2e.sh
./scripts/android/emulator_smoke.sh
./scripts/release/verify_signed_apk.sh dist/MathLand-v1.0.0-arm64.apk
node scripts/release/check_manifest.mjs release/v1.0.0-manifest.json
```

Expected: every command exits `0`; no ignored security/content failure; all release gates print `PASS`.

- [ ] **Step 5: Commit evidence/workflow, tag, publish, and verify download**

```bash
git add packages/integration-tests scripts/integration release/evidence/live-e2e-v1.0.0.json .github/workflows/release.yml
git commit -m "release: gate MathLand 1.0.0 publication"
git tag -a v1.0.0 -m "MathLand 1.0.0"
git push origin main
git push origin v1.0.0
gh workflow run release.yml -f tag=v1.0.0
gh run watch --exit-status
gh release view v1.0.0 --json isDraft,tagName,assets
```

Expected: workflow succeeds, `isDraft` is `false`, all manifest assets are present, and a fresh download passes checksum/signature verification and installs/launches on the API 35 ARM64 emulator.

---

## Final Release Gate

Before declaring Subproject D complete, rerun the Task 12 clean-room commands and confirm:

- `git status --short` is empty and the tag points at the tested commit.
- CI required checks are green on that commit.
- The external keystore, passwords, Supabase service role, AI key, child data, and test-only probe are absent from repository history and artifacts.
- The signed APK is ARM64-only, at most 200 MB, package `com.jinhoofkepco.mathland`, version `1.0.0`/`1`, min/target SDK `24`/`35`, non-debuggable, backup-disabled, and signed by the documented certificate.
- Offline first-install play, lifecycle resume, same-version debug update, idempotent synchronization, cross-family denial, dashboard display, profile deletion, and device disconnect all passed.
- Performance, input latency, 48dp targets, reduced motion, audio independence, three portrait viewports, screenshots, asset rights, privacy, recovery, checksum, and fresh-download installation evidence are committed.
- The GitHub Release and tag at `jinhoofkepco/Mathland_new2` are public only after the authorized live gate passes.
