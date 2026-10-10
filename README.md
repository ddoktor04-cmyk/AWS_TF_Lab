# Route53 DNS Failover Lab (Terraform)

Terraform-реалізація механізму **DNS failover** за допомогою Amazon Route53.

- **PRIMARY** endpoint: internet-facing **ALB + 2 EC2 (nginx)** у `eu-north-1` (Multi-AZ)
- **SECONDARY** endpoint: **S3 static website** у `eu-west-1`
- **Моніторинг**: Route53 **HTTP health check** за DNS-ім'ям ALB (30s interval, 3 failures)

Коли ALB/EC2 стають недоступними (ALB віддає 5xx без healthy targets) → health check
падає → Route53 автоматично перемикає A-alias на резервний S3 website. Після
відновлення — failback на primary.

## Архітектура

```
                   http://cmd521-failover-lab.test
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

## Активні ресурси (поточне розгортання)

| Ресурс | Значення |
|---|---|
| Домен / hosted zone | `cmd521-failover-lab.test` |
| Hosted zone ID | `Z08732093J6OIM6EXGVDJ` |
| NS-сервери зони | `ns-412.awsdns-51.com`, `ns-689.awsdns-22.net`, `ns-1353.awsdns-41.org`, `ns-1901.awsdns-45.co.uk` |
| PRIMARY (ALB) | `http://dns-failover-alb-671914199.eu-north-1.elb.amazonaws.com` |
| SECONDARY (S3 website) | `http://cmd521-failover-lab.test.s3-website-eu-west-1.amazonaws.com` |
| Route53 health check ID | `baf98e4e-2fbc-4b22-a92d-c554c94759ef` |
| EC2 instance IDs | `i-0ca19cf2367d1cc2a` (web-1), `i-0a6d8ed438f5c419a` (web-2) |
| Target Group ARN | `arn:aws:elasticloadbalancing:eu-north-1:989346119941:targetgroup/dns-failover-tg/7ccfc69ab711aca9` |
| S3 bucket | `cmd521-failover-lab.test` |

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
| `app_url` | `http://cmd521-failover-lab.test` |
| `primary_url` | `http://dns-failover-alb-671914199.eu-north-1.elb.amazonaws.com` |
| `secondary_url` | `http://cmd521-failover-lab.test.s3-website-eu-west-1.amazonaws.com` |
| `instance_ids` | `["i-0ca19cf2367d1cc2a", "i-0a6d8ed438f5c419a"]` |
| `health_check_id` | `baf98e4e-2fbc-4b22-a92d-c554c94759ef` |
| `hosted_zone_id` | `Z08732093J6OIM6EXGVDJ` |
| `name_servers` | `["ns-1353.awsdns-41.org", "ns-1901.awsdns-45.co.uk", "ns-412.awsdns-51.com", "ns-689.awsdns-22.net"]` |

> **Домен `.test`** — зарезервований TLD, не делегується в інтернет. Тому браузер
> по `http://cmd521-failover-lab.test` не відкриється без hosts/делегації —
> сайт перевіряємо за прямими URL (ALB/S3), а перемикання DNS — запитами
> напряму до NS-серверів зони (див. нижче). Для реального домену змініть
> `domain_name` у `terraform.tfvars` і делегуйте домен на `name_servers`.

## Як перевірити (з реальними адресами)

### 1. PRIMARY сайт (ALB, eu-north-1)

```powershell
curl.exe http://dns-failover-alb-671914199.eu-north-1.elb.amazonaws.com
# Очікується: HTTP 200, HTML з бейджем «PRIMARY», instance: web-1 або web-2

curl.exe -s http://dns-failover-alb-671914199.eu-north-1.elb.amazonaws.com | Select-String "<h1>"
# → <h1>Primary site</h1>
```

### 2. SECONDARY сайт (S3 website, eu-west-1)

```powershell
curl.exe http://cmd521-failover-lab.test.s3-website-eu-west-1.amazonaws.com
# Очікується: HTTP 200, HTML з бейджем «FALLBACK»
```

### 3. DNS через NS-сервери зони

Домен не делегований, тому запити робимо напряму до NS зони:

```powershell
# Windows (nslookup) — має показати 2 IP ALB:
nslookup cmd521-failover-lab.test ns-412.awsdns-51.com

# PowerShell — той самий запит:
Resolve-DnsName cmd521-failover-lab.test -Type A -Server ns-412.awsdns-51.com

# Очікується (PRIMARY healthy): 2 IP ALB eu-north-1
# Очікується (після failover):  IP S3 website endpoint
```

Або через Python (потрібен `pip install dnspython`):

```powershell
python -c "import dns.resolver; r=dns.resolver.Resolver(configure=False); r.nameservers=['205.251.193.156']; print([rr.to_text() for rr in r.resolve('cmd521-failover-lab.test','A')])"
# 205.251.193.156 = ns-412.awsdns-51.com
```

### 4. Статус Route53 health check

```powershell
# Поточний статус всіх чекерів (Success / Failure):
aws route53 get-health-check-status `
  --health-check-id baf98e4e-2fbc-4b22-a92d-c554c94759ef

# Остання причина невдачі:
aws route53 get-health-check-last-failure-reason `
  --health-check-id baf98e4e-2fbc-4b22-a92d-c554c94759ef
```

### 5. Target Group (ALB → EC2)

```powershell
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:eu-north-1:989346119941:targetgroup/dns-failover-tg/7ccfc69ab711aca9
# Очікується: 2 таргети у стані "healthy"
```

### 6. Тест failover (симуляція збою)

Сценарій: зупиняємо обидва EC2 → ALB без healthy targets віддає 503 →
health check фіксує 3 невдачі (~90s) → DNS перемикається на S3.

```powershell
# Крок 1: зупинити обидва інстанси
aws ec2 stop-instances --instance-ids i-0ca19cf2367d1cc2a i-0a6d8ed438f5c419a

# Крок 2: спостерігати (через ~1-3 хв статус стане Unhealthy)
aws route53 get-health-check-status --health-check-id baf98e4e-2fbc-4b22-a92d-c554c94759ef

# Крок 3: DNS тепер віддає S3 website endpoint:
nslookup cmd521-failover-lab.test ns-412.awsdns-51.com
# → Addresses: IP від cmd521-failover-lab.test.s3-website-eu-west-1.amazonaws.com

# Крок 4: відновити — і через ~1-2 хв failback на ALB (автоматично)
aws ec2 start-instances --instance-ids i-0ca19cf2367d1cc2a i-0a6d8ed438f5c419a

# Перевірка failback:
nslookup cmd521-failover-lab.test ns-412.awsdns-51.com   # знову 2 IP ALB
curl.exe http://dns-failover-alb-671914199.eu-north-1.elb.amazonaws.com   # «Primary site»
```

**Тривалість перемикання**: `failure_threshold(3) × request_interval(30s) ≈ 90s`
плюс TTL DNS-кешу (alias ≈ 60s). Реально — 1-3 хвилини.

### 7. Очищення

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
| `nslookup` → `Non-existent domain` без сервера | Додайте NS-сервер зони: `nslookup <домен> ns-412.awsdns-51.com` |
| Health check Unhealthy, але ALB працює | Перевірте Target Group: `describe-target-health` — має бути `healthy` |
| DNS не перемикається | Дочекайтесь ~90s (3×30s) + TTL; перевірте `get-health-check-status` |
| `DomainNameDuplicate` при create | `domain_name` = ім'я S3-бакета, має бути унікальним у світі |
| `AccessDenied` на S3 website | Перевірте bucket policy та `public_access_block` |
| Alias до S3: помилка | Record name має збігатись з іменем бакета (бакет = `domain_name`) |
| Змінив регіон у tfvars | Спочатку `destroy` зі старим регіоном (`-var="aws_region_primary=..."`), потім apply з новим |
