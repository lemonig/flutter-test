plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.greandata.green_clean_ops"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.greandata.green_clean_ops"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 个推 SDK 的清单里用 ${GETUI_APPID} 占位，构建期由这里替换。
        // 客户端只需要 AppID；AppKey / AppSecret / MasterSecret 仅服务端推消息时使用
        // （见 ops-mobile/application.properties 的 gpush.*）。
        manifestPlaceholders["GETUI_APPID"] = "xD7UWWJDKl8jmq6AiuNnC2"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 个推 SDK：官方 Flutter 插件 getuiflut 的 Android 工程仍是 AGP 4.2 写法
    // （compileSdkVersion / jcenter / lintOptions），与本项目的 AGP 9 + Gradle 9 不兼容，
    // 所以这里直接依赖 AAR，由 PushBridge 通过 MethodChannel 暴露最小能力。
    implementation("com.getui:gtsdk:3.3.12.0")
    implementation("com.getui:gtc:3.2.18.0")

    // 高德地图 SDK：官方 amap_flutter_map 3.0.0 同样是 AGP 3.5 写法（compileSdkVersion 29），
    // 不能用；地图渲染改由 AmapPlatformView 直接承载原生 MapView。
    // 与原 Android 工程保持同一版本（yunwei-android 用的就是 3dmap:9.5.0）。
    implementation("com.amap.api:3dmap:9.5.0")
}

flutter {
    source = "../.."
}
