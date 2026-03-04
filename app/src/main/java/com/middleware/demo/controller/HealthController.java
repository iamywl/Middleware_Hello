package com.middleware.demo.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.LocalDateTime;
import java.util.Map;

@RestController
public class HealthController {

    @Value("${server.port:8080}")
    private String serverPort;

    @GetMapping("/")
    public Map<String, String> index() throws UnknownHostException {
        return Map.of(
                "app", "middleware-demo",
                "host", InetAddress.getLocalHost().getHostName(),
                "port", serverPort,
                "time", LocalDateTime.now().toString(),
                "status", "running"
        );
    }

    @GetMapping("/health")
    public Map<String, String> health() throws UnknownHostException {
        return Map.of(
                "status", "UP",
                "host", InetAddress.getLocalHost().getHostName()
        );
    }

    @GetMapping("/info")
    public Map<String, Object> info() throws UnknownHostException {
        return Map.of(
                "hostname", InetAddress.getLocalHost().getHostName(),
                "javaVersion", System.getProperty("java.version"),
                "maxMemory", Runtime.getRuntime().maxMemory() / 1024 / 1024 + "MB",
                "freeMemory", Runtime.getRuntime().freeMemory() / 1024 / 1024 + "MB",
                "availableProcessors", Runtime.getRuntime().availableProcessors()
        );
    }
}
