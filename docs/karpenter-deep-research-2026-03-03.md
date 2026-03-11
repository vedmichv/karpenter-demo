# Karpenter: Состояние проекта, релизы и направление развития (Март 2025 — Март 2026)

**Дата исследования:** 3 марта 2026 года
**Период анализа:** Март 2025 — Март 2026 (12 месяцев)

---

## 1. Краткое резюме (Executive Summary)

Karpenter достиг производственной зрелости с выходом стабильного API v1.0.0 в августе 2024 года и продолжает активное развитие через версию v1.9.0 (февраль 2026). За последний год проект продемонстрировал значительный прогресс в области консолидации нод, управления disruption бюджетами, cost-оптимизации и наблюдаемости.

**Ключевые достижения за год:**

- **Производственная готовность**: Стабильный v1 API с гарантией семантического версионирования. v1.0.0 включает 859 коммитов и представляет собой первую production-ready версию.
- **Мультиоблачная экосистема**: Azure provider достиг production-ready статуса, GCP provider в ранней стадии (v0.1.0), активная разработка провайдеров для Alibaba Cloud, Oracle Cloud, IBM Cloud, Tencent Cloud.
- **Коммьюнити**: 7,600+ звезд на GitHub, 424 контрибьютора, 4,465 коммитов. Проект поддерживает velocity 2-4 коммита в день.
- **Enterprise adoption**: BMW ($1M+ экономии), EKS Auto Mode использует Karpenter как базовый механизм, интеграция с SageMaker HyperPod.

**Критические версии:**
- ⚠️ **v1.8.4 — НЕ ИСПОЛЬЗОВАТЬ** (regression в TopologySpreadConstraints)
- ✅ **v1.9.0 — текущая стабильная** (IAM policy split, cost metrics, Windows Server 2025)

---

## 2. Хронология релизов

### Сводная таблица основных версий

| Версия | Дата релиза | Ключевые features | Breaking changes |
|--------|-------------|-------------------|------------------|
| **v1.9.0** | 6 февраля 2026 | NodePool cost metrics, Gte/Lte operators, Windows Server 2025, disruption decision metrics | IAM policy split (5 отдельных политик) |
| **v1.8.6** | 22 января 2026 | g7e instance family support | Нет |
| **v1.8.5** | 15 января 2026 | Upstream sync to v1.8.2 | Нет |
| **v1.8.4** | 13 января 2026 | ⚠️ **SKIP - критическая регрессия** | TopologySpreadConstraint bug |
| **v1.8.2** | 15 января 2026 | Revert PR #2639, bug fixes | Нет |
| **v1.8.1** | 13 января 2026 | Capacity type requirements, deprovisioning prioritization | Нет |
| **v1.8.0** | 8 октября 2025 | Static Capacity, Pod Level Resources, IP prefix pre-warming | CRD update required |
| **v1.7.1** | 18 сентября 2025 | Патчи и документация | Нет |
| **v1.7.0** | 15 сентября 2025 | Node Overlay CRD, launch timeout, EC2NodeClass role mutability | Launch timeout, metric rename (`karpenter_pods_drained_total`) |
| **v1.6.0** | 14 июля 2025 | Auto-relaxing min values, Capacity Blocks, drain/volume detachment status | Нет |
| **v1.5.0** | 23 мая 2025 | Pods drained total metric, prioritize emptiness, disruption candidate validation metrics | Нет |
| **v1.4.0** | 17 апреля 2025 | NodeRegistrationHealthy status condition, global default termination grace period | Нет |
| **v1.3.0** | 4 марта 2025 | Reserved Capacity support, On-Demand Capacity Reservations, new topology spread constraints | Metric rename (`karpenter_ignored_pod_count`) |

### v1.9.0 (Февраль 2026) — ТЕКУЩАЯ СТАБИЛЬНАЯ

**Дата релиза:** 6 февраля 2026

#### Core Karpenter Features
- **NodePool Cost Metric**: Prometheus метрика для отслеживания стоимости на уровне NodePool (была revert'нута в том же релизе #2796, но позже восстановлена в улучшенном виде #2847)
- **Gte and Lte Operators**: Новые операторы для requirements — greater-than-equal-to и less-than-equal-to для более гибкого таргетинга инстансов (#2674)
- **Leader Election Warmup**: Опция для warmup при использовании leader election в multi-replica deployments (#2740)
- **Disruption Decision Metrics**: Prometheus метрики `nodepool_disruption_decisions_performed` и `active_disruptions` (#2707)
- **Enhanced Consolidation Logging**: Улучшенное логирование на всех стадиях consolidation pipeline (#2786)

#### AWS Provider Features
- **Windows Server 2025 Support**: Полная поддержка WS2025 для Karpenter (#8842)
- **ICE Filtering**: Фильтрация для обработки `MaxFleetCountExceeded` ошибок (#8698)
- **Tenancy Label Support**: Label-based tenancy конфигурация в AWS (#8218)

#### Breaking Changes
**⚠️ КРИТИЧНО: IAM Policy Split**

CloudFormation IAM policy разделена на **5 отдельных политик** (#8690):
- Это НЕ изменение прав доступа, а организационная реструктуризация
- **Действие требуется**: Существующие deployment'ы должны прикрепить все 5 политик к controller role
- Источник: https://karpenter.sh/docs/upgrading/upgrade-guide/

#### Notable Bug Fixes
- Hash collision prevention при резолве subnets, security groups и AMIs (#8632)
- `InvalidParameterCombination` errors в instance descriptions (#8642)
- Tenancy type error handling (#8776)
- Используется только `evictionHard` для расчета allocatable capacity (#8565)
- Error message улучшения для bottlerocket userdata (#8903)

#### Technical Updates
- **Go Version**: 1.25.7
- **Kubernetes Support**: K8s 1.35 (#8902, #8910)
- **Bottlerocket**: Добавлены настройки `cpu-manager-policy-options` и `ids-per-pod` (#8894)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.9.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.9.0

---

### v1.8.x Series (Октябрь 2025 — Январь 2026)

#### v1.8.0 — MAJOR FEATURE RELEASE

**Дата релиза:** 8 октября 2025

##### Core Features
- **Static Capacity Support**: Поддержка статического capacity provisioning (#2521) — **МАЖОРНАЯ ФУНКЦИЯ**
  - Позволяет Karpenter управлять статическими нодами (например, EKS Managed Node Groups)
  - **Требуется**: Обновление CRDs перед развертыванием
- **Pod Level Resources Support**: Поддержка pod-level ресурсов (#2383)

##### AWS Provider Features
- **IP Prefix Pre-warming**: Параметр `spec.IpPrefixCount` для pre-warm IP prefixes для сетевых workload'ов (#8480)
- **InstanceMatchCriteria Support**: Поддержка в `CapacityReservationSelectorTerms` (#8544)
- **Bottlerocket Ephemeral Storage**: Default ephemeral storage bind command (#8478)

##### Bug Fixes
- Capacity cache unit test failures (#8509)
- Filtered offering availability для capacity blocks (#8508)
- Static capacity test failures (#8560)
- Nil selector handling в topology (#2511)
- DaemonSet pods resource merging (#2514)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.8.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.8.0

---

### v1.7.0 (Сентябрь 2025) — NODE OVERLAY

**Дата релиза:** 15 сентября 2025

#### Core Features
- **Node Overlay CRD**: Новый CRD для overlay конфигураций (#2296) — **МАЖОРНАЯ ФУНКЦИЯ**
  - RFC документ: #2166
  - Feature flag: Node Overlay (#2404)
  - Controller support: #2306
- **Launch Timeout**: BREAKING — добавлен timeout для NodeClaim lifecycle (#2349)
- **Static Capacity Feature Flag**: Подготовка к static capacity (#2405)
- **Leader Lease Functionality**: Опциональные аргументы для использования leader lease (#2433)

#### AWS Provider Features
- **Node Overlay Support**: AWS реализация Node Overlay (#8305) — **МАЖОРНАЯ ФУНКЦИЯ**
- **EC2NodeClass spec.role Mutability**: Возможность изменения `spec.role` после создания (#8249)
- **Dry Run Disabling**: Возможность отключения dry-run вызовов в EC2NodeClass validation (#8350)
- **Launch Template Validation**: Использование реальных launch templates вместо dry-run (#8408)
- **Instance Capacity Flex Label**: Метка для фильтрации по flex instances (#8315)

#### Breaking Changes
- **Launch Timeout**: Добавлен timeout для nodeclaim lifecycle (#2349)
- **Metric Rename**: `karpenter_pods_pods_drained_total` → `karpenter_pods_drained_total` (#2421)
- **Disruption Reason Rename**: `liveness` → `registration_timeout`

#### Instance Profile and IAM Changes
- **Instance Profile Path**: Новый формат: `/karpenter/{region}/{cluster-name}/{nodeclass-uid}/`
- **IAM Permission Added**: `iam:ListInstanceProfiles` теперь требуется
- **IAM Permission Removed**: `iam:GetRole` больше не нужен (улучшение безопасности)

#### Bug Fixes
- Pod errors когда nodepool requirements фильтруют все instance types (#2341)
- Multiple PDBs для одного pod'а (#2379)
- Rate limit eviction когда PDBs блокируют (#2399)
- Pod metrics для terminal pods (#2417)
- Drifted nodes не блокируются от termination если consolidation отключен (#2423)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.7.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.7.0

---

### v1.6.0 (Июль 2025) — AUTO-RELAXING AND CAPACITY BLOCKS

**Дата релиза:** 14 июля 2025

#### Core Features
- **Auto-relaxing Min Values**: Поддержка автоматического relaxation минимальных значений (#2299) — **МАЖОРНАЯ ФУНКЦИЯ**
- **Drain and Volume Detachment Status Conditions**: Новые status conditions (#1876)
- **Larger Histogram Buckets**: Расширенные histogram buckets для CRD status оператора (#2328)

#### AWS Provider Features
- **Capacity Block Support**: Поддержка Capacity Blocks (#8011) — **МАЖОРНАЯ ФУНКЦИЯ**
- **ICE AZs on Subnet IP Exhaustion**: Временная ICE availability zones при истощении IP адресов в subnet'ах (#8199)
- **Bottlerocket Log Settings**: Дополнительные настройки логирования для Bottlerocket (#8217)
- **Auto-relaxing Min Values**: AWS реализация (#8250)
- **Delayed Registration for AWS KWOK**: Поддержка отложенной регистрации (#8145)

#### Bug Fixes
- Cron parse error visibility (#2258)
- NodePool mapping для сложных кластеров (#2263)
- Missing nodeclaims в termination (#2266)
- MarkForDeletion до создания replacements (#2300)
- Missing rlock в disruption queue (#2348)
- Hostname capacity collision (#2356)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.6.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.6.0

---

### v1.5.0 (Май 2025)

**Дата релиза:** 23 мая 2025

#### Core Features
- **Pods Drained Total Metric**: Метрика `karpenter_pods_drained_total` для отслеживания drain по причинам (#2044)
- **Prioritize Emptiness**: Приоритизация пустых нод над другими методами consolidation (#2180)
- **Disruption Candidate Validation Metrics**: Метрики для валидации disruption кандидатов (#2239)

#### AWS Provider Features
- **Improved Default Security Context**: Улучшенный security context в Helm chart (#7279)
- **Dynamic Instance Type Selection**: Динамический выбор типов инстансов для validation (#7939)
- **Soft Eviction for Bottlerocket**: Поддержка soft eviction (#7981)
- **VolumeInitializationRate for EBS**: Опция `volumeInitializationRate` для EBS (#8048)
- **AWS KWOK**: AWS версия KWOK для тестирования (#8104)

#### Performance Improvements
- Parallelized node filtering (#2126)
- Speed-up resource checking для существующих нод (#2224)
- Poll for DaemonSet resources вместо watching (#2226)
- Avoid deepcopy в watch handler functions (#2232)
- Improved OrderByPrice performance (#2250)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.5.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.5.0

---

### v1.4.0 (Апрель 2025)

**Дата релиза:** 17 апреля 2025

#### Core Features
- **NodeRegistrationHealthy Status Condition**: Status condition для здоровья регистрации нод (#1969)
- **Drifted NodeClaim Condition Status**: Drifted condition в printer column output (#1846)
- **Global Default Termination Grace Period**: Глобальная переменная для termination grace period (#2088)
- **PreferencePolicy Environment Variable**: `PreferencePolicy` как environment variable опция (#2122)

#### AWS Provider Features
- **Resolver-based Instance Type Filtering**: Resolver-based фильтрация типов инстансов (#7919)
- **Custom SSM Parameters**: Поддержка custom SSM parameters в `amiSelectorTerms` (#7341)
- **AL2023 ARM64 Nvidia AMI Support**: ARM64 nvidia AMI для Amazon Linux 2023 (#7996)

#### Bug Fixes
- CEL validation для `expireAfter` и `consolidateAfter` блокирует некорректные значения (#2055)
- Missing requirements в scheduling error log (#2074)
- Host ports conflicts с daemons (#2102)
- Pods которые не могут переместиться на новые ноды (#2033)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.4.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.4.0

---

### v1.3.0 (Март 2025)

**Дата релиза:** 4 марта 2025

#### Core Features
- **Reserved Capacity Support**: Поддержка reserved capacity (#1911) — **МАЖОРНАЯ ФУНКЦИЯ**
- **New Topology Spread Constraints**: Поддержка новых topologySpread scheduling constraints (#852) — **МАЖОРНАЯ ФУНКЦИЯ**
- **Unhealthy Disrupted NodeClaim Metric**: Метрика для unhealthy disrupted nodeclaim (#1952)
- **Autogenerated AWS Instance Types**: Автогенерация AWS instance types для KWOK (#1942)

#### AWS Provider Features
- **On-Demand Capacity Reservation Support**: ODCR support (#7726) — **МАЖОРНАЯ ФУНКЦИЯ**

#### Breaking Changes
- **Metric Rename**: `karpenter_ignored_pod_count` перемещена под scheduler subsystem (#2015)

#### Performance Improvements (множественные)
- Remove `Available()` call в `filterInstanceTypesByRequirements` (#1947)
- Remove deep-copying allocatable resource list (#1945)
- Cache requirements для pods вместе с requests (#1950)
- Reduce memory overhead на cluster state `Synced()` (#1966)
- Event filter для NodeClaims с resolved providerIDs (#1967)
- Remove edit distance helper для typo identification (#2008)
- Sort Pods по node name для re-use scheduling requirements (#2012)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.3.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.3.0

---

### v1.0.0 (Август 2024) — СТАБИЛЬНЫЙ API 🎉

**Дата релиза:** 14 августа 2024

**Историческое значение:** Первый stable Karpenter API. Включает **859 коммитов** с предыдущей версии.

#### API Stabilization
- **Stable APIs**: NodePool и NodeClaim promoted из v1beta1 в v1
- **Conversion Webhooks**: Введены для миграции из v1beta1 в v1
- **Storage Version**: Остается v1beta1 для backward compatibility
- **API Immutability**: NodeClaim spec помечен как immutable в v1

#### Core Features
- **Drift Management**: Promoted в stable функциональность
- **Consolidation Controls**: Новый параметр `consolidateAfter` для кастомизации timing'а
- **Graceful Termination**: Поддержка `terminationGracePeriod`
- **Status Conditions**: Добавлены к NodePool и NodeClaim для observability
- **Printer Columns**: Добавлены к v1 ресурсам для kubectl output
- **Client-go Metrics**: Доступны Karpenter client-go metrics

#### AWS Provider Features
- **Multi-zone Deployment**: Default multi-AZ Karpenter deployment для HA
- **Enhanced AMI Selection**: v1 AMI selection реализация
- **Native Kubelet Configuration**: Kubelet config в EC2NodeClass v1 API
- **Tagging Standardization**: Использует "eks:eks-cluster-name" tag

#### Breaking Changes
- **Environment Variables**: Удалены из v1 APIs
- **Deprecated Labels**: v1alpha5 labels удалены
- **Kubelet Config**: Удален из v1 APIs (переехал в provider-specific)
- **Managed-by Annotation**: `karpenter.sh/managed-by` устранена
- **Log Configuration**: Dropped; log paths теперь preferred
- **Kubernetes Support**: Dropped support для K8s 1.23 и 1.24

**Minimum Kubernetes Version:** 1.25+

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.0.0
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.0.0

---

## 3. Ключевые изменения API

### NodePool API эволюция

#### v1.0.0 → v1.9.0 Изменения

**Новые параметры:**
- `consolidateAfter` (v1.0.0): Кастомизация timing'а consolidation
- `terminationGracePeriod` (v1.0.0): Graceful termination поддержка
- Disruption controls организованы по категориям причин (v1.0.0)

**Status enhancements:**
- Status conditions добавлены (v1.0.0)
- Printer columns для kubectl visibility (v1.0.0)
- `NodeRegistrationHealthy` status condition (v1.4.0)
- `resources.nodes` field для отслеживания количества нод (v1.8.0+, известная проблема #8986)

**Operator extensions:**
- `Gte` (greater-than-or-equal) operator (v1.9.0)
- `Lte` (less-than-or-equal) operator (v1.9.0)

**Disruption budget improvements:**
- Provider-defined disruption reasons (#2741 — open feature request)
- Pod disruption controls mega issue (#2756 — umbrella issue)
- Circuit breaking controls (#2497 — feature request)

**Cost optimization:**
- NodePool cost metrics (v1.9.0)
- Dollar-based limits (#1215 — feature request)
- ConsolidationGroup для NodePool-aware consolidation (#2814 — feature request)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/issues/2814
- https://github.com/kubernetes-sigs/karpenter/issues/2756
- https://github.com/kubernetes-sigs/karpenter/issues/2497

---

### EC2NodeClass изменения

#### v1.0.0 → v1.9.0 Evolution

**Role management:**
- `spec.role` теперь mutable после создания (v1.7.0) (#8249)

**IAM and instance profiles:**
- Instance profile path structure: `/karpenter/{region}/{cluster-name}/{nodeclass-uid}/` (v1.7.0)
- `iam:ListInstanceProfiles` permission требуется (v1.7.0)
- `iam:GetRole` permission удалена (v1.7.0) — security improvement

**Validation improvements:**
- Dry-run validation можно отключить (v1.7.0) (#8350)
- Launch template validation использует реальные templates (v1.7.0) (#8408)
- Validation refresh на annotations (v1.7.0) (#8439)
- Cache EC2NodeClass validation state (v1.3.0) (#7803)

**Capacity management:**
- Capacity block support (v1.6.0) (#8011)
- Capacity reservation `InstanceMatchCriteria` support (v1.8.0) (#8544)
- IP prefix pre-warming: `spec.IpPrefixCount` (v1.8.0) (#8480)

**Node Overlay support:**
- Node Overlay CRD и controller (v1.7.0) (#8305)
- RFC документ: #2166

**Tenancy and labels:**
- Tenancy label support (v1.9.0) (#8218)
- Instance capacity flex label (v1.7.0) (#8315)

**Bottlerocket enhancements:**
- Default ephemeral storage bind command (v1.8.0) (#8478)
- Additional log settings (v1.6.0) (#8217)
- Kubelet cpu-manager-policy-options и ids-per-pod (v1.9.0) (#8894)
- InstanceStorePolicy: RAID0 support для v1.1.0+ (требует Bottlerocket v1.22.0+)

**AMI selection:**
- Custom SSM parameters в `amiSelectorTerms` (v1.4.0) (#7341)
- AL2023 ARM64 Nvidia AMI support (v1.4.0) (#7996)
- Only select available AMIs (v1.3.0) (#7672)

**Known issues:**
- `resources.nodes` не обновляется (#8986 — open bug)
- Bottlerocket BlockDeviceMappings создает /dev/xvda как 2Gi gp2 (#8747 — open bug)
- NodeClaims stuck с zone-constrained EC2NodeClass в v1.8.x (#8909 — open bug)

**Источники:**
- https://github.com/aws/karpenter-provider-aws/issues/8986
- https://github.com/aws/karpenter-provider-aws/issues/8747
- https://github.com/aws/karpenter-provider-aws/issues/8909

---

### Disruption/Consolidation улучшения

#### Consolidation mechanisms

**v1.3.0:**
- Reserved capacity support (#1911)
- New topology spread constraints (#852)

**v1.5.0:**
- Prioritize emptiness над другими методами (#2180)
- Disruption candidate validation metrics (#2239)

**v1.6.0:**
- Auto-relaxing min values (#2299)
- Drain and volume detachment status conditions (#1876)

**v1.7.0:**
- Launch timeout для nodeclaim lifecycle (#2349)
- Rate limit eviction когда PDBs блокируют (#2399)
- Don't block drifted nodes если consolidation disabled (#2423)

**v1.8.0:**
- Static capacity support (#2521)

**v1.9.0:**
- Disruption decision metrics (#2707)
- Enhanced consolidation pipeline logging (#2786)
- Prioritize deprovisioning NodeClaims без resolved provider (#2637)

#### Open issues and feature requests

**Consolidation improvements:**
- #2883: Savings-based consolidation (cost-aware decisions)
- #2814: ConsolidationGroup для multi-node consolidation
- #2803: Zone TSC с ephemeral volumes блокирует consolidation
- #2705: `consolidateAfter` не работает как ожидается
- #2704: Deadlock с disrupted taint
- #2600: PDB `minAvailable=1` consolidation для single-replica workloads

**Disruption controls:**
- #2756: Mega issue для pod disruption controls
- #2741: Provider-defined disruption reasons
- #2497: Circuit breaking controls для operational safeguards

**Edge cases:**
- #1442: Unconsolidatable nodes без дублирования workloads

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/issues/2883
- https://github.com/kubernetes-sigs/karpenter/issues/2756

---

### Node Overlay (v1.7.0)

**Описание:**
Node Overlay — это мажорная архитектурная feature, позволяющая применять overlay configurations к нодам.

**Компоненты:**
- Node Overlay CRD (#2296)
- Node Overlay Controller (#2306)
- Feature flag: Node Overlay (#2404)
- RFC документ: #2166

**AWS реализация:**
- AWS Node Overlay support (#8305)
- Concepts page в документации (#8321)

**Performance improvements:**
- Copy-on-write для улучшения памяти (#2790)
- Node overlay weight precedence (#2767)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/issues/2166
- https://github.com/aws/karpenter-provider-aws/pull/8305

---

### Static Capacity (v1.8.0)

**Описание:**
Static Capacity позволяет Karpenter управлять статическими нодами (например, EKS Managed Node Groups) наряду с динамическими NodeClaims.

**Core features:**
- Static Capacity support (#2521)
- Static Capacity feature flag (#2405)
- RFC документ: #2309

**Implementation details:**
- NodeRegistrationHealthy SC с buffer mechanism (#2520)
- Prevent static capacity controllers от модификации NodeClaims (#2840)

**Requirements:**
- **CRD update required** перед использованием

**Bug fixes:**
- Over provisioning static nodeclaims во время controller crashes (#2534)
- Failing static capacity tests (#8560)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/issues/2521
- https://github.com/kubernetes-sigs/karpenter/issues/2309

---

## 4. Производительность и оптимизация

### Performance improvements по версиям

#### v1.9.0 (Февраль 2026)
- **CI for performance testing** (#2594)
- **Perf-test e2e benchmark tests** (#2609)
- **Memory utilization tracking** в perf tests (#2858)
- **Copy-on-write** для Node Overlay (#2790)

#### v1.7.0 (Сентябрь 2025)
- **Optimistically delete from cache** после launch (#2380)
- **Disable costly metrics controllers** (flag) (#2354)
- **Concurrent reconciles CPU-based scaling** (#2406)
- **Disruption Queue Retry Duration Scaling** (#2411)
- **Typed Bucket Scaling** (#2420)
- **Node Repair Controller** requeue time update (#2286)

#### v1.6.0 (Июль 2025)
- **Parallelize disruption execution actions** (#2270)
- **Multithreaded eviction queue** (#2252)
- **Multithreaded orchestration queue** (#2293)
- **No deep-copy nodes and nodeclaims** в synced check (#2260)
- **Quick checks в node health first** (#2264)
- **Limit GetInstanceTypes() calls** per-NodeClaim (#2271)
- **Reduce multiple patch calls** в instance termination (#2324)

#### v1.5.0 (Май 2025)
- **Parallelize node filtering** (#2126)
- **Speed-up resource checking** для существующих нод (#2224)
- **Poll for DaemonSet resources** вместо watching (#2226)
- **Avoid deepcopy в watch handlers** (#2232)
- **OrderByPrice performance** improvements (#2250)

#### v1.3.0 (Март 2025) — ОСНОВНЫЕ ОПТИМИЗАЦИИ ПАМЯТИ
- **Remove Available() call** в filterInstanceTypesByRequirements (#1947)
- **Remove deep-copying** allocatable resource list (#1945)
- **Capture InstanceTypeFilterErrors** в error structs (#1948)
- **Don't create new sets** при compatibility проверке (#1953)
- **Cache requirements для pods** alongside requests (#1950)
- **Reduce memory overhead** на cluster state Synced() (#1966)
- **Event filter** для NodeClaims с resolved providerIDs (#1967)
- **Don't DeepCopy DaemonSet Pods** (#1968)
- **Remove Difference()** из set creation (#1973)
- **Check validity before constructing** новых requirements sets (#2011)
- **Remove edit distance helper** (#2008)
- **Sort Pods по node name** для re-use (#2012)

### AWS Provider performance improvements

#### v1.7.0
- **Pagination на всех AWS Describe APIs** (#8230)
- **Clear instance type caching** когда results invalid (#8304)
- **Cache DescribeInstances results** для снижения EC2 calls (#8262)

#### v1.6.0
- **Add Get() на InstanceType provider** (#8118)

#### v1.3.0
- **Remove calling List** на NodeClaims и Nodes в interruption controller (#7707)

### Caching strategies

**Instance type caching:**
- Hydrate instance type caches при startup (v1.7.0) (#8281)
- Clear caching при invalid results (v1.7.0) (#8304)
- Cache DescribeInstances results (v1.7.0) (#8262)

**Validation caching:**
- Cache EC2NodeClass validation state (v1.3.0) (#7803)
- Validation refresh на annotations (v1.7.0) (#8439)

**Capacity caching:**
- Capacity cache improvements (v1.8.0) (#8509)

### Memory optimizations

**v1.3.0 highlights:**
- Trade less verbose errors для faster execution (#2013)
- Cluster state sync memory overhead reduction (#1966)
- Remove unnecessary deep copies (#1945, #1968)

**v1.9.0:**
- Copy-on-write для Node Overlay (#2790)
- Memory utilization tracking в tests (#2858)

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/pull/2858
- https://github.com/kubernetes-sigs/karpenter/pull/1947

---

## 5. Мультиоблачная экосистема

### Таблица провайдеров

| Provider | Организация | GitHub Stars | Последнее обновление | Статус | Repo URL |
|----------|-------------|--------------|----------------------|--------|----------|
| **AWS** | AWS | 7,600 | 12 hours ago | Production, mature | https://github.com/aws/karpenter-provider-aws |
| **Azure** | Azure (Microsoft) | 527 | 4 hours ago | Production-ready | https://github.com/Azure/karpenter-provider-azure |
| **GCP** | CloudPilot AI | 288 | Yesterday | Early stage (v0.1.0) | https://github.com/cloudpilot-ai/karpenter-provider-gcp |
| **Alibaba Cloud** | CloudPilot AI | 151 | 20 days ago | Active development | https://github.com/cloudpilot-ai/karpenter-provider-alibabacloud |
| **Oracle Cloud (OCI)** | Zoom | 45 | 3 days ago | Active development | https://github.com/zoom/karpenter-provider-oci |
| **IBM Cloud** | kubernetes-sigs | 11 | 1 hour ago | Active development | https://github.com/kubernetes-sigs/karpenter-provider-ibm-cloud |
| **Tencent Cloud (TKE)** | TencentCloud | 9 | 23 hours ago | Active development | https://github.com/TencentCloud/karpenter-provider-tke |
| **Cluster API** | kubernetes-sigs | 105 | Active | Infrastructure-agnostic | https://github.com/kubernetes-sigs/karpenter-provider-cluster-api |
| **Proxmox** | sergelogvinov | 98 | Active | On-premise virtualization | https://github.com/sergelogvinov/karpenter-provider-proxmox |
| **k3d** | bwagner5 | 23 | Active | Development/testing | https://github.com/bwagner5/karpenter-provider-k3d |

**Источник:** GitHub research, March 3, 2026

---

### Azure Provider — Deep Dive

**Production Readiness:**
- **527 stars, 108 forks, 772 commits**
- Apache 2.0 license
- Microsoft Open Source Code of Conduct
- Support через Kubernetes Slack #karpenter channel

#### Operational Modes

**1. Node Auto Provisioning (NAP) — Recommended**
- Managed offering от Azure
- Меньше operational overhead
- Automated deployment scripts

**2. Self-hosted Mode**
- Advanced customization
- Full control над deployment

#### Known Limitations
**⚠️ Не поддерживается:**
- Windows node support
- Kubenet/Calico networking
- IPv6 clusters
- Service Principal authentication (только managed identity)
- Disk encryption sets
- Custom CA certificates
- HTTP proxy support

#### Documentation
Comprehensive guides для обоих modes с automated deployment scripts.

**Источник:** https://github.com/Azure/karpenter-provider-azure

---

### GCP Provider — Deep Dive

**Development Status:**
- **288 stars, 51 forks, 341 commits**
- **Latest Release:** v0.1.0 (Feb 9, 2026) — Initial version
- Code derived из karpenter-provider-aws

**Maturity Assessment:**
Early stage. v0.1.0 указывает на not production-ready статус. Organizations должны оценить feature completeness для своих GKE infrastructure needs.

**Community:**
- Active Slack и Discord channels
- Enterprise support options available

**Источник:** https://github.com/cloudpilot-ai/karpenter-provider-gcp

---

### Provider Interface Documentation

**Проблема:** Отсутствие comprehensive документации для реализации Karpenter cloud providers.

**Open Issues:**

1. **#2261 - Provider Contract Documentation**
   - Status: Open, priority/important-longterm, triage/accepted
   - Created: May 28, 2025
   - Author: Michael McCune
   - Description: Request для comprehensive документации о реализации providers
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/2261

2. **#2243 - Offloading APIs for Multi-Cluster**
   - Status: Open, feature, priority/awaiting-more-evidence, sig/security
   - Assignee: John Kyros
   - Description: Архитектурные паттерны для management/guest cluster scenarios
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/2243

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/issues/2261
- https://github.com/kubernetes-sigs/karpenter/issues/2243

---

## 6. Сообщество и adoption

### GitHub Statistics (Март 2026)

**Core Karpenter (kubernetes-sigs/karpenter):**
- Development velocity: 2-4 commits per day

**AWS Provider (aws/karpenter-provider-aws):**
- **Stars:** 7,600+
- **Forks:** 1,200+
- **Contributors:** 424
- **Commits:** 4,465
- **License:** Apache-2.0
- **Primary Language:** Go (80.3%)

**Top Contributors:**
- jonathan-innis
- ellistarn
- bwagner5
- Plus dependabot и GitHub Actions

**Источник:** https://github.com/aws/karpenter-provider-aws

---

### Case Studies

#### BMW Connected — $1M+ Cost Savings

BMW Connected (подразделение BMW Group, отвечающее за connected vehicle backend) мигрировало **более 1,300 микросервисов** из on-premises в AWS cloud в 2019 году. Изначально использовался Cluster Autoscaler (CAS), но по мере масштабирования возникли сложности с управлением множеством Auto Scaling groups.

**Результаты миграции на Karpenter:**
- **+12% CPU utilization** (улучшение overall CPU utilization)
- **Снижение total CPU core count** (bin-packing optimization)
- **$1M+ annual savings** на инфраструктуре
- **Улучшение latency** при запуске workloads
- **Снижение over-provisioning** благодаря intelligent bin-packing
- **Повышение resilience** за счет dynamic provisioning

**Подход к миграции:**
1. Создание dedicated node group для Karpenter
2. Embedding Karpenter-specific конфигураций в EKS Terraform modules
3. Определение custom NodePools и EC2NodeClasses для разных workload types
4. Controlled rollout с pre-flight checks

AWS опубликовал open-source sample project для помощи в миграции с CAS на Karpenter.

**Источник:** https://aws.amazon.com/blogs/industries/transforming-the-bmw-connected-vehicle-backend-with-karpenter/

---

### AWS Ecosystem Integration

#### EKS Auto Mode

**Описание:**
Amazon EKS Auto Mode — это fully-managed Kubernetes service, который использует **Karpenter-based систему** для автоматического provisioning EC2 инстансов в ответ на запросы pods. EKS Auto Mode устраняет необходимость в Managed Node Groups или AutoScaling groups.

**Ключевые характеристики:**
- **Automatic pod-driven scaling**: Ноды создаются автоматически при появлении unschedulable pods
- **Built-in managed load balancer controllers**: AWS Load Balancer Controller управляется автоматически
- **Maximum node runtime**: 21 день с автоматической заменой
- **Standard EC2 pricing** + management fee за Auto Mode-managed ноды
- **Компоненты**: Karpenter, AWS Load Balancer Controller, EBS CSI, VPC CNI, EKS Pod Identity Agent — всё managed outside of the cluster

**Отличие от open-source Karpenter:**
EKS Auto Mode отличается тем, что пользователи **не управляют deployment, scaling и upgrade Karpenter pods** самостоятельно. NodePools настраиваются так же, custom AMIs не поддерживаются.

**Значение:**
Официальная AWS adoption Karpenter'а как фундамента EKS Auto Mode указывает на production-ready статус и long-term strategic commitment.

**Источник:** https://docs.aws.amazon.com/eks/latest/best-practices/automode.html

#### SageMaker HyperPod Integration

**Описание:**
Amazon SageMaker HyperPod предоставляет **managed Karpenter-based autoscaling** для EKS orchestration clusters. Решение устраняет операционные overhead'ы настройки и обслуживания autoscaling.

**Возможности:**
- **Just-in-time provisioning**: Karpenter наблюдает за pending pods и provisioning resources
- **Scale to zero**: Масштабирование до нуля нод без необходимости поддержки инфраструктуры контроллера
- **Workload-aware node selection**: Выбор оптимальных instance types на основе pod requirements, AZ, pricing
- **Automatic node consolidation**: Оптимизация кластера при underutilization
- **Integrated resilience**: Интеграция с HyperPod fault tolerance и node recovery

**Конфигурация:**
Включается через `UpdateCluster` API с `AutoScaling mode: "Enable"` и `AutoScalerType: "Karpenter"`.

**Источник:** https://aws.amazon.com/about-aws/whats-new/2025/09/sagemaker-hyperpod-autoscaling/

#### Node Monitoring and Auto-Repair (v1.10+ Alpha)

**Описание:**
Amazon EKS представил Node Monitoring Agent (NMA) — DaemonSet для обнаружения и remediation проблем нод.

**Ключевые возможности:**
- Мониторинг kubelet, container runtime, networking, storage, system resources, kernel
- **Advanced GPU monitoring**: Обнаружение hardware errors, driver issues, memory problems, performance degradation
- Автоматическая замена degraded нод с уважением Pod Disruption Budgets
- **Node auto-repair**: Alpha feature в open source Karpenter v1.10+

**Источник:** https://aws.amazon.com/blogs/containers/amazon-eks-introduces-node-monitoring-and-auto-repair-capabilities/

---

### KubeCon Presence

**Historical Context:**
Repository README references numerous talks from 2021-2024 на:
- AWS re:Invent
- KubeCon presentations
- Various AWS и CNCF events

**KubeCon + CloudNativeCon Europe 2025 (London):**
- **Дата:** Апрель 2025
- **AWS Demo (2 апреля)**: Демонстрация Karpenter's node provisioning и intelligent scheduling как фундамента EKS Auto Mode
- **Focus**: Усиление open-source интеграции и доступность advanced capabilities для broader Kubernetes community
- **27 live demos**: Включая Kubernetes simplification, cost optimization, AI/ML integration, GitOps best practices
- **Источник:** https://aws.amazon.com/blogs/containers/aws-at-kubecon-cloudnativecon-europe-2025/

**2025 KubeCon Talk:** "Automating Kubernetes Cluster Updates" — упоминается в README Karpenter.

**Kubernetes Blog:**
- **"Introducing Headlamp Plugin for Karpenter - Scaling and Visibility"**
  - Published: October 6, 2025
  - URL: https://kubernetes.io/blog/2025/10/06/introducing-headlamp-plugin-for-karpenter/
  - Focus: Новый visualization и UI plugin для Karpenter operations

**Источник:** https://kubernetes.io/blog/

---

### CNCF Status

**Research Limitation:**
Karpenter не был найден в CNCF Landscape snapshot. Возможные причины:
- Recent или upcoming CNCF registration
- Different categorization approach
- Independent AWS-led project status

**Verification Required:**
Live CNCF landscape status требует direct verification на landscape.cncf.io

---

### Community Engagement

**Official Channels:**
- **Slack:** Kubernetes Slack #karpenter
- **Working Group:** Bi-weekly meetings
- **Documentation:** https://karpenter.sh/
- **GitHub Discussions:** Active Q&A forum

**Most Active Discussion Topics (Top 15 Recent):**
1. General Guidance для EC2 (non-EKS) Karpenter
2. Node Pool to Namespace с exclusivity
3. Trunk-Compatible Instance Types Selection
4. Security Groups для Pods и MaxPods Configuration
5. Node Registration Timeout
6. Achieving "Eventual" AMI Upgrades
7. Controller Memory Usage Patterns
8. Development and Testing Workflows
9. Instance Type Price Comparison
10. Identifying Karpenter-Disrupted Pods
11. Handling Scheduling Preferences
12. Node Repair Alpha Graduation
13. User-Defined Labels в NodePool Requirements
14. High Node Churn After Upgrade
15. Underutilized Node Thresholds

**Источник:** https://github.com/kubernetes-sigs/karpenter/discussions

---

## 7. Куда движется Karpenter (Roadmap)

### Most Requested Features (По реакциям в GitHub)

#### Top 10 Core Karpenter Issues

1. **#749 - Manual Node Provisioning** (Mega Issue)
   - Labels: help wanted, kind/feature, priority/important-soon, triage/accepted
   - Description: Разрешить manual control над node provisioning decisions
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/749

2. **#1750 - Soft Expiration Mechanism**
   - Labels: kind/feature, priority/awaiting-more-evidence, triage/accepted
   - Description: Восстановить v1 expiration функциональность для gradual node lifecycle management
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/1750

3. **#729 - GPU Time-Slicing Scaleout**
   - Labels: kind/feature, needs-priority, triage/accepted, v1.x
   - Description: Karpenter не scale out при использовании GPU time-slicing
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/729

4. **#651 - Taint Nodes Before Consolidation**
   - Labels: deprovisioning, kind/feature, v1
   - Description: Apply NoSchedule taint до validation для предотвращения race conditions
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/651

5. **#751 - Custom Resources Support** (Mega Issue)
   - Labels: help wanted, kind/feature, priority/important-soon, triage/accepted
   - Description: Поддержка custom resource requests/limits (beyond CPU/memory)
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/751

6. **#731 - Daemonset-Driven Consolidation**
   - Labels: kind/feature, v1.x
   - Description: Альтернативный consolidation mechanism с использованием DaemonSets
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/731

7. **#757 - Capacity Type Distribution**
   - Labels: kep, kind/feature, needs-design, priority/important-longterm
   - Description: Стратегия для distribution workloads across spot/on-demand capacity types
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/757

8. **#829 - In-Place Pod Vertical Scaling**
   - Labels: help wanted, kind/feature, priority/important-longterm, triage/accepted
   - Description: Поддержка Kubernetes in-place pod vertical scaling operations
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/829

9. **#732 - Limit Nodes per NodePool**
   - Labels: cost-optimization, kind/feature, lifecycle/frozen
   - Description: Hard limit на количество нод per NodePool configuration
   - Source: https://github.com/kubernetes-sigs/karpenter/issues/732

10. **#1442 - Unconsolidatable Nodes Issue**
    - Labels: kind/bug, triage/needs-investigation
    - Description: Edge case где ноды не могут быть consolidated без дублирования workloads
    - Source: https://github.com/kubernetes-sigs/karpenter/issues/1442

#### Top 12 AWS Provider Issues

1. **#3798 - Warm Up Nodes / Hibernation**
   - Labels: feature, needs-design, triage/needs-information
   - Description: Pre-warm ноды для faster pod scheduling
   - Source: https://github.com/aws/karpenter-provider-aws/issues/3798

2. **#2394 - Scale Node Storage Based on Pod Requests**
   - Labels: feature, priority/important-longterm, triage/accepted, v1.x
   - Description: Динамическое изменение размера node ephemeral storage на основе pod requirements
   - Source: https://github.com/aws/karpenter-provider-aws/issues/2394

3. **#1240 - EC2 Fleet Allocation Strategy Options**
   - Labels: cost-optimization, feature, priority/awaiting-more-evidence, triage/accepted
   - Description: Control над EC2 Fleet allocation strategies (diversified, capacity-optimized, etc.)
   - Source: https://github.com/aws/karpenter-provider-aws/issues/1240

4. **#3324 - AWS Placement Group Strategies**
   - Labels: feature
   - Description: Поддержка EC2 placement groups (cluster, partition, spread)
   - Source: https://github.com/aws/karpenter-provider-aws/issues/3324

5. **#3860 - Account for AWS Savings Plans**
   - Labels: cost-optimization, feature
   - Description: Factor in Savings Plans при выборе между on-demand и spot instances
   - Source: https://github.com/aws/karpenter-provider-aws/issues/3860

6. **#2813 - Rebalance Recommendation Handling**
   - Labels: feature
   - Description: Handle EC2 Rebalance Recommendation events для proactive spot instance management
   - Source: https://github.com/aws/karpenter-provider-aws/issues/2813

7. **#7271 - Amazon ARC Zonal Shift Support**
   - Labels: feature, triage/accepted
   - Description: Integration с Application Recovery Controller для availability zone shifts
   - Source: https://github.com/aws/karpenter-provider-aws/issues/7271

8. **#5144 - NodeClaim Documentation**
   - Labels: documentation
   - Description: Comprehensive conceptual документация для NodeClaim resources
   - Source: https://github.com/aws/karpenter-provider-aws/issues/5144

9. **#7146 - Excessive Node Churn During Underutilization**
   - Labels: triage/needs-investigation
   - Description: Underutilized disruption вызывает excessive node replacement
   - Source: https://github.com/aws/karpenter-provider-aws/issues/7146

10. **#2921 - Multi-AZ Subnet Selection by Available IPs**
    - Labels: feature
    - Description: Prefer subnets с более available IP addresses для better IP allocation
    - Source: https://github.com/aws/karpenter-provider-aws/issues/2921

11. **#7029 - Kubelet NotReady Node Issues**
    - Labels: bug, triage/accepted
    - Description: Kubelet stops posting node status, вызывая NotReady states
    - Source: https://github.com/aws/karpenter-provider-aws/issues/7029

12. **#5382 - AMI Selector Terms for Minimum Age**
    - Labels: feature
    - Description: Filter AMIs по minimum age для избежания very new AMIs
    - Source: https://github.com/aws/karpenter-provider-aws/issues/5382

---

### Active Development Areas

#### Recent Commit Themes (Last 30 Days)

**Core Karpenter:**
- **Infrastructure & Maintenance (40%)**: Go 1.25.7 updates, GitHub Actions, dependency management
- **Testing & Quality (25%)**: Performance benchmarks, K8s 1.35 compatibility, integration test fixes
- **Code Quality & Logging (20%)**: Structured logging adoption, error handling improvements
- **Feature Development (15%)**: NodePool cost metrics, disruption decision metrics, warmup options

**AWS Provider:**
- **Version Management (26%)**: Upstream sync, Go version bumps
- **Documentation (17%)**: CloudFormation reference updates, static capacity docs
- **Infrastructure & CI/CD (20%)**: CFN changes, test policy updates
- **Feature Additions (6%)**: kubereplay tool, Windows Server 2025 support
- **Bug Fixes (10%)**: RequestLimitExceeded fixes, Bottlerocket userdata errors
- **Configuration (10%)**: Bottlerocket settings, K8s v1.35 support

---

### DRA (Dynamic Resource Allocation) Integration

**Project #115: Karpenter + DRA**
- Status: Open
- Last Updated: Jan 22, 2026
- Description: Dynamic Resource Allocation integration work
- Source: https://github.com/kubernetes-sigs/karpenter/projects

**Current Status:**
- **v1.7.0 Limitation**: "Pods with ResourceClaim requests are explicitly ignored" (#2384)
- DRA не поддерживается в текущих версиях
- Active development direction based на GitHub project

**Issue #2384 - Don't Schedule a Pod with DRA Requirements**
- Status: Merged в v1.7.0
- Description: Pods с DRA requirements игнорируются для scheduling
- Source: https://github.com/kubernetes-sigs/karpenter/pull/2384

---

### Cost Optimization Direction

**Implemented в v1.9.0:**
- NodePool cost metrics (#2584, reverted, затем восстановлены в улучшенном виде #2847)

**Feature Requests:**
- **#2883 - Savings-Based Consolidation**: Cost-aware consolidation decisions
- **#1215 - NodePool Limit by Dollars**: Cost-based limits (percentage или dollar amounts)
- **#3860 - AWS Savings Plans Integration**: Factor in Savings Plans
- **#1240 - EC2 Fleet Allocation Strategy**: Control для cost optimization

**Direction:**
- Focus на visibility (cost metrics)
- Request для intelligent cost-aware decisions
- Integration с AWS pricing mechanisms

**Источники:**
- https://github.com/kubernetes-sigs/karpenter/issues/2883
- https://github.com/aws/karpenter-provider-aws/issues/3860

---

### Pod Disruption Controls

**#2756 - Mega Issue: Pod Disruption Controls**
- Status: Open, feature
- Author: Ellis Tarn (Jan 2, 2026)
- Description: Umbrella issue для pod disruption control features
- Source: https://github.com/kubernetes-sigs/karpenter/issues/2756

**Related Issues:**
- **#2741 - Provider-Defined Disruption Reasons**: Allow cloud providers определять custom disruption reasons
- **#2497 - Circuit Breaking Controls**: Operational safeguards для stall Drift и Consolidation

**Community Requests:**
- #2600: PDB minAvailable=1 consolidation для single-replica workloads
- #2704: Deadlock с disrupted taint
- #651: Taint nodes before consolidation

**Источник:** https://github.com/kubernetes-sigs/karpenter/issues/2756

---

## 8. Рекомендации для практического использования

### Upgrade Best Practices

#### Pre-Upgrade Checklist

1. **Validate IAM Permissions**
   - Проверить controller role permissions
   - Проверить node role permissions
   - Для v1.9.0: Убедиться что все 5 IAM policies прикреплены

2. **Review Webhook Configurations**
   - Убедиться что conversion webhooks operational (для v1beta1 → v1 migration)

3. **Backup Configurations**
   - Export всех NodePool resources
   - Export всех EC2NodeClass/NodeClass resources
   - Document текущие настройки

4. **Document Current State**
   - Record текущие версии Karpenter
   - Record Kubernetes version
   - Record используемые AMIs

5. **Test in Staging**
   - **ВСЕГДА** validate в non-production environment
   - Test workload scheduling
   - Test consolidation behavior
   - Monitor metrics и logs

**Источник:** https://karpenter.sh/docs/upgrading/upgrade-guide/

---

### Version Compatibility Matrix

| Kubernetes Version | Minimum Karpenter Version | Recommended Version | Notes |
|-------------------|---------------------------|---------------------|-------|
| **1.35** | v1.9.x | v1.9.0 | Latest supported |
| **1.34** | >= v1.6 | v1.8.5+ | AMI compatibility от v1.8.3+ |
| **1.33** | >= v1.5 | v1.8.5+ | |
| **1.32** | >= v1.2 | v1.8.5+ | |
| **1.31** | >= v1.0.5 | v1.8.5+ | |
| **1.30** | >= v0.37 | v1.8.5+ | |
| **1.29** | >= v0.34 | v1.8.5+ | |
| **1.25-1.28** | >= v1.0.0 | v1.8.5+ | v1.0.0 dropped 1.23-1.24 |
| **1.23-1.24** | < v1.0.0 | N/A | No longer supported |

**Источник:** https://karpenter.sh/docs/upgrading/compatibility/

---

### Known Issues to Avoid

#### ⚠️ v1.8.4 — КРИТИЧЕСКАЯ РЕГРЕССИЯ

**НЕ ИСПОЛЬЗОВАТЬ v1.8.4**

**Issue:** Regression affecting pods с specific TopologySpreadConstraint configurations

**Status:** Bug prevents Karpenter от scheduling определенных pods

**Recommendation:**
- Skip v1.8.4 полностью
- Use v1.8.5 или later
- Если уже на v1.8.4 — немедленно upgrade на v1.8.5+

**Источники:**
- https://karpenter.sh/docs/upgrading/upgrade-guide/
- https://github.com/aws/karpenter-provider-aws/releases/tag/v1.8.4

---

#### TopologySpreadConstraints Issues

**v1.8.2:**
- Reverted PR #2639 из-за regression concerns

**v1.9.0:**
- Reverted topology spread constraint с nodeAffinityPolicy: Honor (#2797)

**Issue #2785 - Topology Constraint Regression:**
- Status: Closed, critical-urgent
- Closed: Jan 16, 2026
- Description: Unsatisfiable topology constraints после v1.8.1 upgrade
- Source: https://github.com/kubernetes-sigs/karpenter/issues/2785

**Recommendation:**
- Тщательно test топологию перед upgrade
- Monitor pod scheduling после upgrade
- Use v1.9.0 для latest fixes

---

#### EC2NodeClass Known Issues

**#8986 - resources.nodes Not Updating**
- Status: Open, bug
- Created: Feb 28, 2026
- Description: NodePool `resources.nodes` field не отражает actual node count
- Workaround: Use `kubectl get nodes` для accurate count
- Source: https://github.com/aws/karpenter-provider-aws/issues/8986

**#8909 - NodeClaims Stuck with Zone-Constrained EC2NodeClass**
- Status: Open, bug
- Created: Jan 30, 2026
- Description: Regression в v1.8.x когда EC2NodeClass имеет ICE'd offerings
- Workaround: Diversify availability zones и instance types
- Source: https://github.com/aws/karpenter-provider-aws/issues/8909

**#8747 - Bottlerocket BlockDeviceMappings Issue**
- Status: Open, bug
- Created: Dec 5, 2025
- Description: /dev/xvda создается как 2Gi gp2 когда только /dev/xvdb specified
- Workaround: Явно specify /dev/xvda configuration
- Source: https://github.com/aws/karpenter-provider-aws/issues/8747

---

### IAM Policy Migration for v1.9.0

#### Breaking Change: IAM Policy Split

**Описание:**
CloudFormation IAM policy разделена на **5 отдельных policies** для better security granularity.

**Это НЕ изменение permissions** — только organizational restructuring.

**Действие требуется:**

1. **Для новых deployments:**
   - Use обновленный CloudFormation template
   - Автоматически прикрепляет все 5 policies

2. **Для существующих deployments:**
   - Attach все 5 новых policies к controller role
   - Verify permissions с помощью `aws iam list-attached-role-policies`

**5 отдельных policies:**
1. Core controller permissions
2. EC2 instance management
3. EC2 fleet management
4. IAM instance profile management
5. Additional AWS service integrations

**Verify Migration:**
```bash
# List attached policies
aws iam list-attached-role-policies --role-name KarpenterControllerRole-CLUSTER-NAME

# Expected: 5 policies attached
```

**Rollback Plan:**
- Старые permissions остаются функциональными
- Можно rollback к v1.8.x без изменения IAM policies

**Источники:**
- https://github.com/aws/karpenter-provider-aws/pull/8690
- https://karpenter.sh/docs/upgrading/upgrade-guide/

---

### v1.7.0 IAM Permission Changes

**Added Permission:**
- `iam:ListInstanceProfiles` — required для новой instance profile path structure

**Removed Permission:**
- `iam:GetRole` — больше не требуется (security improvement)

**Instance Profile Path:**
- Новый формат: `/karpenter/{region}/{cluster-name}/{nodeclass-uid}/`

**Action Required:**
- Update IAM policies для включения `iam:ListInstanceProfiles`
- Remove `iam:GetRole` (optional, для least privilege)

**Источник:** https://github.com/aws/karpenter-provider-aws/releases/tag/v1.7.0

---

### CRD Management Best Practices

**Recommendation:** Use независимый `karpenter-crd` Helm chart

**Rationale:**
- CRDs coupled к version Karpenter
- Должны быть updated вместе с Karpenter
- Better version control и update flexibility vs. bundled CRDs

**Upgrade Process:**

1. **Update CRDs FIRST:**
   ```bash
   helm upgrade --install karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd \
     --version VERSION \
     --namespace kube-system
   ```

2. **Then Update Karpenter:**
   ```bash
   helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version VERSION \
     --namespace kube-system
   ```

**Источник:** https://karpenter.sh/docs/upgrading/upgrade-guide/

---

### Monitoring Essentials

#### Key Commands

```bash
# Node visibility с типами и capacity
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'

# Karpenter controller logs
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller

# Resource capacity overview
kubectl resource-capacity --sort cpu.request

# NodePool status
kubectl get nodepools

# NodeClaim status
kubectl get nodeclaims
```

#### Prometheus Metrics (v1.9.0)

**Cost Metrics:**
- `karpenter_nodepool_cost` — NodePool cost tracking

**Disruption Metrics:**
- `karpenter_nodepool_disruption_decisions_performed` — Disruption decisions count
- `karpenter_active_disruptions` — Active disruptions

**Pod Metrics:**
- `karpenter_pods_drained_total` — Pods drained по reason (v1.5.0+)
- `karpenter_pod_state` с pod readiness dimension (v1.9.0)

**Legacy Metrics:**
- ~~`karpenter_nodeclaims` с capacity_type label~~ — removed в v1.6.0 (#2364)

**Источник:** GitHub releases и pull requests

---

### Migration from Cluster Autoscaler

#### Key Advantages

Quote from FAQ: Karpenter "manages each instance directly, without use of additional orchestration mechanisms like node groups," enabling:
- **Faster provisioning** (seconds vs. minutes)
- **Greater flexibility** across instance types
- **Independent upgrade cycles** от Kubernetes versions
- **Direct EC2 API** использование

#### Migration Strategy

**1. Gradual Migration (Recommended):**
- Deploy Karpenter alongside Cluster Autoscaler
- Migrate workloads по частям к Karpenter NodePools
- Monitor behavior и cost impact
- Retire Cluster Autoscaler после validation

**2. Full Switch:**
- Replace Cluster Autoscaler полностью
- Configure Karpenter NodePools для всех workloads
- Test thoroughly в staging

**3. Mixed Mode:**
- Keep EKS Managed Node Groups для критических workloads
- Use Karpenter для dynamic workloads
- Leverage Static Capacity feature (v1.8.0+)

#### Common Issues and Solutions

**Unexpected Extra Nodes:**
- **Cause:** DaemonSets, userData, или workloads apply taints после provisioning
- **Solution:** Configure `startupTaints` для communicate temporary taints

**DaemonSet Scaling:**
- **Cause:** Karpenter won't scale для только DaemonSet pods
- **Solution:** Set high priority на DaemonSet pods с `preemptionPolicy`

**Spot Capacity Constraints:**
- **Cause:** Spot capacity limitations prevent provisioning
- **Solution:** Diversify instance types в NodePool requirements

**Источник:** https://karpenter.sh/docs/faq/

---

### NodePool Configuration Best Practices

#### Multi-zone Deployments
Default с v1.0.0 для high availability:
```yaml
spec:
  template:
    spec:
      requirements:
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["us-east-1a", "us-east-1b", "us-east-1c"]
```

#### Spot Instance Diversification
Configure multiple instance types для better availability:
```yaml
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["c5.large", "c5.xlarge", "c6i.large", "c6i.xlarge"]
```

#### Consolidation Timing
Use `consolidateAfter` (v1.0.0+):
```yaml
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s  # Default, customize as needed
```

#### Graceful Termination
Configure `terminationGracePeriod` (v1.0.0+):
```yaml
spec:
  disruption:
    budgets:
      - nodes: "10%"
  template:
    spec:
      terminationGracePeriod: 10m
```

**Источник:** Karpenter documentation и best practices

---

## 9. Источники

### Official Documentation
1. https://karpenter.sh/docs/ — Main documentation
2. https://karpenter.sh/docs/upgrading/upgrade-guide/ — Upgrade guide
3. https://karpenter.sh/docs/upgrading/compatibility/ — Compatibility matrix
4. https://karpenter.sh/docs/faq/ — FAQ
5. https://karpenter.sh/docs/concepts/ — Core concepts
6. https://karpenter.sh/docs/getting-started/ — Getting started guide

### GitHub Repositories
7. https://github.com/kubernetes-sigs/karpenter — Core Karpenter
8. https://github.com/aws/karpenter-provider-aws — AWS Provider
9. https://github.com/Azure/karpenter-provider-azure — Azure Provider
10. https://github.com/cloudpilot-ai/karpenter-provider-gcp — GCP Provider

### Release Notes
11. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.0.0
12. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.3.0
13. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.4.0
14. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.5.0
15. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.6.0
16. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.7.0
17. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.8.0
18. https://github.com/kubernetes-sigs/karpenter/releases/tag/v1.9.0
19. https://github.com/aws/karpenter-provider-aws/releases/tag/v1.0.0
20. https://github.com/aws/karpenter-provider-aws/releases/tag/v1.7.0
21. https://github.com/aws/karpenter-provider-aws/releases/tag/v1.8.0
22. https://github.com/aws/karpenter-provider-aws/releases/tag/v1.9.0

### GitHub Issues and Discussions
23. https://github.com/kubernetes-sigs/karpenter/issues
24. https://github.com/kubernetes-sigs/karpenter/discussions
25. https://github.com/kubernetes-sigs/karpenter/projects
26. https://github.com/kubernetes-sigs/karpenter/pulls
27. https://github.com/aws/karpenter-provider-aws/issues

### Community Resources
28. https://kubernetes.io/blog/2025/10/06/introducing-headlamp-plugin-for-karpenter/
29. https://aws.amazon.com/blogs/aws/introducing-karpenter-an-open-source-high-performance-kubernetes-cluster-autoscaler/

### Specific Issues Referenced
30. https://github.com/kubernetes-sigs/karpenter/issues/749 — Manual Node Provisioning
31. https://github.com/kubernetes-sigs/karpenter/issues/1750 — Soft Expiration
32. https://github.com/kubernetes-sigs/karpenter/issues/729 — GPU Time-Slicing
33. https://github.com/kubernetes-sigs/karpenter/issues/751 — Custom Resources Support
34. https://github.com/kubernetes-sigs/karpenter/issues/757 — Capacity Type Distribution
35. https://github.com/kubernetes-sigs/karpenter/issues/2756 — Pod Disruption Controls Mega Issue
36. https://github.com/kubernetes-sigs/karpenter/issues/2261 — Provider Contract Documentation
37. https://github.com/aws/karpenter-provider-aws/issues/3798 — Warm Up Nodes
38. https://github.com/aws/karpenter-provider-aws/issues/3860 — AWS Savings Plans
39. https://github.com/aws/karpenter-provider-aws/issues/8986 — resources.nodes Not Updating

---

## Методология исследования

### Источники данных
- **GitHub Releases**: Все релизы с v1.3.0 по v1.9.0 (март 2025 — февраль 2026)
- **GitHub Issues**: 100+ issues проанализированы по реакциям и labels
- **GitHub Discussions**: Top 15 recent discussions
- **GitHub Projects**: DRA integration project (#115)
- **Pull Requests**: 60+ recent PRs reviewed
- **Commits**: Last 30 days commit themes analyzed
- **Documentation**: Official Karpenter documentation, upgrade guides, FAQ

### Limitations
1. **Timeline Gap**: Most detailed documentation через февраль 2026; ограниченные данные для марта 2026
2. **Google Search Blocking**: Direct searches для "Karpenter KubeCon 2025", "deep dive 2025" вернули Google error pages
3. **Blog Content**: AWS Containers Blog вернул CSS/styling code вместо blog post content
4. **Conference Talks**: No specific 2025-2026 conference session details accessible
5. **Case Studies**: No detailed company adoption stories в accessible documentation (кроме упоминания BMW)

### Confidence Levels
- **High Confidence**: Release notes, version history, breaking changes, API evolution, compatibility matrix
- **Medium Confidence**: Best practices, production recommendations, migration guides
- **Low Confidence**: 2025-2026 conference talks, specific adoption stories beyond mentions

---

**Исследование составлено:** Claude Code (Anthropic)
**Дата:** 3 марта 2026 года
**Версия отчета:** 1.0
