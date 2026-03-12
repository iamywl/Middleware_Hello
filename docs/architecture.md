# 시스템 아키텍처 문서

## 1. 전체 구성도

```
                         ┌──────────────────┐
                         │  Client Browser   │
                         └────────┬─────────┘
                                  │ HTTPS (TLS 1.2/1.3)
                                  │ Port 443
                         ┌────────▼─────────┐
                    ┌────│      Nginx        │────┐
                    │    │  (Reverse Proxy)   │    │
                    │    │  - SSL Termination │    │
                    │    │  - Load Balancing  │    │
                    │    │  - Static Cache    │    │
                    │    └──────────────────┘    │
                    │ Round Robin                  │
           ┌────────▼─────────┐      ┌────────▼─────────┐
           │    Tomcat #1     │      │    Tomcat #2     │
           │  (WAS + Scouter) │      │  (WAS + Scouter) │
           │  Spring Boot App │      │  Spring Boot App │
           └────────┬─────────┘      └────────┬─────────┘
                    │                          │
           ┌────────▼──────────────────────────▼─────────┐
           │                  MySQL 8.0                   │
           │              (middleware_db)                  │
           └──────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │                    모니터링 / 보안 계층                       │
  │                                                             │
  │  ┌──────────┐  ┌───────────┐  ┌─────────┐  ┌───────────┐  │
  │  │ Scouter  │  │Prometheus │  │ Grafana │  │ Keycloak  │  │
  │  │ Server   │  │           │  │         │  │   (SSO)   │  │
  │  │ :6100    │  │  :9090    │  │  :3000  │  │   :8080   │  │
  │  └──────────┘  └───────────┘  └─────────┘  └───────────┘  │
  │                      ▲                                      │
  │           ┌──────────┴──────────┐                          │
  │     ┌─────┴──────┐  ┌──────────┴─┐                        │
  │     │   Node     │  │   Nginx    │                        │
  │     │  Exporter  │  │  Exporter  │                        │
  │     │   :9100    │  │   :9113    │                        │
  │     └────────────┘  └────────────┘                        │
  └─────────────────────────────────────────────────────────────┘
```

## 2. 네트워크 구조

모든 컨테이너는 `mw-network` (Docker bridge) 내에서 통신한다.

| 컨테이너 | 내부 포트 | 외부 포트 | 역할 |
|----------|----------|----------|------|
| mw-nginx | 80, 443 | 80, 443 | 리버스 프록시, SSL 종단, 로드밸런싱 |
| mw-tomcat1 | 8080 | - | WAS #1 (Spring Boot + Scouter Agent) |
| mw-tomcat2 | 8080 | - | WAS #2 (Spring Boot + Scouter Agent) |
| mw-mysql | 3306 | 3306 | 데이터베이스 |
| mw-keycloak | 8080 | 8080 | SSO 인증 서버 (OIDC) |
| mw-scouter | 6100, 6180 | 6100, 6180 | APM 서버 |
| mw-prometheus | 9090 | 9090 | 메트릭 수집 |
| mw-grafana | 3000 | 3000 | 대시보드 |
| mw-node-exporter | 9100 | 9100 | 서버 리소스 메트릭 |
| mw-nginx-exporter | 9113 | 9113 | Nginx 메트릭 |

## 3. 트래픽 흐름

### 일반 요청
```
Client → Nginx(:443) → [Round Robin] → Tomcat1 or Tomcat2(:8080) → MySQL(:3306)
```

### SSO 인증 요청 (OIDC Authorization Code Flow)
```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────────┐
│ 브라우저  │     │  Nginx   │     │  Tomcat  │     │   Keycloak   │
│(localhost)│     │  (:443)  │     │  (WAS)   │     │   (:8080)    │
└────┬─────┘     └────┬─────┘     └────┬─────┘     └──────┬───────┘
     │ 1. /secured/profile              │                   │
     │──────────────────►│──────────────►│                   │
     │                   │              │                   │
     │ 2. 302 Redirect to localhost:8080 (authorization-uri) │
     │◄──────────────────│◄──────────────│                   │
     │                   │              │                   │
     │ 3. 브라우저 → Keycloak 로그인 페이지 (localhost:8080)  │
     │──────────────────────────────────────────────────────►│
     │                   │              │                   │
     │ 4. 사용자 로그인 후 callback (authorization code)      │
     │◄──────────────────────────────────────────────────────│
     │                   │              │                   │
     │ 5. callback → Nginx → Tomcat     │                   │
     │──────────────────►│──────────────►│                   │
     │                   │              │ 6. code → token   │
     │                   │              │   (keycloak:8080)  │
     │                   │              │──────────────────►│
     │                   │              │◄──────────────────│
     │                   │              │                   │
     │ 7. 인증 완료, 프로필 JSON 응답    │                   │
     │◄──────────────────│◄──────────────│                   │
```

> **Split URI 패턴**: 브라우저가 직접 접근하는 `authorization-uri`는 `localhost:8080`,
> Tomcat이 서버 간 통신하는 `token-uri`/`jwk-set-uri`/`user-info-uri`는 Docker 내부 DNS `keycloak:8080`을 사용한다.

### 모니터링 데이터 흐름
```
Tomcat → Scouter Agent → Scouter Server(:6100)    [APM: TPS, 응답시간, JVM]
Tomcat → Actuator/Prometheus endpoint              [JVM 메트릭]
Node Exporter(:9100) ← Prometheus(:9090)           [CPU, Memory, Disk]
Nginx Exporter(:9113) ← Prometheus(:9090)          [Nginx 상태]
Prometheus → Grafana(:3000)                        [시각화]
```

## 4. SSL/PKI 구조

```
┌─────────────────────────────┐
│  Middleware Root CA          │
│  (자체 인증기관)              │
│  Validity: 10년              │
│  Key: RSA 4096-bit          │
└──────────┬──────────────────┘
           │ 서명
┌──────────▼──────────────────┐
│  Server Certificate         │
│  CN=localhost               │
│  SAN: localhost, nginx,     │
│       *.middleware.local    │
│  Validity: 1년              │
│  Key: RSA 2048-bit          │
└─────────────────────────────┘
```

## 5. 로드밸런싱 정책

| 방식 | 설정 | 특징 |
|------|------|------|
| Round Robin (기본) | weight=1 | 요청을 균등 분산 |
| IP Hash | `ip_hash;` | 같은 클라이언트 IP는 같은 서버로 |
| Least Connections | `least_conn;` | 연결 수가 적은 서버로 |

현재 설정: **Round Robin (weight=1:1)**

페일오버: 한 WAS가 다운되면 Nginx가 자동으로 나머지 WAS로 트래픽 전환.

## 6. 컨테이너 의존성

```
mysql (healthcheck) ──┬──→ tomcat1 ──┬──→ nginx ──→ nginx-exporter
                      └──→ tomcat2 ──┘
scouter-server (독립)
prometheus (독립) ──→ grafana
node-exporter (독립)
keycloak (독립)
```
