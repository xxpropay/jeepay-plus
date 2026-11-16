package com.jeequan.jeepay.core.jwt;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class JWTUtilsTest {

    private static final String STRONG_SECRET =
            "jeepay-test-secret-with-at-least-32-bytes";

    @Test
    void rejectsSecretShorterThan32Bytes() {
        assertThrows(IllegalArgumentException.class,
                () -> JWTUtils.generateToken(new JWTPayload(), "short"));
    }

    @Test
    void generatesAndParsesTokenWithStrongSecret() {
        JWTPayload payload = new JWTPayload();
        payload.setSysUserId(42L);
        payload.setCreated(123L);
        payload.setCacheKey("cache-key");

        String token = JWTUtils.generateToken(payload, STRONG_SECRET);
        JWTPayload parsed = JWTUtils.parseToken(token, STRONG_SECRET);

        assertNotNull(parsed);
        assertEquals(payload.getSysUserId(), parsed.getSysUserId());
        assertEquals(payload.getCreated(), parsed.getCreated());
        assertEquals(payload.getCacheKey(), parsed.getCacheKey());
    }
}
