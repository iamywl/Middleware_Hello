# WEB/WAS 미들웨어 시스템 아키텍처

> 이 문서는 본 프로젝트의 전체 구조와 구동 메커니즘을 **하나의 책**처럼 설명한다.
> 각 장(Chapter)은 독립적으로 읽을 수 있지만, 순서대로 읽으면 시스템의 설계 의도부터
> 패킷이 흐르는 경로, 각 컴포넌트의 내부 동작까지 빠짐없이 이해할 수 있다.

---

## 목차

1. [설계 철학과 전체 개요](#1-설계-철학과-전체-개요)
2. [전체 구성도](#2-전체-구성도)
3. [컨테이너 오케스트레이션과 부팅 순서](#3-컨테이너-오케스트레이션과-부팅-순서)
4. [네트워크 아키텍처](#4-네트워크-아키텍처)
5. [WEB 계층 — Nginx 리버스 프록시](#5-web-계층--nginx-리버스-프록시)
6. [WAS 계층 — Tomcat + Spring Boot](#6-was-계층--tomcat--spring-boot)
7. [데이터베이스 계층 — MySQL](#7-데이터베이스-계층--mysql)
8. [인증/인가 계층 — Keycloak SSO](#8-인증인가-계층--keycloak-sso)
9. [요청 처리 구동 메커니즘](#9-요청-처리-구동-메커니즘)
10. [SSL/TLS와 PKI 구조](#10-ssltls와-pki-구조)
11. [로드밸런싱 메커니즘](#11-로드밸런싱-메커니즘)
12. [모니터링 구동 메커니즘](#12-모니터링-구동-메커니즘)
13. [빌드와 배포 파이프라인](#13-빌드와-배포-파이프라인)
14. [부하 테스트](#14-부하-테스트)
15. [데이터 영속성과 볼륨 관리](#15-데이터-영속성과-볼륨-관리)
16. [장애 감지와 자동 복구](#16-장애-감지와-자동-복구)

---

## 1. 설계 철학과 전체 개요

### 1.1 이 시스템은 무엇인가

본 시스템은 **엔터프라이즈 WEB/WAS 미들웨어 인프라**의 핵심 구성요소를 하나의 Docker Compose 환경으로 재현한 것이다. 실무에서 리눅스 서버 위에 수동으로 구성하는 Nginx → Tomcat → MySQL 3-Tier 아키텍처를 컨테이너로 모델링하여, 미들웨어 엔지니어가 알아야 할 모든 기술 요소를 학습하고 실험할 수 있도록 설계되었다.

### 1.2 왜 이 구조인가

실제 운영 환경에서 미들웨어 엔지니어가 다루는 기술 스택은 크게 네 축으로 나뉜다.

| 축 | 역할 | 본 시스템의 구현 |
|---|---|---|
| **WEB** | 클라이언트 접점, SSL 종단, 정적 자원, 부하 분산 | Nginx 1.24 |
| **WAS** | 비즈니스 로직 실행, 서블릿 컨테이너 | Tomcat 10.1 × 2 (이중화) |
| **DB** | 영속 데이터 저장 | MySQL 8.0 |
| **운영 지원** | 인증, 모니터링, APM | Keycloak 24.0, Prometheus, Grafana, Scouter |

이 네 축을 조합하면 **"클라이언트의 HTTPS 요청이 WEB을 거쳐 WAS에 도달하고, DB에서 데이터를 조회하며, 그 과정이 실시간으로 모니터링되고, 인증이 필요한 경우 SSO를 통해 검증되는"** 엔드-투-엔드(end-to-end) 흐름이 완성된다.

### 1.3 10개 컨테이너 한눈에 보기

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Docker Compose (10 services)                    │
│                                                                         │
│  ┌────────┐  ┌─────────┐  ┌─────────┐  ┌───────┐  ┌──────────┐       │
│  │ Nginx  │→│ Tomcat1 │→│  MySQL  │  │Keycloak│ │  Scouter │       │
│  │ (WEB)  │→│ Tomcat2 │→│  (DB)   │  │ (SSO)  │ │  (APM)   │       │
│  └────────┘  └─────────┘  └─────────┘  └───────┘  └──────────┘       │
│                                                                         │
│  ┌────────────┐  ┌───────────┐  ┌─────────┐  ┌────────────────┐      │
│  │ Prometheus │→│  Grafana  │  │  Node   │  │ Nginx Exporter │      │
│  │ (메트릭DB) │  │ (대시보드) │  │Exporter │  │  (Nginx 메트릭) │      │
│  └────────────┘  └───────────┘  └─────────┘  └────────────────┘      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 전체 구성도

```
                              ┌──────────────────┐
                              │  Client Browser   │
                              └────────┬─────────┘
                                       │
                                       │ HTTPS (TLS 1.2/1.3)
                                       │ Port 443
                                       ▼
                              ┌──────────────────┐
                         ┌────│      Nginx        │────┐
                         │    │  (Reverse Proxy)   │    │
                         │    │  ● SSL Termination │    │
                         │    │  ● Load Balancing  │    │
                         │    │  ● Static Cache    │    │
                         │    │  ● Gzip 압축       │    │
                         │    └──────────────────┘    │
                         │                              │
                         │ Round Robin (weight=1:1)     │
                         ▼                              ▼
                ┌─────────────────┐      ┌─────────────────┐
                │    Tomcat #1     │      │    Tomcat #2     │
                │  ┌─────────────┐ │      │  ┌─────────────┐ │
                │  │ Spring Boot │ │      │  │ Spring Boot │ │
                │  │    (WAR)    │ │      │  │    (WAR)    │ │
                │  ├─────────────┤ │      │  ├─────────────┤ │
                │  │Scouter Agent│ │      │  │Scouter Agent│ │
                │  └─────────────┘ │      │  └─────────────┘ │
                │  JVM: 256~512MB  │      │  JVM: 256~512MB  │
                └────────┬────────┘      └────────┬────────┘
                         │                          │
                         │    JDBC Connection       │
                         ▼                          ▼
                ┌──────────────────────────────────────────┐
                │                MySQL 8.0                   │
                │            middleware_db                    │
                │      (Volume: mysql_data 영속 저장)         │
                └──────────────────────────────────────────┘

   ┌─────────────────────────────────────────────────────────────────┐
   │                   모니터링 / 보안 / APM 계층                      │
   │                                                                   │
   │  ┌──────────┐  ┌───────────┐  ┌─────────┐  ┌───────────┐       │
   │  │ Scouter  │  │Prometheus │→│ Grafana │  │ Keycloak  │       │
   │  │ Server   │  │           │  │         │  │   (SSO)   │       │
   │  │ :6100    │  │  :9090    │  │  :3000  │  │   :8080   │       │
   │  └────▲─────┘  └─────▲────┘  └─────────┘  └───────────┘       │
   │       │              │                                           │
   │       │         ┌────┴─────────────────┐                        │
   │   UDP/TCP  ┌────┴──────┐  ┌───────────┴─┐  ┌──────────────┐   │
   │   6100    │   Node     │  │   Nginx    │  │  Tomcat      │   │
   │           │  Exporter  │  │  Exporter  │  │  /actuator   │   │
   │           │   :9100    │  │   :9113    │  │  /prometheus  │   │
   │           └────────────┘  └────────────┘  └──────────────┘   │
   └─────────────────────────────────────────────────────────────────┘
```

---

## 3. 컨테이너 오케스트레이션과 부팅 순서

### 3.1 의존성 체인

Docker Compose의 `depends_on` 및 `healthcheck`로 부팅 순서를 제어한다. 잘못된 순서로 기동하면 DB 연결 실패나 프록시 504 에러가 발생하므로, 의존성 체인은 시스템 안정성의 핵심이다.

```
Phase 1 (독립 기동)
  ├── mysql            → healthcheck: mysqladmin ping (10초 간격, 5회 재시도)
  ├── keycloak         → 독립 기동 (realm 자동 import)
  ├── scouter-server   → 독립 기동
  ├── prometheus       → 독립 기동
  └── node-exporter    → 독립 기동

Phase 2 (MySQL healthy 이후)
  ├── tomcat1          → depends_on: mysql (condition: service_healthy)
  └── tomcat2          → depends_on: mysql (condition: service_healthy)

Phase 3 (Tomcat 기동 이후)
  └── nginx            → depends_on: tomcat1, tomcat2

Phase 4 (Nginx 기동 이후)
  └── nginx-exporter   → depends_on: nginx

Phase 5 (Prometheus 기동 이후)
  └── grafana          → depends_on: prometheus
```

### 3.2 구동 메커니즘 — 시스템이 기동하는 과정

사용자가 `./scripts/start.sh` 또는 `docker-compose up --build`를 실행하면 다음 과정이 진행된다.

**Step 1. 이미지 빌드 (app/Dockerfile — Multi-stage Build)**

```
[Stage 1: Maven 빌드]
  maven:3.9-eclipse-temurin-17 이미지 위에서
  → pom.xml로 의존성 다운로드 (mvn dependency:go-offline)
  → src/ 복사 후 mvn package → app.war 생성

[Stage 2: Tomcat 런타임]
  tomcat:10.1-jdk17 이미지 위에서
  → Scouter Java Agent 2.20.0 다운로드 및 설치 (/opt/scouter/)
  → 기존 webapps 삭제
  → app.war → /usr/local/tomcat/webapps/ROOT.war 배치
```

**Step 2. 컨테이너 생성 및 네트워크 연결**

```
Docker가 mw-network (bridge 드라이버) 생성
  → 각 컨테이너에 172.x.x.x 대역 IP 할당
  → 컨테이너 이름이 DNS로 등록 (예: mysql, tomcat1, keycloak)
```

**Step 3. MySQL 기동 및 헬스체크**

```
MySQL 시작 → middleware_db 생성, app_user 계정 생성
  → mysqladmin ping 헬스체크 통과할 때까지 대기
  → 통과하면 Phase 2 컨테이너 기동 시작
```

**Step 4. Tomcat 기동**

```
catalina.sh run 실행
  → JVM 시작 (-Xms256m -Xmx512m)
  → Scouter Agent 로드 (-javaagent:/opt/scouter/agent.java/scouter.agent.jar)
  → ROOT.war 자동 배포 (unpackWARs=true)
  → Spring Boot 초기화
    → DataSource: MySQL 연결 (JDBC)
    → JPA: hibernate.ddl-auto=update (스키마 자동 생성/갱신)
    → Spring Security: OAuth2 Client 설정 로드
    → Actuator: /actuator/prometheus 엔드포인트 활성화
  → HTTP Connector 바인딩 (port 8080, maxThreads=200)
  → "Started DemoApplication" 로그 출력 → 서비스 준비 완료
```

**Step 5. Nginx 기동**

```
nginx.conf 로드
  → worker_processes auto (CPU 코어 수만큼 워커 프로세스 생성)
  → conf.d/default.conf 로드
    → upstream was_backend { tomcat1:8080, tomcat2:8080 } 정의
    → SSL 인증서 로드 (server-chain.crt + server.key)
  → 포트 바인딩: 80 (HTTP), 443 (HTTPS)
  → 서비스 준비 완료
```

**Step 6. 모니터링 스택 활성화**

```
Prometheus가 15초 간격으로 스크래핑 시작
  → node-exporter:9100 (OS 메트릭)
  → nginx-exporter:9113 (Nginx 메트릭)
  → tomcat1:8080/actuator/prometheus (JVM 메트릭)
  → tomcat2:8080/actuator/prometheus (JVM 메트릭)

Grafana가 Prometheus를 데이터소스로 자동 등록
  → 사전 구성된 middleware-overview 대시보드 자동 로드

Scouter Agent가 Scouter Server로 데이터 전송 시작
  → UDP/TCP 6100 포트로 TPS, 응답시간, JVM 메트릭 전송
```

---

## 4. 네트워크 아키텍처

### 4.1 Docker Bridge 네트워크

모든 컨테이너는 `mw-network` (Docker bridge 드라이버) 내에서 통신한다. Docker bridge 네트워크는 가상의 내부 스위치로 동작하며, 각 컨테이너는 이 스위치에 연결된 독립적인 네트워크 인터페이스(veth)를 갖는다.

```
┌─────────────────── 호스트 OS ───────────────────┐
│                                                    │
│   ┌─── mw-network (bridge: 172.18.0.0/16) ───┐   │
│   │                                             │   │
│   │  ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐  │   │
│   │  │ nginx │ │tomcat1│ │tomcat2│ │ mysql │  │   │
│   │  │.18.2  │ │.18.3  │ │.18.4  │ │.18.5  │  │   │
│   │  └───┬───┘ └───┬───┘ └───┬───┘ └───┬───┘  │   │
│   │      └─────┴───────┴───────┴─────────┘      │   │
│   │           가상 브릿지 (docker0)               │   │
│   └─────────────────────────────────────────────┘   │
│                        │                              │
│   ┌────────────────────┤ NAT/포트포워딩               │
│   │   80→80  443→443   │ 8080→8080  3306→3306         │
│   │   3000→3000  9090→9090  9100→9100  9113→9113     │
│   │   6100→6100  6180→6180                            │
│   └────────────────────┤                              │
└────────────────────────┼──────────────────────────────┘
                         │
                    외부 클라이언트
```

### 4.2 서비스별 네트워크 바인딩

| 컨테이너 | 컨테이너명 | 내부 포트 | 외부 포트 | 프로토콜 | 역할 |
|----------|-----------|----------|----------|---------|------|
| nginx | mw-nginx | 80, 443 | 80, 443 | HTTP/HTTPS | 리버스 프록시, SSL 종단, 로드밸런싱 |
| tomcat1 | mw-tomcat1 | 8080 | 미노출 | HTTP | WAS #1 (Spring Boot + Scouter Agent) |
| tomcat2 | mw-tomcat2 | 8080 | 미노출 | HTTP | WAS #2 (Spring Boot + Scouter Agent) |
| mysql | mw-mysql | 3306 | 3306 | TCP | 데이터베이스 |
| keycloak | mw-keycloak | 8080 | 8080 | HTTP | SSO 인증 서버 (OIDC) |
| scouter-server | mw-scouter | 6100, 6180 | 6100, 6180 | UDP/TCP/HTTP | APM 서버 |
| prometheus | mw-prometheus | 9090 | 9090 | HTTP | 메트릭 시계열 DB |
| grafana | mw-grafana | 3000 | 3000 | HTTP | 대시보드 |
| node-exporter | mw-node-exporter | 9100 | 9100 | HTTP | 서버 리소스 메트릭 |
| nginx-exporter | mw-nginx-exporter | 9113 | 9113 | HTTP | Nginx 메트릭 |

### 4.3 내부 DNS 해석

Docker 내장 DNS가 컨테이너 이름을 IP로 해석한다. 예를 들어:
- Tomcat에서 `mysql:3306`으로 JDBC 접속 → Docker DNS가 MySQL 컨테이너 IP 반환
- Nginx에서 `tomcat1:8080`으로 프록시 → Docker DNS가 Tomcat1 컨테이너 IP 반환
- Tomcat에서 `keycloak:8080`으로 토큰 교환 → Docker DNS가 Keycloak 컨테이너 IP 반환

이 DNS 해석 덕분에 IP 하드코딩 없이 **서비스 이름만으로 통신**할 수 있다.

---

## 5. WEB 계층 — Nginx 리버스 프록시

### 5.1 Nginx의 역할

Nginx는 시스템의 **최전방(Front Door)**으로, 클라이언트와 WAS 사이에서 다음 역할을 수행한다.

```
클라이언트 → [Nginx] → WAS
              │
              ├── 1. SSL/TLS 종단 (HTTPS 해독)
              ├── 2. HTTP → HTTPS 강제 리다이렉트
              ├── 3. 라운드 로빈 로드밸런싱
              ├── 4. 리버스 프록시 (내부 WAS 주소 은닉)
              ├── 5. 정적 자원 캐싱 (7일)
              ├── 6. Gzip 압축
              ├── 7. 보안 헤더 삽입 (HSTS)
              └── 8. 접근 로그 기록 (upstream 응답시간 포함)
```

### 5.2 Nginx 프로세스 모델

```
                    ┌─────────────────┐
                    │   Master Process │ ← nginx.conf 로드, 워커 관리
                    │    (root 권한)    │
                    └────────┬────────┘
                             │ fork
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │ Worker #1    │  │ Worker #2    │  │ Worker #N    │
  │ (nginx 권한) │  │ (nginx 권한) │  │ (nginx 권한) │
  │              │  │              │  │              │
  │ epoll 이벤트 │  │ epoll 이벤트 │  │ epoll 이벤트 │
  │ 루프 (비동기)│  │ 루프 (비동기)│  │ 루프 (비동기)│
  │              │  │              │  │              │
  │ 최대 1024    │  │ 최대 1024    │  │ 최대 1024    │
  │ 동시 연결    │  │ 동시 연결    │  │ 동시 연결    │
  └──────────────┘  └──────────────┘  └──────────────┘

  N = worker_processes auto = CPU 코어 수
```

Nginx는 **이벤트 드리븐(event-driven) 아키텍처**를 사용한다. 각 워커 프로세스는 단일 스레드로 동작하지만, `epoll`(Linux) 기반의 비동기 I/O 다중화를 통해 수천 개의 동시 연결을 처리한다. 이는 Apache httpd의 프로세스/스레드 모델과 근본적으로 다르며, 메모리 사용량이 극적으로 낮다.

### 5.3 핵심 설정 해설

**upstream 블록 — 로드밸런싱 대상 정의:**
```nginx
upstream was_backend {
    server tomcat1:8080 weight=1;    # WAS 1번 (가중치 1)
    server tomcat2:8080 weight=1;    # WAS 2번 (가중치 1)
}
```
이 블록이 Nginx에게 "요청을 `tomcat1`과 `tomcat2`에 번갈아 보내라"고 지시한다.

**SSL 설정:**
```nginx
ssl_certificate     /etc/nginx/ssl/server-chain.crt;   # 서버 인증서 + CA 체인
ssl_certificate_key /etc/nginx/ssl/server.key;          # 개인 키
ssl_protocols TLSv1.2 TLSv1.3;                          # 허용 프로토콜
ssl_ciphers ECDHE-...-GCM-SHA256:...;                   # 암호화 알고리즘
ssl_session_cache shared:SSL:10m;                        # 세션 캐시 (10MB)
```

**프록시 헤더 — 원본 클라이언트 정보 전달:**
```nginx
proxy_set_header Host $host;                           # 원본 호스트명
proxy_set_header X-Real-IP $remote_addr;               # 실제 클라이언트 IP
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  # IP 체인
proxy_set_header X-Forwarded-Proto $scheme;            # 원본 프로토콜 (https)
```
WAS는 이 헤더를 통해 클라이언트의 실제 IP와 프로토콜을 알 수 있다. 이 헤더가 없으면 WAS에는 항상 Nginx의 내부 IP만 보인다.

### 5.4 요청 처리 흐름 (Nginx 내부)

```
[1] 클라이언트 TCP 연결 수립 (3-way handshake)
                    │
[2] TLS 핸드셰이크 (인증서 교환, 세션 키 합의)
                    │
[3] HTTP 요청 수신 (GET /api/health HTTP/1.1)
                    │
[4] server 블록 매칭 (server_name: localhost)
                    │
[5] location 블록 매칭
    ├── /stub_status  → 내부 상태 페이지 반환
    ├── /nginx-health → "OK" 반환
    ├── ~* \.(js|css|png|...)$ → WAS 프록시 + 7일 캐시 헤더
    └── / → WAS 프록시 (기본)
                    │
[6] upstream 선택 (Round Robin → tomcat1 또는 tomcat2)
                    │
[7] 백엔드 연결 (proxy_connect_timeout: 10초)
                    │
[8] 요청 전달 + 헤더 삽입 (X-Real-IP, X-Forwarded-For 등)
                    │
[9] 백엔드 응답 수신 (proxy_read_timeout: 30초)
                    │
[10] 응답에 X-Upstream 헤더 추가 (어떤 WAS가 처리했는지)
                    │
[11] Gzip 압축 (text/plain, text/css, application/json 등)
                    │
[12] 클라이언트에 응답 전송
                    │
[13] 접근 로그 기록 (upstream 주소 + 응답 시간 포함)
```

---

## 6. WAS 계층 — Tomcat + Spring Boot

### 6.1 Tomcat의 내부 아키텍처

```
┌─────────────────────── Tomcat Server ───────────────────────┐
│                                                               │
│  ┌──── Service (Catalina) ────────────────────────────────┐  │
│  │                                                         │  │
│  │  ┌─── Connector (HTTP/1.1, port 8080) ──────────────┐  │  │
│  │  │  maxThreads=200  acceptCount=100                  │  │  │
│  │  │  minSpareThreads=10  maxConnections=8192          │  │  │
│  │  │                                                    │  │  │
│  │  │  ┌─────────────────────────────────────────────┐  │  │  │
│  │  │  │          스레드 풀 (Thread Pool)              │  │  │  │
│  │  │  │                                               │  │  │  │
│  │  │  │  [Thread-1] [Thread-2] ... [Thread-200]      │  │  │  │
│  │  │  │   (최소 10개 대기, 최대 200개 활성)             │  │  │  │
│  │  │  └─────────────────────────────────────────────┘  │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌─── Engine (Catalina, jvmRoute=tomcat1) ───────────┐  │  │
│  │  │                                                     │  │  │
│  │  │  ┌─── Host (localhost) ──────────────────────────┐  │  │  │
│  │  │  │                                                │  │  │  │
│  │  │  │  ┌─── Context (ROOT.war) ──────────────────┐  │  │  │  │
│  │  │  │  │                                          │  │  │  │  │
│  │  │  │  │   Spring Boot Application               │  │  │  │  │
│  │  │  │  │   ├── DispatcherServlet                  │  │  │  │  │
│  │  │  │  │   ├── SecurityFilterChain                │  │  │  │  │
│  │  │  │  │   ├── Controllers                        │  │  │  │  │
│  │  │  │  │   ├── JPA / DataSource                   │  │  │  │  │
│  │  │  │  │   └── Actuator Endpoints                 │  │  │  │  │
│  │  │  │  │                                          │  │  │  │  │
│  │  │  │  └──────────────────────────────────────────┘  │  │  │  │
│  │  │  │                                                │  │  │  │
│  │  │  │  AccessLogValve (로그: %h %l %u %t %r %s %b %D)│  │  │  │
│  │  │  └────────────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─── JVM ─────────────────────────────────────────────────┐  │
│  │  -Xms256m -Xmx512m                                      │  │
│  │  Scouter Agent (javaagent)                               │  │
│  │  GC: G1 (JDK 17 기본)                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

### 6.2 요청이 Tomcat 내부에서 처리되는 과정

```
[1] Nginx로부터 HTTP 요청 수신 (Connector, port 8080)
                    │
[2] 스레드 풀에서 유휴 스레드 할당
    ├── 유휴 스레드 있음 → 즉시 할당
    ├── 스레드 200개 모두 사용중 → acceptCount 큐에 대기 (최대 100)
    └── 큐도 가득 참 → Connection Refused (503)
                    │
[3] Engine → Host → Context 순으로 요청 라우팅
                    │
[4] Spring Security FilterChain 통과
    │
    ├── 공개 경로 (/,  /health, /info, /actuator/**)
    │   → 인증 없이 통과
    │
    └── 보호 경로 (/secured/**)
        ├── 세션에 인증 정보 있음 → 통과
        └── 세션에 인증 정보 없음 → OAuth2 로그인 리다이렉트
                    │
[5] DispatcherServlet이 URL → Controller 매핑
    │
    ├── GET /         → HealthController.index()
    │                    → {app, host, port, time, status} 반환
    │
    ├── GET /health   → HealthController.health()
    │                    → {status: "UP", host: hostname} 반환
    │
    ├── GET /info     → HealthController.info()
    │                    → {hostname, javaVersion, maxMemory, freeMemory, CPU} 반환
    │
    └── GET /secured/profile → SecuredController.profile()
                                → {username, email, name, host, message} 반환
                    │
[6] (필요시) JPA → DataSource → MySQL JDBC 쿼리
                    │
[7] JSON 응답 생성 → Nginx에 반환
                    │
[8] 스레드 풀에 스레드 반환
                    │
[9] AccessLogValve가 로그 기록 (응답 시간 %D 밀리초 포함)
                    │
[10] Scouter Agent가 트랜잭션 데이터 수집 → Scouter Server 전송
```

### 6.3 왜 WAR 배포인가 — JAR vs WAR

Spring Boot는 기본적으로 **내장 Tomcat이 포함된 JAR**로 실행할 수 있다. 그런데 본 프로젝트에서는 왜 별도 Tomcat 위에 WAR을 배포하는 방식을 사용할까?

```
[JAR 배포 방식]                          [WAR 배포 방식 — 본 프로젝트]
┌──────────────────────┐                ┌──────────────────────┐
│   java -jar app.jar  │                │   Tomcat (독립 서버)   │
│   ┌────────────────┐ │                │   ┌────────────────┐ │
│   │ 내장 Tomcat    │ │                │   │ app.war (배포)  │ │
│   │ + Spring Boot  │ │                │   │ + Spring Boot   │ │
│   └────────────────┘ │                │   └────────────────┘ │
│   포트: 8080          │                │   포트: 8080          │
└──────────────────────┘                │   + Scouter Agent    │
                                        │   + server.xml 튜닝  │
                                        └──────────────────────┘
```

| 비교 항목 | JAR (내장 Tomcat) | WAR (외장 Tomcat) |
|-----------|-------------------|-------------------|
| 배포 방식 | `java -jar app.jar` | WAR → `webapps/` 디렉토리 배치 |
| Tomcat 설정 변경 | application.properties 내 제한적 설정 | `server.xml`에서 **전체 제어** 가능 |
| 서블릿 컨테이너 교체 | 불가 (내장 고정) | Tomcat → Jetty → Undertow 교체 가능 |
| 운영 관리 | 앱 = 서버 (일체형) | 앱과 서버를 **분리 관리** |
| APM Agent 부착 | JVM 옵션으로 가능 | JVM 옵션으로 가능 (동일) |
| **실무 환경** | 마이크로서비스, 클라우드 네이티브 | **엔터프라이즈 미들웨어 운영** |

> **핵심**: 실무 미들웨어 환경에서는 WAS(Tomcat, WebLogic, JBoss)를 **별도로 운영**하며, server.xml 튜닝, 다중 WAR 배포, WAS 이중화 등을 수행한다. 본 프로젝트에서 WAR 배포를 선택한 이유는 이러한 **실무 미들웨어 엔지니어의 작업 환경을 그대로 재현**하기 위해서이다. 면접에서 "왜 Spring Boot인데 외장 Tomcat을 쓰나요?"라는 질문이 나올 수 있으므로, 이 차이를 정확히 이해해두자.

### 6.4 jvmRoute와 세션 식별

각 Tomcat 인스턴스는 고유한 `jvmRoute` 값을 가진다.

```xml
<!-- tomcat1: server.xml -->
<Engine name="Catalina" defaultHost="localhost" jvmRoute="tomcat1">

<!-- tomcat2: server.xml -->
<Engine name="Catalina" defaultHost="localhost" jvmRoute="tomcat2">
```

Tomcat이 세션을 생성하면 세션 ID 뒤에 jvmRoute가 붙는다:
- `SESSIONID.tomcat1` → Tomcat1이 생성한 세션
- `SESSIONID.tomcat2` → Tomcat2가 생성한 세션

이를 통해 로드밸런서가 세션 기반 라우팅(Sticky Session)을 적용할 수 있다.

### 6.4 Scouter Agent 동작 메커니즘

```
JVM 시작 시:
  → -javaagent:/opt/scouter/agent.java/scouter.agent.jar 로드
  → agent.conf 설정 읽기
  → Bytecode Instrumentation으로 대상 클래스에 프로파일링 코드 삽입

실행 중:
  ┌─────────────┐     ┌────────────────┐
  │ Spring Boot │     │  Scouter Agent │
  │ Controller  │────→│  (같은 JVM)    │
  │ 메서드 호출  │     │                │
  └─────────────┘     │ 수집 데이터:    │
                       │ ● 트랜잭션 시작/종료 시간
                       │ ● SQL 쿼리 텍스트 및 소요시간
                       │ ● HTTP 요청 URI
                       │ ● 호출된 메서드 프로파일
                       │ ● Exception 스택트레이스
                       └────────┬───────┘
                                │ UDP/TCP (port 6100)
                                ▼
                       ┌────────────────┐
                       │ Scouter Server │
                       │ (별도 컨테이너) │
                       │ 데이터 저장:    │
                       │ ● XLog (트랜잭션 분포도)
                       │ ● TPS (초당 트랜잭션)
                       │ ● 응답시간 분포
                       │ ● JVM Heap 사용량
                       └────────────────┘
```

Hook 패턴 설정:
```properties
hook_method_patterns=com.middleware.demo.*.*           # 모든 클래스.메서드
hook_service_patterns=com.middleware.demo.controller.*.*  # 컨트롤러 서비스 추적
trace_http_client_ip_header_key=X-Forwarded-For       # 실제 클라이언트 IP 추적
```

---

## 7. 데이터베이스 계층 — MySQL

### 7.1 구성

```
┌─────────────────────────────────┐
│         MySQL 8.0                │
│                                  │
│  Database: middleware_db         │
│  User: app_user / app_password  │
│  Root: root / root_password     │
│                                  │
│  ┌────────────────────────────┐ │
│  │    InnoDB Storage Engine   │ │
│  │    (트랜잭션, MVCC, FK)     │ │
│  └────────────────────────────┘ │
│                                  │
│  Volume: mysql_data             │
│  (호스트의 Docker Volume에 영속) │
└──────────┬──────────────────────┘
           │
  JDBC Connection Pool (HikariCP)
           │
    ┌──────┴──────┐
    ▼              ▼
 Tomcat1        Tomcat2
```

### 7.2 연결 메커니즘

Spring Boot의 DataSource 설정:
```properties
spring.datasource.url=jdbc:mysql://mysql:3306/middleware_db
  ?useSSL=false                       # 컨테이너 내부 통신이므로 SSL 불필요
  &allowPublicKeyRetrieval=true       # MySQL 8 caching_sha2_password 지원
  &serverTimezone=Asia/Seoul          # 타임존 명시
```

연결 과정:
1. Spring Boot 시작 시 `HikariCP` 커넥션 풀 초기화
2. Docker DNS로 `mysql` → MySQL 컨테이너 IP 해석
3. TCP 3306 포트로 JDBC 연결 수립
4. `hibernate.ddl-auto=update`로 엔티티 기반 스키마 자동 갱신
5. 풀에서 커넥션을 꺼내 쓰고, 사용 후 풀에 반환

---

## 8. 인증/인가 계층 — Keycloak SSO

### 8.1 Keycloak의 역할

Keycloak은 **OpenID Connect (OIDC)** 프로토콜 기반의 SSO(Single Sign-On) 서버다. 사용자의 로그인/로그아웃, 세션 관리, 토큰 발급을 중앙에서 처리한다.

```
┌────────────────────── Keycloak Server ──────────────────────┐
│                                                               │
│  Realm: middleware                                           │
│  ├── Client: middleware-app                                  │
│  │   ├── Client ID: middleware-app                           │
│  │   ├── Client Secret: middleware-app-secret                │
│  │   ├── Protocol: openid-connect                            │
│  │   ├── Grant Type: authorization_code                      │
│  │   └── Redirect URIs: http(s)://localhost/*                │
│  │                                                            │
│  ├── Users                                                    │
│  │   ├── admin@middleware.local (roles: admin, user)         │
│  │   └── test@middleware.local  (roles: user)                │
│  │                                                            │
│  └── OIDC Endpoints                                          │
│      ├── Authorization: /realms/middleware/.../auth           │
│      ├── Token:         /realms/middleware/.../token          │
│      ├── UserInfo:      /realms/middleware/.../userinfo       │
│      └── JWKS:          /realms/middleware/.../certs          │
└───────────────────────────────────────────────────────────────┘
```

### 8.2 Split URI 패턴

본 시스템에서 가장 까다로운 설계 포인트 중 하나다. Docker 환경에서 Keycloak은 **두 가지 경로**로 접근해야 한다.

```
┌──────────────────────────────────────────────────────────────────┐
│                     Split URI 패턴                                │
│                                                                    │
│  [브라우저 → Keycloak]  (사용자가 직접 접근)                        │
│    authorization-uri: http://localhost:8080/realms/middleware/...  │
│    └── 이유: 브라우저는 Docker 네트워크 밖에 있으므로                 │
│             localhost:8080(포트포워딩)으로 접근해야 한다             │
│                                                                    │
│  [Tomcat → Keycloak]  (서버 간 통신, 사용자 모름)                   │
│    token-uri:     http://keycloak:8080/realms/middleware/...       │
│    jwk-set-uri:   http://keycloak:8080/realms/middleware/...       │
│    user-info-uri: http://keycloak:8080/realms/middleware/...       │
│    └── 이유: Tomcat은 Docker 네트워크 안에 있으므로                  │
│             컨테이너 이름(keycloak)으로 직접 통신 가능               │
└──────────────────────────────────────────────────────────────────┘
```

만약 모든 URI를 `localhost`로 통일하면 Tomcat이 토큰을 교환할 때 자기 자신(localhost)으로 접속하게 되어 실패한다. 반대로 모든 URI를 `keycloak`으로 통일하면 브라우저가 `keycloak`이라는 호스트를 해석할 수 없어 실패한다.

### 8.3 OIDC Authorization Code Flow — 완전한 구동 메커니즘

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────────┐
│ 브라우저  │     │  Nginx   │     │  Tomcat  │     │   Keycloak   │
│(사용자)   │     │  (:443)  │     │  (WAS)   │     │   (:8080)    │
└────┬─────┘     └────┬─────┘     └────┬─────┘     └──────┬───────┘
     │                 │              │                     │
     │ ① GET /secured/profile        │                     │
     │ (인증이 필요한 페이지 요청)       │                     │
     │────────────────►│──────────────►│                     │
     │                 │              │                     │
     │                 │              │ ② 세션 확인 →        │
     │                 │              │   인증 정보 없음      │
     │                 │              │                     │
     │ ③ 302 Redirect                │                     │
     │ Location: http://localhost:8080│                     │
     │   /realms/middleware/protocol/ │                     │
     │   openid-connect/auth         │                     │
     │   ?response_type=code         │                     │
     │   &client_id=middleware-app   │                     │
     │   &scope=openid+profile+email │                     │
     │   &redirect_uri=https://...   │                     │
     │   /login/oauth2/code/keycloak │                     │
     │◄────────────────│◄──────────────│                     │
     │                 │              │                     │
     │ ④ 브라우저가 Keycloak 로그인 페이지로 직접 이동        │
     │   (localhost:8080 — Docker 포트포워딩으로 Keycloak 접근) │
     │─────────────────────────────────────────────────────►│
     │                 │              │                     │
     │                 │              │      ⑤ 로그인 폼 표시 │
     │◄─────────────────────────────────────────────────────│
     │                 │              │                     │
     │ ⑥ 사용자가 ID/PW 입력 (testuser / test123)           │
     │─────────────────────────────────────────────────────►│
     │                 │              │                     │
     │                 │              │  ⑦ 인증 성공!        │
     │                 │              │  Authorization Code  │
     │ ⑧ 302 Redirect                │  발급               │
     │ Location: https://localhost/login/oauth2/code/keycloak│
     │   ?code=abc123...             │                     │
     │◄─────────────────────────────────────────────────────│
     │                 │              │                     │
     │ ⑨ callback 요청 (code 포함)    │                     │
     │────────────────►│──────────────►│                     │
     │                 │              │                     │
     │                 │              │ ⑩ Tomcat → Keycloak │
     │                 │              │   (서버 간 통신)     │
     │                 │              │   POST token-uri    │
     │                 │              │   keycloak:8080     │
     │                 │              │   (code + secret)   │
     │                 │              │──────────────────────►│
     │                 │              │                     │
     │                 │              │ ⑪ Access Token +    │
     │                 │              │   ID Token +        │
     │                 │              │   Refresh Token 발급 │
     │                 │              │◄──────────────────────│
     │                 │              │                     │
     │                 │              │ ⑫ UserInfo 조회      │
     │                 │              │   GET user-info-uri │
     │                 │              │   keycloak:8080     │
     │                 │              │──────────────────────►│
     │                 │              │◄──────────────────────│
     │                 │              │                     │
     │                 │              │ ⑬ 세션에 인증 정보   │
     │                 │              │   저장 (OAuth2User) │
     │                 │              │                     │
     │ ⑭ 200 OK                      │                     │
     │ { username, email, name, host, │                     │
     │   message: "SSO 인증 성공!" }  │                     │
     │◄────────────────│◄──────────────│                     │
     │                 │              │                     │
```

**핵심 포인트:**
- ③에서 `authorization-uri`는 `localhost:8080` → 브라우저가 직접 접근
- ⑩에서 `token-uri`는 `keycloak:8080` → Tomcat이 Docker 내부에서 직접 접근
- ⑫에서 `user-info-uri`는 `keycloak:8080` → 마찬가지로 Docker 내부 통신

### 8.4 Spring Security 설정

```java
// SecurityConfig.java — 접근 제어 정책
http.authorizeHttpRequests(auth -> auth
    .requestMatchers("/", "/health", "/info").permitAll()    // 공개
    .requestMatchers("/actuator/**").permitAll()             // 모니터링
    .requestMatchers("/secured/**").authenticated()          // 인증 필요
    .anyRequest().permitAll()                                // 나머지 공개
)
.oauth2Login(oauth2 -> oauth2
    .defaultSuccessUrl("/secured/profile", true)             // 로그인 성공 시 이동
)
.logout(logout -> logout
    .logoutSuccessUrl("/").permitAll()                       // 로그아웃 시 루트로
);
```

---

## 9. 요청 처리 구동 메커니즘

이 장에서는 **하나의 HTTP 요청이 시스템의 모든 계층을 관통하는 전체 과정**을 시간 순서대로 추적한다.

### 9.1 일반 요청 (GET /health)

```
시간  │ 위치          │ 동작
──────┼───────────────┼──────────────────────────────────────
 T+0  │ 브라우저      │ https://localhost/health 요청 전송
      │               │
 T+1  │ 호스트 OS     │ TCP SYN → 호스트 443 포트 → Docker NAT → Nginx 443
      │               │
 T+2  │ Nginx        │ 워커 프로세스가 연결 수락 (epoll)
      │               │ TLS 핸드셰이크 수행
      │               │ ① ClientHello (TLS 1.3, 암호 스위트 목록)
      │               │ ② ServerHello (선택된 암호, 인증서 전송)
      │               │ ③ 키 교환 → 세션 키 확립
      │               │
 T+3  │ Nginx        │ HTTP 요청 복호화
      │               │ server 블록 매칭 → localhost
      │               │ location / 매칭
      │               │ upstream was_backend → Round Robin → tomcat1 선택
      │               │
 T+4  │ Nginx→Tomcat │ proxy_pass http://tomcat1:8080/health
      │               │ 헤더 삽입: X-Real-IP, X-Forwarded-For, X-Forwarded-Proto
      │               │
 T+5  │ Tomcat1      │ Connector가 요청 수신
      │               │ 스레드 풀에서 Thread-7 할당
      │               │ Scouter Agent: 트랜잭션 시작 기록 (txid 생성)
      │               │
 T+6  │ Spring Boot  │ SecurityFilterChain: /health → permitAll → 통과
      │               │ DispatcherServlet → HealthController.health()
      │               │ → InetAddress.getLocalHost().getHostName()
      │               │ → Map.of("status", "UP", "host", "<컨테이너ID>")
      │               │
 T+7  │ Tomcat1      │ Jackson이 Map → JSON 직렬화
      │               │ HTTP 200 응답 생성
      │               │ Scouter Agent: 트랜잭션 종료, 응답시간 기록
      │               │ AccessLogValve: 로그 기록 (%D = 3ms)
      │               │ Thread-7을 풀에 반환
      │               │
 T+8  │ Nginx        │ 응답 수신
      │               │ X-Upstream: 172.18.0.3:8080 헤더 추가
      │               │ Gzip 압축 (Content-Type: application/json)
      │               │ 접근 로그 기록 (upstream=tomcat1, response_time=0.003)
      │               │
 T+9  │ Nginx→브라우저│ TLS 암호화 후 응답 전송
      │               │ { "status": "UP", "host": "<컨테이너ID>" }
```

### 9.2 다음 요청은?

Round Robin이므로 **같은 클라이언트의 다음 요청**은 `tomcat2`로 전달된다.

```bash
$ curl -k https://localhost/health
→ { "status": "UP", "host": "69ee1fbd080e" }  ← 1번째: tomcat1 컨테이너

$ curl -k https://localhost/health
→ { "status": "UP", "host": "ef46a33ce234" }  ← 2번째: tomcat2 컨테이너

$ curl -k https://localhost/health
→ { "status": "UP", "host": "69ee1fbd080e" }  ← 3번째: 다시 tomcat1
```

`host` 필드에는 **Docker 컨테이너 ID**가 반환된다 (`InetAddress.getLocalHost().getHostName()` — Docker는 컨테이너 ID를 hostname으로 설정). 두 개의 서로 다른 ID가 교대로 나타나면 Round Robin 로드밸런싱이 정상 동작하는 것이다.

---

## 10. SSL/TLS와 PKI 구조

### 10.1 인증서 체계

```
┌─────────────────────────────────────┐
│  Middleware Root CA (자체 인증기관)   │
│  ─────────────────────────────────   │
│  Subject: CN=Middleware Root CA      │
│  Key: RSA 4096-bit                   │
│  Validity: 10년                      │
│  용도: 서버 인증서 서명               │
│  파일: ca.key (개인키), ca.crt (공개) │
└──────────────┬──────────────────────┘
               │ 서명
               ▼
┌─────────────────────────────────────┐
│  Server Certificate                  │
│  ─────────────────────────────────   │
│  Subject: CN=localhost               │
│  Key: RSA 2048-bit                   │
│  Validity: 1년 (365일)              │
│  SAN (Subject Alternative Names):   │
│    - localhost                        │
│    - nginx                           │
│    - *.middleware.local              │
│  파일: server.key, server.crt        │
└─────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Certificate Chain                   │
│  ─────────────────────────────────   │
│  server-chain.crt                    │
│  = server.crt + ca.crt (연결)        │
│  → Nginx가 이 파일을 클라이언트에 제공 │
└─────────────────────────────────────┘
```

### 10.2 TLS 핸드셰이크 과정

```
 클라이언트                              Nginx
     │                                     │
     │ ① ClientHello                       │
     │   - TLS 1.3 지원                    │
     │   - 지원 암호 스위트 목록             │
     │   - 랜덤 바이트                      │
     │ ──────────────────────────────────►  │
     │                                     │
     │ ② ServerHello                       │
     │   - TLS 1.3 선택                    │
     │   - ECDHE-RSA-AES256-GCM-SHA384    │
     │   - 서버 랜덤 바이트                 │
     │ ◄──────────────────────────────────  │
     │                                     │
     │ ③ Certificate                       │
     │   - server-chain.crt 전송           │
     │     (서버 인증서 + CA 인증서)         │
     │ ◄──────────────────────────────────  │
     │                                     │
     │ ④ 인증서 검증                        │
     │   - CA 서명 확인 (자체 서명이므로     │
     │     curl -k 또는 CA 등록 필요)       │
     │                                     │
     │ ⑤ Key Exchange (ECDHE)              │
     │   - 양측이 임시 키 쌍 생성           │
     │   - 공개키 교환                      │
     │   - Diffie-Hellman으로 세션 키 합의  │
     │ ◄─────────────────────────────────►  │
     │                                     │
     │ ⑥ Finished                          │
     │   - 이후 모든 통신은 대칭 키로 암호화 │
     │ ◄─────────────────────────────────►  │
     │                                     │
     │ ═══════ 암호화된 HTTP 통신 시작 ═════│
```

### 10.3 SSL 세션 캐시

```nginx
ssl_session_cache shared:SSL:10m;    # 워커 간 공유, 10MB
ssl_session_timeout 10m;             # 10분간 재사용
```

동일 클라이언트의 재접속 시 TLS 핸드셰이크를 생략하고, 캐시된 세션을 재사용하여 지연 시간을 줄인다.

---

## 11. 로드밸런싱 메커니즘

### 11.1 지원 알고리즘

#### Nginx OSS (오픈소스) 기본 제공

| 알고리즘 | 설정 방법 | 동작 방식 | 적합한 경우 |
|---------|----------|----------|------------|
| **Round Robin** (현재) | 기본값 (별도 설정 불필요) | 요청을 1:1로 교대 분산 | WAS 성능이 동일할 때 |
| **Weighted Round Robin** | `weight=3` / `weight=1` | 가중치 비율로 분산 | WAS 사양이 다를 때 |
| **IP Hash** | `ip_hash;` 추가 | 클라이언트 IP 해시로 고정 서버 | 세션 고정(Sticky Session)이 필요할 때 |
| **Least Connections** | `least_conn;` 추가 | 활성 연결이 적은 서버 우선 | 요청 처리 시간 편차가 클 때 |
| **Generic Hash** | `hash $request_uri consistent;` | 지정한 변수(URI, 쿠키 등)를 해시 | 캐시 서버 앞단, 특정 키 기반 라우팅 |
| **Random** | `random two least_conn;` | 랜덤으로 2개 선택 후 least_conn 적용 | 다수 서버에서 thundering herd 방지 |

> **Generic Hash**는 `$request_uri`, `$cookie_sessionid` 등 Nginx 변수를 자유롭게 지정할 수 있어 IP Hash보다 유연하다.
> `consistent` 키워드를 붙이면 **Consistent Hashing**이 적용되어, 서버 추가/제거 시에도 기존 매핑이 최소한으로 변경된다.

#### Nginx Plus (상용) 전용

| 알고리즘 | 설정 방법 | 동작 방식 | 적합한 경우 |
|---------|----------|----------|------------|
| **Least Time** | `least_time header\|last_byte;` | 응답시간 + 활성 연결 수를 복합 계산 | 성능 편차가 큰 이기종 서버 |
| **NTLM** | `ntlm;` | Windows NTLM 인증 연결 유지 | Active Directory 연동 환경 |

> 본 시스템은 Nginx OSS를 사용하므로 Least Time, NTLM은 사용할 수 없다.

### 11.2 현재 Round Robin 동작

```nginx
upstream was_backend {
    server tomcat1:8080 weight=1;    # 50% 트래픽
    server tomcat2:8080 weight=1;    # 50% 트래픽
}
```

```
요청 #1 → tomcat1
요청 #2 → tomcat2
요청 #3 → tomcat1
요청 #4 → tomcat2
  ...반복...
```

### 11.3 페일오버 메커니즘

```
정상 상태:
  요청 → [tomcat1] [tomcat2] 교대

tomcat2 다운:
  요청 → [tomcat1] [tomcat1] [tomcat1] ...
  Nginx가 tomcat2 연결 실패 감지 → 자동으로 tomcat1로만 전송
  access.log: upstream=172.18.0.3:8080 (tomcat1만 기록)

tomcat2 복구:
  Nginx가 다음 요청 시 tomcat2 재시도 → 성공 → 정상 교대 재개
```

Nginx는 `proxy_connect_timeout 10s` 내에 백엔드 연결이 실패하면 해당 서버를 **일시적으로 비활성화**하고, 주기적으로 재시도하여 복구를 감지한다.

---

## 12. 모니터링 구동 메커니즘

### 12.1 모니터링 데이터 흐름 전체도

```
┌──────────────── 데이터 수집원 ──────────────────┐
│                                                   │
│  [Tomcat1 JVM]                                   │
│    ├── Scouter Agent ──UDP/TCP──→ Scouter Server │
│    └── /actuator/prometheus ──┐                   │
│                                │                   │
│  [Tomcat2 JVM]                │                   │
│    ├── Scouter Agent ──UDP/TCP──→ Scouter Server │
│    └── /actuator/prometheus ──┤                   │
│                                │ HTTP Pull        │
│  [Node Exporter]              │ (15초 간격)       │
│    └── :9100/metrics ─────────┤                   │
│                                │                   │
│  [Nginx Exporter]             │                   │
│    └── :9113/metrics ─────────┤                   │
│                                ▼                   │
│                        ┌──────────────┐           │
│                        │  Prometheus  │           │
│                        │  (시계열 DB)  │           │
│                        │ 보존: 15일    │           │
│                        └──────┬───────┘           │
│                               │ PromQL 쿼리       │
│                               ▼                    │
│                        ┌──────────────┐           │
│                        │   Grafana    │           │
│                        │  (대시보드)   │           │
│                        │  8개 패널     │           │
│                        └──────────────┘           │
└───────────────────────────────────────────────────┘
```

### 12.2 Prometheus Pull 모델

Prometheus는 **Pull 모델**을 사용한다. 대상 서비스가 메트릭을 Push하는 것이 아니라, Prometheus가 주기적으로 HTTP GET 요청을 보내 메트릭을 **끌어온다(Scrape)**.

```yaml
# prometheus.yml
global:
  scrape_interval: 15s       # 15초마다 스크래핑
  evaluation_interval: 15s   # 15초마다 룰 평가

scrape_configs:
  - job_name: "tomcat1"
    metrics_path: "/actuator/prometheus"      # Spring Actuator 메트릭 경로
    static_configs:
      - targets: ["tomcat1:8080"]
```

**스크래핑 사이클:**
```
T=0s    Prometheus GET http://tomcat1:8080/actuator/prometheus
          → 200 OK (Micrometer 형식의 메트릭 텍스트)
          → TSDB에 저장

T=15s   Prometheus GET http://tomcat1:8080/actuator/prometheus
          → 새 데이터 포인트 추가

T=30s   ... 반복
```

### 12.3 수집되는 메트릭 종류

| 소스 | 수집 메트릭 | 활용 |
|------|-----------|------|
| **Node Exporter** | CPU 사용률, 메모리 사용량, 디스크 I/O, 네트워크 트래픽 | 서버 리소스 모니터링 |
| **Nginx Exporter** | 활성 연결 수, 초당 요청 수, 연결 상태(accepted/handled) | WEB 계층 트래픽 모니터링 |
| **Tomcat Actuator** | JVM Heap 사용량, GC 횟수/시간, 스레드 수, HTTP 요청 카운트 | WAS 계층 상태 모니터링 |
| **Scouter Agent** | TPS, 트랜잭션 응답시간 분포(XLog), SQL 쿼리 시간, 에러율 | 애플리케이션 성능 분석 |

### 12.4 Grafana 대시보드 자동 프로비저닝

Grafana는 기동 시 프로비저닝 설정을 자동으로 로드한다.

```
Grafana 컨테이너 시작
  │
  ├── /etc/grafana/provisioning/datasources/datasource.yml 로드
  │     → Prometheus (http://prometheus:9090) 데이터소스 등록
  │
  └── /etc/grafana/provisioning/dashboards/dashboard.yml 로드
        → /var/lib/grafana/dashboards/ 경로에서 JSON 대시보드 로드
        → middleware-overview.json (8개 패널) 자동 생성
```

**8개 패널 구성:**

| # | 패널 이름 | 데이터 소스 | PromQL |
|---|----------|-----------|--------|
| 1 | CPU 사용률 (%) | node-exporter | `node_cpu_seconds_total` |
| 2 | 메모리 사용률 (%) | node-exporter | `node_memory_*_bytes` |
| 3 | 디스크 사용률 (%) | node-exporter | `node_filesystem_*_bytes` |
| 4 | 네트워크 I/O (bytes/s) | node-exporter | `node_network_*_bytes` |
| 5 | Nginx 활성 연결 | nginx-exporter | `nginx_connections_active` |
| 6 | Nginx 초당 요청 | nginx-exporter | `rate(nginx_http_requests_total)` |
| 7 | JVM Heap - Tomcat1 | tomcat1 actuator | `jvm_memory_used_bytes` |
| 8 | JVM Heap - Tomcat2 | tomcat2 actuator | `jvm_memory_used_bytes` |

### 12.5 APM (Scouter) vs 메트릭 모니터링 (Prometheus) 비교

```
┌─────────────────────────────────────────────────────────────┐
│                    모니터링 이원화 전략                        │
│                                                               │
│  Prometheus + Grafana          │  Scouter                    │
│  ─────────────────────         │  ───────                    │
│  관점: 인프라/시스템             │  관점: 애플리케이션           │
│  방식: Pull (HTTP 스크래핑)     │  방식: Push (Agent → Server) │
│  데이터: 시계열 숫자 메트릭     │  데이터: 개별 트랜잭션 프로파일│
│  질문: "CPU가 몇 %인가?"      │  질문: "이 API가 왜 느린가?" │
│  시각화: Grafana 대시보드       │  시각화: Scouter Client (GUI)│
│  보존: 15일                    │  보존: 7일 (로그 로테이션)    │
│                                │                              │
│  장애 감지:                     │  장애 원인 분석:              │
│  "메모리가 90% 넘었다"         │  "OrderController.save()에서 │
│  "요청이 급증했다"             │   SQL이 3초 걸렸다"          │
└─────────────────────────────────────────────────────────────┘
```

---

## 13. 빌드와 배포 파이프라인

### 13.1 Multi-stage Docker Build

```
┌────────────── Stage 1: Build ──────────────┐
│  Base: maven:3.9-eclipse-temurin-17         │
│                                              │
│  ① COPY pom.xml .                           │
│  ② mvn dependency:go-offline                │
│     → Maven 의존성 캐시 레이어 생성          │
│     → pom.xml이 변경되지 않으면 캐시 히트     │
│                                              │
│  ③ COPY src ./src                           │
│  ④ mvn package -DskipTests                  │
│     → app.war 생성                           │
│                                              │
│  산출물: /app/target/app.war                 │
└──────────────────────────────────────────────┘
                    │
                    │ COPY --from=build
                    ▼
┌────────────── Stage 2: Runtime ────────────┐
│  Base: tomcat:10.1-jdk17                    │
│                                              │
│  ① Scouter Agent 2.20.0 다운로드/설치       │
│     → /opt/scouter/agent.java/              │
│                                              │
│  ② 기본 webapps 삭제                        │
│     → rm -rf /usr/local/tomcat/webapps/*    │
│                                              │
│  ③ app.war → ROOT.war 배치                  │
│     → /usr/local/tomcat/webapps/ROOT.war    │
│                                              │
│  CMD: catalina.sh run                        │
│                                              │
│  최종 이미지 크기: ~400MB                    │
│  (Maven, 소스코드는 포함되지 않음)           │
└──────────────────────────────────────────────┘
```

**Multi-stage Build의 장점:**
- Stage 1의 Maven, 소스코드가 최종 이미지에 포함되지 않아 **이미지 크기 절감**
- 의존성 다운로드 레이어가 캐시되어 소스코드만 변경 시 **빌드 시간 단축**

### 13.2 운영 스크립트

| 스크립트 | 용도 | 실행 시점 |
|---------|------|---------|
| `start.sh` | 빌드 + docker-compose up + 준비 확인 | 수동 / CI 파이프라인 |
| `stop.sh` | docker-compose down (Graceful Shutdown) | 유지보수 시 |
| `status.sh` | docker-compose ps 상태 요약 | 수동 모니터링 |
| `health-check.sh` | 전체 서비스 헬스 감사 (컨테이너, URL, SSL) | Cron: 매일 09:00 |
| `log-analyzer.sh` | Nginx/Tomcat 로그 분석, 에러 패턴 추출 | 수동 / Cron |
| `backup.sh` | MySQL 덤프 + 설정 파일 백업 | Cron: 매일 02:00 |
| `generate-certs.sh` | 자체 서명 CA + 서버 인증서 최초 생성 | 초기 구축 시 1회 |
| `cert-renew.sh` | 서버 인증서 갱신 (만료 전) | Cron: 월 1회 |
| `load-test.sh` | 부하 테스트 (6개 시나리오) | 수동 / 성능 검증 시 |

---

## 14. 부하 테스트

### 14.1 테스트 도구

`scripts/load-test.sh`는 curl + xargs 기반의 부하 테스트 도구로, 별도 설치 없이 사용 가능하다.

```bash
./scripts/load-test.sh [시나리오] [요청수] [동시성]
```

### 14.2 6가지 테스트 시나리오

#### 시나리오 1: health — 단일 엔드포인트 부하

```bash
./scripts/load-test.sh health 1000 20
```

```
목적: 가장 가벼운 API(/health)로 순수 처리 성능 측정
방식: /health에 1000회 요청, 동시 20개
측정: 평균/최소/최대/P95 응답시간, 에러율, 로드밸런싱 분포

기대 결과:
  평균 응답시간 < 0.05초
  에러율 0%
  tomcat1:tomcat2 = 약 50:50 분배
```

#### 시나리오 2: mixed — 혼합 엔드포인트 부하

```bash
./scripts/load-test.sh mixed 500 10
```

```
목적: 실제 트래픽 패턴 시뮬레이션 (다양한 API 동시 호출)
대상 엔드포인트:
  ├── /              (앱 정보)
  ├── /health        (헬스체크)
  ├── /info          (시스템 정보 — Runtime 메서드 호출로 약간 무거움)
  ├── /actuator/health  (Spring Actuator 헬스)
  └── /actuator/metrics (Micrometer 메트릭 목록)

측정: 엔드포인트별 평균 응답시간 비교
  → /info가 /health보다 느리면 Runtime 메서드 오버헤드
  → /actuator/metrics가 가장 느리면 메트릭 수집 비용 확인
```

#### 시나리오 3: slow — 점진적 부하 증가 (Ramp-up)

```bash
./scripts/load-test.sh slow
```

```
목적: "동시 접속자가 늘어나면 성능이 어떻게 변하는가?"
방식: 동시성을 단계적으로 증가
  C=1  → C=5  → C=10 → C=20 → C=50

┌───────────┬──────────┬──────────┬──────────┐
│ 동시성     │ 평균(초)  │ P95(초)   │ 에러     │
├───────────┼──────────┼──────────┼──────────┤
│ C=1       │ 0.005    │ 0.007    │ 0        │ ← 기준선
│ C=5       │ 0.008    │ 0.012    │ 0        │ ← 미미한 증가
│ C=10      │ 0.015    │ 0.025    │ 0        │ ← 선형 증가면 정상
│ C=20      │ 0.030    │ 0.060    │ 0        │
│ C=50      │ 0.080    │ 0.150    │ 0        │ ← 여기서 급증하면 병목
└───────────┴──────────┴──────────┴──────────┘

해석:
  선형 증가 → 정상 (리소스 경합만 발생)
  지수 증가 → 병목 존재 (스레드 풀, DB 커넥션 풀, GC 등)
  에러 발생 → 한계 도달 (maxThreads 초과, acceptCount 초과)
```

#### 시나리오 4: burst — 순간 폭주

```bash
./scripts/load-test.sh burst
```

```
목적: 짧은 시간에 대량 요청(300회, 동시 100)으로 시스템 한계 확인
방식:
  Phase 1: 정상 베이스라인 측정 (50회, 동시 5)
  Phase 2: 순간 폭주 (300회, 동시 100)
  Phase 3: 폭주 후 회복 확인 (50회, 동시 5)

확인 포인트:
  ├── Phase 2에서 에러(503) 발생 여부
  │   → Tomcat maxThreads=200, acceptCount=100
  │   → 동시 100이면 200 스레드 내이므로 정상 처리 예상
  │
  └── Phase 3의 응답시간이 Phase 1과 비슷한가?
      → 비슷하면: 시스템이 정상 회복됨
      → 느리면: GC 폭풍, 커넥션 풀 고갈 등 후유증 존재
```

#### 시나리오 5: failover — WAS 페일오버

```bash
./scripts/load-test.sh failover
```

```
목적: WAS 1대 장애 시 서비스 연속성 확인
방식:
  Phase 1: 양쪽 WAS 정상 → 분배 비율 확인 (50:50)
  Phase 2: docker stop mw-tomcat2
  Phase 3: 1대만으로 요청 처리 → 에러 0건 확인
  Phase 4: docker start mw-tomcat2 → 15초 대기
  Phase 5: 복구 후 분배 비율 확인 (50:50 복귀)

확인 포인트:
  ├── Phase 3에서 에러 0건이면 페일오버 성공
  └── Phase 5에서 50:50 복귀하면 자동 복구 성공
```

#### 시나리오 6: dashboard — 모든 그래프를 움직여라

```bash
./scripts/load-test.sh dashboard
```

```
목적: Scouter + Grafana의 모든 패널이 동시에 반응하는 종합 부하
소요: 약 2분 30초
준비: 실행 전 Scouter Client + Grafana(localhost:3000) 화면을 열어둘 것

7개 Phase로 구성:

  Phase 1 (20초) 워밍업 — 기본 트래픽
    → Scouter XLog에 점 생성 시작
    → Grafana Nginx Requests/sec 상승

  Phase 2 (20초) 혼합 엔드포인트 — 6개 API 동시 호출
    → 다양한 응답 크기로 Network I/O 변화
    → Scouter XLog에 응답시간 편차가 보이는 점 분포

  Phase 3 (40초) 동시성 계단 — C=5 → 20 → 50 → 100
    → Grafana Nginx Active Connections 계단식 증가
    → Scouter Active Service EQ 막대 커짐
    → Scouter Elapsed Time 점진 상승

  Phase 4 (짧음) 순간 폭주 — 500회 동시 100
    → Grafana CPU Usage 스파이크
    → Scouter TPS 최고점 도달
    → Scouter Heap Used 급등

  Phase 5 (15초) 대용량 응답 — /actuator/prometheus 집중
    → /actuator/prometheus는 수천 줄의 메트릭 텍스트 반환
    → Grafana Network I/O TX(송신) 급등

  Phase 6 (20초) 휴식 — GC 관찰
    → 트래픽 완전 중단
    → Scouter Heap Used 톱니 하락 (GC 회수)
    → Scouter TPS → 0
    → Grafana JVM Heap 하락

  Phase 7 (15초) 재부하 — 회복 확인
    → 모든 그래프 다시 활성화
    → 응답시간이 Phase 1과 비슷하면 시스템 정상
```

각 Phase에서 어떤 그래프가 반응하는지:

```
                Phase1 Phase2 Phase3 Phase4 Phase5 Phase6 Phase7
                워밍업  혼합   계단   폭주   대용량  휴식   재부하
  ─────────────────────────────────────────────────────────────
  Scouter:
    XLog          ●      ●      ●      ●      ●      ·      ●
    TPS           ▲      ▲      ▲▲     ▲▲▲    ▲▲     ·      ▲▲
    Heap Used     ─      ─      ↗      ↗↗     ↗      ↘↘     ↗
    Elapsed       ─      ─      ↗↗     ↗↗↗    ↗      ·      ─
    Active EQ     │      │      ██     ████   ██     ·      ██
    CPU           ─      ─      ↗      ↗↗↗    ↗      ↘      ↗
  ─────────────────────────────────────────────────────────────
  Grafana:
    CPU Usage     ─      ─      ↗      ↗↗↗    ↗      ↘      ↗
    Memory        ─      ─      ─      ↗      ─      ─      ─
    Network I/O   ↗      ↗↗     ↗↗     ↗↗     ↗↗↗    ↘      ↗↗
    Nginx Req/s   ▲      ▲      ▲▲     ▲▲▲    ▲▲     ·      ▲▲
    Nginx Conn    │      │      ↗↗↗    ↗↗     ↗      ↘      ↗
    JVM Heap T1   ─      ─      ↗      ↗↗     ↗      ↘↘     ↗
    JVM Heap T2   ─      ─      ↗      ↗↗     ↗      ↘↘     ↗
  ─────────────────────────────────────────────────────────────
  ●=점 생성  ▲=상승  ↗=증가  ↘=감소  ─=평탄  ·=없음  █=활성
```

### 14.3 전체 시나리오 한 번에 실행

```bash
./scripts/load-test.sh all
```

5개 시나리오를 순차 실행하며, Scouter XLog/TPS 그래프에서 부하 패턴을 실시간으로 관찰할 수 있다.

### 14.4 모니터링과 함께 보기

부하 테스트 중 다음 화면을 함께 관찰하면 시스템 동작을 입체적으로 이해할 수 있다.

```
┌──────────────────────────────────────────────────────────────┐
│  부하 테스트 실행 중 동시에 관찰할 것                            │
│                                                                │
│  Scouter Client                                               │
│  ├── XLog: 점이 몰리는 구간 = 부하 구간                        │
│  ├── TPS: 초당 처리량이 얼마나 올라가는지                       │
│  ├── Elapsed Time: 응답시간이 부하와 함께 증가하는지             │
│  └── Heap Used: GC가 제때 메모리를 회수하는지                   │
│                                                                │
│  Grafana (http://localhost:3000)                              │
│  ├── Nginx Requests/sec: 부하 주입량 확인                      │
│  ├── Nginx Active Connections: 동시 연결 수                    │
│  ├── CPU Usage: 부하 시 CPU 변화                               │
│  └── JVM Heap: 메모리 압력 확인                                │
│                                                                │
│  Prometheus (http://localhost:9090)                            │
│  └── PromQL 직접 조회:                                         │
│      rate(http_server_requests_seconds_count[1m])             │
│      = 분당 요청 처리율                                         │
└──────────────────────────────────────────────────────────────┘
```

---

## 15. 데이터 영속성과 볼륨 관리

Docker 컨테이너는 삭제되면 내부 데이터가 사라진다. **Named Volume**을 사용하여 중요 데이터를 호스트에 영속 저장한다.

```
┌──────────────── Docker Volumes ────────────────┐
│                                                  │
│  mysql_data        → /var/lib/mysql              │
│  │                   (DB 데이터 — 가장 중요!)     │
│  │                                               │
│  tomcat1_logs      → /usr/local/tomcat/logs      │
│  tomcat2_logs      → /usr/local/tomcat/logs      │
│  │                   (WAS 접근/에러 로그)          │
│  │                                               │
│  nginx_logs        → /var/log/nginx              │
│  │                   (WEB 접근/에러 로그)          │
│  │                                               │
│  scouter_data      → /opt/scouter/server/database│
│  │                   (APM 수집 데이터)             │
│  │                                               │
│  prometheus_data   → /prometheus                 │
│  │                   (시계열 메트릭 데이터)         │
│  │                                               │
│  grafana_data      → /var/lib/grafana            │
│  │                   (대시보드 설정, 사용자 데이터) │
│  │                                               │
│  keycloak_data     → /opt/keycloak/data          │
│                      (Realm, 사용자, 세션 데이터)  │
└──────────────────────────────────────────────────┘
```

**볼륨 vs 바인드 마운트 사용 구분:**

| 방식 | 사용 위치 | 이유 |
|------|---------|------|
| **Named Volume** | mysql_data, 각종 logs, grafana_data 등 | 런타임에 생성되는 데이터 — Docker가 관리 |
| **Bind Mount (:ro)** | nginx.conf, server.xml, prometheus.yml 등 | 설정 파일 — 호스트에서 편집, 컨테이너는 읽기 전용 |

---

## 16. 장애 감지와 자동 복구

### 16.1 헬스체크 체계

```
┌─────────── 헬스체크 레이어 ───────────────────────────────┐
│                                                             │
│  Layer 1: Docker Healthcheck (컨테이너 레벨)               │
│  ──────────────────────────────────────                     │
│  MySQL:  mysqladmin ping (10초 간격, 5초 타임아웃, 5회)    │
│  결과: healthy / unhealthy 상태 → depends_on 연동          │
│                                                             │
│  Layer 2: Nginx 프록시 헬스체크 (WAS 레벨)                 │
│  ──────────────────────────────────────                     │
│  proxy_connect_timeout: 10초                                │
│  → 연결 실패 시 해당 WAS를 일시적으로 비활성화              │
│  → 주기적 재시도로 복구 자동 감지                           │
│                                                             │
│  Layer 3: Application 헬스체크 (API 레벨)                  │
│  ──────────────────────────────────────                     │
│  GET /health → {"status": "UP"}                            │
│  GET /actuator/health → Spring Actuator 상세 헬스            │
│  → health-check.sh 스크립트가 주기적으로 확인               │
│                                                             │
│  Layer 4: Prometheus 메트릭 기반 모니터링                   │
│  ──────────────────────────────────────                     │
│  up{job="tomcat1"} == 0 → 스크래핑 실패 감지               │
│  → Grafana 알림 설정 가능                                   │
│                                                             │
│  Layer 5: Scouter APM (트랜잭션 레벨)                      │
│  ──────────────────────────────────────                     │
│  obj_deadtime=30000 (30초)                                  │
│  → 30초간 데이터 수신 없으면 Dead 객체로 표시               │
└─────────────────────────────────────────────────────────────┘
```

### 16.2 장애 시나리오별 시스템 동작

**시나리오 1: WAS 1대 다운**
```
tomcat2 컨테이너 중지
  → Nginx가 tomcat2:8080 연결 시도 → 10초 내 실패
  → tomcat2를 upstream에서 일시 제외
  → 모든 트래픽이 tomcat1로 집중
  → 서비스 중단 없음 (이중화의 목적)
  → tomcat2 재시작 시 자동 복귀
```

**시나리오 2: MySQL 다운**
```
MySQL 컨테이너 중지
  → Tomcat의 HikariCP가 연결 풀 에러 감지
  → DB 관련 요청 500 에러 반환
  → /health 엔드포인트는 정상 응답 (DB 비의존)
  → MySQL 재시작 → HikariCP가 자동 재연결
```

**시나리오 3: Nginx 다운**
```
Nginx 컨테이너 중지
  → 외부에서 접근 불가 (443 포트 바인딩 해제)
  → 전체 서비스 중단
  → Nginx는 단일 장애점(SPOF) — 실무에서는 Keepalived/HAProxy로 이중화
```

---

## 부록: 빠른 참조

### 서비스 접근 URL

| 서비스 | URL | 인증 정보 |
|--------|-----|----------|
| 애플리케이션 | https://localhost/ | 불필요 |
| SSO 로그인 테스트 | https://localhost/secured/profile | testuser / test123 |
| Keycloak 관리 콘솔 | http://localhost:8080 | admin / admin |
| Grafana 대시보드 | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | 불필요 |
| Scouter Server | localhost:6100 (Scouter Client) | 불필요 |

### 핵심 설정 파일 위치

| 설정 대상 | 파일 경로 |
|----------|----------|
| 전체 오케스트레이션 | `docker-compose.yml` |
| Nginx 전역 | `configs/nginx/nginx.conf` |
| Nginx 라우팅/SSL | `configs/nginx/conf.d/default.conf` |
| Tomcat 커넥터 | `configs/tomcat/tomcat{1,2}/server.xml` |
| Spring Boot 설정 | `app/src/main/resources/application.properties` |
| Spring Security | `app/src/main/java/.../config/SecurityConfig.java` |
| Scouter Agent | `configs/scouter/agent.conf` |
| Scouter Server | `configs/scouter/server.conf` |
| Prometheus | `configs/prometheus/prometheus.yml` |
| Grafana 데이터소스 | `configs/grafana/provisioning/datasources/datasource.yml` |
| Grafana 대시보드 | `configs/grafana/dashboards/middleware-overview.json` |
| Keycloak Realm | `configs/keycloak/realm-export.json` |
| SSL 인증서 | `configs/nginx/ssl/` |

### 주요 성능 튜닝 파라미터

| 컴포넌트 | 파라미터 | 현재 값 | 의미 |
|---------|---------|--------|------|
| Nginx | worker_processes | auto | CPU 코어 수만큼 워커 |
| Nginx | worker_connections | 1024 | 워커당 최대 동시 연결 |
| Nginx | keepalive_timeout | 65s | Keep-Alive 유지 시간 |
| Tomcat | maxThreads | 200 | 최대 요청 처리 스레드 |
| Tomcat | acceptCount | 100 | 스레드 풀 가득 찰 때 대기 큐 |
| Tomcat | maxConnections | 8192 | 최대 동시 TCP 연결 |
| JVM | -Xms / -Xmx | 256m / 512m | Heap 초기/최대 크기 |
| Prometheus | scrape_interval | 15s | 메트릭 수집 주기 |
| Prometheus | retention.time | 15d | 데이터 보존 기간 |

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [사용자 가이드](user-guide.md) | 설치 및 실행 가이드 |
| [인프라 설계](infrastructure-design.md) | 인프라 설계 상세 |
| [보안 심층 분석](security-deep-dive.md) | 보안 아키텍처 상세 |
| [모니터링 메트릭 가이드](monitoring-metrics.md) | 모니터링 구성 상세 |
| [성능 튜닝 가이드](performance-tuning.md) | 성능 최적화 가이드 |
