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
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
    tasks.configureEach {
        if (name.startsWith("javaPreCompile")) {
            doNotTrackState(
                "Work around Gradle 8 state tracking issue when annotation processor metadata file is missing."
            )
        }
    }
    if (project.name != "app") {
        evaluationDependsOn(":app")
    }
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
