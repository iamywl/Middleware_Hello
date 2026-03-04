#!/bin/bash
# ============================================
# 백업 스크립트
# MySQL 덤프 + 설정 파일 + 로그 백업
# crontab 예시: 0 2 * * * /path/to/backup.sh
# ============================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups/$(date '+%Y%m%d_%H%M%S')"
mkdir -p "$BACKUP_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "=========================================="
log " Backup Started"
log "=========================================="

# ── 1. MySQL 데이터베이스 덤프 ──
log "[1/4] Dumping MySQL database..."
docker exec mw-mysql mysqldump \
    -u root -proot_password \
    --databases middleware_db \
    --single-transaction \
    --routines --triggers \
    > "$BACKUP_DIR/mysql_dump.sql" 2>/dev/null

DUMP_SIZE=$(du -sh "$BACKUP_DIR/mysql_dump.sql" | cut -f1)
log "  MySQL dump: $DUMP_SIZE"

# ── 2. 설정 파일 백업 ──
log "[2/4] Backing up configuration files..."
tar -czf "$BACKUP_DIR/configs.tar.gz" \
    -C "$PROJECT_DIR" configs/ docker-compose.yml 2>/dev/null
log "  Configs archived"

# ── 3. 로그 파일 백업 ──
log "[3/4] Backing up logs..."
mkdir -p "$BACKUP_DIR/logs"

# Nginx 로그
docker cp mw-nginx:/var/log/nginx/access.log "$BACKUP_DIR/logs/nginx-access.log" 2>/dev/null || true
docker cp mw-nginx:/var/log/nginx/error.log "$BACKUP_DIR/logs/nginx-error.log" 2>/dev/null || true

# Tomcat 로그
docker logs mw-tomcat1 > "$BACKUP_DIR/logs/tomcat1.log" 2>&1 || true
docker logs mw-tomcat2 > "$BACKUP_DIR/logs/tomcat2.log" 2>&1 || true

log "  Logs archived"

# ── 4. 백업 정리 (30일 이상 된 백업 삭제) ──
log "[4/4] Cleaning old backups (>30 days)..."
DELETED=$(find "$PROJECT_DIR/backups" -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \; -print 2>/dev/null | wc -l | tr -d ' ')
log "  Deleted $DELETED old backup(s)"

# ── 요약 ──
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log ""
log "=========================================="
log " Backup Completed"
log " Location: $BACKUP_DIR"
log " Total size: $TOTAL_SIZE"
log "=========================================="
