package demo.controller;

import demo.model.ApiResponse;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;


@RestController
public class ProfileController {

    @GetMapping("/profile")
    public ApiResponse profile(@AuthenticationPrincipal OidcUser oidcUser) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("sub",        oidcUser.getSubject());
        data.put("name",       oidcUser.getFullName());
        data.put("email",      oidcUser.getEmail());
        data.put("issuer",     oidcUser.getIssuer());
        data.put("audience",   oidcUser.getAudience());
        data.put("issued_at",  oidcUser.getIssuedAt());
        data.put("expires_at", oidcUser.getExpiresAt());
        // All claims from the ID token (includes custom PingFederate attributes)
        data.put("all_claims", oidcUser.getClaims());

        return ApiResponse.ok("oidc-authorization-code", data);
    }

    @GetMapping("/")
    public Map<String, String> index() {
        return Map.of(
            "demo",    "PingFederate + Spring Boot 4.1",
            "flows",   "OIDC: /profile | API (Bearer): /api/secure | M2M: /api/m2m",
            "health",  "/actuator/health"
        );
    }
}
