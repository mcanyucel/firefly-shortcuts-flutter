  import java.util.Properties
  import java.io.FileInputStream

  plugins {
      id("com.android.application")
      id("dev.flutter.flutter-gradle-plugin")
  }

  val keystoreProperties = Properties()
  val keystorePropertiesFile = rootProject.file("key.properties")
  if (keystorePropertiesFile.exists()) {
      keystoreProperties.load(FileInputStream(keystorePropertiesFile))
  }

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