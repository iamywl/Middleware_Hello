#!/bin/bash
# ============================================
# 인증서 갱신 자동화 스크립트
# crontab 등록 예시: 0 3 1 * * /path/to/cert-renew.sh
# ============================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSL_DIR="$PROJECT_DIR/configs/nginx/ssl"
LOG_FILE="$PROJECT_DIR/logs/cert-renew.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "=== Certificate Renewal Started ==="

# 현재 인증서 만료일 확인
EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_DIR/server.crt" 2>/dev/null | cut -d= -f2)
EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY" "+%s" 2>/dev/null || date -d "$EXPIRY" "+%s" 2>/dev/null)
NOW_EPOCH=$(date "+%s")
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

log "Current certificate expires: $EXPIRY ($DAYS_LEFT days left)"

# 30일 이내 만료 시에만 갱신
if [ "$DAYS_LEFT" -gt 30 ]; then
    log "Certificate still valid for $DAYS_LEFT days. Skipping renewal."
    exit 0
fi

log "Certificate expiring soon. Renewing..."

# 기존 인증서 백업
BACKUP_DIR="$SSL_DIR/backup/$(date '+%Y%m%d_%H%M%S')"
mkdir -p "$BACKUP_DIR"
cp "$SSL_DIR/server.crt" "$SSL_DIR/server.key" "$SSL_DIR/server-chain.crt" "$BACKUP_DIR/"
log "Backed up current certificates to $BACKUP_DIR"

# 새 서버 키 생성
openssl genrsa -out "$SSL_DIR/server.key" 2048
log "Generated new server private key"

# 새 CSR 생성
openssl req -new \
    -key "$SSL_DIR/server.key" \
    -out "$SSL_DIR/server.csr" \
    -config "$SSL_DIR/server.cnf"
log "Generated new CSR"

# CA로 새 인증서 서명 (1년)
openssl x509 -req \
    -in "$SSL_DIR/server.csr" \
    -CA "$SSL_DIR/ca.crt" \
    -CAkey "$SSL_DIR/ca.key" \
    -CAcreateserial \
    -out "$SSL_DIR/server.crt" \
    -days 365 \
    -sha256 \
    -extensions v3_req \
    -extfile "$SSL_DIR/server.cnf"
log "Signed new certificate with CA"

# 인증서 체인 재생성
cat "$SSL_DIR/server.crt" "$SSL_DIR/ca.crt" > "$SSL_DIR/server-chain.crt"
log "Regenerated certificate chain"

# Nginx 리로드
if docker exec mw-nginx nginx -t 2>/dev/null; then
    docker exec mw-nginx nginx -s reload
    log "Nginx reloaded with new certificate"
else
    log "ERROR: Nginx config test failed! Restoring backup..."
    cp "$BACKUP_DIR/server.crt" "$BACKUP_DIR/server.key" "$BACKUP_DIR/server-chain.crt" "$SSL_DIR/"
    log "Backup restored"
    exit 1
fi

# 새 인증서 정보
NEW_EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_DIR/server.crt" | cut -d= -f2)
log "New certificate expires: $NEW_EXPIRY"
log "=== Certificate Renewal Completed ==="
