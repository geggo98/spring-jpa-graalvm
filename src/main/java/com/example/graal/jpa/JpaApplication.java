package com.example.graal.jpa;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.data.web.SpringDataWebAutoConfiguration;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.lang.NonNull;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import java.util.Collection;
import java.util.stream.Stream;


/**
 * This is a simple Spring Boot application that uses Spring Data JPA to store and retrieve data from an in-memory H2 database.
 * <p>
 *     The application is a RESTful service that exposes a single endpoint to retrieve a list of customers.
 *     The application uses Spring Data JPA to store and retrieve data from an in-memory H2 database.
 *     During startup, the application populates the database with a few records.
 * </p><p>
 *     This application runs on the  Java Hotspot VM and GraalVM.
 * </p>
 * <p>
 *     This code is based on the Spring Blog post: <a href="https://spring.io/blog/2020/06/16/spring-tips-spring-and-graalvm-pt-2">Spring Tips: Spring and GraalVM</a>
*  </p>
 */
@SpringBootApplication(
        exclude = SpringDataWebAutoConfiguration.class,
        proxyBeanMethods = false
)
public class JpaApplication {

    public static void main(String[] args) {
        SpringApplication.run(JpaApplication.class, args);
    }

}


@RestController
@RequiredArgsConstructor
class CustomerRestController {

    private final CustomerRepository customerRepository;

    @GetMapping("/customers")
    Collection<Customer> customers() {
        return this.customerRepository.findAll();
    }
}

@Component
@RequiredArgsConstructor
class Initializer implements ApplicationListener<ApplicationReadyEvent> {

    private final CustomerRepository customerRepository;

    @Override
    public void onApplicationEvent(@NonNull ApplicationReadyEvent applicationReadyEvent) {
        Stream.of("Marie Curie", "Albert Einstein", "Rosalind Franklin", "Neil deGrasse Tyson", "Jane Goodall", "Stephen Hawking", "Katherine Johnson", "Chien-Shiung Wu", "Carl Sagan", "Tu Youyou")
                .map(name -> new Customer(null, name))
                .map(this.customerRepository::save)
                .forEach(System.out::println);
    }
}

interface CustomerRepository extends JpaRepository<Customer, Integer> {

}

@Entity
@Data
@AllArgsConstructor
@NoArgsConstructor
class Customer {

    @Id
    @GeneratedValue
    private Integer id;
    private String name;

}
