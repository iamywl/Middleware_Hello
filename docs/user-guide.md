# 사용자 가이드 - 처음부터 따라하기

> 이 프로젝트를 처음 접하는 사람도 각 서비스가 **제대로 동작하는지 직접 확인**할 수 있도록 작성한 가이드이다.

---

## 목차

1. [사전 준비](#1-사전-준비)
2. [전체 환경 구동](#2-전체-환경-구동)
3. [Nginx - 로드밸런싱 확인하기](#3-nginx---로드밸런싱-확인하기)
4. [Spring Boot - API 동작 확인하기](#4-spring-boot---api-동작-확인하기)
5. [Prometheus - 메트릭 수집 확인하기](#5-prometheus---메트릭-수집-확인하기)
6. [Grafana - 대시보드 확인하기](#6-grafana---대시보드-확인하기)
7. [Keycloak - SSO 로그인 확인하기](#7-keycloak---sso-로그인-확인하기)
8. [Scouter - APM 모니터링 확인하기](#8-scouter---apm-모니터링-확인하기)
9. [SSL/HTTPS - 인증서 확인하기](#9-sslhttps---인증서-확인하기)
10. [장애 시뮬레이션 - 고가용성 확인하기](#10-장애-시뮬레이션---고가용성-확인하기)
11. [환경 종료](#11-환경-종료)

---

## 1. 사전 준비

### 1.1 최소 시스템 사양

본 프로젝트는 10개의 컨테이너를 동시에 실행하므로 아래 사양이 필요하다.

| 항목 | 최소 사양 | 권장 사양 |
|------|-----------|-----------|
| **RAM** | 8GB | 16GB |
| **디스크 여유 공간** | 10GB | 20GB |
| **CPU** | 2코어 | 4코어 이상 |

> **Mac/Windows 사용자 주의**: Docker Desktop은 기본 메모리 할당이 **2GB**로 설정되어 있다.
> 반드시 **Settings → Resources → Memory**를 **6GB 이상**으로 올려야 한다. 그렇지 않으면 컨테이너가 기동 중 OOM으로 종료된다.

### 1.2 필수 도구 설치 확인

```bash
# Git 설치 확인
git --version             # git version 2.x 이상

# Docker 설치 확인
docker --version          # Docker version 20.x 이상

# Docker Compose 설치 확인
docker-compose --version  # Docker Compose version 2.x 이상
```

설치가 안 되어 있다면:
- **Mac**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) 설치 (Git은 Xcode Command Line Tools에 포함)
- **Linux**: `sudo apt install git docker.io docker-compose` (Ubuntu 기준)

### 1.3 포트 충돌 확인

아래 포트를 이미 사용 중인 프로그램이 있으면 컨테이너가 기동에 실패한다. 미리 확인하자.

```bash
# Mac/Linux — 사용 중인 포트 확인
lsof -i :80 -i :443 -i :3000 -i :3306 -i :8080 -i :9090

# 아무 출력도 없으면 정상 (포트가 비어 있음)
# 출력이 있으면 해당 프로세스를 종료하거나, 포트를 변경해야 한다
```

| 포트 | 사용 서비스 | 자주 충돌하는 프로그램 |
|------|-------------|----------------------|
| 80, 443 | Nginx | Apache httpd, 다른 웹서버 |
| 3000 | Grafana | 다른 Node.js 앱 |
| 3306 | MySQL | 로컬 MySQL 서버 |
| 8080 | Keycloak | 로컬 Tomcat, Jenkins |
| 9090 | Prometheus | - |

---

## 2. 전체 환경 구동

```bash
# 프로젝트 클론
git clone https://github.com/iamywl/Middleware_Hello.git
cd Middleware_Hello

# 전체 서비스 구동 (최초 실행 시 이미지 빌드로 3~5분 소요)
docker-compose up -d
```

구동이 완료되면 10개의 컨테이너가 실행된다.

```bash
# 상태 확인 - 모든 컨테이너가 "Up" 상태인지 확인
docker-compose ps
```

**확인 포인트**: 아래 컨테이너가 모두 `Up` 또는 `Up (healthy)` 상태여야 한다.

| 컨테이너 | 역할 |
|-----------|------|
| mw-nginx | WEB 서버 (로드밸런서) |
| mw-tomcat1 | WAS #1 |
| mw-tomcat2 | WAS #2 |
| mw-mysql | 데이터베이스 |
| mw-keycloak | SSO 인증 서버 |
| mw-scouter | APM 서버 |
| mw-prometheus | 메트릭 수집 |
| mw-grafana | 모니터링 대시보드 |
| mw-node-exporter | 서버 리소스 수집 |
| mw-nginx-exporter | Nginx 메트릭 수집 |

> 컨테이너가 뜨는 데 1~2분 걸릴 수 있다. 특히 MySQL이 `healthy` 상태가 되어야 Tomcat이 기동된다.

### 구동에 실패했을 때

컨테이너가 `Exited` 또는 `Restarting` 상태라면 아래 순서로 확인한다.

```bash
# ① 어떤 컨테이너가 문제인지 확인
docker-compose ps

# ② 문제 컨테이너의 로그 확인 (예: tomcat1이 Exited일 때)
docker-compose logs tomcat1

# ③ 빌드 실패 시 (Maven 다운로드 에러 등) — 재빌드
docker-compose down
docker-compose up --build -d

# ④ 포트 충돌 에러 ("bind: address already in use")
#    → 1.3절의 포트 충돌 확인 참조

# ⑤ 메모리 부족 (컨테이너가 계속 재시작)
#    → Docker Desktop의 메모리 할당을 6GB 이상으로 올린다
```

> `-k` 옵션 없이 `curl https://localhost/health`를 실행하면 `curl: (60) SSL certificate problem: unable to get local issuer certificate` 에러가 발생한다. 이것은 자체서명 인증서이기 때문이며 정상이다. `-k` 옵션은 인증서 검증을 건너뛰라는 뜻이다.

---

## 3. Nginx - 로드밸런싱 확인하기

**목적**: Nginx가 요청을 Tomcat #1, #2에 번갈아 보내는지 확인한다.

### 터미널에서 확인

```bash
# 같은 명령을 두 번 실행한다 (-k 옵션은 자체서명 인증서 허용)
curl -k https://localhost/health
curl -k https://localhost/health
```

**확인 포인트**: 응답의 `"host"` 값이 번갈아 바뀌면 로드밸런싱이 동작하는 것이다.

```json
// 첫 번째 요청 → Tomcat #1
{"status":"UP","host":"abc1234def"}

// 두 번째 요청 → Tomcat #2
{"status":"UP","host":"fed4321cba"}
```

> `host` 값은 컨테이너 ID이므로 두 값이 **서로 다르면** 정상이다.

### 브라우저에서 확인

1. 브라우저에서 `https://localhost` 접속
2. "연결이 비공개가 아닙니다" 경고가 나오면 → **고급** → **localhost(으)로 이동** 클릭 (자체서명 인증서이므로 정상)
3. JSON 응답이 보이면 성공
4. **새로고침(F5)**을 여러 번 누르면 `host` 값이 바뀌는 것을 확인

---

## 4. Spring Boot - API 동작 확인하기

**목적**: WAS 위에서 Spring Boot 애플리케이션이 정상 동작하는지 확인한다.

### 사용 가능한 API 목록

```bash
# ① 메인 페이지 - 앱 정보, 호스트명, 포트, 시간 확인
curl -k https://localhost/

# ② 헬스체크 - WAS 상태 확인
curl -k https://localhost/health

# ③ 시스템 정보 - JVM 버전, 메모리, CPU 코어 수
curl -k https://localhost/info
```

**확인 포인트**:

| API | 정상 응답 예시 |
|-----|---------------|
| `/` | `{"app":"middleware-demo","status":"running","host":"...","port":"8080","time":"..."}` |
| `/health` | `{"status":"UP","host":"..."}` |
| `/info` | `{"javaVersion":"17.x","maxMemory":"512MB","freeMemory":"...","availableProcessors":...}` |

---

## 5. Prometheus - 메트릭 수집 확인하기

**목적**: Prometheus가 각 서비스에서 메트릭을 정상적으로 수집하고 있는지 확인한다.

### Step 1: Prometheus 웹 UI 접속

브라우저에서 `http://localhost:9090` 접속

### Step 2: 수집 대상(Target) 상태 확인

1. 상단 메뉴에서 **Status** → **Targets** 클릭
2. 아래 5개 Target이 모두 **`UP`** (초록색) 상태인지 확인

| Target 이름 | 수집 대상 | 확인할 점 |
|-------------|-----------|-----------|
| `prometheus` | Prometheus 자체 | State가 `UP` |
| `node-exporter` | 서버 CPU/메모리/디스크 | State가 `UP` |
| `nginx` | Nginx 연결 수/요청 수 | State가 `UP` |
| `tomcat1` | WAS #1 JVM/HTTP 메트릭 | State가 `UP` |
| `tomcat2` | WAS #2 JVM/HTTP 메트릭 | State가 `UP` |

> 하나라도 `DOWN` (빨간색)이면 해당 서비스가 아직 기동 중이거나 문제가 있는 것이다.

### Step 3: 직접 쿼리 실행해보기

1. 메인 페이지의 **검색창(Expression)**에 아래 쿼리를 입력하고 **Execute** 클릭

```promql
# CPU 사용률 확인
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

2. **Graph** 탭을 클릭하면 시간에 따른 CPU 사용률 그래프가 표시된다

**다른 쿼리 예시**:

```promql
# 메모리 사용률 (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Nginx 초당 요청 수
rate(nginx_http_requests_total[5m])

# Tomcat1 JVM 힙 메모리 사용량
jvm_memory_used_bytes{job="tomcat1", area="heap"}
```

---

## 6. Grafana - 대시보드 확인하기

**목적**: Grafana에서 사전 구성된 대시보드로 시스템 상태를 시각적으로 모니터링한다.

### Step 1: Grafana 로그인

1. 브라우저에서 `http://localhost:3000` 접속
2. 로그인 정보 입력:
   - **Username**: `admin`
   - **Password**: `admin`
3. "Change password" 화면이 나오면 → **Skip** 클릭 (데모이므로 변경 불필요)

### Step 2: 대시보드 열기

1. 좌측 메뉴에서 **Dashboards** (네모 4개 아이콘) 클릭
2. **Middleware Overview** 대시보드 클릭

### Step 3: 대시보드 패널 확인

아래 8개 패널이 표시된다:

| 패널 이름 | 표시 내용 | 정상 확인 방법 |
|-----------|-----------|---------------|
| **CPU Usage (%)** | 서버 CPU 사용률 | 그래프 선이 보이면 정상 |
| **Memory Usage (%)** | 서버 메모리 사용률 | 그래프 선이 보이면 정상 |
| **Disk Usage (%)** | 디스크 사용률 (게이지) | 초록색/노란색 게이지가 보이면 정상 |
| **Network I/O** | 네트워크 송수신량 | RX/TX 그래프 선이 보이면 정상 |
| **Nginx Active Connections** | Nginx 활성 연결 수 | 숫자가 표시되면 정상 |
| **Nginx Requests/sec** | Nginx 초당 요청 수 | 그래프가 보이면 정상 |
| **JVM Heap Memory - Tomcat1** | Tomcat #1 힙 메모리 | Used/Max 선이 보이면 정상 |
| **JVM Heap Memory - Tomcat2** | Tomcat #2 힙 메모리 | Used/Max 선이 보이면 정상 |

> "No data" 가 표시되면 우측 상단의 시간 범위를 **Last 5 minutes** 로 변경해본다.

### Step 4: 실시간 변화 관찰하기

터미널에서 부하를 발생시키면 대시보드에서 실시간으로 변화를 볼 수 있다:

```bash
# 반복 요청으로 트래픽 발생 (100회)
for i in $(seq 1 100); do curl -sk https://localhost/health > /dev/null; done
```

실행 후 Grafana에서 **Nginx Requests/sec** 패널의 그래프가 올라가는 것을 확인한다.

---

## 7. Keycloak - SSO 로그인 확인하기

**목적**: Keycloak SSO 서버가 동작하고, 보호된 페이지에 접근 시 로그인이 요구되는지 확인한다.

### Step 1: Keycloak 관리 콘솔 접속

1. 브라우저에서 `http://localhost:8080` 접속
2. **Administration Console** 클릭
3. 로그인 정보 입력:
   - **Username**: `admin`
   - **Password**: `admin`

### Step 2: Realm 및 사용자 확인

1. 좌측 상단 드롭다운에서 **middleware** Realm 선택 (기본은 master)
2. 좌측 메뉴에서 **Users** 클릭
3. 아래 2명의 사용자가 등록되어 있는지 확인:

| 사용자 | 비밀번호 | 역할 | 이메일 |
|--------|----------|------|--------|
| `admin` | `admin123` | admin, user | admin@middleware.local |
| `testuser` | `test123` | user | test@middleware.local |

### Step 3: Client 설정 확인

1. 좌측 메뉴에서 **Clients** 클릭
2. **middleware-app** 클라이언트가 등록되어 있는지 확인
3. 클릭하면 아래 설정을 볼 수 있다:
   - Protocol: `openid-connect`
   - Redirect URIs: `https://localhost/*`

### Step 4: Split URI 패턴 이해하기

Docker Compose 환경에서 OIDC를 사용할 때, **브라우저용 URI**와 **서버 간 통신 URI**를 분리해야 한다.

`application.properties`의 핵심 설정:

```properties
# ✅ 브라우저가 접근 → localhost 사용 (사용자 PC에서 Keycloak 로그인 페이지로 이동)
spring.security.oauth2.client.provider.keycloak.authorization-uri=http://localhost:8080/realms/middleware/protocol/openid-connect/auth

# ✅ 서버 간 통신 → Docker 내부 DNS(keycloak) 사용
spring.security.oauth2.client.provider.keycloak.issuer-uri=http://keycloak:8080/realms/middleware
spring.security.oauth2.client.provider.keycloak.token-uri=http://keycloak:8080/realms/middleware/protocol/openid-connect/token
spring.security.oauth2.client.provider.keycloak.jwk-set-uri=http://keycloak:8080/realms/middleware/protocol/openid-connect/certs
spring.security.oauth2.client.provider.keycloak.user-info-uri=http://keycloak:8080/realms/middleware/protocol/openid-connect/userinfo
```

**왜 분리해야 하는가?**

```
브라우저 (호스트 PC)                    Docker 내부 네트워크
┌─────────────┐                       ┌─────────────────────┐
│  사용자 PC   │──localhost:8080──────►│  Keycloak (:8080)   │
│  (브라우저)  │                       │                     │
└─────────────┘                       └─────────────────────┘
                                              ▲
┌─────────────────────┐                       │
│  Tomcat (WAS)       │──keycloak:8080────────┘
│  (Docker 컨테이너)   │  (Docker DNS로 해석)
└─────────────────────┘
```

- 브라우저는 Docker 내부 DNS인 `keycloak`을 해석할 수 없음 → `localhost` 필요
- Tomcat은 Docker 네트워크 안에 있으므로 `keycloak`으로 직접 접근 가능

### Step 5: SSO 로그인 플로우 테스트

```bash
# 보호된 페이지에 접근 시도
curl -k https://localhost/secured/profile
```

**확인 포인트**: 로그인하지 않았으므로 **302 리다이렉트** 또는 **Keycloak 로그인 페이지 HTML**이 응답된다. 이것은 SSO가 정상 동작하는 것이다.

브라우저에서 직접 테스트:
1. `https://localhost/secured/profile` 접속
2. Keycloak 로그인 페이지로 자동 이동되는지 확인
3. `testuser` / `test123` 으로 로그인
4. 로그인 성공 후 아래와 같은 JSON이 표시되면 SSO 완료:

```json
{
  "username": "testuser",
  "email": "test@middleware.local",
  "name": "Test User",
  "host": "abc1234def",
  "message": "SSO 인증 성공! Keycloak OIDC로 로그인되었다."
}
```

### Step 6: 토큰 직접 발급해보기 (선택)

OIDC Token Endpoint로 직접 토큰을 발급받을 수도 있다:

```bash
# Access Token 발급
curl -X POST http://localhost:8080/realms/middleware/protocol/openid-connect/token \
  -d "grant_type=password" \
  -d "client_id=middleware-app" \
  -d "client_secret=middleware-app-secret" \
  -d "username=testuser" \
  -d "password=test123"
```

**확인 포인트**: `access_token`, `refresh_token`, `token_type: "Bearer"` 가 포함된 JSON이 응답되면 정상이다.

---

## 8. Scouter - APM 모니터링 확인하기

**목적**: Scouter가 Tomcat의 성능 데이터(TPS, 응답시간, JVM)를 수집하고 있는지 확인한다.

### Step 1: Scouter Server 동작 확인

```bash
# Scouter Server 로그 확인
docker logs mw-scouter
```

**확인 포인트**: `Scouter server started` 또는 포트 `6100`에서 수신 대기 중이라는 메시지가 있으면 정상이다.

### Step 2: Scouter Agent 연결 확인

```bash
# Tomcat 로그에서 Scouter Agent 연결 확인
docker logs mw-tomcat1 2>&1 | grep -i scouter
docker logs mw-tomcat2 2>&1 | grep -i scouter
```

**확인 포인트**: `Scouter Agent` 관련 로그가 출력되면 Agent가 정상적으로 부착된 것이다.

### Step 3: Scouter Client 설치 및 접속

Scouter의 전체 기능(XLog, TPS, Heap 등)을 시각적으로 보려면 별도의 **Scouter Client(GUI)**를 설치해야 한다.

> Scouter Client는 Homebrew에 등록되어 있지 않으므로 GitHub Releases에서 직접 다운로드한다.

#### macOS (Apple Silicon / M1~M4)

```bash
# 1. 다운로드 (aarch64 = Apple Silicon)
curl -L -o /tmp/scouter-client-mac.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-macosx.cocoa.aarch64.tar.gz

# 2. 압축 해제
mkdir -p ~/Applications/Scouter
tar -xzf /tmp/scouter-client-mac.tar.gz -C ~/Applications/Scouter

# 3. macOS 보안 속성 제거 (이 단계를 빠뜨리면 "손상된 앱" 경고가 뜹니다)
xattr -cr ~/Applications/Scouter/scouter.client.app

# 4. 실행
open ~/Applications/Scouter/scouter.client.app
```

#### macOS (Intel)

```bash
# Intel Mac은 x86_64 버전을 다운로드한다
curl -L -o /tmp/scouter-client-mac.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-macosx.cocoa.x86_64.tar.gz

# 이후 동일
mkdir -p ~/Applications/Scouter
tar -xzf /tmp/scouter-client-mac.tar.gz -C ~/Applications/Scouter
xattr -cr ~/Applications/Scouter/scouter.client.app
open ~/Applications/Scouter/scouter.client.app
```

#### Windows

1. [scouter.client.product-win32.win32.x86_64.zip](https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-win32.win32.x86_64.zip) 다운로드
2. 압축 해제 후 `scouter.exe` 실행

#### Linux

```bash
curl -L -o /tmp/scouter-client-linux.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-linux.gtk.x86_64.tar.gz
tar -xzf /tmp/scouter-client-linux.tar.gz -C ~/
~/scouter.client/scouter
```

### Step 4: Scouter Client 접속 설정

Scouter Client가 실행되면 접속 정보를 입력한다:

| 항목 | 값 |
|------|------|
| **Server Address** | `127.0.0.1` |
| **Port** | `6100` |
| **ID** | `admin` |
| **Password** | `admin` |

### Step 5: Scouter Client에서 확인 가능한 항목

접속 성공 후 아래 모니터링 항목을 확인할 수 있다:

| 모니터링 항목 | 설명 | 확인 방법 |
|--------------|------|-----------|
| **XLog** | 개별 트랜잭션의 응답시간 분포 (점 하나 = 요청 하나) | Object 우클릭 → XLog 열기 |
| **TPS** | 초당 처리 건수 | Object 우클릭 → TPS 열기 |
| **Active Service** | 현재 처리 중인 요청 수 | 메인 화면에 표시 |
| **Heap Memory** | JVM 힙 메모리 사용량 및 GC 발생 | Object 우클릭 → Heap Memory 열기 |
| **Thread List** | 현재 활성 쓰레드 목록 | Object 우클릭 → Thread List |

> XLog 차트에서 점을 클릭하면 해당 요청의 **SQL, API 호출 경로, 응답시간 상세**를 확인할 수 있다. 이것이 Jennifer와 동일한 APM 분석 방식이다.

### Step 6: 부하 발생 후 모니터링 변화 관찰

```bash
# 부하 발생 (200회 요청)
for i in $(seq 1 200); do curl -sk https://localhost/ > /dev/null; done
```

Scouter Client의 XLog 차트에 점이 찍히고, TPS 그래프가 올라가는 것을 확인한다.

---

## 9. SSL/HTTPS - 인증서 확인하기

**목적**: 자체 CA로 발급한 SSL 인증서가 Nginx에 적용되어 HTTPS 통신이 되는지 확인한다.

### 터미널에서 확인

```bash
# SSL 인증서 상세 정보 확인
openssl s_client -connect localhost:443 -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

**확인 포인트**:
```
subject= CN = localhost                    ← 서버 인증서
issuer= CN = Middleware CA                 ← 자체 CA가 발급
notBefore= ...                             ← 발급일
notAfter= ...                              ← 만료일
```

### 브라우저에서 확인

1. `https://localhost` 접속
2. 주소창의 **자물쇠 아이콘** (또는 "주의 안함") 클릭
3. **인증서 보기** 클릭
4. 발급자가 `Middleware CA`, 주체가 `localhost`인지 확인

### HTTP → HTTPS 리다이렉트 확인

```bash
# HTTP(80)로 접속하면 HTTPS(443)로 자동 리다이렉트
curl -I http://localhost
```

**확인 포인트**: 응답에 `301 Moved Permanently`와 `Location: https://localhost/`가 있으면 정상이다.

---

## 10. 장애 시뮬레이션 - 고가용성 확인하기

**목적**: WAS 한 대가 죽어도 서비스가 계속 동작하는지 확인한다.

### Step 1: 정상 상태에서 요청 확인

```bash
curl -k https://localhost/health
# → {"status":"UP","host":"<tomcat1 또는 tomcat2>"}
```

### Step 2: Tomcat #2를 강제 중지

```bash
docker stop mw-tomcat2
```

### Step 3: 서비스가 여전히 동작하는지 확인

```bash
# 여러 번 요청
curl -k https://localhost/health
curl -k https://localhost/health
curl -k https://localhost/health
```

**확인 포인트**: 모든 요청이 **Tomcat #1**에서만 응답된다. `host` 값이 전부 같으면 정상 — Nginx가 살아있는 서버로만 트래픽을 보내는 것이다.

### Step 4: Tomcat #2 복구

```bash
docker start mw-tomcat2

# 잠시 후 다시 요청
curl -k https://localhost/health
curl -k https://localhost/health
```

**확인 포인트**: 다시 `host` 값이 번갈아 나오면 이중화가 복구된 것이다.

---

## 11. 환경 종료

```bash
# 컨테이너만 종료 (데이터 보존)
docker-compose down

# 컨테이너 + 볼륨 데이터 모두 삭제 (완전 초기화)
docker-compose down -v
```

---

## 전체 서비스 접속 정보 요약

| 서비스 | URL | 계정 | 용도 |
|--------|-----|------|------|
| Nginx (WEB) | `https://localhost` | - | 메인 웹 서비스 |
| Grafana | `http://localhost:3000` | admin / admin | 모니터링 대시보드 |
| Keycloak | `http://localhost:8080` | admin / admin | SSO 관리 콘솔 |
| Keycloak SSO 테스트 | `https://localhost/secured/profile` | testuser / test123 | SSO 로그인 테스트 |
| Prometheus | `http://localhost:9090` | - | 메트릭 조회 |
| Scouter Server | `localhost:6100` | - | APM (Scouter Client 필요) |
| MySQL | `localhost:3306` | root / root_password | DB 접속 (선택) |

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [아키텍처 설계](architecture.md) | 시스템 아키텍처 이해 |
| [Scouter APM 가이드](scouter-guide.md) | Scouter APM 상세 가이드 |
| [보안 심층 분석](security-deep-dive.md) | Keycloak 보안 설정 상세 |
| [트러블슈팅 가이드](troubleshooting.md) | 문제 해결 가이드 |
