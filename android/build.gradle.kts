allprojects {
    buildscript {
        repositories {
            google()
            mavenCentral()
            maven { url = uri("https://maven.aliyun.com/repository/central") }
        }
    }
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
}

// AGP 8 requires every library module to declare `namespace`. Some stale
// Flutter plugins (e.g. on_audio_query_android, whose latest 1.1.0 never got
// migrated) still rely on the old manifest `package` attribute, so their
// module fails to configure. When a module applies the library plugin but
// sets no namespace, fall back to its Gradle `group` — which for those
// plugins already equals the manifest package and the Kotlin code package.
// Reflection avoids depending on AGP types being on this script's classpath.
subprojects {
    plugins.withId("com.android.library") {
        val ext = extensions.findByName("android") ?: return@withId
        try {
            val current = ext.javaClass.getMethod("getNamespace").invoke(ext) as? String
            if (current.isNullOrBlank()) {
                val fallback = group?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                if (fallback != null) {
                    ext.javaClass
                        .getMethod("setNamespace", String::class.java)
                        .invoke(ext, fallback)
                }
            }
        } catch (_: Exception) {
            // Module without a usable group/namespace setter — leave as-is.
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
