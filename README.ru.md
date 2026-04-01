# AD Server Local Group Report

Monorepo с двумя локализованными редакциями одного PowerShell-решения для аудита состава локальных групп на Windows Server.

## Структура репозитория

- [en/](./en/): полная английская редакция
- [ru/](./ru/): полная русская редакция
- [LICENSE](./LICENSE): общая лицензия MIT

## Что входит в каждую редакцию

В каждой редакции есть свои:

- пользовательские entry-point скрипты
- локализованный help
- локализованные runtime-сообщения и логи
- документация
- manifest и реализация модуля

Бизнес-логика эквивалентна, меняется именно операторский язык интерфейса и документации.

## Рекомендуемые точки входа

Английская редакция:

- [en/Start-ServerLocalGroupReport.ps1](./en/Start-ServerLocalGroupReport.ps1)

Русская редакция:

- [ru/Start-ServerLocalGroupReport.ps1](./ru/Start-ServerLocalGroupReport.ps1)

Legacy-wrapper файлы тоже сохранены в обеих редакциях.

## Необязательные инструменты для разработки

Поставляемая версия репозитория намеренно облегчена и не содержит test-suite и quality-runner скриптов.

Если в будущем вы захотите дорабатывать или дополнительно валидировать проект, рекомендуется, но не требуется для
обычного рабочего запуска, установить:

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

## Зачем такой формат репозитория

Эта структура нужна, чтобы не вести два отдельных Git-репозитория только из-за различий по языку.

Она удобна, если вам нужны:

- один issue tracker
- единый релизный процесс
- одна лицензия
- общая история stars/forks
- две операторские языковые редакции

## Лицензия

Проект распространяется по лицензии MIT. Полный текст: [LICENSE](./LICENSE).
