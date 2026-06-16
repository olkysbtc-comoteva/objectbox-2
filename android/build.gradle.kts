// flutterapp/android/build.gradle.kts

plugins {
    // 🔥 SOLUCIÓN DEFINITIVA: Le quitamos las versiones manuales a Android. 
    // Flutter se encargará de inyectar las suyas en el classpath de forma nativa.
    id("com.android.application") apply false
    id("com.android.library") apply false
    id("org.jetbrains.kotlin.android") apply false

    // Este sí mantiene su versión porque es un añadido externo para Firebase
    id("com.google.gms.google-services") version "4.4.4" apply false 
}

allprojects {
    repositories {
        google()
        mavenCentral()
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
