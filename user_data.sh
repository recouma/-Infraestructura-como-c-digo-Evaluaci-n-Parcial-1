#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -euxo pipefail

ok_nginx() {
  # Instala y levanta nginx nativo como último recurso (si Docker no está disponible)
  if command -v amazon-linux-extras >/dev/null 2>&1; then
    amazon-linux-extras enable nginx1 || true
  fi
  yum install -y nginx || dnf install -y nginx || true
  echo "<h1>dtapia / quesotapia (fallback nginx)</h1>" > /usr/share/nginx/html/index.html ||         echo "<h1>dtapia / quesotapia (fallback nginx)</h1>" > /usr/local/nginx/html/index.html || true
  systemctl enable nginx || true
  systemctl restart nginx || true
}

# 1) Instalar Docker (Amazon Linux 2 / 2023)
if [ -f /etc/system-release ] && grep -qi "Amazon Linux 2" /etc/system-release; then
  amazon-linux-extras enable docker || true
  yum clean metadata -y || true
  yum install -y docker || true
elif [ -f /etc/os-release ] && grep -qi "Amazon Linux 2023" /etc/os-release; then
  dnf install -y docker || true
else
  yum install -y docker || dnf install -y docker || true
fi

systemctl enable docker || true
systemctl start docker || true

# 2) Esperar a que Docker esté listo (máx 60s). Si no, usar nginx de sistema
if ! timeout 60 bash -c 'until docker info >/dev/null 2>&1; do sleep 2; done'; then
  ok_nginx
  exit 0
fi

# 3) Intentar la app; si pull o run fallan, fallback a nginx:alpine (contenedor)
IMG="${IMG}"
docker pull "$IMG" || true
docker rm -f dtapia-app || true
if ! docker run -d --restart unless-stopped -p 80:80 --name dtapia-app "$IMG"; then
  docker rm -f dtapia-app || true
  docker run -d --restart unless-stopped -p 80:80 --name dtapia-app nginx:alpine || true
fi
