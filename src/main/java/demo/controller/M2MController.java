package demo.controller;

import demo.model.ApiResponse;
import demo.service.DownstreamService;
import lombok.RequiredArgsConstructor;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class M2MController {

    private final OAuth2AuthorizedClientManager clientManager;
    private final DownstreamService downstreamService;

    @GetMapping("/m2m")
    public ApiResponse m2m() {

        var request = OAuth2AuthorizeRequest
            .withClientRegistrationId("pingfed-m2m")
            .principal("system")
            .build();

        var authorizedClient = clientManager.authorize(request);
        if (authorizedClient == null) {
            throw new IllegalStateException(
                "Could not obtain client_credentials token from PingFederate");
        }

        var token    = authorizedClient.getAccessToken();
        var preview  = token.getTokenValue().substring(0, Math.min(20, token.getTokenValue().length())) + "...";
        var callResult = downstreamService.callWithToken(token.getTokenValue());

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("token_preview",   preview);
        data.put("token_type",      "Bearer");
        data.put("scope",           authorizedClient.getClientRegistration().getScopes());
        data.put("issued_at",       token.getIssuedAt());
        data.put("expires_at",      token.getExpiresAt());
        data.put("downstream_call", callResult);

        return ApiResponse.ok("client-credentials", data);
    }

    @ExceptionHandler(IllegalStateException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    ApiResponse handleTokenError(IllegalStateException ex) {
        return ApiResponse.ok("client-credentials", Map.of("error", ex.getMessage()));
    }
}
