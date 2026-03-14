# 테스트 보고서

## Linux 기반 WEB/WAS 미들웨어 환경 구축 및 APM 모니터링 시스템

> 테스트 일시: 2026-03-04
> 테스트 환경: macOS (Docker Desktop), 10개 컨테이너

---

## 테스트 결과 요약

| Phase | 테스트 항목 | 결과 |
|-------|------------|------|
| Phase 1 | 기본 인프라 (7개 항목) | **PASS** |
| Phase 2 | APM 모니터링 (8개 항목) | **PASS** |
| Phase 3 | 보안 연동 (8개 항목) | **PASS** |
| Phase 4 | 운영 자동화 (3개 항목) | **PASS** |

**전체: 26개 테스트 항목 중 26개 PASS**

---

## Phase 1: 기본 인프라 구축

### 1-1. 컨테이너 상태 (10개)

| 컨테이너 | 이미지 | 상태 |
|----------|--------|------|
| mw-nginx | nginx:1.24 | UP |
| mw-tomcat1 | middle_ware-tomcat1 | UP |
| mw-tomcat2 | middle_ware-tomcat2 | UP |
| mw-mysql | mysql:8.0 | UP (healthy) |
| mw-keycloak | keycloak:24.0 | UP |
| mw-scouter | scouter-server | UP |
| mw-prometheus | prom/prometheus | UP |
| mw-grafana | grafana/grafana | UP |
| mw-node-exporter | prom/node-exporter | UP |
| mw-nginx-exporter | nginx-prometheus-exporter | UP |

### 1-2. Web App 응답

```
# HTTPS 요청
$ curl -sfk https://localhost/
{"port":"8080","time":"2026-03-04T05:10:56","app":"middleware-demo","status":"running","host":"c2afa58583fd"}

# Health 엔드포인트
$ curl -sfk https://localhost/health
{"host":"c2afa58583fd","status":"UP"}

# Info 엔드포인트
$ curl -sfk https://localhost/info
{"hostname":"c2afa58583fd","javaVersion":"17.0.18","maxMemory":"512MB","freeMemory":"152MB","availableProcessors":16}
```

**결과: PASS** - Spring Boot 앱이 Tomcat에서 정상 동작

### 1-3. 로드밸런싱

```
#1  X-Upstream: 172.18.0.9:8080  (Tomcat2)
#2  X-Upstream: 172.18.0.9:8080  (Tomcat2)
#3  X-Upstream: 172.18.0.9:8080  (Tomcat2)
#4  X-Upstream: 172.18.0.8:8080  (Tomcat1)
#5  X-Upstream: 172.18.0.9:8080  (Tomcat2)
#6  X-Upstream: 172.18.0.8:8080  (Tomcat1)
#7  X-Upstream: 172.18.0.9:8080  (Tomcat2)
#8  X-Upstream: 172.18.0.8:8080  (Tomcat1)
#9  X-Upstream: 172.18.0.9:8080  (Tomcat2)
#10 X-Upstream: 172.18.0.8:8080  (Tomcat1)
```

**결과: PASS** - Round Robin으로 두 WAS에 트래픽 분산 확인

### 1-4. MySQL 연결

```
$ docker exec mw-mysql mysql -u app_user -papp_password -e "SELECT 'MySQL OK' AS status;"
+----------+
| status   |
+----------+
| MySQL OK |
+----------+
```

**결과: PASS**

### 1-5. Nginx 설정 검증

```
$ docker exec mw-nginx nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**결과: PASS**

---

## Phase 2: APM 모니터링 체계

### 2-1. Scouter Server

```
jetty-9.4.6.v20170531 Started ServerConnector@37031b3e{HTTP/1.1,[http/1.1]}{0.0.0.0:6180}
```

**결과: PASS** - Scouter Server 정상 기동 (TCP :6100, HTTP :6180)

### 2-2. Scouter Agent 연결

```
# Tomcat1
[SCOUTER] Version 2.20.0
[SCOUTER] objType:tomcat
[SCOUTER] objName:/c2afa58583fd/tomcat1

# Tomcat2
[SCOUTER] Version 2.20.0
[SCOUTER] objType:tomcat
[SCOUTER] objName:/28cb2522d935/tomcat2
```

**결과: PASS** - 양쪽 Tomcat에 Scouter Agent 정상 로드

### 2-3. Prometheus 타겟

| Job | Health |
|-----|--------|
| prometheus | UP |
| node-exporter | UP |
| nginx | UP |
| tomcat1 | UP |
| tomcat2 | UP |

**결과: PASS** - 5개 타겟 전부 UP

### 2-4. JVM Heap 메트릭 (Prometheus 쿼리)

```
G1 Survivor Space: 17 MB
G1 Eden Space: 65 MB
G1 Old Gen: 27 MB
```

**결과: PASS** - Tomcat JVM 메트릭 수집 정상

### 2-5. Grafana

```
Health: {"database":"ok","version":"12.4.0"}
Dashboard: Middleware Overview (uid=middleware-overview)
Datasource: Prometheus (url=http://prometheus:9090)
```

**결과: PASS** - 대시보드 및 데이터소스 자동 프로비저닝 확인

### 2-6. Exporter

```
# Node Exporter (:9100) - CPU/Memory/Disk 메트릭 수출
node_cpu_seconds_total → OK

# Nginx Exporter (:9113) - Nginx 상태 메트릭 수출
nginx_connections_active → OK
```

**결과: PASS**

---

## Phase 3: 보안 연동

### 3-1. HTTP → HTTPS 리다이렉트

```
HTTP 301 → https://localhost/
```

**결과: PASS**

### 3-2. SSL 인증서

```
subject=C=KR, ST=Seoul, L=Seoul, O=Middleware Lab, OU=DevOps, CN=localhost
issuer=C=KR, ST=Seoul, L=Seoul, O=Middleware Lab, OU=DevOps, CN=Middleware Root CA
notBefore=Mar  4 04:59:03 2026 GMT
notAfter=Mar  4 04:59:03 2027 GMT
X509v3 Subject Alternative Name:
    DNS:localhost, DNS:nginx, DNS:*.middleware.local, IP Address:127.0.0.1
```

**결과: PASS** - 자체 CA 발급 인증서, SAN 포함, 1년 유효

### 3-3. HSTS 헤더

```
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

**결과: PASS**

### 3-4. Keycloak SSO

```
# Realm 상태
Keycloak middleware realm: HTTP 200

# OIDC Discovery (호스트에서 조회 시)
issuer: http://localhost:8080/realms/middleware
authorization: http://localhost:8080/realms/middleware/protocol/openid-connect/auth
token: http://localhost:8080/realms/middleware/protocol/openid-connect/token
userinfo: http://localhost:8080/realms/middleware/protocol/openid-connect/userinfo
```

**결과: PASS** - middleware Realm 정상, OIDC 엔드포인트 동작

> **참고: Split URI 구성**
>
> 실제 `application.properties`에서는 **authorization-uri만 `localhost:8080`**, 나머지 URI(`token-uri`, `jwk-set-uri`, `user-info-uri`)는 **Docker 내부 DNS `keycloak:8080`**을 사용한다. 이는 브라우저(authorization)와 서버 간 통신(token/jwk/userinfo)의 네트워크 경로가 다르기 때문이다.

### 3-5. SSO 토큰 발급 (Resource Owner Password Grant)

```
$ curl -X POST .../token -d "grant_type=password&username=testuser&password=test123..."

access_token: eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6IC...
token_type: Bearer
expires_in: 300s
```

**결과: PASS** - testuser 계정으로 JWT 토큰 발급 성공

### 3-6. 보호된 엔드포인트

```
# 미인증 상태로 /secured/profile 접근
HTTP 302 → Keycloak 로그인 페이지로 리다이렉트
```

**결과: PASS** - Spring Security + OAuth2 인증 흐름 정상

---

## Phase 4: 운영 자동화 및 장애 대응

### 4-1. 페일오버 테스트

```
Before: {"host":"c2afa58583fd","status":"UP"}  ← Tomcat1 응답
[Tomcat1 중지]
After:  {"status":"UP","host":"28cb2522d935"}  ← Tomcat2로 자동 전환
[Tomcat1 복구]
```

**결과: PASS** - WAS 1대 다운 시 Nginx가 자동으로 나머지 WAS로 페일오버

### 4-2. 백업 스크립트

```
[1/4] Dumping MySQL database... 4.0K
[2/4] Backing up configuration files... Configs archived
[3/4] Backing up logs... Logs archived
[4/4] Cleaning old backups... 0 deleted
Total size: 92K
```

**결과: PASS** - MySQL 덤프 + 설정 + 로그 백업 정상

### 4-3. 운영 스크립트 목록

| 스크립트 | 기능 | 상태 |
|----------|------|------|
| start.sh | 전체 환경 시작 | 실행 가능 |
| stop.sh | 전체 환경 종료 | 실행 가능 |
| status.sh | 상태 확인 + LB 테스트 | 실행 가능 |
| health-check.sh | 일일 점검 (6개 항목) | 실행 검증 완료 |
| log-analyzer.sh | Nginx/Tomcat 로그 분석 | 실행 가능 |
| backup.sh | MySQL + 설정 + 로그 백업 | 실행 검증 완료 |
| generate-certs.sh | 자체 CA + 서버 인증서 발급 | 실행 검증 완료 |
| cert-renew.sh | 인증서 갱신 자동화 | 실행 가능 |

---

## 접속 정보

| 서비스 | URL | 계정 |
|--------|-----|------|
| Web App | https://localhost | - |
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | - |
| Keycloak Admin | http://localhost:8080 | admin / admin |
| SSO 테스트 사용자 | (Keycloak) | testuser / test123 |
| MySQL | localhost:3306 | app_user / app_password |
| Scouter | localhost:6100 (TCP), :6180 (HTTP) | - |

---

## 리소스 사용량

| 컨테이너 | CPU | Memory |
|----------|-----|--------|
| mw-nginx | 0.00% | 13 MB |
| mw-tomcat1 | 0.61% | 490 MB |
| mw-tomcat2 | 2.72% | 548 MB |
| mw-mysql | 0.39% | 361 MB |
| mw-keycloak | 0.42% | 1.6 GB |
| mw-scouter | 0.50% | 291 MB |
| mw-prometheus | 0.12% | 45 MB |
| mw-grafana | 0.35% | 115 MB |
| mw-node-exporter | 0.00% | 14 MB |
| mw-nginx-exporter | 0.00% | 10 MB |
| **합계** | **~5%** | **~3.5 GB** |

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [사용자 가이드](user-guide.md) | 테스트 환경 설정 |
| [아키텍처 설계](architecture.md) | 테스트 대상 아키텍처 |
| [성능 튜닝 가이드](performance-tuning.md) | 성능 테스트 기준 |
| [트러블슈팅 가이드](troubleshooting.md) | 테스트 중 문제 해결 |
