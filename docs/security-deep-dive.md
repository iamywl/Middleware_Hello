# 보안 심화 가이드

> **대상 독자**: 경력 3년차 이상 백엔드/인프라 엔지니어
> **프로젝트 구성**: Nginx (리버스 프록시) + Tomcat x2 (WAS) + MySQL + Scouter APM + Prometheus + Grafana + Keycloak (SSO) on Docker Compose
> **인증서**: 자체 서명 CA (Self-Signed CA) 기반 TLS

---

## 목차

1. [TLS/SSL 심화](#1-tlsssl-심화)
2. [PKI / 인증서 체인 구조](#2-pki--인증서-체인-구조)
3. [OIDC / OAuth 2.0 심화](#3-oidc--oauth-20-심화)
4. [Spring Security + Keycloak 연동 원리](#4-spring-security--keycloak-연동-원리)
5. [웹 보안 (OWASP Top 10)](#5-웹-보안-owasp-top-10)
6. [Docker 보안](#6-docker-보안)
7. [보안 점검 체크리스트](#7-보안-점검-체크리스트)

---

## 1. TLS/SSL 심화

### 1.1 TLS 핸드셰이크 전체 과정

TLS 연결이 수립되기까지의 과정을 이해하는 것은 HTTPS 디버깅의 기초다. 아래는 TLS 1.2 기준 풀 핸드셰이크 시퀀스다.

```
┌──────────┐                                          ┌──────────┐
│  Client  │                                          │  Server  │
│ (브라우저) │                                          │ (Nginx)  │
└────┬─────┘                                          └────┬─────┘
     │                                                     │
     │  ① Client Hello                                     │
     │  - 지원하는 TLS 버전 (TLS 1.2)                      │
     │  - 지원하는 Cipher Suite 목록                       │
     │  - Client Random (28바이트 난수)                    │
     │  - Session ID (재접속 시 사용)                       │
     │  - SNI (Server Name Indication)                     │
     │ ─────────────────────────────────────────────────► │
     │                                                     │
     │  ② Server Hello                                     │
     │  - 선택된 TLS 버전                                  │
     │  - 선택된 Cipher Suite                              │
     │  - Server Random (28바이트 난수)                    │
     │  - Session ID                                       │
     │ ◄───────────────────────────────────────────────── │
     │                                                     │
     │  ③ Certificate                                      │
     │  - 서버 인증서 체인 전송                            │
     │    (server.crt + ca.crt)                            │
     │ ◄───────────────────────────────────────────────── │
     │                                                     │
     │  ④ Server Key Exchange (ECDHE 사용 시)              │
     │  - ECDHE 공개키 파라미터                            │
     │  - 서명 (서버 개인키로)                             │
     │ ◄───────────────────────────────────────────────── │
     │                                                     │
     │  ⑤ Server Hello Done                                │
     │ ◄───────────────────────────────────────────────── │
     │                                                     │
     │  ⑥ Client Key Exchange                              │
     │  - ECDHE 클라이언트 공개키                          │
     │ ─────────────────────────────────────────────────► │
     │                                                     │
     │  ⑦ [양쪽 모두 Pre-Master Secret 계산]               │
     │  Pre-Master Secret                                  │
     │    + Client Random                                  │
     │    + Server Random                                  │
     │    = Master Secret                                  │
     │    → 세션 키 (대칭키) 도출                          │
     │                                                     │
     │  ⑧ Change Cipher Spec                               │
     │  - "이제부터 암호화된 통신을 시작합니다"            │
     │ ─────────────────────────────────────────────────► │
     │                                                     │
     │  ⑨ Finished (암호화됨)                              │
     │  - 핸드셰이크 메시지의 해시 검증                    │
     │ ─────────────────────────────────────────────────► │
     │                                                     │
     │  ⑩ Change Cipher Spec                               │
     │ ◄───────────────────────────────────────────────── │
     │                                                     │
     │  ⑪ Finished (암호화됨)                              │
     │ ◄───────────────────────────────────────────────── │
     │                                                     │
     │  ══════ TLS 연결 수립 완료 ══════                   │
     │                                                     │
     │  ⑫ Application Data (HTTP 요청/응답)                │
     │ ◄────────────────────────────────────────────────► │
     │                                                     │
```

**핵심 포인트:**
- Client Random + Server Random + Pre-Master Secret 세 가지를 조합하여 Master Secret을 만든다.
- Master Secret에서 실제 데이터 암호화에 사용할 대칭키(세션 키)를 도출한다.
- 비대칭 암호화(RSA/ECDHE)는 키 교환에만 사용되고, 실제 데이터는 대칭키(AES)로 암호화된다.

### 1.2 TLS 1.2 vs TLS 1.3 차이점

| 구분 | TLS 1.2 | TLS 1.3 |
|------|---------|---------|
| **핸드셰이크 RTT** | 2-RTT (풀 핸드셰이크) | 1-RTT (0-RTT도 지원) |
| **키 교환** | RSA, DHE, ECDHE 모두 가능 | ECDHE/DHE만 허용 (Forward Secrecy 필수) |
| **Cipher Suite** | 약 300개 이상 | 5개로 축소 |
| **RSA 키 교환** | 지원 (Forward Secrecy 없음) | **제거됨** |
| **CBC 모드** | 지원 | **제거됨** (AEAD만 허용) |
| **0-RTT 재접속** | 미지원 | 지원 (세션 티켓 기반) |
| **핸드셰이크 암호화** | 인증서가 평문 전송 | 인증서도 암호화 전송 |

**TLS 1.3에서 허용되는 Cipher Suite (5개):**
```
TLS_AES_256_GCM_SHA384
TLS_CHACHA20_POLY1305_SHA256
TLS_AES_128_GCM_SHA256
TLS_AES_128_CCM_SHA256
TLS_AES_128_CCM_8_SHA256
```

> **Forward Secrecy(전방향 비밀성)**: 서버의 개인키가 유출되더라도 과거에 기록된 통신 내용을 복호화할 수 없는 성질. ECDHE를 사용하면 매 세션마다 임시 키 쌍을 생성하므로 달성된다.

### 1.3 암호화 스위트(Cipher Suite) 설명

Cipher Suite는 TLS 연결에서 사용할 알고리즘 조합을 명시한다. 이름을 분해해보면 각 부분이 의미하는 바를 알 수 있다.

```
ECDHE - RSA - AES128 - GCM - SHA256
  │      │      │       │      │
  │      │      │       │      └─ PRF/HMAC 해시 알고리즘
  │      │      │       └──────── 암호화 모드 (블록 암호 운영 모드)
  │      │      └────────────── 대칭 암호화 알고리즘 + 키 길이
  │      └───────────────────── 인증 (서버 인증서 검증 알고리즘)
  └──────────────────────────── 키 교환 알고리즘
```

**각 구성요소의 역할:**
- **키 교환 (ECDHE)**: 클라이언트와 서버가 대칭키를 안전하게 합의하는 방법
- **인증 (RSA)**: 서버가 자신의 신원을 증명하는 방법 (인증서 서명 검증)
- **대칭 암호화 (AES128)**: 실제 데이터를 암호화하는 알고리즘
- **모드 (GCM)**: 블록 암호의 운영 모드. GCM은 AEAD(인증 암호화)를 제공
- **해시 (SHA256)**: PRF(Pseudo-Random Function)에서 사용

### 1.4 본 프로젝트의 Nginx SSL 설정

프로젝트의 `configs/nginx/conf.d/default.conf`에서 사용 중인 설정:

```nginx
# SSL 프로토콜 - TLS 1.2와 1.3만 허용
ssl_protocols TLSv1.2 TLSv1.3;

# 안전한 Cipher Suite만 허용 (ECDHE 기반, GCM 모드)
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

# 서버가 선호하는 Cipher Suite 우선 적용
ssl_prefer_server_ciphers on;

# SSL 세션 캐시 (핸드셰이크 비용 절감)
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

**설정 해설:**
- `ssl_protocols TLSv1.2 TLSv1.3`: TLS 1.0/1.1은 취약점이 알려져 있어 비활성화한다. TLS 1.0은 BEAST, TLS 1.1은 CBC 패딩 오라클 공격에 취약하다.
- `ssl_prefer_server_ciphers on`: 클라이언트가 약한 Cipher를 제안해도 서버가 안전한 것을 선택한다.
- `ssl_session_cache shared:SSL:10m`: 워커 프로세스 간 SSL 세션을 공유하여 재접속 시 풀 핸드셰이크를 생략한다. `10m`은 10MB 메모리를 의미하며 약 40,000개의 세션을 캐시할 수 있다.

**추가 권장 설정:**

```nginx
# DH 파라미터 (ECDHE 대신 DHE 사용 시 필요)
# openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
ssl_dhparam /etc/nginx/ssl/dhparam.pem;

# TLS 1.3 전용 Cipher 지정 (Nginx 1.19.4+)
ssl_conf_command Ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256;

# Session Ticket (0-RTT 재접속용, 보안과 성능 트레이드오프)
ssl_session_tickets off;  # Forward Secrecy를 완벽히 보장하려면 off
```

### 1.5 HSTS (HTTP Strict Transport Security)

본 프로젝트에서 이미 설정되어 있는 HSTS 헤더:

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

**HSTS가 해결하는 문제:**

사용자가 `http://example.com`으로 접속하면 서버가 301로 `https://`로 리다이렉트한다. 하지만 이 첫 번째 HTTP 요청이 중간자 공격(MITM)에 노출될 수 있다. 이를 **SSL Stripping 공격**이라 한다.

HSTS 헤더를 받은 브라우저는 이후 `max-age` 기간(31536000초 = 1년) 동안 해당 도메인에 대해 HTTP 요청 자체를 보내지 않고 내부적으로 HTTPS로 변환한다.

**각 디렉티브의 의미:**
- `max-age=31536000`: 1년간 HTTPS만 사용하도록 브라우저에 기억시킴
- `includeSubDomains`: 서브도메인에도 HSTS 적용
- `always`: 에러 응답(4xx, 5xx)에도 헤더 포함

> **주의**: HSTS를 설정하면 인증서 문제가 발생해도 HTTP로 폴백할 수 없다. 프로덕션 환경에서는 `max-age`를 300초(5분)부터 시작하여 문제가 없으면 점진적으로 늘리는 것을 권장한다.

### 1.6 OCSP Stapling

**OCSP(Online Certificate Status Protocol)란?**

브라우저가 서버 인증서를 받으면 "이 인증서가 폐기(revoke)되지 않았는지" CA에게 확인해야 한다. 전통적으로 브라우저가 직접 CA의 OCSP 서버에 질의했는데, 이는 두 가지 문제가 있다:

1. **성능 저하**: 추가적인 네트워크 요청이 발생
2. **프라이버시**: CA가 사용자의 방문 사이트를 알 수 있음

**OCSP Stapling의 해결 방식:**

서버(Nginx)가 주기적으로 CA의 OCSP 서버에서 인증서 상태 응답을 미리 가져와(staple), TLS 핸드셰이크 시 인증서와 함께 클라이언트에게 전달한다.

```
[기존 방식]
Client → Server : TLS 핸드셰이크
Client → CA OCSP Server : "이 인증서 유효한가요?" (추가 지연)
CA OCSP Server → Client : "유효합니다"

[OCSP Stapling]
Server → CA OCSP Server : 미리 OCSP 응답 캐시 (백그라운드)
Client → Server : TLS 핸드셰이크 + OCSP 응답 함께 전달 (추가 지연 없음)
```

**Nginx 설정:**

```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/nginx/ssl/ca.crt;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
```

> **본 프로젝트에서는**: 자체 서명 CA를 사용하므로 OCSP Stapling을 활성화할 수 없다. OCSP는 공인 CA가 OCSP 서버를 운영해야 동작한다. 하지만 프로덕션에서 Let's Encrypt 등 공인 인증서를 사용할 때는 반드시 설정해야 한다.

### 1.7 openssl 명령어로 인증서 디버깅

실무에서 가장 자주 쓰는 openssl 디버깅 명령어를 정리한다.

**서버 인증서 확인 (s_client):**

```bash
# 서버에 TLS 연결하여 인증서 체인 확인
openssl s_client -connect localhost:443 -servername localhost

# 자체 서명 CA를 사용하는 경우 CA 인증서 지정
openssl s_client -connect localhost:443 \
  -CAfile configs/nginx/ssl/ca.crt \
  -servername localhost

# TLS 1.3 강제
openssl s_client -connect localhost:443 -tls1_3

# 사용 가능한 Cipher Suite 확인
openssl s_client -connect localhost:443 -cipher 'ECDHE-RSA-AES128-GCM-SHA256'
```

**인증서 파일 내용 확인 (x509):**

```bash
# 인증서 정보 출력 (발급자, 주체, 유효기간, SAN 등)
openssl x509 -in configs/nginx/ssl/server.crt -text -noout

# 인증서 만료일만 확인
openssl x509 -in configs/nginx/ssl/server.crt -enddate -noout

# 인증서의 Subject와 Issuer만 확인
openssl x509 -in configs/nginx/ssl/server.crt -subject -issuer -noout

# 인증서의 SAN(Subject Alternative Name) 확인
openssl x509 -in configs/nginx/ssl/server.crt -text -noout | grep -A1 "Subject Alternative Name"

# 인증서 지문(fingerprint) 확인
openssl x509 -in configs/nginx/ssl/server.crt -fingerprint -sha256 -noout
```

**인증서 체인 검증 (verify):**

```bash
# CA 인증서로 서버 인증서 검증
openssl verify -CAfile configs/nginx/ssl/ca.crt configs/nginx/ssl/server.crt

# 체인 인증서 검증 (Intermediate CA가 있는 경우)
openssl verify -CAfile ca.crt -untrusted intermediate.crt server.crt
```

**개인키와 인증서 매칭 확인:**

```bash
# 개인키의 modulus
openssl rsa -in server.key -modulus -noout | md5sum

# 인증서의 modulus
openssl x509 -in server.crt -modulus -noout | md5sum

# 두 해시값이 같으면 매칭됨
```

---

## 2. PKI / 인증서 체인 구조

### 2.1 Root CA - Intermediate CA - Server Certificate 체인

PKI(Public Key Infrastructure)에서 신뢰는 체인 형태로 전달된다. 이를 **인증서 체인(Certificate Chain)** 또는 **신뢰 체인(Chain of Trust)**이라 한다.

```
┌─────────────────────────────────────┐
│          Root CA Certificate         │
│  (브라우저/OS에 사전 탑재)           │
│  자기 자신이 서명 (Self-Signed)      │
│  유효기간: 10~30년                   │
│  오프라인 금고에 보관 (HSM)          │
└──────────────┬──────────────────────┘
               │ 서명 (Sign)
               ▼
┌─────────────────────────────────────┐
│     Intermediate CA Certificate      │
│  Root CA가 서명                      │
│  유효기간: 3~10년                    │
│  실제 인증서 발급 업무 담당          │
│  Root CA 보호를 위한 계층            │
└──────────────┬──────────────────────┘
               │ 서명 (Sign)
               ▼
┌─────────────────────────────────────┐
│       Server Certificate             │
│  (= Leaf Certificate / End-Entity)   │
│  Intermediate CA가 서명              │
│  유효기간: 90일~1년                  │
│  웹 서버에 설치                      │
└─────────────────────────────────────┘
```

**검증 과정:**
1. 클라이언트가 Server Certificate를 받는다
2. Server Certificate의 Issuer(발급자)를 확인하고 Intermediate CA 인증서를 찾는다
3. Intermediate CA의 공개키로 Server Certificate의 서명을 검증한다
4. Intermediate CA의 Issuer를 확인하고 Root CA를 찾는다
5. Root CA의 공개키로 Intermediate CA의 서명을 검증한다
6. Root CA가 브라우저/OS의 신뢰 저장소에 있으면 신뢰 성공

**왜 3계층 구조인가?**
- Root CA의 개인키가 유출되면 전 세계의 신뢰가 깨진다
- Root CA는 오프라인(HSM, 물리 금고)에 보관하고 직접 인증서를 발급하지 않는다
- Intermediate CA만 온라인으로 인증서를 발급하며, 문제 발생 시 Intermediate CA만 폐기(revoke)하면 된다

### 2.2 본 프로젝트의 인증서 체인

본 프로젝트는 개발/학습 환경이므로 2계층 구조(Root CA → Server Certificate)를 사용한다.

```
┌─────────────────────────────────┐
│   자체 Root CA (ca.crt)          │
│   CN: Middleware Lab CA          │
│   자기 자신이 서명                │
│   파일: configs/nginx/ssl/ca.crt │
│         configs/nginx/ssl/ca.key │
└──────────────┬──────────────────┘
               │ 서명
               ▼
┌─────────────────────────────────┐
│   Server Certificate             │
│   CN: localhost                  │
│   SAN: localhost, nginx,         │
│        *.middleware.local,       │
│        127.0.0.1                 │
│   파일: configs/nginx/ssl/       │
│     server.crt, server.key       │
│     server-chain.crt (연결 파일) │
└─────────────────────────────────┘
```

**`server-chain.crt` 파일의 역할:**

Nginx에서 `ssl_certificate`에 지정하는 파일. Server Certificate + CA Certificate를 하나의 파일로 연결(concatenate)한 것이다.

```bash
# server-chain.crt 생성 방법
cat server.crt ca.crt > server-chain.crt
```

이렇게 해야 클라이언트가 서버 인증서와 함께 CA 인증서도 받아서 체인을 검증할 수 있다.

### 2.3 인증서 파일 형식

| 형식 | 확장자 | 인코딩 | 특징 |
|------|--------|--------|------|
| **PEM** | `.pem`, `.crt`, `.key` | Base64 (ASCII) | `-----BEGIN CERTIFICATE-----`로 시작. 텍스트 편집기로 열 수 있음. 가장 보편적 |
| **DER** | `.der`, `.cer` | 바이너리 | PEM의 Base64를 디코딩한 원본 바이너리. Java/Windows에서 주로 사용 |
| **PKCS#12** | `.p12`, `.pfx` | 바이너리 | 인증서 + 개인키 + 체인을 하나의 파일로 묶음. 비밀번호로 보호. Java KeyStore 변환 시 사용 |

**형식 변환 명령어:**

```bash
# PEM → DER
openssl x509 -in server.crt -outform DER -out server.der

# DER → PEM
openssl x509 -in server.der -inform DER -outform PEM -out server.pem

# PEM(인증서+키) → PKCS12
openssl pkcs12 -export \
  -in server.crt \
  -inkey server.key \
  -certfile ca.crt \
  -out server.p12 \
  -name "middleware-server"

# PKCS12 → PEM
openssl pkcs12 -in server.p12 -out server.pem -nodes

# PKCS12 → Java KeyStore (JKS)
keytool -importkeystore \
  -srckeystore server.p12 \
  -srcstoretype PKCS12 \
  -destkeystore keystore.jks \
  -deststoretype JKS
```

### 2.4 CSR (Certificate Signing Request) 생성 과정

CSR은 "이 공개키에 대한 인증서를 발급해주세요"라는 요청서다.

```
┌──────────────┐    ② CSR 제출     ┌──────────┐
│  서버 관리자  │ ──────────────► │    CA     │
│              │                   │          │
│ ① 키 쌍 생성 │    ③ 인증서 발급  │ CSR 검증  │
│  (공개키 +   │ ◄────────────── │ 서명 첨부  │
│   개인키)    │                   │          │
└──────────────┘                   └──────────┘
```

**본 프로젝트의 CSR 설정 (`configs/nginx/ssl/server.cnf`):**

```ini
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = KR
ST = Seoul
L = Seoul
O = Middleware Lab
OU = DevOps
CN = localhost

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = nginx
DNS.3 = *.middleware.local
IP.1 = 127.0.0.1
```

**CSR 생성 및 인증서 발급 전체 흐름:**

```bash
# 1. CA 개인키 생성
openssl genrsa -out ca.key 4096

# 2. CA 자체 서명 인증서 생성
openssl req -x509 -new -nodes \
  -key ca.key \
  -sha256 -days 3650 \
  -subj "/C=KR/ST=Seoul/O=Middleware Lab/CN=Middleware Lab CA" \
  -out ca.crt

# 3. 서버 개인키 생성
openssl genrsa -out server.key 2048

# 4. CSR 생성 (server.cnf 설정 사용)
openssl req -new \
  -key server.key \
  -config server.cnf \
  -out server.csr

# 5. CA가 CSR에 서명하여 서버 인증서 발급
openssl x509 -req \
  -in server.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -days 365 \
  -sha256 \
  -extensions v3_req \
  -extfile server.cnf \
  -out server.crt

# 6. 체인 인증서 생성
cat server.crt ca.crt > server-chain.crt
```

### 2.5 SAN (Subject Alternative Name) 설정

과거에는 인증서의 CN(Common Name) 필드로 도메인을 식별했지만, 현재 브라우저들은 **SAN 확장 필드만 확인**한다 (RFC 6125). CN은 더 이상 도메인 검증에 사용되지 않는다.

**본 프로젝트의 SAN 설정:**

```ini
[alt_names]
DNS.1 = localhost       # 로컬 개발 접속
DNS.2 = nginx           # Docker 내부 서비스 이름
DNS.3 = *.middleware.local  # 와일드카드 (서브도메인 대응)
IP.1 = 127.0.0.1        # IP 직접 접속
```

**SAN에 IP를 포함하는 이유:**
- Docker 환경에서 `https://127.0.0.1:443`으로 접속할 때 SAN에 IP가 없으면 인증서 검증 실패
- `DNS.x`는 도메인에 대한 매칭, `IP.x`는 IP 주소에 대한 매칭

### 2.6 인증서 갱신 절차와 자동화

**수동 갱신 절차:**

```bash
# 1. 새 CSR 생성 (기존 개인키 재사용 가능)
openssl req -new -key server.key -config server.cnf -out server.csr

# 2. 새 인증서 발급
openssl x509 -req -in server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 365 -sha256 \
  -extensions v3_req -extfile server.cnf \
  -out server.crt

# 3. 체인 재생성
cat server.crt ca.crt > server-chain.crt

# 4. Nginx 리로드 (무중단)
docker exec mw-nginx nginx -s reload
```

**자동화 스크립트 (cron 등록):**

```bash
#!/bin/bash
# renew-cert.sh - 인증서 만료 30일 전 자동 갱신
CERT_PATH="./configs/nginx/ssl"
DAYS_BEFORE_EXPIRY=30

# 만료일 확인
expiry=$(openssl x509 -in "$CERT_PATH/server.crt" -enddate -noout | cut -d= -f2)
expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || date -d "$expiry" +%s)
now_epoch=$(date +%s)
days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

if [ "$days_left" -lt "$DAYS_BEFORE_EXPIRY" ]; then
    echo "인증서 만료 ${days_left}일 전 - 갱신 시작"
    openssl x509 -req -in "$CERT_PATH/server.csr" \
      -CA "$CERT_PATH/ca.crt" -CAkey "$CERT_PATH/ca.key" -CAcreateserial \
      -days 365 -sha256 \
      -extensions v3_req -extfile "$CERT_PATH/server.cnf" \
      -out "$CERT_PATH/server.crt"
    cat "$CERT_PATH/server.crt" "$CERT_PATH/ca.crt" > "$CERT_PATH/server-chain.crt"
    docker exec mw-nginx nginx -s reload
    echo "인증서 갱신 완료"
else
    echo "인증서 만료까지 ${days_left}일 남음 - 갱신 불필요"
fi
```

---

## 3. OIDC / OAuth 2.0 심화

### 3.1 OAuth 2.0 4가지 Grant Type

OAuth 2.0은 "제3자 애플리케이션에게 리소스 접근 권한을 위임하는 프레임워크"다. 4가지 Grant Type이 있으며, 각각 사용 시나리오가 다르다.

| Grant Type | 사용 시나리오 | 보안 수준 | 현재 권장 여부 |
|------------|-------------|----------|--------------|
| **Authorization Code** | 서버 사이드 웹 앱 | 높음 | 권장 (PKCE 포함) |
| **Implicit** | SPA (브라우저 전용) | 낮음 | **비권장** (Auth Code + PKCE로 대체) |
| **Client Credentials** | 서버 간 통신 (M2M) | 높음 | 권장 |
| **Resource Owner Password** | 신뢰할 수 있는 자사 앱 | 낮음 | **비권장** |

**Authorization Code Grant** (본 프로젝트에서 사용):
- 가장 안전하고 범용적인 플로우
- Access Token이 브라우저에 직접 노출되지 않음 (서버 사이드에서 교환)
- Keycloak + Spring Security 조합에서 기본으로 사용

**Client Credentials Grant:**
- 사용자 없이 서비스 간 인증할 때 사용
- 예: Prometheus가 Keycloak API를 호출할 때

**Implicit Grant (비권장):**
- Access Token이 URL fragment로 직접 브라우저에 전달되어 노출 위험
- OAuth 2.1에서 공식 제거 예정

**Resource Owner Password Grant (비권장):**
- 사용자의 ID/PW를 클라이언트 앱이 직접 수집하므로 본래 취지에 위배

### 3.2 Authorization Code Flow 시퀀스

본 프로젝트에서 Keycloak + Spring Security가 사용하는 전체 플로우:

```
┌──────────┐       ┌──────────┐        ┌───────────┐       ┌──────────┐
│  브라우저  │       │  Nginx   │        │ Tomcat    │       │ Keycloak │
│ (사용자)  │       │ (프록시)  │        │(Spring)   │       │ (IdP)    │
└────┬─────┘       └────┬─────┘        └─────┬─────┘       └────┬─────┘
     │                   │                    │                   │
     │ ① GET /secured/profile               │                   │
     │ ──────────────────►──────────────────►│                   │
     │                   │                    │                   │
     │                   │  ② 인증 안됨!      │                   │
     │                   │  302 Redirect to   │                   │
     │ ◄─────────────────◄────────────────── │                   │
     │  Keycloak 로그인 페이지로              │                   │
     │  /realms/middleware/protocol/          │                   │
     │  openid-connect/auth                  │                   │
     │  ?response_type=code                  │                   │
     │  &client_id=middleware-app            │                   │
     │  &redirect_uri=https://localhost/     │                   │
     │    login/oauth2/code/keycloak         │                   │
     │  &scope=openid profile email          │                   │
     │  &state=xyz123                        │                   │
     │                   │                    │                   │
     │ ③ GET Keycloak 로그인 페이지          │                   │
     │ ─────────────────────────────────────────────────────────►│
     │                   │                    │                   │
     │ ④ 로그인 폼 표시  │                    │                   │
     │ ◄───────────────────────────────────────────────────────── │
     │                   │                    │                   │
     │ ⑤ ID/PW 입력      │                    │                   │
     │ ─────────────────────────────────────────────────────────►│
     │                   │                    │                   │
     │                   │                    │   ⑥ 인증 성공     │
     │ ⑦ 302 Redirect    │                    │   Authorization  │
     │   ?code=abc789    │                    │   Code 발급      │
     │   &state=xyz123   │                    │                   │
     │ ◄───────────────────────────────────────────────────────── │
     │                   │                    │                   │
     │ ⑧ GET /login/oauth2/code/keycloak     │                   │
     │    ?code=abc789&state=xyz123          │                   │
     │ ──────────────────►──────────────────►│                   │
     │                   │                    │                   │
     │                   │                    │ ⑨ POST /token     │
     │                   │                    │  code=abc789      │
     │                   │                    │  client_id=...    │
     │                   │                    │  client_secret=.. │
     │                   │                    │ ──────────────── ►│
     │                   │                    │                   │
     │                   │                    │ ⑩ Token Response  │
     │                   │                    │  access_token     │
     │                   │                    │  refresh_token    │
     │                   │                    │  id_token (OIDC)  │
     │                   │                    │ ◄──────────────── │
     │                   │                    │                   │
     │ ⑪ 302 Redirect    │                    │                   │
     │    → /secured/profile                 │                   │
     │ ◄─────────────────◄────────────────── │                   │
     │                   │                    │                   │
     │ ⑫ GET /secured/profile (세션 포함)     │                   │
     │ ──────────────────►──────────────────►│                   │
     │                   │                    │                   │
     │ ⑬ 200 OK (프로필 JSON)                │                   │
     │ ◄─────────────────◄────────────────── │                   │
     │                   │                    │                   │
```

**핵심 보안 포인트:**
- **Authorization Code(abc789)**는 짧은 수명(보통 30초~1분)이며 한 번만 사용 가능
- **state 파라미터(xyz123)**는 CSRF 방어용 - Spring Security가 자동 생성/검증
- **⑨번 단계**에서 Authorization Code를 Access Token으로 교환하는 것은 서버 간 통신(백채널)으로 이루어짐 - 브라우저에 Access Token이 노출되지 않음
- **client_secret**은 서버 사이드에서만 사용되므로 안전

### 3.3 OIDC가 OAuth 2.0 위에 추가하는 것

OAuth 2.0은 **인가(Authorization)** 프레임워크이지, **인증(Authentication)** 프로토콜이 아니다. OIDC(OpenID Connect)는 OAuth 2.0 위에 인증 레이어를 추가한 것이다.

```
┌─────────────────────────────────────┐
│          OIDC (OpenID Connect)       │
│  - ID Token (JWT)                    │
│  - UserInfo Endpoint                 │
│  - Discovery (/.well-known/...)      │
│  - 표준화된 Claim (sub, email, ...)  │
├─────────────────────────────────────┤
│          OAuth 2.0                   │
│  - Access Token                      │
│  - Refresh Token                     │
│  - Authorization Endpoint            │
│  - Token Endpoint                    │
│  - Scope / Grant Type                │
└─────────────────────────────────────┘
```

**OIDC가 추가하는 핵심 요소:**

| 요소 | 설명 |
|------|------|
| **ID Token** | 사용자 인증 정보를 담은 JWT. `sub`(사용자 ID), `email`, `name` 등 포함 |
| **UserInfo Endpoint** | Access Token으로 사용자 정보를 조회하는 API |
| **Discovery** | `/.well-known/openid-configuration`에서 IdP의 모든 엔드포인트 자동 발견 |
| **표준 Scope** | `openid`, `profile`, `email` 등 표준화된 스코프 |
| **표준 Claim** | `sub`, `name`, `preferred_username`, `email` 등 |

**Keycloak Discovery URL:**
```bash
# 브라우저 또는 호스트에서 접근 시
http://localhost:8080/realms/middleware/.well-known/openid-configuration

# Docker 컨테이너 내부에서 접근 시
http://keycloak:8080/realms/middleware/.well-known/openid-configuration
```
이 URL을 호출하면 Authorization Endpoint, Token Endpoint, UserInfo Endpoint, 지원하는 Scope, 사용하는 서명 알고리즘 등 모든 설정이 JSON으로 반환된다.

> **참고**: Docker 환경에서는 `issuer` 값이 `http://keycloak:8080/...`으로 반환된다. Spring Boot는 Docker 내부에서 이 값을 사용하므로 문제없지만, 브라우저에서 직접 접근할 때는 `localhost:8080`을 사용해야 한다.

### 3.4 JWT 토큰 구조

JWT(JSON Web Token)는 `Header.Payload.Signature` 세 부분을 `.`으로 연결한 문자열이다.

```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIi
wibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWUsImlhdCI6MTUxNjIzOTAyMn
0.POstGetfAytaZS82wHcjoTyoqhMyxXiWdR7Nn7A29DNSl0EiXLdwJ6xC6AfgZWF
│                        │                               │
│     Header             │       Payload                 │     Signature
│  (Base64URL)           │    (Base64URL)                │   (Base64URL)
▼                        ▼                               ▼

┌─── Header (디코딩) ──┐   ┌──── Payload (디코딩) ────┐   ┌── Signature ──┐
│ {                     │   │ {                         │   │ RSASHA256(    │
│   "alg": "RS256",     │   │   "sub": "user-id-123",  │   │   base64(hdr) │
│   "typ": "JWT",       │   │   "name": "홍길동",      │   │   + "."       │
│   "kid": "key-id"     │   │   "email": "hong@...",    │   │   + base64(   │
│ }                     │   │   "iat": 1516239022,      │   │     payload)  │
│                       │   │   "exp": 1516242622,      │   │   , privateKey│
│ alg: 서명 알고리즘    │   │   "iss": "http://kc/...", │   │ )             │
│ kid: 서명 키 ID       │   │   "aud": "middleware-app" │   │               │
└───────────────────────┘   │ }                         │   │ 서버 개인키로 │
                            │                           │   │ 서명하여      │
                            │ sub: 사용자 식별자        │   │ 위변조 방지   │
                            │ iss: 토큰 발급자          │   └───────────────┘
                            │ aud: 토큰 수신 대상       │
                            │ exp: 만료 시간            │
                            │ iat: 발급 시간            │
                            └───────────────────────────┘
```

**주요 Claim 설명:**

| Claim | 이름 | 설명 |
|-------|------|------|
| `sub` | Subject | 사용자 고유 식별자 (Keycloak에서는 UUID) |
| `iss` | Issuer | 토큰을 발급한 서버 URL |
| `aud` | Audience | 이 토큰을 사용할 클라이언트 ID |
| `exp` | Expiration | 토큰 만료 시간 (Unix timestamp) |
| `iat` | Issued At | 토큰 발급 시간 |
| `nbf` | Not Before | 이 시간 이전에는 토큰이 유효하지 않음 |
| `jti` | JWT ID | 토큰의 고유 ID (재사용 방지) |

### 3.5 Access Token vs Refresh Token vs ID Token

| 구분 | Access Token | Refresh Token | ID Token |
|------|-------------|---------------|----------|
| **용도** | API 리소스 접근 | Access Token 재발급 | 사용자 인증 증명 |
| **수명** | 짧음 (5~15분) | 김 (수 시간~수 일) | 짧음 (5~15분) |
| **전달 대상** | Resource Server (API) | Authorization Server만 | Client Application |
| **형식** | JWT 또는 Opaque | Opaque 문자열 | 반드시 JWT |
| **포함 정보** | scope, 권한 | 없음 (참조용) | 사용자 프로필 |
| **저장 위치** | 메모리 (서버 세션) | 서버 사이드만 | 검증 후 폐기 가능 |

### 3.6 본 프로젝트의 Keycloak OIDC 플로우

```
                    ┌─── mw-network (Docker) ───────────────────┐
                    │                                            │
 브라우저 ──443──► Nginx ──proxy──► Tomcat1 ──OIDC──► Keycloak  │
         (HTTPS)  │  (로드밸런서)   Tomcat2          (IdP)      │
                    │                    │                        │
                    │                    └──JDBC──► MySQL         │
                    └────────────────────────────────────────────┘
```

Spring Boot `application.properties`에서 Keycloak을 IdP로 설정:

```properties
# --- Client Registration ---
spring.security.oauth2.client.registration.keycloak.client-id=middleware-app
spring.security.oauth2.client.registration.keycloak.client-secret=<client-secret>
spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
spring.security.oauth2.client.registration.keycloak.authorization-grant-type=authorization_code
spring.security.oauth2.client.registration.keycloak.redirect-uri={baseUrl}/login/oauth2/code/{registrationId}

# --- Provider (Split URI 패턴) ---
spring.security.oauth2.client.provider.keycloak.issuer-uri=http://keycloak:8080/realms/middleware
spring.security.oauth2.client.provider.keycloak.authorization-uri=http://localhost:8080/realms/middleware/protocol/openid-connect/auth
spring.security.oauth2.client.provider.keycloak.token-uri=http://keycloak:8080/realms/middleware/protocol/openid-connect/token
spring.security.oauth2.client.provider.keycloak.jwk-set-uri=http://keycloak:8080/realms/middleware/protocol/openid-connect/certs
spring.security.oauth2.client.provider.keycloak.user-info-uri=http://keycloak:8080/realms/middleware/protocol/openid-connect/userinfo
spring.security.oauth2.client.provider.keycloak.user-name-attribute=preferred_username
```

> **핵심: Split URI 패턴**
>
> Docker Compose 환경에서 OIDC를 구성할 때, **브라우저가 접근하는 URI**와 **서버 간 통신 URI**를 분리해야 한다.
>
> | URI | 호스트 | 이유 |
> |-----|--------|------|
> | `authorization-uri` | `localhost:8080` | **브라우저**가 직접 Keycloak 로그인 페이지에 접근해야 하므로 호스트 네트워크 주소 사용 |
> | `issuer-uri` | `keycloak:8080` | Spring Boot가 **Docker 내부 네트워크**에서 Keycloak에 연결 |
> | `token-uri` | `keycloak:8080` | Tomcat → Keycloak 간 **서버 사이드** 토큰 교환 |
> | `jwk-set-uri` | `keycloak:8080` | JWT 서명 검증을 위한 공개키 조회 (서버 간 통신) |
> | `user-info-uri` | `keycloak:8080` | Access Token으로 사용자 정보 조회 (서버 간 통신) |
>
> 브라우저는 Docker 내부 DNS(`keycloak:8080`)를 해석할 수 없기 때문에, 사용자가 직접 접근하는 `authorization-uri`만 `localhost:8080`을 사용한다.

### 3.7 jwt.io에서 토큰 디코딩

1. https://jwt.io 접속
2. 왼쪽 "Encoded" 영역에 JWT 문자열을 붙여넣기
3. 오른쪽 "Decoded" 영역에서 Header, Payload, Signature를 확인

> **주의**: jwt.io에 프로덕션 토큰을 붙여넣지 말 것. jwt.io는 클라이언트 사이드에서 디코딩하지만, 민감한 토큰은 로컬에서 디코딩하는 것이 안전하다.

**CLI에서 JWT 디코딩:**

```bash
# JWT의 Payload 부분만 추출하여 디코딩
echo "eyJhbGciOi..." | cut -d. -f2 | base64 -d 2>/dev/null | jq .

# Python으로 디코딩
python3 -c "
import base64, json, sys
token = sys.argv[1]
payload = token.split('.')[1]
# Base64URL 패딩 보정
payload += '=' * (4 - len(payload) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2))
" "eyJhbGciOi..."
```

### 3.8 curl로 직접 토큰 발급/검증

**1. Authorization Code 방식 (일반적으로는 브라우저 필요, 테스트 시 Resource Owner Password 사용):**

```bash
# Resource Owner Password Grant로 Access Token 발급 (테스트 용도)
curl -s -X POST http://localhost:8080/realms/middleware/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=middleware-app" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "username=testuser" \
  -d "password=testpassword" \
  -d "scope=openid" | jq .
```

**2. Client Credentials Grant (서비스 간 통신):**

```bash
curl -s -X POST http://localhost:8080/realms/middleware/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=middleware-app" \
  -d "client_secret=YOUR_CLIENT_SECRET" | jq .
```

**3. Access Token으로 UserInfo 조회:**

```bash
curl -s http://localhost:8080/realms/middleware/protocol/openid-connect/userinfo \
  -H "Authorization: Bearer eyJhbGciOi..." | jq .
```

**4. Token Introspection (토큰 유효성 검증):**

```bash
curl -s -X POST http://localhost:8080/realms/middleware/protocol/openid-connect/token/introspect \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "token=eyJhbGciOi..." \
  -d "client_id=middleware-app" \
  -d "client_secret=YOUR_CLIENT_SECRET" | jq .
```

**5. Refresh Token으로 Access Token 재발급:**

```bash
curl -s -X POST http://localhost:8080/realms/middleware/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=eyJhbGciOi..." \
  -d "client_id=middleware-app" \
  -d "client_secret=YOUR_CLIENT_SECRET" | jq .
```

---

## 4. Spring Security + Keycloak 연동 원리

### 4.1 Spring Security 필터 체인 동작 원리

Spring Security는 서블릿 필터 체인 기반으로 동작한다. HTTP 요청이 컨트롤러에 도달하기 전에 여러 보안 필터를 순서대로 통과한다.

```
HTTP 요청
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  DelegatingFilterProxy (서블릿 필터 → 스프링 빈 위임)     │
│    │                                                      │
│    ▼                                                      │
│  FilterChainProxy (SecurityFilterChain 관리)              │
│    │                                                      │
│    ▼                                                      │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  SecurityFilterChain (순서대로 실행)                  │ │
│  │                                                      │ │
│  │  1. SecurityContextPersistenceFilter                 │ │
│  │     → 세션에서 SecurityContext 복원                   │ │
│  │                                                      │ │
│  │  2. CsrfFilter                                       │ │
│  │     → CSRF 토큰 검증                                 │ │
│  │                                                      │ │
│  │  3. LogoutFilter                                     │ │
│  │     → /logout 요청 처리                              │ │
│  │                                                      │ │
│  │  4. OAuth2AuthorizationRequestRedirectFilter         │ │
│  │     → /oauth2/authorization/{registrationId}         │ │
│  │     → Keycloak 로그인 페이지로 리다이렉트            │ │
│  │                                                      │ │
│  │  5. OAuth2LoginAuthenticationFilter                  │ │
│  │     → /login/oauth2/code/{registrationId}            │ │
│  │     → Authorization Code → Access Token 교환         │ │
│  │                                                      │ │
│  │  6. UsernamePasswordAuthenticationFilter             │ │
│  │     → 폼 로그인 처리                                 │ │
│  │                                                      │ │
│  │  7. BearerTokenAuthenticationFilter                  │ │
│  │     → Authorization: Bearer 헤더의 JWT 검증          │ │
│  │                                                      │ │
│  │  8. AuthorizationFilter                              │ │
│  │     → URL 패턴별 접근 권한 검증                      │ │
│  │     → permitAll(), authenticated(), hasRole() 등     │ │
│  │                                                      │ │
│  │  9. ExceptionTranslationFilter                       │ │
│  │     → 인증/인가 예외 → 로그인 페이지 리다이렉트      │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
    │
    ▼
 DispatcherServlet → Controller
```

### 4.2 OAuth2ResourceServer vs OAuth2Login 차이

| 구분 | `.oauth2Login()` | `.oauth2ResourceServer()` |
|------|-----------------|--------------------------|
| **용도** | 웹 애플리케이션 (브라우저 기반) | REST API 서버 |
| **인증 방식** | 브라우저 리다이렉트 플로우 | Bearer Token (헤더) |
| **세션** | 사용 (JSESSIONID 쿠키) | 무상태 (Stateless) |
| **토큰 저장** | 서버 세션에 저장 | 클라이언트가 관리 |
| **적용 필터** | OAuth2LoginAuthenticationFilter | BearerTokenAuthenticationFilter |
| **본 프로젝트** | 사용 중 (SecurityConfig.java) | 미사용 |

**본 프로젝트의 SecurityConfig:**

```java
@Bean
public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
    http
        .authorizeHttpRequests(auth -> auth
            // 공개 엔드포인트 (헬스체크, 모니터링)
            .requestMatchers("/", "/health", "/info").permitAll()
            .requestMatchers("/actuator/**").permitAll()
            // 보호된 엔드포인트
            .requestMatchers("/secured/**").authenticated()
            .anyRequest().permitAll()
        )
        .oauth2Login(oauth2 -> oauth2
            .defaultSuccessUrl("/secured/profile", true)
        )
        .logout(logout -> logout
            .logoutSuccessUrl("/")
            .permitAll()
        );
    return http.build();
}
```

**각 설정의 의미:**
- `.requestMatchers("/", "/health", "/info").permitAll()`: 헬스체크 엔드포인트는 인증 없이 접근 허용. Prometheus, 로드밸런서 등이 접근해야 하므로 공개.
- `.requestMatchers("/actuator/**").permitAll()`: Spring Actuator 메트릭 엔드포인트 공개. Scouter/Prometheus가 수집.
- `.requestMatchers("/secured/**").authenticated()`: `/secured/**` 경로는 인증된 사용자만 접근 가능.
- `.anyRequest().permitAll()`: 명시되지 않은 나머지 경로는 기본 공개.
- `.oauth2Login()`: Authorization Code Flow를 활성화. 인증이 필요한 요청이 오면 자동으로 Keycloak 로그인 페이지로 리다이렉트.
- `.defaultSuccessUrl("/secured/profile", true)`: 로그인 성공 시 `/secured/profile`로 이동. `true`는 항상 이 URL로 이동 (원래 요청 URL이 아닌).
- `.logoutSuccessUrl("/")`: 로그아웃 후 메인 페이지로 이동.

### 4.3 CORS 설정 방법과 왜 필요한지

**CORS(Cross-Origin Resource Sharing)란?**

브라우저의 동일 출처 정책(Same-Origin Policy)에 의해, `https://frontend.example.com`에서 `https://api.example.com`으로의 AJAX 요청은 기본적으로 차단된다. CORS는 서버가 "이 출처에서의 요청을 허용합니다"라고 명시적으로 선언하는 메커니즘이다.

```
브라우저 (https://frontend.com)
    │
    │ ① Preflight Request (OPTIONS)
    │ Origin: https://frontend.com
    │ Access-Control-Request-Method: POST
    │ ─────────────────────────────────────► API Server (https://api.com)
    │
    │ ② Preflight Response
    │ Access-Control-Allow-Origin: https://frontend.com
    │ Access-Control-Allow-Methods: GET, POST
    │ Access-Control-Allow-Headers: Authorization
    │ ◄─────────────────────────────────────
    │
    │ ③ 실제 요청 (POST)
    │ ─────────────────────────────────────►
    │
    │ ④ 응답
    │ ◄─────────────────────────────────────
```

**Spring Security에서 CORS 설정:**

```java
@Bean
public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
    http
        .cors(cors -> cors.configurationSource(corsConfigurationSource()))
        // ... 기존 설정 ...
    ;
    return http.build();
}

@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of("https://localhost", "https://frontend.middleware.local"));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE"));
    config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
    config.setAllowCredentials(true);  // 쿠키 포함 허용
    config.setMaxAge(3600L);  // Preflight 캐시 1시간

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
}
```

### 4.4 CSRF 방어 원리

**CSRF(Cross-Site Request Forgery) 공격:**
사용자가 이미 로그인된 상태에서, 공격자가 만든 악성 페이지가 사용자의 세션 쿠키를 이용해 의도하지 않은 요청을 보내는 공격.

**Spring Security의 CSRF 방어 메커니즘:**

```
1. 서버가 CSRF 토큰 생성 → 폼에 hidden field로 삽입
2. 사용자가 폼 제출 시 CSRF 토큰을 함께 전송
3. 서버가 세션의 CSRF 토큰과 요청의 CSRF 토큰을 비교
4. 일치하지 않으면 403 Forbidden
```

- Spring Security는 기본적으로 CSRF 보호가 활성화되어 있다
- `GET`, `HEAD`, `OPTIONS`, `TRACE` 요청은 CSRF 검증을 하지 않는다 (안전한 메서드)
- **SPA + JWT 구조에서는** CSRF를 비활성화하는 경우가 많다 (쿠키 기반 세션을 사용하지 않으므로):

```java
http.csrf(csrf -> csrf.disable());  // REST API의 경우
```

본 프로젝트는 쿠키 기반 세션(`.oauth2Login()`)을 사용하므로 CSRF 보호를 유지하는 것이 바람직하다.

---

## 5. 웹 보안 (OWASP Top 10)

### 5.1 SQL Injection

**원리:**
사용자 입력이 SQL 쿼리에 직접 삽입되어 쿼리 구조를 변조하는 공격.

```
[취약한 코드]
String query = "SELECT * FROM users WHERE username = '" + userInput + "'";

[공격 입력]
userInput = "' OR '1'='1' --"

[실행되는 SQL]
SELECT * FROM users WHERE username = '' OR '1'='1' --'
→ 모든 사용자 정보가 반환됨
```

**방어: PreparedStatement (파라미터 바인딩)**

```java
// 취약한 코드 (절대 사용 금지)
String sql = "SELECT * FROM users WHERE id = " + userId;
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery(sql);

// 안전한 코드 (PreparedStatement)
String sql = "SELECT * FROM users WHERE id = ?";
PreparedStatement pstmt = conn.prepareStatement(sql);
pstmt.setInt(1, userId);  // 파라미터 바인딩 → SQL 구조 변조 불가
ResultSet rs = pstmt.executeQuery();

// Spring Data JPA (기본적으로 안전)
@Query("SELECT u FROM User u WHERE u.username = :username")
User findByUsername(@Param("username") String username);
```

**Spring Data JPA를 사용하면 기본적으로 PreparedStatement를 사용**하므로 SQL Injection에 안전하다. 단, `@Query`에서 네이티브 쿼리를 문자열 연결로 만들면 취약해질 수 있다.

### 5.2 XSS (Cross-Site Scripting)

**유형:**

| 유형 | 설명 | 예시 |
|------|------|------|
| **Stored XSS** | 악성 스크립트가 DB에 저장되어 다른 사용자가 조회 시 실행 | 게시판 글에 `<script>` 삽입 |
| **Reflected XSS** | URL 파라미터의 스크립트가 응답에 그대로 반영 | `?search=<script>alert(1)</script>` |
| **DOM-based XSS** | 클라이언트 JavaScript가 DOM을 안전하지 않게 조작 | `innerHTML = location.hash` |

**방어: Content-Security-Policy (CSP) 헤더:**

```nginx
# Nginx에서 CSP 설정
add_header Content-Security-Policy "
    default-src 'self';
    script-src 'self' 'nonce-{random}';
    style-src 'self' 'unsafe-inline';
    img-src 'self' data:;
    font-src 'self';
    connect-src 'self' https://keycloak.middleware.local;
    frame-ancestors 'none';
    base-uri 'self';
    form-action 'self';
" always;
```

**CSP 디렉티브 설명:**
- `default-src 'self'`: 기본적으로 같은 출처의 리소스만 허용
- `script-src 'self'`: 외부 스크립트 차단 (XSS 방어의 핵심)
- `frame-ancestors 'none'`: iframe 삽입 차단 (Clickjacking 방어)

### 5.3 CSRF (Cross-Site Request Forgery)

**원리:**

```
1. 사용자가 은행 사이트(bank.com)에 로그인 → 세션 쿠키 발급
2. 사용자가 악성 사이트(evil.com) 방문
3. evil.com에 숨겨진 폼이 자동으로 bank.com에 송금 요청 전송
4. 브라우저가 bank.com 세션 쿠키를 자동으로 포함
5. bank.com은 정상 요청으로 인식하여 처리
```

**방어 방법:**

1. **SameSite Cookie 속성:**
```
Set-Cookie: JSESSIONID=abc123; SameSite=Strict; Secure; HttpOnly
```
- `Strict`: 다른 사이트에서의 모든 요청에 쿠키 미전송
- `Lax`: GET 요청은 쿠키 전송, POST는 미전송 (기본값)

2. **Anti-CSRF Token**: Spring Security가 자동으로 처리 (4.4절 참조)

3. **Origin/Referer 헤더 검증**: 서버에서 요청의 출처 확인

### 5.4 SSRF (Server-Side Request Forgery)

**원리:**
서버가 사용자 입력을 기반으로 내부 네트워크 리소스에 요청을 보내도록 유도하는 공격.

```
[취약한 코드]
@GetMapping("/fetch")
public String fetch(@RequestParam String url) {
    return restTemplate.getForObject(url, String.class);  // 위험!
}

[공격]
GET /fetch?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/
→ AWS 메타데이터 서버에서 IAM 크레덴셜 탈취

GET /fetch?url=http://mysql:3306/
→ Docker 내부 네트워크의 MySQL에 직접 접근
```

**방어:**
```java
// URL 허용 목록(Allowlist) 기반 검증
private static final Set<String> ALLOWED_HOSTS = Set.of(
    "api.example.com",
    "cdn.example.com"
);

@GetMapping("/fetch")
public String fetch(@RequestParam String url) {
    URI uri = URI.create(url);
    if (!ALLOWED_HOSTS.contains(uri.getHost())) {
        throw new SecurityException("허용되지 않은 호스트: " + uri.getHost());
    }
    // 내부 IP 대역 차단 (10.x, 172.16.x, 192.168.x, 169.254.x)
    InetAddress addr = InetAddress.getByName(uri.getHost());
    if (addr.isSiteLocalAddress() || addr.isLoopbackAddress() || addr.isLinkLocalAddress()) {
        throw new SecurityException("내부 네트워크 접근 차단");
    }
    return restTemplate.getForObject(url, String.class);
}
```

### 5.5 Nginx 보안 헤더 종합 설정

본 프로젝트의 Nginx에 추가할 수 있는 보안 헤더 종합 설정:

```nginx
server {
    listen 443 ssl;
    server_name localhost;

    # ── 기존 SSL 설정 ──
    ssl_certificate     /etc/nginx/ssl/server-chain.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;

    # ── 보안 헤더 ──

    # HSTS: HTTPS 강제 (1년)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Clickjacking 방어: iframe 삽입 차단
    add_header X-Frame-Options "DENY" always;

    # MIME 스니핑 방지: Content-Type 헤더를 신뢰
    add_header X-Content-Type-Options "nosniff" always;

    # XSS 필터 (레거시 브라우저용, CSP가 더 강력)
    add_header X-XSS-Protection "1; mode=block" always;

    # Referrer 정책: HTTPS→HTTP 전환 시 Referer 헤더 제거
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # 권한 정책: 브라우저 기능(카메라, 마이크 등) 제한
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    # CSP: 리소스 로딩 제한 (XSS 방어의 핵심)
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-ancestors 'none';" always;

    # 서버 정보 숨기기 (http 블록에서 설정)
    # server_tokens off;  → nginx.conf의 http 블록에 추가

    # ── 프록시 설정 ──
    location / {
        proxy_pass http://was_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 프록시 응답에서 서버 정보 숨기기
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
    }
}
```

**각 헤더의 검증 방법:**

```bash
# 응답 헤더 확인
curl -kI https://localhost

# 특정 헤더만 확인
curl -kI https://localhost 2>/dev/null | grep -i "strict-transport\|x-frame\|x-content-type\|content-security"
```

---

## 6. Docker 보안

### 6.1 컨테이너를 root가 아닌 사용자로 실행

기본적으로 Docker 컨테이너는 root 사용자로 실행된다. 컨테이너 탈출(Container Escape) 취약점이 발견되면 호스트의 root 권한을 탈취할 수 있으므로, 비root 사용자로 실행해야 한다.

**Dockerfile에서 비root 사용자 설정:**

```dockerfile
FROM tomcat:10.1-jdk17

# 비root 사용자 생성
RUN groupadd -r appuser && useradd -r -g appuser -d /usr/local/tomcat -s /sbin/nologin appuser

# 필요한 디렉토리 권한 설정
RUN chown -R appuser:appuser /usr/local/tomcat

# 비root 사용자로 전환
USER appuser

EXPOSE 8080
CMD ["catalina.sh", "run"]
```

**docker-compose.yml에서 설정:**

```yaml
services:
  tomcat1:
    build:
      context: ./app
      dockerfile: Dockerfile
    user: "1000:1000"  # UID:GID 지정
    # ...
```

**현재 컨테이너의 실행 사용자 확인:**

```bash
# 각 컨테이너의 실행 사용자 확인
docker exec mw-tomcat1 whoami
docker exec mw-nginx whoami
docker exec mw-mysql whoami

# 프로세스 확인
docker exec mw-tomcat1 ps aux
```

> **참고**: Nginx 공식 이미지는 마스터 프로세스가 root로 실행되지만 워커 프로세스는 `nginx` 사용자로 실행된다. MySQL 공식 이미지는 `mysql` 사용자로 실행된다. Keycloak 공식 이미지는 기본적으로 비root 사용자로 실행된다.

### 6.2 Docker 이미지 취약점 스캔

**Docker Scout (Docker Desktop 내장):**

```bash
# 이미지 취약점 분석
docker scout cves mw-tomcat1

# 권장 사항 확인
docker scout recommendations mw-tomcat1

# 특정 심각도 이상만 표시
docker scout cves --only-severity critical,high mw-tomcat1
```

**Trivy (오픈소스, 추천):**

```bash
# Trivy 설치 (macOS)
brew install aquasecurity/trivy/trivy

# 이미지 스캔
trivy image mw-tomcat1:latest

# HIGH, CRITICAL만 표시
trivy image --severity HIGH,CRITICAL mw-tomcat1:latest

# docker-compose의 모든 이미지 스캔 스크립트
for img in $(docker compose config --images); do
    echo "=== Scanning: $img ==="
    trivy image --severity HIGH,CRITICAL "$img"
done

# 파일시스템 스캔 (소스코드 취약점)
trivy fs --security-checks vuln,config ./app/
```

**CI/CD 파이프라인에서 자동 스캔:**

```yaml
# GitHub Actions 예시
- name: Trivy 이미지 스캔
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'mw-tomcat1:latest'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'  # 취약점 발견 시 빌드 실패
```

### 6.3 시크릿 관리

**현재 프로젝트의 문제점:**

docker-compose.yml에 패스워드가 평문으로 노출되어 있다:

```yaml
# 현재 (취약)
environment:
  MYSQL_ROOT_PASSWORD: root_password
  KEYCLOAK_ADMIN_PASSWORD: admin
  GF_SECURITY_ADMIN_PASSWORD: admin
```

**개선 방법 1: .env 파일 분리**

```bash
# .env 파일 생성 (Git에 커밋하지 않음!)
MYSQL_ROOT_PASSWORD=S3cur3_P@ssw0rd!
MYSQL_APP_PASSWORD=App_P@ssw0rd!
KEYCLOAK_ADMIN_PASSWORD=Kc_Adm1n_P@ss!
GRAFANA_ADMIN_PASSWORD=Gr@f_Adm1n!
```

```yaml
# docker-compose.yml
services:
  mysql:
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_PASSWORD: ${MYSQL_APP_PASSWORD}
```

```gitignore
# .gitignore에 추가
.env
*.env
```

**개선 방법 2: Docker Secrets (Swarm 모드)**

```yaml
# docker-compose.yml (Docker Swarm 필요)
services:
  mysql:
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root_pw
    secrets:
      - mysql_root_pw

secrets:
  mysql_root_pw:
    file: ./secrets/mysql_root_password.txt  # 파일에서 읽기
```

**개선 방법 3: Docker Compose Secrets (Swarm 없이)**

Docker Compose v2에서는 Swarm 없이도 시크릿 파일을 마운트할 수 있다:

```yaml
services:
  mysql:
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root_pw
    secrets:
      - mysql_root_pw

secrets:
  mysql_root_pw:
    file: ./secrets/mysql_root_password.txt
```

### 6.4 네트워크 격리 (Docker Network)

현재 프로젝트는 모든 서비스가 `mw-network` 하나의 네트워크에 연결되어 있다. 보안을 강화하려면 역할별로 네트워크를 분리해야 한다.

```
┌─── frontend-net ──────────────────────────┐
│                                            │
│  브라우저 ──► Nginx ──► Keycloak           │
│                                            │
└────────────┬───────────────────────────────┘
             │
┌─── app-net ┴──────────────────────────────┐
│                                            │
│  Nginx ──► Tomcat1, Tomcat2               │
│             │                              │
│  Scouter Server ◄── Tomcat (Agent)        │
│                                            │
└────────────┬───────────────────────────────┘
             │
┌─── db-net ─┴──────────────────────────────┐
│                                            │
│  Tomcat1, Tomcat2 ──► MySQL               │
│                                            │
└────────────────────────────────────────────┘
             │
┌─── monitor-net ───────────────────────────┐
│                                            │
│  Prometheus ──► Node Exporter             │
│  Prometheus ──► Nginx Exporter            │
│  Grafana ──► Prometheus                   │
│                                            │
└────────────────────────────────────────────┘
```

**docker-compose.yml 네트워크 분리 예시:**

```yaml
services:
  nginx:
    networks:
      - frontend-net
      - app-net

  tomcat1:
    networks:
      - app-net
      - db-net

  tomcat2:
    networks:
      - app-net
      - db-net

  mysql:
    networks:
      - db-net    # DB는 app-net에서만 접근 가능

  keycloak:
    networks:
      - frontend-net

  prometheus:
    networks:
      - monitor-net
      - app-net   # 메트릭 수집을 위해

  grafana:
    networks:
      - monitor-net
      - frontend-net  # 대시보드 접근을 위해

networks:
  frontend-net:
    driver: bridge
  app-net:
    driver: bridge
    internal: true  # 외부에서 직접 접근 불가
  db-net:
    driver: bridge
    internal: true  # 외부에서 직접 접근 불가
  monitor-net:
    driver: bridge
    internal: true
```

**`internal: true`의 의미:**
- 해당 네트워크의 컨테이너는 외부(인터넷)에 직접 접근할 수 없다
- 해당 네트워크에 연결된 컨테이너 간에만 통신 가능
- DB, 내부 서비스에 적합

### 6.5 read_only 파일시스템 설정

컨테이너의 파일시스템을 읽기 전용으로 설정하면, 공격자가 컨테이너 내부에 악성 파일을 쓸 수 없다.

```yaml
services:
  nginx:
    image: nginx:1.24
    read_only: true
    tmpfs:
      - /var/run:size=1M        # PID 파일 저장용
      - /var/cache/nginx:size=10M  # 캐시 디렉토리
      - /tmp:size=5M
    volumes:
      - ./configs/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./configs/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./configs/nginx/ssl:/etc/nginx/ssl:ro
      - nginx_logs:/var/log/nginx  # 로그는 볼륨으로

  tomcat1:
    read_only: true
    tmpfs:
      - /tmp:size=100M
      - /usr/local/tomcat/work:size=50M  # JSP 컴파일용
    volumes:
      - tomcat1_logs:/usr/local/tomcat/logs

  mysql:
    # MySQL은 데이터 쓰기가 필수이므로 read_only 대신 볼륨으로 제한
    volumes:
      - mysql_data:/var/lib/mysql
    # 추가 보안: capability 제한
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - SETGID
      - SETUID
```

**추가 Docker 보안 설정:**

```yaml
services:
  tomcat1:
    # 권한 상승 방지
    security_opt:
      - no-new-privileges:true

    # 불필요한 Linux Capability 제거
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE  # 1024 이하 포트 바인딩 (필요 시)

    # 리소스 제한 (DoS 방어)
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M

    # PID 수 제한 (Fork Bomb 방어)
    pids_limit: 100
```

---

## 7. 보안 점검 체크리스트

배포 전 반드시 확인해야 할 항목을 카테고리별로 정리한다.

### TLS / 인증서

| # | 점검 항목 | 확인 명령어 | 상태 |
|---|---------|-----------|------|
| 1 | TLS 1.2 이상만 허용되는가 | `openssl s_client -connect localhost:443 -tls1_1` (실패해야 정상) | [ ] |
| 2 | 안전한 Cipher Suite만 허용되는가 | `nmap --script ssl-enum-ciphers -p 443 localhost` | [ ] |
| 3 | 인증서 만료일이 30일 이상 남았는가 | `openssl x509 -in server.crt -enddate -noout` | [ ] |
| 4 | 인증서 체인이 올바른가 | `openssl verify -CAfile ca.crt server.crt` | [ ] |
| 5 | HSTS 헤더가 설정되어 있는가 | `curl -kI https://localhost \| grep Strict` | [ ] |
| 6 | HTTP → HTTPS 리다이렉트가 동작하는가 | `curl -I http://localhost` (301이어야 정상) | [ ] |
| 7 | 개인키 파일 권한이 600인가 | `ls -la configs/nginx/ssl/server.key` | [ ] |

### 인증 / 인가

| # | 점검 항목 | 확인 방법 | 상태 |
|---|---------|---------|------|
| 8 | 보호된 엔드포인트에 비인증 접근이 차단되는가 | `curl -k https://localhost/secured/profile` (302 또는 401) | [ ] |
| 9 | Keycloak 관리자 비밀번호가 기본값이 아닌가 | docker-compose.yml 확인 | [ ] |
| 10 | OAuth2 client_secret이 코드에 하드코딩되지 않았는가 | 소스코드 검색 | [ ] |
| 11 | JWT 토큰 만료 시간이 적절한가 (15분 이하 권장) | Keycloak Realm 설정 확인 | [ ] |
| 12 | Refresh Token 로테이션이 활성화되어 있는가 | Keycloak 클라이언트 설정 확인 | [ ] |

### 웹 보안 헤더

| # | 점검 항목 | 확인 명령어 | 상태 |
|---|---------|-----------|------|
| 13 | X-Frame-Options 헤더가 설정되어 있는가 | `curl -kI https://localhost \| grep X-Frame` | [ ] |
| 14 | X-Content-Type-Options: nosniff가 설정되어 있는가 | `curl -kI https://localhost \| grep X-Content-Type` | [ ] |
| 15 | Content-Security-Policy가 설정되어 있는가 | `curl -kI https://localhost \| grep Content-Security` | [ ] |
| 16 | 서버 버전 정보가 숨겨져 있는가 (server_tokens off) | `curl -kI https://localhost \| grep Server` | [ ] |
| 17 | X-Powered-By 헤더가 제거되어 있는가 | `curl -kI https://localhost \| grep X-Powered` | [ ] |

### Docker / 인프라

| # | 점검 항목 | 확인 방법 | 상태 |
|---|---------|---------|------|
| 18 | 불필요한 포트가 외부에 노출되지 않았는가 | `docker compose ps` 포트 확인 | [ ] |
| 19 | 환경변수에 비밀번호가 평문으로 노출되지 않았는가 | docker-compose.yml 확인 | [ ] |
| 20 | .env 파일이 .gitignore에 포함되어 있는가 | `.gitignore` 확인 | [ ] |
| 21 | 컨테이너가 비root 사용자로 실행되는가 | `docker exec <컨테이너> whoami` | [ ] |
| 22 | Docker 이미지에 CRITICAL 취약점이 없는가 | `trivy image --severity CRITICAL <이미지>` | [ ] |
| 23 | 볼륨이 :ro (읽기 전용)으로 마운트되어 있는가 (설정 파일) | docker-compose.yml 확인 | [ ] |
| 24 | 네트워크가 역할별로 분리되어 있는가 | docker-compose.yml 네트워크 설정 확인 | [ ] |
| 25 | MySQL 포트(3306)가 외부에 불필요하게 노출되지 않았는가 | 프로덕션에서는 제거 필요 | [ ] |

### 애플리케이션

| # | 점검 항목 | 확인 방법 | 상태 |
|---|---------|---------|------|
| 26 | SQL 쿼리에 파라미터 바인딩을 사용하는가 | 소스코드 리뷰 | [ ] |
| 27 | 사용자 입력이 적절히 검증/이스케이프되는가 | 소스코드 리뷰 | [ ] |
| 28 | 에러 메시지에 내부 정보(스택 트레이스)가 노출되지 않는가 | 에러 발생 시 응답 확인 | [ ] |
| 29 | Actuator 엔드포인트가 적절히 보호되어 있는가 | 민감한 엔드포인트 접근 테스트 | [ ] |
| 30 | 로그에 민감 정보(비밀번호, 토큰)가 기록되지 않는가 | 로그 파일 검사 | [ ] |

### 빠른 점검 스크립트

```bash
#!/bin/bash
# security-check.sh - 배포 전 자동 보안 점검

echo "=== 보안 점검 시작 ==="

# 1. TLS 버전 확인
echo -n "[1] TLS 1.1 차단: "
if openssl s_client -connect localhost:443 -tls1_1 2>&1 | grep -q "alert protocol version"; then
    echo "PASS"
else
    echo "FAIL - TLS 1.1이 허용됨"
fi

# 2. HSTS 헤더
echo -n "[2] HSTS 헤더: "
if curl -kIs https://localhost | grep -qi "strict-transport-security"; then
    echo "PASS"
else
    echo "FAIL"
fi

# 3. HTTP → HTTPS 리다이렉트
echo -n "[3] HTTP→HTTPS 리다이렉트: "
STATUS=$(curl -Is http://localhost | head -1 | awk '{print $2}')
if [ "$STATUS" = "301" ]; then
    echo "PASS"
else
    echo "FAIL - HTTP 상태: $STATUS"
fi

# 4. 보호 엔드포인트 접근 제한
echo -n "[4] /secured 접근 제한: "
STATUS=$(curl -ks -o /dev/null -w "%{http_code}" https://localhost/secured/profile)
if [ "$STATUS" = "302" ] || [ "$STATUS" = "401" ]; then
    echo "PASS (HTTP $STATUS)"
else
    echo "FAIL - HTTP $STATUS"
fi

# 5. 서버 버전 노출
echo -n "[5] 서버 버전 숨김: "
if curl -kIs https://localhost | grep -q "nginx/"; then
    echo "FAIL - Nginx 버전 노출됨"
else
    echo "PASS"
fi

# 6. 인증서 만료일
echo -n "[6] 인증서 만료: "
EXPIRY=$(openssl s_client -connect localhost:443 -servername localhost 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
echo "$EXPIRY"

# 7. 컨테이너 실행 사용자
echo "[7] 컨테이너 실행 사용자:"
for c in mw-nginx mw-tomcat1 mw-tomcat2 mw-mysql mw-keycloak; do
    USER=$(docker exec $c whoami 2>/dev/null || echo "컨테이너 없음")
    echo "  $c: $USER"
done

# 8. 외부 노출 포트
echo "[8] 외부 노출 포트:"
docker compose ps --format "table {{.Name}}\t{{.Ports}}" 2>/dev/null || \
docker compose ps

echo "=== 점검 완료 ==="
```

---

## 참고 자료

- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) - Nginx/Apache SSL 설정 생성기
- [OWASP Top 10 (2021)](https://owasp.org/www-project-top-ten/) - 웹 애플리케이션 보안 위험 목록
- [Keycloak 공식 문서](https://www.keycloak.org/documentation) - OIDC/OAuth2 설정
- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/) - Docker 공식 보안 가이드
- [RFC 8446 (TLS 1.3)](https://datatracker.ietf.org/doc/html/rfc8446) - TLS 1.3 명세
- [RFC 6749 (OAuth 2.0)](https://datatracker.ietf.org/doc/html/rfc6749) - OAuth 2.0 명세
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html) - OIDC 명세
