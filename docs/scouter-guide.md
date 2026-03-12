# Scouter APM 완전 가이드

> 이 문서는 Scouter의 **설치부터 내부 동작 메커니즘**까지 한 권의 책처럼 다룹니다.
>
> Scouter는 **LG CNS의 Jennifer APM 개발자**가 만든 오픈소스 APM(Application Performance Monitoring) 도구로,
> Jennifer의 핵심 개념(XView, Active Service EQ, TPS)을 그대로 계승하면서 무료로 사용할 수 있습니다.

---

## 목차

**Part 1. 개요와 설치**
1. [Scouter란 무엇인가](#1-scouter란-무엇인가)
2. [아키텍처 — 3-Tier 구조](#2-아키텍처--3-tier-구조)
3. [본 프로젝트에서의 배포 구성](#3-본-프로젝트에서의-배포-구성)
4. [Scouter Client 설치](#4-scouter-client-설치)
5. [Scouter Client 접속](#5-scouter-client-접속)

**Part 2. 내부 동작 메커니즘**
6. [Bytecode Instrumentation — Agent의 핵심 원리](#6-bytecode-instrumentation--agent의-핵심-원리)
7. [Agent → Server 통신 프로토콜](#7-agent--server-통신-프로토콜)
8. [데이터 수집 파이프라인](#8-데이터-수집-파이프라인)
9. [XLog 내부 구조와 데이터 흐름](#9-xlog-내부-구조와-데이터-흐름)
10. [Counter(성능 카운터) 수집 메커니즘](#10-counter성능-카운터-수집-메커니즘)
11. [Server의 데이터 저장 구조](#11-server의-데이터-저장-구조)
12. [Object 관리와 생명주기](#12-object-관리와-생명주기)

**Part 3. 모니터링 뷰 완전 가이드**
13. [XLog — 트랜잭션 분석의 핵심](#13-xlog--트랜잭션-분석의-핵심)
14. [TPS 모니터링](#14-tps-모니터링)
15. [Active Service 모니터링](#15-active-service-모니터링)
16. [JVM 힙 메모리 모니터링](#16-jvm-힙-메모리-모니터링)
17. [GC 모니터링](#17-gc-모니터링)
18. [쓰레드 분석](#18-쓰레드-분석)
19. [SQL 추적과 프로파일링](#19-sql-추적과-프로파일링)
20. [Active Service EQ (이퀄라이저)](#20-active-service-eq-이퀄라이저)
21. [전체 뷰 카탈로그](#21-전체-뷰-카탈로그)

**Part 4. 실전 활용**
22. [대시보드 구성하기](#22-대시보드-구성하기)
23. [부하 테스트와 함께 모니터링하기](#23-부하-테스트와-함께-모니터링하기)
24. [알림 설정](#24-알림-설정)
25. [Agent 설정 상세 레퍼런스](#25-agent-설정-상세-레퍼런스)
26. [Server 설정 상세 레퍼런스](#26-server-설정-상세-레퍼런스)
27. [Prometheus/Grafana와의 비교](#27-prometheusgrafana와의-비교)
28. [Jennifer와의 비교](#28-jennifer와의-비교)
29. [트러블슈팅](#29-트러블슈팅)

**Part 5. 실습 과제**
30. [실습 1 — 첫 번째 XLog 점 찍기](#30-실습-1--첫-번째-xlog-점-찍기) (★☆☆☆☆)
31. [실습 2 — 대시보드 구성과 실시간 관찰](#31-실습-2--대시보드-구성과-실시간-관찰) (★★☆☆☆)
32. [실습 3 — XLog 드래그로 느린 요청 필터링](#32-실습-3--xlog-드래그로-느린-요청-필터링) (★★☆☆☆)
33. [실습 4 — 로드밸런싱 분포 확인](#33-실습-4--로드밸런싱-분포-확인) (★★★☆☆)
34. [실습 5 — GC와 응답시간의 상관관계 분석](#34-실습-5--gc와-응답시간의-상관관계-분석) (★★★☆☆)
35. [실습 6 — Thread Dump로 병목 진단](#35-실습-6--thread-dump로-병목-진단) (★★★☆☆)
36. [실습 7 — 에러 추적과 빨간 점 분석](#36-실습-7--에러-추적과-빨간-점-분석) (★★★☆☆)
37. [실습 8 — 전체 대시보드 시나리오 실행](#37-실습-8--전체-대시보드-시나리오-실행) (★★★★☆)
38. [실습 9 — Object 생명주기 관찰](#38-실습-9--object-생명주기-관찰) (★★★★☆)
39. [실습 10 — Agent 원격 설정 변경](#39-실습-10--agent-원격-설정-변경) (★★★★★)
40. [실습 11 — 과거 데이터 조회와 일간 분석](#40-실습-11--과거-데이터-조회와-일간-분석) (★★★☆☆)
41. [실습 12 — 종합 장애 시뮬레이션과 진단](#41-실습-12--종합-장애-시뮬레이션과-진단) (★★★★★)

---

# Part 1. 개요와 설치

## 1. Scouter란 무엇인가

### 1.1 APM이란?

APM(Application Performance Monitoring)은 애플리케이션의 **실시간 성능을 관찰하고 병목을 진단**하는 도구입니다. 단순히 CPU/메모리를 보는 인프라 모니터링과 달리, APM은 **개별 HTTP 요청 하나하나를 추적**하여 "어떤 URL이 느린지", "어떤 SQL이 병목인지"를 알려줍니다.

### 1.2 Scouter의 위치

```
인프라 모니터링          APM (트랜잭션 추적)        로그 수집
────────────           ──────────────────        ──────────
Prometheus/Grafana     ★ Scouter ★              ELK Stack
Zabbix, Nagios         Jennifer (상용)           Loki
node-exporter          Pinpoint (오픈소스)       Fluentd
                       Zipkin/Jaeger (분산추적)
```

Scouter는 **Java 전용 APM**으로, JVM 위에서 동작하는 Tomcat, Spring Boot, Jetty 등의 애플리케이션을 모니터링합니다.

### 1.3 왜 Scouter인가?

| 항목 | Scouter | Jennifer | Pinpoint |
|------|---------|----------|----------|
| 라이선스 | Apache 2.0 (무료) | 상용 (연간 수천만원) | Apache 2.0 (무료) |
| 설치 복잡도 | 낮음 (Agent + Server) | 낮음 | 높음 (HBase 필요) |
| 실시간성 | ★★★★★ (2초 주기) | ★★★★★ | ★★★★ |
| XLog/XView | 지원 | 지원 (원조) | 유사 기능 |
| 경량성 | Agent 오버헤드 < 3% | Agent 오버헤드 < 3% | Agent 오버헤드 5~10% |
| 한국어 자료 | 풍부 | 매우 풍부 | 풍부 |

> **핵심**: Scouter를 사용한 경험은 Jennifer 기반 모니터링 업무에 **그대로 적용**할 수 있습니다. 개념과 용어가 거의 동일합니다.

---

## 2. 아키텍처 — 3-Tier 구조

Scouter는 **Agent**, **Server(Collector)**, **Client(Viewer)** 3개의 컴포넌트로 구성됩니다.

### 2.1 전체 구성도

```
┌─────────────────────────────────────────────────────────────────┐
│                        JVM (Tomcat #1)                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Application Code (Spring Boot)                          │   │
│  │    ├─ HealthController.java                              │   │
│  │    ├─ SecuredController.java                             │   │
│  │    └─ SecurityConfig.java                                │   │
│  └──────────┬───────────────────────────────────────────────┘   │
│             │ Bytecode Instrumentation (자동 Hook)              │
│  ┌──────────▼───────────────────────────────────────────────┐   │
│  │  Scouter Java Agent (scouter.agent.jar)                  │   │
│  │    ├─ ASM Bytecode 변조 엔진                              │   │
│  │    ├─ HTTP 요청 인터셉터                                   │   │
│  │    ├─ JDBC 프록시 래퍼                                     │   │
│  │    ├─ Thread 상태 수집기                                   │   │
│  │    └─ Counter 수집기 (Heap, GC, CPU, TPS)                │   │
│  └──────────┬───────────────────────────────────────────────┘   │
│             │                                                    │
└─────────────┼────────────────────────────────────────────────────┘
              │ UDP (성능 데이터, 2초 주기)
              │ TCP (프로파일 상세, 요청 시)
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Scouter Server (Collector)                                     │
│    ├─ UDP Receiver (6100) ← 성능 카운터, XLog 데이터            │
│    ├─ TCP Receiver (6100) ← 프로파일 상세, 오브젝트 등록         │
│    ├─ HTTP API Server (6180) ← REST API                        │
│    ├─ Data Processor ← 수신 데이터 가공·집계                     │
│    └─ File DB ← 일자별 파일 기반 저장                            │
│         ├─ /database/xlog/          (XLog 데이터)               │
│         ├─ /database/counter/       (성능 카운터)                │
│         ├─ /database/text/          (URL, SQL 텍스트)           │
│         └─ /database/object/        (오브젝트 정보)              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ TCP (6100)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Scouter Client (Viewer) — Eclipse RCP 기반 GUI                 │
│    ├─ Object View (오브젝트 목록)                                │
│    ├─ XLog View (트랜잭션 분포도)                                │
│    ├─ Counter View (TPS, Heap, Active Service 등)               │
│    ├─ Profile View (상세 프로파일)                                │
│    └─ Alert View (알림)                                         │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 각 컴포넌트의 역할

| 컴포넌트 | 역할 | 기술 스택 |
|----------|------|----------|
| **Agent** | JVM에 `-javaagent`로 부착되어 바이트코드를 변조하고, 성능 데이터를 수집하여 Server로 전송 | Java, ASM 라이브러리 |
| **Server** | Agent로부터 데이터를 수신·저장·집계하고, Client에게 데이터를 제공 | Java, 파일 기반 DB |
| **Client** | Server에 접속하여 실시간 데이터를 시각화하는 데스크톱 GUI | Eclipse RCP, SWT |

### 2.3 통신 방식

```
Agent ──UDP──→ Server : 성능 카운터 (2초 주기), XLog 요약 데이터
Agent ──TCP──→ Server : 오브젝트 등록, 프로파일 상세 데이터
Client ─TCP──→ Server : 데이터 조회, 실시간 스트리밍
```

**왜 UDP와 TCP를 나눠서 사용하는가?**

- **UDP**: 빠르고 가벼움. 패킷 손실이 있어도 다음 주기에 새 데이터가 오므로 문제없음. 초당 수십~수백 건의 성능 데이터를 전송하는 데 적합.
- **TCP**: 신뢰성 필요. 오브젝트 등록, 프로파일 상세 데이터(SQL문, 스택트레이스 등)는 유실되면 안 되므로 TCP 사용.

---

## 3. 본 프로젝트에서의 배포 구성

### 3.1 Docker Compose 배치도

```
┌──────────────────────────────────────────────────────────┐
│  Docker Compose (mw-network: 172.18.0.0/16)              │
│                                                          │
│  ┌─────────────┐   ┌─────────────┐   ┌───────────────┐  │
│  │ mw-tomcat1  │   │ mw-tomcat2  │   │  mw-scouter   │  │
│  │ (WAS #1)    │   │ (WAS #2)    │   │  (Server)     │  │
│  │             │   │             │   │               │  │
│  │ Scouter     │   │ Scouter     │   │ Port: 6100    │  │
│  │ Agent 내장  │──→│ Agent 내장  │──→│ Port: 6180    │  │
│  │             │   │             │   │               │  │
│  │ obj_name=   │   │ obj_name=   │   │ DB: /database │  │
│  │  tomcat1    │   │  tomcat2    │   │               │  │
│  └─────────────┘   └─────────────┘   └───────┬───────┘  │
│                                               │          │
└───────────────────────────────────────────────┼──────────┘
                                                │ TCP 6100
                                    ┌───────────▼───────────┐
                                    │  Scouter Client (GUI)  │
                                    │  로컬 PC에 별도 설치    │
                                    │  → 127.0.0.1:6100     │
                                    └───────────────────────┘
```

### 3.2 핵심 설정 파일

| 파일 | 위치 | 역할 |
|------|------|------|
| `agent.conf` | `configs/scouter/agent.conf` | Java Agent 설정 (Server 주소, Hook 패턴 등) |
| `server.conf` | `configs/scouter/server.conf` | Scouter Server 설정 (포트, DB 경로, 로그 등) |
| `Dockerfile` | `configs/scouter/Dockerfile` | Scouter Server 컨테이너 빌드 정의 |
| `app/Dockerfile` | `app/Dockerfile` | Tomcat + Scouter Agent 포함 빌드 |

### 3.3 JVM 기동 인자 (docker-compose.yml)

```yaml
JAVA_OPTS: >-
  -Xms256m -Xmx512m                                        # JVM 힙 메모리
  -DjvmRoute=tomcat1                                        # Tomcat 세션 라우팅 ID
  -Dserver.port=8080                                        # 서블릿 포트
  -javaagent:/opt/scouter/agent.java/scouter.agent.jar      # ★ Scouter Agent 부착
  -Dscouter.config=/opt/scouter-conf/agent.conf             # ★ Agent 설정 파일 경로
  -Dobj_name=tomcat1                                        # ★ Scouter 오브젝트 이름
```

`-javaagent` 옵션이 Scouter의 모든 동작의 출발점입니다. JVM이 클래스를 로드할 때 Agent의 `premain()` 메서드가 먼저 호출되어, 바이트코드 변조 엔진이 활성화됩니다.

---

## 4. Scouter Client 설치

> Scouter Client는 Homebrew에 등록되어 있지 않습니다. GitHub Releases에서 직접 다운로드합니다.

### macOS - Apple Silicon (M1/M2/M3/M4)

```bash
# 1. 다운로드
curl -L -o /tmp/scouter-client-mac.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-macosx.cocoa.aarch64.tar.gz

# 2. 설치 디렉토리 생성 및 압축 해제
mkdir -p ~/Applications/Scouter
tar -xzf /tmp/scouter-client-mac.tar.gz -C ~/Applications/Scouter

# 3. macOS 보안 속성(quarantine) 제거
#    ⚠️ 이 단계를 빠뜨리면 "손상된 앱이므로 열 수 없습니다" 오류 발생
xattr -cr ~/Applications/Scouter/scouter.client.app

# 4. 실행
open ~/Applications/Scouter/scouter.client.app

# (정리) 다운로드 파일 삭제
rm /tmp/scouter-client-mac.tar.gz
```

### macOS - Intel

```bash
curl -L -o /tmp/scouter-client-mac.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-macosx.cocoa.x86_64.tar.gz

mkdir -p ~/Applications/Scouter
tar -xzf /tmp/scouter-client-mac.tar.gz -C ~/Applications/Scouter
xattr -cr ~/Applications/Scouter/scouter.client.app
open ~/Applications/Scouter/scouter.client.app
```

### Windows

1. [scouter.client.product-win32.win32.x86_64.zip](https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-win32.win32.x86_64.zip) 다운로드
2. 원하는 위치에 압축 해제
3. `scouter.exe` 실행

### Linux

```bash
curl -L -o /tmp/scouter-client-linux.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-linux.gtk.x86_64.tar.gz
mkdir -p ~/scouter-client
tar -xzf /tmp/scouter-client-linux.tar.gz -C ~/scouter-client
~/scouter-client/scouter.client/scouter
```

### 내 Mac이 Apple Silicon인지 확인하는 방법

```bash
uname -m
# arm64 → Apple Silicon (M칩) → aarch64 버전 다운로드
# x86_64 → Intel → x86_64 버전 다운로드
```

---

## 5. Scouter Client 접속

### 5.1 사전 조건

Docker 환경이 구동 중이어야 합니다:

```bash
# 프로젝트 디렉토리에서
docker-compose up -d

# Scouter Server가 구동 중인지 확인
docker logs mw-scouter 2>&1 | tail -5
# → "Started ServerConnector@...{HTTP/1.1}{0.0.0.0:6180}" 가 보이면 정상
```

### 5.2 접속 정보

Scouter Client 실행 후 아래 정보를 입력합니다:

| 항목 | 값 |
|------|------|
| **Server Address** | `127.0.0.1` |
| **Port** | `6100` |
| **ID** | `admin` |
| **Password** | `admin` |

### 5.3 접속 성공 확인

접속에 성공하면 좌측 **Object** 패널에 아래와 같이 표시됩니다:

```
▼ /middleware
   ├─ tomcat1    ← Tomcat #1 Agent
   └─ tomcat2    ← Tomcat #2 Agent
```

> Object가 보이지 않으면 Tomcat 컨테이너가 아직 기동 중이거나 Agent 설정에 문제가 있는 것입니다. [트러블슈팅](#29-트러블슈팅) 섹션을 참고하세요.

---

# Part 2. 내부 동작 메커니즘

## 6. Bytecode Instrumentation — Agent의 핵심 원리

### 6.1 개요

Scouter Agent의 핵심 기술은 **Java Bytecode Instrumentation(BCI)**입니다. 애플리케이션 소스코드를 수정하지 않고도, JVM이 클래스를 로드하는 시점에 바이트코드를 변조하여 성능 측정 코드를 삽입합니다.

이것이 가능한 이유는 Java의 `java.lang.instrument` API 때문입니다.

### 6.2 동작 순서

```
① JVM 시작
   └─ -javaagent:scouter.agent.jar 옵션 감지

② Agent의 premain() 호출
   └─ Instrumentation 객체를 JVM으로부터 수신
   └─ ClassFileTransformer 등록

③ 클래스 로딩 시마다 transform() 호출
   └─ 로드되는 클래스가 Hook 대상인지 확인
   └─ 대상이면 ASM으로 바이트코드 변조
   └─ 변조된 바이트코드를 JVM에 반환

④ 변조된 코드가 실행됨
   └─ 메서드 시작 시: 시작 시간 기록, TraceContext 생성
   └─ 메서드 종료 시: 종료 시간 기록, 소요 시간 계산, Server로 전송
```

### 6.3 ASM 바이트코드 변조 원리

Scouter는 **ASM 라이브러리**를 사용하여 Java 바이트코드를 직접 조작합니다. ASM은 Java 바이트코드를 읽고 쓸 수 있는 저수준 프레임워크입니다.

변조 전후의 코드를 개념적으로 비교하면:

**원본 코드 (개발자가 작성한 것):**
```java
public Map<String, String> health() throws UnknownHostException {
    return Map.of(
        "status", "UP",
        "host", InetAddress.getLocalHost().getHostName()
    );
}
```

**Agent가 바이트코드를 변조한 결과 (개념적 표현):**
```java
public Map<String, String> health() throws UnknownHostException {
    // ── Agent가 삽입한 코드 (시작) ──
    TraceContext ctx = TraceContextManager.startTrace();
    ctx.setServiceName("/health");
    ctx.setStartTime(System.nanoTime());
    try {
    // ── 원본 코드 ──
        return Map.of(
            "status", "UP",
            "host", InetAddress.getLocalHost().getHostName()
        );
    // ── Agent가 삽입한 코드 (종료) ──
    } finally {
        ctx.setEndTime(System.nanoTime());
        ctx.setElapsed(ctx.getEndTime() - ctx.getStartTime());
        TraceContextManager.endTrace(ctx);  // → Server로 전송
    }
}
```

실제로는 소스코드가 아닌 **바이트코드(.class) 수준**에서 이 변조가 일어나므로, 원본 소스코드에는 어떤 변경도 없습니다.

### 6.4 Hook 대상 결정

`agent.conf`에서 어떤 클래스/메서드를 Hook할지 결정합니다:

```properties
# 메서드 단위 Hook — 이 패턴에 매칭되는 모든 메서드를 추적
hook_method_patterns=com.middleware.demo.*.*

# 서비스(컨트롤러) 단위 Hook — 이 패턴의 메서드를 서비스(트랜잭션)로 인식
hook_service_patterns=com.middleware.demo.controller.*.*
```

| 설정 | 의미 | 효과 |
|------|------|------|
| `hook_method_patterns` | 지정된 패키지의 모든 메서드를 추적 | 프로파일에서 메서드 호출 내역 확인 가능 |
| `hook_service_patterns` | 지정된 컨트롤러의 메서드를 **서비스 진입점**으로 인식 | XLog에 점이 찍히는 기준이 됨 |

### 6.5 자동 Hook 되는 항목

`agent.conf`에 명시하지 않아도 Scouter Agent가 **자동으로 Hook하는 항목**이 있습니다:

| 항목 | 설명 | 구현 방식 |
|------|------|----------|
| **HTTP 서블릿** | `javax.servlet.http.HttpServlet.service()` | Servlet Filter/Wrapper 프록시 |
| **JDBC** | `java.sql.Connection`, `PreparedStatement`, `Statement` | JDBC 드라이버 프록시 래핑 |
| **HTTP Client** | `HttpURLConnection`, Apache HttpClient | 소켓 I/O Hook |
| **Thread** | `java.lang.Thread` 상태 변화 | JMX MXBean 조회 |
| **GC** | Garbage Collection 이벤트 | `GarbageCollectorMXBean` 리스너 |

### 6.6 성능 오버헤드

바이트코드 변조에 의한 오버헤드는 **1~3%** 수준입니다:

```
요청 처리 시간 비교:
  Agent 없이: 15.2ms (평균)
  Agent 있음: 15.5ms (평균)  → 약 2% 증가
```

오버헤드가 낮은 이유:
- 시작/종료 시간 기록은 `System.nanoTime()` 한 번 호출 수준
- 데이터 전송은 UDP (비동기, 논블로킹)
- 프로파일 상세 데이터는 Client가 요청할 때만 TCP로 전송

---

## 7. Agent → Server 통신 프로토콜

### 7.1 이중 프로토콜 설계

Scouter는 **UDP + TCP 이중 프로토콜**을 사용합니다. 이는 성능과 신뢰성의 균형을 맞추기 위한 설계입니다.

```
                    ┌─────────────────────────────────┐
                    │        Scouter Server            │
                    │         (port 6100)              │
                    │                                  │
Agent ──UDP 6100──→ │  UDP Receiver                    │
  │                 │    ├─ Counter 데이터 수신         │
  │                 │    ├─ XLog 요약 수신              │
  │                 │    └─ Alert 데이터 수신           │
  │                 │                                  │
  └──TCP 6100────→  │  TCP Receiver                    │
                    │    ├─ Object 등록/해제            │
                    │    ├─ Profile 상세 데이터         │
                    │    ├─ Text (URL, SQL) 사전 동기화  │
                    │    └─ Client 요청 중계            │
                    └─────────────────────────────────┘
```

### 7.2 UDP 통신 — 대량 데이터 전송

UDP로 전송되는 데이터:

| 데이터 종류 | 전송 주기 | 내용 |
|------------|----------|------|
| **Performance Counter** | 2초 | TPS, Active Service, Heap Used, GC Count, CPU |
| **XLog** | 요청 완료 즉시 | txid, 서비스명 해시, 응답시간, 에러 여부 |
| **Alert** | 이벤트 발생 시 | 알림 레벨, 메시지 |

**UDP를 선택한 이유:**
1. TCP 연결 유지 비용 없음 → Agent 측 리소스 절약
2. 패킷 손실 허용 → 2초 후 새 데이터가 오므로 무관
3. 높은 처리량 → 초당 수천 건의 XLog도 무리 없이 전송

### 7.3 TCP 통신 — 신뢰성 필요 데이터

TCP로 전송되는 데이터:

| 데이터 종류 | 전송 시점 | 내용 |
|------------|----------|------|
| **Object 등록** | Agent 시작 시 | 오브젝트 이름, 타입, Host 정보 |
| **Object Heartbeat** | 30초 주기 | 생존 확인 신호 |
| **Profile Step** | Client가 XLog 점 클릭 시 | SQL문, 메서드 호출 스택, 파라미터 |
| **Text Dictionary** | 최초 1회 | URL 경로, SQL문 → 해시값 매핑 (중복 전송 방지) |

### 7.4 Text Dictionary — 대역폭 최적화

Scouter는 **Text Dictionary** 기법으로 네트워크 대역폭을 절약합니다:

```
① 최초 요청 시: "/health" 라는 문자열을 해시값 0x7A3F 로 변환
② TCP로 {0x7A3F: "/health"} 매핑을 Server에 등록 (1회만)
③ 이후 XLog 전송 시: 서비스명을 0x7A3F (4바이트)로만 전송

네트워크 절약 효과:
  "/secured/profile" (17바이트) → 0x3B2E (4바이트) = 76% 절약
  "SELECT * FROM users WHERE id = ?" (33바이트) → 0xA1C4 (4바이트) = 88% 절약
```

### 7.5 본 프로젝트의 Agent 설정

```properties
# configs/scouter/agent.conf

# Server 연결 — Docker 내부 DNS로 scouter-server 컨테이너 접속
net_collector_ip=scouter-server
net_collector_udp_port=6100
net_collector_tcp_port=6100

# 트레이싱
trace_interservice_enabled=true        # 서비스 간 호출 추적 (분산 추적)
profile_step_max_count=1024            # 프로파일 스텝 최대 수 (SQL, 메서드 등)
xlog_sampling_enabled=false            # 샘플링 비활성화 (모든 요청 수집)

# Hook 패턴
hook_method_patterns=com.middleware.demo.*.*
hook_service_patterns=com.middleware.demo.controller.*.*

# HTTP 원본 IP
trace_http_client_ip_header_key=X-Forwarded-For   # Nginx 프록시 뒤의 실제 IP
```

`net_collector_ip=scouter-server`가 핵심입니다. Docker Compose의 내부 DNS 덕분에, `scouter-server`라는 서비스명으로 Scouter Server 컨테이너의 IP를 자동 resolve합니다.

---

## 8. 데이터 수집 파이프라인

### 8.1 HTTP 요청의 전체 수집 흐름

사용자가 `curl -sk https://localhost/health`를 실행했을 때, Scouter에서 일어나는 일:

```
시간 흐름 →

[Client/curl]
    │
    │ HTTPS 요청
    ▼
[Nginx] ─── 로드밸런싱 ──→ [Tomcat #1 또는 #2]
                                │
                                ▼
                           ┌─────────────────────────────────┐
                           │ ① Servlet Filter 진입            │
                           │    Scouter Agent 감지            │
                           │    → TraceContext 생성           │
                           │    → txid 발급 (고유 거래 ID)    │
                           │    → 시작 시간 기록              │
                           │                                  │
                           │ ② DispatcherServlet 진입         │
                           │    → URL 매핑: /health           │
                           │                                  │
                           │ ③ HealthController.health() 실행 │
                           │    → (Hook에 의해 메서드 추적)    │
                           │    → (SQL 있으면 JDBC Hook 동작)  │
                           │                                  │
                           │ ④ 응답 생성 완료                  │
                           │    → 종료 시간 기록               │
                           │    → 소요 시간 계산               │
                           │                                  │
                           │ ⑤ XLog Pack 생성                 │
                           │    {                              │
                           │      txid: 0xA1B2C3D4,           │
                           │      service: 0x7A3F,  (/health) │
                           │      elapsed: 12,  (ms)          │
                           │      error: 0,                   │
                           │      ipaddr: "172.18.0.1",       │
                           │      cpu: 850,  (μs)             │
                           │    }                              │
                           │                                  │
                           │ ⑥ UDP 전송 → Scouter Server     │
                           └─────────────────────────────────┘
                                        │
                                        ▼ UDP
                           ┌─────────────────────────────────┐
                           │ Scouter Server                   │
                           │                                  │
                           │ ⑦ XLog Pack 수신                 │
                           │    → 파일 DB에 저장              │
                           │    → 실시간 스트리밍 큐에 추가    │
                           │                                  │
                           │ ⑧ Client로 실시간 Push          │
                           └─────────────────────────────────┘
                                        │
                                        ▼ TCP
                           ┌─────────────────────────────────┐
                           │ Scouter Client                   │
                           │                                  │
                           │ ⑨ XLog View에 점 하나 그려짐     │
                           │    위치: (현재 시각, 12ms)       │
                           └─────────────────────────────────┘
```

### 8.2 데이터 수집 시점 정리

| 수집 시점 | 수집 데이터 | 전송 방식 |
|----------|------------|----------|
| JVM 시작 시 | Object 등록 (이름, 타입, Host) | TCP 즉시 |
| 매 2초 | Performance Counter (TPS, Heap, GC, CPU, Active) | UDP 주기적 |
| 매 30초 | Object Heartbeat | TCP 주기적 |
| HTTP 요청 완료 시 | XLog (txid, 서비스명, 응답시간, 에러) | UDP 즉시 |
| Client가 점 클릭 시 | Profile Steps (SQL, 메서드, 파라미터) | TCP 요청-응답 |

---

## 9. XLog 내부 구조와 데이터 흐름

### 9.1 XLog란?

XLog(eXtended Log)는 Scouter의 **핵심 데이터 모델**입니다. HTTP 요청 하나 = XLog 레코드 하나입니다. Jennifer의 XView와 동일한 개념입니다.

### 9.2 XLog Pack 구조

하나의 XLog Pack에 담기는 필드:

```
XLogPack {
  txid        : long       // 트랜잭션 고유 ID (예: 0xA1B2C3D4E5F6)
  gxid        : long       // 글로벌 트랜잭션 ID (분산 추적용)
  caller      : long       // 호출자 txid (분산 추적용)

  objHash     : int        // 오브젝트 해시 (어떤 Tomcat인지)
  service     : int        // 서비스명 해시 (예: /health → 0x7A3F)

  elapsed     : int        // 응답 시간 (ms)
  error       : int        // 에러 여부 (0=정상, 양수=에러 해시)

  cpu         : int        // CPU 사용 시간 (μs)
  sqlCount    : int        // 실행된 SQL 수
  sqlTime     : int        // SQL 총 소요 시간 (ms)

  ipaddr      : byte[4]   // 클라이언트 IP
  userid      : long       // 사용자 식별 ID

  threadName  : String     // 처리 쓰레드명
  login       : String     // 로그인 사용자명 (있을 경우)
}
```

### 9.3 XLog 시각화 원리

```
XLog 차트 좌표계:
  X축 = 요청 완료 시각
  Y축 = elapsed (응답 시간, ms)
  색상 = 에러 여부 (파란점=정상, 빨간점=에러)

  응답시간(ms)
  5000 |                          ●(빨강) ← 에러 발생
       |
  2000 |              ●(파랑)
       |
   500 |    ● ●   ●     ●
       |
   100 | ●●●●●●●●●●●●●●●●●● ← 정상 대역
     0 |_________________________________ 시각 →
       09:00    09:01    09:02    09:03
```

### 9.4 XLog에서 Profile 조회

XLog의 점을 클릭하면 해당 txid로 **Profile Steps**를 조회합니다:

```
Profile Steps for txid=0xA1B2C3D4E5F6
────────────────────────────────────────────────
  [0ms]  → START service=/health
  [1ms]  → METHOD com.middleware.demo.controller.HealthController.health()
  [2ms]  →   METHOD java.net.InetAddress.getLocalHost()
  [5ms]  →   METHOD java.lang.Runtime.maxMemory()
  [6ms]  →   METHOD java.lang.Runtime.freeMemory()
  [8ms]  →   METHOD java.lang.Runtime.availableProcessors()
  [11ms] → END elapsed=11ms cpu=850μs
────────────────────────────────────────────────
```

SQL이 포함된 요청의 경우:

```
Profile Steps for txid=0xB2C3D4E5F6A1
────────────────────────────────────────────────
  [0ms]  → START service=/api/users
  [1ms]  → METHOD UserController.getUsers()
  [2ms]  →   SQL  SELECT * FROM users WHERE active = ?
  [45ms] →   SQL  elapsed=43ms  rows=150
  [46ms] →   METHOD UserMapper.toDTO()
  [52ms] → END elapsed=52ms cpu=12300μs
────────────────────────────────────────────────
```

이렇게 **요청 하나의 내부 처리 과정**을 시간순으로 추적할 수 있는 것이 APM의 핵심 가치입니다.

---

## 10. Counter(성능 카운터) 수집 메커니즘

### 10.1 Counter란?

Counter는 JVM의 **수치형 성능 지표**를 주기적으로 수집한 데이터입니다. XLog가 "개별 요청"의 데이터라면, Counter는 "시스템 전체"의 상태 데이터입니다.

### 10.2 수집 주기와 방식

```
┌─────────────────────────────────────────────┐
│            Scouter Agent 내부                │
│                                             │
│  [CounterCollector Thread] ← 2초마다 실행    │
│    │                                         │
│    ├─ JMX Query                              │
│    │   ├─ MemoryMXBean → Heap Used/Max      │
│    │   ├─ ThreadMXBean → Thread Count       │
│    │   ├─ GCMXBean → GC Count/Time          │
│    │   ├─ RuntimeMXBean → Uptime            │
│    │   └─ OperatingSystemMXBean → CPU       │
│    │                                         │
│    ├─ Agent 내부 통계                         │
│    │   ├─ 완료된 요청 수 / 2초 → TPS         │
│    │   ├─ 미완료 요청 수 → Active Service     │
│    │   └─ 에러 발생 수 → Error Rate          │
│    │                                         │
│    └─ CounterPack 생성 → UDP 전송            │
│                                              │
└─────────────────────────────────────────────┘
```

### 10.3 수집되는 Counter 목록

| Counter 이름 | 데이터 소스 | 의미 |
|-------------|-----------|------|
| **TPS** | Agent 내부 통계 | 초당 처리 트랜잭션 수 |
| **Active Service** | Agent 내부 통계 | 현재 처리 중인 요청 수 |
| **Elapsed90%** | Agent 내부 통계 | 90% 응답시간 |
| **Heap Used** | MemoryMXBean | JVM 힙 메모리 사용량 (bytes) |
| **Heap Total** | MemoryMXBean | JVM 힙 메모리 최대 크기 |
| **GC Count** | GarbageCollectorMXBean | GC 발생 횟수 |
| **GC Time** | GarbageCollectorMXBean | GC 소요 시간 (ms) |
| **Thread Count** | ThreadMXBean | 전체 쓰레드 수 |
| **CPU** | OperatingSystemMXBean | JVM의 CPU 사용률 (%) |
| **Process CPU** | OperatingSystemMXBean | OS 프로세스 CPU 사용률 |
| **Perm/Metaspace Used** | MemoryMXBean | 메타스페이스 사용량 |

### 10.4 Counter 데이터 흐름

```
Agent (2초마다)                Server                    Client
─────────────                 ──────                    ──────
CounterPack {
  objHash: 0x1234,            수신
  time: 1710000000,           │
  counters: {                 ├─ 파일 DB에 저장
    TPS: 45.5,                │   /database/counter/
    HeapUsed: 268435456,      │   └─ 2026-03-12.data
    ActiveService: 3,         │
    GCCount: 12,              ├─ 5초 평균 집계 → 저장
    CPU: 23.4                 │
  }                           └─ Client로 Push ──────→ 차트 업데이트
}                                                       그래프에 점 추가
  │
  └── UDP ──→
```

---

## 11. Server의 데이터 저장 구조

### 11.1 파일 기반 DB

Scouter Server는 별도의 RDBMS나 NoSQL을 사용하지 않습니다. **자체 파일 기반 DB**를 사용합니다.

```
/opt/scouter/server/database/
├── xlog/                    # XLog 데이터
│   ├── 20260312.xlog        # 일자별 파일 (2026-03-12)
│   └── 20260311.xlog
├── counter/                 # 성능 카운터 데이터
│   ├── 20260312/
│   │   ├── tomcat1/         # 오브젝트별 디렉토리
│   │   │   ├── TPS.data
│   │   │   ├── HeapUsed.data
│   │   │   └── ...
│   │   └── tomcat2/
│   │       ├── TPS.data
│   │       └── ...
│   └── 20260311/
├── text/                    # Text Dictionary (URL, SQL 문자열)
│   ├── service.txt          # 서비스명 해시→문자열 매핑
│   ├── sql.txt              # SQL문 해시→문자열 매핑
│   └── error.txt            # 에러 메시지 매핑
├── object/                  # 오브젝트 메타데이터
│   └── agent_list.data
└── profile/                 # Profile 상세 데이터
    └── 20260312.profile
```

### 11.2 데이터 보존 정책

`server.conf`에서 설정:

```properties
# configs/scouter/server.conf

db_dir=./database           # DB 저장 경로
log_keep_days=7             # 로그 보존 기간 (7일)
obj_deadtime=30000          # 오브젝트 사망 판정 시간 (30초)
```

| 설정 | 값 | 의미 |
|------|---|------|
| `log_keep_days=7` | 7일 | 7일이 지난 데이터는 자동 삭제 |
| `obj_deadtime=30000` | 30초 | Agent가 30초간 Heartbeat를 보내지 않으면 Dead로 판정 |

### 11.3 Docker 볼륨 매핑

```yaml
# docker-compose.yml
scouter-server:
  volumes:
    - scouter_data:/opt/scouter/server/database
```

`scouter_data` Docker 볼륨이 Server의 `/database` 디렉토리에 마운트되어, **컨테이너를 재시작해도 데이터가 유지**됩니다.

---

## 12. Object 관리와 생명주기

### 12.1 Object란?

Scouter에서 **Object**는 모니터링 대상 하나를 의미합니다. 본 프로젝트에서는 Tomcat 인스턴스가 각각 하나의 Object입니다.

### 12.2 Object 식별 체계

```
Object 이름 구조: /<host>/<objType>/<objName>

본 프로젝트 예시:
  /middleware/tomcat1    ← mw-tomcat1 컨테이너의 Agent
  /middleware/tomcat2    ← mw-tomcat2 컨테이너의 Agent
```

Object 이름은 JVM 기동 인자 `-Dobj_name=tomcat1`로 결정됩니다.

### 12.3 Object 생명주기

```
상태 전이도:

  [Agent 시작]                [Client에서 보이는 상태]
      │
      ▼
  ① TCP 연결 → Object 등록    → 파란색 아이콘 (Active)
      │
      ▼
  ② 30초마다 Heartbeat 전송   → 파란색 유지
      │
      ▼
  ③ Agent 종료 (docker stop)   → 30초간 대기...
      │
      ▼
  ④ Heartbeat 30초 미수신      → 회색 아이콘 (Dead)
      │
      ▼
  ⑤ 시간 경과                  → Object 목록에서 제거
```

### 12.4 컨테이너 재빌드 시 Object 문제

Docker 컨테이너를 재빌드(`docker-compose up --build`)하면, 새 컨테이너의 **Container ID가 변경**됩니다. 이 때 Scouter Client에 **같은 이름의 Object가 여러 개** 보일 수 있습니다:

```
▼ /middleware
   ├─ tomcat1     ← 새 컨테이너 (Active, 파란색)
   ├─ tomcat1     ← 이전 컨테이너 (Dead, 회색)  ← obj_deadtime 후 사라짐
   ├─ tomcat2     ← 새 컨테이너 (Active, 파란색)
   └─ tomcat2     ← 이전 컨테이너 (Dead, 회색)
```

**해결 방법:**
- `obj_deadtime=30000` (30초) 후 Dead Object는 자동으로 목록에서 제거됩니다
- 즉시 정리하려면: Scouter Client에서 회색 Object를 우클릭 → **Delete** (또는 Server 재시작)

---

# Part 3. 모니터링 뷰 완전 가이드

## 13. XLog — 트랜잭션 분석의 핵심

### 13.1 XLog란?

- X축: 시간, Y축: 응답시간(ms)
- **점 하나 = HTTP 요청 하나**
- 점의 위치가 높을수록 응답이 느린 요청
- 파란색 = 정상, 빨간색 = 에러

### 13.2 XLog 차트 열기

1. 좌측 Object에서 `tomcat1` 우클릭 → **XLog** 클릭
2. 실시간으로 점이 찍히는 차트가 열림

### 13.3 XLog 패턴 분석

```
응답시간(ms)
  3000 |                          ● ← 느린 요청 (3초)
  2000 |
  1000 |              ●
   500 |    ● ●   ●     ●
   100 | ●●●●●●●●●●●●●●●●●● ← 정상 요청 대역
     0 |__________________________ 시간 →
```

| 패턴 | 의미 | 대응 |
|------|------|------|
| 점이 100ms 아래에 몰려 있음 | 정상 | 유지 |
| 간헐적으로 높은 점 | 특정 요청이 느림 | 해당 점 클릭하여 상세 분석 |
| 전체적으로 점이 올라감 | 시스템 부하 | GC, DB 쿼리 확인 |
| 점이 일직선으로 올라감 | Timeout 발생 | 네트워크/DB 연결 확인 |
| 빨간 점 | 에러 발생 (HTTP 5xx 등) | 에러 프로파일 확인 |
| 점이 수평 밴드 형태 | 특정 시간대 지연 | GC Stop-the-World 의심 |

### 13.4 XLog 점 클릭 → Profile 상세 분석

XLog에서 점을 클릭하면 해당 요청의 **전체 처리 과정**을 볼 수 있습니다:

- **URL**: 요청 경로 (예: `/health`, `/secured/profile`)
- **응답시간**: 전체 처리 시간 (ms)
- **SQL 쿼리**: 실행된 SQL문과 소요 시간
- **API Call**: 외부 서비스 호출 내역
- **CPU Time**: CPU 사용 시간
- **Method Call**: Hook된 메서드의 호출 순서와 소요 시간
- **Error**: 에러 스택트레이스 (에러 발생 시)

> 이것이 APM의 핵심 가치입니다. "느린 요청의 원인이 **SQL인지, 외부 API인지, GC인지**"를 추적할 수 있습니다.

### 13.5 XLog 드래그 선택

차트에서 영역을 **드래그**하면 해당 시간대+응답시간 범위의 요청만 필터링하여 목록으로 볼 수 있습니다. 이를 통해 "2초 이상 걸린 요청만 모아보기" 등이 가능합니다.

---

## 14. TPS 모니터링

### 14.1 TPS(Transaction Per Second)란?

- 초당 처리되는 트랜잭션(HTTP 요청) 수
- 시스템의 **처리 용량**을 나타내는 핵심 지표

### 14.2 TPS 차트 열기

1. Object에서 `tomcat1` 우클릭 → **Counter** → **TPS**
2. (선택) `tomcat2`도 같은 방식으로 열면 2대의 TPS를 비교 가능

### 14.3 TPS 해석

| TPS 값 | 의미 |
|---------|------|
| 0 | 요청이 없음 |
| 1~10 | 가벼운 트래픽 |
| 50~100 | 보통 수준 |
| 100+ | 높은 트래픽 (Tomcat maxThreads=200 기준) |

### 14.4 TPS 내부 계산 방식

```
Agent 내부:

  completedCount = 0  (2초마다 리셋)

  HTTP 요청 완료 시:
    completedCount++

  2초 주기 Counter 수집 시:
    TPS = completedCount / 2.0
    completedCount = 0
    → CounterPack에 담아 UDP 전송
```

---

## 15. Active Service 모니터링

### 15.1 Active Service란?

- **현재 처리 중인 요청 수** (아직 응답이 완료되지 않은 요청)
- 이 숫자가 높으면 서버가 요청을 소화하지 못하고 있다는 의미

### 15.2 Active Service 차트 열기

Object에서 `tomcat1` 우클릭 → **Counter** → **Active Service**

### 15.3 Active Service 해석

| 값 | 의미 |
|----|------|
| 0 | 처리 중인 요청 없음 (유휴 상태) |
| 1~5 | 정상 |
| 10+ | 부하가 걸리고 있음 |
| 50+ | **심각한 병목** — 즉시 원인 분석 필요 |

### 15.4 Active Service 내부 계산

```
Agent 내부:

  activeSet = ConcurrentHashMap<Long, TraceContext>()

  HTTP 요청 시작 시:
    TraceContext ctx = new TraceContext(txid)
    activeSet.put(txid, ctx)

  HTTP 요청 완료 시:
    activeSet.remove(txid)

  2초 주기 Counter 수집 시:
    ActiveService = activeSet.size()
```

---

## 16. JVM 힙 메모리 모니터링

### 16.1 힙 메모리란?

- Java 애플리케이션이 객체를 저장하는 메모리 영역
- 메모리가 가득 차면 **GC(Garbage Collection)**가 실행되어 사용하지 않는 객체를 정리
- GC 실행 중에는 애플리케이션이 잠시 멈춤 → **응답 지연 발생 가능**

### 16.2 Heap Memory 차트 열기

Object에서 `tomcat1` 우클릭 → **Counter** → **Heap Used**

### 16.3 힙 메모리 패턴 읽기

```
메모리(MB)
  512 |─────────────────── Max Heap (-Xmx512m)
      |
  400 |    /\    /\    /\     ← 톱니 모양 = 정상 (GC 반복)
  300 |   /  \  /  \  /  \
  200 |  /    \/    \/    \
  100 | /
    0 |________________________ 시간 →
```

| 패턴 | 의미 | 대응 |
|------|------|------|
| 톱니 모양 (상승→급락 반복) | 정상적인 GC 패턴 | 정상 |
| 계속 상승만 하고 떨어지지 않음 | **메모리 누수** 의심 | Heap Dump 분석 필요 |
| Max에 가깝게 유지 | 메모리 부족 | JVM 힙 크기 증가 필요 (`-Xmx` 조정) |

본 프로젝트에서 Tomcat의 힙 설정: `-Xms256m -Xmx512m`

---

## 17. GC 모니터링

### 17.1 GC가 중요한 이유

GC(Garbage Collection)는 JVM이 더 이상 참조되지 않는 객체를 정리하는 과정입니다. GC 실행 중에는 **Stop-the-World**(모든 애플리케이션 쓰레드 일시 정지)가 발생하므로, GC가 잦거나 길면 응답 지연의 직접적인 원인이 됩니다.

### 17.2 GC 관련 Counter

| Counter | 의미 |
|---------|------|
| **GC Count** | 2초 동안 발생한 GC 횟수 |
| **GC Time** | 2초 동안 GC에 소요된 시간 (ms) |

### 17.3 GC와 XLog의 상관관계

GC가 오래 걸리면 XLog에서 점이 동시에 올라가는 현상이 나타납니다:

```
XLog                              GC Time
응답시간(ms)                       (ms)
 500 |         ●●●●●              50 |    ██
     |         ●●●●●                  |    ██
 100 | ●●●●●●        ●●●●●      10 | ██      ██
   0 |________________________    0 |________________
     09:00  09:01  09:02          09:00  09:01  09:02

     ↑ 09:01에 GC 발생 → 동시에 모든 요청의 응답시간 증가
```

---

## 18. 쓰레드 분석

### 18.1 Thread List 보기

Object에서 `tomcat1` 우클릭 → **Thread List / Thread Dump**

### 18.2 쓰레드 상태

| 상태 | 의미 |
|------|------|
| **RUNNABLE** | 실행 중 |
| **WAITING** | 다른 쓰레드의 알림을 대기 중 |
| **TIMED_WAITING** | 타임아웃이 있는 대기 |
| **BLOCKED** | 락(Lock) 획득 대기 중 ← **병목 원인** |

### 18.3 Thread Dump 분석

Thread Dump는 현재 시점의 **모든 쓰레드의 스택트레이스**를 캡처합니다:

```
"http-nio-8080-exec-1" #42 daemon prio=5
   java.lang.Thread.State: RUNNABLE
   at com.middleware.demo.controller.HealthController.health(HealthController.java:19)
   at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
   at org.apache.catalina.core.ApplicationFilterChain.doFilter(ApplicationFilterChain.java:166)
   ...
```

> BLOCKED 상태의 쓰레드가 많으면 **데드락** 또는 **DB 커넥션 풀 고갈**을 의심해야 합니다.

### 18.4 Thread Dump 활용 패턴

| 상황 | Thread Dump에서 보이는 패턴 | 원인 |
|------|---------------------------|------|
| Active Service가 높음 | 많은 쓰레드가 RUNNABLE + DB 관련 스택 | DB 쿼리 느림 |
| Active Service가 높음 | 많은 쓰레드가 BLOCKED + synchronized | 락 경합 |
| Active Service가 높음 | 많은 쓰레드가 WAITING + socket | 외부 API 타임아웃 |

---

## 19. SQL 추적과 프로파일링

### 19.1 JDBC Hook 원리

Scouter Agent는 `java.sql.Connection`의 `prepareStatement()`, `createStatement()` 메서드를 Hook하여, 실행되는 모든 SQL을 자동 추적합니다.

```
원본 코드 흐름:
  Connection conn = dataSource.getConnection();
  PreparedStatement ps = conn.prepareStatement("SELECT * FROM users");
  ResultSet rs = ps.executeQuery();

Agent가 변조한 흐름 (개념적):
  Connection conn = dataSource.getConnection();
  // ── Agent Hook: SQL문 캡처, 시작 시간 기록 ──
  PreparedStatement ps = conn.prepareStatement("SELECT * FROM users");
  ResultSet rs = ps.executeQuery();
  // ── Agent Hook: 종료 시간 기록, 소요 시간 계산, Profile에 기록 ──
```

### 19.2 SQL 추적 결과

XLog 점 클릭 → Profile에서 SQL 관련 정보:

```
[12ms] → SQL  SELECT * FROM users WHERE active = ?
[55ms] → SQL  elapsed=43ms  rows=150  bind=[1]
```

| 항목 | 의미 |
|------|------|
| SQL 문 | 실행된 SQL (파라미터는 `?`로 표시) |
| elapsed | SQL 실행 소요 시간 |
| rows | 반환된 행 수 |
| bind | 바인드 파라미터 값 (설정 시) |

### 19.3 느린 SQL 찾기

XLog에서 응답시간이 높은 점을 클릭하면, SQL이 병목인 경우 Profile에서 SQL의 elapsed가 큰 것을 바로 확인할 수 있습니다.

---

## 20. Active Service EQ (이퀄라이저)

### 20.1 Active Service EQ란?

Active Service EQ(Equalizer)는 **현재 처리 중인 요청의 경과 시간을 색상 막대**로 시각화한 뷰입니다. 오디오 이퀄라이저처럼 막대가 올라가고 내려가며, 시스템의 실시간 부하 상태를 직관적으로 보여줍니다.

### 20.2 EQ 색상 의미

```
Active Service EQ:

  █ █ █ █ █ █ █ █ █
  ↑               ↑
 0초             8초+

  █ 녹색 (0~3초)   : 정상 처리 중
  █ 노란색 (3~8초)  : 느린 요청 (주의)
  █ 빨간색 (8초+)   : 매우 느린 요청 (위험)
```

### 20.3 EQ 열기

Object에서 `tomcat1` 우클릭 → **Active Service EQ**

### 20.4 EQ 해석

| 패턴 | 의미 |
|------|------|
| 녹색 막대만 간헐적으로 나타남 | 정상 — 요청이 빠르게 처리됨 |
| 노란색/빨간색 막대가 지속 | 느린 요청 — Thread Dump 분석 필요 |
| 빨간색 막대가 가득 참 | 시스템 마비 — 즉시 대응 필요 |

---

## 21. 전체 뷰 카탈로그

### 21.1 Object 우클릭 메뉴 전체 목록

| 카테고리 | 뷰 이름 | 설명 |
|----------|---------|------|
| **실시간 트랜잭션** | XLog | 트랜잭션 응답시간 분포도 (핵심) |
| | Active Service List | 현재 처리 중인 요청 목록 |
| | Active Service EQ | 처리 중 요청의 경과시간 이퀄라이저 |
| **Counter (성능 지표)** | TPS | 초당 처리 건수 |
| | Active Service | 현재 처리 중인 요청 수 (숫자 차트) |
| | Elapsed90% | 90% 백분위 응답시간 |
| | Elapsed Mean | 평균 응답시간 |
| | Heap Used | JVM 힙 메모리 사용량 |
| | Heap Total | JVM 전체 힙 크기 |
| | GC Count | GC 발생 횟수 |
| | GC Time | GC 소요 시간 |
| | CPU | JVM CPU 사용률 |
| | Process CPU | OS 프로세스 CPU |
| | Thread Count | 전체 쓰레드 수 |
| | Perm/Metaspace Used | 메타스페이스 사용량 |
| | Recent User | 최근 사용자 수 |
| | Error Rate | 에러 발생률 |
| **분석** | Thread List | 현재 쓰레드 목록 |
| | Thread Dump | 전체 쓰레드 스택트레이스 |
| | Loaded Class | 로드된 클래스 목록 |
| | Socket | 소켓 연결 목록 |
| | Object Info | 오브젝트 상세 정보 |
| | Env | JVM 환경 변수 |
| | Configure | Agent 설정 (원격 변경 가능) |
| **과거 데이터** | Load XLog | 과거 시간대의 XLog 조회 |
| | Daily Counter | 일별 Counter 추이 |
| | Counter Past Time | 특정 시간대의 Counter 조회 |

### 21.2 메뉴바 전용 뷰

| 뷰 | 설명 |
|----|------|
| **Alert** | 알림 목록 (응답시간 초과, GC 이상 등) |
| **Object Dashboard** | 전체 Object의 종합 현황 |
| **Group XLog** | 여러 Object의 XLog를 하나의 차트에 |
| **Group Counter** | 여러 Object의 Counter를 하나의 차트에 |

---

# Part 4. 실전 활용

## 22. 대시보드 구성하기

### 22.1 추천 대시보드 레이아웃

처음 사용할 때 아래 6개를 열어두면 종합적인 모니터링이 가능합니다:

```
┌───────────────────────────────────────────────────────┐
│  ┌─────────────────────┐  ┌─────────────────────────┐ │
│  │                     │  │                         │ │
│  │    XLog (실시간)     │  │   Active Service EQ    │ │
│  │                     │  │                         │ │
│  └─────────────────────┘  └─────────────────────────┘ │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐            │
│  │    TPS    │ │ Heap Used │ │  GC Time  │            │
│  │           │ │           │ │           │            │
│  └───────────┘ └───────────┘ └───────────┘            │
│  ┌───────────┐                                        │
│  │   CPU     │                                        │
│  └───────────┘                                        │
└───────────────────────────────────────────────────────┘
```

### 22.2 대시보드 구성 순서

1. 좌측 Object에서 `tomcat1` 우클릭 → **XLog** → 차트 열기
2. 같은 방식으로 **Counter** → **TPS**, **Heap Used**, **GC Time**, **CPU** 열기
3. `tomcat1` 우클릭 → **Active Service EQ** 열기
4. 각 창을 드래그하여 위치 조정
5. (선택) `tomcat2`에 대해서도 동일하게 열어 비교 모니터링

### 22.3 Group 뷰 활용

tomcat1과 tomcat2의 데이터를 **하나의 차트에서 비교**하려면:

1. 메뉴바 → **Object** → **Group Counter** 선택
2. tomcat1, tomcat2를 모두 선택
3. Counter 종류 선택 (예: TPS)
4. 하나의 차트에 2개의 라인이 표시됨

---

## 23. 부하 테스트와 함께 모니터링하기

Scouter의 진가는 **부하 상황에서의 실시간 모니터링**입니다.

### 23.1 부하 테스트 스크립트

본 프로젝트에는 다양한 부하 시나리오를 제공하는 `scripts/load-test.sh`가 포함되어 있습니다:

```bash
# 스크립트 사용법
./scripts/load-test.sh [시나리오 번호]

# 시나리오 목록
# 1: health    - 기본 헬스체크 (100회)
# 2: mixed     - 혼합 엔드포인트 (200회)
# 3: slow      - 램프업 부하 (점진적 증가)
# 4: burst     - 버스트 부하 (순간 폭주)
# 5: failover  - 장애 복구 테스트
# 6: dashboard - 전체 대시보드 시나리오 (★ 추천)
```

### 23.2 대시보드 시나리오 (시나리오 6)

시나리오 6은 Scouter Client의 **모든 그래프가 동시에 움직이도록** 설계되었습니다.

```bash
./scripts/load-test.sh 6
```

7개의 Phase를 약 2.5분에 걸쳐 실행합니다:

| Phase | 동작 | Scouter에서 확인할 것 |
|-------|------|---------------------|
| 1. Warm-up | 10초간 느린 요청 | XLog에 점 나타남, TPS 상승 시작 |
| 2. Ramp-up | 점진적 부하 증가 | TPS 계단식 상승, Active Service 증가 |
| 3. Burst | 50병렬 × 5회 폭주 | TPS 급등, Active Service 최고치, Heap 급상승 |
| 4. Mixed Heavy | 다양한 URL 고부하 | XLog 점 분산, CPU 상승 |
| 5. Error Injection | 존재하지 않는 URL | XLog에 빨간 점(에러), Error Rate 상승 |
| 6. Recovery | 느린 트래픽 복구 | TPS 하강, Active Service 감소, GC 발생 |
| 7. Spike | 마지막 스파이크 | 모든 지표 최종 급등 후 안정 |

### 23.3 간단한 부하 테스트

스크립트 없이 간단히 확인하려면:

```bash
# 시나리오 1: 정상 트래픽 (1초 간격, 60회)
for i in $(seq 1 60); do
  curl -sk https://localhost/health > /dev/null
  sleep 1
done

# 시나리오 2: 순간 부하 (10병렬 × 50회)
for i in $(seq 1 50); do
  for j in $(seq 1 10); do
    curl -sk https://localhost/ > /dev/null &
  done
  wait
done

# 시나리오 3: WAS 장애 시 변화 관찰
docker stop mw-tomcat2
for i in $(seq 1 30); do curl -sk https://localhost/health > /dev/null; sleep 1; done
docker start mw-tomcat2
```

### 23.4 각 시나리오에서 관찰할 Scouter 뷰 변화

| 시나리오 | XLog | TPS | Active Service | Heap | GC |
|---------|------|-----|----------------|------|----|
| 정상 트래픽 | 100ms 이하 점 | ~1 | 0~1 | 느린 상승 | 거의 없음 |
| 순간 부하 | 점 밀집 + 높은 점 | 급상승 | 급상승 | 빠른 상승 | 활발 |
| WAS 장애 | tomcat2 점 없음 | tomcat1만 | 정상 | 변화 없음 | 변화 없음 |

---

## 24. 알림 설정

### 24.1 기본 알림 조건

Scouter Server는 기본적으로 아래 상황에서 알림을 발생시킵니다:

| 알림 조건 | 기본값 |
|-----------|--------|
| 응답시간 초과 | 8000ms 이상 |
| GC Time 초과 | 설정값 이상 |
| CPU 사용률 | 80% 이상 |
| Heap 사용률 | 90% 이상 |

### 24.2 알림 확인

알림은 Scouter Client의 **Alert** 패널에서 확인할 수 있습니다. Client 메뉴바에서 Alert 뷰를 열어 놓으면 실시간으로 알림이 표시됩니다.

### 24.3 알림 커스터마이징

`server.conf`에서 알림 임계값을 조정할 수 있습니다:

```properties
# 응답시간 알림 (ms)
alert_pms_error_enabled=true
alert_pms_error_limit=8000

# CPU 알림 (%)
alert_cpu_enabled=true
alert_cpu_limit=80

# Heap 알림 (%)
alert_heap_enabled=true
alert_heap_limit=90

# GC Time 알림 (ms/2초)
alert_gc_time_enabled=true
alert_gc_time_limit=500
```

---

## 25. Agent 설정 상세 레퍼런스

본 프로젝트의 Agent 설정 (`configs/scouter/agent.conf`):

```properties
# ─── Server 연결 ───
net_collector_ip=scouter-server         # Scouter Server IP (Docker DNS)
net_collector_udp_port=6100             # UDP 전송 포트
net_collector_tcp_port=6100             # TCP 전송 포트

# ─── 트레이싱 ───
trace_interservice_enabled=true         # 서비스 간 호출 추적 (분산 추적)
profile_step_max_count=1024             # 프로파일 스텝 최대 수
xlog_sampling_enabled=false             # 샘플링 비활성화 (모든 요청 수집)

# ─── Hook ───
hook_method_patterns=com.middleware.demo.*.*
hook_service_patterns=com.middleware.demo.controller.*.*

# ─── HTTP ───
trace_http_client_ip_header_key=X-Forwarded-For
```

### 25.1 주요 설정 상세

| 설정 | 값 | 설명 |
|------|---|------|
| `net_collector_ip` | `scouter-server` | Docker 내부 DNS 이름. Docker Compose가 자동으로 `scouter-server` 서비스의 컨테이너 IP로 resolve |
| `trace_interservice_enabled` | `true` | 서비스 간 호출 시 txid를 HTTP 헤더에 전파하여 분산 추적 가능 |
| `profile_step_max_count` | `1024` | 하나의 트랜잭션에서 기록할 수 있는 프로파일 스텝(SQL, 메서드 호출 등) 최대 수 |
| `xlog_sampling_enabled` | `false` | 모든 요청을 수집 (true로 하면 일정 비율만 수집하여 부하 감소) |
| `trace_http_client_ip_header_key` | `X-Forwarded-For` | Nginx 리버스 프록시 뒤에서 실제 클라이언트 IP를 가져오는 헤더 |

### 25.2 고급 Agent 설정 (필요 시 추가 가능)

| 설정 | 기본값 | 설명 |
|------|--------|------|
| `hook_jdbc_pstmt_enabled` | `true` | PreparedStatement Hook 활성화 |
| `hook_jdbc_stmt_enabled` | `true` | Statement Hook 활성화 |
| `profile_sql_param_enabled` | `false` | SQL 바인드 파라미터 수집 (`true`로 하면 `?` 대신 실제 값 표시) |
| `xlog_error_on_sqlexception_enabled` | `true` | SQL 예외 발생 시 XLog 에러 표시 |
| `trace_user_mode` | `2` | 사용자 식별 방식 (0=IP, 1=Cookie, 2=Header) |
| `obj_type` | `tomcat` | 오브젝트 타입 (Client의 아이콘 모양 결정) |
| `counter_enabled` | `true` | Counter 수집 활성화 |
| `counter_interaction_enabled` | `true` | 상호작용 Counter 수집 |

---

## 26. Server 설정 상세 레퍼런스

본 프로젝트의 Server 설정 (`configs/scouter/server.conf`):

```properties
# ─── Network ───
net_tcp_listen_port=6100               # Agent 및 Client TCP 통신 포트
net_http_port=6180                     # HTTP API 포트 (REST API)

# ─── DB ───
db_dir=./database                      # 데이터 저장 경로

# ─── Log ───
log_dir=./logs                         # 로그 저장 경로
log_rotation_enabled=true              # 로그 로테이션 활성화
log_keep_days=7                        # 로그 보존 기간

# ─── Object ───
obj_deadtime=30000                     # 30초간 Heartbeat 미수신 시 Dead 판정
```

### 26.1 주요 설정 상세

| 설정 | 값 | 설명 |
|------|---|------|
| `net_tcp_listen_port` | `6100` | Agent의 TCP/UDP, Client의 TCP 모두 이 포트 사용 |
| `net_http_port` | `6180` | REST API 포트. 브라우저에서 `http://localhost:6180`으로 접속 시 Scouter Web API 사용 가능 |
| `obj_deadtime` | `30000` | 30초간 Agent Heartbeat가 없으면 Object를 Dead 상태로 전환 |
| `log_keep_days` | `7` | 7일이 지난 XLog, Counter, Profile 데이터를 자동 삭제하여 디스크 절약 |

### 26.2 Server Dockerfile

```dockerfile
# configs/scouter/Dockerfile
FROM eclipse-temurin:11-jre                              # JRE 11 기반

ARG SCOUTER_VERSION=2.20.0                               # Scouter 버전

RUN apt-get update && apt-get install -y curl unzip \    # Scouter 다운로드·설치
    && curl -fSL "https://github.com/scouter-project/scouter/releases/download/v${SCOUTER_VERSION}/scouter-all-${SCOUTER_VERSION}.tar.gz" \
       -o /tmp/scouter.tar.gz \
    && mkdir -p /opt/scouter \
    && tar -xzf /tmp/scouter.tar.gz -C /opt/scouter --strip-components=1 \
    && rm /tmp/scouter.tar.gz

COPY server.conf /opt/scouter/server/conf/scouter.conf   # 설정 파일 복사

WORKDIR /opt/scouter/server
EXPOSE 6100 6180                                         # 포트 노출

CMD ["java", "-Xmx512m", "-classpath",                  # Server 기동
     "./scouter-server-boot.jar",
     "scouter.boot.Boot", "./lib"]
```

Server도 JVM 위에서 동작합니다. `-Xmx512m`으로 Server의 힙 메모리를 512MB로 제한합니다.

---

## 27. Prometheus/Grafana와의 비교

본 프로젝트에는 Scouter와 Prometheus/Grafana가 **동시에 구동**됩니다. 둘은 보완적 관계입니다.

### 27.1 아키텍처 비교

```
Scouter (Push 모델):
  Agent ──UDP/TCP──→ Server ──TCP──→ Client
  "Agent가 데이터를 Server로 밀어 넣는다"

Prometheus (Pull 모델):
  Exporter ←──HTTP Scrape── Prometheus ←──HTTP── Grafana
  "Prometheus가 Exporter에서 데이터를 가져간다"
```

### 27.2 기능 비교

| 항목 | Scouter | Prometheus + Grafana |
|------|---------|---------------------|
| **관점** | 트랜잭션 중심 (APM) | 메트릭 중심 (인프라) |
| **핵심 기능** | 개별 HTTP 요청 추적 (XLog) | 시계열 메트릭 집계 |
| **SQL 추적** | 지원 (JDBC Hook) | 미지원 |
| **Thread Dump** | 지원 | 미지원 |
| **Profile (상세 추적)** | 지원 | 미지원 |
| **대시보드 커스터마이징** | 제한적 (Eclipse RCP) | 매우 유연 (Grafana) |
| **알림** | 기본 제공 | AlertManager와 통합 |
| **장기 데이터 보존** | 7일 (기본) | 15일 (기본, 설정 가능) |
| **스케일링** | 단일 서버 | 클러스터 가능 (Thanos, Cortex) |

### 27.3 본 프로젝트에서의 역할 분담

| 확인하고 싶은 것 | 사용할 도구 |
|-----------------|-----------|
| "특정 API가 느린 원인이 뭐지?" | **Scouter** (XLog → Profile) |
| "어떤 SQL이 병목이지?" | **Scouter** (SQL Trace) |
| "현재 쓰레드 상태가 어떻지?" | **Scouter** (Thread Dump) |
| "Nginx의 요청 처리량 추이는?" | **Grafana** (nginx-exporter) |
| "서버 CPU/메모리/디스크 상태는?" | **Grafana** (node-exporter) |
| "지난 2주간의 메트릭 추이는?" | **Grafana** (Prometheus 15일 보존) |

> **요약**: "무엇이 느린지 찾을 때는 Scouter, 전체 인프라 상태를 볼 때는 Grafana"

---

## 28. Jennifer와의 비교

| 기능 | Jennifer | Scouter (본 프로젝트) |
|------|----------|----------------------|
| XView/XLog | XView | XLog (동일 개념) |
| TPS | TPS 차트 | TPS Counter (동일) |
| Active Service | Active Service EQ | Active Service EQ (동일) |
| Heap/GC | Heap Memory | Heap Used (동일) |
| Thread Dump | Thread Dump | Thread List/Dump (동일) |
| SQL Trace | SQL 추적 | SQL Trace (동일) |
| 실시간 알림 | Alert | Alert (동일) |
| 토폴로지 맵 | 서비스 맵 | 미지원 |
| 비즈니스 트랜잭션 | 지원 | 미지원 |
| 설치 방식 | Agent + Server + Viewer | Agent + Server + Client (동일 구조) |
| 가격 | 연간 수천만원 | 무료 (Apache 2.0) |

> **Scouter를 사용한 경험은 Jennifer 기반 모니터링 업무에 그대로 적용할 수 있습니다.**
> 용어와 개념이 거의 동일하며, Jennifer의 핵심 개발자가 만든 도구이므로 설계 철학이 같습니다.

---

## 29. 트러블슈팅

### 29.1 Scouter Client 실행 시 "손상된 앱" 오류 (macOS)

```bash
# 보안 속성 제거
xattr -cr ~/Applications/Scouter/scouter.client.app
```

### 29.2 Client에서 Object가 보이지 않음

```bash
# 1. Scouter Server 구동 확인
docker logs mw-scouter 2>&1 | grep "6100\|6180"

# 2. Tomcat에서 Agent 연결 확인
docker logs mw-tomcat1 2>&1 | grep -i scouter
docker logs mw-tomcat2 2>&1 | grep -i scouter

# 3. 포트 접근 확인
nc -z localhost 6100 && echo "OK" || echo "FAIL"
```

### 29.3 Client 접속이 안 됨

| 원인 | 해결 |
|------|------|
| Docker가 실행 중이 아님 | `docker-compose up -d` |
| 6100 포트가 사용 중 | `lsof -i :6100`으로 확인 |
| 방화벽 차단 | macOS 방화벽 설정 확인 |
| Server가 아직 기동 중 | `docker logs mw-scouter`로 기동 완료 확인 |

### 29.4 XLog에 점이 찍히지 않음

트래픽이 없으면 점이 찍히지 않습니다:

```bash
curl -sk https://localhost/health
```

실행 직후 XLog에 점이 나타나야 정상입니다. 점이 나타나지 않으면:

1. Agent가 정상 연결되었는지 확인 (Object 목록에 tomcat1/tomcat2가 보이는지)
2. `hook_service_patterns` 설정이 올바른지 확인
3. Tomcat 로그에서 Scouter Agent 관련 에러 확인

### 29.5 Object가 여러 개 보임 (중복)

컨테이너를 재빌드하면 이전 Object가 Dead 상태로 남아있습니다:

- `obj_deadtime=30000` (30초) 후 자동 제거됩니다
- 즉시 제거: 회색 Object 우클릭 → **Delete**
- 또는 Scouter Server 컨테이너 재시작: `docker restart mw-scouter`

### 29.6 Agent 오버헤드가 의심될 때

Agent를 비활성화하여 비교 테스트:

```bash
# docker-compose.yml에서 JAVA_OPTS의 -javaagent 줄을 주석 처리
# 또는 agent.conf에서:
hook_method_patterns=
hook_service_patterns=
counter_enabled=false
```

이후 동일한 부하 테스트를 실행하여 응답시간을 비교합니다. 일반적으로 **1~3% 이내**의 차이가 정상입니다.

---

# Part 5. 실습 과제

> 아래 실습은 난이도 순으로 구성되어 있습니다. 각 실습을 완료하면 Scouter APM의 핵심 역량을 체득할 수 있습니다.
> 모든 실습의 전제 조건: `docker-compose up -d`로 전체 환경이 구동 중이어야 합니다.

## 30. 실습 1 — 첫 번째 XLog 점 찍기 (난이도: ★☆☆☆☆)

### 목표

Scouter Client를 설치하고 접속하여, 직접 보낸 요청이 XLog에 점으로 나타나는 것을 확인합니다.

### 실습 순서

```
Step 1. Scouter Client 설치 (Ch.4 참고)
Step 2. Scouter Client 실행 → 127.0.0.1:6100 접속 (admin/admin)
Step 3. 좌측 Object에서 tomcat1 우클릭 → XLog 열기
Step 4. 터미널에서 아래 명령 실행:
```

```bash
curl -sk https://localhost/health
```

### 확인할 것

- [ ] XLog 차트에 **파란색 점 1개**가 나타나는가?
- [ ] 점의 Y축(응답시간)이 **100ms 이하**인가?
- [ ] 점을 클릭했을 때 Profile에서 **URL: /health**가 보이는가?

### 학습 포인트

> 이 한 번의 curl 명령으로 일어난 일:
> Agent가 Servlet 진입을 감지 → TraceContext 생성 → 메서드 실행 추적 → XLog Pack 생성 → UDP로 Server 전송 → Client에 실시간 Push → 점이 그려짐

---

## 31. 실습 2 — 대시보드 구성과 실시간 관찰 (난이도: ★★☆☆☆)

### 목표

6개의 모니터링 뷰를 한 화면에 배치하고, 부하를 주면서 모든 차트가 동시에 반응하는 것을 관찰합니다.

### 실습 순서

```
Step 1. 아래 6개 뷰를 모두 열기:
   - tomcat1 우클릭 → XLog
   - tomcat1 우클릭 → Counter → TPS
   - tomcat1 우클릭 → Counter → Active Service
   - tomcat1 우클릭 → Counter → Heap Used
   - tomcat1 우클릭 → Counter → GC Time
   - tomcat1 우클릭 → Active Service EQ

Step 2. 창을 드래그하여 한 화면에 6개가 다 보이도록 배치

Step 3. 터미널에서 부하 생성:
```

```bash
# 10병렬 × 100회 = 1000건 요청
for i in $(seq 1 100); do
  for j in $(seq 1 10); do
    curl -sk https://localhost/ > /dev/null &
  done
  wait
done
```

### 확인할 것

- [ ] **XLog**: 점이 대량으로 찍히는가?
- [ ] **TPS**: 0에서 상승하여 피크를 찍는가?
- [ ] **Active Service**: 부하 중에 숫자가 올라가는가?
- [ ] **Heap Used**: 메모리 사용량이 증가하는가?
- [ ] **GC Time**: GC가 발생하는가? (Heap 상승 후 급락과 연관)
- [ ] **Active Service EQ**: 녹색 막대가 나타나는가?

### 학습 포인트

> 하나의 부하 테스트로 **6개 뷰가 동시에 반응**합니다. 이것이 APM의 종합 모니터링 능력입니다.
> 각 뷰는 같은 데이터의 다른 측면을 보여줍니다: XLog=개별 요청, TPS=처리량, Active=동시성, Heap/GC=자원 소모.

---

## 32. 실습 3 — XLog 드래그로 느린 요청 필터링 (난이도: ★★☆☆☆)

### 목표

다양한 URL에 대한 부하를 주고, XLog에서 특정 응답시간 범위의 요청만 드래그로 선택하여 분석합니다.

### 실습 순서

```
Step 1. XLog 차트를 열어둠

Step 2. 터미널에서 다양한 URL로 요청:
```

```bash
# 빠른 요청 (/, /health)과 다양한 URL 혼합
for i in $(seq 1 50); do
  curl -sk https://localhost/ > /dev/null &
  curl -sk https://localhost/health > /dev/null &
  curl -sk https://localhost/info > /dev/null &
done
wait
```

```
Step 3. XLog 차트에서 응답시간 200ms 이상인 영역을 마우스로 드래그
Step 4. 팝업된 목록에서 각 요청을 클릭하여 Profile 확인
```

### 확인할 것

- [ ] 드래그 선택 시 **해당 범위의 요청만** 목록에 나타나는가?
- [ ] 각 요청의 **URL 경로** (/, /health, /info)가 다른가?
- [ ] Profile에서 **메서드 호출 순서**가 URL마다 다르게 보이는가?

### 학습 포인트

> XLog 드래그 선택은 **"느린 요청만 골라서 분석"**하는 핵심 기술입니다.
> 운영 환경에서 "갑자기 느려졌다"는 보고를 받았을 때, 해당 시간대의 XLog를 드래그하면 원인을 빠르게 파악할 수 있습니다.

---

## 33. 실습 4 — 로드밸런싱 분포 확인 (난이도: ★★★☆☆)

### 목표

tomcat1과 tomcat2 각각의 XLog와 TPS를 열어두고, Nginx 로드밸런싱이 균등하게 분배되는지 Scouter로 직접 확인합니다.

### 실습 순서

```
Step 1. 뷰 열기 (총 4개):
   - tomcat1 우클릭 → XLog
   - tomcat2 우클릭 → XLog
   - tomcat1 우클릭 → Counter → TPS
   - tomcat2 우클릭 → Counter → TPS

Step 2. 2개의 XLog 창을 좌우로, 2개의 TPS 창을 아래에 배치

Step 3. 부하 생성:
```

```bash
# 200건 요청 — Nginx가 Round Robin으로 분배
for i in $(seq 1 200); do
  curl -sk https://localhost/health > /dev/null
done
```

### 확인할 것

- [ ] 두 XLog 차트에 **비슷한 수의 점**이 찍히는가? (Round Robin이므로 약 100:100)
- [ ] 두 TPS 차트의 **피크 값이 비슷**한가?
- [ ] 한쪽에만 점이 몰리지 않는가?

### 심화 — WAS 1대 중단 후 관찰

```bash
# tomcat2 중지
docker stop mw-tomcat2

# 요청 계속
for i in $(seq 1 50); do curl -sk https://localhost/health > /dev/null; done

# Scouter에서 확인:
# - tomcat2의 Object가 회색으로 변경
# - tomcat1의 TPS만 상승, tomcat2의 TPS = 0

# 복구
docker start mw-tomcat2
```

### 확인할 것 (심화)

- [ ] tomcat2 중지 후 **Object 아이콘이 회색**으로 변하는가? (약 30초 후)
- [ ] tomcat2 중지 상태에서 **tomcat1의 TPS가 2배**가 되는가?
- [ ] tomcat2 재시작 후 Object가 다시 **파란색**으로 돌아오는가?

### 학습 포인트

> Scouter로 **로드밸런싱이 정상 동작하는지** 실시간 검증할 수 있습니다.
> 운영 환경에서 "특정 서버에 트래픽이 몰린다"는 상황도 두 Object의 TPS를 비교하면 바로 확인 가능합니다.

---

## 34. 실습 5 — GC와 응답시간의 상관관계 분석 (난이도: ★★★☆☆)

### 목표

대량의 객체를 생성하는 부하를 줘서 GC를 유발하고, GC 발생 시점과 XLog 응답시간 상승의 상관관계를 직접 확인합니다.

### 실습 순서

```
Step 1. 뷰 열기 (3개):
   - tomcat1 우클릭 → XLog
   - tomcat1 우클릭 → Counter → Heap Used
   - tomcat1 우클릭 → Counter → GC Time

Step 2. 3개 창을 세로로 배치하여 시간축을 맞춤

Step 3. 대량 요청으로 객체 생성 유도:
```

```bash
# /info 엔드포인트는 Runtime 객체를 조회하므로 객체 생성이 많음
# 20병렬 × 200회 = 4000건
for round in $(seq 1 200); do
  for p in $(seq 1 20); do
    curl -sk https://localhost/info > /dev/null &
  done
  wait
done
```

### 확인할 것

- [ ] **Heap Used**: 톱니 모양 (상승→급락→상승→급락) 패턴이 보이는가?
- [ ] **GC Time**: Heap 급락 시점에 GC Time 스파이크가 나타나는가?
- [ ] **XLog**: GC Time 스파이크 시점에 응답시간이 높은 점이 나타나는가?

### 그래프 정렬 비교

```
시간축 →     t1        t2        t3
             │         │         │
Heap Used:   /\        /\        /\
            /  ↘      /  ↘      /  ↘   ← GC로 급락
           /    \    /    \    /    \
──────────/──────\──/──────\──/──────\──

GC Time:      █         █         █     ← 급락 시점에 스파이크

XLog (ms):   ●●        ●●        ●●    ← GC 시점에 높은 점
           ●●  ●●    ●●  ●●    ●●  ●●
```

### 학습 포인트

> **"GC가 발생하면 모든 쓰레드가 멈추므로 응답시간이 올라간다"**는 이론을 직접 눈으로 확인합니다.
> 운영 환경에서 "주기적으로 느려진다"는 증상이 있으면, Heap과 GC Time을 함께 보는 것이 첫 번째 진단 단계입니다.

---

## 35. 실습 6 — Thread Dump로 병목 진단 (난이도: ★★★☆☆)

### 목표

부하 상태에서 Thread Dump를 뜨고, 현재 어떤 쓰레드가 어떤 일을 하고 있는지 분석합니다.

### 실습 순서

```
Step 1. 터미널에서 지속적 부하 생성 (백그라운드):
```

```bash
# 30초간 지속적 부하
for i in $(seq 1 300); do
  curl -sk https://localhost/ > /dev/null &
  curl -sk https://localhost/health > /dev/null &
  curl -sk https://localhost/info > /dev/null &
  sleep 0.1
done &
LOAD_PID=$!
```

```
Step 2. 부하가 돌고 있는 동안 Scouter Client에서:
   - tomcat1 우클릭 → Thread List
   - 또는 tomcat1 우클릭 → Thread Dump

Step 3. Thread 목록을 관찰
```

### 확인할 것

- [ ] `http-nio-8080-exec-*` 쓰레드 중 **RUNNABLE** 상태인 것이 있는가?
- [ ] RUNNABLE 쓰레드의 스택트레이스에서 **HealthController** 또는 **SecuredController**가 보이는가?
- [ ] **WAITING** 상태의 쓰레드는 무엇을 기다리고 있는가?
- [ ] `GC task thread` 등의 **JVM 내부 쓰레드**가 보이는가?

```
Step 4. 부하 중지:
```

```bash
kill $LOAD_PID 2>/dev/null; wait 2>/dev/null
```

```
Step 5. 부하 중지 후 다시 Thread Dump를 떠서 비교
```

### 확인할 것 (비교)

- [ ] 부하 중: exec 쓰레드가 **RUNNABLE** 상태
- [ ] 부하 후: exec 쓰레드가 **WAITING/TIMED_WAITING** 상태 (요청 대기)
- [ ] 쓰레드 상태 변화가 **Active Service 차트의 변화**와 일치하는가?

### 학습 포인트

> Thread Dump는 **"지금 이 순간 서버가 정확히 무슨 일을 하고 있는지"**를 보여주는 스냅샷입니다.
> 운영 환경에서 "서버가 멈췄다"는 상황에서 Thread Dump를 뜨면, BLOCKED된 쓰레드 → 락을 잡고 있는 쓰레드 → 진짜 원인을 추적할 수 있습니다.

---

## 36. 실습 7 — 에러 추적과 빨간 점 분석 (난이도: ★★★☆☆)

### 목표

존재하지 않는 URL로 요청을 보내 의도적으로 에러를 발생시키고, XLog에서 빨간 점(에러 트랜잭션)을 추적합니다.

### 실습 순서

```
Step 1. XLog 차트를 열어둠

Step 2. 정상 요청과 에러 요청을 섞어서 보냄:
```

```bash
# 정상 요청 10건
for i in $(seq 1 10); do
  curl -sk https://localhost/health > /dev/null
done

# 에러 요청 10건 (존재하지 않는 URL)
for i in $(seq 1 10); do
  curl -sk https://localhost/nonexistent/path > /dev/null
done

# 정상 요청 10건
for i in $(seq 1 10); do
  curl -sk https://localhost/info > /dev/null
done
```

```
Step 3. XLog에서 빨간 점을 찾아 클릭
Step 4. Profile에서 에러 정보 확인
```

### 확인할 것

- [ ] **파란 점**(정상)과 **빨간 점**(에러)이 구분되어 나타나는가?
- [ ] 빨간 점의 Profile에서 **에러 메시지**가 확인되는가?
- [ ] 빨간 점의 **URL 경로**가 `/nonexistent/path`인가?

### 학습 포인트

> XLog의 색상은 즉각적인 이상 징후 파악 도구입니다.
> 빨간 점이 갑자기 늘어나면 에러가 급증한 것이므로, 클릭하여 원인을 바로 확인할 수 있습니다.
> 이것은 로그를 grep하는 것보다 훨씬 빠른 진단 방법입니다.

---

## 37. 실습 8 — 전체 대시보드 시나리오 실행 (난이도: ★★★★☆)

### 목표

`load-test.sh`의 대시보드 시나리오(시나리오 6)를 실행하면서, 7개 Phase에 따른 모든 그래프의 변화를 관찰하고 기록합니다.

### 실습 순서

```
Step 1. Scouter Client에서 최대한 많은 뷰를 열기:
   - XLog (tomcat1 + tomcat2)
   - TPS (tomcat1 + tomcat2)
   - Active Service
   - Active Service EQ
   - Heap Used
   - GC Time
   - CPU
   - Alert

Step 2. 터미널에서:
```

```bash
./scripts/load-test.sh 6
```

```
Step 3. 스크립트가 실행되는 동안 (~2.5분) 화면 주시
Step 4. 각 Phase 전환 시점의 그래프 변화를 관찰 (스크립트가 Phase를 출력함)
```

### Phase별 관찰 기록표

아래 표를 채워가면서 관찰합니다:

| Phase | XLog 변화 | TPS | Active Service | Heap | GC | EQ 색상 |
|-------|----------|-----|----------------|------|----|---------|
| 1. Warm-up | | | | | | |
| 2. Ramp-up | | | | | | |
| 3. Burst | | | | | | |
| 4. Mixed Heavy | | | | | | |
| 5. Error Injection | | | | | | |
| 6. Recovery | | | | | | |
| 7. Spike | | | | | | |

### 확인할 것

- [ ] **Phase 3 (Burst)** 에서 TPS가 **최고치**를 기록하는가?
- [ ] **Phase 5 (Error)** 에서 XLog에 **빨간 점**이 나타나는가?
- [ ] **Phase 6 (Recovery)** 에서 모든 지표가 **점진적으로 하강**하는가?
- [ ] **Phase 7 (Spike)** 에서 모든 지표가 **마지막 급등** 후 안정되는가?
- [ ] tomcat1과 tomcat2의 TPS가 **비슷하게 분배**되는가? (Round Robin)

### 학습 포인트

> 이 실습은 APM 모니터링의 **종합 시뮬레이션**입니다.
> 실제 운영 환경에서 일어나는 상황(트래픽 증가, 폭주, 에러 급증, 복구)을 2.5분에 압축 체험합니다.
> "그래프가 이렇게 움직이면 이런 상황이다"라는 **패턴 인식 능력**을 기르는 것이 목표입니다.

---

## 38. 실습 9 — Object 생명주기 관찰 (난이도: ★★★★☆)

### 목표

Tomcat 컨테이너를 중지/시작/재빌드하면서, Scouter Client의 Object 상태 변화를 관찰합니다.

### 실습 순서

```
Step 1. Scouter Client 좌측 Object 패널 주시
   현재 상태: tomcat1(파란), tomcat2(파란)

Step 2. Tomcat #2 중지:
```

```bash
docker stop mw-tomcat2
```

```
Step 3. Scouter Client에서 tomcat2 Object 관찰
   - 즉시 변하지 않음
   - 약 30초 후 (obj_deadtime=30000) 회색으로 변경

Step 4. Tomcat #2 재시작:
```

```bash
docker start mw-tomcat2
```

```
Step 5. tomcat2가 다시 파란색으로 돌아오는 것 확인

Step 6. 컨테이너 재빌드 (심화):
```

```bash
docker-compose up --build -d tomcat2
```

```
Step 7. Object 패널에서 tomcat2가 일시적으로 2개 보이는 현상 관찰
   - 새 tomcat2 (Active, 파란)
   - 이전 tomcat2 (Dead, 회색) → 30초 후 자동 제거
```

### 확인할 것

- [ ] `docker stop` 후 **정확히 30초** 후에 Object가 회색으로 변하는가?
- [ ] `docker start` 후 Object가 **즉시** 파란색으로 돌아오는가?
- [ ] 재빌드 시 **일시적으로 중복 Object**가 보이는가?
- [ ] Dead Object가 **자동으로 사라지는** 것을 확인할 수 있는가?

### 학습 포인트

> `obj_deadtime=30000`은 **"30초간 Heartbeat가 없으면 죽은 것으로 간주"**라는 의미입니다.
> 이 값을 이해하면 운영 환경에서 "Agent가 갑자기 사라졌다", "Object가 중복으로 보인다" 같은 상황을 즉시 해석할 수 있습니다.

---

## 39. 실습 10 — Agent 원격 설정 변경 (난이도: ★★★★★)

### 목표

Scouter Client에서 Agent 설정을 **원격으로 변경**하고, 변경 결과를 실시간으로 확인합니다.

### 실습 순서

```
Step 1. tomcat1 우클릭 → Configure 선택
   - 현재 Agent의 모든 설정값이 표시됨

Step 2. 설정값 확인:
   - hook_method_patterns = com.middleware.demo.*.*
   - xlog_sampling_enabled = false
   - profile_step_max_count = 1024

Step 3. XLog를 열어둔 상태에서 요청 보내기:
```

```bash
for i in $(seq 1 20); do curl -sk https://localhost/health > /dev/null; done
```

```
Step 4. XLog에 20개의 점이 찍히는 것 확인

Step 5. Configure에서 xlog_sampling_enabled = true로 변경
   - xlog_sampling_step1 = 100 (TPS 100 이하에서 50% 샘플링)
   → Apply 클릭

Step 6. 같은 요청을 다시 보내기:
```

```bash
for i in $(seq 1 20); do curl -sk https://localhost/health > /dev/null; done
```

```
Step 7. XLog에 찍히는 점의 수가 줄어드는지 확인 (샘플링 적용)

Step 8. 원래대로 복원: xlog_sampling_enabled = false → Apply
```

### 확인할 것

- [ ] Configure 뷰에서 **현재 Agent 설정**이 모두 보이는가?
- [ ] 설정 변경 후 **Agent 재시작 없이** 바로 적용되는가?
- [ ] 샘플링 활성화 시 **XLog 점의 수가 감소**하는가?
- [ ] 설정을 원복하면 **다시 모든 점**이 찍히는가?

### 학습 포인트

> Agent 원격 설정 변경은 **운영 환경에서 매우 유용**한 기능입니다.
> 트래픽이 많을 때 샘플링을 켜서 Server 부하를 줄이고, 문제 분석 시 샘플링을 끄고 모든 요청을 추적하는 등,
> **서비스 재시작 없이** 유연하게 모니터링 전략을 조정할 수 있습니다.

---

## 40. 실습 11 — 과거 데이터 조회와 일간 분석 (난이도: ★★★☆☆)

### 목표

실시간 모니터링뿐 아니라, 과거 시간대의 XLog와 Counter를 조회하는 방법을 익힙니다.

### 실습 순서

```
Step 1. 먼저 데이터를 쌓기 위해 부하 생성:
```

```bash
# 1분간 지속적 부하
for i in $(seq 1 60); do
  curl -sk https://localhost/health > /dev/null
  curl -sk https://localhost/info > /dev/null
  sleep 1
done
```

```
Step 2. 5분 정도 기다린 후 과거 데이터 조회:

Step 3. tomcat1 우클릭 → Load XLog
   - From: 부하를 줬던 시작 시각
   - To: 부하가 끝난 시각
   → OK 클릭

Step 4. 과거 시간대의 XLog가 로드되어 표시됨

Step 5. 메뉴바 → Daily Counter 선택
   - tomcat1 선택 → TPS, Heap Used 등 확인
   - 오늘 하루 동안의 Counter 추이를 한눈에 파악
```

### 확인할 것

- [ ] **Load XLog**로 과거 시간대의 트랜잭션을 조회할 수 있는가?
- [ ] 과거 XLog에서 **점 클릭 → Profile 조회**가 가능한가?
- [ ] **Daily Counter**에서 오늘 하루의 TPS/Heap 추이가 보이는가?
- [ ] 부하를 줬던 시간대에 **TPS 피크**가 Daily Counter에 나타나는가?

### 학습 포인트

> 과거 데이터 조회는 **사후 분석(Post-mortem Analysis)**의 핵심입니다.
> "어제 오후 3시에 장애가 있었다"는 보고를 받았을 때, Load XLog로 해당 시간대를 로드하면
> 어떤 요청이 느렸는지, 에러가 있었는지를 그때의 데이터로 분석할 수 있습니다.

---

## 41. 실습 12 — 종합 장애 시뮬레이션과 진단 (난이도: ★★★★★)

### 목표

WAS 장애 상황을 시뮬레이션하고, Scouter로 장애를 감지 → 원인 분석 → 복구 확인하는 전체 사이클을 수행합니다.

### 시나리오

> "사용자로부터 '사이트가 느려졌다'는 보고가 들어왔다. Scouter로 원인을 추적하라."

### 실습 순서

```
Phase 1. 정상 상태 확인 (Baseline)
```

```bash
# 정상 트래픽 20초간
for i in $(seq 1 20); do
  curl -sk https://localhost/health > /dev/null
  sleep 1
done
```

Scouter 확인: XLog 정상, TPS ~1, Active Service 0~1

```
Phase 2. 장애 주입 — Tomcat #2 중지
```

```bash
docker stop mw-tomcat2
```

```
Phase 3. 장애 상태에서 부하 (장애 관찰)
```

```bash
# Tomcat 1대만 살아있는 상태에서 부하
for i in $(seq 1 100); do
  for j in $(seq 1 5); do
    curl -sk https://localhost/ > /dev/null &
  done
  wait
done
```

Scouter 확인:
- tomcat2 Object가 회색 (Dead)
- tomcat1의 TPS만 상승 (평소의 2배)
- tomcat1의 Active Service 증가

```
Phase 4. Thread Dump 분석
```

- tomcat1 우클릭 → Thread Dump
- `http-nio-8080-exec-*` 쓰레드의 상태 확인
- RUNNABLE 쓰레드가 많으면 → 서버가 열심히 일하고 있음 (과부하)

```
Phase 5. 장애 복구
```

```bash
docker start mw-tomcat2
```

```
Phase 6. 복구 확인
```

```bash
# 복구 후 부하
for i in $(seq 1 50); do
  curl -sk https://localhost/health > /dev/null
done
```

Scouter 확인:
- tomcat2 Object가 파란색으로 복구
- TPS가 tomcat1, tomcat2에 균등 분배
- Active Service 정상 수준으로 복귀

### 진단 보고서 작성 연습

실습 후 아래 형식으로 정리해 봅니다:

```
장애 보고서
──────────
발생 시각: ____
감지 방법: Scouter Object 패널에서 tomcat2 Dead 확인
영향 범위: tomcat1에 트래픽 집중, TPS __→__ 증가, Active Service __→__ 증가
원인: tomcat2 프로세스 중지 (docker stop)
복구 시각: ____
복구 방법: docker start mw-tomcat2
복구 확인: Object 파란색 전환, TPS 균등 분배 정상화
```

### 학습 포인트

> 이 실습은 **실제 운영 장애 대응 사이클**을 시뮬레이션합니다:
> 1. 정상 Baseline 파악
> 2. 이상 징후 감지 (Object Dead, TPS 편중)
> 3. Thread Dump 등으로 원인 분석
> 4. 복구 조치
> 5. 복구 후 정상화 확인
>
> 이 프로세스를 몸에 익혀두면, 실제 장애 상황에서 당황하지 않고 체계적으로 대응할 수 있습니다.

---

## 실습 체크리스트 요약

| 실습 | 난이도 | 핵심 학습 | 소요 시간 |
|------|--------|----------|----------|
| 실습 1: 첫 XLog 점 | ★☆☆☆☆ | Agent→Server→Client 데이터 흐름 이해 | 5분 |
| 실습 2: 대시보드 구성 | ★★☆☆☆ | 6개 뷰의 역할과 상관관계 | 10분 |
| 실습 3: XLog 드래그 | ★★☆☆☆ | 느린 요청 필터링과 Profile 분석 | 10분 |
| 실습 4: 로드밸런싱 분포 | ★★★☆☆ | 다중 WAS의 트래픽 분배 검증 | 15분 |
| 실습 5: GC 상관관계 | ★★★☆☆ | GC↔응답시간 인과 관계 확인 | 15분 |
| 실습 6: Thread Dump | ★★★☆☆ | 쓰레드 상태 분석과 병목 진단 | 15분 |
| 실습 7: 에러 추적 | ★★★☆☆ | 빨간 점 분석과 에러 프로파일링 | 10분 |
| 실습 8: 전체 시나리오 | ★★★★☆ | 7-Phase 종합 모니터링 | 20분 |
| 실습 9: Object 생명주기 | ★★★★☆ | Agent 연결/해제/재빌드 관찰 | 15분 |
| 실습 10: 원격 설정 | ★★★★★ | 운영 중 Agent 설정 동적 변경 | 15분 |
| 실습 11: 과거 데이터 | ★★★☆☆ | 사후 분석 (Post-mortem) | 10분 |
| 실습 12: 장애 시뮬레이션 | ★★★★★ | 장애 감지→분석→복구 전체 사이클 | 30분 |

> **추천 학습 경로**: 실습 1 → 2 → 3 → 7 → 4 → 5 → 6 → 8 → 11 → 9 → 10 → 12

---

## 용어 사전

| 용어 | 영문 | 설명 |
|------|------|------|
| 바이트코드 변조 | Bytecode Instrumentation | JVM 클래스 로딩 시점에 .class 파일의 바이트코드를 변경하는 기술 |
| 에이전트 | Agent | JVM에 부착되어 성능 데이터를 수집하는 컴포넌트 |
| 콜렉터 | Collector/Server | Agent로부터 데이터를 수집·저장하는 중앙 서버 |
| 프로파일 | Profile | 하나의 트랜잭션 내부의 메서드 호출, SQL, API 호출 등의 상세 기록 |
| 트랜잭션 | Transaction | 하나의 HTTP 요청-응답 사이클 |
| 카운터 | Counter | 주기적으로 수집되는 수치형 성능 지표 (TPS, Heap, CPU 등) |
| 오브젝트 | Object | 모니터링 대상 (본 프로젝트에서는 Tomcat 인스턴스) |
| 텍스트 사전 | Text Dictionary | URL/SQL 문자열을 해시값으로 변환하여 대역폭을 절약하는 기법 |
| 이퀄라이저 | Equalizer (EQ) | Active Service의 경과 시간을 색상 막대로 시각화한 뷰 |
