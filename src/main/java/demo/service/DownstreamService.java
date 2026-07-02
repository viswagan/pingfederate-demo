package demo.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.Map;

/**
 * Simulates a downstream API call made with a client_credentials Bearer token.
 *
 * This is similar to another microservice, a data API,
 * or any resource that validates Bearer tokens against PingFederate.
 *
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class DownstreamService {

    @Value("${app.downstream-url}")
    private final String downstreamUrl;
    private final RestClient restClient;

    /**
     * Calls the downstream service with the provided Bearer token.
     * Returns a mocked response if the real service is unavailable.
     */
    public Map<String, Object> callWithToken(String bearerToken) {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> response = restClient.get()
                .uri(downstreamUrl + "/api/data")
                .header("Authorization", "Bearer " + bearerToken)
                .retrieve()
                .body(Map.class);

            log.info("Downstream call succeeded");
            return response != null ? response : mockedResponse("success");

        } catch (RestClientException e) {
            log.warn("Downstream service unreachable ({}), returning mock response", e.getMessage());
            return mockedResponse("mocked — downstream unavailable");
        }
    }

    private Map<String, Object> mockedResponse(String note) {
        return Map.of(
            "source",  downstreamUrl + "/api/data",
            "result",  "Demo data payload",
            "records", 42,
            "note",    note
        );
    }
}
