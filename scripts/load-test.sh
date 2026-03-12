#!/bin/bash
# ============================================================
# load-test.sh — 미들웨어 부하 테스트 스크립트
# ============================================================
# 사용법: ./scripts/load-test.sh [시나리오] [요청수] [동시성]
#   시나리오: all | health | mixed | slow | burst | failover
#   요청수:   총 요청 수 (기본: 500)
#   동시성:   동시 요청 수 (기본: 10)
#
# 예시:
#   ./scripts/load-test.sh all              # 전체 시나리오 순차 실행
#   ./scripts/load-test.sh health 1000 20   # 헬스체크 1000회, 동시 20
#   ./scripts/load-test.sh burst            # 순간 폭주 테스트
#   ./scripts/load-test.sh failover         # WAS 1대 중단 후 복구 테스트
# ============================================================

set -euo pipefail

BASE_URL="https://localhost"
SCENARIO="${1:-all}"
TOTAL="${2:-500}"
CONCURRENCY="${3:-10}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─────────────────────────────────────────
# 유틸리티 함수
# ─────────────────────────────────────────
print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_result() {
    echo -e "${GREEN}  ✔ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✘ $1${NC}"
}

# 응답시간 통계 수집 (curl 병렬)
run_parallel_requests() {
    local url="$1"
    local count="$2"
    local concurrency="$3"
    local label="$4"
    local tmpfile
    tmpfile=$(mktemp)

    echo "  요청: ${count}회, 동시성: ${concurrency}, URL: ${url}"
    echo ""

    # xargs로 병렬 curl 실행, 응답시간 수집
    seq 1 "$count" | xargs -P "$concurrency" -I {} \
        curl -sk -o /dev/null -w "%{http_code} %{time_total} %{size_download}\n" "$url" \
        >> "$tmpfile" 2>/dev/null

    # 통계 계산
    local total_requests
    total_requests=$(wc -l < "$tmpfile" | tr -d ' ')
    local success
    success=$(grep -c '^200 ' "$tmpfile" || echo 0)
    local errors
    errors=$((total_requests - success))

    # 응답시간 통계
    local avg_time min_time max_time p95_time
    avg_time=$(awk '{sum+=$2; n++} END {printf "%.3f", sum/n}' "$tmpfile")
    min_time=$(awk '{print $2}' "$tmpfile" | sort -n | head -1)
    max_time=$(awk '{print $2}' "$tmpfile" | sort -n | tail -1)
    p95_time=$(awk '{print $2}' "$tmpfile" | sort -n | awk -v n="$total_requests" 'NR==int(n*0.95){print}')

    # 총 전송량
    local total_bytes
    total_bytes=$(awk '{sum+=$3} END {print sum}' "$tmpfile")
    local total_kb
    total_kb=$(echo "scale=1; $total_bytes / 1024" | bc)

    echo "  ┌──────────────────────────────────────────┐"
    echo "  │  ${label} 결과"
    echo "  ├──────────────────────────────────────────┤"
    printf "  │  총 요청:    %-10s 성공: %-10s │\n" "$total_requests" "$success"
    printf "  │  실패:       %-10s 전송량: %-7s KB│\n" "$errors" "$total_kb"
    echo "  ├──────────────────────────────────────────┤"
    printf "  │  평균 응답:  %-10s 초                │\n" "$avg_time"
    printf "  │  최소 응답:  %-10s 초                │\n" "$min_time"
    printf "  │  최대 응답:  %-10s 초                │\n" "$max_time"
    printf "  │  P95 응답:   %-10s 초                │\n" "${p95_time:-N/A}"
    echo "  └──────────────────────────────────────────┘"

    if [ "$errors" -gt 0 ]; then
        print_warn "에러 응답 코드 분포:"
        grep -v '^200 ' "$tmpfile" | awk '{print $1}' | sort | uniq -c | sort -rn | while read cnt code; do
            echo "    HTTP ${code}: ${cnt}건"
        done
    fi

    rm -f "$tmpfile"
}

# 로드밸런싱 분포 확인
check_lb_distribution() {
    local count="$1"
    local tmpfile
    tmpfile=$(mktemp)

    echo "  로드밸런싱 분포 확인 (${count}회 요청)..."
    echo ""

    for i in $(seq 1 "$count"); do
        curl -sk "${BASE_URL}/health" >> "$tmpfile" 2>/dev/null
        echo "" >> "$tmpfile"
    done

    echo "  ┌──────────────────────────────────────────┐"
    echo "  │  WAS별 요청 분배                          │"
    echo "  ├──────────────────────────────────────────┤"
    grep -o '"host":"[^"]*"' "$tmpfile" | sort | uniq -c | sort -rn | while read cnt host; do
        local pct
        pct=$(echo "scale=1; $cnt * 100 / $count" | bc)
        printf "  │  %-30s %3d건 (%s%%)│\n" "$host" "$cnt" "$pct"
    done
    echo "  └──────────────────────────────────────────┘"

    rm -f "$tmpfile"
}

# ─────────────────────────────────────────
# 시나리오 1: 헬스체크 단일 엔드포인트 부하
# ─────────────────────────────────────────
scenario_health() {
    print_header "시나리오 1: 헬스체크 엔드포인트 부하 테스트"
    echo "  목적: 단일 경량 API의 처리 성능 측정"
    echo ""
    run_parallel_requests "${BASE_URL}/health" "$TOTAL" "$CONCURRENCY" "GET /health"
    echo ""
    check_lb_distribution 100
}

# ─────────────────────────────────────────
# 시나리오 2: 혼합 엔드포인트 부하
# ─────────────────────────────────────────
scenario_mixed() {
    print_header "시나리오 2: 혼합 엔드포인트 부하 테스트"
    echo "  목적: 다양한 API를 동시에 호출하여 실제 트래픽 패턴 시뮬레이션"
    echo ""

    local endpoints=(
        "${BASE_URL}/"
        "${BASE_URL}/health"
        "${BASE_URL}/info"
        "${BASE_URL}/actuator/health"
        "${BASE_URL}/actuator/metrics"
    )
    local tmpfile
    tmpfile=$(mktemp)

    local per_endpoint=$((TOTAL / ${#endpoints[@]}))
    echo "  엔드포인트 ${#endpoints[@]}개 × ${per_endpoint}회 = 총 $((per_endpoint * ${#endpoints[@]}))회"
    echo ""

    for url in "${endpoints[@]}"; do
        local path="${url#${BASE_URL}}"
        echo "  → ${path} (${per_endpoint}회, 동시 ${CONCURRENCY})"
        seq 1 "$per_endpoint" | xargs -P "$CONCURRENCY" -I {} \
            curl -sk -o /dev/null -w "%{http_code} %{time_total} ${path}\n" "$url" \
            >> "$tmpfile" 2>/dev/null
    done

    echo ""
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │  엔드포인트별 결과                         │"
    echo "  ├──────────────────────────────────────────┤"
    for url in "${endpoints[@]}"; do
        local path="${url#${BASE_URL}}"
        local cnt avg
        cnt=$(grep " ${path}$" "$tmpfile" | wc -l | tr -d ' ')
        avg=$(grep " ${path}$" "$tmpfile" | awk '{sum+=$2; n++} END {printf "%.3f", sum/n}')
        local ok
        ok=$(grep "^200 .* ${path}$" "$tmpfile" | wc -l | tr -d ' ')
        printf "  │  %-20s %4d건  평균 %ss  성공 %d│\n" "$path" "$cnt" "$avg" "$ok"
    done
    echo "  └──────────────────────────────────────────┘"

    rm -f "$tmpfile"
}

# ─────────────────────────────────────────
# 시나리오 3: 점진적 부하 증가 (Ramp-up)
# ─────────────────────────────────────────
scenario_slow() {
    print_header "시나리오 3: 점진적 부하 증가 (Ramp-up)"
    echo "  목적: 동시성을 1→5→10→20→50으로 올리며 성능 변화 관찰"
    echo ""

    local levels=(1 5 10 20 50)
    local per_level=100

    echo "  ┌───────────┬──────────┬──────────┬──────────┐"
    echo "  │ 동시성     │ 평균(초)  │ P95(초)   │ 에러     │"
    echo "  ├───────────┼──────────┼──────────┼──────────┤"

    for c in "${levels[@]}"; do
        local tmpfile
        tmpfile=$(mktemp)

        seq 1 "$per_level" | xargs -P "$c" -I {} \
            curl -sk -o /dev/null -w "%{http_code} %{time_total}\n" "${BASE_URL}/health" \
            >> "$tmpfile" 2>/dev/null

        local avg p95 errs total
        total=$(wc -l < "$tmpfile" | tr -d ' ')
        avg=$(awk '{sum+=$2; n++} END {printf "%.3f", sum/n}' "$tmpfile")
        p95=$(awk '{print $2}' "$tmpfile" | sort -n | awk -v n="$total" 'NR==int(n*0.95){print}')
        errs=$(grep -cv '^200 ' "$tmpfile" || echo 0)

        printf "  │ %-9s │ %-8s │ %-8s │ %-8s │\n" \
            "C=${c}" "${avg}" "${p95:-N/A}" "${errs}"

        rm -f "$tmpfile"
    done

    echo "  └───────────┴──────────┴──────────┴──────────┘"
    echo ""
    echo "  해석: 동시성 증가에 따라 평균 응답시간이 급격히 늘면 병목 존재"
}

# ─────────────────────────────────────────
# 시나리오 4: 순간 폭주 (Burst)
# ─────────────────────────────────────────
scenario_burst() {
    print_header "시나리오 4: 순간 폭주 (Burst)"
    echo "  목적: 짧은 시간에 대량 요청을 보내 시스템 한계 확인"
    echo "  → Tomcat maxThreads=200, acceptCount=100 기준"
    echo ""

    local burst_count=300
    local burst_concurrency=100

    echo "  Phase 1: 정상 상태 베이스라인 (50회, 동시 5)"
    run_parallel_requests "${BASE_URL}/health" 50 5 "베이스라인"

    echo ""
    echo "  Phase 2: 폭주 (${burst_count}회, 동시 ${burst_concurrency})"
    run_parallel_requests "${BASE_URL}/health" "$burst_count" "$burst_concurrency" "순간 폭주"

    echo ""
    echo "  Phase 3: 폭주 후 회복 확인 (50회, 동시 5)"
    run_parallel_requests "${BASE_URL}/health" 50 5 "회복 확인"
}

# ─────────────────────────────────────────
# 시나리오 5: 페일오버 테스트
# ─────────────────────────────────────────
scenario_failover() {
    print_header "시나리오 5: 페일오버 테스트"
    echo "  목적: WAS 1대 중단 시 서비스 연속성 확인"
    echo ""

    echo "  Phase 1: 정상 상태 (양쪽 WAS 동작 중)"
    check_lb_distribution 20

    echo ""
    echo "  Phase 2: tomcat2 중지"
    docker stop mw-tomcat2 > /dev/null 2>&1
    print_warn "mw-tomcat2 중지됨"
    sleep 2

    echo ""
    echo "  Phase 3: tomcat2 중지 상태에서 요청 (서비스 유지 확인)"
    run_parallel_requests "${BASE_URL}/health" 50 5 "1대 운영"
    check_lb_distribution 10

    echo ""
    echo "  Phase 4: tomcat2 재시작"
    docker start mw-tomcat2 > /dev/null 2>&1
    print_result "mw-tomcat2 재시작됨"
    echo "  → WAS 부팅 대기 (15초)..."
    sleep 15

    echo ""
    echo "  Phase 5: 복구 확인"
    check_lb_distribution 20

    print_result "페일오버 테스트 완료"
}

# ─────────────────────────────────────────
# 전체 실행
# ─────────────────────────────────────────
run_all() {
    scenario_health
    scenario_mixed
    scenario_slow
    scenario_burst
    scenario_failover
}

# ─────────────────────────────────────────
# 메인
# ─────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   미들웨어 부하 테스트 도구 v1.0             ║${NC}"
echo -e "${CYAN}║   대상: ${BASE_URL}                    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

case "$SCENARIO" in
    all)      run_all ;;
    health)   scenario_health ;;
    mixed)    scenario_mixed ;;
    slow)     scenario_slow ;;
    burst)    scenario_burst ;;
    failover) scenario_failover ;;
    *)
        echo "사용법: $0 [all|health|mixed|slow|burst|failover] [요청수] [동시성]"
        echo ""
        echo "  시나리오:"
        echo "    health    헬스체크 단일 엔드포인트 부하"
        echo "    mixed     다양한 엔드포인트 혼합 부하"
        echo "    slow      동시성 점진적 증가 (Ramp-up)"
        echo "    burst     순간 폭주 (Burst)"
        echo "    failover  WAS 1대 중단 페일오버 테스트"
        echo "    all       전체 시나리오 순차 실행"
        exit 1
        ;;
esac

echo ""
print_result "테스트 완료!"
echo ""
