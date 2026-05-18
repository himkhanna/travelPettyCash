plugins {
    java
    id("org.springframework.boot") version "3.4.2"
    id("io.spring.dependency-management") version "1.1.7"
}

group = "ae.gov.pdd"
version = "0.1.0-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

extra["testcontainersVersion"] = "1.20.4"
extra["springdocVersion"] = "2.7.0"

dependencies {
    // --- Web + persistence + security ---
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-actuator")

    // --- Database / migrations ---
    runtimeOnly("org.postgresql:postgresql")
    implementation("org.flywaydb:flyway-core")
    implementation("org.flywaydb:flyway-database-postgresql")

    // --- JWT (jjwt API + impl + Jackson bindings) ---
    implementation("io.jsonwebtoken:jjwt-api:0.12.6")
    runtimeOnly("io.jsonwebtoken:jjwt-impl:0.12.6")
    runtimeOnly("io.jsonwebtoken:jjwt-jackson:0.12.6")

    // --- OpenAPI ---
    implementation("org.springdoc:springdoc-openapi-starter-webmvc-ui:${property("springdocVersion")}")

    // --- Object storage (MinIO / S3) ---
    implementation("io.minio:minio:8.5.17")

    // --- Report generation: Excel via Apache POI, PDF via OpenPDF (LGPL —
    // license-compatible per CLAUDE.md §3 vs iText 7 Community's GPL).
    implementation("org.apache.poi:poi-ooxml:5.3.0")
    implementation("com.github.librepdf:openpdf:2.0.3")

    // --- Tests ---
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.security:spring-security-test")
    testImplementation("org.testcontainers:junit-jupiter")
    testImplementation("org.testcontainers:postgresql")
    testImplementation("org.testcontainers:minio")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

dependencyManagement {
    imports {
        mavenBom("org.testcontainers:testcontainers-bom:${property("testcontainersVersion")}")
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.addAll(listOf("-Xlint:all", "-parameters"))
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    testLogging {
        events("passed", "skipped", "failed")
        showStandardStreams = false
    }
}

// ----------------------------------------------------------------------
// Developer convenience: `gradle restart` (alias: `gradle dev`)
//
// Kills whatever JVM is currently listening on :8080, then runs `bootRun`
// in the foreground so logs stream to the same terminal. Avoids the
// "but the running process still has the old classes loaded" trap after
// adding or editing controllers/services.
//
// Use `gradle restart --args='--spring.profiles.active=local'` to forward
// arguments, same as bootRun.
// ----------------------------------------------------------------------
val isWindows = System.getProperty("os.name").lowercase().contains("windows")

tasks.register<Exec>("stopRunning") {
    group = "application"
    description = "Stop any backend process currently listening on :8080."
    if (isWindows) {
        // netstat lists the port twice (IPv4 + IPv6 bindings), so dedupe
        // PIDs through a Set before invoking taskkill. PowerShell handles
        // the set semantics in one line and exits 0 even on no-match,
        // which keeps the build clean when port 8080 is already free.
        commandLine(
            "powershell", "-NoProfile", "-Command",
            "\$pids = @(netstat -ano | Select-String ':8080.*LISTENING' | " +
                "ForEach-Object { (\$_ -split '\\s+')[-1] } | Select-Object -Unique); " +
                "if (\$pids.Count -eq 0) { 'Nothing on :8080 — already stopped.'; exit 0 } " +
                "else { foreach (\$p in \$pids) { taskkill /F /PID \$p | Out-Null }; " +
                "'Stopped PID(s): ' + (\$pids -join ', ') }"
        )
    } else {
        commandLine("bash", "-c", "lsof -ti:8080 | xargs -r kill -9 || true; echo OK")
    }
    // Don't fail the build if nothing was listening — that's the happy path.
    isIgnoreExitValue = true
}

// Make sure stop runs before bootRun whenever both are in the task graph,
// and default to the `local` Spring profile so neither `gradle bootRun` nor
// `gradle restart` need the awkward --args='--spring.profiles.active=local'
// dance. The wrapper `restart` task can't forward --args anyway (only the
// originating BootRun task accepts it), so baking the default here is the
// less-confusing path.
tasks.named<org.springframework.boot.gradle.tasks.run.BootRun>("bootRun") {
    mustRunAfter("stopRunning")
    systemProperty("spring.profiles.active", "local")
}

tasks.register("restart") {
    group = "application"
    description = "Stop the running backend on :8080 and start a fresh bootRun."
    dependsOn("stopRunning", "bootRun")
}

// Friendly alias — what most people will reach for.
tasks.register("dev") {
    group = "application"
    description = "Alias for `restart`."
    dependsOn("restart")
}
