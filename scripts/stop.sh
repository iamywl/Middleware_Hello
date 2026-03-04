#!/bin/bash
# ============================================
# 미들웨어 환경 종료 스크립트
# ============================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=========================================="
echo " Middleware Environment - STOP"
echo "=========================================="

echo "[1/2] Stopping services..."
docker compose down

echo "[2/2] Done."
echo ""
echo " To remove volumes (DB data, logs): docker compose down -v"
echo "=========================================="
