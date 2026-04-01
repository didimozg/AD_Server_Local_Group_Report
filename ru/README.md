# AD Server Local Group Report

PowerShell-инструмент для инвентаризации серверов Windows Server и сбора состава локальных групп на них.

Предпочтительная публичная точка входа:

- [Start-ServerLocalGroupReport.ps1](./Start-ServerLocalGroupReport.ps1)
- legacy-совместимый wrapper: [get_windows_server_local_group_report.ps1](./get_windows_server_local_group_report.ps1)

Проект умеет:

- получать список серверов из Active Directory или из TXT/CSV-файла
- подключаться к каждому серверу по CIM через `DCOM` или `WSMan`
- выгружать прямых участников локальных групп, включая доменных пользователей и доменные группы
- искать конкретного пользователя, группу, SID или wildcard-шаблон и показывать, на каком сервере и в какой локальной группе он найден
- формировать журнал выполнения, статусы обработки, детальные CSV-отчёты по участникам и сводные отчёты

Скрипт рассчитан на смешанные среды Windows Server, включая старые версии, где `DCOM` часто остаётся самым практичным транспортом.

## Лицензия

Проект распространяется по лицензии MIT.

Полный текст лицензии: [LICENSE](./LICENSE).

## Зачем нужен проект

Во многих Windows-инфраструктурах локальные группы на серверах содержат смесь из:

- локальных учётных записей
- доменных пользователей
- доменных групп
- встроенных и well-known сервисных идентификаторов

Проверять такой состав вручную, сервер за сервером, долго и неудобно. Этот проект автоматизирует аудит и формирует повторяемые CSV-результаты, которые удобно использовать для:

- проверок безопасности
- аудита прав доступа
- подготовки миграций
- проверок перед выводом серверов из эксплуатации
- расследования неожиданного локального admin или RDP доступа

## Что делает инструмент

Инструмент поддерживает два режима источника и два режима работы.

Режимы источника:

- `AD`: искать серверы Windows Server в Active Directory
- `File`: читать список серверов из TXT или CSV

Режимы работы:

- `AllMembers`: выгрузить прямых участников локальных групп
- `FindIdentity`: найти одну учётную запись или группу на всех просканированных серверах

В интерактивном режиме скрипт последовательно спрашивает:

- откуда брать список серверов
- что именно делать
- использовать ли текущую Windows-сессию или запросить другие учётные данные

В неинтерактивном режиме скрипт может определить режим по активному набору параметров или по переданным аргументам.

## Ключевые возможности

- wrapper-скрипт для интерактивного и неинтерактивного запуска
- модульная реализация с разделением на `Public` и `Private`
- поддержка PowerShell `5.1` и PowerShell `7+`
- параллельное сканирование серверов в PowerShell `7+`
- выбор транспорта `DCOM` / `WSMan` с автоматическим fallback
- настраиваемая стратегия reachability: `Probe`, `Direct`, `PingOnly`, `None`
- retry для временных `CIM/WMI`-ошибок
- fallback через `WinNT`, если `CIM` возвращает неполный состав группы
- необязательная фильтрация устаревших объектов AD по `pwdLastSet` и `lastLogonTimestamp`
- необязательное включение пустых локальных групп
- экспорт исходного списка серверов в `CSV` и `TXT`
- файл журнала выполнения с timestamp
- компактная поставляемая структура без обязательного dev/test-слоя

## Поддерживаемая среда

Администраторская станция:

- Windows PowerShell `5.1+`
- PowerShell `7+` рекомендуется для параллельного сканирования

Удалённые серверы:

- Windows Server `2008` и выше, включая современные версии вроде `2022/2025`
- версия удалённого PowerShell на целевом сервере не является главным ограничением
- для штатного сбора данных скрипт не требует запускать удалённый PowerShell-код на самих серверах

Зависимости по режимам:

- режим `AD` требует модуль `ActiveDirectory` и доступ к контроллеру домена
- режим `File` не требует модуль `ActiveDirectory`
- `PSScriptAnalyzer` и `Pester 5` могут использоваться как необязательные dev-инструменты, но не требуются для рабочего запуска инструмента

## Как это работает

Общий поток выполнения:

1. Определить режим работы и учётные данные.
2. Получить исходный список серверов из AD или файла.
3. Нормализовать и экспортировать исходный список.
4. Для каждого сервера определить, стоит ли выполнять попытки `CIM`-подключения.
5. Сначала попробовать предпочтительный транспорт, затем резервный, если нужно.
6. Получить список локальных групп.
7. Получить прямых участников каждой локальной группы.
8. При необходимости объединить `CIM`-результаты с fallback через `WinNT`.
9. Экспортировать статусы, детальные membership-строки, сводки и результаты поиска.

Реализация находится в:

- [Start-ServerLocalGroupReport.ps1](./Start-ServerLocalGroupReport.ps1): основная CLI-точка входа со справкой и parameter sets
- [get_windows_server_local_group_report.ps1](./get_windows_server_local_group_report.ps1): legacy-совместимый wrapper
- [AD_Server_Local_Group_Report.psm1](./AD_Server_Local_Group_Report.psm1): загрузчик модуля
- [Public/Commands.ps1](./Public/Commands.ps1): публичные точки входа
- [Private/](./Private): конфигурация, подключение, membership-логика, отчёты, runtime, контракты
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md): внутренние архитектурные заметки

## Модель аутентификации

Инструмент поддерживает три практических варианта аутентификации:

1. Текущая Windows-сессия
2. Раздельные `ADCredential` и `ServerCredential`
3. Один общий `PSCredential` через `-Credential` / `-SharedCredential`

В интерактивном режиме сначала предлагается выбор:

- использовать текущую Windows-сессию
- один раз запросить учётные данные другого пользователя и использовать их и для AD, и для серверов

Поведение по умолчанию в неинтерактивном режиме:

- если явные креды не переданы, используется текущая Windows-сессия

## Источники входных данных

### Active Directory

В режиме `AD` проект запрашивает объекты компьютеров, у которых `OperatingSystem` содержит `Windows Server`.

Необязательные фильтры AD:

- `-DomainServer`
- `-SearchBase`
- `-MaxComputerPasswordAgeDays`
- `-MaxLastLogonAgeDays`
- `-IncludeDisabledComputers`

### Файловый режим

Поддерживаемые форматы:

- `TXT`: один сервер в строке
- `CSV`: одно из полей содержит имя сервера

Имена столбцов, которые определяются автоматически:

- `ConnectionName`
- `Server`
- `ComputerName`
- `Name`
- `DnsHostName`
- `Host`
- `Hostname`

Если у вас нестандартное имя столбца, используйте `-CsvServerColumn`.

Примеры файлов в репозитории:

- [samples/servers_example.txt](./samples/servers_example.txt)
- [samples/servers_example.csv](./samples/servers_example.csv)

## Логика сбора

### Reachability

Перед `CIM`-сбором инструмент может дополнительно проверить доступность сервера:

- `Probe`: ICMP и релевантные порты
- `Direct`: пропустить pre-check и сразу идти в `CIM`
- `PingOnly`: только ICMP
- `None`: полностью отключить pre-check

Это управляется параметром `-ReachabilityMode`.

### Транспорт

Предпочтительный транспорт задаётся через `-CimProtocol`:

- `Dcom`
- `Wsman`

Если основной транспорт не сработал, инструмент автоматически пробует альтернативный. В итоговом отчёте сохраняются:

- запрошенный протокол
- фактически использованный протокол
- факт использования fallback

### Получение состава групп

Основной источник данных:

- `CIM / WMI`-классы вроде `Win32_Group` и `Win32_GroupUser`

Резервный путь:

- перечисление через `WinNT / ADSI`

Fallback нужен потому, что в некоторых средах `CIM` возвращает неполный список участников. Проект объединяет оба результата и удаляет дубликаты.

## Выходные файлы

По умолчанию результаты складываются в каталог `output/`, но его можно переопределить через `-OutputDirectory`.

Файлы, которые создаются всегда:

- `server_source_list.csv`
- `server_source_list.txt`
- `server_membership_status.csv`
- `execution_YYYYMMDD_HHMMSS.log`

Файлы режима `AllMembers`:

- `server_local_group_members.csv`
- `server_local_group_summary.csv`

Файлы режима `FindIdentity`:

- `identity_search_matches.csv`

### `server_source_list.csv`

Нормализованный исходный список серверов. В зависимости от режима может содержать:

- `ConnectionName`
- `DnsHostName`
- `OperatingSystem`
- `Enabled`
- `PasswordLastSetUtc`
- `LastLogonTimestampUtc`

### `server_membership_status.csv`

Одна строка на сервер. Полезные поля:

- `QueryStatus`: `Success`, `Offline`, `Error`
- `RequestedCimProtocol`
- `EffectiveCimProtocol`
- `AttemptedCimProtocols`
- `FallbackUsed`
- `ReachabilityMode`
- `ReachabilitySummary`
- `GroupsCollected`
- `MembersCollected`
- `MatchesFound`
- `ErrorMessage`

### `server_local_group_members.csv`

Одна строка на одного прямого участника локальной группы. Ключевые поля:

- `Server`
- `CimProtocol`
- `LocalGroup`
- `LocalGroupCaption`
- `LocalGroupSid`
- `MemberName`
- `MemberType`
- `MemberClass`
- `MemberPrincipal`
- `MemberCaption`
- `MemberScope`
- `MemberAuthority`
- `MemberSource`
- `MemberLocalAccount`
- `MemberSid`
- `MemberPath`

### `server_local_group_summary.csv`

Одна строка на локальную группу со сводными счётчиками.

### `identity_search_matches.csv`

Подмножество membership-строк, которые совпали с искомой учётной записью или группой, плюс поле:

- `SearchIdentity`

## Логика поиска

Режим `FindIdentity` поддерживает поиск по:

- principal name вроде `DOMAIN\\User1`
- короткому имени вроде `User1`
- `SID`
- wildcard-шаблону вроде `*Admin*`

Сопоставление выполняется по таким membership-свойствам, как:

- `MemberName`
- `MemberPrincipal`
- `MemberCaption`
- `MemberSid`
- `MemberPath`

## Примеры использования

### Интерактивный запуск

```powershell
.\Start-ServerLocalGroupReport.ps1
```

### Полная выгрузка из файла

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.txt" `
    -NonInteractive
```

### CSV-файл с явным указанием столбца

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.csv" `
    -CsvServerColumn "FQDN" `
    -NonInteractive
```

### Полная выгрузка из AD

```powershell
$adCred = Get-Credential
$serverCred = Get-Credential

.\Start-ServerLocalGroupReport.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -NonInteractive
```

### Поиск пользователя или группы

```powershell
$adCred = Get-Credential
$serverCred = Get-Credential

.\Start-ServerLocalGroupReport.ps1 `
    -ADCredential $adCred `
    -ServerCredential $serverCred `
    -SearchIdentity "CONTOSO\\User1" `
    -NonInteractive
```

### Один credential для всего

```powershell
$cred = Get-Credential

.\Start-ServerLocalGroupReport.ps1 `
    -Credential $cred `
    -ServerListPath ".\samples\servers_example.txt" `
    -NonInteractive
```

### Ограничить выгрузку конкретными локальными группами

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.txt" `
    -LocalGroups "Administrators","Remote Desktop Users" `
    -NonInteractive
```

### Пропустить pre-probe и идти сразу в CIM

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -ServerListPath ".\samples\servers_example.txt" `
    -ReachabilityMode Direct `
    -NonInteractive
```

### Фильтрация stale-объектов AD

```powershell
.\Start-ServerLocalGroupReport.ps1 `
    -DomainServer "dc01.contoso.local" `
    -MaxComputerPasswordAgeDays 90 `
    -MaxLastLogonAgeDays 90 `
    -NonInteractive
```

## Параметры

Wrapper-скрипт поддерживает основные параметры:

- `-InputMode`: `AD` или `File`
- `-OperationMode`: `AllMembers` или `FindIdentity`
- `-ServerListPath`: TXT или CSV-файл со списком серверов
- `-CsvServerColumn`: явное имя столбца в CSV
- `-SearchIdentity`: кого искать
- `-DomainServer`: явный DC / AD endpoint
- `-SearchBase`: LDAP search base
- `-ADCredential`: credential для доступа к AD
- `-ServerCredential`: credential для доступа к серверам
- `-Credential` / `-SharedCredential`: один credential для AD и серверов
- `-LocalGroups`: список локальных групп, если нужно ограничить выгрузку
- `-CimProtocol`: `Dcom` или `Wsman`
- `-ReachabilityMode`: `Probe`, `Direct`, `PingOnly`, `None`
- `-ConnectivityTimeoutMs`: timeout на pre-check
- `-CimOperationTimeoutSec`: timeout операций `CIM`
- `-CimRetryCount`: число повторных попыток
- `-CimRetryDelaySec`: задержка между повторами
- `-ThrottleLimit`: уровень параллелизма в PowerShell `7+`
- `-MaxComputerPasswordAgeDays`: фильтр stale-объектов компьютеров AD
- `-MaxLastLogonAgeDays`: фильтр stale-объектов компьютеров AD
- `-WellKnownAuthorities`: свой список well-known authorities
- `-CimSlowQueryWarningSec`: предупреждение о медленном перечислении участников группы
- `-IncludeDisabledComputers`: включать отключённые объекты компьютеров AD
- `-IncludeEmptyGroups`: добавлять placeholder-строки для пустых локальных групп
- `-OutputDirectory`: каталог для артефактов
- `-NonInteractive`: отключить интерактивные запросы

Встроенная справка:

```powershell
Get-Help .\Start-ServerLocalGroupReport.ps1 -Detailed
```

## Структура репозитория

```text
AD_Server_Local_Group_Report_ru/
├─ AD_Server_Local_Group_Report.psd1
├─ AD_Server_Local_Group_Report.psm1
├─ Start-ServerLocalGroupReport.ps1
├─ get_windows_server_local_group_report.ps1
├─ LICENSE
├─ README.md
├─ README.en.md
├─ README.ru.md
├─ docs/
│  └─ ARCHITECTURE.md
├─ Private/
├─ Public/
└─ samples/
```

`Start-ServerLocalGroupReport.ps1` рекомендуется как основное имя скрипта для публикации и повседневного запуска.
Файл `get_windows_server_local_group_report.ps1` оставлен в репозитории для обратной совместимости.

## Необязательные dev-инструменты

Поставляемая версия проекта облегчена и не содержит встроенного каталога `tests/` и quality-runner скриптов.

Если вы хотите развивать проект дальше или собирать собственный quality-gate, можно дополнительно установить:

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

Проверка доступных версий:

```powershell
Get-Module -ListAvailable Pester | Sort-Object Version -Descending
Get-Module -ListAvailable PSScriptAnalyzer
```

## Практические эксплуатационные замечания

- После получения списка серверов из `AD` интерактивный режим специально делает паузу и предлагает открыть `server_source_list.txt` или папку `output`, чтобы оператор мог вручную скорректировать финальный scope опроса.
- Если после ручной правки выбран вариант продолжения, список серверов перечитывается заново из `server_source_list.txt`, а не используется только первоначальный AD-результат.
- Режим `FindIdentity` корректно отрабатывает и при нулевом количестве совпадений: это не ошибка, а штатный сценарий. В таком случае создаётся `identity_search_matches.csv` с заголовками и без строк данных.
- Сообщения вида `WinNT fallback добавил недостающих участников` являются информационными warning-сообщениями о повышении полноты результата, а не признаком сбоя скрипта.
- В конце прогона журнал теперь пишет отдельную категориальную сводку: `Success`, `Offline`, `AccessDenied`, `WinRM`, `Other`. Это помогает быстро отделить проблемы сети и прав доступа от реальных ошибок логики.
- Статусы `Offline`, `AccessDenied` и `WinRM` в итоговых отчётах обычно означают проблему доступности или разрешений на конкретном сервере, а не аварийное завершение wrapper-скрипта.
- В mixed-средах PowerShell/CIM часть провайдеров иногда возвращает не массивы, а scalar-объекты; текущая версия проекта уже учитывает такие кейсы и защищена от типичных падений на `.Count` и пустых коллекциях.

## Важные ограничения

- Отчёт содержит только прямых участников локальных групп.
- Вложенные доменные группы не раскрываются до конечных пользователей.
- Успешное перечисление зависит от сетевой доступности и прав доступа.
- Fallback через `WinNT` работает по best-effort модели и повышает полноту, но не гарантирует идеальное совпадение во всех legacy-краевых сценариях.
- В некоторых сетях ICMP может быть закрыт, хотя `CIM` доступен, поэтому `ReachabilityMode Direct` иногда лучше.
- На старых серверах `WSMan` доступен не всегда; в смешанных инфраструктурах `Dcom` часто остаётся наиболее безопасным выбором по умолчанию.

## Кратко о лицензии

Проект распространяется по лицензии MIT. Полный текст: [LICENSE](./LICENSE).

