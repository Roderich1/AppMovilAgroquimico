// Repositorios del banco de pruebas.
//
// La configuración `exclusiveContent` obliga a Gradle a resolver el namespace
// configurado exclusivamente desde Maven Central dentro del flujo de build
// versionado. Así, un repositorio añadido por descuido —o un `google()` que
// algún día publique un artefacto con esas coordenadas— no puede sustituir a
// `com.alphacephei` ni a `net.java.dev.jna` en esta build.
//
// No sustituye a la verificación por SHA-256: eso lo hace
// `verifyPinnedVoiceArtifacts` en `app/build.gradle.kts`.
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
