import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing — fails closed.
//
// Release signing credentials live in android/key.properties, which is
// gitignored and never committed (LOCKED PRINCIPLE #6). This file may name the
// keys it needs; it must never contain their values.
//
// There are exactly three outcomes for a release build, and no silent one:
//
//   1. key.properties present and complete -> signed with the release key.
//   2. No signing material AND the build explicitly opts in to an unsigned
//      build -> produced with NO signing config at all. Not installable, not
//      distributable. This is the CI path.
//   3. No signing material and no opt-in -> the build FAILS.
//
// The previous behaviour was to fall back to the debug keystore with only a
// logger warning. That produced an APK that looked like a release build,
// carried "release" in its filename, and was signed with a shared, well-known,
// per-machine key. It could not be upgraded in place and must never reach a
// tester. A warning in a 500-line Gradle log is not a control.
//
// Opt in to the unsigned path with either:
//     WELLAPATH_ALLOW_UNSIGNED_RELEASE=true   (environment variable)
//     -Pwellapath.allowUnsignedRelease=true   (Gradle property)
// ---------------------------------------------------------------------------

/// Keys android/key.properties must define. Names only — never values.
val requiredSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreFile = keystorePropertiesFile.exists()

if (hasKeystoreFile) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }

    // Fail on an incomplete file rather than letting Gradle throw a
    // ClassCastException on a null cast further down, which reads as a build
    // bug rather than a configuration problem.
    val missing = requiredSigningKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/key.properties is present but incomplete. Missing or empty: " +
                "${missing.joinToString(", ")}. Required keys: " +
                "${requiredSigningKeys.joinToString(", ")}. " +
                "Values are never committed — obtain them with the founder-issued keystore."
        )
    }

    // A storeFile path that does not resolve would otherwise surface as an
    // opaque signing failure late in the build.
    val storeFilePath = keystoreProperties.getProperty("storeFile")
    val resolvedStore = file(storeFilePath)
    if (!resolvedStore.exists()) {
        throw GradleException(
            "android/key.properties points at a keystore that does not exist. " +
                "Check the storeFile path. (Path not echoed here: it can contain " +
                "a username or directory layout.)"
        )
    }
}

val allowUnsignedRelease =
    System.getenv("WELLAPATH_ALLOW_UNSIGNED_RELEASE") == "true" ||
        project.findProperty("wellapath.allowUnsignedRelease") == "true"

android {
    namespace = "org.wellapath.wellapath_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "org.wellapath.wellapath_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreFile) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasKeystoreFile -> signingConfigs.getByName("release")

                allowUnsignedRelease -> {
                    // Explicitly unsigned. Never labelled as release-signed:
                    // apksigner reports no signer, so a distributability check
                    // downstream cannot be fooled.
                    logger.lifecycle(
                        "WellaPath: building an UNSIGNED release. No signing material " +
                            "present and the unsigned path was explicitly requested. " +
                            "This artifact is NOT installable and NOT distributable."
                    )
                    null
                }

                else -> throw GradleException(
                    "Release build refused: no Android signing material.\n" +
                        "  android/key.properties is absent, so this build cannot be signed " +
                        "with the release key.\n" +
                        "  Release builds no longer fall back to debug signing — a " +
                        "debug-signed APK is not upgradable in place and must never reach " +
                        "a tester.\n" +
                        "  To sign: create android/key.properties (gitignored) defining " +
                        "${requiredSigningKeys.joinToString(", ")} from the founder-issued " +
                        "keystore. See docs/BETA_ROLLBACK.md.\n" +
                        "  To build an explicitly UNSIGNED, non-distributable release for CI: " +
                        "set WELLAPATH_ALLOW_UNSIGNED_RELEASE=true."
                )
            }
        }

        // Debug keeps debug signing. That is correct and unchanged — the
        // fail-closed rule is about release builds only.
    }
}

flutter {
    source = "../.."
}
