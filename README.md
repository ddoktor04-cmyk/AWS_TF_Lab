# Route53 DNS Failover Lab (Terraform)

Terraform-реалізація механізму **DNS failover** за допомогою Amazon Route53.

- **PRIMARY** endpoint: internet-facing **ALB + 2 EC2 (nginx)** у `eu-central-1` (Multi-AZ)
- **SECONDARY** endpoint: **S3 static website** у `eu-west-1`
- **Моніторинг**: Route53 **HTTP health check** за DNS-ім'ям ALB (30s interval, 3 failures)

Коли ALB/EC2 стають недоступними (ALB віддає 5xx без healthy targets) → health check
падає → Route53 автоматично перемикає A-alias на резервний S3 website. Після
відновлення — failback на primary.

## Архітектура

```
                        http://failover-lab.test
                                   │
                          Route53 hosted zone
                          FAILOVER routing policy
                          + HTTP health check
                          (ALB :80  /)
                          failure_threshold=3
                          request_interval=30
                                   │
              ┌────────────────────┴────────────────────┐
              │ PRIMARY (якщо health check OK)          │ SECONDARY (якщо health check FAIL)
              ▼                                         ▼
     ALB (eu-central-1)                        S3 website (eu-west-1)
     ├── EC2 web-1 (AZ-a)  nginx               index.html  → «Fallback»
     └── EC2 web-2 (AZ-b)  nginx               error.html  → 404
```

## Структура проєкту

```
.
├── modules/
│   ├── compute/          # ALB + Target Group + 2 EC2 + SG (primary)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── user_data.sh.tftpl   # nginx + demo-сторінка PRIMARY
│   ├── s3-website/       # S3 static website (secondary/fallback)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── files/
│   │       ├── index.html        # резервна сторінка
│   │       └── error.html        # 404
│   └── dns-failover/     # hosted zone + health check + failover records
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   └── dev/
│       ├── main.tf               # providers + data + виклики модулів
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── terraform.tfvars.example
├── .gitignore
└── README.md
```

## Передумови

- Terraform >= 1.5
- AWS account + access key (права: EC2, ELB, S3, Route53, SSM)
- AWS CLI (для ручних перевірок/симуляції збою)
- Засіб DNS-запитів: `nslookup` (Windows), `dig` (Linux/WSL/Git Bash) або `Resolve-DnsName` (PowerShell)

## Налаштування та розгортання

```powershell
# 1. Скопіюйте шаблон конфігу та заповніть credentials
cd environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars

# 2. Ініціалізація та перевірка
terraform init
terraform validate
terraform plan -out=tfplan

# 3. Розгортання (~5-7 хв: ALB, 2 EC2, S3, Route53)
terraform apply tfplan

# 4. Результати
terraform output
```

Ключові outputs:

| Output | Що дає |
|---|---|
| `app_url` | URL через failover: `http://<domain_name>` |
| `primary_url` | Прямо до ALB (для порівняння) |
| `secondary_url` | Прямо до S3 website (fallback) |
| `instance_ids` | ID EC2 — для симуляції збою |
| `health_check_id` | ID health check — для моніторингу |
| `name_servers` | NS-записи зони (для делегації реального домену) |

> **Домен**: за замовчуванням `failover-lab.test` — це зарезервований TLD, який
> нікуди не делегується. Зона створюється в TF, і щоб «зайти» на сайт, робіть
> DNS-запити **напряму до NS-серверів зони** (див. нижче «Перевірка DNS»).
> Якщо хочете реальний домен — змініть `domain_name` у `terraform.tfvars`, після
> apply делегуйте домен на `name_servers` з output.

## Як перевіряти та тестувати

### 1. Перевірка первинного сайту

```powershell
# Отримайте NS-записи зони
terraform -chdir=environments\dev output -raw name_servers

# DNS-запит напряму до NS-серверів зони (потрібен dig/Git Bash/WSL)
dig @ns-XXXX.awsdns-XX.com failover-lab.test A +short

# Очікується: DNS-ім'я ALB (напр. dns-failover-alb-....eu-central-1.elb.amazonaws.com)

# HTTP-запит напряму до домену (через NS) — Windows PowerShell:
Resolve-DnsName failover-lab.test -Server ns-XXXX.awsdns-XX.com

# Сайт напряму через ALB (без делегації):
curl.exe (terraform -chdir=environments\dev output -raw primary_url)
# → HTML з бейджем «PRIMARY», instance: web-1 / web-2

# Резервний сайт напряму:
curl.exe (terraform -chdir=environments\dev output -raw secondary_url)
# → HTML з бейджем «FALLBACK»
```

Альтернатива без делегації — тимчасово додати в `C:\Windows\System32\drivers\etc\hosts`:

```
<ALB_DNS_IP?>  ...  # не працює з ALB (динамічні IP)
```

Найпростіший спосіб без хаків — перевіряти `primary_url`/`secondary_url` напряму,
а перемикання failover спостерігати через DNS-запити до NS та статус health check.

### 2. Статус Route53 health check

```powershell
$hc = terraform -chdir=environments\dev output -raw health_check_id

# Поточний статус (Healthy / Unhealthy)
aws route53 get-health-check-status --health-check-id $hc

# Історія змін статусу
aws route53 get-health-check-last-failure-reason --health-check-id $hc
```

### 3. Моніторинг Target Group (ALB)

```powershell
$tg = terraform -chdir=environments\dev output -raw alb_arn  # або шукати TG через LB

aws elbv2 describe-target-health `
  --target-group-arn (aws elbv2 describe-target-groups `
    --names dns-failover-tg `
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

### 4. Тест failover (симуляція збою primary)

Сценарій: зупиняємо обидва EC2 → ALB втрачає healthy targets → віддає 503 →
Route53 health check фіксує 3 невдачі поспіль (~90s) → DNS перемикається на S3.

```powershell
# Крок 1: зупинити обидва інстанси
$ids = terraform -chdir=environments\dev output -json instance_ids | ConvertFrom-Json
aws ec2 stop-instances --instance-ids ($ids -split '"' | Where-Object { $_ -match '^i-' })

# Крок 2: спостерігати (через ~1-3 хв статус стане Unhealthy)
aws route53 get-health-check-status --health-check-id $hc

# Крок 3: перевірити, що DNS тепер віддає S3 website endpoint
dig @ns-XXXX.awsdns-XX.com failover-lab.test A +short
# → failover-lab.test.s3-website-eu-west-1.amazonaws.com

# Крок 4: відкрити резервну сторінку
curl.exe (terraform -chdir=environments\dev output -raw secondary_url)
```

Після ~1-2 хв після старту інстансів health check знову стає Healthy →
**failback** на ALB (відбувається автоматично, без дій).

**Тривалість перемикання**: `failure_threshold(3) × request_interval(30s) ≈ 90s`
плюс TTL DNS-кешу клієнтів (alias-записи Route53 ≈ 60s). Реально — 1-3 хвилини.

### 5. Швидке «мертве» тестування без зупинки EC2

Можна тимчасово видалити SG-правило або зупинити nginx на обох інстансах:

```powershell
# Зупинити nginx на всіх web-інстансах (через SSM або SSH):
aws ssm send-command --document-name "AWS-RunShellScript" `
  --targets "Key=tag:Name,Values=dns-failover-web-1,dns-failover-web-2" `
  --parameters '{"commands":["systemctl stop nginx"]}'
```

### 6. Очищення

```powershell
terraform -chdir=environments\dev destroy -auto-approve
```

## Безпека

- `aws_access_key` / `aws_secret_key` — чутливі змінні; `terraform.tfvars` у `.gitignore`
- EC2: IMDSv2 обов'язковий (`http_tokens = required`), EBS encrypted
- EC2 приймають HTTP **лише** від SG ALB; публічний доступ лише на порт 80 ALB
- S3: публічний доступ обмежений політикою `s3:GetObject` на `bucket/*` (потрібен для website endpoint)

## Витрати (~$2-3/міс для demo)

| Сервіс | Ціна |
|---|---|
| ALB | ~$0.0225/год + LCU |
| 2 × t3.micro | ~$0.02/год разом |
| S3 website | $0 (зберігання/GET за тарифами) |
| Route53 zone | $0.50/міс |
| Route53 health check | $0.50/міс |

Не забудьте `terraform destroy` після лабораторної!

## Troubleshooting

| Симптом | Причина / рішення |
|---|---|
| `AccessDenied` на S3 website | Перевірте bucket policy та `aws_s3_bucket_public_access_block` |
| Health check Unhealthy, але сайт працює | Route53 health check іде з **публічних** IP AWS — перевірте, що ALB internet-facing та SG дозволяє 80 ззовні |
| DNS не перемикається | Дочекайтесь ~90s (3×30s); перевірте `get-health-check-status` |
| `DomainNameDuplicate` при create | `domain_name` має бути унікальним (S3 бакети глобальні) — змініть у tfvars |
| Alias до S3: помилка | Record name має збігатись з іменем бакета — бакет створюється з `domain_name` саме для цього |
