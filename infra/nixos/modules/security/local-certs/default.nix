{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.security.rave.localCerts;

  certScript = pkgs.writeShellScript "generate-localhost-certs" ''
    set -euo pipefail
    CERT_DIR=${cfg.certDir}
    mkdir -p "$CERT_DIR"

    if [[ -f "$CERT_DIR/cert.pem" ]]; then
      exit 0
    fi

    echo "Generating SSL certificates for ${cfg.commonName}..."

    ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/ca-key.pem" 4096
    ${pkgs.openssl}/bin/openssl req -new -x509 -days ${toString cfg.daysValid} \
      -key "$CERT_DIR/ca-key.pem" -out "$CERT_DIR/ca.pem" -subj "${cfg.caSubject}"

    ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
    ${pkgs.openssl}/bin/openssl req -new -key "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.csr" -subj "${cfg.serverSubject}"

    cat > "$CERT_DIR/cert.conf" <<'CONF'
${cfg.sanConfig}
CONF

    ${pkgs.openssl}/bin/openssl x509 -req -days ${toString cfg.daysValid} \
      -in "$CERT_DIR/cert.csr" -CA "$CERT_DIR/ca.pem" -CAkey "$CERT_DIR/ca-key.pem" -CAcreateserial \
      -out "$CERT_DIR/cert.pem" -extensions v3_req -extfile "$CERT_DIR/cert.conf"

    chmod 755 "$CERT_DIR"
    chmod 644 "$CERT_DIR"/cert.pem "$CERT_DIR"/ca.pem
    chmod 640 "$CERT_DIR"/key.pem
    chgrp -f traefik "$CERT_DIR"/cert.pem "$CERT_DIR"/key.pem 2>/dev/null || true
  '';

in
{
  options.security.rave.localCerts = {
    enable = mkEnableOption "Generate development TLS certificates";

    certDir = mkOption {
      type = types.str;
      default = "/var/lib/acme/localhost";
      description = "Directory to store generated certificates.";
    };

    commonName = mkOption {
      type = types.str;
      default = "localhost";
      description = "CN for the generated certificate.";
    };

    daysValid = mkOption {
      type = types.int;
      default = 365;
      description = "Validity period for certificates.";
    };

    caSubject = mkOption {
      type = types.str;
      default = "/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=RAVE-CA";
      description = "Subject string for the local CA.";
    };

    serverSubject = mkOption {
      type = types.str;
      default = "/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=localhost";
      description = "Subject for the server certificate CSR.";
    };

    sanConfig = mkOption {
      type = types.lines;
      default = ''
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = SF
O = RAVE
OU = Dev
CN = localhost

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = rave.local
DNS.3 = *.rave.local
DNS.4 = outline.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
'';
      description = "OpenSSL config snippet describing SAN entries.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.generate-localhost-certs = {
      description = "Generate self-signed SSL certificates";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStart = certScript;
      };
    };
  };
}
