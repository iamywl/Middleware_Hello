#!/bin/bash
# ============================================
# 미들웨어 환경 상태 확인 스크립트
# ============================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=========================================="
echo " Middleware Environment - STATUS"
echo "=========================================="

echo ""
echo "[Container Status]"
docker compose ps

echo ""
echo "[Load Balancing Test - 5 requests]"
for i in $(seq 1 5); do
    RESPONSE=$(curl -sf http://localhost/ 2>/dev/null || echo '{"error":"unreachable"}')
    HOST=$(echo "$RESPONSE" | grep -o '"host":"[^"]*"' | head -1)
    echo "  Request #$i -> $HOST"
done

echo ""
echo "[Resource Usage]"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose ps -q 2>/dev/null) 2>/dev/null || echo "  Services not running"

echo "=========================================="
