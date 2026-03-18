# 모니터링 지표 및 Alert 설정 가이드

> 본 문서는 Nginx + Tomcat(x2) + MySQL + Scouter APM + Prometheus + Grafana + Keycloak 기반 미들웨어 환경에서의 모니터링 지표 정의, Alert 규칙 설정, 대시보드 설계를 다룬다.
> **대상 독자**: 미들웨어 모니터링을 학습하려는 엔지니어 (초보자도 [사용자 가이드](user-guide.md) 5~6장을 먼저 실습한 뒤 읽으면 따라갈 수 있다)

---

## 목차

1. [Four Golden Signals (구글 SRE 기반)](#1-four-golden-signals-구글-sre-기반)
2. [SLI / SLO / SLA 정의](#2-sli--slo--sla-정의)
3. [핵심 모니터링 지표 상세](#3-핵심-모니터링-지표-상세)
4. [Prometheus Alert Rules 설정](#4-prometheus-alert-rules-설정)
5. [Grafana 대시보드 설계](#5-grafana-대시보드-설계)
6. [PromQL 실전 쿼리 모음](#6-promql-실전-쿼리-모음)
7. [로그 모니터링](#7-로그-모니터링)
8. [모니터링 체크리스트](#8-모니터링-체크리스트)

---

## 1. Four Golden Signals (구글 SRE 기반)

구글 SRE 팀이 정의한 4가지 핵심 시그널은 분산 시스템 모니터링의 기본 프레임워크다.
어떤 시스템이든 이 4가지만 잘 추적하면 대부분의 장애를 조기에 감지할 수 있다.

### 1.1 Latency (지연 시간)

**정의**: 요청을 처리하는 데 걸리는 시간. 성공 요청과 실패 요청의 지연 시간을 분리해서 측정해야 한다.

**왜 분리해야 하는가**: 에러 응답(예: 500)은 대부분 매우 빠르게 반환된다. 에러 응답을 포함하면 전체 평균 latency가 낮게 왜곡되어 실제 사용자 경험을 반영하지 못한다.

**측정 방법 (본 프로젝트)**:
- Nginx: `nginx_http_request_duration_seconds` (nginx-exporter)
- Tomcat/Spring Boot: `http_server_requests_seconds` (Actuator/Prometheus)
- Scouter: XLog의 응답시간 분포

**정상 기준**:
| 구간 | 기준 |
|------|------|
| 정상 | p95 < 500ms |
| 경고 | p95 500ms ~ 1s |
| 위험 | p95 > 1s |

**PromQL 예시**:
```promql
# Tomcat 응답 시간 p95 (성공 요청만)
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket{status=~"2.."}[5m])) by (le)
)

# Tomcat 응답 시간 p99
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket{status=~"2.."}[5m])) by (le)
)

# 인스턴스별 평균 응답 시간
rate(http_server_requests_seconds_sum{status=~"2.."}[5m])
/
rate(http_server_requests_seconds_count{status=~"2.."}[5m])
```

### 1.2 Traffic (트래픽)

**정의**: 시스템에 들어오는 요청의 양. HTTP 서비스에서는 초당 요청 수(RPS)로 측정한다.

**측정 방법**:
- Nginx: `nginx_http_requests_total` (nginx-exporter)
- Tomcat: `http_server_requests_seconds_count` (Actuator)

**정상 기준**: 서비스마다 다르지만, 갑작스러운 spike(평소 대비 3배 이상) 또는 급격한 drop(평소 대비 50% 이하)은 이상 징후다.

**PromQL 예시**:
```promql
# Nginx 전체 RPS
rate(nginx_http_requests_total[5m])

# Tomcat 인스턴스별 RPS
sum by (instance) (
  rate(http_server_requests_seconds_count[5m])
)

# 전체 Tomcat RPS 합계
sum(rate(http_server_requests_seconds_count[5m]))

# 트래픽 급증 감지 (현재 vs 1시간 전 대비 3배 이상)
rate(nginx_http_requests_total[5m])
>
3 * rate(nginx_http_requests_total[5m] offset 1h)
```

### 1.3 Errors (에러율)

**정의**: 실패한 요청의 비율. 명시적 에러(HTTP 5xx)와 암묵적 에러(정상 응답이지만 내용이 잘못된 경우) 모두 포함한다.

**측정 방법**:
- Nginx: HTTP 상태코드 기반 (5xx / 전체)
- Tomcat: `http_server_requests_seconds_count{status=~"5.."}` / 전체

**정상 기준**:
| 구간 | 기준 |
|------|------|
| 정상 | 에러율 < 1% |
| 경고 | 에러율 1% ~ 5% |
| 위험 | 에러율 > 5% |

**PromQL 예시**:
```promql
# Tomcat 5xx 에러율 (%)
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
/
sum(rate(http_server_requests_seconds_count[5m]))
* 100

# Nginx 기반 에러율 (nginx-exporter는 status별 메트릭이 제한적이므로
# Tomcat Actuator 메트릭을 주로 사용한다)

# 4xx 에러율 (클라이언트 에러)
sum(rate(http_server_requests_seconds_count{status=~"4.."}[5m]))
/
sum(rate(http_server_requests_seconds_count[5m]))
* 100
```

### 1.4 Saturation (포화도)

**정의**: 시스템 리소스가 얼마나 가득 찼는지를 나타내는 지표. CPU, 메모리, 디스크, 네트워크, 커넥션 풀 등의 사용률이 해당한다.

**핵심 포인트**: 대부분의 시스템은 100% saturation 이전에 성능이 급격히 저하된다. CPU 80%, 메모리 85%를 임계점으로 보는 것이 일반적이다.

**측정 방법**:
- Node Exporter: CPU, 메모리, 디스크 사용률
- JVM: Heap 사용률, Thread pool 포화도
- MySQL: Connection 사용률

**PromQL 예시**:
```promql
# CPU 포화도 (1 - idle)
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))

# 메모리 포화도
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# JVM Heap 포화도
jvm_memory_used_bytes{area="heap"}
/
jvm_memory_max_bytes{area="heap"}

# MySQL Connection 포화도
mysql_global_status_threads_connected
/
mysql_global_variables_max_connections
```

---

## 2. SLI / SLO / SLA 정의

### 2.1 SLI (Service Level Indicator)

**정의**: 서비스 수준을 측정하는 구체적인 정량 지표. "무엇을 측정할 것인가"에 대한 답이다.

좋은 SLI는 사용자 경험과 직결되어야 한다. 내부 시스템 지표(CPU 사용률 등)보다는 사용자가 체감하는 지표(응답 시간, 에러율)가 더 적합하다.

**본 프로젝트의 SLI 예시**:

| SLI | 측정 방법 | 데이터 소스 |
|-----|-----------|-------------|
| 가용성 | 성공 응답(2xx+3xx) / 전체 응답 | Tomcat Actuator |
| 응답 지연 | HTTP 요청 p95 응답 시간 | Tomcat Actuator |
| 처리량 | 초당 성공 처리 요청 수 | Nginx Exporter |
| 에러율 | 5xx 응답 / 전체 응답 | Tomcat Actuator |

### 2.2 SLO (Service Level Objective)

**정의**: SLI에 대한 목표값. "얼마나 좋아야 하는가"에 대한 답이다.

SLO는 100%를 목표로 잡으면 안 된다. 100% 가용성 = 변경 불가 = 혁신 불가다. 적절한 수준의 SLO를 설정하고 Error Budget을 운용하는 것이 핵심이다.

**본 프로젝트의 SLO 예시**:

| SLI | SLO 목표 | 허용 다운타임 |
|-----|----------|---------------|
| 가용성 | 99.9% | 연 8.76시간 / 월 43.8분 |
| 응답 지연 (p95) | < 500ms | - |
| 응답 지연 (p99) | < 1s | - |
| 에러율 | < 0.1% | - |

**SLO 수준별 허용 다운타임 비교**:

| SLO | 연간 다운타임 | 월간 다운타임 | 일간 다운타임 |
|-----|---------------|---------------|---------------|
| 99% | 3.65일 | 7.31시간 | 14.4분 |
| 99.5% | 1.83일 | 3.65시간 | 7.2분 |
| 99.9% | 8.76시간 | 43.8분 | 1.44분 |
| 99.95% | 4.38시간 | 21.9분 | 43.2초 |
| 99.99% | 52.6분 | 4.38분 | 8.64초 |

### 2.3 SLA (Service Level Agreement)

**정의**: SLO를 기반으로 고객과 맺는 계약. SLO를 위반하면 금전적 보상(크레딧, 환불)이 따른다.

**SLO vs SLA의 핵심 차이**:
- SLO는 내부 목표이고, SLA는 외부 계약이다.
- SLA는 반드시 SLO보다 느슨하게 설정한다 (예: SLO 99.95% -> SLA 99.9%).
- SLO 위반은 내부 경보, SLA 위반은 비즈니스 리스크다.

### 2.4 Error Budget 개념과 활용법

**정의**: SLO 목표에서 허용되는 실패의 양. `Error Budget = 1 - SLO`

**예시**: SLO 99.9%인 경우
- Error Budget = 0.1%
- 월간 총 요청이 100만 건이면, 1,000건까지 실패 허용
- 시간 기준으로는 월 43.8분 다운타임 허용

**Error Budget 활용 정책**:
1. Error Budget이 남아 있으면: 새로운 기능 배포, 리팩터링, 인프라 변경 가능
2. Error Budget이 소진되면: 신규 배포 동결, 안정화 작업에 집중
3. Error Budget 소진 속도를 모니터링하여 의사결정 근거로 활용

**PromQL로 Error Budget 추적**:
```promql
# 월간 가용성 (30일 기준)
1 - (
  sum(increase(http_server_requests_seconds_count{status=~"5.."}[30d]))
  /
  sum(increase(http_server_requests_seconds_count[30d]))
)

# 남은 Error Budget (%) - SLO 99.9% 기준
(
  1 - (
    sum(increase(http_server_requests_seconds_count{status=~"5.."}[30d]))
    /
    sum(increase(http_server_requests_seconds_count[30d]))
  )
  - 0.999
) / 0.001 * 100
```

---

## 3. 핵심 모니터링 지표 상세

> 본 프로젝트의 Prometheus scrape 대상:
> - `node-exporter:9100` (시스템 리소스)
> - `nginx-exporter:9113` (Nginx stub_status)
> - `tomcat1:8080/actuator/prometheus` (Tomcat #1 JVM/HTTP 메트릭)
> - `tomcat2:8080/actuator/prometheus` (Tomcat #2 JVM/HTTP 메트릭)
> - `localhost:9090` (Prometheus 자체)

### 3.1 시스템 레벨 (Node Exporter)

#### CPU 사용률

```promql
# 전체 CPU 사용률 (%)
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)) * 100

# CPU 모드별 분포 (user, system, iowait, idle 등)
avg by (mode) (rate(node_cpu_seconds_total[5m])) * 100

# iowait만 별도 추적 (디스크 병목 감지용)
avg(rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100
```

| 구간 | 기준 | 조치 |
|------|------|------|
| 정상 | < 70% | - |
| 경고 | 70% ~ 85% | 원인 분석 시작, 스케일업 검토 |
| 위험 | > 85% (5분 지속) | 즉시 대응, 트래픽 분산 또는 프로세스 점검 |

#### 메모리 사용률

```promql
# 메모리 사용률 (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 절대값 (사용 중인 메모리, GB)
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024

# 스왑 사용량 (스왑 사용은 성능 저하의 강력한 신호)
node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes
```

| 구간 | 기준 | 조치 |
|------|------|------|
| 정상 | < 75% | - |
| 경고 | 75% ~ 90% | 메모리 누수 의심, 힙 덤프 검토 |
| 위험 | > 90% | OOM Killer 가능성, 즉시 대응 |

#### 디스크 사용률

```promql
# 파티션별 디스크 사용률 (%)
(1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}
     / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100

# 디스크 I/O 사용률 (busy 시간 비율)
rate(node_disk_io_time_seconds_total[5m]) * 100

# 디스크 읽기/쓰기 속도 (bytes/sec)
rate(node_disk_read_bytes_total[5m])
rate(node_disk_written_bytes_total[5m])
```

#### 네트워크 I/O

```promql
# 네트워크 수신 속도 (bytes/sec)
rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m])

# 네트워크 송신 속도 (bytes/sec)
rate(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m])

# 네트워크 에러 (패킷 드롭)
rate(node_network_receive_drop_total[5m])
rate(node_network_transmit_drop_total[5m])
```

#### 로드 애버리지

```promql
# 1분 / 5분 / 15분 로드 애버리지
node_load1
node_load5
node_load15

# CPU 코어 수 대비 로드 (1.0 이상이면 과부하)
node_load1 / count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})
```

> **로드 애버리지 해석**: CPU 코어 수 대비 1.0 미만이 정상. 예를 들어 4코어 시스템에서 load1이 4.0이면 CPU가 100% 포화 상태.

### 3.2 Nginx 레벨 (Nginx Exporter)

본 프로젝트는 `nginx/nginx-prometheus-exporter`를 사용하며, `stub_status` 모듈 기반으로 메트릭을 수집한다.

#### Active Connections

```promql
# 현재 활성 연결 수
nginx_connections_active

# 대기 중인 연결 수 (keep-alive 상태)
nginx_connections_waiting

# 읽기/쓰기 상태 연결
nginx_connections_reading
nginx_connections_writing
```

> Active = Reading + Writing + Waiting. Active가 급증하면 upstream(Tomcat)의 처리 지연을 의심한다.

#### Request Rate (RPS)

```promql
# 초당 요청 수
rate(nginx_http_requests_total[5m])

# 초당 신규 연결 수
rate(nginx_connections_accepted[5m])

# 처리 완료된 연결의 초당 비율
rate(nginx_connections_handled[5m])

# 드롭된 연결 감지 (accepted - handled > 0이면 문제)
rate(nginx_connections_accepted[5m]) - rate(nginx_connections_handled[5m])
```

#### HTTP 상태코드별 비율

> 주의: `stub_status` 기반 nginx-exporter는 상태코드별 분류를 제공하지 않는다. 상태코드별 메트릭은 Tomcat Actuator에서 수집해야 한다. Nginx에서 상태코드별 메트릭이 필요하면 `nginx-vts-exporter` 또는 로그 파싱 방식을 도입해야 한다.

```promql
# Tomcat Actuator 기반 상태코드별 비율 (Nginx 대체)
# 2xx 비율
sum(rate(http_server_requests_seconds_count{status=~"2.."}[5m]))
/
sum(rate(http_server_requests_seconds_count[5m])) * 100

# 4xx 비율
sum(rate(http_server_requests_seconds_count{status=~"4.."}[5m]))
/
sum(rate(http_server_requests_seconds_count[5m])) * 100

# 5xx 비율
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
/
sum(rate(http_server_requests_seconds_count[5m])) * 100
```

#### 응답시간 분포

```promql
# p50 (중앙값)
histogram_quantile(0.50,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)

# p90
histogram_quantile(0.90,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)

# p95
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)

# p99
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)

# 인스턴스별 p95
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le, instance)
)
```

### 3.3 JVM / Tomcat 레벨 (Spring Boot Actuator)

본 프로젝트의 Tomcat은 Spring Boot + Actuator + Micrometer Prometheus를 통해 JVM 및 HTTP 메트릭을 노출한다.
`-Xms256m -Xmx512m` 설정 기준으로 모니터링한다.

#### JVM Heap Used / Max

```promql
# Heap 사용량 (bytes)
jvm_memory_used_bytes{area="heap"}

# Heap 최대값 (bytes)
jvm_memory_max_bytes{area="heap"}

# Heap 사용률 (%)
jvm_memory_used_bytes{area="heap"}
/
jvm_memory_max_bytes{area="heap"} * 100

# Non-Heap 사용량 (Metaspace, Code Cache 등)
jvm_memory_used_bytes{area="nonheap"}

# 인스턴스별 Heap 사용률
jvm_memory_used_bytes{area="heap"}
/
jvm_memory_max_bytes{area="heap"} * 100
```

| 구간 | 기준 | 조치 |
|------|------|------|
| 정상 | Heap < 60% | - |
| 경고 | Heap 60% ~ 80% | GC 로그 확인, 메모리 누수 점검 |
| 위험 | Heap > 80% (지속) | 힙 덤프, -Xmx 증설 검토 |

#### GC 횟수 및 GC 소요시간

```promql
# GC 횟수 (초당) - Young/Old 구분
rate(jvm_gc_pause_seconds_count[5m])

# GC 총 소요시간 (초당 GC에 소비한 시간)
rate(jvm_gc_pause_seconds_sum[5m])

# GC 1회 평균 소요시간 (초)
rate(jvm_gc_pause_seconds_sum[5m])
/
rate(jvm_gc_pause_seconds_count[5m])

# GC로 인한 CPU 점유 비율 (%) - 10% 초과 시 위험
rate(jvm_gc_pause_seconds_sum[5m]) * 100

# cause별 GC (예: G1 Young Generation, G1 Old Generation)
rate(jvm_gc_pause_seconds_count{cause=~".*"}[5m])
```

> **GC 판단 기준**: GC 시간이 전체 시간의 5% 이내면 정상, 10% 초과 시 튜닝 필요. Full GC가 빈번하면 메모리 누수를 강력히 의심.

#### Thread Pool 상태

```promql
# Tomcat Thread Pool - 현재 활성 스레드 수
tomcat_threads_current_threads

# Tomcat Thread Pool - Busy 스레드 수 (요청 처리 중)
tomcat_threads_busy_threads

# Tomcat Thread Pool - 최대 스레드 수 (설정값)
tomcat_threads_config_max_threads

# Thread Pool 사용률 (%)
tomcat_threads_busy_threads
/
tomcat_threads_config_max_threads * 100

# JVM 전체 스레드 수
jvm_threads_live_threads

# JVM 데몬 스레드 수
jvm_threads_daemon_threads

# JVM 스레드 상태별 분포
jvm_threads_states_threads
```

| 구간 | 기준 | 조치 |
|------|------|------|
| 정상 | busy < 50% of max | - |
| 경고 | busy 50% ~ 80% of max | 슬로우 쿼리/외부 호출 지연 점검 |
| 위험 | busy > 80% of max | 요청 큐잉 발생, 스레드 풀 확장 또는 원인 해결 |

#### HTTP 요청 처리 시간

```promql
# URI별 평균 응답 시간
rate(http_server_requests_seconds_sum[5m])
/
rate(http_server_requests_seconds_count[5m])

# URI별 p95 응답 시간
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le, uri)
)

# 가장 느린 엔드포인트 Top 5 (평균 기준)
topk(5,
  rate(http_server_requests_seconds_sum[5m])
  /
  rate(http_server_requests_seconds_count[5m])
)

# method별 요청 수
sum by (method) (rate(http_server_requests_seconds_count[5m]))
```

### 3.4 MySQL 레벨

> 주의: 본 프로젝트의 현재 Prometheus 설정에는 MySQL Exporter가 포함되어 있지 않다. MySQL 메트릭 수집을 위해서는 `mysqld-exporter`를 docker-compose에 추가해야 한다. 아래 쿼리는 mysqld-exporter 도입 시 사용할 수 있는 PromQL이다.

#### Connections (현재 / 최대)

```promql
# 현재 연결 수
mysql_global_status_threads_connected

# 최대 허용 연결 수 (설정값)
mysql_global_variables_max_connections

# 연결 사용률 (%)
mysql_global_status_threads_connected
/
mysql_global_variables_max_connections * 100

# 연결 거부 횟수 (누적 - increase로 변환)
increase(mysql_global_status_aborted_connects[5m])

# 활성 스레드 수 (실제로 쿼리 실행 중)
mysql_global_status_threads_running
```

#### Queries Per Second

```promql
# 초당 쿼리 수 (전체)
rate(mysql_global_status_queries[5m])

# 명령어별 초당 처리량
rate(mysql_global_status_commands_total{command="select"}[5m])
rate(mysql_global_status_commands_total{command="insert"}[5m])
rate(mysql_global_status_commands_total{command="update"}[5m])
rate(mysql_global_status_commands_total{command="delete"}[5m])

# 읽기 vs 쓰기 비율
sum(rate(mysql_global_status_commands_total{command="select"}[5m]))
/
sum(rate(mysql_global_status_commands_total{command=~"insert|update|delete"}[5m]))
```

#### Slow Queries

```promql
# 초당 슬로우 쿼리 발생 수
rate(mysql_global_status_slow_queries[5m])

# 최근 1시간 슬로우 쿼리 총 건수
increase(mysql_global_status_slow_queries[1h])
```

> **슬로우 쿼리 기준**: MySQL의 `long_query_time` 설정값(기본 10초) 초과 쿼리. 실무에서는 1초로 낮추는 것을 권장한다.

#### InnoDB Buffer Pool Hit Rate

```promql
# Buffer Pool Hit Rate (%) - 99% 이상이 정상
(1 - (
  rate(mysql_global_status_innodb_buffer_pool_reads[5m])
  /
  rate(mysql_global_status_innodb_buffer_pool_read_requests[5m])
)) * 100

# Buffer Pool 사용량 (pages)
mysql_global_status_innodb_buffer_pool_pages_data
mysql_global_status_innodb_buffer_pool_pages_free
mysql_global_status_innodb_buffer_pool_pages_dirty

# Buffer Pool 총 크기 (bytes)
mysql_global_status_innodb_buffer_pool_bytes_data
```

> **Hit Rate 해석**: 99% 이상이면 대부분의 데이터를 메모리에서 읽는 것. 95% 이하로 떨어지면 `innodb_buffer_pool_size` 증설을 검토한다.

---

## 4. Prometheus Alert Rules 설정

### 4.1 alert.rules.yml 전체 예시

아래 파일을 `configs/prometheus/alert.rules.yml`로 저장하고, `prometheus.yml`의 `rule_files`에 추가한다.

```yaml
# configs/prometheus/alert.rules.yml
groups:
  # ============================================================
  # 인프라 기본 Alert
  # ============================================================
  - name: infrastructure_alerts
    rules:
      # ----------------------------------------------------------
      # 서버(타겟) 다운 감지
      # ----------------------------------------------------------
      - alert: TargetDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "타겟 {{ $labels.instance }} 다운"
          description: >
            {{ $labels.job }} 잡의 {{ $labels.instance }} 타겟이
            1분 이상 응답하지 않는다.
            즉시 확인이 필요한다.

      # ----------------------------------------------------------
      # CPU 80% 이상 5분 지속
      # ----------------------------------------------------------
      - alert: HighCpuUsage
        expr: >
          (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU 사용률 {{ printf \"%.1f\" $value }}% ({{ $labels.instance }})"
          description: >
            {{ $labels.instance }}의 CPU 사용률이 5분 이상
            80%를 초과하고 있다.
            현재 값: {{ printf "%.1f" $value }}%

      # ----------------------------------------------------------
      # CPU 95% 이상 2분 지속 (Critical)
      # ----------------------------------------------------------
      - alert: CriticalCpuUsage
        expr: >
          (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "CPU 사용률 위험 {{ printf \"%.1f\" $value }}% ({{ $labels.instance }})"
          description: >
            CPU 사용률이 95%를 초과했다. 즉시 조치가 필요한다.

      # ----------------------------------------------------------
      # 메모리 90% 이상
      # ----------------------------------------------------------
      - alert: HighMemoryUsage
        expr: >
          (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "메모리 사용률 {{ printf \"%.1f\" $value }}% ({{ $labels.instance }})"
          description: >
            가용 메모리가 10% 미만이다. OOM Killer가
            프로세스를 종료할 수 있다.

      # ----------------------------------------------------------
      # 디스크 85% 이상
      # ----------------------------------------------------------
      - alert: HighDiskUsage
        expr: >
          (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}
               / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100 > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "디스크 사용률 {{ printf \"%.1f\" $value }}% ({{ $labels.instance }}:{{ $labels.mountpoint }})"
          description: >
            디스크 공간이 15% 미만 남았다.
            로그 정리 또는 볼륨 확장을 검토한다.

      # ----------------------------------------------------------
      # 디스크 95% 이상 (Critical)
      # ----------------------------------------------------------
      - alert: CriticalDiskUsage
        expr: >
          (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}
               / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100 > 95
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "디스크 거의 가득 참 {{ printf \"%.1f\" $value }}%"
          description: >
            디스크 사용률 95% 초과. 서비스 장애로 이어질 수 있다.

  # ============================================================
  # Nginx Alert
  # ============================================================
  - name: nginx_alerts
    rules:
      # ----------------------------------------------------------
      # Nginx 5xx 에러율 5% 초과 (Tomcat Actuator 기반)
      # ----------------------------------------------------------
      - alert: HighNginx5xxRate
        expr: >
          (
            sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
            /
            sum(rate(http_server_requests_seconds_count[5m]))
          ) * 100 > 5
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "5xx 에러율 {{ printf \"%.2f\" $value }}%"
          description: >
            HTTP 5xx 에러율이 3분 이상 5%를 초과한다.
            Tomcat 로그와 애플리케이션 상태를 확인한다.

      # ----------------------------------------------------------
      # Nginx Active Connection 급증
      # ----------------------------------------------------------
      - alert: HighNginxConnections
        expr: nginx_connections_active > 500
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Nginx Active Connection {{ $value }}개"
          description: >
            Nginx 활성 연결이 500을 초과했다.
            DDoS 또는 upstream 지연을 의심한다.

  # ============================================================
  # JVM / Tomcat Alert
  # ============================================================
  - name: jvm_alerts
    rules:
      # ----------------------------------------------------------
      # JVM Heap 사용률 80% 초과
      # ----------------------------------------------------------
      - alert: HighJvmHeapUsage
        expr: >
          jvm_memory_used_bytes{area="heap"}
          /
          jvm_memory_max_bytes{area="heap"} * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "JVM Heap {{ printf \"%.1f\" $value }}% ({{ $labels.instance }})"
          description: >
            JVM Heap 사용률이 5분 이상 80%를 초과한다.
            메모리 누수 가능성을 점검한다.
            현재 Heap: {{ $labels.instance }}

      # ----------------------------------------------------------
      # JVM Heap 사용률 95% 초과 (Critical)
      # ----------------------------------------------------------
      - alert: CriticalJvmHeapUsage
        expr: >
          jvm_memory_used_bytes{area="heap"}
          /
          jvm_memory_max_bytes{area="heap"} * 100 > 95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "JVM Heap 위험 {{ printf \"%.1f\" $value }}%"
          description: >
            OutOfMemoryError 직전 상태이다.
            힙 덤프를 수집하고 즉시 대응한다.

      # ----------------------------------------------------------
      # GC 시간이 전체의 10% 초과
      # ----------------------------------------------------------
      - alert: HighGcOverhead
        expr: >
          rate(jvm_gc_pause_seconds_sum[5m]) > 0.10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GC 오버헤드 {{ printf \"%.1f\" (mul $value 100) }}% ({{ $labels.instance }})"
          description: >
            GC에 소요되는 시간이 전체의 10%를 초과한다.
            GC 로그를 분석하고 Heap 튜닝을 검토한다.

      # ----------------------------------------------------------
      # Tomcat Thread Pool 포화
      # ----------------------------------------------------------
      - alert: TomcatThreadPoolSaturation
        expr: >
          tomcat_threads_busy_threads
          /
          tomcat_threads_config_max_threads * 100 > 80
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "Tomcat 스레드 풀 {{ printf \"%.1f\" $value }}% 사용 중"
          description: >
            Tomcat 스레드 풀이 80% 이상 사용 중이다.
            요청 큐잉이 발생할 수 있다.

      # ----------------------------------------------------------
      # HTTP 응답시간 p95 > 2초
      # ----------------------------------------------------------
      - alert: HighResponseLatency
        expr: >
          histogram_quantile(0.95,
            sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
          ) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HTTP p95 응답시간 {{ printf \"%.2f\" $value }}초"
          description: >
            HTTP 요청의 p95 응답시간이 2초를 초과한다.
            슬로우 쿼리 또는 외부 API 지연을 점검한다.
```

### 4.2 prometheus.yml에 rule_files 추가

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Alert Rules 파일 로드
rule_files:
  - "alert.rules.yml"

scrape_configs:
  # ... (기존 설정 유지)
```

### 4.3 Alertmanager 연동 개요

Alertmanager는 Prometheus가 발생시킨 Alert를 수신하여 그룹핑, 중복 제거, 라우팅, 알림 전송을 처리한다.

**docker-compose.yml에 Alertmanager 추가 (향후 확장)**:

```yaml
alertmanager:
  image: prom/alertmanager:latest
  container_name: mw-alertmanager
  ports:
    - "9093:9093"
  volumes:
    - ./configs/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
  networks:
    - mw-network
```

**alertmanager.yml 기본 구조**:

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s        # 같은 그룹의 Alert를 모아서 보내는 대기 시간
  group_interval: 10s    # 같은 그룹의 다음 알림까지 간격
  repeat_interval: 1h    # 동일 Alert 재전송 간격
  receiver: 'slack-notifications'

  routes:
    - match:
        severity: critical
      receiver: 'slack-critical'
      repeat_interval: 5m

receivers:
  - name: 'slack-notifications'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#monitoring'
        title: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'slack-critical'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#incident'
        title: '[CRITICAL] {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

**prometheus.yml에 alerting 설정 추가**:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]
```

---

## 5. Grafana 대시보드 설계

### 5.1 대시보드 구성 원칙

#### USE Method (리소스 관점)

모든 **리소스**(CPU, 메모리, 디스크, 네트워크)에 대해 3가지를 측정:

| 항목 | 설명 | 예시 |
|------|------|------|
| **U**tilization | 리소스가 얼마나 사용되고 있는가 | CPU 사용률 75% |
| **S**aturation | 리소스가 얼마나 포화되었는가 (큐잉 발생 여부) | Load Average > CPU 코어 수 |
| **E**rrors | 에러 이벤트 횟수 | 디스크 I/O 에러 |

#### RED Method (서비스 관점)

모든 **서비스**(엔드포인트)에 대해 3가지를 측정:

| 항목 | 설명 | 예시 |
|------|------|------|
| **R**ate | 초당 요청 수 | 150 RPS |
| **E**rrors | 초당 실패 요청 수 또는 비율 | 5xx 에러율 0.5% |
| **D**uration | 요청 처리 시간 분포 | p95 = 320ms |

### 5.2 대시보드 구성 권장안

본 프로젝트에서는 다음 4개의 대시보드를 구성할 것을 권장한다.

#### 대시보드 1: System Overview

| Row | 패널 | PromQL | 시각화 타입 |
|-----|------|--------|-------------|
| 1 | CPU 사용률 | `(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100` | Gauge + Time Series |
| 1 | 메모리 사용률 | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | Gauge + Time Series |
| 1 | 디스크 사용률 | `(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100` | Gauge |
| 2 | 로드 애버리지 | `node_load1`, `node_load5`, `node_load15` | Time Series |
| 2 | 네트워크 I/O | `rate(node_network_receive_bytes_total[5m])` | Time Series (stacked) |

#### 대시보드 2: Nginx / Traffic

| Row | 패널 | PromQL | 시각화 타입 |
|-----|------|--------|-------------|
| 1 | Active Connections | `nginx_connections_active` | Stat + Time Series |
| 1 | RPS | `rate(nginx_http_requests_total[5m])` | Stat + Time Series |
| 2 | Connection 상태 | `nginx_connections_reading`, `writing`, `waiting` | Time Series (stacked) |
| 2 | 상태코드별 비율 | `sum by (status) (rate(http_server_requests_seconds_count[5m]))` | Pie Chart |

#### 대시보드 3: JVM / Tomcat

| Row | 패널 | PromQL | 시각화 타입 |
|-----|------|--------|-------------|
| 1 | Heap Usage | `jvm_memory_used_bytes{area="heap"}` vs max | Time Series (영역) |
| 1 | GC Pause Time | `rate(jvm_gc_pause_seconds_sum[5m])` | Time Series |
| 2 | Thread Pool | `tomcat_threads_busy_threads` vs max | Bar Gauge |
| 2 | HTTP p95 Latency | `histogram_quantile(0.95, ...)` | Time Series |
| 3 | 인스턴스별 RPS | `sum by (instance) (rate(http_server_requests_seconds_count[5m]))` | Time Series |
| 3 | 에러율 | `sum(rate(...{status=~"5.."}[5m])) / sum(rate(...[5m]))` | Time Series |

#### 대시보드 4: MySQL (mysqld-exporter 도입 후)

| Row | 패널 | PromQL | 시각화 타입 |
|-----|------|--------|-------------|
| 1 | Connections | `mysql_global_status_threads_connected` | Gauge + Time Series |
| 1 | QPS | `rate(mysql_global_status_queries[5m])` | Time Series |
| 2 | Slow Queries | `rate(mysql_global_status_slow_queries[5m])` | Time Series |
| 2 | Buffer Pool Hit Rate | `(1 - reads/read_requests) * 100` | Gauge |

### 5.3 Variable (변수) 활용법

Grafana Variable을 사용하면 하나의 대시보드에서 드롭다운으로 대상을 전환할 수 있다.

**instance 변수 설정**:
- Dashboard Settings > Variables > Add variable
- Name: `instance`
- Type: Query
- Data source: Prometheus
- Query: `label_values(up, instance)`
- Multi-value: 활성화
- Include All option: 활성화

**job 변수 설정**:
- Name: `job`
- Query: `label_values(up, job)`

**패널에서 변수 사용**:
```promql
# $instance 변수를 필터로 사용
rate(http_server_requests_seconds_count{instance=~"$instance"}[5m])

# $job 변수를 필터로 사용
up{job=~"$job"}
```

**자주 사용하는 변수 쿼리**:
```
# Tomcat 인스턴스만 조회
label_values(jvm_memory_used_bytes, instance)

# HTTP URI 목록
label_values(http_server_requests_seconds_count, uri)

# 시간 간격 변수 ($__rate_interval 활용)
rate(http_server_requests_seconds_count[$__rate_interval])
```

### 5.4 대시보드 JSON 임포트/익스포트 방법

#### 익스포트

1. 대시보드 상단 > Share > Export 탭
2. "Export for sharing externally" 체크 (uid가 제거되어 다른 Grafana에서 충돌하지 않음)
3. "Save to file" 클릭 -> JSON 파일 다운로드

또는 API로:
```bash
# Grafana API로 대시보드 JSON 가져오기
curl -s -H "Authorization: Bearer <API_KEY>" \
  http://localhost:3000/api/dashboards/uid/<DASHBOARD_UID> \
  | jq '.dashboard' > dashboard-export.json
```

#### 임포트

1. 좌측 메뉴 > Dashboards > Import
2. JSON 파일 업로드 또는 Grafana.com Dashboard ID 입력
3. Data source 매핑 (Prometheus 선택)

또는 프로비저닝으로 자동 임포트 (본 프로젝트 방식):

```yaml
# configs/grafana/provisioning/dashboards/dashboard.yml
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

JSON 대시보드 파일을 `configs/grafana/dashboards/` 디렉토리에 넣으면 Grafana 시작 시 자동 로드된다.

**추천 커뮤니티 대시보드 ID** (Grafana.com):
| 대시보드 | ID | 용도 |
|----------|-----|------|
| Node Exporter Full | 1860 | 시스템 리소스 모니터링 |
| Nginx | 12708 | Nginx 상태 모니터링 |
| JVM Micrometer | 4701 | JVM 메트릭 |
| Spring Boot Statistics | 6756 | Spring Boot 애플리케이션 |
| MySQL Overview | 7362 | MySQL 모니터링 |

---

## 6. PromQL 실전 쿼리 모음

### 6.1 rate() vs irate() 차이

| 항목 | rate() | irate() |
|------|--------|---------|
| 계산 방식 | 범위 내 첫 번째와 마지막 데이터 포인트 사이의 평균 증가율 | 범위 내 가장 마지막 두 데이터 포인트 사이의 순간 증가율 |
| 그래프 특성 | 부드러운 곡선 | 날카로운 피크 포착 |
| Alert 사용 | 적합 (안정적) | 부적합 (변동이 큼) |
| 대시보드 사용 | 트렌드 파악용 | 순간 spike 감지용 |

```promql
# rate(): 5분 평균 RPS (Alert, 장기 트렌드에 적합)
rate(http_server_requests_seconds_count[5m])

# irate(): 순간 RPS (대시보드에서 spike 확인용)
irate(http_server_requests_seconds_count[5m])
```

> **권장**: Alert Rule에는 반드시 `rate()`를 사용하라. `irate()`는 변동성이 커서 false positive가 많다.

### 6.2 histogram_quantile()로 p95/p99 계산

`histogram_quantile()`은 Histogram 타입 메트릭에서 분위수를 계산한다.

```promql
# 기본 구조
histogram_quantile(<분위수>, sum(rate(<metric>_bucket[<범위>])) by (le))

# p50 (중앙값)
histogram_quantile(0.50,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)

# p95
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)

# p99
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le)
)

# 인스턴스별 p95 (by에 instance 추가)
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le, instance)
)

# URI별 p99
histogram_quantile(0.99,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le, uri)
)
```

> **주의**: `by (le)`는 필수다. `le` (less than or equal) 라벨이 없으면 bucket 경계 정보가 사라져 분위수를 계산할 수 없다.

### 6.3 sum by(), avg by() 집계

```promql
# 인스턴스별 합계
sum by (instance) (rate(http_server_requests_seconds_count[5m]))

# job별 평균 CPU
avg by (job) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

# 상태코드별 요청 수
sum by (status) (rate(http_server_requests_seconds_count[5m]))

# without: 특정 라벨을 제외하고 집계
sum without (instance) (rate(http_server_requests_seconds_count[5m]))
```

### 6.4 increase() 활용

`increase()`는 범위 내 counter의 총 증가량을 계산한다. `rate() * 시간(초)`와 동일한 결과.

```promql
# 최근 1시간 동안의 총 요청 수
increase(http_server_requests_seconds_count[1h])

# 최근 24시간 동안의 5xx 에러 총 건수
increase(http_server_requests_seconds_count{status=~"5.."}[24h])

# 최근 1시간 동안의 GC 횟수
increase(jvm_gc_pause_seconds_count[1h])
```

### 6.5 자주 쓰는 PromQL 패턴 20개

```promql
# 1. 서비스 가용성 (up/down)
up{job="tomcat1"}

# 2. 전체 CPU 사용률 (%)
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

# 3. 메모리 사용률 (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 4. HTTP RPS (초당 요청 수)
sum(rate(http_server_requests_seconds_count[5m]))

# 5. HTTP 에러율 (%)
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
/ sum(rate(http_server_requests_seconds_count[5m])) * 100

# 6. 응답시간 p95
histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[5m])) by (le))

# 7. JVM Heap 사용률 (%)
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"} * 100

# 8. GC 소요 시간 비율 (%)
rate(jvm_gc_pause_seconds_sum[5m]) * 100

# 9. Tomcat 스레드 사용률 (%)
tomcat_threads_busy_threads / tomcat_threads_config_max_threads * 100

# 10. Nginx Active Connections
nginx_connections_active

# 11. 로드 애버리지 / CPU 코어
node_load1 / count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})

# 12. 디스크 사용률 (%)
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# 13. 네트워크 수신 속도 (MB/s)
rate(node_network_receive_bytes_total{device="eth0"}[5m]) / 1024 / 1024

# 14. Top 5 느린 엔드포인트
topk(5, rate(http_server_requests_seconds_sum[5m]) / rate(http_server_requests_seconds_count[5m]))

# 15. 특정 시간 대비 증가율 (1시간 전 대비)
rate(http_server_requests_seconds_count[5m])
/ rate(http_server_requests_seconds_count[5m] offset 1h)

# 16. 인스턴스별 요청 분배 비율 (로드밸런싱 확인)
sum by (instance) (rate(http_server_requests_seconds_count[5m]))
/ ignoring(instance) group_left sum(rate(http_server_requests_seconds_count[5m])) * 100

# 17. 특정 URI의 요청 수
sum(rate(http_server_requests_seconds_count{uri="/api/health"}[5m]))

# 18. JVM 스레드 수 추이
jvm_threads_live_threads

# 19. 스왑 사용량 (bytes)
node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes

# 20. Prometheus 자체 ingestion rate (초당 수집 샘플 수)
rate(prometheus_tsdb_head_samples_appended_total[5m])
```

---

## 7. 로그 모니터링

### 7.1 docker logs 활용법

본 프로젝트의 모든 서비스는 Docker 컨테이너로 실행되므로 `docker logs`로 접근한다.

```bash
# 실시간 로그 추적 (tail -f와 동일)
docker logs -f mw-tomcat1
docker logs -f mw-tomcat2
docker logs -f mw-nginx
docker logs -f mw-mysql

# 최근 100줄만 조회
docker logs --tail 100 mw-tomcat1

# 특정 시간 이후 로그만 조회
docker logs --since "2024-01-15T10:00:00" mw-tomcat1

# 최근 30분 로그
docker logs --since 30m mw-tomcat1

# 타임스탬프 포함
docker logs -t mw-tomcat1

# 여러 컨테이너 로그를 동시에 (docker compose)
docker compose logs -f tomcat1 tomcat2 nginx

# 특정 서비스 로그만 docker compose로
docker compose logs -f --tail 50 tomcat1
```

### 7.2 로그 레벨 모니터링 (ERROR, WARN, INFO)

```bash
# ERROR 로그만 필터링
docker logs mw-tomcat1 2>&1 | grep "ERROR"

# WARN 이상 로그 필터링
docker logs mw-tomcat1 2>&1 | grep -E "(ERROR|WARN)"

# 특정 시간대 ERROR 로그 카운트
docker logs --since 1h mw-tomcat1 2>&1 | grep -c "ERROR"

# Nginx 5xx 에러 로그 필터링
docker logs mw-nginx 2>&1 | grep '" 5[0-9][0-9] '

# MySQL 에러 로그
docker logs mw-mysql 2>&1 | grep -i "error"

# Exception 발생 확인 (Java Stack Trace)
docker logs mw-tomcat1 2>&1 | grep -A 10 "Exception"

# OutOfMemoryError 감지
docker logs mw-tomcat1 2>&1 | grep "OutOfMemoryError"
```

### 7.3 로그 기반 Alert (grep + cron 간이 방식)

전문 로그 수집 시스템 없이 간단한 Alert를 구현하는 방법.

**로그 감시 스크립트 (scripts/log-alert.sh)**:

```bash
#!/bin/bash
# 간이 로그 Alert 스크립트
# crontab에 등록: */5 * * * * /path/to/log-alert.sh

LOG_DIR="/var/log/middleware-alerts"
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
THRESHOLD_ERROR=10  # 5분간 ERROR 10건 이상이면 Alert

mkdir -p "$LOG_DIR"

# Tomcat ERROR 로그 카운트 (최근 5분)
for CONTAINER in mw-tomcat1 mw-tomcat2; do
  ERROR_COUNT=$(docker logs --since 5m "$CONTAINER" 2>&1 | grep -c "ERROR" || echo 0)

  if [ "$ERROR_COUNT" -ge "$THRESHOLD_ERROR" ]; then
    MESSAGE="[ALERT] ${CONTAINER}: 최근 5분간 ERROR ${ERROR_COUNT}건 발생"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $MESSAGE" >> "$LOG_DIR/alerts.log"

    # Slack 알림 (선택)
    curl -s -X POST -H 'Content-type: application/json' \
      --data "{\"text\": \"$MESSAGE\"}" \
      "$SLACK_WEBHOOK" > /dev/null 2>&1
  fi
done

# Nginx 5xx 에러 카운트 (최근 5분)
NGINX_5XX=$(docker logs --since 5m mw-nginx 2>&1 | grep -c '" 5[0-9][0-9] ' || echo 0)
if [ "$NGINX_5XX" -ge 5 ]; then
  MESSAGE="[ALERT] Nginx: 최근 5분간 5xx 에러 ${NGINX_5XX}건"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $MESSAGE" >> "$LOG_DIR/alerts.log"
fi

# OOM 감지
for CONTAINER in mw-tomcat1 mw-tomcat2; do
  OOM=$(docker logs --since 5m "$CONTAINER" 2>&1 | grep -c "OutOfMemoryError" || echo 0)
  if [ "$OOM" -gt 0 ]; then
    MESSAGE="[CRITICAL] ${CONTAINER}: OutOfMemoryError 발생!"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $MESSAGE" >> "$LOG_DIR/alerts.log"
  fi
done
```

**crontab 등록**:
```bash
# 5분마다 로그 감시 실행
*/5 * * * * /path/to/scripts/log-alert.sh

# 매일 자정에 Alert 로그 로테이션
0 0 * * * mv /var/log/middleware-alerts/alerts.log /var/log/middleware-alerts/alerts.$(date +\%Y\%m\%d).log
```

### 7.4 향후 확장: ELK Stack / Loki 도입 시 고려사항

#### Grafana Loki (권장)

본 프로젝트가 이미 Grafana를 사용하고 있으므로, Loki가 자연스러운 확장이다.

**장점**:
- Grafana와 네이티브 통합 (같은 대시보드에서 메트릭 + 로그 조회)
- Prometheus와 유사한 라벨 기반 인덱싱 (LogQL 쿼리)
- ELK 대비 리소스 소비가 적음 (full-text 인덱싱 안 함)
- Docker 로그 드라이버로 간편 연동

**도입 시 추가 구성**:
```yaml
# docker-compose에 추가
loki:
  image: grafana/loki:latest
  container_name: mw-loki
  ports:
    - "3100:3100"
  networks:
    - mw-network

promtail:
  image: grafana/promtail:latest
  container_name: mw-promtail
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ./configs/promtail/config.yml:/etc/promtail/config.yml:ro
  networks:
    - mw-network
```

#### ELK Stack (Elasticsearch + Logstash + Kibana)

**장점**:
- Full-text 검색에 강력함
- 복잡한 로그 파싱/변환 (Logstash Grok 패턴)
- 대규모 로그 분석에 적합

**단점**:
- 리소스 소비가 큼 (Elasticsearch는 최소 2GB+ RAM)
- 별도의 대시보드(Kibana) 관리 필요
- 학습 곡선이 높음

**도입 판단 기준**:
- 로그 볼륨이 하루 수 GB 이하 -> Loki 추천
- 복잡한 로그 파싱 + full-text 검색 필요 -> ELK 추천
- 이미 Grafana를 운영 중 -> Loki가 운영 부담 적음

---

## 8. 모니터링 체크리스트

### 8.1 일일 점검 항목

| 순번 | 점검 항목 | 확인 방법 | 정상 기준 | 확인 |
|------|-----------|-----------|-----------|------|
| 1 | 모든 서비스 가동 상태 | Prometheus `up` 메트릭 | 모든 타겟 `up == 1` | [ ] |
| 2 | CPU 사용률 | Grafana System Overview | < 70% | [ ] |
| 3 | 메모리 사용률 | Grafana System Overview | < 80% | [ ] |
| 4 | 디스크 사용률 | Grafana System Overview | < 80% | [ ] |
| 5 | JVM Heap 사용률 | Grafana JVM Dashboard | < 70% | [ ] |
| 6 | HTTP 에러율 (5xx) | Grafana Nginx/Tomcat | < 1% | [ ] |
| 7 | 응답시간 p95 | Grafana Tomcat Dashboard | < 500ms | [ ] |
| 8 | Nginx Active Connection | Grafana Nginx Dashboard | 비정상 spike 없음 | [ ] |
| 9 | GC 오버헤드 | Grafana JVM Dashboard | < 5% | [ ] |
| 10 | ERROR 로그 건수 | `docker logs --since 24h` + grep | 비정상 증가 없음 | [ ] |
| 11 | Prometheus Alert 발생 여부 | Prometheus Alerts 페이지 | Firing alert 없음 | [ ] |
| 12 | Docker 컨테이너 재시작 횟수 | `docker ps` (STATUS 컬럼) | 비정상 재시작 없음 | [ ] |

### 8.2 주간 점검 항목

| 순번 | 점검 항목 | 확인 방법 | 정상 기준 | 확인 |
|------|-----------|-----------|-----------|------|
| 1 | 트래픽 트렌드 분석 | Grafana RPS 주간 그래프 | 급격한 변동 없음 | [ ] |
| 2 | 응답시간 트렌드 | Grafana p95 주간 그래프 | 점진적 증가 없음 | [ ] |
| 3 | 에러율 트렌드 | Grafana 에러율 주간 그래프 | 증가 추세 없음 | [ ] |
| 4 | JVM Heap 트렌드 | Grafana Heap 주간 그래프 | 메모리 누수 패턴 없음 | [ ] |
| 5 | 디스크 사용량 증가율 | Node Exporter 디스크 트렌드 | 월내 80% 초과 예상 없음 | [ ] |
| 6 | Slow Query 건수 | MySQL slow query log | 주간 10건 미만 | [ ] |
| 7 | Docker 이미지/볼륨 정리 | `docker system df` | 불필요 리소스 없음 | [ ] |
| 8 | Scouter XLog 분석 | Scouter Client | 비정상 패턴 없음 | [ ] |
| 9 | Error Budget 잔량 | PromQL Error Budget 쿼리 | 50% 이상 잔여 | [ ] |
| 10 | Prometheus 스토리지 | Prometheus TSDB 상태 | 정상 범위 내 | [ ] |

### 8.3 월간 점검 항목

| 순번 | 점검 항목 | 확인 방법 | 정상 기준 | 확인 |
|------|-----------|-----------|-----------|------|
| 1 | SLO 달성 여부 리뷰 | Error Budget 소진율 | SLO 99.9% 충족 | [ ] |
| 2 | 용량 계획 (Capacity Planning) | 리소스 사용률 월간 트렌드 | 3개월 내 한계 도달 없음 | [ ] |
| 3 | Alert Rule 효과성 리뷰 | Firing 이력, false positive 분석 | false positive < 10% | [ ] |
| 4 | Grafana 대시보드 정비 | 사용하지 않는 패널 정리 | 최신 상태 유지 | [ ] |
| 5 | Prometheus 데이터 보존 확인 | `--storage.tsdb.retention.time` | 15일 이상 보존 | [ ] |
| 6 | 보안 패치 확인 | Docker 이미지 업데이트 여부 | 최신 패치 적용 | [ ] |
| 7 | 백업 검증 | MySQL 백업 복원 테스트 | 복원 성공 확인 | [ ] |
| 8 | Keycloak 인증 로그 리뷰 | Keycloak Admin Console | 비인가 시도 없음 | [ ] |
| 9 | 부하 테스트 (선택) | JMeter / k6 | SLO 기준 내 응답 | [ ] |
| 10 | 인시던트 회고 | 장애 리포트 작성 | 재발 방지책 수립 | [ ] |

---

## 참고 자료

- [Google SRE Book - Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Prometheus 공식 문서 - Querying](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana 공식 문서 - Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [USE Method (Brendan Gregg)](https://www.brendangregg.com/usemethod.html)
- [RED Method (Tom Wilkie)](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [Scouter APM 가이드](scouter-guide.md) | Scouter APM 심층 가이드 |
| [성능 튜닝 가이드](performance-tuning.md) | 메트릭 기반 성능 튜닝 |
| [장애 대응 매뉴얼](incident-response.md) | 모니터링 기반 장애 대응 |
| [아키텍처 설계](architecture.md) | 모니터링 아키텍처 구조 |
