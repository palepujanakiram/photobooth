plugins {
    id("com.android.library")
}

version = run {
    val pubspecContent = file("../pubspec.yaml").readText()
    val pubspecVersionMatch = Regex("version:\\s+(.*)").find(pubspecContent)
    val pubspecVersion = pubspecVersionMatch?.groupValues?.get(1)
    pubspecVersion ?: "0.0.0-SNAPSHOT"
}

android {
    namespace = "org.uvccamera.flutter"
    compileSdk = 34

    defaultConfig {
        minSdk = 21
        // Consumer rules from the vendored org.uvccamera:lib rebuild.
        consumerProguardFiles("libs/uvccamera-lib-proguard.txt")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    // Maven 0.0.13 ships 4 KB-aligned .so files. Native libs live in src/main/jniLibs
    // and Java classes in libs/uvccamera-lib-classes.jar — rebuilt with NDK r28 for
    // Google Play 16 KB page-size support. Rebuild: ./scripts/rebuild_uvccamera_16kb.sh
    implementation(files("libs/uvccamera-lib-classes.jar"))
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
