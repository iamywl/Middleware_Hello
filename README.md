# Linux 기반 WEB/WAS 미들웨어 환경 구축 및 APM 모니터링 시스템

미들웨어(M/W) 기술엔지니어 직무 대비 실습 프로젝트

## 시스템 아키텍처

```
[클라이언트 브라우저]
        |  HTTPS (SSL/TLS)
        v
[Nginx - 리버스 프록시 + 로드밸런싱]
       / \
      v   v
[Tomcat #1]  [Tomcat #2]  ← WAS 이중화
      \   /
       v v
[MySQL DB] + [Scouter APM Server] + [Keycloak SSO]
                    |
        [Grafana + Prometheus 대시보드]
```

## 기술 스택

| 분류 | 기술/도구 |
|------|-----------|
| OS | Ubuntu 22.04 LTS |
| WEB 서버 | Nginx 1.24 |
| WAS | Apache Tomcat 10 (2대) |
| 언어/프레임워크 | Java 17, Spring Boot 3.x |
| APM | Scouter (Jennifer 오픈소스 대안) |
| 대시보드 | Grafana + Prometheus |
| SSO | Keycloak (OIDC) |
| 인증서 | OpenSSL (자체 CA) |
| 가상화 | Docker Compose |
| DB | MySQL 8.x |

## 프로젝트 구조

```
middle_ware/
├── docker-compose.yml          # 전체 환경 원클릭 구동
├── configs/
│   ├── nginx/                  # Nginx 리버스 프록시 + SSL 설정
│   ├── tomcat/                 # Tomcat #1, #2 설정
│   ├── scouter/                # Scouter Server/Agent 설정
│   ├── keycloak/               # Realm 설정
│   ├── prometheus/             # 메트릭 수집 설정
│   └── grafana/                # 대시보드 JSON
├── app/                        # Spring Boot 샘플 애플리케이션
├── scripts/                    # 운영 자동화 스크립트
├── docs/                       # 아키텍처, 트러블슈팅 문서
└── screenshots/                # 대시보드, SSO 흐름 캡처
```

## 단계별 진행 계획

| 주차 | 단계 | 핵심 내용 |
|------|------|-----------|
| 1~2 | 인프라 구축 | Nginx + Tomcat 이중화, 로드밸런싱, Spring Boot 배포 |
| 3~4 | APM 모니터링 | Scouter Agent 연동, Prometheus + Grafana 대시보드 |
| 5~6 | 보안 연동 | 자체 CA/SSL 인증서, Keycloak SSO (OIDC) |
| 7~8 | 운영 자동화 | 셸 스크립트 자동화, 장애 시나리오 대응 훈련 |

## 빠른 시작

```bash
# 전체 환경 구동
docker-compose up -d

# 상태 확인
docker-compose ps

# 접속
# Web: https://localhost
# Grafana: http://localhost:3000
# Keycloak: http://localhost:8080
# Scouter: localhost:6100
```

## 주요 기능

- **WEB/WAS 이중화**: Nginx 로드밸런싱으로 Tomcat 2대에 트래픽 분산
- **APM 모니터링**: Scouter로 TPS, 응답시간, JVM 상태 실시간 추적
- **통합 인증**: Keycloak SSO를 통한 OIDC 기반 싱글 사인온
- **SSL/PKI**: 자체 CA로 발급한 인증서 기반 HTTPS 통신
- **운영 자동화**: 서버 점검, 로그 분석, 백업 셸 스크립트

## 운영 스크립트

```bash
# 일일 서버 점검
./scripts/health-check.sh

# 로그 분석
./scripts/log-analyzer.sh

# 인증서 갱신
./scripts/cert-renew.sh

# 백업
./scripts/backup.sh
```

## APM: Scouter vs Jennifer

본 프로젝트에서는 APM으로 **Scouter**를 사용한다. Jennifer는 상용(유료) 제품이므로 사이드 프로젝트에서 사용할 수 없어, 같은 계열의 오픈소스인 Scouter로 대체하였다.

| 항목 | Jennifer (상용) | Scouter (본 프로젝트) |
|------|-----------------|----------------------|
| 라이선스 | 상용 (유료) | 오픈소스 (무료) |
| 개발 배경 | 제니퍼소프트 | 제니퍼소프트 출신 개발자 (LG CNS) |
| 핵심 기능 | TPS, 응답시간, JVM 모니터링 | 동일 |
| Agent 방식 | Java Agent (javaagent) | 동일 |
| 실시간 대시보드 | O | O |
| 힙 덤프/쓰레드 분석 | O | O |

Scouter는 Jennifer와 동일한 Java Agent 기반 APM으로, TPS/응답시간/JVM 힙/GC 모니터링 등 핵심 기능이 같다. 채용공고의 "Jennifer 기반 시스템 기술지원" 역량을 이 프로젝트 경험으로 어필할 수 있다.

## 문서

- [개발계획서](개발계획서.md) - 상세 개발 계획 및 일정
- [아키텍처 문서](docs/architecture.md) - 시스템 구성도 및 네트워크 구조
- [트러블슈팅](docs/troubleshooting.md) - 장애 시나리오별 대응 내역
- [테스트 보고서](docs/test-report.md) - 전체 26개 항목 테스트 결과
