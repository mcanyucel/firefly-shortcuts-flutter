  import java.util.Properties
  import java.io.FileInputStream
  import com.android.build.api.variant.FilterConfiguration.FilterType.ABI

  plugins {
      id("com.android.application")
      id("dev.flutter.flutter-gradle-plugin")
  }

  val keystoreProperties = Properties()
  val keystorePropertiesFile = rootProject.file("key.properties")
  if (keystorePropertiesFile.exists()) {
      keystoreProperties.load(FileInputStream(keystorePropertiesFile))
  }

  // F-Droid wants the ABI split scheme "versionCode * 10 + abi". Flutter's
  // --split-per-abi instead applies "abi * 1000 + versionCode" from its plugin,
  // registered in afterEvaluate so it clobbers anything set here. Its two
  // split-related blocks are both gated on the Gradle property below, while the
  // flutter tool decides the expected APK filenames on its own, so clearing the
  // property leaves the tool splitting while this file owns the version codes.
  if (project.hasProperty("split-per-abi")) {
      project.setProperty("split-per-abi", "false")
  }

  val abiForTargetPlatform = mapOf(
      "android-arm" to "armeabi-v7a",
      "android-arm64" to "arm64-v8a",
      "android-x64" to "x86_64"
  )
  val requestedAbis = (project.findProperty("target-platform") as String?)
      ?.split(",")
      ?.mapNotNull { abiForTargetPlatform[it.trim()] }
      ?.takeIf { it.isNotEmpty() }
      ?: abiForTargetPlatform.values.toList()

  android {
      namespace = "com.mustafacanyucel.firefly_shortcuts"
      compileSdk = flutter.compileSdkVersion
      ndkVersion = flutter.ndkVersion

      compileOptions {
          sourceCompatibility = JavaVersion.VERSION_17
          targetCompatibility = JavaVersion.VERSION_17
      }

      signingConfigs {
          create("release") {
              keyAlias = keystoreProperties["keyAlias"] as String
              keyPassword = keystoreProperties["keyPassword"] as String
              storeFile = file(keystoreProperties["storeFile"] as String)
              storePassword = keystoreProperties["storePassword"] as String
          }
      }

      defaultConfig {
          applicationId = "com.mustafacanyucel.firefly_shortcuts"
          minSdk = flutter.minSdkVersion
          targetSdk = flutter.targetSdkVersion
          versionCode = flutter.versionCode
          versionName = flutter.versionName
          manifestPlaceholders["appAuthRedirectScheme"] = "com.mustafacanyucel.firefly_shortcuts"
      }

      // Splitting is done here instead of by flutter's plugin. The ABI list
      // follows the -Ptarget-platform the flutter tool forwards, so a single
      // invocation still yields exactly one APK.
      splits {
          abi {
              isEnable = true
              reset()
              include(*requestedAbis.toTypedArray())
              isUniversalApk = false
          }
      }

      buildTypes {
          release {
              signingConfig = signingConfigs.getByName("release")
              isMinifyEnabled = true
              isShrinkResources = true
              proguardFiles(
                  getDefaultProguardFile("proguard-android-optimize.txt"),
                  "proguard-rules.pro"
              )
          }
      }
  }

  // Ordered armeabi-v7a < arm64-v8a < x86_64, per F-Droid's requirement. Uses
  // the AGP 9 variant API; applicationVariants and ApkVariantOutputImpl, which
  // the older recipe for this relies on, were removed in AGP 9.
  val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)

  androidComponents {
      // flutter's plugin sets ndk abiFilters, which AGP refuses to combine with
      // splits.abi even when the two lists match. Clear it once the DSL is final.
      finalizeDsl { ext ->
          ext.defaultConfig.ndk.abiFilters.clear()
      }

      onVariants { variant ->
          variant.outputs.forEach { output ->
              val abiCode = abiCodes[output.filters.find { it.filterType == ABI }?.identifier]
              if (abiCode != null) {
                  output.versionCode.set(flutter.versionCode * 10 + abiCode)
              }
          }
      }
  }

  dependencies {
      implementation("androidx.work:work-runtime-ktx:2.9.0")
      implementation("com.squareup.okhttp3:okhttp:4.12.0")
  }

  kotlin {
      compilerOptions {
          jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
      }
  }

  flutter {
      source = "../.."
  }