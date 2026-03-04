#!/bin/bash
# ============================================
# 일일 서버 점검 자동화 스크립트
# crontab 예시: 0 9 * * * /path/to/health-check.sh
# ============================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
REPORT="$LOG_DIR/health-check-$(date '+%Y%m%d_%H%M%S').log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$REPORT"; }
check() {
    local name=$1 result=$2
    if [ "$result" = "OK" ]; then
        log "  [PASS] $name"
    else
        log "  [FAIL] $name - $result"
        FAILURES=$((FAILURES + 1))
    fi
}

FAILURES=0

log "=========================================="
log " Daily Health Check Report"
log "=========================================="

# ── 1. 컨테이너 상태 점검 ──
log ""
log "[1] Container Status"
CONTAINERS=("mw-mysql" "mw-tomcat1" "mw-tomcat2" "mw-nginx" "mw-scouter" "mw-prometheus" "mw-grafana" "mw-keycloak" "mw-node-exporter" "mw-nginx-exporter")
for c in "${CONTAINERS[@]}"; do
    STATUS=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "not found")
    if [ "$STATUS" = "running" ]; then
        check "$c" "OK"
    else
        check "$c" "Status: $STATUS"
    fi
done

# ── 2. 서비스 응답 점검 ──
log ""
log "[2] Service Response"

# Web App (HTTPS)
HTTP_CODE=$(curl -sfk -o /dev/null -w '%{http_code}' https://localhost/ 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && check "Web App (HTTPS)" "OK" || check "Web App (HTTPS)" "HTTP $HTTP_CODE"

# Nginx Health
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost/nginx-health 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && check "Nginx Health" "OK" || check "Nginx Health" "HTTP $HTTP_CODE"

# Prometheus
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost:9090/-/ready 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && check "Prometheus" "OK" || check "Prometheus" "HTTP $HTTP_CODE"

# Grafana
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost:3000/api/health 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && check "Grafana" "OK" || check "Grafana" "HTTP $HTTP_CODE"

# Keycloak
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost:8080/realms/middleware 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ] && check "Keycloak" "OK" || check "Keycloak" "HTTP $HTTP_CODE"

# ── 3. 리소스 사용량 ──
log ""
log "[3] Resource Usage"
docker stats --no-stream --format "  {{.Name}}\t CPU={{.CPUPerc}}\t MEM={{.MemUsage}}" $(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps -q 2>/dev/null) 2>/dev/null | tee -a "$REPORT"

# ── 4. 디스크 사용량 ──
log ""
log "[4] Disk Usage"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
log "  Root filesystem: ${DISK_USAGE}% used"
[ "$DISK_USAGE" -lt 90 ] && check "Disk (<90%)" "OK" || check "Disk (<90%)" "${DISK_USAGE}% used"

DOCKER_DISK=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1)
log "  Docker disk: $DOCKER_DISK"

# ── 5. SSL 인증서 만료일 ──
log ""
log "[5] SSL Certificate"
EXPIRY=$(echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$EXPIRY" ]; then
    log "  Expires: $EXPIRY"
    check "SSL Certificate" "OK"
else
    check "SSL Certificate" "Cannot read certificate"
fi

# ── 6. 로드밸런싱 점검 ──
log ""
log "[6] Load Balancing"
HOSTS=""
for i in $(seq 1 4); do
    H=$(curl -sfk -o /dev/null -D- https://localhost/ 2>/dev/null | grep -i x-upstream | tr -d '\r')
    HOSTS="$HOSTS $H"
done
UNIQUE=$(echo "$HOSTS" | tr ' ' '\n' | sort -u | grep -c "X-Upstream" || echo "0")
[ "$UNIQUE" -ge 2 ] && check "Load Balancing (2+ backends)" "OK" || check "Load Balancing" "Only $UNIQUE backend(s) responding"

# ── 결과 요약 ──
log ""
log "=========================================="
if [ "$FAILURES" -eq 0 ]; then
    log " Result: ALL CHECKS PASSED"
else
    log " Result: $FAILURES CHECK(S) FAILED"
fi
log " Report: $REPORT"
log "=========================================="

exit "$FAILURES"
