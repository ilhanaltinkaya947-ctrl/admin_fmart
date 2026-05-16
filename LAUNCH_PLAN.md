# F-Mart Pre-Launch & Launch-Day Plan

Last updated: 2026-05-16 · Status: in-progress

This plan covers the customer app (`fmart-flutter`), admin app (`admin_fmart`),
and backend services (`order-service`, `payment-service`, `delivery-service`,
`notification-service`, `auth-service`, `catalog-service`, `gateway-service`).

---

## Guiding principles

- Each phase has a clear "done" gate — don't move forward until the gate is met.
- Backend + Flutter work runs in parallel where possible.
- Every change deployed → smoke-tested → committed → documented in commit message before next item.
- No silent failures — every fix in a `catch` block gets a Sentry breadcrumb.

---

## Phase 0 — Done today (2026-05-16) ✅

- ✅ Category restructure (meat/fish/eggs/frozen split, 28 clean tiles)
- ✅ Flutter category tile mapping + non-breaking-space for "и" wraps
- ✅ RU-only locales on customer app; drop EN; fix "до" prepositions
- ✅ OneSignal dSYM Run Script in both Podfiles
- ✅ Customer + Admin TF builds uploaded (1.3.0+33, 1.0.0+8)
- ✅ Image ingestion pipeline (Kiril xlsx → MinIO, 130/3576 done, 56% coverage)
- ✅ Payment-service P1+P2+P3 deployed (one-stage charge, webhook dedup migration, alembic in sync)
- ✅ **CRITICAL**: webhook dedup bug fix (was treating every webhook as duplicate → blocked ALL order status updates → root cause of "Ожидает оплату" stuck status)
- ✅ Admin: phone normalization + Remember-me + better login errors + customer detail endpoint fix + file_picker for banners

---

## Phase 1 — Real-customer launch blockers · target: ~2 days

**Gate: a real customer can buy, get a courier, get pushed each step, get delivered, get refunded — without manual admin babysitting.**

### 1A. Backend: Order ↔ Yandex ↔ Customer notification chain (~1 day)

| # | Task | Where | Acceptance |
|---|---|---|---|
| 1A-1 | Yandex courier status polling worker (sweeps non-terminal claims every 30-60s; publishes `delivered`/`cancelled` events) | new `delivery-service/app/workers/poller.py` + RabbitMQ producer | Place test order → mark courier delivered in Yandex sandbox → admin order auto-advances to `delivered`, customer gets push |
| 1A-2 | Auto-create Yandex claim when order hits `ready_for_delivery` (event-driven, not manual second tap) | new order→delivery consumer | Status change to `ready` → claim appears in delivery panel within 5s without staff action |
| 1A-3 | Customer "courier on the way" push fires when claim succeeds | notification-service | Customer phone gets push within seconds of claim creation |
| 1A-4 | Per-status friendly push copy (RU): "Заказ принят", "Ваш заказ собирают", "Курьер забрал заказ", "Заказ доставлен" | `order-service/app/domain/statuses.py` | Walk through all 5 statuses → customer sees right copy each time |
| 1A-5 | GPS coord end-to-end validation: reject `create_claim` if coords are 0/null; backfill any existing 0-coord orders flagged | delivery-service guard + audit SQL | Query shows 0 orders with `shipping_lat IS NULL OR shipping_lat = 0` |
| 1A-6 | Refund writes to `order_status_history` (today's refund didn't audit) | order-service refund handler | Refund an order → history table has the transition row |
| 1A-7 | Null `onesignal_user_id` → Sentry breadcrumb (currently silent skip) | notification-service consumer | Sentry shows "skipped push — no onesignal_id" event |

### 1B. Customer app fixes (~2h)

| # | Task | Where | Acceptance |
|---|---|---|---|
| 1B-1 | Cart cleared after successful payment | `fmart-flutter/lib/features/cart/checkout/` | Buy item → return to catalog → "В КОРЗИНУ" button orange (not green "В КОРЗИНЕ") |

### 1C. Admin app: refund + picker safety (~1.5 days)

| # | Task | Where | Acceptance |
|---|---|---|---|
| 1C-1 | **Refund confirmation modal** with amount + masked card + stable idempotency key per modal session | `order_details_page.dart` | Triple-tap refund button → only 1 refund record + 1 TipTop call |
| 1C-2 | **Barcode scan-to-pick** workflow: scanner page + match SKU against order items + ✅/❌ haptic + per-item `picked_at` + "X of Y picked" progress | new `admin_fmart/lib/features/picking/` + `order_items.picked_at` DB column | Scan wrong barcode → loud rejection. Right one → check, item picked, progress advances |
| 1C-3 | Hide status-change form when order is in terminal state (no "Выбери статус" red error) | `order_details_page.dart` | Refunded order → form hidden, only "Этот заказ завершён" |
| 1C-4 | Pull-to-refresh on order detail | `order_details_page.dart` | Swipe down → spinner → refresh |
| 1C-5 | OneSignal sound + iPad vibration on new-order push | `admin_fmart/ios/Runner/NotificationServiceExtension/` + OneSignal config | New order while iPad on stand → chime + vibrate |

**Phase 1 gate (smoke test from one real phone):**
- Buy 1 cheap item with real card from customer TF build
- Order shows up in admin within 5s, status = `paid`
- Mark `ready_for_delivery` → Yandex claim auto-created, customer gets "courier on the way" push
- Move through statuses → customer gets friendly push at each
- Mark `delivered` (or wait for polling) → customer gets "Заказ доставлен" push
- Refund → confirmation modal → 1 refund only → status history shows transition

If all 7 pass → gate cleared → ship to F-Mart staff for internal dry-runs.

---

## Phase 2 — Pre-broad-launch polish · target: 2-3 days

**Gate: F-Mart staff runs a real shift at 50+ orders/day without fighting the app.**

### 2A. Admin workflow at scale (~1 day)

| # | Task | Effort |
|---|---|---|
| 2A-1 | 1-tap quick-action status buttons in sticky bottom bar ("Mark paid / Mark ready / Hand to courier") | 1.5h |
| 2A-2 | Sort "Новые заказы" oldest-first (tightest SLA first) | 5m |
| 2A-3 | Color-by-SLA on order list (green <30m, yellow 30-60m, red >60m) | 1h |
| 2A-4 | Wrap silent `catch (_)` in admin with `Sentry.captureException` (10+ sites) | 1h |
| 2A-5 | Backend: dedicated `GET /admin/orders/{id}` endpoint (~7× DB load reduction on detail polling) | 30m + 10m client |
| 2A-6 | "Last touched by" avatar in order detail | 30m |

### 2B. Customer app polish (~3h)

| # | Task | Effort |
|---|---|---|
| 2B-1 | Sweep visible screens (checkout, order detail, account) for rough RU stub strings | 1h |
| 2B-2 | Fix duplicate "Сладости" tile bug (3048 + 3299 both match КОНДИТЕР) | 30m |
| 2B-3 | NONFOOD migration off FOOD root | 4h |

### 2C. Operational SOP (parallel, you drive)

| # | Task | Owner |
|---|---|---|
| 2C-1 | Print picker SOP: status flow, push meanings, refund decision tree | You + manager |
| 2C-2 | F-Mart staff TestFlight invites + onboarding session | You |
| 2C-3 | Stock check on 132 ingested images — any 404s after a few days? | You + Kiril |
| 2C-4 | Send Kiril daily image batch reminder + run ingest script | You (~5 min/day) |

**Phase 2 gate:**
- F-Mart staff runs a simulated half-shift (~25 orders over 4 hours)
- Open issues logged
- No data-loss bugs observed
- Avg status-change time <10s

---

## Phase 3 — Post-launch operational hardening · target: weeks 2-4

**Gate: app survives sustained 100+ orders/day without operator complaints.**

| # | Task | Effort |
|---|---|---|
| 3-1 | Offline command queue (Hive/Drift) for status changes + item picks; replay on reconnect; "X pending" badge | 1-2 days |
| 3-2 | "Claim / Pick up" button + lock so two staff don't fight over same order | 3h |
| 3-3 | Global search (order #, phone, customer name, address) | 2h |
| 3-4 | Saved filter views ("Все неоплаченные >1ч", etc.) | 3h |
| 3-5 | Bulk select for batch status changes | 3h |
| 3-6 | Print integration (kitchen ticket + courier label) | 4h |
| 3-7 | Live charts on Today dashboard (orders/hr, avg time, refund %) | 3h |
| 3-8 | Broadcast push to customers from admin (task #70) | 4h |
| 3-9 | Coupons / promo codes admin CRUD (task #71) | 6h |
| 3-10 | Reports — sales by day + top products (task #72) | 6h |
| 3-11 | Minimum test suite (`AuthCubit`, `ApiClient._refresh` lock, `kAdminAllowedTransitions` vs backend `StatusMachine`, `LoginPage`, `_StatusBadge`) | 4h |
| 3-12 | Refactor `order_details_page.dart` (1009 lines) into widgets | 3h |
| 3-13 | Comprehensive `GET /admin/customers/{id}` endpoint returning full CustomerInfo | 1h |

---

## Phase 4 — V1.5 reimagining · target: 1-2 months post-launch

Only do these if operational metrics warrant the investment.

| # | Task | Strategic value |
|---|---|---|
| 4-1 | **Kanban view** for orders (drag-and-drop columns: New / Packing / Ready / Delivering) | Wolt/Lavka pattern. Big UX win for kitchen staff. |
| 4-2 | **WebSocket order updates** replacing polling — always fresh, less battery | Backend gateway work needed |
| 4-3 | **Multi-store kitchen-display mode** (wall-mounted TV view) | New feature for high-volume stores |
| 4-4 | **Proper l10n wiring** on admin (`flutter_gen_l10n` or strip multi-locale dressing) | Honesty win |
| 4-5 | **Build-time config via `--dart-define`** for backend URL + OneSignal app id | Useful when adding staging env |
| 4-6 | **Cert pinning** in admin Dio client | Defense in depth |
| 4-7 | **Polish remaining customer-app l10n stubs** (50+ rough auto-translations on less-visited screens) | Translator work |
| 4-8 | **Apple Pay / Google Pay verification post-launch** (task #35 still pending) | Was blocked in test env, revisit after live |

---

## Cross-cutting infra cleanups (batch any time)

| # | Task | Effort |
|---|---|---|
| X-1 | payment-service Dockerfile: bake `alembic.ini` + `psycopg2-binary` so migrations don't need manual `docker cp` + `pip install` | 20m |
| X-2 | Pre-commit hook: `flutter analyze && dart format` on both apps | 30m |
| X-3 | Customer app Sentry env name mismatch (`SENTRY_ENVIRONMENT=production` but `testfmart` domain) | 5m |
| X-4 | Delete dead code: `TipTopPayRepository` (hardcoded secret), `SearchPage`, `auth_interceptor.dart` 1-line stub, dupe `_initials()` | 30m |
| X-5 | `OrdersCubit.refresh` shouldn't wipe to skeleton on pull-to-refresh | 15m |
| X-6 | Move `Pagination` model to `core/api/models/` (currently cross-feature import smell) | 20m |

---

## Effort summary

| Phase | Goal | Effort |
|---|---|---|
| **Phase 1** | Real-customer-safe | ~2 days |
| **Phase 2** | Dry-run-ready for F-Mart staff | ~3 days |
| **Phase 3** | 100/day operational | ~2-3 weeks |
| **Phase 4** | V1.5 enhancement | 1-2 months, optional |

---

## Working agreement

- Each task → one commit with descriptive message.
- No deploying to prod without backup plan (`docker compose up -d --force-recreate` + verify with grep).
- Each Tier 0 task gets a verification step in commit message.
- Daily status update at end of working session: what landed, what's blocked, what's next.
