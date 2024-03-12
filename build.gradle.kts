plugins {
	java
	id("org.springframework.boot") version "3.2.3"
	id("io.spring.dependency-management") version "1.1.4"
	id("org.hibernate.orm") version "6.4.2.Final"
	id("org.graalvm.buildtools.native") version "0.9.28"
}

group = "com.example.graal"
version = "0.0.1-SNAPSHOT"

configurations {
	compileOnly {
		// Enable annotation processor compiler plugins (like Lombok)
		extendsFrom(configurations.annotationProcessor.get())
	}
}

repositories {
	// Download dependencies from Maven Central
	mavenCentral()
}

dependencies {
	// Spring modules
	implementation("org.springframework.boot:spring-boot-starter-actuator")
	implementation("org.springframework.boot:spring-boot-starter-data-jpa")
	implementation("org.springframework.boot:spring-boot-starter-web")
	// Micrometer metrics: Prometheus, OpenTelemetry (Jaeger), and OpenZipkin Brave (Amazon X-Ray),
	// Note: The OpenTelemetry and OpenZipkin Brave bridges are optional.
	//       You can choose one of them based on your tracing system or disable both..
	//       You cannot use both at the same time.
	implementation("io.micrometer:micrometer-tracing-bridge-brave")
//	implementation("io.micrometer:micrometer-tracing-bridge-otel")
	implementation("io.micrometer:micrometer-registry-prometheus")

	// Compiler plugins and annotation processors
	compileOnly("org.projectlombok:lombok")
	annotationProcessor("org.projectlombok:lombok")

	// Database drivers.
	// They are needed at runtime, but not available at compile time,
	// so that no code accidentally depends directly on the driver.
	runtimeOnly("com.h2database:h2")
	runtimeOnly("org.xerial:sqlite-jdbc")

	// Test dependencies
	testImplementation("org.springframework.boot:spring-boot-starter-test")
}

java {
	// Set the source and target compatibility to Java 21
	sourceCompatibility = JavaVersion.VERSION_21
	// Request GraalVM as the target platform for creating the native image
	toolchain {
		languageVersion = JavaLanguageVersion.of(21)
		vendor = JvmVendorSpec.GRAAL_VM
	}
}

graalvmNative {
	binaries {
		named("main") {
			// Enable Java Flight Recorder (JFR) built-in profiler for the native image
			// - "AllowVMInspection" is required to enable JFR on older GraalVM versions.
			// - "enable-monitoring" is required to enable JFR on GraalVM 21.3.0 and later.
			buildArgs(listOf("-H:+AllowVMInspection", "--enable-monitoring"))
		}
	}
}

tasks.withType<Test> {
	// Use JUnit 5 as the test runner.
	// This is the default in Spring Boot 3.2.
	// And it's also supported by GraalVM to run native tests.
	useJUnitPlatform()
}

hibernate {
	enhancement {
		enableAssociationManagement.set(true)
	}
}

