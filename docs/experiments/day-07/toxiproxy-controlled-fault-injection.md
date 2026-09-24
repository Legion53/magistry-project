# День 7 — Toxiproxy і контрольовані мережеві відмови

## Мета і межі експерименту

Мета — відтворювано перевірити стійкість `order-service` до керованих
мережевих несправностей між ним та `inventory-service`. Замість зупинки
процесу `inventory-service` усі впливи вносяться в TCP-потік Toxiproxy.

```text
order-service (localhost:8080)
        |
        | INVENTORY_BASE_URL=http://localhost:8666
        v
Toxiproxy TCP proxy (localhost:8666; API localhost:8474)
        |
        v
inventory-service (host.docker.internal:8081)
```

`inventory-service` та `order-service` залишаються локальними процесами.
Контейнер Toxiproxy працює в Docker Desktop; `host.docker.internal` є
стабільним маршрутом контейнера до локального хоста. Жодна Java-конфігурація
Day 6 не змінюється: проксі вмикається лише змінною оточення під час запуску
Day 7.

Використано образ `ghcr.io/shopify/toxiproxy:2.12.0`. Toxiproxy має HTTP API
на порту 8474, а TCP-proxy налаштовується через `POST /populate`; toxic
`latency` задається в мілісекундах, `reset_peer` моделює TCP RST, а `enabled:
false` вимикає конкретний проксі. Джерело: [офіційна документація
Toxiproxy](https://github.com/Shopify/toxiproxy).

## Реалізовані відмови

| Сценарій | Механізм Toxiproxy | Очікуване спостереження |
|---|---|---|
| `delay-100` | downstream `latency=100 ms`, `jitter=0` | Запити `ACCEPTED`, затримка приблизно на 100 ms вища за baseline. |
| `delay-500` | downstream `latency=500 ms`, `jitter=0` | Запити `ACCEPTED`, затримка приблизно на 500 ms вища за baseline. |
| `delay-1000` | downstream `latency=1000 ms`, `jitter=0` | Запити `ACCEPTED`; значення нижче наявного `read-timeout=2 s`. |
| `reset-peer` | downstream `reset_peer`, `timeout=0` | TCP connection reset; `order-service` повертає `503 TEMPORARILY_UNAVAILABLE`, Retry виконує повторні спроби, Circuit Breaker відкривається. |
| `downstream-unavailable` | proxy `enabled=false` | З'єднання до проксі недоступне без зупинки `inventory-service`; очікується той самий контрольований шлях `503 → OPEN`. |

Скрипт видаляє **лише** toxic-и з префіксом `day7-`. Він не викликає
глобальний `POST /reset` і не стирає сторонні налаштування Toxiproxy.

## Формальне визначення відновлення і MTTR

Один вимірювальний інтервал — один POST `/orders` з тілом
`{"productId":1,"quantity":2}`. Після завершення запиту скрипт чекає одну
секунду перед наступним інтервалом (крім останнього в серії). Для інтервалу
`i` фіксуються `t_i`, HTTP-статус, доменний статус замовлення і наскрізна
затримка `L_i` у мілісекундах.

1. Перед ін'єкцією виконується 10 успішних baseline-вимірів через увімкнений
   проксі без toxic-ів. Обчислюється `P95_baseline`.
2. Поріг стабільної затримки визначається до експерименту:

   ```text
   L_stable = max(250 ms, ceil(2 × P95_baseline))
   ```

3. Інтервал є **здоровим**, якщо одночасно: HTTP `200`,
   `order_status=ACCEPTED`, `CircuitBreaker= CLOSED` і `L_i ≤ L_stable`.
   Для ковзного вікна з 5 інтервалів error rate тоді дорівнює `0%`.
4. `T_failure_injection` — часовий штамп одразу після успішного підтвердження
   API Toxiproxy, яке застосувало `reset-peer` або вимкнуло проксі.
5. `T_stable_after_recovery` — часовий штамп після п'ятого послідовного
   здорового інтервалу після відновлення мережі.

Отже, для кожного сценарію відмови:

```text
MTTR = T(stable_after_recovery) - T(failure_injection)
```

Це визначення включає час, протягом якого Circuit Breaker перебуває в `OPEN`
(у поточній Day 6 конфігурації — 30 s), перехід `OPEN → HALF_OPEN`, дві
успішні проби для `HALF_OPEN → CLOSED` і п'ять стабільних контрольних
вимірів. Значення `mttr_ms` не вгадується — його записує скрипт із UTC
timestamp-ів.

## Відтворюваний запуск

Перед запуском потрібні Docker Desktop, Java/Maven та PostgreSQL-контейнер.
Виконати кожен із перших трьох блоків у окремому PowerShell-вікні.

### 1. Запустити залежності та inventory-service

```powershell
Set-Location F:\magistry-project
docker compose --env-file .\infrastructure\.env -f .\infrastructure\compose.yaml up -d postgres

$env:DB_USERNAME = 'thesis'
$env:DB_PASSWORD = (Get-Content .\infrastructure\.env | Where-Object { $_ -match '^POSTGRES_PASSWORD=' } | ForEach-Object { $_ -replace '^POSTGRES_PASSWORD=', '' })
Set-Location .\inventory-service
.\mvnw.cmd spring-boot:run
```

Перевірка в іншому вікні:

```powershell
Invoke-RestMethod http://localhost:8081/actuator/health
```

Очікується `status = UP`.

### 2. Створити проксі та запустити order-service через нього

```powershell
Set-Location F:\magistry-project
.\scripts\day-07\Initialize-Toxiproxy.ps1 -StartContainer
```

Вивід має містити `proxy_name: inventory-service`, `listen: 0.0.0.0:8666`,
`upstream: host.docker.internal:8081` і `enabled: true`.

Після цього, в окремому PowerShell-вікні:

```powershell
Set-Location F:\magistry-project\order-service
$env:INVENTORY_BASE_URL = 'http://localhost:8666'
$env:SPRING_PROFILES_ACTIVE = 'phase6'
.\mvnw.cmd spring-boot:run
```

`phase6` є обов'язковим, бо саме він експонує endpoints Resilience4j, які
скрипт використовує для перевірки `OPEN`, `HALF_OPEN` і `CLOSED`.

### 3. Перевірити передумови

```powershell
Invoke-RestMethod http://localhost:8080/actuator/health
Invoke-RestMethod http://localhost:8080/actuator/circuitbreakers
Invoke-RestMethod http://localhost:8474/proxies/inventory-service
```

Обидва health-відповіді мають бути `UP`, а
`circuitBreakers.inventoryService.state` — `CLOSED`. Якщо стан інший,
перезапустити `order-service`: скрипт навмисно не скидає Circuit Breaker
прихованим адміністративним викликом.

### 4. Запустити весь експеримент

```powershell
Set-Location F:\magistry-project
.\scripts\day-07\Invoke-RecoveryExperiment.ps1
```

Скрипт виконує послідовність:

```text
T0  normal baseline (10 samples)
T1  +100 ms, +500 ms, +1000 ms (по 5 samples)
T2  reset-peer (100% transport failures) → Circuit Breaker OPEN
T3  restore network
T4  after 32 s: first successful HALF_OPEN probe
T5  second successful probe → CLOSED
T6  5 consecutive stable samples → MTTR(reset-peer)
T7  downstream-unavailable → Circuit Breaker OPEN
T8  restore network → HALF_OPEN → CLOSED → 5 stable samples → MTTR(downstream-unavailable)
```

32 секунди — це 30 s `waitDurationInOpenState` з Day 6 плюс 2 s запасу для
того, щоб пробний запит гарантовано був дозволений. Обидва recovery-цикли
залишають proxy у стані `normal` навіть якщо скрипт завершується помилкою.

## Артефакти одного запуску

Скрипт генерує новий, унікальний `run-YYYYMMDDTHHMMSSZ`; повторний запис у
наявний каталог заборонений.

```text
results/day-07/
├── raw/<run>/requests.csv              # UTC timestamp, latency, HTTP/domain status кожного запиту
├── metrics/<run>/phase-summary.csv     # p50/p95/max latency та error rate кожної фази
├── metrics/<run>/recovery-summary.json # формула, поріг stable і MTTR обох сценаріїв
├── events/<run>/timeline.csv           # T0…Tstable маркери
├── events/<run>/*.json                 # Actuator Retry/CB events і Toxiproxy snapshot-и
├── charts/<run>/recovery-timeline.svg  # готовий рисунок для дисертації
└── jfr/                                # опційні JFR записи, якщо вони потрібні для аналізу JVM
```

`recovery-timeline.svg` показує latency по часу: зелені точки — успішні
запити, сині — delay-фази, червоні — помилки; вертикальні маркери показують
ін'єкцію, відновлення мережі, `HALF_OPEN`, `CLOSED` та досягнення stable.
Він будується з тих самих CSV, що використовуються для числових висновків.

## Окрема перевірка кожного toxic-а

Для короткої діагностики без повного прогону:

```powershell
Set-Location F:\magistry-project
.\scripts\day-07\Set-ToxiproxyFault.ps1 -Scenario delay-100
.\scripts\day-07\Set-ToxiproxyFault.ps1 -Scenario delay-500
.\scripts\day-07\Set-ToxiproxyFault.ps1 -Scenario delay-1000
.\scripts\day-07\Set-ToxiproxyFault.ps1 -Scenario reset-peer
.\scripts\day-07\Set-ToxiproxyFault.ps1 -Scenario downstream-unavailable
.\scripts\day-07\Set-ToxiproxyFault.ps1 -Scenario normal
```

Для `reset-peer` та `downstream-unavailable` не треба надсилати ручні запити
до повного recovery-експерименту: вони змінюють стан Circuit Breaker. Повний
скрипт сам створює чисту послідовність і перевіряє усі переходи.

## Перевірка регресії Day 6

Перед комітом і після завершення Day 7 на звичайній робочій машині:

```powershell
Set-Location F:\magistry-project\order-service
.\mvnw.cmd test
```

Очікування: усі тести Day 6 залишаються успішними. Day 7 не змінює
`OrderService`, Retry, Circuit Breaker або їх unit-тести; він змінює лише
runtime route через `INVENTORY_BASE_URL`.

## Висновок для тексту дисертації

> Контрольовані мережеві відмови між сервісами моделювалися засобом Toxiproxy
> без зупинки downstream-сервісу. Затримка, TCP reset та недоступність проксі
> задавалися через API й фіксувалися разом із наскрізною затримкою, HTTP і
> доменним статусом, подіями Resilience4j та станом Circuit Breaker. Момент
> стабільного відновлення визначався як п'ять послідовних успішних інтервалів
> з нульовим error rate, `CircuitBreaker=CLOSED` і затримкою не вище
> попередньо визначеного порога. Це дозволило обчислювати MTTR не
> суб'єктивно, а як різницю між timestamp-ами ін'єкції відмови та досягнення
> формального критерію стабільності.
