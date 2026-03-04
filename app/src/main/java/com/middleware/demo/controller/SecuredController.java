package com.middleware.demo.controller;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.core.user.OAuth2User;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.Map;

@RestController
@RequestMapping("/secured")
public class SecuredController {

    @GetMapping("/profile")
    public Map<String, Object> profile(@AuthenticationPrincipal OAuth2User principal)
            throws UnknownHostException {
        return Map.of(
                "username", principal.getAttribute("preferred_username"),
                "email", principal.getAttribute("email"),
                "name", principal.getAttribute("name"),
                "host", InetAddress.getLocalHost().getHostName(),
                "message", "SSO 인증 성공! Keycloak OIDC로 로그인되었습니다."
        );
    }
}
