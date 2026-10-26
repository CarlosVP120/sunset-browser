#!/bin/zsh
# Crea en tu Llavero el certificado "Sunset Local Signing" (autofirmado, solo para firmar código).
# Con él, scripts/bundle.sh firma Sunset siempre igual y macOS deja de pedir la contraseña del Mac
# para leer las contraseñas guardadas después de cada compilación (ver CONTRIBUTING.md).
set -euo pipefail

NAME="Sunset Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    echo "El certificado «$NAME» ya existe."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSWORD="$(uuidgen)"

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

# Certificado de 10 años con su clave privada.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/cert.p12" -passout "pass:$PASSWORD"

# Al Llavero de inicio de sesión; solo codesign puede usar la clave sin preguntar.
security import "$WORK/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASSWORD" -T /usr/bin/codesign

echo "Listo: «$NAME» está en tu Llavero. Vuelve a compilar con ./scripts/bundle.sh"
