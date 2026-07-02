package demo.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    @Order(1)
    SecurityFilterChain apiFilterChain(HttpSecurity http) throws Exception {
        return http
            .securityMatcher("/api/**")
            .authorizeHttpRequests(auth -> auth
                // /api/m2m is intentionally public — the app fetches its own token internally
                .requestMatchers("/api/m2m").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(rs -> rs.opaqueToken(Customizer.withDefaults()))
            .build();
    }

    @Bean
    @Order(2)
    SecurityFilterChain webFilterChain(HttpSecurity http) throws Exception {
        return http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/", "/actuator/health", "/actuator/info").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2Login(login -> login
                .defaultSuccessUrl("/profile", true)
            )
            .build();
    }
}
