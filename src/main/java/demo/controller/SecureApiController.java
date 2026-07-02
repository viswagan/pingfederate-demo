package demo.controller;

import demo.model.ApiResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.core.OAuth2AuthenticatedPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class SecureApiController {

    @GetMapping("/secure")
    public ApiResponse secure(Authentication auth) {
        var principal = (OAuth2AuthenticatedPrincipal) auth.getPrincipal();

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("sub",       principal.getAttribute("sub"));
        data.put("client_id", principal.getAttribute("client_id"));
        data.put("scope",     principal.getAttribute("scope"));
        data.put("active",    principal.getAttribute("active"));
        data.put("exp",       principal.getAttribute("exp"));
        data.put("all_attributes", principal.getAttributes());

        return ApiResponse.ok("opaque-token-introspection", data);
    }

    @GetMapping("/echo")
    public ApiResponse echo(Authentication auth) {
        return ApiResponse.ok("opaque-token-introspection",
            Map.of("authenticated_as", auth.getName(),
                   "authorities",      auth.getAuthorities().toString()));
    }
}
