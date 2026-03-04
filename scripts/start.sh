#!/bin/bash
# ============================================
# 미들웨어 환경 시작 스크립트
# ============================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=========================================="
echo " Middleware Environment - START"
echo "=========================================="

echo "[1/3] Building application..."
docker compose build --no-cache

echo "[2/3] Starting services..."
docker compose up -d

echo "[3/3] Waiting for services to be ready..."
echo -n "  MySQL: "
for i in $(seq 1 30); do
    if docker compose exec -T mysql mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "OK"
        break
    fi
    sleep 2
    echo -n "."
done

echo -n "  Tomcat1: "
for i in $(seq 1 30); do
    if curl -sf http://localhost:80/health > /dev/null 2>&1; then
        echo "OK"
        break
    fi
    sleep 2
    echo -n "."
done

echo ""
echo "=========================================="
echo " Services Status"
echo "=========================================="
docker compose ps

echo ""
echo " Access URLs:"
echo "   Web App  : http://localhost"
echo "   Nginx    : http://localhost/nginx-health"
echo "=========================================="
