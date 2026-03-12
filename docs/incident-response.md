# 장애 대응 가이드

> **대상 시스템**: Nginx + Tomcat(x2) + MySQL + Scouter APM + Prometheus + Grafana + Keycloak (Docker Compose)
> **문서 수준**: 실무 3년차 엔지니어 기준
> **최종 수정**: 2026-03-12

---

## 목차

1. [장애 대응 프로세스](#1-장애-대응-프로세스)
2. [OOM Kill (메모리 부족)](#2-oom-kill-메모리-부족)
3. [Connection Pool 고갈](#3-connection-pool-고갈)
4. [GC Storm (Full GC 반복)](#4-gc-storm-full-gc-반복)
5. [Slow Query (느린 쿼리)](#5-slow-query-느린-쿼리)
6. [Nginx 502/504 에러](#6-nginx-502504-에러)
7. [SSL 인증서 만료](#7-ssl-인증서-만료)
8. [Keycloak 장애 (SSO 로그인 불가)](#8-keycloak-장애-sso-로그인-불가)
9. [Docker 디스크 풀](#9-docker-디스크-풀)
10. [장애 보고서 작성법](#10-장애-보고서-작성법)

---

## 1. 장애 대응 프로세스

### 1.1 장애 등급 분류

| 등급 | 정의 | 영향 범위 | 최대 허용 복구 시간 | 에스컬레이션 |
|------|------|-----------|---------------------|-------------|
| **P1 (Critical)** | 전체 서비스 중단 | 전체 사용자 접근 불가 | 30분 | 발생 즉시 팀장 + CTO 보고 |
| **P2 (Major)** | 핵심 기능 장애 | 로그인 불가, 결제 불가 등 주요 기능 마비 | 1시간 | 15분 내 팀장 보고 |
| **P3 (Minor)** | 일부 기능 저하 | 응답 지연, 간헐적 에러 | 4시간 | 30분 내 팀장 보고 |
| **P4 (Low)** | 경미한 이슈 | UI 깨짐, 로그 에러 등 서비스 영향 없음 | 다음 업무일 | 일일 보고에 포함 |

### 1.2 5단계 대응 프로세스

```
[1단계] 장애 감지 → [2단계] 1차 대응 → [3단계] 원인 분석 → [4단계] 복구 → [5단계] 사후 분석
```

#### 1단계: 장애 감지 (0~5분)

- **담당자**: 당번 엔지니어 (On-Call)
- **감지 경로**:
  - Grafana Alert (Slack/Email 알림)
  - Scouter Client 실시간 모니터링
  - Prometheus Alertmanager
  - 사용자 신고 (CS팀 전달)
- **수행 사항**:
  1. 장애 현상 1차 확인 (어떤 서비스가 영향받는지)
  2. 장애 등급 판단 (P1~P4)
  3. 장애 채널(Slack 등)에 최초 보고

```bash
# 전체 컨테이너 상태 즉시 확인
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 최근 재시작된 컨테이너 확인
docker ps -a --filter "status=restarting" --format "{{.Names}}: {{.Status}}"

# 각 서비스 헬스체크
curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health     # Nginx
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health   # Keycloak
curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy # Prometheus
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health # Grafana
```

#### 2단계: 1차 대응 (5~15분)

- **담당자**: 당번 엔지니어
- **목표**: 서비스 가용성 최우선 복구 (임시 조치 포함)
- **에스컬레이션 기준**: 15분 내 복구 불가 시 팀장 + 시니어 엔지니어 호출
- **수행 사항**:
  1. 장애 서비스 재시작 시도
  2. 트래픽 우회 (가능한 경우)
  3. 롤백 판단 (최근 배포가 원인인 경우)

```bash
# 장애 컨테이너 재시작
docker compose restart tomcat1

# 특정 WAS를 upstream에서 제외 (Nginx 설정 수정 후 reload)
docker exec mw-nginx nginx -s reload

# 최근 배포 이력 확인
docker inspect --format='{{.Created}}' mw-tomcat1
```

#### 3단계: 원인 분석 (15~60분)

- **담당자**: 시니어 엔지니어 + 당번 엔지니어
- **목표**: 장애의 근본 원인(Root Cause) 파악
- **수행 사항**:
  1. 로그 수집 및 분석
  2. 메트릭 데이터 상관관계 분석 (Grafana 대시보드)
  3. Scouter XLog/Profile 분석
  4. 타임라인 정리 (언제부터 이상 징후가 있었는지)

```bash
# 모든 서비스 로그를 타임스탬프 기준으로 수집
docker compose logs --since "2024-01-15T10:00:00" --timestamps > /tmp/incident_logs.txt

# 특정 컨테이너 로그 상세 확인
docker logs mw-tomcat1 --since "30m" --tail 500
docker logs mw-nginx --since "30m" --tail 500
docker logs mw-mysql --since "30m" --tail 500
```

#### 4단계: 복구 (원인에 따라 상이)

- **담당자**: 시니어 엔지니어
- **목표**: 근본 원인 제거 및 정상 상태 복구
- **수행 사항**:
  1. 근본 원인에 대한 수정 적용
  2. 정상 동작 검증 (기능 테스트 + 모니터링 지표 확인)
  3. 모니터링 강화 (최소 1시간 집중 관찰)

#### 5단계: 사후 분석 (복구 후 1~3일 이내)

- **담당자**: 전체 팀
- **목표**: 재발 방지 대책 수립
- **수행 사항**:
  1. 장애 보고서 작성 (10장 참고)
  2. Post-mortem 미팅 진행 (비난 금지 원칙)
  3. 재발 방지 대책 도출 및 티켓 등록
  4. 모니터링/알람 보완

---

## 2. OOM Kill (메모리 부족)

### 2.1 증상

- 컨테이너가 예고 없이 재시작된다.
- `docker ps -a`에서 특정 컨테이너의 STATUS가 `Exited (137)`로 표시된다. (137 = 128 + 9, 즉 SIGKILL)
- Grafana 대시보드에서 메모리 사용량이 100%에 도달한 후 급격히 떨어지는 패턴이 반복된다.
- Scouter Client에서 해당 WAS 인스턴스가 일시적으로 사라졌다가 다시 나타난다.
- 애플리케이션 로그에 `java.lang.OutOfMemoryError` 메시지가 기록된다.

### 2.2 확인 명령어

```bash
# 1. 컨테이너 종료 코드 확인 (137이면 OOM Kill 가능성 높음)
docker inspect mw-tomcat1 --format='{{.State.ExitCode}}'
# 출력 예: 137

# 2. 컨테이너의 OOM Kill 여부 직접 확인
docker inspect mw-tomcat1 --format='{{.State.OOMKilled}}'
# 출력 예: true

# 3. 호스트 커널 로그에서 OOM 이벤트 확인
dmesg | grep -i "oom" | tail -20
# 출력 예: [12345.678] Out of memory: Killed process 1234 (java) total-vm:2048000kB

# 4. 컨테이너에 설정된 메모리 제한 확인
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"

# 5. 현재 JVM 힙 사용량 확인 (컨테이너 내부)
docker exec mw-tomcat1 jstat -gcutil $(docker exec mw-tomcat1 pgrep java) 1000 5
# S0, S1, E(Eden), O(Old), M(Metaspace), GC 횟수 등이 출력됨

# 6. JVM 힙 덤프 생성 (분석용)
docker exec mw-tomcat1 jmap -dump:format=b,file=/tmp/heap_dump.hprof $(docker exec mw-tomcat1 pgrep java)
docker cp mw-tomcat1:/tmp/heap_dump.hprof ./heap_dump_tomcat1.hprof
```

### 2.3 즉시 대응 (1분 이내)

```bash
# 1. 장애 컨테이너 재시작
docker compose restart tomcat1

# 2. 메모리 제한이 너무 낮다면 docker-compose.yml 수정 후 재시작
# docker-compose.yml의 tomcat1 서비스에 deploy.resources 추가:
#   deploy:
#     resources:
#       limits:
#         memory: 1024M    # 기존 512M에서 증가
#       reservations:
#         memory: 512M
docker compose up -d tomcat1

# 3. 다른 WAS가 정상이면 트래픽 몰리지 않도록 확인
docker logs mw-tomcat2 --tail 10
```

### 2.4 근본 해결

```bash
# 1. 힙 덤프 파일을 Eclipse MAT(Memory Analyzer Tool)로 분석
#    - Leak Suspects Report 확인
#    - Dominator Tree에서 가장 큰 객체 확인
#    - Histogram에서 인스턴스 수가 비정상적으로 많은 클래스 확인

# 2. JVM 힙 사이즈 조정 (docker-compose.yml)
# 현재 설정: -Xms256m -Xmx512m
# 권장 변경: -Xms512m -Xmx1024m
# 주의: 컨테이너 메모리 제한의 70~80%를 JVM 힙으로 설정
#        나머지 20~30%는 Metaspace, 스레드 스택, Native 메모리용

# 3. 메모리 누수 원인 코드 수정
#    대표적 원인:
#    - static Collection에 데이터를 계속 추가하는 경우
#    - DB 커넥션/스트림을 close하지 않는 경우
#    - 캐시에 만료 정책이 없는 경우
#    - ThreadLocal 변수를 제거하지 않는 경우
```

### 2.5 예방

```bash
# 1. JVM 옵션에 OOM 발생 시 자동 힙 덤프 설정 추가
# docker-compose.yml의 JAVA_OPTS에 추가:
#   -XX:+HeapDumpOnOutOfMemoryError
#   -XX:HeapDumpPath=/usr/local/tomcat/logs/heap_dump.hprof
#   -XX:+ExitOnOutOfMemoryError

# 2. Prometheus Alert 설정 (컨테이너 메모리 사용률 80% 이상 시)
# prometheus/alert_rules.yml:
#   - alert: ContainerHighMemory
#     expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.8
#     for: 5m
#     labels:
#       severity: warning
#     annotations:
#       summary: "컨테이너 메모리 사용률 80% 초과 ({{ $labels.name }})"

# 3. Grafana 대시보드에 JVM Heap 패널 추가하여 추이 상시 모니터링
```

---

## 3. Connection Pool 고갈

### 3.1 증상

- 애플리케이션 로그에 `Cannot get a connection, pool error Timeout waiting for idle object` 또는 `HikariPool-1 - Connection is not available, request timed out after 30000ms` 에러가 반복 출력된다.
- 사용자에게 500 Internal Server Error가 반환된다.
- Scouter XLog에서 Active Service 수가 급격히 증가하며, 대부분의 요청이 SQL 구간에서 대기 중인 것으로 표시된다.
- 응답 시간이 평소 200ms 수준에서 30초 이상으로 급증한다.
- Grafana의 DB 커넥션 관련 메트릭이 max 값에 도달해 있다.

### 3.2 확인 명령어

```bash
# 1. Tomcat 로그에서 커넥션 풀 에러 검색
docker logs mw-tomcat1 --since "10m" 2>&1 | grep -i "connection.*pool\|timeout.*connection\|hikari"

# 2. Scouter에서 Active Service 확인
#    Scouter Client 접속 (localhost:6100) -> Active Service 탭에서 대기 중인 서비스 수 확인

# 3. MySQL 현재 연결 수 확인
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW STATUS LIKE 'Threads_connected';"
# 출력 예: Threads_connected | 150

# 4. MySQL 최대 연결 수 확인
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW VARIABLES LIKE 'max_connections';"
# 출력 예: max_connections | 151

# 5. MySQL에서 현재 실행 중인 쿼리 확인 (어떤 쿼리가 커넥션을 잡고 있는지)
docker exec mw-mysql mysql -uroot -proot_password -e "SHOW FULL PROCESSLIST;"

# 6. 네트워크 레벨에서 MySQL 포트(3306) 연결 상태 확인
docker exec mw-tomcat1 sh -c "netstat -an | grep 3306 | awk '{print \$6}' | sort | uniq -c | sort -rn"
# 출력 예:
#   85 ESTABLISHED
#   23 TIME_WAIT
#    5 CLOSE_WAIT

# 7. TIME_WAIT 상태 연결이 과도한지 확인
docker exec mw-tomcat1 sh -c "netstat -an | grep TIME_WAIT | wc -l"
```

### 3.3 즉시 대응 (1분 이내)

```bash
# 1. 문제가 되는 WAS 재시작 (커넥션 풀 초기화)
docker compose restart tomcat1

# 2. MySQL에서 장시간 실행 중인 쿼리 강제 종료
# 먼저 문제 쿼리의 ID 확인
docker exec mw-mysql mysql -uroot -proot_password -e \
  "SELECT ID, USER, HOST, DB, TIME, STATE, LEFT(INFO, 80) AS QUERY FROM information_schema.PROCESSLIST WHERE TIME > 30 ORDER BY TIME DESC;"

# 해당 쿼리 Kill (예: ID가 1234인 경우)
docker exec mw-mysql mysql -uroot -proot_password -e "KILL 1234;"

# 3. MySQL max_connections 임시 증가 (재시작 없이 즉시 적용)
docker exec mw-mysql mysql -uroot -proot_password -e "SET GLOBAL max_connections = 300;"
```

### 3.4 근본 해결

```bash
# 1. HikariCP 커넥션 풀 사이즈 최적화
# application.properties 또는 application.yml에서:
#
#   spring.datasource.hikari.maximum-pool-size=20        # 기본 10 -> 20
#   spring.datasource.hikari.minimum-idle=10             # 최소 유휴 커넥션
#   spring.datasource.hikari.idle-timeout=300000         # 유휴 커넥션 5분 후 제거
#   spring.datasource.hikari.max-lifetime=600000         # 커넥션 최대 수명 10분
#   spring.datasource.hikari.connection-timeout=20000    # 커넥션 획득 대기 20초
#   spring.datasource.hikari.leak-detection-threshold=60000  # 60초 이상 반환 안된 커넥션 로그 출력
#
# 풀 사이즈 공식 (HikariCP 권장):
#   pool_size = (core_count * 2) + effective_spindle_count
#   예: 4코어 서버, SSD -> (4 * 2) + 1 = 9 ~ 10개가 적정

# 2. 슬로우 쿼리 최적화 (5장 참고)
#    커넥션을 오래 점유하는 쿼리를 개선해야 풀 고갈을 방지할 수 있음

# 3. 커넥션 누수 원인 코드 수정
#    - try-with-resources를 사용하지 않아 close()가 호출되지 않는 경우
#    - @Transactional 범위가 너무 넓어 트랜잭션이 장시간 유지되는 경우
#    - 외부 API 호출을 트랜잭션 내에서 수행하는 경우
```

### 3.5 예방

```bash
# 1. HikariCP 메트릭을 Prometheus로 수집하여 Grafana에서 모니터링
# application.properties:
#   management.endpoints.web.exposure.include=health,prometheus
#   management.metrics.export.prometheus.enabled=true

# 2. Prometheus Alert 설정 (활성 커넥션이 풀 사이즈의 80%에 도달 시)
# alert_rules.yml:
#   - alert: HikariPoolNearExhaustion
#     expr: hikaricp_connections_active / hikaricp_connections_max > 0.8
#     for: 2m
#     labels:
#       severity: warning
#     annotations:
#       summary: "HikariCP 풀 사용률 80% 초과 ({{ $labels.pool }})"

# 3. MySQL max_connections는 모든 WAS의 풀 사이즈 합계보다 충분히 크게 설정
#    예: WAS 2대 x pool_size 20 = 40 -> max_connections = 100 이상 권장
```

---

## 4. GC Storm (Full GC 반복)

### 4.1 증상

- 애플리케이션 응답 시간이 수 초~수십 초로 급증한다.
- Scouter XLog에서 점(dot)들이 평소보다 훨씬 높은 위치(긴 응답시간)에 집중적으로 몰려 있다.
- Scouter의 GC Time, GC Count 그래프가 급격히 상승한다.
- CPU 사용률이 100%에 도달하지만, 실제 비즈니스 로직이 아닌 GC에 의해 소비된다.
- 로그에 `GC overhead limit exceeded` 에러가 출력될 수 있다.
- Grafana에서 JVM Heap의 Old Generation 영역이 GC 후에도 줄어들지 않고 계속 높은 수준을 유지한다.

### 4.2 확인 명령어

```bash
# 1. GC 상태 실시간 확인 (1초 간격, 10회)
docker exec mw-tomcat1 jstat -gcutil $(docker exec mw-tomcat1 pgrep java) 1000 10
# 출력 컬럼 설명:
#   S0   S1   E     O      M     CCS   YGC  YGCT   FGC  FGCT   CGC  CGCT   GCT
#   0.00 99.8 95.2  98.7   95.1  92.3  1523 12.34  145  89.56  0    0.00   101.90
#
# 핵심 지표:
#   O (Old Gen): 80% 이상이면 위험
#   FGC (Full GC 횟수): 짧은 시간에 급증하면 GC Storm
#   FGCT (Full GC 소요 시간): 총 누적 시간이 크면 서비스에 영향

# 2. GC 로그 직접 확인 (JVM 옵션에 GC 로그 활성화된 경우)
docker exec mw-tomcat1 cat /usr/local/tomcat/logs/gc.log | tail -50

# 3. JVM 힙 메모리 상세 확인
docker exec mw-tomcat1 jmap -heap $(docker exec mw-tomcat1 pgrep java)

# 4. Old Generation에서 가장 많은 공간을 차지하는 객체 확인
docker exec mw-tomcat1 jmap -histo $(docker exec mw-tomcat1 pgrep java) | head -30

# 5. Scouter Client에서 확인
#    - GC Time 그래프: 초당 GC 소요 시간 확인
#    - Heap Used 그래프: 톱니 패턴이 아니라 계속 상승하면 누수 의심
#    - XLog: 응답시간 분포 패턴 확인 (GC Storm 중에는 전체적으로 높아짐)
```

### 4.3 즉시 대응 (1분 이내)

```bash
# 1. 트래픽을 다른 WAS로 분산 (Nginx upstream에서 장애 WAS 제외)
# configs/nginx/conf.d/default.conf의 upstream 블록에서 해당 서버에 down 표시:
#   upstream backend {
#       server mw-tomcat1:8080 down;    # <-- down 추가
#       server mw-tomcat2:8080;
#   }
docker exec mw-nginx nginx -s reload

# 2. 장애 WAS에서 힙 덤프 확보 (재시작 전에 반드시 수행)
docker exec mw-tomcat1 jmap -dump:format=b,file=/tmp/heapdump.hprof $(docker exec mw-tomcat1 pgrep java)
docker cp mw-tomcat1:/tmp/heapdump.hprof ./heapdump_$(date +%Y%m%d_%H%M%S).hprof

# 3. 장애 WAS 재시작
docker compose restart tomcat1

# 4. Nginx upstream 복구
# configs/nginx/conf.d/default.conf에서 down 제거 후:
docker exec mw-nginx nginx -s reload
```

### 4.4 근본 해결

```bash
# 1. JVM 힙 사이즈 조정 (docker-compose.yml의 JAVA_OPTS)
# 현재: -Xms256m -Xmx512m
# 조정: -Xms1g -Xmx1g    (Xms와 Xmx를 동일하게 설정하여 힙 리사이징 오버헤드 제거)
#
# 주의: 무조건 크게 잡으면 Full GC 한 번의 pause가 길어짐
#       적정 사이즈를 찾아야 함 (모니터링 데이터 기반)

# 2. GC 알고리즘 변경 (JAVA_OPTS에 추가)
# Java 8 기본: Parallel GC -> G1GC로 변경 권장
#   -XX:+UseG1GC
#   -XX:MaxGCPauseMillis=200          # GC pause 목표 200ms
#   -XX:G1HeapRegionSize=16m          # Region 크기 (힙 크기에 따라 조정)
#   -XX:InitiatingHeapOccupancyPercent=45  # Old Gen 45%에서 concurrent GC 시작
#
# Java 11+에서 ZGC 사용 시 (초저지연 요구 시):
#   -XX:+UseZGC
#   -XX:+ZGenerational                # Java 21+

# 3. GC 로그 활성화 (원인 분석을 위해 항상 켜둘 것)
# Java 8:
#   -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -Xloggc:/usr/local/tomcat/logs/gc.log
# Java 9+:
#   -Xlog:gc*:file=/usr/local/tomcat/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=10M

# 4. 메모리 누수 코드 수정 (힙 덤프 분석 기반)
#    - Eclipse MAT의 Leak Suspects Report 활용
#    - GC Root로부터의 참조 체인 추적
```

### 4.5 예방

```bash
# 1. Prometheus + Grafana Alert (Old Gen 사용률 70% 이상 시 경고)
# alert_rules.yml:
#   - alert: JVMOldGenHigh
#     expr: jvm_memory_used_bytes{area="heap",id="G1 Old Gen"} / jvm_memory_max_bytes{area="heap",id="G1 Old Gen"} > 0.7
#     for: 5m
#     labels:
#       severity: warning
#     annotations:
#       summary: "JVM Old Gen 사용률 70% 초과 ({{ $labels.instance }})"

# 2. Scouter Alert 설정 (GC Time 기준)
#    Scouter Server 설정 파일에서:
#    alert_gc_time_threshold=3000     # GC 시간이 3초 이상이면 Alert

# 3. 부하 테스트 시 GC 패턴 반드시 확인
#    - JMeter/nGrinder로 부하 테스트 중 jstat 모니터링 병행
#    - GC 로그를 GCViewer 또는 GCEasy(https://gceasy.io)에 업로드하여 분석
```

---

## 5. Slow Query (느린 쿼리)

### 5.1 증상

- 특정 API 호출 시 응답이 수 초 이상 지연된다.
- Scouter XLog에서 해당 요청의 프로파일을 열면 SQL 구간이 전체 응답 시간의 대부분을 차지한다.
- Scouter의 SQL 통계에서 특정 쿼리의 평균 수행 시간이 비정상적으로 길다.
- Grafana의 MySQL 대시보드에서 Slow Query 카운트가 증가한다.
- 해당 API에 의존하는 다른 기능들도 연쇄적으로 느려진다.
- Connection Pool 고갈로 이어질 수 있다 (3장 참고).

### 5.2 확인 명령어

```bash
# 1. MySQL Slow Query Log 활성화 상태 확인
docker exec mw-mysql mysql -uroot -proot_password -e \
  "SHOW VARIABLES LIKE 'slow_query%'; SHOW VARIABLES LIKE 'long_query_time';"
# 출력 예:
#   slow_query_log      | ON
#   slow_query_log_file | /var/lib/mysql/slow.log
#   long_query_time     | 1.000000    (1초 이상이면 기록)

# 2. Slow Query Log가 비활성화 상태라면 즉시 활성화 (재시작 불필요)
docker exec mw-mysql mysql -uroot -proot_password -e \
  "SET GLOBAL slow_query_log = 'ON'; SET GLOBAL long_query_time = 1;"

# 3. 최근 슬로우 쿼리 확인
docker exec mw-mysql sh -c "tail -100 /var/lib/mysql/slow.log"

# 4. 현재 실행 중인 느린 쿼리 확인
docker exec mw-mysql mysql -uroot -proot_password -e \
  "SELECT ID, USER, HOST, DB, TIME, STATE, LEFT(INFO,120) AS QUERY
   FROM information_schema.PROCESSLIST
   WHERE COMMAND != 'Sleep' AND TIME > 2
   ORDER BY TIME DESC;"

# 5. 문제 쿼리 실행 계획 분석
docker exec mw-mysql mysql -uroot -proot_password middleware_db -e \
  "EXPLAIN SELECT * FROM users WHERE email = 'test@example.com';"
# 주의할 점:
#   type: ALL -> Full Table Scan (인덱스 미사용, 위험)
#   type: ref, eq_ref, const -> 인덱스 사용 (양호)
#   rows: 예상 스캔 행 수 (클수록 비효율적)
#   Extra: Using filesort, Using temporary -> 성능 저하 요인

# 6. 테이블별 인덱스 현황 확인
docker exec mw-mysql mysql -uroot -proot_password middleware_db -e \
  "SHOW INDEX FROM users;"

# 7. 테이블 통계 확인 (행 수, 데이터 크기)
docker exec mw-mysql mysql -uroot -proot_password -e \
  "SELECT table_name, table_rows, ROUND(data_length/1024/1024, 2) AS data_mb,
          ROUND(index_length/1024/1024, 2) AS index_mb
   FROM information_schema.TABLES
   WHERE table_schema = 'middleware_db'
   ORDER BY data_length DESC;"
```

### 5.3 즉시 대응 (1분 이내)

```bash
# 1. 문제가 되는 쿼리 강제 종료
docker exec mw-mysql mysql -uroot -proot_password -e \
  "SELECT ID, TIME, LEFT(INFO,80) FROM information_schema.PROCESSLIST WHERE TIME > 30;"
# 출력에서 ID 확인 후:
docker exec mw-mysql mysql -uroot -proot_password -e "KILL <PROCESS_ID>;"

# 2. 동일 쿼리가 대량으로 실행 중이면 일괄 종료 스크립트 사용
docker exec mw-mysql mysql -uroot -proot_password -Nse \
  "SELECT CONCAT('KILL ', ID, ';')
   FROM information_schema.PROCESSLIST
   WHERE TIME > 30 AND COMMAND != 'Sleep';" | \
docker exec -i mw-mysql mysql -uroot -proot_password
```

### 5.4 근본 해결

```bash
# 1. EXPLAIN 결과를 기반으로 적절한 인덱스 추가
docker exec mw-mysql mysql -uroot -proot_password middleware_db -e \
  "CREATE INDEX idx_users_email ON users(email);"

# 인덱스 설계 원칙:
#   - WHERE 절에 자주 사용되는 컬럼
#   - JOIN 조건에 사용되는 컬럼
#   - 카디널리티(고유값 비율)가 높은 컬럼 우선
#   - 복합 인덱스는 선택도가 높은 컬럼을 앞에 배치

# 2. 쿼리 리팩토링 예시
# Before (N+1 문제):
#   SELECT * FROM orders WHERE user_id = ?;  -- user 수만큼 반복 실행
# After (JOIN으로 한 번에):
#   SELECT u.*, o.* FROM users u LEFT JOIN orders o ON u.id = o.user_id;

# 3. 대용량 테이블 파티셔닝 검토
#   - 날짜 기반 데이터는 RANGE 파티셔닝
#   - 로그성 데이터는 오래된 파티션을 DROP하여 정리

# 4. 쿼리 캐시 또는 애플리케이션 레벨 캐시 도입
#   - 자주 조회되지만 변경이 적은 데이터는 Redis 등으로 캐싱
```

### 5.5 예방

```bash
# 1. slow_query_log 상시 활성화 (MySQL 설정 파일에 영구 적용)
# configs/mysql/my.cnf:
#   [mysqld]
#   slow_query_log = 1
#   slow_query_log_file = /var/lib/mysql/slow.log
#   long_query_time = 1
#   log_queries_not_using_indexes = 1

# 2. Prometheus + MySQL Exporter로 슬로우 쿼리 메트릭 수집
# docker-compose.yml에 mysqld-exporter 서비스 추가:
#   mysqld-exporter:
#     image: prom/mysqld-exporter:latest
#     container_name: mw-mysqld-exporter
#     environment:
#       DATA_SOURCE_NAME: "root:root_password@(mysql:3306)/"
#     ports:
#       - "9104:9104"
#     networks:
#       - mw-network

# 3. Grafana Alert: 슬로우 쿼리 수가 분당 10건 이상이면 경고
# alert_rules.yml:
#   - alert: MySQLSlowQueries
#     expr: rate(mysql_global_status_slow_queries[5m]) > 0.15
#     for: 5m
#     labels:
#       severity: warning
#     annotations:
#       summary: "MySQL 슬로우 쿼리 급증"

# 4. 배포 전 쿼리 리뷰 프로세스 수립
#    - 새로운 SQL이 포함된 PR은 EXPLAIN 결과를 첨부하도록 규칙화
#    - 100만 건 이상 테이블에 대한 쿼리는 DBA 리뷰 필수
```

---

## 6. Nginx 502/504 에러

### 6.1 증상

- **502 Bad Gateway**: Nginx가 upstream(Tomcat)으로부터 유효하지 않은 응답을 받았거나, upstream에 연결할 수 없는 경우 발생한다.
- **504 Gateway Timeout**: Nginx가 upstream으로부터 `proxy_read_timeout` 시간 내에 응답을 받지 못한 경우 발생한다.
- 사용자에게 Nginx 기본 에러 페이지가 표시된다.
- Grafana의 Nginx 대시보드에서 5xx 에러 카운트가 급증한다.
- nginx-exporter 메트릭에서 에러율이 증가한다.

### 6.2 확인 명령어

```bash
# 1. Nginx 에러 로그 확인
docker logs mw-nginx --since "10m" 2>&1 | grep -E "502|504|upstream|error"

# 또는 로그 파일 직접 확인
docker exec mw-nginx tail -100 /var/log/nginx/error.log

# 출력 예 (502):
#   upstream prematurely closed connection while reading response header from upstream
#   connect() failed (111: Connection refused) while connecting to upstream
#
# 출력 예 (504):
#   upstream timed out (110: Connection timed out) while reading response header from upstream

# 2. Nginx access.log에서 5xx 에러 빈도 확인
docker exec mw-nginx sh -c "awk '{print \$9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head"
# 출력 예:
#   15234  200
#    1523  502
#     234  504
#      12  404

# 3. upstream(Tomcat) 상태 확인
docker exec mw-nginx sh -c "curl -s -o /dev/null -w '%{http_code}' http://mw-tomcat1:8080/"
docker exec mw-nginx sh -c "curl -s -o /dev/null -w '%{http_code}' http://mw-tomcat2:8080/"
# 200이 아니면 해당 WAS에 문제 있음

# 4. 각 Tomcat 컨테이너 상태 확인
docker ps --filter "name=mw-tomcat" --format "table {{.Names}}\t{{.Status}}"
docker logs mw-tomcat1 --tail 30
docker logs mw-tomcat2 --tail 30

# 5. Nginx 설정 문법 검증
docker exec mw-nginx nginx -t

# 6. Nginx 현재 연결 상태 확인
curl -s http://localhost:80/stub_status
# 출력 예:
#   Active connections: 256
#   server accepts handled requests
#    12345 12345 67890
#   Reading: 5 Writing: 12 Waiting: 239
```

### 6.3 즉시 대응 (1분 이내)

```bash
# 1. 장애 WAS를 upstream에서 제외
# configs/nginx/conf.d/default.conf 수정:
#   upstream backend {
#       server mw-tomcat1:8080 down;    # 장애 발생 시 down 추가
#       server mw-tomcat2:8080;
#   }

# Nginx 설정 리로드 (무중단)
docker exec mw-nginx nginx -s reload

# 2. 장애 WAS 재시작
docker compose restart tomcat1

# 3. WAS 복구 확인 후 upstream 복구
docker exec mw-nginx sh -c "curl -s -o /dev/null -w '%{http_code}' http://mw-tomcat1:8080/"
# 200 확인 후 default.conf에서 down 제거
docker exec mw-nginx nginx -s reload
```

### 6.4 근본 해결

```bash
# 1. proxy_read_timeout 조정 (504 에러가 잦은 경우)
# configs/nginx/conf.d/default.conf:
#   location / {
#       proxy_pass http://backend;
#       proxy_connect_timeout 10s;     # upstream 연결 타임아웃
#       proxy_send_timeout 30s;        # 요청 전송 타임아웃
#       proxy_read_timeout 60s;        # 응답 대기 타임아웃 (기본 60s)
#       proxy_next_upstream error timeout http_502 http_503;  # 장애 시 다음 서버로 자동 전환
#       proxy_next_upstream_tries 2;   # 최대 재시도 횟수
#   }

# 2. upstream 헬스체크 설정 (Nginx Plus 또는 nginx_upstream_check_module)
# 오픈소스 Nginx에서는 passive health check 활용:
#   upstream backend {
#       server mw-tomcat1:8080 max_fails=3 fail_timeout=30s;
#       server mw-tomcat2:8080 max_fails=3 fail_timeout=30s;
#   }
#   # 30초 내 3번 실패하면 해당 서버를 30초간 비활성화

# 3. WAS 성능 개선
#    - Tomcat의 maxThreads 조정 (기본 200, 필요 시 증가)
#    - GC 최적화 (4장 참고)
#    - 커넥션 풀 최적화 (3장 참고)
#    - 슬로우 쿼리 최적화 (5장 참고)

# 4. Nginx worker 설정 최적화
# configs/nginx/nginx.conf:
#   worker_processes auto;                    # CPU 코어 수에 맞게 자동 설정
#   worker_connections 1024;                  # worker당 최대 연결 수
#   keepalive_timeout 65;                     # keepalive 타임아웃
#
#   upstream backend {
#       keepalive 32;                         # upstream keepalive 연결 수
#       server mw-tomcat1:8080;
#       server mw-tomcat2:8080;
#   }
```

### 6.5 예방

```bash
# 1. Prometheus + nginx-exporter Alert 설정
# 이 프로젝트에서는 이미 mw-nginx-exporter가 구성되어 있음
# alert_rules.yml:
#   - alert: NginxHighErrorRate
#     expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) > 0.05
#     for: 2m
#     labels:
#       severity: critical
#     annotations:
#       summary: "Nginx 5xx 에러율 5% 초과"

# 2. Grafana 대시보드에 HTTP 상태 코드별 요청 수 패널 추가
#    - nginx_http_requests_total 메트릭 활용
#    - 200, 4xx, 5xx 별도 시각화

# 3. Nginx 접근 로그에 upstream 응답 시간 기록
# configs/nginx/nginx.conf의 log_format에 추가:
#   log_format main '$remote_addr - $remote_user [$time_local] '
#                   '"$request" $status $body_bytes_sent '
#                   '"$http_referer" "$http_user_agent" '
#                   'upstream_response_time=$upstream_response_time '
#                   'request_time=$request_time';
```

---

## 7. SSL 인증서 만료

### 7.1 증상

- 브라우저에서 `ERR_CERT_DATE_INVALID` 또는 `NET::ERR_CERT_AUTHORITY_INVALID` 에러가 표시된다.
- HTTPS 접속이 완전히 불가능하거나, 브라우저가 보안 경고를 표시한다.
- API 클라이언트에서 `SSL certificate problem: certificate has expired` 에러가 발생한다.
- 모바일 앱 등 인증서 에러를 무시할 수 없는 클라이언트에서 서비스 접근 불가.

### 7.2 확인 명령어

```bash
# 1. 인증서 만료일 확인 (외부에서)
echo | openssl s_client -servername localhost -connect localhost:443 2>/dev/null | \
  openssl x509 -noout -dates
# 출력 예:
#   notBefore=Jan 15 00:00:00 2024 GMT
#   notAfter=Apr 15 23:59:59 2024 GMT

# 2. 인증서 상세 정보 확인
echo | openssl s_client -servername localhost -connect localhost:443 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates

# 3. Nginx 컨테이너 내부에서 인증서 파일 직접 확인
docker exec mw-nginx openssl x509 -in /etc/nginx/ssl/server.crt -noout -dates

# 4. 인증서 만료까지 남은 일수 계산
docker exec mw-nginx sh -c "
  expiry=\$(openssl x509 -in /etc/nginx/ssl/server.crt -noout -enddate | cut -d= -f2)
  expiry_epoch=\$(date -d \"\$expiry\" +%s 2>/dev/null || date -jf '%b %d %T %Y %Z' \"\$expiry\" +%s)
  now_epoch=\$(date +%s)
  days_left=\$(( (expiry_epoch - now_epoch) / 86400 ))
  echo \"인증서 만료까지 남은 일수: \$days_left일\"
"

# 5. 인증서 체인 검증
echo | openssl s_client -servername localhost -connect localhost:443 2>&1 | \
  grep -E "Verify|depth|Certificate chain"
```

### 7.3 즉시 대응 (1분 이내)

```bash
# 1. Let's Encrypt 인증서 사용 시 수동 갱신
# certbot이 설치된 환경:
certbot renew --force-renewal

# 2. 갱신된 인증서를 Nginx 컨테이너에 적용
docker cp /etc/letsencrypt/live/yourdomain/fullchain.pem mw-nginx:/etc/nginx/ssl/server.crt
docker cp /etc/letsencrypt/live/yourdomain/privkey.pem mw-nginx:/etc/nginx/ssl/server.key

# 3. Nginx 리로드 (무중단 적용)
docker exec mw-nginx nginx -s reload

# 4. 적용 확인
echo | openssl s_client -servername localhost -connect localhost:443 2>/dev/null | \
  openssl x509 -noout -dates

# 5. 자체 서명 인증서로 긴급 대응 (개발/스테이징 환경 한정)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ./configs/nginx/ssl/server.key \
  -out ./configs/nginx/ssl/server.crt \
  -subj "/CN=localhost"
docker exec mw-nginx nginx -s reload
```

### 7.4 예방

```bash
# 1. 인증서 만료 30일 전 Alert 스크립트 (cron에 등록)
# scripts/check_ssl_expiry.sh:
#!/bin/bash
DOMAIN="yourdomain.com"
DAYS_THRESHOLD=30
EXPIRY=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | \
  openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
if [ $DAYS_LEFT -lt $DAYS_THRESHOLD ]; then
  echo "WARNING: SSL 인증서가 ${DAYS_LEFT}일 후 만료됩니다!" | \
    # Slack webhook 또는 이메일로 알림 발송
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"SSL 인증서 만료 경고: ${DAYS_LEFT}일 남음\"}" \
      https://hooks.slack.com/services/YOUR/WEBHOOK/URL
fi

# crontab 등록 (매일 09:00 실행):
#   0 9 * * * /path/to/scripts/check_ssl_expiry.sh

# 2. Prometheus blackbox_exporter로 SSL 만료 모니터링
# docker-compose.yml에 추가:
#   blackbox-exporter:
#     image: prom/blackbox-exporter:latest
#     container_name: mw-blackbox-exporter
#     ports:
#       - "9115:9115"
#     networks:
#       - mw-network

# prometheus.yml에 추가:
#   - job_name: 'ssl-check'
#     metrics_path: /probe
#     params:
#       module: [http_2xx]
#     static_configs:
#       - targets: ['https://yourdomain.com']
#     relabel_configs:
#       - source_labels: [__address__]
#         target_label: __param_target
#       - target_label: __address__
#         replacement: blackbox-exporter:9115

# Alert 설정:
#   - alert: SSLCertExpiringSoon
#     expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 30
#     for: 1h
#     labels:
#       severity: warning
#     annotations:
#       summary: "SSL 인증서 만료 30일 이내 ({{ $labels.instance }})"

# 3. Let's Encrypt 자동 갱신 설정
#    certbot renew는 기본적으로 만료 30일 전부터 갱신 시도
#    crontab: 0 3 * * * certbot renew --quiet --deploy-hook "docker exec mw-nginx nginx -s reload"
```

---

## 8. Keycloak 장애 (SSO 로그인 불가)

### 8.1 증상

- 사용자가 로그인 페이지에 접근할 수 없다. (`localhost:8080` 응답 없음)
- 로그인 시도 후 302 리다이렉트가 실패하며, `ERR_CONNECTION_REFUSED` 또는 무한 리다이렉트가 발생한다.
- 이미 로그인된 사용자의 세션은 유지되지만, 새로운 로그인이 불가능하다.
- SSO로 연동된 다른 서비스(Grafana 등)에서도 로그인이 실패한다.
- Keycloak 컨테이너가 `Exited` 상태이거나 `Starting` 상태에서 멈춰 있다.

### 8.2 확인 명령어

```bash
# 1. Keycloak 컨테이너 상태 확인
docker ps -a --filter "name=mw-keycloak" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 2. Keycloak 로그 확인
docker logs mw-keycloak --tail 100

# 출력에서 주의할 에러:
#   - "Failed to connect to database" -> DB 연결 문제
#   - "java.net.ConnectException" -> 네트워크 문제
#   - "Realm 'xxxx' not found" -> Realm 설정 문제
#   - "java.lang.OutOfMemoryError" -> 메모리 부족

# 3. Keycloak Health Check (내부 헬스체크 엔드포인트)
curl -s http://localhost:8080/health | python3 -m json.tool
curl -s http://localhost:8080/health/ready | python3 -m json.tool
# status: "UP"이면 정상

# 4. Keycloak Admin Console 접근 테스트
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/admin/

# 5. Realm 설정 확인 (Admin REST API)
# 먼저 토큰 획득:
TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Realm 목록 확인:
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/admin/realms | python3 -m json.tool

# 6. Keycloak 내부 DB 상태 확인 (H2 내장 DB 사용 시)
docker exec mw-keycloak ls -la /opt/keycloak/data/

# 7. Keycloak가 사용하는 포트 충돌 확인
docker port mw-keycloak
# 주의: Keycloak(8080)과 Tomcat이 동일 포트를 사용하지 않도록 확인
# 이 프로젝트에서 Keycloak은 호스트 8080, Tomcat은 내부 네트워크에서만 8080 사용
```

### 8.3 즉시 대응 (1분 이내)

```bash
# 1. Keycloak 컨테이너 재시작
docker compose restart keycloak

# 2. 재시작 후 헬스체크 (시작까지 30~60초 소요)
sleep 30
curl -s http://localhost:8080/health/ready

# 3. Realm 가져오기가 실패한 경우, 수동으로 Realm 임포트
docker exec mw-keycloak /opt/keycloak/bin/kc.sh import --file /opt/keycloak/data/import/realm-export.json

# 4. Keycloak이 완전히 손상된 경우, 볼륨 초기화 후 재생성
# 주의: 기존 사용자 데이터가 모두 삭제됨!
# docker compose down keycloak
# docker volume rm middle_ware_keycloak_data
# docker compose up -d keycloak
```

### 8.4 근본 해결

```bash
# 1. Keycloak 전용 외부 DB 연결 (H2 대신 MySQL 사용)
# docker-compose.yml의 keycloak 서비스에 환경변수 추가:
#   environment:
#     KC_DB: mysql
#     KC_DB_URL: jdbc:mysql://mysql:3306/keycloak_db
#     KC_DB_USERNAME: keycloak_user
#     KC_DB_PASSWORD: keycloak_password
#   command:
#     - start-dev
#     - --import-realm
#     - --db=mysql

# MySQL에 Keycloak DB 생성:
docker exec mw-mysql mysql -uroot -proot_password -e \
  "CREATE DATABASE IF NOT EXISTS keycloak_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER IF NOT EXISTS 'keycloak_user'@'%' IDENTIFIED BY 'keycloak_password';
   GRANT ALL PRIVILEGES ON keycloak_db.* TO 'keycloak_user'@'%';
   FLUSH PRIVILEGES;"

# 2. Keycloak JVM 메모리 설정 (docker-compose.yml)
#   environment:
#     JAVA_OPTS_APPEND: "-Xms256m -Xmx512m"

# 3. Keycloak 세션 타임아웃 조정
#    Admin Console > Realm Settings > Sessions
#    - SSO Session Idle: 30분 (기본)
#    - SSO Session Max: 10시간 (기본)
```

### 8.5 예방

```bash
# 1. Keycloak Health Check를 Prometheus로 수집
# prometheus.yml에 추가:
#   - job_name: 'keycloak'
#     metrics_path: /health
#     static_configs:
#       - targets: ['keycloak:8080']

# 2. Docker Compose에 healthcheck 추가
# docker-compose.yml의 keycloak 서비스:
#   healthcheck:
#     test: ["CMD", "curl", "-f", "http://localhost:8080/health/ready"]
#     interval: 30s
#     timeout: 10s
#     retries: 3
#     start_period: 60s

# 3. Realm 설정 백업 자동화 스크립트
# scripts/backup_keycloak.sh:
#!/bin/bash
BACKUP_DIR="./backups/keycloak"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

# Admin 토큰 획득
TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=admin&grant_type=password&client_id=admin-cli" | \
  python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Realm Export
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/admin/realms/middleware-realm" > \
  "$BACKUP_DIR/realm_backup_$TIMESTAMP.json"

echo "Keycloak Realm 백업 완료: $BACKUP_DIR/realm_backup_$TIMESTAMP.json"

# crontab: 0 2 * * * /path/to/scripts/backup_keycloak.sh
```

---

## 9. Docker 디스크 풀

### 9.1 증상

- 컨테이너 시작 시 `no space left on device` 에러가 발생한다.
- `docker compose up`이 실패하며, 이미지 빌드도 불가능해진다.
- 실행 중인 컨테이너에서 로그 기록이 중단된다.
- MySQL이 `Table is full` 에러와 함께 쓰기 작업을 거부한다.
- Prometheus 데이터 수집이 중단된다.

### 9.2 확인 명령어

```bash
# 1. 호스트 디스크 사용량 확인
df -h
# /var/lib/docker가 위치한 파티션의 사용률 확인
# Use%가 90% 이상이면 위험

# 2. Docker가 사용하는 디스크 공간 상세 확인
docker system df
# 출력 예:
#   TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
#   Images          15        8         5.2GB     2.1GB (40%)
#   Containers      12        10        1.8GB     200MB (11%)
#   Local Volumes   8         8         12.3GB    0B (0%)
#   Build Cache     0         0         2.5GB     2.5GB

# 더 상세한 정보:
docker system df -v

# 3. 각 컨테이너의 로그 파일 크기 확인
for c in $(docker ps -q); do
  name=$(docker inspect --format='{{.Name}}' $c | sed 's/\///')
  log_path=$(docker inspect --format='{{.LogPath}}' $c)
  size=$(ls -lh "$log_path" 2>/dev/null | awk '{print $5}')
  echo "$name: $size ($log_path)"
done

# 4. 볼륨별 사용량 확인
docker system df -v | grep -A 100 "VOLUME NAME"

# 5. 사용하지 않는(댕글링) 이미지 확인
docker images -f "dangling=true"

# 6. 중지된 컨테이너 확인
docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}\t{{.Size}}"
```

### 9.3 즉시 대응 (1분 이내)

```bash
# 1. 사용하지 않는 리소스 정리 (안전한 정리)
# 중지된 컨테이너, 사용하지 않는 네트워크, 댕글링 이미지 제거
docker system prune -f
# 주의: 실행 중인 컨테이너와 사용 중인 이미지/볼륨은 삭제되지 않음

# 2. 댕글링 이미지뿐 아니라 사용하지 않는 모든 이미지 제거 (더 공격적)
docker image prune -a -f

# 3. 특정 컨테이너 로그 즉시 비우기
# truncate는 파일을 비우지만 inode를 유지하여 Docker가 계속 로그를 쓸 수 있음
truncate -s 0 $(docker inspect --format='{{.LogPath}}' mw-tomcat1)
truncate -s 0 $(docker inspect --format='{{.LogPath}}' mw-tomcat2)
truncate -s 0 $(docker inspect --format='{{.LogPath}}' mw-nginx)

# 4. 빌드 캐시 정리
docker builder prune -f

# 5. 정리 후 확인
df -h
docker system df
```

### 9.4 근본 해결

```bash
# 1. Docker 로그 로테이션 설정 (모든 컨테이너에 적용)
# /etc/docker/daemon.json 생성 또는 수정:
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
# 적용: sudo systemctl restart docker
# 주의: 이 설정은 새로 생성되는 컨테이너에만 적용됨
#        기존 컨테이너는 재생성 필요 (docker compose up -d --force-recreate)

# 2. docker-compose.yml에서 서비스별 로그 설정 (더 세밀한 제어)
# 각 서비스에 추가:
#   logging:
#     driver: json-file
#     options:
#       max-size: "10m"
#       max-file: "3"

# 3. Prometheus 데이터 보존 기간 조정
# 현재 설정: --storage.tsdb.retention.time=15d
# 디스크가 부족하면 줄일 수 있음: --storage.tsdb.retention.time=7d
# 또는 크기 기반: --storage.tsdb.retention.size=5GB

# 4. MySQL 바이너리 로그 정리
docker exec mw-mysql mysql -uroot -proot_password -e \
  "PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 3 DAY);"

# 5. 사용하지 않는 볼륨 정리
docker volume ls -f dangling=true
docker volume prune -f
# 주의: 볼륨 삭제는 데이터 손실! 반드시 확인 후 실행
```

### 9.5 예방

```bash
# 1. 디스크 사용률 모니터링 Alert
# 이 프로젝트에서 mw-node-exporter가 이미 구성되어 있으므로 활용
# alert_rules.yml:
#   - alert: HostHighDiskUsage
#     expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 0.85
#     for: 5m
#     labels:
#       severity: warning
#     annotations:
#       summary: "디스크 사용률 85% 초과 ({{ $labels.instance }})"
#
#   - alert: HostDiskAlmostFull
#     expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 0.95
#     for: 1m
#     labels:
#       severity: critical
#     annotations:
#       summary: "디스크 사용률 95% 초과! 즉시 조치 필요 ({{ $labels.instance }})"

# 2. 주간 자동 정리 cron 등록
# crontab:
#   0 3 * * 0 docker system prune -f >> /var/log/docker_cleanup.log 2>&1
#   0 3 * * 0 docker image prune -a -f >> /var/log/docker_cleanup.log 2>&1

# 3. Grafana 대시보드에 디스크 사용량 패널 추가
#    - node_filesystem_avail_bytes 메트릭 활용
#    - 파티션별 사용량 시각화

# 4. MySQL 데이터 디렉토리를 별도 볼륨/파티션으로 분리
#    데이터가 가장 빠르게 증가하는 서비스이므로 분리 관리 권장
```

---

## 10. 장애 보고서 작성법

### 10.1 장애 보고서 템플릿

```markdown
# 장애 보고서

## 기본 정보
| 항목 | 내용 |
|------|------|
| 장애 등급 | P1 / P2 / P3 / P4 |
| 발생 일시 | YYYY-MM-DD HH:MM:SS |
| 복구 일시 | YYYY-MM-DD HH:MM:SS |
| 총 장애 시간 | X시간 Y분 |
| 영향 범위 | (예: 전체 서비스 접근 불가 / 로그인 기능 장애 등) |
| 영향 사용자 수 | 약 N명 |
| 작성자 | 홍길동 |
| 작성일 | YYYY-MM-DD |

## 장애 요약
(1~2문장으로 장애 현상과 원인을 요약)

## 타임라인
| 시각 | 이벤트 | 조치 사항 |
|------|--------|-----------|
| HH:MM | 장애 감지 (Grafana Alert 수신) | 당번 엔지니어 확인 시작 |
| HH:MM | 1차 원인 파악 (OOM Kill 확인) | 컨테이너 재시작 |
| HH:MM | 서비스 복구 확인 | 모니터링 강화 |
| HH:MM | 근본 원인 분석 완료 | JVM 힙 사이즈 조정 적용 |
| HH:MM | 최종 복구 확인 | 장애 종료 선언 |

## 원인 분석

### 직접 원인 (Direct Cause)
(장애를 직접적으로 발생시킨 원인)

### 근본 원인 (Root Cause)
(직접 원인이 발생하게 된 근본적인 이유)

### 기여 요인 (Contributing Factors)
(장애 감지나 복구를 지연시킨 요인)

## 영향 분석
- 서비스 영향: (어떤 기능이 얼마나 영향받았는지)
- 비즈니스 영향: (매출 손실, SLA 위반 여부 등)
- 데이터 영향: (데이터 유실 여부)

## 복구 조치
1. (복구를 위해 수행한 조치 1)
2. (복구를 위해 수행한 조치 2)

## 재발 방지 대책
| 번호 | 대책 | 담당자 | 완료 예정일 | 우선순위 |
|------|------|--------|------------|---------|
| 1 | (예: JVM 힙 사이즈 1GB로 증가) | 홍길동 | YYYY-MM-DD | 높음 |
| 2 | (예: OOM Alert 설정 추가) | 김철수 | YYYY-MM-DD | 중간 |
| 3 | (예: 메모리 누수 코드 수정) | 이영희 | YYYY-MM-DD | 높음 |

## 교훈 (Lessons Learned)
- 잘한 점: (빠르게 감지했다, 팀 협업이 원활했다 등)
- 개선할 점: (모니터링이 부족했다, 문서가 없었다 등)
```

### 10.2 실제 장애 보고서 예시

```markdown
# 장애 보고서

## 기본 정보
| 항목 | 내용 |
|------|------|
| 장애 등급 | P2 |
| 발생 일시 | 2026-02-20 14:32:00 |
| 복구 일시 | 2026-02-20 15:15:00 |
| 총 장애 시간 | 43분 |
| 영향 범위 | mw-tomcat1 서비스 중단, 전체 응답 지연 |
| 영향 사용자 수 | 약 200명 |
| 작성자 | 이연우 |
| 작성일 | 2026-02-21 |

## 장애 요약
mw-tomcat1 컨테이너에서 OOM Kill이 발생하여 WAS가 중단되었으며,
Nginx의 로드밸런싱으로 mw-tomcat2에 트래픽이 집중되면서 전체 응답 지연이 발생했다.
근본 원인은 대량 데이터 조회 API에서 페이지네이션 없이 전체 결과를 메모리에 로딩하는 코드였다.

## 타임라인
| 시각 | 이벤트 | 조치 사항 |
|------|--------|-----------|
| 14:32 | Grafana "ContainerHighMemory" Alert 수신 | 당번 엔지니어 확인 시작 |
| 14:34 | mw-tomcat1 컨테이너 Exited(137) 확인 | OOM Kill 판단 |
| 14:35 | mw-tomcat1 재시작 시도 | `docker compose restart tomcat1` |
| 14:37 | mw-tomcat1 정상 기동 확인 | Scouter에서 인스턴스 확인 |
| 14:42 | 동일 API 호출로 다시 메모리 급증 시작 | 해당 API 확인 중 |
| 14:50 | 원인 API 식별 (/api/reports/export) | 해당 API 임시 차단 (Nginx에서 return 503) |
| 14:55 | mw-tomcat1 메모리 안정화 확인 | API 차단 유지 |
| 15:00 | 개발팀에 핫픽스 요청 | 페이지네이션 + 스트리밍 처리 적용 |
| 15:10 | 핫픽스 배포 완료 | 새 이미지로 컨테이너 재생성 |
| 15:15 | 정상 동작 확인, API 차단 해제 | 장애 종료 선언 |

## 원인 분석

### 직접 원인 (Direct Cause)
`/api/reports/export` API가 30만 건의 보고서 데이터를 한 번에 메모리에 로딩하면서
JVM 힙 메모리(512MB)를 초과하여 OOM Kill이 발생했다.

### 근본 원인 (Root Cause)
해당 API가 `SELECT * FROM reports`로 전체 데이터를 조회한 뒤
List<Report>에 담아 CSV로 변환하는 방식으로 구현되어 있었다.
데이터 증가에 따른 메모리 사용량 검증이 누락되었다.

### 기여 요인 (Contributing Factors)
- JVM 힙 사이즈가 512MB로 프로덕션 환경 대비 낮게 설정되어 있었다.
- HeapDumpOnOutOfMemoryError 옵션이 설정되지 않아 초기 분석이 지연되었다.
- 해당 API에 대한 부하 테스트가 수행되지 않았다.

## 영향 분석
- 서비스 영향: mw-tomcat1 중단 8분, 전체 응답 지연 약 35분
- 비즈니스 영향: SLA(99.9%) 기준 월간 허용 다운타임 43분 중 8분 소진
- 데이터 영향: 없음

## 복구 조치
1. mw-tomcat1 컨테이너 재시작
2. 문제 API Nginx에서 임시 차단
3. 페이지네이션 + 스트리밍 방식으로 핫픽스 배포

## 재발 방지 대책
| 번호 | 대책 | 담당자 | 완료 예정일 | 우선순위 |
|------|------|--------|------------|---------|
| 1 | JVM 힙 사이즈 1GB로 증가 | 이연우 | 2026-02-22 | 높음 |
| 2 | HeapDumpOnOutOfMemoryError 옵션 추가 | 이연우 | 2026-02-22 | 높음 |
| 3 | 대량 데이터 조회 API 전수 점검 | 김개발 | 2026-03-01 | 높음 |
| 4 | OOM 관련 Grafana Alert 임계치 세분화 | 박운영 | 2026-02-28 | 중간 |
| 5 | 대량 데이터 API 부하 테스트 시나리오 추가 | QA팀 | 2026-03-07 | 중간 |

## 교훈 (Lessons Learned)
- 잘한 점: Grafana Alert 덕분에 2분 이내에 감지할 수 있었다. Nginx 로드밸런싱으로 완전 중단은 방지되었다.
- 개선할 점: HeapDump 설정이 없어 OOM 원인 분석에 시간이 걸렸다. 데이터 증가에 따른 성능 영향을 정기적으로 점검하는 프로세스가 필요하다.
```

---

## 부록: 유용한 명령어 모음

### 전체 시스템 상태 한눈에 보기

```bash
# 모든 컨테이너 상태 + 리소스 사용량
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"

# 컨테이너별 재시작 횟수 확인 (재시작이 반복되면 문제 징후)
docker inspect --format='{{.Name}}: RestartCount={{.RestartCount}}' $(docker ps -aq) 2>/dev/null

# Docker 이벤트 실시간 모니터링 (컨테이너 시작/중지/OOM 이벤트)
docker events --since "1h" --filter "type=container"

# 네트워크 상태 확인
docker network inspect mw-network --format='{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'
```

### 로그 수집 스크립트

```bash
#!/bin/bash
# scripts/collect_logs.sh
# 장애 발생 시 관련 로그를 일괄 수집하는 스크립트

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="./logs/incident_${TIMESTAMP}"
mkdir -p "$LOG_DIR"

echo "=== 장애 로그 수집 시작: $TIMESTAMP ==="

# 1. 컨테이너 상태
docker ps -a > "$LOG_DIR/docker_ps.txt"
docker stats --no-stream > "$LOG_DIR/docker_stats.txt"
docker system df -v > "$LOG_DIR/docker_disk.txt"

# 2. 각 서비스 로그
for service in mw-nginx mw-tomcat1 mw-tomcat2 mw-mysql mw-keycloak mw-scouter mw-prometheus mw-grafana; do
  docker logs "$service" --since "1h" > "$LOG_DIR/${service}.log" 2>&1
done

# 3. 호스트 정보
df -h > "$LOG_DIR/disk_usage.txt"
free -h > "$LOG_DIR/memory_usage.txt" 2>/dev/null || vm_stat > "$LOG_DIR/memory_usage.txt"
dmesg | tail -100 > "$LOG_DIR/dmesg.txt" 2>/dev/null

# 4. JVM 상태 (Tomcat)
for tc in mw-tomcat1 mw-tomcat2; do
  docker exec "$tc" jstat -gcutil $(docker exec "$tc" pgrep java) 1000 5 > "$LOG_DIR/${tc}_gc.txt" 2>&1
done

echo "=== 로그 수집 완료: $LOG_DIR ==="
ls -la "$LOG_DIR"
```

### 긴급 복구 체크리스트

```
[ ] 장애 등급 판단 (P1~P4)
[ ] 장애 채널에 최초 보고
[ ] 전체 컨테이너 상태 확인 (docker ps -a)
[ ] 장애 컨테이너 로그 확인 (docker logs)
[ ] 1차 복구 시도 (재시작 또는 트래픽 우회)
[ ] 서비스 정상화 확인
[ ] 모니터링 지표 안정화 확인 (Grafana, Scouter)
[ ] 팀 보고 완료
[ ] 장애 보고서 작성 (복구 후 1일 이내)
[ ] Post-mortem 미팅 일정 잡기
[ ] 재발 방지 대책 티켓 등록
```
