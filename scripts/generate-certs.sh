#!/bin/bash
# ============================================
# 자체 CA 구축 및 서버 인증서 발급 스크립트
# ============================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSL_DIR="$PROJECT_DIR/configs/nginx/ssl"
mkdir -p "$SSL_DIR"

echo "=========================================="
echo " Self-Signed CA & Server Certificate"
echo "=========================================="

# ── 1. Root CA 개인키 생성 ──
echo "[1/5] Generating Root CA private key..."
openssl genrsa -out "$SSL_DIR/ca.key" 4096

# ── 2. Root CA 인증서 생성 (10년) ──
echo "[2/5] Generating Root CA certificate..."
openssl req -x509 -new -nodes \
    -key "$SSL_DIR/ca.key" \
    -sha256 -days 3650 \
    -out "$SSL_DIR/ca.crt" \
    -subj "/C=KR/ST=Seoul/L=Seoul/O=Middleware Lab/OU=DevOps/CN=Middleware Root CA"

# ── 3. 서버 개인키 생성 ──
echo "[3/5] Generating server private key..."
openssl genrsa -out "$SSL_DIR/server.key" 2048

# ── 4. 서버 CSR(인증서 서명 요청) 생성 ──
echo "[4/5] Generating server CSR..."
cat > "$SSL_DIR/server.cnf" << 'CNFEOF'
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
CNFEOF

openssl req -new \
    -key "$SSL_DIR/server.key" \
    -out "$SSL_DIR/server.csr" \
    -config "$SSL_DIR/server.cnf"

# ── 5. CA로 서버 인증서 서명 (1년) ──
echo "[5/5] Signing server certificate with CA..."
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

# 인증서 체인 생성 (서버 인증서 + CA 인증서)
cat "$SSL_DIR/server.crt" "$SSL_DIR/ca.crt" > "$SSL_DIR/server-chain.crt"

echo ""
echo "=========================================="
echo " Certificates generated successfully!"
echo "=========================================="
echo ""
echo " CA Certificate  : $SSL_DIR/ca.crt"
echo " Server Key      : $SSL_DIR/server.key"
echo " Server Cert     : $SSL_DIR/server.crt"
echo " Cert Chain      : $SSL_DIR/server-chain.crt"
echo ""
echo " Certificate info:"
openssl x509 -in "$SSL_DIR/server.crt" -noout -subject -dates -issuer
echo "=========================================="
