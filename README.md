# Route53 DNS Failover Lab (Terraform)

Terraform-реалізація механізму **DNS failover** за допомогою Amazon Route53.

- **PRIMARY** endpoint: internet-facing **ALB + 2 EC2 (nginx)** у `eu-north-1` (Multi-AZ)
- **SECONDARY** endpoint: **S3 static website** у `eu-west-1`
- **Моніторинг**: Route53 **HTTP health check** за DNS-ім'ям ALB (30s interval, 3 failures)

Коли ALB/EC2 стають недоступними (ALB віддає 5xx без healthy targets) → health check
падає → Route53 автоматично перемикає A-запис на резервний S3 website. Після
відновлення — failback на primary.

## Архітектура

```
                   http://hwbarabash1.pp.ua
                              │
                     Route53 hosted zone
                     FAILOVER routing policy
                     + HTTP health check
                     (ALB :80  /)
                     failure_threshold=3
                     request_interval=30
                              │
          ┌───────────────────┴───────────────────┐
          │ PRIMARY (health check OK)             │ SECONDARY (health check FAIL)
          ▼                                       ▼
  ALB (eu-north-1)                        S3 website (eu-west-1)
  ├── EC2 web-1 (eu-north-1a) nginx       index.html → «Fallback»
   └── EC2 web-2 (eu-north-1b) nginx       error.html → 404
```

> **Чому звичайні A-записи, а не alias?** Експериментально перевірено: alias-записи
> (з `evaluate_target_health` як `true`, так і `false`, з health check і без) **не
> перемикалися** навіть коли health check був 16/16 Failure 12+ хвилин, а alias-SECONDARY
> взагалі блокував failover (правило «both unhealthy → primary»). Звичайний non-alias
> A-запис на PRIMARY з `health_check_id` + non-alias SECONDARY без health check
> перемикається коректно: stop EC2 → ~90s → S3, start EC2 → ~90s → ALB.
> IP ALB та S3 endpoint резолвляться через провайдер `hashicorp/dns`
> (`data "dns_a_record_set"`), TTL записів — 60s. Для SECONDARY `records` зафіксовано
> через `ignore_changes`, бо публічний DNS S3 website endpoint віддає різний підмножину
> IP-пула щозапиту (perpetual diff).

## Активні ресурси (поточне розгортання)

| Ресурс | Значення |
|---|---|
| Домен / hosted zone | `hwbarabash1.pp.ua` |
| Hosted zone ID | `Z09009853QYQ3YI0A3JS4` |
| NS-сервери зони | `ns-131.awsdns-16.com`, `ns-551.awsdns-04.net`, `ns-1437.awsdns-51.org`, `ns-1564.awsdns-03.co.uk` |
| PRIMARY (ALB) | `http://dns-failover-alb-655472536.eu-north-1.elb.amazonaws.com` |
| SECONDARY (S3 website) | `http://hwbarabash1.pp.ua.s3-website-eu-west-1.amazonaws.com` |
| Route53 health check ID | `096755f8-691c-4c0f-b5d6-d850c0a049ba` |
| EC2 instance IDs | `i-0cf7255a64a2c3856` (web-1), `i-03a58aab033f48dc2` (web-2) |
| Target Group ARN | `arn:aws:elasticloadbalancing:eu-north-1:989346119941:targetgroup/dns-failover-tg/19369bdc70db9ad1` |
| S3 bucket | `hwbarabash1.pp.ua` |

> Після `terraform output` усі значення також доступні як outputs (див. таблицю нижче).

## Структура проєкту

```
.
├── modules/
│   ├── compute/          # ALB + Target Group + 2 EC2 + SG (primary)
│   ├── s3-website/       # S3 static website + index.html/error.html (secondary)
│   └── dns-failover/     # hosted zone + health check + failover records
├── environments/
│   └── dev/
│       ├── main.tf               # providers (eu-north-1 + eu-west-1) + модулі
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── terraform.tfvars.example
├── .gitignore
└── README.md
```

## Передумови

- Terraform >= 1.5
- AWS account + access key (права: EC2, ELB, S3, Route53)
- Windows: `nslookup`, `curl.exe`, PowerShell — усе вже в системі

## Розгортання

```powershell
cd environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars          # заповнити access_key / secret_key

terraform init
terraform validate
terraform apply -auto-approve     # ~3-4 хв

terraform output                  # всі адреси/ID
```

Ключові outputs:

| Output | Поточне значення |
|---|---|
| `app_url` | `http://hwbarabash1.pp.ua` |
| `primary_url` | `http://dns-failover-alb-655472536.eu-north-1.elb.amazonaws.com` |
| `secondary_url` | `http://hwbarabash1.pp.ua.s3-website-eu-west-1.amazonaws.com` |
| `instance_ids` | `["i-0cf7255a64a2c3856", "i-03a58aab033f48dc2"]` |
| `health_check_id` | `096755f8-691c-4c0f-b5d6-d850c0a049ba` |
| `hosted_zone_id` | `Z09009853QYQ3YI0A3JS4` |
| `name_servers` | `["ns-131.awsdns-16.com", "ns-1437.awsdns-51.org", "ns-1564.awsdns-03.co.uk", "ns-551.awsdns-04.net"]` |

> **Делегація домену**: `hwbarabash1.pp.ua` — реальний домен. Щоб `http://hwbarabash1.pp.ua`
> працював з інтернету, у панелі **pp.ua** для піддомену `hwbarabash1` створіть
> NS-записи (делегацію) на ці 4 сервери:
>
> ```
> hwbarabash1.pp.ua.   NS   ns-131.awsdns-16.com.
> hwbarabash1.pp.ua.   NS   ns-551.awsdns-04.net.
> hwbarabash1.pp.ua.   NS   ns-1437.awsdns-51.org.
> hwbarabash1.pp.ua.   NS   ns-1564.awsdns-03.co.uk.
> ```
>
> Після делегації (поширення DNS ~15-60 хв) сайт відкриється у браузері.
> До делегації перевіряйте за прямими URL та NS-запитами (див. нижче).

## Як перевірити (з реальними адресами)

> ⚠️ **Головна адреса сайту — `http://hwbarabash1.pp.ua`**, але вона працює
> **лише після делегації NS-записів у панелі pp.ua** (див. блок вище).
> Поки делегації немає, публічний DNS не знає про нашу Route53-зону і браузер/`curl`
> на `hwbarabash1.pp.ua` даватиме помилку — тому нижче прямі URL (ALB/S3),
> які працюють завжди, незалежно від делегації.
>
> Перевірити, чи делегація вже «прийшла»:
> ```powershell
> nslookup hwbarabash1.pp.ua   # без сервера — працює тільки після делегації
> ```

### 1. Сайт через домен (після делегації)

```powershell
curl.exe http://hwbarabash1.pp.ua
# Очікується: HTTP 200, HTML з бейджем «PRIMARY» (бо healthy targets є)

curl.exe -s http://hwbarabash1.pp.ua | Select-String "<h1>"
# → <h1>Primary site</h1>
```

### 2. PRIMARY напряму до ALB (eu-north-1) — працює завжди

```powershell
curl.exe http://dns-failover-alb-655472536.eu-north-1.elb.amazonaws.com
# Очікується: HTTP 200, HTML з бейджем «PRIMARY», instance: web-1 або web-2

curl.exe -s http://dns-failover-alb-655472536.eu-north-1.elb.amazonaws.com | Select-String "<h1>"
# → <h1>Primary site</h1>
```

### 3. SECONDARY напряму до S3 website (eu-west-1) — працює завжди

```powershell
curl.exe http://hwbarabash1.pp.ua.s3-website-eu-west-1.amazonaws.com
# Очікується: HTTP 200, HTML з бейджем «FALLBACK»
```

### 4. DNS через NS-сервери зони

До делегації в pp.ua запити робимо напряму до NS зони; після делегації
`nslookup hwbarabash1.pp.ua` працюватиме без вказання сервера:

```powershell
# Windows (nslookup) — має показати 2 IP ALB:
nslookup hwbarabash1.pp.ua ns-131.awsdns-16.com

# PowerShell — той самий запит:
Resolve-DnsName hwbarabash1.pp.ua -Type A -Server ns-131.awsdns-16.com

# Очікується (PRIMARY healthy): 2 IP ALB eu-north-1
# Очікується (після failover):  IP S3 website endpoint
```

Або через Python (потрібен `pip install dnspython`):

```powershell
python -c "import dns.resolver; r=dns.resolver.Resolver(configure=False); r.nameservers=['205.251.192.131']; print([rr.to_text() for rr in r.resolve('hwbarabash1.pp.ua','A')])"
# 205.251.192.131 = ns-131.awsdns-16.com
```

### 5. Статус Route53 health check

```powershell
# Поточний статус всіх чекерів (Success / Failure):
aws route53 get-health-check-status `
  --health-check-id 096755f8-691c-4c0f-b5d6-d850c0a049ba

# Остання причина невдачі:
aws route53 get-health-check-last-failure-reason `
  --health-check-id 096755f8-691c-4c0f-b5d6-d850c0a049ba
```

### 6. Target Group (ALB → EC2)

```powershell
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:eu-north-1:989346119941:targetgroup/dns-failover-tg/19369bdc70db9ad1
# Очікується: 2 таргети у стані "healthy"
```

### 7. Тест failover (симуляція збою)

Сценарій: зупиняємо обидва EC2 → ALB без healthy targets віддає 503 →
health check фіксує 3 невдачі (~90s) → DNS перемикається на S3.

```powershell
# Крок 1: зупинити обидва інстанси
aws ec2 stop-instances --instance-ids i-0cf7255a64a2c3856 i-03a58aab033f48dc2

# Крок 2: спостерігати (через ~1-3 хв статус стане Unhealthy)
aws route53 get-health-check-status --health-check-id 096755f8-691c-4c0f-b5d6-d850c0a049ba

# Крок 3: DNS тепер віддає S3 website endpoint:
nslookup hwbarabash1.pp.ua ns-131.awsdns-16.com
# → Addresses: IP від hwbarabash1.pp.ua.s3-website-eu-west-1.amazonaws.com

# Крок 4: відновити — і через ~1-2 хв failback на ALB (автоматично)
aws ec2 start-instances --instance-ids i-0cf7255a64a2c3856 i-03a58aab033f48dc2

# Перевірка failback:
nslookup hwbarabash1.pp.ua ns-131.awsdns-16.com   # знову 2 IP ALB
curl.exe http://dns-failover-alb-655472536.eu-north-1.elb.amazonaws.com   # «Primary site»
```

**Тривалість перемикання**: `failure_threshold(3) × request_interval(30s) ≈ 90s`
плюс TTL DNS-запису (60s). Реально — 1-3 хвилини.

### 8. Очищення

```powershell
terraform -chdir=environments\dev destroy -auto-approve
```

## Безпека

- `aws_access_key` / `aws_secret_key` — чутливі змінні; `terraform.tfvars` у `.gitignore`
- EC2: IMDSv2 обов'язковий, EBS encrypted
- EC2 приймають HTTP **лише** від SG ALB; публічний лише порт 80 ALB
- S3: публічне читання обмежене політикою `s3:GetObject` на `bucket/*` (потрібен для website endpoint)

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
| `nslookup` → `Non-existent domain` без сервера | Додайте NS-сервер зони: `nslookup <домен> ns-131.awsdns-16.com` |
| Health check Unhealthy, але ALB працює | Перевірте Target Group: `describe-target-health` — має бути `healthy` |
| DNS не перемикається | Дочекайтесь ~90s (3×30s) + TTL; перевірте `get-health-check-status` |
| `DomainNameDuplicate` при create | `domain_name` = ім'я S3-бакета, має бути унікальним у світі |
| `AccessDenied` на S3 website | Перевірте bucket policy та `public_access_block` |
| Alias до S3: помилка | Record name має збігатись з іменем бакета (бакет = `domain_name`) |
| Змінив регіон у tfvars | Спочатку `destroy` зі старим регіоном (`-var="aws_region_primary=..."`), потім apply з новим |
