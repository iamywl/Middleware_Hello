# 인프라 설계 심화 가이드

> **대상 독자**: 3년차 이상 인프라/백엔드 엔지니어
> **프로젝트 구성**: Nginx + Tomcat(x2) + MySQL + Scouter APM + Prometheus + Grafana + Keycloak on Docker Compose
> **최종 수정**: 2026-03-12

---

## 목차

1. [로드밸런싱 알고리즘 비교](#1-로드밸런싱-알고리즘-비교)
2. [세션 관리 전략](#2-세션-관리-전략)
3. [배포 전략](#3-배포-전략)
4. [고가용성(HA) 설계](#4-고가용성ha-설계)
5. [네트워크 설계](#5-네트워크-설계)
6. [용량 계획 (Capacity Planning)](#6-용량-계획-capacity-planning)
7. [백업 및 복구 전략](#7-백업-및-복구-전략)
8. [확장성 설계](#8-확장성-설계)
9. [인프라 설계 체크리스트](#9-인프라-설계-체크리스트)

---

## 1. 로드밸런싱 알고리즘 비교

로드밸런서는 다수의 WAS 서버에 트래픽을 분산하여 단일 서버에 부하가 집중되는 것을 방지한다. Nginx는 L7(Application Layer) 로드밸런서로서 HTTP 요청 단위로 분산을 수행한다.

### 1.1 Round Robin (기본값)

**동작 원리**: 요청을 순서대로 각 서버에 번갈아 전달한다. 서버 목록의 첫 번째 서버부터 시작하여 마지막 서버까지 도달하면 다시 처음으로 돌아간다.

```
요청 1 → Tomcat1
요청 2 → Tomcat2
요청 3 → Tomcat1
요청 4 → Tomcat2
...
```

**장점**:
- 구현이 단순하고 직관적이다
- 서버 스펙이 동일할 때 균등한 분산을 보장한다
- 추가 설정 없이 기본 동작으로 사용 가능하다

**단점**:
- 서버별 처리 능력 차이를 고려하지 않는다
- 특정 요청이 처리 시간이 길 경우, 해당 서버에 요청이 쌓일 수 있다
- 세션 고정(Sticky Session)을 보장하지 않는다

**사용 시기**: 동일 스펙의 서버가 동일한 애플리케이션을 서비스할 때 가장 적합하다.

**Nginx 설정**:
```nginx
upstream was_backend {
    # Round Robin은 별도 지시어가 필요 없다 (기본값)
    server tomcat1:8080;
    server tomcat2:8080;
}
```

### 1.2 Weighted Round Robin

**동작 원리**: 각 서버에 가중치(weight)를 부여하여, 가중치가 높은 서버에 더 많은 요청을 전달한다. weight=3인 서버는 weight=1인 서버보다 3배 많은 요청을 받는다.

```
weight=3 서버: 요청 1, 2, 3 처리
weight=1 서버: 요청 4 처리
weight=3 서버: 요청 5, 6, 7 처리
weight=1 서버: 요청 8 처리
...
```

**장점**:
- 서버 성능 차이를 반영할 수 있다
- 신규 서버 투입 시 점진적으로 가중치를 올릴 수 있다 (Warm-up)

**단점**:
- 적절한 가중치 산정이 필요하다 (부하 테스트 기반으로 결정해야 한다)
- 동적으로 변하는 서버 상태를 반영하지 못한다

**사용 시기**: 서버 스펙이 다르거나, 한 서버에 다른 프로세스가 동시에 실행될 때.

**Nginx 설정**:
```nginx
upstream was_backend {
    server tomcat1:8080 weight=3;  # 고성능 서버: 요청의 75% 처리
    server tomcat2:8080 weight=1;  # 저사양 서버: 요청의 25% 처리
}
```

### 1.3 Least Connections

**동작 원리**: 현재 활성(active) 연결 수가 가장 적은 서버에 새 요청을 전달한다. Nginx는 각 upstream 서버의 활성 연결 수를 실시간으로 추적한다.

```
Tomcat1 활성 연결: 5개 ← 새 요청은 여기로
Tomcat2 활성 연결: 8개
```

**장점**:
- 요청 처리 시간이 불균일할 때 효과적이다
- 서버별 부하를 동적으로 반영한다
- 느린 서버에 요청이 쌓이는 현상을 방지한다

**단점**:
- 연결 수만 기준으로 하므로, CPU/메모리 사용률을 반영하지 못한다
- 짧은 요청이 많을 때는 Round Robin과 성능 차이가 미미하다
- 서버 간 네트워크 지연 차이를 고려하지 않는다

**사용 시기**: 요청 처리 시간이 요청마다 크게 다를 때 (파일 업로드, 리포트 생성 등 혼재).

**Nginx 설정**:
```nginx
upstream was_backend {
    least_conn;
    server tomcat1:8080;
    server tomcat2:8080;
}
```

### 1.4 IP Hash (Session Affinity)

**동작 원리**: 클라이언트 IP 주소를 해싱하여 항상 동일한 서버로 요청을 전달한다. 동일 IP의 사용자는 항상 같은 WAS에 연결된다.

```
IP 192.168.1.10 → hash → Tomcat1 (항상)
IP 192.168.1.20 → hash → Tomcat2 (항상)
```

**장점**:
- 별도의 세션 공유 메커니즘 없이 세션 고정을 구현할 수 있다
- 설정이 간단하다

**단점**:
- 대규모 NAT 환경(사내망 등)에서 특정 서버에 부하가 집중된다
- 서버 추가/제거 시 해시 테이블이 변경되어 기존 세션이 깨진다
- CDN이나 프록시 뒤에서는 실제 클라이언트 IP를 얻기 어렵다

**사용 시기**: 세션 저장소 외부화가 어렵고, 서버 사이드 세션을 반드시 사용해야 할 때.

**Nginx 설정**:
```nginx
upstream was_backend {
    ip_hash;
    server tomcat1:8080;
    server tomcat2:8080;
}
```

### 1.5 알고리즘 비교 요약

| 항목 | Round Robin | Weighted RR | Least Conn | IP Hash |
|------|-----------|------------|-----------|---------|
| 분산 균등성 | 높음 (동일 스펙 시) | 가중치 기반 | 동적 반영 | IP 분포에 의존 |
| 세션 고정 | X | X | X | O |
| 설정 복잡도 | 낮음 | 낮음 | 낮음 | 낮음 |
| 서버 상태 반영 | X | X | O (연결 수) | X |
| 서버 스펙 차이 대응 | X | O | 부분적 | X |
| NAT 환경 적합성 | O | O | O | X |

### 1.6 본 프로젝트에서 Round Robin을 선택한 이유

본 프로젝트의 현재 설정 (`configs/nginx/conf.d/default.conf`):

```nginx
upstream was_backend {
    server tomcat1:8080 weight=1;
    server tomcat2:8080 weight=1;
}
```

**선택 근거**:

1. **동일 스펙의 WAS 구성**: Tomcat1과 Tomcat2는 동일한 Docker 이미지에서 빌드되며, 동일한 JVM 옵션(`-Xms256m -Xmx512m`)으로 실행된다. 서버 간 성능 차이가 없으므로 가중치 기반 분산이 불필요하다.

2. **Stateless 아키텍처 지향**: Keycloak 기반 JWT 인증을 사용하므로 서버 사이드 세션에 의존하지 않는다. IP Hash를 통한 세션 고정이 필요 없다.

3. **균등 분산으로 모니터링 용이**: Round Robin은 두 WAS에 균등하게 트래픽을 분산하므로, Scouter APM과 Prometheus를 통해 두 서버의 메트릭을 비교하기에 적합하다. 특정 서버에만 부하가 쏠리면 비교 분석이 어려워진다.

4. **단순성**: 학습 및 운영 환경에서 가장 이해하기 쉬운 알고리즘이다. 문제 발생 시 디버깅이 용이하다.

---

## 2. 세션 관리 전략

> **본 프로젝트의 선택**: 본 프로젝트는 JWT 기반 Stateless 인증을 채택하였다 (2.6절 참고). 아래 2.1~2.5절은 세션 관리 전략의 종류와 장단점을 비교 분석한 내용으로, 각 전략의 특성을 이해하기 위한 참고 자료이다.

WAS를 이중화하면 세션 관리가 핵심 과제가 된다. 사용자가 로그인 후 다른 WAS로 요청이 전달되면 세션을 찾지 못해 다시 로그인해야 하는 문제가 발생한다.

### 2.1 Sticky Session (Session Affinity)

**원리**: 로드밸런서가 최초 요청을 처리한 서버를 기억하고, 이후 동일 사용자의 요청을 항상 같은 서버로 전달한다.

**구현 방법 1 - Nginx ip_hash**:
```nginx
upstream was_backend {
    ip_hash;
    server tomcat1:8080;
    server tomcat2:8080;
}
```

**구현 방법 2 - Cookie 기반 (Nginx Plus 또는 OpenResty)**:
```nginx
upstream was_backend {
    server tomcat1:8080;
    server tomcat2:8080;
    sticky cookie srv_id expires=1h domain=.example.com path=/;
}
```

**구현 방법 3 - Tomcat jvmRoute 기반 (본 프로젝트에서 세션 어피니티 참조용으로 설정됨, 실제 인증은 JWT 기반)**:

Tomcat의 `jvmRoute` 설정으로 JSESSIONID 뒤에 서버 식별자를 붙인다:
```
JSESSIONID=ABC123.tomcat1
JSESSIONID=DEF456.tomcat2
```

본 프로젝트 docker-compose.yml에서 이미 설정되어 있다:
```yaml
environment:
  JAVA_OPTS: >-
    -DjvmRoute=tomcat1
```

**장점**: 구현이 간단하고 기존 세션 메커니즘을 그대로 사용할 수 있다.
**단점**: 특정 서버에 부하가 집중될 수 있고, 서버 장애 시 해당 서버의 모든 세션이 소실된다.

### 2.2 Session Replication (세션 복제)

**원리**: 클러스터 내 모든 WAS가 세션 데이터를 공유한다. 한 서버에서 생성/변경된 세션이 실시간으로 다른 서버에 복제된다.

**Tomcat 클러스터링 설정** (`server.xml`):
```xml
<Cluster className="org.apache.catalina.ha.tcp.SimpleTcpCluster"
         channelSendOptions="8">

  <Manager className="org.apache.catalina.ha.session.DeltaManager"
           expireSessionsOnShutdown="false"
           notifyListenersOnReplication="true"/>

  <Channel className="org.apache.catalina.tribes.group.GroupChannel">
    <Membership className="org.apache.catalina.tribes.membership.McastService"
                address="228.0.0.4"
                port="45564"
                frequency="500"
                dropTime="3000"/>
    <Receiver className="org.apache.catalina.tribes.transport.nio.NioReceiver"
              address="auto"
              port="4000"
              autoBind="100"
              selectorTimeout="5000"
              maxThreads="6"/>
    <Sender className="org.apache.catalina.tribes.transport.ReplicationTransmitter">
      <Transport className="org.apache.catalina.tribes.transport.nio.PooledParallelSender"/>
    </Sender>
    <Interceptor className="org.apache.catalina.tribes.group.interceptors.TcpFailureDetector"/>
    <Interceptor className="org.apache.catalina.tribes.group.interceptors.MessageDispatchInterceptor"/>
  </Channel>

  <Valve className="org.apache.catalina.ha.tcp.ReplicationValve"
         filter=""/>
  <Valve className="org.apache.catalina.ha.session.JvmRouteBinderValve"/>

  <ClusterListener className="org.apache.catalina.ha.session.ClusterSessionListener"/>
</Cluster>
```

**장점**: 서버 장애 시에도 세션이 유지된다. 로드밸런서에 세션 고정 설정이 불필요하다.
**단점**: WAS가 늘어날수록 복제 트래픽이 기하급수적으로 증가한다 (N*(N-1) 복제). 대규모 클러스터에 부적합하다.

### 2.3 Session Externalization (세션 외부 저장소)

**원리**: 세션 데이터를 WAS 외부의 공유 저장소(Redis, Memcached)에 저장한다. 모든 WAS가 동일한 저장소를 참조하므로 어느 서버로 요청이 가도 세션을 조회할 수 있다.

**Spring Boot + Redis 세션 구현**:
```yaml
# application.yml
spring:
  session:
    store-type: redis
    redis:
      flush-mode: on_save
      namespace: spring:session
  redis:
    host: redis-server
    port: 6379
    password: redis_password
```

```java
// build.gradle
implementation 'org.springframework.boot:spring-boot-starter-data-redis'
implementation 'org.springframework.session:spring-session-data-redis'
```

**Docker Compose에 Redis 추가 시**:
```yaml
redis:
  image: redis:7-alpine
  container_name: mw-redis
  command: redis-server --requirepass redis_password --maxmemory 256mb
  ports:
    - "6379:6379"
  volumes:
    - redis_data:/data
  networks:
    - mw-network
```

**장점**: WAS의 무상태성을 유지할 수 있다. 서버 추가/제거가 자유롭다. 세션 복제 대비 네트워크 트래픽이 적다.
**단점**: Redis 장애가 전체 서비스 장애로 이어진다 (SPOF). 네트워크 호출로 인한 약간의 레이턴시가 추가된다.

### 2.4 Token-based (JWT)

**원리**: 서버에 세션을 저장하지 않고, 인증 정보를 토큰(JWT)에 담아 클라이언트에 전달한다. 클라이언트는 매 요청 시 토큰을 포함하며, 서버는 토큰의 서명을 검증하여 인증 상태를 확인한다.

```
1. 사용자 → Keycloak: 로그인 요청
2. Keycloak → 사용자: JWT Access Token + Refresh Token 발급
3. 사용자 → Nginx → Tomcat: API 요청 (Authorization: Bearer <JWT>)
4. Tomcat: JWT 서명 검증 (Keycloak 공개키 사용), 별도의 세션 조회 불필요
```

**JWT 구조**:
```
Header.Payload.Signature

Header:  {"alg": "RS256", "typ": "JWT"}
Payload: {"sub": "user123", "roles": ["USER"], "exp": 1700000000, "iss": "keycloak"}
Signature: RS256(Header.Payload, Keycloak_Private_Key)
```

**장점**: 서버가 완전한 무상태(Stateless)가 된다. WAS 확장이 자유롭다. 세션 저장소가 불필요하다.
**단점**: 토큰 크기가 세션 ID보다 크다 (매 요청마다 전송). 발급된 토큰을 서버에서 즉시 무효화하기 어렵다 (로그아웃/권한 변경 시). Refresh Token 관리 로직이 필요하다.

### 2.5 세션 관리 전략 비교

| 항목 | Sticky Session | Session Replication | Session External | JWT |
|------|--------------|-------------------|-----------------|-----|
| 서버 무상태성 | X | X | 부분적 | O |
| 서버 장애 시 세션 유지 | X | O | O | O (토큰 유효 시) |
| 확장성 | 낮음 | 낮음 (N^2 복제) | 높음 | 매우 높음 |
| 추가 인프라 필요 | X | X | Redis 등 | IdP (Keycloak) |
| 구현 복잡도 | 낮음 | 중간 | 중간 | 높음 |
| 네트워크 오버헤드 | 없음 | 높음 | 낮음 | 없음 |
| 즉시 무효화 가능 | O (서버 측) | O (서버 측) | O (저장소 삭제) | X (만료 대기) |

### 2.6 본 프로젝트의 세션 전략: Keycloak JWT 기반

본 프로젝트는 **JWT 기반 인증**을 채택하였다.

**선택 근거**:

1. **Keycloak이 IdP 역할 수행**: Keycloak이 토큰 발급/검증/갱신을 전담한다. WAS는 토큰 검증만 수행하므로 세션을 관리할 필요가 없다.

2. **WAS 완전 무상태화**: Tomcat1, Tomcat2 어디로 요청이 가든 동일하게 처리된다. 이는 Round Robin 로드밸런싱과 완벽하게 호환된다.

3. **향후 확장성 확보**: 마이크로서비스 전환이나 Kubernetes 마이그레이션 시 JWT 기반 인증은 그대로 사용 가능하다.

4. **세션 복제/외부 저장소 불필요**: Redis 등 추가 인프라 없이도 WAS 이중화가 가능하다. 인프라 복잡도를 낮춘다.

**주의사항**: JWT의 즉시 무효화 한계를 보완하기 위해 Access Token의 만료 시간을 짧게(5~15분) 설정하고, Refresh Token으로 갱신하는 패턴을 사용해야 한다.

---

## 3. 배포 전략

서비스 무중단 배포는 운영 환경의 핵심 요구사항이다. Docker Compose 환경에서 적용 가능한 주요 배포 전략을 분석한다.

### 3.1 Rolling Update (순차 배포)

**원리**: 서버를 하나씩 순차적으로 업데이트한다. 한 서버가 업데이트되는 동안 나머지 서버가 트래픽을 처리한다.

```
단계 1: Tomcat1 중지 → 업데이트 → 시작 (Tomcat2가 전체 트래픽 처리)
단계 2: Tomcat2 중지 → 업데이트 → 시작 (Tomcat1이 전체 트래픽 처리)
```

**장점**: 추가 서버 리소스가 불필요하다. 다운타임을 최소화할 수 있다.
**단점**: 배포 중 일시적으로 서버 수가 줄어 처리 능력이 감소한다. 롤백이 느리다 (역순으로 재배포 필요). 구/신 버전이 동시에 서비스되는 구간이 존재한다.

**Docker Compose 환경 구현**:
```bash
#!/bin/bash
# rolling-update.sh

set -e

echo "=== Rolling Update 시작 ==="

# 1단계: Tomcat1 업데이트
echo "[1/4] Tomcat1 중지..."
docker compose stop tomcat1

echo "[2/4] Tomcat1 재빌드 및 시작..."
docker compose build tomcat1
docker compose up -d tomcat1

echo "  [2/4] Tomcat1 헬스체크 대기..."
until docker exec mw-tomcat1 curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1; do
  echo "  Tomcat1 시작 대기 중..."
  sleep 3
done
echo "  Tomcat1 정상 기동 확인"

# 2단계: Tomcat2 업데이트
echo "[3/4] Tomcat2 중지..."
docker compose stop tomcat2

echo "[4/4] Tomcat2 재빌드 및 시작..."
docker compose build tomcat2
docker compose up -d tomcat2

until docker exec mw-tomcat2 curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1; do
  echo "  Tomcat2 시작 대기 중..."
  sleep 3
done
echo "  Tomcat2 정상 기동 확인"

echo "=== Rolling Update 완료 ==="
```

### 3.2 Blue-Green Deployment (블루-그린 배포)

**원리**: 두 개의 동일한 환경(Blue=현재, Green=신규)을 준비하고, 신규 버전 검증 후 트래픽을 한 번에 전환한다.

```
Blue (현재 v1.0 서비스 중)  ← Nginx 연결
Green (v2.0 배포 및 테스트 중)

검증 완료 후:
Blue (v1.0 대기/롤백용)
Green (v2.0 서비스 중)  ← Nginx 연결 전환
```

**장점**: 즉시 롤백이 가능하다 (Nginx 설정만 되돌리면 된다). 신규 버전을 충분히 테스트한 후 전환할 수 있다.
**단점**: 2배의 서버 리소스가 필요하다. 데이터베이스 스키마 변경이 있을 경우 복잡해진다.

**Nginx upstream 설정으로 Blue-Green 구현**:

```nginx
# /etc/nginx/conf.d/default.conf

# Blue 환경 (현재 서비스)
upstream blue_backend {
    server tomcat-blue-1:8080;
    server tomcat-blue-2:8080;
}

# Green 환경 (신규 버전)
upstream green_backend {
    server tomcat-green-1:8080;
    server tomcat-green-2:8080;
}

# 활성 환경 선택 - 이 파일을 교체하여 전환
# active_backend.conf 내용: "set $active_backend blue_backend;" 또는 green_backend
include /etc/nginx/conf.d/active_backend.conf;

server {
    listen 443 ssl;

    location / {
        proxy_pass http://$active_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

**전환 스크립트**:
```bash
#!/bin/bash
# blue-green-switch.sh

CURRENT=$(cat /etc/nginx/conf.d/active_backend.conf | grep -o 'blue\|green')

if [ "$CURRENT" = "blue" ]; then
  NEW="green"
else
  NEW="blue"
fi

echo "Switching from $CURRENT to $NEW..."

# active_backend.conf 교체
echo "set \$active_backend ${NEW}_backend;" > /etc/nginx/conf.d/active_backend.conf

# Nginx 설정 리로드 (다운타임 없음)
docker exec mw-nginx nginx -s reload

echo "Switched to $NEW environment"
```

### 3.3 Canary Deployment (카나리 배포)

**원리**: 전체 트래픽 중 일부(예: 5~10%)만 신규 버전으로 보내고, 모니터링 결과가 양호하면 점진적으로 비율을 높여 전체 전환한다.

```
단계 1: 95% → v1.0 (기존), 5% → v2.0 (신규)
단계 2: 80% → v1.0, 20% → v2.0  (에러율 정상 확인 후)
단계 3: 50% → v1.0, 50% → v2.0
단계 4: 0% → v1.0, 100% → v2.0
```

**Nginx weight를 활용한 Canary 구현**:
```nginx
upstream was_backend {
    # 기존 버전: weight=9 (90% 트래픽)
    server tomcat-v1-1:8080 weight=9;
    server tomcat-v1-2:8080 weight=9;

    # 신규 버전: weight=1 (10% 트래픽)
    server tomcat-v2-1:8080 weight=1;
}
```

**장점**: 위험을 최소화하면서 실제 트래픽으로 신규 버전을 검증할 수 있다. 문제 발생 시 소수 사용자만 영향을 받는다.
**단점**: 모니터링 체계가 잘 갖춰져 있어야 한다. 배포 과정이 길다. 트래픽 비율 조정이 수동이면 운영 부담이 크다.

### 3.4 배포 전략 비교

| 항목 | Rolling Update | Blue-Green | Canary |
|------|--------------|-----------|--------|
| 다운타임 | 최소 (순차 교체) | 없음 (즉시 전환) | 없음 |
| 롤백 속도 | 느림 (재배포) | 즉시 (설정 전환) | 빠름 (가중치 변경) |
| 리소스 비용 | 낮음 | 높음 (2배) | 중간 |
| 구현 복잡도 | 낮음 | 중간 | 높음 |
| 위험도 | 중간 | 낮음 | 매우 낮음 |
| 테스트 충분성 | 낮음 | 높음 (전환 전 테스트) | 매우 높음 (실 트래픽) |
| Docker Compose 적합성 | 높음 | 중간 | 낮음 |
| 적합 환경 | 소규모, 개발/스테이징 | 중규모, 프로덕션 | 대규모, 프로덕션 |

---

## 4. 고가용성(HA) 설계

### 4.1 SPOF(Single Point of Failure) 분석

SPOF는 단일 장애 지점으로, 해당 컴포넌트가 실패하면 전체 서비스가 중단되는 지점을 말한다.

**본 프로젝트의 아키텍처 SPOF 분석**:

```
┌─────────────────────────────────────────────────────────┐
│                    Client (Browser)                      │
└────────────────────┬────────────────────────────────────┘
                     │
              ┌──────▼──────┐
              │   Nginx(1)  │  ◀── SPOF #1: WEB 서버 단일 구성
              └──────┬──────┘
                     │
              ┌──────┴──────┐
        ┌─────▼─────┐ ┌────▼─────┐
        │ Tomcat1   │ │ Tomcat2  │  ◀── HA 구성: WAS 이중화 완료
        └─────┬─────┘ └────┬─────┘
              └──────┬──────┘
              ┌──────▼──────┐
              │  MySQL(1)   │  ◀── SPOF #2: DB 서버 단일 구성
              └─────────────┘
```

| 컴포넌트 | 인스턴스 수 | SPOF 여부 | 장애 영향 |
|---------|-----------|----------|---------|
| Nginx | 1대 | **SPOF** | 전체 서비스 중단 |
| Tomcat | 2대 | 아님 | 1대 장애 시 나머지가 처리 |
| MySQL | 1대 | **SPOF** | 전체 서비스 중단 (데이터 접근 불가) |
| Keycloak | 1대 | **부분 SPOF** | 신규 로그인 불가 (기존 JWT는 만료까지 유효) |
| Scouter | 1대 | 아님 | 모니터링 중단 (서비스에 영향 없음) |
| Prometheus | 1대 | 아님 | 메트릭 수집 중단 (서비스에 영향 없음) |
| Grafana | 1대 | 아님 | 대시보드 접근 불가 (서비스에 영향 없음) |

### 4.2 Nginx HA: keepalived + VIP 구성

Nginx SPOF를 해소하려면 2대 이상의 Nginx를 구성하고, keepalived로 VIP(Virtual IP)를 공유해야 한다.

```
                    ┌─────────────┐
                    │  VIP        │
                    │ 192.168.1.100│
                    └──────┬──────┘
                           │
                ┌──────────┴──────────┐
          ┌─────▼─────┐        ┌─────▼─────┐
          │ Nginx #1  │        │ Nginx #2  │
          │ (MASTER)  │        │ (BACKUP)  │
          │ .101      │        │ .102      │
          └───────────┘        └───────────┘
              keepalived ←VRRP→ keepalived
```

**keepalived 설정 (Master)**:
```conf
# /etc/keepalived/keepalived.conf (Nginx #1 - Master)
vrrp_script check_nginx {
    script "/usr/bin/curl -sf http://localhost/nginx-health"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass secure_password_here
    }
    virtual_ipaddress {
        192.168.1.100/24
    }
    track_script {
        check_nginx
    }
}
```

**keepalived 설정 (Backup)**:
```conf
# /etc/keepalived/keepalived.conf (Nginx #2 - Backup)
vrrp_script check_nginx {
    script "/usr/bin/curl -sf http://localhost/nginx-health"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass secure_password_here
    }
    virtual_ipaddress {
        192.168.1.100/24
    }
    track_script {
        check_nginx
    }
}
```

**Failover 동작**:
1. Master(Nginx #1)의 `check_nginx` 스크립트가 3회 연속 실패한다.
2. Master의 priority가 `100 - 20 = 80`으로 떨어진다.
3. Backup(Nginx #2)의 priority `90`이 더 높으므로 VIP가 Backup으로 이동한다.
4. 클라이언트는 VIP로 접속하므로 Failover를 인지하지 못한다.

### 4.3 MySQL HA

#### Master-Slave Replication

```
             ┌───────────┐
   Write ──▶ │  Master   │
             │  MySQL    │ ──Binlog──▶ ┌───────────┐
             └───────────┘             │  Slave    │
                                       │  MySQL    │ ◀── Read
                                       └───────────┘
```

**Master 설정** (`my.cnf`):
```ini
[mysqld]
server-id = 1
log-bin = mysql-bin
binlog-format = ROW
binlog-do-db = middleware_db
sync_binlog = 1
innodb_flush_log_at_trx_commit = 1
```

**Slave 설정** (`my.cnf`):
```ini
[mysqld]
server-id = 2
relay-log = relay-bin
read-only = 1
log-slave-updates = 1
```

**Replication 시작**:
```sql
-- Master에서 실행
CREATE USER 'repl_user'@'%' IDENTIFIED BY 'repl_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';
SHOW MASTER STATUS;  -- File, Position 확인

-- Slave에서 실행
CHANGE MASTER TO
  MASTER_HOST='mysql-master',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='repl_password',
  MASTER_LOG_FILE='mysql-bin.000001',
  MASTER_LOG_POS=154;
START SLAVE;
SHOW SLAVE STATUS\G  -- Slave_IO_Running, Slave_SQL_Running 확인
```

**특징**: Write는 Master만, Read는 Slave에서도 가능하다. Master 장애 시 Slave를 수동으로 Master로 승격해야 한다 (자동 Failover 없음).

#### Galera Cluster (Multi-Master)

```
      ┌─────────┐   ┌─────────┐   ┌─────────┐
      │ Node 1  │◀─▶│ Node 2  │◀─▶│ Node 3  │
      │ (R/W)   │   │ (R/W)   │   │ (R/W)   │
      └─────────┘   └─────────┘   └─────────┘
         Galera Synchronous Replication
```

**특징**: 모든 노드에서 Read/Write 가능하다. 동기식 복제로 데이터 일관성이 보장된다. 최소 3노드 구성이 필요하다 (Split-brain 방지). Master-Slave 대비 Write 성능이 다소 낮다 (합의 과정 필요).

### 4.4 Health Check 설계

각 컴포넌트별로 적절한 헬스체크 방법을 설계해야 한다.

| 컴포넌트 | 헬스체크 방법 | 확인 주기 | 판정 기준 |
|---------|------------|---------|---------|
| Nginx | `curl http://localhost/nginx-health` | 5초 | 3회 연속 실패 시 장애 |
| Tomcat | `curl http://localhost:8080/actuator/health` | 10초 | 3회 연속 실패 시 장애 |
| MySQL | `mysqladmin ping -h localhost` | 10초 | 5회 연속 실패 시 장애 |
| Keycloak | `curl http://localhost:8080/health/ready` | 15초 | 3회 연속 실패 시 장애 |
| Scouter | TCP 포트 6100 연결 확인 | 30초 | 3회 연속 실패 시 장애 |

**본 프로젝트 docker-compose.yml의 MySQL 헬스체크** (이미 구현됨):
```yaml
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
  interval: 10s
  timeout: 5s
  retries: 5
```

**Nginx upstream 수준의 헬스체크** (수동):
```nginx
upstream was_backend {
    server tomcat1:8080 max_fails=3 fail_timeout=30s;
    server tomcat2:8080 max_fails=3 fail_timeout=30s;
}
```

위 설정은 다음과 같이 동작한다:
- 특정 서버에 3회 연속 요청 실패 시(`max_fails=3`) 해당 서버를 30초간 비활성화한다(`fail_timeout=30s`).
- 30초 후 다시 요청을 보내 복구 여부를 확인한다.

### 4.5 Failover 시나리오별 동작

**시나리오 1: Tomcat1 장애**
```
1. Tomcat1 프로세스 비정상 종료
2. Nginx upstream에서 tomcat1:8080 연결 실패 감지 (max_fails 도달)
3. Nginx가 tomcat1을 upstream에서 일시 제외
4. 모든 트래픽이 Tomcat2로 전달됨
5. fail_timeout 경과 후 Nginx가 Tomcat1에 재연결 시도
6. Tomcat1 복구 시 자동으로 upstream에 재합류
```

**시나리오 2: MySQL 장애**
```
1. MySQL 프로세스 비정상 종료
2. Tomcat1, Tomcat2 모두 DB 연결 실패
3. 애플리케이션에서 Database Connection Error 발생
4. 사용자에게 500 에러 응답
5. MySQL 복구 필요 (현재 단일 구성이므로 자동 Failover 없음)
6. HikariCP Connection Pool이 자동으로 재연결 시도
```

**시나리오 3: Nginx 장애**
```
1. Nginx 프로세스 비정상 종료
2. 클라이언트 접속 불가 (전체 서비스 중단)
3. Docker restart policy로 자동 재시작 시도
4. 재시작 실패 시 수동 개입 필요
5. (HA 구성 시) keepalived가 VIP를 Backup Nginx로 전환
```

**Docker restart 정책 설정 (자동 복구)**:
```yaml
# docker-compose.yml에 추가
nginx:
  restart: unless-stopped  # 컨테이너 비정상 종료 시 자동 재시작

tomcat1:
  restart: unless-stopped

tomcat2:
  restart: unless-stopped

mysql:
  restart: unless-stopped
```

---

## 5. 네트워크 설계

### 5.1 3-Tier 네트워크 구조

프로덕션 환경에서는 보안을 위해 네트워크를 3개의 영역(Zone)으로 분리한다.

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                        ┌─────▼─────┐
                        │ Firewall  │
                        └─────┬─────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│  DMZ Zone (Frontend Network)                                     │
│  ┌─────────┐  ┌──────────┐                                      │
│  │  Nginx  │  │ Keycloak │   외부 접근 허용: 80, 443, 8080      │
│  └────┬────┘  └──────────┘                                      │
│       │                                                          │
├───────▼─────────────────────────────────────────────────────────┤
│  WAS Zone (Application Network)                                  │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌───────────┐        │
│  │Tomcat 1 │  │ Tomcat 2 │  │ Scouter  │  │Prometheus │        │
│  └────┬────┘  └────┬─────┘  └──────────┘  └───────────┘        │
│       │            │         외부 접근 차단, DMZ에서만 접근 가능   │
│       └──────┬─────┘                                             │
├──────────────▼──────────────────────────────────────────────────┤
│  DB Zone (Data Network)                                          │
│  ┌─────────┐                                                     │
│  │  MySQL  │   외부 접근 차단, WAS Zone에서만 접근 가능           │
│  └─────────┘                                                     │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Docker Network 종류

| 종류 | 설명 | 격리 | 성능 | 사용 시기 |
|------|------|------|------|---------|
| **bridge** | 가상 브릿지를 통한 격리된 네트워크 | 높음 | 보통 | 단일 호스트 환경 (기본값) |
| **host** | 호스트 네트워크 스택을 공유 | 없음 | 높음 | 최대 성능이 필요할 때 |
| **overlay** | 멀티 호스트 간 네트워크 연결 | 높음 | 낮음 | Docker Swarm/멀티 호스트 |
| **macvlan** | 컨테이너에 실제 MAC 주소 부여 | 높음 | 높음 | 레거시 시스템 연동 |
| **none** | 네트워크 비활성화 | 완전 격리 | N/A | 네트워크 불필요한 배치 작업 |

본 프로젝트는 **bridge** 네트워크를 사용한다:
```yaml
networks:
  mw-network:
    driver: bridge
```

### 5.3 네트워크 분리 설계 (개선안)

현재 프로젝트는 단일 네트워크(`mw-network`)를 사용하지만, 프로덕션 환경에서는 다음과 같이 분리해야 한다:

```yaml
# docker-compose.yml (네트워크 분리 개선안)
networks:
  frontend-net:      # DMZ Zone
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
  backend-net:       # WAS Zone
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.1.0/24
  db-net:            # DB Zone
    driver: bridge
    internal: true   # 외부 접근 차단
    ipam:
      config:
        - subnet: 172.20.2.0/24
  monitoring-net:    # Monitoring Zone
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.3.0/24

services:
  nginx:
    networks:
      - frontend-net   # 외부 트래픽 수신
      - backend-net    # WAS로 프록시

  tomcat1:
    networks:
      - backend-net    # Nginx로부터 요청 수신
      - db-net         # MySQL 접근
      - monitoring-net # 메트릭 노출

  tomcat2:
    networks:
      - backend-net
      - db-net
      - monitoring-net

  mysql:
    networks:
      - db-net         # WAS에서만 접근 가능

  keycloak:
    networks:
      - frontend-net   # 외부 인증 요청 수신
      - db-net         # 자체 DB 접근 (필요 시)

  prometheus:
    networks:
      - monitoring-net # 메트릭 수집
      - backend-net    # WAS 메트릭 스크래핑

  grafana:
    networks:
      - monitoring-net # Prometheus 접근
      - frontend-net   # 대시보드 외부 접근
```

**네트워크 격리 효과**:
- MySQL은 `db-net`에만 연결되어 WAS만 접근 가능하다.
- `internal: true` 설정으로 DB Zone에서 외부로의 아웃바운드 트래픽도 차단된다.
- Nginx는 `frontend-net`과 `backend-net`을 모두 가지므로 두 Zone을 연결하는 게이트웨이 역할을 한다.

### 5.4 포트 매핑 전략과 보안 고려사항

**현재 프로젝트의 포트 매핑**:

| 서비스 | 컨테이너 포트 | 호스트 매핑 | 외부 노출 필요 여부 |
|--------|-------------|-----------|------------------|
| Nginx | 80, 443 | 80, 443 | O (서비스 진입점) |
| Tomcat1 | 8080 | 매핑 없음 | X (Nginx 경유) |
| Tomcat2 | 8080 | 매핑 없음 | X (Nginx 경유) |
| MySQL | 3306 | 3306 | X (개발 환경에서만) |
| Keycloak | 8080 | 8080 | O (인증 서비스) |
| Scouter | 6100, 6180 | 6100, 6180 | 내부만 |
| Prometheus | 9090 | 9090 | 내부만 |
| Grafana | 3000 | 3000 | 내부만 |

**프로덕션 보안 권장 사항**:
```yaml
# 프로덕션에서는 외부 노출 최소화
mysql:
  ports: []  # 호스트 포트 매핑 제거 (Docker 네트워크 내부에서만 접근)
  # 또는 로컬만 허용:
  # ports:
  #   - "127.0.0.1:3306:3306"

# 모니터링 도구도 로컬에서만 접근
prometheus:
  ports:
    - "127.0.0.1:9090:9090"

grafana:
  ports:
    - "127.0.0.1:3000:3000"
```

### 5.5 방화벽 규칙 설계

**iptables 기본 규칙**:
```bash
#!/bin/bash
# firewall-rules.sh

# 기본 정책: 모든 인바운드 차단
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Loopback 허용
iptables -A INPUT -i lo -j ACCEPT

# 기존 연결 유지
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH (관리용)
iptables -A INPUT -p tcp --dport 22 -s 관리자_IP/32 -j ACCEPT

# HTTP/HTTPS (서비스)
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Keycloak (인증 서비스)
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# Grafana (내부 네트워크에서만)
iptables -A INPUT -p tcp --dport 3000 -s 10.0.0.0/8 -j ACCEPT

# Prometheus (내부 네트워크에서만)
iptables -A INPUT -p tcp --dport 9090 -s 10.0.0.0/8 -j ACCEPT

# Scouter (내부 네트워크에서만)
iptables -A INPUT -p tcp --dport 6100 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 6180 -s 10.0.0.0/8 -j ACCEPT

# MySQL (직접 외부 접근 차단 - Docker 네트워크 내부에서만)
# iptables -A INPUT -p tcp --dport 3306 -j DROP
```

### 5.6 네트워크 다이어그램

```
                              Internet
                                 │
                          ┌──────▼──────┐
                          │  Firewall   │
                          │  80,443     │
                          └──────┬──────┘
                                 │
═══════════════════════════════╪══════════════════  DMZ Zone (172.20.0.0/24)
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
        ┌─────▼─────┐    ┌──────▼──────┐    ┌──────▼──────┐
        │   Nginx   │    │  Keycloak   │    │   Grafana   │
        │  :80/:443 │    │   :8080     │    │   :3000     │
        └─────┬─────┘    └─────────────┘    └──────┬──────┘
              │                                     │
═════════════╪═════════════════════════════════════╪═  WAS Zone (172.20.1.0/24)
              │                                     │
       ┌──────┴──────┐                       ┌──────▼──────┐
       │             │                       │ Prometheus  │
  ┌────▼────┐  ┌─────▼────┐                 │   :9090     │
  │Tomcat 1 │  │ Tomcat 2 │                 └──────┬──────┘
  │  :8080  │  │  :8080   │                        │
  └────┬────┘  └─────┬────┘   ┌────────────┐ ┌────▼────────┐
       │             │        │  Scouter   │ │Node Exporter│
       │             │        │ :6100/6180 │ │   :9100     │
       │             │        └────────────┘ └─────────────┘
═══════╪═════════════╪══════════════════════════════════════  DB Zone (172.20.2.0/24)
       │             │                                         internal: true
       └──────┬──────┘
        ┌─────▼─────┐
        │   MySQL   │
        │   :3306   │
        └───────────┘
```

---

## 6. 용량 계획 (Capacity Planning)

### 6.1 동시 사용자 수에서 필요 TPS 계산

**핵심 공식**:
```
TPS = 동시 사용자 수 (CCU) × 사용자당 초당 요청 수

사용자당 초당 요청 수 = 페이지당 요청 수 / 평균 체류 시간(초)
```

**예시**: 동시 사용자 1,000명, 페이지당 평균 5개 요청, 평균 체류 시간 30초
```
사용자당 초당 요청 수 = 5 / 30 = 0.167 요청/초
TPS = 1,000 × 0.167 = 약 167 TPS
```

**피크 시간 고려**: 일반적으로 피크 TPS는 평균의 2~3배이다.
```
피크 TPS = 167 × 3 = 약 500 TPS
```

### 6.2 TPS에서 서버 스펙 산정

**CPU 산정**:
```
필요 CPU 코어 수 = 피크 TPS × 요청당 평균 CPU 사용 시간(초)

예시: 500 TPS × 0.05초 = 25 CPU 코어
WAS 2대 구성 시: 서버당 약 13코어 (여유분 포함 16코어 권장)
```

**메모리 산정**:
```
필요 메모리 = JVM Heap + 스레드 스택 + OS 오버헤드 + 버퍼

JVM Heap: Xmx 값 (본 프로젝트: 512MB)
스레드 스택: maxThreads × 1MB (기본 스택 크기)
OS 오버헤드: 약 500MB
버퍼/여유분: 30%

예시: 512MB + (200 × 1MB) + 500MB = 1,212MB → 여유분 포함 약 2GB
```

**디스크 산정**:
```
필요 디스크 = OS + 애플리케이션 + 로그 + 임시파일

OS: 10GB
Docker 이미지: 5GB
애플리케이션 로그: 일 500MB × 보관일수 30일 = 15GB
MySQL 데이터: 예상 데이터 크기 × 2 (인덱스/임시테이블 포함)
```

### 6.3 Tomcat maxThreads 계산 공식

**핵심 공식**:
```
maxThreads = (목표 TPS × 평균 응답 시간(초)) + 여유분

또는

maxThreads = 목표 동시 처리 수 × 1.5 (안전 마진)
```

**상세 산정 과정**:
```
목표 TPS: 250 (WAS 1대 기준, 2대 중 1대)
평균 응답 시간: 0.2초 (200ms)

최소 필요 스레드 = 250 × 0.2 = 50개
안전 마진 적용 (1.5배): 50 × 1.5 = 75개
반올림: 100개 (일반적으로 50, 100, 200 단위로 설정)
```

**Tomcat server.xml 설정**:
```xml
<Connector port="8080" protocol="HTTP/1.1"
           maxThreads="200"
           minSpareThreads="25"
           acceptCount="100"
           connectionTimeout="20000"
           maxConnections="8192" />
```

| 파라미터 | 의미 | 권장값 |
|---------|------|-------|
| `maxThreads` | 최대 워커 스레드 수 | 요청 패턴에 따라 100~400 |
| `minSpareThreads` | 유휴 상태 유지 최소 스레드 | maxThreads의 10~25% |
| `acceptCount` | 모든 스레드 사용 시 대기열 크기 | maxThreads의 50~100% |
| `maxConnections` | 최대 동시 연결 수 | NIO 기본값 8192 |

**주의**: `maxThreads`를 과도하게 높이면 컨텍스트 스위칭 오버헤드와 메모리 사용량이 증가한다. 부하 테스트를 통해 최적값을 찾아야 한다.

### 6.4 DB Connection Pool 크기 계산 공식

**핵심 공식 (HikariCP 권장)**:
```
Pool Size = (CPU 코어 수 × 2) + 유효 디스크 수

예시: 4코어 서버, SSD 1개
Pool Size = (4 × 2) + 1 = 9
```

이 공식은 PostgreSQL 위키에서 제안한 것으로, MySQL에도 적용 가능하다. 핵심 원리는 디스크 I/O 대기 시간 동안 다른 커넥션이 CPU를 활용할 수 있도록 하는 것이다.

**WAS별 설정 (application.yml)**:
```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10        # 위 공식 기반
      minimum-idle: 5              # 최소 유휴 커넥션
      idle-timeout: 600000         # 10분 (유휴 커넥션 해제 시간)
      max-lifetime: 1800000        # 30분 (커넥션 최대 수명)
      connection-timeout: 30000    # 30초 (커넥션 획득 대기 시간)
      leak-detection-threshold: 60000  # 1분 (커넥션 누수 감지)
```

**MySQL max_connections 산정**:
```
max_connections = (WAS 수 × Pool Size) + 관리/모니터링 여유분

예시: WAS 2대 × Pool 10개 + 여유 10개 = 30
```

```ini
# my.cnf
[mysqld]
max_connections = 30
```

### 6.5 동시 1,000명 사용자 기준 전체 산정 예시

**전제 조건**:
- 동시 사용자(CCU): 1,000명
- 페이지당 요청: 5개 (API 호출)
- 평균 체류 시간: 30초
- 평균 응답 시간: 200ms
- 피크 배율: 3배

**산정 결과**:

| 항목 | 계산 과정 | 결과 |
|------|---------|------|
| 평균 TPS | 1,000 × (5/30) | 167 TPS |
| 피크 TPS | 167 × 3 | 500 TPS |
| WAS당 TPS | 500 / 2 | 250 TPS |
| Tomcat maxThreads | 250 × 0.2 × 1.5 | 75 → **100** (반올림) |
| DB Pool Size/WAS | (4 × 2) + 1 | **10** |
| MySQL max_connections | (2 × 10) + 10 | **30** |
| JVM Heap (Xmx) | 실측 기반 | **1GB** |
| 서버당 메모리 | 1GB + 100MB + 500MB + 30% | **약 2.5GB** |
| 서버당 CPU | 250 × 0.05 × 1.5 | **약 4코어** |

**인프라 구성 요약**:
```
Nginx:     1대 (2 CPU, 2GB RAM)
Tomcat:    2대 (4 CPU, 2.5GB RAM 각각)
MySQL:     1대 (4 CPU, 4GB RAM, SSD 100GB)
Keycloak:  1대 (2 CPU, 2GB RAM)
Monitoring: 1대 (2 CPU, 4GB RAM) - Prometheus + Grafana + Scouter
────────────────────────────────────────
합계:       약 16 CPU, 17GB RAM
```

---

## 7. 백업 및 복구 전략

### 7.1 MySQL 백업

#### mysqldump (논리적 백업)

**전체 백업**:
```bash
# 전체 데이터베이스 백업
docker exec mw-mysql mysqldump \
  -u root \
  -proot_password \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --all-databases > backup_$(date +%Y%m%d_%H%M%S).sql

# 특정 데이터베이스만 백업
docker exec mw-mysql mysqldump \
  -u root \
  -proot_password \
  --single-transaction \
  middleware_db > middleware_db_$(date +%Y%m%d_%H%M%S).sql
```

**주요 옵션 설명**:
- `--single-transaction`: InnoDB 테이블을 트랜잭션 내에서 일관된 상태로 백업 (테이블 락 없음)
- `--routines`: 스토어드 프로시저/함수 포함
- `--triggers`: 트리거 포함
- `--events`: 이벤트 스케줄러 포함

**장점**: 이식성이 높다 (SQL 텍스트). MySQL 버전 간 호환 가능.
**단점**: 대용량 DB에서 백업/복원 시간이 길다. 백업 중 성능 영향.

#### Percona XtraBackup (물리적 백업)

```bash
# 전체 백업 (Hot Backup - 서비스 중단 없음)
docker exec mw-mysql xtrabackup \
  --backup \
  --target-dir=/var/lib/mysql/backup \
  --user=root \
  --password=root_password

# 증분 백업 (전체 백업 이후 변경분만)
docker exec mw-mysql xtrabackup \
  --backup \
  --target-dir=/var/lib/mysql/backup_inc_1 \
  --incremental-basedir=/var/lib/mysql/backup \
  --user=root \
  --password=root_password

# 복원 준비
docker exec mw-mysql xtrabackup --prepare --target-dir=/var/lib/mysql/backup
```

**장점**: 대용량 DB에서도 빠르다. Hot Backup (서비스 중단 없음). 증분 백업 지원.
**단점**: MySQL/Percona Server 전용. 복원 시 서비스 중지 필요.

### 7.2 설정 파일 백업: Git 기반 형상 관리

본 프로젝트는 이미 Git으로 설정 파일을 관리하고 있다. 관리 대상:

```
configs/
├── nginx/
│   ├── nginx.conf              # Nginx 메인 설정
│   └── conf.d/default.conf     # 가상 호스트/upstream 설정
├── tomcat/
│   ├── tomcat1/server.xml      # Tomcat1 설정
│   └── tomcat2/server.xml      # Tomcat2 설정
├── scouter/
│   ├── server.conf             # Scouter 서버 설정
│   └── agent.conf              # Scouter 에이전트 설정
├── prometheus/
│   └── prometheus.yml          # Prometheus 스크래핑 설정
├── grafana/
│   └── provisioning/           # 데이터소스/대시보드 프로비저닝
└── keycloak/
    └── realm-export.json       # Keycloak Realm 설정
```

**권장 사항**:
- `.env` 파일에 민감 정보(패스워드 등)를 분리하고 `.gitignore`에 추가
- 설정 변경 시 반드시 커밋 메시지에 변경 이유를 기록
- 태그를 활용하여 안정 버전 표시 (`git tag v1.0.0-stable`)

### 7.3 Docker Volume 백업

```bash
#!/bin/bash
# docker-volume-backup.sh

BACKUP_DIR="/opt/backups/docker-volumes"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# MySQL 데이터 볼륨 백업
docker run --rm \
  -v middle_ware_mysql_data:/source:ro \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/mysql_data_${DATE}.tar.gz -C /source .

# Prometheus 데이터 볼륨 백업
docker run --rm \
  -v middle_ware_prometheus_data:/source:ro \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/prometheus_data_${DATE}.tar.gz -C /source .

# Grafana 데이터 볼륨 백업
docker run --rm \
  -v middle_ware_grafana_data:/source:ro \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/grafana_data_${DATE}.tar.gz -C /source .

# Keycloak 데이터 볼륨 백업
docker run --rm \
  -v middle_ware_keycloak_data:/source:ro \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/keycloak_data_${DATE}.tar.gz -C /source .

# 오래된 백업 삭제 (30일 이상)
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Volume backup completed: $DATE"
```

### 7.4 RPO / RTO 정의

| 용어 | 정의 | 의미 |
|------|------|------|
| **RPO** (Recovery Point Objective) | 복구 시점 목표 | 최대 몇 시간 전의 데이터까지 손실을 허용할 수 있는가? |
| **RTO** (Recovery Time Objective) | 복구 시간 목표 | 장애 발생 후 몇 시간 이내에 서비스를 복구해야 하는가? |

**본 프로젝트 RPO/RTO 설정**:

| 컴포넌트 | RPO | RTO | 백업 주기 | 비고 |
|---------|-----|-----|---------|------|
| MySQL | 1시간 | 30분 | 매시간 mysqldump | 가장 중요한 데이터 |
| 설정 파일 | 0 (Git) | 10분 | 변경 시 즉시 커밋 | Git에서 즉시 복원 |
| Docker Volume | 24시간 | 1시간 | 일 1회 야간 백업 | 재구축 가능한 데이터 |
| Keycloak | 24시간 | 1시간 | 일 1회 | realm-export.json 백업 |

### 7.5 복구 절차 (DR Plan)

#### MySQL 복구
```bash
# 1. 서비스 중지
docker compose stop tomcat1 tomcat2

# 2. MySQL 컨테이너에 백업 파일 복원
docker exec -i mw-mysql mysql \
  -u root \
  -proot_password \
  middleware_db < backup_20260312_030000.sql

# 3. 데이터 정합성 확인
docker exec mw-mysql mysql \
  -u root \
  -proot_password \
  -e "SELECT COUNT(*) FROM middleware_db.users;"

# 4. 서비스 재시작
docker compose start tomcat1 tomcat2
```

#### Docker Volume 복구
```bash
# 1. 대상 서비스 중지
docker compose stop mysql

# 2. 기존 볼륨 삭제
docker volume rm middle_ware_mysql_data

# 3. 새 볼륨 생성 및 백업 복원
docker volume create middle_ware_mysql_data
docker run --rm \
  -v middle_ware_mysql_data:/target \
  -v /opt/backups/docker-volumes:/backup:ro \
  alpine tar xzf /backup/mysql_data_20260312_030000.tar.gz -C /target

# 4. 서비스 재시작
docker compose start mysql
```

#### 전체 환경 재구축 (최악의 경우)
```bash
# 1. Git에서 프로젝트 클론
git clone <repository-url> middle_ware
cd middle_ware

# 2. 환경 변수 설정
cp .env.example .env
# .env 파일 편집

# 3. 전체 서비스 빌드 및 시작
docker compose build
docker compose up -d

# 4. MySQL 데이터 복원
docker exec -i mw-mysql mysql -u root -proot_password middleware_db < latest_backup.sql

# 5. Keycloak Realm 복원 (realm-export.json이 마운트되어 자동 임포트)

# 6. 서비스 정상 동작 확인
curl -k https://localhost/
curl http://localhost:9090/targets  # Prometheus targets 확인
```

### 7.6 백업 스크립트 자동화 (cron)

```bash
# crontab -e

# MySQL 전체 백업: 매시간 정각
0 * * * * /opt/scripts/mysql-backup.sh >> /var/log/backup.log 2>&1

# Docker Volume 백업: 매일 새벽 3시
0 3 * * * /opt/scripts/docker-volume-backup.sh >> /var/log/backup.log 2>&1

# 오래된 백업 정리: 매일 새벽 4시
0 4 * * * find /opt/backups -name "*.sql" -mtime +7 -delete
0 4 * * * find /opt/backups -name "*.tar.gz" -mtime +30 -delete
```

**mysql-backup.sh**:
```bash
#!/bin/bash
set -e

BACKUP_DIR="/opt/backups/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

echo "[$(date)] MySQL 백업 시작..."

docker exec mw-mysql mysqldump \
  -u root \
  -proot_password \
  --single-transaction \
  --routines \
  --triggers \
  middleware_db | gzip > ${BACKUP_DIR}/middleware_db_${DATE}.sql.gz

FILESIZE=$(du -h ${BACKUP_DIR}/middleware_db_${DATE}.sql.gz | cut -f1)
echo "[$(date)] MySQL 백업 완료: middleware_db_${DATE}.sql.gz (${FILESIZE})"

# 오래된 백업 삭제
DELETED=$(find $BACKUP_DIR -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
echo "[$(date)] 삭제된 오래된 백업: ${DELETED}개"
```

---

## 8. 확장성 설계

### 8.1 Scale Up vs Scale Out

| 구분 | Scale Up (수직 확장) | Scale Out (수평 확장) |
|------|---------------------|---------------------|
| 방법 | CPU/RAM/Disk 증설 | 서버 대수 추가 |
| 비용 | 고사양 하드웨어 비용 급증 | 서버 수에 비례하여 선형 증가 |
| 한계 | 물리적 한계 존재 | 이론적으로 무한 확장 |
| 복잡도 | 낮음 (설정 변경만) | 높음 (로드밸런싱, 세션 등) |
| 가용성 | SPOF 해소 불가 | 다중화로 HA 확보 |
| 적합 대상 | DB (MySQL), 캐시 | WAS (Tomcat), Web (Nginx) |

**본 프로젝트의 확장 방향**:
- **Tomcat (WAS)**: Scale Out 우선 (2대 → N대)
- **MySQL (DB)**: Scale Up 우선, 이후 Read Replica 추가 (Scale Out)
- **Nginx (Web)**: Scale Up 우선 (단일 Nginx로 상당한 트래픽 처리 가능)

### 8.2 수평 확장: WAS 추가

Tomcat 인스턴스를 2대에서 5대로 확장하는 과정:

**1단계: docker-compose.yml에 서비스 추가**:
```yaml
tomcat3:
  build:
    context: ./app
    dockerfile: Dockerfile
  container_name: mw-tomcat3
  environment:
    JAVA_OPTS: >-
      -Xms256m -Xmx512m
      -DjvmRoute=tomcat3
      -Dserver.port=8080
      -javaagent:/opt/scouter/agent.java/scouter.agent.jar
      -Dscouter.config=/opt/scouter-conf/agent.conf
      -Dobj_name=tomcat3
  volumes:
    - ./configs/tomcat/tomcat3/server.xml:/usr/local/tomcat/conf/server.xml:ro
    - ./configs/scouter/agent.conf:/opt/scouter-conf/agent.conf:ro
    - tomcat3_logs:/usr/local/tomcat/logs
  networks:
    - mw-network
  depends_on:
    mysql:
      condition: service_healthy

# tomcat4, tomcat5 도 동일 패턴으로 추가
```

**2단계: Nginx upstream에 서버 추가**:
```nginx
upstream was_backend {
    server tomcat1:8080 weight=1;
    server tomcat2:8080 weight=1;
    server tomcat3:8080 weight=1;
    server tomcat4:8080 weight=1;
    server tomcat5:8080 weight=1;
}
```

**3단계: Prometheus 스크래핑 대상 추가**:
```yaml
- job_name: "tomcat3"
  metrics_path: "/actuator/prometheus"
  static_configs:
    - targets: ["tomcat3:8080"]
      labels:
        instance: "tomcat3"

# tomcat4, tomcat5 도 동일하게 추가
```

**4단계: MySQL Connection Pool 재계산**:
```
기존: max_connections = (2 × 10) + 10 = 30
변경: max_connections = (5 × 10) + 10 = 60
```

**5단계: 적용**:
```bash
docker compose up -d --build
docker exec mw-nginx nginx -s reload
```

### 8.3 Docker Compose --scale 활용

`docker compose --scale`을 사용하면 서비스 정의를 복제하지 않고 인스턴스 수를 조절할 수 있다. 단, 고정 `container_name`과 포트 매핑이 있으면 충돌하므로 수정이 필요하다.

```yaml
# docker-compose.yml 수정 (scale 대응)
tomcat:
  build:
    context: ./app
    dockerfile: Dockerfile
  # container_name 제거 (자동 부여)
  environment:
    JAVA_OPTS: >-
      -Xms256m -Xmx512m
      -Dserver.port=8080
      -javaagent:/opt/scouter/agent.java/scouter.agent.jar
      -Dscouter.config=/opt/scouter-conf/agent.conf
  # ports 매핑 제거 (Docker 네트워크 내부에서만 접근)
  networks:
    - mw-network
  depends_on:
    mysql:
      condition: service_healthy
  deploy:
    replicas: 3   # 기본 인스턴스 수
```

```bash
# 인스턴스 5개로 확장
docker compose up -d --scale tomcat=5

# 인스턴스 2개로 축소
docker compose up -d --scale tomcat=2
```

**Nginx upstream 동적 해석** (DNS 기반):
```nginx
upstream was_backend {
    # Docker DNS가 여러 IP를 반환하면 자동으로 분산
    server tomcat:8080;

    # DNS 재해석 주기 (Nginx Plus 또는 resolver 설정 필요)
}

# resolver 설정 (Docker 내장 DNS)
resolver 127.0.0.11 valid=10s;
```

### 8.4 향후 확장 로드맵: Kubernetes 마이그레이션

Docker Compose에서 Kubernetes로 마이그레이션할 때 고려해야 할 사항:

**현재 Docker Compose 리소스 → Kubernetes 리소스 매핑**:

| Docker Compose | Kubernetes | 비고 |
|---------------|-----------|------|
| `services` | `Deployment` + `Service` | Pod 관리 + 서비스 디스커버리 |
| `volumes` | `PersistentVolumeClaim` | 동적 프로비저닝 |
| `networks` | `NetworkPolicy` | Pod 간 통신 규칙 |
| `ports` | `Service` (ClusterIP/NodePort/LoadBalancer) | 노출 방식 선택 |
| `depends_on` | `initContainers` / `readinessProbe` | 기동 순서 제어 |
| `environment` | `ConfigMap` / `Secret` | 설정/민감 정보 분리 |
| `docker-compose.yml` | `Helm Chart` | 패키징/배포 관리 |

**마이그레이션 단계**:

```
Phase 1: 컨테이너화 완료 (현재)
  - Docker Compose 기반 개발/테스트 환경
  - CI/CD 파이프라인 구축

Phase 2: Kubernetes 전환
  - Kompose 도구로 초기 변환: kompose convert -f docker-compose.yml
  - Deployment/Service YAML 작성
  - Helm Chart 패키징
  - Ingress Controller 설정 (Nginx → Kubernetes Ingress)

Phase 3: 클라우드 네이티브 고도화
  - HPA (Horizontal Pod Autoscaler) 적용
  - PDB (Pod Disruption Budget) 설정
  - Service Mesh (Istio) 도입 검토
  - GitOps (ArgoCD) 적용
```

**Kubernetes 마이그레이션 시 특별히 주의할 점**:

1. **상태 관리**: MySQL, Keycloak 등 상태를 가진 서비스는 `StatefulSet`으로 배포해야 한다. `Deployment`는 무상태 서비스에 적합하다.

2. **스토리지**: Docker Volume은 호스트 로컬이지만, Kubernetes PV는 클러스터 전체에서 접근 가능한 스토리지(NFS, EBS 등)가 필요하다.

3. **네트워크**: Docker Compose의 서비스 이름 기반 DNS는 Kubernetes Service로 대체된다. 서비스 이름이 변경될 수 있으므로 애플리케이션 설정을 확인해야 한다.

4. **모니터링**: Prometheus는 Kubernetes에서 ServiceMonitor CRD를 통해 자동 디스커버리가 가능하다. 기존 static_configs를 kubernetes_sd_configs로 전환한다.

### 8.5 마이크로서비스 전환 시 고려사항

현재 모놀리식 Spring Boot 애플리케이션을 마이크로서비스로 전환할 때:

```
현재 (Monolith):
┌──────────────────────────┐
│     Spring Boot App      │
│  ┌─────┐ ┌─────┐ ┌────┐ │
│  │User │ │Order│ │Pay │ │
│  │Svc  │ │Svc  │ │Svc │ │
│  └─────┘ └─────┘ └────┘ │
│         단일 DB           │
└──────────────────────────┘

향후 (Microservices):
┌────────┐  ┌────────┐  ┌────────┐
│User Svc│  │Order   │  │Payment │
│+ DB    │  │Svc + DB│  │Svc + DB│
└────┬───┘  └───┬────┘  └───┬────┘
     └──────────┼────────────┘
         API Gateway (Nginx/Kong)
          + Service Mesh (Istio)
```

**주요 고려사항**:

| 항목 | 모놀리식 (현재) | 마이크로서비스 (향후) |
|------|---------------|-------------------|
| 배포 단위 | 전체 애플리케이션 | 개별 서비스 |
| 데이터베이스 | 공유 DB | 서비스별 독립 DB |
| 서비스 간 통신 | 메서드 호출 | REST/gRPC/이벤트 |
| 트랜잭션 | ACID (단일 DB) | Saga 패턴 |
| 인증 | Keycloak JWT (유지) | Keycloak JWT (유지 가능) |
| 모니터링 | Scouter/Prometheus | 분산 추적 (Jaeger/Zipkin) 추가 필요 |

---

## 9. 인프라 설계 체크리스트

프로덕션 투입 전 반드시 확인해야 하는 항목을 카테고리별로 정리한다.

### 보안

| # | 확인 항목 | 상태 | 비고 |
|---|---------|------|------|
| 1 | HTTPS(TLS 1.2+) 적용 여부 | | SSL 인증서 유효기간 확인 |
| 2 | 기본 계정 패스워드 변경 | | MySQL root, Keycloak admin, Grafana admin |
| 3 | 불필요한 포트 외부 노출 차단 | | MySQL 3306, Prometheus 9090 등 |
| 4 | 방화벽 규칙 설정 | | iptables/nftables/Security Group |
| 5 | 환경 변수에 민감 정보 분리 | | .env 파일 또는 Secret Manager |
| 6 | Docker 이미지 취약점 스캔 | | Trivy, Snyk 등 |
| 7 | 네트워크 분리 (DMZ/WAS/DB) | | docker network 또는 VPC Subnet |
| 8 | HSTS 헤더 설정 | | Nginx에서 설정 |
| 9 | X-Frame-Options, CSP 헤더 | | 클릭재킹/XSS 방어 |
| 10 | SQL Injection 방어 | | PreparedStatement 사용 확인 |

### 가용성

| # | 확인 항목 | 상태 | 비고 |
|---|---------|------|------|
| 1 | WAS 이중화 구성 | | Tomcat 2대 이상 |
| 2 | 로드밸런서 헬스체크 설정 | | max_fails, fail_timeout |
| 3 | Docker restart policy 설정 | | unless-stopped 또는 always |
| 4 | DB 백업 자동화 | | cron 스케줄 확인 |
| 5 | 복구 절차 문서화 및 테스트 | | DR 드릴 주기적 실행 |
| 6 | SPOF 식별 및 대응 방안 수립 | | Nginx, MySQL |
| 7 | 장애 알림 설정 | | Grafana Alert / Scouter Alert |
| 8 | RPO/RTO 정의 및 달성 가능 확인 | | 백업 주기와 복원 시간 측정 |

### 성능

| # | 확인 항목 | 상태 | 비고 |
|---|---------|------|------|
| 1 | JVM Heap 크기 적정성 | | Xms/Xmx, GC 로그 분석 |
| 2 | Tomcat maxThreads 설정 | | 부하 테스트 기반 산정 |
| 3 | DB Connection Pool 크기 | | HikariCP 설정 확인 |
| 4 | MySQL max_connections | | WAS 수 × Pool Size + 여유분 |
| 5 | Nginx worker_connections | | 예상 동시 접속 수 기반 |
| 6 | Gzip 압축 활성화 | | 텍스트 기반 리소스 |
| 7 | 정적 리소스 캐싱 설정 | | expires, Cache-Control |
| 8 | 부하 테스트 수행 | | JMeter, k6, wrk 등 |
| 9 | 슬로우 쿼리 로깅 활성화 | | long_query_time 설정 |
| 10 | 인덱스 최적화 | | EXPLAIN 분석 |

### 모니터링

| # | 확인 항목 | 상태 | 비고 |
|---|---------|------|------|
| 1 | Prometheus 메트릭 수집 정상 | | /targets 페이지 확인 |
| 2 | Grafana 대시보드 구성 | | 주요 지표 시각화 |
| 3 | Scouter APM 연결 상태 | | 에이전트-서버 통신 확인 |
| 4 | 로그 수집 체계 구축 | | ELK/Loki 등 중앙 집중 로깅 |
| 5 | 알림 임계값 설정 | | CPU > 80%, 메모리 > 85%, 에러율 > 1% |
| 6 | 디스크 사용량 모니터링 | | 로그/데이터 볼륨 증가 감시 |
| 7 | SSL 인증서 만료 모니터링 | | 만료 30일 전 알림 |

### 배포

| # | 확인 항목 | 상태 | 비고 |
|---|---------|------|------|
| 1 | 배포 전략 결정 및 문서화 | | Rolling/Blue-Green/Canary |
| 2 | 롤백 절차 문서화 | | 이전 이미지 태그 관리 |
| 3 | 배포 스크립트 작성 및 테스트 | | 자동화 수준 확인 |
| 4 | Docker 이미지 태깅 전략 | | latest 사용 금지, 버전 태그 |
| 5 | CI/CD 파이프라인 구축 | | Jenkins/GitHub Actions/GitLab CI |
| 6 | 환경별 설정 분리 | | dev/staging/prod |

### 문서화

| # | 확인 항목 | 상태 | 비고 |
|---|---------|------|------|
| 1 | 아키텍처 다이어그램 | | 최신 상태 유지 |
| 2 | 운영 매뉴얼 (Runbook) | | 장애 대응 절차 |
| 3 | API 명세서 | | Swagger/OpenAPI |
| 4 | 트러블슈팅 가이드 | | 자주 발생하는 문제와 해결법 |
| 5 | 온보딩 문서 | | 신규 팀원용 환경 구축 가이드 |

---

> **참고**: 본 문서는 Docker Compose 기반의 개발/스테이징 환경을 전제로 작성되었다. 프로덕션 환경에서는 Kubernetes, 클라우드 매니지드 서비스(RDS, ELB 등), 전용 CI/CD 파이프라인 등 추가적인 인프라 고도화가 필요하다.

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [아키텍처 설계](architecture.md) | 전체 아키텍처 개요 |
| [성능 튜닝 가이드](performance-tuning.md) | 리소스 최적화 |
| [장애 대응 매뉴얼](incident-response.md) | 장애 복구 매뉴얼 |
| [보안 심층 분석](security-deep-dive.md) | 보안 인프라 설계 |
