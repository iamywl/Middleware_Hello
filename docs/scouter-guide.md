# Scouter APM 사용 가이드

> Scouter는 **Jennifer의 오픈소스 대안**으로, Java Agent 기반의 APM(Application Performance Monitoring) 도구입니다.
>
> 이 문서는 Scouter Client 설치부터 실제 모니터링 활용법까지 다룹니다.

---

## 목차

1. [Scouter 구성 요소 이해하기](#1-scouter-구성-요소-이해하기)
2. [Scouter Client 설치](#2-scouter-client-설치)
3. [Scouter Client 접속](#3-scouter-client-접속)
4. [대시보드 구성하기](#4-대시보드-구성하기)
5. [XLog로 트랜잭션 분석하기](#5-xlog로-트랜잭션-분석하기)
6. [TPS 모니터링](#6-tps-모니터링)
7. [JVM 힙 메모리 모니터링](#7-jvm-힙-메모리-모니터링)
8. [Active Service 모니터링](#8-active-service-모니터링)
9. [쓰레드 분석](#9-쓰레드-분석)
10. [부하 테스트와 함께 모니터링하기](#10-부하-테스트와-함께-모니터링하기)
11. [알림 설정](#11-알림-설정)
12. [트러블슈팅](#12-트러블슈팅)

---

## 1. Scouter 구성 요소 이해하기

Scouter는 3개의 구성 요소로 이루어져 있습니다:

```
[Tomcat #1] ──Agent──┐
                      ├──→ [Scouter Server:6100] ←──→ [Scouter Client (GUI)]
[Tomcat #2] ──Agent──┘         (수집·저장)              (시각화·분석)
```

| 구성 요소 | 역할 | 본 프로젝트에서의 위치 |
|-----------|------|----------------------|
| **Scouter Agent** | Tomcat(WAS)에 `-javaagent`로 부착, 성능 데이터 수집 | Docker: mw-tomcat1, mw-tomcat2 내부 |
| **Scouter Server** | Agent로부터 데이터를 수신·저장, 6100 포트로 서비스 | Docker: mw-scouter (6100 포트) |
| **Scouter Client** | Server에 접속하여 데이터를 시각화하는 GUI 도구 | **로컬 PC에 별도 설치 필요** |

---

## 2. Scouter Client 설치

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
# Intel Mac은 x86_64 버전 사용
curl -L -o /tmp/scouter-client-mac.tar.gz \
  https://github.com/scouter-project/scouter/releases/download/v2.21.3/scouter.client.product-macosx.cocoa.x86_64.tar.gz

# 이후 과정 동일
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

## 3. Scouter Client 접속

### 사전 조건

Docker 환경이 구동 중이어야 합니다:

```bash
# 프로젝트 디렉토리에서
docker-compose up -d

# Scouter Server가 구동 중인지 확인
docker logs mw-scouter 2>&1 | tail -5
# → "Started ServerConnector@...{HTTP/1.1}{0.0.0.0:6180}" 가 보이면 정상
```

### 접속 정보

Scouter Client 실행 후 아래 정보를 입력합니다:

| 항목 | 값 |
|------|------|
| **Server Address** | `127.0.0.1` |
| **Port** | `6100` |
| **ID** | `admin` |
| **Password** | `admin` |

### 접속 성공 확인

접속에 성공하면 좌측 **Object** 패널에 아래와 같이 표시됩니다:

```
▼ /middleware
   ├─ tomcat1    ← Tomcat #1 Agent
   └─ tomcat2    ← Tomcat #2 Agent
```

> Object가 보이지 않으면 Tomcat 컨테이너가 아직 기동 중이거나 Agent 설정에 문제가 있는 것입니다. [트러블슈팅](#12-트러블슈팅) 섹션을 참고하세요.

---

## 4. 대시보드 구성하기

Scouter Client에서 모니터링 차트를 열어 대시보드를 구성합니다.

### 추천 대시보드 레이아웃

좌측 Object 패널에서 `/middleware` 아래의 `tomcat1` 또는 `tomcat2`를 **우클릭**하면 다양한 차트를 열 수 있습니다.

처음 사용할 때 아래 4개를 열어두면 기본적인 모니터링이 가능합니다:

| 순서 | 메뉴 경로 | 차트 이름 | 용도 |
|------|-----------|-----------|------|
| 1 | 우클릭 → **XLog** | XLog (실시간) | 개별 트랜잭션 응답시간 분포 |
| 2 | 우클릭 → **Counter** → **TPS** | TPS | 초당 처리 건수 |
| 3 | 우클릭 → **Counter** → **Heap Used** | Heap Memory | JVM 힙 메모리 사용량 |
| 4 | 우클릭 → **Counter** → **Active Service** | Active Service | 현재 처리 중인 요청 수 |

> 차트 창을 드래그하여 위치를 조정하면 한 화면에서 4개를 동시에 모니터링할 수 있습니다.

---

## 5. XLog로 트랜잭션 분석하기

XLog는 Scouter의 **핵심 기능**으로, Jennifer의 XView와 동일한 개념입니다.

### XLog란?

- X축: 시간, Y축: 응답시간(ms)
- **점 하나 = HTTP 요청 하나**
- 점의 위치가 높을수록 응답이 느린 요청

### XLog 차트 열기

1. 좌측 Object에서 `tomcat1` 우클릭 → **XLog** 클릭
2. 실시간으로 점이 찍히는 차트가 열림

### XLog 읽는 법

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
| 점이 100ms 아래에 몰려 있음 | 정상 | - |
| 간헐적으로 높은 점 | 특정 요청이 느림 | 해당 점 클릭하여 상세 분석 |
| 전체적으로 점이 올라감 | 시스템 부하 | GC, DB 쿼리 확인 |
| 점이 일직선으로 올라감 | Timeout 발생 | 네트워크/DB 연결 확인 |

### XLog 점 클릭 → 상세 분석

XLog에서 점을 클릭하면 해당 요청의 상세 정보를 확인할 수 있습니다:

- **URL**: 요청 경로 (예: `/health`, `/api/info`)
- **응답시간**: 전체 처리 시간(ms)
- **SQL 쿼리**: 실행된 SQL문과 소요 시간
- **API Call**: 외부 서비스 호출 내역
- **CPU Time**: CPU 사용 시간
- **Parameter**: 요청 파라미터

> 이것이 APM의 핵심입니다. 느린 요청의 원인이 **SQL인지, 외부 API인지, GC인지** 추적할 수 있습니다.

---

## 6. TPS 모니터링

### TPS(Transaction Per Second)란?

- 초당 처리되는 트랜잭션(HTTP 요청) 수
- 시스템의 **처리 용량**을 나타내는 핵심 지표

### TPS 차트 열기

1. Object에서 `tomcat1` 우클릭 → **Counter** → **TPS**
2. (선택) `tomcat2`도 같은 방식으로 열면 2대의 TPS를 비교 가능

### TPS 해석

| TPS 값 | 의미 |
|---------|------|
| 0 | 요청이 없음 |
| 1~10 | 가벼운 트래픽 |
| 50~100 | 보통 수준 |
| 100+ | 높은 트래픽 |

### 부하를 줘서 TPS 변화 확인하기

```bash
# 터미널에서 반복 요청 (100회)
for i in $(seq 1 100); do curl -sk https://localhost/health > /dev/null; done
```

실행하면 TPS 차트가 **0 → 상승 → 0**으로 변화하는 것을 확인할 수 있습니다.

---

## 7. JVM 힙 메모리 모니터링

### 힙 메모리란?

- Java 애플리케이션이 객체를 저장하는 메모리 영역
- 메모리가 가득 차면 **GC(Garbage Collection)**가 실행되어 사용하지 않는 객체를 정리
- GC 실행 중에는 애플리케이션이 잠시 멈춤 → **응답 지연 발생 가능**

### Heap Memory 차트 열기

1. Object에서 `tomcat1` 우클릭 → **Counter** → **Heap Used**
2. 그래프에서 메모리 사용량 추이를 관찰

### 힙 메모리 패턴 읽기

```
메모리(MB)
  512 |─────────────────── Max Heap
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
| Max에 가깝게 유지 | 메모리 부족 | JVM 힙 크기 증가 필요 |

---

## 8. Active Service 모니터링

### Active Service란?

- **현재 처리 중인 요청 수** (아직 응답이 완료되지 않은 요청)
- 이 숫자가 높으면 서버가 요청을 소화하지 못하고 있다는 의미

### Active Service 차트 열기

1. Object에서 `tomcat1` 우클릭 → **Counter** → **Active Service**

### Active Service 해석

| 값 | 의미 |
|----|------|
| 0 | 처리 중인 요청 없음 (유휴 상태) |
| 1~5 | 정상 |
| 10+ | 부하가 걸리고 있음 |
| 50+ | **심각한 병목** - 즉시 원인 분석 필요 |

---

## 9. 쓰레드 분석

### Thread List 보기

1. Object에서 `tomcat1` 우클릭 → **Thread List / Thread Dump**
2. 현재 실행 중인 모든 쓰레드의 상태를 확인할 수 있습니다

### 쓰레드 상태

| 상태 | 의미 |
|------|------|
| **RUNNABLE** | 실행 중 |
| **WAITING** | 다른 쓰레드의 알림을 대기 중 |
| **TIMED_WAITING** | 타임아웃이 있는 대기 |
| **BLOCKED** | 락(Lock) 획득 대기 중 ← **병목 원인** |

> BLOCKED 상태의 쓰레드가 많으면 **데드락** 또는 **DB 커넥션 풀 고갈**을 의심해야 합니다.

---

## 10. 부하 테스트와 함께 모니터링하기

Scouter의 진가는 **부하 상황에서의 실시간 모니터링**입니다.

### 테스트 시나리오

#### 시나리오 1: 정상 트래픽

```bash
# 1초 간격으로 60회 요청
for i in $(seq 1 60); do
  curl -sk https://localhost/health > /dev/null
  sleep 1
done
```

**Scouter에서 확인**: XLog에 100ms 이하의 점이 1초 간격으로 찍힘, TPS = 약 1

#### 시나리오 2: 순간 부하

```bash
# 동시에 대량 요청 (500회를 10개씩 병렬)
for i in $(seq 1 50); do
  for j in $(seq 1 10); do
    curl -sk https://localhost/ > /dev/null &
  done
  wait
done
```

**Scouter에서 확인**:
- TPS가 급격히 상승
- Active Service 수가 증가
- XLog에서 응답시간이 높은 점들이 나타남
- Heap Memory가 빠르게 상승 후 GC 발생

#### 시나리오 3: WAS 장애 시 변화

```bash
# Tomcat #2 중지
docker stop mw-tomcat2

# 요청 계속 보내기
for i in $(seq 1 30); do curl -sk https://localhost/health > /dev/null; sleep 1; done

# 복구
docker start mw-tomcat2
```

**Scouter에서 확인**: tomcat2 Object가 회색(비활성)으로 변경, tomcat1만 TPS 발생

---

## 11. 알림 설정

Scouter Server는 기본적으로 아래 상황에서 알림을 발생시킵니다:

| 알림 조건 | 기본값 |
|-----------|--------|
| 응답시간 초과 | 8000ms 이상 |
| GC Time 초과 | 설정값 이상 |
| CPU 사용률 | 80% 이상 |

알림은 Scouter Client의 **Alert** 패널에서 확인할 수 있습니다.

---

## 12. 트러블슈팅

### Scouter Client 실행 시 "손상된 앱" 오류 (macOS)

```bash
# 보안 속성 제거
xattr -cr ~/Applications/Scouter/scouter.client.app
```

### Client에서 Object가 보이지 않음

```bash
# 1. Scouter Server 구동 확인
docker logs mw-scouter 2>&1 | grep "6100\|6180"

# 2. Tomcat에서 Agent 연결 확인
docker logs mw-tomcat1 2>&1 | grep -i scouter
docker logs mw-tomcat2 2>&1 | grep -i scouter

# 3. 포트 접근 확인
nc -z localhost 6100 && echo "OK" || echo "FAIL"
```

### Client 접속이 안 됨

| 원인 | 해결 |
|------|------|
| Docker가 실행 중이 아님 | `docker-compose up -d` |
| 6100 포트가 사용 중 | `lsof -i :6100`으로 확인 |
| 방화벽 차단 | macOS 방화벽 설정 확인 |

### XLog에 점이 찍히지 않음

트래픽이 없으면 점이 찍히지 않습니다. 아래 명령으로 요청을 보내보세요:

```bash
curl -sk https://localhost/health
```

실행 직후 XLog에 점이 나타나야 정상입니다.

---

## Jennifer와의 비교 참고

| 기능 | Jennifer | Scouter (본 프로젝트) |
|------|----------|----------------------|
| XView/XLog | XView | XLog (동일 개념) |
| TPS | TPS 차트 | TPS Counter (동일) |
| Active Service | Active Service EQ | Active Service (동일) |
| Heap/GC | Heap Memory | Heap Used (동일) |
| Thread Dump | Thread Dump | Thread List/Dump (동일) |
| SQL Trace | SQL 추적 | SQL Trace (동일) |
| 설치 방식 | Agent + Server + Viewer | Agent + Server + Client (동일 구조) |

> Scouter를 사용한 경험은 Jennifer 기반 모니터링 업무에 그대로 적용할 수 있습니다.
