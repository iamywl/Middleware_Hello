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
