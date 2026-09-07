// Repositorios del banco de pruebas.
//
// Los binarios de voz de la Fase 0-bis se resuelven **exclusivamente** desde
// Maven Central. `exclusiveContent` no es una preferencia: hace que
// `com.alphacephei` y `net.java.dev.jna` no puedan venir de ningún otro sitio,
// de modo que un repositorio añadido por descuido —o un `google()` que algún día
// publique un artefacto con esas coordenadas— no pueda sustituirlos.
//
// No hay JitPack, ni repositorios de terceros, ni URLs sin versión. La versión
// es exacta y su contenido está fijado por SHA-256 en `app/build.gradle.kts`.
allprojects {
    repositories {
        exclusiveContent {
            forRepository { mavenCentral() }
            filter {
                includeGroup("com.alphacephei")
                includeGroup("net.java.dev.jna")
            }
        }
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
