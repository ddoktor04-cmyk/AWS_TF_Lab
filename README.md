# Route53 DNS Failover Lab (Terraform)

Terraform-реалізація механізму **DNS failover** за допомогою Amazon Route53.

- **PRIMARY** endpoint: EC2 **web-1** з Elastic IP у `eu-north-1`
- **SECONDARY** endpoint: EC2 **web-2** з Elastic IP у `eu-north-1`
- **Моніторинг**: Route53 **HTTP health check по IP** web-1 (30s interval, 3 failures)

Коли web-1 недоступний → health check падає → Route53 автоматично перемикає
A-запис на web-2. Після відновлення — failback на web-1.

## Архітектура

```
                  http://hwbarabash1.pp.ua
                             │
                    Route53 hosted zone
                    FAILOVER routing policy
                    + HTTP health check
                    (IP web-1 :80 /)
                    failure_threshold=3
                    request_interval=30
                             │
          ┌──────────────────┴──────────────────┐
          │ PRIMARY (HC OK)                     │ SECONDARY (HC FAIL)
          ▼                                     ▼
   EC2 web-1 + Elastic IP              EC2 web-2 + Elastic IP
   13.62.107.91 (eu-north-1a)          13.50.66.192 (eu-north-1b)
   бейдж «Primary», nginx              бейдж «Secondary», nginx
```

> **Чому звичайні A-записи, а не alias?** Експериментально перевірено: alias-записи
> (з `evaluate_target_health` як `true`, так і `false`, з health check і без) **не
> перемикалися** навіть коли health check був 16/16 Failure 12+ хвилин, а alias-SECONDARY
> взагалі блокував failover (правило «both unhealthy → primary»). Звичайний non-alias
> A-запис на PRIMARY з `health_check_id` + non-alias SECONDARY без health check
> перемикається коректно в обидва боки (~90s).
>
> **Чому EIP, а не статичний public IP чи alias?** Публічний IP інстансу без
> `associate_public_ip_address` змінюється при кожному stop/start (perpetual diff у
> плані, ризик заміни інстансу). Elastic IP зберігає адресу назавжди → IP для
> health check і A-запису стабільний.

## Активні ресурси (поточне розгортання)

| Ресурс | Значення |
|---|---|
| Домен / hosted zone | `hwbarabash1.pp.ua` |
| Hosted zone ID | `Z09009853QYQ3YI0A3JS4` |
| NS-сервери зони | `ns-131.awsdns-16.com`, `ns-551.awsdns-04.net`, `ns-1437.awsdns-51.org`, `ns-1564.awsdns-03.co.uk` |
| PRIMARY (web-1 EIP) | `http://13.62.107.91` |
| SECONDARY (web-2 EIP) | `http://13.50.66.192` |
| Route53 health check ID | `6e1a83b8-15e0-4508-9af9-903c05f86ff4` (ip-based, 13.62.107.91:80 `/`) |
| EC2 instance IDs | `i-0640f21c7cc5ec782` (web-1), `i-09c478b3049df5f19` (web-2) |

> Після `terraform output` усі значення також доступні як outputs (див. таблицю нижче).

## Структура проєкту

```
.
├── modules/
│   ├── compute/          # 2 EC2 + 2 Elastic IP + SG (primary endpoint)
│   └── dns-failover/     # hosted zone + health check + failover records
├── environments/
│   └── dev/
│       ├── main.tf               # provider (eu-north-1) + модулі
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── terraform.tfvars.example
├── .gitignore
└── README.md
```

## Передумови

- Terraform >= 1.5
- AWS account + access key (права: EC2, Route53)
- Windows: `nslookup`, `curl.exe`, PowerShell — усе вже в системі

## Розгортання

```powershell
cd environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars          # заповнити access_key / secret_key

terraform init
terraform validate
terraform apply -auto-approve     # ~2-3 хв

terraform output                  # всі адреси/ID
```

Ключові outputs:

| Output | Поточне значення |
|---|---|
| `app_url` | `http://hwbarabash1.pp.ua` |
| `primary_url` | `http://13.62.107.91` |
| `secondary_url` | `http://13.50.66.192` |
| `eip_public_ips` | `["13.62.107.91", "13.50.66.192"]` |
| `instance_ids` | `["i-0640f21c7cc5ec782", "i-09c478b3049df5f19"]` |
| `health_check_id` | `6e1a83b8-15e0-4508-9af9-903c05f86ff4` |
| `hosted_zone_id` | `Z09009853QYQ3YI0A3JS4` |
| `name_servers` | `["ns-131.awsdns-16.com", "ns-1437.awsdns-51.org", "ns-1564.awsdns-03.co.uk", "ns-551.awsdns-04.net"]` |

> **Делегація домену** виконана: `hwbarabash1.pp.ua` делеговано на ці 4 NS-сервери
> в панелі pp.ua, сайт відкривається з інтернету.
> Якщо працюєте на іншому домені — створіть NS-записи у своїй панелі:
>
> ```
> hwbarabash1.pp.ua.   NS   ns-131.awsdns-16.com.
> hwbarabash1.pp.ua.   NS   ns-551.awsdns-04.net.
> hwbarabash1.pp.ua.   NS   ns-1437.awsdns-51.org.
> hwbarabash1.pp.ua.   NS   ns-1564.awsdns-03.co.uk.
> ```

## Як перевірити (з реальними адресами)

### 1. Сайт через домен

```powershell
curl.exe http://hwbarabash1.pp.ua
# Очікується: HTTP 200, бейдж «Primary», instance: web-1

curl.exe -s http://hwbarabash1.pp.ua | Select-String "<h1>"
# → <h1>Primary site</h1>
```

### 2. PRIMARY напряму (EIP web-1) — працює завжди, коли web-1 running

```powershell
curl.exe http://13.62.107.91
# Очікується: HTTP 200, бейдж «Primary», instance: web-1
```

### 3. SECONDARY напряму (EIP web-2) — працює завжди, коли web-2 running

```powershell
curl.exe http://13.50.66.192
# Очікується: HTTP 200, бейдж «Secondary», instance: web-2
```

### 4. DNS через NS-сервери зони

```powershell
# Windows (nslookup) — має показати IP web-1:
nslookup hwbarabash1.pp.ua ns-131.awsdns-16.com

# PowerShell — той самий запит:
Resolve-DnsName hwbarabash1.pp.ua -Type A -Server ns-131.awsdns-16.com

# Очікується (PRIMARY healthy): 13.62.107.91 (IP web-1)
# Очікується (після failover):  13.50.66.192 (IP web-2)
```

Або через Python (потрібен `pip install dnspython`):

```powershell
python -c "import dns.resolver; r=dns.resolver.Resolver(configure=False); r.nameservers=['205.251.192.131']; print([rr.to_text() for rr in r.resolve('hwbarabash1.pp.ua','A')])"
# 205.251.192.131 = ns-131.awsdns-16.com
```

> ⚠️ Після перемикання локальний DNS-кеш ще ~TTL (60s) віддає стару адресу —
> перевіряйте через NS-запити напряму до серверів зони.

### 5. Статус Route53 health check

```powershell
# Поточний статус всіх чекерів (Success / Failure):
aws route53 get-health-check-status `
  --health-check-id 6e1a83b8-15e0-4508-9af9-903c05f86ff4

# Остання причина невдачі:
aws route53 get-health-check-last-failure-reason `
  --health-check-id 6e1a83b8-15e0-4508-9af9-903c05f86ff4
```

### 6. Тест failover (симуляція збою web-1)

Сценарій: зупиняємо web-1 → health check фіксує 3 невдачі (~90s) →
DNS перемикається на web-2.

```powershell
# Крок 1: зупинити web-1
aws ec2 stop-instances --instance-ids i-0640f21c7cc5ec782

# Крок 2: спостерігати (через ~1-3 хв статус стане Failure)
aws route53 get-health-check-status --health-check-id 6e1a83b8-15e0-4508-9af9-903c05f86ff4

# Крок 3: DNS тепер віддає IP web-2:
nslookup hwbarabash1.pp.ua ns-131.awsdns-16.com
# → 13.50.66.192

# Крок 4: відновити — і через ~1-2 хв failback на web-1 (автоматично)
aws ec2 start-instances --instance-ids i-0640f21c7cc5ec782

# Перевірка failback:
nslookup hwbarabash1.pp.ua ns-131.awsdns-16.com   # знову 13.62.107.91
curl.exe http://hwbarabash1.pp.ua                  # «Primary site»
```

**Перевірено експериментально** (2026-10):

| Сценарій | Результат |
|---|---|
| stop web-1 | ~90s → домен віддає web-2 (бейдж «Secondary») |
| start web-1 | ~90-120s → домен віддає web-1 (бейдж «Primary») |
| stop обох | HC=0 → домен віддає IP web-2, але web-2 мертвий → помилка з'єднання (SECONDARY без HC завжди «кандидат») |

**Тривалість перемикання**: `failure_threshold(3) × request_interval(30s) ≈ 90s`
плюс TTL DNS-запису (60s). Реально — 1-3 хвилини.

### 7. Очищення

```powershell
terraform -chdir=environments\dev destroy -auto-approve
```

## Безпека

- `aws_access_key` / `aws_secret_key` — чутливі змінні; `terraform.tfvars` у `.gitignore`
- EC2: IMDSv2 обов'язковий, EBS encrypted
- SG інстансів: HTTP (80) з `0.0.0.0/0` — **для демо**; у проді обмежте
  діапазонами Route53 health-checker та своїм IP

## Витрати (~$1.7-2/міс для demo)

| Сервіс | Ціна |
|---|---|
| 2 × t3.micro | ~$0.02/год разом |
| 2 × Elastic IP (прив'язаний) | $0 (за необґрунтований/EIP без прив'язки — $0.005/год) |
| Route53 zone | $0.50/міс |
| Route53 health check | $0.50/міс |

Не забудьте `terraform destroy` після лабораторної!

## Troubleshooting

| Симптом | Причина / рішення |
|---|---|
| `nslookup` → `Non-existent domain` без сервера | Додайте NS-сервер зони: `nslookup <домен> ns-131.awsdns-16.com` |
| Після failover сайт з кешу показує старий IP | Локальний DNS-кеш (TTL 60s) — перевіряйте через NS-запит напряму |
| DNS не перемикається | Дочекайтесь ~90s (3×30s) + TTL; перевірте `get-health-check-status` |
| Змінив текст сторінки в `user_data.sh.tftpl` | cloud-init виконує user_data **лише при першому запуску** — потрібна заміна інстанса (`user_data_replace_on_change = true`, `terraform apply -replace=...`) |
| Хочете змінити description SG | НЕ РОБІТЬ: AWS форсує заміну SG, а заміна SG з підключеними ENI = deadlock (старий SG не видаляється) |
| `Migrating between dns-based and ip-based health check types is not supported` | Route53 не мігрує HC між типами ін-плейс — замініть: `terraform apply -replace='module.dns_failover.aws_route53_health_check.primary'` |
| План хоче замінити інстанси після stop/start | Був `associate_public_ip_address` у конфігу (drift) — не використовуйте його разом з EIP |
| Змінив регіон у tfvars | Спочатку `destroy` зі старим регіоном (`-var="aws_region=..."`), потім apply з новим |
