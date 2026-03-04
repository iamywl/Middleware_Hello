#!/bin/bash
# ============================================
# 로그 분석 스크립트
# Nginx access/error log, Tomcat catalina.out 파싱
# ============================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
REPORT="$LOG_DIR/log-analysis-$(date '+%Y%m%d_%H%M%S').log"

log() { echo "$1" | tee -a "$REPORT"; }

log "=========================================="
log " Log Analysis Report - $(date '+%Y-%m-%d %H:%M:%S')"
log "=========================================="

# ── 1. Nginx Access Log 분석 ──
log ""
log "[1] Nginx Access Log Analysis"
log "──────────────────────────────"

NGINX_ACCESS=$(docker exec mw-nginx cat /var/log/nginx/access.log 2>/dev/null || echo "")

if [ -n "$NGINX_ACCESS" ]; then
    TOTAL=$(echo "$NGINX_ACCESS" | wc -l | tr -d ' ')
    log "  Total requests: $TOTAL"

    log ""
    log "  Status code distribution:"
    echo "$NGINX_ACCESS" | awk '{print $9}' | sort | uniq -c | sort -rn | head -10 | while read count code; do
        log "    HTTP $code: $count requests"
    done

    log ""
    log "  Top 10 requested URLs:"
    echo "$NGINX_ACCESS" | awk '{print $7}' | sort | uniq -c | sort -rn | head -10 | while read count url; do
        log "    $count  $url"
    done

    log ""
    log "  Top 10 client IPs:"
    echo "$NGINX_ACCESS" | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | while read count ip; do
        log "    $count  $ip"
    done

    log ""
    log "  Upstream distribution (Load Balancing):"
    echo "$NGINX_ACCESS" | grep -oP 'upstream=\S+' | sort | uniq -c | sort -rn | while read count upstream; do
        log "    $count  $upstream"
    done

    # 5xx 에러 추출
    ERRORS_5XX=$(echo "$NGINX_ACCESS" | awk '$9 ~ /^5/ {print}' | wc -l | tr -d ' ')
    if [ "$ERRORS_5XX" -gt 0 ]; then
        log ""
        log "  WARNING: $ERRORS_5XX requests with 5xx errors"
        echo "$NGINX_ACCESS" | awk '$9 ~ /^5/' | tail -5 | while read line; do
            log "    $line"
        done
    fi
else
    log "  (No access log data)"
fi

# ── 2. Nginx Error Log 분석 ──
log ""
log "[2] Nginx Error Log"
log "──────────────────────────────"

NGINX_ERROR=$(docker exec mw-nginx cat /var/log/nginx/error.log 2>/dev/null || echo "")

if [ -n "$NGINX_ERROR" ]; then
    ERROR_COUNT=$(echo "$NGINX_ERROR" | wc -l | tr -d ' ')
    log "  Total error entries: $ERROR_COUNT"

    log ""
    log "  Error level distribution:"
    echo "$NGINX_ERROR" | grep -oP '\[(emerg|alert|crit|error|warn|notice|info)\]' | sort | uniq -c | sort -rn | while read count level; do
        log "    $count  $level"
    done

    log ""
    log "  Last 5 errors:"
    echo "$NGINX_ERROR" | tail -5 | while IFS= read -r line; do
        log "    $line"
    done
else
    log "  (No error log data)"
fi

# ── 3. Tomcat Log 분석 ──
for TC in mw-tomcat1 mw-tomcat2; do
    log ""
    log "[3] $TC - catalina.out"
    log "──────────────────────────────"

    TC_LOG=$(docker logs "$TC" 2>&1 || echo "")

    if [ -n "$TC_LOG" ]; then
        # ERROR/WARN 카운트
        ERRORS=$(echo "$TC_LOG" | grep -c "ERROR" || echo "0")
        WARNS=$(echo "$TC_LOG" | grep -c "WARN" || echo "0")
        log "  ERROR count: $ERRORS"
        log "  WARN count: $WARNS"

        if [ "$ERRORS" -gt 0 ]; then
            log ""
            log "  Last 5 ERROR lines:"
            echo "$TC_LOG" | grep "ERROR" | tail -5 | while IFS= read -r line; do
                log "    ${line:0:200}"
            done
        fi

        # OOM / GC 관련
        OOM=$(echo "$TC_LOG" | grep -ci "OutOfMemory\|heap space\|GC overhead" || echo "0")
        if [ "$OOM" -gt 0 ]; then
            log ""
            log "  WARNING: $OOM OOM/GC related entries detected!"
        fi
    else
        log "  (No log data)"
    fi
done

log ""
log "=========================================="
log " Report saved: $REPORT"
log "=========================================="
