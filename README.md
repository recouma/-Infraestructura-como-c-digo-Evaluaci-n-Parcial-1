# Infra – dtapia / quesotapia (Eval 1)

Infra mínima en AWS con **3 EC2** detrás de un **Application Load Balancer (ALB)**.
- Health check del ALB: `HTTP /` con `matcher = 200–399`
- Cada EC2 ejecuta un contenedor Docker (`errm/cheese:*`)
- Si falla el contenedor o Docker, *fallback* a **nginx** (sistema o `nginx:alpine`) para evitar 503
- Nombres personales: `dtapia`, `quesotapia-1..3`

> **Nunca subas credenciales al repo.** Exporta variables de entorno localmente.

## Requisitos
- Windows 10+
- Terraform ≥ 1.5
- AWS CLI (con credenciales válidas)
- Cuenta AWS (puede ser de laboratorio)

## Uso rápido (PowerShell)
```powershell
# 1) Credenciales (ejemplo; NO uses 'aws_access_key_id=' como prefijo)
$Env:AWS_ACCESS_KEY_ID     = "<TU_ACCESS_KEY_ID>"
$Env:AWS_SECRET_ACCESS_KEY = "<TU_SECRET_ACCESS_KEY>"
$Env:AWS_SESSION_TOKEN     = "<TU_SESSION_TOKEN>"   # si aplica
$Env:AWS_DEFAULT_REGION    = "us-east-1"
aws sts get-caller-identity

# 2) Init y apply
terraform init
terraform apply -auto-approve

# 3) Obtener DNS del ALB y abrir
$dns = terraform output -raw alb_dns_name
start "http://$dns"
```

## Ver salud de los targets
```powershell
$tg = aws elbv2 describe-target-groups --names dtapia-tg --query "TargetGroups[0].TargetGroupArn" --output text
aws elbv2 describe-target-health --target-group-arn $tg --query "TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State}" --output table
```

## Diagnóstico (opcional)
Abrir temporalmente HTTP directo a EC2 **sólo desde tu IP**:
```powershell
terraform apply -auto-approve -var "diag_open_http=true"
$ips = terraform output -json instance_public_ips | ConvertFrom-Json
foreach ($ip in $ips) { try { (Invoke-WebRequest -UseBasicParsing "http://$ip" -TimeoutSec 5).StatusCode } catch { $_.Exception.Message } }
# Cerrar:
terraform apply -auto-approve -var "diag_open_http=false"
```

## Personalización
- Crea `terraform.tfvars` a partir de `terraform.tfvars.example` para cambiar:
  - `project_name`, `node_name_prefix` (ej. `dtapia-queso`, `quesotapia`)
  - `docker_images`
  - `allow_ssh`, `ssh_cidr_override`
  - `diag_open_http`
- Para reducir costos, ajusta `count` (recurso `aws_instance.web`) y `aws_lb_target_group_attachment`.

## Destruir (evitar consumo de créditos)
```powershell
terraform destroy -auto-approve
```

**Autor:** Daniel Tapia
**Ramo:** INFRAESTRUCTURA COMO CODIGO I_001V
**Profe:**RODRIGO HORACIO AGUILAR GONZALEZ
