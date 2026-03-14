# 성능 튜닝 가이드

> 본 문서는 Nginx + Tomcat(x2) + MySQL + Scouter APM + Prometheus + Grafana + Keycloak 기반 미들웨어 스택의 성능 튜닝을 다룬다.
> 각 컴포넌트별로 **WHY**(왜 중요한지), **HOW**(구체적 설정), **VERIFY**(검증 방법), **EXAMPLE**(실제 예시)를 포함한다.
>
> 대상 독자: 경력 3년차 이상 엔지니어

---

## 목차

1. [Nginx 튜닝](#1-nginx-튜닝)
2. [Tomcat/JVM 튜닝](#2-tomcatjvm-튜닝)
3. [MySQL 튜닝](#3-mysql-튜닝)
4. [Docker 리소스 제한](#4-docker-리소스-제한)
5. [성능 측정 방법](#5-성능-측정-방법)
6. [튜닝 체크리스트](#6-튜닝-체크리스트)

---

## 1. Nginx 튜닝

### 1.1 worker_processes / worker_connections

**WHY:** Nginx는 이벤트 기반 비동기 아키텍처이다. `worker_processes`는 요청을 처리하는 프로세스 수이고, `worker_connections`는 각 워커가 동시에 처리할 수 있는 연결 수다. 이 두 값의 곱이 동시 처리 가능한 최대 연결 수를 결정한다.

**HOW:**

- **worker_processes**: CPU 코어 수와 동일하게 설정하거나 `auto`로 자동 감지한다.
- **worker_connections**: 공식 = `(예상 동시 접속자 수) / worker_processes`이다. 리버스 프록시 환경에서는 클라이언트 연결 + 업스트림 연결이 모두 필요하므로, 실질적 동시 처리 가능 클라이언트 수는 `worker_processes * worker_connections / 2`이다.

```
# 최대 동시 연결 수 계산 (리버스 프록시 환경)
최대_클라이언트_수 = worker_processes * worker_connections / 2

# 예시: 4코어, worker_connections=2048
최대_클라이언트_수 = 4 * 2048 / 2 = 4096 동시 접속
```

**설정 파일:** `configs/nginx/nginx.conf`

```nginx
# CPU 코어 수 확인 후 설정 (컨테이너 내부)
# docker exec mw-nginx nproc
# 결과가 4이면 worker_processes 4; 또는 auto 사용

user  nginx;
worker_processes  auto;  # CPU 코어 수 자동 감지 (권장)

# 파일 디스크립터 한도 - worker_connections보다 커야 함
worker_rlimit_nofile 8192;

events {
    worker_connections  2048;    # 기본값 1024에서 상향
    multi_accept on;             # 한 번에 여러 연결을 accept
    use epoll;                   # Linux 환경에서 epoll 사용 (성능 최적)
}
```

**VERIFY:**

```bash
# 현재 워커 프로세스 수 확인
docker exec mw-nginx ps aux | grep nginx

# Nginx 설정 문법 검증
docker exec mw-nginx nginx -t

# 현재 연결 상태 확인
docker exec mw-nginx nginx -T | grep worker
```

---

### 1.2 keepalive_timeout / keepalive_requests

**WHY:** HTTP keepalive는 TCP 연결을 재사용하여 핸드셰이크 오버헤드를 줄인다. 값이 너무 크면 유휴 연결이 워커 리소스를 점유하고, 너무 작으면 연결 수립 비용이 증가한다.

**HOW:**

| 설정 | 설명 | 권장값 |
|------|------|--------|
| `keepalive_timeout` | 유휴 연결 유지 시간 (초) | 30~65초 |
| `keepalive_requests` | 하나의 keepalive 연결에서 처리할 최대 요청 수 | 100~1000 |

**EXAMPLE:**

```nginx
http {
    # 클라이언트 -> Nginx 간 keepalive
    keepalive_timeout  30;        # 현재 65 -> 30으로 줄여 리소스 회수 가속
    keepalive_requests 1000;      # 하나의 연결에서 1000개 요청까지 처리

    # Nginx -> 업스트림(Tomcat) 간 keepalive
    upstream was_backend {
        server tomcat1:8080 weight=1;
        server tomcat2:8080 weight=1;
        keepalive 32;             # 업스트림에 유지할 idle 커넥션 풀 크기
    }
}
```

업스트림 keepalive를 사용하려면 proxy 설정에 아래를 추가해야 한다.

```nginx
location / {
    proxy_pass http://was_backend;
    proxy_http_version 1.1;                    # keepalive는 HTTP/1.1 필수
    proxy_set_header Connection "";             # "close" 제거하여 keepalive 유지
}
```

**VERIFY:**

```bash
# keepalive 연결 수 모니터링
docker exec mw-nginx curl -s http://localhost/stub_status
# 출력 예시:
# Active connections: 5
# server accepts handled requests
#  1234 1234 5678
# Reading: 0 Writing: 1 Waiting: 4   <-- Waiting = keepalive 유휴 연결
```

---

### 1.3 proxy_buffer_size / proxy_buffers

**WHY:** Nginx가 업스트림(Tomcat)으로부터 응답을 받을 때 버퍼에 저장한다. 버퍼가 너무 작으면 임시 파일에 쓰게 되어 디스크 I/O가 발생하고, 너무 크면 메모리를 낭비한다.

**HOW:**

- `proxy_buffer_size`: 응답 헤더를 저장하는 버퍼 크기. 보통 4k~8k면 충분하지만, 헤더에 대형 쿠키나 토큰(Keycloak JWT 등)이 포함되면 16k 이상 필요하다.
- `proxy_buffers`: 응답 본문을 저장하는 버퍼의 개수와 크기.
- `proxy_busy_buffers_size`: 클라이언트에게 전송 중인 버퍼의 최대 크기.

**EXAMPLE:**

```nginx
# 설정 파일: configs/nginx/conf.d/default.conf
location / {
    proxy_pass http://was_backend;

    # 응답 헤더 버퍼 (Keycloak JWT 토큰이 크므로 16k 권장)
    proxy_buffer_size          16k;

    # 응답 본문 버퍼: 4개 x 32k = 128k
    proxy_buffers              4 32k;

    # 전송 중 사용 가능한 최대 버퍼
    proxy_busy_buffers_size    64k;

    # 임시 파일 쓰기 방지 (버퍼로만 처리)
    # 주의: 대용량 응답이 있으면 이 설정은 제거
    # proxy_max_temp_file_size 0;
}
```

**VERIFY:**

```bash
# 에러 로그에서 버퍼 부족 경고 확인
docker exec mw-nginx cat /var/log/nginx/error.log | grep "upstream sent too big header"

# 버퍼 부족 시 아래와 같은 로그가 나타남:
# upstream sent too big header while reading response header from upstream
```

---

### 1.4 gzip 압축

**WHY:** gzip 압축으로 전송 데이터 크기를 60~80% 줄일 수 있다. 네트워크 대역폭을 절약하고 응답 시간을 단축한다. 단, CPU를 사용하므로 이미 압축된 파일(이미지, 동영상)에는 적용하지 않는다.

**HOW:**

| 설정 | 설명 | 권장값 |
|------|------|--------|
| `gzip` | 활성화 여부 | on |
| `gzip_min_length` | 압축 최소 크기 (이보다 작으면 압축 안 함) | 1000 (1KB) |
| `gzip_comp_level` | 압축 수준 (1=빠름/낮은압축, 9=느림/높은압축) | 4~6 |
| `gzip_types` | 압축 대상 MIME 타입 | text/*, application/json 등 |
| `gzip_vary` | Vary: Accept-Encoding 헤더 추가 | on |

**EXAMPLE:**

```nginx
# 설정 파일: configs/nginx/nginx.conf (http 블록 내)
http {
    gzip  on;
    gzip_min_length  1000;            # 1KB 미만은 압축 효과 미미
    gzip_comp_level  5;               # CPU vs 압축률 균형점
    gzip_vary on;                     # 프록시 캐시 호환성
    gzip_proxied any;                 # 프록시 응답도 압축

    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml
        application/xml+rss
        application/x-javascript
        image/svg+xml;

    # 이미 압축된 파일은 제외 (이미지, 동영상, 압축파일)
    # gzip_types에 image/png, image/jpeg 등을 넣지 않으면 자동 제외
}
```

**VERIFY:**

```bash
# gzip 압축 확인 (Content-Encoding: gzip 헤더 존재 여부)
curl -H "Accept-Encoding: gzip" -I https://localhost/api/health -k

# 압축 전후 크기 비교
curl -so /dev/null -w "압축 없이: %{size_download} bytes\n" https://localhost/api/data -k
curl -so /dev/null -w "압축 적용: %{size_download} bytes\n" -H "Accept-Encoding: gzip" https://localhost/api/data -k
```

---

### 1.5 Rate Limiting

**WHY:** DDoS 공격이나 과도한 API 호출로부터 업스트림 서버를 보호한다. Rate Limiting 없이 운영하면 한 클라이언트가 전체 시스템 리소스를 소진할 수 있다.

**HOW:**

- `limit_req_zone`: 요청 빈도를 추적하는 공유 메모리 영역을 정의한다.
- `limit_req`: 특정 location에 적용한다.
- `burst`: 허용할 버스트(돌발 요청) 수.
- `nodelay`: burst 요청을 지연 없이 처리.

**EXAMPLE:**

```nginx
# 설정 파일: configs/nginx/nginx.conf (http 블록 내)
http {
    # 클라이언트 IP 기준, 10MB 공유 메모리, 초당 10개 요청 허용
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

    # 로그인 엔드포인트는 더 엄격하게 (brute-force 방지)
    limit_req_zone $binary_remote_addr zone=login_limit:10m rate=3r/s;
}

# 설정 파일: configs/nginx/conf.d/default.conf
server {
    # 일반 API
    location / {
        limit_req zone=api_limit burst=20 nodelay;
        limit_req_status 429;          # 초과 시 429 Too Many Requests 반환

        proxy_pass http://was_backend;
    }

    # 로그인 엔드포인트 (강화된 제한)
    location /auth/login {
        limit_req zone=login_limit burst=5 nodelay;
        limit_req_status 429;

        proxy_pass http://was_backend;
    }
}
```

**VERIFY:**

```bash
# rate limit 테스트 (빠르게 20회 요청)
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code}\n" https://localhost/ -k
done
# 429 응답이 나오면 rate limit 정상 동작

# 제한된 요청 로그 확인
docker exec mw-nginx grep "limiting requests" /var/log/nginx/error.log
```

---

### 1.6 Nginx 튜닝 종합 설정 예시

아래는 현재 프로젝트의 `configs/nginx/nginx.conf`에 적용할 수 있는 튜닝 완료 설정이다.

```nginx
user  nginx;
worker_processes  auto;
worker_rlimit_nofile 8192;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  2048;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # 로그 포맷 (응답 시간 포함)
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for" '
                      'upstream=$upstream_addr rt=$upstream_response_time';

    access_log  /var/log/nginx/access.log  main;

    # 커널 레벨 파일 전송 최적화
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;

    # keepalive 설정
    keepalive_timeout  30;
    keepalive_requests 1000;

    # 해시 테이블 최적화
    types_hash_max_size 2048;

    # gzip 압축
    gzip  on;
    gzip_min_length  1000;
    gzip_comp_level  5;
    gzip_vary on;
    gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml image/svg+xml;

    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login_limit:10m rate=3r/s;

    include /etc/nginx/conf.d/*.conf;
}
```

---

## 2. Tomcat/JVM 튜닝

### 2.1 Connector 설정 (maxThreads / minSpareThreads / acceptCount)

**WHY:** Tomcat은 요청 하나당 스레드 하나를 할당한다(BIO/NIO 모두 스레드 풀 기반). 스레드 풀 설정이 잘못되면 요청 거부(503) 또는 메모리 낭비가 발생한다.

| 설정 | 의미 | 현재값 | 권장값 |
|------|------|--------|--------|
| `maxThreads` | 동시 처리 가능한 최대 스레드 수 | 200 | 200~400 |
| `minSpareThreads` | 항상 대기 중인 최소 스레드 수 | 10 | 25~50 |
| `acceptCount` | maxThreads가 모두 사용 중일 때 대기열 크기 | 100 | 100~200 |
| `maxConnections` | NIO 기반 최대 연결 수 | 8192 | 8192~10000 |
| `connectionTimeout` | 연결 수립 후 요청 대기 시간 (ms) | 20000 | 10000~20000 |

**계산 기준:**

```
# 필요한 maxThreads 계산
maxThreads = 예상_동시_요청수 * 평균_응답_시간(초) * 1.5(여유분)

# 예시: 동시 100명, 평균 응답 0.5초
maxThreads = 100 * 0.5 * 1.5 = 75 → 최소 100으로 설정

# acceptCount는 maxThreads의 50~100%
acceptCount = maxThreads * 0.5 ~ 1.0
```

**EXAMPLE:**

```xml
<!-- 설정 파일: configs/tomcat/tomcat1/server.xml (tomcat2도 동일) -->
<Connector port="8080" protocol="HTTP/1.1"
           connectionTimeout="15000"
           redirectPort="8443"
           maxThreads="200"
           minSpareThreads="25"
           acceptCount="150"
           maxConnections="8192"
           enableLookups="false"
           compression="off"
           URIEncoding="UTF-8" />

<!--
  enableLookups="false" : DNS 역방향 조회 비활성화 (성능 향상)
  compression="off"     : Nginx에서 gzip 처리하므로 Tomcat에서는 비활성화 (이중 압축 방지)
-->
```

**VERIFY:**

```bash
# Tomcat 스레드 풀 상태 확인 (JMX 또는 Scouter에서 모니터링)
# manager 앱이 배포되어 있다면:
docker exec mw-tomcat1 curl -s http://localhost:8080/manager/jmxproxy?get=Catalina:type=ThreadPool,name=%22http-nio-8080%22\&att=currentThreadCount

# 또는 jstack으로 현재 스레드 상태 확인
docker exec mw-tomcat1 jstack $(docker exec mw-tomcat1 pgrep java) | grep -c "http-nio-8080-exec"
```

---

### 2.2 JVM 힙 메모리 설정

**WHY:** JVM 힙이 너무 작으면 OutOfMemoryError가 발생하고, 너무 크면 GC pause time이 길어진다. 컨테이너 환경에서는 Docker의 메모리 제한과 JVM 힙의 관계를 반드시 이해해야 한다.

**HOW:**

```
# JVM 메모리 구조
전체 JVM 메모리 = Heap + Metaspace + Thread Stack + Native Memory + GC Overhead

# 공식: 컨테이너 메모리 제한의 50~75%를 힙으로 할당
# 나머지 25~50%는 Metaspace, 스레드 스택, 네이티브 메모리에 필요

# 예시: 컨테이너 mem_limit=1g
-Xms512m   # 초기 힙 (시작과 동시에 확보, GC 빈도 감소)
-Xmx768m   # 최대 힙 (컨테이너 메모리의 75%)
-Xss512k   # 스레드 스택 크기 (기본 1m → 512k로 줄이면 스레드당 메모리 절약)
```

**주요 파라미터 설명:**

| 옵션 | 설명 | 현재값 | 권장값 (컨테이너 1GB 기준) |
|------|------|--------|---------------------------|
| `-Xms` | 초기 힙 크기 | 256m | 512m |
| `-Xmx` | 최대 힙 크기 | 512m | 768m |
| `-Xss` | 스레드 스택 크기 | 기본(1m) | 512k |
| `-XX:MetaspaceSize` | 초기 Metaspace | 기본 | 128m |
| `-XX:MaxMetaspaceSize` | 최대 Metaspace | 무제한 | 256m |

**중요:** `-Xms`와 `-Xmx`를 동일하게 설정하면 힙 리사이징에 따른 GC 부담을 줄일 수 있다. 운영 환경에서는 동일 값을 권장한다.

---

### 2.3 GC 알고리즘 선택

**WHY:** GC 알고리즘에 따라 응답 시간(latency)과 처리량(throughput)의 트레이드오프가 달라진다. 서비스 특성에 맞는 GC를 선택해야 한다.

#### GC 알고리즘 비교

| GC | 힙 크기 | 특징 | 적합한 경우 |
|----|---------|------|------------|
| **Serial GC** | ~수백 MB | 단일 스레드 GC, STW(Stop-The-World) 김 | 테스트/개발 환경, 소규모 앱 |
| **Parallel GC** | 1~4 GB | 멀티스레드 GC, 높은 처리량 | 배치 처리, 처리량 우선 |
| **G1 GC** | 4~16 GB | Region 기반, STW 예측 가능 | 웹 서비스 (Java 9+ 기본) |
| **ZGC** | 8 GB~ | 초저지연 (STW < 10ms), 멀티스레드 | 대규모 힙, 지연 민감 서비스 |

#### 각 GC별 JVM 옵션

```bash
# Serial GC (개발 환경용)
-XX:+UseSerialGC

# Parallel GC (배치 처리용, 처리량 최대화)
-XX:+UseParallelGC
-XX:ParallelGCThreads=4         # GC 스레드 수 (CPU 코어 수)
-XX:MaxGCPauseMillis=200        # 목표 GC 일시정지 시간

# G1 GC (웹 서비스 권장, Java 9+ 기본값)
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200        # 목표 GC 일시정지 시간 (200ms)
-XX:G1HeapRegionSize=4m         # Region 크기 (힙/2048 ~ 힙/1)
-XX:InitiatingHeapOccupancyPercent=45  # Mixed GC 시작 임계값

# ZGC (Java 15+, 초저지연 필요 시)
-XX:+UseZGC
-XX:+ZGenerational               # Java 21+: Generational ZGC (더 효율적)
```

**이 프로젝트에서의 권장:** 웹 서비스 특성과 힙 크기(512m~768m)를 고려하면 **G1 GC**가 적합하다.

---

### 2.4 GC 로그 활성화 및 분석

**WHY:** GC 로그 없이는 메모리 문제를 사후에 분석할 수 없다. GC 빈도, pause time, 메모리 사용 패턴을 파악하여 튜닝 근거를 마련한다.

**EXAMPLE:**

```bash
# Java 11+ GC 로그 옵션 (Unified Logging)
-Xlog:gc*:file=/usr/local/tomcat/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10m

# 구성 요소 설명:
# gc*              : 모든 GC 관련 로그
# file=...         : 로그 파일 경로
# time,uptime,...  : 타임스탬프, 가동시간, 로그레벨, 태그 포함
# filecount=5      : 최대 5개 파일 로테이션
# filesize=10m     : 파일당 10MB
```

**GC 로그 분석 방법:**

```bash
# 컨테이너에서 GC 로그 추출
docker cp mw-tomcat1:/usr/local/tomcat/logs/gc.log ./gc-tomcat1.log

# Full GC 발생 횟수 확인
grep "Full GC\|Pause Full" gc-tomcat1.log | wc -l

# GC pause time 추출 (단위: ms)
grep "pause" gc-tomcat1.log | awk '{print $NF}'

# 온라인 분석 도구: https://gceasy.io 에 GC 로그 업로드
```

**Scouter APM과 연동:** Scouter에서 실시간 GC 모니터링이 가능하다. Scouter Client에서 `Object > GC Count`, `GC Time` 차트를 확인한다.

---

### 2.5 JVM 옵션 전체 예시

현재 프로젝트의 `docker-compose.yml`에서 Tomcat의 JAVA_OPTS를 아래와 같이 변경한다.

```yaml
# docker-compose.yml 내 tomcat1 서비스
tomcat1:
  environment:
    JAVA_OPTS: >-
      -Xms512m -Xmx768m
      -Xss512k
      -XX:MetaspaceSize=128m
      -XX:MaxMetaspaceSize=256m
      -XX:+UseG1GC
      -XX:MaxGCPauseMillis=200
      -XX:G1HeapRegionSize=4m
      -XX:InitiatingHeapOccupancyPercent=45
      -XX:+HeapDumpOnOutOfMemoryError
      -XX:HeapDumpPath=/usr/local/tomcat/logs/heapdump.hprof
      -Xlog:gc*:file=/usr/local/tomcat/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10m
      -DjvmRoute=tomcat1
      -Dserver.port=8080
      -javaagent:/opt/scouter/agent.java/scouter.agent.jar
      -Dscouter.config=/opt/scouter-conf/agent.conf
      -Dobj_name=tomcat1
```

각 옵션의 역할:

| 옵션 | 역할 |
|------|------|
| `-XX:+HeapDumpOnOutOfMemoryError` | OOM 발생 시 힙 덤프 자동 생성 (장애 분석 필수) |
| `-XX:HeapDumpPath=...` | 힙 덤프 저장 경로 |
| `-Xlog:gc*:...` | GC 로그 활성화 |
| `-XX:InitiatingHeapOccupancyPercent=45` | 힙 사용률 45% 넘으면 Concurrent GC 시작 |

---

### 2.6 Thread Pool 모니터링

**WHY:** 스레드 풀이 고갈되면 신규 요청이 acceptCount 큐에 쌓이고, 큐마저 가득 차면 Connection Refused가 발생한다. 실시간 모니터링으로 병목을 조기에 감지해야 한다.

**HOW:**

```bash
# 방법 1: jstack으로 스레드 덤프 (즉시 상태 확인)
docker exec mw-tomcat1 jstack $(docker exec mw-tomcat1 pgrep java) > thread-dump.txt

# 스레드 상태별 카운트
grep "java.lang.Thread.State" thread-dump.txt | sort | uniq -c | sort -rn
# 예시 출력:
#   150 java.lang.Thread.State: WAITING (parking)
#    30 java.lang.Thread.State: RUNNABLE
#    20 java.lang.Thread.State: TIMED_WAITING (sleeping)

# 방법 2: Scouter APM에서 모니터링
# Scouter Client > Host > Thread Pool 차트
# - Active Thread Count: 현재 활성 스레드 (높으면 부하 증가)
# - Active Service: 진행 중인 서비스 수

# 방법 3: Prometheus + JMX Exporter (선택사항)
# JMX Exporter를 추가하면 Grafana에서 스레드 풀 대시보드 구성 가능
```

**경고 기준:**

| 지표 | 정상 | 주의 | 위험 |
|------|------|------|------|
| Active Thread / maxThreads | < 50% | 50~80% | > 80% |
| acceptCount 큐 사용량 | < 30% | 30~70% | > 70% |

---

## 3. MySQL 튜닝

### 3.1 innodb_buffer_pool_size

**WHY:** InnoDB Buffer Pool은 MySQL 성능의 핵심이다. 테이블 데이터와 인덱스를 메모리에 캐싱하여 디스크 I/O를 줄인다. 이 값 하나가 MySQL 성능의 70%를 결정한다고 해도 과언이 아니다.

**HOW:**

```
# 계산 공식
innodb_buffer_pool_size = 시스템_가용_메모리 * 0.70 ~ 0.80

# Docker 환경에서:
# 컨테이너 mem_limit=2g인 경우
# OS + MySQL 기타 = ~500MB 필요
# innodb_buffer_pool_size = 2GB * 0.70 = 약 1.4GB → 1G로 보수적 설정

# 현재 버퍼풀 적중률 확인 (99% 이상이어야 정상)
SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';   -- 메모리 히트
SHOW STATUS LIKE 'Innodb_buffer_pool_reads';            -- 디스크 읽기

# 적중률 계산:
# hit_rate = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests) * 100
```

**VERIFY:**

```bash
# 컨테이너 내부에서 확인
docker exec -it mw-mysql mysql -uroot -proot_password -e "
  SELECT
    FORMAT((A.num - B.num) * 100.0 / A.num, 2) AS buffer_pool_hit_rate
  FROM
    (SELECT variable_value num FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_read_requests') A,
    (SELECT variable_value num FROM performance_schema.global_status
     WHERE variable_name = 'Innodb_buffer_pool_reads') B;
"
```

---

### 3.2 innodb_log_file_size / innodb_flush_log_at_trx_commit

**WHY:**

- `innodb_log_file_size`: Redo 로그 크기. 너무 작으면 체크포인트가 빈번해져 디스크 쓰기가 증가하고, 너무 크면 복구 시간이 길어진다.
- `innodb_flush_log_at_trx_commit`: 트랜잭션 커밋 시 로그를 디스크에 쓰는 빈도. 데이터 안정성과 성능의 트레이드오프이다.

| 값 | 동작 | 성능 | 안정성 |
|----|------|------|--------|
| `1` (기본) | 매 커밋마다 디스크 flush | 낮음 | 최고 (데이터 손실 없음) |
| `2` | 매 커밋마다 OS 버퍼에 쓰기, 1초마다 flush | 중간 | 중간 (OS 크래시 시 최대 1초 손실) |
| `0` | 1초마다 로그 쓰기 + flush | 높음 | 낮음 (최대 1초 데이터 손실) |

**운영 환경 권장:** `1` (데이터 무결성 최우선)
**개발/테스트 환경:** `2` (적절한 타협점)

---

### 3.3 max_connections / wait_timeout

**WHY:** `max_connections`는 동시 연결 가능한 최대 커넥션 수다. 부족하면 "Too many connections" 에러가 발생하고, 과도하면 메모리를 낭비한다. `wait_timeout`은 유휴 연결을 자동으로 끊는 시간이다.

```
# max_connections 계산
# Tomcat 2대 x maxThreads(200) = 400 + 관리자 연결 여유분 = 420
# 커넥션풀 사용 시: Tomcat 2대 x pool_size(50) = 100 + 여유분 = 120

# 커넥션 하나당 메모리 소비 (약 ~10MB)
# max_connections * 10MB < 가용 메모리
```

---

### 3.4 Slow Query Log

**WHY:** 느린 쿼리를 식별하지 않으면 어떤 쿼리가 병목인지 알 수 없다. Slow Query Log는 성능 튜닝의 출발점이다.

**HOW:**

```sql
-- 활성화 (런타임)
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;          -- 1초 이상 걸리는 쿼리 기록
SET GLOBAL log_queries_not_using_indexes = 'ON';  -- 인덱스 미사용 쿼리도 기록
SET GLOBAL slow_query_log_file = '/var/log/mysql/slow.log';
```

**VERIFY:**

```bash
# slow query 로그 확인
docker exec mw-mysql cat /var/log/mysql/slow.log

# mysqldumpslow로 요약 분석 (가장 느린 쿼리 Top 10)
docker exec mw-mysql mysqldumpslow -s t -t 10 /var/log/mysql/slow.log

# 출력 예시:
# Count: 50  Time=2.50s (125s)  Lock=0.00s (0s)  Rows=1000.0 (50000)
#   SELECT * FROM orders WHERE status = 'S' ORDER BY created_at DESC LIMIT N
```

---

### 3.5 EXPLAIN으로 쿼리 실행 계획 분석

**WHY:** 쿼리가 느린 원인을 파악하려면 MySQL이 쿼리를 어떻게 실행하는지 알아야 한다. EXPLAIN은 쿼리 실행 계획을 보여주는 필수 도구이다.

**HOW:**

```sql
-- 기본 사용법
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 'ACTIVE';

-- JSON 형식 (더 상세한 정보)
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE user_id = 100;

-- ANALYZE 키워드 (실제 실행 후 통계 포함, MySQL 8.0.18+)
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 100;
```

**EXPLAIN 결과 핵심 컬럼 해석:**

| 컬럼 | 좋은 값 | 나쁜 값 | 설명 |
|------|---------|---------|------|
| `type` | `eq_ref`, `ref`, `range` | `ALL` (풀 테이블 스캔) | 접근 방식 |
| `key` | 인덱스 이름 | `NULL` | 사용된 인덱스 |
| `rows` | 작을수록 좋음 | 테이블 전체 행 수 | 예상 스캔 행 수 |
| `Extra` | `Using index` | `Using filesort`, `Using temporary` | 추가 정보 |

```sql
-- 나쁜 예시 (type=ALL, 풀 스캔)
EXPLAIN SELECT * FROM orders WHERE DATE(created_at) = '2024-01-01';
-- 함수 적용하면 인덱스 사용 불가!

-- 좋은 예시 (type=range, 인덱스 사용)
EXPLAIN SELECT * FROM orders
WHERE created_at >= '2024-01-01' AND created_at < '2024-01-02';
```

---

### 3.6 인덱스 설계 원칙

**WHY:** 적절한 인덱스는 쿼리 성능을 수십~수백 배 개선한다. 반면 불필요한 인덱스는 INSERT/UPDATE 성능을 저하시킨다.

#### B-Tree 인덱스 (기본)

```sql
-- 단일 컬럼 인덱스
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- WHERE 조건에 자주 사용되는 컬럼에 생성
-- 카디널리티(고유값 비율)가 높은 컬럼이 효과적
-- 성별(M/F) 같은 낮은 카디널리티 → 인덱스 효과 없음
```

#### 복합 인덱스 (Composite Index)

```sql
-- 복합 인덱스 순서가 핵심!
-- 규칙: WHERE절에서 "=" 조건 컬럼을 앞에, 범위 조건 컬럼을 뒤에 배치

-- 쿼리: SELECT * FROM orders WHERE user_id = 100 AND status = 'ACTIVE' ORDER BY created_at DESC

-- 좋은 인덱스 (최좌측 접두어 원칙 만족)
CREATE INDEX idx_orders_composite ON orders(user_id, status, created_at);

-- 나쁜 인덱스 (순서가 잘못됨)
CREATE INDEX idx_orders_bad ON orders(created_at, status, user_id);
-- user_id 단독 검색 시 이 인덱스를 사용할 수 없음
```

#### 커버링 인덱스 (Covering Index)

```sql
-- 인덱스만으로 쿼리를 처리 (테이블 접근 없음 = 가장 빠름)
-- EXPLAIN에서 Extra: "Using index"로 확인

-- 쿼리: SELECT user_id, status, created_at FROM orders WHERE user_id = 100
-- 인덱스에 필요한 모든 컬럼이 포함되어 있으면 커버링 인덱스
CREATE INDEX idx_covering ON orders(user_id, status, created_at);
```

#### 인덱스 설계 체크리스트

1. WHERE 절에 자주 사용되는 컬럼에 인덱스를 생성한다
2. JOIN 조건 컬럼에 인덱스를 생성한다
3. ORDER BY 컬럼을 인덱스에 포함한다
4. SELECT 컬럼까지 인덱스에 포함하면 커버링 인덱스가 된다
5. 인덱스는 테이블당 3~5개를 넘지 않도록 한다

---

### 3.7 MySQL my.cnf 전체 설정 예시

Docker 환경에서 MySQL 설정 파일을 마운트하여 사용한다.

```ini
# configs/mysql/my.cnf (신규 생성 후 docker-compose.yml에서 마운트)
[mysqld]
# ─── 기본 설정 ───
server-id                      = 1
port                           = 3306
character-set-server           = utf8mb4
collation-server               = utf8mb4_unicode_ci

# ─── InnoDB 엔진 ───
innodb_buffer_pool_size        = 1G          # 컨테이너 메모리의 70% (mem_limit=2g 기준)
innodb_buffer_pool_instances   = 4           # buffer pool을 4개로 분할 (경합 감소)
innodb_log_file_size           = 256M        # redo 로그 크기
innodb_log_buffer_size         = 64M         # 로그 버퍼 (대량 트랜잭션 시 유리)
innodb_flush_log_at_trx_commit = 1           # 운영: 1 (안전), 개발: 2 (성능)
innodb_flush_method            = O_DIRECT    # OS 캐시 우회 (이중 버퍼링 방지)
innodb_file_per_table          = 1           # 테이블별 파일 관리

# ─── 연결 관리 ───
max_connections                = 200         # Tomcat 2대 커넥션풀 합계 + 여유분
wait_timeout                   = 600         # 유휴 연결 10분 후 종료 (기본 28800초는 과다)
interactive_timeout            = 600
max_connect_errors             = 100000      # 연결 오류 허용 횟수

# ─── 쿼리 캐시 / 임시 테이블 ───
tmp_table_size                 = 64M
max_heap_table_size            = 64M
sort_buffer_size               = 4M
join_buffer_size               = 4M

# ─── Slow Query Log ───
slow_query_log                 = 1
long_query_time                = 1           # 1초 이상 쿼리 기록
slow_query_log_file            = /var/log/mysql/slow.log
log_queries_not_using_indexes  = 1

# ─── 바이너리 로그 (복제/백업용) ───
log_bin                        = mysql-bin
binlog_expire_logs_seconds     = 604800      # 7일 보관
binlog_format                  = ROW

[client]
default-character-set          = utf8mb4
```

**docker-compose.yml에 마운트 추가:**

```yaml
mysql:
  image: mysql:8.0
  container_name: mw-mysql
  volumes:
    - mysql_data:/var/lib/mysql
    - ./configs/mysql/my.cnf:/etc/mysql/conf.d/custom.cnf:ro   # 추가
```

**VERIFY:**

```bash
# 설정 적용 확인
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'"
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW VARIABLES LIKE 'max_connections'"
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW VARIABLES LIKE 'slow_query_log'"

# InnoDB 상태 전체 확인
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW ENGINE INNODB STATUS\G"
```

---

## 4. Docker 리소스 제한

### 4.1 docker-compose.yml에서 리소스 제한 설정

**WHY:** Docker 컨테이너에 리소스 제한을 설정하지 않으면, 하나의 컨테이너가 호스트의 모든 리소스를 소진하여 다른 컨테이너에 영향을 줄 수 있다. 특히 MySQL이나 JVM은 메모리를 탐욕적으로 사용하므로 반드시 제한해야 한다.

**HOW:**

Docker Compose v3 (deploy) 또는 v2 (직접 지정) 방식으로 설정한다.

```yaml
# docker-compose.yml 리소스 제한 설정 예시

services:
  mysql:
    image: mysql:8.0
    container_name: mw-mysql
    # --- 리소스 제한 ---
    mem_limit: 2g
    mem_reservation: 1g          # 소프트 제한 (보장 메모리)
    cpus: 2.0                    # CPU 코어 2개 제한
    # 또는 deploy 섹션 사용 (Swarm/Compose v3)
    # deploy:
    #   resources:
    #     limits:
    #       memory: 2G
    #       cpus: '2.0'
    #     reservations:
    #       memory: 1G
    #       cpus: '1.0'

  tomcat1:
    mem_limit: 1g
    mem_reservation: 512m
    cpus: 1.0

  tomcat2:
    mem_limit: 1g
    mem_reservation: 512m
    cpus: 1.0

  nginx:
    mem_limit: 512m
    mem_reservation: 128m
    cpus: 1.0

  keycloak:
    mem_limit: 1g
    mem_reservation: 512m
    cpus: 1.0

  scouter-server:
    mem_limit: 512m
    mem_reservation: 256m
    cpus: 0.5

  prometheus:
    mem_limit: 512m
    mem_reservation: 256m
    cpus: 0.5

  grafana:
    mem_limit: 256m
    mem_reservation: 128m
    cpus: 0.5

  node-exporter:
    mem_limit: 128m
    cpus: 0.25

  nginx-exporter:
    mem_limit: 128m
    cpus: 0.25
```

**컨테이너별 권장 리소스:**

| 컨테이너 | 메모리 (limit) | 메모리 (reservation) | CPU (cores) |
|-----------|---------------|---------------------|-------------|
| mysql | 2g | 1g | 2.0 |
| tomcat1 | 1g | 512m | 1.0 |
| tomcat2 | 1g | 512m | 1.0 |
| nginx | 512m | 128m | 1.0 |
| keycloak | 1g | 512m | 1.0 |
| scouter-server | 512m | 256m | 0.5 |
| prometheus | 512m | 256m | 0.5 |
| grafana | 256m | 128m | 0.5 |
| node-exporter | 128m | - | 0.25 |
| nginx-exporter | 128m | - | 0.25 |
| **합계** | **~7.0g** | | **~7.5 cores** |

---

### 4.2 OOM Killer 방지 전략

**WHY:** Linux OOM Killer는 메모리가 부족하면 가장 많은 메모리를 사용하는 프로세스를 강제 종료한다. Docker 컨테이너 환경에서는 JVM이나 MySQL이 OOM Killer에 의해 종료되면 서비스 장애로 이어진다.

**전략:**

```yaml
# 1. mem_limit을 JVM/MySQL 설정보다 넉넉하게 설정
# JVM -Xmx=768m → 컨테이너 mem_limit=1g (JVM 힙 외 메모리 여유분 필요)

# 2. oom-kill-disable 사용 (주의: 반드시 mem_limit과 함께 사용)
services:
  mysql:
    mem_limit: 2g
    oom-kill-disable: true        # OOM Killer 비활성화

# 3. oom_score_adj로 우선순위 조정 (낮을수록 보호)
services:
  mysql:
    oom_score_adj: -500           # MySQL은 OOM에서 보호 (-1000 ~ 1000)
  nginx:
    oom_score_adj: -300           # Nginx도 보호
  grafana:
    oom_score_adj: 300            # 모니터링은 상대적으로 낮은 우선순위
```

**OOM 발생 여부 확인:**

```bash
# 호스트에서 OOM 로그 확인
dmesg | grep -i "oom\|killed"

# Docker 컨테이너 OOM 기록 확인
docker inspect mw-tomcat1 | grep -i oom
# "OOMKilled": true 이면 OOM으로 종료된 것

# 컨테이너 재시작 기록
docker inspect mw-tomcat1 --format='{{.RestartCount}}'
```

---

### 4.3 컨테이너별 리소스 모니터링

**HOW:**

```bash
# 실시간 리소스 사용량 확인
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"

# 출력 예시:
# NAME              CPU %     MEM USAGE / LIMIT   MEM %     NET I/O          BLOCK I/O
# mw-mysql          15.20%    1.2GiB / 2GiB       60.00%    5.5MB / 3.2MB    120MB / 45MB
# mw-tomcat1        8.50%     450MiB / 1GiB       43.95%    2.1MB / 1.8MB    0B / 12MB
# mw-tomcat2        7.30%     420MiB / 1GiB       41.02%    1.9MB / 1.6MB    0B / 10MB
# mw-nginx          0.50%     25MiB / 512MiB      4.88%     8.2MB / 7.5MB    0B / 0B

# 특정 컨테이너만 모니터링
docker stats mw-tomcat1 mw-tomcat2 mw-mysql

# JSON 형식으로 출력 (스크립트 연동용)
docker stats --no-stream --format '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","mem":"{{.MemPerc}}"}'

# cAdvisor 활용 (Prometheus + Grafana 연동)
# docker-compose.yml에 cAdvisor 추가하면 컨테이너 메트릭을 Grafana에서 시각화 가능
```

**경고 기준:**

| 지표 | 정상 | 주의 | 위험 |
|------|------|------|------|
| CPU 사용률 | < 60% | 60~80% | > 80% |
| 메모리 사용률 | < 70% | 70~85% | > 85% |
| 네트워크 I/O | 안정적 | 급증 추세 | 급격한 스파이크 |

---

## 5. 성능 측정 방법

### 5.1 ab (Apache Benchmark) 사용법

**WHY:** ab는 Apache 프로젝트에서 제공하는 가장 간단한 HTTP 부하 테스트 도구이다. 빠른 스모크 테스트에 적합하다.

**HOW:**

```bash
# 설치 (macOS)
brew install httpd  # ab가 포함됨

# 설치 (Ubuntu/Debian)
apt-get install apache2-utils

# 기본 사용법
# -n: 총 요청 수, -c: 동시 접속 수
ab -n 1000 -c 50 https://localhost/

# POST 요청 테스트
ab -n 500 -c 20 -p post_data.json -T "application/json" https://localhost/api/orders

# keepalive 활성화 (실제 브라우저와 유사)
ab -n 1000 -c 50 -k https://localhost/

# SSL 인증서 검증 비활성화 (자체 서명 인증서)
# ab는 -k 옵션이 keepalive용이므로 SSL 무시는 별도 불가
# → wrk 또는 curl 기반 스크립트 활용
```

**결과 해석:**

```
# ab 결과 주요 항목
Concurrency Level:      50           # 동시 접속 수
Time taken for tests:   5.234 seconds
Complete requests:      1000         # 완료된 요청 수
Failed requests:        0            # 실패한 요청 (0이어야 정상)
Requests per second:    191.06 [#/sec] (mean)     # ★ RPS (초당 처리량)
Time per request:       261.700 [ms] (mean)       # ★ 평균 응답 시간
Time per request:       5.234 [ms] (mean, across all concurrent requests)

Percentage of the requests served within a certain time (ms)
  50%    230        # ★ p50 (중앙값)
  66%    280
  75%    310
  90%    420        # p90
  95%    580        # ★ p95
  99%    890        # ★ p99
 100%   1250        # 최대 응답 시간
```

---

### 5.2 wrk 사용법

**WHY:** wrk는 ab보다 더 정교한 부하 테스트 도구이다. Lua 스크립트를 통해 복잡한 시나리오(로그인 후 API 호출 등)를 구현할 수 있고, 더 정확한 레이턴시 분포를 제공한다.

**HOW:**

```bash
# 설치
brew install wrk        # macOS
apt-get install wrk     # Ubuntu

# 기본 사용법
# -t: 스레드 수, -c: 동시 연결 수, -d: 테스트 지속 시간
wrk -t4 -c100 -d30s https://localhost/

# 결과 예시:
# Running 30s test @ https://localhost/
#   4 threads and 100 connections
#   Thread Stats   Avg      Stdev     Max   +/- Stdev
#     Latency    45.23ms   12.50ms  250.00ms   89.50%
#     Req/Sec   550.12    100.23     1.2k      72.30%
#   Latency Distribution
#      50%   42.00ms       ★ p50
#      75%   48.00ms
#      90%   58.00ms       ★ p90
#      99%  120.00ms       ★ p99
#   65012 requests in 30.00s, 120.50MB read
# Requests/sec:   2167.07   ★ RPS
# Transfer/sec:      4.02MB

# Lua 스크립트로 POST 요청 테스트
cat << 'SCRIPT' > post_test.lua
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
wrk.body = '{"username": "testuser", "action": "test"}'
SCRIPT

wrk -t4 -c50 -d30s -s post_test.lua https://localhost/api/data

# 커스텀 헤더 추가 (인증 토큰 등)
cat << 'SCRIPT' > auth_test.lua
wrk.headers["Authorization"] = "Bearer eyJhbGciOiJSUzI1NiIs..."
SCRIPT

wrk -t2 -c20 -d30s -s auth_test.lua https://localhost/api/protected
```

---

### 5.3 측정 결과 해석

**핵심 지표:**

| 지표 | 의미 | 기준 |
|------|------|------|
| **RPS** (Requests Per Second) | 초당 처리 요청 수 | 높을수록 좋음 |
| **Latency p50** | 전체 요청의 50%가 이 시간 내에 완료 | 사용자 체감 응답시간의 기준 |
| **Latency p95** | 전체 요청의 95%가 이 시간 내에 완료 | SLA 기준으로 자주 사용 |
| **Latency p99** | 전체 요청의 99%가 이 시간 내에 완료 | 최악의 사용자 경험 (테일 레이턴시) |
| **Error Rate** | 실패한 요청 비율 | 0%에 가까워야 함 |

**주의 사항:**

- **평균(mean)에 속지 말 것.** p99가 평균의 10배라면 일부 사용자는 극심한 지연을 경험한다. p95/p99를 기준으로 판단한다.
- **워밍업 필요.** JVM은 JIT 컴파일러가 최적화를 완료할 때까지 초기 몇천 요청은 느리다. 측정 전 워밍업 요청을 보내야 정확하다.

```bash
# 워밍업 (결과 무시)
wrk -t2 -c10 -d10s https://localhost/ > /dev/null 2>&1

# 실제 측정
wrk -t4 -c100 -d60s --latency https://localhost/
```

---

### 5.4 튜닝 전/후 비교 방법론

성능 튜닝은 반드시 **정량적 비교**를 해야 한다. "체감상 빨라졌다"는 근거가 되지 않는다.

**절차:**

```
1. 베이스라인 측정 (튜닝 전)
   ├── 동일한 테스트 조건 설정 (동시 접속 수, 요청 수, 지속 시간)
   ├── 3회 이상 반복 측정하여 평균 산출
   └── 결과 기록: RPS, p50, p95, p99, 에러율

2. 튜닝 적용
   ├── 한 번에 하나의 파라미터만 변경 (다중 변경 시 효과 판별 불가)
   └── 변경 사항 기록

3. 사후 측정 (튜닝 후)
   ├── 베이스라인과 동일한 조건으로 측정
   ├── 3회 이상 반복
   └── 결과 기록

4. 비교 분석
   ├── 개선율 = (튜닝후 - 튜닝전) / 튜닝전 * 100
   └── 개선이 없거나 악화되면 롤백
```

**비교 기록 예시:**

```
┌──────────────────────┬────────────┬────────────┬──────────┐
│       항목           │  튜닝 전   │  튜닝 후   │  개선율  │
├──────────────────────┼────────────┼────────────┼──────────┤
│ RPS                  │   150.2    │   220.5    │  +46.8%  │
│ Latency p50          │   120ms    │    85ms    │  -29.2%  │
│ Latency p95          │   380ms    │   210ms    │  -44.7%  │
│ Latency p99          │   850ms    │   450ms    │  -47.1%  │
│ Error Rate           │   0.5%     │   0.1%     │  -80.0%  │
│ CPU 사용률 (peak)    │    85%     │    72%     │  -15.3%  │
│ 메모리 사용률 (peak) │    90%     │    78%     │  -13.3%  │
└──────────────────────┴────────────┴────────────┴──────────┘
```

**스크립트로 자동화:**

```bash
#!/bin/bash
# scripts/benchmark.sh - 성능 측정 자동화

URL="https://localhost/"
THREADS=4
CONNECTIONS=100
DURATION=30s
OUTPUT_DIR="./benchmark_results"

mkdir -p $OUTPUT_DIR
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$OUTPUT_DIR/result_$TIMESTAMP.txt"

echo "=== Performance Benchmark ===" | tee $RESULT_FILE
echo "Date: $(date)" | tee -a $RESULT_FILE
echo "URL: $URL" | tee -a $RESULT_FILE
echo "Threads: $THREADS, Connections: $CONNECTIONS, Duration: $DURATION" | tee -a $RESULT_FILE
echo "---" | tee -a $RESULT_FILE

# 워밍업
echo "Warming up..."
wrk -t2 -c10 -d10s $URL > /dev/null 2>&1

# 3회 반복 측정
for i in 1 2 3; do
  echo "--- Run $i ---" | tee -a $RESULT_FILE
  wrk -t$THREADS -c$CONNECTIONS -d$DURATION --latency $URL 2>&1 | tee -a $RESULT_FILE
  echo "" | tee -a $RESULT_FILE
  sleep 5
done

echo "Results saved to: $RESULT_FILE"
```

---

## 6. 튜닝 체크리스트

운영 환경 투입 전 아래 항목을 모두 확인한다.

### Nginx

| # | 항목 | 확인 | 비고 |
|---|------|------|------|
| 1 | `worker_processes`가 CPU 코어 수와 일치하는가 (또는 auto) | [ ] | `nginx -T \| grep worker_processes` |
| 2 | `worker_connections`가 예상 동시 접속 수를 수용하는가 | [ ] | 최소 1024 이상 |
| 3 | keepalive_timeout이 적절한가 (30~65초) | [ ] | |
| 4 | 업스트림 keepalive가 설정되어 있는가 | [ ] | `proxy_http_version 1.1` 필수 |
| 5 | gzip 압축이 활성화되어 있는가 | [ ] | 이미지/동영상 제외 확인 |
| 6 | proxy_buffer_size가 충분한가 (JWT 토큰 고려) | [ ] | 16k 이상 |
| 7 | rate limiting이 설정되어 있는가 | [ ] | 로그인 엔드포인트 강화 |
| 8 | SSL/TLS 프로토콜이 TLSv1.2 이상만 허용하는가 | [ ] | |
| 9 | `nginx -t` 설정 검증 통과하는가 | [ ] | |
| 10 | access_log에 응답 시간이 포함되어 있는가 | [ ] | `$upstream_response_time` |

### Tomcat/JVM

| # | 항목 | 확인 | 비고 |
|---|------|------|------|
| 1 | `-Xms`와 `-Xmx`가 적절한가 (컨테이너 메모리의 50~75%) | [ ] | |
| 2 | `-Xms`와 `-Xmx`가 동일한가 (운영 환경) | [ ] | 힙 리사이징 방지 |
| 3 | GC 알고리즘이 서비스 특성에 맞는가 | [ ] | 웹 서비스: G1 GC 권장 |
| 4 | GC 로그가 활성화되어 있는가 | [ ] | `-Xlog:gc*:file=...` |
| 5 | HeapDumpOnOutOfMemoryError가 설정되어 있는가 | [ ] | 장애 분석 필수 |
| 6 | maxThreads가 예상 부하를 수용하는가 | [ ] | |
| 7 | Tomcat compression이 off인가 (Nginx에서 처리) | [ ] | 이중 압축 방지 |
| 8 | enableLookups="false"인가 | [ ] | DNS 역방향 조회 비활성화 |
| 9 | Scouter Agent가 정상 연결되어 있는가 | [ ] | |
| 10 | jvmRoute가 Tomcat 인스턴스별로 다른가 | [ ] | 로드밸런싱 식별용 |

### MySQL

| # | 항목 | 확인 | 비고 |
|---|------|------|------|
| 1 | innodb_buffer_pool_size가 가용 메모리의 70~80%인가 | [ ] | |
| 2 | buffer pool 적중률이 99% 이상인가 | [ ] | |
| 3 | slow_query_log가 활성화되어 있는가 | [ ] | |
| 4 | max_connections가 적절한가 | [ ] | 커넥션풀 합계 + 여유분 |
| 5 | wait_timeout이 적절한가 (300~600초) | [ ] | 기본 28800초는 과다 |
| 6 | innodb_flush_log_at_trx_commit이 환경에 맞는가 | [ ] | 운영: 1, 개발: 2 |
| 7 | 주요 테이블에 인덱스가 설정되어 있는가 | [ ] | EXPLAIN으로 확인 |
| 8 | character-set이 utf8mb4인가 | [ ] | |

### Docker

| # | 항목 | 확인 | 비고 |
|---|------|------|------|
| 1 | 모든 컨테이너에 mem_limit이 설정되어 있는가 | [ ] | |
| 2 | JVM -Xmx < 컨테이너 mem_limit인가 | [ ] | 최소 25% 여유 |
| 3 | MySQL innodb_buffer_pool_size < 컨테이너 mem_limit인가 | [ ] | 최소 30% 여유 |
| 4 | 호스트 전체 메모리가 컨테이너 합계를 수용하는가 | [ ] | 합계 ~6.2GB |
| 5 | OOM Killer 방지 설정이 되어 있는가 | [ ] | 핵심 서비스 보호 |
| 6 | 컨테이너 재시작 정책(restart)이 설정되어 있는가 | [ ] | `restart: unless-stopped` |
| 7 | docker stats로 리소스 사용량을 확인했는가 | [ ] | |

### 성능 측정

| # | 항목 | 확인 | 비고 |
|---|------|------|------|
| 1 | 베이스라인 측정을 완료했는가 | [ ] | 3회 이상 반복 |
| 2 | 튜닝 후 측정을 완료했는가 | [ ] | 동일 조건 필수 |
| 3 | RPS가 목표치를 달성하는가 | [ ] | |
| 4 | p95 레이턴시가 SLA 이내인가 | [ ] | |
| 5 | 에러율이 0%에 가까운가 | [ ] | |
| 6 | 장시간 부하 테스트(소크 테스트) 시 메모리 누수가 없는가 | [ ] | 30분 이상 |

---

## 부록: 빠른 참조 명령어 모음

```bash
# ─── Nginx ───
docker exec mw-nginx nginx -t                    # 설정 검증
docker exec mw-nginx nginx -s reload             # 무중단 설정 리로드
docker exec mw-nginx curl -s localhost/stub_status  # 연결 상태

# ─── Tomcat/JVM ───
docker exec mw-tomcat1 jstack $(docker exec mw-tomcat1 pgrep java)   # 스레드 덤프
docker exec mw-tomcat1 jmap -heap $(docker exec mw-tomcat1 pgrep java)  # 힙 상태
docker exec mw-tomcat1 jstat -gc $(docker exec mw-tomcat1 pgrep java) 1000  # GC 통계 (1초 간격)

# ─── MySQL ───
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW PROCESSLIST"
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW ENGINE INNODB STATUS\G"
docker exec mw-mysql mysqldumpslow -s t -t 10 /var/log/mysql/slow.log

# ─── Docker ───
docker stats --no-stream                          # 전체 리소스 스냅샷
docker inspect mw-tomcat1 | grep -i oom           # OOM 발생 여부
docker system df                                  # 디스크 사용량

# ─── 성능 측정 ───
ab -n 1000 -c 50 -k https://localhost/            # Apache Benchmark
wrk -t4 -c100 -d30s --latency https://localhost/  # wrk 부하 테스트
```

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [모니터링 메트릭 가이드](monitoring-metrics.md) | 성능 메트릭 수집 가이드 |
| [Scouter APM 가이드](scouter-guide.md) | APM 기반 병목 분석 |
| [인프라 설계](infrastructure-design.md) | 인프라 용량 설계 |
| [장애 대응 매뉴얼](incident-response.md) | 성능 장애 대응 |
