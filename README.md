# Linux 기반 WEB/WAS 미들웨어 환경 구축 및 APM 모니터링 시스템

> 미들웨어(M/W) 기술엔지니어 직무 대비 실습 프로젝트
>
> `docker-compose up -d` 한 줄로 **WEB/WAS 이중화 + APM 모니터링 + SSO 인증 + SSL 보안** 전체 인프라를 구동할 수 있다.

---

## 프로젝트 소개

실제 기업 운영 환경과 동일한 **WEB/WAS 미들웨어 아키텍처**를 Docker 기반으로 구축한 프로젝트이다.

클라이언트 요청이 **Nginx(WEB)** → **Tomcat(WAS) 이중화** → **MySQL(DB)** 로 흐르는 3-Tier 구조를 구현하고, **Scouter APM**으로 WAS 성능을 실시간 모니터링하며, **Keycloak**으로 SSO 인증, **자체 CA 인증서**로 HTTPS 보안 통신까지 적용한 풀스택 미들웨어 환경이다.

---

## 시스템 아키텍처

```
[클라이언트 브라우저]
        |  HTTPS (SSL/TLS)
        v
[Nginx - 리버스 프록시 + 로드밸런싱]
       / \
      v   v
[Tomcat #1]  [Tomcat #2]  ← WAS 이중화 (Round Robin)
      \   /
       v v
[MySQL DB] + [Scouter APM Server] + [Keycloak SSO]
                    |
        [Grafana + Prometheus 대시보드]
```

---

## 사용 오픈소스 기술 스택

### WEB / WAS / DB

| 기술 | 역할 | 설명 |
|:----:|------|------|
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/nginx/nginx-original.svg" alt="Nginx" width="80"> <br> **Nginx 1.24** | **리버스 프록시 + 로드밸런서** | 클라이언트의 HTTPS 요청을 받아 SSL 종료(Termination) 처리 후, 백엔드 Tomcat 2대에 **Round Robin** 방식으로 트래픽을 분산한다. `/stub_status` 엔드포인트로 활성 연결 수, 요청 처리량 등의 메트릭을 Prometheus에 노출한다. |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/tomcat/tomcat-original.svg" alt="Tomcat" width="80"> <br> **Apache Tomcat 10** | **WAS (2대 이중화)** | Spring Boot 애플리케이션을 구동하는 서블릿 컨테이너이다. 2대를 이중화하여 한 대가 장애 시에도 서비스가 중단되지 않는 **고가용성(HA)** 환경을 구현한다. 각 인스턴스에 Scouter Java Agent를 부착하여 TPS, 응답시간, JVM 힙 메모리를 실시간 수집한다. |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/mysql/mysql-original-wordmark.svg" alt="MySQL" width="80"> <br> **MySQL 8.0** | **관계형 데이터베이스** | 애플리케이션 데이터를 저장하는 RDBMS이다. Docker Volume으로 데이터 영속성을 보장하며, Health Check를 통해 DB가 준비된 후에만 WAS가 기동되도록 의존성을 관리한다. |

### APM / 모니터링

| 기술 | 역할 | 설명 |
|:----:|------|------|
| <img src="https://avatars.githubusercontent.com/u/13431280?s=200&v=4" alt="Scouter" width="80"> <br> **Scouter** | **APM (Application Performance Monitoring)** | **Jennifer의 오픈소스 대안**이다. Java Agent(`-javaagent`) 방식으로 Tomcat에 부착되어 **TPS, 응답시간, Active Service, JVM 힙/GC** 등을 실시간으로 수집한다. Scouter Server(6100 포트)가 Agent 데이터를 수집·저장하고, Scouter Client에서 XLog 차트로 시각화한다. |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/prometheus/prometheus-original.svg" alt="Prometheus" width="80"> <br> **Prometheus** | **메트릭 수집 및 시계열 DB** | Pull 방식으로 각 Exporter(Node Exporter, Nginx Exporter)에서 **CPU, 메모리, 디스크, 네트워크, HTTP 요청 수** 등의 메트릭을 15초 간격으로 스크래핑한다. 15일간 데이터를 보관하며 PromQL로 조회할 수 있다. |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/grafana/grafana-original.svg" alt="Grafana" width="80"> <br> **Grafana** | **모니터링 대시보드** | Prometheus를 데이터소스로 연결하여 **서버 리소스, Nginx 트래픽, WAS 상태**를 시각화하는 대시보드를 제공한다. 사전 구성된 대시보드(JSON)가 프로비저닝되어 구동 즉시 모니터링이 가능하다. |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/prometheus/prometheus-original.svg" alt="Node Exporter" width="80"> <br> **Node Exporter** | **서버 리소스 메트릭 수집** | 호스트 시스템의 CPU 사용률, 메모리, 디스크 I/O, 네트워크 트래픽 등 OS 레벨 메트릭을 Prometheus 형식으로 노출한다. |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/nginx/nginx-original.svg" alt="Nginx Exporter" width="80"> <br> **Nginx Exporter** | **Nginx 메트릭 수집** | Nginx의 `stub_status` 모듈에서 활성 연결 수, 요청 처리량, 응답 코드별 카운트를 가져와 Prometheus에 노출한다. |

### 인증 / 보안

| 기술 | 역할 | 설명 |
|:----:|------|------|
| <img src="https://www.keycloak.org/resources/images/logo.svg" alt="Keycloak" width="80"> <br> **Keycloak 24.0** | **SSO / 통합 인증 서버** | **OpenID Connect(OIDC)** 프로토콜 기반의 싱글 사인온(SSO) 서버이다. `middleware-realm`을 사전 구성하여 사용자 인증·인가를 중앙에서 관리한다. Spring Security와 연동하여 `/secured/**` 경로에 접근 시 Keycloak 로그인 페이지로 리다이렉트된다. |
| <img src="https://raw.githubusercontent.com/openssl/web/master/img/openssl.svg" alt="OpenSSL" width="80"> <br> **OpenSSL (자체 CA)** | **SSL/TLS 인증서 발급** | 자체 CA(Certificate Authority)를 구축하여 서버 인증서를 발급한다. Nginx에서 HTTPS(443)를 제공하며, 인증서 체인(`server-chain.crt`)으로 클라이언트-서버 간 암호화 통신을 보장한다. |

### 애플리케이션 / 인프라

| 기술 | 역할 | 설명 |
|:----:|------|------|
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/spring/spring-original.svg" alt="Spring Boot" width="80"> <br> **Spring Boot 3.x** | **백엔드 애플리케이션** | Tomcat 위에서 구동되는 REST API 애플리케이션이다. Health Check 엔드포인트(`/health`, `/api/health`), Actuator 메트릭, Keycloak 연동 보안 컨트롤러를 포함한다. |
| <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/docker/docker-original.svg" alt="Docker" width="80"> <br> **Docker Compose** | **컨테이너 오케스트레이션** | 10개 서비스(Nginx, Tomcat×2, MySQL, Keycloak, Scouter, Prometheus, Grafana, Node Exporter, Nginx Exporter)를 **단일 YAML 파일**로 정의하여 `docker-compose up -d` 한 줄로 전체 환경을 구동한다. |

---

## 데모 실행 방법

### 1. 전체 환경 구동

```bash
# 클론
git clone https://github.com/iamywl/Middleware_Hello.git
cd Middleware_Hello

# 전체 서비스 구동 (10개 컨테이너)
docker-compose up -d

# 구동 상태 확인
docker-compose ps
```

### 2. 서비스 접속

| 서비스 | URL | 계정 |
|--------|-----|------|
| **WEB (Nginx)** | `https://localhost` | - |
| **Grafana 대시보드** | `http://localhost:3000` | admin / admin |
| **Keycloak SSO** | `http://localhost:8080` | admin / admin |
| **Prometheus** | `http://localhost:9090` | - |
| **Scouter Server** | `localhost:6100` (Scouter Client 연결) | - |

### 3. 데모 시나리오

```bash
# ① 로드밸런싱 확인 - 요청마다 Tomcat #1, #2가 번갈아 응답
curl -k https://localhost/api/health
curl -k https://localhost/api/health

# ② Health Check - 전체 시스템 상태 점검
./scripts/health-check.sh

# ③ Grafana에서 대시보드 확인
#    → http://localhost:3000 접속 → Middleware Overview 대시보드

# ④ SSO 테스트 - Keycloak 로그인 페이지로 리다이렉트 확인
curl -k https://localhost/secured/profile

# ⑤ 로그 분석
./scripts/log-analyzer.sh
```

### 4. 환경 종료

```bash
docker-compose down        # 컨테이너 종료
docker-compose down -v     # 컨테이너 + 볼륨 데이터 삭제
```

---

## 프로젝트 구조

```
middle_ware/
├── docker-compose.yml          # 전체 환경 원클릭 구동 (10개 서비스)
├── configs/
│   ├── nginx/                  # Nginx 리버스 프록시 + SSL 설정
│   ├── tomcat/                 # Tomcat #1, #2 server.xml
│   ├── scouter/                # Scouter Server/Agent 설정
│   ├── keycloak/               # Realm 설정 (OIDC)
│   ├── prometheus/             # 메트릭 수집 대상 설정
│   └── grafana/                # 대시보드 JSON + 프로비저닝
├── app/                        # Spring Boot 샘플 애플리케이션
├── scripts/                    # 운영 자동화 스크립트 (9종)
│   ├── start.sh / stop.sh      # 서비스 시작/종료
│   ├── health-check.sh         # 일일 서버 점검
│   ├── log-analyzer.sh         # 로그 분석
│   ├── backup.sh               # 백업
│   ├── cert-renew.sh           # 인증서 갱신
│   ├── generate-certs.sh       # SSL 인증서 생성
│   ├── load-test.sh            # 부하 테스트
│   └── status.sh               # 상태 확인
└── docs/                       # 기술 문서
```

---

## APM: Scouter vs Jennifer

본 프로젝트에서는 APM으로 **Scouter**를 사용한다. Jennifer는 상용(유료) 제품이므로 사이드 프로젝트에서 사용할 수 없어, 같은 계열의 오픈소스인 Scouter로 대체하였다.

| 항목 | Jennifer (상용) | Scouter (본 프로젝트) |
|------|-----------------|----------------------|
| 라이선스 | 상용 (유료) | 오픈소스 (무료) |
| 개발 배경 | 제니퍼소프트 | 제니퍼소프트 출신 개발자 (LG CNS) |
| 핵심 기능 | TPS, 응답시간, JVM 모니터링 | 동일 |
| Agent 방식 | Java Agent (javaagent) | 동일 |
| 실시간 대시보드 | O | O |
| 힙 덤프/쓰레드 분석 | O | O |

> Scouter는 Jennifer와 동일한 Java Agent 기반 APM으로, TPS/응답시간/JVM 힙/GC 모니터링 등 핵심 기능이 같다.
> 채용공고의 "Jennifer 기반 시스템 기술지원" 역량을 이 프로젝트 경험으로 어필할 수 있다.

---

## 문서 가이드

### 처음 시작하는 분 (순서대로 읽기)

| 순서 | 문서 | 목적 | 소요 시간 |
|:----:|------|------|:---------:|
| 1 | **[사용자 가이드](docs/user-guide.md)** | 전체 환경 구동 및 각 서비스 동작 확인 | 30분 |
| 2 | [아키텍처 문서](docs/architecture.md) | 시스템 전체 구성과 데이터 흐름 이해 | 15분 |
| 3 | [Scouter APM 가이드](docs/scouter-guide.md) | Scouter Client 설치 → XLog/TPS/Heap 실습 | 30분 |
| 4 | [모니터링 지표 가이드](docs/monitoring-metrics.md) | Prometheus/Grafana에서 PromQL 쿼리 실습 | 40분 |

### 심화 학습 (주제별 선택)

| 주제 | 문서 | 핵심 내용 |
|------|------|-----------|
| **성능** | [성능 튜닝 가이드](docs/performance-tuning.md) | Nginx worker, Tomcat maxThreads, JVM GC 튜닝, MySQL 최적화, ab/wrk 벤치마크 |
| **장애** | [장애 대응 가이드](docs/incident-response.md) | OOM Kill, GC Storm, Connection Pool 고갈, 502/504 등 10개 시나리오별 원인→대응→예방 |
| **보안** | [보안 심화 가이드](docs/security-deep-dive.md) | TLS 핸드셰이크 과정, OIDC/JWT 토큰 플로우, OWASP Top 10, Docker 보안 |
| **인프라** | [인프라 설계 심화 가이드](docs/infrastructure-design.md) | LB 알고리즘 비교, Blue-Green/Canary 배포, HA 설계, 용량 계획, DR |

### 참고 문서

| 문서 | 설명 |
|------|------|
| [개발계획서](개발계획서.md) | 프로젝트 상세 개발 계획 및 일정 |
| [트러블슈팅](docs/troubleshooting.md) | 구축 중 만난 장애 시나리오별 대응 내역 |
| [테스트 보고서](docs/test-report.md) | 전체 26개 항목 테스트 결과 |

### 면접 대비 추천 학습 경로

```
[1주차] 환경 구축 + 사용자 가이드 실습
   ↓
[2주차] Scouter APM 실습 + 모니터링 지표 (PromQL 직접 쿼리)
   ↓
[3주차] 성능 튜닝 실습 (ab/wrk로 Before/After 비교)
   ↓
[4주차] 장애 대응 시나리오 실습 (docker stop으로 장애 시뮬레이션)
   ↓
[5주차] 보안 심화 (openssl 명령어, curl로 OIDC 토큰 발급)
   ↓
[6주차] 인프라 설계 (Blue-Green 배포, 용량 계획 산정 실습)
```

> 각 문서에는 **실제 명령어와 설정 파일 예시**가 포함되어 있어, 읽기만 하지 말고 **직접 터미널에서 실행하면서 학습**하는 것을 권장한다.
