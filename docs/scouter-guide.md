# Scouter APM 완전 가이드

> Scouter는 **LG CNS의 Jennifer APM 핵심 개발자**가 만든 오픈소스 APM(Application Performance Monitoring) 도구로,
> Jennifer의 핵심 개념(XView, Active Service EQ, TPS)을 그대로 계승하면서 무료로 사용할 수 있다.

---

## 이 책의 구성

이 문서는 **한 권의 책**처럼 기승전결 구조로 설계되었다. 처음부터 순서대로 읽으면 Scouter를 "설치하는 사람"에서 "이해하고 활용하는 사람"으로 성장하는 과정을 따라갈 수 있다.

```
이 책의 여정:

  Part 1. 개요와 설치          "Scouter가 뭔지 알고, 직접 설치해서 화면을 본다"
       │
       ▼
  Part 2. 내부 동작 메커니즘    "화면 뒤에서 무슨 일이 벌어지는지 이해한다"
       │
       ▼
  Part 3. 모니터링 뷰 가이드    "각 그래프가 무엇을 보여주는지, 패턴을 읽는다"
       │
       ▼
  Part 4. 실전 활용            "대시보드를 구성하고, 실제 문제를 진단한다"
       │
       ▼
  Part 5. 실습 과제            "직접 손으로 해보며 몸에 익힌다"
```

**읽는 방법:**
- **시간이 충분하다면**: Part 1 → 2 → 3 → 4 → 5 순서대로 읽는다.
- **빨리 써보고 싶다면**: Part 1 → 3 → 5(실습 1~3) → Part 2 → 4 순서로 읽는다.
- **이미 APM을 알고 있다면**: Part 2(내부 메커니즘)부터 시작한다.

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
13. [Scouter 소스코드 아키텍처](#13-scouter-소스코드-아키텍처)

**Part 3. 모니터링 뷰 완전 가이드**
14. [XLog — 트랜잭션 분석의 핵심](#14-xlog--트랜잭션-분석의-핵심)
15. [TPS 모니터링](#15-tps-모니터링)
16. [Active Service 모니터링](#16-active-service-모니터링)
17. [JVM 힙 메모리 모니터링](#17-jvm-힙-메모리-모니터링)
18. [GC 모니터링](#18-gc-모니터링)
19. [쓰레드 분석](#19-쓰레드-분석)
20. [SQL 추적과 프로파일링](#20-sql-추적과-프로파일링)
21. [Active Service EQ (이퀄라이저)](#21-active-service-eq-이퀄라이저)
22. [전체 뷰 카탈로그](#22-전체-뷰-카탈로그)

**Part 4. 실전 활용**
23. [대시보드 구성하기](#23-대시보드-구성하기)
24. [부하 테스트와 함께 모니터링하기](#24-부하-테스트와-함께-모니터링하기)
25. [알림 설정](#25-알림-설정)
26. [Agent 설정 상세 레퍼런스](#26-agent-설정-상세-레퍼런스)
27. [Server 설정 상세 레퍼런스](#27-server-설정-상세-레퍼런스)
28. [Prometheus/Grafana와의 비교](#28-prometheusgrafana와의-비교)
29. [Jennifer와의 비교](#29-jennifer와의-비교)
30. [프로덕션 환경 튜닝 가이드](#30-프로덕션-환경-튜닝-가이드)
31. [트러블슈팅](#31-트러블슈팅)

**Part 5. 실습 과제**
32. [실습 1 — 첫 번째 XLog 점 찍기](#32-실습-1--첫-번째-xlog-점-찍기) (★☆☆☆☆)
33. [실습 2 — 대시보드 구성과 실시간 관찰](#33-실습-2--대시보드-구성과-실시간-관찰) (★★☆☆☆)
34. [실습 3 — XLog 드래그로 느린 요청 필터링](#34-실습-3--xlog-드래그로-느린-요청-필터링) (★★☆☆☆)
35. [실습 4 — 로드밸런싱 분포 확인](#35-실습-4--로드밸런싱-분포-확인) (★★★☆☆)
36. [실습 5 — GC와 응답시간의 상관관계 분석](#36-실습-5--gc와-응답시간의-상관관계-분석) (★★★☆☆)
37. [실습 6 — Thread Dump로 병목 진단](#37-실습-6--thread-dump로-병목-진단) (★★★☆☆)
38. [실습 7 — 에러 추적과 빨간 점 분석](#38-실습-7--에러-추적과-빨간-점-분석) (★★★☆☆)
39. [실습 8 — 전체 대시보드 시나리오 실행](#39-실습-8--전체-대시보드-시나리오-실행) (★★★★☆)
40. [실습 9 — Object 생명주기 관찰](#40-실습-9--object-생명주기-관찰) (★★★★☆)
41. [실습 10 — Agent 원격 설정 변경](#41-실습-10--agent-원격-설정-변경) (★★★★★)
42. [실습 11 — 과거 데이터 조회와 일간 분석](#42-실습-11--과거-데이터-조회와-일간-분석) (★★★☆☆)
43. [실습 12 — 종합 장애 시뮬레이션과 진단](#43-실습-12--종합-장애-시뮬레이션과-진단) (★★★★★)

---

# Part 1. 개요와 설치

## 1. Scouter란 무엇인가

### 1.1 APM이란?

APM(Application Performance Monitoring)은 애플리케이션의 **실시간 성능을 관찰하고 병목을 진단**하는 도구이다. 단순히 CPU/메모리를 보는 인프라 모니터링과 달리, APM은 **개별 HTTP 요청 하나하나를 추적**하여 "어떤 URL이 느린지", "어떤 SQL이 병목인지"를 알려준다.

### 1.2 Scouter의 위치

```
인프라 모니터링          APM (트랜잭션 추적)        로그 수집
────────────           ──────────────────        ──────────
Prometheus/Grafana     ★ Scouter ★              ELK Stack
Zabbix, Nagios         Jennifer (상용)           Loki
node-exporter          Pinpoint (오픈소스)       Fluentd
                       Zipkin/Jaeger (분산추적)
```

Scouter는 **Java 전용 APM**으로, JVM 위에서 동작하는 Tomcat, Spring Boot, Jetty 등의 애플리케이션을 모니터링한다.

### 1.3 왜 Scouter인가?

| 항목 | Scouter | Jennifer | Pinpoint |
|------|---------|----------|----------|
| 라이선스 | Apache 2.0 (무료) | 상용 (연간 수천만원) | Apache 2.0 (무료) |
| 설치 복잡도 | 낮음 (Agent + Server) | 낮음 | 높음 (HBase 필요) |
| 실시간성 | ★★★★★ (2초 주기) | ★★★★★ | ★★★★ |
| XLog/XView | 지원 | 지원 (원조) | 유사 기능 |
| 경량성 | Agent 오버헤드 < 3% | Agent 오버헤드 < 3% | Agent 오버헤드 5~10% |
| 한국어 자료 | 풍부 | 매우 풍부 | 풍부 |

> **핵심**: Scouter를 사용한 경험은 Jennifer 기반 모니터링 업무에 **그대로 적용**할 수 있다. 개념과 용어가 거의 동일하다.

---

## 2. 아키텍처 — 3-Tier 구조

Scouter는 **Agent**, **Server(Collector)**, **Client(Viewer)** 3개의 컴포넌트로 구성된다.

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

`-javaagent` 옵션이 Scouter의 모든 동작의 출발점이다. JVM이 클래스를 로드할 때 Agent의 `premain()` 메서드가 먼저 호출되어, 바이트코드 변조 엔진이 활성화된다.

---

## 4. Scouter Client 설치

> Scouter Client는 Homebrew에 등록되어 있지 않는다. GitHub Releases에서 직접 다운로드한다.

### macOS - Apple Silicon (M1/M2/M3/M4)

```bash
# 1. 다운로드
curl -L -o /tmp/scouter-client-mac.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-macosx.cocoa.aarch64.tar.gz

# 2. 설치 디렉토리 생성 및 압축 해제
mkdir -p ~/Applications/Scouter
tar -xzf /tmp/scouter-client-mac.tar.gz -C ~/Applications/Scouter

# 3. macOS 보안 속성(quarantine) 제거
#    ⚠️ 이 단계를 빠뜨리면 "손상된 앱이므로 열 수 없다" 오류 발생
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

Docker 환경이 구동 중이어야 한다:

```bash
# 프로젝트 디렉토리에서
docker-compose up -d

# Scouter Server가 구동 중인지 확인
docker logs mw-scouter 2>&1 | tail -5
# → "Started ServerConnector@...{HTTP/1.1}{0.0.0.0:6180}" 가 보이면 정상
```

### 5.2 접속 정보

Scouter Client 실행 후 아래 정보를 입력한다:

| 항목 | 값 |
|------|------|
| **Server Address** | `127.0.0.1` |
| **Port** | `6100` |
| **ID** | `admin` |
| **Password** | `admin` |

### 5.3 접속 성공 확인

접속에 성공하면 좌측 **Object** 패널에 아래와 같이 표시된다:

```
▼ /middleware
   ├─ tomcat1    ← Tomcat #1 Agent
   └─ tomcat2    ← Tomcat #2 Agent
```

> Object가 보이지 않으면 Tomcat 컨테이너가 아직 기동 중이거나 Agent 설정에 문제가 있는 것이다. [트러블슈팅](#31-트러블슈팅) 섹션을 참고한다.

### Part 1 정리 — 여기까지 온 당신의 현재 위치

Part 1을 마치면 다음 상태가 된다:

```
✓ Scouter가 무엇인지 안다 (APM, Jennifer 계보)
✓ 3-Tier 아키텍처를 이해한다 (Agent → Server → Client)
✓ Docker 환경에서 Scouter가 어떻게 배포되어 있는지 안다
✓ Client를 설치하고 접속하여 Object 목록을 확인했다
```

이제 터미널에서 `curl -sk https://localhost/health`를 실행하면 Scouter Client의 XLog 화면에 **파란 점 하나**가 찍힙니다. 축하한다 — Scouter가 동작하고 있다.

하지만 이 시점에서 떠오르는 질문이 있을 것이다:
- "소스코드를 한 줄도 안 고쳤는데, **어떻게** 요청을 감지한 거지?"
- "데이터가 Agent에서 Server로 **어떻게** 전달된 거지?"
- "그 점의 **위치**(X축, Y축)는 어떻게 결정된 거지?"

Part 2에서 이 질문들에 정확히 답한다.

---

# Part 2. 내부 동작 메커니즘

> Part 1에서 Scouter를 설치하고 Client를 접속했다. Object 패널에 tomcat1, tomcat2가 보이고, curl을 치면 XLog에 점이 찍힙니다. **하지만 여기서 멈추면 Scouter는 "그냥 그래프 보는 도구"로 끝난다.**
>
> Part 2에서는 그 점 하나가 **어떻게** 만들어지는지를 추적한다. Agent가 바이트코드를 어떻게 변조하고(6장), 수집한 데이터를 어떤 프로토콜로 Server에 보내며(7장), Server가 이를 어떻게 가공·저장하는지(8~11장)를 이해하면, 운영 환경에서 "XLog에 점이 안 찍힌다", "Counter 그래프가 갑자기 끊겼다" 같은 문제를 **원인 수준에서** 진단할 수 있다.
>
> 즉, Part 2는 **"Scouter를 쓸 줄 아는 사람"에서 "Scouter를 이해하는 사람"으로 넘어가는 단계**이다.

## 6. Bytecode Instrumentation — Agent의 핵심 원리

이 장은 Scouter Agent의 핵심 기술인 **Java Bytecode Instrumentation(BCI)**을 JVM 내부 구조부터 Opcode 수준까지 설명한다. 이 장을 이해하면 "소스코드를 수정하지 않고 어떻게 성능을 측정하는가?"라는 질문에 정확히 답할 수 있다.

앞서 Part 1의 docker-compose.yml에서 `-javaagent:scouter.agent.jar` 옵션을 봤다. 이 한 줄의 JVM 인자가 Scouter의 모든 동작의 출발점이며, 이 장에서는 그 한 줄이 JVM 내부에서 정확히 무슨 일을 일으키는지를 파헤칩니다.

### 6.1 전제 지식: JVM은 스택 기반 가상 머신이다

JVM은 CPU가 아닙니다. Java 소스코드(.java)는 `javac` 컴파일러에 의해 **바이트코드(.class)**로 변환되고, JVM이 이 바이트코드를 해석(Interpret)하거나 네이티브 코드로 컴파일(JIT)하여 실행한다.

바이트코드는 **JVM 명령어 세트(Instruction Set)**로 구성된다. x86 CPU가 `MOV`, `ADD`, `CALL` 같은 기계어 명령어를 실행하듯, JVM은 `ALOAD`, `INVOKEVIRTUAL`, `ARETURN` 같은 **Opcode**를 실행한다.

핵심적인 차이: JVM은 **레지스터가 아닌 스택(Operand Stack)**을 사용한다.

```
x86 CPU (레지스터 기반):
  MOV EAX, [a]     ; 변수 a를 EAX 레지스터에 로드
  ADD EAX, [b]     ; 변수 b를 EAX에 더함
  MOV [result], EAX ; 결과를 메모리에 저장

JVM (스택 기반):
  ILOAD 1           ; 로컬 변수 1번(a)을 오퍼랜드 스택에 push
  ILOAD 2           ; 로컬 변수 2번(b)을 오퍼랜드 스택에 push
  IADD              ; 스택 상위 2개를 pop, 더한 결과를 push
  ISTORE 3          ; 스택 상위를 pop, 로컬 변수 3번(result)에 저장
```

### 6.2 .class 파일의 바이너리 구조

`.class` 파일은 정해진 바이너리 포맷을 따릅니다:

```
.class 파일 구조:
  ┌─────────────────────────────────────────────────┐
  │ Magic Number: 0xCAFEBABE (4 bytes)              │ ← 모든 .class 파일의 시작
  │ Minor Version: 0 (2 bytes)                       │
  │ Major Version: 61 (2 bytes) ← Java 17            │
  ├─────────────────────────────────────────────────┤
  │ Constant Pool                                    │ ← 문자열, 클래스명, 메서드명 등 상수 테이블
  │   #1 = Methodref  java/lang/Object."<init>"      │
  │   #2 = String     "UP"                           │
  │   #3 = Methodref  InetAddress.getLocalHost()     │
  │   ...                                            │
  ├─────────────────────────────────────────────────┤
  │ Access Flags: ACC_PUBLIC                         │
  │ This Class: HealthController                     │
  │ Super Class: java/lang/Object                    │
  ├─────────────────────────────────────────────────┤
  │ Fields[]                                         │ ← 필드 정의
  ├─────────────────────────────────────────────────┤
  │ Methods[]                                        │ ← 메서드 정의
  │   Method: health()                               │
  │     Code Attribute:                              │
  │       max_stack  = 4                             │ ← 오퍼랜드 스택 최대 깊이
  │       max_locals = 1                             │ ← 로컬 변수 슬롯 수
  │       bytecode[] = { ALOAD_0, INVOKEVIRTUAL, ... }│ ← 실행할 Opcode 배열
  │       exception_table[] = { ... }                │
  │       StackMapTable = { ... }                    │ ← 바이트코드 검증용
  ├─────────────────────────────────────────────────┤
  │ Attributes[]                                     │
  └─────────────────────────────────────────────────┘
```

**중요**: 메서드의 실행 코드는 `Code Attribute` 안의 `bytecode[]` 배열이다. Scouter Agent가 변조하는 것이 바로 이 바이트 배열이다.

### 6.3 실제 바이트코드 예시: health() 메서드

`HealthController.health()` 메서드를 `javap -c`로 역어셈블하면 다음과 같다:

```
// javap -c HealthController.class

public java.util.Map<java.lang.String, java.lang.String> health()
    throws java.net.UnknownHostException;
  Code:
     0: ldc           #7    // String "status"    → 스택에 "status" push
     2: ldc           #8    // String "UP"        → 스택에 "UP" push
     4: ldc           #9    // String "host"      → 스택에 "host" push
     6: invokestatic  #10   // InetAddress.getLocalHost()
                            //   → 스택에 InetAddress 객체 push
     9: invokevirtual #11   // InetAddress.getHostName()
                            //   → 스택의 InetAddress를 pop, 호스트명을 push
    12: invokestatic  #12   // Map.of(K,V,K,V)
                            //   → 스택의 4개 인자를 pop, Map 결과를 push
    15: areturn              // 스택 상위의 Map 객체를 반환
```

각 숫자(0, 2, 4, 6, ...)는 `bytecode[]` 배열의 오프셋(인덱스)이다. JVM의 실행 엔진은 이 배열을 순차적으로 읽으며 명령을 수행한다.

**Opcode 설명:**

| Opcode | 바이트값 | 동작 |
|--------|---------|------|
| `ldc` | 0x12 | Constant Pool의 값을 오퍼랜드 스택에 push |
| `invokestatic` | 0xB8 | static 메서드를 호출 (인스턴스 불필요) |
| `invokevirtual` | 0xB6 | 인스턴스 메서드를 호출 (다형성 적용) |
| `areturn` | 0xB0 | 스택 상위의 참조(reference) 값을 반환 |
| `aload_0` | 0x2A | 로컬 변수 0번(this)을 스택에 push |
| `astore` | 0x3A | 스택 상위를 로컬 변수에 저장 |

### 6.4 JVM Class Loading 서브시스템

JVM이 코드를 실행하려면 `.class` 파일을 메모리에 로드해야 한다. 이 과정은 3단계로 구성된다:

```
.class 파일 (디스크)
    │
    ▼
① Loading ─────────────────────────────────────────────────
   ClassLoader가 .class 파일의 바이너리 데이터(byte[])를 읽는다.
   3종의 ClassLoader가 계층 구조를 형성한다:

   Bootstrap ClassLoader  (C++ 구현, JVM 내장)
     └─ java.lang.*, java.util.* 등 JDK 핵심 클래스 로드
   Platform ClassLoader   (Java 구현)
     └─ java.sql.*, javax.* 등 플랫폼 확장 클래스 로드
   Application ClassLoader (Java 구현)
     └─ classpath에 있는 사용자 클래스 로드
     └─ HealthController.class는 여기서 로드됨

    │
    ▼
② Linking ──────────────────────────────────────────────────
   a. Verification: 바이트코드가 JVM 스펙을 준수하는지 검증
      - StackMapTable 검사: 스택 상태 일관성 확인
      - 타입 검사: 메서드 시그니처와 인자 타입 일치 여부
   b. Preparation: static 필드에 기본값(0, null) 할당
   c. Resolution: Constant Pool의 심볼릭 참조를 실제 메모리 주소로 변환

    │
    ▼
③ Initialization ───────────────────────────────────────────
   static 블록과 static 필드의 초기화 코드 실행.
   이 단계가 끝나면 클래스가 사용 가능한 상태가 된다.
```

**Scouter Agent가 개입하는 시점은 ①과 ② 사이**이다. Loading 단계에서 ClassLoader가 `byte[]`를 읽어온 직후, 그 `byte[]`를 JVM에 넘기기 직전에 가로채서 변조한다.

### 6.5 java.lang.instrument API — Agent의 법적 근거

JVM은 임의의 코드가 클래스 로딩에 개입하는 것을 허용하지 않는다. **`java.lang.instrument`** 패키지는 JVM이 공식적으로 제공하는 유일한 바이트코드 변조 경로이다.

#### 6.5.1 -javaagent 옵션의 동작

```
JVM 기동 명령어:
  java -javaagent:/opt/scouter/agent.java/scouter.agent.jar \
       -Dscouter.config=/opt/scouter-conf/agent.conf \
       -Dobj_name=tomcat1 \
       -jar app.war
```

JVM이 이 명령어를 파싱하면 다음이 발생한다:

```
① JVM은 scouter.agent.jar의 META-INF/MANIFEST.MF를 읽는다:

   Manifest-Version: 1.0
   Premain-Class: scouter.agent.AgentBoot    ← 이 클래스의 premain()을 호출하라
   Can-Redefine-Classes: true                ← 이미 로드된 클래스도 재정의 가능
   Can-Retransform-Classes: true             ← 이미 로드된 클래스도 재변환 가능

② JVM은 애플리케이션의 main() 메서드를 호출하기 전에
   Premain-Class로 지정된 scouter.agent.AgentBoot.premain()을 먼저 호출한다.

③ premain() 호출 시 JVM은 Instrumentation 인스턴스를 인자로 전달한다.
   이 인스턴스가 바이트코드 변조 권한의 핵심이다.
```

#### 6.5.2 premain() 메서드

```java
// Scouter Agent의 진입점 (단순화)
public class AgentBoot {

    public static void premain(String agentArgs, Instrumentation inst) {
        // ① Instrumentation 인스턴스를 저장 — 이것이 변조 권한의 핸들
        //    이 객체를 통해서만 ClassFileTransformer를 등록할 수 있다.

        // ② ClassFileTransformer 구현체를 JVM에 등록
        inst.addTransformer(new ScouterClassFileTransformer(), true);
        //                                                     ^^^^
        //                         true = canRetransform (이미 로드된 클래스도 재변환 가능)

        // ③ Agent 설정 로드 (agent.conf 파일)
        AgentConfigure.getInstance().load(agentArgs);

        // ④ Counter 수집 스레드, TCP/UDP 통신 스레드 등 시작
        AgentBoot.startWorkers();
    }
}
```

**핵심**: `inst.addTransformer()`를 호출하는 순간, 이후 JVM에서 로드되는 **모든 클래스**에 대해 등록된 Transformer의 `transform()` 메서드가 콜백된다.

#### 6.5.3 ClassFileTransformer.transform()

```java
public interface ClassFileTransformer {

    byte[] transform(
        ClassLoader         loader,          // 이 클래스를 로드하는 ClassLoader
        String              className,       // 클래스의 내부 이름 (예: "com/middleware/demo/controller/HealthController")
        Class<?>            classBeingRedefined,  // 재정의 시 기존 Class 객체 (최초 로딩 시 null)
        ProtectionDomain    protectionDomain,     // 보안 도메인
        byte[]              classfileBuffer  // ★ 원본 .class 파일의 바이트 배열
    ) throws IllegalClassFormatException;
    // 반환값: 변조된 byte[] (null 반환 시 원본 유지)
}
```

이 인터페이스의 구현이 Scouter Agent의 핵심이다:

```java
// Scouter의 ClassFileTransformer 구현 (단순화)
public class ScouterClassFileTransformer implements ClassFileTransformer {

    @Override
    public byte[] transform(ClassLoader loader, String className,
            Class<?> classBeingRedefined, ProtectionDomain protectionDomain,
            byte[] classfileBuffer) {

        // ① className으로 Hook 대상 여부를 판별
        //    "javax/servlet/http/HttpServlet" → HTTP Hook 적용
        //    "java/sql/Connection"            → JDBC Hook 적용
        //    agent.conf의 hook_method_patterns과 매칭 → Method Hook 적용

        if (isHttpServletClass(className)) {
            return HttpServiceASM.transform(classfileBuffer);
            // classfileBuffer(원본 byte[])를 입력받아
            // 변조된 byte[]를 반환
        }

        if (isJdbcClass(className)) {
            return JDBCConnectionOpenASM.transform(classfileBuffer);
        }

        if (matchesHookPattern(className)) {
            return MethodASM.transform(classfileBuffer);
        }

        // Hook 대상이 아니면 null 반환 → 원본 유지
        return null;
    }
}
```

**실행 흐름 정리:**

```
JVM이 HealthController.class를 로드하려 함
    │
    ▼
ClassLoader가 디스크에서 byte[]를 읽음
    │
    ▼
JVM이 등록된 모든 ClassFileTransformer.transform()을 순차 호출
    │
    ├─ className = "com/middleware/demo/controller/HealthController"
    ├─ classfileBuffer = [원본 바이트코드 배열]
    │
    ▼
ScouterClassFileTransformer.transform() 실행
    │
    ├─ hook_service_patterns = "com.middleware.demo.controller.*.*"
    ├─ className이 패턴에 매칭됨 → Hook 대상
    │
    ▼
HttpServiceASM.transform(classfileBuffer) 호출
    │
    ├─ ASM 라이브러리로 바이트코드 파싱
    ├─ 메서드 진입점에 시간 측정 코드 삽입
    ├─ 메서드 종료점에 데이터 전송 코드 삽입
    │
    ▼
변조된 byte[]를 JVM에 반환
    │
    ▼
JVM은 변조된 byte[]로 Verification → Preparation → Resolution → Initialization 수행
    │
    ▼
Method Area(Metaspace)에 변조된 클래스 정의가 올라감
    │
    ▼
이후 이 클래스의 메서드가 호출될 때 변조된 코드가 실행됨
```

### 6.6 ASM 라이브러리 — 바이트코드 편집기

ASM은 `.class` 파일의 바이너리를 파싱하고 편집하는 라이브러리이다. Scouter뿐 아니라 Spring Framework, Hibernate, Gradle도 내부적으로 ASM을 사용한다.

#### 6.6.1 ASM의 Visitor 패턴

ASM은 **Visitor 패턴**으로 바이트코드를 처리한다. `.class` 파일을 한 바이트씩 순차적으로 읽으면서, 구조적 요소(클래스, 필드, 메서드, 명령어)를 만날 때마다 대응하는 Visitor 메서드를 콜백한다.

```
ASM 파이프라인:

  ClassReader ──→ ClassVisitor ──→ ClassWriter
  (입력: byte[])   (중간: 변환)     (출력: byte[])

  ┌─────────────┐    ┌──────────────────┐    ┌──────────────┐
  │ ClassReader  │───→│  ClassVisitor    │───→│ ClassWriter  │
  │              │    │  (Scouter 구현)   │    │              │
  │ 원본 byte[]  │    │                  │    │ 변조된 byte[] │
  │ 를 파싱하여  │    │ visit()          │    │ 를 생성       │
  │ 이벤트 발생  │    │ visitMethod()    │    │              │
  │              │    │ visitField()     │    │              │
  │              │    │ visitEnd()       │    │              │
  └─────────────┘    └──────────────────┘    └──────────────┘
```

**콜백 순서:**

```
ClassReader가 byte[]를 읽으면서 다음 순서로 ClassVisitor에 콜백:

  visit(version, access, name, signature, superName, interfaces)
    ├─ "이 클래스의 이름은 HealthController이고, public이고, Object를 상속한다"
    │
    ├─ visitField(access, name, descriptor, ...)
    │   "필드 하나를 발견했다"
    │
    ├─ visitMethod(access, name, descriptor, ...)  ← ★ 메서드를 발견했을 때
    │   │   "health 메서드를 발견했다. MethodVisitor를 반환하라"
    │   │
    │   └─ MethodVisitor 반환
    │       ├─ visitCode()           ← 메서드 본문 시작
    │       ├─ visitInsn(ALOAD_0)    ← Opcode 하나하나마다 콜백
    │       ├─ visitMethodInsn(INVOKESTATIC, ...)
    │       ├─ visitMethodInsn(INVOKEVIRTUAL, ...)
    │       ├─ visitInsn(ARETURN)    ← return 명령어
    │       ├─ visitMaxs(stack, locals) ← max_stack, max_locals
    │       └─ visitEnd()            ← 메서드 끝
    │
    └─ visitEnd()  ← 클래스 끝
```

#### 6.6.2 Scouter가 ASM을 사용하는 코드 (단순화)

Scouter의 HTTP 서비스 Hook은 다음과 같이 구현된다:

```java
// HttpServiceASM.java (단순화)
public class HttpServiceASM {

    public static byte[] transform(byte[] classfileBuffer) {
        // ① ClassReader: 원본 byte[]를 파싱 엔진에 투입
        ClassReader cr = new ClassReader(classfileBuffer);

        // ② ClassWriter: 최종 byte[] 생성기
        ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_FRAMES);
        //                               ^^^^^^^^^^^^^^^^^^^^^^^
        //                    StackMapFrame을 자동 재계산 (Verification 통과를 위해 필수)

        // ③ 커스텀 ClassVisitor: 메서드를 발견하면 변조할 MethodVisitor를 끼워 넣음
        ClassVisitor cv = new ClassVisitor(Opcodes.ASM9, cw) {
            @Override
            public MethodVisitor visitMethod(int access, String name,
                    String descriptor, String signature, String[] exceptions) {

                MethodVisitor mv = super.visitMethod(access, name,
                        descriptor, signature, exceptions);

                // "service" 메서드이고, 서블릿 시그니처에 해당하면 Hook
                if ("service".equals(name) && isServletDescriptor(descriptor)) {
                    return new HttpServiceMethodVisitor(mv);
                }
                return mv;  // 다른 메서드는 그대로 통과
            }
        };

        // ④ 파이프라인 실행: Reader가 byte[]를 읽으며 Visitor 체인에 이벤트를 발생
        cr.accept(cv, ClassReader.EXPAND_FRAMES);

        // ⑤ Writer로부터 변조된 byte[]를 추출
        return cw.toByteArray();
    }
}
```

```java
// HttpServiceMethodVisitor.java (단순화)
public class HttpServiceMethodVisitor extends MethodVisitor {

    public HttpServiceMethodVisitor(MethodVisitor mv) {
        super(Opcodes.ASM9, mv);
    }

    @Override
    public void visitCode() {
        super.visitCode();

        // ★ 메서드 본문 시작 직후에 삽입할 Opcode들:
        // TraceContext ctx = TraceMain.startHttpService(req, res);
        mv.visitVarInsn(Opcodes.ALOAD, 1);     // 로컬변수 1번(req)을 스택에 push
        mv.visitVarInsn(Opcodes.ALOAD, 2);     // 로컬변수 2번(res)을 스택에 push
        mv.visitMethodInsn(
            Opcodes.INVOKESTATIC,               // static 메서드 호출
            "scouter/agent/trace/TraceMain",    // 클래스 (내부 이름)
            "startHttpService",                 // 메서드명
            "(Ljavax/servlet/ServletRequest;Ljavax/servlet/ServletResponse;)Ljava/lang/Object;",
            false                               // 인터페이스 메서드 아님
        );
        mv.visitVarInsn(Opcodes.ASTORE, 3);    // 반환된 TraceContext를 로컬변수 3번에 저장
    }

    @Override
    public void visitInsn(int opcode) {
        // ★ RETURN 또는 ATHROW 명령어를 만나면 그 직전에 종료 코드 삽입
        if (opcode == Opcodes.ARETURN || opcode == Opcodes.RETURN
                || opcode == Opcodes.ATHROW) {

            mv.visitVarInsn(Opcodes.ALOAD, 3);  // 로컬변수 3번(TraceContext)을 스택에 push
            mv.visitMethodInsn(
                Opcodes.INVOKESTATIC,
                "scouter/agent/trace/TraceMain",
                "endHttpService",
                "(Ljava/lang/Object;)V",         // void 반환
                false
            );
        }
        super.visitInsn(opcode);  // 원래 RETURN/ATHROW 명령어 실행
    }
}
```

#### 6.6.3 변조 전후 바이트코드 비교

위 ASM 코드가 실행되면, `HttpServlet.service()` 메서드의 바이트코드가 다음과 같이 변한다:

```
[변조 전] HttpServlet.service() 바이트코드:

  Offset  Opcode              설명
  ──────  ──────              ────
  0:      aload_0             this를 스택에 push
  1:      aload_1             req를 스택에 push
  2:      aload_2             res를 스택에 push
  3:      invokevirtual #15   doGet(req, res) 호출
  6:      return              메서드 종료


[변조 후] HttpServlet.service() 바이트코드:

  Offset  Opcode              설명                          삽입자
  ──────  ──────              ────                          ──────
  0:      aload_1             req를 스택에 push              ← Scouter 삽입
  1:      aload_2             res를 스택에 push              ← Scouter 삽입
  2:      invokestatic #50    TraceMain.startHttpService()   ← Scouter 삽입
  5:      astore_3            반환값을 로컬변수 3에 저장       ← Scouter 삽입
  ──── 원본 코드 시작 ────
  6:      aload_0             this를 스택에 push
  7:      aload_1             req를 스택에 push
  8:      aload_2             res를 스택에 push
  9:      invokevirtual #15   doGet(req, res) 호출
  ──── 원본 코드 끝 ────
  12:     aload_3             TraceContext를 스택에 push      ← Scouter 삽입
  13:     invokestatic #51    TraceMain.endHttpService()      ← Scouter 삽입
  16:     return              메서드 종료
```

**변조의 결과:**
- `max_locals`가 3에서 4로 증가 (로컬변수 3번 슬롯을 TraceContext 저장에 사용)
- `max_stack`이 필요에 따라 재계산됨
- `StackMapTable`이 `COMPUTE_FRAMES` 옵션에 의해 자동 재생성됨

이 세 가지가 정확하지 않으면 JVM의 Verification 단계에서 `VerifyError`가 발생하고 클래스 로딩이 실패한다. ASM의 `ClassWriter.COMPUTE_FRAMES` 옵션이 이를 자동 처리한다.

### 6.7 TraceContext와 ThreadLocal — 요청 추적의 핵심

바이트코드 삽입은 "언제 시작하고 언제 끝나는지"를 기록할 뿐이다. 하나의 HTTP 요청이 여러 메서드를 거치는 동안 **동일한 컨텍스트**를 유지하는 것은 `ThreadLocal`이 담당한다.

```java
// TraceContextManager.java (단순화)
public class TraceContextManager {

    // ThreadLocal: 각 스레드마다 독립적인 TraceContext를 보유
    private static final ThreadLocal<TraceContext> local = new ThreadLocal<>();

    public static TraceContext startTrace() {
        TraceContext ctx = new TraceContext();
        ctx.txid = generateUniqueId();       // 고유 트랜잭션 ID
        ctx.startTime = System.nanoTime();   // 시작 시간
        local.set(ctx);                      // 현재 스레드에 바인딩
        return ctx;
    }

    public static TraceContext getContext() {
        return local.get();                  // 현재 스레드의 컨텍스트 반환
    }

    public static void endTrace(TraceContext ctx) {
        ctx.elapsed = (System.nanoTime() - ctx.startTime) / 1_000_000;  // ms 변환
        DataProxy.sendXLog(ctx.toXLogPack());  // UDP로 Server에 전송
        local.remove();                        // ThreadLocal 정리 (메모리 누수 방지)
    }
}
```

**동작 원리:**

```
Thread "http-nio-8080-exec-7" 이 /health 요청을 처리한다고 가정:

  ┌─ exec-7 스레드 ──────────────────────────────────────────────┐
  │                                                               │
  │  [Servlet.service() 진입]                                     │
  │    └─ Scouter 삽입 코드: TraceContextManager.startTrace()     │
  │       → ThreadLocal<exec-7> = TraceContext { txid=0xA1B2 }    │
  │                                                               │
  │  [HealthController.health() 진입]                             │
  │    └─ Scouter 삽입 코드: TraceContextManager.getContext()     │
  │       → ThreadLocal<exec-7>에서 txid=0xA1B2 컨텍스트를 꺼냄   │
  │       → 메서드 시작 시간을 Profile Step에 기록                 │
  │                                                               │
  │  [HealthController.health() 종료]                             │
  │    └─ 메서드 종료 시간을 Profile Step에 기록                   │
  │                                                               │
  │  [Servlet.service() 종료]                                     │
  │    └─ Scouter 삽입 코드: TraceContextManager.endTrace()       │
  │       → elapsed 계산, XLogPack 생성, UDP 전송                 │
  │       → ThreadLocal<exec-7> 정리                              │
  │                                                               │
  └───────────────────────────────────────────────────────────────┘

  동시에 다른 스레드가 /info 요청을 처리:

  ┌─ exec-12 스레드 ─────────────────────────────────────────────┐
  │  ThreadLocal<exec-12> = TraceContext { txid=0xC3D4 }         │
  │  → exec-7과 완전히 독립된 컨텍스트                             │
  └───────────────────────────────────────────────────────────────┘
```

`ThreadLocal`은 JVM의 스레드별 격리 저장소이다. 동시에 수십 개의 HTTP 요청이 처리되더라도, 각 스레드의 TraceContext는 서로 간섭하지 않는다. 이것이 Scouter가 멀티스레드 환경에서 안전하게 동작하는 근거이다.

### 6.8 Hook 대상 결정 메커니즘

`transform()` 메서드는 JVM이 로드하는 **모든 클래스**에 대해 호출된다. 하지만 모든 클래스를 변조하면 오버헤드가 발생하므로, Scouter는 두 가지 기준으로 Hook 대상을 결정한다.

#### 6.8.1 자동 Hook (Built-in)

`agent.conf`에 명시하지 않아도 Scouter Agent가 코드 내부에 하드코딩된 규칙으로 자동 Hook하는 항목:

| 항목 | className 패턴 | Hook 클래스 | 삽입하는 로직 |
|------|---------------|------------|-------------|
| HTTP 서블릿 | `javax/servlet/http/HttpServlet` | `HttpServiceASM` | 요청 시작/종료 시간, URL, 응답코드, 클라이언트 IP |
| JDBC Connection | `java/sql/Connection` 구현체 | `JDBCConnectionOpenASM` | Connection 획득 시간, DB URL |
| JDBC Statement | `java/sql/PreparedStatement` 구현체 | `JDBCPreparedStatementASM` | SQL문 캡처, 실행 시간, 반환 행 수 |
| HTTP Client | `java/net/HttpURLConnection` | `HttpCallASM` | 외부 호출 URL, 응답시간, 상태코드 |
| Thread | `java.lang.Thread` 상태 | JMX `ThreadMXBean` 직접 조회 | 스레드 수, 상태별 분포 |
| GC | GC 이벤트 | JMX `GarbageCollectorMXBean` 리스너 | GC 횟수, 소요 시간 |

JDBC Hook의 경우, `java.sql.Connection`은 인터페이스이므로 실제로는 MySQL 드라이버의 `com.mysql.cj.jdbc.ConnectionImpl` 같은 구현 클래스가 로드될 때 해당 클래스의 `prepareStatement()` 메서드를 Hook한다.

#### 6.8.2 사용자 정의 Hook (agent.conf)

```properties
# configs/scouter/agent.conf

# 서비스 진입점 Hook — XLog 점이 찍히는 기준
hook_service_patterns=com.middleware.demo.controller.*.*
# → HealthController.health(), SecuredController.profile() 등이 서비스로 인식됨

# 메서드 Hook — Profile Step에 기록되는 기준
hook_method_patterns=com.middleware.demo.*.*
# → com.middleware.demo 패키지 하위의 모든 메서드 호출이 프로파일에 기록됨
```

패턴 매칭은 `transform()` 메서드 내에서 className을 `.`을 `/`로 치환하고, 와일드카드(`*`)를 정규식으로 변환하여 수행한다.

| 설정 | 역할 | 효과 |
|------|------|------|
| `hook_service_patterns` | 지정된 메서드를 **트랜잭션의 시작점**으로 인식 | XLog에 점이 찍히고, TraceContext가 생성됨 |
| `hook_method_patterns` | 지정된 메서드의 **호출 시간**을 기록 | Profile의 METHOD Step으로 기록됨 |

두 설정의 차이: `hook_service_patterns`은 `TraceContextManager.startTrace()`를 호출하고, `hook_method_patterns`은 이미 존재하는 TraceContext에 Step을 추가할 뿐이다.

### 6.9 JIT 컴파일러와의 상호작용

변조된 바이트코드가 JVM에 로드된 후의 실행 경로:

```
변조된 바이트코드
    │
    ▼
① Interpreter (인터프리터 모드)
   최초에는 바이트코드를 한 Opcode씩 해석하며 실행한다.
   Scouter가 삽입한 INVOKESTATIC도 이 시점에 실행된다.
    │
    │  메서드가 JIT 컴파일 임계값(기본 10,000회 호출)을 넘기면:
    ▼
② C1 Compiler (클라이언트 컴파일러)
   바이트코드 전체를 네이티브 머신코드(x86/ARM)로 컴파일한다.
   Scouter가 삽입한 코드도 네이티브 코드에 포함된다.
    │
    │  추가 최적화 대상이 되면:
    ▼
③ C2 Compiler (서버 컴파일러)
   더 공격적인 최적화(인라이닝, 루프 언롤링, 이스케이프 분석)를 적용한다.
   Scouter의 TraceMain.startHttpService()가 충분히 작으면 인라인될 수 있다.
```

JIT 컴파일의 결과: 반복 실행되는 메서드에서 Scouter의 측정 코드는 **네이티브 기계어 수준에서 최적화**된다. 따라서 바이트코드 인터프리터 모드보다 오버헤드가 더 줄어듭니다.

### 6.10 성능 오버헤드 분석

바이트코드 변조에 의한 오버헤드는 두 시점으로 나뉩니다:

**① 클래스 로딩 시점 (1회성)**

| 작업 | 소요 시간 |
|------|----------|
| `transform()` 내 className 패턴 매칭 | ~0.01ms |
| ASM ClassReader 파싱 | ~0.1ms |
| ASM ClassWriter 바이트코드 생성 | ~0.2ms |
| StackMapFrame 재계산 (COMPUTE_FRAMES) | ~0.5ms |
| **합계 (Hook 대상 클래스 1개당)** | **~1ms** |

이 오버헤드는 클래스 로딩 시 1회만 발생한다. 애플리케이션 기동 시간에 미미한 영향을 준다.

**② 런타임 (매 요청마다)**

| 작업 | 소요 시간 |
|------|----------|
| `System.nanoTime()` 호출 2회 (시작/종료) | ~0.05μs × 2 |
| ThreadLocal.get()/set()/remove() | ~0.02μs × 3 |
| XLogPack 객체 생성 및 필드 설정 | ~0.1μs |
| UDP 패킷 전송 (비동기, 논블로킹) | ~1μs |
| **합계 (요청 1건당)** | **~2μs** |

응답시간이 10ms인 요청에 대해 2μs의 오버헤드는 **0.02%**이다.

```
요청 처리 시간 비교:
  Agent 없이: 15.2ms (평균)
  Agent 있음: 15.5ms (평균)  → 약 2% 증가 (측정 오차 포함)
```

오버헤드가 낮은 구조적 이유:
1. 시간 기록은 `System.nanoTime()` 한 번 호출 수준 (OS 클럭 읽기)
2. 데이터 전송은 UDP — TCP처럼 연결 유지/ACK 대기가 없음
3. Profile 상세 데이터(SQL문, 스택트레이스)는 Client가 XLog 점을 클릭할 때만 TCP로 전송
4. JIT 컴파일러가 측정 코드를 네이티브 수준으로 최적화

---

## 7. Agent → Server 통신 프로토콜

6장에서 Agent가 바이트코드 변조를 통해 **요청의 시작/종료 시간, URL, SQL 등을 수집**하는 과정을 살펴보았다. 그런데 수집한 데이터가 Agent의 JVM 메모리에만 남아 있으면 소용이 없다. Scouter Client에서 그래프를 보려면, 이 데이터가 **네트워크를 통해 Server로 전달**되어야 한다.

이 장에서는 Agent가 수집한 데이터를 Server로 보내는 **통신 프로토콜**을 다룹니다. 왜 UDP와 TCP를 동시에 사용하는지, 데이터를 어떤 형태로 직렬화하는지, 네트워크 대역폭을 어떻게 절약하는지를 이해하면, "Agent는 연결됐는데 XLog만 안 뜬다"거나 "Counter는 보이는데 Profile이 안 열린다" 같은 증상의 원인을 정확히 짚을 수 있다.

### 7.1 이중 프로토콜 설계

Scouter는 **UDP + TCP 이중 프로토콜**을 사용한다. 이는 성능과 신뢰성의 균형을 맞추기 위한 설계이다.

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

### 7.2 Pack — Scouter의 데이터 전송 단위

Scouter는 모든 데이터를 **Pack**이라는 직렬화 단위로 포장하여 전송한다. Pack은 Scouter가 자체 정의한 바이너리 프로토콜로, JSON이나 Protobuf가 아닌 **커스텀 직렬화 포맷**이다.

```
Pack 바이너리 구조:

  ┌────────────────────────────────────────────────────┐
  │ Pack Type (1 byte)                                  │ ← Pack의 종류 식별
  │   0x01 = XLogPack (트랜잭션 데이터)                  │
  │   0x02 = PerfCounterPack (성능 카운터)               │
  │   0x06 = ObjectPack (오브젝트 등록)                   │
  │   0x10 = TextPack (텍스트 사전)                      │
  │   0x12 = AlertPack (알림)                            │
  ├────────────────────────────────────────────────────┤
  │ Payload (가변 길이)                                  │
  │   DataOutputX로 직렬화된 필드들:                      │
  │   ├─ writeLong(txid)        → 8 bytes               │
  │   ├─ writeInt(elapsed)      → 4 bytes               │
  │   ├─ writeInt(serviceHash)  → 4 bytes               │
  │   ├─ writeShort(cpu)        → 2 bytes               │
  │   └─ ...                                            │
  └────────────────────────────────────────────────────┘
```

**DataOutputX / DataInputX**: Scouter의 커스텀 직렬화 유틸리티이다. Java 표준의 `ObjectOutputStream`을 사용하지 않는 이유는 성능이다. `ObjectOutputStream`은 클래스 메타데이터, 직렬화 버전 UID 등의 오버헤드가 크지만, DataOutputX는 필드를 원시 바이트로 직접 쓰므로 패킷 크기가 최소화된다.

```
XLogPack 1건의 바이너리 크기:

  Java ObjectOutputStream 사용 시: ~350 bytes (클래스 메타 포함)
  Scouter DataOutputX 사용 시:    ~62 bytes  (순수 필드 데이터만)

  → 약 82% 절약
```

### 7.3 UDP 통신 — 대량 데이터 고속 전송

UDP로 전송되는 Pack 종류:

| Pack 종류 | 전송 주기 | 패킷 크기 | 내용 |
|-----------|----------|----------|------|
| **PerfCounterPack** | 2초 | ~120 bytes | TPS, Active Service, Heap Used, GC Count, CPU |
| **XLogPack** | 요청 완료 즉시 | ~62 bytes | txid, 서비스명 해시, 응답시간, 에러 여부 |
| **AlertPack** | 이벤트 발생 시 | ~80 bytes | 알림 레벨, 메시지 |

**UDP 전송 내부 구조:**

```java
// Agent 내부의 UDP 전송 코드 (단순화)
public class DataProxy {

    private static DatagramSocket udpSocket;

    public static void sendXLog(XLogPack pack) {
        DataOutputX out = new DataOutputX();
        out.writeByte(0x01);           // Pack Type = XLogPack
        pack.write(out);               // 필드들을 바이트로 직렬화

        byte[] data = out.toByteArray();
        DatagramPacket packet = new DatagramPacket(
            data, data.length,
            serverAddress, 6100         // Scouter Server UDP 포트
        );
        udpSocket.send(packet);        // 비동기 전송 — send() 즉시 반환
    }
}
```

`udpSocket.send()`는 커널의 송신 버퍼에 데이터를 복사하고 즉시 반환한다. TCP처럼 상대방의 ACK를 기다리지 않으므로, 호출 스레드가 블로킹되지 않는다. 이것이 Agent의 오버헤드를 최소화하는 핵심이다.

**UDP를 선택한 공학적 이유:**

| 기준 | TCP | UDP |
|------|-----|-----|
| 연결 유지 비용 | 3-way handshake, Keep-Alive | 없음 (connectionless) |
| 전송 보장 | ACK/재전송으로 보장 | 보장 없음 |
| 패킷 손실 시 | 재전송 (지연 발생) | 다음 주기에 새 데이터가 옴 |
| 처리량 | 흐름 제어로 제한 | 커널 버퍼 한도까지 전송 |
| Agent 스레드 블로킹 | 가능 (네트워크 지연 시) | 불가능 (send 즉시 반환) |

성능 카운터는 2초마다 새 값이 오므로, 한 건이 유실되어도 다음 주기의 값으로 대체된다. XLog도 마찬가지로, TPS가 극도로 높은 상황에서 일부가 유실되어도 전체 패턴 분석에는 지장이 없다.

### 7.4 TCP 통신 — 신뢰성 필요 데이터

TCP로 전송되는 데이터는 **유실되면 복구할 수 없는** 것들이다:

| Pack 종류 | 전송 시점 | 내용 | 유실 시 영향 |
|-----------|----------|------|------------|
| **ObjectPack** | Agent 시작 시 | 오브젝트 이름, 타입, Host | Server가 Agent를 인식 불가 |
| **Heartbeat** | 30초 주기 | 생존 확인 신호 | Object가 Dead로 판정됨 |
| **TextPack** | 최초 1회 | URL, SQL 해시→문자열 매핑 | Client에서 해시값만 보임 |
| **Profile Steps** | Client 요청 시 | SQL문, 메서드 스택, 파라미터 | 상세 분석 불가 |

TCP 연결은 Agent 시작 시 1개만 생성하고, 이후 모든 TCP 통신에 재사용한다. 연결이 끊기면 자동 재연결을 시도한다.

### 7.5 Text Dictionary — 대역폭 최적화

Scouter는 **Text Dictionary** 기법으로 네트워크 대역폭을 절약한다. 이는 HTTP/2의 HPACK 헤더 압축과 유사한 원리이다.

```
Text Dictionary 등록 프로세스:

① Agent가 "/health" URL을 최초로 처리함
② Agent 내부에서 해시 함수 적용:
   hash("/health") = 0x7A3F (Jenkins One-at-a-Time Hash)
③ Agent의 로컬 캐시(HashSet)에 0x7A3F가 없으면:
   → TCP로 TextPack {type=SERVICE, hash=0x7A3F, text="/health"} 전송 (1회만)
   → 로컬 캐시에 0x7A3F 추가
④ 이후 XLogPack 전송 시:
   → service 필드에 0x7A3F (4바이트)만 담아 UDP로 전송
⑤ Client가 XLog를 표시할 때:
   → Server에게 "0x7A3F에 해당하는 문자열은?" 요청
   → Server의 Text Dictionary에서 "/health" 반환
```

```
네트워크 절약 효과:
  URL                                  원본 크기    해시 크기   절약률
  "/health"                            7 bytes     4 bytes    43%
  "/secured/profile"                   17 bytes    4 bytes    76%
  "SELECT * FROM users WHERE id = ?"   33 bytes    4 bytes    88%

  TPS 1000인 환경에서 초당 XLog 1000건 × (33-4) = 29KB/s 절약
```

### 7.6 네트워크 버퍼와 패킷 유실

UDP 패킷 유실이 발생하는 조건과 대응:

```
Agent → (UDP) → OS 커널 송신 버퍼 → (네트워크) → OS 커널 수신 버퍼 → Server

유실 발생 지점:
① 송신 버퍼 오버플로: Agent가 버퍼보다 빠르게 전송 (극단적 TPS에서)
② 네트워크 경로: 패킷 손상, 라우터 드랍 (Docker bridge에서는 거의 없음)
③ 수신 버퍼 오버플로: Server가 수신 버퍼를 비우는 속도 < 도착 속도
```

본 프로젝트에서는 Agent와 Server가 동일 Docker 네트워크(`mw-network`)에 있으므로 ②의 확률은 사실상 0이다. ③이 문제가 되는 것은 Agent가 10대 이상이고 TPS가 수만인 대규모 환경이다.

### 7.7 본 프로젝트의 Agent 설정

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

`net_collector_ip=scouter-server`가 핵심이다. Docker Compose의 내부 DNS 덕분에, `scouter-server`라는 서비스명으로 Scouter Server 컨테이너의 IP를 자동 resolve한다.

---

## 8. 데이터 수집 파이프라인

6장에서 Agent가 바이트코드를 변조하여 성능 데이터를 **수집**하는 과정을, 7장에서 그 데이터를 Server로 **전송**하는 프로토콜을 살펴보았다. 이 장에서는 이 두 과정을 하나로 엮어, **사용자의 curl 명령 한 번이 XLog 점 하나가 되기까지의 전체 여정**을 시간순으로 따라간다.

이 파이프라인을 한 눈에 이해하면, "데이터가 어디서 누락되었는가"를 단계별로 체크할 수 있는 **트러블슈팅 지도**를 갖게 된다.

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

8장에서 HTTP 요청이 XLog Pack으로 변환되어 Server에 도달하는 전체 흐름을 보았다. 이 장에서는 그 **XLog Pack 자체**에 집중한다. Pack 안에 어떤 필드가 담겨 있고, 그 필드들이 Client 화면에서 어떤 시각적 요소(점의 위치, 색상, 클릭 시 프로파일)로 매핑되는지를 구체적으로 설명한다.

XLog의 내부 구조를 알면, Part 3에서 다룰 XLog 차트의 모든 동작을 "왜 그렇게 보이는지" 수준에서 이해할 수 있다.

### 9.1 XLog란?

XLog(eXtended Log)는 Scouter의 **핵심 데이터 모델**이다. HTTP 요청 하나 = XLog 레코드 하나이다. Jennifer의 XView와 동일한 개념이다.

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

### 9.3 분산 추적: txid, gxid, caller

XLogPack의 `txid`, `gxid`, `caller` 3개 필드는 **분산 추적(Distributed Tracing)**을 위한 것이다.

```
단일 서비스 요청 (본 프로젝트의 /health):

  Client → Nginx → Tomcat1 (또는 Tomcat2)
                    txid = 0xA1B2C3D4
                    gxid = 0xA1B2C3D4  (= txid, 최초 요청이므로)
                    caller = 0          (호출자 없음)


분산 서비스 요청 (서비스 A → 서비스 B → 서비스 C):

  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
  │ Service A        │───→│ Service B        │───→│ Service C        │
  │ txid  = 0x1111   │    │ txid  = 0x2222   │    │ txid  = 0x3333   │
  │ gxid  = 0x1111   │    │ gxid  = 0x1111   │    │ gxid  = 0x1111   │
  │ caller = 0       │    │ caller = 0x1111  │    │ caller = 0x2222  │
  └─────────────────┘    └─────────────────┘    └─────────────────┘
```

| 필드 | 의미 | 생성 규칙 |
|------|------|----------|
| `txid` | 이 트랜잭션의 고유 ID | 매 요청마다 Agent가 생성 (KeyGen.next()) |
| `gxid` | 전체 호출 체인의 루트 ID | 최초 요청의 txid가 그대로 전파됨 |
| `caller` | 나를 호출한 트랜잭션의 txid | HTTP 헤더 `X-Scouter-Gxid`로 전달받음 |

`trace_interservice_enabled=true`로 설정하면, Agent는 외부 HTTP 요청을 보낼 때 `X-Scouter-Gxid`와 `X-Scouter-Caller` 헤더를 자동 삽입한다. 수신 측 Agent는 이 헤더를 읽어 `gxid`와 `caller` 필드를 채웁니다.

### 9.4 XLog 시각화 원리

```
XLog 차트 좌표계:
  X축 = 요청 완료 시각 (endtime = starttime + elapsed)
  Y축 = elapsed (응답 시간, ms)
  색상 = 에러 여부 (파란점=정상, 빨간점=에러)

  응답시간(ms)
  5000 |                          ●(빨강) ← 에러 발생 (HTTP 5xx 또는 Exception)
       |
  2000 |              ●(파랑) ← 느린 정상 요청 (DB 쿼리 병목 가능성)
       |
   500 |    ● ●   ●     ●   ← 보통 요청
       |
   100 | ●●●●●●●●●●●●●●●●●● ← 정상 대역 (대부분의 요청)
     0 |_________________________________ 시각 →
       09:00    09:01    09:02    09:03
```

XLog 차트에서 점의 좌표는 XLogPack의 필드로 직접 결정된다:
- **X 좌표** = `endtime` 필드 (요청 완료 시각, epoch ms)
- **Y 좌표** = `elapsed` 필드 (응답 시간, ms)
- **색상** = `error` 필드 (0이면 파란색, 0이 아니면 빨간색)

Client는 Server로부터 XLogPack을 실시간으로 수신받아, 이 3개 필드만으로 점을 그립니다.

### 9.5 Profile Step — 요청 내부의 타임라인

XLog의 점을 클릭하면 해당 txid에 대한 **Profile Steps**를 Server에 TCP로 요청한다. Profile Step은 하나의 트랜잭션 내부에서 발생한 이벤트의 시계열 기록이다.

**Profile Step의 타입:**

| Step 타입 | 기록 시점 | 기록 내용 |
|-----------|----------|----------|
| `StartStep` | 트랜잭션 시작 | URL, 시작 시각, 클라이언트 IP |
| `MethodStep` | Hook된 메서드 진입/종료 | 클래스명.메서드명, 소요 시간 |
| `SqlStep` | JDBC 실행 | SQL문 해시, 소요 시간, 반환 행 수, 바인드 파라미터 |
| `ApiCallStep` | 외부 HTTP 호출 | 대상 URL, 소요 시간, 응답 코드 |
| `ThreadSubmitStep` | 비동기 스레드 전환 | 새 스레드명, 컨텍스트 전달 여부 |
| `MessageStep` | 사용자 정의 메시지 | 임의의 문자열 (디버깅용) |
| `ErrorStep` | Exception 발생 | 에러 클래스명, 메시지, 스택트레이스 해시 |
| `EndStep` | 트랜잭션 종료 | 총 소요 시간, CPU 시간 |

**Profile Step 예시 — /health 요청:**

```
Profile Steps for txid=0xA1B2C3D4E5F6
──────────────────────────────────────────────────────────────────
  [0ms]  → START service=/health  ip=172.18.0.1
  [1ms]  → METHOD com.middleware.demo.controller.HealthController.health()
  [2ms]  →   METHOD java.net.InetAddress.getLocalHost()        elapsed=3ms
  [5ms]  →   METHOD java.lang.Runtime.maxMemory()              elapsed=0ms
  [6ms]  →   METHOD java.lang.Runtime.freeMemory()             elapsed=0ms
  [8ms]  →   METHOD java.lang.Runtime.availableProcessors()    elapsed=0ms
  [11ms] → END elapsed=11ms cpu=850μs
──────────────────────────────────────────────────────────────────
```

**Profile Step 예시 — SQL이 포함된 요청:**

```
Profile Steps for txid=0xB2C3D4E5F6A1
──────────────────────────────────────────────────────────────────
  [0ms]  → START service=/api/users  ip=172.18.0.1
  [1ms]  → METHOD UserController.getUsers()
  [2ms]  →   SQL  SELECT * FROM users WHERE active = ?
  [45ms] →   SQL  elapsed=43ms  rows=150  bind=[1]
  [46ms] →   METHOD UserMapper.toDTO()                         elapsed=5ms
  [52ms] → END elapsed=52ms cpu=12300μs
──────────────────────────────────────────────────────────────────
```

**Profile Step의 내부 저장 구조:**

```java
// Step 하나의 구조 (단순화)
public class SqlStep extends Step {
    public int    hash;       // SQL문의 해시값 (Text Dictionary로 원문 조회)
    public int    elapsed;    // SQL 실행 시간 (ms)
    public int    param;      // 바인드 파라미터 해시 (Text Dictionary)
    public int    rows;       // 반환 행 수
    public int    start_time; // 트랜잭션 시작 기준 상대 시간 (ms)
}
```

Profile Step들은 `ArrayList<Step>`에 순서대로 쌓이며, `profile_step_max_count=1024` 설정에 의해 하나의 트랜잭션 내에 최대 1024개의 Step만 기록된다. 이 제한은 무한 루프나 대량 SQL 실행 시 메모리를 보호한다.

이렇게 **요청 하나의 내부 처리 과정**을 시간순으로 추적할 수 있는 것이 APM의 핵심 가치이다.

---

## 10. Counter(성능 카운터) 수집 메커니즘

9장까지는 **개별 HTTP 요청**(XLog)의 데이터 흐름을 추적했다. 하지만 APM에는 "이 요청이 느렸다"는 개별 추적 외에, "지금 시스템 전체가 어떤 상태인가"를 보여주는 **종합 지표**도 필요한다.

이 장에서 다루는 Counter가 바로 그 역할이다. TPS, Heap 사용량, GC 횟수, Active Service 등 **시스템 수준의 수치 데이터**가 어떻게 수집되고 전송되는지를 설명한다. Part 3에서 TPS 차트, Heap 차트, GC 차트를 볼 때, 그 그래프의 데이터가 정확히 여기서 온다는 것을 알게 된다.

### 10.1 Counter란?

Counter는 JVM의 **수치형 성능 지표**를 주기적으로 수집한 데이터이다. XLog가 "개별 요청"의 데이터라면, Counter는 "시스템 전체"의 상태 데이터이다.

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

9장(XLog)과 10장(Counter)에서 Agent가 데이터를 수집하고 Server로 전송하는 과정을 보았다. Server는 이 데이터를 **수신만 하는 것이 아니라, 저장해야** 한다. 실시간 모니터링뿐 아니라, "어제 오후 3시의 XLog를 다시 보고 싶다"는 **과거 조회**가 가능해야 하기 때문이다.

이 장에서는 Scouter Server가 데이터를 어떤 구조로 디스크에 저장하는지, 보존 기간은 어떻게 결정되는지를 다룹니다.

### 11.1 파일 기반 DB

Scouter Server는 별도의 RDBMS나 NoSQL을 사용하지 않는다. **자체 파일 기반 DB**를 사용한다.

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

`scouter_data` Docker 볼륨이 Server의 `/database` 디렉토리에 마운트되어, **컨테이너를 재시작해도 데이터가 유지**된다.

---

## 12. Object 관리와 생명주기

지금까지 데이터의 흐름(수집→전송→저장)을 추적했다. 하지만 이 모든 데이터에는 **"어디서 왔는가"**라는 출처 정보가 붙어야 한다. TPS 45라는 숫자가 tomcat1의 것인지 tomcat2의 것인지 구분할 수 없다면 의미가 없다.

Scouter에서 이 "모니터링 대상의 식별과 상태 관리"를 담당하는 것이 **Object**이다. Client 좌측 패널에 보이는 tomcat1, tomcat2 각각이 하나의 Object이며, 이 장에서는 Object가 어떻게 등록되고, 어떻게 죽은 것으로 판정되며, 컨테이너 재빌드 시 왜 중복으로 보이는지를 설명한다.

### 12.1 Object란?

Scouter에서 **Object**는 모니터링 대상 하나를 의미한다. 본 프로젝트에서는 Tomcat 인스턴스가 각각 하나의 Object이다.

### 12.2 Object 식별 체계

```
Object 이름 구조: /<host>/<objType>/<objName>

본 프로젝트 예시:
  /middleware/tomcat1    ← mw-tomcat1 컨테이너의 Agent
  /middleware/tomcat2    ← mw-tomcat2 컨테이너의 Agent
```

Object 이름은 JVM 기동 인자 `-Dobj_name=tomcat1`로 결정된다.

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

Docker 컨테이너를 재빌드(`docker-compose up --build`)하면, 새 컨테이너의 **Container ID가 변경**된다. 이 때 Scouter Client에 **같은 이름의 Object가 여러 개** 보일 수 있다:

```
▼ /middleware
   ├─ tomcat1     ← 새 컨테이너 (Active, 파란색)
   ├─ tomcat1     ← 이전 컨테이너 (Dead, 회색)  ← obj_deadtime 후 사라짐
   ├─ tomcat2     ← 새 컨테이너 (Active, 파란색)
   └─ tomcat2     ← 이전 컨테이너 (Dead, 회색)
```

**해결 방법:**
- `obj_deadtime=30000` (30초) 후 Dead Object는 자동으로 목록에서 제거된다
- 즉시 정리하려면: Scouter Client에서 회색 Object를 우클릭 → **Delete** (또는 Server 재시작)

---

## 13. Scouter 소스코드 아키텍처

Part 2의 마지막 장이다. 6~12장에서 BCI, 통신 프로토콜, 데이터 파이프라인, 저장 구조, Object 관리를 각각 개별적으로 다루었다. 이 장에서는 그 모든 것이 **소스코드 수준에서 어떻게 조직되어 있는지**를 한 눈에 정리한다. 앞에서 설명한 `TraceMain`, `DataProxy`, `XLogHandler` 같은 클래스들이 실제 코드에서 어디에 위치하고 어떤 의존 관계를 맺는지를 보여줌으로써, Part 2 전체를 하나의 그림으로 통합한다.

Scouter의 동작을 깊이 이해하려면 소스코드의 패키지 구조와 핵심 클래스 간의 관계를 알아야 한다. Scouter는 GitHub(`scouter-project/scouter`)에서 Apache 2.0 라이선스로 공개되어 있으며, Java로 작성되었다.

### 13.1 전체 모듈 구조

```
scouter/
├── scouter.common/          ← Agent, Server, Client가 공유하는 코드
│   ├── pack/                  XLogPack, PerfCounterPack 등 Pack 정의
│   ├── io/                    DataOutputX, DataInputX (직렬화)
│   ├── util/                  HashUtil, DateUtil 등 유틸리티
│   └── net/                   네트워크 프로토콜 상수
│
├── scouter.agent.java/      ← Java Agent (JVM에 부착되는 코드)
│   ├── asm/                   ASM 기반 Bytecode 변조 클래스
│   │   ├── HttpServiceASM.java      HTTP 서블릿 Hook
│   │   ├── JDBCConnectionOpenASM.java  JDBC Connection Hook
│   │   ├── JDBCPreparedStatementASM.java  PreparedStatement Hook
│   │   ├── MethodASM.java            사용자 정의 메서드 Hook
│   │   └── ScouterClassFileTransformer.java  ClassFileTransformer 구현
│   │
│   ├── trace/                 런타임 추적 로직
│   │   ├── TraceMain.java           startHttpService(), endHttpService()
│   │   ├── TraceContext.java        요청별 컨텍스트 (txid, elapsed, steps)
│   │   ├── TraceContextManager.java ThreadLocal 기반 컨텍스트 관리
│   │   ├── TraceSql.java            SQL 추적 로직
│   │   └── TraceApiCall.java        외부 API 호출 추적
│   │
│   ├── counter/               성능 카운터 수집
│   │   ├── CounterExecutingTask.java  2초 주기 수집 스케줄러
│   │   ├── TomcatJMXCounter.java      Tomcat MXBean 조회
│   │   └── JVMPerf.java              JVM 메트릭 (Heap, GC, Thread)
│   │
│   ├── proxy/                 네트워크 전송 프록시
│   │   ├── DataProxy.java           UDP/TCP 전송 (XLog, Counter)
│   │   └── TextProxy.java           Text Dictionary TCP 전송
│   │
│   ├── configure/             설정 관리
│   │   └── Configure.java           agent.conf 파싱, 원격 설정 변경
│   │
│   └── AgentBoot.java         premain() 진입점
│
├── scouter.server/           ← Scouter Server (Collector)
│   ├── core/                  데이터 수신 및 처리
│   │   ├── UDPDataProcessor.java    UDP 패킷 수신 및 Pack 디코딩
│   │   ├── TCPDataProcessor.java    TCP 연결 관리 및 Pack 처리
│   │   └── AgentManager.java        Object 생명주기 관리
│   │
│   ├── db/                    파일 기반 DB
│   │   ├── XLogWR.java              XLog 일자별 파일 읽기/쓰기
│   │   ├── CounterRD.java           Counter 데이터 읽기
│   │   ├── TextRD.java              Text Dictionary 저장/조회
│   │   └── ProfileRD.java           Profile Step 저장/조회
│   │
│   ├── handler/               Pack 타입별 핸들러
│   │   ├── XLogHandler.java         XLogPack 처리 → 저장 + Client Push
│   │   ├── CounterHandler.java      PerfCounterPack 처리 → 집계 + 저장
│   │   ├── ObjectHandler.java       ObjectPack 처리 → Object 등록/해제
│   │   └── AlertHandler.java        AlertPack 처리 → 알림 발생
│   │
│   └── netio/                 Client 통신
│       ├── TcpAgentWorker.java      Client TCP 요청 처리
│       └── RealTimeXLogReader.java  Client에 XLog 실시간 Push
│
└── scouter.client/           ← Eclipse RCP 기반 GUI (Viewer)
    ├── xlog/                  XLog 차트 렌더링
    ├── counter/               Counter 차트 렌더링
    ├── thread/                Thread List/Dump 뷰
    └── net/                   Server 통신 (TCP)
```

### 13.2 Agent 내부의 핵심 실행 흐름

```
[JVM 시작]
    │
    ▼
AgentBoot.premain(args, inst)
    │
    ├─ Configure.getInstance().load()  ← agent.conf 파싱
    │   hook_service_patterns, hook_method_patterns 등을 메모리에 로드
    │
    ├─ inst.addTransformer(ScouterClassFileTransformer)  ← Hook 등록
    │
    ├─ CounterExecutingTask.start()    ← 2초 주기 Counter 수집 스레드 시작
    │   └─ 무한루프: JVMPerf 조회 → PerfCounterPack 생성 → DataProxy.sendCounter()
    │
    ├─ DataProxy.openUDP()             ← UDP 소켓 생성
    │
    └─ TcpWorker.start()              ← TCP 연결 스레드 시작
        └─ Server에 ObjectPack 전송 (Agent 등록)
        └─ 30초마다 Heartbeat 전송

[이후 HTTP 요청이 들어올 때]
    │
    ▼
Servlet.service() → (Hook에 의해) TraceMain.startHttpService() 호출
    │
    ├─ TraceContext 생성 (txid 발급, startTime 기록)
    ├─ ThreadLocal에 TraceContext 저장
    │
    ▼
Controller.method() → (Hook에 의해) Step 기록
    │
    ▼
Servlet.service() 종료 → (Hook에 의해) TraceMain.endHttpService() 호출
    │
    ├─ elapsed 계산
    ├─ XLogPack 생성
    ├─ DataProxy.sendXLog(pack)   → UDP 전송
    ├─ Profile Steps을 메모리 캐시에 보관 (Client 요청 시 TCP로 전달)
    └─ ThreadLocal 정리
```

### 13.3 Server 내부의 데이터 처리 파이프라인

```
[UDP 수신]
    │
UDPDataProcessor (수신 스레드)
    │
    ├─ byte[] → DataInputX로 디시리얼라이즈 → Pack 객체 생성
    │
    ├─ Pack Type 판별:
    │   ├─ 0x01 (XLogPack)       → XLogHandler
    │   ├─ 0x02 (PerfCounterPack) → CounterHandler
    │   └─ 0x12 (AlertPack)      → AlertHandler
    │
    ▼
XLogHandler:
    ├─ XLogWR.write(pack)          → /database/xlog/20260313.xlog에 append
    ├─ ProfileRD.write(steps)      → /database/profile/20260313.profile에 append
    └─ RealTimeXLogReader.add(pack) → 연결된 Client들에게 TCP Push

CounterHandler:
    ├─ CounterRD.write(pack)       → /database/counter/20260313/tomcat1/TPS.data
    ├─ 5초 평균 집계 → 저장
    └─ Client Push

[TCP 수신]
    │
TCPDataProcessor
    ├─ ObjectPack 수신  → AgentManager.register()   → Object 목록에 추가
    ├─ TextPack 수신    → TextRD.write()             → Text Dictionary에 저장
    └─ Client 요청 수신 → Profile Steps / 과거 XLog 등을 조회하여 응답
```

### 13.4 핵심 클래스 간 의존 관계

```
                    Agent 내부
  ┌──────────────────────────────────────────────────────┐
  │                                                      │
  │  ScouterClassFileTransformer                         │
  │      │                                               │
  │      ├─ HttpServiceASM ──→ TraceMain                │
  │      ├─ JDBCPreparedStatementASM ──→ TraceSql       │
  │      ├─ MethodASM ──→ TraceMain                     │
  │      └─ HttpCallASM ──→ TraceApiCall                │
  │                   │                                  │
  │                   ▼                                  │
  │           TraceContextManager (ThreadLocal)          │
  │                   │                                  │
  │                   ▼                                  │
  │             TraceContext ──→ Profile Steps (List)    │
  │                   │                                  │
  │                   ▼                                  │
  │             DataProxy ──→ UDP/TCP 전송               │
  │                                                      │
  └──────────────────────────────────────────────────────┘
```

이 구조에서 모든 ASM 클래스는 `TraceMain`의 static 메서드를 호출하는 코드를 삽입하고, `TraceMain`은 `TraceContextManager`를 통해 현재 스레드의 컨텍스트를 관리하며, 트랜잭션 종료 시 `DataProxy`를 통해 Server로 전송한다.

### Part 2 정리 — "점 하나"의 일생을 완전히 이해했다

Part 2를 마치면, Part 1에서 봤던 XLog의 파란 점 하나가 어떤 여정을 거쳐 화면에 나타났는지를 **엔드-투-엔드**로 설명할 수 있다:

```
curl 요청 → Nginx → Tomcat JVM
                       │
               ① BCI(6장): Agent가 Servlet.service()에 삽입한 코드가
                  시작 시간을 기록하고 TraceContext를 생성
                       │
               ② 메서드 실행 추적: ThreadLocal로 요청 컨텍스트를 유지하며
                  Controller, SQL 등의 호출을 Step으로 기록
                       │
               ③ XLogPack 생성(9장): txid, elapsed, service 해시 등을 패킹
                       │
               ④ UDP 전송(7장): DataProxy가 62바이트 Pack을 Server로 전송
                       │
               ⑤ Server 수신·저장(11장): 파일 DB에 append, 실시간 큐에 추가
                       │
               ⑥ Client Push: Server가 TCP로 XLogPack을 Client에 푸시
                       │
               ⑦ 화면 렌더링: X축=완료시각, Y축=elapsed, 색상=에러여부
                  → 파란 점 하나가 찍힘
```

이 흐름의 각 단계를 이해하면, **"데이터가 어디서 끊겼는가"**를 단계별로 체크하는 진단 능력이 생깁니다:
- Object는 보이는데 점이 안 찍힌다 → ①~③ 구간 (Hook 설정 문제)
- Agent 로그엔 전송했다는데 점이 없다 → ④~⑤ 구간 (UDP 통신 문제)
- 점은 찍히는데 Profile이 안 열린다 → ⑥ 구간 (TCP 통신 문제)

이제 Part 3에서 이 데이터가 **Client 화면에서 어떤 형태로 시각화되는지**를 하나씩 살펴본다.

---

# Part 3. 모니터링 뷰 완전 가이드

> Part 2에서 Scouter의 내부 동작 메커니즘을 이해했다. Agent가 바이트코드를 변조하여 데이터를 수집하고, UDP/TCP로 Server에 전송하며, Server가 이를 파일 DB에 저장하는 전체 파이프라인을 알게 되었다.
>
> Part 3에서는 그 파이프라인의 **최종 출력물** — 즉, Scouter Client에서 실제로 눈에 보이는 **모니터링 뷰**들을 다룹니다. 각 뷰가 Part 2에서 설명한 어떤 데이터를 시각화하는지 연결하며, 뷰를 열고 읽는 방법뿐 아니라 **그래프 패턴이 의미하는 바**를 해석하는 방법을 익힙니다.
>
> **Part 2 → Part 3 대응 관계:**
> - 9장(XLog 내부 구조) → 14장(XLog 뷰에서 점 읽기)
> - 10장(Counter 수집) → 15~18장(TPS, Heap, GC 등 Counter 차트 읽기)
> - 12장(Object 관리) → Part 5 실습 9(Object 생명주기 관찰)

## 14. XLog — 트랜잭션 분석의 핵심

### 14.1 XLog란?

XLog는 Scouter(그리고 Jennifer)의 **가장 핵심적인 뷰**이다. 다른 뷰는 못 열어도 XLog만 열어두면 시스템 상태의 80%를 파악할 수 있다.

- **X축**: 요청 완료 시각 (시간 흐름)
- **Y축**: 응답시간(ms) — 높을수록 느린 요청
- **점 하나 = HTTP 요청 하나** — curl 한 번 = 점 하나
- **색상**: 파란색 = 정상 완료, 빨간색 = 에러 발생 (HTTP 5xx, Exception 등)

Part 2의 9장에서 다뤘듯, 점의 좌표는 XLogPack의 필드로 직접 결정된다:
- X좌표 = `endtime` (요청 완료 시각)
- Y좌표 = `elapsed` (응답시간 ms)
- 색상 = `error` (0이면 파란색, 그 외 빨간색)

### 14.2 XLog 차트 열기

1. 좌측 Object에서 `tomcat1` 우클릭 → **XLog** 클릭
2. 실시간으로 점이 찍히는 차트가 열림
3. 요청이 없으면 빈 화면 — `curl -sk https://localhost/health`를 실행하면 점이 나타남

### 14.3 XLog 패턴 분석

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

### 14.4 XLog 점 클릭 → Profile 상세 분석

XLog의 진짜 힘은 **점을 클릭했을 때** 발휘된다. 점을 클릭하면 해당 요청의 **전체 처리 과정**(Profile)이 시간순으로 펼쳐집니다:

```
점 클릭 시 보이는 Profile 정보:
─────────────────────────────
  URL        : /health                  ← 어떤 경로로 들어온 요청인가
  응답시간    : 12ms                     ← 전체 처리에 걸린 시간
  CPU Time   : 850μs                    ← CPU를 실제로 사용한 시간
  Client IP  : 172.18.0.1               ← 요청을 보낸 클라이언트

  [0ms]  → START service=/health
  [1ms]  → METHOD HealthController.health()
  [2ms]  →   METHOD InetAddress.getLocalHost()     elapsed=3ms
  [11ms] → END elapsed=11ms cpu=850μs
```

| 항목 | 의미 | 활용 |
|------|------|------|
| **URL** | 요청 경로 | 어떤 API가 문제인지 식별 |
| **SQL 쿼리** | 실행된 SQL문과 소요 시간 | DB 병목 진단 |
| **Method Call** | Hook된 메서드의 호출 순서와 시간 | 코드 레벨 병목 식별 |
| **API Call** | 외부 서비스 호출 내역 | 외부 의존성 지연 파악 |
| **Error** | 에러 스택트레이스 | 에러 원인 추적 |

> **APM의 핵심 가치**: 로그 파일을 grep하는 대신, **점 하나를 클릭**하면 "이 요청이 왜 느렸는지"가 SQL 레벨, 메서드 레벨에서 바로 보이다. 이것이 인프라 모니터링(Prometheus/Grafana)과 APM의 결정적 차이이다.

### 14.5 XLog 드래그 선택

차트에서 영역을 **드래그**하면 해당 시간대+응답시간 범위의 요청만 필터링하여 목록으로 볼 수 있다.

```
실전 시나리오: "오후 2시에 갑자기 느려졌다"는 보고를 받았을 때

  응답시간(ms)
  2000 |  드래그 범위: ┌────────────┐
  1000 |              │  ●  ●  ●   │ ← 이 영역만 선택
   500 |              │ ●  ● ●    │
       |──────────────└────────────┘────
     0 | ●●●●●●●●●●                 ●●●●●
       14:00        14:01        14:02

  드래그하면 → 해당 범위의 요청 목록이 팝업
  → 각 요청을 클릭하여 Profile 확인
  → "SQL elapsed=1200ms" 발견
  → "이 시간대에 특정 SQL이 느려졌구나" 확인
```

이 기법은 Jennifer에서도 동일하게 사용되며, APM 분석의 가장 기본적이고 강력한 도구이다.

---

## 15. TPS 모니터링

14장의 XLog가 **개별 요청을 점으로** 보여준다면, TPS는 그 점들을 **초 단위로 세어서 선(line)으로** 보여준다. "지금 초당 몇 건의 요청이 처리되고 있는가"라는 시스템의 처리 용량을 한눈에 파악하는 지표이다.

### 15.1 TPS(Transaction Per Second)란?

- 초당 처리되는 트랜잭션(HTTP 요청) 수
- 시스템의 **처리 용량**을 나타내는 핵심 지표

### 15.2 TPS 차트 열기

1. Object에서 `tomcat1` 우클릭 → **Counter** → **TPS**
2. (선택) `tomcat2`도 같은 방식으로 열면 2대의 TPS를 비교 가능

### 15.3 TPS 해석

| TPS 값 | 의미 | 대응 |
|---------|------|------|
| 0 | 요청이 없음 | 정상 (비업무 시간) 또는 장애 (업무 시간에 0이면 위험) |
| 1~10 | 가벼운 트래픽 | 정상 |
| 50~100 | 보통 수준 | 정상, Heap/GC 함께 모니터링 |
| 100+ | 높은 트래픽 | maxThreads(200) 대비 부하율 확인 필요 |

**TPS를 읽는 핵심 포인트:**
- TPS의 **절대값**보다 **변화 패턴**이 중요한다
- 평소 TPS 50인 서비스에서 갑자기 10으로 떨어졌다면, 서버 문제이거나 앞단(Nginx, 로드밸런서)의 문제
- 평소 TPS 50인데 200으로 치솟았다면, 트래픽 급증이나 DDoS 가능성
- tomcat1과 tomcat2의 TPS를 비교하면 **로드밸런싱이 균등한지** 즉시 확인 가능

### 15.4 TPS 내부 계산 방식

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

## 16. Active Service 모니터링

TPS가 "완료된 요청의 수"라면, Active Service는 "아직 완료되지 않은, **지금 처리 중인 요청의 수**"이다. TPS가 높더라도 Active Service가 낮으면 서버가 빠르게 소화하고 있다는 뜻이고, TPS는 같은데 Active Service가 높아지면 **요청이 밀리고 있다**는 경고 신호이다. 두 지표를 함께 봐야 시스템 상태를 정확히 판단할 수 있다.

### 16.1 Active Service란?

- **현재 처리 중인 요청 수** (아직 응답이 완료되지 않은 요청)
- 이 숫자가 높으면 서버가 요청을 소화하지 못하고 있다는 의미

### 16.2 Active Service 차트 열기

Object에서 `tomcat1` 우클릭 → **Counter** → **Active Service**

### 16.3 Active Service 해석

| 값 | 의미 | 다음 행동 |
|----|------|----------|
| 0 | 처리 중인 요청 없음 (유휴 상태) | 정상 |
| 1~5 | 정상 | 모니터링 유지 |
| 10+ | 부하가 걸리고 있음 | XLog에서 느린 점 확인, Thread Dump 검토 |
| 50+ | **심각한 병목** | 즉시 Thread Dump → BLOCKED 쓰레드 확인 |

**TPS와 Active Service의 관계로 상황 판단하기:**

```
Case 1: TPS 높음 + Active 낮음 = 정상 (빠르게 잘 처리하고 있음)
Case 2: TPS 높음 + Active 높음 = 한계 (처리는 하지만 밀리고 있음)
Case 3: TPS 낮음 + Active 높음 = 위험 (요청이 쌓이고 처리가 안 됨)
Case 4: TPS 낮음 + Active 낮음 = 유휴 (트래픽이 적은 상태)
```

**Case 3이 가장 위험**한다. 요청은 들어오는데 처리가 안 되고 있다는 뜻이므로, 즉시 Thread Dump를 떠서 쓰레드가 어디에 걸려 있는지 확인해야 한다.

### 16.4 Active Service 내부 계산

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

## 17. JVM 힙 메모리 모니터링

TPS와 Active Service가 **요청 수준의 지표**라면, 힙 메모리는 **JVM 자원 수준의 지표**이다. 요청을 처리할 때마다 Java 객체가 힙에 생성되고, 힙이 가득 차면 GC가 발생하여 응답 지연을 일으킵니다. 따라서 힙 메모리 모니터링은 "왜 갑자기 느려졌는가?"의 원인을 추적하는 출발점이 된다.

### 17.1 힙 메모리란?

- Java 애플리케이션이 객체를 저장하는 메모리 영역
- 메모리가 가득 차면 **GC(Garbage Collection)**가 실행되어 사용하지 않는 객체를 정리
- GC 실행 중에는 애플리케이션이 잠시 멈춤 → **응답 지연 발생 가능**

### 17.2 Heap Memory 차트 열기

Object에서 `tomcat1` 우클릭 → **Counter** → **Heap Used**

### 17.3 힙 메모리 패턴 읽기

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

**실전 팁**: Heap Used 차트를 볼 때는 반드시 **GC Time 차트를 옆에 나란히 열어둔다**. Heap이 급락하는 시점이 GC가 실행된 시점이고, 그 GC에 얼마나 걸렸는지가 응답 지연의 직접 원인이 된다. 다음 장에서 이 관계를 자세히 다룬다.

---

## 18. GC 모니터링

17장에서 힙 메모리의 "톱니 모양 패턴"을 언급했다. 그 톱니의 급락 지점이 바로 **GC(Garbage Collection)**가 실행된 시점이다. GC 모니터링은 힙 메모리와 짝으로 봐야 완전한 그림이 된다 — 힙이 "얼마나 쌓였는가"를 보여준다면, GC는 "정리에 얼마나 걸렸는가"를 보여준다.

### 18.1 GC가 중요한 이유

GC(Garbage Collection)는 JVM이 더 이상 참조되지 않는 객체를 정리하는 과정이다. GC 실행 중에는 **Stop-the-World**(모든 애플리케이션 쓰레드 일시 정지)가 발생하므로, GC가 잦거나 길면 응답 지연의 직접적인 원인이 된다.

### 18.2 GC 관련 Counter

| Counter | 의미 |
|---------|------|
| **GC Count** | 2초 동안 발생한 GC 횟수 |
| **GC Time** | 2초 동안 GC에 소요된 시간 (ms) |

### 18.3 GC와 XLog의 상관관계

GC가 오래 걸리면 XLog에서 점이 동시에 올라가는 현상이 나타난다:

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

**GC 문제 진단 체크리스트:**

| 증상 | 가능한 원인 | 해결 방향 |
|------|-----------|----------|
| GC Time이 주기적으로 높음 | Young GC가 잦음 | `-Xmn`(Young 영역) 크기 조정 |
| GC Time이 갑자기 수초 단위 | Full GC 발생 | Heap Dump로 대형 객체 분석 |
| GC 후에도 Heap이 안 떨어짐 | 메모리 누수 | 객체 참조 체인 분석 필요 |
| GC Count가 0인데 Heap이 계속 참 | GC가 트리거되지 않음 | `-Xmx` 증가 또는 GC 알고리즘 변경 |

> **한 줄 요약**: "XLog에서 주기적으로 점이 올라간다" → Heap/GC를 먼저 확인한다. GC가 원인이면 JVM 튜닝으로 해결되고, GC가 아니면 코드 레벨(SQL, 외부 API)을 봐야 한다.

---

## 19. 쓰레드 분석

지금까지 XLog, TPS, Active Service, Heap, GC 등의 **수치 그래프**로 시스템 상태를 관찰했다. 하지만 이 그래프들이 "무언가 느리다"는 현상을 보여줄 뿐, **왜 느린지**는 알려주지 않는다. 쓰레드 분석은 "지금 이 순간 서버가 정확히 무엇을 하고 있는가"를 코드 레벨(스택트레이스)에서 보여주는 진단 도구이다. Active Service가 높은데 원인을 모를 때, Thread Dump를 뜨면 답이 보이다.

### 19.1 Thread List 보기

Object에서 `tomcat1` 우클릭 → **Thread List / Thread Dump**

### 19.2 쓰레드 상태

| 상태 | 의미 |
|------|------|
| **RUNNABLE** | 실행 중 |
| **WAITING** | 다른 쓰레드의 알림을 대기 중 |
| **TIMED_WAITING** | 타임아웃이 있는 대기 |
| **BLOCKED** | 락(Lock) 획득 대기 중 ← **병목 원인** |

### 19.3 Thread Dump 분석

Thread Dump는 현재 시점의 **모든 쓰레드의 스택트레이스**를 캡처한다:

```
"http-nio-8080-exec-1" #42 daemon prio=5
   java.lang.Thread.State: RUNNABLE
   at com.middleware.demo.controller.HealthController.health(HealthController.java:19)
   at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
   at org.apache.catalina.core.ApplicationFilterChain.doFilter(ApplicationFilterChain.java:166)
   ...
```

> BLOCKED 상태의 쓰레드가 많으면 **데드락** 또는 **DB 커넥션 풀 고갈**을 의심해야 한다.

### 19.4 Thread Dump 읽는 순서

Thread Dump를 처음 보면 수백 줄의 스택트레이스에 압도된다. 다음 순서로 읽으면 효율적이다:

```
Step 1. BLOCKED 쓰레드를 먼저 찾는다
        → "waiting to lock" 뒤의 객체 주소를 메모
Step 2. 그 객체를 잡고 있는 쓰레드를 찾는다
        → "locked" 뒤에 같은 주소가 있는 쓰레드
Step 3. 그 쓰레드의 스택트레이스를 읽는다
        → 어떤 코드에서 락을 잡고 뭘 하고 있는지 확인
Step 4. 그것이 병목의 근본 원인
```

### 19.5 Thread Dump 활용 패턴

| 상황 | Thread Dump에서 보이는 패턴 | 원인 |
|------|---------------------------|------|
| Active Service가 높음 | 많은 쓰레드가 RUNNABLE + DB 관련 스택 | DB 쿼리 느림 |
| Active Service가 높음 | 많은 쓰레드가 BLOCKED + synchronized | 락 경합 |
| Active Service가 높음 | 많은 쓰레드가 WAITING + socket | 외부 API 타임아웃 |

---

## 20. SQL 추적과 프로파일링

19장의 Thread Dump가 "이 스레드가 DB 관련 코드에 머물러 있다"고 알려줬다면, 다음 질문은 "**어떤 SQL이 느린가?**"이다. SQL 추적은 6장에서 다룬 JDBC Hook이 실제로 어떤 데이터를 보여주는지를 다룹니다. XLog 점을 클릭하면 Profile에서 실행된 SQL문과 소요 시간을 바로 확인할 수 있다.

### 20.1 JDBC Hook 원리

Scouter Agent는 `java.sql.Connection`의 `prepareStatement()`, `createStatement()` 메서드를 Hook하여, 실행되는 모든 SQL을 자동 추적한다.

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

### 20.2 SQL 추적 결과

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

### 20.3 느린 SQL 찾기

**실전에서 가장 많이 쓰는 진단 패턴**은 다음과 같다:

```
진단 흐름:

  XLog에서 느린 점 발견 (Y축이 높은 점)
    │
    ▼
  점 클릭 → Profile 열기
    │
    ├─ SQL Step이 있는가?
    │   ├─ YES → SQL elapsed 확인
    │   │         elapsed가 전체의 80% 이상이면 → DB 병목
    │   │         실행 SQL문을 DBA에게 전달하여 실행 계획(EXPLAIN) 분석
    │   │
    │   └─ NO  → SQL 외 다른 원인
    │             METHOD Step의 elapsed 확인 → 코드 병목
    │             API Call Step의 elapsed 확인 → 외부 API 지연
    │
    └─ Error Step이 있는가?
        └─ YES → 에러 메시지와 스택트레이스로 원인 파악
```

> 본 프로젝트의 `/health` 엔드포인트는 DB를 사용하지 않으므로 SQL Step이 나타나지 않는다. DB가 포함된 프로젝트에서는 이 진단 흐름이 장애 분석의 핵심 도구가 된다.

---

## 21. Active Service EQ (이퀄라이저)

16장에서 Active Service를 **숫자(선 그래프)**로 보았다. Active Service EQ는 같은 데이터를 **다른 방식으로 시각화**한다 — 현재 처리 중인 요청들의 경과 시간을 색상 막대로 표현하여, "몇 개가 처리 중인가"뿐 아니라 "**얼마나 오래 걸리고 있는가**"까지 한눈에 보여준다. Jennifer APM에서도 동일한 EQ 뷰가 핵심 모니터링 도구로 사용된다.

### 21.1 Active Service EQ란?

Active Service EQ(Equalizer)는 **현재 처리 중인 요청의 경과 시간을 색상 막대**로 시각화한 뷰이다. 오디오 이퀄라이저처럼 막대가 올라가고 내려가며, 시스템의 실시간 부하 상태를 직관적으로 보여준다.

### 21.2 EQ 색상 의미

```
Active Service EQ:

  █ █ █ █ █ █ █ █ █
  ↑               ↑
 0초             8초+

  █ 녹색 (0~3초)   : 정상 처리 중
  █ 노란색 (3~8초)  : 느린 요청 (주의)
  █ 빨간색 (8초+)   : 매우 느린 요청 (위험)
```

### 21.3 EQ 열기

Object에서 `tomcat1` 우클릭 → **Active Service EQ**

### 21.4 EQ 해석

| 패턴 | 의미 |
|------|------|
| 녹색 막대만 간헐적으로 나타남 | 정상 — 요청이 빠르게 처리됨 |
| 노란색/빨간색 막대가 지속 | 느린 요청 — Thread Dump 분석 필요 |
| 빨간색 막대가 가득 참 | 시스템 마비 — 즉시 대응 필요 |

---

## 22. 전체 뷰 카탈로그

### 22.1 Object 우클릭 메뉴 전체 목록

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

### 22.2 메뉴바 전용 뷰

| 뷰 | 설명 |
|----|------|
| **Alert** | 알림 목록 (응답시간 초과, GC 이상 등) |
| **Object Dashboard** | 전체 Object의 종합 현황 |
| **Group XLog** | 여러 Object의 XLog를 하나의 차트에 |
| **Group Counter** | 여러 Object의 Counter를 하나의 차트에 |

### Part 3 정리 — 뷰 간의 관계를 머릿속에 그려라

Part 3에서 9개의 모니터링 뷰를 살펴보았다. 각 뷰를 개별적으로 아는 것도 중요하지만, 진짜 모니터링 역량은 **뷰 간의 관계**에서 나온다. 장애 상황에서의 진단 흐름을 정리하면:

```
장애 감지 → 진단 흐름:

  ① XLog를 본다 — "점이 올라갔는가? 빨간 점이 있는가?"
       │
       ├─ 점이 올라갔다 (느려졌다)
       │   │
       │   ├─ ② TPS를 본다 — "처리량이 줄었는가, 유지되는가?"
       │   │   ├─ TPS 유지 + 점 올라감 → 특정 요청만 느림 → 점 클릭 → Profile
       │   │   └─ TPS 감소 + 점 올라감 → 시스템 전체 문제
       │   │
       │   ├─ ③ Active Service를 본다 — "요청이 밀리고 있는가?"
       │   │   └─ Active 높음 → Thread Dump 확인
       │   │
       │   ├─ ④ Heap/GC를 본다 — "GC 때문에 느린 건가?"
       │   │   └─ GC Time 스파이크와 XLog 상승이 동시 → JVM 튜닝 필요
       │   │
       │   └─ ⑤ 점 클릭 → Profile — "어떤 SQL/API가 병목인가?"
       │
       └─ 빨간 점이 있다 (에러)
           └─ 빨간 점 클릭 → Error Step → 스택트레이스 확인
```

이 흐름이 **몸에 익을 때까지** Part 5의 실습을 반복하는 것을 권장한다.

---

# Part 4. 실전 활용

> Part 3에서 개별 뷰의 의미와 읽는 법을 익혔다. 하지만 실제 운영 환경에서는 뷰 하나만 보고 판단하지 않는다. **여러 뷰를 동시에 열어 놓고, 지표 간의 상관관계를 읽어내는 것**이 APM 모니터링의 핵심 역량이다.
>
> Part 4에서는 대시보드 구성(23장), 부하 테스트와 모니터링의 결합(24장), 알림 설정(25장)을 통해 Scouter를 **실전에서 활용하는 방법**을 다룹니다. 또한 Prometheus/Grafana, Jennifer와의 비교(28~29장)를 통해 Scouter의 위치를 객관적으로 파악하고, 프로덕션 환경 튜닝(30장)과 트러블슈팅(31장)으로 운영 레벨의 노하우를 정리한다.

## 23. 대시보드 구성하기

### 23.1 추천 대시보드 레이아웃

처음 사용할 때 아래 6개를 열어두면 종합적인 모니터링이 가능한다:

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

### 23.2 대시보드 구성 순서

1. 좌측 Object에서 `tomcat1` 우클릭 → **XLog** → 차트 열기
2. 같은 방식으로 **Counter** → **TPS**, **Heap Used**, **GC Time**, **CPU** 열기
3. `tomcat1` 우클릭 → **Active Service EQ** 열기
4. 각 창을 드래그하여 위치 조정
5. (선택) `tomcat2`에 대해서도 동일하게 열어 비교 모니터링

### 23.3 Group 뷰 활용

tomcat1과 tomcat2의 데이터를 **하나의 차트에서 비교**하려면:

1. 메뉴바 → **Object** → **Group Counter** 선택
2. tomcat1, tomcat2를 모두 선택
3. Counter 종류 선택 (예: TPS)
4. 하나의 차트에 2개의 라인이 표시됨

---

## 24. 부하 테스트와 함께 모니터링하기

23장에서 대시보드를 구성했다면, 이제 **대시보드에 생명을 불어넣을 차례**이다. 아무 요청도 없으면 그래프는 평평한 선일 뿐이니까요. 부하를 주면서 그래프가 어떻게 반응하는지를 관찰하는 것이 Scouter 학습의 가장 효과적인 방법이다.

### 24.1 부하 테스트 스크립트

본 프로젝트에는 다양한 부하 시나리오를 제공하는 `scripts/load-test.sh`가 포함되어 있다:

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

### 24.2 대시보드 시나리오 (시나리오 6)

시나리오 6은 Scouter Client의 **모든 그래프가 동시에 움직이도록** 설계되었다.

```bash
./scripts/load-test.sh 6
```

7개의 Phase를 약 2.5분에 걸쳐 실행한다:

| Phase | 동작 | Scouter에서 확인할 것 |
|-------|------|---------------------|
| 1. Warm-up | 10초간 느린 요청 | XLog에 점 나타남, TPS 상승 시작 |
| 2. Ramp-up | 점진적 부하 증가 | TPS 계단식 상승, Active Service 증가 |
| 3. Burst | 50병렬 × 5회 폭주 | TPS 급등, Active Service 최고치, Heap 급상승 |
| 4. Mixed Heavy | 다양한 URL 고부하 | XLog 점 분산, CPU 상승 |
| 5. Error Injection | 존재하지 않는 URL | XLog에 빨간 점(에러), Error Rate 상승 |
| 6. Recovery | 느린 트래픽 복구 | TPS 하강, Active Service 감소, GC 발생 |
| 7. Spike | 마지막 스파이크 | 모든 지표 최종 급등 후 안정 |

### 24.3 간단한 부하 테스트

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

### 24.4 각 시나리오에서 관찰할 Scouter 뷰 변화

| 시나리오 | XLog | TPS | Active Service | Heap | GC |
|---------|------|-----|----------------|------|----|
| 정상 트래픽 | 100ms 이하 점 | ~1 | 0~1 | 느린 상승 | 거의 없음 |
| 순간 부하 | 점 밀집 + 높은 점 | 급상승 | 급상승 | 빠른 상승 | 활발 |
| WAS 장애 | tomcat2 점 없음 | tomcat1만 | 정상 | 변화 없음 | 변화 없음 |

---

## 25. 알림 설정

24장에서 부하를 주면서 그래프 변화를 직접 관찰했다. 하지만 운영 환경에서 24시간 화면을 주시할 수는 없다. **알림(Alert)**은 "문제가 생기면 알려달라"고 Scouter에게 맡기는 기능이다. 응답시간이 기준을 넘거나, GC가 오래 걸리거나, CPU가 치솟으면 자동으로 알림이 발생한다.

### 25.1 기본 알림 조건

Scouter Server는 기본적으로 아래 상황에서 알림을 발생시킵니다:

| 알림 조건 | 기본값 |
|-----------|--------|
| 응답시간 초과 | 8000ms 이상 |
| GC Time 초과 | 설정값 이상 |
| CPU 사용률 | 80% 이상 |
| Heap 사용률 | 90% 이상 |

### 25.2 알림 확인

알림은 Scouter Client의 **Alert** 패널에서 확인할 수 있다. Client 메뉴바에서 Alert 뷰를 열어 놓으면 실시간으로 알림이 표시된다.

### 25.3 알림 커스터마이징

`server.conf`에서 알림 임계값을 조정할 수 있다:

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

## 26. Agent 설정 상세 레퍼런스

Part 2의 6장에서 Agent가 `agent.conf`의 `hook_service_patterns`, `hook_method_patterns` 등을 읽어 Hook 대상을 결정한다고 설명했다. 이 장에서는 그 설정 파일의 **전체 항목**을 레퍼런스로 정리한다. 필요할 때 찾아보는 사전처럼 활용한다.

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

### 26.1 주요 설정 상세

| 설정 | 값 | 설명 |
|------|---|------|
| `net_collector_ip` | `scouter-server` | Docker 내부 DNS 이름. Docker Compose가 자동으로 `scouter-server` 서비스의 컨테이너 IP로 resolve |
| `trace_interservice_enabled` | `true` | 서비스 간 호출 시 txid를 HTTP 헤더에 전파하여 분산 추적 가능 |
| `profile_step_max_count` | `1024` | 하나의 트랜잭션에서 기록할 수 있는 프로파일 스텝(SQL, 메서드 호출 등) 최대 수 |
| `xlog_sampling_enabled` | `false` | 모든 요청을 수집 (true로 하면 일정 비율만 수집하여 부하 감소) |
| `trace_http_client_ip_header_key` | `X-Forwarded-For` | Nginx 리버스 프록시 뒤에서 실제 클라이언트 IP를 가져오는 헤더 |

### 26.2 고급 Agent 설정 (필요 시 추가 가능)

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

## 27. Server 설정 상세 레퍼런스

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

### 27.1 주요 설정 상세

| 설정 | 값 | 설명 |
|------|---|------|
| `net_tcp_listen_port` | `6100` | Agent의 TCP/UDP, Client의 TCP 모두 이 포트 사용 |
| `net_http_port` | `6180` | REST API 포트. 브라우저에서 `http://localhost:6180`으로 접속 시 Scouter Web API 사용 가능 |
| `obj_deadtime` | `30000` | 30초간 Agent Heartbeat가 없으면 Object를 Dead 상태로 전환 |
| `log_keep_days` | `7` | 7일이 지난 XLog, Counter, Profile 데이터를 자동 삭제하여 디스크 절약 |

### 27.2 Server Dockerfile

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

Server도 JVM 위에서 동작한다. `-Xmx512m`으로 Server의 힙 메모리를 512MB로 제한한다.

---

## 28. Prometheus/Grafana와의 비교

여기까지 오면 자연스럽게 드는 질문이 있다: "우리 프로젝트에는 이미 Prometheus/Grafana가 있는데, Scouter는 왜 필요한가?" 이 장에서는 두 도구의 **아키텍처, 기능, 적합한 상황**을 비교하여 답한다. 결론부터 말하면, 둘은 경쟁이 아니라 **보완 관계**이다.

### 28.1 아키텍처 비교

```
Scouter (Push 모델):
  Agent ──UDP/TCP──→ Server ──TCP──→ Client
  "Agent가 데이터를 Server로 밀어 넣는다"

Prometheus (Pull 모델):
  Exporter ←──HTTP Scrape── Prometheus ←──HTTP── Grafana
  "Prometheus가 Exporter에서 데이터를 가져간다"
```

### 28.2 기능 비교

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

### 28.3 본 프로젝트에서의 역할 분담

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

## 29. Jennifer와의 비교

28장에서 Scouter와 Prometheus/Grafana의 차이를 보았다. 이번에는 Scouter의 **직계 조상**인 Jennifer와 비교한다. Scouter는 Jennifer 핵심 개발자가 오픈소스로 만든 도구이므로, 개념과 용어가 거의 동일하다. **Scouter를 능숙하게 다루면, Jennifer를 쓰는 현업에 바로 투입될 수 있다.**

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

> **Scouter를 사용한 경험은 Jennifer 기반 모니터링 업무에 그대로 적용할 수 있다.**
> 용어와 개념이 거의 동일하며, Jennifer의 핵심 개발자가 만든 도구이므로 설계 철학이 같다.

---

## 30. 프로덕션 환경 튜닝 가이드

28~29장에서 Scouter가 Prometheus/Grafana, Jennifer와 어떻게 다른지를 비교했다. 이제 Scouter를 실제로 **운영 환경에 투입**할 때 고려해야 할 사항을 다룹니다. 본 프로젝트의 Docker Compose 환경은 Agent 2대, TPS 수십 수준이지만, 프로덕션에서는 Agent 수십 대, TPS 수천 이상인 환경을 대비해야 한다. 이 장에서는 샘플링 전략, Server 스케일링, 네트워크 분리, 보안 고려사항을 정리한다.

### 30.1 대용량 트래픽 환경의 샘플링 전략

TPS가 1,000을 넘는 환경에서는 모든 요청을 수집하면 Server의 디스크 I/O와 네트워크 대역폭에 부담이 된다. Scouter는 **다단계 샘플링**을 제공한다.

```properties
# agent.conf — 샘플링 설정

xlog_sampling_enabled=true

# 단계별 샘플링 규칙 (TPS 기준)
# TPS ≤ step1_rate_pct 까지는 step1_rate_pct% 수집
# TPS > step1 이면 step2 규칙 적용, ...

xlog_sampling_step1=100       # TPS 100 이하
xlog_sampling_step1_rate_pct=100  # → 100% 수집 (전수)
xlog_sampling_step2=500       # TPS 100~500
xlog_sampling_step2_rate_pct=50   # → 50% 수집
xlog_sampling_step3=1000      # TPS 500~1000
xlog_sampling_step3_rate_pct=20   # → 20% 수집
xlog_sampling_over_rate_pct=10    # TPS 1000 초과 → 10% 수집
```

**샘플링의 동작 원리:**

```
Agent 내부:

  HTTP 요청 도착
      │
      ▼
  현재 TPS 확인 (CounterCollector가 2초마다 갱신)
      │
      ├─ TPS ≤ 100   → 100% 수집 (모든 요청 XLog 생성)
      ├─ TPS ≤ 500   → 50% 수집  (Random.nextInt(100) < 50 이면 수집)
      ├─ TPS ≤ 1000  → 20% 수집
      └─ TPS > 1000  → 10% 수집
      │
      ▼
  수집 대상이면: TraceContext 생성, 정상 추적
  수집 대상 아니면: TraceContext 미생성, 오버헤드 최소화
```

**에러 요청은 샘플링에서 제외**: `xlog_sampling_exclude_patterns`에 에러 패턴을 등록하면, 에러 응답은 TPS와 무관하게 항상 수집된다. 장애 분석에 필수적인 데이터를 놓치지 않기 위함이다.

### 30.2 Agent 수가 많은 환경 (10대 이상)

| 환경 규모 | Agent 수 | Server 권장 사양 | 고려 사항 |
|-----------|---------|----------------|----------|
| 소규모 | 1~5대 | 1 CPU, 1GB Heap | 기본 설정으로 충분 |
| 중규모 | 5~20대 | 2 CPU, 2GB Heap | UDP 수신 버퍼 증가 필요 |
| 대규모 | 20~50대 | 4 CPU, 4GB Heap | 디스크 I/O 병목 주의 |
| 초대규모 | 50대+ | Server 다중화 필요 | Agent 그룹별로 Server 분리 |

**Server 측 튜닝:**

```properties
# server.conf — 대규모 환경

# Server JVM Heap 증가 (CMD에서 -Xmx 옵션)
# java -Xmx4g -classpath ... scouter.boot.Boot ./lib

# UDP 수신 스레드 수 (기본: 2)
net_udp_worker_count=4

# XLog 저장 큐 크기 (기본: 10000)
xlog_queue_size=50000

# Text Dictionary 캐시 크기 (기본: 100000)
text_cache_size=500000

# 데이터 보존 기간 축소 (디스크 절약)
log_keep_days=3
```

### 30.3 네트워크 분리 환경

프로덕션 환경에서 Agent와 Server가 다른 네트워크 대역에 있을 때:

```
[Production Zone]                    [Monitoring Zone]
Agent (Tomcat)                       Scouter Server
172.16.1.0/24                        10.0.1.0/24

방화벽 규칙:
  TCP 6100: Agent → Server (Object 등록, Profile)
  UDP 6100: Agent → Server (Counter, XLog)
  TCP 6100: Client → Server (데이터 조회)
  TCP 6180: (선택) HTTP API 접근
```

UDP는 방화벽/NAT 환경에서 문제가 될 수 있다. 이 경우 `net_udp_packet_max_bytes`를 MTU(1500) 이하로 설정하여 IP fragmentation을 방지한다:

```properties
# agent.conf
net_udp_packet_max_bytes=1400
```

### 30.4 Profile Step 제한과 메모리 관리

운영 환경에서 단일 트랜잭션이 수천 개의 SQL을 실행하는 경우(배치 작업 등), Profile Step 메모리가 급증할 수 있다.

```properties
# agent.conf

# 트랜잭션당 최대 Profile Step 수 (기본: 1024)
profile_step_max_count=1024

# SQL 바인드 파라미터 수집 (기본: false, 프로덕션에서는 false 권장)
profile_sql_param_enabled=false
# true로 설정하면 SQL의 ? 바인드 값이 수집되어 디버깅에 유용하지만,
# 개인정보(이메일, 전화번호 등)가 Scouter Server에 저장될 수 있음

# HTTP 요청 본문 수집 (기본: false)
profile_http_parameter_enabled=false
# true로 하면 POST body가 Profile에 포함됨 — 보안 주의
```

### 30.5 Container 환경 특수 고려사항

Docker/Kubernetes 환경에서의 주의점:

**Container ID 변경 문제**: 컨테이너가 재생성되면 `obj_name`이 같더라도 내부적으로 다른 Object로 인식될 수 있다. `-Dobj_name=tomcat1`처럼 고정된 이름을 JVM 인자로 지정하면 해결된다.

**Kubernetes에서의 obj_name 전략:**
```yaml
env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: JAVA_OPTS
    value: "-javaagent:/opt/scouter/agent.java/scouter.agent.jar -Dobj_name=$(POD_NAME)"
```

이렇게 하면 Pod 이름(`app-deployment-7b8c9d-x4k2j`)이 Object 이름이 되어, 스케일 아웃/인 시 각 Pod을 구분할 수 있다.

---

## 31. 트러블슈팅

Scouter를 처음 세팅하거나 운영 중에 만나는 **흔한 문제들과 해결 방법**을 정리한다. 대부분의 문제는 Part 2에서 다룬 통신 구조(UDP/TCP 포트), Object 생명주기(Heartbeat 30초), 바이트코드 Hook 대상(agent.conf 패턴)에 대한 이해만 있으면 원인을 빠르게 특정할 수 있다.

### 31.1 Scouter Client 실행 시 "손상된 앱" 오류 (macOS)

```bash
# 보안 속성 제거
xattr -cr ~/Applications/Scouter/scouter.client.app
```

### 31.2 Client에서 Object가 보이지 않음

```bash
# 1. Scouter Server 구동 확인
docker logs mw-scouter 2>&1 | grep "6100\|6180"

# 2. Tomcat에서 Agent 연결 확인
docker logs mw-tomcat1 2>&1 | grep -i scouter
docker logs mw-tomcat2 2>&1 | grep -i scouter

# 3. 포트 접근 확인
nc -z localhost 6100 && echo "OK" || echo "FAIL"
```

### 31.3 Client 접속이 안 됨

| 원인 | 해결 |
|------|------|
| Docker가 실행 중이 아님 | `docker-compose up -d` |
| 6100 포트가 사용 중 | `lsof -i :6100`으로 확인 |
| 방화벽 차단 | macOS 방화벽 설정 확인 |
| Server가 아직 기동 중 | `docker logs mw-scouter`로 기동 완료 확인 |

### 31.4 XLog에 점이 찍히지 않음

트래픽이 없으면 점이 찍히지 않는다:

```bash
curl -sk https://localhost/health
```

실행 직후 XLog에 점이 나타나야 정상이다. 점이 나타나지 않으면:

1. Agent가 정상 연결되었는지 확인 (Object 목록에 tomcat1/tomcat2가 보이는지)
2. `hook_service_patterns` 설정이 올바른지 확인
3. Tomcat 로그에서 Scouter Agent 관련 에러 확인

### 31.5 Object가 여러 개 보임 (중복)

컨테이너를 재빌드하면 이전 Object가 Dead 상태로 남아있다:

- `obj_deadtime=30000` (30초) 후 자동 제거된다
- 즉시 제거: 회색 Object 우클릭 → **Delete**
- 또는 Scouter Server 컨테이너 재시작: `docker restart mw-scouter`

### 31.6 Agent 오버헤드가 의심될 때

Agent를 비활성화하여 비교 테스트:

```bash
# docker-compose.yml에서 JAVA_OPTS의 -javaagent 줄을 주석 처리
# 또는 agent.conf에서:
hook_method_patterns=
hook_service_patterns=
counter_enabled=false
```

이후 동일한 부하 테스트를 실행하여 응답시간을 비교한다. 일반적으로 **1~3% 이내**의 차이가 정상이다.

### Part 4 정리 — "아는 것"에서 "할 수 있는 것"으로

Part 4까지 오면 다음 능력을 갖추게 된다:

```
✓ 대시보드를 구성하여 종합 모니터링 환경을 만들 수 있다 (23장)
✓ 부하 테스트와 모니터링을 연계하여 시스템 한계를 파악할 수 있다 (24장)
✓ 알림을 설정하여 24시간 감시를 자동화할 수 있다 (25장)
✓ Agent/Server 설정을 필요에 따라 조정할 수 있다 (26~27장)
✓ Scouter와 Prometheus/Grafana의 역할을 구분하여 사용할 수 있다 (28장)
✓ Scouter 경험을 Jennifer 기반 업무에 적용할 수 있다 (29장)
✓ 프로덕션 환경의 튜닝 포인트를 알고 있다 (30장)
✓ 흔한 문제를 스스로 해결할 수 있다 (31장)
```

이제 남은 것은 **직접 해보는 것**이다. Part 5의 실습 과제로 넘어간다.

---

# Part 5. 실습 과제

> Part 1~4에서 Scouter의 설치, 내부 동작, 뷰 해석, 실전 활용을 모두 다루었다. 하지만 모니터링은 **읽기만으로는 체득할 수 없는 기술**이다. 그래프 패턴을 눈으로 보고, 변화의 원인을 추론하고, 스스로 검증하는 경험이 있어야 실제 장애 상황에서 빠르게 대응할 수 있다.
>
> Part 5의 12개 실습은 난이도 순으로 구성되어 있으며, 앞선 Part들에서 배운 지식을 **직접 손으로 확인**한다. 실습 1에서 첫 XLog 점을 찍어보는 것부터, 실습 12에서 장애 시뮬레이션과 진단 보고서 작성까지, 점진적으로 역량을 쌓아간다.
>
> 모든 실습의 전제 조건: `docker-compose up -d`로 전체 환경이 구동 중이어야 한다.

## 32. 실습 1 — 첫 번째 XLog 점 찍기 (난이도: ★☆☆☆☆)

### 목표

Scouter Client를 설치하고 접속하여, 직접 보낸 요청이 XLog에 점으로 나타나는 것을 확인한다.

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

## 33. 실습 2 — 대시보드 구성과 실시간 관찰 (난이도: ★★☆☆☆)

### 목표

6개의 모니터링 뷰를 한 화면에 배치하고, 부하를 주면서 모든 차트가 동시에 반응하는 것을 관찰한다.

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

> 하나의 부하 테스트로 **6개 뷰가 동시에 반응**한다. 이것이 APM의 종합 모니터링 능력이다.
> 각 뷰는 같은 데이터의 다른 측면을 보여준다: XLog=개별 요청, TPS=처리량, Active=동시성, Heap/GC=자원 소모.

---

## 34. 실습 3 — XLog 드래그로 느린 요청 필터링 (난이도: ★★☆☆☆)

### 목표

다양한 URL에 대한 부하를 주고, XLog에서 특정 응답시간 범위의 요청만 드래그로 선택하여 분석한다.

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

> XLog 드래그 선택은 **"느린 요청만 골라서 분석"**하는 핵심 기술이다.
> 운영 환경에서 "갑자기 느려졌다"는 보고를 받았을 때, 해당 시간대의 XLog를 드래그하면 원인을 빠르게 파악할 수 있다.

---

## 35. 실습 4 — 로드밸런싱 분포 확인 (난이도: ★★★☆☆)

### 목표

tomcat1과 tomcat2 각각의 XLog와 TPS를 열어두고, Nginx 로드밸런싱이 균등하게 분배되는지 Scouter로 직접 확인한다.

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

> Scouter로 **로드밸런싱이 정상 동작하는지** 실시간 검증할 수 있다.
> 운영 환경에서 "특정 서버에 트래픽이 몰린다"는 상황도 두 Object의 TPS를 비교하면 바로 확인 가능한다.

---

## 36. 실습 5 — GC와 응답시간의 상관관계 분석 (난이도: ★★★☆☆)

### 목표

대량의 객체를 생성하는 부하를 줘서 GC를 유발하고, GC 발생 시점과 XLog 응답시간 상승의 상관관계를 직접 확인한다.

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

> **"GC가 발생하면 모든 쓰레드가 멈추므로 응답시간이 올라간다"**는 이론을 직접 눈으로 확인한다.
> 운영 환경에서 "주기적으로 느려진다"는 증상이 있으면, Heap과 GC Time을 함께 보는 것이 첫 번째 진단 단계이다.

---

## 37. 실습 6 — Thread Dump로 병목 진단 (난이도: ★★★☆☆)

### 목표

부하 상태에서 Thread Dump를 뜨고, 현재 어떤 쓰레드가 어떤 일을 하고 있는지 분석한다.

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

> Thread Dump는 **"지금 이 순간 서버가 정확히 무슨 일을 하고 있는지"**를 보여주는 스냅샷이다.
> 운영 환경에서 "서버가 멈췄다"는 상황에서 Thread Dump를 뜨면, BLOCKED된 쓰레드 → 락을 잡고 있는 쓰레드 → 진짜 원인을 추적할 수 있다.

---

## 38. 실습 7 — 에러 추적과 빨간 점 분석 (난이도: ★★★☆☆)

### 목표

존재하지 않는 URL로 요청을 보내 의도적으로 에러를 발생시키고, XLog에서 빨간 점(에러 트랜잭션)을 추적한다.

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

> XLog의 색상은 즉각적인 이상 징후 파악 도구이다.
> 빨간 점이 갑자기 늘어나면 에러가 급증한 것이므로, 클릭하여 원인을 바로 확인할 수 있다.
> 이것은 로그를 grep하는 것보다 훨씬 빠른 진단 방법이다.

---

## 39. 실습 8 — 전체 대시보드 시나리오 실행 (난이도: ★★★★☆)

### 목표

`load-test.sh`의 대시보드 시나리오(시나리오 6)를 실행하면서, 7개 Phase에 따른 모든 그래프의 변화를 관찰하고 기록한다.

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

아래 표를 채워가면서 관찰한다:

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

> 이 실습은 APM 모니터링의 **종합 시뮬레이션**이다.
> 실제 운영 환경에서 일어나는 상황(트래픽 증가, 폭주, 에러 급증, 복구)을 2.5분에 압축 체험한다.
> "그래프가 이렇게 움직이면 이런 상황이다"라는 **패턴 인식 능력**을 기르는 것이 목표이다.

---

## 40. 실습 9 — Object 생명주기 관찰 (난이도: ★★★★☆)

### 목표

Tomcat 컨테이너를 중지/시작/재빌드하면서, Scouter Client의 Object 상태 변화를 관찰한다.

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

> `obj_deadtime=30000`은 **"30초간 Heartbeat가 없으면 죽은 것으로 간주"**라는 의미이다.
> 이 값을 이해하면 운영 환경에서 "Agent가 갑자기 사라졌다", "Object가 중복으로 보인다" 같은 상황을 즉시 해석할 수 있다.

---

## 41. 실습 10 — Agent 원격 설정 변경 (난이도: ★★★★★)

### 목표

Scouter Client에서 Agent 설정을 **원격으로 변경**하고, 변경 결과를 실시간으로 확인한다.

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

> Agent 원격 설정 변경은 **운영 환경에서 매우 유용**한 기능이다.
> 트래픽이 많을 때 샘플링을 켜서 Server 부하를 줄이고, 문제 분석 시 샘플링을 끄고 모든 요청을 추적하는 등,
> **서비스 재시작 없이** 유연하게 모니터링 전략을 조정할 수 있다.

---

## 42. 실습 11 — 과거 데이터 조회와 일간 분석 (난이도: ★★★☆☆)

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

> 과거 데이터 조회는 **사후 분석(Post-mortem Analysis)**의 핵심이다.
> "어제 오후 3시에 장애가 있었다"는 보고를 받았을 때, Load XLog로 해당 시간대를 로드하면
> 어떤 요청이 느렸는지, 에러가 있었는지를 그때의 데이터로 분석할 수 있다.

---

## 43. 실습 12 — 종합 장애 시뮬레이션과 진단 (난이도: ★★★★★)

### 목표

WAS 장애 상황을 시뮬레이션하고, Scouter로 장애를 감지 → 원인 분석 → 복구 확인하는 전체 사이클을 수행한다.

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

실습 후 아래 형식으로 정리해 본다:

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

> 이 실습은 **실제 운영 장애 대응 사이클**을 시뮬레이션한다:
> 1. 정상 Baseline 파악
> 2. 이상 징후 감지 (Object Dead, TPS 편중)
> 3. Thread Dump 등으로 원인 분석
> 4. 복구 조치
> 5. 복구 후 정상화 확인
>
> 이 프로세스를 몸에 익혀두면, 실제 장애 상황에서 당황하지 않고 체계적으로 대응할 수 있다.

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

---

## 마치며

이 문서를 끝까지 읽고 실습을 완료했다면, 당신은 다음을 할 수 있는 사람이 되었다:

1. **Scouter를 설치하고 운영할 수 있다** — Agent-Server-Client 구조를 이해하고 직접 배포할 수 있다.
2. **내부 동작을 설명할 수 있다** — "소스코드 수정 없이 어떻게 성능을 측정하나요?"라는 질문에 BCI, ASM, ThreadLocal까지 답할 수 있다.
3. **그래프를 읽고 진단할 수 있다** — XLog 패턴, TPS/Active Service 관계, GC-응답시간 상관관계를 보고 원인을 추론할 수 있다.
4. **장애를 체계적으로 대응할 수 있다** — 감지 → 진단 → 복구 → 확인의 사이클을 수행할 수 있다.
5. **Jennifer 기반 환경에 바로 적응할 수 있다** — 용어, 개념, 진단 흐름이 동일하므로 현업 투입이 가능한다.

APM 모니터링은 **이론만으로는 완성되지 않는 기술**이다. 부하를 주고, 그래프가 어떻게 반응하는지 관찰하고, 장애를 만들어 보고, 진단해 보는 경험을 반복할수록 실력이 쌓이다. 실습 과제를 가능한 한 모두 수행해 보시기 바랍니다.

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [모니터링 메트릭 가이드](monitoring-metrics.md) | Prometheus/Grafana 메트릭 가이드 |
| [성능 튜닝 가이드](performance-tuning.md) | JVM 및 애플리케이션 튜닝 |
| [장애 대응 매뉴얼](incident-response.md) | APM 기반 장애 대응 |
| [아키텍처 설계](architecture.md) | 전체 시스템 아키텍처 |
