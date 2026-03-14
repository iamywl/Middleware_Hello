# 트러블슈팅 가이드

## 장애 시나리오 #1: WAS 1대 다운 → Nginx 자동 페일오버

### 증상
- 브라우저 접속 시 간헐적으로 502 Bad Gateway 발생 후 정상 복구
- Scouter에서 특정 Tomcat 인스턴스 모니터링 데이터 소실

### 원인 분석
```bash
# 컨테이너 상태 확인
docker compose ps

# Tomcat 로그 확인
docker logs mw-tomcat1 --tail 50
docker logs mw-tomcat2 --tail 50

# Nginx error log에서 upstream 에러 확인
docker exec mw-nginx tail -20 /var/log/nginx/error.log
```

### 확인된 동작
Nginx upstream의 `Round Robin`이 장애 서버를 자동 감지하여 정상 서버로 트래픽을 전환한다.

```
[정상] Client → Nginx → Tomcat1 (OK) or Tomcat2 (OK)
[장애] Client → Nginx → Tomcat1 (DOWN) → 자동 Tomcat2로 전환
```

### 조치
```bash
# 1. 장애 Tomcat 로그 확인
docker logs mw-tomcat1

# 2. 컨테이너 재시작
docker compose restart tomcat1

# 3. 정상 복구 확인
curl -sfk https://localhost/health
```

### 재발 방지
- Nginx `max_fails`와 `fail_timeout` 설정으로 빠른 감지
- health-check.sh 스크립트를 crontab에 등록하여 자동 감지

---

## 장애 시나리오 #2: OOM (Out of Memory) 발생

### 증상
- 응답 시간 급격히 증가 (Scouter에서 확인)
- Tomcat 프로세스가 갑자기 종료
- 로그에 `java.lang.OutOfMemoryError: Java heap space` 출력

### 원인 분석
```bash
# JVM 힙 메모리 현황 확인
docker exec mw-tomcat1 jcmd 1 GC.heap_info

# GC 로그 확인 (Scouter에서 실시간 확인 가능)
docker logs mw-tomcat1 | grep -i "GC\|OutOfMemory\|heap"

# 힙 덤프 생성 (분석용)
docker exec mw-tomcat1 jmap -dump:live,format=b,file=/tmp/heapdump.hprof 1
docker cp mw-tomcat1:/tmp/heapdump.hprof ./heapdump.hprof
```

### JVM 튜닝 조치
docker-compose.yml의 `JAVA_OPTS`를 조정:

```yaml
# 변경 전
JAVA_OPTS: -Xms256m -Xmx512m

# 변경 후 (메모리 증가 + GC 로그 활성화)
JAVA_OPTS: >-
  -Xms512m -Xmx1024m
  -XX:+UseG1GC
  -XX:MaxGCPauseMillis=200
  -XX:+HeapDumpOnOutOfMemoryError
  -XX:HeapDumpPath=/usr/local/tomcat/logs/heapdump.hprof
  -Xlog:gc*:file=/usr/local/tomcat/logs/gc.log:time,uptime,level,tags
```

### 재발 방지
- Grafana 대시보드에서 JVM Heap 사용률 80% 초과 시 알림 설정
- Scouter에서 Active Service 수 모니터링
- 정기적인 힙 덤프 분석으로 메모리 누수 조기 발견

---

## 장애 시나리오 #3: DB 커넥션 풀 고갈

### 증상
- 애플리케이션 응답 지연 또는 timeout 발생
- 로그에 `Cannot get a connection, pool error` 또는 `Connection is not available` 출력
- Scouter에서 Active Service 수가 비정상적으로 증가

### 원인 분석
```bash
# MySQL 현재 연결 수 확인
docker exec mw-mysql mysql -u root -proot_password -e "SHOW STATUS LIKE 'Threads_connected';"

# 최대 연결 수 확인
docker exec mw-mysql mysql -u root -proot_password -e "SHOW VARIABLES LIKE 'max_connections';"

# 프로세스 리스트 확인 (어떤 쿼리가 오래 걸리는지)
docker exec mw-mysql mysql -u root -proot_password -e "SHOW FULL PROCESSLIST;"

# Spring Boot 커넥션 풀 상태 (Actuator)
curl -sfk https://localhost/actuator/metrics/hikaricp.connections.active
curl -sfk https://localhost/actuator/metrics/hikaricp.connections.pending
```

### 조치
1. **장시간 실행 쿼리 Kill**
```bash
docker exec mw-mysql mysql -u root -proot_password -e "KILL <process_id>;"
```

2. **커넥션 풀 설정 조정** (application.properties)
```properties
# HikariCP 커넥션 풀 설정
spring.datasource.hikari.maximum-pool-size=20
spring.datasource.hikari.minimum-idle=5
spring.datasource.hikari.idle-timeout=300000
spring.datasource.hikari.connection-timeout=20000
spring.datasource.hikari.max-lifetime=1200000
spring.datasource.hikari.leak-detection-threshold=60000
```

3. **MySQL max_connections 증가**
```bash
docker exec mw-mysql mysql -u root -proot_password -e "SET GLOBAL max_connections = 200;"
```

### 재발 방지
- `leak-detection-threshold` 설정으로 커넥션 누수 조기 탐지
- Prometheus에서 HikariCP 메트릭 모니터링
- Slow Query Log 활성화로 문제 쿼리 추적

---

## 장애 시나리오 #4: Keycloak SSO 로그인 실패

### 증상
- 로그인 페이지에 접근할 수 없거나 빈 페이지가 표시됨
- 로그인 후 토큰 발급에 실패하여 리다이렉트 루프 발생
- 브라우저 콘솔에 CORS 또는 OIDC 관련 오류 출력

### 원인 분석
```bash
# Keycloak 컨테이너 로그 확인
docker logs mw-keycloak --tail 100

# Realm 상태 확인 (Admin REST API)
curl -sf http://localhost:8080/realms/middleware-realm/.well-known/openid-configuration | jq .

# OIDC Discovery Endpoint 응답 확인
curl -sf http://localhost:8080/realms/middleware-realm/.well-known/openid-configuration | jq '.issuer, .authorization_endpoint, .token_endpoint'

# Keycloak 내부 네트워크에서 접근 확인
docker exec mw-keycloak curl -sf http://localhost:8080/health/ready
```

### 조치
1. **Split URI 패턴 확인**
   - 브라우저(외부)에서는 `localhost:8080`으로 접근
   - 컨테이너(내부)에서는 `keycloak:8080`으로 접근
   - `application.properties`의 issuer-uri와 브라우저 접근 URI가 불일치하면 토큰 검증이 실패한다

```properties
# Spring Boot 설정 예시 (Split URI 패턴)
spring.security.oauth2.resourceserver.jwt.issuer-uri=http://keycloak:8080/realms/middleware-realm
spring.security.oauth2.client.provider.keycloak.issuer-uri=http://localhost:8080/realms/middleware-realm
```

2. **Realm 재가져오기**
```bash
# Realm export 후 재import
docker exec mw-keycloak /opt/keycloak/bin/kc.sh export --dir /tmp/export --realm middleware-realm
docker exec mw-keycloak /opt/keycloak/bin/kc.sh import --dir /tmp/export
docker compose restart keycloak
```

3. **Client Secret 재확인**
```bash
# Keycloak Admin CLI로 client secret 확인
docker exec mw-keycloak /opt/keycloak/bin/kcadm.sh get clients -r middleware-realm --fields clientId,secret
```

### 재발 방지
- Nginx 리버스 프록시에서 Keycloak 경로를 통합하여 Split URI 문제 최소화
- health check 스크립트에 OIDC discovery endpoint 확인 항목 추가
- Keycloak realm 설정을 Git으로 버전 관리

---

## 장애 시나리오 #5: Scouter Agent 미연결

### 증상
- Scouter Client에서 Object 목록에 Tomcat 인스턴스가 보이지 않음
- Scouter Client 좌측 Object 트리가 비어있거나 일부 인스턴스만 표시
- 모니터링 차트에 데이터가 수집되지 않음

### 원인 분석
```bash
# Scouter Collector 로그 확인
docker logs mw-scouter-collector --tail 50

# Tomcat 컨테이너에서 Scouter Agent 로그 확인
docker exec mw-tomcat1 cat /usr/local/tomcat/logs/scouter-agent.log
docker exec mw-tomcat2 cat /usr/local/tomcat/logs/scouter-agent.log

# 6100 포트(Collector TCP) 연결 상태 확인
docker exec mw-tomcat1 sh -c "nc -zv scouter-collector 6100 2>&1 || echo 'Connection failed'"

# Scouter Collector가 리스닝 중인지 확인
docker exec mw-scouter-collector netstat -tlnp | grep 6100
```

### 조치
1. **agent.conf의 net_collector_ip 확인**
```properties
# agent.conf 설정 확인 — 컨테이너 내부 호스트명 사용
net_collector_ip=scouter-collector
net_collector_udp_port=6100
net_collector_tcp_port=6100
obj_name=/tomcat1
```

2. **컨테이너 네트워크 확인**
```bash
# 같은 Docker 네트워크에 속해있는지 확인
docker network inspect middleware_default | jq '.[0].Containers'

# Scouter Collector와 Tomcat 간 통신 테스트
docker exec mw-tomcat1 ping -c 3 scouter-collector
```

3. **Scouter Agent JVM 옵션 확인**
```bash
# Tomcat 컨테이너의 JAVA_OPTS에 Scouter Agent가 포함되어 있는지 확인
docker exec mw-tomcat1 ps aux | grep scouter
# -javaagent:/usr/local/scouter/agent.java/scouter.agent.jar 가 있어야 함
```

4. **Collector 재시작 후 Agent 재연결**
```bash
docker compose restart scouter-collector
docker compose restart tomcat1 tomcat2
```

### 재발 방지
- docker-compose.yml에 `depends_on` 설정으로 Collector가 먼저 기동되도록 구성
- Scouter Agent의 `net_collector_ip`를 환경변수로 관리
- 헬스체크에 Scouter Object 수 확인 항목 추가

---

## 장애 시나리오 #6: SSL 인증서 만료/오류

### 증상
- 브라우저에서 `ERR_CERT_DATE_INVALID` 또는 `ERR_CERT_AUTHORITY_INVALID` 오류 표시
- curl 요청 시 `SSL certificate problem: certificate has expired` 오류 발생
- Nginx 로그에 `SSL_do_handshake() failed` 출력

### 원인 분석
```bash
# 인증서 상세 정보 및 만료일 확인
echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | openssl x509 -noout -dates -subject -issuer

# 인증서 체인 검증
echo | openssl s_client -connect localhost:443 -showcerts 2>/dev/null

# 인증서 파일 직접 확인
docker exec mw-nginx openssl x509 -in /etc/nginx/ssl/server.crt -noout -dates

# Nginx SSL 설정 확인
docker exec mw-nginx cat /etc/nginx/conf.d/default.conf | grep -A5 ssl_
```

### 조치
1. **인증서 만료일 확인 및 갱신**
```bash
# 만료까지 남은 일수 확인
EXPIRY=$(echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
echo "만료일: $EXPIRY"

# 자체 서명 인증서 재생성 (개발 환경)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ./nginx/ssl/server.key \
  -out ./nginx/ssl/server.crt \
  -subj "/CN=localhost"
```

2. **인증서 갱신 스크립트 실행**
```bash
# 프로젝트 제공 갱신 스크립트
./scripts/cert-renew.sh

# Nginx 재시작으로 새 인증서 적용
docker compose restart nginx
```

3. **인증서 적용 확인**
```bash
# 갱신된 인증서 확인
curl -vk https://localhost 2>&1 | grep -E "expire|subject|issuer"
```

### 재발 방지
- 인증서 만료 30일 전 알림을 crontab으로 설정
- Prometheus의 `ssl_cert_not_after` 메트릭으로 Grafana 알림 구성
- 인증서 갱신 스크립트를 CI/CD 파이프라인에 통합

---

## 장애 시나리오 #7: Prometheus/Grafana 데이터 수집 실패

### 증상
- Grafana 대시보드 패널에 `No Data` 또는 `N/A` 표시
- Grafana에서 특정 시간대의 데이터만 누락
- Prometheus UI에서 쿼리 실행 시 빈 결과 반환

### 원인 분석
```bash
# Prometheus targets 상태 확인
curl -sf http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl: .scrapeUrl, health: .health, lastError: .lastError}'

# 브라우저에서 직접 확인
# http://localhost:9090/targets 접속하여 각 target의 State가 UP인지 확인

# Exporter 컨테이너 상태 확인
docker compose ps | grep -E "exporter|prometheus|grafana"

# Prometheus 로그 확인
docker logs mw-prometheus --tail 50

# Grafana 로그 확인
docker logs mw-grafana --tail 50
```

### 조치
1. **Exporter 상태 점검 및 재시작**
```bash
# Node Exporter 응답 확인
curl -sf http://localhost:9100/metrics | head -5

# MySQL Exporter 응답 확인
curl -sf http://localhost:9104/metrics | head -5

# 응답이 없으면 exporter 재시작
docker compose restart node-exporter mysql-exporter
```

2. **Prometheus scrape config 확인**
```bash
# prometheus.yml 설정 확인
docker exec mw-prometheus cat /etc/prometheus/prometheus.yml

# 설정 파일 문법 검증
docker exec mw-prometheus promtool check config /etc/prometheus/prometheus.yml
```

3. **Grafana 데이터소스 확인**
```bash
# Grafana 데이터소스 목록 확인
curl -sf -u admin:admin http://localhost:3000/api/datasources | jq '.[].name, .[].url'

# Prometheus 연결 테스트 (Grafana 컨테이너 내부에서)
docker exec mw-grafana wget -qO- http://prometheus:9090/api/v1/query?query=up
```

4. **데이터 수집 재개 확인**
```bash
# Prometheus에서 up 메트릭으로 전체 target 상태 확인
curl -sf 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'
```

### 재발 방지
- Prometheus의 `up` 메트릭에 대한 Grafana 알림 규칙 설정 (0이면 알림)
- Exporter 컨테이너에 `restart: unless-stopped` 정책 적용
- scrape_interval과 evaluation_interval을 적절히 조정하여 수집 안정성 확보

---

## 공통 문제 해결

### 컨테이너가 시작되지 않을 때
```bash
# 로그 확인
docker compose logs <service-name>

# 설정 파일 문법 검증
docker exec mw-nginx nginx -t              # Nginx
docker exec mw-tomcat1 catalina.sh configtest  # Tomcat
```

### 전체 환경 초기화
```bash
# 모든 컨테이너 + 볼륨 삭제 후 재시작
docker compose down -v
docker compose up -d --build
```

### Nginx 502 Bad Gateway
- 원인: Tomcat이 아직 기동 중이거나 다운됨
- 조치: `docker compose ps`로 Tomcat 상태 확인, 필요 시 재시작

### SSL 인증서 만료
```bash
# 인증서 만료일 확인
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -dates

# 인증서 갱신
./scripts/cert-renew.sh
```

---

## 관련 문서

| 문서 | 설명 |
|------|------|
| [장애 대응 매뉴얼](incident-response.md) | 심층 장애 대응 매뉴얼 |
| [사용자 가이드](user-guide.md) | 설치 및 설정 가이드 |
| [모니터링 메트릭 가이드](monitoring-metrics.md) | 모니터링 확인 방법 |
| [Scouter APM 가이드](scouter-guide.md) | APM 진단 가이드 |
