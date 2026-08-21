#!/usr/bin/env bash
# Crea la identidad de firma "Companion Dev" en tu llavero (una sola vez).
#
# El porqué: bundle.sh firma ad-hoc (--sign -) y esa firma cambia en cada
# build, así que macOS invalida los permisos TCC (micrófono, reconocimiento
# de voz) en CADA rebuild: el micrófono empieza a entregar 0 Hz y la sesión
# reporta "el micrófono no está disponible". Con un certificado propio la
# firma es estable y los permisos sobreviven. Portado del prototipo. macOS puede pedirte tu contraseña al
# confiar en el certificado: acéptalo. La primera firma puede preguntar si
# codesign puede usar la llave: "Permitir siempre".
set -euo pipefail

NAME="Companion Dev"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "ya existe la identidad '$NAME'; nada que hacer"
  exit 0
fi

cat > "$DIR/ext.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Companion Dev
[v3]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$DIR/key.pem" \
  -out "$DIR/cert.pem" -days 3650 -nodes -config "$DIR/ext.cnf"
# -legacy: el keychain de macOS no lee el cifrado moderno de openssl 3.
openssl pkcs12 -export -legacy -out "$DIR/companion.p12" \
  -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -passout pass:companion \
  2>/dev/null || \
openssl pkcs12 -export -out "$DIR/companion.p12" \
  -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -passout pass:companion

# -A: cualquier app puede usar la llave — evita que codesign se quede
# colgado esperando un diálogo en cada build. Es una llave que solo firma
# builds locales; si te incomoda, quita -A y acepta el diálogo una vez.
security import "$DIR/companion.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" -P companion -A

# Confiar el certificado para firma de código (aquí sale el diálogo).
security add-trusted-cert -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" "$DIR/cert.pem"

security find-identity -v -p codesigning | grep "$NAME" \
  && echo "ok  identidad '$NAME' lista; el siguiente scripts/bundle.sh firma con ella"
